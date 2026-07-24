import SwiftUI
import ReclockKit

/// Full-screen detail for any action (from the pinned hero or any day in the plan).
struct ActionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let action: PlanAction
    let trip: Trip

    @State private var completing = false
    @State private var checkingDrive = false
    @State private var driveNote: String?
    @State private var driveSuggestion: Int?

    private var zone: TimeZone { live.displayZone.resolved }

    /// The live copy of this step: after a replan (a drive-time apply, a delay),
    /// the hero must show the new window — not the snapshot from presentation time.
    private var live: PlanAction {
        model.plan(for: trip)?.actions.first { $0.id == action.id } ?? action
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                // The action's sky, full bleed: glyph, title, window — zero chrome.
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        HeroGlyph(systemName: action.type.symbolName, size: 72)
                        Spacer()
                        if action.priority == .mustDo {
                            Text("MUST DO")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.22), in: Capsule())
                        }
                    }
                    Text(live.title)
                        .font(Theme.display(30))
                        .foregroundStyle(Color.white)
                    Text("\(TimeFormat.range(live.window, zone: zone)) · \(TimeFormat.zoneCity(zone)) time")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.sky(for: action.type))
                        .shadow(color: Theme.skyColors(for: action.type).last?.opacity(0.35) ?? .clear,
                                radius: 12, y: 5)
                )
                .grain()
                .livingSky()

                Text(live.instruction)
                    .font(Theme.display(21, black: false))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                driveTimeCheck

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Why this helps")
                    Text(live.explanation)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    if let alternative = live.alternative {
                        SectionHeader(title: "If it's not practical")
                        Text(alternative)
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note = live.adjustmentNote {
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .accessibilityHidden(true)
                        Text("Evidence: \(live.confidence.displayName)")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if live.completion == .pending {
                    Button {
                        guard !completing else { return }
                        completing = true
                        Haptics.success()
                        Task {
                            await model.setCompletion(.done, for: live, in: trip)
                            dismiss()
                        }
                    } label: {
                        Label("Mark done", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(completing)

                    Button("Couldn't do it") {
                        guard !completing else { return }
                        completing = true
                        Haptics.soft()
                        Task {
                            await model.setCompletion(.notPossible, for: live, in: trip)
                            dismiss()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(completing)

                    // Snooze lived only in an unadvertised long-press menu; the step's
                    // own page is where people look for it.
                    Button("Remind me in 30 minutes") {
                        guard !completing else { return }
                        Haptics.soft()
                        Task {
                            await model.snooze(action: live, in: trip)
                            dismiss()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Label(
                        live.completion == .done ? "Completed" : "Marked as \(completionText)",
                        systemImage: live.completion == .done ? "checkmark.circle.fill" : "slash.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(live.completion == .done ? Theme.success : Theme.textSecondary)

                    if live.completion != .expired {
                        Button("Undo — mark as not done yet") {
                            Haptics.soft()
                            Task {
                                await model.setCompletion(.pending, for: live, in: trip)
                                dismiss()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.background)
        .navigationTitle("Plan step")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var completionText: String {
        switch live.completion {
        case .notPossible: "couldn't do it"
        case .skipped: "skipped"
        case .sleptInstead: "slept instead"
        case .expired: "missed"
        default: live.completion.rawValue
        }
    }

    // MARK: Live drive time (leave-for-airport only)

    private var currentTransferMinutes: Int {
        let live = model.state.trips.first { $0.id == trip.id } ?? trip
        return live.airportTransferMinutes ?? 60
    }

    /// The airport this leave-by step drives to: the next segment to depart at or
    /// after the action's window opens.
    private var driveTargetAirport: Airport? {
        guard let segment = trip.segments.first(where: { $0.departure >= action.window.start })
        else { return nil }
        return model.deps.airports.airport(iata: segment.departureAirport)
    }

    /// The plan's transfer allowance is a guess until the day arrives; this checks it
    /// against real traffic from where the user actually is, and offers to re-plan
    /// the leave-by time when reality disagrees by ten minutes or more.
    @ViewBuilder
    private var driveTimeCheck: some View {
        if live.type == .leaveForAirport, live.completion == .pending,
           let airport = driveTargetAirport,
           let latitude = airport.latitude, let longitude = airport.longitude,
           !model.state.settings.localOnlyMode {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionHeader(title: "Traffic right now")
                Button {
                    Task { await checkDrive(airport: airport, latitude: latitude, longitude: longitude) }
                } label: {
                    if checkingDrive {
                        HStack(spacing: Theme.Space.s) {
                            ProgressView()
                            Text("Checking drive time…")
                        }
                    } else {
                        Label("Check drive time from my location", systemImage: "location")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentDeep)
                .disabled(checkingDrive)

                if let driveNote {
                    Text(driveNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let suggestion = driveSuggestion {
                    Button {
                        Haptics.success()
                        driveSuggestion = nil
                        Task {
                            await model.updateTrip(id: trip.id) { $0.airportTransferMinutes = suggestion }
                            withAnimation(Theme.Anim.gentle) {
                                driveNote = "Done — your leave-by time moved to match."
                            }
                        }
                    } label: {
                        Text("Plan around \(suggestion) min instead")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    // The hero above re-reads the live plan, so the window moves in
                    // place; this note confirms the change in words too.
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func checkDrive(airport: Airport, latitude: Double, longitude: Double) async {
        checkingDrive = true
        defer { checkingDrive = false }
        switch await model.deps.transitEstimator.estimateMinutes(toLatitude: latitude, longitude: longitude) {
        case .minutes(let total, let drive):
            Haptics.soft()
            withAnimation(Theme.Anim.spring) {
                if abs(total - currentTransferMinutes) >= 10 {
                    driveNote = "≈ \(drive) min drive to \(airport.iata) from where you are, plus parking and walking. Your plan currently allows \(currentTransferMinutes) min. Your location isn't stored."
                    driveSuggestion = total
                } else {
                    driveNote = "≈ \(drive) min drive to \(airport.iata) right now — your \(currentTransferMinutes)-min allowance already covers it. Your location isn't stored."
                    driveSuggestion = nil
                }
            }
        case .permissionDenied:
            withAnimation(Theme.Anim.gentle) {
                driveNote = "Location is off for Reclock — set the transfer time by hand in Adjust, or enable location in iOS Settings → Privacy."
                driveSuggestion = nil
            }
        case .unavailable:
            withAnimation(Theme.Anim.gentle) {
                driveNote = "Couldn't check traffic right now. Try again in a moment."
                driveSuggestion = nil
            }
        }
    }
}
