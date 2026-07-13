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
                VStack(spacing: Theme.Space.l) {
                    HeroGlyph(systemName: "sun.and.horizon.fill", size: 104)
                        .padding(.top, Theme.Space.xl)
                    Text("Feel local when you land")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white)
                    Text("Your trip becomes a plan for sleep, light, and caffeine. Free, private, offline.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, Theme.Space.l)
                    Button("Add my trip") { showAddTrip = true }
                        .buttonStyle(OnGradientPrimaryButtonStyle())
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.bottom, Theme.Space.xl)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.sky(for: .seekLight))
                        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
                )
                .padding(.top, Theme.Space.m)

                HowItWorksRow()
                    .padding(.vertical, Theme.Space.s)

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

                    TripStrip(focusedID: trip.id, now: now)

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

                    // Today at a glance: one strip of color, no words.
                    if let plan,
                       let today = plan.days.first(where: {
                           $0.dayStart <= now && now < $0.dayStart.addingTimeInterval(86_400)
                       }) {
                        DayRibbon(
                            actions: plan.actions(onDay: today.index),
                            dayStart: today.dayStart,
                            now: now
                        )
                        .padding(.horizontal, Theme.Space.xs)
                    }

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
                        TripSummaryRow(trip: trip, plan: model.plan(for: trip), progress: context.progress)
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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                HeroGlyph(systemName: next == nil ? "checkmark.seal.fill" : "moon.stars.fill", size: 76)
                Spacer(minLength: 0)
                if let next {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(TimeFormat.countdown(to: next.window.start, from: now))
                            .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.white)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(Theme.Anim.gentle, value: TimeFormat.countdown(to: next.window.start, from: now))
                        Text("until \(next.title.lowercased())")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            Text("Nothing to do right now")
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.white)
            if next == nil {
                Text("You're through the plan. Keep regular hours and enjoy the trip.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.quietSky)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        )
        .accessibilityElement(children: .combine)
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
        HStack(spacing: Theme.Space.m) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trip strip (multi-trip focus switcher)

/// One chip per upcoming/active trip; tap to change which trip the whole screen follows.
/// Hidden with a single trip — no chrome without a choice to make.
private struct TripStrip: View {
    @Environment(AppModel.self) private var model
    let focusedID: UUID
    let now: Date

    private var trips: [Trip] {
        model.state.trips
            .filter { $0.status != .completed }
            .sorted { ($0.segments.first?.departure ?? .distantFuture) < ($1.segments.first?.departure ?? .distantFuture) }
    }

    var body: some View {
        if trips.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.s) {
                    ForEach(trips) { trip in
                        TripChip(
                            trip: trip,
                            isFocused: trip.id == focusedID,
                            statusText: statusText(for: trip)
                        ) {
                            Haptics.selection()
                            Task {
                                // Picking the automatic choice clears the pin (same rule
                                // as the trips list) so future trips auto-rotate in.
                                let id = model.automaticTrip?.id == trip.id ? nil : trip.id
                                await model.selectTrip(id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func statusText(for trip: Trip) -> String {
        guard let departure = trip.segments.first?.departure else { return "" }
        if departure > now {
            let days = Int((departure.timeIntervalSince(now) / 86_400).rounded(.up))
            return days <= 1 ? "tomorrow" : "in \(days)d"
        }
        return "under way"
    }
}

private struct TripChip: View {
    let trip: Trip
    let isFocused: Bool
    let statusText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(trip.origin) → \(trip.destination)")
                    .font(.subheadline.weight(.heavy))
                    .fontDesign(.rounded)
                Text(statusText)
                    .font(.caption2.weight(.medium))
                    .opacity(0.8)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(
                isFocused ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(isFocused ? Color.white : Theme.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isFocused ? Color.clear : Theme.surfaceSecondary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.springQuick, value: isFocused)
        .accessibilityLabel("\(trip.origin) to \(trip.destination), \(statusText)\(isFocused ? ", focused" : "")")
    }
}

// MARK: - Trip summary row

private struct TripSummaryRow: View {
    let trip: Trip
    let plan: JetLagPlan?
    var progress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.origin)
                    .font(.title2.weight(.heavy))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(trip.destination)
                    .font(.title2.weight(.heavy))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.textPrimary)
            }

            // The plane rides the body-clock progress line between the two cities.
            GeometryReader { geo in
                let width = geo.size.width
                let x = min(1, max(0, progress)) * max(0, width - 22)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceSecondary)
                        .frame(height: 4)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: x + 4, height: 4)
                    Image(systemName: "airplane")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .offset(x: x)
                        .animation(Theme.Anim.spring, value: x)
                }
            }
            .frame(height: 22)
            .accessibilityHidden(true)

            HStack {
                if let plan {
                    Text(plan.strategySummary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Space.m)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Trip \(trip.origin) to \(trip.destination), \(Int((progress * 100).rounded())) percent adjusted")
    }
}
