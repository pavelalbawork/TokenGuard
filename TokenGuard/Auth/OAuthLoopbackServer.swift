import Foundation
import Network

enum OAuthLoopbackError: LocalizedError {
    case timeout
    case invalidRequest
    case portUnavailable

    var errorDescription: String? {
        switch self {
        case .timeout: return "The authentication request timed out."
        case .invalidRequest: return "Received an invalid callback payload."
        case .portUnavailable: return "Could not bind to local port 4242. Make sure no other apps are using it."
        }
    }
}

final class OAuthLoopbackServer: @unchecked Sendable {
    private let port: NWEndpoint.Port = 4242
    private var listener: NWListener?
    private var activeConnections = [NWConnection]()
    private let lock = NSLock()
    private var isCompleted = false
    
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
                let listener = try NWListener(using: .tcp, on: port)
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
            
            let lines = request.components(separatedBy: .newlines)
            guard let requestLine = lines.first else {
                connection.cancel()
                return
            }
            
            let parts = requestLine.components(separatedBy: .whitespaces)
            guard parts.count >= 2, parts[0] == "GET" else {
                connection.cancel()
                return
            }
            
            guard let urlComponents = URLComponents(string: parts[1]),
                  let queryItems = urlComponents.queryItems else {
                connection.cancel()
                return
            }
            
            if queryItems.first(where: { $0.name == "error" })?.value != nil {
                self?.respond(to: connection, success: false) {
                    completion(.failure(OAuthLoopbackError.invalidRequest))
                }
                return
            }
            
            guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
                connection.cancel()
                return
            }
            
            self?.respond(to: connection, success: true) {
                completion(.success(code))
            }
        }
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
}
