import Foundation

/// Estimates scheduled block time between two airports from great-circle distance and a
/// direction-aware effective speed (eastbound rides the jet stream; westbound fights it).
///
/// Purpose: pre-fill the arrival time during manual entry so the user types three things,
/// not four. Always presented as an estimate the user confirms against their ticket —
/// typical error is ±15–25 minutes on long-haul routes.
public enum FlightDurationEstimator {

    /// Effective ground speeds (km/h) calibrated against typical published block times.
    /// [REVIEW-free: pure product heuristic, user-confirmed.]
    static let eastboundSpeed = 875.0
    static let westboundSpeed = 800.0
    static let neutralSpeed = 840.0
    /// Taxi, climb, descent, approach overhead.
    static let fixedOverhead: TimeInterval = .minutes(42)

    /// Great-circle distance in kilometers.
    public static func distanceKm(
        lat1: Double, lon1: Double, lat2: Double, lon2: Double
    ) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Estimated block time, or nil when either airport lacks coordinates.
    /// Result is rounded to 5 minutes.
    public static func estimate(from: Airport, to: Airport) -> TimeInterval? {
        guard
            let lat1 = from.latitude, let lon1 = from.longitude,
            let lat2 = to.latitude, let lon2 = to.longitude
        else { return nil }
        let km = distanceKm(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        guard km > 30 else { return nil }

        // Signed eastward longitude change, wrapped to (-180, 180].
        var dLon = lon2 - lon1
        if dLon > 180 { dLon -= 360 }
        if dLon <= -180 { dLon += 360 }
        // Blend toward the neutral speed for mostly north–south routes.
        let eastwardness = min(1.0, abs(dLon) / 25.0) * (dLon > 0 ? 1.0 : -1.0)
        let speed = neutralSpeed + (eastwardness > 0
            ? (eastboundSpeed - neutralSpeed) * eastwardness
            : (westboundSpeed - neutralSpeed) * -eastwardness)

        let seconds = km / speed * 3600 + fixedOverhead
        return (seconds / 300).rounded() * 300
    }
}
