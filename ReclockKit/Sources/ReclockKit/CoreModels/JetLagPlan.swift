import Foundation

/// A complete generated plan for one trip.
public struct JetLagPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var tripID: UUID
    public var protocolVersion: String
    /// Monotonic revision, bumped on every recalculation. Used for stable notification IDs.
    public var revision: Int
    public var generatedAt: Date
    /// The strategy the engine actually chose (may differ from the trip's request under `.automatic`).
    public var strategy: AdaptationStrategy
    /// Signed hours the body clock must shift. Positive = advance (shift earlier / eastward).
    public var requiredShiftHours: Double
    /// Direction the engine chose to shift (may be "around the other way" for large eastward shifts).
    public var shiftDirection: ShiftDirection
    public var days: [PlanDay]
    public var actions: [PlanAction]
    /// Human-readable notes about how reality constrained the ideal plan.
    public var adjustments: [PlanAdjustment]
    /// A short sentence explaining the overall approach, shown at the top of the plan.
    public var strategySummary: String

    public init(
        id: UUID = UUID(),
        tripID: UUID,
        protocolVersion: String = ProtocolVersion.current.description,
        revision: Int = 1,
        generatedAt: Date,
        strategy: AdaptationStrategy,
        requiredShiftHours: Double,
        shiftDirection: ShiftDirection,
        days: [PlanDay],
        actions: [PlanAction],
        adjustments: [PlanAdjustment] = [],
        strategySummary: String
    ) {
        self.id = id
        self.tripID = tripID
        self.protocolVersion = protocolVersion
        self.revision = revision
        self.generatedAt = generatedAt
        self.strategy = strategy
        self.requiredShiftHours = requiredShiftHours
        self.shiftDirection = shiftDirection
        self.days = days
        self.actions = actions
        self.adjustments = adjustments
        self.strategySummary = strategySummary
    }

    public func actions(onDay index: Int) -> [PlanAction] {
        actions.filter { $0.dayIndex == index }.sorted { $0.window.start < $1.window.start }
    }

    /// Fraction of the required shift scheduled to be complete by the end of a given day.
    public func progress(atEndOfDay index: Int) -> Double {
        guard let day = days.first(where: { $0.index == index }) else { return 0 }
        guard abs(requiredShiftHours) > 0.01 else { return 1 }
        return min(1, abs(day.cumulativeShiftHours) / abs(requiredShiftHours))
    }
}

public enum ShiftDirection: String, Codable, Sendable {
    /// Body clock moves earlier (typical for eastward travel).
    case advance
    /// Body clock moves later (typical for westward travel).
    case delay
    /// No meaningful shift needed (same zone or anchored to home time).
    case none
}

/// One traveler-day of the plan, with the engine's phase estimate for that day.
public struct PlanDay: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var index: Int
    /// Start of this traveler-day (local midnight in `zone`).
    public var dayStart: Date
    /// The zone the traveler predominantly occupies this day.
    public var zone: ZoneID
    public var phase: TripPhase
    /// Estimated body-clock sleep onset for this day (UTC instant).
    public var estimatedBed: Date
    /// Estimated body-clock wake for this day (UTC instant).
    public var estimatedWake: Date
    /// Estimated core body temperature minimum — the pivot for light timing (UTC instant).
    public var estimatedCBTmin: Date
    /// Hours shifted from home baseline by the end of this day (signed; positive = advance).
    public var cumulativeShiftHours: Double
    /// Short label like "2 days before departure", "Landing day", "Day 2 in Tokyo".
    public var label: String

    public init(
        id: UUID = UUID(),
        index: Int,
        dayStart: Date,
        zone: ZoneID,
        phase: TripPhase,
        estimatedBed: Date,
        estimatedWake: Date,
        estimatedCBTmin: Date,
        cumulativeShiftHours: Double,
        label: String
    ) {
        self.id = id
        self.index = index
        self.dayStart = dayStart
        self.zone = zone
        self.phase = phase
        self.estimatedBed = estimatedBed
        self.estimatedWake = estimatedWake
        self.estimatedCBTmin = estimatedCBTmin
        self.cumulativeShiftHours = cumulativeShiftHours
        self.label = label
    }
}

/// A note explaining why the plan deviates from the circadian ideal.
public struct PlanAdjustment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var reason: String
    /// e.g. "Moved your light window to 15:00 because of your 09:00 meeting."
    public var message: String

    public init(id: UUID = UUID(), date: Date, reason: String, message: String) {
        self.id = id
        self.date = date
        self.reason = reason
        self.message = message
    }
}

// MARK: - Traveler state & adaptive replanning

/// What actually happened, as reported by the traveler. Drives recalculation.
public struct TravelerState: Codable, Hashable, Sendable {
    /// The instant the state was captured; the engine replans from here.
    public var asOf: Date
    /// Phase shift the engine believes has actually been achieved so far (signed hours).
    public var achievedShiftHours: Double
    /// Rough sleep debt in hours relative to the traveler's typical need.
    public var sleepDebtHours: Double
    /// Recent reported events, newest last.
    public var events: [TravelerEvent]

    public init(
        asOf: Date,
        achievedShiftHours: Double = 0,
        sleepDebtHours: Double = 0,
        events: [TravelerEvent] = []
    ) {
        self.asOf = asOf
        self.achievedShiftHours = achievedShiftHours
        self.sleepDebtHours = sleepDebtHours
        self.events = events
    }
}

public struct TravelerEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: TravelerEventKind

    public init(id: UUID = UUID(), date: Date, kind: TravelerEventKind) {
        self.id = id
        self.date = date
        self.kind = kind
    }
}

public enum TravelerEventKind: Codable, Hashable, Sendable {
    case completedAction(actionID: UUID)
    case couldNotDoAction(actionID: UUID)
    case sleptInstead(actionID: UUID)
    case stillAwake
    case sleptUntil(Date)
    case couldNotSleep
    case consumedCaffeine(Date)
    case flightDelayed(segmentID: UUID, newDeparture: Date, newArrival: Date)
    case missedConnection(segmentID: UUID)
}

// MARK: - Validation

public struct PlanValidationResult: Sendable {
    public var conflicts: [PlanConflict]
    public var isValid: Bool { conflicts.filter { $0.severity == .error }.isEmpty }

    public init(conflicts: [PlanConflict]) {
        self.conflicts = conflicts
    }
}

public struct PlanConflict: Sendable, CustomStringConvertible {
    public enum Severity: Sendable { case error, warning }
    public enum Kind: String, Sendable {
        case contradictoryOverlap
        case sleepInBlockedWindow
        case caffeineAfterCutoff
        case melatoninWhenOptedOut
        case invalidDate
        case actionAfterTripEnd
        case duplicateAction
        case missingArrivalGuidance
        case exceedsInFlightSleepMax
    }

    public var kind: Kind
    public var severity: Severity
    public var message: String
    public var actionIDs: [UUID]

    public init(kind: Kind, severity: Severity, message: String, actionIDs: [UUID] = []) {
        self.kind = kind
        self.severity = severity
        self.message = message
        self.actionIDs = actionIDs
    }

    public var description: String { "[\(severity)] \(kind.rawValue): \(message)" }
}

// MARK: - Protocol versioning

public struct ProtocolVersion: Sendable, CustomStringConvertible, Equatable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static let v1 = ProtocolVersion(major: 1, minor: 0)
    public static let current = ProtocolVersion.v1

    public var description: String { "\(major).\(minor)" }
}

// MARK: - Engine interface

public protocol JetLagPlanGenerating: Sendable {
    func generatePlan(
        trip: Trip,
        profile: UserProfile,
        currentState: TravelerState?
    ) throws -> JetLagPlan
}

public enum PlanEngineError: Error, Sendable, CustomStringConvertible {
    case noSegments
    case invalidItinerary(String)
    case unresolvableTimeZone(String)

    public var description: String {
        switch self {
        case .noSegments:
            "The trip has no flight segments."
        case .invalidItinerary(let detail):
            "The itinerary looks inconsistent: \(detail)"
        case .unresolvableTimeZone(let zone):
            "Unknown time zone: \(zone)"
        }
    }
}
