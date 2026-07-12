import SwiftUI
import ReclockKit

// Preview support: a model preloaded with the flagship demo trip on landing day.
@MainActor
enum PreviewData {
    static func model(seeded: Bool = true) -> AppModel {
        let model = AppModel(dependencies: .preview())
        if seeded {
            Task { await model.seedDemoData() }
        }
        return model
    }

    static var landingDayTrip: (Trip, JetLagPlan, UserProfile) {
        let reference = Date().addingTimeInterval(-5 * 86_400)
        let trip = DemoTrips.newYorkToHelsinki(reference: reference)
        let profile = DemoTrips.defaultProfile()
        let plan = (try? PlanEngine().generatePlan(trip: trip, profile: profile, currentState: nil))
            ?? JetLagPlan(
                tripID: trip.id,
                generatedAt: reference,
                strategy: .fullyAdapt,
                requiredShiftHours: 7,
                shiftDirection: .advance,
                days: [],
                actions: [],
                strategySummary: ""
            )
        return (trip, plan, profile)
    }
}

#Preview("Home — landing day") {
    RootView()
        .environment(PreviewData.model())
}

#Preview("Timeline") {
    let (trip, plan, _) = PreviewData.landingDayTrip
    return NavigationStack {
        PlanTimelineView(trip: trip, plan: plan)
    }
    .environment(PreviewData.model())
}

#Preview("Trip detail") {
    let (trip, _, _) = PreviewData.landingDayTrip
    return NavigationStack {
        TripDetailView(trip: trip)
    }
    .environment(PreviewData.model())
}

#Preview("Onboarding") {
    OnboardingFlow()
        .environment(PreviewData.model(seeded: false))
}

#Preview("Why it works") {
    NavigationStack {
        WhyItWorksView()
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(PreviewData.model())
}

#Preview("Survey") {
    let (trip, _, _) = PreviewData.landingDayTrip
    return PostTripSurveyView(trip: trip)
        .environment(PreviewData.model())
}

#Preview("Now card — dark") {
    let (trip, plan, _) = PreviewData.landingDayTrip
    let action = plan.actions.first { $0.type == .seekLight } ?? plan.actions[0]
    return ScrollView {
        NowCard(action: action, trip: trip, now: action.window.start.addingTimeInterval(600))
            .padding()
    }
    .background(Theme.background)
    .environment(PreviewData.model())
    .preferredColorScheme(.dark)
}
