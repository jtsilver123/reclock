import Foundation

/// A recent night of observed sleep (e.g. from HealthKit). Start/end are instants;
/// the provider does not interpret them.
public struct ObservedSleepNight: Sendable, Hashable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum SleepDataAvailability: Sendable, Equatable {
    case available
    case notDetermined
    case denied
    case unsupported
}

/// Abstracts the source of observed sleep so HealthKit stays optional and the app is fully
/// functional without it. The HealthKit implementation lives in the app target; the kit
/// only ever sees this protocol.
public protocol SleepDataProvider: Sendable {
    func availability() async -> SleepDataAvailability
    func requestAccess() async -> Bool
    /// Recent sleep nights, most recent first. Empty when unavailable.
    func recentNights(limit: Int) async -> [ObservedSleepNight]
}

/// Default provider when HealthKit is unavailable or declined: does nothing, reports
/// unsupported, and the app quietly hides the related UI.
public struct UnavailableSleepDataProvider: SleepDataProvider {
    public init() {}
    public func availability() async -> SleepDataAvailability { .unsupported }
    public func requestAccess() async -> Bool { false }
    public func recentNights(limit: Int) async -> [ObservedSleepNight] { [] }
}

/// Derives suggested habitual bed/wake times from observed nights, for onboarding pre-fill.
public enum SleepPatternAnalyzer {
    public struct Suggestion: Sendable, Equatable {
        public var bedtime: LocalClockTime
        public var wakeTime: LocalClockTime
        public var sampleCount: Int
    }

    /// Median bed/wake clock times across recent *main* sleep periods (≥ 3h), in the given
    /// zone. Returns nil with fewer than 3 usable nights — a bad suggestion is worse than none.
    public static func suggestTypicalSleep(
        nights: [ObservedSleepNight],
        zone: TimeZone
    ) -> Suggestion? {
        let usable = nights.filter { $0.duration >= .hours(3) && $0.duration <= .hours(14) }
        guard usable.count >= 3 else { return nil }
        let cal = Calendar.gregorian(in: zone)

        func clockMinutes(_ date: Date) -> Int {
            let comps = cal.dateComponents([.hour, .minute], from: date)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }

        // Bedtimes cluster around midnight; unwrap by shifting early-morning values +24h
        // before taking the median.
        let bedMinutes = usable.map { night -> Int in
            let m = clockMinutes(night.start)
            return m < 12 * 60 ? m + 24 * 60 : m
        }.sorted()
        let wakeMinutes = usable.map { clockMinutes($0.end) }.sorted()

        let medianBed = bedMinutes[bedMinutes.count / 2] % (24 * 60)
        let medianWake = wakeMinutes[wakeMinutes.count / 2]

        return Suggestion(
            bedtime: LocalClockTime(minutesSinceMidnight: medianBed),
            wakeTime: LocalClockTime(minutesSinceMidnight: medianWake),
            sampleCount: usable.count
        )
    }
}
