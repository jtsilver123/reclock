import SwiftUI
import ReclockKit

/// The dominant "right now" card: one action, its remaining time, why it matters, and
/// one-tap responses.
struct NowCard: View {
    @Environment(AppModel.self) private var model
    let action: PlanAction
    let trip: Trip
    let now: Date

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top) {
                ActionGlyph(type: action.type, size: 52)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    PriorityBadge(priority: action.priority)
                    Text("\(TimeFormat.countdown(to: action.window.end, from: now)) left")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Now")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.tint(for: action.type))
                Text(action.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Until \(TimeFormat.time(action.window.end, zone: zone)) · \(TimeFormat.zoneCity(zone)) time")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(action.instruction)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(action.explanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    if let alternative = action.alternative {
                        Label(alternative, systemImage: "arrow.triangle.branch")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, Theme.Space.xs)
            } label: {
                Text("Why this helps")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: Theme.Space.s) {
                Button {
                    Haptics.success()
                    Task { await model.setCompletion(.done, for: action, in: trip) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())

                Menu {
                    Button("Couldn't do it") {
                        Task { await model.setCompletion(.notPossible, for: action, in: trip) }
                    }
                    Button("Remind me in 30 min") {
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
                        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityLabel("More options")
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(emphasized: true)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.tint(for: action.type).opacity(0.35), lineWidth: 1.5)
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
                        action.completion == .done ? "Completed" : "Marked as \(action.completion.rawValue)",
                        systemImage: action.completion == .done ? "checkmark.circle.fill" : "slash.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(action.completion == .done ? .green : Theme.textSecondary)
                }
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.background)
        .navigationTitle("Plan step")
        .navigationBarTitleDisplayMode(.inline)
    }
}
