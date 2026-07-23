import Foundation

/// Recognizes when two separately-added trips are really one journey — a flight plus
/// its connection, entered one at a time — so the app can fold them into a single
/// trip instead of showing twins. "One journey" means every seam between segments
/// from different trips is a same-airport handoff within the layover window; a gap
/// long enough to be a stay never merges (that's a distinct trip, or a stopover the
/// user should enter deliberately).
public enum TripMerger {

    /// Longest ground time that still reads as a layover. Overnight connections
    /// (land 22:00, depart 09:00) fit; anything longer is a stay with its own plan.
    /// TripAssembler independently treats ≥48h as the destination stay.
    public static let maxConnectionGap: TimeInterval = .hours(16)

    /// True when `next` continues the journey `previous` ends: it leaves from the
    /// airport where `previous` lands, after it lands, within the layover window.
    public static func chains(_ previous: FlightSegment, into next: FlightSegment) -> Bool {
        guard previous.arrivalAirport == next.departureAirport else { return false }
        let gap = next.departure.timeIntervalSince(previous.arrival)
        return gap > 0 && gap <= maxConnectionGap
    }

    /// The longest stay after which a homebound flight no longer reads as the same
    /// trip's return. Two months covers long stays; a return booked further out is
    /// its own journey until proven otherwise.
    public static let maxReturnStayGap: TimeInterval = .hours(24 * 60)

    /// The combined segments when `b` is `a`'s return journey (or vice versa):
    /// it leaves from where the other trip ended, lands back where it began, and
    /// departs after a stay-length gap — longer than a layover, shorter than the
    /// return-stay cap. Connections stay `mergedSegments`' job.
    public static func roundTripSegments(_ a: Trip, _ b: Trip) -> [FlightSegment]? {
        guard !a.segments.isEmpty, !b.segments.isEmpty else { return nil }
        let aFirst = a.segments.first!
        let bFirst = b.segments.first!
        let (out, back) = aFirst.departure <= bFirst.departure ? (a, b) : (b, a)
        guard
            let outFirst = out.segments.first, let outLast = out.segments.last,
            let backFirst = back.segments.first, let backLast = back.segments.last,
            backFirst.departureAirport == outLast.arrivalAirport,
            backLast.arrivalAirport == outFirst.departureAirport
        else { return nil }
        let gap = backFirst.departure.timeIntervalSince(outLast.arrival)
        guard gap > maxConnectionGap, gap <= maxReturnStayGap else { return nil }
        return out.segments + back.segments
    }

    /// The pooled, departure-ordered segments if the two trips are one journey;
    /// nil otherwise. Trips merge when every adjacent pair drawn from DIFFERENT
    /// trips chains as a connection. Pairs from the same trip keep whatever
    /// spacing they already had (an existing stay stays a stay). Overlapping
    /// segments — duplicates, bad data — never merge.
    public static func mergedSegments(_ a: Trip, _ b: Trip) -> [FlightSegment]? {
        guard !a.segments.isEmpty, !b.segments.isEmpty else { return nil }
        let pooled = (a.segments.map { (owner: a.id, segment: $0) }
                      + b.segments.map { (owner: b.id, segment: $0) })
            .sorted { $0.segment.departure < $1.segment.departure }
        var crossSeams = 0
        for i in 1..<pooled.count {
            let previous = pooled[i - 1]
            let next = pooled[i]
            guard next.segment.departure > previous.segment.arrival else { return nil }
            if previous.owner != next.owner {
                guard chains(previous.segment, into: next.segment) else { return nil }
                crossSeams += 1
            }
        }
        guard crossSeams > 0 else { return nil }
        return pooled.map(\.segment)
    }
}
