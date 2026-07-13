import SwiftUI
import ReclockKit

/// Full-screen detail for any action (from the pinned hero or any day in the plan).
struct ActionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let action: PlanAction
    let trip: Trip

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                // The action's sky, full bleed: glyph, title, window — zero chrome.
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        HeroGlyph(systemName: action.type.symbolName, size: 72)
                        Spacer()
                        if action.priority == .mustDo {
                            Text("MUST DO")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.22), in: Capsule())
                        }
                    }
                    Text(action.title)
                        .font(Theme.display(30))
                        .foregroundStyle(Color.white)
                    Text("\(TimeFormat.range(action.window, zone: zone)) · \(TimeFormat.zoneCity(zone)) time")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.sky(for: action.type))
                )
                .grain()
                .livingSky()

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
