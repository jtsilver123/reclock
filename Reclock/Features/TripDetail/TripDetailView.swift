import SwiftUI
import ReclockKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var showDelaySheet = false
    @State private var showDeleteConfirm = false
    @State private var showSurvey = false
    @State private var editingSegment: FlightSegment?
    @State private var showAddCommitment = false
    @State private var editingCommitment: FixedCommitment?

    private var currentTrip: Trip {
        model.state.trips.first { $0.id == trip.id } ?? trip
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(currentTrip.origin) → \(currentTrip.destination)")
                            .font(.title3.weight(.bold))
                        if let plan = model.plan(for: currentTrip) {
                            Text(shiftDescription(plan))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                }
                if let plan = model.plan(for: currentTrip) {
                    Text(plan.strategySummary)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                Label("Plan works fully offline once generated", systemImage: "airplane.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Section {
                ForEach(currentTrip.segments) { segment in
                    Button {
                        editingSegment = segment
                    } label: {
                        SegmentRow(segment: segment)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Flights")
            } footer: {
                Text("Tap a flight to correct its times.")
            }

            Section {
                ForEach(currentTrip.commitments) { commitment in
                    Button {
                        editingCommitment = commitment
                    } label: {
                        CommitmentRow(commitment: commitment)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await model.removeCommitment(id: commitment.id, from: currentTrip) }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Button {
                    showAddCommitment = true
                } label: {
                    Label("Add a commitment", systemImage: "plus.circle")
                }
            } header: {
                Text("Commitments the plan works around")
            } footer: {
                Text(currentTrip.commitments.isEmpty
                     ? "Work, a dinner, a wedding — add anything the plan must not schedule sleep or light windows over."
                     : "Sleep, naps, and light windows always route around these.")
            }

            Section("Plan style") {
                Picker("Intensity", selection: intensityBinding) {
                    ForEach(PlanIntensity.allCases, id: \.self) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                Text(currentTrip.intensity.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Picker("Start adjusting", selection: preTripBinding) {
                    Text("Automatic").tag(-1)
                    Text("On travel day").tag(0)
                    Text("1 day before").tag(1)
                    Text("2 days before").tag(2)
                    Text("3 days before").tag(3)
                    Text("4 days before").tag(4)
                }
                Text(preTripFootnote)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Picker("Getting to the airport", selection: transferBinding) {
                    ForEach([20, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                Text("Door to terminal. Sets the leave-by reminder and keeps sleep clear of the airport run — for departure and return.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                if currentTrip.destinationNights.map({ $0 <= 3 }) == true {
                    Picker("Adaptation", selection: strategyBinding) {
                        Text("Automatic").tag(AdaptationStrategy.automatic)
                        Text("Fully adapt").tag(AdaptationStrategy.fullyAdapt)
                        Text("Stay on home time").tag(AdaptationStrategy.anchorToHome)
                    }
                }
            }

            Section {
                Button {
                    showDelaySheet = true
                } label: {
                    Label("My flight changed / was delayed", systemImage: "clock.badge.exclamationmark")
                }
                Button {
                    Task { await model.recalculate(trip: currentTrip, trigger: "manual") }
                } label: {
                    Label("Recalculate plan", systemImage: "arrow.triangle.2.circlepath")
                }
                if currentTrip.status == .active || currentTrip.status == .completed {
                    Button {
                        showSurvey = true
                    } label: {
                        Label("How did it go? (post-trip check-in)", systemImage: "checklist")
                    }
                }
                if let shareText = model.shareText(for: currentTrip) {
                    ShareLink(item: shareText) {
                        Label("Share my plan", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete trip", systemImage: "trash")
                }
            } footer: {
                Text("Deleting removes this trip, its plan, and its notifications from your device.")
            }
        }
        .navigationTitle(currentTrip.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDelaySheet) {
            ReportDelayView(trip: currentTrip)
        }
        .sheet(isPresented: $showSurvey) {
            PostTripSurveyView(trip: currentTrip)
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditSheet(trip: currentTrip, segment: segment)
        }
        .sheet(isPresented: $showAddCommitment) {
            CommitmentFormView(trip: currentTrip, existing: nil)
        }
        .sheet(item: $editingCommitment) { commitment in
            CommitmentFormView(trip: currentTrip, existing: commitment)
        }
        .confirmationDialog(
            "Delete this trip?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete trip and plan", role: .destructive) {
                Task {
                    await model.deleteTrip(currentTrip)
                    dismiss()
                }
            }
        } message: {
            Text("This removes the trip, its plan, and scheduled reminders. There's no undo.")
        }
    }

    private func shiftDescription(_ plan: JetLagPlan) -> String {
        let hours = abs(Int(plan.requiredShiftHours.rounded()))
        switch plan.shiftDirection {
        case .none: return "No body-clock shift needed"
        case .advance: return "\(hours)h shift · body clock moves earlier"
        case .delay: return "\(hours)h shift · body clock moves later"
        }
    }

    private var intensityBinding: Binding<PlanIntensity> {
        Binding(
            get: { currentTrip.intensity },
            set: { newValue in
                var updated = currentTrip
                updated.intensity = newValue
                model.deps.analytics.track(.planModeSelected(intensity: newValue.rawValue))
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private var strategyBinding: Binding<AdaptationStrategy> {
        Binding(
            get: { currentTrip.adaptationStrategy },
            set: { newValue in
                var updated = currentTrip
                updated.adaptationStrategy = newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private var transferBinding: Binding<Int> {
        Binding(
            get: { currentTrip.airportTransferMinutes ?? 60 },
            set: { newValue in
                var updated = currentTrip
                updated.airportTransferMinutes = newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    /// -1 = automatic (derived from your profile), 0–4 = explicit days before departure.
    private var preTripBinding: Binding<Int> {
        Binding(
            get: { currentTrip.preTripDaysOverride ?? -1 },
            set: { newValue in
                var updated = currentTrip
                updated.preTripDaysOverride = newValue < 0 ? nil : newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private var preTripFootnote: String {
        if let override = currentTrip.preTripDaysOverride {
            switch override {
            case 0: return "Your choice: no early shifting — the plan starts working on travel day."
            case 1: return "Your choice: bedtime starts moving 1 day before departure."
            default: return "Your choice: bedtime starts moving \(override) days before departure."
            }
        }
        return "Automatic uses your profile's pre-trip preference (Settings → Sleep profile), capped by plan intensity. Pick a value to decide exactly when the shift begins for this trip."
    }
}

private struct CommitmentRow: View {
    let commitment: FixedCommitment

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: commitment.requiresAlertness ? "bolt.circle.fill" : "calendar.circle.fill")
                .font(.title3)
                .foregroundStyle(commitment.importance == .critical ? Theme.priorityColor(.mustDo) : Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(commitment.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(TimeFormat.range(commitment.window, zone: commitment.zone.resolved)
                     + " · " + TimeFormat.dayDate(commitment.start, zone: commitment.zone.resolved))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if commitment.requiresAlertness {
                    Text("Needs you sharp")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SegmentRow: View {
    let segment: FlightSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(segment.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if segment.status == .delayed {
                    Text("Delayed")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            HStack {
                VStack(alignment: .leading) {
                    Text(TimeFormat.time(segment.departure, zone: segment.departureZone.resolved))
                        .font(.callout.weight(.medium).monospacedDigit())
                    Text(TimeFormat.dayDate(segment.departure, zone: segment.departureZone.resolved))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("to")
                VStack(alignment: .leading) {
                    Text(TimeFormat.time(segment.arrival, zone: segment.arrivalZone.resolved))
                        .font(.callout.weight(.medium).monospacedDigit())
                    Text(TimeFormat.dayDate(segment.arrival, zone: segment.arrivalZone.resolved))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(blockText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var blockText: String {
        let hours = Int(segment.blockTime) / 3600
        let minutes = (Int(segment.blockTime) % 3600) / 60
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }
}

// MARK: - Delay reporting

struct ReportDelayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var selectedSegmentID: UUID?
    @State private var newDeparture = Date()
    @State private var newArrival = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Which flight changed?") {
                    Picker("Flight", selection: $selectedSegmentID) {
                        ForEach(trip.segments) { segment in
                            Text(segment.displayName).tag(Optional(segment.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let segment = selectedSegment {
                    Section("New times (\(TimeFormat.zoneCity(segment.departureZone.resolved)) departure)") {
                        DatePicker(
                            "New departure",
                            selection: $newDeparture,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        DatePicker(
                            "New arrival",
                            selection: $newArrival,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    Section {
                        quickDelayButtons(segment: segment)
                    } header: {
                        Text("Common delays")
                    } footer: {
                        Text("We'll rebuild the rest of your plan around the new times and update your reminders.")
                    }
                }
            }
            .navigationTitle("Flight changed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update plan") {
                        guard let id = selectedSegmentID else { return }
                        Task {
                            await model.reportDelay(
                                trip: trip,
                                segmentID: id,
                                newDeparture: newDeparture,
                                newArrival: newArrival
                            )
                            dismiss()
                        }
                    }
                    .disabled(selectedSegmentID == nil || newArrival <= newDeparture)
                }
            }
            .onAppear {
                if selectedSegmentID == nil {
                    selectSegment(trip.segments.first)
                }
            }
            .onChange(of: selectedSegmentID) { _, _ in
                selectSegment(selectedSegment)
            }
        }
    }

    private var selectedSegment: FlightSegment? {
        trip.segments.first { $0.id == selectedSegmentID }
    }

    private func selectSegment(_ segment: FlightSegment?) {
        guard let segment else { return }
        selectedSegmentID = segment.id
        newDeparture = segment.departure
        newArrival = segment.arrival
    }

    @ViewBuilder
    private func quickDelayButtons(segment: FlightSegment) -> some View {
        HStack {
            ForEach([1.0, 2.0, 4.0], id: \.self) { hours in
                Button("+\(Int(hours))h") {
                    newDeparture = segment.departure.addingTimeInterval(hours * 3600)
                    newArrival = segment.arrival.addingTimeInterval(hours * 3600)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
