import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A flight found by number lookup, ready to become a segment after user confirmation.
public struct ScheduledFlight: Sendable, Hashable, Identifiable {
    public var id: String { "\(airline ?? "")\(flightNumber)/\(departure.timeIntervalSince1970)" }
    public var airline: String?
    public var flightNumber: String
    public var departureAirport: String
    public var arrivalAirport: String
    public var departure: Date
    public var arrival: Date
    public var departureZone: ZoneID
    public var arrivalZone: ZoneID

    public init(
        airline: String?,
        flightNumber: String,
        departureAirport: String,
        arrivalAirport: String,
        departure: Date,
        arrival: Date,
        departureZone: ZoneID,
        arrivalZone: ZoneID
    ) {
        self.airline = airline
        self.flightNumber = flightNumber
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departure = departure
        self.arrival = arrival
        self.departureZone = departureZone
        self.arrivalZone = arrivalZone
    }

    public func segment(importSource: ImportSource = .flightNumber) -> FlightSegment {
        FlightSegment(
            airline: airline,
            flightNumber: flightNumber,
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departure: departure,
            arrival: arrival,
            departureZone: departureZone,
            arrivalZone: arrivalZone,
            importSource: importSource,
            externalIdentifier: flightNumber
        )
    }
}

public enum FlightScheduleError: Error, Sendable, Equatable {
    /// No API key configured — the app works fully without one; UI falls back to manual.
    case notConfigured
    case networkUnavailable
    case notFound
    case unparseable
}

/// Looks up a flight's schedule by number and local departure date.
public protocol FlightScheduleProvider: Sendable {
    var isConfigured: Bool { get }
    func lookup(flightNumber: String, departureDate: Date, homeZone: TimeZone) async throws -> [ScheduledFlight]
}

/// Always-unconfigured provider: the default when no key is present.
public struct UnconfiguredFlightScheduleProvider: FlightScheduleProvider {
    public init() {}
    public var isConfigured: Bool { false }
    public func lookup(flightNumber: String, departureDate: Date, homeZone: TimeZone) async throws -> [ScheduledFlight] {
        throw FlightScheduleError.notConfigured
    }
}

/// Deterministic mock for previews, UI tests, and unit tests.
public struct MockFlightScheduleProvider: FlightScheduleProvider {
    public var results: [ScheduledFlight]
    public init(results: [ScheduledFlight] = []) {
        self.results = results
    }
    public var isConfigured: Bool { true }
    public func lookup(flightNumber: String, departureDate: Date, homeZone: TimeZone) async throws -> [ScheduledFlight] {
        if results.isEmpty { throw FlightScheduleError.notFound }
        return results
    }
}

/// AeroDataBox (via RapidAPI) schedule lookup.
///
/// Activation: set `ReclockAeroDataBoxKey` in the app's Info.plist (see SETUP.md). Without
/// a key this class is never constructed. The request contains ONLY the flight number and
/// date — no user identity, no device data (see PRIVACY.md).
///
/// The response mapping is deliberately defensive: AeroDataBox fields are decoded as
/// optionals and any flight missing essentials is skipped, so minor upstream schema drift
/// degrades to "not found" (with manual entry one tap away) rather than bad data.
public struct AeroDataBoxScheduleProvider: FlightScheduleProvider {
    let apiKey: String
    let airports: AirportDirectory
    /// Injectable transport for tests.
    let fetch: @Sendable (URLRequest) async throws -> (Data, Int)

    public init(
        apiKey: String,
        airports: AirportDirectory = .bundled,
        fetch: (@Sendable (URLRequest) async throws -> (Data, Int))? = nil
    ) {
        self.apiKey = apiKey
        self.airports = airports
        self.fetch = fetch ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        }
    }

    public var isConfigured: Bool { !apiKey.isEmpty }

    public func lookup(
        flightNumber: String,
        departureDate: Date,
        homeZone: TimeZone
    ) async throws -> [ScheduledFlight] {
        guard isConfigured else { throw FlightScheduleError.notConfigured }
        let cleaned = flightNumber.uppercased().replacingOccurrences(of: " ", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = homeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let dateText = formatter.string(from: departureDate)

        guard let url = URL(string:
            "https://aerodatabox.p.rapidapi.com/flights/number/\(cleaned)/\(dateText)?dateLocalRole=Departure"
        ) else { throw FlightScheduleError.unparseable }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue("aerodatabox.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")

        let (data, status): (Data, Int)
        do {
            (data, status) = try await fetch(request)
        } catch {
            throw FlightScheduleError.networkUnavailable
        }
        if status == 404 { throw FlightScheduleError.notFound }
        guard (200..<300).contains(status) else { throw FlightScheduleError.unparseable }
        return try Self.parse(data: data, fallbackNumber: cleaned, airports: airports)
    }

    // MARK: Response mapping (isolated for testability)

    struct RawFlight: Decodable {
        struct Endpoint: Decodable {
            struct RawAirport: Decodable {
                var iata: String?
                var timeZone: String?
            }
            struct RawTime: Decodable {
                var utc: String?
                var local: String?
            }
            var airport: RawAirport?
            var scheduledTime: RawTime?
        }
        struct Airline: Decodable { var iata: String?; var name: String? }
        var number: String?
        var airline: Airline?
        var departure: Endpoint?
        var arrival: Endpoint?
    }

    static func parse(
        data: Data,
        fallbackNumber: String,
        airports: AirportDirectory
    ) throws -> [ScheduledFlight] {
        let decoder = JSONDecoder()
        guard let raw = try? decoder.decode([RawFlight].self, from: data) else {
            throw FlightScheduleError.unparseable
        }
        let flights = raw.compactMap { flight -> ScheduledFlight? in
            guard
                let depCode = flight.departure?.airport?.iata?.uppercased(),
                let arrCode = flight.arrival?.airport?.iata?.uppercased(),
                let depTime = instant(from: flight.departure?.scheduledTime),
                let arrTime = instant(from: flight.arrival?.scheduledTime),
                arrTime > depTime
            else { return nil }
            // Zone precedence: our directory (trusted IANA ids) → provider's zone field.
            guard
                let depZone = airports.zone(forIATA: depCode)
                    ?? flight.departure?.airport?.timeZone.flatMap(validZone),
                let arrZone = airports.zone(forIATA: arrCode)
                    ?? flight.arrival?.airport?.timeZone.flatMap(validZone)
            else { return nil }
            return ScheduledFlight(
                airline: flight.airline?.iata ?? flight.airline?.name,
                flightNumber: flight.number?.replacingOccurrences(of: " ", with: "") ?? fallbackNumber,
                departureAirport: depCode,
                arrivalAirport: arrCode,
                departure: depTime,
                arrival: arrTime,
                departureZone: depZone,
                arrivalZone: arrZone
            )
        }
        guard !flights.isEmpty else { throw FlightScheduleError.notFound }
        return flights
    }

    private static func validZone(_ identifier: String) -> ZoneID? {
        TimeZone(identifier: identifier) != nil ? ZoneID(identifier) : nil
    }

    /// AeroDataBox UTC stamps look like "2026-09-19 22:30Z" or ISO8601.
    static func instant(from time: RawFlight.Endpoint.RawTime?) -> Date? {
        guard let utc = time?.utc else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: utc) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm'Z'", "yyyy-MM-dd HH:mmZ", "yyyy-MM-dd'T'HH:mm'Z'"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: utc) { return date }
        }
        return nil
    }
}
