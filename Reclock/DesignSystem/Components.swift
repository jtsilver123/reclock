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

// MARK: - Action row (next list)

/// Visual-first row: big glyph, one line of words, the time as the loudest text.
struct ActionRow: View {
    let action: PlanAction
    var showsDay = false

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ActionGlyph(type: action.type, size: 46)
                .overlay(alignment: .topTrailing) {
                    if action.priority == .mustDo && action.completion == .pending {
                        Circle()
                            .fill(Theme.priorityColor(.mustDo))
                            .frame(width: 9, height: 9)
                            .offset(x: 2, y: -2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(action.completion == .done)
                    .lineLimit(1)
                Text(showsDay
                     ? TimeFormat.weekdayTime(action.window.start, zone: zone)
                     : TimeFormat.zoneCity(zone))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)
            if action.completion == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: action.completion)
                    .accessibilityLabel("Done")
            } else if action.completion == .notPossible || action.completion == .skipped {
                Image(systemName: "slash.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Skipped")
            } else {
                Text(TimeFormat.time(action.window.start, zone: zone))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.tint(for: action.type))
            }
        }
        .padding(Theme.Space.m)
        .card()
        .opacity(action.completion == .pending ? 1 : 0.72)
        .animation(Theme.Anim.gentle, value: action.completion)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(action.title), \(TimeFormat.range(action.window, zone: zone)), priority \(action.priority.displayName)")
    }
}

// MARK: - On-gradient pieces

/// Big white symbol in a translucent ring — the hero card's centerpiece.
struct HeroGlyph: View {
    let systemName: String
    var size: CGFloat = 92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.16))
            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (inhale ? 1.04 : 1))
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
            value: inhale
        )
        .onAppear { inhale = true }
        .accessibilityHidden(true)
    }
}

/// Solid white pill — the primary action on a gradient card.
struct OnGradientPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Color.black.opacity(0.82))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(Theme.Anim.springQuick, value: configuration.isPressed)
    }
}

// MARK: - Day ribbon

/// The whole day as one strip of color — sleep, light, caffeine — with a "now" marker.
/// Zero words; the hero and Tonight cards carry the specifics.
struct DayRibbon: View {
    let actions: [PlanAction]
    /// Start of the plan-day this ribbon draws (24h domain).
    let dayStart: Date
    let now: Date

    private static let ribbonTypes: Set<ActionType> = [
        .sleep, .nap, .seekLight, .avoidLight, .windDown, .stayAwake, .leaveForAirport,
    ]

    private struct Segment: Identifiable {
        let id: UUID
        let from: Double
        let to: Double
        let color: Color
        let isTick: Bool
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        for action in actions {
            let isTick = action.type == .caffeineCutoff
            guard Self.ribbonTypes.contains(action.type) || isTick else { continue }
            let from = fraction(of: action.window.start)
            let to = isTick ? from + 0.008 : fraction(of: action.window.end)
            guard to > 0, from < 1, to > from else { continue }
            result.append(Segment(
                id: action.id,
                from: max(0, from),
                to: min(1, to),
                color: Theme.tint(for: action.type),
                isTick: isTick
            ))
        }
        // Longer spans first so short moments (ticks, naps) stay visible on top.
        return result.sorted { ($0.to - $0.from) > ($1.to - $1.from) }
    }

    private func fraction(of date: Date) -> Double {
        date.timeIntervalSince(dayStart) / 86_400
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceSecondary)
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(segment.color.opacity(segment.isTick ? 1 : 0.85))
                        .frame(width: max(3, (segment.to - segment.from) * width))
                        .offset(x: segment.from * width)
                }
                let nowFraction = min(1, max(0, fraction(of: now)))
                Circle()
                    .fill(Theme.textPrimary)
                    .frame(width: 7, height: 7)
                    .background(Circle().fill(Theme.background).frame(width: 13, height: 13))
                    .offset(x: nowFraction * width - 3.5)
                    .animation(Theme.Anim.gentle, value: nowFraction)
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let parts = actions
            .filter { Self.ribbonTypes.contains($0.type) || $0.type == .caffeineCutoff }
            .sorted { $0.window.start < $1.window.start }
            .map { "\($0.title) \(TimeFormat.time($0.window.start, zone: $0.displayZone.resolved))" }
        return parts.isEmpty ? "No scheduled windows today" : "Today: " + parts.joined(separator: ", ")
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
                    .animation(Theme.Anim.spring, value: progress)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.gentle, value: progress)
            }
            .frame(width: 54, height: 54)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
                .animation(Theme.Anim.gentle, value: label)
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
                .contentTransition(.numericText())
                .animation(Theme.Anim.gentle, value: TimeFormat.time(now, zone: zone))
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
            .foregroundStyle(Theme.ink)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(Theme.Anim.springQuick, value: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(Theme.Anim.springQuick, value: configuration.isPressed)
    }
}

/// A symbol that gently breathes — the app's welcome heartbeat. Respects Reduce Motion.
struct BreathingSymbol: View {
    let systemName: String
    var size: CGFloat = 56
    var tint: Color = Theme.tint(for: .seekLight)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundStyle(tint)
            .scaleEffect(reduceMotion ? 1 : (inhale ? 1.05 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                value: inhale
            )
            .onAppear { inhale = true }
            .accessibilityHidden(true)
    }
}

// MARK: - How it works

/// The whole product in three glyphs and nine words.
struct HowItWorksRow: View {
    private struct Step: Identifiable {
        let id: Int
        let symbol: String
        let label: String
        let tint: Color
    }

    private var steps: [Step] {
        [
            Step(id: 0, symbol: "airplane", label: "Add a flight", tint: Theme.accent),
            Step(id: 1, symbol: "sun.max.fill", label: "Get your plan", tint: Theme.tint(for: .seekLight)),
            Step(id: 2, symbol: "bell.badge.fill", label: "Follow the nudges", tint: Theme.tint(for: .sleep)),
        ]
    }

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(steps) { step in
                if step.id > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        .accessibilityHidden(true)
                }
                VStack(spacing: Theme.Space.s) {
                    ZStack {
                        Circle().fill(step.tint.opacity(0.15))
                        Image(systemName: step.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(step.tint)
                    }
                    .frame(width: 52, height: 52)
                    Text(step.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How it works: add a flight, get your plan, follow the nudges")
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
