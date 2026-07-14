import Foundation

/// Pure math for the trip globe: orthographic projection, great-circle routes, and
/// the live day/night terminator. Foundation-only so every formula is unit-tested
/// on Linux; the app layer just draws the points this hands back.
public enum GlobeMath {

    public struct Vec3: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(_ x: Double, _ y: Double, _ z: Double) {
            self.x = x; self.y = y; self.z = z
        }

        public static func dot(_ a: Vec3, _ b: Vec3) -> Double {
            a.x * b.x + a.y * b.y + a.z * b.z
        }

        public static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
            Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        }

        public var length: Double { (x * x + y * y + z * z).squareRoot() }

        public var normalized: Vec3 {
            let l = length
            guard l > 1e-12 else { return Vec3(0, 0, 1) }
            return Vec3(x / l, y / l, z / l)
        }

        public static func * (v: Vec3, s: Double) -> Vec3 { Vec3(v.x * s, v.y * s, v.z * s) }
        public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    }

    /// Unit sphere position for a latitude/longitude in degrees.
    /// x → (lat 0, lon 0), z → north pole.
    public static func unit(latDeg: Double, lonDeg: Double) -> Vec3 {
        let lat = latDeg * .pi / 180
        let lon = lonDeg * .pi / 180
        return Vec3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }

    /// A projected point: screen offsets in unit-sphere scale (multiply by radius),
    /// +x right, +y up. `visible` is true on the viewer-facing hemisphere.
    public struct Projected: Sendable {
        public var x: Double
        public var y: Double
        public var visible: Bool
    }

    /// Orthographic projection looking straight at `center` with north up (tilted
    /// only when the center approaches a pole).
    public static func project(_ p: Vec3, lookingAt center: Vec3) -> Projected {
        let forward = center.normalized
        let worldUp = Vec3(0, 0, 1)
        var right = Vec3.cross(worldUp, forward)
        if right.length < 1e-6 {  // looking at a pole; pick an arbitrary right
            right = Vec3(0, 1, 0)
        }
        right = right.normalized
        let up = Vec3.cross(forward, right).normalized
        return Projected(
            x: Vec3.dot(p, right),
            y: Vec3.dot(p, up),
            visible: Vec3.dot(p, forward) > 0
        )
    }

    /// Great-circle path from a to b (inclusive), slerped in `samples` steps.
    public static func greatCircle(from a: Vec3, to b: Vec3, samples: Int = 64) -> [Vec3] {
        let a = a.normalized
        let b = b.normalized
        let cosO = max(-1, min(1, Vec3.dot(a, b)))
        let omega = acos(cosO)
        guard omega > 1e-9 else { return [a, b] }
        let sinO = sin(omega)
        return (0...max(1, samples)).map { i in
            let t = Double(i) / Double(max(1, samples))
            let s1 = sin((1 - t) * omega) / sinO
            let s2 = sin(t * omega) / sinO
            return (a * s1 + b * s2).normalized
        }
    }

    /// Subsolar point (where the sun is overhead) for an instant. Declination via
    /// the standard 23.44°·sin approximation; longitude from UTC solar time.
    /// Accurate to a degree or two — plenty for painting day and night.
    public static func subsolarPoint(at date: Date) -> (latDeg: Double, lonDeg: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 172)
        let decl = 23.44 * sin(2 * .pi * (284 + dayOfYear) / 365.0)
        let comps = cal.dateComponents([.hour, .minute, .second], from: date)
        let utcHours = Double(comps.hour ?? 12)
            + Double(comps.minute ?? 0) / 60
            + Double(comps.second ?? 0) / 3600
        var lon = (12.0 - utcHours) * 15.0
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }
        return (decl, lon)
    }

    /// The terminator: the great circle 90° from the sun, sampled as unit vectors.
    /// Points with dot(p, sun) < 0 are in night.
    public static func terminator(sun: Vec3, samples: Int = 90) -> [Vec3] {
        let s = sun.normalized
        var u = Vec3.cross(s, Vec3(0, 0, 1))
        if u.length < 1e-6 { u = Vec3(1, 0, 0) }
        u = u.normalized
        let v = Vec3.cross(s, u).normalized
        return (0..<max(3, samples)).map { i in
            let theta = 2 * .pi * Double(i) / Double(max(3, samples))
            return (u * cos(theta) + v * sin(theta)).normalized
        }
    }
}
