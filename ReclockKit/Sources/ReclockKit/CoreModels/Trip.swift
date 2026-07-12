import Foundation

/// A journey: one or more flight segments plus everything needed to plan around them.
public struct Trip: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// IATA code or free-text city for display.
    public var origin: String
    public var destination: String
    public var homeZone: ZoneID
    public var destinationZone: ZoneID
    public var segments: [FlightSegment]
    public var commitments: [FixedCommitment]
    public var intensity: PlanIntensity
    /// How the plan should approach adaptation. `.automatic` lets the engine decide
    /// (including recommending home-time anchoring for very short trips).
    public var adaptationStrategy: AdaptationStrategy
    /// Per-trip override for how many days before departure the shift starts (0–4).
    /// `nil` = derive from profile willingness ∩ intensity. When set, the user's choice
    /// wins outright — intensity presets never cap an explicit decision.
    public var preTripDaysOverride: Int?
    /// Door-to-terminal transit time in minutes (home → airport, hotel → airport for the
    /// return). Drives the leave-by reminder and extends the pre-departure no-sleep block.
    /// `nil` = the configured default (60).
    public var airportTransferMinutes: Int?
    public var status: TripStatus
    public var importSource: ImportSource
    public var createdAt: Date
    public var lastRecalculatedAt: Date?
    public var protocolVersion: String

    public init(
        id: UUID = UUID(),
        name: String,
        origin: String,
        destination: String,
        homeZone: ZoneID,
        destinationZone: ZoneID,
        segments: [FlightSegment],
        commitments: [FixedCommitment] = [],
        intensity: PlanIntensity = .balanced,
        adaptationStrategy: AdaptationStrategy = .automatic,
        preTripDaysOverride: Int? = nil,
        airportTransferMinutes: Int? = nil,
        status: TripStatus = .upcoming,
        importSource: ImportSource = .manual,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        lastRecalculatedAt: Date? = nil,
        protocolVersion: String = ProtocolVersion.current.description
    ) {
        self.id = id
        self.name = name
        self.origin = origin
        self.destination = destination
        self.homeZone = homeZone
        self.destinationZone = destinationZone
        self.segments = segments.sorted { $0.departure < $1.departure }
        self.commitments = commitments
        self.intensity = intensity
        self.adaptationStrategy = adaptationStrategy
        self.preTripDaysOverride = preTripDaysOverride
        self.airportTransferMinutes = airportTransferMinutes
        self.status = status
        self.importSource = importSource
        self.createdAt = createdAt
        self.lastRecalculatedAt = lastRecalculatedAt
        self.protocolVersion = protocolVersion
    }

    /// Segments that fly away from home, before the longest stay.
    public var outboundSegments: [FlightSegment] {
        guard let split = returnSplitIndex else { return segments }
        return Array(segments[..<split])
    }

    /// Segments after the longest ground gap (the return journey), if any.
    public var returnSegments: [FlightSegment] {
        guard let split = returnSplitIndex else { return [] }
        return Array(segments[split...])
    }

    /// Index of the first return segment: the segment following the longest ground gap,
    /// provided that gap is at least 48h (shorter gaps are treated as layovers/stopovers).
    private var returnSplitIndex: Int? {
        guard segments.count >= 2 else { return nil }
        var bestGap: TimeInterval = 0
        var bestIndex: Int? = nil
        for i in 1..<segments.count {
            let gap = segments[i].departure.timeIntervalSince(segments[i - 1].arrival)
            if gap > bestGap {
                bestGap = gap
                bestIndex = i
            }
        }
        guard let index = bestIndex, bestGap >= .hours(48) else { return nil }
        return index
    }

    public var firstDeparture: Date? { segments.first?.departure }
    public var finalArrival: Date? { segments.last?.arrival }

    /// Arrival of the outbound journey (start of the stay).
    public var outboundArrival: Date? { outboundSegments.last?.arrival }

    /// Nights spent at the destination between outbound arrival and return departure.
    public var destinationNights: Int? {
        guard let arrive = outboundArrival else { return nil }
        guard let returnDep = returnSegments.first?.departure else { return nil }
        let seconds = returnDep.timeIntervalSince(arrive)
        return max(0, Int(seconds / 86_400))
    }
}

public enum TripStatus: String, Codable, CaseIterable, Sendable {
    case upcoming
    case active
    case completed
    case archived
}

public enum ImportSource: String, Codable, CaseIterable, Sendable {
    case manual
    case flightNumber
    case calendar
    case forwardedEmail
    case demo
}

public enum PlanIntensity: String, Codable, CaseIterable, Sendable {
    case easy
    case balanced
    case maximum

    public var displayName: String {
        switch self {
        case .easy: "Easy"
        case .balanced: "Balanced"
        case .maximum: "Maximum"
        }
    }

    public var summary: String {
        switch self {
        case .easy:
            "Minimal disruption before travel. Focus on the highest-impact arrival actions."
        case .balanced:
            "Meaningful adjustment without heavily disrupting normal life."
        case .maximum:
            "More aggressive preparation for an important goal after arrival."
        }
    }
}

public enum AdaptationStrategy: String, Codable, CaseIterable, Sendable {
    /// Engine decides — including recommending home-time anchoring for short trips.
    case automatic
    /// Fully shift to the destination clock.
    case fullyAdapt
    /// Stay anchored to home time (sensible for 1–2 night trips).
    case anchorToHome
}

/// One flight leg.
public struct FlightSegment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var airline: String?
    public var flightNumber: String?
    public var departureAirport: String
    public var arrivalAirport: String
    public var departure: Date
    public var arrival: Date
    public var departureZone: ZoneID
    public var arrivalZone: ZoneID
    public var departureTerminal: String?
    public var arrivalTerminal: String?
    /// Minutes before departure when boarding typically starts (default 45).
    public var boardingLeadMinutes: Int
    /// Meal services expected on this segment, as offsets from departure.
    public var mealServices: [MealService]
    public var status: SegmentStatus
    public var importSource: ImportSource
    public var externalIdentifier: String?
    public var lastUpdatedAt: Date?

    public init(
        id: UUID = UUID(),
        airline: String? = nil,
        flightNumber: String? = nil,
        departureAirport: String,
        arrivalAirport: String,
        departure: Date,
        arrival: Date,
        departureZone: ZoneID,
        arrivalZone: ZoneID,
        departureTerminal: String? = nil,
        arrivalTerminal: String? = nil,
        boardingLeadMinutes: Int = 45,
        mealServices: [MealService] = [],
        status: SegmentStatus = .scheduled,
        importSource: ImportSource = .manual,
        externalIdentifier: String? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.airline = airline
        self.flightNumber = flightNumber
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departure = departure
        self.arrival = arrival
        self.departureZone = departureZone
        self.arrivalZone = arrivalZone
        self.departureTerminal = departureTerminal
        self.arrivalTerminal = arrivalTerminal
        self.boardingLeadMinutes = boardingLeadMinutes
        self.mealServices = mealServices
        self.status = status
        self.importSource = importSource
        self.externalIdentifier = externalIdentifier
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var blockTime: TimeInterval { arrival.timeIntervalSince(departure) }
    public var isLongHaul: Bool { blockTime >= .hours(7) }

    public var window: TimeWindow { TimeWindow(start: departure, end: arrival) }

    /// Default meal windows for a segment with no explicit data: dinner/lunch service starting
    /// ~40 min after departure on any flight ≥ 2.5h, plus a pre-landing service on long-haul.
    public var estimatedMealWindows: [TimeWindow] {
        if !mealServices.isEmpty {
            return mealServices.map { service in
                TimeWindow(
                    start: departure.addingTimeInterval(service.startOffset),
                    end: departure.addingTimeInterval(service.startOffset + service.duration)
                )
            }
        }
        var windows: [TimeWindow] = []
        if blockTime >= .hours(2.5) {
            windows.append(TimeWindow(start: departure.adding(minutes: 40), end: departure.adding(minutes: 100)))
        }
        if isLongHaul {
            windows.append(TimeWindow(start: arrival.adding(minutes: -110), end: arrival.adding(minutes: -50)))
        }
        return windows
    }

    public var displayName: String {
        let flight = [airline, flightNumber].compactMap(\.self).joined(separator: " ")
        let route = "\(departureAirport) → \(arrivalAirport)"
        return flight.isEmpty ? route : "\(flight) · \(route)"
    }
}

public struct MealService: Codable, Hashable, Sendable {
    /// Offset from departure to the start of service.
    public var startOffset: TimeInterval
    public var duration: TimeInterval

    public init(startOffset: TimeInterval, duration: TimeInterval = .minutes(60)) {
        self.startOffset = startOffset
        self.duration = duration
    }
}

public enum SegmentStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case delayed
    case departed
    case landed
    case cancelled
}

/// A block of real life the plan must respect: work, childcare, a wedding, a presentation.
public struct FixedCommitment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var end: Date
    public var zone: ZoneID
    public var importance: CommitmentImportance
    /// The user must be alert (drives caffeine/nap suggestions before it).
    public var requiresAlertness: Bool
    /// Sleep cannot happen during this block (true for almost everything except a rest day).
    public var blocksSleep: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date,
        zone: ZoneID,
        importance: CommitmentImportance = .standard,
        requiresAlertness: Bool = false,
        blocksSleep: Bool = true
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.zone = zone
        self.importance = importance
        self.requiresAlertness = requiresAlertness
        self.blocksSleep = blocksSleep
    }

    public var window: TimeWindow { TimeWindow(start: start, end: end) }
}

public enum CommitmentImportance: String, Codable, CaseIterable, Sendable {
    case standard
    case critical
}
