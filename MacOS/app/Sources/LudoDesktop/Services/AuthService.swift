import SwiftUI
import AppKit
import AuthenticationServices
import CryptoKit

/// Browser-redirect login (the "like Claude" flow).
///
/// `.live` opens the system browser via `ASWebAuthenticationSession`; the OAuth
/// callback returns to the custom scheme `ludo-desktop://auth/callback` and we
/// complete a PKCE exchange. `.mock` returns an instant fake session so the
/// click-dummy can be navigated without a backend.
@Observable
final class AuthService: NSObject, ASWebAuthenticationPresentationContextProviding {

    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case mock, live
        var id: String { rawValue }
    }

    struct Session { let token: String; let accountID: String }

    var mode: Mode
    var session: Session?
    var isAuthenticating = false
    var lastError: String?

    /// Live config — the BFF that brokers GitHub OAuth for the desktop app. Resolved from
    /// env / UserDefaults / cluster.yaml default (see `ClientConfig`); never hardcoded (#5).
    var bffBaseURL = ClientConfig.baseURL
    private let callbackScheme = "ludo-desktop"
    private var verifier: String?
    private var webSession: ASWebAuthenticationSession?

    init(mode: Mode) { self.mode = mode }

    var isSignedIn: Bool { session != nil }

    func signIn() {
        lastError = nil
        switch mode {
        case .mock:
            session = Session(token: "mock-token", accountID: "acct_demo")
        case .live:
            startBrowserRedirect()
        }
    }

    func signOut() { session = nil }

    // MARK: - Browser redirect (PKCE + custom scheme)

    private func startBrowserRedirect() {
        isAuthenticating = true
        let v = Self.randomURLSafe(64)
        verifier = v
        let challenge = Self.codeChallenge(for: v)

        var comps = URLComponents(
            url: bffBaseURL.appendingPathComponent("/auth/desktop/start"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://auth/callback"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let session = ASWebAuthenticationSession(
            url: comps.url!,
            callbackURLScheme: callbackScheme
        ) { [weak self] url, error in
            guard let self else { return }
            self.isAuthenticating = false
            if let error {
                // User cancel is expected and not an error worth surfacing loudly.
                if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                    self.lastError = error.localizedDescription
                }
                return
            }
            if let url { self.handleCallback(url) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        session.start()
    }

    /// Handles `ludo-desktop://auth/callback?code=...` (from the session closure
    /// or the app-level `.onOpenURL`).
    func handleCallback(_ url: URL) {
        guard url.scheme == callbackScheme else { return }
        let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        guard let code else { lastError = "Missing authorization code"; return }

        // TODO(#94): POST {code, code_verifier} to /auth/desktop/token, store the
        // returned bearer token in Keychain. Stubbed here for the click-dummy.
        _ = verifier
        session = Session(token: "exchanged:\(code)", accountID: "acct_demo")
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow }
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }

    // MARK: - PKCE helpers

    static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
