import Foundation
import Testing
@testable import ReclockKit

@Suite("Globe math")
struct GlobeMathTests {
    typealias V = GlobeMath.Vec3

    @Test("Lat/lon to unit vectors hits the landmarks")
    func landmarks() {
        let pole = GlobeMath.unit(latDeg: 90, lonDeg: 0)
        #expect(abs(pole.z - 1) < 1e-9)
        let greenwich = GlobeMath.unit(latDeg: 0, lonDeg: 0)
        #expect(abs(greenwich.x - 1) < 1e-9)
        let east90 = GlobeMath.unit(latDeg: 0, lonDeg: 90)
        #expect(abs(east90.y - 1) < 1e-9)
    }

    @Test("Projection: center faces viewer, antipode hides")
    func projectionVisibility() {
        let center = GlobeMath.unit(latDeg: 40, lonDeg: -74)
        let front = GlobeMath.project(center, lookingAt: center)
        #expect(front.visible)
        #expect(abs(front.x) < 1e-9 && abs(front.y) < 1e-9)
        let antipode = center * -1
        #expect(!GlobeMath.project(antipode, lookingAt: center).visible)
    }

    @Test("North stays up in projection")
    func northUp() {
        let center = GlobeMath.unit(latDeg: 0, lonDeg: 20)
        let north = GlobeMath.unit(latDeg: 60, lonDeg: 20)
        let p = GlobeMath.project(north, lookingAt: center)
        #expect(p.y > 0.5)
        #expect(abs(p.x) < 1e-6)
    }

    @Test("Great circle keeps endpoints and stays on the sphere")
    func greatCircle() {
        let jfk = GlobeMath.unit(latDeg: 40.64, lonDeg: -73.78)
        let hel = GlobeMath.unit(latDeg: 60.32, lonDeg: 24.96)
        let path = GlobeMath.greatCircle(from: jfk, to: hel, samples: 32)
        #expect(path.count == 33)
        #expect(V.dot(path.first!, jfk) > 0.9999)
        #expect(V.dot(path.last!, hel) > 0.9999)
        for p in path { #expect(abs(p.length - 1) < 1e-9) }
    }

    @Test("Subsolar point stays inside the tropics and tracks UTC noon")
    func subsolar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let noon = cal.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))!
        let s = GlobeMath.subsolarPoint(at: noon)
        #expect(abs(s.latDeg) <= 23.45)
        #expect(s.latDeg > 15)          // mid-July: well north
        #expect(abs(s.lonDeg) < 2)      // UTC noon: sun near the prime meridian
        let sixUTC = cal.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 6))!
        #expect(abs(GlobeMath.subsolarPoint(at: sixUTC).lonDeg - 90) < 2)
    }

    @Test("Terminator is 90 degrees from the sun everywhere")
    func terminator() {
        let sun = GlobeMath.unit(latDeg: 20, lonDeg: 40)
        for p in GlobeMath.terminator(sun: sun, samples: 60) {
            #expect(abs(V.dot(p, sun)) < 1e-9)
            #expect(abs(p.length - 1) < 1e-9)
        }
    }
}
