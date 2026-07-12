import Foundation

/// Pure functions for phase arithmetic. All instants are UTC `Date`s; zones only matter
/// when resolving a wall-clock target into an instant.
public enum CircadianMath {

    /// Normalizes an hour delta into (-12, +12].
    /// +7 means the destination clock reads 7h later (eastward; body must advance).
    public static func normalizedZoneDelta(hours: Double) -> Double {
        var d = hours.truncatingRemainder(dividingBy: 24)
        if d > 12 { d -= 24 }
        if d <= -12 { d += 24 }
        return d
    }

    /// Signed zone difference (destination − home) in hours at a reference instant.
    public static func zoneDelta(home: TimeZone, destination: TimeZone, at instant: Date) -> Double {
        let homeOffset = Double(home.secondsFromGMT(for: instant))
        let destOffset = Double(destination.secondsFromGMT(for: instant))
        return normalizedZoneDelta(hours: (destOffset - homeOffset) / 3600)
    }

    public struct ShiftPlan: Sendable, Equatable {
        /// Signed hours to shift. Positive = advance.
        public var shiftHours: Double
        public var direction: ShiftDirection
        public var daysToComplete: Int
    }

    /// Chooses direction and magnitude, including the antidromic case: for a large eastward
    /// shift it may be faster to delay "the long way around" (e.g. +11h east → 13h delay).
    public static func chooseShift(
        zoneDeltaHours: Double,
        configuration: PlanEngineConfiguration,
        intensity: PlanIntensity
    ) -> ShiftPlan {
        let delta = normalizedZoneDelta(hours: zoneDeltaHours)
        if abs(delta) < configuration.minimumShiftWorthPlanning {
            return ShiftPlan(shiftHours: 0, direction: .none, daysToComplete: 0)
        }
        if delta > 0 {
            // Eastward: default is to advance by `delta`.
            let advanceRate = configuration.shiftRate(direction: .advance, intensity: intensity)
            let advanceDays = Int((delta / advanceRate).rounded(.up))
            if delta >= configuration.antidromicThresholdHours {
                let delayHours = 24 - delta
                let delayRate = configuration.shiftRate(direction: .delay, intensity: intensity)
                let delayDays = Int((delayHours / delayRate).rounded(.up))
                if delayDays < advanceDays {
                    return ShiftPlan(shiftHours: -delayHours, direction: .delay, daysToComplete: delayDays)
                }
            }
            return ShiftPlan(shiftHours: delta, direction: .advance, daysToComplete: advanceDays)
        } else {
            // Westward: delay by |delta|.
            let delayRate = configuration.shiftRate(direction: .delay, intensity: intensity)
            let days = Int((abs(delta) / delayRate).rounded(.up))
            return ShiftPlan(shiftHours: delta, direction: .delay, daysToComplete: days)
        }
    }

    /// Estimated CBTmin as an offset before wake, adjusted for chronotype.
    public static func cbtMinOffsetBeforeWake(
        profile: UserProfile,
        configuration: PlanEngineConfiguration
    ) -> Double {
        let adjustment = configuration.chronotypeCBTAdjustment[profile.chronotype] ?? 0
        return configuration.cbtMinHoursBeforeWake - adjustment
    }

    /// The phase-response regions around CBTmin for bright light.
    /// Light in `advanceRegion` (after CBTmin) advances the clock; light in
    /// `delayRegion` (before CBTmin) delays it.
    public struct LightRegions: Sendable {
        public var advanceRegion: TimeWindow
        public var delayRegion: TimeWindow
    }

    public static func lightRegions(
        cbtMin: Date,
        configuration: PlanEngineConfiguration
    ) -> LightRegions {
        let buffer = TimeInterval.hours(configuration.lightBufferFromCBTmin)
        let half = TimeInterval.hours(configuration.lightResponsiveHalfWindow)
        return LightRegions(
            advanceRegion: TimeWindow(
                start: cbtMin.addingTimeInterval(buffer),
                end: cbtMin.addingTimeInterval(half)
            ),
            delayRegion: TimeWindow(
                start: cbtMin.addingTimeInterval(-half),
                end: cbtMin.addingTimeInterval(-buffer)
            )
        )
    }

    /// Clamps a UTC window to the local daylight span of the calendar day containing its midpoint.
    /// Returns nil if nothing remains (e.g. the whole window is at local night).
    public static func clampToDaylight(
        _ window: TimeWindow,
        zone: TimeZone,
        daylight: ClockRange
    ) -> TimeWindow? {
        let cal = Calendar.gregorian(in: zone)
        let day = cal.startOfDay(for: window.midpoint)
        guard
            let dayStart = daylight.start.date(on: day, in: zone),
            let dayEnd = daylight.end.date(on: day, in: zone)
        else { return nil }
        return window.intersection(TimeWindow(start: dayStart, end: dayEnd))
    }

    /// Resolves a wall-clock time on the local calendar day containing `reference` in `zone`.
    public static func resolve(
        _ clock: LocalClockTime,
        onDayContaining reference: Date,
        zone: TimeZone
    ) -> Date {
        let cal = Calendar.gregorian(in: zone)
        let day = cal.startOfDay(for: reference)
        return clock.date(on: day, in: zone) ?? reference
    }
}
