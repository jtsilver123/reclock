import Foundation
import Testing
@testable import ReclockKit

/// The Plan tab renders days sorted by index and groups consecutive days by phase.
/// These tests pin the engine-side invariants that rendering depends on.
@Suite("Plan day ordering & phase consistency")
struct PlanDayOrderingTests {

    private func makePlan(daysOut: Double = 14) throws -> JetLagPlan {
        let dep = Date().addingTimeInterval(daysOut * 86_400)
        let seg = FlightSegment(
            airline: "AA", flightNumber: "AA 100",
            departureAirport: "ORD", arrivalAirport: "JFK",
            departure: dep, arrival: dep.addingTimeInterval(2.2 * 3600),
            departureZone: ZoneID("America/Chicago"), arrivalZone: ZoneID("America/New_York")
        )
        var trip = Trip(
            name: "ORD → New York",
            origin: "ORD", destination: "New York",
            homeZone: ZoneID("Pacific/Honolulu"),
            destinationZone: ZoneID("America/New_York"),
            segments: [seg]
        )
        trip.preTripDaysOverride = 2
        let profile = UserProfile(homeZone: ZoneID("Pacific/Honolulu"))
        return try PlanEngine().generatePlan(trip: trip, profile: profile, currentState: nil)
    }

    @Test("Day index order is chronological")
    func indexOrderIsChronological() throws {
        let plan = try makePlan()
        let byIndex = plan.days.sorted { $0.index < $1.index }
        let byStart = plan.days.sorted { $0.dayStart < $1.dayStart }
        #expect(byIndex.map(\.id) == byStart.map(\.id))
    }

    @Test("Pre-departure days carry the before-departure phase their label claims")
    func labelsAgreeWithPhases() throws {
        let plan = try makePlan()
        for day in plan.days {
            if day.label.contains("before departure") {
                #expect(day.phase == .beforeDeparture, "\(day.label) has phase \(day.phase)")
            }
            if day.label.hasPrefix("Travel day") {
                #expect(day.phase == .atAirport, "\(day.label) has phase \(day.phase)")
            }
        }
    }

    @Test("The first rendered group is before-departure, not the airport")
    func firstGroupIsBeforeDeparture() throws {
        let plan = try makePlan()
        // Mirror the app's grouping: skip empty non-arrival days, group consecutive phases.
        var firstPhase: TripPhase?
        for day in plan.days.sorted(by: { $0.index < $1.index }) {
            let actions = plan.actions(onDay: day.index)
            if actions.isEmpty && !(day.phase == .afterArrival || day.phase == .recovery) { continue }
            firstPhase = day.phase
            break
        }
        #expect(firstPhase == .beforeDeparture)
    }
}
