import Foundation
import XCTest
@testable import TokenGuard

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func write(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func withValue<T>(_ transform: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return transform(&value)
    }
}

private func anthropicHttpOK(data: Data, for url: URL) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (response, data)
}

private func requestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    var data = Data()
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 {
            break
        }
        data.append(buffer, count: read)
    }

    return data.isEmpty ? nil : data
}

final class AnthropicProviderTests: XCTestCase {
    func testConsumerUsageUsesOAuthRemainingWindows() async throws {
        let apiURL = URL(string: "https://api.anthropic.com")!
        let session = makeMockedSession()
        let responseData = Data(
            """
            {
              "five_hour": {
                "utilization": 40.0,
                "resets_at": "2026-04-07T05:59:59.763996+00:00"
              },
              "seven_day": {
                "utilization": 14.0,
                "resets_at": "2026-04-13T19:00:00.764018+00:00"
              }
            }
            """.utf8
        )

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
            return anthropicHttpOK(data: responseData, for: apiURL)
        }

        let provider = AnthropicProvider(
            session: session,
            baseURL: apiURL,
            snapshotReader: nil,
            credentialLoader: {
                ClaudeOAuthCredential(
                    accessToken: "test-access-token",
                    refreshToken: "test-refresh-token",
                    subscriptionType: "pro",
                    rateLimitTier: "default_claude_ai",
                    expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
                    scope: "user:profile"
                )
            },
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let account = Account(
            name: "claude@example.com",
            serviceType: .claude,
            credentialRef: "claude-test",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )

        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.tier, "Pro")
        XCTAssertEqual(snapshot.windows.count, 2)
        XCTAssertEqual(snapshot.windows.first(where: { $0.windowType == .rolling5h })?.unit, .percent)
        XCTAssertEqual(snapshot.windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 40, accuracy: 0.1)
        XCTAssertEqual(snapshot.windows.first(where: { $0.windowType == .weekly })?.used ?? -1, 14, accuracy: 0.1)
    }

    func testExpiredConsumerCredentialRefreshesBeforeUsageRequest() async throws {
        let apiURL = URL(string: "https://api.anthropic.com")!
        let session = makeMockedSession()
        let tokenResponse = Data(
            """
            {
              "access_token": "refreshed-access-token",
              "refresh_token": "refreshed-refresh-token",
              "expires_in": 3600,
              "scope": "user:profile"
            }
            """.utf8
        )
        let usageResponse = Data(
            """
            {
              "five_hour": {
                "utilization": 22.0,
                "resets_at": "2026-04-07T05:59:59.763996+00:00"
              },
              "seven_day": {
                "utilization": 9.0,
                "resets_at": "2026-04-13T19:00:00.764018+00:00"
              }
            }
            """.utf8
        )
        let persistedCredential = LockedBox<ClaudeOAuthCredential?>(nil)

        URLProtocolMock.requestHandler = { request in
            switch request.url?.path {
            case "/v1/oauth/token":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let body = try XCTUnwrap(requestBodyData(from: request))
                let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
                XCTAssertEqual(payload["grant_type"], "refresh_token")
                XCTAssertEqual(payload["client_id"], "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
                XCTAssertEqual(payload["refresh_token"], "expired-refresh-token")
                return anthropicHttpOK(data: tokenResponse, for: apiURL)
            case "/api/oauth/usage":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed-access-token")
                return anthropicHttpOK(data: usageResponse, for: apiURL)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                return anthropicHttpOK(data: Data("{}".utf8), for: apiURL)
            }
        }

        let provider = AnthropicProvider(
            session: session,
            baseURL: apiURL,
            snapshotReader: nil,
            credentialLoader: {
                ClaudeOAuthCredential(
                    accessToken: "expired-access-token",
                    refreshToken: "expired-refresh-token",
                    subscriptionType: "max",
                    rateLimitTier: "default_claude_ai",
                    expiresAt: Date(timeIntervalSince1970: 1_774_999_900),
                    scope: "user:profile"
                )
            },
            credentialPersister: { persistedCredential.write($0) },
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let account = Account(
            name: "claude@example.com",
            serviceType: .claude,
            credentialRef: "claude-test",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )

        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.tier, "Max")
        XCTAssertEqual(snapshot.windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 22, accuracy: 0.1)
        XCTAssertEqual(persistedCredential.read()?.accessToken, "refreshed-access-token")
        XCTAssertEqual(persistedCredential.read()?.refreshToken, "refreshed-refresh-token")
    }

    func testUnauthorizedUsageRefreshesAndRetriesOnce() async throws {
        let apiURL = URL(string: "https://api.anthropic.com")!
        let session = makeMockedSession()
        let tokenResponse = Data(
            """
            {
              "access_token": "fresh-access-token",
              "refresh_token": "fresh-refresh-token",
              "expires_in": 3600
            }
            """.utf8
        )
        let usageResponse = Data(
            """
            {
              "five_hour": {
                "utilization": 11.0,
                "resets_at": "2026-04-07T05:59:59.763996+00:00"
              }
            }
            """.utf8
        )
        let usageRequestCount = LockedBox(0)

        URLProtocolMock.requestHandler = { request in
            switch request.url?.path {
            case "/api/oauth/usage":
                let count = usageRequestCount.withValue {
                    $0 += 1
                    return $0
                }
                if count == 1 {
                    let response = HTTPURLResponse(url: apiURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (response, Data("{}".utf8))
                }

                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-access-token")
                return anthropicHttpOK(data: usageResponse, for: apiURL)
            case "/v1/oauth/token":
                return anthropicHttpOK(data: tokenResponse, for: apiURL)
            default:
                XCTFail("Unexpected request path: \(request.url?.path ?? "nil")")
                return anthropicHttpOK(data: Data("{}".utf8), for: apiURL)
            }
        }

        let provider = AnthropicProvider(
            session: session,
            baseURL: apiURL,
            snapshotReader: nil,
            credentialLoader: {
                ClaudeOAuthCredential(
                    accessToken: "stale-access-token",
                    refreshToken: "stale-refresh-token",
                    subscriptionType: "pro",
                    rateLimitTier: nil,
                    expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
                    scope: nil
                )
            },
            credentialPersister: { _ in },
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let account = Account(
            name: "claude@example.com",
            serviceType: .claude,
            credentialRef: "claude-test",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )

        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(usageRequestCount.read(), 2)
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.used ?? -1, 11, accuracy: 0.1)
    }
}
