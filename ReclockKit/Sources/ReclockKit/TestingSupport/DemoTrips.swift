import Foundation

/// Built-in demo trips and profiles for previews, the hidden dev menu, and tests.
/// Everything is derived from a caller-supplied reference instant so tests stay
/// deterministic (fixed reference) while the dev menu uses "now".
public enum DemoTrips {

    // MARK: - Date helpers

    /// A wall-clock instant `dayOffset` days after the reference day, at `hour:minute`
    /// in `zone`. The reference day is the calendar day containing `reference` in `zone`.
    /// "Day N at HH:MM in zone Z" — with day N anchored to ONE canonical calendar
    /// (UTC), not to Z's. Anchoring per-zone made departure/arrival pairs drift a
    /// whole day apart for the few hours each night when two zones disagree about
    /// the date — a time-of-day bomb that produced impossible 32-hour "flights"
    /// and made the itinerary validator (rightly) reject the demo trips.
    static func at(
        _ reference: Date,
        dayOffset: Int,
        _ hour: Int,
        _ minute: Int,
        _ zoneID: String
    ) -> Date {
        let utc = Calendar.gregorian(in: TimeZone(identifier: "UTC")!)
        let anchor = utc.date(byAdding: .day, value: dayOffset, to: utc.startOfDay(for: reference))!
        let comps = utc.dateComponents([.year, .month, .day], from: anchor)
        let zone = TimeZone(identifier: zoneID)!
        var cal = Calendar.gregorian(in: zone)
        cal.timeZone = zone
        return cal.date(from: DateComponents(
            year: comps.year, month: comps.month, day: comps.day, hour: hour, minute: minute
        ))!
    }

    // MARK: - Profiles

    public static func defaultProfile(homeZone: String = "America/New_York") -> UserProfile {
        UserProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            homeZone: ZoneID(homeZone),
            typicalBedtime: LocalClockTime(hour: 23, minute: 0),
            typicalWakeTime: LocalClockTime(hour: 7, minute: 0),
            chronotype: .neutral,
            planeSleepAbility: .sometimes,
            maxInFlightSleep: .hours(4),
            caffeine: .include,
            melatonin: .includeOptionalReminders,
            preTripAdjustment: .moderate
        )
    }

    public static func cantSleepOnPlanesProfile() -> UserProfile {
        var profile = defaultProfile()
        profile.planeSleepAbility = .never
        profile.maxInFlightSleep = 0
        return profile
    }

    public static func nightOwlProfile() -> UserProfile {
        var profile = defaultProfile()
        profile.chronotype = .late
        profile.typicalBedtime = LocalClockTime(hour: 0, minute: 30)
        profile.typicalWakeTime = LocalClockTime(hour: 8, minute: 30)
        return profile
    }

    public static func noStimulantsProfile() -> UserProfile {
        var profile = defaultProfile()
        profile.caffeine = .exclude
        profile.melatonin = .exclude
        return profile
    }

    // MARK: - Trips

    /// JFK → HEL overnight eastward (+7h), 7 nights, with return. The flagship demo.
    public static func newYorkToHelsinki(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "AY", flightNumber: "AY16",
            departureAirport: "JFK", arrivalAirport: "HEL",
            departure: at(reference, dayOffset: 4, 18, 30, "America/New_York"),
            arrival: at(reference, dayOffset: 5, 9, 50, "Europe/Helsinki"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/Helsinki"),
            importSource: .demo
        )
        let back = FlightSegment(
            airline: "AY", flightNumber: "AY15",
            departureAirport: "HEL", arrivalAirport: "JFK",
            departure: at(reference, dayOffset: 12, 13, 45, "Europe/Helsinki"),
            arrival: at(reference, dayOffset: 12, 15, 25, "America/New_York"),
            departureZone: ZoneID("Europe/Helsinki"),
            arrivalZone: ZoneID("America/New_York"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Helsinki",
            origin: "JFK", destination: "Helsinki",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/Helsinki"),
            segments: [outbound, back],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// LAX → HND: big westward-equivalent shift across the date line (−7h via +17).
    public static func losAngelesToTokyo(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "NH", flightNumber: "NH105",
            departureAirport: "LAX", arrivalAirport: "HND",
            departure: at(reference, dayOffset: 3, 11, 35, "America/Los_Angeles"),
            arrival: at(reference, dayOffset: 4, 14, 40, "Asia/Tokyo"),
            departureZone: ZoneID("America/Los_Angeles"),
            arrivalZone: ZoneID("Asia/Tokyo"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            name: "Tokyo",
            origin: "LAX", destination: "Tokyo",
            homeZone: ZoneID("America/Los_Angeles"),
            destinationZone: ZoneID("Asia/Tokyo"),
            segments: [outbound],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// LHR → JFK daytime westward (−5h).
    public static func londonToNewYork(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "BA", flightNumber: "BA175",
            departureAirport: "LHR", arrivalAirport: "JFK",
            departure: at(reference, dayOffset: 5, 10, 30, "Europe/London"),
            arrival: at(reference, dayOffset: 5, 13, 25, "America/New_York"),
            departureZone: ZoneID("Europe/London"),
            arrivalZone: ZoneID("America/New_York"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
            name: "New York",
            origin: "LHR", destination: "New York",
            homeZone: ZoneID("Europe/London"),
            destinationZone: ZoneID("America/New_York"),
            segments: [outbound],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// JFK → HNL: long westward day flight (−5/−6h, Hawaii has no DST).
    public static func newYorkToHonolulu(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "HA", flightNumber: "HA51",
            departureAirport: "JFK", arrivalAirport: "HNL",
            departure: at(reference, dayOffset: 6, 9, 15, "America/New_York"),
            arrival: at(reference, dayOffset: 6, 14, 35, "Pacific/Honolulu"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Pacific/Honolulu"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!,
            name: "Honolulu",
            origin: "JFK", destination: "Honolulu",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Pacific/Honolulu"),
            segments: [outbound],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// SYD → SFO: crosses the date line, lands "before" it departs (eastward +7 equivalent).
    public static func sydneyToSanFrancisco(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "UA", flightNumber: "UA870",
            departureAirport: "SYD", arrivalAirport: "SFO",
            departure: at(reference, dayOffset: 7, 10, 15, "Australia/Sydney"),
            arrival: at(reference, dayOffset: 7, 6, 45, "America/Los_Angeles"),
            departureZone: ZoneID("Australia/Sydney"),
            arrivalZone: ZoneID("America/Los_Angeles"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!,
            name: "San Francisco",
            origin: "SYD", destination: "San Francisco",
            homeZone: ZoneID("Australia/Sydney"),
            destinationZone: ZoneID("America/Los_Angeles"),
            segments: [outbound],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// JFK → FRA → SIN: multi-leg, +12h total — the antidromic edge case.
    public static func newYorkToSingaporeViaFrankfurt(reference: Date) -> Trip {
        let leg1 = FlightSegment(
            airline: "LH", flightNumber: "LH401",
            departureAirport: "JFK", arrivalAirport: "FRA",
            departure: at(reference, dayOffset: 5, 18, 0, "America/New_York"),
            arrival: at(reference, dayOffset: 6, 7, 35, "Europe/Berlin"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/Berlin"),
            importSource: .demo
        )
        let leg2 = FlightSegment(
            airline: "LH", flightNumber: "LH778",
            departureAirport: "FRA", arrivalAirport: "SIN",
            departure: at(reference, dayOffset: 6, 10, 35, "Europe/Berlin"),
            arrival: at(reference, dayOffset: 7, 5, 10, "Asia/Singapore"),
            departureZone: ZoneID("Europe/Berlin"),
            arrivalZone: ZoneID("Asia/Singapore"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A6")!,
            name: "Singapore",
            origin: "JFK", destination: "Singapore",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Asia/Singapore"),
            segments: [leg1, leg2],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// JFK → LHR for 2 nights: the stay-on-home-time candidate.
    public static func shortLondonBusinessTrip(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "B6", flightNumber: "B620",
            departureAirport: "JFK", arrivalAirport: "LHR",
            departure: at(reference, dayOffset: 10, 21, 0, "America/New_York"),
            arrival: at(reference, dayOffset: 11, 9, 10, "Europe/London"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/London"),
            importSource: .demo
        )
        let back = FlightSegment(
            airline: "B6", flightNumber: "B619",
            departureAirport: "LHR", arrivalAirport: "JFK",
            departure: at(reference, dayOffset: 13, 13, 30, "Europe/London"),
            arrival: at(reference, dayOffset: 13, 16, 25, "America/New_York"),
            departureZone: ZoneID("Europe/London"),
            arrivalZone: ZoneID("America/New_York"),
            importSource: .demo
        )
        var trip = Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A7")!,
            name: "London (48h)",
            origin: "JFK", destination: "London",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/London"),
            segments: [outbound, back],
            importSource: .demo,
            createdAt: reference
        )
        trip.commitments = [
            FixedCommitment(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
                title: "Client meetings",
                start: at(reference, dayOffset: 11, 13, 0, "Europe/London"),
                end: at(reference, dayOffset: 11, 17, 0, "Europe/London"),
                zone: ZoneID("Europe/London"),
                importance: .critical,
                requiresAlertness: true
            )
        ]
        return trip
    }

    /// LAX → LHR with a wedding on arrival evening — the "fixed commitment first night" case.
    public static func weddingTrip(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "VS", flightNumber: "VS8",
            departureAirport: "LAX", arrivalAirport: "LHR",
            departure: at(reference, dayOffset: 3, 17, 5, "America/Los_Angeles"),
            arrival: at(reference, dayOffset: 4, 11, 35, "Europe/London"),
            departureZone: ZoneID("America/Los_Angeles"),
            arrivalZone: ZoneID("Europe/London"),
            importSource: .demo
        )
        var trip = Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A8")!,
            name: "Wedding in London",
            origin: "LAX", destination: "London",
            homeZone: ZoneID("America/Los_Angeles"),
            destinationZone: ZoneID("Europe/London"),
            segments: [outbound],
            intensity: .maximum,
            importSource: .demo,
            createdAt: reference
        )
        trip.commitments = [
            FixedCommitment(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!,
                title: "Wedding",
                start: at(reference, dayOffset: 4, 17, 0, "Europe/London"),
                end: at(reference, dayOffset: 4, 23, 0, "Europe/London"),
                zone: ZoneID("Europe/London"),
                importance: .critical,
                requiresAlertness: true
            )
        ]
        return trip
    }

    /// JFK → CDG red-eye for a traveler who can't sleep on planes (pair with
    /// `cantSleepOnPlanesProfile()`).
    public static func parisRedEye(reference: Date) -> Trip {
        let outbound = FlightSegment(
            airline: "AF", flightNumber: "AF7",
            departureAirport: "JFK", arrivalAirport: "CDG",
            departure: at(reference, dayOffset: 2, 19, 30, "America/New_York"),
            arrival: at(reference, dayOffset: 3, 8, 45, "Europe/Paris"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/Paris"),
            importSource: .demo
        )
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A9")!,
            name: "Paris",
            origin: "JFK", destination: "Paris",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/Paris"),
            segments: [outbound],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// EWR → LHR overnight that has been delayed 2 hours (for testing replanning).
    public static func delayedOvernight(reference: Date) -> Trip {
        var segment = FlightSegment(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            airline: "UA", flightNumber: "UA16",
            departureAirport: "EWR", arrivalAirport: "LHR",
            departure: at(reference, dayOffset: 1, 22, 0, "America/New_York"),
            arrival: at(reference, dayOffset: 2, 9, 55, "Europe/London"),
            departureZone: ZoneID("America/New_York"),
            arrivalZone: ZoneID("Europe/London"),
            importSource: .demo
        )
        segment.status = .scheduled
        return Trip(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
            name: "London",
            origin: "EWR", destination: "London",
            homeZone: ZoneID("America/New_York"),
            destinationZone: ZoneID("Europe/London"),
            segments: [segment],
            importSource: .demo,
            createdAt: reference
        )
    }

    /// All demo trips paired with sensible profiles, for the dev menu and blanket tests.
    public static func all(reference: Date) -> [(trip: Trip, profile: UserProfile)] {
        [
            (newYorkToHelsinki(reference: reference), defaultProfile()),
            (losAngelesToTokyo(reference: reference), defaultProfile(homeZone: "America/Los_Angeles")),
            (londonToNewYork(reference: reference), defaultProfile(homeZone: "Europe/London")),
            (newYorkToHonolulu(reference: reference), defaultProfile()),
            (sydneyToSanFrancisco(reference: reference), defaultProfile(homeZone: "Australia/Sydney")),
            (newYorkToSingaporeViaFrankfurt(reference: reference), defaultProfile()),
            (shortLondonBusinessTrip(reference: reference), defaultProfile()),
            (weddingTrip(reference: reference), defaultProfile(homeZone: "America/Los_Angeles")),
            (parisRedEye(reference: reference), cantSleepOnPlanesProfile()),
            (delayedOvernight(reference: reference), defaultProfile()),
        ]
    }
}
