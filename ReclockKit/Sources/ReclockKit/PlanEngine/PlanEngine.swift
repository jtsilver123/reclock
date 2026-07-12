import Foundation

/// The deterministic, protocol-versioned jet lag planning engine.
///
/// Design notes:
/// - All phase math happens on UTC instants; zones are only used to resolve wall-clock targets.
///   This makes DST transitions and the International Date Line fall out of `TimeZone` itself.
/// - The trip is decomposed into "stints": groups of segments separated by ground stays of
///   ≥ 48h. Each stint's final arrival zone becomes the adaptation target, and the body-clock
///   offset carries across stints. This uniformly models one-way, return, open-jaw and
///   multi-destination trips.
/// - The traveler's state is summarized by `B`: signed hours the body clock has shifted from
///   home baseline (positive = advance). Nightly steps move `B` toward the active target.
/// - No `Date()` and no randomness inside the engine: same inputs → same plan.
public struct PlanEngine: JetLagPlanGenerating, Sendable {
    public let configuration: PlanEngineConfiguration

    public init(configuration: PlanEngineConfiguration = PlanEngineConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Entry point

    public func generatePlan(
        trip: Trip,
        profile: UserProfile,
        currentState: TravelerState?
    ) throws -> JetLagPlan {
        guard !trip.segments.isEmpty else { throw PlanEngineError.noSegments }
        try validateItinerary(trip)

        guard let homeZone = trip.homeZone.timeZone else {
            throw PlanEngineError.unresolvableTimeZone(trip.homeZone.identifier)
        }
        guard let destZone = trip.destinationZone.timeZone else {
            throw PlanEngineError.unresolvableTimeZone(trip.destinationZone.identifier)
        }

        let stints = buildStints(trip: trip)
        let firstStint = stints[0]
        let outboundDelta = CircadianMath.zoneDelta(
            home: homeZone, destination: destZone, at: firstStint.arrival
        )

        // Decide strategy.
        let strategy = chooseStrategy(trip: trip, delta: outboundDelta)
        let shiftPlan: CircadianMath.ShiftPlan
        switch strategy {
        case .anchorToHome:
            shiftPlan = .init(shiftHours: 0, direction: .none, daysToComplete: 0)
        default:
            shiftPlan = CircadianMath.chooseShift(
                zoneDeltaHours: outboundDelta,
                configuration: configuration,
                intensity: trip.intensity
            )
        }

        let context = PlanContext(
            trip: trip,
            profile: profile,
            configuration: configuration,
            homeZone: homeZone,
            zoneTimeline: ZoneTimeline(trip: trip),
            stints: stints,
            strategy: strategy,
            outboundShift: shiftPlan,
            state: currentState
        )

        let nights = try buildNightSchedule(context: context)
        var days: [PlanDay] = []
        var actions: [PlanAction] = []
        var adjustments: [PlanAdjustment] = []

        for (index, night) in nights.enumerated() {
            let day = makePlanDay(index: index, night: night, context: context)
            days.append(day)
            let built = buildActions(
                dayIndex: index,
                night: night,
                previousNight: index > 0 ? nights[index - 1] : nil,
                day: day,
                context: context
            )
            actions.append(contentsOf: built.actions)
            adjustments.append(contentsOf: built.adjustments)
        }

        // Trim trailing quiet days (fully adapted, nothing to do) so plans end crisply.
        while let last = days.last,
              !actions.contains(where: { $0.dayIndex == last.index }),
              days.count > 1 {
            days.removeLast()
        }

        actions = enforceDensityCaps(actions: actions, days: days, context: context)
        actions = Self.roundWindows(actions)

        let summary = strategySummary(context: context, delta: outboundDelta)

        return JetLagPlan(
            id: Self.deterministicPlanID(tripID: trip.id),
            tripID: trip.id,
            protocolVersion: ProtocolVersion.current.description,
            revision: 1,
            generatedAt: currentState?.asOf ?? trip.createdAt,
            strategy: strategy == .automatic ? .fullyAdapt : strategy,
            requiredShiftHours: shiftPlan.shiftHours,
            shiftDirection: shiftPlan.direction,
            days: days,
            actions: actions,
            adjustments: adjustments,
            strategySummary: summary
        )
    }

    // MARK: - Itinerary sanity

    private func validateItinerary(_ trip: Trip) throws {
        var previousArrival: Date?
        for segment in trip.segments {
            guard segment.arrival > segment.departure else {
                throw PlanEngineError.invalidItinerary(
                    "\(segment.displayName) lands before it departs. Check the dates and time zones."
                )
            }
            guard segment.blockTime < .hours(20) else {
                throw PlanEngineError.invalidItinerary(
                    "\(segment.displayName) would be \(Int(segment.blockTime.inHours))h long — no scheduled flight is. Check the dates."
                )
            }
            if let previous = previousArrival, segment.departure < previous {
                throw PlanEngineError.invalidItinerary(
                    "\(segment.displayName) departs before the previous flight lands."
                )
            }
            guard segment.departureZone.timeZone != nil else {
                throw PlanEngineError.unresolvableTimeZone(segment.departureZone.identifier)
            }
            guard segment.arrivalZone.timeZone != nil else {
                throw PlanEngineError.unresolvableTimeZone(segment.arrivalZone.identifier)
            }
            previousArrival = segment.arrival
        }
    }

    // MARK: - Stints

    struct Stint {
        var segments: [FlightSegment]
        var departure: Date { segments.first!.departure }
        var arrival: Date { segments.last!.arrival }
        var arrivalZone: ZoneID { segments.last!.arrivalZone }
        /// End of the ground stay following this stint (next stint departure, or open-ended).
        var stayEnd: Date
    }

    func buildStints(trip: Trip) -> [Stint] {
        var groups: [[FlightSegment]] = []
        var current: [FlightSegment] = []
        for segment in trip.segments {
            if let last = current.last,
               segment.departure.timeIntervalSince(last.arrival) >= .hours(48) {
                groups.append(current)
                current = []
            }
            current.append(segment)
        }
        if !current.isEmpty { groups.append(current) }

        var stints: [Stint] = []
        for (index, group) in groups.enumerated() {
            let stayEnd: Date
            if index + 1 < groups.count {
                stayEnd = groups[index + 1].first!.departure
            } else {
                stayEnd = group.last!.arrival.addingTimeInterval(.hours(24 * 14))
            }
            stints.append(Stint(segments: group, stayEnd: stayEnd))
        }
        return stints
    }

    // MARK: - Strategy

    private func chooseStrategy(trip: Trip, delta: Double) -> AdaptationStrategy {
        switch trip.adaptationStrategy {
        case .fullyAdapt: return .fullyAdapt
        case .anchorToHome: return .anchorToHome
        case .automatic:
            if abs(delta) < configuration.minimumShiftWorthPlanning { return .anchorToHome }
            if let nights = trip.destinationNights,
               nights <= configuration.anchorMaxNights,
               abs(delta) <= configuration.anchorMaxShiftHours {
                return .anchorToHome
            }
            return .fullyAdapt
        }
    }

    // MARK: - Night schedule

    /// One traveler night with the surrounding phase estimate.
    struct Night {
        var index: Int
        /// Wake that begins the waking day preceding this night.
        var wake: Date
        /// Estimated CBTmin on the morning of the waking day (pivot for that day's light).
        var cbtMin: Date
        /// Sleep onset target.
        var bed: Date
        /// Bed before practical clamping — the pure phase-model value. Used to compute when
        /// the body *feels* like sleeping (the stay-awake anchor).
        var nominalBed: Date
        /// Wake that ends this night.
        var nextWake: Date
        /// Body-clock offset (signed hours advanced from home) after this night's step.
        var bodyOffsetAfter: Double
        /// Offset before this night's step (used for daily-progress displays).
        var bodyOffsetBefore: Double
        /// The stint whose target this night is shifting toward, if adaptation is active.
        var targetZone: ZoneID
        /// The body-offset value this night is stepping toward (per-stint, DST-correct).
        var targetOffset: Double
        /// True if this night falls before the first departure.
        var isPreTrip: Bool
        /// True while shifting ahead of a stint's departure (first or return) — normal life
        /// continues, so the gentler pre-trip rate applies.
        var isPreDeparture: Bool

        /// The direction tonight's remaining shift actually points — the return leg of an
        /// eastward trip is a delay, so this must never be assumed from the outbound.
        var direction: ShiftDirection {
            let remaining = targetOffset - bodyOffsetBefore
            if remaining > 0.3 { return .advance }
            if remaining < -0.3 { return .delay }
            return .none
        }

        var isAdapted: Bool {
            abs(bodyOffsetAfter - targetOffset) < 0.3 && abs(bodyOffsetBefore - targetOffset) < 0.3
        }
    }

    func buildNightSchedule(context: PlanContext) throws -> [Night] {
        let cfg = configuration
        let profile = context.profile
        let trip = context.trip
        let homeCal = Calendar.gregorian(in: context.homeZone)

        // Planning span.
        let preDays = context.strategy == .anchorToHome
            ? 0
            : cfg.preTripDayCount(intensity: trip.intensity, willingness: profile.preTripAdjustment)
        let firstDeparture = trip.firstDeparture!
        let planStartDay = homeCal.startOfDay(
            for: firstDeparture.addingTimeInterval(-Double(preDays) * 86_400)
        )
        let lastArrival = trip.finalArrival!
        // Adaptation continues after final arrival until complete (bounded).
        let postDays = context.strategy == .anchorToHome
            ? (trip.destinationNights.map { min($0 + 1, 4) } ?? 2)
            : min(cfg.maxAdaptationDays, context.outboundShift.daysToComplete + cfg.recoveryBufferDays + 1)
        let planEnd = lastArrival.addingTimeInterval(Double(postDays) * 86_400)

        let sleepDuration = profile.typicalSleepDuration
        let cbtOffset = CircadianMath.cbtMinOffsetBeforeWake(profile: profile, configuration: cfg)

        var nights: [Night] = []
        var body = 0.0
        if let state = context.state {
            // Historical nights are regenerated on schedule; the achieved offset applies
            // from the first night after `asOf` (handled inside the loop below).
            _ = state
        }

        var nightDate = planStartDay
        var index = 0
        var previousBed: Date? = nil

        while true {
            guard let homeBedInstant = profile.typicalBedtime.date(on: nightDate, in: context.homeZone) else {
                throw PlanEngineError.invalidItinerary("Could not resolve bedtime on \(nightDate).")
            }
            if homeBedInstant > planEnd { break }
            if index > 60 { break } // hard stop; no sane trip plans 2 months of nights

            let bodyBefore: Double
            if let state = context.state, previousBed != nil,
               let prev = previousBed, prev <= state.asOf,
               homeBedInstant.addingTimeInterval(-86_400) <= state.asOf {
                // The upcoming night is the first at-or-after asOf: adopt the achieved offset.
                bodyBefore = state.achievedShiftHours
            } else {
                bodyBefore = body
            }

            // Which target is active tonight?
            let (target, targetZone, stepAllowed, isPreDeparture) = activeTarget(
                bedInstant: homeBedInstant.adding(hours: -bodyBefore),
                homeBedInstant: homeBedInstant,
                context: context
            )

            let step = nightlyStep(
                current: bodyBefore,
                target: target,
                stepAllowed: stepAllowed,
                isPreDeparture: isPreDeparture,
                context: context
            )
            let bodyAfter = step.newOffset

            // The night's bed instant reflects tonight's *post-step* phase: you sleep at the
            // newly shifted time tonight.
            let nominalBed = homeBedInstant.adding(hours: -bodyAfter)
            // Clamp scheduled bedtime to a practical local window at the place you're sleeping.
            let bed = clampBedtimePractically(nominalBed, context: context)

            let wake = (previousBed ?? bed.addingTimeInterval(-86_400)).addingTimeInterval(sleepDuration)
            let nextWake = bed.addingTimeInterval(sleepDuration)
            let cbtMin = wake.adding(hours: -cbtOffset)

            nights.append(
                Night(
                    index: index,
                    wake: wake,
                    cbtMin: cbtMin,
                    bed: bed,
                    nominalBed: nominalBed,
                    nextWake: nextWake,
                    bodyOffsetAfter: bodyAfter,
                    bodyOffsetBefore: bodyBefore,
                    targetZone: targetZone,
                    targetOffset: target,
                    isPreTrip: homeBedInstant < firstDeparture,
                    isPreDeparture: isPreDeparture
                )
            )

            body = bodyAfter
            previousBed = bed
            index += 1
            nightDate = homeCal.date(byAdding: .day, value: 1, to: nightDate) ?? nightDate.addingTimeInterval(86_400)
        }

        guard !nights.isEmpty else {
            throw PlanEngineError.invalidItinerary("The trip produced no plannable days.")
        }
        return nights
    }

    /// The adaptation target (in body-offset hours) active for a night, plus whether stepping
    /// is allowed (pre-trip shifting only starts within the allowed pre-days window) and
    /// whether tonight precedes the governing stint's departure.
    private func activeTarget(
        bedInstant: Date,
        homeBedInstant: Date,
        context: PlanContext
    ) -> (target: Double, zone: ZoneID, stepAllowed: Bool, isPreDeparture: Bool) {
        let cfg = configuration
        if context.strategy == .anchorToHome {
            return (0, context.trip.homeZone, false, false)
        }

        // Find the stint governing this night: the last stint departed at/before tonight,
        // or — within the pre-shift window — the upcoming stint.
        let preDays = cfg.preTripDayCount(
            intensity: context.trip.intensity,
            willingness: context.profile.preTripAdjustment
        )
        var governing: Stint? = nil
        var isPreShift = false
        for stint in context.stints {
            if bedInstant >= stint.departure.addingTimeInterval(-.hours(6)) {
                governing = stint
                isPreShift = false
            } else if bedInstant >= stint.departure.addingTimeInterval(-Double(max(preDays, 0)) * 86_400 - .hours(6)) {
                if governing == nil || !isPreShift {
                    governing = stint
                    isPreShift = true
                }
                break
            } else {
                break
            }
        }

        guard let stint = governing, let targetTZ = stint.arrivalZone.timeZone else {
            return (0, context.trip.homeZone, false, false)
        }

        let target = targetOffset(
            homeBedInstant: homeBedInstant,
            targetZone: targetTZ,
            context: context
        )
        return (target, stint.arrivalZone, true, isPreShift)
    }

    /// The body offset that would put tonight's sleep exactly at the habitual bedtime wall-clock
    /// in the target zone, expressed on the branch (advance vs. delay-around) the plan chose.
    private func targetOffset(
        homeBedInstant: Date,
        targetZone: TimeZone,
        context: PlanContext
    ) -> Double {
        let bedClock = context.profile.typicalBedtime
        let cal = Calendar.gregorian(in: targetZone)
        var best: Double = 0
        var bestDistance = Double.infinity
        // Candidate target-zone bed instants on nearby local dates; pick the one nearest the
        // chosen shift branch (e.g. −13 for an antidromic delay rather than +11).
        let expected = context.outboundShift.shiftHours
        for dayOffset in -2...2 {
            let baseDay = cal.startOfDay(for: homeBedInstant)
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: baseDay),
                  let candidate = bedClock.date(on: day, in: targetZone) else { continue }
            let offset = homeBedInstant.timeIntervalSince(candidate).inHours
            let distance = abs(offset - expected)
            if distance < bestDistance {
                bestDistance = distance
                best = offset
            }
        }
        return best
    }

    private struct StepResult {
        var newOffset: Double
    }

    private func nightlyStep(
        current: Double,
        target: Double,
        stepAllowed: Bool,
        isPreDeparture: Bool,
        context: PlanContext
    ) -> StepResult {
        guard stepAllowed else { return StepResult(newOffset: current) }
        let remaining = target - current
        if abs(remaining) < 0.35 { return StepResult(newOffset: target) }

        let direction: ShiftDirection = remaining > 0 ? .advance : .delay
        var rate = configuration.shiftRate(direction: direction, intensity: context.trip.intensity)
        if isPreDeparture {
            // Normal life continues before any departure (outbound or return): gentler rate.
            rate = min(rate, configuration.preTripRatePerDay)
        }
        let step = min(rate, abs(remaining))
        return StepResult(newOffset: current + (remaining > 0 ? step : -step))
    }

    /// Keeps a scheduled bedtime inside a practical local window (e.g. never "go to bed at 18:40").
    private func clampBedtimePractically(_ bed: Date, context: PlanContext) -> Date {
        // Anchor mode deliberately sleeps at odd local hours — that's the whole point.
        if context.strategy == .anchorToHome { return bed }
        let zoneID = context.zoneTimeline.zone(at: bed)
        guard let zone = zoneID.timeZone else { return bed }
        // Never clamp a bed that falls mid-flight; in-flight fitting handles it.
        if context.zoneTimeline.segment(at: bed, in: context.trip) != nil { return bed }

        let cal = Calendar.gregorian(in: zone)
        let comps = cal.dateComponents([.hour, .minute], from: bed)
        let clock = LocalClockTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        let earliest = configuration.earliestPracticalBedtime
        let latest = configuration.latestPracticalBedtime

        // The practical window wraps midnight: [20:30 … 01:30].
        let inWindow = clock >= earliest || clock <= latest
        if inWindow { return bed }

        if clock > latest && clock < LocalClockTime(hour: 12) {
            // Too late (e.g. 03:30) → pull back to the latest practical bedtime.
            let anchor = bed.addingTimeInterval(-.hours(6))
            return CircadianMath.resolve(latest, onDayContaining: anchor, zone: zone).addingTimeInterval(86_400)
        } else {
            // Too early (e.g. 18:45) → push to the earliest practical bedtime that evening.
            return CircadianMath.resolve(earliest, onDayContaining: bed, zone: zone)
        }
    }

    // MARK: - Plan days

    private func makePlanDay(index: Int, night: Night, context: PlanContext) -> PlanDay {
        let midday = night.wake.addingTimeInterval(night.bed.timeIntervalSince(night.wake) / 2)
        let zoneID = context.zoneTimeline.zone(at: midday)
        let zone = zoneID.resolved
        let cal = Calendar.gregorian(in: zone)
        let dayStart = cal.startOfDay(for: midday)
        let phase = context.zoneTimeline.phase(at: midday, in: context.trip)
        var label = dayLabel(phase: phase, midday: midday, zone: zone, context: context)
        if night.isPreDeparture && !night.isPreTrip && !night.isAdapted {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone
            formatter.dateFormat = "EEE, MMM d"
            label = "Easing toward home time · \(formatter.string(from: midday))"
        }

        return PlanDay(
            id: Self.deterministicID(planScope: context.trip.id, kind: "day", index: index),
            index: index,
            dayStart: dayStart,
            zone: zoneID,
            phase: phase,
            estimatedBed: night.bed,
            estimatedWake: night.wake,
            estimatedCBTmin: night.cbtMin,
            cumulativeShiftHours: night.bodyOffsetAfter,
            label: label
        )
    }

    private func dayLabel(phase: TripPhase, midday: Date, zone: TimeZone, context: PlanContext) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "EEE, MMM d"
        let dateText = formatter.string(from: midday)

        switch phase {
        case .beforeDeparture:
            if let dep = context.trip.firstDeparture {
                let days = Int((dep.timeIntervalSince(midday) / 86_400).rounded(.up))
                if days == 1 { return "Day before departure · \(dateText)" }
                if days > 1 { return "\(days) days before departure · \(dateText)" }
            }
            return "Before departure · \(dateText)"
        case .atAirport:
            return "Travel day · \(dateText)"
        case .inFlight:
            return "Flight day · \(dateText)"
        case .afterArrival:
            if let arrival = context.trip.outboundArrival {
                let days = Int(midday.timeIntervalSince(arrival) / 86_400)
                if days < 1 { return "Landing day · \(dateText)" }
                return "Day \(days + 1) in \(context.trip.destination) · \(dateText)"
            }
            return "After arrival · \(dateText)"
        case .recovery:
            return "Recovery · \(dateText)"
        case .returnTrip:
            return "Return · \(dateText)"
        }
    }

    // MARK: - Density caps

    private func enforceDensityCaps(actions: [PlanAction], days: [PlanDay], context: PlanContext) -> [PlanAction] {
        let cap = configuration.maxActionsPerDay[context.trip.intensity] ?? 8
        var kept: [PlanAction] = []
        for day in days {
            var dayActions = actions.filter { $0.dayIndex == day.index }
            if dayActions.count > cap {
                dayActions.sort { lhs, rhs in
                    if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                    return lhs.impactScore > rhs.impactScore
                }
                let mustKeep = dayActions.filter { $0.priority == .mustDo }
                let rest = dayActions.filter { $0.priority != .mustDo }
                let room = max(0, cap - mustKeep.count)
                dayActions = mustKeep + Array(rest.prefix(room))
            }
            kept.append(contentsOf: dayActions.sorted { $0.window.start < $1.window.start })
        }
        return kept
    }

    // MARK: - Utilities

    static func roundWindows(_ actions: [PlanAction]) -> [PlanAction] {
        actions.map { action in
            var copy = action
            copy.window = TimeWindow(
                start: round5(action.window.start),
                end: round5(action.window.end)
            )
            return copy
        }
    }

    static func round5(_ date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        let rounded = (interval / 300).rounded() * 300
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    /// Deterministic UUIDs so regenerated plans keep stable identities for identical inputs.
    static func deterministicPlanID(tripID: UUID) -> UUID {
        deterministicID(planScope: tripID, kind: "plan", index: 0)
    }

    static func deterministicID(planScope: UUID, kind: String, index: Int) -> UUID {
        // FNV-1a over a stable string, expanded to 16 bytes. Not cryptographic; just stable.
        let seed = "\(planScope.uuidString)/\(kind)/\(index)"
        var hash1: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash1 ^= UInt64(byte)
            hash1 = hash1 &* 0x100000001b3
        }
        var hash2: UInt64 = 0x84222325cbf29ce4
        for byte in seed.utf8.reversed() {
            hash2 ^= UInt64(byte)
            hash2 = hash2 &* 0x100000001b3
        }
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((hash1 >> UInt64(shift)) & 0xff)) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((hash2 >> UInt64(shift)) & 0xff)) }
        // Set RFC 4122 version (4) and variant bits so the UUID is well-formed.
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func strategySummary(context: PlanContext, delta: Double) -> String {
        let trip = context.trip
        let hours = Int(abs(delta).rounded())
        let aheadBehind = delta > 0 ? "ahead of" : "behind"
        switch context.strategy {
        case .anchorToHome:
            if abs(delta) < configuration.minimumShiftWorthPlanning {
                return "\(trip.destination) is on nearly the same clock as home, so no body-clock shift is needed — we'll just protect your sleep around the flights."
            }
            return "You're only in \(trip.destination) briefly, so the easiest option is to stay close to your home clock instead of fully adapting. We'll protect sleep and keep you sharp when it matters."
        case .fullyAdapt, .automatic:
            let dir = context.outboundShift.direction
            let perDay = configuration.shiftRate(direction: dir, intensity: trip.intensity)
            let dirText = dir == .advance ? "earlier" : "later"
            let magnitude = Int(abs(context.outboundShift.shiftHours).rounded())
            if dir == .delay && delta > 0 {
                return "\(trip.destination) is \(hours)h \(aheadBehind) home — so far east that it's faster to shift your clock \(magnitude)h later (the long way around) at about \(trimmedRate(perDay))h per day, using evening light and later sleep."
            }
            return "\(trip.destination) is \(hours)h \(aheadBehind) home. We'll shift your body clock \(dirText) by about \(trimmedRate(perDay))h per day using timed light, sleep, and caffeine."
        }
    }

    private func trimmedRate(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2g", value)
    }
}

/// Everything the per-day builders need, bundled to keep signatures sane.
struct PlanContext {
    let trip: Trip
    let profile: UserProfile
    let configuration: PlanEngineConfiguration
    let homeZone: TimeZone
    let zoneTimeline: ZoneTimeline
    let stints: [PlanEngine.Stint]
    let strategy: AdaptationStrategy
    let outboundShift: CircadianMath.ShiftPlan
    let state: TravelerState?
}
