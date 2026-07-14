import SwiftUI
import ReclockKit

/// The trip as a planet: an orthographic globe with the live day/night terminator,
/// the route arcing between the two cities, and both local clocks ticking below.
/// Drag to spin. Pure Canvas + GlobeMath — no maps, no network, no assets.
struct TripGlobeView: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let origin: Airport
    let destination: Airport

    @State private var lonOffset: Double = 0
    @State private var lonOffsetAtDragStart: Double?

    private var originVec: GlobeMath.Vec3 {
        GlobeMath.unit(latDeg: origin.latitude ?? 0, lonDeg: origin.longitude ?? 0)
    }

    private var destVec: GlobeMath.Vec3 {
        GlobeMath.unit(latDeg: destination.latitude ?? 0, lonDeg: destination.longitude ?? 0)
    }

    var body: some View {
        NavigationStack {
            SwiftUI.TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                VStack(spacing: Theme.Space.m) {
                    Text("\(trip.origin) → \(trip.destination)")
                        .font(Theme.display(26))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, Theme.Space.s)

                    globe(now: now)
                        .aspectRatio(1, contentMode: .fit)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if lonOffsetAtDragStart == nil {
                                        lonOffsetAtDragStart = lonOffset
                                    }
                                    lonOffset = (lonOffsetAtDragStart ?? 0)
                                        - Double(value.translation.width) / 3.2
                                }
                                .onEnded { _ in lonOffsetAtDragStart = nil }
                        )
                        .accessibilityLabel(
                            "Globe showing the route from \(origin.city) to \(destination.city) with the current day and night sides of Earth"
                        )

                    HStack(spacing: Theme.Space.m) {
                        cityClock(code: trip.origin, city: origin.city,
                                  zone: origin.zone.resolved, now: now)
                        Image(systemName: "airplane")
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        cityClock(code: trip.destination, city: destination.city,
                                  zone: destination.zone.resolved, now: now)
                    }

                    Text("The bright side is daylight right now. Drag to spin.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(.bottom, Theme.Space.m)
                }
                .padding(.horizontal, Theme.Space.m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.07, blue: 0.16).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.white)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: Pieces

    private func cityClock(code: String, city: String, zone: TimeZone, now: Date) -> some View {
        VStack(spacing: 2) {
            Text(TimeFormat.time(now, zone: zone))
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.white)
                .contentTransition(.numericText())
            Text(code)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(city): \(TimeFormat.time(now, zone: zone))")
    }

    private func globe(now: Date) -> some View {
        Canvas { ctx, size in
            let radius = min(size.width, size.height) * 0.46
            let centerPt = CGPoint(x: size.width / 2, y: size.height / 2)

            // View center: the route midpoint, spun by the drag offset.
            let mid = GlobeMath.greatCircle(from: originVec, to: destVec, samples: 2)[1]
            let midLat = asin(max(-1, min(1, mid.z))) * 180 / .pi
            let midLon = atan2(mid.y, mid.x) * 180 / .pi
            let center = GlobeMath.unit(latDeg: midLat * 0.8, lonDeg: midLon + lonOffset)

            func screen(_ p: GlobeMath.Projected) -> CGPoint {
                CGPoint(x: centerPt.x + p.x * radius, y: centerPt.y - p.y * radius)
            }

            // Stars, deterministic.
            for i in 0..<42 {
                let a = Double((i * 2654435761) % 1000) / 1000 * 2 * .pi
                let r = radius * (1.12 + Double((i * 40503) % 500) / 500 * 0.55)
                let pt = CGPoint(x: centerPt.x + cos(a) * r, y: centerPt.y + sin(a) * r * 0.9)
                guard pt.x > 4, pt.x < size.width - 4, pt.y > 4, pt.y < size.height - 4 else { continue }
                let s = 0.6 + Double((i * 97) % 10) / 8.0
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pt.x, y: pt.y, width: s, height: s)),
                    with: .color(.white.opacity(0.5))
                )
            }

            // The lit sphere.
            let disk = Path(ellipseIn: CGRect(
                x: centerPt.x - radius, y: centerPt.y - radius,
                width: radius * 2, height: radius * 2
            ))
            ctx.fill(disk, with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.42, green: 0.58, blue: 0.86),
                    Color(red: 0.20, green: 0.32, blue: 0.62),
                ]),
                center: CGPoint(x: centerPt.x - radius * 0.25, y: centerPt.y - radius * 0.3),
                startRadius: 0, endRadius: radius * 1.9
            ))

            // Graticule.
            var grid = Path()
            for lonLine in stride(from: -180.0, to: 180.0, by: 30.0) {
                var started = false
                for lat in stride(from: -85.0, through: 85.0, by: 4.0) {
                    let p = GlobeMath.project(GlobeMath.unit(latDeg: lat, lonDeg: lonLine), lookingAt: center)
                    if p.visible {
                        let pt = screen(p)
                        if started { grid.addLine(to: pt) } else { grid.move(to: pt); started = true }
                    } else { started = false }
                }
            }
            for latLine in stride(from: -60.0, through: 60.0, by: 30.0) {
                var started = false
                for lon in stride(from: -180.0, through: 180.0, by: 4.0) {
                    let p = GlobeMath.project(GlobeMath.unit(latDeg: latLine, lonDeg: lon), lookingAt: center)
                    if p.visible {
                        let pt = screen(p)
                        if started { grid.addLine(to: pt) } else { grid.move(to: pt); started = true }
                    } else { started = false }
                }
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.13)), lineWidth: 0.7)

            // Night side: everything past the terminator, closed along the limb.
            let sunLatLon = GlobeMath.subsolarPoint(at: now)
            let sun = GlobeMath.unit(latDeg: sunLatLon.latDeg, lonDeg: sunLatLon.lonDeg)
            let facingSun = GlobeMath.Vec3.dot(center.normalized, sun)
            let termPoints = GlobeMath.terminator(sun: sun, samples: 180)
                .map { (vec: $0, proj: GlobeMath.project($0, lookingAt: center)) }

            let visibleRuns = contiguousVisibleRuns(termPoints.map(\.proj))
            if let run = visibleRuns.max(by: { $0.count < $1.count }), run.count > 4 {
                var night = Path()
                let pts = run.map { screen(termPoints[$0].proj) }
                night.move(to: pts[0])
                for pt in pts.dropFirst() { night.addLine(to: pt) }
                // Close along the limb through the anti-sun side.
                let a2 = limbAngle(pts.last!, center: centerPt)
                let a1 = limbAngle(pts[0], center: centerPt)
                let antiSunFlat = GlobeMath.project(sun * -1, lookingAt: center)
                let aNight = atan2(-(antiSunFlat.y), antiSunFlat.x)
                night.addArc(
                    center: centerPt, radius: radius,
                    startAngle: .radians(a2), endAngle: .radians(a1),
                    clockwise: !arcContains(from: a2, to: a1, angle: aNight, clockwise: false)
                )
                night.closeSubpath()
                // Clip a COPY: clipping the shared context would also clip the
                // route, city labels, and sun/moon drawn after this.
                var nightCtx = ctx
                nightCtx.clip(to: disk)
                nightCtx.fill(night, with: .color(Color(red: 0.03, green: 0.05, blue: 0.13).opacity(0.55)))
            } else if facingSun < 0 {
                ctx.fill(disk, with: .color(Color(red: 0.03, green: 0.05, blue: 0.13).opacity(0.55)))
            }

            // The route.
            let route = GlobeMath.greatCircle(from: originVec, to: destVec, samples: 72)
                .map { GlobeMath.project($0, lookingAt: center) }
            var routePath = Path()
            var started = false
            for p in route where p.visible {
                let pt = screen(p)
                if started { routePath.addLine(to: pt) } else { routePath.move(to: pt); started = true }
            }
            ctx.stroke(
                routePath,
                with: .color(Theme.accent),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6])
            )

            // City markers.
            for (vec, code) in [(originVec, trip.origin), (destVec, trip.destination)] {
                let p = GlobeMath.project(vec, lookingAt: center)
                guard p.visible else { continue }
                let pt = screen(p)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 4.5, y: pt.y - 4.5, width: 9, height: 9)),
                    with: .color(Theme.accent)
                )
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: pt.x - 7.5, y: pt.y - 7.5, width: 15, height: 15)),
                    with: .color(.white.opacity(0.85)), lineWidth: 1.2
                )
                ctx.draw(
                    Text(code).font(.system(size: 11, weight: .bold)).foregroundStyle(.white),
                    at: CGPoint(x: pt.x, y: pt.y - 16)
                )
            }

            // Sun and moon, riding their real positions.
            let sunProj = GlobeMath.project(sun, lookingAt: center)
            if sunProj.visible {
                ctx.draw(
                    Image(systemName: "sun.max.fill").resizable(),
                    in: CGRect(x: screen(sunProj).x - 9, y: screen(sunProj).y - 9, width: 18, height: 18)
                )
            }
            let moonProj = GlobeMath.project(sun * -1, lookingAt: center)
            if moonProj.visible {
                ctx.draw(
                    Image(systemName: "moon.fill").resizable(),
                    in: CGRect(x: screen(moonProj).x - 7, y: screen(moonProj).y - 7, width: 14, height: 14)
                )
            }
        }
        .grain(0.35, cornerRadius: 0)
    }

    /// Indices of the longest contiguous visible run(s) in a projected loop.
    private func contiguousVisibleRuns(_ points: [GlobeMath.Projected]) -> [[Int]] {
        var runs: [[Int]] = []
        var current: [Int] = []
        for (i, p) in points.enumerated() {
            if p.visible { current.append(i) } else {
                if !current.isEmpty { runs.append(current); current = [] }
            }
        }
        if !current.isEmpty {
            // The loop may wrap: merge tail into head run.
            if let first = runs.first, first.first == 0 {
                runs[0] = current + first
            } else {
                runs.append(current)
            }
        }
        return runs
    }

    private func limbAngle(_ pt: CGPoint, center: CGPoint) -> Double {
        atan2(Double(pt.y - center.y), Double(pt.x - center.x))
    }

    /// Whether sweeping from `from` to `to` (counterclockwise when clockwise=false,
    /// in screen coordinates) passes through `angle`.
    private func arcContains(from: Double, to: Double, angle: Double, clockwise: Bool) -> Bool {
        func norm(_ a: Double) -> Double {
            var a = a.truncatingRemainder(dividingBy: 2 * .pi)
            if a < 0 { a += 2 * .pi }
            return a
        }
        let span = norm(to - from)
        let offset = norm(angle - from)
        return clockwise ? offset >= span : offset <= span
    }
}
