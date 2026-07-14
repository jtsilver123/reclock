import SwiftUI
import ReclockKit

/// Add or edit a fixed commitment — the real-life blocks the plan must respect.
/// Times are entered in destination local time (where the commitment happens).
struct CommitmentFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    /// nil = creating a new commitment.
    var existing: FixedCommitment?

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(2 * 3600)
    @State private var mustBeAlert = false
    @State private var isCritical = false

    /// Where the commitment happens: before the first departure it's at home,
    /// afterwards at the destination — judged live from the picked start, and the
    /// section header names the zone so the traveler sees which clock they're on.
    /// (Always pinning to the destination turned "Work 9–17 the day before flying"
    /// into an overnight block at home.)
    private var zoneID: ZoneID {
        guard let departure = trip.firstDeparture else { return trip.destinationZone }
        let asDestination = TimeFormat.reinterpret(start, into: trip.destinationZone.resolved)
        return asDestination < departure ? trip.homeZone : trip.destinationZone
    }

    private var zone: TimeZone { zoneID.resolved }

    private static let suggestions = ["Work", "Meeting", "Dinner", "Wedding", "Presentation", "Tour", "Childcare"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it? (e.g. Client dinner)", text: $title)
                    if title.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Space.s) {
                                ForEach(Self.suggestions, id: \.self) { suggestion in
                                    Button(suggestion) { title = suggestion }
                                        .font(.footnote.weight(.medium))
                                        .padding(.horizontal, Theme.Space.m)
                                        .padding(.vertical, 6)
                                        .background(Theme.surfaceSecondary, in: Capsule())
                                        .foregroundStyle(Theme.textPrimary)
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Section("\(TimeFormat.zoneCity(zone)) local time") {
                    DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Toggle("I need to be sharp for this", isOn: $mustBeAlert)
                    Toggle("This is unmissable", isOn: $isCritical)
                } footer: {
                    Text("The plan never schedules sleep or naps during a commitment, moves light windows around it, and — if you need to be sharp — times caffeine to help.")
                }
            }
            .navigationTitle(existing == nil ? "Add commitment" : "Edit commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || end <= start)
                }
            }
            .onAppear { seed() }
        }
    }

    private func seed() {
        if let existing {
            title = existing.title
            start = TimeFormat.pickerDate(for: existing.start, in: existing.zone.resolved)
            end = TimeFormat.pickerDate(for: existing.end, in: existing.zone.resolved)
            mustBeAlert = existing.requiresAlertness
            isCritical = existing.importance == .critical
        } else if let arrival = trip.outboundArrival {
            // Default to the evening after landing — the most common real commitment.
            let seeded = TimeFormat.pickerDate(for: arrival, in: zone)
            start = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: seeded) ?? seeded
            end = start.addingTimeInterval(2 * 3600)
        }
    }

    private func save() async {
        let commitment = FixedCommitment(
            id: existing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            start: TimeFormat.reinterpret(start, into: zone),
            end: TimeFormat.reinterpret(end, into: zone),
            zone: zoneID,
            importance: isCritical ? .critical : .standard,
            requiresAlertness: mustBeAlert,
            blocksSleep: true
        )
        if existing == nil {
            await model.addCommitment(commitment, to: trip)
        } else {
            await model.updateCommitment(commitment, in: trip)
        }
        dismiss()
    }
}

/// Correct a flight's times (typo or airline schedule change known in advance).
/// For day-of disruptions, "My flight changed / was delayed" also reschedules reminders
/// with delay framing.
struct SegmentEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let segment: FlightSegment

    @State private var departure = Date()
    @State private var arrival = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Departs (\(TimeFormat.zoneCity(segment.departureZone.resolved)) time)",
                        selection: $departure,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Arrives (\(TimeFormat.zoneCity(segment.arrivalZone.resolved)) time)",
                        selection: $arrival,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text(segment.displayName)
                } footer: {
                    Text("Times are the airport-local times on your ticket. Saving rebuilds the plan.")
                }
            }
            .navigationTitle("Edit flight times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await model.editSegmentTimes(
                                trip: trip,
                                segmentID: segment.id,
                                newDeparture: TimeFormat.reinterpret(departure, into: segment.departureZone.resolved),
                                newArrival: TimeFormat.reinterpret(arrival, into: segment.arrivalZone.resolved)
                            )
                            dismiss()
                        }
                    }
                    .disabled(arrivalInstant <= departureInstant)
                }
            }
            .onAppear {
                departure = TimeFormat.pickerDate(for: segment.departure, in: segment.departureZone.resolved)
                arrival = TimeFormat.pickerDate(for: segment.arrival, in: segment.arrivalZone.resolved)
            }
        }
    }

    private var departureInstant: Date {
        TimeFormat.reinterpret(departure, into: segment.departureZone.resolved)
    }

    private var arrivalInstant: Date {
        TimeFormat.reinterpret(arrival, into: segment.arrivalZone.resolved)
    }
}
