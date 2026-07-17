import SwiftUI
import ReclockKit

/// The curtain-up moment right after a trip is added: the destination sky takes the
/// screen, the plane flies the route, the plan lands with a burst of brand confetti.
/// Pure theater (~2.5s) — tap anywhere to skip, quiet under Reduce Motion.
struct PlanRevealView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trip: Trip
    var onDone: () -> Void

    @State private var stage = 0          // 0 blank · 1 route in · 2 ready line · 3 confetti
    @State private var flight: CGFloat = 0
    @State private var finished = false

    var body: some View {
        ZStack {
            // Night-to-dawn: the brand sky, full bleed.
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.13, blue: 0.30),
                    Color(red: 0.16, green: 0.20, blue: 0.42),
                    Color(red: 0.55, green: 0.34, blue: 0.16),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .grain(0.35, cornerRadius: 0)

            VStack(spacing: Theme.Space.l) {
                Spacer()

                // The route, boarding-pass style, with the plane riding its arc.
                VStack(spacing: Theme.Space.m) {
                    HStack {
                        Text(trip.origin)
                            .font(Theme.display(36))
                        Spacer()
                        Text(trip.destination)
                            .font(Theme.display(36))
                    }
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    FlightArc(progress: flight)
                        .frame(height: 90)
                }
                .padding(.horizontal, Theme.Space.xl)
                .opacity(stage >= 1 ? 1 : 0)
                .scaleEffect(stage >= 1 ? 1 : 0.94)

                VStack(spacing: Theme.Space.xs) {
                    Text("Your plan is ready")
                        .font(Theme.display(27))
                        .foregroundStyle(Color.white)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 ? 0 : 12)

                Spacer()

                Text("Tap to continue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .opacity(stage >= 2 ? 1 : 0)
                    .padding(.bottom, Theme.Space.xl)
            }

            if stage >= 3 && !reduceMotion {
                ConfettiField()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your plan for \(trip.origin) to \(trip.destination) is ready. Tap to continue.")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        "Sleep, light, and caffeine — timed to \(trip.destination)."
    }

    private func run() async {
        // Let the add-trip sheet finish dismissing before the show starts.
        try? await Task.sleep(nanoseconds: 300_000_000)
        Haptics.soft()
        withAnimation(Theme.Anim.spring) { stage = 1 }

        if reduceMotion {
            flight = 1
            Haptics.success()
            withAnimation(.easeInOut(duration: 0.3)) { stage = 2 }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            finish()
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeInOut(duration: 1.05)) { flight = 1 }
        try? await Task.sleep(nanoseconds: 850_000_000)
        Haptics.success()
        withAnimation(Theme.Anim.spring) { stage = 2 }
        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation { stage = 3 }
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }
}

// MARK: - Flight arc

/// A dashed arc that draws itself while the plane rides it, nose along the tangent.
private struct FlightArc: View {
    var progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ArcPath()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    Color.white.opacity(0.55),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 7])
                )
            Image(systemName: "airplane")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(Double(progress) * 44 - 22))
                .position(point(at: progress, in: size))
                .shadow(color: Theme.accent.opacity(0.6), radius: 8)
        }
        .accessibilityHidden(true)
    }

    /// Quadratic Bézier: takeoff left, apex mid, landing right.
    private func point(at t: CGFloat, in size: CGSize) -> CGPoint {
        let p0 = CGPoint(x: 8, y: size.height - 12)
        let p1 = CGPoint(x: size.width / 2, y: -size.height * 0.55)
        let p2 = CGPoint(x: size.width - 8, y: size.height - 12)
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    private struct ArcPath: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 8, y: rect.height - 12))
            path.addQuadCurve(
                to: CGPoint(x: rect.width - 8, y: rect.height - 12),
                control: CGPoint(x: rect.width / 2, y: -rect.height * 0.55)
            )
            return path
        }
    }
}

// MARK: - Confetti

/// Brand confetti: marigold suns, sparks, and little moons drifting down —
/// sun shower, not party paper.
private struct ConfettiField: View {
    private struct Particle: Identifiable {
        let id: Int
        let x0: CGFloat
        let x1: CGFloat
        let delay: Double
        let duration: Double
        let size: CGFloat
        let symbol: String
        let color: Color
        let spin: Double
    }

    private let particles: [Particle]
    @State private var fall = false

    init() {
        let symbols = ["sun.max.fill", "sparkle", "star.fill", "moon.fill", "circle.fill"]
        let colors: [Color] = [
            Theme.accent,
            Color(red: 1.0, green: 0.85, blue: 0.55),
            Color(red: 0.62, green: 0.70, blue: 1.00),
            Color.white.opacity(0.9),
        ]
        particles = (0..<26).map { i in
            let x = CGFloat.random(in: 0.03...0.97)
            return Particle(
                id: i,
                x0: x,
                x1: min(1, max(0, x + CGFloat.random(in: -0.12...0.12))),
                delay: Double.random(in: 0...0.5),
                duration: Double.random(in: 1.5...2.4),
                size: CGFloat.random(in: 10...20),
                symbol: symbols[i % symbols.count],
                color: colors[i % colors.count],
                spin: Double.random(in: -260...260)
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Image(systemName: p.symbol)
                    .font(.system(size: p.size, weight: .bold))
                    .foregroundStyle(p.color)
                    .position(
                        x: geo.size.width * (fall ? p.x1 : p.x0),
                        y: fall ? geo.size.height + 40 : -36
                    )
                    .rotationEffect(.degrees(fall ? p.spin : 0))
                    .opacity(fall ? 1 : 0)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: fall)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { fall = true }
    }
}
