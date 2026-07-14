import SwiftUI
import ReclockKit

/// The one-shot path: type "AY 16" + a date, and the plan builds itself. A single
/// match adds the trip immediately — no confirmation screen, no fields to edit —
/// and hands straight over to the plan-reveal moment. Multiple matches (rare)
/// take one pick, then build. Connections belong to "Type it in" or email paste.
struct FlightLookupView: View {
    @Environment(AppModel.self) private var model
    var onFinished: () -> Void

    @State private var flightNumber = ""
    @State private var date = Date().addingTimeInterval(3 * 86_400)
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var results: [ScheduledFlight] = []
    @State private var buildingFlight: ScheduledFlight?
    @State private var buildError: String?

    private var provider: FlightScheduleProvider { model.deps.scheduleProvider }
    private var localOnly: Bool { model.state.settings.localOnlyMode }
    private var isBusy: Bool { isSearching || buildingFlight != nil }

    var body: some View {
        Form {
            if !provider.isConfigured {
                unavailableSection(reason: "Flight lookup isn't set up in this build.")
            } else if localOnly {
                unavailableSection(reason: "Flight lookup is off while Local-only mode is on (Settings → Privacy).")
            } else if let buildingFlight {
                buildingSection(buildingFlight)
            } else {
                searchSection
                resultsSection
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
            .disabled(flightNumber.trimmingCharacters(in: .whitespaces).count < 3 || isBusy)
            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let buildError {
                Label(buildError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("One match and your plan builds itself. Connecting flights? Use Type it in, or paste the whole confirmation email. Only the flight number and date are sent — never who you are.")
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if !results.isEmpty {
            Section("Which one is yours?") {
                ForEach(results) { flight in
                    Button {
                        Task { await build(flight) }
                    } label: {
                        ScheduledFlightRow(flight: flight)
                    }
                }
            }
        }
    }

    /// The brief beat between "found it" and the curtain-up: the flight, confirmed.
    private func buildingSection(_ flight: ScheduledFlight) -> some View {
        Section {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                ScheduledFlightRow(flight: flight)
            }
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Building your plan…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
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
        buildError = nil
        defer { isSearching = false }
        do {
            let homeZone = model.profile?.homeZone.resolved ?? .current
            let found = try await provider.lookup(
                flightNumber: flightNumber,
                departureDate: date,
                homeZone: homeZone
            )
            if found.count == 1, let only = found.first {
                // It found your flight. That IS the confirmation — build.
                await build(only)
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

    private func build(_ flight: ScheduledFlight) async {
        Haptics.success()
        withAnimation(Theme.Anim.spring) {
            buildingFlight = flight
            results = []
        }
        guard let trip = TripAssembler.makeTrip(
            segments: [flight.segment()],
            homeZone: model.profile?.homeZone ?? ZoneID(TimeZone.current.identifier),
            airports: model.deps.airports,
            intensity: model.state.settings.defaultIntensity ?? .balanced,
            airportTransferMinutes: 60,
            importSource: .flightNumber
        ) else {
            withAnimation(Theme.Anim.spring) { buildingFlight = nil }
            buildError = "That flight couldn't become a trip — try entering it manually."
            return
        }
        if await model.addTrip(trip) {
            // The plan-reveal takes it from here.
            onFinished()
        } else {
            withAnimation(Theme.Anim.spring) { buildingFlight = nil }
            buildError = "Couldn't build the plan for that flight. Try manual entry."
        }
    }
}

struct ScheduledFlightRow: View {
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
