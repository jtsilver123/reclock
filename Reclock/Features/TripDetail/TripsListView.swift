import SwiftUI
import ReclockKit

/// All trips in one place: tap to focus Today/Timeline on a trip, swipe to delete.
struct TripsListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showAddTrip = false
    @State private var pendingDelete: Trip?

    var body: some View {
        NavigationStack {
            List {
                if model.state.trips.isEmpty {
                    ContentUnavailableView(
                        "No trips yet",
                        systemImage: "airplane",
                        description: Text("Add your first trip and the plan appears instantly.")
                    )
                } else {
                    Section {
                        ForEach(sortedTrips) { trip in
                            TripListRow(
                                trip: trip,
                                isFocused: model.activeTrip?.id == trip.id,
                                isAutomaticChoice: model.automaticTrip?.id == trip.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Task {
                                    // Selecting the automatic choice clears the pin.
                                    let id = model.automaticTrip?.id == trip.id ? nil : trip.id
                                    await model.selectTrip(id)
                                    dismiss()
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = trip
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("Tap a trip to focus Today and Timeline on it. Reclock follows your current or next trip automatically unless you choose one.")
                    }
                }
            }
            .navigationTitle("My trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
}

private struct TripListRow: View {
    let trip: Trip
    let isFocused: Bool
    let isAutomaticChoice: Bool

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "airplane.circle.fill")
                .font(.title2)
                .foregroundStyle(isFocused ? Theme.accent : Theme.textSecondary)
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
            if isFocused {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Currently shown on Today")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isFocused ? [.isSelected] : [])
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
