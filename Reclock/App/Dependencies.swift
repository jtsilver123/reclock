import Foundation
import ReclockKit

/// Composition root. Every service the app touches is a protocol here, so tests and
/// previews can swap any piece.
struct Dependencies {
    let store: AppStatePersisting
    let engine: PlanEngine
    let coordinator: PlanCoordinator
    let validator: PlanValidator
    let notifications: NotificationScheduling
    let calendarImporter: CalendarImporting
    let sleepProvider: SleepDataProvider
    let analytics: AnalyticsClient
    let airports: AirportDirectory
    /// Flight-number schedule lookup. Unconfigured (and invisible in UI) without a key.
    let scheduleProvider: FlightScheduleProvider
    /// One-shot drive-time-to-airport estimation (MapKit). Mocked in tests/previews.
    let transitEstimator: TransitEstimating
    /// Injected clock so UI tests and previews can pin "now".
    let now: @Sendable () -> Date

    static func live() -> Dependencies {
        let configuration = PlanEngineConfiguration()
        let storeURL = (try? JSONStore.defaultURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("reclock-state.json")

        let sleepProvider: SleepDataProvider
        #if canImport(HealthKit)
        if FeatureFlags.healthKitEnabled && !ProcessInfo.isUITest {
            sleepProvider = HealthKitSleepProvider()
        } else {
            sleepProvider = UnavailableSleepDataProvider()
        }
        #else
        sleepProvider = UnavailableSleepDataProvider()
        #endif

        return Dependencies(
            store: JSONStore(fileURL: ProcessInfo.isUITest ? uiTestStoreURL() : storeURL),
            engine: PlanEngine(configuration: configuration),
            coordinator: PlanCoordinator(configuration: configuration),
            validator: PlanValidator(configuration: configuration),
            notifications: ProcessInfo.isUITest ? NoOpNotificationScheduler() : LocalNotificationScheduler(),
            calendarImporter: ProcessInfo.isUITest ? MockCalendarImporter() : EventKitCalendarImporter(),
            sleepProvider: sleepProvider,
            analytics: NoOpAnalyticsClient(),
            airports: .bundled,
            scheduleProvider: ProcessInfo.isUITest ? mockScheduleProvider() : liveScheduleProvider(),
            transitEstimator: ProcessInfo.isUITest ? MockTransitEstimator() : MapKitTransitEstimator(),
            now: { Date() }
        )
    }

    /// Reads `ReclockAeroDataBoxKey` from Info.plist (owner-configured; never committed).
    private static func liveScheduleProvider() -> FlightScheduleProvider {
        if let key = Bundle.main.object(forInfoDictionaryKey: "ReclockAeroDataBoxKey") as? String,
           !key.isEmpty {
            return AeroDataBoxScheduleProvider(apiKey: key)
        }
        return UnconfiguredFlightScheduleProvider()
    }

    private static func mockScheduleProvider() -> FlightScheduleProvider {
        let departure = Date().addingTimeInterval(4 * 86_400)
        return MockFlightScheduleProvider(results: [
            ScheduledFlight(
                airline: "AY",
                flightNumber: "AY16",
                departureAirport: "JFK",
                arrivalAirport: "HEL",
                departure: departure,
                arrival: departure.addingTimeInterval(8.33 * 3600),
                departureZone: ZoneID("America/New_York"),
                arrivalZone: ZoneID("Europe/Helsinki")
            )
        ])
    }

    /// Fully in-memory-ish dependencies for previews.
    static func preview(seed: Bool = true) -> Dependencies {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reclock-preview-\(UUID().uuidString).json")
        return Dependencies(
            store: JSONStore(fileURL: url),
            engine: PlanEngine(),
            coordinator: PlanCoordinator(),
            validator: PlanValidator(),
            notifications: NoOpNotificationScheduler(),
            calendarImporter: MockCalendarImporter(),
            sleepProvider: UnavailableSleepDataProvider(),
            analytics: NoOpAnalyticsClient(),
            airports: .bundled,
            scheduleProvider: mockScheduleProvider(),
            transitEstimator: MockTransitEstimator(),
            now: { Date() }
        )
    }

    private static func uiTestStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("reclock-uitest-\(ProcessInfo.processInfo.globallyUniqueString).json")
    }
}

extension ProcessInfo {
    static var isUITest: Bool {
        processInfo.arguments.contains("-reclock-uitest")
    }

    static var seedsDemoData: Bool {
        processInfo.arguments.contains("-reclock-seed-demo")
    }
}
