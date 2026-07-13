import Foundation
import Observation
import SwiftUI
import ReclockKit

/// Central observable state. Owns the persisted `AppState`, exposes derived views of the
/// active trip/plan, and funnels every mutation through one place so persistence and
/// notification scheduling never drift apart.
@MainActor
@Observable
final class AppModel {
    let deps: Dependencies
    /// Optional backup & sync identity. The app never requires it.
    let auth = AuthManager()
    let sync = SyncService()

    // Internal (not private(set)): AppModel+Sharing funnels mutations through
    // the same persist path from its own file.
    var state = AppState()
    private(set) var isLoaded = false
    /// Non-fatal problems surfaced to the user (plan regeneration failure, etc.).
    var activeAlert: AppAlert?
    /// Messages describing the latest replan ("Your flight moved by 2 hours…").
    var lastChangeMessages: [String] = []
    /// Set when onboarding finishes via "Add my trip" so Home opens the add-trip flow
    /// immediately — the button the user tapped should do what it says.
    var shouldPresentAddTrip = false
    /// Transient acknowledgment after completing a step; Home shows it for ~2s.
    var celebration: CelebrationEvent?
    /// A join code arriving via reclock://join?c=… — RootView presents the join sheet.
    var pendingJoinCode: PendingJoinCode?

    init(dependencies: Dependencies) {
        self.deps = dependencies
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isLoaded else { return }
        do {
            state = try await deps.store.load()
        } catch {
            state = AppState()
        }
        if ProcessInfo.seedsDemoData && state.trips.isEmpty {
            await seedDemoData()
        }
        isLoaded = true
        deps.analytics.track(.appOpened)
        await refreshTripStatuses()
        // Fresh install with a backup waiting (new phone): restore silently.
        if auth.isSignedIn && state.trips.isEmpty && !ProcessInfo.isUITest {
            await restoreFromBackupIfEmpty()
        }
    }

    func persist() async {
        do {
            try await deps.store.save(state)
        } catch {
            activeAlert = AppAlert(
                title: "Couldn't save",
                message: "Your last change couldn't be written to storage. Free up space and try again."
            )
        }
        sync.schedulePush(state: state, auth: auth)
    }

    // MARK: - Backup & sync

    /// After sign-in: an empty device restores the backup; a device with trips becomes
    /// the source of truth and pushes up immediately.
    func handleSignedIn() async {
        if state.trips.isEmpty {
            await restoreFromBackupIfEmpty()
        }
        await sync.push(state: state, auth: auth)
    }

    func backUpNow() async {
        await sync.push(state: state, auth: auth)
    }

    private func restoreFromBackupIfEmpty() async {
        guard state.trips.isEmpty, let restored = await sync.fetchSnapshot(auth: auth) else { return }
        state = restored
        await persist()
        await refreshTripStatuses()
        await rescheduleAllNotifications()
        lastChangeMessages = ["Restored your trips from backup."]
    }

    // MARK: - Derived state

    var profile: UserProfile? { state.profile }

    var activeTrip: Trip? {
        let candidates = state.trips.filter { $0.status != .archived }
        // An explicit user selection wins as long as the trip still exists.
        if let selected = state.settings.selectedTripID,
           let trip = candidates.first(where: { $0.id == selected }) {
            return trip
        }
        return Self.automaticTrip(from: candidates, now: deps.now())
    }

    /// The trip Today/Timeline would follow with no explicit selection.
    var automaticTrip: Trip? {
        Self.automaticTrip(from: state.trips.filter { $0.status != .archived }, now: deps.now())
    }

    /// Heuristic: a trip whose window (including pre-trip shift days and recovery)
    /// contains now, else the next upcoming, else the most recent.
    private static func automaticTrip(from candidates: [Trip], now: Date) -> Trip? {
        let current = candidates.first { trip in
            guard let dep = trip.firstDeparture, let arr = trip.finalArrival else { return false }
            return dep.addingTimeInterval(-4 * 86_400) <= now && now <= arr.addingTimeInterval(8 * 86_400)
        }
        if let current { return current }
        return candidates
            .filter { ($0.firstDeparture ?? .distantPast) > now }
            .min { ($0.firstDeparture ?? .distantFuture) < ($1.firstDeparture ?? .distantFuture) }
            ?? candidates.max { ($0.firstDeparture ?? .distantPast) < ($1.firstDeparture ?? .distantPast) }
    }

    func selectTrip(_ id: UUID?) async {
        state.settings.selectedTripID = id
        await persist()
    }

    func hasSurvey(for trip: Trip) -> Bool {
        state.surveys.contains { $0.tripID == trip.id }
    }

    func shareText(for trip: Trip) -> String? {
        plan(for: trip).map { PlanShareFormatter.text(trip: trip, plan: $0) }
    }

    func plan(for trip: Trip) -> JetLagPlan? {
        state.plan(forTrip: trip.id)
    }

    /// The plan's actions relevant right now: current, next few, and tonight.
    struct NowContext {
        var current: [PlanAction] = []
        var next: [PlanAction] = []
        var tonightSleep: PlanAction?
        var tonightCutoff: PlanAction?
        var tonightOptional: PlanAction?
        var progress: Double = 0
        var dayLabel: String = ""
    }

    func nowContext(trip: Trip) -> NowContext {
        guard let plan = plan(for: trip) else { return NowContext() }
        let now = deps.now()
        var context = NowContext()

        let pending = plan.actions
            .filter { $0.completion == .pending }
            .sorted { $0.window.start < $1.window.start }

        context.current = pending
            .filter { $0.window.contains(now) }
            .sorted { $0.priority < $1.priority }
        context.next = pending
            .filter { $0.window.start > now }
            .prefix(3)
            .map { $0 }

        // Tonight: the next sleep action and the caffeine cutoff/optional item before it.
        let nextSleep = pending.first {
            ($0.type == .sleep) && $0.window.end > now && $0.window.duration >= .hours(2)
        }
        context.tonightSleep = nextSleep
        if let sleep = nextSleep {
            context.tonightCutoff = plan.actions.first {
                $0.type == .caffeineCutoff && $0.window.start <= sleep.window.start
                    && $0.window.end >= now.addingTimeInterval(-12 * 3600)
                    && abs($0.window.start.timeIntervalSince(sleep.window.start)) < 20 * 3600
            }
            context.tonightOptional = plan.actions.first {
                $0.type == .melatoninOptional && $0.window.start <= sleep.window.start
                    && $0.window.end > now && $0.completion == .pending
            }
        }

        if let today = plan.days.last(where: { $0.dayStart <= now }) ?? plan.days.first {
            context.progress = plan.progress(atEndOfDay: today.index)
            context.dayLabel = today.label
        }
        return context
    }

    // MARK: - Onboarding & profile

    func completeOnboarding(profile: UserProfile) async {
        state.profile = profile
        state.onboardingComplete = true
        shouldPresentAddTrip = true
        deps.analytics.track(.onboardingCompleted)
        await persist()
    }

    /// True while the user is exploring the seeded sample trip without ever having
    /// answered the onboarding questions themselves.
    var isExploringSample: Bool {
        activeTrip?.importSource == .demo
    }

    /// Leaves sample mode: removes demo trips. If the profile itself is the seeded
    /// placeholder (the user never answered onboarding), returns to onboarding; a real
    /// profile from real onboarding is left untouched.
    func exitSampleMode() async {
        for trip in state.trips where trip.importSource == .demo {
            state.plans.removeAll { $0.tripID == trip.id }
            state.setTravelerState(nil, forTrip: trip.id)
        }
        state.trips.removeAll { $0.importSource == .demo }
        state.settings.selectedTripID = nil
        if state.profile?.id == Self.demoProfileID {
            state.profile = nil
            state.onboardingComplete = false
        }
        await persist()
        await rescheduleAllNotifications()
    }

    /// The fixed ID DemoTrips.defaultProfile uses — marks a profile as seeded, not answered.
    private static let demoProfileID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func updateProfile(_ profile: UserProfile) async {
        state.profile = profile
        await persist()
        // Profile changes affect all future plans; regenerate active ones.
        for trip in state.trips where trip.status == .upcoming || trip.status == .active {
            await regeneratePlan(for: trip, trigger: "profile_changed")
        }
    }

    // MARK: - Trips

    @discardableResult
    func addTrip(_ trip: Trip) async -> Bool {
        guard let profile = state.profile else { return false }
        do {
            var stamped = trip
            stamped.createdAt = deps.now()
            let plan = try deps.engine.generatePlan(trip: stamped, profile: profile, currentState: nil)
            let validation = deps.validator.validate(plan: plan, trip: stamped, profile: profile)
            guard validation.isValid else {
                activeAlert = AppAlert(
                    title: "Couldn't build that plan",
                    message: "This itinerary produced an inconsistent plan. Double-check the flight times and time zones."
                )
                return false
            }
            state.trips.append(stamped)
            state.plans.removeAll { $0.tripID == stamped.id }
            state.plans.append(plan)
            await persist()
            await rescheduleNotifications(trip: stamped, plan: plan)
            let delta = Int(plan.requiredShiftHours.rounded())
            deps.analytics.track(
                trip.importSource == .calendar
                    ? .tripImported(source: "calendar", segmentCount: trip.segments.count, timezoneDelta: delta)
                    : .tripManuallyEntered(segmentCount: trip.segments.count, timezoneDelta: delta)
            )
            deps.analytics.track(.planGenerated(
                strategy: plan.strategy.rawValue,
                direction: plan.shiftDirection.rawValue,
                shiftHours: delta,
                intensity: trip.intensity.rawValue
            ))
            celebration = .planReady(destination: stamped.destination)
            return true
        } catch {
            activeAlert = AppAlert(
                title: "Couldn't build that plan",
                message: (error as? PlanEngineError).map(String.init(describing:))
                    ?? "Something about this itinerary doesn't add up. Check the dates and times."
            )
            return false
        }
    }

    func deleteTrip(_ trip: Trip) async {
        state.trips.removeAll { $0.id == trip.id }
        state.plans.removeAll { $0.tripID == trip.id }
        state.setTravelerState(nil, forTrip: trip.id)
        if state.settings.selectedTripID == trip.id {
            state.settings.selectedTripID = nil
        }
        await persist()
        // Rebuild the whole schedule so other trips' reminders survive the deletion.
        await rescheduleAllNotifications()
    }

    // MARK: - Commitments

    func addCommitment(_ commitment: FixedCommitment, to trip: Trip) async {
        var updated = trip
        updated.commitments.append(commitment)
        updated.commitments.sort { $0.start < $1.start }
        await updateTrip(updated)
    }

    func updateCommitment(_ commitment: FixedCommitment, in trip: Trip) async {
        var updated = trip
        guard let index = updated.commitments.firstIndex(where: { $0.id == commitment.id }) else { return }
        updated.commitments[index] = commitment
        updated.commitments.sort { $0.start < $1.start }
        await updateTrip(updated)
    }

    func removeCommitment(id: UUID, from trip: Trip) async {
        var updated = trip
        updated.commitments.removeAll { $0.id == id }
        await updateTrip(updated)
    }

    // MARK: - Segment edits

    /// Corrects a segment's times (typo fixes, schedule changes known in advance).
    /// Unlike `reportDelay`, this does not mark the flight as delayed.
    func editSegmentTimes(trip: Trip, segmentID: UUID, newDeparture: Date, newArrival: Date) async {
        var updated = trip
        updated.segments = trip.segments.map { segment in
            guard segment.id == segmentID else { return segment }
            var s = segment
            s.departure = newDeparture
            s.arrival = newArrival
            return s
        }.sorted { $0.departure < $1.departure }
        await updateTrip(updated)
    }

    func updateTrip(_ trip: Trip, regenerate: Bool = true) async {
        guard let index = state.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        state.trips[index] = trip
        await persist()
        if regenerate {
            await regeneratePlan(for: trip, trigger: "trip_edited")
        }
    }

    private func refreshTripStatuses() async {
        let now = deps.now()
        var changed = false
        state.trips = state.trips.map { trip in
            var t = trip
            let newStatus: TripStatus
            if let dep = trip.firstDeparture, let arr = trip.finalArrival {
                if now < dep { newStatus = .upcoming }
                else if now <= arr.addingTimeInterval(8 * 86_400) { newStatus = .active }
                else { newStatus = .completed }
            } else {
                newStatus = trip.status
            }
            if newStatus != t.status { t.status = newStatus; changed = true }
            return t
        }
        if changed { await persist() }
    }

    // MARK: - Actions on actions

    func setCompletion(_ completion: CompletionState, for action: PlanAction, in trip: Trip) async {
        guard var plan = plan(for: trip) else { return }
        guard let index = plan.actions.firstIndex(where: { $0.id == action.id }) else { return }
        plan.actions[index].completion = completion
        replacePlan(plan)
        await persist()
        mirrorProgress(action: action, completion: completion, trip: trip)

        switch completion {
        case .done:
            celebration = CelebrationEvent(type: action.type)
            deps.analytics.track(.actionCompleted(type: action.type.rawValue, priority: action.priority.rawValue))
            await deps.notifications.cancel(notificationIDsPrefixed: "r\(plan.revision)/\(action.id.uuidString)")
        case .notPossible, .skipped, .sleptInstead:
            deps.analytics.track(.actionSkipped(type: action.type.rawValue, priority: action.priority.rawValue))
            await deps.notifications.cancel(notificationIDsPrefixed: "r\(plan.revision)/\(action.id.uuidString)")
            // A missed key action changes the trajectory — recalculate the future.
            if action.type == .sleep || action.type == .seekLight {
                await recalculate(trip: trip, trigger: "missed_action")
            }
        case .pending, .expired:
            break
        }
    }

    func snooze(action: PlanAction, in trip: Trip, minutes: Double = 30) async {
        guard let plan = plan(for: trip) else { return }
        await deps.notifications.snooze(
            actionID: action.id,
            revision: plan.revision,
            title: action.title,
            body: action.instruction,
            fireDate: deps.now().addingTimeInterval(minutes * 60)
        )
    }

    // MARK: - Replanning

    func reportDelay(trip: Trip, segmentID: UUID, newDeparture: Date, newArrival: Date) async {
        let updated = deps.coordinator.applyingDelay(
            to: trip, segmentID: segmentID, newDeparture: newDeparture, newArrival: newArrival
        )
        guard let index = state.trips.firstIndex(where: { $0.id == trip.id }) else { return }
        state.trips[index] = updated
        if let original = trip.segments.first(where: { $0.id == segmentID }) {
            let minutes = Int(newDeparture.timeIntervalSince(original.departure) / 60)
            deps.analytics.track(.flightDelayReported(delayMinutes: minutes))
        }
        await recalculate(trip: updated, trigger: "delay_reported")
    }

    func recalculate(trip: Trip, trigger: String) async {
        guard let profile = state.profile, let previous = plan(for: trip) else { return }
        let asOf = deps.now()
        let events = state.travelerState(forTrip: trip.id)?.events ?? []
        let travelerState = deps.coordinator.estimateState(
            plan: previous, trip: trip, events: events, asOf: asOf
        )
        state.setTravelerState(travelerState, forTrip: trip.id)
        do {
            let result = try deps.coordinator.replan(
                trip: trip, profile: profile, previousPlan: previous, state: travelerState
            )
            replacePlan(result.plan)
            lastChangeMessages = result.changeMessages
            if var t = state.trips.first(where: { $0.id == trip.id }),
               let index = state.trips.firstIndex(where: { $0.id == trip.id }) {
                t.lastRecalculatedAt = asOf
                state.trips[index] = t
            }
            await persist()
            await rescheduleNotifications(trip: trip, plan: result.plan, cancellingRevision: previous.revision)
            deps.analytics.track(.planRecalculated(trigger: trigger))
        } catch {
            activeAlert = AppAlert(
                title: "Couldn't update the plan",
                message: "We kept your current plan. If a flight changed, check its new times in Trip settings."
            )
        }
    }

    private func regeneratePlan(for trip: Trip, trigger: String) async {
        guard let profile = state.profile else { return }
        if plan(for: trip) != nil {
            await recalculate(trip: trip, trigger: trigger)
        } else if let plan = try? deps.engine.generatePlan(trip: trip, profile: profile, currentState: nil) {
            replacePlan(plan)
            await persist()
            await rescheduleNotifications(trip: trip, plan: plan)
        }
    }

    private func replacePlan(_ plan: JetLagPlan) {
        state.plans.removeAll { $0.tripID == plan.tripID }
        state.plans.append(plan)
    }

    // MARK: - Notifications

    func requestNotificationPermission() async -> Bool {
        let granted = await deps.notifications.requestPermission()
        deps.analytics.track(.notificationPermission(granted: granted))
        if granted {
            await rescheduleAllNotifications()
        }
        return granted
    }

    private func rescheduleNotifications(trip: Trip, plan: JetLagPlan, cancellingRevision: Int? = nil) async {
        guard let profile = state.profile, profile.notifications.enabled else {
            // Reminders were turned off: pending notifications must die with the setting.
            await deps.notifications.cancelEverything()
            return
        }
        if let old = cancellingRevision {
            await deps.notifications.cancel(notificationIDsPrefixed: "r\(old)/")
        }
        let planner = NotificationPlanner(configuration: PlanEngineConfiguration())
        let planned = planner.plannedNotifications(
            plan: plan, trip: trip, profile: profile, after: deps.now()
        )
        await deps.notifications.schedule(planned)
    }

    /// Clears every Reclock notification and rebuilds the schedule for all live trips.
    /// The blunt-but-correct tool for cross-trip changes (deletion, sample exit,
    /// reminders re-enabled): per-trip cancellation can't distinguish trips, and a
    /// missing reminder is worse than a rebuilt one.
    func rescheduleAllNotifications() async {
        await deps.notifications.cancelEverything()
        guard let profile = state.profile, profile.notifications.enabled else { return }
        let planner = NotificationPlanner(configuration: PlanEngineConfiguration())
        for trip in state.trips where trip.status == .upcoming || trip.status == .active {
            guard let plan = plan(for: trip) else { continue }
            let planned = planner.plannedNotifications(
                plan: plan, trip: trip, profile: profile, after: deps.now()
            )
            await deps.notifications.schedule(planned)
        }
    }

    // MARK: - Survey & data

    func submitSurvey(_ survey: PostTripSurvey) async {
        state.surveys.append(survey)
        if let index = state.trips.firstIndex(where: { $0.id == survey.tripID }) {
            state.trips[index].status = .completed
        }
        deps.analytics.track(.postTripSurveyCompleted(
            severity: survey.severity, usefulness: survey.usefulness, adherence: survey.adherence.rawValue
        ))
        await persist()
    }

    func exportData() async -> Data? {
        try? await deps.store.exportData()
    }

    func deleteAllData() async {
        for trip in state.trips {
            await deps.notifications.cancelAll(forTrip: trip.id)
        }
        try? await deps.store.wipe()
        state = AppState()
        await deps.notifications.cancelEverything()
    }

    func updateSettings(_ settings: AppSettings) async {
        state.settings = settings
        await persist()
    }

    // MARK: - Demo data

    func seedDemoData() async {
        // Landing-day snapshot of the flagship demo trip, so the home screen is alive.
        let reference = deps.now().addingTimeInterval(-5 * 86_400)
        // Never clobber a real profile: only seed the placeholder when none exists.
        if state.profile == nil {
            var demoProfile = DemoTrips.defaultProfile(homeZone: TimeZone.current.identifier)
            demoProfile.melatonin = .includeOptionalReminders
            state.profile = demoProfile
        }
        state.onboardingComplete = true
        let profile = state.profile!
        let trip = DemoTrips.newYorkToHelsinki(reference: reference)
        if let plan = try? deps.engine.generatePlan(trip: trip, profile: profile, currentState: nil) {
            state.trips.removeAll { $0.id == trip.id }
            state.plans.removeAll { $0.tripID == trip.id }
            state.trips.append(trip)
            state.plans.append(plan)
            state.settings.selectedTripID = trip.id
        }
        await persist()
    }

    func loadFixture(_ pair: (trip: Trip, profile: UserProfile), reference: Date) async {
        state.profile = pair.profile
        state.onboardingComplete = true
        if let plan = try? deps.engine.generatePlan(trip: pair.trip, profile: pair.profile, currentState: nil) {
            state.trips.removeAll { $0.id == pair.trip.id }
            state.plans.removeAll { $0.tripID == pair.trip.id }
            state.trips.append(pair.trip)
            state.plans.append(plan)
            await persist()
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}
