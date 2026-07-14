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

    private enum Tab: Hashable { case plan, trips, settings }
    @State private var selection: Tab = .plan

    var body: some View {
        TabView(selection: $selection) {
            PlanView()
                .tabItem { Label("Plan", systemImage: "sun.horizon.fill") }
                .tag(Tab.plan)
            TripsListView()
                .tabItem { Label("Trips", systemImage: "airplane") }
                .tag(Tab.trips)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
        .onChange(of: selection) { _, _ in
            Haptics.selection()
        }
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
                    .padding(.top, 52)  // below the nav bar, not on it
            }
        }
        .animation(Theme.Anim.spring, value: model.celebration)
        // The curtain-up after adding a trip: sky, flight, confetti — then the plan.
        .overlay {
            if let trip = model.planReveal {
                PlanRevealView(trip: trip) {
                    withAnimation(Theme.Anim.spring) { model.planReveal = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(10)
            }
        }
        .animation(Theme.Anim.spring, value: model.planReveal?.id)
        .onChange(of: model.planReveal?.id) { _, id in
            // The reveal ends on the plan itself, wherever the trip was added from.
            if id != nil { selection = .plan }
        }
        .onChange(of: model.planTabRequest) { _, _ in
            // A calendar event's deep link: land on the plan it points at.
            selection = .plan
        }
        .task(id: model.celebration?.id) {
            guard model.celebration != nil else { return }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            model.celebration = nil
        }
    }
}
