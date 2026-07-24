import SwiftUI
import StoreKit
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
        // The three root states hand off with a breath, not a hard cut.
        .animation(Theme.Anim.gentle, value: model.isLoaded)
        .animation(Theme.Anim.spring, value: model.state.onboardingComplete)
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
    @Environment(\.requestReview) private var requestReview

    private enum Tab: Hashable { case plan, trips, settings }
    @State private var selection: Tab = .plan

    var body: some View {
        @Bindable var model = model
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
        // A deliberate replan re-computes on screen, then shows what moved.
        .overlay {
            if let update = model.planUpdate {
                PlanUpdateView(update: update) {
                    withAnimation(Theme.Anim.spring) { model.planUpdate = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
                .zIndex(11)
            }
        }
        .animation(Theme.Anim.spring, value: model.planUpdate?.id)
        .onChange(of: model.planUpdate?.id) { _, id in
            // "See the plan" lands on the updated plan itself.
            if id != nil { selection = .plan }
        }
        .onChange(of: model.planTabRequest) { _, _ in
            // A calendar event's deep link: land on the plan it points at.
            selection = .plan
        }
        // A reminder's body tap opens the very step it announced.
        .sheet(item: $model.actionDetailRequest) { request in
            NavigationStack {
                ActionDetailView(action: request.action, trip: request.trip)
            }
            .tint(Theme.accentDeep)
        }
        .onChange(of: model.reviewRequestToken) { _, token in
            guard token > 0 else { return }
            Task { @MainActor in
                // Let the celebration land first, and never stack the rating prompt on
                // top of a full-screen moment.
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard model.planReveal == nil, model.planUpdate == nil,
                      model.pendingJoinCode == nil else {
                    // Suppressed by a takeover: the ask stays unspent for next time.
                    model.cancelReviewAsk()
                    return
                }
                requestReview()
                model.confirmReviewPrompted()
            }
        }
        .task(id: model.celebration?.id) {
            guard model.celebration != nil else { return }
            // A cancelled sleep must NOT fall through to the clear: when toast B
            // replaces toast A inside 2.2s, A's dying task would wipe B out.
            do { try await Task.sleep(nanoseconds: 2_200_000_000) } catch { return }
            model.celebration = nil
        }
    }
}
