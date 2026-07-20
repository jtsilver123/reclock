import Foundation
import Testing
@testable import ReclockKit

/// Pre-departure days must read in the zone the traveler actually stands in — the
/// first flight's departure zone — not a home zone that may be somewhere else
/// entirely (the app installed mid-journey stamps home from the device's zone).
@Suite("Zone timeline: trips that start away from home")
struct ZoneTimelineTests {

    /// Tromsø → Chicago, but the profile's home was stamped Copenhagen at install.
    private var awayTrip: Trip {
        let segment = FlightSegment(
            departureAirport: "TOS",
            arrivalAirport: "ORD",
            departure: TestSupport.utcDate(2026, 10, 5, 10, 0),
            arrival: TestSupport.utcDate(2026, 10, 5, 19, 30),
            departureZone: ZoneID("Europe/Oslo"),
            arrivalZone: ZoneID("America/Chicago")
        )
        return Trip(
            name: "Chicago", origin: "TOS", destination: "Chicago",
            homeZone: ZoneID("Europe/Copenhagen"),
            destinationZone: ZoneID("America/Chicago"),
            segments: [segment]
        )
    }

    @Test("Before departure the timeline reads in the origin's zone, not home's")
    func preDepartureUsesOriginZone() {
        let timeline = ZoneTimeline(trip: awayTrip)
        let twoDaysBefore = TestSupport.utcDate(2026, 10, 3, 12, 0)
        #expect(timeline.zone(at: twoDaysBefore) == ZoneID("Europe/Oslo"))
        let afterLanding = TestSupport.utcDate(2026, 10, 6, 12, 0)
        #expect(timeline.zone(at: afterLanding) == ZoneID("America/Chicago"))
        // The home anchor itself is untouched — only presentation moves.
        #expect(timeline.homeZone == ZoneID("Europe/Copenhagen"))
    }

    @Test("Trips that start at home behave exactly as before")
    func homeStartUnchanged() {
        let segment = FlightSegment(
            departureAirport: "JFK",
            arrivalAirport: "HEL",
            departure: TestSupport.utcDate(2026, 10, 5, 22, 0),
            arrival: TestSupport.utcDate(2026, 10, 6, 6, 0),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/Helsinki")
        )
        let trip = Trip(
            name: "Helsinki", origin: "JFK", destination: "Helsinki",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/Helsinki"),
            segments: [segment]
        )
        let timeline = ZoneTimeline(trip: trip)
        #expect(timeline.zone(at: TestSupport.utcDate(2026, 10, 3, 12, 0)) == ZoneID("America/New_York"))
    }

    @Test("Plan days before departure carry the origin's zone label")
    func planDaysLabelOriginZone() throws {
        let profile = UserProfile(homeZone: ZoneID("Europe/Copenhagen"))
        let plan = try TestSupport.generateValidPlan(trip: awayTrip, profile: profile)
        let departure = awayTrip.firstDeparture!
        let preDays = plan.days.filter { $0.dayStart < departure.addingTimeInterval(-12 * 3600) }
        #expect(!preDays.isEmpty)
        for day in preDays {
            #expect(day.zone == ZoneID("Europe/Oslo"),
                    "pre-departure day labeled \(day.zone.identifier), expected Europe/Oslo")
        }
    }
}
