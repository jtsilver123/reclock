import Foundation
import Testing
@testable import ReclockKit

/// The Apple Health → typical bed/wake derivation now ships as a real Settings
/// feature, so its median logic and refusals need pinning: bad suggestions are
/// worse than none, and bedtimes that straddle midnight must not average to noon.
@Suite("Sleep pattern analyzer")
struct SleepPatternAnalyzerTests {
    private let zone = TimeZone(identifier: "America/New_York")!

    /// A night that starts at `bedHour:bedMin` (24h, may be < 12 for after-midnight)
    /// on an arbitrary base day and ends at `wakeHour:wakeMin` the following morning.
    private func night(bedHour: Int, bedMin: Int, wakeHour: Int, wakeMin: Int, dayOffset: Int) -> ObservedSleepNight {
        let base = TestSupport.zoned(2026, 9, 10 + dayOffset, bedHour, bedMin, zone.identifier)
        // If bedtime is in the morning it belongs to the same calendar day as wake;
        // otherwise wake is the next morning.
        let wakeDay = bedHour >= 12 ? 11 + dayOffset : 10 + dayOffset
        let wake = TestSupport.zoned(2026, 9, wakeDay, wakeHour, wakeMin, zone.identifier)
        return ObservedSleepNight(start: base, end: wake)
    }

    @Test("Median bed and wake across enough nights")
    func medianAcrossNights() throws {
        let nights = [
            night(bedHour: 23, bedMin: 0, wakeHour: 7, wakeMin: 0, dayOffset: 0),
            night(bedHour: 23, bedMin: 30, wakeHour: 7, wakeMin: 15, dayOffset: 1),
            night(bedHour: 22, bedMin: 45, wakeHour: 6, wakeMin: 45, dayOffset: 2),
            night(bedHour: 23, bedMin: 15, wakeHour: 7, wakeMin: 30, dayOffset: 3),
            night(bedHour: 0, bedMin: 0, wakeHour: 8, wakeMin: 0, dayOffset: 4),
        ]
        let suggestion = try #require(SleepPatternAnalyzer.suggestTypicalSleep(nights: nights, zone: zone))
        #expect(suggestion.sampleCount == 5)
        // Bedtimes: 22:45, 23:00, 23:15, 23:30, 00:00 → median 23:15.
        #expect(suggestion.bedtime.hour == 23)
        #expect(suggestion.bedtime.minute == 15)
        // Wakes: 06:45, 07:00, 07:15, 07:30, 08:00 → median 07:15.
        #expect(suggestion.wakeTime.hour == 7)
        #expect(suggestion.wakeTime.minute == 15)
    }

    @Test("Fewer than three usable nights yields no suggestion")
    func tooFewNights() {
        let nights = [
            night(bedHour: 23, bedMin: 0, wakeHour: 7, wakeMin: 0, dayOffset: 0),
            night(bedHour: 23, bedMin: 30, wakeHour: 7, wakeMin: 0, dayOffset: 1),
        ]
        #expect(SleepPatternAnalyzer.suggestTypicalSleep(nights: nights, zone: zone) == nil)
    }

    @Test("Naps and impossibly long records are excluded from the median")
    func filtersOutliers() {
        // Three real nights plus a 20-minute nap and a 30-hour garbage record.
        var nights = [
            night(bedHour: 23, bedMin: 0, wakeHour: 7, wakeMin: 0, dayOffset: 0),
            night(bedHour: 23, bedMin: 0, wakeHour: 7, wakeMin: 0, dayOffset: 1),
            night(bedHour: 23, bedMin: 0, wakeHour: 7, wakeMin: 0, dayOffset: 2),
        ]
        let napStart = TestSupport.zoned(2026, 9, 14, 14, 0, zone.identifier)
        nights.append(ObservedSleepNight(start: napStart, end: napStart.addingTimeInterval(20 * 60)))
        let junkStart = TestSupport.zoned(2026, 9, 15, 20, 0, zone.identifier)
        nights.append(ObservedSleepNight(start: junkStart, end: junkStart.addingTimeInterval(30 * 3600)))

        let suggestion = SleepPatternAnalyzer.suggestTypicalSleep(nights: nights, zone: zone)
        #expect(suggestion?.sampleCount == 3)
        #expect(suggestion?.bedtime.hour == 23)
        #expect(suggestion?.wakeTime.hour == 7)
    }

    @Test("After-midnight bedtimes don't average toward noon")
    func midnightWraparound() throws {
        // All bedtimes just after midnight — a naive average would land near midday.
        let nights = (0..<4).map {
            night(bedHour: 0, bedMin: 30, wakeHour: 8, wakeMin: 0, dayOffset: $0)
        }
        let suggestion = try #require(SleepPatternAnalyzer.suggestTypicalSleep(nights: nights, zone: zone))
        #expect(suggestion.bedtime.hour == 0)
        #expect(suggestion.bedtime.minute == 30)
    }
}
