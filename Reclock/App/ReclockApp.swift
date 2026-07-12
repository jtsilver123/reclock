import SwiftUI
import ReclockKit

@main
struct ReclockApp: App {
    @UIApplicationDelegateAdaptor(ReclockAppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let dependencies = Dependencies.live()
        _model = State(initialValue: AppModel(dependencies: dependencies))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    appDelegate.notificationHandler.model = model
                    await model.start()
                }
        }
    }
}
