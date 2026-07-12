import Foundation
import Testing
@testable import ReclockKit

@Suite("Direction & shift selection")
struct EngineDirectionTests {

    @Test("Zone delta normalization")
    func normalization() {
        #expect(CircadianMath.normalizedZoneDelta(hours: 7) == 7)
        #expect(CircadianMath.normalizedZoneDelta(hours: -5) == -5)
        #expect(CircadianMath.normalizedZoneDelta(hours: 16) == -8)
        #expect(CircadianMath.normalizedZoneDelta(hours: -17) == 7)
        #expect(CircadianMath.normalizedZoneDelta(hours: 12) == 12)
        #expect(CircadianMath.normalizedZoneDelta(hours: -12) == 12)
        #expect(CircadianMath.normalizedZoneDelta(hours: 0) == 0)
    }

    @Test("Eastward Atlantic crossing advances")
    func eastward() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        #expect(plan.shiftDirection == .advance)
        #expect(abs(plan.requiredShiftHours - 7) < 0.6)
        #expect(plan.strategy == .fullyAdapt)
    }

    @Test("Westward Atlantic crossing delays")
    func westward() throws {
        let trip = DemoTrips.londonToNewYork(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(
            trip: trip,
            profile: DemoTrips.defaultProfile(homeZone: "Europe/London")
        )
        #expect(plan.shiftDirection == .delay)
        #expect(abs(plan.requiredShiftHours + 5) < 0.6)
    }

    @Test("Trans-Pacific LAX→Tokyo is a delay, not a 16-hour advance")
    func dateLineWestward() throws {
        let trip = DemoTrips.losAngelesToTokyo(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(
            trip: trip,
            profile: DemoTrips.defaultProfile(homeZone: "America/Los_Angeles")
        )
        #expect(plan.shiftDirection == .delay)
        #expect(abs(plan.requiredShiftHours + 8) < 0.6)
    }

    @Test("Sydney→San Francisco crosses the date line and advances ~7h")
    func dateLineEastward() throws {
        let trip = DemoTrips.sydneyToSanFrancisco(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(
            trip: trip,
            profile: DemoTrips.defaultProfile(homeZone: "Australia/Sydney")
        )
        #expect(plan.shiftDirection == .advance)
        #expect(abs(plan.requiredShiftHours - 7) < 0.6)
        // The itinerary lands before it departs on the local calendar; block time stays positive.
        let segment = trip.segments[0]
        #expect(segment.blockTime > 0)
    }

    @Test("+12h Singapore goes the long way around (antidromic delay)")
    func antidromic() throws {
        let trip = DemoTrips.newYorkToSingaporeViaFrankfurt(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        // Advancing 12h at 1h/day = 12 days; delaying 12h at 1.5h/day = 8 days → delay wins.
        #expect(plan.shiftDirection == .delay)
        #expect(abs(plan.requiredShiftHours + 12) < 0.8)
    }

    @Test("One-hour difference produces a small, sane plan")
    func oneHour() throws {
        let segment = FlightSegment(
            departureAirport: "JFK", arrivalAirport: "ORD",
            departure: TestSupport.zoned(2026, 9, 20, 9, 0, "America/New_York"),
            arrival: TestSupport.zoned(2026, 9, 20, 10, 45, "America/Chicago"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("America/Chicago")
        )
        let trip = Trip(
            name: "Chicago", origin: "JFK", destination: "Chicago",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("America/Chicago"),
            segments: [segment],
            createdAt: TestSupport.reference
        )
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        #expect(abs(plan.requiredShiftHours) <= 1.2)
    }

    @Test("Same-zone trip needs no shift")
    func sameZone() throws {
        let segment = FlightSegment(
            departureAirport: "JFK", arrivalAirport: "MIA",
            departure: TestSupport.zoned(2026, 9, 20, 9, 0, "America/New_York"),
            arrival: TestSupport.zoned(2026, 9, 20, 12, 10, "America/New_York"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("America/New_York")
        )
        let trip = Trip(
            name: "Miami", origin: "JFK", destination: "Miami",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("America/New_York"),
            segments: [segment],
            createdAt: TestSupport.reference
        )
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        #expect(plan.shiftDirection == ShiftDirection.none)
        #expect(plan.requiredShiftHours == 0)
    }

    @Test("Deterministic: same inputs, identical plan")
    func deterministic() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let a = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        let b = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        #expect(a == b)
    }

    @Test("Pre-trip advance shifts bedtime earlier before departure")
    func preTripShift() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())
        let departure = trip.firstDeparture!
        let preTripDays = plan.days.filter { $0.estimatedBed < departure }
        // Balanced intensity + moderate willingness → 2 pre-trip shift days.
        #expect(preTripDays.count >= 2)
        let shifts = preTripDays.map(\.cumulativeShiftHours)
        // Monotonically non-decreasing advance before departure.
        #expect(shifts == shifts.sorted())
        #expect((shifts.last ?? 0) > 0.5)
    }
}
