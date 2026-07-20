import Foundation

/// Builds a Trip from confirmed segments — one shared implementation of destination
/// inference (the stay airport before the longest ≥48h gap) for every import path.
public enum TripAssembler {

    /// The stay airport: arrival of the last segment before the longest ≥48h ground gap,
    /// or the final arrival for one-way itineraries.
    public static func stayAirport(of segments: [FlightSegment]) -> String? {
        let sorted = segments.sorted { $0.departure < $1.departure }
        guard let last = sorted.last else { return nil }
        guard sorted.count > 1 else { return last.arrivalAirport }
        var bestGap: TimeInterval = 0
        var stay = last.arrivalAirport
        for i in 1..<sorted.count {
            let gap = sorted[i].departure.timeIntervalSince(sorted[i - 1].arrival)
            if gap > bestGap && gap >= .hours(48) {
                bestGap = gap
                stay = sorted[i - 1].arrivalAirport
            }
        }
        return stay
    }

    public static func makeTrip(
        segments: [FlightSegment],
        homeZone: ZoneID,
        airports: AirportDirectory,
        intensity: PlanIntensity = .balanced,
        preTripDaysOverride: Int? = nil,
        airportTransferMinutes: Int? = nil,
        importSource: ImportSource
    ) -> Trip? {
        let sorted = segments.sorted { $0.departure < $1.departure }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let stayCode = stayAirport(of: sorted) ?? last.arrivalAirport
        let stayAirport = airports.airport(iata: stayCode)
        let destinationName = stayAirport?.city ?? stayCode
        let destinationZone = stayAirport?.zone
            ?? sorted.first(where: { $0.arrivalAirport == stayCode })?.arrivalZone
            ?? last.arrivalZone

        return Trip(
            name: destinationName,
            origin: first.departureAirport,
            destination: destinationName,
            homeZone: homeZone,
            destinationZone: destinationZone,
            segments: sorted,
            intensity: intensity,
            preTripDaysOverride: preTripDaysOverride,
            airportTransferMinutes: airportTransferMinutes,
            importSource: importSource
        )
    }

    /// One trip from two, when they're really one journey (a connection entered
    /// flight-by-flight). Keeps `host`'s identity and levers — id, intensity,
    /// overrides, share state — pools segments and commitments, and re-derives the
    /// route fields the same way `makeTrip` would. Returns nil when the trips
    /// don't chain as a connection.
    public static func merging(
        _ host: Trip,
        absorbing other: Trip,
        airports: AirportDirectory
    ) -> Trip? {
        guard let segments = TripMerger.mergedSegments(host, other),
              let first = segments.first, let last = segments.last
        else { return nil }
        var merged = host
        merged.segments = segments
        merged.commitments = (host.commitments + other.commitments).sorted { $0.start < $1.start }
        let stayCode = stayAirport(of: segments) ?? last.arrivalAirport
        let stay = airports.airport(iata: stayCode)
        let destinationName = stay?.city ?? stayCode
        merged.name = destinationName
        merged.origin = first.departureAirport
        merged.destination = destinationName
        merged.destinationZone = stay?.zone
            ?? segments.first(where: { $0.arrivalAirport == stayCode })?.arrivalZone
            ?? last.arrivalZone
        return merged
    }
}
