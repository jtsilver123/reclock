import SwiftUI
import ReclockKit

/// Trip creation: calendar import (with explicit consent and confirmation) or manual entry.
struct AddTripFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Route: Hashable {
        case calendarImport
        case flightLookup
        case manualEntry
    }

    @State private var path: [Route] = []

    private var lookupAvailable: Bool {
        model.deps.scheduleProvider.isConfigured && !model.state.settings.localOnlyMode
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        model.deps.analytics.track(.importMethodSelected(method: "calendar"))
                        path.append(.calendarImport)
                    } label: {
                        ImportOptionRow(
                            icon: "calendar.badge.checkmark",
                            title: "Import from Calendar",
                            subtitle: "Finds flights that Flighty, TripIt, or airline emails put in your calendar. Scanning happens on this device only."
                        )
                    }
                    if lookupAvailable {
                        Button {
                            model.deps.analytics.track(.importMethodSelected(method: "flight_number"))
                            path.append(.flightLookup)
                        } label: {
                            ImportOptionRow(
                                icon: "number.square",
                                title: "Search by flight number",
                                subtitle: "Type “AY 16” and a date — airports and times fill themselves in."
                            )
                        }
                    }
                    Button {
                        model.deps.analytics.track(.importMethodSelected(method: "manual"))
                        path.append(.manualEntry)
                    } label: {
                        ImportOptionRow(
                            icon: "keyboard",
                            title: "Enter it myself",
                            subtitle: "Airports and times — arrival is pre-estimated from the route."
                        )
                    }
                } footer: {
                    Text("Reclock never uploads your calendar. Detected events are shown to you before anything is saved.")
                }
            }
            .navigationTitle("Add a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .calendarImport:
                    CalendarImportView(onFinished: { dismiss() })
                case .flightLookup:
                    FlightLookupView(onFinished: { dismiss() })
                case .manualEntry:
                    ManualTripEntryView(onFinished: { dismiss() })
                }
            }
        }
    }
}

private struct ImportOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Calendar import

struct CalendarImportView: View {
    @Environment(AppModel.self) private var model
    var onFinished: () -> Void

    enum Phase {
        case explaining
        case scanning
        case results([DetectedFlight])
        case denied
    }

    @State private var phase: Phase = .explaining
    @State private var selectedIDs: Set<String> = []
    @State private var isCreating = false

    var body: some View {
        Group {
            switch phase {
            case .explaining:
                VStack(spacing: Theme.Space.l) {
                    Spacer()
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Scan your calendar for flights")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Reclock looks for flight-shaped events — airline codes, airport pairs, boarding notes — on this device only. You'll see exactly what was found and choose what to import. Nothing else is read, stored, or sent anywhere.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                    Button("Allow calendar access") {
                        Task { await requestAndScan() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Theme.Space.l)
            case .scanning:
                ProgressView("Looking for flights…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied:
                VStack(spacing: Theme.Space.l) {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                    Text("Calendar access is optional")
                        .font(.title3.weight(.bold))
                    Text("No problem — you can still enter your flight in under a minute. To allow access later, visit Settings → Privacy → Calendars.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                    NavigationLink {
                        ManualTripEntryView(onFinished: onFinished)
                    } label: {
                        Text("Enter flight manually")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(Color.white)
                    }
                }
                .padding(Theme.Space.l)
            case .results(let flights):
                resultsList(flights)
            }
        }
        .navigationTitle("Calendar import")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func requestAndScan() async {
        phase = .scanning
        let status = await model.deps.calendarImporter.accessStatus()
        let granted: Bool
        switch status {
        case .granted: granted = true
        case .notDetermined: granted = await model.deps.calendarImporter.requestAccess()
        case .denied: granted = false
        }
        model.deps.analytics.track(.calendarPermission(granted: granted))
        guard granted else {
            phase = .denied
            return
        }
        let flights = await model.deps.calendarImporter.detectFlights(daysAhead: 180)
        selectedIDs = Set(flights.filter(\.isComplete).map(\.id))
        phase = .results(flights)
    }

    @ViewBuilder
    private func resultsList(_ flights: [DetectedFlight]) -> some View {
        if flights.isEmpty {
            VStack(spacing: Theme.Space.l) {
                Spacer()
                Text("No flights found")
                    .font(.title3.weight(.bold))
                Text("We looked through the next six months and didn't spot flight-shaped events. You can enter the trip manually instead.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer()
                NavigationLink {
                    ManualTripEntryView(onFinished: onFinished)
                } label: {
                    Text("Enter flight manually")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color.white)
                }
            }
            .padding(Theme.Space.l)
        } else {
            List {
                Section {
                    ForEach(flights) { flight in
                        DetectedFlightRow(
                            flight: flight,
                            isSelected: selectedIDs.contains(flight.id),
                            toggle: {
                                if selectedIDs.contains(flight.id) {
                                    selectedIDs.remove(flight.id)
                                } else {
                                    selectedIDs.insert(flight.id)
                                }
                            }
                        )
                    }
                } header: {
                    Text("Found \(flights.count) flight\(flights.count == 1 ? "" : "s")")
                } footer: {
                    Text("Only the flights you keep selected are imported. Incomplete detections can be finished manually.")
                }
                Section {
                    Button {
                        Task { await importSelected(flights) }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Import \(selectedIDs.count) flight\(selectedIDs.count == 1 ? "" : "s")")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(selectedIDs.isEmpty || isCreating)
                }
            }
        }
    }

    private func importSelected(_ flights: [DetectedFlight]) async {
        isCreating = true
        defer { isCreating = false }
        let parser = FlightEventParser()
        let segments = flights
            .filter { selectedIDs.contains($0.id) }
            .compactMap { parser.makeSegment(from: $0) }
        let homeZone = model.profile?.homeZone ?? ZoneID(TimeZone.current.identifier)
        guard let trip = TripAssembler.makeTrip(
            segments: segments,
            homeZone: homeZone,
            airports: model.deps.airports,
            importSource: .calendar
        ) else { return }
        if await model.addTrip(trip) {
            Haptics.success()
            onFinished()
        }
    }
}

private struct DetectedFlightRow: View {
    let flight: DetectedFlight
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                VStack(alignment: .leading, spacing: 2) {
                    Text(routeText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(flight.sourceTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if !flight.isComplete {
                        Label("Needs details — finish manually after import", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        }
        .disabled(!flight.isComplete)
    }

    private var routeText: String {
        let dep = flight.departureAirport ?? "?"
        let arr = flight.arrivalAirport ?? "?"
        let number = flight.flightNumber.map { " · \($0)" } ?? ""
        return "\(dep) → \(arr)\(number)"
    }
}
