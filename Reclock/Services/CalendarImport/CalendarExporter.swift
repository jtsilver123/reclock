import Foundation
// EventKit predates Sendable annotations; EKEventStore is documented thread-safe.
@preconcurrency import EventKit
import ReclockKit

/// Writes the plan's key moments into the user's calendar as quiet events — marked
/// Free, no alarms (Reclock's own reminders handle timing). Every event carries a
/// `reclock://trip/…` link back to its plan. Re-exporting replaces the events written
/// last time instead of duplicating them, and everything the app ever wrote can be
/// removed again, per trip or wholesale.
protocol CalendarExporting: Sendable {
    /// Writable calendars the user could export into. Empty when access is denied.
    func writableCalendars() async -> [ExportCalendar]
    /// Replaces any previously exported events for this trip. Returns the number of
    /// events written, or nil when calendar access is denied/unavailable.
    func export(_ requests: [CalendarEventRequest], tripID: UUID, calendarID: String?) async -> Int?
    /// Removes every event this app wrote for the trip. Returns the number removed,
    /// or nil when calendar access is denied/unavailable.
    func removeAll(tripID: UUID) async -> Int?
    /// Removes every event this app ever wrote, across all trips.
    func removeEverything() async -> Int?
}

struct ExportCalendar: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var isDefault: Bool
}

struct CalendarEventRequest: Sendable {
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var zoneIdentifier: String
    /// Deep link back into the app (shown as the event's URL field).
    var url: URL?
}

final class EventKitCalendarExporter: CalendarExporting {
    private let store = EKEventStore()
    private static let markerPrefix = "calendarExport."
    private static func markerKey(_ tripID: UUID) -> String { markerPrefix + tripID.uuidString }

    private func ensureAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return true
        case .notDetermined: return (try? await store.requestFullAccessToEvents()) ?? false
        default: return false
        }
    }

    func writableCalendars() async -> [ExportCalendar] {
        guard await ensureAccess() else { return [] }
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map {
                ExportCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    isDefault: $0.calendarIdentifier == defaultID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func export(_ requests: [CalendarEventRequest], tripID: UUID, calendarID: String?) async -> Int? {
        guard await ensureAccess() else { return nil }
        let calendar = calendarID.flatMap { store.calendar(withIdentifier: $0) }
            ?? store.defaultCalendarForNewEvents
        guard let calendar else { return nil }

        // Replace, don't duplicate: remove whatever we wrote for this trip last time.
        removeStoredEvents(tripID: tripID, commit: false)

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
            event.url = request.url
            do {
                try store.save(event, span: .thisEvent, commit: false)
                if let id = event.eventIdentifier { written.append(id) }
            } catch { continue }
        }
        do { try store.commit() } catch { return nil }

        UserDefaults.standard.set(written, forKey: Self.markerKey(tripID))
        return written.count
    }

    func removeAll(tripID: UUID) async -> Int? {
        guard await ensureAccess() else { return nil }
        let removed = removeStoredEvents(tripID: tripID, commit: true)
        UserDefaults.standard.removeObject(forKey: Self.markerKey(tripID))
        return removed
    }

    func removeEverything() async -> Int? {
        guard await ensureAccess() else { return nil }
        let defaults = UserDefaults.standard
        var total = 0
        // Prefix scan, not a registry: also catches exports written by older builds
        // (and survives any bookkeeping drift) — the marker keys ARE the registry.
        let keys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(Self.markerPrefix)
        }
        for key in keys {
            guard let id = UUID(uuidString: String(key.dropFirst(Self.markerPrefix.count))) else { continue }
            total += removeStoredEvents(tripID: id, commit: false)
            defaults.removeObject(forKey: key)
        }
        try? store.commit()
        return total
    }

    /// Deletes the identifiers recorded for a trip. Returns how many still existed.
    @discardableResult
    private func removeStoredEvents(tripID: UUID, commit: Bool) -> Int {
        let key = Self.markerKey(tripID)
        var removed = 0
        for identifier in UserDefaults.standard.stringArray(forKey: key) ?? [] {
            if let old = store.event(withIdentifier: identifier) {
                try? store.remove(old, span: .thisEvent, commit: false)
                removed += 1
            }
        }
        if commit { try? store.commit() }
        return removed
    }
}

/// Deterministic exporter for previews and UI tests: pretends everything worked.
final class MockCalendarExporter: CalendarExporting {
    func writableCalendars() async -> [ExportCalendar] {
        [ExportCalendar(id: "mock", title: "Calendar", isDefault: true)]
    }

    func export(_ requests: [CalendarEventRequest], tripID: UUID, calendarID: String?) async -> Int? {
        requests.count
    }

    func removeAll(tripID: UUID) async -> Int? { 0 }
    func removeEverything() async -> Int? { 0 }
}

// MARK: - Building requests from a plan

enum PlanCalendarEvents {
    /// The essentials, as a traveler would want them on a calendar: every non-optional
    /// step still ahead, titled with a glanceable emoji, quiet by design — each linking
    /// straight back to its plan in the app.
    static func requests(trip: Trip, plan: JetLagPlan, now: Date) -> [CalendarEventRequest] {
        let link = AppLinks.tripURL(trip.id)
        return plan.actions
            .filter { $0.priority != .optional && $0.completion == .pending && $0.window.end > now }
            .sorted { $0.window.start < $1.window.start }
            .map { action in
                CalendarEventRequest(
                    title: "\(emoji(for: action.type)) \(action.title)",
                    notes: action.instruction
                        + "\n\nFrom your Reclock plan · \(trip.origin) → \(trip.destination)"
                        + "\nOpen the plan: \(link.absoluteString)",
                    start: action.window.start,
                    end: action.window.end,
                    zoneIdentifier: action.displayZone.resolved.identifier,
                    url: link
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
