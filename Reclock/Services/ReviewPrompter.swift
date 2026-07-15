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

    /// True when the caller should trigger the native prompt now. When it returns true
    /// it also records the ask, so a burst of completions never asks more than once.
    func shouldRequest(_ trigger: ReviewPolicy.Trigger, now: Date) -> Bool {
        guard ReviewPolicy.shouldRequest(trigger, state: state, now: now) else { return false }
        var s = state
        s.lastPromptedAt = now
        s.promptCount += 1
        state = s
        return true
    }
}
