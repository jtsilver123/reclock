import SwiftUI
import ReclockKit

// MARK: - Cards

struct CardBackground: ViewModifier {
    var emphasized = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
                    .shadow(color: .black.opacity(emphasized ? 0.10 : 0.05), radius: emphasized ? 14 : 6, y: 3)
            )
    }
}

extension View {
    func card(emphasized: Bool = false) -> some View {
        modifier(CardBackground(emphasized: emphasized))
    }
}

// MARK: - Priority badge

struct PriorityBadge: View {
    let priority: ActionPriority

    var body: some View {
        Text(priority.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 3)
            .background(Theme.priorityColor(priority).opacity(0.14), in: Capsule())
            .foregroundStyle(Theme.priorityColor(priority))
            .accessibilityLabel("Priority: \(priority.displayName)")
    }
}

// MARK: - Action glyph

/// Icon + shape combination so action types are distinguishable without color alone.
struct ActionGlyph: View {
    let type: ActionType
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.tint(for: type).opacity(0.16))
            Image(systemName: type.symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Theme.tint(for: type))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Action row (timeline / next list)

struct ActionRow: View {
    let action: PlanAction
    var showsDay = false

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ActionGlyph(type: action.type)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .strikethrough(action.completion == .done)
                    Spacer()
                    PriorityBadge(priority: action.priority)
                }
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if let note = action.adjustmentNote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if action.completion == .done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Done")
            } else if action.completion == .notPossible || action.completion == .skipped {
                Image(systemName: "slash.circle")
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Skipped")
            }
        }
        .padding(Theme.Space.m)
        .card()
        .opacity(action.completion == .pending ? 1 : 0.72)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        let range = TimeFormat.range(action.window, zone: zone)
        let city = TimeFormat.zoneCity(zone)
        return showsDay
            ? "\(TimeFormat.weekdayTime(action.window.start, zone: zone)) · \(city)"
            : "\(range) · \(city)"
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    /// 0…1
    let progress: Double
    var label: String

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle()
                    .stroke(Theme.surfaceSecondary, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 54, height: 54)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int((progress * 100).rounded())) percent")
    }
}

// MARK: - Dual clock chip

struct ClockChip: View {
    let title: String
    let zone: TimeZone
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(TimeFormat.time(now, zone: zone))
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Color.white)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.textPrimary)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
