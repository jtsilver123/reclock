import SwiftUI
import ReclockKit

/// Post-trip check-in: 90 seconds, tappable, and it directly improves the product.
struct PostTripSurveyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var severity = 5
    @State private var usefulness = 7
    @State private var adherence: SurveyAdherence = .aboutHalf
    @State private var unrealistic: Set<ActionType> = []
    @State private var daysUntilNormal = 3
    @State private var wouldUseAgain = true

    private let candidateTypes: [ActionType] = [
        .seekLight, .avoidLight, .sleep, .stayAwake, .caffeineCutoff, .melatoninOptional, .nap,
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("How rough was jet lag this trip?") {
                    RatingSlider(value: $severity, low: "Barely felt it", high: "Wrecked me")
                }
                Section("How useful was the plan?") {
                    RatingSlider(value: $usefulness, low: "Not at all", high: "Very")
                }
                Section("How much of it did you follow?") {
                    Picker("Adherence", selection: $adherence) {
                        ForEach(SurveyAdherence.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Anything feel unrealistic? (tap all that apply)") {
                    ForEach(candidateTypes, id: \.self) { type in
                        Button {
                            if unrealistic.contains(type) {
                                unrealistic.remove(type)
                            } else {
                                unrealistic.insert(type)
                            }
                        } label: {
                            HStack {
                                Image(systemName: type.symbolName)
                                    .foregroundStyle(Theme.tint(for: type))
                                    .frame(width: 26)
                                Text(label(for: type))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if unrealistic.contains(type) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accentDeep)
                                }
                            }
                        }
                    }
                }
                Section("Days until you felt normal") {
                    Stepper("\(daysUntilNormal) day\(daysUntilNormal == 1 ? "" : "s")", value: $daysUntilNormal, in: 0...14)
                }
                Section {
                    Toggle("I'd use Reclock again", isOn: $wouldUseAgain)
                }
                Section {
                    Button("Submit") {
                        Task {
                            let survey = PostTripSurvey(
                                tripID: trip.id,
                                submittedAt: model.deps.now(),
                                severity: severity,
                                usefulness: usefulness,
                                adherence: adherence,
                                unrealisticActionTypes: unrealistic.map(\.rawValue),
                                daysUntilNormal: daysUntilNormal,
                                wouldUseAgain: wouldUseAgain
                            )
                            await model.submitSurvey(survey)
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Stored on your device. If you've enabled anonymous analytics, only the ratings — never trip details — are shared to improve default plans.")
                }
            }
            .navigationTitle("How did it go?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
            }
        }
    }

    private func label(for type: ActionType) -> String {
        switch type {
        case .seekLight: "Light-seeking windows"
        case .avoidLight: "Avoiding light"
        case .sleep: "Sleep windows"
        case .stayAwake: "Staying awake"
        case .caffeineCutoff: "Caffeine cutoffs"
        case .melatoninOptional: "Melatonin timing"
        case .nap: "Nap limits"
        default: type.rawValue
        }
    }
}

private struct RatingSlider: View {
    @Binding var value: Int
    let low: String
    let high: String

    var body: some View {
        VStack {
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: 0...10,
                step: 1
            )
            .accessibilityValue("\(value) of 10")
            HStack {
                Text(low)
                Spacer()
                Text("\(value)")
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(high)
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }
}
