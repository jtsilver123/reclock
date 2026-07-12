import Foundation

/// Validates user-entered or imported itineraries before a trip is saved.
public struct TripValidator: Sendable {
    public enum Issue: Sendable, Equatable, CustomStringConvertible {
        case noSegments
        case arrivalBeforeDeparture(segmentIndex: Int)
        case implausiblyLongFlight(segmentIndex: Int, hours: Int)
        case overlappingSegments(firstIndex: Int, secondIndex: Int)
        case unknownTimeZone(identifier: String)
        case unknownAirport(code: String)
        case departureInPast(segmentIndex: Int)

        public var description: String {
            switch self {
            case .noSegments:
                return "Add at least one flight."
            case .arrivalBeforeDeparture(let index):
                return "Flight \(index + 1) lands before it takes off. Double-check the dates and times — this usually means a time zone or overnight date slipped."
            case .implausiblyLongFlight(let index, let hours):
                return "Flight \(index + 1) would be \(hours) hours long. The longest scheduled flights are about 19 hours, so a date is probably off."
            case .overlappingSegments(let first, let second):
                return "Flights \(first + 1) and \(second + 1) overlap in time."
            case .unknownTimeZone(let identifier):
                return "We couldn't resolve the time zone “\(identifier)”. Pick the airport's city instead."
            case .unknownAirport(let code):
                return "We don't recognize the airport code “\(code)”. You can still continue by picking its time zone manually."
            case .departureInPast(let index):
                return "Flight \(index + 1) departs in the past."
            }
        }

        public var isBlocking: Bool {
            switch self {
            case .unknownAirport, .departureInPast: return false
            default: return true
            }
        }
    }

    private let airports: AirportDirectory

    public init(airports: AirportDirectory = .bundled) {
        self.airports = airports
    }

    public func validate(segments: [FlightSegment], now: Date? = nil) -> [Issue] {
        var issues: [Issue] = []
        guard !segments.isEmpty else { return [.noSegments] }

        let sorted = segments.sorted { $0.departure < $1.departure }
        for (index, segment) in sorted.enumerated() {
            if segment.arrival <= segment.departure {
                issues.append(.arrivalBeforeDeparture(segmentIndex: index))
            } else if segment.blockTime > .hours(20) {
                issues.append(.implausiblyLongFlight(segmentIndex: index, hours: Int(segment.blockTime.inHours)))
            }
            if segment.departureZone.timeZone == nil {
                issues.append(.unknownTimeZone(identifier: segment.departureZone.identifier))
            }
            if segment.arrivalZone.timeZone == nil {
                issues.append(.unknownTimeZone(identifier: segment.arrivalZone.identifier))
            }
            if !airports.isKnownIATA(segment.departureAirport) {
                issues.append(.unknownAirport(code: segment.departureAirport))
            }
            if !airports.isKnownIATA(segment.arrivalAirport) {
                issues.append(.unknownAirport(code: segment.arrivalAirport))
            }
            if let now, segment.departure < now.addingTimeInterval(-.hours(6)) {
                issues.append(.departureInPast(segmentIndex: index))
            }
            if index > 0, segment.departure < sorted[index - 1].arrival {
                issues.append(.overlappingSegments(firstIndex: index - 1, secondIndex: index))
            }
        }
        return issues
    }

    public func hasBlockingIssues(segments: [FlightSegment], now: Date? = nil) -> Bool {
        validate(segments: segments, now: now).contains { $0.isBlocking }
    }
}
