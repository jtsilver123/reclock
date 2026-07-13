import SwiftUI
import ReclockKit

/// The Trips tab: every plan you're running — add one, join a friend's, open a trip
/// for its flights and buddies, clean up the past. Viewing happens on the Plan tab.
struct TripsListView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddTrip = false
    @State private var showJoin = false
    @State private var pendingDelete: Trip?
    @State private var showClearPast = false
    @State private var buddiesTrip: Trip?
    @State private var buddyCounts: [UUID: Int] = [:]

    var body: some View {
        NavigationStack {
            List {
                // The tab's whole reason to exist, drawn at hero size.
                Section {
                    Button {
                        Haptics.soft()
                        showAddTrip = true
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Add a trip")
                                    .font(Theme.display(26))
                                    .foregroundStyle(Theme.ink)
                                Text("Flight number in, plan out.")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.ink.opacity(0.72))
                            }
                            Spacer(minLength: Theme.Space.s)
                            Image(systemName: "airplane.departure")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .accessibilityHidden(true)
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.accent)
                                .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 6)
                        )
                        .grain()
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityIdentifier("trips.add")
                    .accessibilityLabel("Add a trip")
                    .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.m,
                                              bottom: Theme.Space.xs, trailing: Theme.Space.m))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Button {
                        showJoin = true
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: "person.2.fill")
                                .font(.footnote.weight(.semibold))
                            Text("Join a friend's trip")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accentDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.s)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(PressableCardStyle())
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.m,
                                              bottom: Theme.Space.s, trailing: Theme.Space.m))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if model.state.trips.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No trips yet",
                            systemImage: "airplane",
                            description: Text("Add your first trip and the plan appears instantly.")
                        )
                    }
                }

                if !currentTrips.isEmpty {
                    Section {
                        ForEach(currentTrips) { trip in
                            tripRow(trip)
                        }
                    } footer: {
                        Text("Tap a trip for flights, travel buddies, and changes. The Plan tab follows your current or next trip on its own — switch trips at the top of it.")
                    }
                }

                if !pastTrips.isEmpty {
                    Section {
                        ForEach(pastTrips) { trip in
                            tripRow(trip)
                                .opacity(0.6)
                        }
                        Button(role: .destructive) {
                            showClearPast = true
                        } label: {
                            Label("Clear all past trips", systemImage: "trash")
                        }
                    } header: {
                        Text("Past trips")
                    } footer: {
                        Text("Finished trips keep their plans for reference. Clearing removes them — and their reminders — for good.")
                    }
                }
            }
            .navigationTitle("Trips")
            .contentMargins(.bottom, 84, for: .scrollContent)
            .sheet(isPresented: $showAddTrip) {
                AddTripFlow()
            }
            .sheet(isPresented: $showJoin) {
                NavigationStack { JoinPlanView() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $buddiesTrip) { trip in
                NavigationStack {
                    List {
                        TravelBuddiesSection(trip: trip)
                    }
                    .navigationTitle("\(trip.origin) → \(trip.destination)")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .task(id: taskKey) {
                await refreshBuddyCounts()
            }
            .confirmationDialog(
                "Clear \(pastTrips.count) past trip\(pastTrips.count == 1 ? "" : "s")?",
                isPresented: $showClearPast,
                titleVisibility: .visible
            ) {
                Button("Clear past trips", role: .destructive) {
                    Task {
                        for trip in pastTrips {
                            await model.deleteTrip(trip)
                        }
                    }
                }
            } message: {
                Text("Removes finished trips, their plans, and any leftover reminders. There's no undo.")
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "trip")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { trip in
                Button("Delete trip and plan", role: .destructive) {
                    Task { await model.deleteTrip(trip) }
                }
            } message: { _ in
                Text("Removes the trip, its plan, and its reminders. There's no undo.")
            }
        }
    }

    private var sortedTrips: [Trip] {
        model.state.trips.sorted {
            ($0.firstDeparture ?? .distantPast) > ($1.firstDeparture ?? .distantPast)
        }
    }

    private var currentTrips: [Trip] { sortedTrips.filter { $0.status != .completed } }
    private var pastTrips: [Trip] { sortedTrips.filter { $0.status == .completed } }

    /// Re-fetch buddy counts when trips or share states change.
    private var taskKey: String {
        model.state.trips.map { "\($0.id):\($0.sharedPlanCode ?? "-")" }.joined()
    }

    private func refreshBuddyCounts() async {
        guard model.auth.isSignedIn else { return }
        for trip in currentTrips where trip.sharedPlanCode != nil {
            if let board = await model.fetchBuddyBoard(for: trip) {
                buddyCounts[trip.id] = board.members.count
            }
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            TripListRow(
                trip: trip,
                isOnPlanTab: model.activeTrip?.id == trip.id,
                buddyCount: buddyCounts[trip.id],
                onBuddies: {
                    Haptics.selection()
                    buddiesTrip = trip
                }
            )
        }
        .accessibilityIdentifier("trips.row")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDelete = trip
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct TripListRow: View {
    let trip: Trip
    let isOnPlanTab: Bool
    let buddyCount: Int?
    var onBuddies: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: isOnPlanTab ? "sun.horizon.fill" : "airplane.circle.fill")
                .font(.title2)
                .foregroundStyle(trip.status == .completed ? Theme.textSecondary : Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.origin) → \(trip.destination)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.s)

            // Who's on this plan — or the door to inviting someone.
            if trip.status != .completed {
                Button(action: onBuddies) {
                    HStack(spacing: 3) {
                        Image(systemName: trip.sharedPlanCode == nil ? "person.badge.plus" : "person.2.fill")
                            .font(.footnote.weight(.semibold))
                        if let buddyCount, trip.sharedPlanCode != nil {
                            Text("\(buddyCount)")
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                    }
                    .foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: 30)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(trip.sharedPlanCode == nil
                    ? "Invite a friend to this trip"
                    : "Travel buddies\(buddyCount.map { ": \($0) on this plan" } ?? "")")
            }

            statusCapsule
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusCapsule: some View {
        if isOnPlanTab {
            Text("On Plan")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.4), in: Capsule())
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Currently shown on the Plan tab")
        } else {
            Text(statusText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 3)
                .background(Theme.surfaceSecondary, in: Capsule())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var statusText: String {
        switch trip.status {
        case .upcoming: "Next up"
        case .active: "Current"
        case .completed: "Done"
        case .archived: "Archived"
        }
    }

    private var dateRange: String {
        guard let dep = trip.firstDeparture else { return "" }
        let zone = trip.homeZone.resolved
        let start = TimeFormat.dayDate(dep, zone: zone)
        if let arr = trip.finalArrival, let nights = trip.destinationNights, nights > 0 {
            _ = arr
            return "\(start) · \(nights) night\(nights == 1 ? "" : "s")"
        }
        return start
    }
}
