import SwiftUI
import ReclockKit

// The plan, drawn the way a child reads it: the day as parallel capsule tracks
// against an hour rail. Filled capsule = do it; outlined capsule = avoid it.
// Shared by Home (today) and the Timeline (every day).

/// Which action types ride the capsule lanes (everything else is a point-in-time
/// "moment" chip). One source of truth for Home and the Timeline.
enum DayTracks {
    static let laneTypes: Set<ActionType> = [
        .seekLight, .avoidLight, .sleep, .nap, .windDown, .stayAwake, .caffeineOK, .caffeineCutoff,
    ]
}

// MARK: - Vertical pill tracks (the day as parallel capsules against an hour rail)

struct DayColumn: View {
    let actions: [PlanAction]
    let labelZone: TimeZone
    let now: Date

    var hourHeight: CGFloat = 30
    private let railWidth: CGFloat = 48

    struct Cap: Identifiable {
        let id: String
        let action: PlanAction
        let window: TimeWindow
        let lane: Int
        let outlined: Bool
        let slashed: Bool
    }

    private static func lane(for type: ActionType) -> Int {
        switch type {
        case .seekLight, .avoidLight: 0
        case .sleep, .nap, .windDown, .stayAwake: 1
        default: 2
        }
    }

    /// Capsules: every lane action as drawn, plus the synthesized "no coffee from the
    /// cutoff until sleep" stretch — filled means do, outlined means avoid.
    private var caps: [Cap] {
        var result: [Cap] = []
        let sleepStarts = actions
            .filter { $0.type == .sleep }
            .map(\.window.start)
        for action in actions {
            switch action.type {
            case .caffeineCutoff:
                let end = sleepStarts.filter { $0 > action.window.start }.min()
                    ?? action.window.start.addingTimeInterval(5 * 3600)
                result.append(Cap(
                    id: action.id.uuidString + "/nocoffee",
                    action: action,
                    window: TimeWindow(start: action.window.start, end: end),
                    lane: 2,
                    outlined: true,
                    slashed: true
                ))
            case .avoidLight:
                result.append(Cap(
                    id: action.id.uuidString,
                    action: action,
                    window: action.window,
                    lane: 0,
                    outlined: true,
                    slashed: false
                ))
            default:
                result.append(Cap(
                    id: action.id.uuidString,
                    action: action,
                    window: action.window,
                    lane: Self.lane(for: action.type),
                    outlined: false,
                    slashed: false
                ))
            }
        }
        return result
    }

    private var domainStart: Date {
        let earliest = caps.map(\.window.start).min() ?? now
        // Floor to the hour in the label zone so rail labels sit on real hours.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = labelZone
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: earliest)
        return cal.date(from: comps) ?? earliest
    }

    private var totalHours: Int {
        let latest = caps.map(\.window.end).max() ?? domainStart.addingTimeInterval(3600)
        let hours = latest.timeIntervalSince(domainStart) / 3600
        return max(2, Int(hours.rounded(.up)))
    }

    var body: some View {
        let totalHeight = CGFloat(totalHours) * hourHeight
        GeometryReader { geo in
            let laneWidth = (geo.size.width - railWidth) / 3
            ZStack(alignment: .topLeading) {
                // Hour rail + hairlines.
                ForEach(Array(stride(from: 0, through: totalHours, by: 2)), id: \.self) { hour in
                    let y = CGFloat(hour) * hourHeight
                    Rectangle()
                        .fill(Theme.textSecondary.opacity(0.12))
                        .frame(width: geo.size.width - railWidth, height: 1)
                        .offset(x: railWidth, y: y)
                    Text(hourLabel(domainStart.addingTimeInterval(Double(hour) * 3600)))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: railWidth - 8, alignment: .leading)
                        .offset(x: 0, y: y - 7)
                }

                // Capsules.
                ForEach(caps) { cap in
                    let y = max(0, cap.window.start.timeIntervalSince(domainStart) / 3600 * hourHeight)
                    let rawHeight = cap.window.duration / 3600 * hourHeight
                    let height = min(max(34, rawHeight), totalHeight - y)
                    NavigationLink(value: cap.action) {
                        TrackCapsule(cap: cap, height: height, width: laneWidth - 10)
                    }
                    .buttonStyle(PressableCardStyle())
                    .offset(x: railWidth + laneWidth * CGFloat(cap.lane) + 5, y: y)
                }

                // Now marker.
                let sinceStart = now.timeIntervalSince(domainStart) / 3600
                if sinceStart >= 0 && sinceStart <= Double(totalHours) {
                    let y = sinceStart * hourHeight
                    Rectangle()
                        .fill(Theme.ink.opacity(0.45))
                        .frame(width: geo.size.width - railWidth, height: 1.5)
                        .offset(x: railWidth, y: y)
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 7, height: 7)
                        .offset(x: railWidth - 3.5, y: y - 3)
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement(children: .contain)
    }

    private func hourLabel(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted)
            .hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = labelZone
        return date.formatted(style).lowercased()
    }
}

/// One pill on a track. Filled = do it; outlined (with a slash on the glyph) = avoid.
struct TrackCapsule: View {
    let cap: DayColumn.Cap
    let height: CGFloat
    let width: CGFloat

    private var tint: Color { Theme.tint(for: cap.action.type) }
    private var done: Bool { cap.action.completion == .done }

    var body: some View {
        ZStack(alignment: .top) {
            if cap.outlined {
                Capsule()
                    .strokeBorder(tint.opacity(0.75), lineWidth: 1.5)
                    .background(Capsule().fill(tint.opacity(0.05)))
            } else {
                Capsule().fill(tint.opacity(done ? 0.45 : 0.9))
            }
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(cap.outlined ? tint.opacity(0.12) : Color.white.opacity(0.25))
                        .frame(width: 26, height: 26)
                    Image(systemName: cap.action.type.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(cap.outlined ? tint : Color.white)
                    if cap.slashed {
                        Image(systemName: "line.diagonal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(tint)
                    }
                }
                if height >= 64 {
                    Text(durationText)
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(cap.outlined ? Theme.textSecondary : Color.white.opacity(0.9))
                }
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(cap.outlined ? tint : Color.white)
                }
            }
            .padding(.top, 6)
        }
        .frame(width: width, height: height)
        .accessibilityLabel("\(cap.action.title), \(TimeFormat.range(cap.window, zone: cap.action.displayZone.resolved))")
    }

    private var durationText: String {
        let hours = cap.window.duration / 3600
        if hours >= 1.75 {
            return "\(Int(hours.rounded())) h"
        }
        return "\(Int((cap.window.duration / 60).rounded())) m"
    }
}

/// The day's point-in-time steps (leave for the airport, switch your watch, melatonin…)
/// as a row of tappable circles.
struct MomentsRow: View {
    let moments: [PlanAction]
    let zone: TimeZone

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.m) {
                ForEach(moments.sorted { $0.window.start < $1.window.start }) { action in
                    NavigationLink(value: action) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(Theme.tint(for: action.type).opacity(0.15))
                                Image(systemName: action.type.symbolName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.tint(for: action.type))
                            }
                            .frame(width: 46, height: 46)
                            Text(TimeFormat.time(action.window.start, zone: zone))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("\(action.title) at \(TimeFormat.time(action.window.start, zone: zone))")
                }
            }
            .padding(.horizontal, Theme.Space.m)
        }
    }
}

private struct TimelineActionRow: View {
    let action: PlanAction
    let displayMode: TimeDisplayMode
    let trip: Trip

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            ActionGlyph(type: action.type, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .strikethrough(action.completion == .done)
                    .lineLimit(1)
                ForEach(timeLines, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Theme.Space.s)
            if action.completion != .pending {
                Image(systemName: action.completion == .done ? "checkmark.circle.fill" : "slash.circle")
                    .font(.title3)
                    .foregroundStyle(action.completion == .done ? .green : Theme.textSecondary)
                    .symbolEffect(.bounce, value: action.completion)
                    .accessibilityLabel(action.completion == .done ? "Done" : "Skipped")
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TimeFormat.time(action.window.start, zone: displayZone))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.tint(for: action.type))
                    if action.priority == .mustDo {
                        Circle()
                            .fill(Theme.priorityColor(.mustDo))
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Must do")
                    }
                }
            }
        }
        .padding(Theme.Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .opacity(action.completion == .pending ? 1 : 0.7)
        .accessibilityElement(children: .combine)
    }

    private var displayZone: TimeZone {
        displayMode == .home ? trip.homeZone.resolved : action.displayZone.resolved
    }

    private var timeLines: [String] {
        let actionZone = action.displayZone.resolved
        let homeZone = trip.homeZone.resolved
        switch displayMode {
        case .destination:
            return ["\(TimeFormat.range(action.window, zone: actionZone)) · \(TimeFormat.zoneCity(actionZone))"]
        case .home:
            return ["\(TimeFormat.range(action.window, zone: homeZone)) · \(TimeFormat.zoneCity(homeZone)) (home)"]
        case .dual:
            var lines = ["\(TimeFormat.range(action.window, zone: actionZone)) · \(TimeFormat.zoneCity(actionZone))"]
            if actionZone.identifier != homeZone.identifier {
                lines.append("\(TimeFormat.range(action.window, zone: homeZone)) · home")
            }
            return lines
        }
    }
}
