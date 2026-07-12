import SwiftUI
import ReclockKit

/// The full plan, day by day, grouped under phase headers, with a home/destination/dual
/// time-zone switch.
struct PlanTimelineView: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    let plan: JetLagPlan

    @State private var displayMode: TimeDisplayMode = .destination
    @State private var priorityFilter: PriorityFilter = .all

    enum PriorityFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case essential = "Essentials"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.m, pinnedViews: [.sectionHeaders]) {
                    Text(plan.strategySummary)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.m)

                    Picker("Filter", selection: $priorityFilter) {
                        ForEach(PriorityFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Space.m)

                    ForEach(groupedPhases) { group in
                        Section {
                            ForEach(group.days) { entry in
                                DayBlock(
                                    day: entry.day,
                                    actions: entry.actions,
                                    displayMode: displayMode,
                                    trip: trip
                                )
                                .id(entry.day.id)
                            }
                        } header: {
                            PhaseHeader(phase: group.phase)
                        }
                    }
                }
                .padding(.bottom, Theme.Space.xl)
            }
            .onAppear {
                // Mid-trip, the reader's day is what matters — not day 0 last week.
                if let today = currentDayID {
                    proxy.scrollTo(today, anchor: .top)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Time zone", selection: $displayMode) {
                        Text("Destination time").tag(TimeDisplayMode.destination)
                        Text("Home time").tag(TimeDisplayMode.home)
                        Text("Both").tag(TimeDisplayMode.dual)
                    }
                } label: {
                    Image(systemName: "globe")
                        .accessibilityLabel("Time zone display")
                }
            }
        }
        .navigationDestination(for: PlanAction.self) { action in
            ActionDetailView(action: action, trip: trip)
        }
        .onAppear {
            displayMode = model.state.settings.timeDisplay
            model.deps.analytics.track(.timelineViewed)
        }
        .onChange(of: displayMode) { _, newValue in
            var settings = model.state.settings
            settings.timeDisplay = newValue
            Task { await model.updateSettings(settings) }
        }
    }

    private struct DayEntry: Identifiable {
        var day: PlanDay
        var actions: [PlanAction]
        var id: UUID { day.id }
    }

    private struct PhaseGroup: Identifiable {
        var phase: TripPhase
        var days: [DayEntry]
        var id: String { "\(phase.rawValue)-\(days.first?.day.index ?? 0)" }
    }

    /// The plan day containing "now" (else the first future day), for initial scroll.
    private var currentDayID: UUID? {
        let now = model.deps.now()
        let days = groupedPhases.flatMap(\.days).map(\.day)
        let current = days.last { $0.dayStart <= now && now < $0.dayStart.addingTimeInterval(36 * 3600) }
        let target = current ?? days.first { $0.dayStart > now }
        // Only jump when the target isn't already the first visible day.
        return target?.id == days.first?.id ? nil : target?.id
    }

    private var groupedPhases: [PhaseGroup] {
        var groups: [PhaseGroup] = []
        for day in plan.days.sorted(by: { $0.index < $1.index }) {
            var actions = plan.actions(onDay: day.index)
            if priorityFilter == .essential {
                actions = actions.filter { $0.priority != .optional }
            }
            if actions.isEmpty && !(day.phase == .afterArrival || day.phase == .recovery) {
                continue
            }
            let entry = DayEntry(day: day, actions: actions)
            if let lastIndex = groups.indices.last, groups[lastIndex].phase == day.phase {
                groups[lastIndex].days.append(entry)
            } else {
                groups.append(PhaseGroup(phase: day.phase, days: [entry]))
            }
        }
        return groups
    }
}

/// The reward state: a day with nothing to do because the work is done.
private struct AdjustedDayRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if reduceMotion {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.tint(for: .seekLight))
            } else {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.tint(for: .seekLight))
                    .symbolEffect(.variableColor.iterative.reversing)
            }
            Text("Fully adjusted — nothing scheduled. Enjoy the day.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PhaseHeader: View {
    let phase: TripPhase

    var body: some View {
        Text(phase.displayName)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background.opacity(0.96))
            .accessibilityAddTraits(.isHeader)
    }
}

private struct DayBlock: View {
    let day: PlanDay
    let actions: [PlanAction]
    let displayMode: TimeDisplayMode
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(day.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if abs(day.cumulativeShiftHours) > 0.1 {
                    Text(shiftLabel)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, Theme.Space.m)

            if actions.isEmpty {
                AdjustedDayRow()
                    .padding(.horizontal, Theme.Space.m)
            }

            ForEach(actions) { action in
                NavigationLink(value: action) {
                    TimelineActionRow(action: action, displayMode: displayMode, trip: trip)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    private var shiftLabel: String {
        let value = day.cumulativeShiftHours
        let formatted = String(format: "%.1f", abs(value)).replacingOccurrences(of: ".0", with: "")
        return value > 0 ? "\(formatted)h earlier" : "\(formatted)h later"
    }
}

private struct TimelineActionRow: View {
    let action: PlanAction
    let displayMode: TimeDisplayMode
    let trip: Trip

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            ActionGlyph(type: action.type, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(action.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .strikethrough(action.completion == .done)
                        .lineLimit(2)
                    Spacer()
                    PriorityBadge(priority: action.priority)
                }
                ForEach(timeLines, id: \.self) { line in
                    Text(line)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if action.completion != .pending {
                Image(systemName: action.completion == .done ? "checkmark.circle.fill" : "slash.circle")
                    .foregroundStyle(action.completion == .done ? .green : Theme.textSecondary)
                    .symbolEffect(.bounce, value: action.completion)
                    .accessibilityLabel(action.completion == .done ? "Done" : "Skipped")
            }
        }
        .padding(Theme.Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .opacity(action.completion == .pending ? 1 : 0.7)
        .accessibilityElement(children: .combine)
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
