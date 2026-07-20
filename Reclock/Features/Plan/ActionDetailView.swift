import SwiftUI
import ReclockKit

/// Full-screen detail for any action (from the pinned hero or any day in the plan).
struct ActionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let action: PlanAction
    let trip: Trip

    @State private var checkingDrive = false
    @State private var driveNote: String?
    @State private var driveSuggestion: Int?

    private var zone: TimeZone { action.displayZone.resolved }

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
                    Text(action.title)
                        .font(Theme.display(30))
                        .foregroundStyle(Color.white)
                    Text("\(TimeFormat.range(action.window, zone: zone)) · \(TimeFormat.zoneCity(zone)) time")
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

                Text(action.instruction)
                    .font(Theme.display(21, black: false))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                driveTimeCheck

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Why this helps")
                    Text(action.explanation)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    if let alternative = action.alternative {
                        SectionHeader(title: "If it's not practical")
                        Text(alternative)
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note = action.adjustmentNote {
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .accessibilityHidden(true)
                        Text("Evidence: \(action.confidence.displayName)")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                if action.completion == .pending {
                    Button {
                        Haptics.success()
                        Task {
                            await model.setCompletion(.done, for: action, in: trip)
                            dismiss()
                        }
                    } label: {
                        Label("Mark done", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Couldn't do it") {
                        Haptics.soft()
                        Task {
                            await model.setCompletion(.notPossible, for: action, in: trip)
                            dismiss()
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Label(
                        action.completion == .done ? "Completed" : "Marked as \(completionText)",
                        systemImage: action.completion == .done ? "checkmark.circle.fill" : "slash.circle"
                    )
                    .font(.headline)
                    .foregroundStyle(action.completion == .done ? Theme.success : Theme.textSecondary)

                    if action.completion != .expired {
                        Button("Undo — mark as not done yet") {
                            Haptics.soft()
                            Task {
                                await model.setCompletion(.pending, for: action, in: trip)
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
        switch action.completion {
        case .notPossible: "couldn't do it"
        case .skipped: "skipped"
        case .sleptInstead: "slept instead"
        case .expired: "missed"
        default: action.completion.rawValue
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
        if action.type == .leaveForAirport, action.completion == .pending,
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
                            guard var updated = model.state.trips.first(where: { $0.id == trip.id }) else { return }
                            updated.airportTransferMinutes = suggestion
                            await model.updateTrip(updated)
                        }
                    } label: {
                        Text("Plan around \(suggestion) min instead")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
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
