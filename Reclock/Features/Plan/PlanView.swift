import SwiftUI
import ReclockKit

/// The Plan tab: the whole plan in one place. A pinned header keeps the trip summary
/// and the current step on screen; the full day-by-day plan scrolls underneath it.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddTrip = false
    @State private var adjustTrip: Trip?
    @State private var exportTrip: Trip?

    var body: some View {
        NavigationStack {
            Group {
                if let trip = model.activeTrip, let plan = model.plan(for: trip) {
                    PlanContent(trip: trip, plan: plan, onAdjust: { adjustTrip = trip })
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
                ToolbarItem(placement: .topBarLeading) {
                    if let trip = model.activeTrip, model.plan(for: trip) != nil {
                        Button {
                            Haptics.soft()
                            exportTrip = trip
                        } label: {
                            Image(systemName: "calendar.badge.plus")
                                .accessibilityLabel("Add plan to my calendar")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let trip = model.activeTrip, model.plan(for: trip) != nil {
                        Button {
                            Haptics.soft()
                            adjustTrip = trip
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .accessibilityLabel("Adjust plan")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddTrip) {
                AddTripFlow()
            }
            .sheet(item: $adjustTrip) { trip in
                PlanAdjustSheet(trip: trip)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $exportTrip) { trip in
                CalendarExportSheet(trip: trip)
                    .presentationDetents([.medium, .large])
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
                    .grain(0.4, cornerRadius: 108)
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
    let onAdjust: () -> Void

    @State private var notificationsPending = false
    @AppStorage("planPrimerDismissed") private var planPrimerDismissed = false
    // Back-to-now: shown only when today is ON this plan and scrolled out of view.
    @State private var showBackToNow = false
    @State private var todayIsAbove = true
    @State private var viewportHeight: CGFloat = 0
    /// Suppresses the button during the launch auto-scroll, which starts at day 0.
    @State private var backToNowArmed = false
    /// Bumped by the pinned header's now bar; the scroll reader answers it.
    @State private var scrollToNowRequest = 0

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let context = model.nowContext(trip: trip)
            let todayID = PlanDays.currentDayID(plan: plan, now: now)
            VStack(spacing: 0) {
                // Frozen: which trip, where your body clock stands, what to do now.
                PlanPinnedHeader(
                    trip: trip, plan: plan, context: context, now: now,
                    onTapNow: todayID == nil ? nil : { scrollToNowRequest += 1 }
                )

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
                                NotificationNudge(onEnabled: {
                                    withAnimation(Theme.Anim.spring) { notificationsPending = false }
                                })
                                .padding(.horizontal, Theme.Space.m)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            }

                            if trip.status == .completed && !model.hasSurvey(for: trip) {
                                SurveyPromptCard(trip: trip)
                                    .padding(.horizontal, Theme.Space.m)
                            }

                            if !planPrimerDismissed && !ProcessInfo.isUITest {
                                PlanPrimerCard(
                                    sleepText: assumedSleepText,
                                    onAdjust: onAdjust,
                                    onDismiss: {
                                        Haptics.selection()
                                        withAnimation(Theme.Anim.spring) { planPrimerDismissed = true }
                                    }
                                )
                                .padding(.horizontal, Theme.Space.m)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            }

                            // Group once per render — this body re-evaluates every 30s
                            // tick, and grouping walks every day and action.
                            let groups = PlanDays.groupedPhases(plan: plan)
                            let zoneChanges = PlanDays.zoneChangeDayIDs(plan: plan)
                            let firstDayID = groups.first?.days.first?.id

                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.days) { entry in
                                        if zoneChanges.contains(entry.day.id) {
                                            ZoneMarkerRow(
                                                zone: entry.day.zone.resolved,
                                                isFirst: entry.day.id == firstDayID
                                            )
                                        }
                                        PlanDayBlock(
                                            day: entry.day,
                                            actions: entry.actions,
                                            trip: trip,
                                            now: now
                                        )
                                        .id(entry.day.id)
                                        .background {
                                            // Today's block reports its frame so the
                                            // back-to-now button knows when it left view.
                                            // A lazily-unrealized block reports nothing,
                                            // which reads (correctly) as "far away".
                                            // Fully inert under XCUITest — continuous
                                            // preference traffic during re-layout can
                                            // starve the harness's idle-wait.
                                            if !ProcessInfo.isUITest, entry.day.id == todayID {
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: TodayFrameKey.self,
                                                        value: geo.frame(in: .named("planScroll"))
                                                    )
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    PlanPhaseHeader(phase: group.phase)
                                }
                            }
                        }
                        .padding(.top, Theme.Space.s)
                        .padding(.bottom, 96)  // clears the floating assistant orb
                        // Every replan bumps the revision; the pills spring to their
                        // new spots instead of teleporting.
                        .animation(Theme.Anim.spring, value: plan.revision)
                    }
                    .coordinateSpace(name: "planScroll")
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { viewportHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, height in
                                    viewportHeight = height
                                }
                        }
                    }
                    .onPreferenceChange(TodayFrameKey.self) { frame in
                        // Hysteresis: appear only once today is clearly beyond the
                        // viewport, hide only once it's genuinely back on screen —
                        // the flag can't oscillate at the boundary mid-animation.
                        let slack: CGFloat = showBackToNow ? 0 : 60
                        var nearNow = false
                        if let frame, viewportHeight > 0 {
                            nearNow = frame.maxY > -slack && frame.minY < viewportHeight + slack
                            todayIsAbove = frame.midY < viewportHeight / 2
                        }
                        let show = !nearNow && backToNowArmed
                        guard show != showBackToNow else { return }
                        showBackToNow = show
                    }
                    .overlay(alignment: .bottom) {
                        // Scrolled off into another day? One tap brings the reader
                        // home. Exists only while today is actually on this plan.
                        if showBackToNow, let todayID, !ProcessInfo.isUITest {
                            BackToNowButton(pointsUp: todayIsAbove) {
                                Haptics.soft()
                                scrollToNow(proxy, todayID: todayID)
                            }
                            .padding(.bottom, Theme.Space.m)
                            .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(Theme.Anim.spring, value: showBackToNow)
                    .onChange(of: scrollToNowRequest) { _, _ in
                        guard let todayID = PlanDays.currentDayID(plan: plan, now: model.deps.now())
                        else { return }
                        scrollToNow(proxy, todayID: todayID)
                    }
                    .task {
                        // Mid-trip, the reader's day is what matters — not day 0 last
                        // week. Lazy rows realize progressively, and a single early
                        // scrollTo can land short on long plans — try a few times.
                        defer { backToNowArmed = true }
                        guard let today = PlanDays.currentDayID(plan: plan, now: model.deps.now()) else { return }
                        for delay in [200_000_000, 400_000_000, 600_000_000] {
                            try? await Task.sleep(nanoseconds: UInt64(delay))
                            proxy.scrollTo(today, anchor: .top)
                        }
                    }
                }
            }
        }
        .navigationDestination(for: PlanAction.self) { action in
            ActionDetailView(action: action, trip: trip)
        }
        .onAppear {
            model.deps.analytics.track(.timelineViewed)
        }
        .task {
            if let profile = model.profile, profile.notifications.enabled {
                notificationsPending = !(await model.deps.notifications.permissionGranted())
            }
            await model.checkForKudos(trip: trip)
        }
    }

    /// One tap home. Lazy rows realize as the scroll travels, so a single pass can
    /// land short of today on long plans — the launch auto-scroll learned this the
    /// hard way. Settle over a few passes, and hide the button optimistically; the
    /// frame preference brings it straight back if we still landed short.
    private func scrollToNow(_ proxy: ScrollViewProxy, todayID: UUID) {
        showBackToNow = false
        Task {
            for delay in [0, 250_000_000, 500_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay)) }
                withAnimation(Theme.Anim.spring) {
                    proxy.scrollTo(todayID, anchor: .top)
                }
            }
        }
    }

    /// Onboarding never asks about sleep anymore, so the primer says out loud what
    /// the plan assumed — in the user's clock format.
    private var assumedSleepText: String {
        let bed = model.profile?.typicalBedtime ?? LocalClockTime(hour: 23, minute: 0)
        let wake = model.profile?.typicalWakeTime ?? LocalClockTime(hour: 7, minute: 0)
        return "\(clockText(bed)) – \(clockText(wake))"
    }

    private func clockText(_ clock: LocalClockTime) -> String {
        let date = Calendar.current.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Back to now

/// Today's block, reporting its frame in the plan's scroll space. No report at all
/// means the lazy list hasn't even built it — the reader is far away.
private struct TodayFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The floating way home: appears once today scrolls out of view, points back
/// toward it, and one tap lands the reader on the current moment.
private struct BackToNowButton: View {
    let pointsUp: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: pointsUp ? "arrow.up" : "arrow.down")
                    .font(.caption.weight(.bold))
                Text("Now")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 10, y: 4)
            )
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Scroll back to now")
    }
}

// MARK: - First-time primer

/// One-time decoder for the pill timeline — and, now that onboarding asks nothing,
/// the plan's assumptions said out loud with the fix one tap away.
private struct PlanPrimerCard: View {
    let sleepText: String
    var onAdjust: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Your plan, at a glance")
                .font(Theme.display(19, black: false))
                .foregroundStyle(Theme.textPrimary)

            primerRow(text: "Two columns: Stay awake and Sleep. A filled pill is a do — it covers the exact window, in local time.") {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.solidTint(for: .sleep))
                    .frame(width: 16, height: 34)
            }
            primerRow(text: "A slashed outline means that mode's tool is off-limits — like coffee after the cutoff.") {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.tint(for: .caffeineCutoff), lineWidth: 1.5)
                    .frame(width: 16, height: 34)
                    .overlay(
                        Image(systemName: "line.diagonal")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.tint(for: .caffeineCutoff))
                    )
            }
            primerRow(text: "We assumed your usual sleep is \(sleepText). The sliders up top adjust that — plus intensity and your head start.") {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: 16, height: 34)
            }
            primerRow(text: "The calendar button up top puts every remaining step on your calendar — and each event links back here.") {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: 16, height: 34)
            }
            primerRow(text: "Tap any step to see why it helps.") {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: 16, height: 34)
            }

            HStack(spacing: Theme.Space.l) {
                Button(action: onAdjust) {
                    Text("Adjust my sleep")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableCardStyle())
                Button("Looks right", action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        // .contain, not .combine: the card now holds two buttons, and VoiceOver
        // must reach each one individually.
        .accessibilityElement(children: .contain)
    }

    private func primerRow(text: String, @ViewBuilder glyph: () -> some View) -> some View {
        HStack(spacing: Theme.Space.m) {
            glyph()
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15))
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                Text(wasDenied ? "Reminders are off" : "Get nudged at the right moments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
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
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15))
                    Image(systemName: "checklist")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
                Text("Back from \(trip.destination)?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
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
                Haptics.selection()
                withAnimation(Theme.Anim.spring) { model.lastChangeMessages = [] }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accentDeep)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}
