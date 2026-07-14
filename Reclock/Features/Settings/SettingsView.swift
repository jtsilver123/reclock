import SwiftUI
import AuthenticationServices
import ReclockKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var showDeleteAllConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var exportedData: ExportPayload?
    @State private var notificationStatusGranted: Bool?

    struct ExportPayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            List {
                preferencesSection
                notificationSection
                backupSection
                Section {
                    NavigationLink {
                        WhyItWorksView()
                    } label: {
                        Label("Why light, sleep & caffeine timing work", systemImage: "questionmark.circle")
                    }
                } header: {
                    SettingsHeader(title: "Understand the plan", symbol: "sparkles")
                }
                privacySection
                aboutSection
                #if DEBUG
                Section("Developer") {
                    NavigationLink {
                        DevMenuView()
                    } label: {
                        Label("Demo trips & fixtures", systemImage: "wrench.and.screwdriver")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .task {
                notificationStatusGranted = await model.deps.notifications.permissionGranted()
            }
            .confirmationDialog(
                "Delete all Reclock data?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await model.deleteAllData() }
                }
            } message: {
                Text(model.auth.isSignedIn
                     ? "Removes your profile, trips, plans, reminders and survey answers from this device. Your encrypted server backup is not touched — use Delete account & backup to remove that too."
                     : "Removes your profile, trips, plans, reminders and survey answers from this device. There is no server copy — this is permanent.")
            }
            .sheet(item: $exportedData) { payload in
                ShareSheet(url: payload.url)
            }
        }
    }

    // MARK: Profile

    @ViewBuilder
    private var preferencesSection: some View {
        Section {
            NavigationLink {
                if let profile = model.profile {
                    ProfileEditorView(profile: profile)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep & plan preferences")
                        .font(.subheadline.weight(.semibold))
                    Text("Sleep times, chronotype, caffeine, melatonin, default intensity")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            Text("Day-to-day tuning lives on the Plan tab — tap the sliders on any plan.")
        }
    }

    // MARK: Notifications

    private var notificationSection: some View {
        Section {
            if let granted = notificationStatusGranted, !granted {
                Button {
                    Task {
                        notificationStatusGranted = await model.requestNotificationPermission()
                    }
                } label: {
                    Label("Enable reminders", systemImage: "bell.badge")
                }
                Text("Without alerts, the Plan tab still shows everything as an in-app checklist. You can also enable alerts later in iOS Settings → Notifications → Reclock.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Toggle(
                    "Plan reminders",
                    isOn: profileBinding(\.notifications.enabled)
                )
                Toggle(
                    "Include optional actions",
                    isOn: profileBinding(\.notifications.includeOptionalActions)
                )
                QuietHoursEditor()
            }
        } header: {
            SettingsHeader(title: "Notifications", symbol: "bell.badge.fill")
        }
    }

    // MARK: Planning

    // MARK: Backup & sync

    @ViewBuilder
    private var backupSection: some View {
        Section {
            if model.auth.isSignedIn {
                LabeledContent("Signed in") {
                    Text(model.auth.email ?? "Apple ID")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let error = model.auth.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task {
                        await model.backUpNow()
                        Haptics.success()
                    }
                } label: {
                    Label(
                        model.sync.lastBackupDescription.map { "Back up now (last: \($0))" } ?? "Back up now",
                        systemImage: "icloud.and.arrow.up"
                    )
                    .animation(Theme.Anim.gentle, value: model.sync.lastBackupDescription)
                }
                Button("Sign out") {
                    Task { await model.auth.signOut() }
                }
                Button(role: .destructive) {
                    showDeleteAccountConfirm = true
                } label: {
                    Label("Delete account & backup", systemImage: "person.crop.circle.badge.xmark")
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    model.auth.prepare(request)
                } onCompletion: { result in
                    Task {
                        if await model.auth.complete(result) {
                            Haptics.success()
                            await model.handleSignedIn()
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                if model.auth.googleAvailable {
                    GoogleSignInButton {
                        Task {
                            if await model.auth.signInWithGoogle() {
                                Haptics.success()
                                await model.handleSignedIn()
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if let error = model.auth.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            SettingsHeader(title: "Backup & sync", symbol: "icloud.fill")
        } footer: {
            Text(model.auth.isSignedIn
                 ? "Your trips back up automatically after every change. A new phone signed into the same Apple ID restores them."
                 : "Optional. Everything works without it — signing in keeps an encrypted copy of your trips so a new phone can restore them.")
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete account & backup", role: .destructive) {
                Task { _ = await model.auth.deleteAccount() }
            }
        } message: {
            Text("Removes your server-side account and backup permanently. Everything on this phone stays.")
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            Label("Everything stays on this device", systemImage: "iphone.and.arrow.forward")
                .font(.subheadline)
            Text("No account required — plans, reminders, and calendar scanning all run on-device and work in airplane mode. Optional sign-in adds an encrypted backup of your trips, nothing else. Anonymous usage analytics are OFF unless you turn them on.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Toggle("Local-only mode", isOn: Binding(
                get: { model.state.settings.localOnlyMode },
                set: { newValue in
                    var settings = model.state.settings
                    settings.localOnlyMode = newValue
                    Task { await model.updateSettings(settings) }
                }
            ))
            Text("Blocks every network feature — flight lookup, drive-time estimates, backup, sharing. Plans themselves never needed the internet.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Toggle("Share anonymous usage analytics", isOn: Binding(
                get: { model.state.settings.analyticsEnabled },
                set: { newValue in
                    var settings = model.state.settings
                    settings.analyticsEnabled = newValue
                    Task { await model.updateSettings(settings) }
                }
            ))
            Button {
                Task {
                    if let data = await model.exportData() {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent("reclock-export.json")
                        try? data.write(to: url)
                        exportedData = ExportPayload(url: url)
                    }
                }
            } label: {
                Label("Export my data (JSON)", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label("Delete all data", systemImage: "trash")
            }
        } header: {
            SettingsHeader(title: "Privacy", symbol: "lock.fill")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Plan protocol", value: "v\(ProtocolVersion.current.description)")
            Link(destination: URL(string: "https://jtsilver123.github.io/reclock/privacy/")!) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://jtsilver123.github.io/reclock/")!) {
                Label("Support", systemImage: "lifepreserver")
            }
            Text("Reclock offers general wellness guidance for travel, not medical advice. If you have a sleep disorder or health condition, talk to a clinician.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            SettingsHeader(title: "About", symbol: "info.circle.fill")
        }
    }

    /// Locale-aware rendering of a stored clock time (12/24-hour follows the device).
    private func clockText(_ clock: LocalClockTime) -> String {
        let date = Calendar.current.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func profileBinding(_ keyPath: WritableKeyPath<UserProfile, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.profile?[keyPath: keyPath] ?? false },
            set: { newValue in
                Task {
                    guard var profile = model.profile else { return }
                    profile[keyPath: keyPath] = newValue
                    await model.updateProfile(profile)
                }
            }
        )
    }
}

// MARK: - Section header

/// Standard header type plus a small tinted glyph, so every section gets a visual anchor.
private struct SettingsHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accentDeep)
        }
    }
}

// MARK: - Quiet hours

private struct QuietHoursEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.profile != nil {
            DatePicker(
                "Quiet from",
                selection: clockBinding(\.start),
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "until",
                selection: clockBinding(\.end),
                displayedComponents: .hourAndMinute
            )
            Text("Only sleep-related reminders (wind-down, sleep windows) may arrive during quiet hours; everything else waits or is skipped.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func clockBinding(_ keyPath: WritableKeyPath<ClockRange, LocalClockTime>) -> Binding<Date> {
        Binding(
            get: {
                let clock = model.profile?.notifications.quietHours[keyPath: keyPath]
                    ?? LocalClockTime(hour: 22)
                return Calendar.current.date(
                    bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                Task {
                    guard var profile = model.profile else { return }
                    profile.notifications.quietHours[keyPath: keyPath] = LocalClockTime(
                        hour: comps.hour ?? 22, minute: comps.minute ?? 0
                    )
                    await model.updateProfile(profile)
                }
            }
        )
    }
}

// MARK: - Profile editor

struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var profile: UserProfile

    @State private var bedtime = Date()
    @State private var wakeTime = Date()

    var body: some View {
        Form {
            Section("Normal sleep") {
                DatePicker("Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                DatePicker("Wake time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                Picker("Chronotype", selection: $profile.chronotype) {
                    ForEach(Chronotype.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("On planes") {
                Picker("Sleep on planes", selection: $profile.planeSleepAbility) {
                    ForEach(PlaneSleepAbility.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if profile.planeSleepAbility != .never {
                    Stepper(
                        "Max in-flight sleep: \(Int(profile.maxInFlightSleep / 3600))h",
                        value: Binding(
                            get: { profile.maxInFlightSleep / 3600 },
                            set: { profile.maxInFlightSleep = $0 * 3600 }
                        ),
                        in: 1...9,
                        step: 1
                    )
                    Toggle("Skip meals to sleep", isOn: $profile.prioritizesSleepOverMeals)
                }
            }
            Section("Before a trip") {
                Picker("Pre-trip adjustment", selection: $profile.preTripAdjustment) {
                    ForEach(PreTripAdjustmentWillingness.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            }
            Section {
                Toggle("Caffeine guidance", isOn: Binding(
                    get: { profile.caffeine == .include },
                    set: { profile.caffeine = $0 ? .include : .exclude }
                ))
                Toggle("Optional melatonin reminders", isOn: Binding(
                    get: { profile.melatonin.remindersEnabled },
                    set: { profile.melatonin = $0 ? .includeOptionalReminders : .exclude }
                ))
                Picker("Default plan intensity", selection: Binding(
                    get: { model.state.settings.defaultIntensity ?? .balanced },
                    set: { newValue in
                        var settings = model.state.settings
                        settings.defaultIntensity = newValue
                        Task { await model.updateSettings(settings) }
                    }
                )) {
                    ForEach(PlanIntensity.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } header: {
                Text("Guidance & defaults")
            } footer: {
                Text("Melatonin steps appear only on nights your clock shifts earlier — typically eastward trips. New trips start from the default intensity.")
            }
            Section {
                Button("Save changes") {
                    Task {
                        var updated = profile
                        let bedComps = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
                        let wakeComps = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
                        updated.typicalBedtime = LocalClockTime(hour: bedComps.hour ?? 23, minute: bedComps.minute ?? 0)
                        updated.typicalWakeTime = LocalClockTime(hour: wakeComps.hour ?? 7, minute: wakeComps.minute ?? 0)
                        await model.updateProfile(updated)
                        dismiss()
                    }
                }
            } footer: {
                Text("Changing your profile rebuilds the plan for upcoming trips.")
            }
        }
        .navigationTitle("Sleep profile")
        .onAppear {
            bedtime = Calendar.current.date(
                bySettingHour: profile.typicalBedtime.hour,
                minute: profile.typicalBedtime.minute, second: 0, of: Date()
            ) ?? Date()
            wakeTime = Calendar.current.date(
                bySettingHour: profile.typicalWakeTime.hour,
                minute: profile.typicalWakeTime.minute, second: 0, of: Date()
            ) ?? Date()
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Dev menu (DEBUG only)

#if DEBUG
struct DevMenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Load fixture (replaces nothing, adds trip)") {
                fixtureButton("NYC → Helsinki (+7 east, return)") { DemoTrips.newYorkToHelsinki(reference: $0) }
                fixtureButton("LA → Tokyo (date line, −8)") { DemoTrips.losAngelesToTokyo(reference: $0) }
                fixtureButton("London → NYC (−5 west)") { DemoTrips.londonToNewYork(reference: $0) }
                fixtureButton("NYC → Honolulu (−6 west)") { DemoTrips.newYorkToHonolulu(reference: $0) }
                fixtureButton("Sydney → SF (date line east)") { DemoTrips.sydneyToSanFrancisco(reference: $0) }
                fixtureButton("NYC → Singapore via FRA (+12)") { DemoTrips.newYorkToSingaporeViaFrankfurt(reference: $0) }
                fixtureButton("48h London (anchor mode)") { DemoTrips.shortLondonBusinessTrip(reference: $0) }
                fixtureButton("Wedding in London (max mode)") { DemoTrips.weddingTrip(reference: $0) }
                fixtureButton("Delayed overnight EWR → LHR") { DemoTrips.delayedOvernight(reference: $0) }
            }
            Section("Reference date") {
                Text("Fixtures are generated relative to now − 5 days, so the flagship trip sits on landing day.")
                    .font(.caption)
            }
        }
        .navigationTitle("Dev fixtures")
    }

    private func fixtureButton(_ title: String, _ make: @escaping (Date) -> Trip) -> some View {
        Button(title) {
            Task {
                let reference = model.deps.now().addingTimeInterval(-5 * 86_400)
                let trip = make(reference)
                let profile = model.profile ?? DemoTrips.defaultProfile(homeZone: TimeZone.current.identifier)
                await model.loadFixture((trip, profile), reference: reference)
            }
        }
    }
}
#endif
