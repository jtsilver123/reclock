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

/// Three tabs, three jobs: Plan is where you look, Trips is where you manage,
/// Settings is where you tune. Nothing overlaps.
struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView {
            PlanView()
                .tabItem { Label("Plan", systemImage: "sun.horizon.fill") }
            TripsListView()
                .tabItem { Label("Trips", systemImage: "airplane") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        // The assistant floats above everything, always within thumb's reach.
        .overlay(alignment: .bottomTrailing) {
            AssistantFAB()
                .padding(.trailing, Theme.Space.m)
                .padding(.bottom, 70)
        }
        // Celebrations belong to the whole app, not one tab.
        .overlay(alignment: .top) {
            if let celebration = model.celebration {
                CelebrationToast(event: celebration)
                    .transition(CelebrationToast.transition(reduceMotion: reduceMotion))
                    .padding(.top, Theme.Space.xs)
            }
        }
        .animation(Theme.Anim.spring, value: model.celebration)
        .task(id: model.celebration?.id) {
            guard model.celebration != nil else { return }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            model.celebration = nil
        }
    }
}
