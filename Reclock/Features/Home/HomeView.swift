import SwiftUI
import ReclockKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddTrip = false
    @State private var showTrips = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if let trip = model.activeTrip, model.plan(for: trip) != nil {
                    TripHomeContent(trip: trip)
                } else {
                    EmptyHome(showAddTrip: $showAddTrip)
                }
            }
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
            .background(Theme.background)
            .navigationTitle("Reclock")
            .toolbar {
                if model.state.trips.count > 1 || model.state.settings.selectedTripID != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showTrips = true
                        } label: {
                            Image(systemName: "list.bullet.circle")
                                .accessibilityLabel("My trips")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add trip")
                    }
                }
            }
            .sheet(isPresented: $showAddTrip) {
                AddTripFlow()
            }
            .sheet(isPresented: $showTrips) {
                TripsListView()
            }
            .onAppear {
                // "Add my trip" at the end of onboarding should do what it says.
                if model.shouldPresentAddTrip {
                    model.shouldPresentAddTrip = false
                    if model.state.trips.isEmpty {
                        showAddTrip = true
                    }
                }
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyHome: View {
    @Environment(AppModel.self) private var model
    @Binding var showAddTrip: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: 40)
                BreathingSymbol(systemName: "sun.and.horizon.fill", size: 56)
                Text("Feel local when you land")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                Text("Add your next trip and Reclock builds a practical plan for sleep, light, and caffeine — free, private, and it works offline.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)
                Button("Add my trip") { showAddTrip = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.Space.xl)
                Button("See an example") {
                    Task { await model.seedDemoData() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, Theme.Space.xl)
                Spacer()
            }
            .padding(Theme.Space.m)
        }
    }
}

// MARK: - Active trip home

private struct TripHomeContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trip: Trip
    @State private var notificationsPending = false

    private var heroTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            )
    }

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let context = model.nowContext(trip: trip)
            let plan = model.plan(for: trip)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if model.isExploringSample {
                        SampleModeBanner()
                    }

                    HomeHeader(
                        trip: trip,
                        context: context,
                        now: now,
                        requiredShiftHours: plan?.requiredShiftHours ?? 0
                    )

                    if !model.lastChangeMessages.isEmpty {
                        ChangeBanner(messages: model.lastChangeMessages)
                    }

                    if notificationsPending {
                        NotificationNudge(onEnabled: { notificationsPending = false })
                    }

                    if trip.status == .completed && !model.hasSurvey(for: trip) {
                        SurveyPromptCard(trip: trip)
                    }

                    // The hero card swaps with a spring: completed cards lift away,
                    // the next state settles in.
                    Group {
                        if let current = context.current.first {
                            NowCard(action: current, trip: trip, now: now)
                                .id(current.id)
                                .transition(heroTransition)
                        } else {
                            QuietNowCard(next: context.next.first, now: now)
                                .transition(heroTransition)
                        }
                    }
                    .animation(Theme.Anim.spring, value: context.current.first?.id)

                    if context.current.count > 1 {
                        ForEach(context.current.dropFirst()) { action in
                            NavigationLink(value: action) {
                                ActionRow(action: action)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !context.next.isEmpty {
                        SectionHeader(title: "Next")
                        ForEach(context.next) { action in
                            NavigationLink(value: action) {
                                ActionRow(action: action)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TonightCard(context: context)

                    NavigationLink {
                        TripDetailView(trip: trip)
                    } label: {
                        TripSummaryRow(trip: trip, plan: model.plan(for: trip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.tripCard")
                }
                .padding(Theme.Space.m)
            }
            .navigationDestination(for: PlanAction.self) { action in
                ActionDetailView(action: action, trip: trip)
            }
        }
        .task {
            if let profile = model.profile, profile.notifications.enabled {
                notificationsPending = !(await model.deps.notifications.permissionGranted())
            }
        }
    }
}

// MARK: - Sample mode banner

private struct SampleModeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("This is a sample trip")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Set up my own") {
                Task { await model.exitSampleMode() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

// MARK: - Notification nudge

private struct NotificationNudge: View {
    @Environment(AppModel.self) private var model
    var onEnabled: () -> Void
    @State private var wasDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label(
                wasDenied ? "Reminders are off" : "Get nudged at the right moments",
                systemImage: "bell.badge.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            Text(wasDenied
                 ? "The Today tab works as your checklist. To get alerts at the right moments, allow notifications in iOS Settings."
                 : "Your plan is ready. Reminders fire exactly when a window opens — even in airplane mode.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if wasDenied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            } else {
                Button("Turn on reminders") {
                    Task {
                        if await model.requestNotificationPermission() {
                            onEnabled()
                        } else {
                            wasDenied = true
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Header

private struct HomeHeader: View {
    let trip: Trip
    let context: AppModel.NowContext
    let now: Date
    let requiredShiftHours: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(context.dayLabel.isEmpty ? trip.name : context.dayLabel)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: Theme.Space.s) {
                ClockChip(
                    title: "Home",
                    zone: trip.homeZone.resolved,
                    now: now
                )
                ClockChip(
                    title: TimeFormat.zoneCity(trip.destinationZone.resolved),
                    zone: trip.destinationZone.resolved,
                    now: now
                )
                Spacer()
                ProgressRing(progress: context.progress, label: shiftLabel)
            }
        }
    }

    private var shiftLabel: String {
        let total = abs(requiredShiftHours)
        guard total > 0.5 else { return "Adjusted" }
        let done = min(total, context.progress * total)
        let doneText = done == done.rounded()
            ? String(Int(done)) : String(format: "%.1f", done)
        return "\(doneText) of \(Int(total.rounded()))h shifted"
    }
}

// MARK: - Post-trip check-in prompt

private struct SurveyPromptCard: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    @State private var showSurvey = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label("Back from \(trip.destination)?", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("90 seconds: how rough was jet lag, and what was unrealistic? Your answers tune future plans.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Button("Quick check-in") { showSurvey = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $showSurvey) {
            PostTripSurveyView(trip: trip)
        }
    }
}

// MARK: - Change banner

private struct ChangeBanner: View {
    @Environment(AppModel.self) private var model
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ForEach(messages, id: \.self) { message in
                Label(message, systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
            }
            Button("Got it") {
                model.lastChangeMessages = []
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

// MARK: - Quiet state

private struct QuietNowCard: View {
    let next: PlanAction?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label("Nothing to do right now", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if let next {
                Text("Next up: \(next.title.lowercased()) in \(TimeFormat.countdown(to: next.window.start, from: now)).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(Theme.Anim.gentle, value: TimeFormat.countdown(to: next.window.start, from: now))
            } else {
                Text("You're through the plan. Keep regular hours and enjoy the trip.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Tonight

private struct TonightCard: View {
    let context: AppModel.NowContext

    var body: some View {
        if context.tonightSleep != nil || context.tonightCutoff != nil {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Tonight")
                if let cutoff = context.tonightCutoff {
                    TonightRow(
                        icon: "cup.and.saucer",
                        tint: Theme.tint(for: .caffeineCutoff),
                        title: "Last caffeine",
                        value: TimeFormat.time(cutoff.window.start, zone: cutoff.displayZone.resolved)
                    )
                }
                if let sleep = context.tonightSleep {
                    TonightRow(
                        icon: "bed.double.fill",
                        tint: Theme.tint(for: .sleep),
                        title: "Sleep window",
                        value: TimeFormat.range(sleep.window, zone: sleep.displayZone.resolved)
                    )
                }
                if let optional = context.tonightOptional {
                    TonightRow(
                        icon: "pills.fill",
                        tint: Theme.tint(for: .melatoninOptional),
                        title: "Optional melatonin",
                        value: TimeFormat.time(optional.window.start, zone: optional.displayZone.resolved)
                    )
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

private struct TonightRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trip summary row

private struct TripSummaryRow: View {
    let trip: Trip
    let plan: JetLagPlan?

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "airplane.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.origin) → \(trip.destination)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let plan {
                    Text(plan.strategySummary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Space.m)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
