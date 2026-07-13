import Foundation
import Security

/// Reclock's backend for optional backup & sync. These values are public by design —
/// the publishable key only ever grants what row-level security allows.
enum SupabaseConfig {
    static let url = URL(string: "https://txqysnyfrlizxatbimpb.supabase.co")!
    static let publishableKey = "sb_publishable_9p_e5W30ufD35gxW4lxULA_LbCMyLO_"
}

/// A signed-in Supabase session. Stored as one Codable blob in the Keychain.
struct AuthSession: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String?

    var needsRefresh: Bool { Date() > expiresAt.addingTimeInterval(-60) }
}

/// Minimal Keychain wrapper for the session blob. Device-only, not synced to iCloud —
/// the backup itself lives server-side, so the token has no business roaming.
enum KeychainStore {
    private static let service = "app.reclock.auth"
    private static let account = "session"

    static func loadSession() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum SupabaseAuthError: Error {
    case badResponse(status: Int, message: String)
    case invalidCredential
}

/// Hand-rolled thin client for the three Supabase endpoints Reclock uses:
/// auth token exchange/refresh, the snapshot table, and the delete-account function.
/// Deliberately no SDK — ~150 lines beats a dependency for three endpoints.
struct SupabaseAuthClient: Sendable {
    var urlSession: URLSession = .shared

    // MARK: Auth

    /// Exchanges a Sign in with Apple identity token for a Supabase session.
    /// `nonce` is the RAW nonce (Supabase hashes it to match the token's claim).
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        body["nonce"] = nonce
        return try await tokenRequest(query: "grant_type=id_token", body: body)
    }

    func refresh(_ session: AuthSession) async throws -> AuthSession {
        try await tokenRequest(
            query: "grant_type=refresh_token",
            body: ["refresh_token": session.refreshToken]
        )
    }

    func signOut(_ session: AuthSession) async {
        var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/logout"))
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        _ = try? await urlSession.data(for: request)
    }

    func deleteAccount(_ session: AuthSession) async throws {
        var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    private func tokenRequest(query: String, body: [String: Any]) async throws -> AuthSession {
        var request = URLRequest(url: URL(string: "\(SupabaseConfig.url)/auth/v1/token?\(query)")!)
        request.httpMethod = "POST"
        decorate(&request, bearer: nil)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)

        struct TokenResponse: Decodable {
            struct User: Decodable {
                var id: String
                var email: String?
            }
            var access_token: String
            var refresh_token: String
            var expires_in: Double
            var user: User
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: Date().addingTimeInterval(token.expires_in),
            userID: token.user.id,
            email: token.user.email
        )
    }

    // MARK: Snapshot sync

    func pushSnapshot(state payload: Data, schemaVersion: Int, session: AuthSession) async throws {
        var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("rest/v1/state_snapshots"))
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: Any] = [
            "user_id": session.userID,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
            "schema_version": schemaVersion,
            "payload": try JSONSerialization.jsonObject(with: payload),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    /// The user's snapshot, if any: (payload JSON data, server updated-at).
    func pullSnapshot(session: AuthSession) async throws -> (payload: Data, updatedAt: Date)? {
        var components = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("rest/v1/state_snapshots"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "select", value: "updated_at,payload"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        var request = URLRequest(url: components.url!)
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)

        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first,
              let updatedString = row["updated_at"] as? String,
              let payloadObject = row["payload"] else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAt = formatter.date(from: updatedString)
            ?? ISO8601DateFormatter().date(from: updatedString)
            ?? Date()
        let payload = try JSONSerialization.data(withJSONObject: payloadObject)
        return (payload, updatedAt)
    }

    // MARK: Plumbing

    private func decorate(_ request: inout URLRequest, bearer: String?) {
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func expectOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseAuthError.badResponse(status: http.statusCode, message: message)
        }
    }
}
