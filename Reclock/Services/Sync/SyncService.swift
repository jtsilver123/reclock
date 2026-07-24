import Foundation
import Observation
import ReclockKit

/// Whole-state backup: the local JSON store, mirrored to one server row per user.
///
/// Policy (v1, deliberately boring):
/// - Push: debounced after every save while signed in. Last writer wins.
/// - Restore: only onto an EMPTY device (fresh install / new phone) — a device with
///   trips keeps them and becomes the new source of truth on its next push.
@MainActor
@Observable
final class SyncService {
    @ObservationIgnored private let client = SupabaseAuthClient()
    @ObservationIgnored private let schemaVersion = 1
    @ObservationIgnored private var pushTask: Task<Void, Never>?

    /// Observable mirror of the persisted stamp, so "Back up now (last: …)" in
    /// Settings actually refreshes when a backup lands.
    private(set) var lastBackupAt: Date? {
        didSet { UserDefaults.standard.set(lastBackupAt, forKey: "reclock.sync.lastBackupAt") }
    }

    init() {
        lastBackupAt = UserDefaults.standard.object(forKey: "reclock.sync.lastBackupAt") as? Date
    }

    var lastBackupDescription: String? {
        guard let lastBackupAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastBackupAt, relativeTo: Date())
    }

    /// Debounced push — several rapid saves collapse into one upload.
    func schedulePush(state: AppState, auth: AuthManager) {
        // Local-only mode promises "no network, full stop" — including backup.
        guard !state.settings.localOnlyMode, auth.isSignedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak auth] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let auth else { return }
            await self.push(state: state, auth: auth)
        }
    }

    /// Immediate push (Settings "Back up now", right after sign-in). Returns whether
    /// the snapshot actually landed, so the UI can be honest about it.
    @discardableResult
    func push(state: AppState, auth: AuthManager) async -> Bool {
        // A debounced upload still in flight carries an older snapshot; if it
        // finished after this one, the server would end on stale data.
        pushTask?.cancel()
        guard !state.settings.localOnlyMode else { return false }
        guard let session = try? await auth.validSession() else { return false }
        guard let payload = Self.encode(state) else { return false }
        do {
            try await client.pushSnapshot(state: payload, schemaVersion: schemaVersion, session: session)
            lastBackupAt = Date()
            return true
        } catch {
            // Backup is best-effort; the next save retries. Local data is never at risk.
            return false
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
