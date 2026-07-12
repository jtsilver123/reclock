import SwiftUI
import ReclockKit

/// Manual flight entry with airport autocomplete and automatic zone inference.
/// Works with a flight number (for reference) or plain airports and times.
struct ManualTripEntryView: View {
    @Environment(AppModel.self) private var model
    var onFinished: () -> Void

    struct SegmentDraft: Identifiable {
        let id = UUID()
        var flightNumber = ""
        var departureAirport: Airport?
        var arrivalAirport: Airport?
        var departureDate = Date().addingTimeInterval(3 * 86_400)
        var arrivalDate = Date().addingTimeInterval(3 * 86_400 + 8 * 3600)
    }

    @State private var segments: [SegmentDraft] = [SegmentDraft()]
    @State private var includeReturn = false
    @State private var returnSegment = SegmentDraft()
    @State private var intensity: PlanIntensity = .balanced
    /// -1 = automatic (profile preference), 0–4 = explicit days before departure.
    @State private var preTripChoice: Int = -1
    @State private var validationMessages: [String] = []
    @State private var isCreating = false

    var body: some View {
        Form {
            ForEach($segments) { $draft in
                Section(segments.count > 1 ? "Flight \(index(of: draft.id) + 1)" : "Your flight") {
                    SegmentEditor(draft: $draft)
                }
            }

            Section {
                Button {
                    var next = SegmentDraft()
                    if let last = segments.last {
                        next.departureAirport = last.arrivalAirport
                        next.departureDate = last.arrivalDate.addingTimeInterval(2 * 3600)
                        next.arrivalDate = last.arrivalDate.addingTimeInterval(5 * 3600)
                    }
                    segments.append(next)
                } label: {
                    Label("Add connecting flight", systemImage: "plus")
                }
                if segments.count > 1 {
                    Button(role: .destructive) {
                        segments.removeLast()
                    } label: {
                        Label("Remove last flight", systemImage: "minus.circle")
                    }
                }
                Toggle("Add return flight", isOn: $includeReturn)
                if includeReturn {
                    SegmentEditor(draft: $returnSegment)
                }
            }

            Section("Plan style") {
                Picker("Intensity", selection: $intensity) {
                    ForEach(PlanIntensity.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                Text(intensity.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Picker("Start adjusting", selection: $preTripChoice) {
                    Text("Automatic").tag(-1)
                    Text("On travel day").tag(0)
                    Text("1 day before").tag(1)
                    Text("2 days before").tag(2)
                    Text("3 days before").tag(3)
                    Text("4 days before").tag(4)
                }
                Text("When your bedtime starts moving. Automatic follows your profile preference; picking a value makes it exact for this trip.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if !validationMessages.isEmpty {
                Section {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                Button {
                    Task { await createTrip() }
                } label: {
                    if isCreating {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Build my plan").frame(maxWidth: .infinity)
                    }
                }
                .disabled(!isComplete || isCreating)
            } footer: {
                Text("Times are entered in each airport's local time — exactly as they appear on your ticket.")
            }
        }
        .navigationTitle("Enter trip")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func index(of id: UUID) -> Int {
        segments.firstIndex { $0.id == id } ?? 0
    }

    private var isComplete: Bool {
        let outboundOK = segments.allSatisfy { $0.departureAirport != nil && $0.arrivalAirport != nil }
        let returnOK = !includeReturn || (returnSegment.departureAirport != nil && returnSegment.arrivalAirport != nil)
        return outboundOK && returnOK
    }

    private func buildSegments() -> [FlightSegment] {
        var drafts = segments
        if includeReturn { drafts.append(returnSegment) }
        return drafts.compactMap { draft in
            guard let dep = draft.departureAirport, let arr = draft.arrivalAirport else { return nil }
            // DatePickers produce instants in the device zone; reinterpret the wall-clock
            // components in the airport's zone so "18:30 on the ticket" means 18:30 there.
            let departure = reinterpret(draft.departureDate, into: dep.zone.resolved)
            let arrival = reinterpret(draft.arrivalDate, into: arr.zone.resolved)
            return FlightSegment(
                airline: draft.flightNumber.isEmpty ? nil : String(draft.flightNumber.prefix(2)).uppercased(),
                flightNumber: draft.flightNumber.isEmpty ? nil : draft.flightNumber.uppercased().replacingOccurrences(of: " ", with: ""),
                departureAirport: dep.iata,
                arrivalAirport: arr.iata,
                departure: departure,
                arrival: arrival,
                departureZone: dep.zone,
                arrivalZone: arr.zone,
                importSource: .manual
            )
        }
    }

    private func reinterpret(_ date: Date, into zone: TimeZone) -> Date {
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        let comps = deviceCal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = zone
        return targetCal.date(from: comps) ?? date
    }

    private func createTrip() async {
        isCreating = true
        defer { isCreating = false }
        let built = buildSegments().sorted { $0.departure < $1.departure }
        let validator = TripValidator(airports: model.deps.airports)
        let issues = validator.validate(segments: built, now: model.deps.now())
        validationMessages = issues.map(\.description)
        guard !issues.contains(where: \.isBlocking) else { return }

        guard let first = built.first else { return }
        let stayAirport = outboundDestination(built)
        let destinationAirport = model.deps.airports.airport(iata: stayAirport)
        let homeZone = model.profile?.homeZone ?? first.departureZone
        let trip = Trip(
            name: destinationAirport?.city ?? stayAirport,
            origin: first.departureAirport,
            destination: destinationAirport?.city ?? stayAirport,
            homeZone: homeZone,
            destinationZone: destinationAirport?.zone
                ?? model.deps.airports.zone(forIATA: stayAirport)
                ?? built.last!.arrivalZone,
            segments: built,
            intensity: intensity,
            preTripDaysOverride: preTripChoice < 0 ? nil : preTripChoice,
            importSource: .manual
        )
        if await model.addTrip(trip) {
            onFinished()
        }
    }

    private func outboundDestination(_ segments: [FlightSegment]) -> String {
        guard segments.count > 1 else { return segments.first?.arrivalAirport ?? "" }
        var bestGap: TimeInterval = 0
        var stay = segments.last!.arrivalAirport
        for i in 1..<segments.count {
            let gap = segments[i].departure.timeIntervalSince(segments[i - 1].arrival)
            if gap > bestGap && gap >= 48 * 3600 {
                bestGap = gap
                stay = segments[i - 1].arrivalAirport
            }
        }
        return stay
    }
}

// MARK: - Segment editor

private struct SegmentEditor: View {
    @Binding var draft: ManualTripEntryView.SegmentDraft

    var body: some View {
        TextField("Flight number (optional, e.g. AY 16)", text: $draft.flightNumber)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        AirportField(label: "From", selection: $draft.departureAirport)
        AirportField(label: "To", selection: $draft.arrivalAirport)
        DatePicker("Departs", selection: $draft.departureDate, displayedComponents: [.date, .hourAndMinute])
        DatePicker("Arrives", selection: $draft.arrivalDate, displayedComponents: [.date, .hourAndMinute])
        if let dep = draft.departureAirport, let arr = draft.arrivalAirport {
            Text("Times read as local: \(dep.iata) departs \(dep.zone.identifier), \(arr.iata) arrives \(arr.zone.identifier).")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Airport autocomplete backed by the bundled directory, with a custom-airport fallback
/// (code + time zone) so smaller airports are never a dead end.
struct AirportField: View {
    @Environment(AppModel.self) private var model
    let label: String
    @Binding var selection: Airport?

    @State private var query = ""
    @State private var isSearching = false
    @State private var showCustomEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                if let airport = selection {
                    Button {
                        selection = nil
                        query = ""
                        isSearching = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(airport.iata) · \(airport.city)")
                                .foregroundStyle(Theme.textPrimary)
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityLabel("Clear airport")
                        }
                    }
                } else {
                    TextField("City or code", text: $query)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, _ in isSearching = true }
                }
            }
            if isSearching && selection == nil && !query.isEmpty {
                let hits = model.deps.airports.search(query, limit: 5)
                ForEach(hits) { airport in
                    Button {
                        selection = airport
                        isSearching = false
                    } label: {
                        HStack {
                            Text(airport.iata)
                                .font(.subheadline.weight(.bold).monospaced())
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading) {
                                Text(airport.city)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(airport.name)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                if hits.isEmpty {
                    Button {
                        showCustomEntry = true
                    } label: {
                        Label("Not listed? Add “\(query.uppercased().prefix(3))” with its time zone", systemImage: "plus.circle")
                            .font(.caption)
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomEntry) {
            CustomAirportSheet(initialCode: String(query.uppercased().prefix(3))) { airport in
                selection = airport
                isSearching = false
            }
        }
    }
}

/// Fallback entry for airports outside the bundled directory: a code plus the airport's
/// time zone — everything the planner actually needs.
private struct CustomAirportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initialCode: String
    let onSave: (Airport) -> Void

    @State private var code: String = ""
    @State private var zoneQuery = ""
    @State private var selectedZone: String?

    private var zoneMatches: [String] {
        guard zoneQuery.count >= 2 else { return [] }
        let q = zoneQuery.replacingOccurrences(of: " ", with: "_").lowercased()
        return TimeZone.knownTimeZoneIdentifiers
            .filter { $0.lowercased().contains(q) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Airport code") {
                    TextField("e.g. BGO", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    if let zone = selectedZone {
                        HStack {
                            Text(zone)
                            Spacer()
                            Button("Change") { selectedZone = nil }
                                .font(.footnote)
                        }
                    } else {
                        TextField("Search a city, e.g. Oslo", text: $zoneQuery)
                            .autocorrectionDisabled()
                        ForEach(zoneMatches, id: \.self) { zone in
                            Button(zone.replacingOccurrences(of: "_", with: " ")) {
                                selectedZone = zone
                            }
                        }
                    }
                } header: {
                    Text("Airport time zone")
                } footer: {
                    Text("Pick the city that shares the airport's clock — that's all the planner needs to get every time right.")
                }
            }
            .navigationTitle("Custom airport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use airport") {
                        guard let zoneID = selectedZone else { return }
                        let cleaned = code.trimmingCharacters(in: .whitespaces).uppercased()
                        onSave(Airport(
                            iata: cleaned,
                            name: "Custom airport",
                            city: cleaned,
                            country: "",
                            zone: ZoneID(zoneID)
                        ))
                        dismiss()
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).count != 3 || selectedZone == nil)
                }
            }
            .onAppear {
                if code.isEmpty { code = initialCode }
            }
        }
    }
}
