import SwiftUI
import ReclockKit

/// The dominant "right now" card: one action, its remaining time, why it matters, and
/// one-tap responses.
struct NowCard: View {
    @Environment(AppModel.self) private var model
    let action: PlanAction
    let trip: Trip
    let now: Date

    @State private var showWhy = false

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                HeroGlyph(systemName: action.type.symbolName)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TimeFormat.countdown(to: action.window.end, from: now))
                        .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Theme.Anim.gentle, value: TimeFormat.countdown(to: action.window.end, from: now))
                    Text("left · until \(TimeFormat.time(action.window.end, zone: zone))")
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(action.title)
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(action.instruction)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            if showWhy {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(action.explanation)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.85))
                    if let alternative = action.alternative {
                        Label(alternative, systemImage: "arrow.triangle.branch")
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: Theme.Space.s) {
                Button {
                    Haptics.success()
                    Task { await model.setCompletion(.done, for: action, in: trip) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(OnGradientPrimaryButtonStyle())

                Menu {
                    Button(showWhy ? "Hide why this helps" : "Why this helps") {
                        withAnimation(Theme.Anim.spring) { showWhy.toggle() }
                    }
                    Button("Couldn't do it") {
                        Haptics.soft()
                        Task { await model.setCompletion(.notPossible, for: action, in: trip) }
                    }
                    Button("Remind me in 30 min") {
                        Haptics.soft()
                        Task { await model.snooze(action: action, in: trip) }
                    }
                    if action.type == .stayAwake || action.type == .seekLight {
                        Button("I slept instead") {
                            Task { await model.setCompletion(.sleptInstead, for: action, in: trip) }
                        }
                    }
                    if action.type == .sleep {
                        Button("I'm still awake") {
                            Task { await model.setCompletion(.notPossible, for: action, in: trip) }
                        }
                    }
                } label: {
                    Text("More")
                        .font(.headline)
                        .frame(maxWidth: 100)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color.white)
                }
                .accessibilityLabel("More options")
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.sky(for: action.type))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .shadow(color: Theme.skyColors(for: action.type).last?.opacity(0.35) ?? .clear, radius: 16, y: 6)
        )
        .accessibilityElement(children: .contain)
    }
}

/// Full-screen detail for any action (from Next list or Timeline).
struct ActionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let action: PlanAction
    let trip: Trip

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack {
                    ActionGlyph(type: action.type, size: 56)
                    Spacer()
                    PriorityBadge(priority: action.priority)
                }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(action.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(TimeFormat.range(action.window, zone: zone)) · \(TimeFormat.zoneCity(zone)) time")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(action.instruction)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Why this helps")
                    Text(action.explanation)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    if let alternative = action.alternative {
                        SectionHeader(title: "If it's not practical")
                        Text(alternative)
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note = action.adjustmentNote {
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .accessibilityHidden(true)
                        Text("Evidence: \(action.confidence.displayName)")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if action.completion == .pending {
                    Button {
                        Haptics.success()
                        Task {
                            await model.setCompletion(.done, for: action, in: trip)
                            dismiss()
                        }
                    } label: {
                        Label("Mark done", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Couldn't do it") {
                        Task {
                            await model.setCompletion(.notPossible, for: action, in: trip)
                            dismiss()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Label(
                        action.completion == .done ? "Completed" : "Marked as \(completionText)",
                        systemImage: action.completion == .done ? "checkmark.circle.fill" : "slash.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(action.completion == .done ? .green : Theme.textSecondary)

                    if action.completion != .expired {
                        Button("Undo — mark as not done yet") {
                            Task {
                                await model.setCompletion(.pending, for: action, in: trip)
                                dismiss()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.background)
        .navigationTitle("Plan step")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var completionText: String {
        switch action.completion {
        case .notPossible: "couldn't do it"
        case .skipped: "skipped"
        case .sleptInstead: "slept instead"
        case .expired: "missed"
        default: action.completion.rawValue
        }
    }
}
