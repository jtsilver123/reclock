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
