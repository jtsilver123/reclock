import Foundation
import UserNotifications
import UIKit
import ReclockKit

/// Routes notification action taps (Done / Snooze / Couldn't do it) back into the model.
/// Set as the UNUserNotificationCenter delegate at launch.
@MainActor
final class NotificationResponseHandler: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

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
            let model,
            let actionIDString = response.notification.request.content.userInfo["actionID"] as? String,
            let actionID = UUID(uuidString: actionIDString)
        else { return }

        guard
            let trip = model.activeTrip,
            let plan = model.plan(for: trip),
            let action = plan.actions.first(where: { $0.id == actionID })
        else { return }

        switch response.actionIdentifier {
        case "RECLOCK_DONE":
            await model.setCompletion(.done, for: action, in: trip)
        case "RECLOCK_SNOOZE":
            await model.snooze(action: action, in: trip)
        case "RECLOCK_COULDNT":
            await model.setCompletion(.notPossible, for: action, in: trip)
        default:
            break // default tap opens the app; Today tab already shows the action
        }
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
