import Foundation

/// A single recommendation the traveler can act on.
public struct PlanAction: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var type: ActionType
    public var window: TimeWindow
    /// Zone the action should be displayed in (where the traveler will be at the time).
    public var displayZone: ZoneID
    public var priority: ActionPriority
    /// Raw impact score used to derive priority. Higher = more circadian benefit.
    public var impactScore: Int
    public var title: String
    /// One imperative sentence: what to do.
    public var instruction: String
    /// One or two sentences: why it helps, in plain language.
    public var explanation: String
    public var completion: CompletionState
    public var notificationEnabled: Bool
    /// A fallback when the primary action is impractical ("Can't get outside? Sit by a bright window.")
    public var alternative: String?
    /// Present when reality forced this action away from the circadian ideal.
    public var adjustmentNote: String?
    /// Which day of the plan this belongs to (see `JetLagPlan.days`).
    public var dayIndex: Int
    /// Trip phase used for timeline grouping.
    public var phase: TripPhase
    public var confidence: ActionConfidence
    /// Protocol rule that produced this action, for traceability (e.g. "v1/light-advance").
    public var ruleReference: String

    public init(
        id: UUID = UUID(),
        type: ActionType,
        window: TimeWindow,
        displayZone: ZoneID,
        priority: ActionPriority,
        impactScore: Int,
        title: String,
        instruction: String,
        explanation: String,
        completion: CompletionState = .pending,
        notificationEnabled: Bool = true,
        alternative: String? = nil,
        adjustmentNote: String? = nil,
        dayIndex: Int,
        phase: TripPhase,
        confidence: ActionConfidence = .solid,
        ruleReference: String
    ) {
        self.id = id
        self.type = type
        self.window = window
        self.displayZone = displayZone
        self.priority = priority
        self.impactScore = impactScore
        self.title = title
        self.instruction = instruction
        self.explanation = explanation
        self.completion = completion
        self.notificationEnabled = notificationEnabled
        self.alternative = alternative
        self.adjustmentNote = adjustmentNote
        self.dayIndex = dayIndex
        self.phase = phase
        self.confidence = confidence
        self.ruleReference = ruleReference
    }
}

public enum ActionType: String, Codable, CaseIterable, Sendable {
    case seekLight
    case avoidLight
    case sleep
    case nap
    case stayAwake
    case caffeineOK
    case caffeineCutoff
    case melatoninOptional
    case shiftMeals
    case hydrate
    case moveBody
    case windDown
    case switchToDestinationTime
    case checkIn
    case recalculate

    /// True for comfort/routine support actions that are never presented as circadian levers.
    public var isComfort: Bool {
        switch self {
        case .hydrate, .moveBody, .shiftMeals: true
        default: false
        }
    }

    public var symbolName: String {
        switch self {
        case .seekLight: "sun.max.fill"
        case .avoidLight: "sunglasses.fill"
        case .sleep: "bed.double.fill"
        case .nap: "powersleep"
        case .stayAwake: "eye.fill"
        case .caffeineOK: "cup.and.saucer.fill"
        case .caffeineCutoff: "cup.and.saucer"
        case .melatoninOptional: "pills.fill"
        case .shiftMeals: "fork.knife"
        case .hydrate: "drop.fill"
        case .moveBody: "figure.walk"
        case .windDown: "moon.stars.fill"
        case .switchToDestinationTime: "clock.arrow.2.circlepath"
        case .checkIn: "checkmark.circle.fill"
        case .recalculate: "arrow.triangle.2.circlepath"
        }
    }
}

public enum ActionPriority: String, Codable, CaseIterable, Sendable, Comparable {
    case mustDo
    case helpful
    case optional

    public var displayName: String {
        switch self {
        case .mustDo: "Must do"
        case .helpful: "Helpful"
        case .optional: "Optional"
        }
    }

    private var rank: Int {
        switch self {
        case .mustDo: 0
        case .helpful: 1
        case .optional: 2
        }
    }

    public static func < (lhs: ActionPriority, rhs: ActionPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum CompletionState: String, Codable, CaseIterable, Sendable {
    case pending
    case done
    case skipped
    case notPossible
    case sleptInstead
    case expired
}

public enum TripPhase: String, Codable, CaseIterable, Sendable {
    case beforeDeparture
    case atAirport
    case inFlight
    case afterArrival
    case recovery
    case returnTrip

    public var displayName: String {
        switch self {
        case .beforeDeparture: "Before departure"
        case .atAirport: "At the airport"
        case .inFlight: "In flight"
        case .afterArrival: "After arrival"
        case .recovery: "Recovery days"
        case .returnTrip: "Return trip"
        }
    }
}

public enum ActionConfidence: String, Codable, CaseIterable, Sendable {
    /// Well-established intervention with clear timing evidence.
    case solid
    /// Reasonable timing estimate; individual response varies.
    case estimate
    /// Optional extra; evidence or fit is individual.
    case individual

    public var displayName: String {
        switch self {
        case .solid: "Well-established"
        case .estimate: "Good estimate"
        case .individual: "Varies by person"
        }
    }
}
