import Foundation

/// Re-stamps a trip's zones from the airport directory wherever they disagree — the
/// directory is the trusted source for every airport it knows. This heals trips that
/// were imported while an airport was missing from the directory: the calendar
/// importer falls back to the event's own time zone then (whatever city the calendar
/// happened to be set to), which labels a Tromsø departure "Copenhagen time". Flight
/// instants are absolute and never move; only the zone used to read them out does.
public enum ZoneHealer {

    /// The trip with directory-corrected zones, or nil when nothing needed fixing.
    /// Airports the directory does not know (custom entries) are left exactly as
    /// the user set them.
    public static func healed(_ trip: Trip, airports: AirportDirectory) -> Trip? {
        var changed = false
        var segments = trip.segments
        for index in segments.indices {
            if let zone = airports.zone(forIATA: segments[index].departureAirport),
               zone != segments[index].departureZone {
                segments[index].departureZone = zone
                changed = true
            }
            if let zone = airports.zone(forIATA: segments[index].arrivalAirport),
               zone != segments[index].arrivalZone {
                segments[index].arrivalZone = zone
                changed = true
            }
        }
        var healed = trip
        healed.segments = segments
        // The destination zone follows the stay airport whenever the directory knows it.
        if let stayCode = TripAssembler.stayAirport(of: segments),
           let stay = airports.airport(iata: stayCode),
           stay.zone != trip.destinationZone {
            healed.destinationZone = stay.zone
            changed = true
        }
        return changed ? healed : nil
    }
}
