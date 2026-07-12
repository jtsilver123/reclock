import Foundation
import EventKit
import ReclockKit

/// Calendar import happens in three explicit steps the user can see:
/// 1. request access (only after the user taps "Import from Calendar")
/// 2. scan upcoming events on-device and show what was detected
/// 3. import only the flights the user confirms
/// Nothing from the calendar is stored except confirmed flight fields.
protocol CalendarImporting: Sendable {
    func accessStatus() async -> CalendarAccessStatus
    func requestAccess() async -> Bool
    /// Detected flights in the next `days` days. Empty when access is missing.
    func detectFlights(daysAhead: Int) async -> [DetectedFlight]
}

enum CalendarAccessStatus: Sendable {
    case notDetermined
    case granted
    case denied
}

final class EventKitCalendarImporter: CalendarImporting {
    private let store = EKEventStore()

    func accessStatus() async -> CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    func detectFlights(daysAhead: Int = 180) async -> [DetectedFlight] {
        guard await accessStatus() == .granted else { return [] }
        let start = Date()
        let end = start.addingTimeInterval(Double(daysAhead) * 86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        // Map to the neutral struct immediately; EKEvent never leaves this function.
        let snapshots: [CalendarEventData] = events.compactMap { event in
            guard !event.isAllDay, let eventStart = event.startDate, let eventEnd = event.endDate else {
                return nil
            }
            return CalendarEventData(
                title: event.title ?? "",
                location: event.location,
                notes: event.notes,
                start: eventStart,
                end: eventEnd,
                timeZoneIdentifier: event.timeZone?.identifier
            )
        }
        return FlightEventParser().detectFlights(in: snapshots)
    }
}

/// Deterministic importer for previews and UI tests.
final class MockCalendarImporter: CalendarImporting {
    func accessStatus() async -> CalendarAccessStatus { .granted }
    func requestAccess() async -> Bool { true }

    func detectFlights(daysAhead: Int) async -> [DetectedFlight] {
        let reference = Date().addingTimeInterval(3 * 86_400)
        return [
            DetectedFlight(
                airlineCode: "AY",
                flightNumber: "AY16",
                departureAirport: "JFK",
                arrivalAirport: "HEL",
                departure: reference,
                arrival: reference.addingTimeInterval(8.3 * 3600),
                departureZone: ZoneID("America/New_York"),
                arrivalZone: ZoneID("Europe/Helsinki"),
                confidence: .high,
                sourceTitle: "AY 16 · JFK → HEL"
            )
        ]
    }
}
