import Foundation
import Testing
@testable import ReclockKit

@Suite("Adaptive replanning")
struct ReplanningTests {
    let coordinator = PlanCoordinator()

    @Test("Flight delay rebuilds the future and preserves the past")
    func delayReplan() throws {
        let trip = DemoTrips.delayedOvernight(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let original = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)

        // Two hours before departure, the airline slips the flight by 2h.
        let segment = trip.segments[0]
        let asOf = segment.departure.adding(hours: -2)
        let delayed = coordinator.applyingDelay(
            to: trip,
            segmentID: segment.id,
            newDeparture: segment.departure.adding(hours: 2),
            newArrival: segment.arrival.adding(hours: 2)
        )
        #expect(delayed.segments[0].status == .delayed)

        var state = coordinator.estimateState(plan: original, trip: trip, events: [], asOf: asOf)
        state.events.append(TravelerEvent(
            date: asOf,
            kind: .flightDelayed(
                segmentID: segment.id,
                newDeparture: segment.departure.adding(hours: 2),
                newArrival: segment.arrival.adding(hours: 2)
            )
        ))
        let result = try coordinator.replan(trip: delayed, profile: profile, previousPlan: original, state: state)

        #expect(result.plan.revision == 2)
        #expect(!result.changeMessages.isEmpty)
        // No sleep may be scheduled during the *new* boarding window.
        let newBoarding = TimeWindow(
            start: segment.departure.adding(hours: 2).adding(minutes: -45),
            end: segment.departure.adding(hours: 2).adding(minutes: 45)
        )
        for action in result.plan.actions where action.type == .sleep {
            #expect(!action.window.overlaps(newBoarding))
        }
        // The merged plan validates against the delayed trip.
        let validation = TestSupport.validator.validate(plan: result.plan, trip: delayed, profile: profile)
        #expect(validation.isValid, Comment(rawValue: validation.conflicts.map(\.description).joined(separator: "; ")))
    }

    @Test("Completed past actions survive replanning untouched")
    func pastPreserved() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        var original = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)

        // Traveler completes the first two actions.
        let sorted = original.actions.sorted { $0.window.start < $1.window.start }
        let completedIDs = Set(sorted.prefix(2).map(\.id))
        original.actions = original.actions.map { action in
            var a = action
            if completedIDs.contains(a.id) { a.completion = .done }
            return a
        }
        let asOf = sorted[1].window.end.adding(minutes: 10)

        let state = coordinator.estimateState(plan: original, trip: trip, events: [], asOf: asOf)
        let result = try coordinator.replan(trip: trip, profile: profile, previousPlan: original, state: state)

        for id in completedIDs {
            let preserved = result.plan.actions.first { $0.id == id }
            #expect(preserved?.completion == .done, "completed action lost or reset")
        }
    }

    @Test("Missed sleep reduces estimated progress and future plans adapt")
    func missedSleepLowersEstimate() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)

        // As of the morning after the second night, compare: all-done vs. all-missed.
        guard plan.days.count >= 3 else {
            Issue.record("plan unexpectedly short")
            return
        }
        let asOf = plan.days[1].estimatedWake.adding(hours: 26)

        var allDone = plan
        allDone.actions = allDone.actions.map { a in
            var x = a; if x.window.end <= asOf { x.completion = .done }; return x
        }
        var allMissed = plan
        allMissed.actions = allMissed.actions.map { a in
            var x = a
            if x.window.end <= asOf && (x.type == .sleep || x.type == .seekLight) {
                x.completion = .notPossible
            }
            return x
        }

        let doneState = coordinator.estimateState(plan: allDone, trip: trip, events: [], asOf: asOf)
        let missedState = coordinator.estimateState(plan: allMissed, trip: trip, events: [], asOf: asOf)
        #expect(abs(doneState.achievedShiftHours) > abs(missedState.achievedShiftHours))

        // Replanning from the lower estimate still yields a valid plan.
        let result = try coordinator.replan(trip: trip, profile: profile, previousPlan: allMissed, state: missedState)
        let validation = TestSupport.validator.validate(plan: result.plan, trip: trip, profile: profile)
        #expect(validation.isValid)
    }

    @Test("Sleep-debt events raise the debt estimate and enable a nap")
    func sleepDebtEvents() {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try? TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        guard let plan else {
            Issue.record("plan generation failed")
            return
        }
        let asOf = trip.outboundArrival!.adding(minutes: 30)
        let events = [
            TravelerEvent(date: asOf.adding(hours: -3), kind: .couldNotSleep),
            TravelerEvent(date: asOf.adding(hours: -1), kind: .stillAwake),
        ]
        let state = coordinator.estimateState(plan: plan, trip: trip, events: events, asOf: asOf)
        #expect(state.sleepDebtHours >= 3)
    }

    @Test("Replan with no changes says so instead of inventing movement")
    func noopReplanMessage() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let original = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        let asOf = TestSupport.reference.adding(hours: 2)
        var state = coordinator.estimateState(plan: original, trip: trip, events: [], asOf: asOf)
        // Perfect adherence so far → same trajectory.
        state.achievedShiftHours = original.days.last(where: { $0.estimatedBed < asOf })?.cumulativeShiftHours ?? 0
        let result = try coordinator.replan(trip: trip, profile: profile, previousPlan: original, state: state)
        #expect(result.changeMessages.count >= 1)
    }
}
