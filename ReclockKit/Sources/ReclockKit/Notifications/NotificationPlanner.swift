import Foundation

/// A notification the app should schedule. Pure data — the app layer adapts these to
/// `UNNotificationRequest`s; tests exercise this planner directly.
public struct PlannedNotification: Sendable, Hashable, Identifiable {
    /// Deterministic identity: `r<revision>/<actionID>/<kind>`. Replacing a plan revision
    /// replaces the entire notification set without touching unrelated notifications.
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
    public var categoryID: String
    public var actionID: UUID
    public var kind: Kind
    /// Missing this notification has immediate real-world cost (e.g. leave-for-airport),
    /// so delivery may break through Focus modes where the platform supports it.
    public var isTimeCritical: Bool

    public enum Kind: String, Sendable {
        case start          // action window is beginning
        case reminder       // lead-up (e.g. "try to sleep in 30 minutes")
        case cutoff         // hard stop (e.g. last caffeine)
    }

    public init(id: String, fireDate: Date, title: String, body: String, categoryID: String, actionID: UUID, kind: Kind, isTimeCritical: Bool = false) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.categoryID = categoryID
        self.actionID = actionID
        self.kind = kind
        self.isTimeCritical = isTimeCritical
    }
}

public enum NotificationCategory {
    /// Actionable plan step: Done / Snooze / Couldn't do it.
    public static let planAction = "RECLOCK_PLAN_ACTION"
    /// Informational: Open plan.
    public static let planInfo = "RECLOCK_PLAN_INFO"
}

/// Turns a plan into a bounded, deduplicated, quiet-hours-respecting notification schedule.
public struct NotificationPlanner: Sendable {
    public let configuration: PlanEngineConfiguration

    /// Per-day cap by intensity, so Easy stays quiet and Maximum stays tolerable.
    public static let dailyCaps: [PlanIntensity: Int] = [
        .easy: 3, .balanced: 5, .maximum: 7,
    ]

    public init(configuration: PlanEngineConfiguration = PlanEngineConfiguration()) {
        self.configuration = configuration
    }

    public func plannedNotifications(
        plan: JetLagPlan,
        trip: Trip,
        profile: UserProfile,
        after: Date
    ) -> [PlannedNotification] {
        guard profile.notifications.enabled else { return [] }
        var results: [PlannedNotification] = []
        let zoneTimeline = ZoneTimeline(trip: trip)

        for action in plan.actions {
            guard action.notificationEnabled else { continue }
            guard action.completion == .pending else { continue }
            if action.priority == .optional && !profile.notifications.includeOptionalActions { continue }

            for candidate in notifications(for: action, revision: plan.revision) {
                guard candidate.fireDate > after else { continue }
                let adjusted = respectQuietHours(
                    candidate,
                    action: action,
                    profile: profile,
                    zoneTimeline: zoneTimeline
                )
                if let adjusted { results.append(adjusted) }
            }
        }

        results = dedupe(results)
        results = applyDailyCaps(results, plan: plan, trip: trip)
        return results.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Per-action notifications

    private func notifications(for action: PlanAction, revision: Int) -> [PlannedNotification] {
        func make(_ kind: PlannedNotification.Kind, at date: Date, title: String, body: String, category: String = NotificationCategory.planAction) -> PlannedNotification {
            PlannedNotification(
                id: "r\(revision)/\(action.id.uuidString)/\(kind.rawValue)",
                fireDate: date,
                title: title,
                body: body,
                categoryID: category,
                actionID: action.id,
                kind: kind,
                // Only leave-for-airport breaks through Focus: missing it forfeits the
                // flight. Everything else respects the user's attention settings.
                isTimeCritical: action.type == .leaveForAirport
            )
        }

        switch action.type {
        case .sleep:
            // Lead-up only; a notification *at* bedtime would fire mid-wind-down.
            return [make(.reminder,
                         at: action.window.start.adding(minutes: -30),
                         title: "Bed in 30 minutes",
                         body: "Start heading for bed — tonight's window is \(action.title == "Sleep on the flight" ? "on the flight" : "coming up").")]
        case .nap:
            return [make(.start, at: action.window.start,
                         title: "Nap window open",
                         body: "If you need it: \(Int(configuration.maxNapMinutes)) minutes max, alarm set.")]
        case .seekLight:
            return [make(.start, at: action.window.start,
                         title: action.title,
                         body: "Now through the next couple of hours is your light window — it's the strongest lever you have.")]
        case .avoidLight:
            return [make(.start, at: action.window.start,
                         title: "Sunglasses time",
                         body: "Bright light right now would push your clock the wrong way — keep things dim for a bit.")]
        case .stayAwake:
            return [make(.start, at: action.window.start,
                         title: "Push through to bedtime",
                         body: "The hard part starts now. Stay busy and upright — bed comes at the planned time.")]
        case .caffeineCutoff:
            return [make(.cutoff, at: action.window.start,
                         title: "Last call for caffeine",
                         body: "After this, switch to water or decaf so tonight's sleep can do its job.")]
        case .melatoninOptional:
            return [make(.reminder, at: action.window.start,
                         title: "Melatonin window, if you're using it",
                         body: "If you've chosen to use it, now is the time that supports your shift.")]
        case .windDown:
            return [make(.start, at: action.window.start,
                         title: "Start dimming the lights",
                         body: "Screens away, lights low — give your body a runway into tonight's sleep.")]
        case .switchToDestinationTime:
            return [make(.start, at: action.window.start,
                         title: "Switch to destination time",
                         body: "Change your watch and start living on arrival time.",
                         category: NotificationCategory.planInfo)]
        case .leaveForAirport:
            return [make(.start, at: action.window.start,
                         title: "Time to get moving",
                         body: "Pack up and head for the airport — this window covers your ride plus check-in and security.")]
        case .caffeineOK, .shiftMeals, .hydrate, .moveBody, .checkIn, .recalculate:
            return []
        }
    }

    // MARK: - Quiet hours

    /// Shifts or drops notifications that would fire inside quiet hours (in the zone the
    /// traveler occupies at fire time). Sleep-adjacent notifications are exempt: a wind-down
    /// or sleep reminder *should* fire late.
    func respectQuietHours(
        _ notification: PlannedNotification,
        action: PlanAction,
        profile: UserProfile,
        zoneTimeline: ZoneTimeline
    ) -> PlannedNotification? {
        // Sleep-adjacent notifications belong near bedtime; leave-by is time-critical
        // logistics (a 5 AM airport run must ring at 5 AM). Neither defers to quiet hours.
        let exemptTypes: Set<ActionType> = [.sleep, .windDown, .nap, .melatoninOptional, .leaveForAirport]
        if exemptTypes.contains(action.type) { return notification }

        let zone = zoneTimeline.zone(at: notification.fireDate).resolved
        let cal = Calendar.gregorian(in: zone)
        let comps = cal.dateComponents([.hour, .minute], from: notification.fireDate)
        let clock = LocalClockTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
        guard profile.notifications.quietHours.contains(clock) else { return notification }

        // Inside quiet hours: move to the end of quiet hours if the action window will still
        // be running then; otherwise drop it.
        let quietEnd = profile.notifications.quietHours.end
        var fireDay = cal.startOfDay(for: notification.fireDate)
        if clock >= profile.notifications.quietHours.start && profile.notifications.quietHours.wrapsMidnight {
            fireDay = cal.date(byAdding: .day, value: 1, to: fireDay) ?? fireDay
        }
        guard let newFire = quietEnd.date(on: fireDay, in: zone) else { return nil }
        guard newFire < action.window.end else { return nil }
        return PlannedNotification(
            id: notification.id,
            fireDate: newFire,
            title: notification.title,
            body: notification.body,
            categoryID: notification.categoryID,
            actionID: notification.actionID,
            kind: notification.kind,
            isTimeCritical: notification.isTimeCritical
        )
    }

    // MARK: - Dedupe & caps

    private func dedupe(_ notifications: [PlannedNotification]) -> [PlannedNotification] {
        var seenIDs = Set<String>()
        var seenSlots = Set<String>()
        var kept: [PlannedNotification] = []
        for n in notifications.sorted(by: { $0.fireDate < $1.fireDate }) {
            guard !seenIDs.contains(n.id) else { continue }
            // Two notifications within 5 minutes with the same title are duplicates.
            let slot = "\(n.title)/\(Int(n.fireDate.timeIntervalSinceReferenceDate / 300))"
            guard !seenSlots.contains(slot) else { continue }
            seenIDs.insert(n.id)
            seenSlots.insert(slot)
            kept.append(n)
        }
        return kept
    }

    private func applyDailyCaps(
        _ notifications: [PlannedNotification],
        plan: JetLagPlan,
        trip: Trip
    ) -> [PlannedNotification] {
        let cap = Self.dailyCaps[trip.intensity] ?? 5
        let priorityByAction = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.id, $0) })
        var byDay: [String: [PlannedNotification]] = [:]
        let zoneTimeline = ZoneTimeline(trip: trip)

        for n in notifications {
            let zone = zoneTimeline.zone(at: n.fireDate).resolved
            let cal = Calendar.gregorian(in: zone)
            let comps = cal.dateComponents([.year, .month, .day], from: n.fireDate)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            byDay[key, default: []].append(n)
        }

        var kept: [PlannedNotification] = []
        for (_, group) in byDay {
            if group.count <= cap {
                kept.append(contentsOf: group)
                continue
            }
            // Time-critical notifications (leave-for-airport) are exempt from the
            // cap outright — "missing it forfeits the flight" must never lose a
            // ranking fight to three well-meaning sleep reminders on a busy day.
            let critical = group.filter(\.isTimeCritical)
            kept.append(contentsOf: critical)
            let group = group.filter { !$0.isTimeCritical }
            if group.count <= max(0, cap - critical.count) {
                kept.append(contentsOf: group)
                continue
            }
            let ranked = group.sorted { a, b in
                let pa = priorityByAction[a.actionID]?.priority ?? .optional
                let pb = priorityByAction[b.actionID]?.priority ?? .optional
                if pa != pb { return pa < pb }
                let ia = priorityByAction[a.actionID]?.impactScore ?? 0
                let ib = priorityByAction[b.actionID]?.impactScore ?? 0
                return ia > ib
            }
            kept.append(contentsOf: ranked.prefix(max(0, cap - critical.count)))
        }
        return kept
    }
}
