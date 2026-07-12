import Foundation

/// Every tunable constant in the planning protocol, in one reviewable place.
///
/// ⚠️ EXPERT REVIEW: values marked [REVIEW] are implementation choices layered on top of
/// established chronobiology and should be reviewed by a sleep/circadian specialist before
/// any public marketing claims. See SCIENCE_SPEC.md for sources and rationale.
public struct PlanEngineConfiguration: Sendable {

    // MARK: Phase model

    /// Estimated core-body-temperature minimum, as hours before habitual wake. [REVIEW]
    /// Literature places CBTmin ~2–3h before habitual wake in adults.
    public var cbtMinHoursBeforeWake: Double = 2.5
    /// Chronotype nudge applied to the CBTmin estimate (early types sit earlier). [REVIEW]
    public var chronotypeCBTAdjustment: [Chronotype: Double] = [
        .early: -0.25,
        .neutral: 0,
        .late: 0.25,
        .unsure: 0,
    ]

    // MARK: Shift rates (hours of body-clock movement scheduled per day)

    /// Daily phase advance rate (eastward). Field studies support ~1h/day with timed light. [REVIEW]
    public var advanceRatePerDay: Double = 1.0
    /// Daily phase delay rate (westward). Delays come easier; ~1.5h/day. [REVIEW]
    public var delayRatePerDay: Double = 1.5
    /// Rate multiplier for `.maximum` intensity. [REVIEW]
    public var maximumIntensityRateMultiplier: Double = 1.25
    /// Pre-departure shifting is slower because normal life continues. [REVIEW]
    public var preTripRatePerDay: Double = 1.0

    /// Eastward shifts larger than this are compared against going "the long way round"
    /// (delaying instead of advancing); the faster path wins. [REVIEW]
    public var antidromicThresholdHours: Double = 9.0

    // MARK: Pre-trip days by intensity (intersected with user willingness)

    public var preTripDays: [PlanIntensity: Int] = [
        .easy: 0,
        .balanced: 2,
        .maximum: 3,
    ]

    // MARK: Short-trip anchoring

    /// Trips of at most this many destination nights suggest staying on home time…
    public var anchorMaxNights: Int = 2
    /// …when the zone change is at most this many hours. Beyond it, even short trips adapt partially.
    public var anchorMaxShiftHours: Double = 5.0
    /// Below this absolute zone difference no adaptation plan is needed at all.
    public var minimumShiftWorthPlanning: Double = 1.0

    // MARK: Light windows (relative to estimated CBTmin)

    /// Keep light interventions this far away from CBTmin, where response flips direction. [REVIEW]
    public var lightBufferFromCBTmin: Double = 0.5
    /// The phase-response region considered effective, in hours from CBTmin. [REVIEW]
    public var lightResponsiveHalfWindow: Double = 6.0
    /// Preferred duration of a seek-light block.
    public var seekLightDuration: Double = 2.0
    public var seekLightMinimumDuration: Double = 0.75
    /// Hours of local clock time considered plausible for outdoor light.
    public var daylightWindow: ClockRange = ClockRange(
        start: LocalClockTime(hour: 7, minute: 0),
        end: LocalClockTime(hour: 20, minute: 0)
    )
    /// How many days after arrival to keep scheduling avoid-light guidance.
    public var avoidLightDaysAfterArrival: Int = 3

    // MARK: Airport logistics

    /// Time to be at the airport before departure (check-in, security, walk to gate).
    public var airportArrivalLeadHours: Double = 2.0
    /// Door-to-terminal transfer when the trip doesn't specify one.
    public var defaultTransferMinutes: Int = 60
    /// Packing/shoes-on buffer added before the transfer for the leave-by reminder.
    public var transferPrepBufferMinutes: Double = 15

    // MARK: Sleep constraints

    /// No planned sleep within this window after departure (boarding, taxi, climb, service start).
    public var minutesAfterTakeoffBeforeSleep: Double = 45
    /// No planned sleep within this window before landing (descent, arrival prep).
    public var minutesBeforeLandingNoSleep: Double = 75
    /// Shortest in-flight sleep block worth scheduling.
    public var minimumUsefulInFlightSleep: Double = 1.5 * 3600
    /// Shortest layover during which airport sleep is scheduled (below this: stay awake).
    public var minimumLayoverForSleep: Double = 5 * 3600
    /// Practical clamp on scheduled local bedtime at the destination. [REVIEW]
    public var earliestPracticalBedtime = LocalClockTime(hour: 20, minute: 30)
    public var latestPracticalBedtime = LocalClockTime(hour: 1, minute: 30)
    /// Nights with less than this much sleep add to sleep-debt tracking.
    public var minimumProtectedSleep: Double = 5.5 * 3600

    // MARK: Naps

    /// Maximum arrival-day recovery nap. Longer invites deep sleep and worse night sleep. [REVIEW]
    public var maxNapMinutes: Double = 30
    /// A nap must end at least this many hours before the target bedtime.
    public var napBufferBeforeBed: Double = 8.0
    /// Only offer a nap when the previous night produced less than this much sleep.
    public var napSleepDebtThreshold: Double = 5.0 * 3600

    // MARK: Caffeine

    /// Last caffeine this many hours before target bedtime. Half-life ~5h; 8–10h is prudent. [REVIEW]
    public var caffeineCutoffHoursBeforeBed: Double = 9.0
    /// Don't suggest caffeine within this many hours after waking (adenosine still low).
    public var caffeineDelayAfterWake: Double = 0.75

    // MARK: Melatonin (optional reminders only — never presented as required)

    /// For phase advances, an early-evening reminder this many hours before the *shifting*
    /// bedtime aligns with the advance portion of the melatonin PRC. [REVIEW]
    public var melatoninAdvanceLeadHours: Double = 5.0
    /// Whether to offer melatonin reminders for delays (westward). Default off: weaker evidence.
    public var melatoninForDelays: Bool = false
    /// Days after arrival to keep offering the reminder.
    public var melatoninDaysAfterArrival: Int = 3

    // MARK: Adaptive replanning

    /// Credit multiplier for a day whose key actions were confirmed done.
    public var complianceCreditDone: Double = 1.0
    /// Credit when we have no reports (assume mostly-followed). [REVIEW]
    public var complianceCreditUnknown: Double = 0.75
    /// Credit when key actions were reported missed.
    public var complianceCreditMissed: Double = 0.4

    // MARK: Action density caps per day

    public var maxActionsPerDay: [PlanIntensity: Int] = [
        .easy: 5,
        .balanced: 8,
        .maximum: 11,
    ]

    // MARK: Priority thresholds (impact score → bucket)

    public var mustDoThreshold: Int = 80
    public var helpfulThreshold: Int = 45

    /// How many recovery days to plan after arrival, beyond the shift itself.
    public var recoveryBufferDays: Int = 1
    /// Maximum days the engine will plan after arrival regardless of shift size.
    public var maxAdaptationDays: Int = 8

    public init() {}

    public func shiftRate(direction: ShiftDirection, intensity: PlanIntensity) -> Double {
        let base: Double
        switch direction {
        case .advance: base = advanceRatePerDay
        case .delay: base = delayRatePerDay
        case .none: return 0
        }
        return intensity == .maximum ? base * maximumIntensityRateMultiplier : base
    }

    public func preTripDayCount(intensity: PlanIntensity, willingness: PreTripAdjustmentWillingness) -> Int {
        min(preTripDays[intensity] ?? 0, willingness.maxPreTripDays)
    }

    public func priority(forImpact score: Int) -> ActionPriority {
        if score >= mustDoThreshold { return .mustDo }
        if score >= helpfulThreshold { return .helpful }
        return .optional
    }
}

/// The user-facing safety text attached to every melatonin action.
public enum SafetyCopy {
    public static let melatoninDisclaimer = """
    Melatonin affects people differently and product contents can vary. This is optional \
    general information, not medical advice. Check with a clinician or pharmacist if you \
    have questions, take medication, are pregnant, or have a health condition.
    """

    public static let drowsinessWarning = """
    If you feel very sleepy, don't drive or do anything hazardous — adjust the plan instead.
    """
}
