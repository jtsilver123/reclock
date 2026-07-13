import SwiftUI
import ReclockKit

/// Progressive onboarding: value → sleep basics → plane sleep → constraints → plan style →
/// preferences. Short, skimmable, and every answer has a sensible default so "just keep
/// tapping continue" still produces a good profile.
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model

    @State private var step = 0
    @State private var bedtime = defaultTime(hour: 23)
    @State private var wakeTime = defaultTime(hour: 7)
    @State private var chronotype: Chronotype = .neutral
    @State private var planeSleep: PlaneSleepAbility = .sometimes
    @State private var maxPlaneSleepHours: Double = 4
    @State private var prioritizeSleepOverMeals = false
    @State private var willingness: PreTripAdjustmentWillingness = .small
    @State private var includeCaffeine = true
    @State private var includeMelatonin = false
    @State private var wantsNotifications = true
    @State private var healthSuggestion: SleepPatternAnalyzer.Suggestion?

    private static func defaultTime(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private let stepCount = 5

    var body: some View {
        VStack(spacing: 0) {
            if step > 0 {
                ProgressView(value: Double(step), total: Double(stepCount))
                    .tint(Theme.accent)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.s)
                    .accessibilityLabel("Step \(step) of \(stepCount)")
            }
            TabView(selection: $step) {
                welcome.tag(0)
                sleepBasics.tag(1)
                planeSleepStep.tag(2)
                planStyle.tag(3)
                preferences.tag(4)
                finish.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: Theme.Anim.standard), value: step)
        }
        .background(Theme.background)
        .onAppear {
            model.deps.analytics.track(.onboardingStarted)
        }
    }

    // MARK: Screens

    private var welcome: some View {
        OnboardingScreen(
            primaryLabel: "Add my trip",
            primaryAction: { step = 1 }
        ) {
            Spacer()
            BreathingSymbol(systemName: "sun.and.horizon.fill", size: 64)
            Text("Feel local when you land")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text("Your flights become a plan for sleep, light, and caffeine.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HowItWorksRow()
                .padding(.vertical, Theme.Space.m)
            Text("Free · Private · Works offline")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private var sleepBasics: some View {
        OnboardingScreen(
            title: "Your normal sleep",
            subtitle: "At home, on a regular night — this anchors the whole plan.",
            symbol: "moon.zzz.fill",
            primaryLabel: "Continue",
            primaryAction: { step = 2 }
        ) {
            VStack(spacing: Theme.Space.m) {
                if let suggestion = healthSuggestion {
                    Button {
                        bedtime = time(from: suggestion.bedtime)
                        wakeTime = time(from: suggestion.wakeTime)
                    } label: {
                        Label(
                            "Use my recent sleep: \(suggestion.bedtime.description)–\(suggestion.wakeTime.description)",
                            systemImage: "heart.fill"
                        )
                        .font(.footnote)
                    }
                }
                HStack {
                    Text("I usually sleep at")
                    Spacer()
                    DatePicker("Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                HStack {
                    Text("and wake at")
                    Spacer()
                    DatePicker("Wake time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Divider()
                Picker("Chronotype", selection: $chronotype) {
                    ForEach(Chronotype.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                Text("Early birds and night owls get slightly different light timing.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.l)
            .card()
            .task {
                if healthSuggestion == nil,
                   await model.deps.sleepProvider.availability() == .available {
                    let nights = await model.deps.sleepProvider.recentNights(limit: 14)
                    healthSuggestion = SleepPatternAnalyzer.suggestTypicalSleep(
                        nights: nights, zone: .current
                    )
                }
            }
        }
    }

    private var planeSleepStep: some View {
        OnboardingScreen(
            title: "Sleep on planes?",
            subtitle: "Be honest — the plan only works if it's built for the real you.",
            symbol: "airplane",
            primaryLabel: "Continue",
            primaryAction: { step = 3 }
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker("Can you sleep on planes?", selection: $planeSleep) {
                    ForEach(PlaneSleepAbility.allCases, id: \.self) { ability in
                        Text(ability.displayName).tag(ability)
                    }
                }
                .pickerStyle(.segmented)

                if planeSleep != .never {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Longest realistic stretch: \(Int(maxPlaneSleepHours)) hour\(Int(maxPlaneSleepHours) == 1 ? "" : "s")")
                            .font(.subheadline)
                        Slider(value: $maxPlaneSleepHours, in: 1...9, step: 1)
                            .accessibilityLabel("Maximum in-flight sleep in hours")
                    }
                    Toggle("Skip meal service to sleep more", isOn: $prioritizeSleepOverMeals)
                } else {
                    Label(
                        "Got it — we'll plan quiet rest instead of pretending you'll sleep, and protect your first night after landing.",
                        systemImage: "checkmark.seal"
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Space.l)
            .card()
        }
    }

    private var planStyle: some View {
        OnboardingScreen(
            title: "When should trips start shifting you?",
            subtitle: "Your default head start before any departure. You can set it exactly, per trip, when you add one.",
            symbol: "calendar.badge.clock",
            primaryLabel: "Continue",
            primaryAction: { step = 4 }
        ) {
            VStack(spacing: Theme.Space.m) {
                WillingnessOption(
                    selected: $willingness,
                    value: .none,
                    title: "None before I fly",
                    detail: "Start adjusting only once travel begins."
                )
                WillingnessOption(
                    selected: $willingness,
                    value: .small,
                    title: "A little (1 day)",
                    detail: "One slightly shifted evening before departure."
                )
                WillingnessOption(
                    selected: $willingness,
                    value: .moderate,
                    title: "Some (2 days)",
                    detail: "The default — a meaningful head start without upending your week."
                )
                WillingnessOption(
                    selected: $willingness,
                    value: .maximum,
                    title: "As much as helps (3 days)",
                    detail: "For a big meeting, a race, or a wedding you must be sharp for."
                )
            }
        }
    }

    private var preferences: some View {
        OnboardingScreen(
            title: "A few last things",
            subtitle: "Everything here can change later in Settings.",
            symbol: "slider.horizontal.3",
            primaryLabel: "Continue",
            primaryAction: { step = 5 }
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Toggle(isOn: $includeCaffeine) {
                    Label("Include caffeine timing", systemImage: "cup.and.saucer.fill")
                }
                Toggle(isOn: $includeMelatonin) {
                    Label("Optional melatonin reminders", systemImage: "pills.fill")
                }
                if includeMelatonin {
                    Text("Reminders only — never presented as required, never a dosage. Ask a clinician or pharmacist if you're unsure whether melatonin is right for you.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Toggle(isOn: $wantsNotifications) {
                    Label("Remind me at the right moments", systemImage: "bell.badge.fill")
                }
                Text("We'll ask the system for permission only after your first plan exists.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.l)
            .card()
        }
    }

    private var finish: some View {
        OnboardingScreen(
            primaryLabel: "Add my trip",
            primaryAction: { Task { await complete() } }
        ) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: step)
                .accessibilityHidden(true)
            Text("You're set")
                .font(.largeTitle.weight(.bold))
            Text("Add your first trip and the plan appears instantly — no account, no payment, nothing to unlock.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: Completion

    private func time(from clock: LocalClockTime) -> Date {
        Calendar.current.date(
            bySettingHour: clock.hour, minute: clock.minute, second: 0, of: Date()
        ) ?? Date()
    }

    private func clock(from date: Date) -> LocalClockTime {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return LocalClockTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }

    private func complete() async {
        let profile = UserProfile(
            homeZone: ZoneID(TimeZone.current.identifier),
            typicalBedtime: clock(from: bedtime),
            typicalWakeTime: clock(from: wakeTime),
            chronotype: chronotype,
            planeSleepAbility: planeSleep,
            maxInFlightSleep: planeSleep == .never ? 0 : maxPlaneSleepHours * 3600,
            prioritizesSleepOverMeals: prioritizeSleepOverMeals,
            caffeine: includeCaffeine ? .include : .exclude,
            melatonin: includeMelatonin ? .includeOptionalReminders : .exclude,
            preTripAdjustment: willingness,
            notifications: NotificationPreferences(enabled: wantsNotifications)
        )
        await model.completeOnboarding(profile: profile)
    }
}

// MARK: - Building blocks

private struct OnboardingScreen<Content: View>: View {
    var title: String?
    var subtitle: String?
    var symbol: String?
    var primaryLabel: String
    var primaryAction: () -> Void
    var secondaryLabel: String?
    var secondaryAction: (() -> Void)?
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        symbol: String? = nil,
        primaryLabel: String,
        primaryAction: @escaping () -> Void,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: Theme.Space.l) {
                if let title {
                    VStack(spacing: Theme.Space.xs) {
                        if let symbol {
                            ZStack {
                                Circle().fill(Theme.accent.opacity(0.18))
                                Image(systemName: symbol)
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Theme.accentDeep)
                            }
                            .frame(width: 64, height: 64)
                            .padding(.bottom, Theme.Space.xs)
                            .accessibilityHidden(true)
                        }
                        Text(title)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, Theme.Space.xl)
                }
                content
                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(PrimaryButtonStyle())
                if let secondaryLabel, let secondaryAction {
                    Button(secondaryLabel, action: secondaryAction)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WillingnessOption: View {
    @Binding var selected: PreTripAdjustmentWillingness
    let value: PreTripAdjustmentWillingness
    let title: String
    let detail: String

    var body: some View {
        Button {
            selected = value
            Haptics.selection()
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: selected == value ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected == value ? Theme.accent : Theme.textSecondary)
                    .symbolEffect(.bounce, value: selected == value)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(Theme.Space.m)
            .card(emphasized: selected == value)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        selected == value ? Theme.accent.opacity(0.5) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .scaleEffect(selected == value ? 1.0 : 0.985)
            .animation(Theme.Anim.springQuick, value: selected == value)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == value ? [.isSelected] : [])
    }
}
