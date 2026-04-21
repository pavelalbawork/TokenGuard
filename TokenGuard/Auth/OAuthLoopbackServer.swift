import Foundation
import Network

enum OAuthLoopbackError: LocalizedError, Equatable {
    case timeout
    case invalidRequest
    case invalidState
    case invalidConfiguration
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .timeout: return "The authentication request timed out."
        case .invalidRequest: return "Received an invalid callback payload."
        case .invalidState: return "The Google OAuth callback state did not match the active sign-in request."
        case .invalidConfiguration: return "The Google OAuth redirect URI must use a loopback host with an explicit port."
        case .portUnavailable: return "Could not bind to the local OAuth callback port. Make sure no other apps are using it."
        }
    }
}

final class OAuthLoopbackServer: @unchecked Sendable {
    private let localHost: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let expectedPath: String
    private let expectedState: String
    private var listener: NWListener?
    private var activeConnections = [NWConnection]()
    private let lock = NSLock()
    private var isCompleted = false

    init(redirectURL: URL, expectedState: String) throws {
        guard
            let host = redirectURL.host,
            let localHost = Self.loopbackHost(from: host),
            let portValue = redirectURL.port,
            let port = NWEndpoint.Port(rawValue: UInt16(portValue))
        else {
            throw OAuthLoopbackError.invalidConfiguration
        }

        self.localHost = localHost
        self.port = port
        self.expectedPath = Self.normalizedPath(redirectURL.path)
        self.expectedState = expectedState
    }

    func waitForCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let complete: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
                guard let self = self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                
                guard !self.isCompleted else { return }
                self.isCompleted = true
                
                self.listener?.cancel()
                self.activeConnections.forEach { $0.cancel() }
                self.activeConnections.removeAll()
                
                continuation.resume(with: result)
            }
            
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: localHost, port: port)

                let listener = try NWListener(using: parameters)
                self.listener = listener
                
                listener.newConnectionHandler = { [weak self] connection in
                    guard let self = self else { return }
                    self.lock.lock()
                    if self.isCompleted {
                        self.lock.unlock()
                        connection.cancel()
                        return
                    }
                    self.activeConnections.append(connection)
                    self.lock.unlock()
                    
                    connection.start(queue: .global())
                    self.receiveData(on: connection, completion: complete)
                }
                
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .failed(_):
                        complete(.failure(OAuthLoopbackError.portUnavailable))
                    default:
                        break
                    }
                }
                
                listener.start(queue: .global())
                
                // Timeout after 5 minutes
                DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                    complete(.failure(OAuthLoopbackError.timeout))
                }
            } catch {
                complete(.failure(OAuthLoopbackError.portUnavailable))
            }
        }
    }
    
    private func receiveData(on connection: NWConnection, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if error != nil {
                connection.cancel()
                return
            }
            
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                if !isComplete { self?.receiveData(on: connection, completion: completion) }
                return
            }
            
            do {
                guard let self else {
                    connection.cancel()
                    return
                }

                let code = try Self.authorizationCode(
                    from: request,
                    expectedPath: self.expectedPath,
                    expectedState: self.expectedState
                )

                self.respond(to: connection, success: true) {
                    completion(.success(code))
                }
            } catch {
                self?.respond(to: connection, success: false) {
                    completion(.failure(error))
                }
            }
        }
    }

    static func authorizationCode(
        from request: String,
        expectedPath: String,
        expectedState: String
    ) throws -> String {
        let lines = request.components(separatedBy: .newlines)
        guard let requestLine = lines.first else {
            throw OAuthLoopbackError.invalidRequest
        }

        let parts = requestLine.components(separatedBy: .whitespaces)
        guard parts.count >= 2, parts[0] == "GET" else {
            throw OAuthLoopbackError.invalidRequest
        }

        guard let urlComponents = URLComponents(string: parts[1]) else {
            throw OAuthLoopbackError.invalidRequest
        }

        let path = normalizedPath(urlComponents.path)
        guard path == normalizedPath(expectedPath) else {
            throw OAuthLoopbackError.invalidRequest
        }

        let queryItems = urlComponents.queryItems ?? []
        if queryItems.first(where: { $0.name == "error" })?.value != nil {
            throw OAuthLoopbackError.invalidRequest
        }

        guard let state = queryItems.first(where: { $0.name == "state" })?.value,
              state == expectedState else {
            throw OAuthLoopbackError.invalidState
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw OAuthLoopbackError.invalidRequest
        }

        return code
    }
    
    private func respond(to connection: NWConnection, success: Bool, completion: @escaping @Sendable () -> Void) {
        let title = success ? "Authorization Successful" : "Authorization Failed"
        let subtitle = success ? "You can safely close this tab and return to TokenGuard." : "An error occurred during authentication."
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>\(title)</title>
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#f5f5f7;color:#1d1d1f;}</style>
        </head><body><div style="text-align:center;padding:40px;background:#fff;border-radius:12px;box-shadow:0 4px 14px rgba(0,0,0,0.1);">
        <h2>\(title)</h2><p>\(subtitle)</p></div>
        <script>window.setTimeout(function() { window.close(); }, 3000);</script>
        </body></html>
        """
        
        let response = "HTTP/1.1 200 OK\r\nContent-Length: \(html.utf8.count)\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(html)"
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            completion()
        })
    }

    private static func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    private static func loopbackHost(from host: String) -> NWEndpoint.Host? {
        switch host.lowercased() {
        case "localhost", "127.0.0.1":
            guard let address = IPv4Address("127.0.0.1") else { return nil }
            return .ipv4(address)
        case "::1":
            guard let address = IPv6Address("::1") else { return nil }
            return .ipv6(address)
        default:
            return nil
        }
    }
}
