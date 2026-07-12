import Foundation

/// A wall-clock time of day (e.g. "23:15") independent of any date or zone.
public struct LocalClockTime: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = ((hour % 24) + 24) % 24
        self.minute = min(max(minute, 0), 59)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public init(minutesSinceMidnight: Int) {
        let normalized = ((minutesSinceMidnight % 1440) + 1440) % 1440
        self.hour = normalized / 60
        self.minute = normalized % 60
    }

    public static func < (lhs: LocalClockTime, rhs: LocalClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Resolves this clock time on a given calendar day in a zone.
    /// During DST gaps (a nonexistent time), Foundation returns the closest valid instant.
    public func date(on day: Date, in timeZone: TimeZone, calendar: Calendar = .gregorianUTC) -> Date? {
        var cal = calendar
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: day)
        var target = DateComponents()
        target.year = comps.year
        target.month = comps.month
        target.day = comps.day
        target.hour = hour
        target.minute = minute
        return cal.date(from: target)
    }
}

extension Calendar {
    /// A Gregorian calendar pinned to UTC, for deterministic arithmetic independent of device locale.
    public static var gregorianUTC: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    /// A Gregorian calendar in a specific zone.
    public static func gregorian(in timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }
}

extension TimeInterval {
    public static func hours(_ value: Double) -> TimeInterval { value * 3600 }
    public static func minutes(_ value: Double) -> TimeInterval { value * 60 }
    public var inHours: Double { self / 3600 }
}

extension Date {
    public func adding(hours: Double) -> Date { addingTimeInterval(.hours(hours)) }
    public func adding(minutes: Double) -> Date { addingTimeInterval(.minutes(minutes)) }
}

/// A closed interval of instants. Half-open semantics (start inclusive, end exclusive) for overlap math.
public struct TimeWindow: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var midpoint: Date { start.addingTimeInterval(duration / 2) }

    public func overlaps(_ other: TimeWindow) -> Bool {
        start < other.end && other.start < end
    }

    public func contains(_ instant: Date) -> Bool {
        instant >= start && instant < end
    }

    public func intersection(_ other: TimeWindow) -> TimeWindow? {
        let s = max(start, other.start)
        let e = min(end, other.end)
        guard s < e else { return nil }
        return TimeWindow(start: s, end: e)
    }

    /// Subtracts another window, returning the remaining pieces (0, 1, or 2).
    public func subtracting(_ other: TimeWindow) -> [TimeWindow] {
        guard overlaps(other) else { return [self] }
        var pieces: [TimeWindow] = []
        if other.start > start { pieces.append(TimeWindow(start: start, end: other.start)) }
        if other.end < end { pieces.append(TimeWindow(start: other.end, end: end)) }
        return pieces
    }
}

/// Wraps an IANA time-zone identifier so models stay Codable and valid zones are enforced at the edges.
public struct ZoneID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let identifier: String

    public init(_ identifier: String) {
        self.identifier = identifier
    }

    public var timeZone: TimeZone? { TimeZone(identifier: identifier) }

    /// Resolves the zone, falling back to UTC. Callers that must surface bad zones use `timeZone` directly.
    public var resolved: TimeZone { timeZone ?? TimeZone(identifier: "UTC")! }

    public var description: String { identifier }

    public static let utc = ZoneID("UTC")
}
