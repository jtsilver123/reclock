import AuthenticationServices
import SwiftUI
import ReclockKit

/// First run, two screens, zero questions: what the app does, then an optional
/// sign-in framed as backup — and straight into adding a flight. The plan assumes
/// a typical sleeper (11 pm–7 am; optional melatonin reminders on, each step
/// saying how to turn them off). The Plan-tab primer announces the sleep
/// assumption, and the Adjust sheet is the real "step 2".
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var model

    @State private var step = 0
    @State private var finishing = false

    var body: some View {
        TabView(selection: $step) {
            welcome.tag(0)
            syncStep.tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: Theme.Anim.standard), value: step)
        .background(Theme.background)
        .onAppear {
            model.deps.analytics.track(.onboardingStarted)
        }
        .onChange(of: step) { _, newStep in
            // Already signed in (a kept keychain session on reinstall): the sync
            // step has nothing to offer, so finish the moment the user reaches it.
            // Checked here, not in the page's onAppear — page TabViews prefetch
            // neighbors, and prefetch must not end onboarding under the welcome.
            if newStep == 1 && model.auth.isSignedIn {
                Task { await finish() }
            }
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
                .font(Theme.display(36))
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

    /// The one account moment, framed as exactly what it is: sync, nothing more.
    /// Skipping is a first-class path; signing in on a reinstall restores old trips
    /// before the user even lands in the app.
    private var syncStep: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                Spacer(minLength: Theme.Space.xl)
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.18))
                    Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

                Text("Back up your plans")
                    .font(Theme.display(28))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)

                Text("Sign in and your trips quietly sync — a new phone picks up right where you left off. That's all sign-in does. Everything works without it.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SignInWithAppleButton(.signIn) { request in
                    model.auth.prepare(request)
                } onCompletion: { result in
                    Task {
                        if await model.auth.complete(result) {
                            Haptics.success()
                            await model.handleSignedIn()
                            await finish()
                        }
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .frame(maxWidth: 360)

                if let error = model.auth.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Skip and add my trip") {
                    Haptics.soft()
                    Task { await finish() }
                }
                .buttonStyle(SecondaryButtonStyle())

                Text("No emails from us · Delete anytime in Settings")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Completion

    /// Onboarding ends here either way — the next screen is the add-trip flow.
    /// A sign-in that restored a full backup already brings its own profile and
    /// flips `onboardingComplete`; never overwrite that with defaults.
    private func finish() async {
        guard !finishing else { return }
        finishing = true
        if !model.state.onboardingComplete {
            let profile = UserProfile(
                homeZone: ZoneID(TimeZone.current.identifier),
                melatonin: .includeOptionalReminders
            )
            await model.completeOnboarding(profile: profile)
        }
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
                            .font(Theme.display(26))
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
                Button(primaryLabel) {
                    Haptics.soft()
                    primaryAction()
                }
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
