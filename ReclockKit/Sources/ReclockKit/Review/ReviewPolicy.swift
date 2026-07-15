import Foundation

/// Device-local history behind the "rate us on the App Store" prompt. The app persists
/// this in UserDefaults (never synced); it lives here as a plain value so the timing
/// rules are unit-tested on Linux.
public struct ReviewPromptState: Codable, Sendable, Equatable {
    /// When we last asked (or decided to ask). nil means never.
    public var lastPromptedAt: Date?
    /// How many times we have ever asked on this device.
    public var promptCount: Int
    /// Cumulative plan steps marked done here, our "delivered value" signal.
    public var completedSteps: Int

    public init(lastPromptedAt: Date? = nil, promptCount: Int = 0, completedSteps: Int = 0) {
        self.lastPromptedAt = lastPromptedAt
        self.promptCount = promptCount
        self.completedSteps = completedSteps
    }
}

/// When it is polite to ask for an App Store rating. Ask only at genuine high points,
/// stay well under Apple's cap of three prompts per 365 days, and never nag: no first
/// run, no error states, and long gaps between asks.
public enum ReviewPolicy {
    /// Our own lifetime cap. Apple also silently caps at three per year.
    public static let maxPrompts = 3
    /// Never two prompts closer together than this.
    public static let minDaysBetween = 90.0
    /// "Following the plan" bar: enough done steps that the value is real before we ask.
    public static let stepsForAsk = 6

    /// A moment worth asking about.
    public enum Trigger: Sendable {
        /// The traveler just marked another plan step done.
        case completedStep
        /// The traveler just submitted a positive post-trip check-in.
        case positiveSurvey
    }

    /// Given the trigger and the history, is now an allowed, well-timed moment to ask?
    public static func shouldRequest(
        _ trigger: Trigger,
        state: ReviewPromptState,
        now: Date
    ) -> Bool {
        guard state.promptCount < maxPrompts else { return false }
        if let last = state.lastPromptedAt,
           now.timeIntervalSince(last) < minDaysBetween * 86_400 {
            return false
        }
        switch trigger {
        case .completedStep:
            // Only once the traveler has actually been following a plan for a while.
            return state.completedSteps >= stepsForAsk
        case .positiveSurvey:
            // A happy check-in is always a good moment, subject to the cap and spacing.
            return true
        }
    }
}
