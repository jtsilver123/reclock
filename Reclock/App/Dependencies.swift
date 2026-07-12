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
            now: { Date() }
        )
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
