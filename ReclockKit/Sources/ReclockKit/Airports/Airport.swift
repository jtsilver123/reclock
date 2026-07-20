import Foundation

public struct Airport: Codable, Hashable, Sendable, Identifiable {
    public var iata: String
    public var name: String
    public var city: String
    public var country: String
    public var zone: ZoneID
    /// Approximate coordinates (~±1 km). Used only for flight-duration estimation —
    /// never navigation. nil for user-entered custom airports.
    public var latitude: Double?
    public var longitude: Double?

    public var id: String { iata }

    public init(
        iata: String,
        name: String,
        city: String,
        country: String,
        zone: ZoneID,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.iata = iata
        self.name = name
        self.city = city
        self.country = country
        self.zone = zone
        self.latitude = latitude
        self.longitude = longitude
    }

    enum CodingKeys: String, CodingKey {
        case iata, name, city, country, zone
        case latitude = "lat"
        case longitude = "lon"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iata = try container.decode(String.self, forKey: .iata)
        name = try container.decode(String.self, forKey: .name)
        city = try container.decode(String.self, forKey: .city)
        country = try container.decode(String.self, forKey: .country)
        zone = ZoneID(try container.decode(String.self, forKey: .zone))
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(iata, forKey: .iata)
        try container.encode(name, forKey: .name)
        try container.encode(city, forKey: .city)
        try container.encode(country, forKey: .country)
        try container.encode(zone.identifier, forKey: .zone)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
    }
}

/// Bundled directory of major airports, used for manual entry autocomplete, calendar-event
/// parsing, and time-zone inference. Unknown codes fall back to asking the user for a zone.
public struct AirportDirectory: Sendable {
    public let airports: [Airport]
    private let byIATA: [String: Airport]

    public static let bundled: AirportDirectory = {
        guard
            let url = Bundle.module.url(forResource: "airports", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let airports = try? JSONDecoder().decode([Airport].self, from: data)
        else {
            return AirportDirectory(airports: [])
        }
        return AirportDirectory(airports: airports)
    }()

    public init(airports: [Airport]) {
        self.airports = airports
        // First entry wins on a duplicate IATA — bad data must degrade, never trap.
        self.byIATA = Dictionary(airports.map { ($0.iata, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func airport(iata: String) -> Airport? {
        byIATA[iata.uppercased()]
    }

    public func zone(forIATA iata: String) -> ZoneID? {
        airport(iata: iata)?.zone
    }

    public func isKnownIATA(_ code: String) -> Bool {
        byIATA[code.uppercased()] != nil
    }

    /// Prefix/substring search across code, city and airport name for autocomplete.
    public func search(_ query: String, limit: Int = 12) -> [Airport] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()
        var codeHits: [Airport] = []
        var cityPrefixHits: [Airport] = []
        var substringHits: [Airport] = []
        for airport in airports {
            if airport.iata.lowercased().hasPrefix(q) {
                codeHits.append(airport)
            } else if airport.city.lowercased().hasPrefix(q) {
                cityPrefixHits.append(airport)
            } else if airport.city.lowercased().contains(q) || airport.name.lowercased().contains(q) {
                substringHits.append(airport)
            }
        }
        return Array((codeHits + cityPrefixHits + substringHits).prefix(limit))
    }
}
