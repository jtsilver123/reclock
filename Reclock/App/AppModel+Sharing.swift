import Foundation
import Security
import ReclockKit

/// Travel buddies: share a trip's plan by code, join a friend's, mirror progress,
/// and cheer each other on. Everything requires sign-in (there's no anonymous write).
extension AppModel {

    private var shareClient: SupabaseAuthClient { SupabaseAuthClient() }

    var buddyDisplayName: String {
        if let email = auth.email, let prefix = email.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "Traveler"
    }

    // MARK: Create & share

    /// Publishes the trip + current plan under a fresh invite code and marks the local
    /// trip as shared. Returns the code, or nil (with an alert) on failure.
    func createSharedPlan(for trip: Trip) async -> String? {
        guard let session = try? await auth.validSession() else { return nil }
        guard let plan = plan(for: trip) else { return nil }
        let code = Self.makeInviteCode()
        do {
            try await shareClient.createSharedPlan(
                code: code,
                title: "\(trip.origin) → \(trip.destination)",
                trip: trip,
                plan: plan,
                session: session
            )
            try await shareClient.joinSharedPlan(
                code: code, displayName: buddyDisplayName, session: session
            )
            if let index = state.trips.firstIndex(where: { $0.id == trip.id }) {
                state.trips[index].sharedPlanCode = code
                state.trips[index].isSharedPlanOwner = true
                await persist()
            }
            deps.analytics.track(.importMethodSelected(method: "share_created"))
            return code
        } catch {
            activeAlert = AppAlert(
                title: "Couldn't create the invite",
                message: "Check your connection and try again."
            )
            return nil
        }
    }

    // MARK: Join

    /// Fetches a friend's shared plan by code. The caller shows a preview and then
    /// calls `acceptSharedPlan`.
    func fetchSharedPlan(code: String) async -> FetchedSharedPlan? {
        guard let session = try? await auth.validSession() else { return nil }
        return try? await shareClient.fetchSharedPlan(
            code: code.trimmingCharacters(in: .whitespaces).uppercased(),
            session: session
        )
    }

    /// Adds the friend's trip + plan to this device and registers membership.
    func acceptSharedPlan(_ fetched: FetchedSharedPlan) async -> Bool {
        guard let session = try? await auth.validSession() else { return false }
        // Same trip already present (tapped the link twice): just make sure we're a member.
        if !state.trips.contains(where: { $0.sharedPlanCode == fetched.code }) {
            var trip = fetched.trip
            trip.sharedPlanCode = fetched.code
            trip.isSharedPlanOwner = false
            state.trips.append(trip)
            state.plans.removeAll { $0.tripID == trip.id }
            state.plans.append(fetched.plan)
            state.settings.selectedTripID = trip.id
            await persist()
            await rescheduleAllNotifications()
        }
        do {
            try await shareClient.joinSharedPlan(
                code: fetched.code, displayName: buddyDisplayName, session: session
            )
        } catch {
            return false
        }
        deps.analytics.track(.importMethodSelected(method: "share_joined"))
        return true
    }

    // MARK: Progress mirroring

    /// Called after a local completion change on a shared trip. Best-effort.
    func mirrorProgress(action: PlanAction, completion: CompletionState, trip: Trip) {
        guard let code = trip.sharedPlanCode else { return }
        Task {
            guard let session = try? await auth.validSession() else { return }
            switch completion {
            case .done, .notPossible, .skipped, .sleptInstead:
                try? await shareClient.upsertProgress(
                    code: code,
                    actionID: action.id,
                    status: completion == .done ? "done" : "skipped",
                    session: session
                )
            case .pending, .expired:
                try? await shareClient.deleteProgress(
                    code: code, actionID: action.id, session: session
                )
            }
        }
    }

    // MARK: Buddies board

    struct BuddyBoard {
        var members: [PlanMember]
        var doneByUser: [String: Set<UUID>]
        var myUserID: String?
    }

    func fetchBuddyBoard(for trip: Trip) async -> BuddyBoard? {
        guard let code = trip.sharedPlanCode,
              let session = try? await auth.validSession() else { return nil }
        do {
            let members = try await shareClient.fetchMembers(code: code, session: session)
            let progress = try await shareClient.fetchProgress(code: code, session: session)
            var done: [String: Set<UUID>] = [:]
            for row in progress where row.status == "done" {
                done[row.userID, default: []].insert(row.actionID)
            }
            return BuddyBoard(members: members, doneByUser: done, myUserID: session.userID)
        } catch {
            return nil
        }
    }

    func sendKudos(to member: PlanMember, trip: Trip, emoji: String) async -> Bool {
        guard let code = trip.sharedPlanCode,
              let session = try? await auth.validSession() else { return false }
        do {
            try await shareClient.sendKudos(
                code: code,
                toUser: member.userID,
                fromName: buddyDisplayName,
                emoji: emoji,
                session: session
            )
            return true
        } catch {
            return false
        }
    }

    /// New kudos since last check, surfaced as a celebration. Marker in UserDefaults.
    func checkForKudos(trip: Trip) async {
        guard let code = trip.sharedPlanCode,
              let session = try? await auth.validSession() else { return }
        let key = "reclock.kudos.lastSeen.\(code)"
        let since = UserDefaults.standard.object(forKey: key) as? Date
            ?? Date().addingTimeInterval(-7 * 86_400)
        guard let received = try? await shareClient.fetchKudos(
            code: code, since: since, session: session
        ), let newest = received.first else { return }
        UserDefaults.standard.set(newest.createdAt, forKey: key)
        lastChangeMessages = received.prefix(3).map { "\($0.emoji) \($0.fromName) sent you kudos!" }
    }

    // MARK: Invite plumbing

    /// Unambiguous 6-char code (no 0/O/1/I/L).
    static func makeInviteCode() -> String {
        let charset = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")
        var bytes = [UInt8](repeating: 0, count: 6)
        _ = SecRandomCopyBytes(kSecRandomDefault, 6, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }
}

/// Canonical outward-facing links — Cini's pattern: a share message whose deep link
/// opens the app for installed users; everyone else follows the plain instructions.
/// When a hosted invite page exists (web/invite), point `inviteBase` at it and the
/// same message upgrades to a smart link automatically.
enum AppLinks {
    /// The hosted smart page: tries the app, shows the code + instructions otherwise.
    static let inviteBase: String? = "https://jtsilver123.github.io/reclock/invite/?c="
    static let scheme = "reclock"

    static func inviteLink(code: String) -> String {
        if let inviteBase {
            return "\(inviteBase)\(code)"
        }
        return "\(scheme)://join?c=\(code)"
    }

    static func inviteMessage(code: String, route: String) -> String {
        """
        Fly \(route) with me on Reclock — we'll beat jet lag together and see each other's progress.

        Have Reclock? Tap: \(inviteLink(code: code))
        New? Get Reclock on TestFlight, then choose "Join a friend's trip" and enter code \(code).
        """
    }
}
