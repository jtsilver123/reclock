import SwiftUI
import ReclockKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else if !model.state.onboardingComplete {
                OnboardingFlow()
            } else {
                MainTabs()
            }
        }
        .alert(
            model.activeAlert?.title ?? "",
            isPresented: Binding(
                get: { model.activeAlert != nil },
                set: { if !$0 { model.activeAlert = nil } }
            ),
            presenting: model.activeAlert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "sun.horizon.fill") }
            TimelineTab()
                .tabItem { Label("Timeline", systemImage: "calendar.day.timeline.left") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
    }
}

struct TimelineTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if let trip = model.activeTrip, let plan = model.plan(for: trip) {
                PlanTimelineView(trip: trip, plan: plan)
            } else {
                ContentUnavailableView(
                    "No trip yet",
                    systemImage: "airplane",
                    description: Text("Add a trip on the Today tab and your full timeline will appear here.")
                )
            }
        }
    }
}
