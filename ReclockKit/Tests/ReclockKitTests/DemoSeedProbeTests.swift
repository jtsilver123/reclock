import Foundation
import Testing
@testable import ReclockKit

/// The demo/fixture trips must generate valid plans no matter what time of day the
/// app (or CI) runs — a per-zone day-anchoring bug once made flights 24h too long
/// for a few hours every night, silently emptying the seeded demo.
@Suite("Demo trips generate at any hour")
struct DemoTripsGenerationTests {
    @Test("Every fixture generates a plan at every hour of the day")
    func allFixturesAllHours() throws {
        let engine = PlanEngine()
        let base = Date().addingTimeInterval(-5 * 86_400)
        for hourShift in stride(from: 0, to: 24, by: 3) {
            let reference = base.addingTimeInterval(Double(hourShift) * 3600)
            for pair in DemoTrips.all(reference: reference) {
                do {
                    let plan = try engine.generatePlan(
                        trip: pair.trip, profile: pair.profile, currentState: nil
                    )
                    #expect(!plan.days.isEmpty)
                } catch {
                    Issue.record("\(pair.trip.name) at +\(hourShift)h threw: \(error)")
                }
            }
        }
    }
}
