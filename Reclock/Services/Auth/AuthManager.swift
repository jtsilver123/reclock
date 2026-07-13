import Foundation
import AuthenticationServices
import CryptoKit
import Observation

/// Auth state for optional backup & sync. The app is fully functional signed out —
/// signing in only adds an encrypted server copy of the local state.
@MainActor
@Observable
final class AuthManager {
    enum State: Equatable {
        case signedOut
        case signedIn(AuthSession)
    }

    private(set) var state: State = .signedOut
    /// Set while a sign-in sheet is in flight so the UI can spin.
    var isWorking = false
    var lastError: String?

    private let client = SupabaseAuthClient()
    @ObservationIgnored private var currentNonce: String?

    init() {
        if let session = KeychainStore.loadSession() {
            state = .signedIn(session)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var email: String? {
        if case .signedIn(let session) = state { return session.email }
        return nil
    }

    // MARK: Sign in with Apple

    /// Configure the Apple request: email scope + a fresh hashed nonce (replay guard).
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Exchange Apple's identity token for a Supabase session. Returns true on success.
    func complete(_ result: Result<ASAuthorization, Error>) async -> Bool {
        lastError = nil
        switch result {
        case .failure(let error):
            // The user closing the sheet is not an error worth surfacing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                lastError = "Sign-in didn't go through. Try again in a moment."
            }
            return false
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                lastError = "Apple didn't return a usable credential."
                return false
            }
            isWorking = true
            defer { isWorking = false }
            do {
                let session = try await client.signInWithApple(idToken: idToken, nonce: nonce)
                KeychainStore.save(session)
                state = .signedIn(session)
                return true
            } catch {
                lastError = "Couldn't reach the backup service. Your plan is unaffected."
                return false
            }
        }
    }

    /// Google is offered only when a client ID ships in the build.
    var googleAvailable: Bool { GoogleAuthConfig.clientID != nil }

    /// Full Google PKCE dance → Supabase session. Returns true on success.
    func signInWithGoogle() async -> Bool {
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let coordinator = GoogleSignInCoordinator()
            let result = try await coordinator.signIn()
            let session = try await client.signInWithGoogle(
                idToken: result.idToken, nonce: result.rawNonce
            )
            KeychainStore.save(session)
            state = .signedIn(session)
            return true
        } catch GoogleSignInError.cancelled {
            return false
        } catch {
            lastError = "Google sign-in didn't go through. Try again in a moment."
            return false
        }
    }

    func signOut() async {
        if case .signedIn(let session) = state {
            await client.signOut(session)
        }
        KeychainStore.clear()
        state = .signedOut
    }

    /// Deletes the server-side account and backup. Local data stays on the device.
    func deleteAccount() async -> Bool {
        guard case .signedIn(let session) = state else { return true }
        isWorking = true
        defer { isWorking = false }
        do {
            let fresh = try await validSession() ?? session
            try await client.deleteAccount(fresh)
            KeychainStore.clear()
            state = .signedOut
            return true
        } catch {
            lastError = "Couldn't delete the account right now. Try again with a connection."
            return false
        }
    }

    /// A session with a live access token, refreshing (and re-persisting) if needed.
    /// Signs out locally if the refresh token itself has been revoked.
    func validSession() async throws -> AuthSession? {
        guard case .signedIn(let session) = state else { return nil }
        guard session.needsRefresh else { return session }
        do {
            let refreshed = try await client.refresh(session)
            KeychainStore.save(refreshed)
            state = .signedIn(refreshed)
            return refreshed
        } catch let error as SupabaseAuthError {
            if case .badResponse(let status, _) = error, status == 400 || status == 401 {
                KeychainStore.clear()
                state = .signedOut
                return nil
            }
            throw error
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }
}
