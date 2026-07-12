import Foundation
import Testing
@testable import ReclockKit

@Suite("Calendar flight detection")
struct FlightEventParserTests {
    let parser = FlightEventParser()

    private func event(
        _ title: String,
        location: String? = nil,
        notes: String? = nil,
        startOffsetHours: Double = 48,
        durationHours: Double = 8,
        zone: String? = "America/New_York"
    ) -> CalendarEventData {
        CalendarEventData(
            title: title,
            location: location,
            notes: notes,
            start: TestSupport.reference.adding(hours: startOffsetHours),
            end: TestSupport.reference.adding(hours: startOffsetHours + durationHours),
            timeZoneIdentifier: zone
        )
    }

    @Test("Flighty-style event")
    func flightyFormat() {
        let detected = parser.detectFlight(in: event("Flight to San Francisco (DL 423)"))
        #expect(detected != nil)
        #expect(detected?.flightNumber == "DL423")
        #expect(detected?.arrivalAirport == "SFO")
        #expect(detected?.arrivalZone?.identifier == "America/Los_Angeles")
    }

    @Test("TripIt-style event")
    func tripItFormat() {
        let detected = parser.detectFlight(
            in: event("BA 178 LHR to JFK", location: "London Heathrow (LHR)")
        )
        #expect(detected != nil)
        #expect(detected?.confidence == .high)
        #expect(detected?.departureAirport == "LHR")
        #expect(detected?.arrivalAirport == "JFK")
        #expect(detected?.departureZone?.identifier == "Europe/London")
        #expect(detected?.arrivalZone?.identifier == "America/New_York")
    }

    @Test("Airline confirmation with arrow route")
    func arrowRoute() {
        let detected = parser.detectFlight(
            in: event("✈ AY 16 · JFK → HEL", notes: "Confirmation: ABC123\nTerminal 8, Gate 14")
        )
        #expect(detected != nil)
        #expect(detected?.flightNumber == "AY16")
        #expect(detected?.departureAirport == "JFK")
        #expect(detected?.arrivalAirport == "HEL")
    }

    @Test("Plain-language flight without codes still detected via keywords")
    func plainLanguage() {
        let detected = parser.detectFlight(
            in: event("Flight to Tokyo", notes: "Boarding 10:45, Terminal B")
        )
        #expect(detected != nil)
        #expect(detected?.arrivalAirport == "NRT" || detected?.arrivalAirport == "HND")
    }

    @Test("Non-flight events are rejected")
    func nonFlights() {
        #expect(parser.detectFlight(in: event("Dinner with Sam")) == nil)
        #expect(parser.detectFlight(in: event("Dentist appointment", durationHours: 1)) == nil)
        #expect(parser.detectFlight(in: event("Pick up rental car", location: "Airport Ave 12", durationHours: 0.5)) == nil)
        // An all-week conference is too long to be a flight even with keywords.
        #expect(parser.detectFlight(in: event("Airline industry conference", durationHours: 100)) == nil)
        // "Gate" alone shouldn't trigger.
        #expect(parser.detectFlight(in: event("Beers at Gate 21 Brewery", durationHours: 2)) == nil)
    }

    @Test("Duplicate events from two apps collapse to one flight")
    func duplicates() {
        let flighty = event("Flight to Helsinki (AY 16)", startOffsetHours: 48)
        let airline = event("AY16 JFK → HEL", startOffsetHours: 48.2)
        let detected = parser.detectFlights(in: [flighty, airline])
        #expect(detected.count == 1)
        // The higher-confidence detection (explicit route) wins.
        #expect(detected.first?.departureAirport == "JFK")
    }

    @Test("Complete detections convert to segments; incomplete ones don't")
    func segmentConversion() {
        let complete = parser.detectFlight(in: event("AY16 JFK → HEL"))
        #expect(complete != nil)
        if let complete {
            let segment = parser.makeSegment(from: complete)
            #expect(segment != nil)
            #expect(segment?.departureZone.identifier == "America/New_York")
            #expect(segment?.arrivalZone.identifier == "Europe/Helsinki")
            #expect(segment?.importSource == .calendar)
        }

        let incomplete = parser.detectFlight(in: event("Flight to Tokyo", notes: "Boarding info at gate"))
        if let incomplete {
            // No departure airport detectable → cannot build a segment silently.
            #expect(parser.makeSegment(from: incomplete) == nil)
        }
    }

    @Test("Mock itinerary provider round-trips segments")
    func mockProvider() async throws {
        let canned = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference).segments
        let provider = MockItineraryParsingProvider(cannedSegments: canned)
        let parsed = try await provider.parseItinerary(emailContent: "irrelevant")
        #expect(parsed == canned)
    }

    @Test("AwardWallet provider reports not-configured without a proxy")
    func awardWalletUnconfigured() async {
        let provider = AwardWalletItineraryParsingProvider(proxyURL: nil)
        await #expect(throws: ItineraryParsingError.self) {
            _ = try await provider.parseItinerary(emailContent: "forwarded email")
        }
    }
}
