import SwiftUI
import ReclockKit

/// The frozen top of the Plan tab: which trip, how far the body clock has come, and
/// the one step that matters right now. Everything below it scrolls; this doesn't.
struct PlanPinnedHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trip: Trip
    let plan: JetLagPlan
    let context: AppModel.NowContext
    let now: Date
    /// When today is on this plan, tapping the now bar rides back to it.
    var onTapNow: (() -> Void)? = nil

    private var heroTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.originName(for: trip)) → \(trip.destination)")
                        .font(Theme.display(18))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !context.dayLabel.isEmpty {
                        Text(context.dayLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: Theme.Space.s)
            }

            // What time it is for the traveler, right now — the device's zone travels
            // with them — plus the destination clock until the two agree. When today
            // is on the plan, the bar doubles as the way back to it.
            if let onTapNow {
                Button {
                    Haptics.soft()
                    onTapNow()
                } label: {
                    NowBar(now: now, destinationZone: trip.destinationZone.resolved)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityHint("Scrolls the plan to now")
            } else {
                NowBar(now: now, destinationZone: trip.destinationZone.resolved)
            }

            // The body clock's journey between the two cities, plane included.
            ShiftProgressLine(progress: context.progress, label: shiftLabel)

            // The hero swaps with a spring: completed steps lift away, the next settles in.
            Group {
                if let current = context.current.first {
                    CompactNowCard(action: current, trip: trip, now: now)
                        .id(current.id)
                        .transition(heroTransition)
                } else {
                    CompactQuietCard(next: context.next.first, now: now)
                        .transition(heroTransition)
                }
            }
            .animation(Theme.Anim.spring, value: context.current.first?.id)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.s)
        .background {
            ZStack {
                Theme.background
                AmbientHorizon(zone: trip.destinationZone.resolved, now: now)
            }
        }
        .overlay(alignment: .bottom) {
            // Content scrolling past reads as sliding under the frozen block.
            LinearGradient(
                colors: [Color.black.opacity(0.12), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 5)
            .offset(y: 5)
            .allowsHitTesting(false)
        }
    }

    private var shiftLabel: String {
        let total = abs(plan.requiredShiftHours)
        guard total > 0.5 else { return "Adjusted" }
        let done = min(total, context.progress * total)
        let doneText = done == done.rounded()
            ? String(Int(done)) : String(format: "%.1f", done)
        return "\(doneText) of \(Int(total.rounded()))h shifted"
    }
}

/// The now bar: the time where the traveler is standing (the device's zone follows
/// them — Tromsø before the flight, Chicago after landing), live to the half-minute,
/// with the destination's clock alongside until the two read the same.
private struct NowBar: View {
    let now: Date
    let destinationZone: TimeZone

    private var hereZone: TimeZone { .current }
    private var clocksAgree: Bool {
        hereZone.secondsFromGMT(for: now) == destinationZone.secondsFromGMT(for: now)
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            // The same "the sun marks now" dot the timeline uses.
            Circle()
                .fill(Theme.accent)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(TimeFormat.time(now, zone: hereZone))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(clocksAgree ? "in \(TimeFormat.zoneCity(destinationZone)) — where you are" : "where you are")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Theme.Space.s)
            if !clocksAgree {
                Text(TimeFormat.time(now, zone: destinationZone))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.accentDeep)
                    .contentTransition(.numericText())
                Text("in \(TimeFormat.zoneCity(destinationZone))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 7)
        .background(Theme.surfaceSecondary.opacity(0.7), in: Capsule())
        .animation(Theme.Anim.gentle, value: clocksAgree)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let here = "It's \(TimeFormat.time(now, zone: hereZone)) where you are"
        return clocksAgree
            ? "\(here), in \(TimeFormat.zoneCity(destinationZone))."
            : "\(here). \(TimeFormat.time(now, zone: destinationZone)) in \(TimeFormat.zoneCity(destinationZone))."
    }
}

/// A thin track with a plane riding the body-clock progress between origin and destination.
private struct ShiftProgressLine: View {
    let progress: Double
    let label: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = min(1, max(0, progress)) * max(0, width - 16)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceSecondary)
                        .frame(height: 4)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: x + 4, height: 4)
                    Image(systemName: "airplane")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .offset(x: x)
                        .animation(Theme.Anim.spring, value: x)
                }
            }
            .frame(height: 16)
            Text(label)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body clock \(label)")
    }
}

// MARK: - Compact hero cards

/// The current step, always on screen: glyph, title, countdown — and one-tap Done.
/// Tapping the card opens the full story (why, alternatives, more options).
struct CompactNowCard: View {
    @Environment(AppModel.self) private var model
    let action: PlanAction
    let trip: Trip
    let now: Date

    private var zone: TimeZone { action.displayZone.resolved }

    var body: some View {
        NavigationLink(value: action) {
            HStack(spacing: Theme.Space.m) {
                HeroGlyph(systemName: action.type.symbolName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(Theme.display(19))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text("\(TimeFormat.countdown(to: action.window.end, from: now)) left · until \(TimeFormat.time(action.window.end, zone: zone))")
                        .font(.footnote.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.8))
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Theme.Anim.gentle, value: TimeFormat.countdown(to: action.window.end, from: now))
                }
                Spacer(minLength: 44 + Theme.Space.m)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.sky(for: action.type))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Color.black.opacity(0.08))
                    )
                    .shadow(color: Theme.skyColors(for: action.type).last?.opacity(0.35) ?? .clear, radius: 12, y: 5)
            )
            .grain()
            .livingSky()
        }
        .buttonStyle(PressableCardStyle())
        .overlay(alignment: .trailing) {
            Button {
                Haptics.success()
                Task { await model.setCompletion(.done, for: action, in: trip) }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.22), in: Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("Done")
            .padding(.trailing, Theme.Space.m)
        }
        .contextMenu {
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
                    Haptics.soft()
                    Task { await model.setCompletion(.sleptInstead, for: action, in: trip) }
                }
            }
            if action.type == .sleep {
                Button("I'm still awake") {
                    Haptics.soft()
                    Task { await model.setCompletion(.notPossible, for: action, in: trip) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Between steps: a calm card that says so, with the next step a glance (and a tap) away.
struct CompactQuietCard: View {
    let next: PlanAction?
    let now: Date

    var body: some View {
        if let next {
            NavigationLink(value: next) {
                quietBody(next: next)
            }
            .buttonStyle(PressableCardStyle())
        } else {
            quietBody(next: nil)
        }
    }

    private func quietBody(next: PlanAction?) -> some View {
        // A ticking countdown only earns its width inside a day; beyond that the
        // subtitle carries the when and the title keeps the whole line.
        let isSoon = next.map { $0.window.start.timeIntervalSince(now) < 24 * 3600 } ?? false
        return HStack(spacing: Theme.Space.m) {
            HeroGlyph(systemName: next == nil ? "checkmark.seal.fill" : "moon.stars.fill", size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing to do right now")
                    .font(Theme.display(19))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let next {
                    let zone = next.displayZone.resolved
                    Text(isSoon
                         ? "Next: \(next.title)"
                         : "Next: \(next.title) · \(TimeFormat.dayDate(next.window.start, zone: zone)), \(TimeFormat.time(next.window.start, zone: zone))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(2)
                } else {
                    Text("You're through the plan. Enjoy the trip.")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let next, isSoon {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TimeFormat.countdown(to: next.window.start, from: now))
                        .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Theme.Anim.gentle, value: TimeFormat.countdown(to: next.window.start, from: now))
                    Text("at \(TimeFormat.time(next.window.start, zone: next.displayZone.resolved))")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .layoutPriority(1)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.quietSky)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
        )
        .grain()
        .livingSky()
        .accessibilityElement(children: .combine)
    }
}
