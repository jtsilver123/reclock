import SwiftUI
import ReclockKit

/// Grouping logic for the scrolling day-by-day plan on the Plan tab. The ForEach over
/// these groups lives directly in PlanContent's LazyVStack so phase headers pin.
enum PlanDays {
    struct DayEntry: Identifiable {
        var day: PlanDay
        var actions: [PlanAction]
        var id: UUID { day.id }
    }

    struct PhaseGroup: Identifiable {
        var phase: TripPhase
        var days: [DayEntry]
        var id: String { "\(phase.rawValue)-\(days.first?.day.index ?? 0)" }
    }

    static func groupedPhases(plan: JetLagPlan) -> [PhaseGroup] {
        var groups: [PhaseGroup] = []
        for day in plan.days.sorted(by: { $0.index < $1.index }) {
            let actions = plan.actions(onDay: day.index)
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

    /// The plan day containing "now" (else the first future day), for initial scroll.
    static func currentDayID(plan: JetLagPlan, now: Date) -> UUID? {
        let days = groupedPhases(plan: plan).flatMap(\.days).map(\.day)
        let current = days.last { $0.dayStart <= now && now < $0.dayStart.addingTimeInterval(36 * 3600) }
        // Future day next; for a fully-past plan, land on the most recent day.
        let target = current ?? days.first { $0.dayStart > now } ?? days.last
        // Only jump when the target isn't already the first visible day.
        return target?.id == days.first?.id ? nil : target?.id
    }

    /// Rendered days where the wall clock changes (plus the first day) — the plan
    /// announces its zone exactly when it matters and never asks the user to choose.
    static func zoneChangeDayIDs(plan: JetLagPlan) -> Set<UUID> {
        let days = groupedPhases(plan: plan).flatMap(\.days).map(\.day)
        var ids: Set<UUID> = []
        var lastZone: String?
        for day in days {
            if day.zone.identifier != lastZone {
                ids.insert(day.id)
                lastZone = day.zone.identifier
            }
        }
        return ids
    }
}

/// A quiet announcement that the plan's clock just changed ("Times now in Tokyo time").
struct ZoneMarkerRow: View {
    let zone: TimeZone
    let isFirst: Bool

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "globe")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
            Text(isFirst
                 ? "Times in \(TimeFormat.zoneCity(zone)) time"
                 : "Times now in \(TimeFormat.zoneCity(zone)) time")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.accentDeep)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 4)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .padding(.horizontal, Theme.Space.m)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// One traveler-day: label row, capsule tracks against the hour rail, moment chips.
struct PlanDayBlock: View {
    let day: PlanDay
    let actions: [PlanAction]
    let trip: Trip
    let now: Date

    private var laneActions: [PlanAction] {
        actions.filter { DayTracks.laneTypes.contains($0.type) }
    }

    private var moments: [PlanAction] {
        actions.filter { !DayTracks.laneTypes.contains($0.type) }
    }

    /// A day whose 24 hours are fully behind us reads as history, not homework.
    private var isPast: Bool {
        day.dayStart.addingTimeInterval(24 * 3600) <= now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(day.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isPast {
                    Text("Past")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceSecondary, in: Capsule())
                }
                Spacer()
                if abs(day.cumulativeShiftHours) > 0.1 {
                    Text(shiftLabel)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.35), in: Capsule())
                }
            }
            .padding(.horizontal, Theme.Space.m)

            if actions.isEmpty {
                AdjustedDayRow()
                    .padding(.horizontal, Theme.Space.m)
            }

            if !laneActions.isEmpty {
                DayColumn(
                    actions: laneActions,
                    labelZone: labelZone,
                    now: now
                )
                .padding(.horizontal, Theme.Space.m)
            }

            if !moments.isEmpty {
                MomentsRow(moments: moments, zone: labelZone)
            }
        }
        .opacity(isPast ? 0.55 : 1)
    }

    /// The zone the traveler actually occupies this day — no mode to pick.
    private var labelZone: TimeZone {
        day.zone.resolved
    }

    private var shiftLabel: String {
        let value = day.cumulativeShiftHours
        let formatted = String(format: "%.1f", abs(value)).replacingOccurrences(of: ".0", with: "")
        return value > 0 ? "bed \(formatted)h earlier" : "bed \(formatted)h later"
    }
}

/// Pinned phase banner ("Before departure", "In flight", …) for the scrolling plan.
struct PlanPhaseHeader: View {
    let phase: TripPhase

    private var symbol: String {
        switch phase {
        case .beforeDeparture: "airplane.departure"
        case .atAirport: "figure.walk.departure"
        case .inFlight: "airplane"
        case .afterArrival: "sun.max.fill"
        case .recovery: "sparkles"
        case .returnTrip: "airplane.arrival"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            Text(phase.displayName)
                .font(Theme.display(20, black: false))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .accessibilityAddTraits(.isHeader)
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
