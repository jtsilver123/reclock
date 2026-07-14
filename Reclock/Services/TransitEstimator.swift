import Foundation
import CoreLocation
import MapKit
import ReclockKit

/// One-shot "how long to the airport from here?" estimation.
///
/// Privacy contract (see PRIVACY.md):
/// - Location permission is requested only when the user taps the estimate button.
/// - The fix is used once, in memory, to ask Apple's Maps service for a driving ETA —
///   Reclock never stores or transmits coordinates itself.
/// - The only thing persisted is the resulting minutes value the user confirms.
enum TransitEstimateOutcome: Equatable {
    /// Total door-to-terminal minutes (drive + parking/walk buffer), plus the raw drive time.
    case minutes(total: Int, drive: Int)
    case permissionDenied
    case unavailable
}

protocol TransitEstimating: Sendable {
    @MainActor func estimateMinutes(toLatitude: Double, longitude: Double) async -> TransitEstimateOutcome
}

/// Fixed-value estimator for previews and UI tests.
struct MockTransitEstimator: TransitEstimating {
    var outcome: TransitEstimateOutcome = .minutes(total: 55, drive: 42)
    @MainActor func estimateMinutes(toLatitude: Double, longitude: Double) async -> TransitEstimateOutcome {
        outcome
    }
}

/// Real implementation: CoreLocation one-shot fix + MKDirections driving ETA.
struct MapKitTransitEstimator: TransitEstimating {
    /// Parking, shuttle, walk-to-terminal padding added on top of the drive.
    static let terminalBufferMinutes = 12

    @MainActor
    func estimateMinutes(toLatitude latitude: Double, longitude: Double) async -> TransitEstimateOutcome {
        let provider = OneShotLocationProvider()
        switch await provider.requestOneFix() {
        case .denied:
            return .permissionDenied
        case .failed:
            return .unavailable
        case .fix(let location):
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            request.destination = MKMapItem(
                placemark: MKPlacemark(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                )
            )
            request.transportType = .automobile
            do {
                let response = try await MKDirections(request: request).calculateETA()
                let driveMinutes = Int((response.expectedTravelTime / 60).rounded(.up))
                guard driveMinutes > 0, driveMinutes < 12 * 60 else { return .unavailable }
                let total = Self.roundUpToFive(driveMinutes + Self.terminalBufferMinutes)
                return .minutes(total: total, drive: driveMinutes)
            } catch {
                return .unavailable
            }
        }
    }

    static func roundUpToFive(_ minutes: Int) -> Int {
        let remainder = minutes % 5
        return remainder == 0 ? minutes : minutes + (5 - remainder)
    }
}

/// Wraps CLLocationManager's delegate dance into a single async call that resolves
/// exactly once: authorization (if needed) → one location fix → done. City-block
/// accuracy is plenty for a drive ETA.
@MainActor
private final class OneShotLocationProvider: NSObject, CLLocationManagerDelegate {
    enum Result {
        case fix(CLLocation)
        case denied
        case failed
    }

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var fixContinuation: CheckedContinuation<Result, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOneFix() async -> Result {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied, .restricted:
            return .denied
        default:
            return .failed
        }

        return await withCheckedContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
            // Backstop: never leave the button spinning forever.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.resolve(.failed)
            }
        }
    }

    private func resolve(_ result: Result) {
        fixContinuation?.resume(returning: result)
        fixContinuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // The delegate fires once immediately on assignment, while the permission
            // dialog is still on screen (status == .notDetermined). Resuming then
            // fails the estimate under the live prompt — wait for the real answer.
            guard status != .notDetermined else { return }
            self.authContinuation?.resume()
            self.authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.last {
                self.resolve(.fix(location))
            } else {
                self.resolve(.failed)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resolve(.failed)
        }
    }
}
