import Foundation

/// Per-day action generation: sleep fitting, light windows, caffeine, melatonin, naps,
/// stay-awake anchors, and comfort actions — each constrained by flights, meal service,
/// commitments, and the traveler's stated limits.
extension PlanEngine {

    struct DayBuild {
        var actions: [PlanAction] = []
        var adjustments: [PlanAdjustment] = []
    }

    func buildActions(
        dayIndex: Int,
        night: Night,
        previousNight: Night?,
        day: PlanDay,
        context: PlanContext
    ) -> DayBuild {
        var build = DayBuild()
        var slot = 0
        func nextID(_ kind: String) -> UUID {
            slot += 1
            return Self.deterministicID(planScope: context.trip.id, kind: "action/\(kind)/\(dayIndex)", index: slot)
        }

        let cfg = context.configuration
        let profile = context.profile
        let strategy = context.strategy
        // Direction is per-night: the return leg of an eastward trip is a delay.
        let direction = night.direction

        let adapted = night.isAdapted
        let isShifting = !adapted && strategy != .anchorToHome
        let arrivalInfo = arrivalToday(night: night, previousNight: previousNight, context: context)
        let flightOverlapsToday = context.trip.segments.contains {
            $0.window.overlaps(TimeWindow(start: night.wake, end: night.nextWake))
        }

        // When last night's sleep actually ends later than the schedule says (an in-flight
        // block running past the nominal wake), the *day* starts when the sleep ends —
        // caffeine, light and stay-awake guidance must not overlap it.
        let previousSleepEnd = previousNight.flatMap { prev in
            fitSleep(night: prev, context: context).pieces.map(\.window.end).max()
        }
        let effectiveWake = min(
            max(night.wake, previousSleepEnd ?? night.wake),
            night.bed.adding(hours: -2)
        )

        // Fully adapted, no travel today, past the recovery buffer → quiet day, no actions.
        if adapted, !flightOverlapsToday, arrivalInfo == nil,
           daysSinceLastArrival(night: night, context: context) > cfg.recoveryBufferDays + 1,
           night.bed > (context.trip.outboundArrival ?? .distantPast) {
            return build
        }

        // MARK: Sleep

        let fit = fitSleep(night: night, context: context)
        build.adjustments.append(contentsOf: fit.adjustments)
        var mainPieceID: UUID?
        for (pieceIndex, piece) in fit.pieces.enumerated() {
            let isMain = pieceIndex == fit.mainIndex
            let id = nextID("sleep")
            if isMain { mainPieceID = id }
            build.actions.append(sleepAction(
                id: id,
                piece: piece,
                isMain: isMain,
                night: night,
                dayIndex: dayIndex,
                day: day,
                context: context,
                adapted: adapted
            ))
        }
        if fit.pieces.isEmpty, let restWindow = fit.restFallback {
            build.actions.append(PlanAction(
                id: nextID("rest"),
                type: .sleep,
                window: restWindow,
                displayZone: context.zoneTimeline.zone(at: restWindow.start),
                priority: .helpful,
                impactScore: 65,
                title: "Rest, even without sleep",
                instruction: "Eyes closed, seat back, noise-cancelling on. Quiet rest still lowers tonight's cost even if you never fully sleep.",
                explanation: "You told us sleeping on planes isn't realistic for you, so the plan doesn't depend on it. Restful wakefulness reduces strain, and we'll protect your first night at the destination instead.",
                alternative: "A short doze is a bonus, not a requirement.",
                dayIndex: dayIndex,
                phase: .inFlight,
                confidence: .solid,
                ruleReference: "v1/rest-inflight"
            ))
        }
        _ = mainPieceID

        // MARK: Wind-down before the main sleep

        if let main = fit.pieces.indices.contains(fit.mainIndex) ? fit.pieces[fit.mainIndex] : nil,
           main.window.duration >= .hours(3) {
            let windDown = TimeWindow(
                start: main.window.start.adding(minutes: -45),
                end: main.window.start
            )
            let inFlight = main.kind.isInFlight
            if !inFlight || main.window.duration >= .hours(4) {
                build.actions.append(PlanAction(
                    id: nextID("winddown"),
                    type: .windDown,
                    window: windDown,
                    displayZone: context.zoneTimeline.zone(at: windDown.start),
                    priority: .helpful,
                    impactScore: 46,
                    title: inFlight ? "Set up to sleep" : "Start winding down",
                    instruction: inFlight
                        ? "Eye mask, water, seat arranged, screens off. Tell the crew to skip you if a service comes."
                        : "Dim the lights, put screens away, and let the day end. Bright light now works against tonight's shift.",
                    explanation: "Light and stimulation in the last hour before bed push your body clock the wrong way and make sleep shallower.",
                    dayIndex: dayIndex,
                    phase: inFlight ? .inFlight : day.phase,
                    confidence: .solid,
                    ruleReference: "v1/wind-down"
                ))
            }
        }

        // MARK: Light

        if isShifting || arrivalInfo != nil {
            // The traveler's day starts at whichever comes first: scheduled wake or being
            // forced awake by a landing — but never before last night's sleep actually ends.
            var lightDayStart = night.wake
            if let arrival = arrivalInfo {
                lightDayStart = min(lightDayStart, arrival.adding(minutes: 20))
            }
            lightDayStart = max(lightDayStart, previousSleepEnd?.adding(minutes: 15) ?? lightDayStart)
            let lightBuild = lightActions(
                night: night,
                dayIndex: dayIndex,
                day: day,
                dayStart: lightDayStart,
                arrival: arrivalInfo,
                direction: direction,
                sleepWindows: fit.pieces.map(\.window),
                nextID: nextID,
                context: context
            )
            build.actions.append(contentsOf: lightBuild.actions)
            build.adjustments.append(contentsOf: lightBuild.adjustments)
        }

        // MARK: Stay awake until local bedtime (the westward arrival-evening anchor)

        if let arrival = arrivalInfo, strategy != .anchorToHome {
            // When the body *feels* like sleeping: tonight's nominal (unclamped) bed re-shifted
            // back to the phase actually reached before tonight's step.
            let bodyFeelsBed = night.nominalBed.adding(
                hours: night.bodyOffsetAfter - night.bodyOffsetBefore
            )
            let gapStart = max(arrival.adding(minutes: 45), max(bodyFeelsBed, effectiveWake))
            if night.bed.timeIntervalSince(gapStart) >= .hours(1.5) {
                let window = TimeWindow(start: gapStart, end: night.bed)
                build.actions.append(PlanAction(
                    id: nextID("stayawake"),
                    type: .stayAwake,
                    window: window,
                    displayZone: context.zoneTimeline.zone(at: window.start),
                    priority: .mustDo,
                    impactScore: 88,
                    title: "Hold out for bedtime",
                    instruction: "This stretch is the hard part — your body is lobbying for sleep. Stay busy, stay upright, stay social. Bed comes at the time shown, not before.",
                    explanation: "Crashing early tonight locks in your old time zone and usually means a 3 AM wide-awake stare at the ceiling. Making it to a sensible local bedtime is the single biggest win of arrival day.",
                    alternative: "Fading badly? A 20-minute nap now beats an accidental 3-hour crash — set an alarm.",
                    dayIndex: dayIndex,
                    phase: .afterArrival,
                    confidence: .solid,
                    ruleReference: "v1/stay-awake-arrival"
                ))
            }
        }

        // MARK: Nap (arrival-day damage control)

        if let arrival = arrivalInfo {
            let previousSleep = previousNight.map { scheduledSleepSeconds(night: $0, context: context) }
                ?? profile.typicalSleepDuration
            let debtFromState = context.state?.sleepDebtHours ?? 0
            if previousSleep < cfg.napSleepDebtThreshold || debtFromState >= 2 {
                if let nap = napWindow(night: night, arrival: arrival, context: context) {
                    build.actions.append(PlanAction(
                        id: nextID("nap"),
                        type: .nap,
                        window: nap,
                        displayZone: context.zoneTimeline.zone(at: nap.start),
                        priority: .helpful,
                        impactScore: 50,
                        title: "Power nap, \(Int(cfg.maxNapMinutes)) minutes tops",
                        instruction: "If you're struggling, one short nap now. Set an alarm for \(Int(cfg.maxNapMinutes)) minutes — longer drops you into deep sleep and steals from tonight.",
                        explanation: "Last night was short. A brief nap takes the edge off without shifting your clock or wrecking tonight's sleep, as long as it ends early enough.",
                        alternative: "Can't nap? Ten minutes sitting quietly with eyes closed still helps.",
                        dayIndex: dayIndex,
                        phase: .afterArrival,
                        confidence: .estimate,
                        ruleReference: "v1/nap-arrival"
                    ))
                }
            }
        }

        // MARK: Caffeine

        if profile.caffeine == .include, isShifting || arrivalInfo != nil || flightOverlapsToday {
            let cutoff = night.bed.adding(hours: -cfg.caffeineCutoffHoursBeforeBed)
            let earliest = effectiveWake.adding(hours: cfg.caffeineDelayAfterWake)
            if cutoff.timeIntervalSince(earliest) >= .hours(1.5) {
                let showOKWindow = flightOverlapsToday || arrivalInfo != nil
                    || daysSinceLastArrival(night: night, context: context) <= 2
                if showOKWindow {
                    let window = TimeWindow(start: earliest, end: cutoff)
                    build.actions.append(PlanAction(
                        id: nextID("caffeine-ok"),
                        type: .caffeineOK,
                        window: window,
                        displayZone: context.zoneTimeline.zone(at: window.start),
                        priority: .optional,
                        impactScore: 30,
                        title: "Coffee's on your side",
                        instruction: "Coffee and tea are on your side in this window — use them to stay alert, especially through the afternoon dip.",
                        explanation: "Caffeine can't move your body clock, but it papers over sleepiness while the clock catches up. The trick is stopping early enough that it can't touch tonight's sleep.",
                        notificationEnabled: false,
                        dayIndex: dayIndex,
                        phase: day.phase,
                        confidence: .solid,
                        ruleReference: "v1/caffeine-window"
                    ))
                }
                build.actions.append(PlanAction(
                    id: nextID("caffeine-cutoff"),
                    type: .caffeineCutoff,
                    window: TimeWindow(start: cutoff, end: cutoff.adding(minutes: 15)),
                    displayZone: context.zoneTimeline.zone(at: cutoff),
                    priority: .helpful,
                    impactScore: 55,
                    title: "Last call for caffeine",
                    instruction: "This is last call — after this, water, decaf, or herbal tea. Caffeine lingers for 8–10 hours and tonight's sleep is doing real work.",
                    explanation: "Half the caffeine you drink is still active ~5 hours later. Stopping well before bed keeps it from cutting into the deep sleep that moves your clock.",
                    dayIndex: dayIndex,
                    phase: day.phase,
                    confidence: .solid,
                    ruleReference: "v1/caffeine-cutoff"
                ))
            } else if isShifting {
                let window = TimeWindow(start: night.wake, end: night.wake.adding(minutes: 30))
                build.actions.append(PlanAction(
                    id: nextID("caffeine-skip"),
                    type: .caffeineCutoff,
                    window: window,
                    displayZone: context.zoneTimeline.zone(at: window.start),
                    priority: .helpful,
                    impactScore: 55,
                    title: "Skip caffeine today",
                    instruction: "Bedtime comes early today, so even a morning coffee would still be working against you tonight. Push through on water and daylight.",
                    explanation: "Today's target bedtime is early enough that there's no window where caffeine clears in time.",
                    dayIndex: dayIndex,
                    phase: day.phase,
                    confidence: .solid,
                    ruleReference: "v1/caffeine-skip"
                ))
            }
        }

        // MARK: Melatonin (optional reminders only)

        if profile.melatonin.remindersEnabled, isShifting,
           direction == .advance || cfg.melatoninForDelays {
            let withinArrival = daysSinceLastArrival(night: night, context: context) <= cfg.melatoninDaysAfterArrival
            if night.isPreTrip || withinArrival || flightOverlapsToday {
                let time = night.bed.adding(hours: -cfg.melatoninAdvanceLeadHours)
                if time > night.wake.adding(hours: 1) {
                    build.actions.append(PlanAction(
                        id: nextID("melatonin"),
                        type: .melatoninOptional,
                        window: TimeWindow(start: time, end: time.adding(minutes: 30)),
                        displayZone: context.zoneTimeline.zone(at: time),
                        priority: .optional,
                        impactScore: 40,
                        title: "Melatonin, if you use it",
                        instruction: "If you've chosen to use melatonin, early evening (a few hours before your shifted bedtime) is when it best supports an earlier clock — not just at lights-out.",
                        explanation: "Taken well before bed, melatonin acts as a timing signal that complements your light plan. It's entirely optional — the plan works without it. \(SafetyCopy.melatoninDisclaimer)",
                        notificationEnabled: profile.notifications.includeOptionalActions,
                        dayIndex: dayIndex,
                        phase: day.phase,
                        confidence: .individual,
                        ruleReference: "v1/melatonin-advance"
                    ))
                }
            }
        }

        // MARK: Travel-day comfort & framing actions

        build.actions.append(contentsOf: travelDayActions(
            night: night,
            dayIndex: dayIndex,
            day: day,
            nextID: nextID,
            context: context
        ))

        return build
    }

    // MARK: - Sleep fitting

    struct SleepPiece {
        enum Kind {
            case home
            case ground
            case layover
            case inFlight(FlightSegment)
            case postArrival

            var isInFlight: Bool {
                if case .inFlight = self { return true }
                return false
            }
        }
        var window: TimeWindow
        var kind: Kind
    }

    struct SleepFitResult {
        var pieces: [SleepPiece]
        var mainIndex: Int
        var restFallback: TimeWindow?
        var adjustments: [PlanAdjustment]
    }

    func fitSleep(night: Night, context: PlanContext) -> SleepFitResult {
        let base = computeSleepPieces(
            window: TimeWindow(start: night.bed, end: night.nextWake),
            context: context
        )
        var pieces = base.pieces
        var adjustments: [PlanAdjustment] = []
        let total = pieces.reduce(0.0) { $0 + $1.window.duration }

        // Short night? Retry with a widened window (earlier bed, later wake) and keep if better.
        if total < context.configuration.minimumProtectedSleep {
            let widened = computeSleepPieces(
                window: TimeWindow(
                    start: night.bed.adding(hours: -1.5),
                    end: night.nextWake.adding(hours: 1.5)
                ),
                context: context
            )
            let widenedTotal = widened.pieces.reduce(0.0) { $0 + $1.window.duration }
            if widenedTotal > total + .hours(0.5) {
                pieces = widened.pieces
                if !pieces.isEmpty {
                    adjustments.append(PlanAdjustment(
                        id: PlanEngine.deterministicID(planScope: context.trip.id, kind: "adj/sleep/\(night.index)", index: 0),
                        date: night.bed,
                        reason: "short-night",
                        message: "Tonight is squeezed by your flights and commitments, so we widened the sleep window to protect as much rest as possible."
                    ))
                }
            }
        }

        var restFallback: TimeWindow?
        if pieces.isEmpty {
            // If the night mostly overlaps a flight, offer quiet rest there.
            let nightWindow = TimeWindow(start: night.bed, end: night.nextWake)
            if let segment = context.trip.segments.first(where: { $0.window.overlaps(nightWindow) }) {
                let start = max(segment.departure.adding(minutes: context.configuration.minutesAfterTakeoffBeforeSleep), night.bed)
                let end = min(segment.arrival.adding(minutes: -context.configuration.minutesBeforeLandingNoSleep), night.nextWake)
                if end > start { restFallback = TimeWindow(start: start, end: end) }
            }
        }

        let mainIndex = pieces.indices.max(by: { pieces[$0].window.duration < pieces[$1].window.duration }) ?? 0
        return SleepFitResult(pieces: pieces, mainIndex: mainIndex, restFallback: restFallback, adjustments: adjustments)
    }

    private struct PieceComputation {
        var pieces: [SleepPiece]
    }

    private func computeSleepPieces(window nightWindow: TimeWindow, context: PlanContext) -> PieceComputation {
        let cfg = context.configuration
        let profile = context.profile
        var candidates: [TimeWindow] = [nightWindow]

        func block(_ blocked: TimeWindow) {
            candidates = candidates.flatMap { $0.subtracting(blocked) }
        }

        // Pre-departure block: airport lead time, plus door-to-terminal transfer for the
        // first segment of each stint (connections only need the airport lead).
        let transferSeconds = Double(context.trip.airportTransferMinutes ?? cfg.defaultTransferMinutes) * 60
        let stintStartIDs = Set(context.stints.compactMap { $0.segments.first?.id })

        for segment in context.trip.segments where segment.window.overlaps(nightWindow) || TimeWindow(start: segment.departure.adding(hours: -6), end: segment.arrival.adding(hours: 1)).overlaps(nightWindow) {
            let preDeparture = TimeInterval.hours(cfg.airportArrivalLeadHours)
                + (stintStartIDs.contains(segment.id) ? transferSeconds + .minutes(cfg.transferPrepBufferMinutes) : .hours(0.5))
            // Transfer, security, boarding — no planned sleep.
            block(TimeWindow(
                start: segment.departure.addingTimeInterval(-preDeparture),
                end: segment.departure.adding(minutes: cfg.minutesAfterTakeoffBeforeSleep)
            ))
            // Descent, landing, deplaning, immigration.
            block(TimeWindow(
                start: segment.arrival.adding(minutes: -cfg.minutesBeforeLandingNoSleep),
                end: segment.arrival.adding(minutes: 60)
            ))
            // Meal services, unless the user prefers sleeping through them.
            if !profile.prioritizesSleepOverMeals {
                for meal in segment.estimatedMealWindows {
                    block(meal)
                }
            }
            // Users who never sleep on planes get no in-flight sleep scheduled at all.
            if profile.planeSleepAbility == .never {
                block(segment.window)
            }
        }

        for commitment in context.trip.commitments where commitment.blocksSleep {
            block(commitment.window)
        }

        // Post-arrival daytime gate: after landing at the final stint arrival, don't sleep
        // unless it's locally night (19:00–05:00) or the plan anchors to home time.
        if context.strategy != .anchorToHome {
            for stint in context.stints {
                let postArrival = TimeWindow(start: stint.arrival, end: stint.arrival.adding(hours: 14))
                guard postArrival.overlaps(nightWindow) else { continue }
                if let zone = stint.arrivalZone.timeZone {
                    let cal = Calendar.gregorian(in: zone)
                    let hour = cal.component(.hour, from: stint.arrival)
                    let landedInDaytime = hour >= 5 && hour < 19
                    if landedInDaytime {
                        block(TimeWindow(start: stint.arrival, end: eveningStart(after: stint.arrival, zone: zone)))
                    }
                }
            }
        }

        // Classify and filter.
        var pieces: [SleepPiece] = []
        for candidate in candidates {
            let midpoint = candidate.midpoint
            var kind: SleepPiece.Kind = .home
            var minimum: TimeInterval = .hours(1.5)
            if let segment = context.trip.segments.first(where: { $0.window.contains(midpoint) }) {
                kind = .inFlight(segment)
                minimum = cfg.minimumUsefulInFlightSleep
            } else if isDuringLayover(midpoint, context: context) {
                kind = .layover
                minimum = .hours(2.5)
            } else if let firstDep = context.trip.firstDeparture, midpoint < firstDep {
                kind = .home
            } else {
                kind = .ground
            }

            var window = candidate
            if case .inFlight = kind {
                // Respect the user's realistic in-flight maximum.
                var cap = profile.maxInFlightSleep
                if profile.planeSleepAbility == .rarely { cap = min(cap, .hours(2.5)) }
                if window.duration > cap {
                    window = TimeWindow(start: window.start, end: window.start.addingTimeInterval(cap))
                }
                if profile.planeSleepAbility == .never { continue }
            }
            if window.duration >= minimum {
                pieces.append(SleepPiece(window: window, kind: kind))
            }
        }
        pieces.sort { $0.window.start < $1.window.start }
        return PieceComputation(pieces: pieces)
    }

    private func isDuringLayover(_ instant: Date, context: PlanContext) -> Bool {
        let segments = context.trip.segments
        guard segments.count > 1 else { return false }
        for i in 1..<segments.count {
            let gap = TimeWindow(start: segments[i - 1].arrival, end: segments[i].departure)
            if gap.duration < .hours(48), gap.contains(instant) {
                return true
            }
        }
        return false
    }

    private func eveningStart(after instant: Date, zone: TimeZone) -> Date {
        let sevenPM = LocalClockTime(hour: 19)
        let candidate = CircadianMath.resolve(sevenPM, onDayContaining: instant, zone: zone)
        return candidate > instant ? candidate : candidate.addingTimeInterval(86_400)
    }

    private func sleepAction(
        id: UUID,
        piece: SleepPiece,
        isMain: Bool,
        night: Night,
        dayIndex: Int,
        day: PlanDay,
        context: PlanContext,
        adapted: Bool
    ) -> PlanAction {
        let zone = context.zoneTimeline.zone(at: piece.window.start)
        switch piece.kind {
        case .inFlight(let segment):
            let capped = piece.window.duration < night.nextWake.timeIntervalSince(night.bed) - .hours(1)
            return PlanAction(
                id: id,
                type: .sleep,
                window: piece.window,
                displayZone: zone,
                priority: isMain ? .mustDo : .helpful,
                impactScore: isMain ? 92 : 60,
                title: isMain ? "Sleep on the flight" : "Top-up sleep",
                instruction: context.profile.planeSleepAbility == .rarely
                    ? "Even broken dozing counts. Eye mask on, belt visible over the blanket, seat as flat as it goes."
                    : "This block lines up with your body's night. Eye mask, earplugs, seat back — protect it from movies and snack carts.",
                explanation: "This window overlaps the hours your body clock already expects to be asleep, so sleep here is easier to get and does double duty: rest now, and a head start on \(context.trip.destination) time.",
                alternative: "Can't drop off? Stay reclined with eyes closed — quiet rest is worth more than another movie.",
                adjustmentNote: capped ? "Capped at your realistic in-flight maximum — the plan doesn't pretend you'll sleep the whole flight." : nil,
                dayIndex: dayIndex,
                phase: .inFlight,
                confidence: .solid,
                ruleReference: "v1/sleep-inflight/\(segment.departureAirport)"
            )
        case .layover:
            return PlanAction(
                id: id,
                type: .sleep,
                window: piece.window,
                displayZone: zone,
                priority: .helpful,
                impactScore: 70,
                title: "Sleep during your layover",
                instruction: "Long enough connection to get real sleep. A lounge, a quiet gate, or a transit hotel — set two alarms and keep your passport on you.",
                explanation: "This layover overlaps your body's night. Banking sleep here beats arriving wrecked.",
                dayIndex: dayIndex,
                phase: .atAirport,
                confidence: .estimate,
                ruleReference: "v1/sleep-layover"
            )
        case .home, .ground, .postArrival:
            let anchored = context.strategy == .anchorToHome
            let title: String
            let instruction: String
            let explanation: String
            if anchored {
                title = "Sleep on home time"
                instruction = "You're staying on home time this trip, so keep to this window even though the local clock disagrees. Blackout curtains and an eye mask are your friends."
                explanation = "For a stay this short, fully adapting would cost more than it pays back — you'd just have to shift back again. Holding your home rhythm keeps you sharp for the trip and intact when you return."
            } else if adapted {
                title = "Keep regular hours"
                instruction = "You're adjusted — protect it. Regular bed and wake times for another day or two locks the new rhythm in."
                explanation = "The clock has moved; consistency now prevents it drifting back."
            } else if night.isPreTrip {
                title = "Tonight's sleep window"
                instruction = "Bedtime moves tonight as part of your head start. Dim the lights 45 minutes before, and keep the wake time too — sleeping in undoes the shift."
                explanation = "Each shifted night before you fly is one less groggy day after you land."
            } else {
                title = "Tonight's sleep window"
                instruction = "This is tonight's target window on local time. Dark room, cool air, phone face-down across the room."
                explanation = "Sleeping at the destination's night — even imperfectly — is the anchor every other part of the plan builds on."
            }
            return PlanAction(
                id: id,
                type: .sleep,
                window: piece.window,
                displayZone: zone,
                priority: isMain ? (adapted ? .helpful : .mustDo) : .helpful,
                impactScore: isMain ? (adapted ? 70 : (night.isPreTrip ? 85 : 95)) : 60,
                title: title,
                instruction: instruction,
                explanation: explanation,
                alternative: isMain && !adapted ? "Can't fall asleep? Stay in the dark and rest — don't reach for a screen; the darkness itself is doing work." : nil,
                dayIndex: dayIndex,
                phase: day.phase == .inFlight ? .beforeDeparture : day.phase,
                confidence: .solid,
                ruleReference: anchored ? "v1/sleep-anchor" : "v1/sleep-night"
            )
        }
    }

    private func scheduledSleepSeconds(night: Night, context: PlanContext) -> TimeInterval {
        fitSleep(night: night, context: context).pieces.reduce(0) { $0 + $1.window.duration }
    }

    // MARK: - Light

    private func lightActions(
        night: Night,
        dayIndex: Int,
        day: PlanDay,
        dayStart: Date,
        arrival: Date?,
        direction: ShiftDirection,
        sleepWindows: [TimeWindow],
        nextID: (String) -> UUID,
        context: PlanContext
    ) -> DayBuild {
        var build = DayBuild()
        let cfg = context.configuration
        guard direction != .none else { return build }
        let regions = CircadianMath.lightRegions(cbtMin: night.cbtMin, configuration: cfg)
        // The evening ends when tonight's sleep *actually* starts — the fitted window may
        // begin earlier than the nominal bed (e.g. widened before a dawn airport run).
        let actualBed = sleepWindows
            .map(\.start)
            .filter { abs($0.timeIntervalSince(night.bed)) < .hours(3) }
            .min() ?? night.bed
        let waking = TimeWindow(start: dayStart, end: min(night.bed, actualBed))
        let earliestToday = dayStart
        let isArrivalWindow = daysSinceLastArrival(night: night, context: context) <= 2

        switch direction {
        case .advance:
            // Seek morning light after CBTmin.
            var seek = regions.advanceRegion
            seek = TimeWindow(start: max(seek.start, earliestToday), end: seek.end)
            let seekResult = placeLightWindow(
                ideal: seek,
                waking: waking,
                zoneID: day.zone,
                preferStart: true,
                context: context
            )
            if let placed = seekResult.window {
                build.actions.append(seekLightAction(
                    id: nextID("seek-light"),
                    window: placed,
                    outdoor: seekResult.outdoor,
                    moved: seekResult.movedByCommitment,
                    isArrival: isArrivalWindow,
                    direction: .advance,
                    dayIndex: dayIndex,
                    day: day,
                    context: context
                ))
            }
            // Avoid light while the body is still pre-CBTmin (the red-eye sunglasses case).
            // The window hands over exactly where seek-light opens (CBTmin + buffer): the
            // phase estimate carries uncertainty, so "sunglasses until the seek window" is
            // both safer and simpler to follow than a gap between the two.
            let avoidEnd = night.cbtMin.adding(hours: cfg.lightBufferFromCBTmin)
            if avoidEnd > earliestToday {
                let avoid = TimeWindow(start: earliestToday, end: avoidEnd)
                if avoid.duration >= .hours(0.75),
                   let daylight = CircadianMath.clampToDaylight(avoid, zone: day.zone.resolved, daylight: cfg.daylightWindow) {
                    build.actions.append(avoidLightAction(
                        id: nextID("avoid-light"),
                        window: daylight,
                        direction: .advance,
                        isArrival: isArrivalWindow,
                        dayIndex: dayIndex,
                        day: day,
                        context: context
                    ))
                }
            }
        case .delay:
            // Seek evening light before the actual (fitted) sleep start.
            let seek = TimeWindow(start: actualBed.adding(hours: -3), end: actualBed.adding(hours: -0.5))
            let seekResult = placeLightWindow(
                ideal: seek,
                waking: waking,
                zoneID: day.zone,
                preferStart: false,
                context: context
            )
            if let placed = seekResult.window {
                build.actions.append(seekLightAction(
                    id: nextID("seek-light"),
                    window: placed,
                    outdoor: seekResult.outdoor,
                    moved: seekResult.movedByCommitment,
                    isArrival: isArrivalWindow,
                    direction: .delay,
                    dayIndex: dayIndex,
                    day: day,
                    context: context
                ))
            }
            // Avoid early-morning light for the first days (it would drag the clock forward).
            if isArrivalWindow {
                let avoid = TimeWindow(start: max(night.wake, earliestToday), end: max(night.wake, earliestToday).adding(hours: 2))
                if regions.advanceRegion.overlaps(avoid),
                   let daylight = CircadianMath.clampToDaylight(avoid, zone: day.zone.resolved, daylight: cfg.daylightWindow),
                   daylight.duration >= .hours(0.75) {
                    build.actions.append(avoidLightAction(
                        id: nextID("avoid-light"),
                        window: daylight,
                        direction: .delay,
                        isArrival: isArrivalWindow,
                        dayIndex: dayIndex,
                        day: day,
                        context: context
                    ))
                }
            }
        case .none:
            break
        }
        return build
    }

    private struct LightPlacement {
        var window: TimeWindow?
        var outdoor: Bool
        var movedByCommitment: Bool
    }

    /// Fits a light window into waking hours and daylight, dodging commitments.
    private func placeLightWindow(
        ideal: TimeWindow,
        waking: TimeWindow,
        zoneID: ZoneID,
        preferStart: Bool,
        context: PlanContext
    ) -> LightPlacement {
        let cfg = context.configuration
        guard var candidate = ideal.intersection(waking) else {
            return LightPlacement(window: nil, outdoor: true, movedByCommitment: false)
        }
        var outdoor = true
        if let daylight = CircadianMath.clampToDaylight(candidate, zone: zoneID.resolved, daylight: cfg.daylightWindow) {
            candidate = daylight
        } else {
            // Entirely outside plausible daylight (e.g. a winter evening) → indoor bright light.
            outdoor = false
        }

        // Subtract commitments; keep the best surviving slice.
        var slices = [candidate]
        for commitment in context.trip.commitments {
            slices = slices.flatMap { $0.subtracting(commitment.window) }
        }
        var moved = slices.count != 1 || slices.first != candidate
        var best = slices.max { $0.duration < $1.duration }
        if best == nil || best!.duration < .hours(cfg.seekLightMinimumDuration) {
            // Nothing usable around commitments — fall back to the raw candidate as an
            // indoor/at-desk suggestion rather than dropping the lever entirely.
            best = candidate
            outdoor = false
            moved = true
        }
        var final = best!
        let targetDuration = TimeInterval.hours(cfg.seekLightDuration)
        if final.duration > targetDuration {
            final = preferStart
                ? TimeWindow(start: final.start, end: final.start.addingTimeInterval(targetDuration))
                : TimeWindow(start: final.end.addingTimeInterval(-targetDuration), end: final.end)
        }
        return LightPlacement(window: final, outdoor: outdoor, movedByCommitment: moved)
    }

    private func seekLightAction(
        id: UUID,
        window: TimeWindow,
        outdoor: Bool,
        moved: Bool,
        isArrival: Bool,
        direction: ShiftDirection,
        dayIndex: Int,
        day: PlanDay,
        context: PlanContext
    ) -> PlanAction {
        let evening = direction == .delay
        let title = outdoor
            ? (evening ? "Soak up the evening light" : "Chase the daylight")
            : (evening ? "Keep your evening bright" : "Find your brightest spot")
        let instruction: String
        if outdoor {
            instruction = evening
                ? "Be outside or somewhere flooded with light. A walk, an outdoor dinner, a bright café — anything but a dim room."
                : "Get real daylight — a walk, breakfast by a window seat outside, coffee to go. Cloudy still counts; outdoor light beats indoor light 10-to-1."
        } else {
            instruction = evening
                ? "Keep every light on and sit near the brightest one. Screens are fine tonight — brightness is the point."
                : "Sit at the brightest spot you can find — a big window, a well-lit desk, a light-therapy lamp if you have one."
        }
        return PlanAction(
            id: id,
            type: .seekLight,
            window: window,
            displayZone: context.zoneTimeline.zone(at: window.start),
            priority: isArrival ? .mustDo : .helpful,
            impactScore: isArrival ? 90 : 75,
            title: title,
            instruction: instruction,
            explanation: evening
                ? "Evening light tells your body the day isn't over, nudging your clock later — exactly the direction this trip needs."
                : "Light in this window lands on the advancing side of your body's low point, pulling your clock earlier. It's the strongest single lever you have.",
            alternative: outdoor ? "Can't get out? The brightest window or lamp you can find is the next best thing." : nil,
            adjustmentNote: moved ? "Timed around your schedule — a smaller dose of light at the right time still counts." : nil,
            dayIndex: dayIndex,
            phase: day.phase,
            confidence: .solid,
            ruleReference: evening ? "v1/light-delay-seek" : "v1/light-advance-seek"
        )
    }

    private func avoidLightAction(
        id: UUID,
        window: TimeWindow,
        direction: ShiftDirection,
        isArrival: Bool,
        dayIndex: Int,
        day: PlanDay,
        context: PlanContext
    ) -> PlanAction {
        PlanAction(
            id: id,
            type: .avoidLight,
            window: window,
            displayZone: context.zoneTimeline.zone(at: window.start),
            priority: isArrival ? .mustDo : .helpful,
            impactScore: isArrival ? 82 : 60,
            title: "Sunglasses time",
            instruction: "Sunglasses outside, brim down, shady side of the street. Indoors, stay away from bright windows until this window ends.",
            explanation: direction == .advance
                ? "Bright light right now lands on the wrong side of your body's low point and would push your clock later — undoing last night's progress. After this window, light flips to your side."
                : "Early bright light would drag your clock earlier just as we're shifting it later. Ease into the morning; the light you want comes this evening.",
            alternative: "No sunglasses? Any shade helps — the goal is dimmer, not darkness.",
            dayIndex: dayIndex,
            phase: day.phase,
            confidence: .solid,
            ruleReference: direction == .advance ? "v1/light-advance-avoid" : "v1/light-delay-avoid"
        )
    }

    // MARK: - Travel-day actions

    private func travelDayActions(
        night: Night,
        dayIndex: Int,
        day: PlanDay,
        nextID: (String) -> UUID,
        context: PlanContext
    ) -> [PlanAction] {
        var actions: [PlanAction] = []
        let dayWindow = TimeWindow(start: night.wake, end: night.nextWake)
        let cfg = context.configuration
        let transferMinutes = Double(context.trip.airportTransferMinutes ?? cfg.defaultTransferMinutes)

        for (stintIndex, stint) in context.stints.enumerated() {
            // Leave-by anchor: prep + transfer + at-airport lead, back-computed from departure.
            if dayWindow.contains(stint.departure) {
                let leave = stint.departure
                    .adding(hours: -cfg.airportArrivalLeadHours)
                    .adding(minutes: -transferMinutes)
                let prepStart = leave.adding(minutes: -cfg.transferPrepBufferMinutes)
                actions.append(PlanAction(
                    id: nextID("leave"),
                    type: .leaveForAirport,
                    window: TimeWindow(start: prepStart, end: leave),
                    displayZone: stint.segments.first!.departureZone,
                    priority: .helpful,
                    impactScore: 72,
                    title: "Leave for the airport",
                    instruction: "About \(Int(transferMinutes)) minutes door to terminal, plus \(Int(cfg.airportArrivalLeadHours * 60)) minutes for check-in and security. Head out by the end of this window.",
                    explanation: "A calm departure protects the plan: no sprinting, no cortisol spike, and no temptation to nap at the gate at the wrong time. Adjust the transfer time in trip settings if your ride is longer.",
                    notificationEnabled: true,
                    dayIndex: dayIndex,
                    phase: .beforeDeparture,
                    confidence: .estimate,
                    ruleReference: "v1/leave-for-airport"
                ))
            }
            // Switch-to-destination-time at the first departure of each stint.
            if dayWindow.contains(stint.departure), context.strategy != .anchorToHome,
               abs(context.outboundShift.shiftHours) >= 3 {
                let window = TimeWindow(
                    start: stint.departure.adding(minutes: -20),
                    end: stint.departure.adding(minutes: 10)
                )
                let destination = stintIndex == context.stints.count - 1 && context.stints.count > 1
                    ? "home" : context.trip.destination
                actions.append(PlanAction(
                    id: nextID("switch-time"),
                    type: .switchToDestinationTime,
                    window: window,
                    displayZone: stint.segments.first!.departureZone,
                    priority: .helpful,
                    impactScore: 46,
                    title: "Switch your head to \(destination) time",
                    instruction: "Change your watch and phone now, and start living on \(destination) time — when you eat, when you doze, what 'late' means.",
                    explanation: "The sooner your decisions run on destination time, the sooner your body follows. It also makes the rest of this plan easier to read.",
                    dayIndex: dayIndex,
                    phase: .atAirport,
                    confidence: .solid,
                    ruleReference: "v1/switch-time"
                ))
                actions.append(PlanAction(
                    id: nextID("meals"),
                    type: .shiftMeals,
                    window: TimeWindow(start: stint.departure, end: stint.arrival),
                    displayZone: stint.arrivalZone,
                    priority: .optional,
                    impactScore: 25,
                    title: "Eat on \(destination) time",
                    instruction: "When meals come around, ask yourself what mealtime it is in \(destination) — eat with the new clock when you can, lightly when you can't.",
                    explanation: "Meal timing is a gentle secondary signal for your body clock. This is comfort and routine support, not a substitute for light and sleep timing.",
                    notificationEnabled: false,
                    dayIndex: dayIndex,
                    phase: .inFlight,
                    confidence: .individual,
                    ruleReference: "v1/meals"
                ))
            }

            for segment in stint.segments where segment.isLongHaul && dayWindow.contains(segment.departure) {
                actions.append(PlanAction(
                    id: nextID("hydrate"),
                    type: .hydrate,
                    window: segment.window,
                    displayZone: segment.departureZone,
                    priority: .optional,
                    impactScore: 20,
                    title: "Water over wine tonight",
                    instruction: "Cabin air is desert-dry. A glass of water every hour or two; go easy on alcohol — it fragments exactly the sleep you're trying to protect.",
                    explanation: "Hydration won't shift your clock, but dehydration and alcohol both make jet lag feel worse and sleep shallower. Comfort support, not circadian medicine.",
                    notificationEnabled: false,
                    dayIndex: dayIndex,
                    phase: .inFlight,
                    confidence: .solid,
                    ruleReference: "v1/hydrate"
                ))
            }

            if dayWindow.contains(stint.arrival) {
                let window = TimeWindow(
                    start: stint.arrival.adding(minutes: 40),
                    end: stint.arrival.adding(minutes: 100)
                )
                if window.end < night.bed {
                    actions.append(PlanAction(
                        id: nextID("move"),
                        type: .moveBody,
                        window: window,
                        displayZone: stint.arrivalZone,
                        priority: .optional,
                        impactScore: 20,
                        title: "Walk it off",
                        instruction: "Once you're through the airport, spend 20–30 minutes on your feet outside if you can — luggage drop, then a walk before you settle in.",
                        explanation: "Gentle movement after a long flight helps circulation and alertness, and pairs nicely with your light plan. Comfort support, not a circadian lever.",
                        notificationEnabled: false,
                        dayIndex: dayIndex,
                        phase: .afterArrival,
                        confidence: .estimate,
                        ruleReference: "v1/move"
                    ))
                }
            }
        }
        return actions
    }

    // MARK: - Shared helpers

    /// The stint arrival that makes this day "landing day", if any. The window opens at the
    /// previous night's bedtime: a red-eye lands during the body's night, before the
    /// scheduled wake, and that morning is still landing day.
    func arrivalToday(night: Night, previousNight: Night?, context: PlanContext) -> Date? {
        let windowStart = previousNight?.bed ?? night.wake.adding(hours: -14)
        let dayWindow = TimeWindow(start: windowStart, end: night.bed)
        for stint in context.stints where dayWindow.contains(stint.arrival) {
            return stint.arrival
        }
        return nil
    }

    private func daysSinceLastArrival(night: Night, context: PlanContext) -> Int {
        let reference = night.bed
        var best: Int = .max
        for stint in context.stints where stint.arrival <= reference {
            let days = Int(reference.timeIntervalSince(stint.arrival) / 86_400)
            best = min(best, days)
        }
        return best == .max ? .max : best
    }

    private func napWindow(night: Night, arrival: Date, context: PlanContext) -> TimeWindow? {
        let cfg = context.configuration
        let zone = context.zoneTimeline.zone(at: arrival).resolved
        let earliest = arrival.adding(minutes: 45)
        let latestEnd = night.bed.adding(hours: -cfg.napBufferBeforeBed)
        guard latestEnd > earliest else { return nil }

        // Candidate span, minus commitments (a nap during the client meeting helps no one).
        var slots = [TimeWindow(start: earliest, end: latestEnd)]
        for commitment in context.trip.commitments where commitment.blocksSleep {
            slots = slots.flatMap { $0.subtracting(commitment.window) }
        }
        let napLength = TimeInterval.minutes(cfg.maxNapMinutes)
        let usable = slots.filter { $0.duration >= napLength }
        guard !usable.isEmpty else { return nil }

        // Prefer the slot containing (or nearest after) 13:00 local.
        let onePM = CircadianMath.resolve(LocalClockTime(hour: 13), onDayContaining: max(earliest, night.wake), zone: zone)
        let preferred = usable.first { $0.end > onePM } ?? usable[0]
        let start = min(max(preferred.start, onePM), preferred.end.addingTimeInterval(-napLength))
        return TimeWindow(start: start, end: start.addingTimeInterval(napLength))
    }
}
