import Foundation
import UserNotifications
import ReclockKit

/// Bridges `PlannedNotification`s to UNUserNotificationCenter. All scheduling decisions
/// (dedupe, quiet hours, caps) already happened in the kit's NotificationPlanner; this
/// layer only delivers and cancels.
protocol NotificationScheduling: Sendable {
    func requestPermission() async -> Bool
    func permissionGranted() async -> Bool
    func schedule(_ notifications: [PlannedNotification]) async
    func cancel(notificationIDsPrefixed prefix: String) async
    func cancelAll(forTrip tripID: UUID) async
    func cancelEverything() async
    func snooze(actionID: UUID, revision: Int, title: String, body: String, fireDate: Date) async
}

final class LocalNotificationScheduler: NotificationScheduling {

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        registerCategories(center)
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func permissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Bumped per schedule pass. A pass that has been superseded (a newer replan
    /// started rescheduling) stops adding — otherwise its tail lands AFTER the
    /// newer pass's cancel sweep and stale reminders fire alongside fresh ones.
    private var scheduleGeneration = 0

    func schedule(_ notifications: [PlannedNotification]) async {
        guard await permissionGranted() else { return }
        scheduleGeneration += 1
        let myGeneration = scheduleGeneration
        let center = UNUserNotificationCenter.current()
        registerCategories(center)

        // Never exceed the system's 64-pending limit: keep the soonest 60.
        let limited = notifications.sorted { $0.fireDate < $1.fireDate }.prefix(60)
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))

        for planned in limited where !pendingIDs.contains(planned.id) {
            guard scheduleGeneration == myGeneration else { return }
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            content.categoryIdentifier = planned.categoryID
            content.threadIdentifier = "reclock-plan"
            content.userInfo = ["actionID": planned.actionID.uuidString]
            // Requires the time-sensitive entitlement; without it the system
            // silently treats this as .active, so it degrades safely.
            content.interruptionLevel = planned.isTimeCritical ? .timeSensitive : .active

            let interval = planned.fireDate.timeIntervalSinceNow
            guard interval > 1 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancel(notificationIDsPrefixed prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAll(forTrip tripID: UUID) async {
        // Notification IDs embed action UUIDs, not trip IDs; when a trip is removed the
        // caller replaces the whole schedule, so clearing every plan notification is right.
        await cancelEverything()
    }

    func cancelEverything() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("r") || $0.hasPrefix("snooze/") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    func snooze(actionID: UUID, revision: Int, title: String, body: String, fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.planAction
        content.userInfo = ["actionID": actionID.uuidString]
        let interval = max(60, fireDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: "snooze/\(revision)/\(actionID.uuidString)/\(Int(fireDate.timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func registerCategories(_ center: UNUserNotificationCenter) {
        let done = UNNotificationAction(identifier: "RECLOCK_DONE", title: "Done", options: [])
        let snooze = UNNotificationAction(identifier: "RECLOCK_SNOOZE", title: "Snooze 30 min", options: [])
        let couldnt = UNNotificationAction(identifier: "RECLOCK_COULDNT", title: "Couldn't do it", options: [])
        let open = UNNotificationAction(identifier: "RECLOCK_OPEN", title: "Open plan", options: [.foreground])

        let actionCategory = UNNotificationCategory(
            identifier: NotificationCategory.planAction,
            actions: [done, snooze, couldnt],
            intentIdentifiers: [],
            options: []
        )
        let infoCategory = UNNotificationCategory(
            identifier: NotificationCategory.planInfo,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([actionCategory, infoCategory])
    }
}

/// For UI tests and previews.
final class NoOpNotificationScheduler: NotificationScheduling {
    func requestPermission() async -> Bool { true }
    func permissionGranted() async -> Bool { true }
    func schedule(_ notifications: [PlannedNotification]) async {}
    func cancel(notificationIDsPrefixed prefix: String) async {}
    func cancelAll(forTrip tripID: UUID) async {}
    func cancelEverything() async {}
    func snooze(actionID: UUID, revision: Int, title: String, body: String, fireDate: Date) async {}
}
