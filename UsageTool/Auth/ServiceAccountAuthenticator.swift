import Foundation
import Security

struct GoogleServiceAccount: Codable, Equatable, Sendable {
    let type: String
    let projectId: String
    let privateKeyId: String
    let privateKey: String
    let clientEmail: String
    let clientId: String
    let authUri: String
    let tokenUri: String
    
    enum CodingKeys: String, CodingKey {
        case type
        case projectId = "project_id"
        case privateKeyId = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientId = "client_id"
        case authUri = "auth_uri"
        case tokenUri = "token_uri"
    }
}

enum ServiceAccountError: LocalizedError {
    case invalidKeyFormat
    case keyDerivationFailed
    case signingFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidKeyFormat: return "The service account private key format is invalid."
        case .keyDerivationFailed: return "Could not derive a secure key from the provided JSON."
        case .signingFailed: return "Failed to sign the authentication payload."
        case .invalidResponse: return "Received an invalid token response from Google."
        }
    }
}

struct ServiceAccountAuthenticator: Sendable {
    private let session: NetworkSession
    private let now: @Sendable () -> Date
    
    init(
        session: NetworkSession = URLSession.shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.now = now
    }
    
    func fetchAccessToken(serviceAccount: GoogleServiceAccount) async throws -> GoogleOAuthTokens {
        let jwt = try mintJWT(for: serviceAccount)
        
        var request = URLRequest(url: URL(string: serviceAccount.tokenUri)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: jwt)
        ]
        request.httpBody = components.query?.data(using: .utf8)
        
        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Google Service Account token response")
        
        guard let accessToken = ProviderSupport.string(root["access_token"]),
              let expiresIn = ProviderSupport.double(root["expires_in"]) else {
            throw ServiceAccountError.invalidResponse
        }
        
        return GoogleOAuthTokens(
            accessToken: accessToken,
            refreshToken: "", // Service Accounts do not use refresh tokens; you just mint a new JWT
            expiresAt: now().addingTimeInterval(expiresIn),
            tokenType: ProviderSupport.string(root["token_type"]) ?? "Bearer",
            scope: nil
        )
    }
    
    private func mintJWT(for account: GoogleServiceAccount) throws -> String {
        let headerJSON = """
        {"alg":"RS256","typ":"JWT"}
        """.data(using: .utf8)!
        
        let iat = Int(now().timeIntervalSince1970)
        let exp = iat + 3600
        
        let claimJSON = """
        {
          "iss": "\(account.clientEmail)",
          "scope": "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/monitoring.read",
          "aud": "\(account.tokenUri)",
          "exp": \(exp),
          "iat": \(iat)
        }
        """.data(using: .utf8)!
        
        let headerB64 = base64URLEncode(headerJSON)
        let claimB64 = base64URLEncode(claimJSON)
        let unsignedToken = "\(headerB64).\(claimB64)"
        
        guard let unsignedData = unsignedToken.data(using: .utf8) else {
            throw ServiceAccountError.signingFailed
        }
        
        let signature = try sign(unsignedData, privateKeyPEM: account.privateKey)
        let signatureB64 = base64URLEncode(signature)
        
        return "\(unsignedToken).\(signatureB64)"
    }
    
    private func sign(_ data: Data, privateKeyPEM: String) throws -> Data {
        let lines = privateKeyPEM.components(separatedBy: .newlines)
        let base64String = lines
            .filter { !$0.hasPrefix("-----") }
            .joined()
        
        guard let keyData = Data(base64Encoded: base64String, options: .ignoreUnknownCharacters) else {
            throw ServiceAccountError.invalidKeyFormat
        }
        
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            keyData as CFData,
            [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate
            ] as CFDictionary,
            &error
        ) else {
            throw ServiceAccountError.keyDerivationFailed
        }
        
        guard let signature = SecKeyCreateSignature(
            secKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw ServiceAccountError.signingFailed
        }
        
        return signature
    }
    
    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
