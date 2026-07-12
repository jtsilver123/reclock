import Foundation

/// Answers "what zone is the traveler in at instant t?" for a trip.
///
/// Built from flight segments: home zone before first departure, each segment's arrival zone
/// after it lands, and the departure zone while airborne (display code may prefer showing
/// destination time in flight; that is a presentation choice).
public struct ZoneTimeline: Sendable {
    public struct Breakpoint: Sendable {
        public let start: Date
        public let zone: ZoneID
    }

    public let breakpoints: [Breakpoint]
    public let homeZone: ZoneID

    public init(trip: Trip) {
        self.homeZone = trip.homeZone
        var points: [Breakpoint] = [Breakpoint(start: .distantPast, zone: trip.homeZone)]
        for segment in trip.segments {
            // While airborne, remain in the departure zone until landing.
            points.append(Breakpoint(start: segment.departure, zone: segment.departureZone))
            points.append(Breakpoint(start: segment.arrival, zone: segment.arrivalZone))
        }
        self.breakpoints = points.sorted { $0.start < $1.start }
    }

    public func zone(at instant: Date) -> ZoneID {
        var current = homeZone
        for point in breakpoints {
            if point.start <= instant {
                current = point.zone
            } else {
                break
            }
        }
        return current
    }

    /// The segment airborne at the instant, if any.
    public func segment(at instant: Date, in trip: Trip) -> FlightSegment? {
        trip.segments.first { $0.window.contains(instant) }
    }

    /// The trip phase at an instant, for grouping and labels.
    public func phase(at instant: Date, in trip: Trip) -> TripPhase {
        guard let firstDeparture = trip.firstDeparture, let finalArrival = trip.finalArrival else {
            return .beforeDeparture
        }
        if instant < firstDeparture {
            // Within 3h of departure counts as "at the airport".
            return firstDeparture.timeIntervalSince(instant) <= .hours(3) ? .atAirport : .beforeDeparture
        }
        if let segment = segment(at: instant, in: trip) {
            _ = segment
            return .inFlight
        }
        let returnSegments = trip.returnSegments
        if let returnDeparture = returnSegments.first?.departure {
            if instant >= returnDeparture || returnDeparture.timeIntervalSince(instant) <= .hours(3) {
                return instant > (returnSegments.last?.arrival ?? finalArrival) ? .recovery : .returnTrip
            }
        }
        if let outboundArrival = trip.outboundArrival, instant >= outboundArrival {
            // Between outbound legs (layover) still reads as at-airport.
            if let next = trip.segments.first(where: { $0.departure > instant }),
               trip.outboundSegments.contains(where: { $0.id == next.id }) {
                return .atAirport
            }
            let daysIn = instant.timeIntervalSince(outboundArrival) / 86_400
            return daysIn <= 2 ? .afterArrival : .recovery
        }
        return .atAirport
    }
}
