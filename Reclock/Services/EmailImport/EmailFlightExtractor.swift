import Foundation

/// Finds flight candidates in pasted confirmation-email text, entirely on-device.
/// Deliberately liberal: anything that looks like a flight designator becomes a
/// candidate, and the schedule lookup is the real validator — a candidate that
/// isn't a real flight on that date simply won't confirm.
enum EmailFlightExtractor {

    struct Candidate: Identifiable, Hashable {
        var id: String { "\(flightNumber)-\(date?.timeIntervalSince1970 ?? 0)" }
        var flightNumber: String
        /// Best nearby date in the text, if any; the UI lets the traveler adjust.
        var date: Date?
    }

    /// Tokens that match the AA-1234 shape but are never airlines in booking emails.
    private static let stopWords: Set<String> = [
        "NO", "OF", "TO", "AT", "ON", "IN", "US", "PM", "AM", "ID", "OR",
        "GB", "EU", "PO", "RE", "CC", "TV", "HD", "MY", "BY", "IS", "IT",
    ]

    static func extract(from text: String, now: Date = Date()) -> [Candidate] {
        let nsText = text as NSString

        // 1. Every date the system detector can see, with its position.
        var dates: [(location: Int, date: Date)] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if let date = match.date, date > now.addingTimeInterval(-86_400) {
                    dates.append((match.range.location, date))
                }
            }
        }

        // 2. Flight designators: a two-character airline code (AA, B6, 9W) plus
        //    1–4 digits, optional space. "Flight AA 1234", "DL0442", "UA 5".
        let pattern = "\\b([A-Z0-9]{2})\\s?(\\d{1,4})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var seen = Set<String>()
        var candidates: [Candidate] = []
        for match in matches {
            let airline = nsText.substring(with: match.range(at: 1))
            let number = nsText.substring(with: match.range(at: 2))
            let designator = "\(airline) \(number)"
            guard !stopWords.contains(airline) else { continue }
            // Years and times sneak through as "20 26" style artifacts; flights
            // are 1–4 digits and airlines aren't purely numeric.
            guard airline.rangeOfCharacter(from: .letters) != nil else { continue }
            guard !seen.contains(designator) else { continue }
            seen.insert(designator)

            // Pair with the nearest date mentioned in the text (by character
            // distance) — confirmation emails put the date next to the flight.
            let nearest = dates.min {
                abs($0.location - match.range.location) < abs($1.location - match.range.location)
            }?.date

            candidates.append(Candidate(flightNumber: designator, date: nearest))
            if candidates.count >= 6 { break }  // sanity cap; emails list a handful at most
        }
        return candidates
    }
}
