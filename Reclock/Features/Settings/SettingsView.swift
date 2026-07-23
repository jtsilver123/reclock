import SwiftUI
import AuthenticationServices
import ReclockKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var showDeleteAllConfirm = false
    @State private var calendarSweepResult: Int??  // nil = idle, .some(nil) = denied, .some(n) = removed
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
                privacySection
                dataSection
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
            .tint(Theme.accentDeep)
            .contentMargins(.bottom, 84, for: .scrollContent)
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
                HStack(spacing: Theme.Space.m) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15))
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                    }
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default preferences")
                            .font(.subheadline.weight(.semibold))
                        Text("Sleep times, chronotype, planes, caffeine, melatonin, plan defaults")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        } footer: {
            Text("Every new trip starts from these. Per-trip tuning lives in Adjust on the Plan tab — and \"Save these as my defaults\" there writes back here.")
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
                .tint(Theme.accent)
                Toggle(
                    "Include optional actions",
                    isOn: profileBinding(\.notifications.includeOptionalActions)
                )
                .tint(Theme.accent)
                QuietHoursEditor()
            }
        } header: {
            SettingsHeader(title: "Notifications", symbol: "bell.badge.fill")
        }
    }

    // MARK: Backup & sync

    @ViewBuilder
    private var backupSection: some View {
        Section {
            if model.state.settings.localOnlyMode {
                Label("Local-only mode is on — backup and sharing are paused.", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.auth.isSignedIn {
                LabeledContent("Signed in") {
                    Text(model.auth.email ?? "Apple ID")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let error = model.auth.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
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
                        .foregroundStyle(Theme.warning)
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
            Text("No account required — plans, reminders, and calendar scanning all run on-device and work in airplane mode. Optional sign-in adds an encrypted backup of your trips, nothing else.")
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
            .tint(Theme.accent)
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
            .tint(Theme.accent)
            Text("Off by default — never includes trip details, flights, or where you are.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            SettingsHeader(title: "Privacy", symbol: "lock.fill")
        }
    }

    // MARK: Your data

    private var dataSection: some View {
        Section {
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
            Button {
                Task {
                    let count = await model.deps.calendarExporter.removeEverything()
                    if count != nil { Haptics.soft() }
                    calendarSweepResult = .some(count)
                }
            } label: {
                Label("Remove Reclock events from Calendar", systemImage: "calendar.badge.minus")
            }
            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Label("Delete all data", systemImage: "trash")
            }
        } header: {
            SettingsHeader(title: "Your data", symbol: "tray.full.fill")
        } footer: {
            Text("Removing calendar events takes back everything Reclock ever added, across all trips — your own events are never touched.")
        }
        .alert(
            calendarSweepResult == .some(nil) ? "Calendar access is off" : "Calendar cleaned up",
            isPresented: Binding(
                get: { calendarSweepResult != nil },
                set: { if !$0 { calendarSweepResult = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if calendarSweepResult == .some(nil) {
                Text("Allow calendar access for Reclock in iOS Settings, then try again.")
            } else {
                let count = calendarSweepResult?.flatMap { $0 } ?? 0
                Text(count == 0
                     ? "There were no Reclock events to remove."
                     : "Removed \(count) event\(count == 1 ? "" : "s") Reclock had added.")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                WhyItWorksView()
            } label: {
                Label("Why light, sleep & caffeine timing work", systemImage: "questionmark.circle")
            }
            Link(destination: URL(string: "https://jtsilver123.github.io/reclock/privacy/")!) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://jtsilver123.github.io/reclock/")!) {
                Label("Support", systemImage: "lifepreserver")
            }
            // Shows itself the moment the App Store ID below is filled in.
            if let rateURL = Self.rateURL {
                Link(destination: rateURL) {
                    Label("Rate Reclock", systemImage: "star")
                }
            }
            ShareLink(item: URL(string: "https://jtsilver123.github.io/reclock/")!) {
                Label("Share Reclock with a traveler", systemImage: "square.and.arrow.up")
            }
            LabeledContent("Version", value: appVersion)
            LabeledContent("Plan protocol", value: "v\(ProtocolVersion.current.description)")
            Text("Reclock offers general wellness guidance for travel, not medical advice. If you have a sleep disorder or health condition, talk to a clinician.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            SettingsHeader(title: "About", symbol: "info.circle.fill")
        }
    }

    /// Numeric App Store ID — the "Apple ID" on the app's App Information page in
    /// App Store Connect. Empty until the app is live; the Rate row hides meanwhile.
    private static let appStoreID = ""

    private static var rateURL: URL? {
        guard !appStoreID.isEmpty else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
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

/// Every control writes through instantly — same contract as the Adjust sheet.
/// The old "Save changes" button silently discarded edits from anyone who backed
/// out without finding it.
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @State var profile: UserProfile

    @State private var bedtime = Date()
    @State private var wakeTime = Date()

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    HomeZonePicker(current: profile.homeZone) { picked in
                        profile.homeZone = picked
                    }
                } label: {
                    LabeledContent("Home time zone") {
                        Text(TimeFormat.zoneCity(profile.homeZone.resolved))
                    }
                }
            } header: {
                SettingsHeader(title: "Home", symbol: "house.fill")
            } footer: {
                Text("Where your body normally lives — every plan measures its shift from here. Installed Reclock while traveling? It may have picked up the wrong city; fixing it rebuilds upcoming plans.")
            }
            Section {
                DatePicker("Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                DatePicker("Wake time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                Picker("Chronotype", selection: $profile.chronotype) {
                    ForEach(Chronotype.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } header: {
                SettingsHeader(title: "Normal sleep", symbol: "bed.double.fill")
            }
            Section {
                HealthSleepRow { bed, wake in
                    // Health set the times: mirror them into the pickers above so the
                    // whole screen agrees, and persist through the same profile path.
                    bedtime = Calendar.current.date(
                        bySettingHour: bed.hour, minute: bed.minute, second: 0, of: Date()
                    ) ?? bedtime
                    wakeTime = Calendar.current.date(
                        bySettingHour: wake.hour, minute: wake.minute, second: 0, of: Date()
                    ) ?? wakeTime
                    profile.typicalBedtime = bed
                    profile.typicalWakeTime = wake
                }
            } header: {
                SettingsHeader(title: "Apple Health", symbol: "heart.fill")
            } footer: {
                Text("Optional. Reclock reads your recent sleep from Apple Health to set the bed and wake times above. Your Health data stays on this device — only the two resulting times are saved.")
            }
            Section {
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
                        .tint(Theme.accent)
                }
            } header: {
                SettingsHeader(title: "On planes", symbol: "airplane")
            }
            Section {
                Picker("Pre-trip adjustment", selection: $profile.preTripAdjustment) {
                    ForEach(PreTripAdjustmentWillingness.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            } header: {
                SettingsHeader(title: "Before a trip", symbol: "calendar.badge.clock")
            }
            Section {
                Toggle("Caffeine guidance", isOn: Binding(
                    get: { profile.caffeine == .include },
                    set: { profile.caffeine = $0 ? .include : .exclude }
                ))
                .tint(Theme.accent)
                Toggle("Optional melatonin reminders", isOn: Binding(
                    get: { profile.melatonin.remindersEnabled },
                    set: { profile.melatonin = $0 ? .includeOptionalReminders : .exclude }
                ))
                .tint(Theme.accent)
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
                SettingsHeader(title: "Caffeine, melatonin & intensity", symbol: "cup.and.saucer.fill")
            } footer: {
                Text("Melatonin steps appear only on nights your clock shifts earlier — typically eastward trips. New trips start from the default intensity. Every change applies instantly and rebuilds upcoming plans.")
            }
        }
        .navigationTitle("Default preferences")
        .tint(Theme.accentDeep)
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
        .onChange(of: bedtime) { _, newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            profile.typicalBedtime = LocalClockTime(hour: comps.hour ?? 23, minute: comps.minute ?? 0)
        }
        .onChange(of: wakeTime) { _, newValue in
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            profile.typicalWakeTime = LocalClockTime(hour: comps.hour ?? 7, minute: comps.minute ?? 0)
        }
        .onChange(of: profile) { _, updated in
            // The onAppear seeding round-trips identical values; only real edits
            // reach the store (and rebuild plans).
            guard updated != model.profile else { return }
            Task { await model.updateProfile(updated) }
        }
    }
}

// MARK: - Apple Health

/// The one place Apple Health is identified and used: reads recent sleep to set the
/// traveler's typical bed and wake times. Fully optional — the app never needs it,
/// and the row states plainly where the data goes.
private struct HealthSleepRow: View {
    @Environment(AppModel.self) private var model
    /// Called with the derived clock times so the editor can mirror them into its pickers.
    let onApplied: (LocalClockTime, LocalClockTime) -> Void

    @State private var availability: SleepDataAvailability?
    @State private var working = false
    @State private var note: Note?

    private struct Note: Equatable {
        var text: String
        var isWarning: Bool
    }

    var body: some View {
        Group {
            if availability == .unsupported {
                Label("Apple Health isn't available on this device.", systemImage: "heart.slash")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    if working {
                        HStack(spacing: Theme.Space.s) {
                            ProgressView()
                            Text("Reading your sleep…")
                        }
                    } else {
                        Label("Set my times from Apple Health", systemImage: "heart.text.square")
                    }
                }
                .disabled(working)
            }
            if let note {
                Label(note.text, systemImage: note.isWarning ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(note.isWarning ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(Theme.success))
                    .transition(.opacity)
            }
        }
        .task { availability = await model.healthSleepAvailability() }
    }

    private func connect() async {
        working = true
        defer { working = false }
        switch await model.connectHealthSleep() {
        case let .applied(bedtime, wakeTime, nights):
            Haptics.success()
            onApplied(bedtime, wakeTime)
            let bed = clockText(bedtime)
            let wake = clockText(wakeTime)
            withAnimation(Theme.Anim.gentle) {
                note = Note(text: "Set to \(bed)–\(wake) from your last \(nights) nights.", isWarning: false)
            }
        case .connectedNoData:
            withAnimation(Theme.Anim.gentle) {
                note = Note(text: "Connected, but there wasn't enough recent sleep to set your times. They're unchanged.", isWarning: true)
            }
        case .denied:
            withAnimation(Theme.Anim.gentle) {
                note = Note(text: "Health access is off. You can allow it in iOS Settings → Health → Data Access, or just set your times by hand above.", isWarning: true)
            }
        case .unsupported:
            withAnimation(Theme.Anim.gentle) {
                availability = .unsupported
            }
        }
    }

    private func clockText(_ clock: LocalClockTime) -> String {
        let date = Calendar.current.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Home zone picker

/// Search-and-pick the home time zone by city name. The device's own zone gets a
/// one-tap shortcut, since "I onboarded abroad and home is where my phone usually
/// lives" is the whole reason this screen exists.
private struct HomeZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    let current: ZoneID
    let onPick: (ZoneID) -> Void

    @State private var query = ""

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()
        guard q.count >= 2 else { return [] }
        return Array(TimeZone.knownTimeZoneIdentifiers.filter { $0.lowercased().contains(q) }.prefix(20))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Current home", value: TimeFormat.zoneCity(current.resolved))
                if ZoneID(TimeZone.current.identifier) != current {
                    Button {
                        Haptics.success()
                        onPick(ZoneID(TimeZone.current.identifier))
                        dismiss()
                    } label: {
                        Label(
                            "Use this device's zone (\(TimeFormat.zoneCity(.current)))",
                            systemImage: "iphone"
                        )
                    }
                }
            }
            Section {
                TextField("Search a city, e.g. Chicago", text: $query)
                    .autocorrectionDisabled()
                ForEach(matches, id: \.self) { identifier in
                    Button {
                        Haptics.success()
                        onPick(ZoneID(identifier))
                        dismiss()
                    } label: {
                        HStack {
                            Text(identifier.replacingOccurrences(of: "_", with: " "))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if identifier == current.identifier {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accentDeep)
                            }
                        }
                    }
                }
            } footer: {
                Text("Zones are named for a major city — pick the one your home shares a clock with.")
            }
        }
        .navigationTitle("Home time zone")
        .tint(Theme.accentDeep)
        .navigationBarTitleDisplayMode(.inline)
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
