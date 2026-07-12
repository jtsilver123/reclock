import Foundation
@testable import ReclockKit

/// Shared fixtures. Everything uses explicit UTC dates and IANA zones — never the machine's
/// locale or current time — so results are identical on any CI machine in any zone.
enum TestSupport {
    /// 2026-09-15 12:00 UTC — a Tuesday; both US and EU are on DST.
    static let reference = utcDate(2026, 9, 15, 12, 0)

    static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return Calendar.gregorianUTC.date(from: comps)!
    }

    static func zoned(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ zoneID: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID)!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return cal.date(from: comps)!
    }

    static let engine = PlanEngine()
    static let validator = PlanValidator()

    static func generateValidPlan(
        trip: Trip,
        profile: UserProfile,
        state: TravelerState? = nil,
        sourceLocation: String = #function
    ) throws -> JetLagPlan {
        let plan = try engine.generatePlan(trip: trip, profile: profile, currentState: state)
        let result = validator.validate(plan: plan, trip: trip, profile: profile)
        if !result.isValid {
            let details = result.conflicts.map(\.description).joined(separator: "\n")
            throw ValidationFailure(details: "Plan for \(trip.name) failed validation (\(sourceLocation)):\n\(details)")
        }
        return plan
    }

    struct ValidationFailure: Error, CustomStringConvertible {
        var details: String
        var description: String { details }
    }

    /// Local clock hour (0–23) of an instant in a zone, for readable assertions.
    static func localHour(_ date: Date, _ zoneID: String) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID)!
        return cal.component(.hour, from: date)
    }

    static func localMinutes(_ date: Date, _ zoneID: String) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID)!
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
