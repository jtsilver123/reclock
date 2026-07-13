import Foundation
// EventKit predates Sendable annotations; EKEventStore is documented thread-safe.
@preconcurrency import EventKit
import ReclockKit

/// Writes the plan's key moments into the user's calendar as quiet events — marked
/// Free, no alarms (Reclock's own reminders handle timing). Uses the same on-device
/// full access the flight importer asks for. Re-exporting replaces the events written
/// last time instead of duplicating them.
protocol CalendarExporting: Sendable {
    /// Replaces any previously exported events for this trip. Returns the number of
    /// events written, or nil when calendar access is denied/unavailable.
    func export(_ requests: [CalendarEventRequest], tripID: UUID) async -> Int?
}

struct CalendarEventRequest: Sendable {
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var zoneIdentifier: String
}

final class EventKitCalendarExporter: CalendarExporting {
    private let store = EKEventStore()
    private static func markerKey(_ tripID: UUID) -> String { "calendarExport.\(tripID.uuidString)" }

    func export(_ requests: [CalendarEventRequest], tripID: UUID) async -> Int? {
        let granted: Bool
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: granted = true
        case .notDetermined: granted = (try? await store.requestFullAccessToEvents()) ?? false
        default: granted = false
        }
        guard granted, let calendar = store.defaultCalendarForNewEvents else { return nil }

        // Replace, don't duplicate: remove whatever we wrote for this trip last time.
        let defaults = UserDefaults.standard
        let key = Self.markerKey(tripID)
        for identifier in defaults.stringArray(forKey: key) ?? [] {
            if let old = store.event(withIdentifier: identifier) {
                try? store.remove(old, span: .thisEvent, commit: false)
            }
        }

        var written: [String] = []
        for request in requests {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = request.title
            event.notes = request.notes
            event.startDate = request.start
            event.endDate = request.end
            event.timeZone = TimeZone(identifier: request.zoneIdentifier)
            event.availability = .free
            do {
                try store.save(event, span: .thisEvent, commit: false)
                if let id = event.eventIdentifier { written.append(id) }
            } catch { continue }
        }
        do { try store.commit() } catch { return nil }
        defaults.set(written, forKey: key)
        return written.count
    }
}

/// Deterministic exporter for previews and UI tests: pretends everything worked.
final class MockCalendarExporter: CalendarExporting {
    func export(_ requests: [CalendarEventRequest], tripID: UUID) async -> Int? {
        requests.count
    }
}

// MARK: - Building requests from a plan

enum PlanCalendarEvents {
    /// The essentials, as a traveler would want them on a calendar: every non-optional
    /// step still ahead, titled with a glanceable emoji, quiet by design.
    static func requests(trip: Trip, plan: JetLagPlan, now: Date) -> [CalendarEventRequest] {
        plan.actions
            .filter { $0.priority != .optional && $0.completion == .pending && $0.window.end > now }
            .sorted { $0.window.start < $1.window.start }
            .map { action in
                CalendarEventRequest(
                    title: "\(emoji(for: action.type)) \(action.title)",
                    notes: action.instruction
                        + "\n\nFrom your Reclock plan · \(trip.origin) → \(trip.destination)",
                    start: action.window.start,
                    end: action.window.end,
                    zoneIdentifier: action.displayZone.resolved.identifier
                )
            }
    }

    private static func emoji(for type: ActionType) -> String {
        switch type {
        case .sleep: "🛏"
        case .nap: "😴"
        case .windDown: "🌙"
        case .seekLight: "☀️"
        case .avoidLight: "🕶"
        case .stayAwake: "⚡️"
        case .caffeineOK, .caffeineCutoff: "☕️"
        case .melatoninOptional: "💊"
        case .leaveForAirport: "🧳"
        default: "🌤"
        }
    }
}
