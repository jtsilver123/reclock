import Foundation
import UserNotifications
import UIKit
import ReclockKit

/// Routes notification action taps (Done / Snooze / Couldn't do it) back into the model.
/// Set as the UNUserNotificationCenter delegate at launch.
@MainActor
final class NotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel? {
        didSet {
            // A tap that cold-launched the app arrived before RootView could hand
            // us the model — replay it now instead of silently dropping it.
            if model != nil, let queued = pending {
                pending = nil
                Task { await handle(actionID: queued.actionID, actionIdentifier: queued.identifier) }
            }
        }
    }

    private var pending: (actionID: UUID, identifier: String)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let actionIDString = response.notification.request.content.userInfo["actionID"] as? String,
            let actionID = UUID(uuidString: actionIDString)
        else { return }
        guard model != nil else {
            pending = (actionID, response.actionIdentifier)
            return
        }
        await handle(actionID: actionID, actionIdentifier: response.actionIdentifier)
    }

    private func handle(actionID: UUID, actionIdentifier: String) async {
        guard let model else { return }
        // Wait out a cold launch: the store may still be loading when the tap lands.
        for _ in 0..<50 where !model.isLoaded {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // The notification names its action, not a trip — search every plan, not just
        // the active one, so acting on another trip's reminder isn't a silent no-op.
        guard let (trip, action) = findAction(actionID, in: model) else { return }

        switch actionIdentifier {
        case "RECLOCK_DONE":
            await model.setCompletion(.done, for: action, in: trip)
        case "RECLOCK_SNOOZE":
            await model.snooze(action: action, in: trip)
        case "RECLOCK_COULDNT":
            await model.setCompletion(.notPossible, for: action, in: trip)
        default:
            // A body tap means "show me": open the exact step the reminder named.
            model.openActionDetail(actionID: action.id)
        }
    }

    private func findAction(_ id: UUID, in model: AppModel) -> (Trip, PlanAction)? {
        for trip in model.state.trips {
            if let action = model.plan(for: trip)?.actions.first(where: { $0.id == id }) {
                return (trip, action)
            }
        }
        return nil
    }
}

/// Minimal app delegate: installs the notification delegate before any notification can
/// be delivered to a cold-launched app.
final class ReclockAppDelegate: NSObject, UIApplicationDelegate {
    let notificationHandler = NotificationResponseHandler()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationHandler
        return true
    }
}
