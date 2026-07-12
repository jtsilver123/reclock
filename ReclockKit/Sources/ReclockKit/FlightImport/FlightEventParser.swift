import Foundation

/// A neutral snapshot of a calendar event. The EventKit adapter in the app maps `EKEvent`s
/// into this struct so all parsing logic stays platform-independent and testable.
/// Only fields needed for flight detection are captured; nothing else leaves EventKit.
public struct CalendarEventData: Sendable, Hashable {
    public var title: String
    public var location: String?
    public var notes: String?
    public var start: Date
    public var end: Date
    public var timeZoneIdentifier: String?

    public init(
        title: String,
        location: String? = nil,
        notes: String? = nil,
        start: Date,
        end: Date,
        timeZoneIdentifier: String? = nil
    ) {
        self.title = title
        self.location = location
        self.notes = notes
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// A flight detected in a calendar event, before the user confirms the import.
public struct DetectedFlight: Sendable, Hashable, Identifiable {
    public var id: String { "\(sourceTitle)|\(departure.timeIntervalSince1970)" }
    public var airlineCode: String?
    public var flightNumber: String?
    public var departureAirport: String?
    public var arrivalAirport: String?
    public var departure: Date
    public var arrival: Date
    public var departureZone: ZoneID?
    public var arrivalZone: ZoneID?
    public var confidence: DetectionConfidence
    /// Original event title, shown to the user so they can verify what was detected.
    public var sourceTitle: String

    public init(
        airlineCode: String? = nil,
        flightNumber: String? = nil,
        departureAirport: String? = nil,
        arrivalAirport: String? = nil,
        departure: Date,
        arrival: Date,
        departureZone: ZoneID? = nil,
        arrivalZone: ZoneID? = nil,
        confidence: DetectionConfidence,
        sourceTitle: String
    ) {
        self.airlineCode = airlineCode
        self.flightNumber = flightNumber
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departure = departure
        self.arrival = arrival
        self.departureZone = departureZone
        self.arrivalZone = arrivalZone
        self.confidence = confidence
        self.sourceTitle = sourceTitle
    }

    public var isComplete: Bool {
        departureAirport != nil && arrivalAirport != nil
            && departureZone != nil && arrivalZone != nil
    }
}

public enum DetectionConfidence: String, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// Detects flights in calendar events. Recognizes Flighty and TripIt formats, generic
/// airline confirmations, and hand-typed events like "Flight to Tokyo".
///
/// Privacy: this parser runs on-device only, and the import UI shows exactly which events
/// were detected before anything is stored. Unmatched event content is discarded.
public struct FlightEventParser: Sendable {
    private let airports: AirportDirectory

    public init(airports: AirportDirectory = .bundled) {
        self.airports = airports
    }

    private static let flightKeywords = [
        "flight", "departure", "boarding", "terminal", "gate", "airport",
        "airline", "airways", "confirmation", "record locator", "✈",
    ]

    /// e.g. "DL 423", "BA178", "LH-456", "AF 007" — 2-char airline code + 1–4 digits.
    private static let flightNumberPattern = #"\b([A-Z]{2}|[A-Z]\d|\d[A-Z])\s?-?\s?(\d{1,4})\b"#
    /// e.g. "JFK → HEL", "JFK-HEL", "JFK to HEL", "(SFO – NRT)"
    private static let routePattern = #"\b([A-Z]{3})\s*(?:→|➔|->|–|—|-|to|/)\s*([A-Z]{3})\b"#
    /// Booking references: 6-char alphanumeric with at least one digit, in a confirmation context.
    private static let bookingRefPattern = #"(?:confirmation|record locator|booking(?:\sref(?:erence)?)?|PNR)[:\s#]*([A-Z0-9]{6})\b"#

    public func detectFlights(in events: [CalendarEventData]) -> [DetectedFlight] {
        var detected: [DetectedFlight] = []
        for event in events {
            if let flight = detectFlight(in: event) {
                detected.append(flight)
            }
        }
        return Self.deduplicate(detected)
    }

    public func detectFlight(in event: CalendarEventData) -> DetectedFlight? {
        let title = event.title
        let haystackParts = [title, event.location ?? "", event.notes ?? ""]
        let haystack = haystackParts.joined(separator: "\n")
        let lowered = haystack.lowercased()

        let keywordHits = Self.flightKeywords.filter { lowered.contains($0) }.count
        let route = firstRoute(in: haystack)
        let flightNumber = firstFlightNumber(in: haystack)
        let hasBookingRef = matches(Self.bookingRefPattern, in: haystack, caseInsensitive: true) != nil
        let cityHit = cityDestination(in: title)

        // Reject obvious non-flights ("Dinner at Gate 21 Brewery" needs more than one weak signal).
        var score = 0
        if route != nil { score += 2 }
        if flightNumber != nil { score += 2 }
        if cityHit != nil { score += 1 }
        score += min(keywordHits, 2)
        if hasBookingRef { score += 1 }
        // Duration sanity: flights are 30 min – 20 h.
        let duration = event.end.timeIntervalSince(event.start)
        let plausibleDuration = duration >= .minutes(30) && duration <= .hours(20)
        guard plausibleDuration, score >= 3 else { return nil }

        var departureAirport = route?.0
        var arrivalAirport = route?.1

        // Flighty style: "Flight to San Francisco (DL 423)" — resolve city names to airports
        // when explicit codes are missing.
        if arrivalAirport == nil {
            arrivalAirport = cityHit
        }
        // TripIt style locations: "SFO San Francisco Int'l" in the location field.
        if departureAirport == nil, let location = event.location {
            departureAirport = firstKnownAirportCode(in: location)
        }

        let departureZone = departureAirport.flatMap { airports.zone(forIATA: $0) }
            ?? event.timeZoneIdentifier.map { ZoneID($0) }
        let arrivalZone = arrivalAirport.flatMap { airports.zone(forIATA: $0) }

        let confidence: DetectionConfidence
        if route != nil && flightNumber != nil {
            confidence = .high
        } else if route != nil || (flightNumber != nil && keywordHits >= 1) || (cityHit != nil && keywordHits >= 2) {
            confidence = .medium
        } else {
            confidence = .low
        }
        guard confidence > .low else { return nil }

        return DetectedFlight(
            airlineCode: flightNumber?.0,
            flightNumber: flightNumber.map { "\($0.0)\($0.1)" },
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departure: event.start,
            arrival: event.end,
            departureZone: departureZone,
            arrivalZone: arrivalZone,
            confidence: confidence,
            sourceTitle: event.title
        )
    }

    // MARK: - Pattern helpers

    private func firstRoute(in text: String) -> (String, String)? {
        // Scan all route-shaped matches and prefer ones whose codes are real airports.
        let all = allMatches(Self.routePattern, in: text)
        var fallback: (String, String)?
        for match in all {
            guard match.count >= 3 else { continue }
            let a = match[1], b = match[2]
            let aKnown = airports.isKnownIATA(a)
            let bKnown = airports.isKnownIATA(b)
            if aKnown && bKnown { return (a, b) }
            if (aKnown || bKnown) && fallback == nil { fallback = (a, b) }
        }
        return fallback
    }

    private func firstFlightNumber(in text: String) -> (String, String)? {
        let all = allMatches(Self.flightNumberPattern, in: text)
        for match in all {
            guard match.count >= 3 else { continue }
            let code = match[1], number = match[2]
            // Filter obvious false positives: airport codes are 3 letters (won't match),
            // but seat rows ("12A") and years slip through — require the code to not be
            // two digits and the whole thing to not look like a time or seat.
            if code.allSatisfy(\.isNumber) { continue }
            if number.count == 4, let n = Int(number), (1900...2100).contains(n),
               !text.lowercased().contains("flight \(code.lowercased())") {
                continue // looks like a year
            }
            return (code, number)
        }
        return nil
    }

    private func firstKnownAirportCode(in text: String) -> String? {
        let all = allMatches(#"\b([A-Z]{3})\b"#, in: text)
        for match in all where match.count >= 2 {
            if airports.isKnownIATA(match[1]) { return match[1] }
        }
        return nil
    }

    /// "Flight to San Francisco", "Flight to Tokyo (NH 7)": map trailing city to an airport.
    private func cityDestination(in title: String) -> String? {
        guard let range = title.range(of: #"(?i)flight to ([A-Za-zÀ-ÿ .'-]+)"#, options: .regularExpression) else {
            return nil
        }
        var city = String(title[range]).dropFirst("flight to ".count)
        if let paren = city.firstIndex(of: "(") {
            city = city[..<paren]
        }
        let cleaned = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let hits = airports.search(cleaned, limit: 1)
        return hits.first?.iata
    }

    private func matches(_ pattern: String, in text: String, caseInsensitive: Bool = false) -> [String]? {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let r = Range(match.range(at: index), in: text) else { return "" }
            return String(text[r])
        }
    }

    private func allMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let r = Range(match.range(at: index), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    /// Collapses duplicate detections of the same flight (e.g. Flighty + airline both wrote
    /// events). Duplicates depart within 90 minutes of each other and don't disagree on any
    /// field both events actually specify (a missing airport is not a disagreement — one app
    /// may only know the destination city). Higher confidence wins.
    static func deduplicate(_ flights: [DetectedFlight]) -> [DetectedFlight] {
        func fieldsAgree(_ a: String?, _ b: String?) -> Bool {
            guard let a, let b else { return true }
            return a == b
        }
        var kept: [DetectedFlight] = []
        for flight in flights.sorted(by: { $0.confidence > $1.confidence }) {
            let isDuplicate = kept.contains { existing in
                abs(existing.departure.timeIntervalSince(flight.departure)) < .minutes(90)
                    && fieldsAgree(existing.departureAirport, flight.departureAirport)
                    && fieldsAgree(existing.arrivalAirport, flight.arrivalAirport)
                    && fieldsAgree(existing.flightNumber, flight.flightNumber)
            }
            if !isDuplicate { kept.append(flight) }
        }
        return kept.sorted { $0.departure < $1.departure }
    }

    /// Converts a confirmed detection into a flight segment. Returns nil if required fields
    /// are missing — the UI then routes the user to manual completion.
    public func makeSegment(from flight: DetectedFlight) -> FlightSegment? {
        guard
            let departureAirport = flight.departureAirport,
            let arrivalAirport = flight.arrivalAirport,
            let departureZone = flight.departureZone,
            let arrivalZone = flight.arrivalZone
        else { return nil }
        return FlightSegment(
            airline: flight.airlineCode,
            flightNumber: flight.flightNumber,
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departure: flight.departure,
            arrival: flight.arrival,
            departureZone: departureZone,
            arrivalZone: arrivalZone,
            importSource: .calendar,
            externalIdentifier: flight.sourceTitle
        )
    }
}
