import Foundation

/// Orchestrates replanning: estimates what the traveler's body clock actually did from their
/// reports, regenerates the future, preserves the past, and explains what changed.
public struct PlanCoordinator: Sendable {
    public let engine: PlanEngine
    public let configuration: PlanEngineConfiguration

    public init(configuration: PlanEngineConfiguration = PlanEngineConfiguration()) {
        self.configuration = configuration
        self.engine = PlanEngine(configuration: configuration)
    }

    // MARK: - State estimation

    /// Folds the traveler's reports into an updated `TravelerState` as of `asOf`.
    ///
    /// Model: each past night was scheduled to move the clock by some delta. Nights whose key
    /// actions (sleep, light) were confirmed done earn full credit; unreported nights earn
    /// partial credit; nights with reported misses earn reduced credit. Deliberately simple,
    /// deterministic, and documented in SCIENCE_SPEC.md — not a learned model.
    public func estimateState(
        plan: JetLagPlan,
        trip: Trip,
        events: [TravelerEvent],
        asOf: Date
    ) -> TravelerState {
        var achieved = 0.0
        var previousOffset = 0.0

        for day in plan.days.sorted(by: { $0.index < $1.index }) {
            guard day.estimatedBed < asOf else { break }
            let scheduledDelta = day.cumulativeShiftHours - previousOffset
            previousOffset = day.cumulativeShiftHours
            guard abs(scheduledDelta) > 0.01 else { continue }

            let dayActions = plan.actions.filter {
                $0.dayIndex == day.index && ($0.type == .sleep || $0.type == .seekLight)
            }
            let credit: Double
            if dayActions.isEmpty {
                credit = configuration.complianceCreditUnknown
            } else if dayActions.contains(where: { $0.completion == .notPossible || $0.completion == .skipped }) {
                credit = configuration.complianceCreditMissed
            } else if dayActions.allSatisfy({ $0.completion == .done }) {
                credit = configuration.complianceCreditDone
            } else {
                credit = configuration.complianceCreditUnknown
            }
            achieved += scheduledDelta * credit
        }

        // Sleep debt from explicit reports in the last ~48h.
        var debt = 0.0
        for event in events where event.date > asOf.addingTimeInterval(-.hours(48)) {
            switch event.kind {
            case .couldNotSleep: debt += 2.5
            case .stillAwake: debt += 1.0
            case .sleptInstead: debt = max(0, debt - 1.5)
            case .sleptUntil: debt = max(0, debt - 1.0)
            default: break
            }
        }

        return TravelerState(
            asOf: asOf,
            achievedShiftHours: achieved,
            sleepDebtHours: min(debt, 6),
            events: events.suffix(50).map { $0 }
        )
    }

    // MARK: - Replanning

    public struct ReplanResult: Sendable {
        public var plan: JetLagPlan
        /// User-facing messages about what changed, most important first.
        public var changeMessages: [String]
    }

    /// Applies a traveler event (delay, missed sleep, etc.), regenerates future actions,
    /// preserves completed history, and produces a "here's what changed" summary.
    public func replan(
        trip: Trip,
        profile: UserProfile,
        previousPlan: JetLagPlan,
        state: TravelerState
    ) throws -> ReplanResult {
        let fresh = try engine.generatePlan(trip: trip, profile: profile, currentState: state)
        let merged = merge(previous: previousPlan, fresh: fresh, asOf: state.asOf)
        let messages = describeChanges(previous: previousPlan, merged: merged, asOf: state.asOf, trip: trip)
        return ReplanResult(plan: merged, changeMessages: messages)
    }

    /// Applies a delay report to the trip's segments (the caller persists the returned trip).
    public func applyingDelay(
        to trip: Trip,
        segmentID: UUID,
        newDeparture: Date,
        newArrival: Date
    ) -> Trip {
        var updated = trip
        updated.segments = trip.segments.map { segment in
            guard segment.id == segmentID else { return segment }
            var s = segment
            s.departure = newDeparture
            s.arrival = newArrival
            s.status = .delayed
            return s
        }.sorted { $0.departure < $1.departure }
        return updated
    }

    // MARK: - Merge

    /// Past actions (ended before `asOf`) keep their recorded completion state from the
    /// previous plan; future actions come from the fresh plan. Notification identity is keyed
    /// off the bumped revision so stale notifications are fully replaced.
    public func merge(previous: JetLagPlan, fresh: JetLagPlan, asOf: Date) -> JetLagPlan {
        var merged = fresh
        merged.revision = previous.revision + 1

        let pastActions = previous.actions.filter { $0.window.end <= asOf }
        let pastIDs = Set(pastActions.map(\.id))
        let futureActions = fresh.actions.filter { $0.window.end > asOf }
        // Engine IDs are deterministic across regenerations, so a fresh action whose ID was
        // already preserved as history must not appear twice; likewise drop fresh actions
        // that materially duplicate preserved ones (same type, overlapping window).
        let dedupedFuture = futureActions.filter { future in
            guard !pastIDs.contains(future.id) else { return false }
            return !pastActions.contains { past in
                past.type == future.type && past.window.overlaps(future.window)
            }
        }
        var expiredPast = pastActions.map { action in
            var a = action
            if a.completion == .pending { a.completion = .expired }
            return a
        }
        expiredPast.append(contentsOf: dedupedFuture)
        merged.actions = expiredPast.sorted { $0.window.start < $1.window.start }
        merged.adjustments = (previous.adjustments + fresh.adjustments).suffix(20).map { $0 }
        return merged
    }

    // MARK: - Change narration

    private func describeChanges(
        previous: JetLagPlan,
        merged: JetLagPlan,
        asOf: Date,
        trip: Trip
    ) -> [String] {
        var messages: [String] = []

        // A switch to home-time anchoring rewrites the whole story: window deltas
        // ("your sleep moved 50 hours later") and shift-start messages are noise
        // against the one fact that matters.
        let becameAnchored = merged.strategy == .anchorToHome && previous.strategy != .anchorToHome
        if becameAnchored {
            messages.append("Staying on home time — no body-clock shifting scheduled.")
        }

        func upcoming(_ plan: JetLagPlan, _ type: ActionType) -> PlanAction? {
            plan.actions
                .filter { $0.type == type && $0.window.start > asOf }
                .min { $0.window.start < $1.window.start }
        }

        /// "1.5 hours", "2 hours", "45 minutes" — plain numbers at any magnitude
        /// (%.1g rendered a 2-day jump as "5e+01 hours").
        func amountText(_ delta: TimeInterval) -> String {
            let hours = abs(delta) / 3600
            guard hours >= 1 else { return "\(Int(abs(delta) / 60)) minutes" }
            let formatted = String(format: "%.1f", hours).replacingOccurrences(of: ".0", with: "")
            return "\(formatted) hour\(hours >= 1.95 ? "s" : "")"
        }

        let pairsToCheck: [(ActionType, String)] = [
            (.sleep, "sleep window"),
            (.seekLight, "light window"),
            (.caffeineCutoff, "caffeine cutoff"),
        ]
        for (type, label) in pairsToCheck where !becameAnchored {
            guard
                let before = upcoming(previous, type),
                let after = upcoming(merged, type)
            else { continue }
            let delta = after.window.start.timeIntervalSince(before.window.start)
            guard abs(delta) >= .minutes(30) else { continue }
            let direction = delta > 0 ? "later" : "earlier"
            messages.append("Your next \(label) moved \(amountText(delta)) \(direction).")
        }

        // Structural changes the next-window checks can't see — without these, an
        // Adjust-sheet change that reshapes the plan (more recovery days, a different
        // head start) gets reported as "nothing needed to move".
        func shiftedEveningsBeforeTravelDay(_ plan: JetLagPlan) -> Int {
            guard let departure = trip.firstDeparture,
                  let home = trip.homeZone.timeZone else { return 0 }
            let travelDay = Calendar.gregorian(in: home).startOfDay(for: departure)
            return plan.days.filter {
                $0.dayStart < travelDay && abs($0.cumulativeShiftHours) > 0.1
            }.count
        }
        let preBefore = shiftedEveningsBeforeTravelDay(previous)
        let preAfter = shiftedEveningsBeforeTravelDay(merged)
        if preBefore != preAfter && merged.strategy != .anchorToHome {
            messages.append(preAfter == 0
                ? "Shifting now starts on your travel day."
                : "Shifting now starts \(preAfter) evening\(preAfter == 1 ? "" : "s") before departure.")
        }
        if merged.days.count != previous.days.count {
            messages.append("Your plan now covers \(merged.days.count) days (was \(previous.days.count)).")
        }

        if let delayed = trip.segments.first(where: { $0.status == .delayed }) {
            messages.insert("We rebuilt the plan around the new times for \(delayed.displayName).", at: 0)
        }
        if messages.isEmpty {
            messages.append("Your plan is up to date — nothing ahead needed to move.")
        }
        return messages
    }
}
