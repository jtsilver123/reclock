import SwiftUI
import ReclockKit

/// The earned moment: a quiet, warm acknowledgment when the traveler completes a plan
/// step. One pill, one line that knows *why* the step mattered, gone in two seconds.
/// Deliberately not confetti — Reclock celebrates like a good coach, not a slot machine.
struct CelebrationEvent: Equatable, Identifiable {
    let id: UUID
    let type: ActionType
    /// Overrides the per-type line for product moments (plan ready, kudos, joined).
    var customLine: String?
    var symbol: String = "checkmark.circle.fill"

    init(id: UUID = UUID(), type: ActionType, customLine: String? = nil, symbol: String = "checkmark.circle.fill") {
        self.id = id
        self.type = type
        self.customLine = customLine
        self.symbol = symbol
    }

    static func planReady(destination: String) -> CelebrationEvent {
        CelebrationEvent(type: .checkIn, customLine: "Plan ready — feel local in \(destination).", symbol: "sparkles")
    }

    static func joinedPlan() -> CelebrationEvent {
        CelebrationEvent(type: .checkIn, customLine: "You're in — fly it together.", symbol: "person.2.fill")
    }

    static func kudos(from name: String, emoji: String) -> CelebrationEvent {
        CelebrationEvent(type: .checkIn, customLine: "\(emoji) \(name) sent you kudos!", symbol: "hands.clap.fill")
    }

    /// Copy is deterministic by action type so the voice stays consistent.
    var line: String {
        if let customLine { return customLine }
        return switch type {
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
            Image(systemName: event.symbol)
                .foregroundStyle(event.customLine == nil ? Color.green : Theme.accentDeep)
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
