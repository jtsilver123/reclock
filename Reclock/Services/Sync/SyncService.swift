import Foundation
import ReclockKit

/// Whole-state backup: the local JSON store, mirrored to one server row per user.
///
/// Policy (v1, deliberately boring):
/// - Push: debounced after every save while signed in. Last writer wins.
/// - Restore: only onto an EMPTY device (fresh install / new phone) — a device with
///   trips keeps them and becomes the new source of truth on its next push.
@MainActor
final class SyncService {
    private let client = SupabaseAuthClient()
    private let schemaVersion = 1
    private var pushTask: Task<Void, Never>?

    private(set) var lastBackupAt: Date? {
        get { UserDefaults.standard.object(forKey: "reclock.sync.lastBackupAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "reclock.sync.lastBackupAt") }
    }

    var lastBackupDescription: String? {
        guard let lastBackupAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastBackupAt, relativeTo: Date())
    }

    /// Debounced push — several rapid saves collapse into one upload.
    func schedulePush(state: AppState, auth: AuthManager) {
        guard auth.isSignedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak auth] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let auth else { return }
            await self.push(state: state, auth: auth)
        }
    }

    /// Immediate push (Settings "Back up now", right after sign-in).
    func push(state: AppState, auth: AuthManager) async {
        guard let session = try? await auth.validSession() else { return }
        guard let payload = Self.encode(state) else { return }
        do {
            try await client.pushSnapshot(state: payload, schemaVersion: schemaVersion, session: session)
            lastBackupAt = Date()
        } catch {
            // Backup is best-effort; the next save retries. Local data is never at risk.
        }
    }

    /// The server snapshot, decoded — nil when none exists or the token is stale.
    func fetchSnapshot(auth: AuthManager) async -> AppState? {
        guard let session = try? await auth.validSession() else { return nil }
        guard let (payload, _) = try? await client.pullSnapshot(session: session) else { return nil }
        return Self.decode(payload)
    }

    private static func encode(_ state: AppState) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(state)
    }

    private static func decode(_ data: Data) -> AppState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppState.self, from: data)
    }
}
