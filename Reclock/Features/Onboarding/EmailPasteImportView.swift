import SwiftUI
import ReclockKit

/// Paste a booking-confirmation email; Reclock finds the flights in it on-device,
/// confirms each against the schedule service, and builds the plan. The email text
/// itself never leaves the phone — only flight numbers and dates are looked up.
struct EmailPasteImportView: View {
    @Environment(AppModel.self) private var model
    var onFinished: () -> Void

    private struct VerifiedLeg: Identifiable {
        let id = UUID()
        var candidate: EmailFlightExtractor.Candidate
        var state: LegState
    }

    private enum LegState {
        case checking
        case confirmed(ScheduledFlight)
        case notFound
    }

    @State private var pastedText = ""
    @State private var legs: [VerifiedLeg] = []
    @State private var hasExtracted = false
    @State private var transferMinutes = 60
    @State private var isCreating = false
    @State private var clipboardNote: String?
    @State private var wasTruncated = false
    @State private var buildError: String?

    private var confirmedFlights: [ScheduledFlight] {
        legs.compactMap {
            if case .confirmed(let flight) = $0.state { return flight }
            return nil
        }
    }

    var body: some View {
        Form {
            if !hasExtracted {
                pasteSection
            } else {
                resultsSection
                if !confirmedFlights.isEmpty {
                    buildSection
                }
                Section {
                    Button {
                        withAnimation(Theme.Anim.spring) {
                            hasExtracted = false
                            legs = []
                            buildError = nil
                        }
                    } label: {
                        Label("Paste a different email", systemImage: "arrow.uturn.backward")
                            .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("From an email")
        .tint(Theme.accentDeep)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Paste

    private var pasteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.m) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15))
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                    }
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)
                    Text("Copy your airline confirmation email, then paste it here. The flights find themselves.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                Button {
                    Haptics.soft()
                    if let clip = UIPasteboard.general.string, !clip.isEmpty {
                        withAnimation(Theme.Anim.gentle) { clipboardNote = nil }
                        pastedText = clip
                        extractAndVerify()
                    } else {
                        // A silent no-op reads as broken; say why nothing happened.
                        withAnimation(Theme.Anim.gentle) {
                            clipboardNote = "Nothing on the clipboard — copy the confirmation email first."
                        }
                    }
                } label: {
                    Label("Paste copied email", systemImage: "doc.on.clipboard")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                if let clipboardNote {
                    Label(clipboardNote, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .transition(.opacity)
                }

                TextField("…or paste / type the text here", text: $pastedText, axis: .vertical)
                    .lineLimit(4...10)
                    .font(.footnote)
                if !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Haptics.soft()
                        extractAndVerify()
                    } label: {
                        Label("Find the flights", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        } footer: {
            Text("Reading happens on this phone. Only flight numbers and dates are sent to the schedule service — never the email.")
        }
    }

    // MARK: Results

    private var resultsSection: some View {
        Section {
            if legs.isEmpty {
                Label("No flight numbers found in that text. Try pasting more of the email, or add the flight by number instead.",
                      systemImage: "questionmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                // Every dead end carries its own way out.
                NavigationLink {
                    FlightLookupView(onFinished: onFinished)
                } label: {
                    Label("Add by flight number instead", systemImage: "magnifyingglass")
                }
                NavigationLink {
                    ManualTripEntryView(onFinished: onFinished)
                } label: {
                    Label("Type it in instead", systemImage: "keyboard")
                }
            }
            ForEach(legs) { leg in
                legRow(leg)
            }
            .onDelete { legs.remove(atOffsets: $0) }
        } header: {
            if !legs.isEmpty {
                Text("Found in your email")
            }
        } footer: {
            if legs.contains(where: { if case .notFound = $0.state { return true } else { return false } }) {
                Text("Unmatched lines are usually booking numbers, not flights — swipe to remove them.")
            }
        }
    }

    @ViewBuilder
    private func legRow(_ leg: VerifiedLeg) -> some View {
        switch leg.state {
        case .checking:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text(leg.candidate.flightNumber)
                    .font(.subheadline.weight(.semibold).monospaced())
                Text("checking…")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        case .confirmed(let flight):
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
                    .accessibilityHidden(true)
                ScheduledFlightRow(flight: flight)
            }
        case .notFound:
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.candidate.flightNumber)
                        .font(.subheadline.weight(.semibold).monospaced())
                        .foregroundStyle(Theme.textSecondary)
                    Text("No matching flight on that date")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Build

    private var buildSection: some View {
        Section {
            Button {
                Task { await buildTrip() }
            } label: {
                if isCreating {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Build my plan")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isCreating)
            if let buildError {
                Label(buildError, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
            DisclosureGroup {
                TransferTimeRow(
                    minutes: $transferMinutes,
                    departureAirport: confirmedFlights.first.flatMap {
                        model.deps.airports.airport(iata: $0.departureAirport)
                    }
                )
            } label: {
                Text("Getting to the airport · \(transferMinutes) min")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        } footer: {
            Text(wasTruncated
                 ? "Showing the first 6 flights found — trim the email to just your itinerary if one is missing. Everything else can be tuned any time with Adjust on the Plan tab."
                 : "Everything else — intensity, start day — can be tuned any time with Adjust on the Plan tab.")
        }
    }

    // MARK: Actions

    private func extractAndVerify() {
        let extraction = EmailFlightExtractor.extraction(from: pastedText, now: model.deps.now())
        let candidates = extraction.candidates
        withAnimation(Theme.Anim.spring) {
            hasExtracted = true
            wasTruncated = extraction.truncated
            legs = candidates.map { VerifiedLeg(candidate: $0, state: .checking) }
        }
        if !candidates.isEmpty { Haptics.selection() }

        for leg in legs {
            Task {
                let date = leg.candidate.date ?? model.deps.now().addingTimeInterval(3 * 86_400)
                // The detector produced this Date in the DEVICE zone; the lookup
                // formats it back to yyyy-MM-dd in whatever zone we pass. Passing
                // the home zone shifted the query a day for users currently abroad.
                let found = try? await model.deps.scheduleProvider.lookup(
                    flightNumber: leg.candidate.flightNumber,
                    departureDate: date,
                    homeZone: .current
                )
                await MainActor.run {
                    guard let index = legs.firstIndex(where: { $0.id == leg.id }) else { return }
                    withAnimation(Theme.Anim.spring) {
                        if let flight = found?.first {
                            legs[index].state = .confirmed(flight)
                            Haptics.success()
                        } else {
                            legs[index].state = .notFound
                        }
                    }
                }
            }
        }
    }

    private func buildTrip() async {
        guard !isCreating else { return }
        isCreating = true
        buildError = nil
        defer { isCreating = false }
        // Codeshares (AA 8987 / AY 9) confirm as the same physical flight — keep one.
        var unique: [ScheduledFlight] = []
        for flight in confirmedFlights.sorted(by: { $0.departure < $1.departure }) {
            let isDuplicate = unique.contains {
                $0.departureAirport == flight.departureAirport
                    && $0.arrivalAirport == flight.arrivalAirport
                    && abs($0.departure.timeIntervalSince(flight.departure)) < 45 * 60
            }
            if !isDuplicate { unique.append(flight) }
        }
        let segments = unique.map { $0.segment() }
        guard let trip = TripAssembler.makeTrip(
            segments: segments,
            homeZone: model.profile?.homeZone ?? ZoneID(TimeZone.current.identifier),
            airports: model.deps.airports,
            intensity: model.state.settings.defaultIntensity ?? .balanced,
            airportTransferMinutes: transferMinutes,
            importSource: .flightNumber
        ) else {
            buildError = "These flights don't line up as one trip — remove the ones that aren't yours."
            return
        }
        if await model.addTrip(trip) {
            Haptics.success()
            onFinished()
        } else {
            buildError = "Couldn't build the plan from these flights. Remove any that aren't yours and try again."
        }
    }
}
