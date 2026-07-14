import SwiftUI
import AuthenticationServices
import ReclockKit

/// Trip-detail section: share this plan with travel buddies and cheer each other on.
/// Each member gets a row of checkmarks for today's actions — done lights up green.
struct TravelBuddiesSection: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    @State private var board: AppModel.BuddyBoard?
    @State private var isCreating = false
    @State private var kudosSentTo: Set<String> = []

    var body: some View {
        Section {
            if let code = trip.sharedPlanCode {
                sharedContent(code: code)
            } else if model.auth.isSignedIn {
                Button {
                    Task {
                        isCreating = true
                        defer { isCreating = false }
                        _ = await model.createSharedPlan(for: trip)
                    }
                } label: {
                    if isCreating {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Invite a travel buddy", systemImage: "person.2.fill")
                    }
                }
                .disabled(isCreating)
            } else {
                Text("Traveling with someone? Sign in and you can share this plan — you'll see each other's progress and send kudos.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                SignInWithAppleButton(.signIn) { request in
                    model.auth.prepare(request)
                } onCompletion: { result in
                    Task {
                        if await model.auth.complete(result) {
                            Haptics.success()
                            await model.handleSignedIn()
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if model.auth.googleAvailable {
                    GoogleSignInButton {
                        Task {
                            if await model.auth.signInWithGoogle() {
                                Haptics.success()
                                await model.handleSignedIn()
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            Text("Travel buddies")
        } footer: {
            if trip.sharedPlanCode == nil && model.auth.isSignedIn {
                Text("Creates an invite code for this trip. Buddies get the same plan and you all see each other's checkmarks.")
            }
        }
        .task(id: trip.sharedPlanCode) {
            if trip.sharedPlanCode != nil {
                board = await model.fetchBuddyBoard(for: trip)
            }
        }
    }

    @ViewBuilder
    private func sharedContent(code: String) -> some View {
        ShareLink(item: AppLinks.inviteMessage(code: code, route: "\(trip.origin) → \(trip.destination)")) {
            HStack {
                Label("Invite with code", systemImage: "square.and.arrow.up")
                Spacer()
                Text(code)
                    .font(.headline.monospaced())
                    .foregroundStyle(Theme.accentDeep)
            }
        }

        if let board {
            ForEach(board.members) { member in
                BuddyRow(
                    member: member,
                    isMe: member.userID == board.myUserID,
                    doneIDs: board.doneByUser[member.userID] ?? [],
                    todaysActions: todaysActions,
                    kudosSent: kudosSentTo.contains(member.userID),
                    sendKudos: {
                        Task {
                            if await model.sendKudos(to: member, trip: trip, emoji: "👏") {
                                Haptics.success()
                                kudosSentTo.insert(member.userID)
                            }
                        }
                    }
                )
            }
            if board.members.count == 1 {
                Text("Just you so far — send the invite.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            HStack {
                ProgressView()
                Text("Loading buddies…")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Today's waking actions, in order — the checkmark strip everyone shares.
    private var todaysActions: [PlanAction] {
        guard let plan = model.plan(for: trip) else { return [] }
        let now = model.deps.now()
        guard let today = plan.days.first(where: {
            $0.dayStart <= now && now < $0.dayStart.addingTimeInterval(86_400)
        }) else { return [] }
        return plan.actions(onDay: today.index)
            .filter { $0.type != .sleep }
            .sorted { $0.window.start < $1.window.start }
    }
}

private struct BuddyRow: View {
    let member: PlanMember
    let isMe: Bool
    let doneIDs: Set<UUID>
    let todaysActions: [PlanAction]
    let kudosSent: Bool
    let sendKudos: () -> Void

    private var doneCount: Int {
        todaysActions.filter { doneIDs.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                ZStack {
                    Circle().fill(Theme.accent.opacity(isMe ? 0.9 : 0.25))
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isMe ? Theme.ink : Theme.textPrimary)
                }
                .frame(width: 32, height: 32)
                Text(isMe ? "\(member.displayName) (you)" : member.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.Space.s)
                if !todaysActions.isEmpty {
                    Text("\(doneCount)/\(todaysActions.count) today")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                if !isMe {
                    Button(action: sendKudos) {
                        Text(kudosSent ? "Sent 👏" : "👏")
                            .font(.subheadline)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, 4)
                            .background(Theme.surfaceSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(kudosSent)
                    .accessibilityLabel(kudosSent
                        ? "Kudos sent to \(member.displayName)"
                        : "Send kudos to \(member.displayName)")
                }
            }
            if !todaysActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(todaysActions.prefix(10)) { action in
                        Image(systemName: doneIDs.contains(action.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(doneIDs.contains(action.id)
                                             ? Color.green : Theme.textSecondary.opacity(0.5))
                            .accessibilityLabel("\(action.title): \(doneIDs.contains(action.id) ? "done" : "not yet")")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
