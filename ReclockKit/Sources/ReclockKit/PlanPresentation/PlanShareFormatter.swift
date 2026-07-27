import Foundation

/// Renders a plan as compact, human-readable text for sharing ("here's when I'll be
/// asleep") — no permissions, no attachments, just words a travel partner can read.
public enum PlanShareFormatter {

    /// Storefront-neutral App Store link, so a shared plan is also a way in.
    public static let appStoreLink = "https://apps.apple.com/app/id6790334639"


    /// Essentials-only summary: must-do and helpful actions, grouped by day, times in
    /// each action's display zone. Optional items are omitted on purpose — a share
    /// should fit on one screen.
    public static func text(trip: Trip, plan: JetLagPlan) -> String {
        var lines: [String] = []
        lines.append("Reclock plan — \(trip.origin) → \(trip.destination)")
        lines.append(plan.strategySummary)
        lines.append("")

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        for day in plan.days.sorted(by: { $0.index < $1.index }) {
            let actions = plan.actions(onDay: day.index)
                .filter { $0.priority != .optional && $0.completion != .expired }
            guard !actions.isEmpty else { continue }
            lines.append(day.label)
            for action in actions {
                guard let zone = action.displayZone.timeZone else { continue }
                timeFormatter.timeZone = zone
                let start = timeFormatter.string(from: action.window.start)
                let end = timeFormatter.string(from: action.window.end)
                let city = zone.identifier.split(separator: "/").last.map {
                    $0.replacingOccurrences(of: "_", with: " ")
                } ?? zone.identifier
                let marker = action.priority == .mustDo ? "•" : "◦"
                if action.type == .caffeineCutoff {
                    lines.append("  \(marker) \(start) \(city) — \(action.title)")
                } else {
                    lines.append("  \(marker) \(start)–\(end) \(city) — \(action.title)")
                }
            }
            lines.append("")
        }
        lines.append("Made with Reclock — free jet lag plans that adapt to your trip.")
        lines.append(appStoreLink)
        return lines.joined(separator: "\n")
    }
}
