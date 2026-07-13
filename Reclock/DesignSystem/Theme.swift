import SwiftUI
import ReclockKit

/// Design tokens. One place for spacing, radius, color, typography and motion so every
/// screen reads as the same product.
enum Theme {

    // MARK: Spacing & shape

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 20
        static let chip: CGFloat = 10
        static let pill: CGFloat = 100
    }

    enum Anim {
        static let quick: Double = 0.18
        static let standard: Double = 0.3
        /// The app's signature movement: snappy but soft-landing.
        static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
        /// For button presses and small state flips.
        static let springQuick = Animation.spring(response: 0.24, dampingFraction: 0.72)
        /// For text/number changes.
        static let gentle = Animation.easeInOut(duration: 0.22)
    }

    // MARK: Colors (semantic, adaptive light/dark)

    /// Dynamic color helper: explicit light/dark pairs, no asset catalog required.
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// Marigold — the sun is the brand. Always pair with `ink` for text on top;
    /// white on this yellow fails contrast.
    static let accent = dynamic(
        light: UIColor(red: 0.99, green: 0.72, blue: 0.07, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.76, blue: 0.16, alpha: 1)
    )

    /// Near-black warm ink for text/glyphs sitting on the marigold accent.
    static let ink = dynamic(
        light: UIColor(red: 0.20, green: 0.16, blue: 0.06, alpha: 1),
        dark: UIColor(red: 0.16, green: 0.13, blue: 0.05, alpha: 1)
    )

    /// Burnt amber for small interactive TEXT on the cream background — pure marigold
    /// belongs to big shapes only; at caption sizes it fails contrast.
    static let accentDeep = dynamic(
        light: UIColor(red: 0.65, green: 0.42, blue: 0.02, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.78, blue: 0.28, alpha: 1)
    )

    /// Deep dusk blue — the night half of the identity (rings, sleep chrome).
    static let dusk = dynamic(
        light: UIColor(red: 0.22, green: 0.32, blue: 0.65, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.70, blue: 1.00, alpha: 1)
    )

    static let background = dynamic(
        light: UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
    )

    static let surface = dynamic(
        light: .white,
        dark: UIColor(red: 0.11, green: 0.12, blue: 0.16, alpha: 1)
    )

    static let surfaceSecondary = dynamic(
        light: UIColor(red: 0.93, green: 0.92, blue: 0.90, alpha: 1),
        dark: UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1)
    )

    static let textPrimary = dynamic(
        light: UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1),
        dark: UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)
    )

    static let textSecondary = dynamic(
        light: UIColor(red: 0.42, green: 0.43, blue: 0.48, alpha: 1),
        dark: UIColor(red: 0.62, green: 0.63, blue: 0.70, alpha: 1)
    )

    /// Per-action-type accents. Never the sole differentiator — every action also has a
    /// distinct SF Symbol and a text label (accessibility).
    static func tint(for type: ActionType) -> Color {
        switch type {
        case .seekLight:
            dynamic(light: UIColor(red: 0.95, green: 0.60, blue: 0.10, alpha: 1),
                    dark: UIColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1))
        case .avoidLight:
            dynamic(light: UIColor(red: 0.36, green: 0.31, blue: 0.60, alpha: 1),
                    dark: UIColor(red: 0.64, green: 0.58, blue: 0.95, alpha: 1))
        case .sleep, .windDown, .nap:
            dynamic(light: UIColor(red: 0.28, green: 0.36, blue: 0.72, alpha: 1),
                    dark: UIColor(red: 0.60, green: 0.68, blue: 1.00, alpha: 1))
        case .stayAwake:
            dynamic(light: UIColor(red: 0.80, green: 0.34, blue: 0.22, alpha: 1),
                    dark: UIColor(red: 1.00, green: 0.55, blue: 0.42, alpha: 1))
        case .caffeineOK, .caffeineCutoff:
            dynamic(light: UIColor(red: 0.52, green: 0.36, blue: 0.24, alpha: 1),
                    dark: UIColor(red: 0.80, green: 0.62, blue: 0.46, alpha: 1))
        case .melatoninOptional:
            dynamic(light: UIColor(red: 0.32, green: 0.52, blue: 0.44, alpha: 1),
                    dark: UIColor(red: 0.52, green: 0.78, blue: 0.68, alpha: 1))
        default:
            accent
        }
    }

    /// Immersive gradient identity per action — the "sky" of that moment of the body's
    /// day. Foreground on these is always white; every gradient is dark enough for it.
    static func skyColors(for type: ActionType) -> [Color] {
        switch type {
        case .seekLight:  // sunrise
            [dynamic(light: UIColor(red: 0.98, green: 0.58, blue: 0.12, alpha: 1),
                     dark: UIColor(red: 0.88, green: 0.48, blue: 0.10, alpha: 1)),
             dynamic(light: UIColor(red: 0.89, green: 0.35, blue: 0.10, alpha: 1),
                     dark: UIColor(red: 0.72, green: 0.28, blue: 0.10, alpha: 1))]
        case .avoidLight:  // shaded noon
            [dynamic(light: UIColor(red: 0.42, green: 0.35, blue: 0.72, alpha: 1),
                     dark: UIColor(red: 0.34, green: 0.28, blue: 0.60, alpha: 1)),
             dynamic(light: UIColor(red: 0.26, green: 0.22, blue: 0.52, alpha: 1),
                     dark: UIColor(red: 0.20, green: 0.17, blue: 0.42, alpha: 1))]
        case .sleep, .nap:  // deep night
            [dynamic(light: UIColor(red: 0.25, green: 0.31, blue: 0.66, alpha: 1),
                     dark: UIColor(red: 0.19, green: 0.24, blue: 0.54, alpha: 1)),
             dynamic(light: UIColor(red: 0.12, green: 0.15, blue: 0.38, alpha: 1),
                     dark: UIColor(red: 0.08, green: 0.10, blue: 0.28, alpha: 1))]
        case .windDown, .melatoninOptional:  // dusk
            [dynamic(light: UIColor(red: 0.48, green: 0.32, blue: 0.64, alpha: 1),
                     dark: UIColor(red: 0.38, green: 0.25, blue: 0.54, alpha: 1)),
             dynamic(light: UIColor(red: 0.25, green: 0.20, blue: 0.50, alpha: 1),
                     dark: UIColor(red: 0.18, green: 0.14, blue: 0.38, alpha: 1))]
        case .stayAwake:  // hold-the-line ember
            [dynamic(light: UIColor(red: 0.90, green: 0.42, blue: 0.22, alpha: 1),
                     dark: UIColor(red: 0.78, green: 0.34, blue: 0.18, alpha: 1)),
             dynamic(light: UIColor(red: 0.72, green: 0.22, blue: 0.22, alpha: 1),
                     dark: UIColor(red: 0.58, green: 0.17, blue: 0.18, alpha: 1))]
        case .caffeineOK, .caffeineCutoff:  // espresso
            [dynamic(light: UIColor(red: 0.58, green: 0.40, blue: 0.26, alpha: 1),
                     dark: UIColor(red: 0.48, green: 0.33, blue: 0.22, alpha: 1)),
             dynamic(light: UIColor(red: 0.38, green: 0.25, blue: 0.17, alpha: 1),
                     dark: UIColor(red: 0.30, green: 0.20, blue: 0.14, alpha: 1))]
        case .leaveForAirport:  // clear travel sky
            [dynamic(light: UIColor(red: 0.20, green: 0.48, blue: 0.85, alpha: 1),
                     dark: UIColor(red: 0.16, green: 0.38, blue: 0.70, alpha: 1)),
             dynamic(light: UIColor(red: 0.12, green: 0.28, blue: 0.62, alpha: 1),
                     dark: UIColor(red: 0.09, green: 0.20, blue: 0.48, alpha: 1))]
        default:  // brand dusk blue
            [dynamic(light: UIColor(red: 0.28, green: 0.38, blue: 0.72, alpha: 1),
                     dark: UIColor(red: 0.22, green: 0.30, blue: 0.60, alpha: 1)),
             dynamic(light: UIColor(red: 0.16, green: 0.22, blue: 0.50, alpha: 1),
                     dark: UIColor(red: 0.11, green: 0.15, blue: 0.38, alpha: 1))]
        }
    }

    static func sky(for type: ActionType) -> LinearGradient {
        LinearGradient(colors: skyColors(for: type), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The quiet state's calm night sky (no action to push).
    static var quietSky: LinearGradient {
        LinearGradient(
            colors: [
                dynamic(light: UIColor(red: 0.23, green: 0.30, blue: 0.52, alpha: 1),
                        dark: UIColor(red: 0.15, green: 0.20, blue: 0.38, alpha: 1)),
                dynamic(light: UIColor(red: 0.13, green: 0.17, blue: 0.34, alpha: 1),
                        dark: UIColor(red: 0.08, green: 0.11, blue: 0.24, alpha: 1)),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func priorityColor(_ priority: ActionPriority) -> Color {
        switch priority {
        case .mustDo:
            dynamic(light: UIColor(red: 0.75, green: 0.28, blue: 0.22, alpha: 1),
                    dark: UIColor(red: 1.00, green: 0.52, blue: 0.45, alpha: 1))
        case .helpful:
            dynamic(light: UIColor(red: 0.22, green: 0.42, blue: 0.65, alpha: 1),
                    dark: UIColor(red: 0.55, green: 0.72, blue: 1.00, alpha: 1))
        case .optional:
            dynamic(light: UIColor(red: 0.45, green: 0.46, blue: 0.50, alpha: 1),
                    dark: UIColor(red: 0.60, green: 0.61, blue: 0.66, alpha: 1))
        }
    }
}

// MARK: - Time formatting

enum TimeFormat {
    /// Localized short time (respects the user's 12/24-hour setting) in an explicit zone.
    static func time(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }

    static func weekdayTime(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        var day = Date.FormatStyle().weekday(.abbreviated)
        day.timeZone = zone
        return "\(date.formatted(day)) \(date.formatted(style))"
    }

    static func dayDate(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        style.timeZone = zone
        return date.formatted(style)
    }

    static func range(_ window: TimeWindow, zone: TimeZone) -> String {
        "\(time(window.start, zone: zone)) – \(time(window.end, zone: zone))"
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Short zone label: "Helsinki", "New York".
    static func zoneCity(_ zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map {
            $0.replacingOccurrences(of: "_", with: " ")
        } ?? zone.identifier
    }

    /// Reinterprets the wall-clock reading of `date` (in the device zone) as the same
    /// wall-clock time in `zone`. DatePickers hand back device-zone instants; tickets
    /// and destination events mean their *local* time.
    static func reinterpret(_ date: Date, into zone: TimeZone) -> Date {
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        let comps = deviceCal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = zone
        return targetCal.date(from: comps) ?? date
    }

    /// Inverse of `reinterpret`: shows an instant's wall-clock in `zone` as a device-zone
    /// Date suitable for seeding a DatePicker.
    static func pickerDate(for instant: Date, in zone: TimeZone) -> Date {
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = zone
        let comps = zoneCal.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        var deviceCal = Calendar(identifier: .gregorian)
        deviceCal.timeZone = .current
        return deviceCal.date(from: comps) ?? instant
    }
}

// MARK: - Haptics

enum Haptics {
    @MainActor static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// For picking among options (presets, chips, radio cards).
    @MainActor static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Whisper-weight confirmation for secondary actions (snooze, skip, estimate done).
    @MainActor static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }
}
