import SwiftUI
import ReclockKit

/// Plain-language explanations of every lever the plan uses. No jargon, no overselling.
struct WhyItWorksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ExplainerBlock(
                    icon: "sun.max.fill",
                    tint: Theme.tint(for: .seekLight),
                    title: "Why light matters most",
                    body: """
                    Your body clock doesn't listen to your watch — it listens to light. \
                    Bright light at the right time pulls your internal clock toward the new \
                    zone; the same light at the wrong time pushes it away. That's why Reclock \
                    sometimes asks you to chase the sun and sometimes to wear sunglasses at \
                    10 AM. The timing isn't arbitrary: it pivots around your body's \
                    temperature low point, which sits a couple of hours before your natural \
                    wake time.
                    """
                )
                ExplainerBlock(
                    icon: "sunglasses.fill",
                    tint: Theme.tint(for: .avoidLight),
                    title: "Why avoiding light can beat seeking it",
                    body: """
                    After an overnight flight east, your body's low point often lands \
                    mid-morning local time. Light before that point pushes your clock the \
                    wrong way — later, not earlier. Keeping light low for the first hour or \
                    two after landing, then getting outside, moves you days ahead of \
                    "just push through it."
                    """
                )
                ExplainerBlock(
                    icon: "bed.double.fill",
                    tint: Theme.tint(for: .sleep),
                    title: "Why sleep timing anchors everything",
                    body: """
                    Sleeping at the destination's night — even a shortened, imperfect \
                    version — sets the stage for every other signal. Reclock schedules \
                    realistic windows: it won't tell you to sleep through boarding, meal \
                    service, or a wedding, and it caps in-flight sleep at what's realistic \
                    for you — tune that in Settings › Default preferences.
                    """
                )
                ExplainerBlock(
                    icon: "cup.and.saucer.fill",
                    tint: Theme.tint(for: .caffeineOK),
                    title: "How caffeine is used",
                    body: """
                    Caffeine can't move your body clock — but it's excellent at masking \
                    sleepiness while your clock catches up. The plan gives you a daily \
                    window where coffee works for you, and a hard stop 8–10 hours before \
                    bedtime so it can't steal the deep sleep that does the real work.
                    """
                )
                ExplainerBlock(
                    icon: "pills.fill",
                    tint: Theme.tint(for: .melatoninOptional),
                    title: "Why melatonin is optional",
                    body: """
                    Melatonin is a timing signal, not a sleeping pill. Taken in the early \
                    evening it can support an eastward shift. But it affects people \
                    differently, product contents vary, and plenty of travelers adjust \
                    fine without it. Reclock's melatonin reminders are optional and easy to turn \
                    off in Settings › Default preferences — and it never suggests a dose. Ask a clinician or pharmacist if you're unsure, \
                    take medication, are pregnant, or have a health condition.
                    """
                )
                ExplainerBlock(
                    icon: "checkmark.seal.fill",
                    tint: .green,
                    title: "When the plan is inconvenient",
                    body: """
                    Life wins sometimes. Miss a light window, crash early, drink the \
                    espresso — tell Reclock and it rebuilds the rest of the plan from \
                    where you actually are. Partial adherence still helps: every correctly \
                    timed signal moves your clock; nothing is all-or-nothing.
                    """
                )
                ExplainerBlock(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: "A note on safety",
                    body: """
                    \(SafetyCopy.drowsinessWarning) Reclock offers general wellness \
                    guidance for travel, not medical care. If you have a sleep disorder, \
                    are pregnant, or manage a health condition, check with your clinician \
                    about travel and sleep.
                    """
                )
            }
            .padding(Theme.Space.m)
        }
        .background(Theme.background)
        .navigationTitle("Why this works")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExplainerBlock: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    init(icon: String, tint: Color, title: String, body text: String) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
