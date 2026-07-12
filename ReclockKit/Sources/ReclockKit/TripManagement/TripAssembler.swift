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
}
