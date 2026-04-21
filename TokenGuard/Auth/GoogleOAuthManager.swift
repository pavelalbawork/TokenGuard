import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

struct GoogleOAuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let tokenType: String
    let scope: String?

    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow <= 60
    }
}

protocol GoogleOAuthManaging: Sendable {
    func authorizationURL(for account: Account, state: String) throws -> URL
    @MainActor
    func authorize(account: Account, clientSecret: String) async throws -> GoogleOAuthTokens
    func exchangeAuthorizationCode(_ code: String, account: Account, clientSecret: String) async throws -> GoogleOAuthTokens
    func accessToken(using storedSecret: String, account: Account) async throws -> String
    func saveTokens(_ tokens: GoogleOAuthTokens, clientSecret: String, reference: String, keychainManager: KeychainManager) throws
    func loadTokens(reference: String, keychainManager: KeychainManager) throws -> GoogleOAuthTokens?
}

enum GoogleOAuthError: LocalizedError, Equatable, Sendable {
    case missingConfiguration(String)
    case invalidRedirect
    case invalidState
    case invalidTokenResponse
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case let .missingConfiguration(message):
            return message
        case .invalidRedirect:
            return "The Google OAuth redirect did not contain an authorization code."
        case .invalidState:
            return "The Google OAuth redirect did not match the active sign-in request."
        case .invalidTokenResponse:
            return "The Google OAuth token response was invalid."
        case .unsupportedPlatform:
            return "Opening the Google consent screen is not supported on this platform."
        }
    }
}

struct GoogleOAuthManager: GoogleOAuthManaging {
    private struct StoredOAuthSecret: Codable, Sendable {
        let tokens: GoogleOAuthTokens
        let clientSecret: String
    }

    private let session: NetworkSession
    private let authBaseURL: URL
    private let tokenBaseURL: URL
    private let now: @Sendable () -> Date

    init(
        session: NetworkSession = URLSession.shared,
        authBaseURL: URL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenBaseURL: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.authBaseURL = authBaseURL
        self.tokenBaseURL = tokenBaseURL
        self.now = now
    }

    func authorizationURL(for account: Account, state: String) throws -> URL {
        guard let clientID = account.configurationValue(for: Account.ConfigurationKey.googleClientID) else {
            throw GoogleOAuthError.missingConfiguration("Gemini accounts require a Google OAuth client ID.")
        }
        guard let redirectURI = account.configurationValue(for: Account.ConfigurationKey.googleRedirectURI) else {
            throw GoogleOAuthError.missingConfiguration("Gemini accounts require a Google OAuth redirect URI.")
        }

        let scopes = account.configurationValue(for: Account.ConfigurationKey.googleOAuthScopes)
            ?? "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/monitoring.read"

        var components = URLComponents(url: authBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw GoogleOAuthError.missingConfiguration("Could not build the Google OAuth authorization URL.")
        }

        return url
    }

    @MainActor
    func authorize(account: Account, clientSecret: String) async throws -> GoogleOAuthTokens {
        guard let redirectURI = account.configurationValue(for: Account.ConfigurationKey.googleRedirectURI),
              let redirectURL = URL(string: redirectURI) else {
            throw GoogleOAuthError.missingConfiguration("Gemini accounts require a valid Google OAuth redirect URI.")
        }

        let state = UUID().uuidString
        let url = try authorizationURL(for: account, state: state)
        let code = try await authenticate(url: url, expectedState: state, redirectURL: redirectURL)
        return try await exchangeAuthorizationCode(code, account: account, clientSecret: clientSecret)
    }

    func exchangeAuthorizationCode(_ code: String, account: Account, clientSecret: String) async throws -> GoogleOAuthTokens {
        let bodyItems = try tokenRequestBodyItems(
            account: account,
            clientSecret: clientSecret,
            extraItems: [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "grant_type", value: "authorization_code")
            ]
        )
        return try await exchangeTokens(bodyItems: bodyItems)
    }

    func accessToken(using storedSecret: String, account: Account) async throws -> String {
        if let storedSecret = decodeStoredSecret(from: storedSecret) {
            if !storedSecret.tokens.isExpired {
                return storedSecret.tokens.accessToken
            }

            let bodyItems = try tokenRequestBodyItems(
                account: account,
                clientSecret: storedSecret.clientSecret,
                extraItems: [
                    URLQueryItem(name: "refresh_token", value: storedSecret.tokens.refreshToken),
                    URLQueryItem(name: "grant_type", value: "refresh_token")
                ]
            )
            let refreshed = try await exchangeTokens(
                bodyItems: bodyItems,
                fallbackRefreshToken: storedSecret.tokens.refreshToken
            )
            return refreshed.accessToken
        }

        if let tokens = decodeTokens(from: storedSecret), !tokens.isExpired {
            return tokens.accessToken
        }

        throw GoogleOAuthError.missingConfiguration(
            "Gemini refresh requires the Google client secret to be stored in Keychain with the OAuth tokens."
        )
    }

    func saveTokens(_ tokens: GoogleOAuthTokens, clientSecret: String, reference: String, keychainManager: KeychainManager) throws {
        let storedSecret = StoredOAuthSecret(tokens: tokens, clientSecret: clientSecret)
        let data = try JSONEncoder().encode(storedSecret)
        try keychainManager.saveSecret(String(decoding: data, as: UTF8.self), reference: reference)
    }

    func loadTokens(reference: String, keychainManager: KeychainManager) throws -> GoogleOAuthTokens? {
        guard let secret = try keychainManager.readSecret(reference: reference) else {
            return nil
        }

        return decodeStoredSecret(from: secret)?.tokens ?? decodeTokens(from: secret)
    }

    private func tokenRequestBodyItems(
        account: Account,
        clientSecret: String,
        extraItems: [URLQueryItem]
    ) throws -> [URLQueryItem] {
        guard let clientID = account.configurationValue(for: Account.ConfigurationKey.googleClientID) else {
            throw GoogleOAuthError.missingConfiguration("Gemini accounts require a Google OAuth client ID.")
        }
        guard let redirectURI = account.configurationValue(for: Account.ConfigurationKey.googleRedirectURI) else {
            throw GoogleOAuthError.missingConfiguration("Gemini accounts require a Google OAuth redirect URI.")
        }

        return [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ] + extraItems
    }

    @MainActor
    private func authenticate(url: URL, expectedState: String, redirectURL: URL) async throws -> String {
        #if canImport(AppKit)
        let loopback: OAuthLoopbackServer
        do {
            loopback = try OAuthLoopbackServer(redirectURL: redirectURL, expectedState: expectedState)
        } catch OAuthLoopbackError.invalidConfiguration {
            throw GoogleOAuthError.invalidRedirect
        } catch {
            throw GoogleOAuthError.invalidRedirect
        }

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                return try await loopback.waitForCode()
            }
            
            // Give the listener a tiny fraction to bind
            try await Task.sleep(nanoseconds: 50_000_000) 
            NSWorkspace.shared.open(url)
            
            guard let code = try await group.next() else {
                throw GoogleOAuthError.invalidRedirect
            }
            
            return code
        }
        } catch OAuthLoopbackError.invalidState {
            throw GoogleOAuthError.invalidState
        } catch OAuthLoopbackError.invalidRequest {
            throw GoogleOAuthError.invalidRedirect
        } catch {
            throw error
        }
        #else
        throw GoogleOAuthError.unsupportedPlatform
        #endif
    }

    private func exchangeTokens(
        bodyItems: [URLQueryItem],
        fallbackRefreshToken: String? = nil
    ) async throws -> GoogleOAuthTokens {
        var request = URLRequest(url: tokenBaseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = bodyItems
        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Google token response")

        guard let accessToken = ProviderSupport.string(root["access_token"]),
              let expiresIn = ProviderSupport.double(root["expires_in"]),
              let tokenType = ProviderSupport.string(root["token_type"]) else {
            throw GoogleOAuthError.invalidTokenResponse
        }

        let refreshToken = ProviderSupport.string(root["refresh_token"]) ?? fallbackRefreshToken
        guard let refreshToken else {
            throw GoogleOAuthError.invalidTokenResponse
        }

        return GoogleOAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(expiresIn),
            tokenType: tokenType,
            scope: ProviderSupport.string(root["scope"])
        )
    }

    private func decodeStoredSecret(from secret: String) -> StoredOAuthSecret? {
        guard let data = secret.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredOAuthSecret.self, from: data)
    }

    private func decodeTokens(from secret: String) -> GoogleOAuthTokens? {
        guard let data = secret.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(GoogleOAuthTokens.self, from: data)
    }
}
