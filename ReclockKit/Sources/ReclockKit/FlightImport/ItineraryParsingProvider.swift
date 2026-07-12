import Foundation

/// Phase-two import path: the user forwards an airline confirmation email to a unique
/// address; a parsing provider turns it into structured segments.
///
/// This ships behind `FeatureFlags.emailForwardingEnabled` (off in v1). The AwardWallet
/// provider is a scaffold: it requires a commercial agreement and a server-side proxy so
/// API credentials never live in the app. See DECISIONS.md.
public protocol ItineraryParsingProvider: Sendable {
    var providerName: String { get }
    /// Parses raw forwarded-email content into flight segments.
    /// Implementations must not retain the raw content after parsing.
    func parseItinerary(emailContent: String) async throws -> [FlightSegment]
}

public enum ItineraryParsingError: Error, Sendable {
    case providerUnavailable
    case notConfigured
    case unparseable(String)
}

/// Deterministic mock used by tests, previews, and the dev menu.
public struct MockItineraryParsingProvider: ItineraryParsingProvider {
    public let providerName = "Mock"
    public var cannedSegments: [FlightSegment]

    public init(cannedSegments: [FlightSegment] = []) {
        self.cannedSegments = cannedSegments
    }

    public func parseItinerary(emailContent: String) async throws -> [FlightSegment] {
        guard !cannedSegments.isEmpty else {
            throw ItineraryParsingError.unparseable("Mock has no canned segments.")
        }
        return cannedSegments
    }
}

/// Scaffold for the AwardWallet email-parsing API.
///
/// Contract: the app POSTs forwarded content to *our* proxy (never AwardWallet directly);
/// the proxy holds the API credentials, calls AwardWallet, deletes raw content after
/// parsing, and returns normalized segments. Until a commercial agreement and proxy exist,
/// this provider reports `.notConfigured` and the UI falls back to manual entry.
public struct AwardWalletItineraryParsingProvider: ItineraryParsingProvider {
    public let providerName = "AwardWallet"
    private let proxyURL: URL?

    public init(proxyURL: URL?) {
        self.proxyURL = proxyURL
    }

    public func parseItinerary(emailContent: String) async throws -> [FlightSegment] {
        guard proxyURL != nil else {
            throw ItineraryParsingError.notConfigured
        }
        // Intentionally unimplemented until the commercial relationship and server proxy
        // exist. Guarded by FeatureFlags.emailForwardingEnabled == false.
        throw ItineraryParsingError.providerUnavailable
    }
}

/// Compile-time feature flags. Kept in the kit so both app and tests see the same values.
public enum FeatureFlags {
    /// Email forwarding import (AwardWallet). Off until authorized and proxied.
    public static let emailForwardingEnabled = false
    /// HealthKit-based sleep suggestions. The provider protocol ships either way; the
    /// HealthKit implementation activates only when this is true AND the user opts in.
    public static let healthKitEnabled = true
    /// Optional cloud sync. Off in v1 — the interface exists, no backend is required.
    public static let cloudSyncEnabled = false
}
