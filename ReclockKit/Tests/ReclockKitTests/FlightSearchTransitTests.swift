import Foundation
import Testing
@testable import ReclockKit

@Suite("Flight duration estimation")
struct DurationEstimatorTests {
    let airports = AirportDirectory.bundled

    private func airport(_ code: String) -> Airport {
        airports.airport(iata: code)!
    }

    @Test("Transatlantic estimates land near published block times")
    func transatlantic() {
        let east = FlightDurationEstimator.estimate(from: airport("JFK"), to: airport("LHR"))
        let west = FlightDurationEstimator.estimate(from: airport("LHR"), to: airport("JFK"))
        #expect(east != nil && west != nil)
        // Published blocks: ~6:50–7:20 east, ~7:50–8:30 west.
        #expect(east!.inHours > 6.2 && east!.inHours < 7.8, "east \(east!.inHours)h")
        #expect(west!.inHours > 7.2 && west!.inHours < 8.8, "west \(west!.inHours)h")
        #expect(west! > east!, "westbound must be slower than eastbound")
    }

    @Test("Long-haul and short-hop sanity")
    func ranges() {
        let longHaul = FlightDurationEstimator.estimate(from: airport("JFK"), to: airport("HNL"))
        #expect(longHaul != nil && longHaul!.inHours > 9.5 && longHaul!.inHours < 12.5)

        let hop = FlightDurationEstimator.estimate(from: airport("LGA"), to: airport("BOS"))
        #expect(hop != nil && hop!.inHours > 0.6 && hop!.inHours < 1.8)

        let pacific = FlightDurationEstimator.estimate(from: airport("LAX"), to: airport("HND"))
        #expect(pacific != nil && pacific!.inHours > 10.5 && pacific!.inHours < 13.5)
    }

    @Test("Custom airports without coordinates return nil (no fake precision)")
    func noCoordinates() {
        let custom = Airport(iata: "XXX", name: "Custom", city: "XXX", country: "", zone: ZoneID("UTC"))
        #expect(FlightDurationEstimator.estimate(from: custom, to: airport("JFK")) == nil)
    }

    @Test("Every bundled airport has coordinates")
    func coordinatesComplete() {
        for airport in airports.airports {
            #expect(airport.latitude != nil && airport.longitude != nil, "\(airport.iata) missing coords")
        }
    }
}

@Suite("Flight schedule lookup")
struct FlightScheduleProviderTests {

    static let sampleResponse = """
    [
      {
        "number": "AY 16",
        "airline": { "name": "Finnair", "iata": "AY" },
        "departure": {
          "airport": { "iata": "JFK", "timeZone": "America/New_York" },
          "scheduledTime": { "utc": "2026-09-19 22:30Z", "local": "2026-09-19 18:30-04:00" }
        },
        "arrival": {
          "airport": { "iata": "HEL", "timeZone": "Europe/Helsinki" },
          "scheduledTime": { "utc": "2026-09-20 06:50Z", "local": "2026-09-20 09:50+03:00" }
        }
      }
    ]
    """

    @Test("Parses a canned AeroDataBox response into a correct segment")
    func parsesResponse() throws {
        let flights = try AeroDataBoxScheduleProvider.parse(
            data: Data(Self.sampleResponse.utf8),
            fallbackNumber: "AY16",
            airports: .bundled
        )
        #expect(flights.count == 1)
        let flight = flights[0]
        #expect(flight.departureAirport == "JFK")
        #expect(flight.arrivalAirport == "HEL")
        #expect(flight.flightNumber == "AY16")
        #expect(flight.departureZone.identifier == "America/New_York")
        #expect(flight.arrivalZone.identifier == "Europe/Helsinki")
        #expect(abs(flight.arrival.timeIntervalSince(flight.departure) - .hours(8.33)) < .minutes(5))

        let segment = flight.segment()
        #expect(segment.importSource == .flightNumber)
        #expect(TestSupport.localHour(segment.departure, "America/New_York") == 18)
    }

    @Test("Malformed or empty responses degrade to clear errors, never bad data")
    func defensiveParsing() {
        #expect(throws: FlightScheduleError.self) {
            try AeroDataBoxScheduleProvider.parse(
                data: Data("not json".utf8), fallbackNumber: "XX1", airports: .bundled
            )
        }
        #expect(throws: FlightScheduleError.self) {
            try AeroDataBoxScheduleProvider.parse(
                data: Data("[]".utf8), fallbackNumber: "XX1", airports: .bundled
            )
        }
        // A flight with an arrival before departure is dropped.
        let backwards = Self.sampleResponse
            .replacingOccurrences(of: "2026-09-20 06:50Z", with: "2026-09-19 20:00Z")
        #expect(throws: FlightScheduleError.self) {
            try AeroDataBoxScheduleProvider.parse(
                data: Data(backwards.utf8), fallbackNumber: "AY16", airports: .bundled
            )
        }
    }

    @Test("Full lookup path via injected transport")
    func lookupWithTransport() async throws {
        let provider = AeroDataBoxScheduleProvider(
            apiKey: "test-key",
            fetch: { request in
                #expect(request.url?.absoluteString.contains("AY16") == true)
                #expect(request.value(forHTTPHeaderField: "x-rapidapi-key") == "test-key")
                return (Data(Self.sampleResponse.utf8), 200)
            }
        )
        let flights = try await provider.lookup(
            flightNumber: "ay 16",
            departureDate: TestSupport.utcDate(2026, 9, 19),
            homeZone: TimeZone(identifier: "America/New_York")!
        )
        #expect(flights.count == 1)
    }

    @Test("Unconfigured provider fails softly and reports itself")
    func unconfigured() async {
        let provider = UnconfiguredFlightScheduleProvider()
        #expect(!provider.isConfigured)
        await #expect(throws: FlightScheduleError.self) {
            _ = try await provider.lookup(
                flightNumber: "AY16",
                departureDate: TestSupport.reference,
                homeZone: TimeZone(identifier: "UTC")!
            )
        }
    }
}

@Suite("Airport transfer & leave-by")
struct TransitTests {

    @Test("Every stint departure gets a leave-by anchor, timed by the transfer setting")
    func leaveByExists() throws {
        var trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        trip.airportTransferMinutes = 45
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: DemoTrips.defaultProfile())

        let leaves = plan.actions.filter { $0.type == .leaveForAirport }
        #expect(leaves.count == 2, "outbound and return departures both need leave-by anchors")

        let outboundDep = trip.segments[0].departure
        let cfg = PlanEngineConfiguration()
        let expectedLeave = outboundDep
            .adding(hours: -cfg.airportArrivalLeadHours)
            .adding(minutes: -45)
        let outboundLeave = leaves.min { $0.window.start < $1.window.start }!
        #expect(abs(outboundLeave.window.end.timeIntervalSince(expectedLeave)) <= .minutes(5))
    }

    @Test("Longer transfers push the leave-by earlier")
    func transferScales() throws {
        var quick = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        quick.airportTransferMinutes = 20
        var far = quick
        far.airportTransferMinutes = 120
        let profile = DemoTrips.defaultProfile()

        let quickLeave = try TestSupport.generateValidPlan(trip: quick, profile: profile)
            .actions.first { $0.type == .leaveForAirport }!
        let farLeave = try TestSupport.generateValidPlan(trip: far, profile: profile)
            .actions.first { $0.type == .leaveForAirport }!
        let gap = quickLeave.window.end.timeIntervalSince(farLeave.window.end)
        #expect(abs(gap - .minutes(100)) <= .minutes(5))
    }

    @Test("No sleep scheduled during the transfer + airport window")
    func noSleepDuringTransfer() throws {
        var trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        trip.airportTransferMinutes = 90
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.generateValidPlan(trip: trip, profile: profile)
        let cfg = PlanEngineConfiguration()

        for stintFirst in [trip.outboundSegments.first, trip.returnSegments.first].compactMap({ $0 }) {
            let blocked = TimeWindow(
                start: stintFirst.departure
                    .adding(hours: -cfg.airportArrivalLeadHours)
                    .adding(minutes: -90 - cfg.transferPrepBufferMinutes),
                end: stintFirst.departure
            )
            for action in plan.actions where action.type == .sleep || action.type == .nap {
                #expect(!action.window.overlaps(blocked), "sleep overlaps the airport run")
            }
        }
    }

    @Test("Leave-by notifications fire even inside quiet hours")
    func leaveByBeatsQuietHours() throws {
        // 09:15 departure ⇒ leave ≈ 06:15, inside default 22:00–07:00 quiet hours.
        let trip = DemoTrips.newYorkToHonolulu(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        let planner = NotificationPlanner()
        let notifications = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: TestSupport.reference
        )
        let leaveAction = plan.actions.first { $0.type == .leaveForAirport }
        #expect(leaveAction != nil)
        if let leaveAction {
            let note = notifications.first { $0.actionID == leaveAction.id }
            #expect(note != nil, "leave-by must not be silenced by quiet hours")
            if let note {
                #expect(abs(note.fireDate.timeIntervalSince(leaveAction.window.start)) < .minutes(6))
            }
        }
    }
}

@Suite("Trip assembly")
struct TripAssemblerTests {

    @Test("Destination inferred as the stay airport, not the final leg")
    func destinationInference() {
        let segments = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference).segments
        #expect(TripAssembler.stayAirport(of: segments) == "HEL")

        let trip = TripAssembler.makeTrip(
            segments: segments,
            homeZone: ZoneID("America/New_York"),
            airports: .bundled,
            importSource: .flightNumber
        )
        #expect(trip?.destination == "Helsinki")
        #expect(trip?.destinationZone.identifier == "Europe/Helsinki")
    }

    @Test("Multi-leg outbound keeps the final stop as destination")
    func multiLeg() {
        let segments = DemoTrips.newYorkToSingaporeViaFrankfurt(reference: TestSupport.reference).segments
        #expect(TripAssembler.stayAirport(of: segments) == "SIN")
    }
}
