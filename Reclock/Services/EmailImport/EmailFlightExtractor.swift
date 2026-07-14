import Foundation

/// Finds flight candidates in pasted confirmation-email text, entirely on-device.
/// Deliberately liberal: anything that looks like a flight designator becomes a
/// candidate, and the schedule lookup is the real validator — a candidate that
/// isn't a real flight on that date simply won't confirm.
enum EmailFlightExtractor {

    struct Candidate: Identifiable, Hashable {
        var id: String { "\(flightNumber)-\(date?.timeIntervalSince1970 ?? 0)" }
        var flightNumber: String
        /// Best nearby date in the text, if any; the schedule lookup validates it.
        var date: Date?
    }

    struct Extraction {
        var candidates: [Candidate]
        /// True when the email held more designators than the cap — the UI says so
        /// instead of silently dropping legs.
        var truncated: Bool
    }

    /// Tokens that match the AA-1234 shape but are never airlines in booking emails.
    private static let stopWords: Set<String> = [
        "NO", "OF", "TO", "AT", "ON", "IN", "US", "PM", "AM", "ID", "OR",
        "GB", "EU", "PO", "RE", "CC", "TV", "HD", "MY", "BY", "IS", "IT",
    ]

    static func extract(from text: String, now: Date = Date()) -> [Candidate] {
        extraction(from: text, now: now).candidates
    }

    static func extraction(from text: String, now: Date = Date()) -> Extraction {
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
        var truncated = false
        for match in matches {
            let airline = nsText.substring(with: match.range(at: 1))
            let number = nsText.substring(with: match.range(at: 2))
            let designator = "\(airline) \(number)"
            guard !stopWords.contains(airline) else { continue }
            // Years and times sneak through as "20 26" style artifacts; flights
            // are 1–4 digits and airlines aren't purely numeric.
            guard airline.rangeOfCharacter(from: .letters) != nil else { continue }
            // Aircraft types masquerade as designators: "Airbus A320" → "A3 20",
            // "Boeing 777-300" nearby tokens, "A350-900" model suffixes.
            let prefixStart = max(0, match.range.location - 12)
            let prefix = nsText.substring(
                with: NSRange(location: prefixStart, length: match.range.location - prefixStart)
            ).lowercased()
            if prefix.hasSuffix("airbus ") || prefix.hasSuffix("boeing ") || prefix.hasSuffix("embraer ") {
                continue
            }
            let tailStart = match.range.location + match.range.length
            if tailStart < nsText.length,
               nsText.substring(with: NSRange(location: tailStart, length: 1)) == "-" {
                continue  // "A350-900": a model number, not a flight
            }
            guard !seen.contains(designator) else { continue }

            if candidates.count >= 6 {  // sanity cap; emails list a handful at most
                truncated = true
                break
            }
            seen.insert(designator)

            // Pair with a date mentioned in the text. Confirmation emails put each
            // leg's date at or after its designator ("AY 16 — Sat, Jul 18"), while
            // a summary block up top can sit closer by raw distance — prefer the
            // nearest FOLLOWING date, falling back to nearest overall.
            let following = dates
                .filter { $0.location >= match.range.location }
                .min { $0.location - match.range.location < $1.location - match.range.location }
            let nearest = following ?? dates.min {
                abs($0.location - match.range.location) < abs($1.location - match.range.location)
            }

            candidates.append(Candidate(flightNumber: designator, date: nearest?.date))
        }
        return Extraction(candidates: candidates, truncated: truncated)
    }
}
