import SwiftUI
import ReclockKit

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var showDelaySheet = false
    @State private var showGlobe = false
    @State private var showAdjust = false
    @State private var showCalendarSheet = false
    @State private var showDeleteConfirm = false
    @State private var showSurvey = false
    @State private var editingSegment: FlightSegment?
    @State private var showAddCommitment = false
    @State private var editingCommitment: FixedCommitment?

    /// Both endpoints with real coordinates — the globe needs them to place cities.
    private var globeAirports: (origin: Airport, destination: Airport)? {
        guard let depIata = currentTrip.segments.first?.departureAirport,
              let arrIata = (currentTrip.outboundSegments.last ?? currentTrip.segments.last)?.arrivalAirport,
              let origin = model.deps.airports.airport(iata: depIata),
              let destination = model.deps.airports.airport(iata: arrIata),
              origin.latitude != nil, origin.longitude != nil,
              destination.latitude != nil, destination.longitude != nil
        else { return nil }
        return (origin, destination)
    }

    private var currentTrip: Trip {
        model.state.trips.first { $0.id == trip.id } ?? trip
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(currentTrip.origin)
                            .font(Theme.display(33))
                        Image(systemName: "airplane")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .accessibilityHidden(true)
                        Spacer()
                        Text(currentTrip.destination)
                            .font(Theme.display(33))
                    }
                    if let plan = model.plan(for: currentTrip) {
                        HStack(spacing: Theme.Space.s) {
                            Text(shiftDescription(plan))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.4), in: Capsule())
                            Text(plan.strategySummary)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    Label("Works fully offline once generated", systemImage: "airplane.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .overlay(alignment: .topTrailing) {
                    if globeAirports != nil {
                        Button {
                            Haptics.soft()
                            showGlobe = true
                        } label: {
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accentDeep)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Theme.accent.opacity(0.15)))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Globe view: route and daylight")
                    }
                }
            }

            Section {
                Button {
                    Haptics.soft()
                    showAdjust = true
                } label: {
                    Label("Adjust plan (intensity, timing, transfer)", systemImage: "slider.horizontal.3")
                }
                Button {
                    Task { await model.recalculate(trip: currentTrip, trigger: "manual") }
                } label: {
                    Label("Recalculate plan", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("Plan")
            } footer: {
                Text("Opens the same Adjust sheet as the sliders on the Plan tab — one page, always in sync.")
            }

            TravelBuddiesSection(trip: currentTrip)

            Section {
                ForEach(currentTrip.segments) { segment in
                    Button {
                        editingSegment = segment
                    } label: {
                        SegmentRow(segment: segment)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showDelaySheet = true
                } label: {
                    Label("My flight changed / was delayed", systemImage: "clock.badge.exclamationmark")
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

            Section("Take it with you") {
                Button {
                    Haptics.soft()
                    showCalendarSheet = true
                } label: {
                    Label("My calendar — add or remove this plan", systemImage: "calendar.badge.plus")
                }
                if let shareText = model.shareText(for: currentTrip) {
                    ShareLink(item: shareText) {
                        Label("Share my plan", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if currentTrip.status == .active || currentTrip.status == .completed {
                Section {
                    Button {
                        showSurvey = true
                    } label: {
                        Label("How did it go? (post-trip check-in)", systemImage: "checklist")
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
        .sheet(isPresented: $showAdjust) {
            PlanAdjustSheet(trip: currentTrip)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGlobe) {
            if let pair = globeAirports {
                TripGlobeView(trip: currentTrip, origin: pair.origin, destination: pair.destination)
            }
        }
        .sheet(isPresented: $showCalendarSheet) {
            CalendarExportSheet(trip: currentTrip)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showDelaySheet) {
            ReportDelayView(trip: currentTrip)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSurvey) {
            PostTripSurveyView(trip: currentTrip)
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditSheet(trip: currentTrip, segment: segment)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAddCommitment) {
            CommitmentFormView(trip: currentTrip, existing: nil)
                .presentationDetents([.medium, .large])
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

    /// -1 = automatic (derived from your profile), 0–4 = explicit days before departure.
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
                    Section("New times, airport-local") {
                        DatePicker(
                            "Departs (\(TimeFormat.zoneCity(segment.departureZone.resolved)) time)",
                            selection: $newDeparture,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        DatePicker(
                            "Arrives (\(TimeFormat.zoneCity(segment.arrivalZone.resolved)) time)",
                            selection: $newArrival,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    Section {
                        quickDelayButtons(segment: segment)
                    } header: {
                        Text("Common delays")
                    } footer: {
                        Text("Times as they appear on the departure boards. We'll rebuild the rest of your plan and update your reminders.")
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
                        guard let segment = selectedSegment else { return }
                        Haptics.success()
                        Task {
                            await model.reportDelay(
                                trip: trip,
                                segmentID: segment.id,
                                newDeparture: TimeFormat.reinterpret(newDeparture, into: segment.departureZone.resolved),
                                newArrival: TimeFormat.reinterpret(newArrival, into: segment.arrivalZone.resolved)
                            )
                            dismiss()
                        }
                    }
                    .disabled(!timesAreValid)
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

    private var timesAreValid: Bool {
        guard let segment = selectedSegment else { return false }
        let dep = TimeFormat.reinterpret(newDeparture, into: segment.departureZone.resolved)
        let arr = TimeFormat.reinterpret(newArrival, into: segment.arrivalZone.resolved)
        return arr > dep
    }

    /// Pickers hold the wall-clock reading in each airport's zone (like every other
    /// time entry in the app); instants are reconstructed on save.
    private func selectSegment(_ segment: FlightSegment?) {
        guard let segment else { return }
        selectedSegmentID = segment.id
        newDeparture = TimeFormat.pickerDate(for: segment.departure, in: segment.departureZone.resolved)
        newArrival = TimeFormat.pickerDate(for: segment.arrival, in: segment.arrivalZone.resolved)
    }

    @ViewBuilder
    private func quickDelayButtons(segment: FlightSegment) -> some View {
        HStack {
            ForEach([1.0, 2.0, 4.0], id: \.self) { hours in
                Button("+\(Int(hours))h") {
                    // Shifting the wall-clock reading by N hours shifts the instant by N.
                    newDeparture = TimeFormat.pickerDate(for: segment.departure, in: segment.departureZone.resolved)
                        .addingTimeInterval(hours * 3600)
                    newArrival = TimeFormat.pickerDate(for: segment.arrival, in: segment.arrivalZone.resolved)
                        .addingTimeInterval(hours * 3600)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
