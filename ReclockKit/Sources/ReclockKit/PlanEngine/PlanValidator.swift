import Foundation

/// Validates a generated plan before it reaches the user. The engine runs this in tests and
/// the app runs it defensively after every generation; an `error` conflict means the plan
/// must not be shown.
public struct PlanValidator: Sendable {
    public let configuration: PlanEngineConfiguration

    public init(configuration: PlanEngineConfiguration = PlanEngineConfiguration()) {
        self.configuration = configuration
    }

    public func validate(plan: JetLagPlan, trip: Trip, profile: UserProfile) -> PlanValidationResult {
        var conflicts: [PlanConflict] = []

        conflicts.append(contentsOf: checkContradictoryOverlaps(plan))
        conflicts.append(contentsOf: checkSleepBlockedWindows(plan, trip: trip, profile: profile))
        conflicts.append(contentsOf: checkCaffeine(plan, profile: profile))
        conflicts.append(contentsOf: checkMelatonin(plan, profile: profile))
        conflicts.append(contentsOf: checkDates(plan))
        conflicts.append(contentsOf: checkTripEnd(plan, trip: trip))
        conflicts.append(contentsOf: checkDuplicates(plan))
        conflicts.append(contentsOf: checkArrivalGuidance(plan, trip: trip))
        conflicts.append(contentsOf: checkInFlightSleepCap(plan, trip: trip, profile: profile))

        return PlanValidationResult(conflicts: conflicts)
    }

    // MARK: Contradictions

    private static let contradictoryPairs: [(ActionType, ActionType)] = [
        (.seekLight, .avoidLight),
        (.sleep, .stayAwake),
        (.sleep, .seekLight),
        (.nap, .stayAwake),
        (.caffeineOK, .sleep),
    ]

    private func checkContradictoryOverlaps(_ plan: JetLagPlan) -> [PlanConflict] {
        var conflicts: [PlanConflict] = []
        // Only live guidance can contradict; completed/expired actions are history records.
        let actions = plan.actions.filter { $0.completion == .pending }
        for i in actions.indices {
            for j in actions.indices where j > i {
                let a = actions[i], b = actions[j]
                guard a.window.overlaps(b.window) else { continue }
                let pair = (a.type, b.type)
                let hit = Self.contradictoryPairs.contains { p in
                    (p.0 == pair.0 && p.1 == pair.1) || (p.0 == pair.1 && p.1 == pair.0)
                }
                if hit {
                    conflicts.append(PlanConflict(
                        kind: .contradictoryOverlap,
                        severity: .error,
                        message: "\(a.type.rawValue) overlaps \(b.type.rawValue) (\(a.window.start)–\(a.window.end) vs \(b.window.start)–\(b.window.end)).",
                        actionIDs: [a.id, b.id]
                    ))
                }
            }
        }
        return conflicts
    }

    // MARK: Sleep in blocked windows

    private func checkSleepBlockedWindows(_ plan: JetLagPlan, trip: Trip, profile: UserProfile) -> [PlanConflict] {
        var conflicts: [PlanConflict] = []
        let sleepActions = plan.actions.filter {
            ($0.type == .sleep || $0.type == .nap) && $0.completion == .pending
        }
        // Note: quiet-rest fallbacks share the .sleep type but are titled "Rest…"; they are
        // intentionally allowed inside flights, but never inside the hard buffers below.
        for action in sleepActions {
            for segment in trip.segments {
                let boarding = TimeWindow(
                    start: segment.departure.adding(minutes: -Double(segment.boardingLeadMinutes)),
                    end: segment.departure.adding(minutes: configuration.minutesAfterTakeoffBeforeSleep)
                )
                let landing = TimeWindow(
                    start: segment.arrival.adding(minutes: -configuration.minutesBeforeLandingNoSleep),
                    end: segment.arrival
                )
                if action.window.overlaps(boarding) {
                    conflicts.append(PlanConflict(
                        kind: .sleepInBlockedWindow,
                        severity: .error,
                        message: "Sleep scheduled during boarding/takeoff of \(segment.displayName).",
                        actionIDs: [action.id]
                    ))
                }
                if action.window.overlaps(landing) {
                    conflicts.append(PlanConflict(
                        kind: .sleepInBlockedWindow,
                        severity: .error,
                        message: "Sleep scheduled during descent/landing of \(segment.displayName).",
                        actionIDs: [action.id]
                    ))
                }
            }
            for commitment in trip.commitments where commitment.blocksSleep {
                if action.window.overlaps(commitment.window) {
                    conflicts.append(PlanConflict(
                        kind: .sleepInBlockedWindow,
                        severity: .error,
                        message: "Sleep overlaps commitment “\(commitment.title)”.",
                        actionIDs: [action.id]
                    ))
                }
            }
        }
        return conflicts
    }

    // MARK: Caffeine

    private func checkCaffeine(_ plan: JetLagPlan, profile: UserProfile) -> [PlanConflict] {
        var conflicts: [PlanConflict] = []
        if profile.caffeine == .exclude {
            for action in plan.actions where action.type == .caffeineOK || action.type == .caffeineCutoff {
                conflicts.append(PlanConflict(
                    kind: .caffeineAfterCutoff,
                    severity: .error,
                    message: "Caffeine action present although the user opted out.",
                    actionIDs: [action.id]
                ))
            }
            return conflicts
        }
        // No caffeine-OK window may extend past that day's cutoff (live guidance only).
        for day in plan.days {
            let dayActions = plan.actions.filter { $0.dayIndex == day.index && $0.completion == .pending }
            let cutoffs = dayActions.filter { $0.type == .caffeineCutoff }
            guard let cutoff = cutoffs.max(by: { $0.window.start < $1.window.start }) else { continue }
            for ok in dayActions where ok.type == .caffeineOK {
                if ok.window.end > cutoff.window.start.adding(minutes: 5) {
                    conflicts.append(PlanConflict(
                        kind: .caffeineAfterCutoff,
                        severity: .error,
                        message: "Caffeine window on day \(day.index) runs past the cutoff.",
                        actionIDs: [ok.id, cutoff.id]
                    ))
                }
            }
        }
        return conflicts
    }

    // MARK: Melatonin

    private func checkMelatonin(_ plan: JetLagPlan, profile: UserProfile) -> [PlanConflict] {
        guard !profile.melatonin.remindersEnabled else { return [] }
        return plan.actions
            .filter { $0.type == .melatoninOptional }
            .map {
                PlanConflict(
                    kind: .melatoninWhenOptedOut,
                    severity: .error,
                    message: "Melatonin reminder present although the user did not opt in.",
                    actionIDs: [$0.id]
                )
            }
    }

    // MARK: Dates

    private func checkDates(_ plan: JetLagPlan) -> [PlanConflict] {
        var conflicts: [PlanConflict] = []
        for action in plan.actions {
            if action.window.duration <= 0 && action.type != .caffeineCutoff {
                conflicts.append(PlanConflict(
                    kind: .invalidDate,
                    severity: .error,
                    message: "Zero/negative-length window on \(action.type.rawValue).",
                    actionIDs: [action.id]
                ))
            }
            if action.window.duration > .hours(20) {
                conflicts.append(PlanConflict(
                    kind: .invalidDate,
                    severity: .warning,
                    message: "\(action.type.rawValue) window longer than 20h looks wrong.",
                    actionIDs: [action.id]
                ))
            }
            guard action.displayZone.timeZone != nil else {
                conflicts.append(PlanConflict(
                    kind: .invalidDate,
                    severity: .error,
                    message: "Unresolvable display zone \(action.displayZone.identifier).",
                    actionIDs: [action.id]
                ))
                continue
            }
        }
        return conflicts
    }

    // MARK: Trip end

    private func checkTripEnd(_ plan: JetLagPlan, trip: Trip) -> [PlanConflict] {
        guard let finalArrival = trip.finalArrival else { return [] }
        let hardEnd = finalArrival.addingTimeInterval(
            Double(configuration.maxAdaptationDays + 2) * 86_400
        )
        return plan.actions
            .filter { $0.window.start > hardEnd }
            .map {
                PlanConflict(
                    kind: .actionAfterTripEnd,
                    severity: .error,
                    message: "\($0.type.rawValue) scheduled long after the trip ended.",
                    actionIDs: [$0.id]
                )
            }
    }

    // MARK: Duplicates

    private func checkDuplicates(_ plan: JetLagPlan) -> [PlanConflict] {
        var seen: [String: UUID] = [:]
        var conflicts: [PlanConflict] = []
        for action in plan.actions {
            // Two same-type actions starting within 10 minutes of each other are duplicates.
            let bucket = Int(action.window.start.timeIntervalSinceReferenceDate / 600)
            let key = "\(action.type.rawValue)/\(bucket)"
            if let existing = seen[key] {
                conflicts.append(PlanConflict(
                    kind: .duplicateAction,
                    severity: .error,
                    message: "Duplicate \(action.type.rawValue) actions at the same time.",
                    actionIDs: [existing, action.id]
                ))
            } else {
                seen[key] = action.id
            }
            if plan.actions.filter({ $0.id == action.id }).count > 1 {
                conflicts.append(PlanConflict(
                    kind: .duplicateAction,
                    severity: .error,
                    message: "Duplicate action ID \(action.id).",
                    actionIDs: [action.id]
                ))
            }
        }
        return conflicts
    }

    // MARK: Arrival guidance

    private func checkArrivalGuidance(_ plan: JetLagPlan, trip: Trip) -> [PlanConflict] {
        guard let arrival = trip.outboundArrival else { return [] }
        let arrivalDay = TimeWindow(start: arrival.adding(hours: -2), end: arrival.adding(hours: 26))
        let hasGuidance = plan.actions.contains { action in
            action.window.overlaps(arrivalDay) && !action.type.isComfort
        }
        if !hasGuidance {
            return [PlanConflict(
                kind: .missingArrivalGuidance,
                severity: .error,
                message: "No clear recommendation on arrival day."
            )]
        }
        return []
    }

    // MARK: In-flight sleep cap

    private func checkInFlightSleepCap(_ plan: JetLagPlan, trip: Trip, profile: UserProfile) -> [PlanConflict] {
        var conflicts: [PlanConflict] = []
        for action in plan.actions where action.type == .sleep {
            for segment in trip.segments {
                guard let overlap = action.window.intersection(segment.window) else { continue }
                // Quiet-rest fallbacks are not sleep promises; identified by rule reference.
                if action.ruleReference.hasPrefix("v1/rest") { continue }
                if overlap.duration > profile.maxInFlightSleep + .minutes(10) {
                    conflicts.append(PlanConflict(
                        kind: .exceedsInFlightSleepMax,
                        severity: .error,
                        message: "In-flight sleep exceeds the user's stated realistic maximum.",
                        actionIDs: [action.id]
                    ))
                }
                if profile.planeSleepAbility == .never {
                    conflicts.append(PlanConflict(
                        kind: .exceedsInFlightSleepMax,
                        severity: .error,
                        message: "Sleep scheduled in flight for a user who never sleeps on planes.",
                        actionIDs: [action.id]
                    ))
                }
            }
        }
        return conflicts
    }
}
