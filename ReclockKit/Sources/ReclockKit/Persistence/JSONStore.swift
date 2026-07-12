import Foundation

/// The app's entire persisted state. Small enough (a handful of trips + plans) that a single
/// atomically-written JSON document is simpler and more robust than a database, trivially
/// exportable for the privacy "export my data" feature, and testable on any platform.
public struct AppState: Codable, Sendable, Equatable {
    public var profile: UserProfile?
    public var trips: [Trip]
    public var plans: [JetLagPlan]
    /// Keyed by trip UUID string. (String keys keep the JSON a readable object — Swift
    /// encodes non-String dictionary keys as flat arrays, which would wreck the export.)
    public var travelerStates: [String: TravelerState]
    public var surveys: [PostTripSurvey]
    public var onboardingComplete: Bool
    public var settings: AppSettings

    public init(
        profile: UserProfile? = nil,
        trips: [Trip] = [],
        plans: [JetLagPlan] = [],
        travelerStates: [String: TravelerState] = [:],
        surveys: [PostTripSurvey] = [],
        onboardingComplete: Bool = false,
        settings: AppSettings = AppSettings()
    ) {
        self.profile = profile
        self.trips = trips
        self.plans = plans
        self.travelerStates = travelerStates
        self.surveys = surveys
        self.onboardingComplete = onboardingComplete
        self.settings = settings
    }

    public func plan(forTrip tripID: UUID) -> JetLagPlan? {
        plans.first { $0.tripID == tripID }
    }

    public func travelerState(forTrip tripID: UUID) -> TravelerState? {
        travelerStates[tripID.uuidString]
    }

    public mutating func setTravelerState(_ state: TravelerState?, forTrip tripID: UUID) {
        travelerStates[tripID.uuidString] = state
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    /// Local-only mode: never contact any network service (analytics forced off).
    public var localOnlyMode: Bool
    public var analyticsEnabled: Bool
    /// Display timeline in destination time, home time, or both.
    public var timeDisplay: TimeDisplayMode

    public init(
        localOnlyMode: Bool = false,
        analyticsEnabled: Bool = false,
        timeDisplay: TimeDisplayMode = .destination
    ) {
        self.localOnlyMode = localOnlyMode
        self.analyticsEnabled = analyticsEnabled
        self.timeDisplay = timeDisplay
    }
}

public enum TimeDisplayMode: String, Codable, CaseIterable, Sendable {
    case destination
    case home
    case dual

    public var displayName: String {
        switch self {
        case .destination: "Destination time"
        case .home: "Home time"
        case .dual: "Both"
        }
    }
}

public struct PostTripSurvey: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var tripID: UUID
    public var submittedAt: Date
    /// 0–10: how bad was jet lag overall.
    public var severity: Int
    /// 0–10: how useful was the plan.
    public var usefulness: Int
    /// Rough fraction of the plan followed.
    public var adherence: SurveyAdherence
    /// Which recommendations felt unrealistic (action type raw values).
    public var unrealisticActionTypes: [String]
    public var daysUntilNormal: Int?
    public var wouldUseAgain: Bool?
    public var freeText: String?

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        submittedAt: Date,
        severity: Int,
        usefulness: Int,
        adherence: SurveyAdherence,
        unrealisticActionTypes: [String] = [],
        daysUntilNormal: Int? = nil,
        wouldUseAgain: Bool? = nil,
        freeText: String? = nil
    ) {
        self.id = id
        self.tripID = tripID
        self.submittedAt = submittedAt
        self.severity = severity
        self.usefulness = usefulness
        self.adherence = adherence
        self.unrealisticActionTypes = unrealisticActionTypes
        self.daysUntilNormal = daysUntilNormal
        self.wouldUseAgain = wouldUseAgain
        self.freeText = freeText
    }
}

public enum SurveyAdherence: String, Codable, CaseIterable, Sendable {
    case most
    case aboutHalf
    case some
    case barely

    public var displayName: String {
        switch self {
        case .most: "Most of it"
        case .aboutHalf: "About half"
        case .some: "Some of it"
        case .barely: "Barely any"
        }
    }
}

// MARK: - Store

public protocol AppStatePersisting: Sendable {
    func load() async throws -> AppState
    func save(_ state: AppState) async throws
    func wipe() async throws
    func exportData() async throws -> Data
}

/// Atomic, versioned JSON persistence with corruption recovery.
///
/// Envelope format: `{ "schemaVersion": N, "payload": { … } }`. Migrations transform older
/// payloads forward one version at a time. A corrupt file is moved aside (never deleted) and
/// a fresh state is returned, so one bad write can't brick the app.
public actor JSONStore: AppStatePersisting {
    public static let currentSchemaVersion = 1

    private struct Envelope: Codable {
        var schemaVersion: Int
        var payload: AppState
    }

    private let fileURL: URL
    private var cached: AppState?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default store location in Application Support.
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Reclock", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }

    public func load() async throws -> AppState {
        if let cached { return cached }
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            let fresh = AppState()
            cached = fresh
            return fresh
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try Self.decode(data: data)
            cached = state
            return state
        } catch {
            // Corruption recovery: move the bad file aside and start fresh.
            let quarantine = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt.json")
            try? fm.removeItem(at: quarantine)
            try? fm.moveItem(at: fileURL, to: quarantine)
            let fresh = AppState()
            cached = fresh
            return fresh
        }
    }

    static func decode(data: Data) throws -> AppState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Try the current envelope first, then run migrations for older versions.
        if let envelope = try? decoder.decode(Envelope.self, from: data),
           envelope.schemaVersion == currentSchemaVersion {
            return envelope.payload
        }
        // Version sniffing for migration.
        struct VersionProbe: Codable { var schemaVersion: Int }
        let probe = try decoder.decode(VersionProbe.self, from: data)
        var version = probe.schemaVersion
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        while version < currentSchemaVersion {
            object = try migrate(object: object, from: version)
            version += 1
        }
        guard version == currentSchemaVersion else {
            throw CocoaError(.coderInvalidValue)
        }
        let migrated = try JSONSerialization.data(withJSONObject: object)
        let envelope = try decoder.decode(Envelope.self, from: migrated)
        return envelope.payload
    }

    /// Forward-migration hook. Version 1 is the first shipped schema, so this is currently
    /// only exercised by tests; each future schema bump adds a case here.
    static func migrate(object: [String: Any], from version: Int) throws -> [String: Any] {
        switch version {
        case 0:
            // v0 → v1: v0 stored the payload at the top level without an envelope.
            var payload = object
            payload.removeValue(forKey: "schemaVersion")
            return ["schemaVersion": 1, "payload": payload]
        default:
            throw CocoaError(.coderInvalidValue)
        }
    }

    public func save(_ state: AppState) async throws {
        cached = state
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let envelope = Envelope(schemaVersion: Self.currentSchemaVersion, payload: state)
        let data = try encoder.encode(envelope)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `.atomic` writes to a temp file and renames, so a crash mid-write can't corrupt
        // the store. (Not FileManager.replaceItemAt: that requires an existing original on
        // Linux, which breaks the first save.)
        try data.write(to: fileURL, options: .atomic)
    }

    public func wipe() async throws {
        cached = AppState()
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
        let quarantine = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
        if fm.fileExists(atPath: quarantine.path) {
            try fm.removeItem(at: quarantine)
        }
    }

    /// The user's complete data as pretty-printed JSON (for the export feature).
    public func exportData() async throws -> Data {
        let state = try await load()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }
}
