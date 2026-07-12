#if canImport(HealthKit)
import Foundation
import HealthKit
import ReclockKit

/// Optional, read-only sleep history used to pre-fill typical bed/wake times during
/// onboarding. Data never leaves the device; the app is fully functional without it.
///
/// NOTE: activating this on-device requires the HealthKit capability + entitlement in
/// Signing & Capabilities (see SETUP.md). Without the entitlement the availability check
/// reports `.unsupported` and the UI hides the option.
final class HealthKitSleepProvider: SleepDataProvider {
    private let healthStore = HKHealthStore()

    private var sleepType: HKCategoryType {
        HKCategoryType(.sleepAnalysis)
    }

    func availability() async -> SleepDataAvailability {
        guard HKHealthStore.isHealthDataAvailable() else { return .unsupported }
        switch healthStore.authorizationStatus(for: sleepType) {
        case .notDetermined: return .notDetermined
        case .sharingDenied:
            // Read authorization status is intentionally opaque in HealthKit; a query is
            // the only way to know. Treat as available and let the query return nothing.
            return .available
        case .sharingAuthorized: return .available
        @unknown default: return .unsupported
        }
    }

    func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            return true
        } catch {
            return false
        }
    }

    func recentNights(limit: Int) async -> [ObservedSleepNight] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let end = Date()
        let start = end.addingTimeInterval(-21 * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 500,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }

        // Merge asleep-stage samples into contiguous nights (gap > 90 min splits nights).
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples
            .filter { asleepValues.contains($0.value) }
            .sorted { $0.startDate < $1.startDate }

        var nights: [ObservedSleepNight] = []
        var currentStart: Date?
        var currentEnd: Date?
        for sample in asleep {
            if let end = currentEnd, sample.startDate.timeIntervalSince(end) > 90 * 60 {
                if let s = currentStart, let e = currentEnd {
                    nights.append(ObservedSleepNight(start: s, end: e))
                }
                currentStart = sample.startDate
                currentEnd = sample.endDate
            } else {
                currentStart = currentStart ?? sample.startDate
                currentEnd = max(currentEnd ?? sample.endDate, sample.endDate)
            }
        }
        if let s = currentStart, let e = currentEnd {
            nights.append(ObservedSleepNight(start: s, end: e))
        }
        return Array(nights.sorted { $0.start > $1.start }.prefix(limit))
    }
}
#endif
