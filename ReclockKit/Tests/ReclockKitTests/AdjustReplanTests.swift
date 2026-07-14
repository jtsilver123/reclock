import Foundation
import Testing
@testable import ReclockKit

/// The app's Adjust sheet edits the trip or profile, then replans through
/// estimateState → replan → merge (AppModel.recalculate's exact path). These tests
/// replicate that path and insist the knobs actually move the plan — guarding the
/// "adjusted, but nothing changed" bug class.
@Suite("Adjust-sheet replans move the plan")
struct AdjustReplanTests {
    let coordinator = PlanCoordinator()

    /// Fixed instant; the fixture departs JFK 4 days after this.
    private static let reference: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
    }()

    private struct Replay {
        var previous: JetLagPlan
        var merged: JetLagPlan
        var asOf: Date
        var trip: Trip
    }

    /// Build the original plan, apply the "adjustment", then replan the way the app does.
    private func adjust(
        asOf: (Trip) -> Date = { _ in reference },
        mutateTrip: (inout Trip) -> Void = { _ in },
        mutateProfile: (inout UserProfile) -> Void = { _ in }
    ) throws -> Replay {
        var trip = DemoTrips.newYorkToHelsinki(reference: Self.reference)
        var profile = DemoTrips.defaultProfile()
        let previous = try coordinator.engine.generatePlan(
            trip: trip, profile: profile, currentState: nil
        )
        mutateTrip(&trip)
        mutateProfile(&profile)
        let instant = asOf(trip)
        let state = coordinator.estimateState(plan: previous, trip: trip, events: [], asOf: instant)
        let result = try coordinator.replan(
            trip: trip, profile: profile, previousPlan: previous, state: state
        )
        return Replay(previous: previous, merged: result.plan, asOf: instant, trip: trip)
    }

    private func futureStarts(_ plan: JetLagPlan, after asOf: Date, type: ActionType) -> [Date] {
        plan.actions
            .filter { $0.type == type && $0.window.start > asOf }
            .map(\.window.start)
            .sorted()
    }

    @Test("Bedtime change moves upcoming sleep windows before departure")
    func bedtimeMovesSleep() throws {
        let replay = try adjust(
            mutateProfile: { $0.typicalBedtime = LocalClockTime(hour: 21, minute: 30) }
        )
        #expect(replay.merged.revision == replay.previous.revision + 1)
        let before = futureStarts(replay.previous, after: replay.asOf, type: .sleep)
        let after = futureStarts(replay.merged, after: replay.asOf, type: .sleep)
        try #require(!before.isEmpty && !after.isEmpty)
        #expect(abs(after[0].timeIntervalSince(before[0])) >= 1800,
                "a 90-minute bedtime change must move the next sleep window")
    }

    @Test("Intensity change reshapes the future plan")
    func intensityReshapes() throws {
        let replay = try adjust(mutateTrip: { $0.intensity = .maximum })
        let before = futureStarts(replay.previous, after: replay.asOf, type: .sleep)
        let after = futureStarts(replay.merged, after: replay.asOf, type: .sleep)
        #expect(before != after, "maximum intensity must alter upcoming sleep timing")
    }

    @Test("Head-start override adds and removes pre-departure shift days")
    func headStartOverride() throws {
        // "On travel day" (override 0) still shifts on the travel day itself — the
        // knob controls the *days before* it. Count shifted days on strictly earlier
        // calendar days, in home time.
        func shiftedDaysBeforeTravelDay(_ override: Int) throws -> Int {
            let replay = try adjust(mutateTrip: { $0.preTripDaysOverride = override })
            let departure = try #require(replay.trip.firstDeparture)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "America/New_York")!
            let travelDay = cal.startOfDay(for: departure)
            return replay.merged.days.filter {
                $0.dayStart < travelDay && abs($0.cumulativeShiftHours) > 0.1
            }.count
        }
        let none = try shiftedDaysBeforeTravelDay(0)
        let three = try shiftedDaysBeforeTravelDay(3)
        #expect(none == 0, "override 0 means no shifting before the travel day")
        #expect(three > none, "override 3 must schedule shifted evenings before departure")
    }

    @Test("Mid-trip bedtime change still moves the recovery nights")
    func midTripAdjust() throws {
        let replay = try adjust(
            asOf: { ($0.segments.first?.arrival ?? Self.reference).addingTimeInterval(7200) },
            mutateProfile: { $0.typicalBedtime = LocalClockTime(hour: 21, minute: 30) }
        )
        let before = futureStarts(replay.previous, after: replay.asOf, type: .sleep)
        let after = futureStarts(replay.merged, after: replay.asOf, type: .sleep)
        try #require(!before.isEmpty && !after.isEmpty)
        #expect(before != after, "post-landing sleep windows must track the new bedtime")
    }

    @Test("Switching to home-time anchoring tells one clear story")
    func anchorSwitchNarration() throws {
        var trip = DemoTrips.newYorkToHelsinki(reference: Self.reference)
        let profile = DemoTrips.defaultProfile()
        let previous = try coordinator.engine.generatePlan(
            trip: trip, profile: profile, currentState: nil
        )
        trip.adaptationStrategy = .anchorToHome
        let state = coordinator.estimateState(plan: previous, trip: trip, events: [], asOf: Self.reference)
        let result = try coordinator.replan(
            trip: trip, profile: profile, previousPlan: previous, state: state
        )
        #expect(result.changeMessages.contains { $0.contains("Staying on home time") })
        // No shift-start claims and no window-move noise for a plan that never shifts —
        // and never scientific notation anywhere.
        for message in result.changeMessages {
            #expect(!message.contains("Shifting now starts"))
            #expect(!message.contains("window moved"))
            #expect(!message.lowercased().contains("e+"))
        }
    }

    @Test("Replanning with nothing changed leaves the future alone")
    func noChangeIsStable() throws {
        let replay = try adjust()
        let before = futureStarts(replay.previous, after: replay.asOf, type: .sleep)
        let after = futureStarts(replay.merged, after: replay.asOf, type: .sleep)
        #expect(before == after, "an idle replan must not shuffle the plan")
    }
}
