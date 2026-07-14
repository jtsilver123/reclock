import SwiftUI
import ReclockKit

/// "Getting to the airport" control: preset menu + optional one-tap drive-time estimate
/// from the user's current location (MapKit). Used in the Adjust sheet, manual entry, and
/// flight lookup so the behavior is identical everywhere.
struct TransferTimeRow: View {
    @Environment(AppModel.self) private var model
    @Binding var minutes: Int
    /// Departure airport, for the ETA destination. Estimation hides when nil or when the
    /// airport has no coordinates (custom entries).
    var departureAirport: Airport?

    @State private var isEstimating = false
    @State private var note: Note?

    private struct Note: Equatable {
        var text: String
        var isWarning: Bool
    }

    private static let presets = [20, 30, 45, 60, 75, 90, 120]

    private var canEstimate: Bool {
        departureAirport?.latitude != nil
            && departureAirport?.longitude != nil
            && !model.state.settings.localOnlyMode
    }

    var body: some View {
        HStack {
            Text("Getting to the airport")
            Spacer()
            Menu {
                ForEach(Self.presets, id: \.self) { preset in
                    Button("\(preset) min") {
                        minutes = preset
                        note = nil
                        Haptics.selection()
                    }
                }
            } label: {
                Text("\(minutes) min")
                    .font(.body.monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(Theme.Anim.gentle, value: minutes)
            }
            .accessibilityLabel("Transfer time: \(minutes) minutes")
        }

        if canEstimate {
            Button {
                Task { await estimate() }
            } label: {
                if isEstimating {
                    HStack(spacing: Theme.Space.s) {
                        ProgressView()
                        Text("Checking drive time…")
                    }
                } else {
                    Label(
                        "Estimate from my location",
                        systemImage: "location"
                    )
                }
            }
            .font(.footnote)
            .disabled(isEstimating)
        }

        if let note {
            Label(note.text, systemImage: note.isWarning ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(note.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(Theme.textSecondary))
                .transition(.opacity)
                .animation(Theme.Anim.gentle, value: note)
        }
    }

    private func estimate() async {
        guard let airport = departureAirport,
              let latitude = airport.latitude,
              let longitude = airport.longitude else { return }
        isEstimating = true
        defer { isEstimating = false }
        switch await model.deps.transitEstimator.estimateMinutes(toLatitude: latitude, longitude: longitude) {
        case .minutes(let total, let drive):
            minutes = total
            Haptics.soft()
            note = Note(
                text: "≈ \(drive) min drive to \(airport.iata) from where you are now, plus parking and walking. Your location isn't stored.",
                isWarning: false
            )
        case .permissionDenied:
            note = Note(
                text: "Location is off for Reclock — no problem, just pick a value. (Enable later in iOS Settings → Privacy → Location.)",
                isWarning: true
            )
        case .unavailable:
            note = Note(
                text: "Couldn't estimate right now. Pick the value that matches your usual ride.",
                isWarning: true
            )
        }
    }
}
