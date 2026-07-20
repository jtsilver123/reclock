import Foundation
import Testing
@testable import ReclockKit

/// Two flights added one at a time that chain airport-to-airport within a layover
/// are ONE journey — the merger must fold them, and must refuse everything that
/// isn't a connection (stays, returns, duplicates, different airports).
@Suite("Trip merging: connections entered flight-by-flight")
struct TripMergerTests {
    let airports = AirportDirectory.bundled

    private func segment(
        _ dep: String, _ arr: String,
        departure: Date, blockHours: Double,
        depZone: String, arrZone: String,
        flight: String? = nil
    ) -> FlightSegment {
        FlightSegment(
            flightNumber: flight,
            departureAirport: dep,
            arrivalAirport: arr,
            departure: departure,
            arrival: departure.addingTimeInterval(blockHours * 3600),
            departureZone: ZoneID(depZone),
            arrivalZone: ZoneID(arrZone)
        )
    }

    private func trip(_ segments: [FlightSegment], name: String = "Test") -> Trip {
        Trip(
            name: name,
            origin: segments.first?.departureAirport ?? "",
            destination: segments.last?.arrivalAirport ?? "",
            homeZone: ZoneID("America/New_York"),
            destinationZone: segments.last?.arrivalZone ?? ZoneID("America/New_York"),
            segments: segments
        )
    }

    /// JFK→FRA landing, FRA→SIN two hours later: the classic layover.
    private var jfkFra: FlightSegment {
        segment("JFK", "FRA", departure: TestSupport.utcDate(2026, 10, 1, 22, 0), blockHours: 7.5,
                depZone: "America/New_York", arrZone: "Europe/Berlin", flight: "LH 401")
    }

    private func fraSin(gapHours: Double) -> FlightSegment {
        segment("FRA", "SIN", departure: jfkFra.arrival.addingTimeInterval(gapHours * 3600),
                blockHours: 12, depZone: "Europe/Berlin", arrZone: "Asia/Singapore", flight: "SQ 25")
    }

    @Test("A layover-length handoff merges into one ordered journey")
    func connectionMerges() {
        let a = trip([jfkFra])
        let b = trip([fraSin(gapHours: 2)])
        let merged = TripMerger.mergedSegments(a, b)
        #expect(merged?.count == 2)
        #expect(merged?.first?.departureAirport == "JFK")
        #expect(merged?.last?.arrivalAirport == "SIN")
    }

    @Test("Merge is order-independent: the later leg can be added first")
    func orderIndependent() {
        let late = trip([fraSin(gapHours: 3)])
        let early = trip([jfkFra])
        #expect(TripMerger.mergedSegments(late, early) != nil)
        #expect(TripMerger.mergedSegments(early, late) != nil)
    }

    @Test("An overnight layover still merges; beyond the window it does not")
    func layoverWindow() {
        #expect(TripMerger.mergedSegments(trip([jfkFra]), trip([fraSin(gapHours: 10)])) != nil)
        #expect(TripMerger.mergedSegments(trip([jfkFra]), trip([fraSin(gapHours: 17)])) == nil)
        // Three days in Frankfurt is a stay — its own trip, never an auto-merge.
        #expect(TripMerger.mergedSegments(trip([jfkFra]), trip([fraSin(gapHours: 72)])) == nil)
    }

    @Test("Different airports never chain, even minutes apart")
    func differentAirportNoMerge() {
        let muc = segment("MUC", "SIN", departure: jfkFra.arrival.addingTimeInterval(2 * 3600),
                          blockHours: 12, depZone: "Europe/Berlin", arrZone: "Asia/Singapore")
        #expect(TripMerger.mergedSegments(trip([jfkFra]), trip([muc])) == nil)
    }

    @Test("Overlapping or duplicate flights never merge")
    func overlapNoMerge() {
        #expect(TripMerger.mergedSegments(trip([jfkFra]), trip([jfkFra])) == nil)
        let overlapping = segment("FRA", "SIN", departure: jfkFra.arrival.addingTimeInterval(-1800),
                                  blockHours: 12, depZone: "Europe/Berlin", arrZone: "Asia/Singapore")
        #expect(TripMerger.mergedSegments(trip([jfkFra]), trip([overlapping])) == nil)
    }

    @Test("A return a week later is out of scope for auto-merge")
    func returnLegNoMerge() {
        let lhrOut = segment("JFK", "LHR", departure: TestSupport.utcDate(2026, 10, 1, 23, 0), blockHours: 7,
                             depZone: "America/New_York", arrZone: "Europe/London")
        let lhrBack = segment("LHR", "JFK", departure: TestSupport.utcDate(2026, 10, 8, 11, 0), blockHours: 8,
                              depZone: "Europe/London", arrZone: "America/New_York")
        #expect(TripMerger.mergedSegments(trip([lhrOut]), trip([lhrBack])) == nil)
    }

    @Test("A new leg chains onto the end of an existing multi-leg trip")
    func chainsOntoMultiLeg() {
        let host = trip([jfkFra, fraSin(gapHours: 2)])
        let onward = segment("SIN", "NRT", departure: fraSin(gapHours: 2).arrival.addingTimeInterval(4 * 3600),
                             blockHours: 7, depZone: "Asia/Singapore", arrZone: "Asia/Tokyo")
        let merged = TripMerger.mergedSegments(host, trip([onward]))
        #expect(merged?.count == 3)
        #expect(merged?.last?.arrivalAirport == "NRT")
    }

    @Test("A round trip's internal stay survives merging a connection onto its outbound")
    func staySurvivesMerge() {
        // Host: JFK→FRA out, FRA→JFK back ten days later. New leg: FRA→SIN?? No —
        // the realistic case is the outbound's connection: host outbound lands FRA,
        // return departs FRA in 10 days; adding FRA→SIN 2h after landing would
        // interleave and hit the return seam. The merger must refuse rather than
        // scramble a round trip.
        let back = segment("FRA", "JFK", departure: jfkFra.arrival.addingTimeInterval(10 * 86_400),
                           blockHours: 9, depZone: "Europe/Berlin", arrZone: "America/New_York")
        let roundTrip = trip([jfkFra, back])
        #expect(TripMerger.mergedSegments(roundTrip, trip([fraSin(gapHours: 2)])) == nil)
    }

    @Test("merging() keeps the host's identity and re-derives the route")
    func mergedTripFields() throws {
        var host = trip([jfkFra], name: "Frankfurt")
        host.intensity = .maximum
        host.preTripDaysOverride = 3
        host.commitments = [FixedCommitment(
            title: "Board meeting",
            start: TestSupport.utcDate(2026, 10, 5, 9, 0),
            end: TestSupport.utcDate(2026, 10, 5, 11, 0),
            zone: ZoneID("Asia/Singapore")
        )]
        let added = trip([fraSin(gapHours: 2)])

        let merged = try #require(TripAssembler.merging(host, absorbing: added, airports: airports))
        #expect(merged.id == host.id)
        #expect(merged.intensity == .maximum)
        #expect(merged.preTripDaysOverride == 3)
        #expect(merged.commitments.count == 1)
        #expect(merged.origin == "JFK")
        #expect(merged.destination == "Singapore")
        #expect(merged.name == "Singapore")
        #expect(merged.destinationZone == ZoneID("Asia/Singapore"))
        #expect(merged.segments.count == 2)
    }

    @Test("A merged one-stop itinerary still yields a valid plan")
    func mergedTripPlans() throws {
        let host = trip([jfkFra], name: "Frankfurt")
        let merged = try #require(TripAssembler.merging(host, absorbing: trip([fraSin(gapHours: 2)]), airports: airports))
        let profile = UserProfile(homeZone: ZoneID("America/New_York"))
        _ = try TestSupport.generateValidPlan(trip: merged, profile: profile)
    }
}
