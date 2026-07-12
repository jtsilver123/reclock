import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Privacy-conscious product analytics. Everything is behind this protocol; the app works
/// fully with `NoOpAnalyticsClient` (the default unless the user opts in AND a key is set).
public protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
    func flush() async
}

/// The complete, closed set of events Reclock may record. Payloads are constrained to
/// non-identifying properties — no free text, no titles, no health data, no locations
/// beyond coarse route metadata.
public enum AnalyticsEvent: Sendable {
    case appOpened
    case onboardingStarted
    case onboardingCompleted
    case importMethodSelected(method: String)
    case calendarPermission(granted: Bool)
    case tripImported(source: String, segmentCount: Int, timezoneDelta: Int)
    case tripManuallyEntered(segmentCount: Int, timezoneDelta: Int)
    case planGenerated(strategy: String, direction: String, shiftHours: Int, intensity: String)
    case planModeSelected(intensity: String)
    case notificationPermission(granted: Bool)
    case actionCompleted(type: String, priority: String)
    case actionSkipped(type: String, priority: String)
    case planRecalculated(trigger: String)
    case flightDelayReported(delayMinutes: Int)
    case timelineViewed
    case postTripSurveyCompleted(severity: Int, usefulness: Int, adherence: String)
    case reviewPromptShown

    public var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .onboardingStarted: "onboarding_started"
        case .onboardingCompleted: "onboarding_completed"
        case .importMethodSelected: "import_method_selected"
        case .calendarPermission: "calendar_permission"
        case .tripImported: "trip_imported"
        case .tripManuallyEntered: "trip_manually_entered"
        case .planGenerated: "plan_generated"
        case .planModeSelected: "plan_mode_selected"
        case .notificationPermission: "notification_permission"
        case .actionCompleted: "action_completed"
        case .actionSkipped: "action_skipped"
        case .planRecalculated: "plan_recalculated"
        case .flightDelayReported: "flight_delay_reported"
        case .timelineViewed: "timeline_viewed"
        case .postTripSurveyCompleted: "post_trip_survey_completed"
        case .reviewPromptShown: "review_prompt_shown"
        }
    }

    public var properties: [String: String] {
        switch self {
        case .appOpened, .onboardingStarted, .onboardingCompleted, .timelineViewed, .reviewPromptShown:
            return [:]
        case .importMethodSelected(let method):
            return ["method": method]
        case .calendarPermission(let granted), .notificationPermission(let granted):
            return ["granted": granted ? "true" : "false"]
        case .tripImported(let source, let segments, let delta):
            return ["source": source, "segments": String(segments), "tz_delta": String(delta)]
        case .tripManuallyEntered(let segments, let delta):
            return ["segments": String(segments), "tz_delta": String(delta)]
        case .planGenerated(let strategy, let direction, let shift, let intensity):
            return ["strategy": strategy, "direction": direction, "shift_hours": String(shift), "intensity": intensity]
        case .planModeSelected(let intensity):
            return ["intensity": intensity]
        case .actionCompleted(let type, let priority), .actionSkipped(let type, let priority):
            return ["type": type, "priority": priority]
        case .planRecalculated(let trigger):
            return ["trigger": trigger]
        case .flightDelayReported(let minutes):
            return ["delay_minutes": String(minutes)]
        case .postTripSurveyCompleted(let severity, let usefulness, let adherence):
            return ["severity": String(severity), "usefulness": String(usefulness), "adherence": adherence]
        }
    }
}

public struct NoOpAnalyticsClient: AnalyticsClient {
    public init() {}
    public func track(_ event: AnalyticsEvent) {}
    public func flush() async {}
}

/// Minimal direct PostHog capture client — deliberately not the full SDK (no session
/// recording, no autocapture, no device fingerprinting). Sends only the closed event set
/// above with an app-generated random anonymous ID that the user can reset by toggling
/// analytics off and on.
public actor PostHogAnalyticsClient: AnalyticsClient {
    private let apiKey: String
    private let host: URL
    private let anonymousID: String
    private var queue: [[String: Any]] = []
    private let session: URLSession

    public init(apiKey: String, host: URL, anonymousID: String) {
        self.apiKey = apiKey
        self.host = host
        self.anonymousID = anonymousID
        self.session = URLSession(configuration: .ephemeral)
    }

    public nonisolated func track(_ event: AnalyticsEvent) {
        Task { await enqueue(event) }
    }

    private func enqueue(_ event: AnalyticsEvent) {
        var properties: [String: Any] = event.properties
        properties["$lib"] = "reclock-ios"
        queue.append([
            "event": event.name,
            "distinct_id": anonymousID,
            "properties": properties,
        ])
        if queue.count >= 10 {
            Task { await flush() }
        }
    }

    public func flush() async {
        guard !queue.isEmpty else { return }
        let batch = queue
        queue.removeAll()
        let payload: [String: Any] = [
            "api_key": apiKey,
            "batch": batch,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: host.appendingPathComponent("batch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // Fire and forget; analytics must never affect the product. Failed batches are
        // dropped, not retried — losing an event is better than building a retry queue
        // of behavioral data on disk.
        _ = try? await session.data(for: request)
    }
}
