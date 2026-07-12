import Foundation
import Testing
@testable import ReclockKit

@Suite("Time-zone edges: DST, date line, fixed dates")
struct TimeZoneEdgeTests {

    @Test("Zone deltas use real offsets at the instant, not fixed assumptions")
    func zoneDeltaAtInstant() {
        let ny = TimeZone(identifier: "America/New_York")!
        let london = TimeZone(identifier: "Europe/London")!
        // 2026-10-26: UK left DST on Oct 25; US leaves Nov 1 → gap week, only 4h apart.
        let gapWeek = TestSupport.utcDate(2026, 10, 26, 12, 0)
        #expect(CircadianMath.zoneDelta(home: london, destination: ny, at: gapWeek) == -4)
        // Mid-September: normal 5h difference.
        let normal = TestSupport.utcDate(2026, 9, 15, 12, 0)
        #expect(CircadianMath.zoneDelta(home: london, destination: ny, at: normal) == -5)
    }

    @Test("Nonexistent local times during spring-forward resolve to valid instants")
    func springForwardGap() {
        // US spring forward 2027-03-14: 02:00–03:00 does not exist in New York.
        let zone = TimeZone(identifier: "America/New_York")!
        let day = TestSupport.zoned(2027, 3, 14, 12, 0, "America/New_York")
        let resolved = LocalClockTime(hour: 2, minute: 30).date(on: day, in: zone)
        #expect(resolved != nil)
        if let resolved {
            let hour = TestSupport.localHour(resolved, "America/New_York")
            #expect(hour != 2, "02:30 does not exist on this day; resolution must not claim it does")
        }
    }

    @Test("Plan spanning the EU fall-back transition stays valid")
    func fallBackPlan() throws {
        // Flight lands in Paris two days before the EU transition (2026-10-25); the
        // adaptation window spans it.
        let segment = FlightSegment(
            departureAirport: "JFK", arrivalAirport: "CDG",
            departure: TestSupport.zoned(2026, 10, 22, 19, 30, "America/New_York"),
            arrival: TestSupport.zoned(2026, 10, 23, 8, 45, "Europe/Paris"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/Paris")
        )
        let trip = Trip(
            name: "Paris DST", origin: "JFK", destination: "Paris",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/Paris"),
            segments: [segment],
            createdAt: TestSupport.utcDate(2026, 10, 20)
        )
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        // Sleep windows after the transition should still land at a sane local hour.
        let lateNights = plan.actions.filter {
            $0.type == .sleep
                && $0.window.start > TestSupport.utcDate(2026, 10, 25, 12, 0)
                && $0.ruleReference == "v1/sleep-night"
        }
        for night in lateNights {
            let hour = TestSupport.localHour(night.window.start, "Europe/Paris")
            #expect(hour >= 20 || hour <= 2, "bedtime at \(hour):00 local after DST change")
        }
    }

    @Test("Date-line crossing keeps chronology: arrival instant after departure instant")
    func dateLineChronology() {
        let trip = DemoTrips.sydneyToSanFrancisco(reference: TestSupport.reference)
        let segment = trip.segments[0]
        #expect(segment.arrival > segment.departure)
        // But the local calendar date at arrival is the same day, earlier clock time.
        let depDay = Calendar.gregorian(in: TimeZone(identifier: "Australia/Sydney")!)
            .component(.day, from: segment.departure)
        let arrDay = Calendar.gregorian(in: TimeZone(identifier: "America/Los_Angeles")!)
            .component(.day, from: segment.arrival)
        #expect(depDay == arrDay)
    }

    @Test("ZoneTimeline tracks the traveler across segments")
    func zoneTimeline() {
        let trip = DemoTrips.newYorkToSingaporeViaFrankfurt(reference: TestSupport.reference)
        let timeline = ZoneTimeline(trip: trip)
        let beforeTrip = trip.segments[0].departure.adding(hours: -10)
        #expect(timeline.zone(at: beforeTrip).identifier == "America/New_York")
        let duringLayover = trip.segments[0].arrival.adding(hours: 1)
        #expect(timeline.zone(at: duringLayover).identifier == "Europe/Berlin")
        let afterArrival = trip.segments[1].arrival.adding(hours: 5)
        #expect(timeline.zone(at: afterArrival).identifier == "Asia/Singapore")
    }

    @Test("Unresolvable zone throws a clear error")
    func badZone() {
        let segment = FlightSegment(
            departureAirport: "JFK", arrivalAirport: "XXX",
            departure: TestSupport.reference.adding(hours: 24),
            arrival: TestSupport.reference.adding(hours: 30),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Not/AZone")
        )
        let trip = Trip(
            name: "Bad", origin: "JFK", destination: "Nowhere",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Not/AZone"),
            segments: [segment],
            createdAt: TestSupport.reference
        )
        #expect(throws: PlanEngineError.self) {
            try TestSupport.engine.generatePlan(trip: trip, profile: DemoTrips.defaultProfile(), currentState: nil)
        }
    }

    @Test("Impossible itineraries are rejected")
    func impossibleItinerary() {
        // Arrival before departure (a real data-entry mistake: wrong date).
        let segment = FlightSegment(
            departureAirport: "JFK", arrivalAirport: "LHR",
            departure: TestSupport.reference.adding(hours: 24),
            arrival: TestSupport.reference.adding(hours: 20),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/London")
        )
        let trip = Trip(
            name: "Backwards", origin: "JFK", destination: "London",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/London"),
            segments: [segment],
            createdAt: TestSupport.reference
        )
        #expect(throws: PlanEngineError.self) {
            try TestSupport.engine.generatePlan(trip: trip, profile: DemoTrips.defaultProfile(), currentState: nil)
        }
    }

    @Test("TripValidator catches user-entry mistakes with friendly messages")
    func tripValidator() {
        let validator = TripValidator()
        let backwards = FlightSegment(
            departureAirport: "JFK", arrivalAirport: "LHR",
            departure: TestSupport.reference.adding(hours: 24),
            arrival: TestSupport.reference.adding(hours: 20),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/London")
        )
        let issues = validator.validate(segments: [backwards])
        #expect(issues.contains { if case .arrivalBeforeDeparture = $0 { return true }; return false })
        #expect(validator.hasBlockingIssues(segments: [backwards]))

        // Unknown airport is advisory, not blocking (manual zone selection covers it).
        let unknownAirport = FlightSegment(
            departureAirport: "ZZZ", arrivalAirport: "LHR",
            departure: TestSupport.reference.adding(hours: 24),
            arrival: TestSupport.reference.adding(hours: 31),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/London")
        )
        let advisory = validator.validate(segments: [unknownAirport])
        #expect(advisory.contains { if case .unknownAirport = $0 { return true }; return false })
        #expect(!validator.hasBlockingIssues(segments: [unknownAirport]))
    }

    @Test("Airport directory resolves codes and searches cities")
    func airportDirectory() {
        let directory = AirportDirectory.bundled
        #expect(directory.airports.count > 100)
        #expect(directory.zone(forIATA: "hel")?.identifier == "Europe/Helsinki")
        #expect(directory.zone(forIATA: "HNL")?.identifier == "Pacific/Honolulu")
        #expect(directory.zone(forIATA: "ZZZ") == nil)
        let hits = directory.search("Toky")
        #expect(hits.contains { $0.iata == "NRT" || $0.iata == "HND" })
        // Every bundled zone must resolve on this platform.
        for airport in directory.airports {
            #expect(airport.zone.timeZone != nil, "\(airport.iata) has invalid zone \(airport.zone.identifier)")
        }
    }
}
