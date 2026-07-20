import Foundation
import Testing
@testable import ReclockKit

/// Guards the expanded bundled airport directory (7,900+ airports) and the zone
/// healing that a richer directory makes possible. A Tromsø flight imported while
/// TOS was missing got labeled with the calendar's own zone ("Copenhagen time");
/// the directory must know these airports, and the healer must fix stored trips.
@Suite("Airport directory data & zone healing")
struct AirportDataTests {
    let airports = AirportDirectory.bundled

    @Test("The directory is comprehensive, unique, and fully zone-resolvable")
    func directoryIntegrity() {
        #expect(airports.airports.count > 5_000)
        #expect(Set(airports.airports.map(\.iata)).count == airports.airports.count)
        for airport in airports.airports {
            #expect(TimeZone(identifier: airport.zone.identifier) != nil,
                    "\(airport.iata) has unresolvable zone \(airport.zone.identifier)")
            #expect(airport.iata.count == 3)
        }
    }

    @Test("Smaller airports that burned real users are present with real zones")
    func regionalAirportsPresent() throws {
        let tos = try #require(airports.airport(iata: "TOS"))
        #expect(tos.zone == ZoneID("Europe/Oslo"))
        #expect(tos.latitude != nil && tos.longitude != nil)
        for code in ["BGO", "TRD", "SVG", "AES", "LYR"] {
            #expect(airports.airport(iata: code) != nil, "\(code) missing")
        }
    }

    @Test("Curated display names survive the data expansion")
    func curatedNamesWin() {
        #expect(airports.airport(iata: "NRT")?.city == "Tokyo")
        #expect(airports.airport(iata: "JFK")?.city == "New York")
        #expect(airports.airport(iata: "CPH")?.city == "Copenhagen")
    }

    @Test("Duplicate IATA codes degrade instead of trapping")
    func duplicateCodesSafe() {
        let a = Airport(iata: "XXX", name: "First", city: "One", country: "AA", zone: ZoneID("UTC"))
        let b = Airport(iata: "XXX", name: "Second", city: "Two", country: "BB", zone: ZoneID("UTC"))
        let directory = AirportDirectory(airports: [a, b])
        #expect(directory.airport(iata: "XXX")?.name == "First")
    }

    @Test("Healing re-stamps a mislabeled zone from the directory")
    func healsMislabeledZone() throws {
        // A TOS departure stamped with the calendar's zone (Copenhagen) — the classic.
        let segment = FlightSegment(
            departureAirport: "TOS",
            arrivalAirport: "OSL",
            departure: TestSupport.utcDate(2026, 10, 2, 10, 0),
            arrival: TestSupport.utcDate(2026, 10, 2, 12, 0),
            departureZone: ZoneID("Europe/Copenhagen"),
            arrivalZone: ZoneID("Europe/Oslo")
        )
        let trip = Trip(
            name: "Oslo", origin: "TOS", destination: "Oslo",
            homeZone: ZoneID("Europe/Oslo"),
            destinationZone: ZoneID("Europe/Copenhagen"),
            segments: [segment]
        )
        let healed = try #require(ZoneHealer.healed(trip, airports: airports))
        #expect(healed.segments[0].departureZone == ZoneID("Europe/Oslo"))
        #expect(healed.destinationZone == ZoneID("Europe/Oslo"))
        // Instants never move — only the label used to read them out.
        #expect(healed.segments[0].departure == segment.departure)
    }

    @Test("Healing leaves correct trips and unknown custom airports alone")
    func healingIsConservative() {
        let custom = FlightSegment(
            departureAirport: "ZZ9",
            arrivalAirport: "JFK",
            departure: TestSupport.utcDate(2026, 10, 2, 10, 0),
            arrival: TestSupport.utcDate(2026, 10, 2, 16, 0),
            departureZone: ZoneID("Pacific/Galapagos"),
            arrivalZone: ZoneID("America/New_York")
        )
        let trip = Trip(
            name: "New York", origin: "ZZ9", destination: "New York",
            homeZone: ZoneID("Pacific/Galapagos"),
            destinationZone: ZoneID("America/New_York"),
            segments: [custom]
        )
        #expect(ZoneHealer.healed(trip, airports: airports) == nil)
    }
}
