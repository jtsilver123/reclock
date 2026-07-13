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
        case joinShared
    }

    @State private var path: [Route] = []

    private var lookupAvailable: Bool {
        model.deps.scheduleProvider.isConfigured && !model.state.settings.localOnlyMode
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    Text("Where's your flight?")
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Space.s)

                    // The zero-typing path gets the hero treatment.
                    Button {
                        model.deps.analytics.track(.importMethodSelected(method: "calendar"))
                        path.append(.calendarImport)
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.18))
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                            .frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("From your calendar")
                                    .font(.title3.weight(.bold))
                                    .fontDesign(.rounded)
                                    .foregroundStyle(Color.white)
                                Text("We spot the flights already on your phone. No typing.")
                                    .font(.footnote)
                                    .foregroundStyle(Color.white.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        .padding(Theme.Space.m)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.sky(for: .leaveForAirport))
                                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    if lookupAvailable {
                        Button {
                            model.deps.analytics.track(.importMethodSelected(method: "flight_number"))
                            path.append(.flightLookup)
                        } label: {
                            ImportOptionCard(
                                icon: "number.square.fill",
                                tint: Theme.tint(for: .seekLight),
                                title: "By flight number",
                                subtitle: "Type AY 16 and a date — we fill in the rest."
                            )
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                    Button {
                        model.deps.analytics.track(.importMethodSelected(method: "manual"))
                        path.append(.manualEntry)
                    } label: {
                        ImportOptionCard(
                            icon: "keyboard.fill",
                            tint: Theme.tint(for: .sleep),
                            title: "Type it in",
                            subtitle: "Two airports, two times. About a minute."
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    Button {
                        model.deps.analytics.track(.importMethodSelected(method: "join_shared"))
                        path.append(.joinShared)
                    } label: {
                        ImportOptionCard(
                            icon: "person.2.fill",
                            tint: Theme.tint(for: .melatoninOptional),
                            title: "Join a friend's trip",
                            subtitle: "Got an invite code? Fly it together."
                        )
                    }
                    .buttonStyle(PressableCardStyle())

                    Label("Nothing leaves your phone. You approve every flight before it's saved.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Space.s)
                }
                .padding(Theme.Space.m)
            }
            .background(Theme.background)
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
                case .joinShared:
                    JoinPlanView(onFinished: { dismiss() })
                }
            }
        }
    }
}

private struct ImportOptionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Space.m)
        .card()
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
    @State private var importError: String?

    var body: some View {
        Group {
            switch phase {
            case .explaining:
                VStack(spacing: Theme.Space.l) {
                    Spacer()
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accentDeep)
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
                            .foregroundStyle(Theme.ink)
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
                        .foregroundStyle(Theme.ink)
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
                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
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
        importError = nil
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
        ) else {
            importError = "Those flights don't line up as one trip — try importing fewer, or add the trip manually."
            return
        }
        if await model.addTrip(trip) {
            Haptics.success()
            onFinished()
        } else {
            importError = "Couldn't build a plan from those flights. Add the trip manually and it'll take under a minute."
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
                        .font(.headline.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.textPrimary)
                    Text(flight.sourceTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
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
