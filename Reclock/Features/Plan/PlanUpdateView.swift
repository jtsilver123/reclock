import SwiftUI
import ReclockKit

/// The moment right after a deliberate replan (a flight change, a manual recalculate):
/// the plan visibly re-computes — concentric rings sweeping around a hub — then settles
/// into a card that says, in plain words, exactly what moved. Unlike the first-trip
/// reveal this waits for the reader: there's something to understand, not just applaud.
struct PlanUpdateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let update: PlanUpdate
    var onDone: () -> Void

    @State private var stage = 0        // 0 recomputing · 1 settled · 2 card
    @State private var spin = false
    @State private var finished = false

    var body: some View {
        ZStack {
            // A cool indigo wash — kin to the reveal's dawn, but calmer: this is a
            // tune-up, not a launch.
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.26),
                    Color(red: 0.14, green: 0.17, blue: 0.36),
                    Color(red: 0.20, green: 0.24, blue: 0.44),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Space.l) {
                Spacer()

                hub
                    .frame(width: 132, height: 132)

                VStack(spacing: Theme.Space.xs) {
                    Text(stage >= 2 ? "Plan updated" : "Updating your plan")
                        .font(Theme.display(28))
                        .foregroundStyle(Color.white)
                        .contentTransition(.opacity)
                    Text(update.route)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                if stage >= 2 {
                    changeCard
                        .padding(.horizontal, Theme.Space.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()

                if stage >= 2 {
                    Button("See the plan") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, Theme.Space.xl)
                        .padding(.bottom, Theme.Space.l)
                        .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if stage >= 2 { finish() } }
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Hub

    private var hub: some View {
        ZStack {
            // Sweeping rings while recomputing; they fade as the plan settles.
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .trim(from: 0, to: [0.62, 0.4, 0.75][i])
                    .stroke(
                        Color.white.opacity([0.5, 0.35, 0.25][i]),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6])
                    )
                    .frame(width: [132, 100, 70][i], height: [132, 100, 70][i])
                    .rotationEffect(.degrees(spin ? [360, -360, 300][i] : 0))
                    .opacity(stage >= 1 ? 0 : 1)
            }

            // The hub glyph: the recompute mark that becomes a check.
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(stage >= 1 ? 1 : 0.22))
                    .frame(width: 72, height: 72)
                    .shadow(color: Theme.accent.opacity(stage >= 1 ? 0.5 : 0), radius: 16)
                Image(systemName: stage >= 1 ? "checkmark" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(stage >= 1 ? Theme.ink : Color.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .scaleEffect(stage >= 1 ? 1 : 0.9)
        }
        .accessibilityHidden(true)
    }

    // MARK: Change card

    private var changeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("What changed")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)

            ForEach(Array(update.changes.enumerated()), id: \.offset) { index, change in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    Image(systemName: Self.symbol(for: change))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(change)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 ? 0 : 8)
                .animation(Theme.Anim.spring.delay(0.06 * Double(index)), value: stage)
            }

            Text("Your reminders were rescheduled to match.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var accessibilitySummary: String {
        "Plan updated for \(update.route). " + update.changes.joined(separator: ". ") + ". Tap to see the plan."
    }

    /// A glyph that matches what the sentence is about, so the list scans at a glance.
    private static func symbol(for change: String) -> String {
        let c = change.lowercased()
        if c.contains("home time") { return "house.fill" }
        if c.contains("sleep") { return "bed.double.fill" }
        if c.contains("light") { return "sun.max.fill" }
        if c.contains("caffeine") || c.contains("coffee") { return "cup.and.saucer.fill" }
        if c.contains("melatonin") { return "pills.fill" }
        if c.contains("evening") || c.contains("travel day") || c.contains("shifting") { return "calendar" }
        if c.contains("covers") || c.contains("days") { return "calendar.badge.clock" }
        if c.contains("new times") || c.contains("rebuilt") || c.contains("flight") { return "airplane" }
        if c.contains("up to date") || c.contains("nothing") { return "checkmark.seal.fill" }
        return "arrow.triangle.2.circlepath"
    }

    // MARK: Choreography

    private func run() async {
        // Let the delay sheet finish dismissing before the show takes the screen.
        try? await Task.sleep(nanoseconds: 300_000_000)

        if reduceMotion {
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.3)) { stage = 2 }
            return
        }

        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { spin = true }
        Haptics.soft()
        try? await Task.sleep(nanoseconds: 1_150_000_000)
        Haptics.success()
        withAnimation(Theme.Anim.spring) { stage = 1 }
        try? await Task.sleep(nanoseconds: 420_000_000)
        withAnimation(Theme.Anim.spring) { stage = 2 }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        Haptics.soft()
        onDone()
    }
}
