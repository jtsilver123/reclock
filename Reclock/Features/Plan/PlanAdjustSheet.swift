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
    /// Debounce for the bed/wake wheels: one replan for the settled value, not one
    /// per detent — a spin from 23:00 to 21:30 is one edit, not six.
    @State private var profileWriteTask: Task<Void, Never>?
    /// Local echo while the debounced write is in flight, so the wheel never
    /// snaps back to the old stored value on a re-render.
    @State private var pendingBed: LocalClockTime?
    @State private var pendingWake: LocalClockTime?

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
                    SettingsHeader(title: "Your sleep", symbol: "bed.double.fill")
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
                    SettingsHeader(title: "This plan", symbol: "slider.horizontal.3")
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
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: savedDefaults)
                    }
                    .disabled(savedDefaults)
                } footer: {
                    Text("Future trips start from this intensity and head start. Long-term traits — planes, caffeine, melatonin, chronotype — live in Settings › Default preferences.")
                }
            }
            .navigationTitle("Adjust plan")
            .tint(Theme.accentDeep)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear {
                // A pending debounced write must not die with the sheet.
                if profileWriteTask != nil {
                    profileWriteTask = nil
                    Task {
                        guard var profile = model.profile else { return }
                        if let bed = pendingBed { profile.typicalBedtime = bed }
                        if let wake = pendingWake { profile.typicalWakeTime = wake }
                        if pendingBed != nil || pendingWake != nil {
                            await model.updateProfile(profile)
                        }
                    }
                }
                // The plan already rebuilt live with each change; this is the moment
                // that SAYS so — toast up top, pills springing to their new spots.
                // Not when the same action just raised an error alert.
                if touched && model.activeAlert == nil {
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
            get: { clockDate(pendingBed ?? model.profile?.typicalBedtime ?? LocalClockTime(hour: 23)) },
            set: { newValue in
                markEdited()
                pendingBed = clock(from: newValue)
                scheduleProfileWrite()
            }
        )
    }

    private var wakeBinding: Binding<Date> {
        Binding(
            get: { clockDate(pendingWake ?? model.profile?.typicalWakeTime ?? LocalClockTime(hour: 7)) },
            set: { newValue in
                markEdited()
                pendingWake = clock(from: newValue)
                scheduleProfileWrite()
            }
        )
    }

    /// Coalesces wheel spins into one profile write ~0.4s after the last detent.
    /// Every write replans all live trips and reschedules notifications — per-detent
    /// that's a burst of full rebuilds fighting each other.
    private func scheduleProfileWrite() {
        profileWriteTask?.cancel()
        profileWriteTask = Task {
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            guard var profile = model.profile else { return }
            if let bed = pendingBed { profile.typicalBedtime = bed }
            if let wake = pendingWake { profile.typicalWakeTime = wake }
            await model.updateProfile(profile)
            pendingBed = nil
            pendingWake = nil
        }
    }

    private var intensityBinding: Binding<PlanIntensity> {
        Binding(
            get: { currentTrip.intensity },
            set: { newValue in
                Haptics.selection()
                markEdited()
                Task { await model.updateTrip(id: currentTrip.id) { $0.intensity = newValue } }
            }
        )
    }

    private var preTripBinding: Binding<Int> {
        Binding(
            get: { currentTrip.preTripDaysOverride ?? -1 },
            set: { newValue in
                Haptics.selection()
                markEdited()
                Task { await model.updateTrip(id: currentTrip.id) { $0.preTripDaysOverride = newValue < 0 ? nil : newValue } }
            }
        )
    }

    private var recoveryBinding: Binding<Int> {
        Binding(
            get: { currentTrip.recoveryDaysOverride ?? -1 },
            set: { newValue in
                Haptics.selection()
                markEdited()
                Task { await model.updateTrip(id: currentTrip.id) { $0.recoveryDaysOverride = newValue < 0 ? nil : newValue } }
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
                Task { await model.updateTrip(id: currentTrip.id) { $0.adaptationStrategy = newValue } }
            }
        )
    }

    private var transferBinding: Binding<Int> {
        Binding(
            get: { currentTrip.airportTransferMinutes ?? 60 },
            set: { newValue in
                markEdited()
                Task { await model.updateTrip(id: currentTrip.id) { $0.airportTransferMinutes = newValue } }
            }
        )
    }
}
