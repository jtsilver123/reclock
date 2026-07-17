import SwiftUI
import ReclockKit

// The plan, drawn the way a child reads it: the day as parallel capsule tracks
// against an hour rail. Filled capsule = do it; outlined capsule = avoid it.
// Shared by Home (today) and the Timeline (every day).

/// Which action types ride the capsule lanes (everything else is a point-in-time
/// "moment" chip). One source of truth for Home and the Timeline.
enum DayTracks {
    static let laneTypes: Set<ActionType> = [
        .seekLight, .avoidLight, .sleep, .nap, .windDown, .stayAwake,
        .caffeineOK, .caffeineCutoff, .melatoninOptional,
    ]

    /// Width of the hour-label rail. TrackModeBar (in the pinned phase header) uses
    /// the same inset so its labels sit exactly over the columns below.
    static let railWidth: CGFloat = 48

    /// One readable word per pill, so the timeline explains itself.
    static func shortLabel(for type: ActionType) -> String {
        switch type {
        case .sleep: "Sleep"
        case .nap: "Nap"
        case .windDown: "Wind down"
        case .seekLight: "Light"
        case .avoidLight: "Dim"
        case .stayAwake: "Stay up"
        case .caffeineOK: "Coffee OK"
        case .caffeineCutoff: "No coffee"
        case .melatoninOptional: "Melatonin"
        default: ""
        }
    }
}

// MARK: - Vertical pill tracks (the day as parallel capsules against an hour rail)

struct DayColumn: View {
    let actions: [PlanAction]
    let labelZone: TimeZone
    let now: Date

    var hourHeight: CGFloat = 30
    private var railWidth: CGFloat { DayTracks.railWidth }

    struct Cap: Identifiable {
        let id: String
        let action: PlanAction
        let window: TimeWindow
        let lane: Int
        let outlined: Bool
        let slashed: Bool
    }

    /// Column = the mode you're in. Stay awake holds the stimulation toolkit
    /// (light, coffee, holding out) plus its bans (dim, no coffee, slashed).
    /// Sleep holds the wind-down program (wind down, melatonin, sleep, nap).
    private static func lane(for type: ActionType) -> Int {
        switch type {
        case .sleep, .nap, .windDown, .melatoninOptional: 1
        default: 0
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
                    lane: 0,
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
                    slashed: true
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
        // The column labels live in the pinned phase header (TrackModeBar), so they
        // stay on screen while any number of days scroll past underneath.
        columnBody(totalHeight: CGFloat(totalHours) * hourHeight)
    }

    /// Same-mode pills that overlap in time share the column side-by-side;
    /// a pill alone in its hours gets the full column width.
    private struct PlacedCap: Identifiable {
        let cap: Cap
        let sub: Int
        /// How many sub-lanes THIS pill's cluster needs — width divides by this,
        /// so one busy evening never halves every lone pill all day.
        let subCount: Int
        var id: String { cap.id }
    }

    private func packed() -> [PlacedCap] {
        var placed: [PlacedCap] = []
        // A pill is drawn at least 44 pt tall, so a short window occupies more
        // vertical space than its time span. Pack against the drawn extent —
        // otherwise the next pill in the column lands on top of the overflow.
        let minVisualSpan = Double(44 / hourHeight) * 3600
        func drawnEnd(_ cap: Cap) -> Date {
            max(cap.window.end, cap.window.start.addingTimeInterval(minVisualSpan))
        }
        // Per lane, sweep by start time; a cluster is a maximal run of pills whose
        // drawn extents chain-overlap. Widths divide by the cluster's own need.
        for laneCaps in Dictionary(grouping: caps, by: \.lane).values {
            var cluster: [(cap: Cap, sub: Int)] = []
            var ends: [Date] = []
            var clusterMaxEnd = Date.distantPast
            func closeCluster() {
                guard !cluster.isEmpty else { return }
                let width = ends.count
                placed.append(contentsOf: cluster.map {
                    PlacedCap(cap: $0.cap, sub: $0.sub, subCount: width)
                })
                cluster = []
                ends = []
                clusterMaxEnd = .distantPast
            }
            for cap in laneCaps.sorted(by: { $0.window.start < $1.window.start }) {
                if cap.window.start >= clusterMaxEnd { closeCluster() }
                if let free = ends.firstIndex(where: { $0 <= cap.window.start }) {
                    ends[free] = drawnEnd(cap)
                    cluster.append((cap, free))
                } else {
                    cluster.append((cap, ends.count))
                    ends.append(drawnEnd(cap))
                }
                clusterMaxEnd = max(clusterMaxEnd, drawnEnd(cap))
            }
            closeCluster()
        }
        return placed
    }

    private func columnBody(totalHeight: CGFloat) -> some View {
        GeometryReader { geo in
            let laneWidth = (geo.size.width - railWidth) / 2
            let layout = packed()
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

                // The seam between the two modes — continues the line the pinned
                // labels start, so the columns read as columns at every scroll depth.
                Rectangle()
                    .fill(Theme.textSecondary.opacity(0.16))
                    .frame(width: 1, height: totalHeight)
                    .offset(x: railWidth + laneWidth - 0.5)

                // Capsules, packed into their mode column.
                ForEach(layout) { placed in
                    let cap = placed.cap
                    let y = max(0, cap.window.start.timeIntervalSince(domainStart) / 3600 * hourHeight)
                    let rawHeight = cap.window.duration / 3600 * hourHeight
                    let height = min(max(44, rawHeight), totalHeight - y)
                    let subWidth = laneWidth / CGFloat(placed.subCount)
                    NavigationLink(value: cap.action) {
                        TrackCapsule(cap: cap, height: height, width: subWidth - 10)
                    }
                    .buttonStyle(PressableCardStyle())
                    .offset(
                        x: railWidth + laneWidth * CGFloat(cap.lane) + subWidth * CGFloat(placed.sub) + 5,
                        y: y
                    )
                }

                // Now marker: a small sun on the rail. (Ink here was invisible in
                // dark mode — ink is spec'd for sitting on marigold, not on the
                // background.)
                let sinceStart = now.timeIntervalSince(domainStart) / 3600
                if sinceStart >= 0 && sinceStart <= Double(totalHours) {
                    let y = sinceStart * hourHeight
                    Rectangle()
                        .fill(Theme.accentDeep.opacity(0.55))
                        .frame(width: geo.size.width - railWidth, height: 1.5)
                        .offset(x: railWidth, y: y)
                    Circle()
                        .fill(Theme.background)
                        .frame(width: 13, height: 13)
                        .offset(x: railWidth - 6.5, y: y - 6)
                    Circle()
                        .fill(Theme.accent)
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

/// The two mode labels, frozen to their columns: this rides in the pinned phase
/// header, so "Stay awake | Sleep" stays on screen while the days scroll beneath.
/// Geometry mirrors DayColumn exactly — rail inset, then two equal halves.
struct TrackModeBar: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: DayTracks.railWidth, height: 1)
            Text("Stay awake")
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Theme.textSecondary.opacity(0.3))
                .frame(width: 1, height: 12)
            Text("Sleep")
                .frame(maxWidth: .infinity)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }
}

/// One pill on a track. Filled = do it; outlined (with a slash on the glyph) = avoid.
struct TrackCapsule: View {
    let cap: DayColumn.Cap
    let height: CGFloat
    let width: CGFloat

    private var tint: Color { Theme.tint(for: cap.action.type) }
    private var fill: Color { Theme.solidTint(for: cap.action.type) }
    private var done: Bool { cap.action.completion == .done }

    var body: some View {
        ZStack(alignment: .top) {
            if cap.outlined {
                Capsule()
                    .strokeBorder(tint.opacity(0.75), lineWidth: 1.5)
                    .background(Capsule().fill(tint.opacity(0.05)))
            } else {
                Capsule().fill(fill.opacity(done ? 0.5 : 0.95))
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
                if height >= 84 {
                    Text(DayTracks.shortLabel(for: cap.action.type))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(cap.outlined ? tint : Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 2)
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
        .animation(Theme.Anim.gentle, value: cap.action.completion)
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
                    .foregroundStyle(action.completion == .done ? Theme.success : Theme.textSecondary)
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
