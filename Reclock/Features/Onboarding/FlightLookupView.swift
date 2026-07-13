import SwiftUI
import ReclockKit

/// Search a flight by number: type "AY 16" + date, confirm, and the plan builds itself.
/// Requires a schedule key (SETUP.md); without one this screen explains and hands off to
/// manual entry with everything typed so far carried over.
struct FlightLookupView: View {
    @Environment(AppModel.self) private var model
    var onFinished: () -> Void

    struct FoundLeg: Identifiable {
        let id = UUID()
        var flight: ScheduledFlight
    }

    @State private var flightNumber = ""
    @State private var date = Date().addingTimeInterval(3 * 86_400)
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var results: [ScheduledFlight] = []
    @State private var legs: [FoundLeg] = []
    @State private var transferMinutes = 60
    @State private var isCreating = false
    @State private var addingAnotherLeg = false
    @State private var buildError: String?

    private var provider: FlightScheduleProvider { model.deps.scheduleProvider }
    private var localOnly: Bool { model.state.settings.localOnlyMode }

    var body: some View {
        Form {
            if !provider.isConfigured {
                unavailableSection(reason: "Flight lookup isn't set up in this build.")
            } else if localOnly {
                unavailableSection(reason: "Flight lookup is off while Local-only mode is on (Settings → Privacy).")
            } else {
                legsSection
                if !legs.isEmpty && !addingAnotherLeg {
                    buildSection
                }
                if legs.isEmpty || addingAnotherLeg {
                    searchSection
                }
                resultsSection
                if !legs.isEmpty && addingAnotherLeg {
                    buildSection
                }
            }
        }
        .navigationTitle("Flight number")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var searchSection: some View {
        Section {
            TextField("Flight number (e.g. AY 16)", text: $flightNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            DatePicker("Departure date", selection: $date, displayedComponents: .date)
            Button {
                Task { await search() }
            } label: {
                if isSearching {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Find my flight", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(flightNumber.trimmingCharacters(in: .whitespaces).count < 3 || isSearching)
            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Only the flight number and date are sent — never who you are.")
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if !results.isEmpty {
            Section("Select your flight") {
                ForEach(results) { flight in
                    Button {
                        accept(flight)
                    } label: {
                        ScheduledFlightRow(flight: flight)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var legsSection: some View {
        if !legs.isEmpty {
            Section {
                ForEach(legs) { leg in
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        ScheduledFlightRow(flight: leg.flight)
                    }
                }
                .onDelete { legs.remove(atOffsets: $0) }
            } header: {
                Text(legs.count == 1 ? "Your flight" : "Your flights")
            } footer: {
                Text("Swipe a flight to remove it.")
            }
        }
    }

    private var buildSection: some View {
        Section {
            Button {
                Task { await buildTrip() }
            } label: {
                if isCreating {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Build my plan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isCreating)
            if let buildError {
                Label(buildError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button {
                Haptics.selection()
                withAnimation(Theme.Anim.spring) { addingAnotherLeg = true }
            } label: {
                Label("Add return or connecting flight", systemImage: "plus")
                    .font(.subheadline)
            }
            DisclosureGroup {
                TransferTimeRow(
                    minutes: $transferMinutes,
                    departureAirport: legs.first.flatMap {
                        model.deps.airports.airport(iata: $0.flight.departureAirport)
                    }
                )
            } label: {
                Text("Getting to the airport · \(transferMinutes) min")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            Text("Everything else — intensity, start day — can be tuned any time in trip settings.")
        }
    }

    private func unavailableSection(reason: String) -> some View {
        Section {
            Label(reason, systemImage: "wifi.slash")
                .font(.subheadline)
            NavigationLink {
                ManualTripEntryView(onFinished: onFinished)
            } label: {
                Label("Enter the flight manually instead", systemImage: "keyboard")
            }
        } footer: {
            Text("Manual entry takes under a minute, and arrival times are pre-estimated from the route.")
        }
    }

    // MARK: Actions

    private func search() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let homeZone = model.profile?.homeZone.resolved ?? .current
            let found = try await provider.lookup(
                flightNumber: flightNumber,
                departureDate: date,
                homeZone: homeZone
            )
            if found.count == 1, let only = found.first {
                // One match: it's your flight. No extra tap.
                accept(only)
            } else {
                results = found
            }
        } catch let error as FlightScheduleError {
            switch error {
            case .notFound:
                searchError = "No flight found for that number and date. Double-check both, or enter it manually."
            case .networkUnavailable:
                searchError = "No connection. Try again later, or enter the flight manually."
            case .notConfigured, .unparseable:
                searchError = "Lookup is unavailable right now. Manual entry takes under a minute."
            }
        } catch {
            searchError = "Something went wrong. Manual entry takes under a minute."
        }
    }

    private func accept(_ flight: ScheduledFlight) {
        Haptics.success()
        withAnimation(Theme.Anim.spring) {
            legs.append(FoundLeg(flight: flight))
            results = []
            flightNumber = ""
            addingAnotherLeg = false
        }
    }

    private func buildTrip() async {
        isCreating = true
        buildError = nil
        defer { isCreating = false }
        let segments = legs.map { $0.flight.segment() }
        guard let trip = TripAssembler.makeTrip(
            segments: segments,
            homeZone: model.profile?.homeZone ?? ZoneID(TimeZone.current.identifier),
            airports: model.deps.airports,
            airportTransferMinutes: transferMinutes,
            importSource: .flightNumber
        ) else {
            buildError = "These flights don't line up as one trip — check the dates and order."
            return
        }
        if await model.addTrip(trip) {
            Haptics.success()
            onFinished()
        } else {
            buildError = "Couldn't build the plan from these flights. Check the trip makes sense time-wise, or try manual entry."
        }
    }
}

private struct ScheduledFlightRow: View {
    let flight: ScheduledFlight

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(flight.flightNumber) · \(flight.departureAirport) → \(flight.arrivalAirport)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(
                TimeFormat.weekdayTime(flight.departure, zone: flight.departureZone.resolved)
                + "  →  "
                + TimeFormat.weekdayTime(flight.arrival, zone: flight.arrivalZone.resolved)
                + " local"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
