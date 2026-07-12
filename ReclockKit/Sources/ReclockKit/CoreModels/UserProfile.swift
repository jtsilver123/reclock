import Foundation

/// Everything Reclock knows about the traveler. Lives on-device only.
public struct UserProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var homeZone: ZoneID
    /// Habitual bedtime on a normal (non-travel) night, in home local time.
    public var typicalBedtime: LocalClockTime
    /// Habitual wake time on a normal morning, in home local time.
    public var typicalWakeTime: LocalClockTime
    public var chronotype: Chronotype
    public var planeSleepAbility: PlaneSleepAbility
    /// The longest block of sleep the user believes they can realistically get in their usual cabin.
    public var maxInFlightSleep: TimeInterval
    /// Whether the user would rather sleep through in-flight meal service.
    public var prioritizesSleepOverMeals: Bool
    public var caffeine: CaffeinePreference
    /// The window in which the user normally drinks caffeine (home local time).
    public var typicalCaffeineWindow: ClockRange?
    public var melatonin: MelatoninPreference
    public var preTripAdjustment: PreTripAdjustmentWillingness
    public var notifications: NotificationPreferences
    public var accessibility: AccessibilityPreferences

    public init(
        id: UUID = UUID(),
        homeZone: ZoneID,
        typicalBedtime: LocalClockTime = LocalClockTime(hour: 23, minute: 0),
        typicalWakeTime: LocalClockTime = LocalClockTime(hour: 7, minute: 0),
        chronotype: Chronotype = .neutral,
        planeSleepAbility: PlaneSleepAbility = .sometimes,
        maxInFlightSleep: TimeInterval = .hours(4),
        prioritizesSleepOverMeals: Bool = false,
        caffeine: CaffeinePreference = .include,
        typicalCaffeineWindow: ClockRange? = nil,
        melatonin: MelatoninPreference = .unsure,
        preTripAdjustment: PreTripAdjustmentWillingness = .small,
        notifications: NotificationPreferences = NotificationPreferences(),
        accessibility: AccessibilityPreferences = AccessibilityPreferences()
    ) {
        self.id = id
        self.homeZone = homeZone
        self.typicalBedtime = typicalBedtime
        self.typicalWakeTime = typicalWakeTime
        self.chronotype = chronotype
        self.planeSleepAbility = planeSleepAbility
        self.maxInFlightSleep = maxInFlightSleep
        self.prioritizesSleepOverMeals = prioritizesSleepOverMeals
        self.caffeine = caffeine
        self.typicalCaffeineWindow = typicalCaffeineWindow
        self.melatonin = melatonin
        self.preTripAdjustment = preTripAdjustment
        self.notifications = notifications
        self.accessibility = accessibility
    }

    /// Habitual sleep duration derived from bed/wake clock times (handles crossing midnight).
    public var typicalSleepDuration: TimeInterval {
        let bed = typicalBedtime.minutesSinceMidnight
        let wake = typicalWakeTime.minutesSinceMidnight
        let minutes = wake > bed ? wake - bed : (1440 - bed) + wake
        return TimeInterval(minutes) * 60
    }
}

public enum Chronotype: String, Codable, CaseIterable, Sendable {
    case early
    case neutral
    case late
    case unsure

    public var displayName: String {
        switch self {
        case .early: "Early bird"
        case .neutral: "Neither"
        case .late: "Night owl"
        case .unsure: "Not sure"
        }
    }
}

public enum PlaneSleepAbility: String, Codable, CaseIterable, Sendable {
    case easily
    case sometimes
    case rarely
    case never

    public var displayName: String {
        switch self {
        case .easily: "Easily"
        case .sometimes: "Sometimes"
        case .rarely: "Rarely"
        case .never: "Basically never"
        }
    }
}

public enum CaffeinePreference: String, Codable, CaseIterable, Sendable {
    case include
    case exclude

    public var displayName: String {
        switch self {
        case .include: "Include caffeine timing"
        case .exclude: "Skip caffeine guidance"
        }
    }
}

public enum MelatoninPreference: String, Codable, CaseIterable, Sendable {
    case exclude
    case includeOptionalReminders
    case unsure

    public var displayName: String {
        switch self {
        case .exclude: "Don't include"
        case .includeOptionalReminders: "Include optional reminders"
        case .unsure: "Not sure yet"
        }
    }

    public var remindersEnabled: Bool { self == .includeOptionalReminders }
}

public enum PreTripAdjustmentWillingness: String, Codable, CaseIterable, Sendable {
    case none
    case small
    case moderate
    case maximum

    public var displayName: String {
        switch self {
        case .none: "None — start when I fly"
        case .small: "A little (1 day)"
        case .moderate: "Some (2 days)"
        case .maximum: "As much as helps (3 days)"
        }
    }

    /// Maximum number of pre-departure shift days this willingness allows.
    public var maxPreTripDays: Int {
        switch self {
        case .none: 0
        case .small: 1
        case .moderate: 2
        case .maximum: 3
        }
    }
}

/// A daily clock-time range, e.g. caffeine 07:00–15:00 or quiet hours 22:00–07:00 (may wrap midnight).
public struct ClockRange: Codable, Hashable, Sendable {
    public var start: LocalClockTime
    public var end: LocalClockTime

    public init(start: LocalClockTime, end: LocalClockTime) {
        self.start = start
        self.end = end
    }

    public var wrapsMidnight: Bool { end <= start }

    public func contains(_ time: LocalClockTime) -> Bool {
        if wrapsMidnight {
            return time >= start || time < end
        }
        return time >= start && time < end
    }
}

public struct NotificationPreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// Quiet hours in whatever zone the traveler is in when a notification would fire.
    public var quietHours: ClockRange
    public var includeOptionalActions: Bool

    public init(
        enabled: Bool = true,
        quietHours: ClockRange = ClockRange(
            start: LocalClockTime(hour: 22, minute: 0),
            end: LocalClockTime(hour: 7, minute: 0)
        ),
        includeOptionalActions: Bool = false
    ) {
        self.enabled = enabled
        self.quietHours = quietHours
        self.includeOptionalActions = includeOptionalActions
    }
}

public struct AccessibilityPreferences: Codable, Hashable, Sendable {
    /// Prefer 24-hour time display regardless of locale. `nil` follows the system.
    public var prefers24HourTime: Bool?
    public var reduceMotionOverride: Bool?

    public init(prefers24HourTime: Bool? = nil, reduceMotionOverride: Bool? = nil) {
        self.prefers24HourTime = prefers24HourTime
        self.reduceMotionOverride = reduceMotionOverride
    }
}
