import SwiftUI
import ReclockKit

/// The earned moment: a quiet, warm acknowledgment when the traveler completes a plan
/// step. One pill, one line that knows *why* the step mattered, gone in two seconds.
/// Deliberately not confetti — Reclock celebrates like a good coach, not a slot machine.
struct CelebrationEvent: Equatable, Identifiable {
    let id: UUID
    let type: ActionType

    init(id: UUID = UUID(), type: ActionType) {
        self.id = id
        self.type = type
    }

    /// Copy is deterministic by action type so the voice stays consistent.
    var line: String {
        switch type {
        case .seekLight: "Light logged — the strongest lever, pulled."
        case .avoidLight: "Clock protected. The sun can wait."
        case .sleep: "Sleep banked. Everything builds on that."
        case .nap: "Recharged — and tonight is still safe."
        case .stayAwake: "You made it to bedtime. That was the hard one."
        case .caffeineCutoff: "Cutoff honored. Tonight will thank you."
        case .windDown: "Winding down — the landing is smooth from here."
        case .melatoninOptional: "Noted. Every signal counts."
        case .leaveForAirport: "On your way. Travel calm."
        case .switchToDestinationTime: "New clock, new you."
        default: "Done. Every signal counts."
        }
    }
}

struct CelebrationToast: View {
    let event: CelebrationEvent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: event.id)
            Text(event.line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        )
        .overlay(
            Capsule().strokeBorder(Theme.tint(for: event.type).opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Space.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Slide-drop from the top with a spring; plain fade under Reduce Motion.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }
}
