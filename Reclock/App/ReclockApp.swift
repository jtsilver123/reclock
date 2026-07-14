import SwiftUI
import ReclockKit

@main
struct ReclockApp: App {
    @UIApplicationDelegateAdaptor(ReclockAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
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
                .onChange(of: scenePhase) { _, phase in
                    // Statuses and the 60-slot notification window go stale while
                    // the app naps; every return to foreground refreshes both.
                    if phase == .active {
                        Task { await model.refreshOnForeground() }
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == AppLinks.scheme else { return }

                    // reclock://trip/UUID — the link on every exported calendar
                    // event; tapping one lands back on that trip's plan.
                    if url.host == "trip", let id = UUID(uuidString: url.lastPathComponent) {
                        model.openTripFromLink(id)
                        return
                    }

                    // reclock://join?c=CODE — the invite deep link (Cini pattern).
                    let isJoin = url.host == "join" || url.path.contains("join")
                    guard isJoin,
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let code = components.queryItems?.first(where: { $0.name == "c" })?.value,
                          !code.isEmpty
                    else { return }
                    model.pendingJoinCode = PendingJoinCode(code: code.uppercased())
                }
                .sheet(item: Binding(
                    get: { model.pendingJoinCode },
                    set: { model.pendingJoinCode = $0 }
                )) { pending in
                    NavigationStack {
                        JoinPlanView(prefilledCode: pending.code)
                    }
                    .presentationDetents([.medium, .large])
                }
        }
    }
}
