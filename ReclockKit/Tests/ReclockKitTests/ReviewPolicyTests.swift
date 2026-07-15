import Foundation
import Testing
@testable import ReclockKit

@Suite("Review prompt timing")
struct ReviewPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("Never asks before the value bar is met")
    func stepsBarGuardsFirstAsk() {
        var state = ReviewPromptState(completedSteps: ReviewPolicy.stepsForAsk - 1)
        #expect(!ReviewPolicy.shouldRequest(.completedStep, state: state, now: now))
        state.completedSteps = ReviewPolicy.stepsForAsk
        #expect(ReviewPolicy.shouldRequest(.completedStep, state: state, now: now))
    }

    @Test("A positive survey can ask even with few steps")
    func positiveSurveyBypassesStepBar() {
        let state = ReviewPromptState(completedSteps: 0)
        #expect(ReviewPolicy.shouldRequest(.positiveSurvey, state: state, now: now))
    }

    @Test("Respects the lifetime cap")
    func lifetimeCap() {
        let maxed = ReviewPromptState(
            lastPromptedAt: now.addingTimeInterval(-400 * 86_400),
            promptCount: ReviewPolicy.maxPrompts,
            completedSteps: 99
        )
        #expect(!ReviewPolicy.shouldRequest(.completedStep, state: maxed, now: now))
        #expect(!ReviewPolicy.shouldRequest(.positiveSurvey, state: maxed, now: now))
    }

    @Test("Never asks twice inside the spacing window")
    func spacingWindow() {
        let recent = ReviewPromptState(
            lastPromptedAt: now.addingTimeInterval(-10 * 86_400),
            promptCount: 1,
            completedSteps: 99
        )
        #expect(!ReviewPolicy.shouldRequest(.completedStep, state: recent, now: now))
        #expect(!ReviewPolicy.shouldRequest(.positiveSurvey, state: recent, now: now))

        let longAgo = ReviewPromptState(
            lastPromptedAt: now.addingTimeInterval(-(ReviewPolicy.minDaysBetween + 1) * 86_400),
            promptCount: 1,
            completedSteps: 99
        )
        #expect(ReviewPolicy.shouldRequest(.completedStep, state: longAgo, now: now))
    }
}
