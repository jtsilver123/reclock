import SwiftUI
import ReclockKit

/// The Plan tab's tune-up sheet: your sleep anchor plus the per-trip levers —
/// intensity, when shifting starts, recovery, and the drive to the airport.
/// Long-term traits (planes, caffeine, melatonin, chronotype) live in Settings ›
/// Default preferences; this sheet is about *this* plan. Every change rebuilds
/// the plan on the spot, and closing after a change announces the rebuild.
struct PlanAdjustSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var savedDefaults = false
    /// Any plan-affecting edit arms the "plan rebuilt" moment shown on close.
    @State private var touched = false

    /// Every edit re-arms both the close celebration and Save-as-defaults —
    /// otherwise the save button latches "Saved" and can't take a second value.
    private func markEdited() {
        touched = true
        savedDefaults = false
    }

    /// Live copy — edits land in the store, and this view re-reads them.
    private var currentTrip: Trip {
        model.state.trips.first { $0.id == trip.id } ?? trip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("I usually sleep at", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                    DatePicker("and wake at", selection: wakeBinding, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Your sleep")
                } footer: {
                    Text("The anchor for every plan you build.")
                }

                Section {
                    Picker("Intensity", selection: intensityBinding) {
                        ForEach(PlanIntensity.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(currentTrip.intensity.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Picker("Start adjusting", selection: preTripBinding) {
                        Text("Automatic").tag(-1)
                        Text("On travel day").tag(0)
                        Text("1 day before").tag(1)
                        Text("2 days before").tag(2)
                        Text("3 days before").tag(3)
                        Text("4 days before").tag(4)
                    }

                    Picker("Recovery after landing", selection: recoveryBinding) {
                        Text("Automatic").tag(-1)
                        Text("None").tag(0)
                        Text("1 day").tag(1)
                        Text("2 days").tag(2)
                        Text("3 days").tag(3)
                    }

                    if currentTrip.destinationNights.map({ $0 <= 3 }) == true {
                        Picker("Short-trip strategy", selection: strategyBinding) {
                            Text("Automatic").tag(AdaptationStrategy.automatic)
                            Text("Fully adapt").tag(AdaptationStrategy.fullyAdapt)
                            Text("Stay on home time").tag(AdaptationStrategy.anchorToHome)
                        }
                    }

                    TransferTimeRow(
                        minutes: transferBinding,
                        departureAirport: departureAirport
                    )
                    Text("Door to terminal — sets your leave-by reminder and keeps sleep clear of the airport run.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    Text("This plan")
                } footer: {
                    Text("Every change rebuilds the plan and its reminders instantly.")
                }

                Section {
                    Button {
                        saveAsDefaults()
                    } label: {
                        Label(
                            savedDefaults ? "Saved as your defaults" : "Save these as my defaults",
                            systemImage: savedDefaults ? "checkmark.circle.fill" : "square.and.arrow.down"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .disabled(savedDefaults)
                } footer: {
                    Text("Future trips start from this intensity and head start. Long-term traits — planes, caffeine, melatonin, chronotype — live in Settings › Default preferences.")
                }
            }
            .navigationTitle("Adjust plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear {
                // The plan already rebuilt live with each change; this is the moment
                // that SAYS so — toast up top, pills springing to their new spots.
                if touched {
                    Haptics.success()
                    withAnimation(Theme.Anim.spring) {
                        model.celebration = .planTuned()
                    }
                }
            }
        }
    }

    // MARK: Bindings

    private var departureAirport: Airport? {
        currentTrip.segments.first.flatMap {
            model.deps.airports.airport(iata: $0.departureAirport)
        }
    }

    private func clockDate(_ clock: LocalClockTime) -> Date {
        Calendar.current.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
        ) ?? Date()
    }

    private func clock(from date: Date) -> LocalClockTime {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return LocalClockTime(hour: comps.hour ?? 23, minute: comps.minute ?? 0)
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(
            get: { clockDate(model.profile?.typicalBedtime ?? LocalClockTime(hour: 23)) },
            set: { newValue in
                markEdited()
                Task {
                    guard var profile = model.profile else { return }
                    profile.typicalBedtime = clock(from: newValue)
                    await model.updateProfile(profile)
                }
            }
        )
    }

    private var wakeBinding: Binding<Date> {
        Binding(
            get: { clockDate(model.profile?.typicalWakeTime ?? LocalClockTime(hour: 7)) },
            set: { newValue in
                markEdited()
                Task {
                    guard var profile = model.profile else { return }
                    profile.typicalWakeTime = clock(from: newValue)
                    await model.updateProfile(profile)
                }
            }
        )
    }

    private var intensityBinding: Binding<PlanIntensity> {
        Binding(
            get: { currentTrip.intensity },
            set: { newValue in
                Haptics.selection()
                markEdited()
                var updated = currentTrip
                updated.intensity = newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private var preTripBinding: Binding<Int> {
        Binding(
            get: { currentTrip.preTripDaysOverride ?? -1 },
            set: { newValue in
                Haptics.selection()
                markEdited()
                var updated = currentTrip
                updated.preTripDaysOverride = newValue < 0 ? nil : newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private var recoveryBinding: Binding<Int> {
        Binding(
            get: { currentTrip.recoveryDaysOverride ?? -1 },
            set: { newValue in
                Haptics.selection()
                markEdited()
                var updated = currentTrip
                updated.recoveryDaysOverride = newValue < 0 ? nil : newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private func saveAsDefaults() {
        Haptics.success()
        var settings = model.state.settings
        settings.defaultIntensity = currentTrip.intensity
        let trip = currentTrip
        Task {
            await model.updateSettings(settings)
            if let override = trip.preTripDaysOverride, var profile = model.profile {
                profile.preTripAdjustment = switch override {
                case 0: .none
                case 1: .small
                case 2: .moderate
                default: .maximum
                }
                await model.updateProfile(profile)
            }
        }
        withAnimation(Theme.Anim.spring) { savedDefaults = true }
    }

    private var strategyBinding: Binding<AdaptationStrategy> {
        Binding(
            get: { currentTrip.adaptationStrategy },
            set: { newValue in
                Haptics.selection()
                markEdited()
                var updated = currentTrip
                updated.adaptationStrategy = newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }

    private var transferBinding: Binding<Int> {
        Binding(
            get: { currentTrip.airportTransferMinutes ?? 60 },
            set: { newValue in
                markEdited()
                var updated = currentTrip
                updated.airportTransferMinutes = newValue
                Task { await model.updateTrip(updated) }
            }
        )
    }
}
