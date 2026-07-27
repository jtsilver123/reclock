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
    @State private var lastBuddyRefresh: Date?

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
                        Haptics.soft()
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
            .animation(Theme.Anim.spring, value: model.state.trips.map(\.id))
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
                    .navigationTitle("\(model.originName(for: trip)) → \(trip.destination)")
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
                    // One persist and one notification rebuild — not one per trip.
                    Task { await model.deleteTrips(pastTrips) }
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

    private var currentTrips: [Trip] {
        sortedTrips.filter { $0.status != .completed && $0.status != .archived }
    }
    private var pastTrips: [Trip] {
        sortedTrips.filter { $0.status == .completed || $0.status == .archived }
    }

    /// Re-fetch buddy counts when trips or share states change.
    private var taskKey: String {
        model.state.trips.map { "\($0.id):\($0.sharedPlanCode ?? "-")" }.joined()
    }

    private func refreshBuddyCounts() async {
        guard model.auth.isSignedIn else { return }
        // Fresh enough: a tab flip within a minute must not refetch every board.
        if let last = lastBuddyRefresh, Date().timeIntervalSince(last) < 60 { return }
        lastBuddyRefresh = Date()
        // Boards load concurrently — three shared trips took three round trips.
        let shared = currentTrips.filter { $0.sharedPlanCode != nil }
        await withTaskGroup(of: (UUID, Int)?.self) { group in
            for trip in shared {
                group.addTask { @MainActor in
                    guard let board = await model.fetchBuddyBoard(for: trip) else { return nil }
                    return (trip.id, board.members.count)
                }
            }
            for await result in group {
                if let (id, count) = result { buddyCounts[id] = count }
            }
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            TripListRow(
                trip: trip,
                originName: model.originName(for: trip),
                isOnPlanTab: model.activeTrip?.id == trip.id,
                buddyCount: buddyCounts[trip.id]
            )
        }
        .accessibilityIdentifier("trips.row")
        .swipeActions(edge: .leading) {
            if trip.status != .completed {
                Button {
                    Haptics.selection()
                    buddiesTrip = trip
                } label: {
                    Label("Buddies", systemImage: "person.2.fill")
                }
                .tint(Theme.accentDeep)
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
}

private struct TripListRow: View {
    let trip: Trip
    let originName: String
    let isOnPlanTab: Bool
    let buddyCount: Int?

    private var isPast: Bool { trip.status == .completed || trip.status == .archived }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ZStack {
                Circle()
                    .fill((isPast ? Theme.textSecondary : Theme.accent).opacity(0.15))
                Image(systemName: isOnPlanTab ? "sun.horizon.fill" : "airplane")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPast ? Theme.textSecondary : Theme.accentDeep)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(originName) → \(trip.destination)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                SwiftUI.TimelineView(.everyMinute) { timeline in
                    Text(isPast
                         ? dateRange(now: timeline.date)
                         : "\(dateRange(now: timeline.date)) · \(TimeFormat.time(timeline.date, zone: trip.destinationZone.resolved)) there")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.numericText())
                        .animation(Theme.Anim.gentle,
                                   value: TimeFormat.time(timeline.date, zone: trip.destinationZone.resolved))
                }
            }
            Spacer(minLength: Theme.Space.s)

            // Who's on this plan, at a glance. Display only — interactive views
            // nested in a NavigationLink row hijack row taps (it broke navigation
            // in two UI tests). Buddies open via leading swipe or inside the trip.
            if !isPast {
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
                .accessibilityLabel(trip.sharedPlanCode == nil
                    ? "No travel buddies yet"
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
                .background(Theme.accent.opacity(0.12), in: Capsule())
                .foregroundStyle(Theme.accentDeep)
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

    private func dateRange(now: Date) -> String {
        guard let dep = trip.firstDeparture else { return "" }
        let zone = trip.homeZone.resolved
        var start = TimeFormat.dayDate(dep, zone: zone)
        // Upcoming trips answer the first question — "how soon?" — up front.
        if trip.status == .upcoming, dep > now {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let days = cal.dateComponents(
                [.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: dep)
            ).day ?? 0
            switch days {
            case 0: start = "Today · \(start)"
            case 1: start = "Tomorrow · \(start)"
            default: start = "In \(days) days · \(start)"
            }
        }
        if let nights = trip.destinationNights, nights > 0 {
            return "\(start) · \(nights) night\(nights == 1 ? "" : "s")"
        }
        return start
    }
}
