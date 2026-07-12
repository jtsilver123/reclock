import Foundation
import Testing
@testable import ReclockKit

@Suite("Plan dump (debug aid)")
struct PlanDumpDebug {
    @Test("Dump Helsinki plan", .enabled(if: ProcessInfo.processInfo.environment["RECLOCK_DUMP"] == "1"))
    func dumpHelsinki() throws {
        let trip = DemoTrips.newYorkToHelsinki(reference: TestSupport.reference)
        let profile = DemoTrips.defaultProfile()
        let plan = try TestSupport.engine.generatePlan(trip: trip, profile: profile, currentState: nil)
        print("=== \(trip.name) — \(plan.strategySummary)")
        print("=== shift \(plan.requiredShiftHours)h \(plan.shiftDirection), \(plan.days.count) days, \(plan.actions.count) actions")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE HH:mm"
        for day in plan.days {
            print("\n— Day \(day.index): \(day.label) [\(day.zone.identifier)] shift=\(String(format: "%.1f", day.cumulativeShiftHours))h")
            for action in plan.actions(onDay: day.index) {
                let zone = action.displayZone.resolved
                formatter.timeZone = zone
                let start = formatter.string(from: action.window.start)
                let end = formatter.string(from: action.window.end)
                print("   [\(action.priority.rawValue)] \(action.type.rawValue) \(start)–\(end) \(zone.identifier.split(separator: "/").last ?? "") · \(action.title)")
            }
        }
        let tokyo = DemoTrips.losAngelesToTokyo(reference: TestSupport.reference)
        let tokyoPlan = try TestSupport.engine.generatePlan(trip: tokyo, profile: DemoTrips.defaultProfile(homeZone: "America/Los_Angeles"), currentState: nil)
        print("\n=== \(tokyo.name) — \(tokyoPlan.strategySummary)")
        for day in tokyoPlan.days.prefix(4) {
            print("\n— Day \(day.index): \(day.label) shift=\(String(format: "%.1f", day.cumulativeShiftHours))h")
            for action in tokyoPlan.actions(onDay: day.index) {
                let zone = action.displayZone.resolved
                formatter.timeZone = zone
                print("   [\(action.priority.rawValue)] \(action.type.rawValue) \(formatter.string(from: action.window.start))–\(formatter.string(from: action.window.end)) \(zone.identifier.split(separator: "/").last ?? "") · \(action.title)")
            }
        }
    }
}
