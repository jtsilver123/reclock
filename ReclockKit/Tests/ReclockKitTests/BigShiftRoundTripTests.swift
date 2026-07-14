import Foundation
import Testing
@testable import ReclockKit

/// Round trips with a large eastward return shift (Tokyo/Singapore → US East Coast)
/// once produced duplicate nights: the "too late" bedtime clamp overshot by a full
/// day whenever a nominal bed fell between ~06:00 and noon, two nights collapsed
/// onto the same instant, the validator rejected the plan, and addTrip refused the
/// itinerary outright. These trips are the app's bread and butter — lock them green.
@Suite("Big eastward round trips build valid plans")
struct BigShiftRoundTripTests {
    private static let reference: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 12))!
    }()

    private func segment(
        _ number: String, from dep: String, _ depZone: String,
        to arr: String, _ arrZone: String,
        depDay: Int, depH: Int, depM: Int, arrDay: Int, arrH: Int, arrM: Int
    ) -> FlightSegment {
        FlightSegment(
            airline: String(number.prefix(2)), flightNumber: number,
            departureAirport: dep, arrivalAirport: arr,
            departure: DemoTrips.at(Self.reference, dayOffset: depDay, depH, depM, depZone),
            arrival: DemoTrips.at(Self.reference, dayOffset: arrDay, arrH, arrM, arrZone),
            departureZone: ZoneID(depZone),
            arrivalZone: ZoneID(arrZone),
            importSource: .manual
        )
    }

    private func roundTrip(name: String, out: FlightSegment, back: FlightSegment, destZone: String) -> Trip {
        Trip(
            name: name,
            origin: out.departureAirport, destination: name,
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID(destZone),
            segments: [out, back],
            importSource: .manual,
            createdAt: Self.reference
        )
    }

    private func assertBuildsValid(_ trip: Trip) throws {
        let profile = DemoTrips.defaultProfile()
        let engine = PlanEngine(configuration: PlanEngineConfiguration())
        let plan = try engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        let validation = PlanValidator().validate(plan: plan, trip: trip, profile: profile)
        #expect(validation.isValid, "\(trip.name): \(validation.conflicts.map(\.description))")
        // The specific historical failure: two nights clamped onto one instant.
        let sleepStarts = plan.actions.filter { $0.type == .sleep }.map(\.window.start).sorted()
        for (a, b) in zip(sleepStarts, sleepStarts.dropFirst()) {
            #expect(b.timeIntervalSince(a) > 6 * 3600,
                    "\(trip.name): consecutive sleeps \(a) → \(b) are impossibly close")
        }
    }

    @Test("New York ↔ Tokyo, 12-night stay")
    func tokyoRoundTrip() throws {
        let out = segment("NH9", from: "JFK", "America/New_York", to: "HND", "Asia/Tokyo",
                          depDay: 4, depH: 18, depM: 0, arrDay: 5, arrH: 21, arrM: 5)
        let back = segment("NH10", from: "HND", "Asia/Tokyo", to: "JFK", "America/New_York",
                           depDay: 17, depH: 17, depM: 0, arrDay: 17, arrH: 17, arrM: 10)
        try assertBuildsValid(roundTrip(name: "Tokyo", out: out, back: back, destZone: "Asia/Tokyo"))
    }

    @Test("New York ↔ Singapore, 12-night stay")
    func singaporeRoundTrip() throws {
        let out = segment("SQ23", from: "JFK", "America/New_York", to: "SIN", "Asia/Singapore",
                          depDay: 4, depH: 22, depM: 30, arrDay: 6, arrH: 5, arrM: 30)
        let back = segment("SQ24", from: "SIN", "Asia/Singapore", to: "JFK", "America/New_York",
                           depDay: 18, depH: 23, depM: 55, arrDay: 19, arrH: 6, arrM: 0)
        try assertBuildsValid(roundTrip(name: "Singapore", out: out, back: back, destZone: "Asia/Singapore"))
    }

    @Test("Sweep: eastward returns at several stay lengths stay valid")
    func stayLengthSweep() throws {
        for stayDays in [7, 10, 14, 21] {
            let out = segment("NH9", from: "JFK", "America/New_York", to: "HND", "Asia/Tokyo",
                              depDay: 4, depH: 18, depM: 0, arrDay: 5, arrH: 21, arrM: 5)
            let back = segment("NH10", from: "HND", "Asia/Tokyo", to: "JFK", "America/New_York",
                               depDay: 5 + stayDays, depH: 17, depM: 0,
                               arrDay: 5 + stayDays, arrH: 17, arrM: 10)
            try assertBuildsValid(roundTrip(name: "Tokyo \(stayDays)n", out: out, back: back, destZone: "Asia/Tokyo"))
        }
    }
}
