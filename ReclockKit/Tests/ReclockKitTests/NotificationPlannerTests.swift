import Foundation
import Testing
@testable import ReclockKit

@Suite("Notification planning")
struct NotificationPlannerTests {
    let planner = NotificationPlanner()

    private func makePlanAndTrip() throws -> (JetLagPlan, Trip, UserProfile) {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        return (plan, trip, profile)
    }

    @Test("Notifications are scheduled with deterministic revision-scoped IDs")
    func deterministicIDs() throws {
        let (plan, trip, profile) = try makePlanAndTrip()
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        #expect(!notifications.isEmpty)
        for n in notifications {
            #expect(n.id.hasPrefix("r1/"))
        }
        // Same inputs → identical schedule (needed for duplicate prevention).
        let again = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        #expect(notifications == again)
    }

    @Test("Only leave-for-airport notifications are time-critical (Focus break-through)")
    func timeCriticalFlag() throws {
        let (plan, trip, profile) = try makePlanAndTrip()
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        let actionsByID = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.id, $0) })
        let critical = notifications.filter(\.isTimeCritical)
        let leaveActions = plan.actions.filter { $0.type == .leaveForAirport }
        #expect(!leaveActions.isEmpty, Comment(rawValue: "demo trip should produce leave-for-airport actions"))
        for n in critical {
            #expect(actionsByID[n.actionID]?.type == .leaveForAirport)
        }
        // Every future leave-for-airport notification carries the flag.
        for n in notifications where actionsByID[n.actionID]?.type == .leaveForAirport {
            #expect(n.isTimeCritical)
        }
    }

    @Test("A new revision produces a fully distinct ID set (old ones removable by prefix)")
    func revisionReplacement() throws {
        let (plan, trip, profile) = try makePlanAndTrip()
        var revised = plan
        revised.revision = 2
        let first = planner.plannedNotifications(plan: plan, trip: trip, profile: profile, after: TestSupport.reference)
        let second = planner.plannedNotifications(plan: revised, trip: trip, profile: profile, after: TestSupport.reference)
        let firstIDs = Set(first.map(\.id))
        let secondIDs = Set(second.map(\.id))
        #expect(firstIDs.isDisjoint(with: secondIDs))
    }

    @Test("Notifications disabled → empty schedule")
    func disabled() throws {
        var (plan, trip, profile) = try makePlanAndTrip()
        profile.notifications.enabled = false
        _ = plan
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        #expect(notifications.isEmpty)
    }

    @Test("Optional actions notify only when opted in")
    func optionalOptIn() throws {
        var (plan, trip, profile) = try makePlanAndTrip()
        _ = plan
        profile.notifications.includeOptionalActions = false
        let without = planner.plannedNotifications(plan: plan, trip: trip, profile: profile, after: TestSupport.reference)
        let optionalIDs = Set(plan.actions.filter { $0.priority == .optional }.map(\.id))
        #expect(!without.contains { optionalIDs.contains($0.actionID) })
    }

    @Test("Completed actions don't notify")
    func completedSilenced() throws {
        var (plan, trip, profile) = try makePlanAndTrip()
        // Mark every action done.
        plan.actions = plan.actions.map { action in
            var a = action
            a.completion = .done
            return a
        }
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        #expect(notifications.isEmpty)
    }

    @Test("Quiet hours: sleep-adjacent notifications are exempt; others move or drop")
    func quietHours() throws {
        let (plan, trip, profile) = try makePlanAndTrip()
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        let timeline = ZoneTimeline(trip: trip)
        let exemptTypes: Set<ActionType> = [.sleep, .windDown, .nap, .melatoninOptional, .leaveForAirport]
        let actionsByID = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.id, $0) })
        for n in notifications {
            guard let action = actionsByID[n.actionID], !exemptTypes.contains(action.type) else { continue }
            let zone = timeline.zone(at: n.fireDate).resolved
            let minutes = TestSupport.localMinutes(n.fireDate, zone.identifier)
            let clock = LocalClockTime(minutesSinceMidnight: minutes)
            #expect(
                !profile.notifications.quietHours.contains(clock),
                "\(action.type.rawValue) notification fires at \(clock) inside quiet hours"
            )
        }
    }

    @Test("Daily cap respected per intensity")
    func dailyCaps() throws {
        var trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        trip.intensity = .maximum
        var profile = DemoTrips.defaultProfile()
        profile.notifications.includeOptionalActions = true
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        let timeline = ZoneTimeline(trip: trip)
        var byDay: [String: Int] = [:]
        for n in notifications {
            let zone = timeline.zone(at: n.fireDate).resolved
            let cal = Calendar.gregorian(in: zone)
            let c = cal.dateComponents([.year, .month, .day], from: n.fireDate)
            byDay["\(c.year!)-\(c.month!)-\(c.day!)", default: 0] += 1
        }
        for (day, count) in byDay {
            #expect(count <= NotificationPlanner.dailyCaps[.maximum]!, "day \(day) has \(count) notifications")
        }
    }

    @Test("Only future notifications are scheduled")
    func futureOnly() throws {
        let (plan, trip, profile) = try makePlanAndTrip()
        let midTrip = trip.outboundArrival!
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: midTrip
        )
        for n in notifications {
            #expect(n.fireDate > midTrip)
        }
    }
}
