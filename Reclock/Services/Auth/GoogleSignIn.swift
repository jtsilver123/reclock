import Foundation
import AuthenticationServices
import CryptoKit
import SwiftUI

/// Google sign-in without the SDK: standard OAuth PKCE in ASWebAuthenticationSession,
/// then the resulting id_token goes through the same Supabase exchange as Apple's.
/// Config-gated — no client ID in the build means no Google button anywhere.
enum GoogleAuthConfig {
    /// iOS OAuth client ID from Info.plist (injected via build settings, like the
    /// AeroDataBox key). E.g. "1234-abc.apps.googleusercontent.com".
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ReclockGoogleClientID") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    /// Google's iOS redirect is the reversed client ID as a scheme.
    static func redirectScheme(clientID: String) -> String {
        clientID
            .split(separator: ".")
            .reversed()
            .joined(separator: ".")
    }
}

struct GoogleSignInResult {
    var idToken: String
    var rawNonce: String
}

enum GoogleSignInError: Error {
    case notConfigured
    case cancelled
    case failed
}

/// One-shot OAuth dance. Kept tiny: build the consent URL with PKCE + nonce, catch the
/// custom-scheme redirect (ASWebAuthenticationSession needs no Info.plist entry for it),
/// swap the code for tokens.
@MainActor
final class GoogleSignInCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {

    func signIn() async throws -> GoogleSignInResult {
        guard let clientID = GoogleAuthConfig.clientID else { throw GoogleSignInError.notConfigured }
        let scheme = GoogleAuthConfig.redirectScheme(clientID: clientID)
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomURLSafe(length: 64)
        let challenge = Self.base64URL(SHA256.hash(data: Data(verifier.utf8)))
        let nonce = Self.randomURLSafe(length: 32)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: nonce),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: scheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let authError = error as? ASWebAuthenticationSessionError,
                          authError.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleSignInError.failed)
                }
            }
            session.presentationContextProvider = self
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.failed
        }

        // Code → tokens. iOS OAuth clients have no secret; PKCE is the proof.
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        struct TokenResponse: Decodable { var id_token: String? }
        guard let idToken = (try? JSONDecoder().decode(TokenResponse.self, from: data))?.id_token else {
            throw GoogleSignInError.failed
        }
        return GoogleSignInResult(idToken: idToken, rawNonce: nonce)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }

    private static func randomURLSafe(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func base64URL(_ digest: SHA256.Digest) -> String {
        Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// "Continue with Google" — text-styled per brand rules, shown only when configured
/// and always BELOW the Apple button (guideline 4.8 keeps Apple first).
struct GoogleSignInButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Text("G")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                Text("Continue with Google")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.surfaceSecondary, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
