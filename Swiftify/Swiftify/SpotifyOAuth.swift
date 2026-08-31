import CryptoKit
import Foundation
import SwiftUI
import WebKit

struct SpotifyOAuthToken {
    let accessToken: String
    let refreshToken: String?
    let expirationDate: Date
}

enum SpotifyOAuthError: LocalizedError {
    case invalidClientID
    case invalidAuthorizationURL
    case invalidCallback
    case authorizationDenied(String)
    case stateMismatch
    case missingRefreshToken
    case tokenRequestFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidClientID:
            "Enter the Client ID from your Spotify developer app."
        case .invalidAuthorizationURL:
            "Could not create the Spotify authorization URL."
        case .invalidCallback:
            "Spotify returned an invalid authorization callback."
        case let .authorizationDenied(message):
            "Spotify authorization was denied: \(message)"
        case .stateMismatch:
            "Spotify returned an authorization response with an invalid state."
        case .missingRefreshToken:
            "Spotify did not return a refresh token. Please try connecting again."
        case let .tokenRequestFailed(message):
            "Spotify token exchange failed: \(message)"
        }
    }
}

@MainActor
final class SpotifyOAuthFlow {
    nonisolated static let playbackClientID = "65b708073fc0480ea92a077233ca87bd"
    nonisolated static let playbackAuthorizationVersion = 2
    nonisolated static let libraryAuthorizationVersion = 2
    static let redirectURI = URL(string: "http://127.0.0.1:8898/login")!

    private var codeVerifier: String?
    private var expectedState: String?

    func makeAuthorizationURL(clientID: String, scopes: [String]) throws -> URL {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw SpotifyOAuthError.invalidClientID
        }

        let verifier = Self.randomURLSafeString(byteCount: 32)
        let challengeDigest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(challengeDigest).base64URLEncodedString()
        let state = Self.randomURLSafeString(byteCount: 24)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components?.url else {
            throw SpotifyOAuthError.invalidAuthorizationURL
        }

        codeVerifier = verifier
        expectedState = state
        return url
    }

    func exchangeCallback(
        _ callbackURL: URL,
        clientID: String
    ) async throws -> SpotifyOAuthToken {
        guard
            Self.isCallbackURL(callbackURL),
            let verifier = codeVerifier,
            let expectedState
        else {
            throw SpotifyOAuthError.invalidCallback
        }

        defer {
            codeVerifier = nil
            self.expectedState = nil
        }

        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        let value = { name in
            queryItems.first(where: { $0.name == name })?.value
        }

        if let error = value("error") {
            throw SpotifyOAuthError.authorizationDenied(error)
        }

        guard value("state") == expectedState else {
            throw SpotifyOAuthError.stateMismatch
        }

        guard let code = value("code") else {
            throw SpotifyOAuthError.invalidCallback
        }

        return try await requestToken(formItems: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: verifier),
        ])
    }

    func refreshAccessToken(
        refreshToken: String,
        clientID: String
    ) async throws -> SpotifyOAuthToken {
        return try await requestToken(formItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID),
        ])
    }

    private func requestToken(formItems: [URLQueryItem]) async throws -> SpotifyOAuthToken {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        var form = URLComponents()
        form.queryItems = formItems
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyOAuthError.tokenRequestFailed("invalid HTTP response")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SpotifyOAuthError.tokenRequestFailed(responseBody)
        }

        let responseToken = try JSONDecoder().decode(TokenResponse.self, from: data)
        return SpotifyOAuthToken(
            accessToken: responseToken.accessToken,
            refreshToken: responseToken.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(responseToken.expiresIn))
        )
    }

    func cancel() {
        codeVerifier = nil
        expectedState = nil
    }

    static func isCallbackURL(_ url: URL) -> Bool {
        url.scheme == redirectURI.scheme
            && url.host == redirectURI.host
            && url.port == redirectURI.port
            && url.path == redirectURI.path
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0 ..< byteCount).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        return Data(bytes).base64URLEncodedString()
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct SpotifyLoginSheet: View {
    let authorizationURL: URL
    let onCallback: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Spotify")
                    .font(.headline)

                Spacer()

                Button("Cancel", action: onCancel)
            }
            .padding()

            Divider()

            SpotifyLoginWebView(
                authorizationURL: authorizationURL,
                onCallback: onCallback
            )
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 640, idealHeight: 720)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .interactiveDismissDisabled()
    }
}

#if os(macOS)
struct SpotifyLoginWebView: NSViewRepresentable {
    let authorizationURL: URL
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: authorizationURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCallback: (URL) -> Void

        init(onCallback: @escaping (URL) -> Void) {
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if SpotifyOAuthFlow.isCallbackURL(url) {
                decisionHandler(.cancel)
                onCallback(url)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
#endif

#if os(iOS)
struct SpotifyLoginWebView: UIViewRepresentable {
    let authorizationURL: URL
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCallback: onCallback)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: authorizationURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onCallback: (URL) -> Void

        init(onCallback: @escaping (URL) -> Void) {
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if SpotifyOAuthFlow.isCallbackURL(url) {
                decisionHandler(.cancel)
                onCallback(url)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
#endif
