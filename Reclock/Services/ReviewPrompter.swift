import Foundation
import ReclockKit

/// Persists the App Store review history in UserDefaults (device-local, never synced)
/// and applies ReviewPolicy to decide when to surface Apple's native rating prompt.
/// The actual `requestReview` call happens in the view layer; this only decides.
@MainActor
final class ReviewPrompter {
    private let defaults: UserDefaults
    private static let key = "reclock.review.state"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var state: ReviewPromptState {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(ReviewPromptState.self, from: data)
            else { return ReviewPromptState() }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    /// Count a completed plan step toward the "delivered value" signal.
    func noteCompletedStep() {
        var s = state
        s.completedSteps += 1
        state = s
    }

    /// Pure check — records nothing. The 3-lifetime/90-day budget is charged only
    /// when the prompt actually fires (`recordPrompted`), never when a takeover
    /// suppresses it.
    func shouldAsk(_ trigger: ReviewPolicy.Trigger, now: Date) -> Bool {
        ReviewPolicy.shouldRequest(trigger, state: state, now: now)
    }

    /// The prompt was really shown: spend one ask from the budget.
    func recordPrompted(now: Date) {
        var s = state
        s.lastPromptedAt = now
        s.promptCount += 1
        state = s
    }
}
