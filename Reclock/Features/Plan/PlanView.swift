import SwiftUI
import ReclockKit

/// The Plan tab: the whole plan in one place. A pinned header keeps the trip summary
/// and the current step on screen; the full day-by-day plan scrolls underneath it.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddTrip = false

    var body: some View {
        NavigationStack {
            Group {
                if let trip = model.activeTrip, let plan = model.plan(for: trip) {
                    PlanContent(trip: trip, plan: plan)
                        .id(trip.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    EmptyPlanState(showAddTrip: $showAddTrip)
                        .transition(.opacity)
                }
            }
            .animation(Theme.Anim.spring, value: model.activeTrip?.id)
            .background(Theme.background)
            .navigationTitle("Reclock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Reclock")
                        .font(Theme.display(21))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .sheet(isPresented: $showAddTrip) {
                AddTripFlow()
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

private struct EmptyPlanState: View {
    @Environment(AppModel.self) private var model
    @Binding var showAddTrip: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Text("Feel local when you land")
                    .font(Theme.display(34))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, Theme.Space.xl)
                Text("Your trip becomes a plan for sleep, light, and caffeine.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.xl)

                // The one thing to do, drawn as the one big thing on screen.
                Button {
                    showAddTrip = true
                } label: {
                    VStack(spacing: Theme.Space.s) {
                        Image(systemName: "airplane.departure")
                            .font(.system(size: 44, weight: .semibold))
                        Text("Add my trip")
                            .font(.title3.weight(.bold))
                            .fontDesign(.rounded)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(width: 216, height: 216)
                    .background(
                        Circle()
                            .fill(Theme.accent)
                            .shadow(color: Theme.accent.opacity(0.45), radius: 20, y: 8)
                    )
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel("Add my trip")
                .padding(.vertical, Theme.Space.l)
                .breathing()

                HowItWorksRow()
                    .padding(.vertical, Theme.Space.s)
                Spacer()
            }
            .padding(Theme.Space.m)
        }
        .background(alignment: .top) {
            AmbientHorizon(zone: .current, now: Date())
                .frame(height: 280)
        }
    }
}

// MARK: - Active plan

private struct PlanContent: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    let plan: JetLagPlan

    @State private var notificationsPending = false
    @State private var displayMode: TimeDisplayMode = .destination
    @State private var priorityFilter: PlanDays.PriorityFilter = .all

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let context = model.nowContext(trip: trip)
            VStack(spacing: 0) {
                // Frozen: which trip, where your body clock stands, what to do now.
                PlanPinnedHeader(trip: trip, plan: plan, context: context, now: now)

                // Scrolls: transient banners, then every day of the plan.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Theme.Space.m, pinnedViews: [.sectionHeaders]) {
                            if model.isExploringSample {
                                SampleModeBanner()
                                    .padding(.horizontal, Theme.Space.m)
                            }

                            TripStrip(focusedID: trip.id, now: now)
                                .padding(.horizontal, Theme.Space.m)

                            if !model.lastChangeMessages.isEmpty {
                                ChangeBanner(messages: model.lastChangeMessages)
                                    .padding(.horizontal, Theme.Space.m)
                            }

                            if notificationsPending {
                                NotificationNudge(onEnabled: { notificationsPending = false })
                                    .padding(.horizontal, Theme.Space.m)
                            }

                            if trip.status == .completed && !model.hasSurvey(for: trip) {
                                SurveyPromptCard(trip: trip)
                                    .padding(.horizontal, Theme.Space.m)
                            }

                            ZoneModeChip(displayMode: $displayMode, trip: trip)
                                .padding(.horizontal, Theme.Space.m)

                            ForEach(PlanDays.groupedPhases(plan: plan, filter: priorityFilter)) { group in
                                Section {
                                    ForEach(group.days) { entry in
                                        PlanDayBlock(
                                            day: entry.day,
                                            actions: entry.actions,
                                            displayMode: displayMode,
                                            trip: trip,
                                            now: now
                                        )
                                        .id(entry.day.id)
                                    }
                                } header: {
                                    PlanPhaseHeader(phase: group.phase)
                                }
                            }
                        }
                        .padding(.top, Theme.Space.s)
                        .padding(.bottom, Theme.Space.xl)
                    }
                    .onAppear {
                        // Mid-trip, the reader's day is what matters — not day 0 last week.
                        if let today = PlanDays.currentDayID(
                            plan: plan, filter: priorityFilter, now: model.deps.now()
                        ) {
                            proxy.scrollTo(today, anchor: .top)
                        }
                    }
                }
            }
            .navigationDestination(for: PlanAction.self) { action in
                ActionDetailView(action: action, trip: trip)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Time zone", selection: $displayMode) {
                        Text("Destination time").tag(TimeDisplayMode.destination)
                        Text("Home time").tag(TimeDisplayMode.home)
                        Text("Both").tag(TimeDisplayMode.dual)
                    }
                    Picker("Show", selection: $priorityFilter) {
                        ForEach(PlanDays.PriorityFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .accessibilityLabel("Plan options")
                }
            }
        }
        .onAppear {
            displayMode = model.state.settings.timeDisplay
            model.deps.analytics.track(.timelineViewed)
        }
        .onChange(of: displayMode) { _, newValue in
            var settings = model.state.settings
            settings.timeDisplay = newValue
            Task { await model.updateSettings(settings) }
        }
        .task {
            if let profile = model.profile, profile.notifications.enabled {
                notificationsPending = !(await model.deps.notifications.permissionGranted())
            }
            await model.checkForKudos(trip: trip)
        }
    }
}

// MARK: - Zone mode chip

/// Says out loud which clock the plan below is written in — and switches it.
private struct ZoneModeChip: View {
    @Binding var displayMode: TimeDisplayMode
    let trip: Trip

    private var text: String {
        displayMode == .home
            ? "Times in \(TimeFormat.zoneCity(trip.homeZone.resolved)) — home time"
            : "Times in \(TimeFormat.zoneCity(trip.destinationZone.resolved)) time"
    }

    var body: some View {
        Menu {
            Picker("Time zone", selection: $displayMode) {
                Text("Destination time").tag(TimeDisplayMode.destination)
                Text("Home time").tag(TimeDisplayMode.home)
                Text("Both").tag(TimeDisplayMode.dual)
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "globe")
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.accentDeep)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel("Plan time zone: \(text). Tap to change.")
    }
}

// MARK: - Sample mode banner

private struct SampleModeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.accentDeep)
                .accessibilityHidden(true)
            Text("This is a sample trip")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Set up my own") {
                Task { await model.exitSampleMode() }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accentDeep)
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
                 ? "The Plan tab works as your checklist. To get alerts at the right moments, allow notifications in iOS Settings."
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
                .foregroundStyle(Theme.accentDeep)
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
                .foregroundStyle(Theme.accentDeep)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
                .foregroundStyle(Theme.accentDeep)
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
            .foregroundStyle(Theme.accentDeep)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}
