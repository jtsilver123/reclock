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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Haptics.soft()
                        showAddTrip = true
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Theme.accent))
                                .accessibilityHidden(true)
                            Text("Add a trip")
                                .font(.headline)
                                .fontDesign(.rounded)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("trips.add")

                    Button {
                        showJoin = true
                    } label: {
                        Label("Join a friend's trip", systemImage: "person.2.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accentDeep)
                    }
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
            .sheet(isPresented: $showAddTrip) {
                AddTripFlow()
            }
            .sheet(isPresented: $showJoin) {
                NavigationStack { JoinPlanView() }
                    .presentationDetents([.medium, .large])
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

    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            TripListRow(trip: trip)
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

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "airplane.circle.fill")
                .font(.title2)
                .foregroundStyle(trip.status == .completed ? Theme.textSecondary : Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.origin) → \(trip.destination)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(statusText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 3)
                .background(Theme.surfaceSecondary, in: Capsule())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
