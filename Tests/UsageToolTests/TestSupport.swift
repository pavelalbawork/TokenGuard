import Foundation
import Security
import XCTest
@testable import UsageTool

final class URLProtocolMock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = URLProtocolMock.requestHandler else {
            XCTFail("Missing request handler.")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolMock.self]
    return URLSession(configuration: configuration)
}

struct MockCLIParser: CLIParser {
    let windows: [UsageWindow]

    func parseUsageOutput() async throws -> [UsageWindow] {
        windows
    }
}

struct MockCommandRunner: CommandRunning {
    let output: String

    func run(_ command: String, arguments: [String]) async throws -> String {
        _ = command
        _ = arguments
        return output
    }
}

struct MockGoogleOAuthManager: GoogleOAuthManaging {
    let accessTokenValue: String

    func authorizationURL(for account: Account, state: String) throws -> URL {
        _ = account
        _ = state
        return URL(string: "https://example.com/oauth")!
    }

    func authorize(account: Account, clientSecret: String) async throws -> GoogleOAuthTokens {
        _ = account
        _ = clientSecret
        return GoogleOAuthTokens(
            accessToken: accessTokenValue,
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer",
            scope: nil
        )
    }

    func exchangeAuthorizationCode(_ code: String, account: Account, clientSecret: String) async throws -> GoogleOAuthTokens {
        _ = code
        _ = account
        _ = clientSecret
        return GoogleOAuthTokens(
            accessToken: accessTokenValue,
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            tokenType: "Bearer",
            scope: nil
        )
    }

    func accessToken(using storedSecret: String, account: Account) async throws -> String {
        _ = storedSecret
        _ = account
        return accessTokenValue
    }

    func saveTokens(_ tokens: GoogleOAuthTokens, clientSecret: String, reference: String, keychainManager: KeychainManager) throws {
        let data = try JSONEncoder().encode(tokens)
        _ = clientSecret
        try keychainManager.saveSecret(String(decoding: data, as: UTF8.self), reference: reference)
    }

    func loadTokens(reference: String, keychainManager: KeychainManager) throws -> GoogleOAuthTokens? {
        guard let secret = try keychainManager.readSecret(reference: reference) else {
            return nil
        }
        return try JSONDecoder().decode(GoogleOAuthTokens.self, from: Data(secret.utf8))
    }
}

final class InMemoryKeychainBackingStore: KeychainBackingStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    func add(query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let key = compositeKey(query: query)
        guard storage[key] == nil else { return errSecDuplicateItem }
        storage[key] = query[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let key = compositeKey(query: query)
        guard storage[key] != nil else { return errSecItemNotFound }
        storage[key] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let key = compositeKey(query: query)
        guard let data = storage[key] else { return errSecItemNotFound }
        result?.pointee = data as CFTypeRef
        return errSecSuccess
    }

    func delete(query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let key = compositeKey(query: query)
        guard storage.removeValue(forKey: key) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }

    private func compositeKey(query: [String: Any]) -> String {
        let service = query[kSecAttrService as String] as? String ?? ""
        let account = query[kSecAttrAccount as String] as? String ?? ""
        return "\(service)::\(account)"
    }
}
