import CryptoKit
import Foundation
import SQLite3

// MARK: - Internal types

private struct AntigravityAccount: Sendable {
    let email: String
    let isActive: Bool
    let pools: [QuotaPool]
}

private struct QuotaPool: Sendable {
    enum Category: Sendable {
        case anthropic
        case geminiFlash
        case geminiPro

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .geminiFlash: return "Gemini Flash"
            case .geminiPro: return "Gemini Pro"
            }
        }
    }

    let category: Category
    let remainingPercent: Int   // 0 = exhausted, 100 = full
    let resetTime: Date?
    let modelNames: [String]
}

// MARK: - Provider

struct AntigravityProvider: ServiceProvider {
    let serviceType: ServiceType = .antigravity

    private let dbURL: URL
    private let keyURL: URL
    private let stateDbURL: URL
    private let cloudCodeBaseURL: URL
    private let session: NetworkSession
    private let now: @Sendable () -> Date

    init(
        dbURL: URL = URL(
            fileURLWithPath: ("~/.antigravity-agent/cloud_accounts.db" as NSString)
                .expandingTildeInPath
        ),
        keyURL: URL = URL(
            fileURLWithPath: (
                "~/Library/Application Support/Antigravity Manager/.mk" as NSString
            ).expandingTildeInPath
        ),
        stateDbURL: URL = URL(
            fileURLWithPath: (
                "~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" as NSString
            ).expandingTildeInPath
        ),
        cloudCodeBaseURL: URL = URL(string: "https://cloudcode-pa.googleapis.com")!,
        session: NetworkSession = URLSession.shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dbURL = dbURL
        self.keyURL = keyURL
        self.stateDbURL = stateDbURL
        self.cloudCodeBaseURL = cloudCodeBaseURL
        self.session = session
        self.now = now
    }

    func fetchUsage(account: Account, credential _: String) async throws -> UsageSnapshot {
        let accounts: [AntigravityAccount]

        // Primary path: read from Antigravity Manager's encrypted database.
        if FileManager.default.fileExists(atPath: dbURL.path),
           FileManager.default.fileExists(atPath: keyURL.path)
        {
            accounts = try readAccounts()
        } else {
            // Fallback path: call the cloudcode API directly using the Antigravity
            // editor's stored access token.
            accounts = try await readAccountsDirect()
        }

        guard let active = accounts.first(where: { $0.isActive }) ?? accounts.first else {
            throw ServiceProviderError.unavailable("No Antigravity accounts found.")
        }

        let timestamp = now()
        var windows: [UsageWindow] = []
        var breakdown: [UsageBreakdown] = []

        for pool in active.pools {
            let usedPercent = Double(100 - pool.remainingPercent)
            windows.append(UsageWindow(
                windowType: .daily,
                used: usedPercent,
                limit: 100,
                unit: .percent,
                resetDate: pool.resetTime,
                label: pool.category.displayName
            ))
            for model in pool.modelNames {
                breakdown.append(UsageBreakdown(
                    label: model,
                    used: usedPercent,
                    limit: 100,
                    unit: .percent
                ))
            }
        }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: windows,
            tier: active.email,
            breakdown: breakdown.isEmpty ? nil : breakdown,
            isStale: false
        )
    }

    func validateCredentials(account _: Account, credential _: String) async throws -> Bool {
        let hasManagerFiles = FileManager.default.fileExists(atPath: dbURL.path)
            && FileManager.default.fileExists(atPath: keyURL.path)

        if hasManagerFiles {
            let accounts = try readAccounts()
            return !accounts.isEmpty
        }

        // Without Manager, check if the Antigravity editor state exists.
        guard FileManager.default.fileExists(atPath: stateDbURL.path) else {
            throw ServiceProviderError.unavailable(
                "Antigravity not found. Install Antigravity Manager or the Antigravity editor."
            )
        }

        // Try fetching — this will throw a meaningful error if the token is expired.
        let accounts = try await readAccountsDirect()
        return !accounts.isEmpty
    }

    // MARK: - Manager path (encrypted SQLite)

    private func readAccounts() throws -> [AntigravityAccount] {
        let key = try readSymmetricKey()

        var db: OpaquePointer?
        let dbEncoded = dbURL.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dbURL.path
        let dbUri = "file:\(dbEncoded)?immutable=1"
        guard sqlite3_open_v2(dbUri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            throw ServiceProviderError.unavailable("Could not open Antigravity database.")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT email, quota_json, is_active FROM accounts ORDER BY is_active DESC, last_used DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ServiceProviderError.unavailable("Could not query Antigravity database.")
        }
        defer { sqlite3_finalize(stmt) }

        var accounts: [AntigravityAccount] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let emailPtr = sqlite3_column_text(stmt, 0) else { continue }
            let email = String(cString: emailPtr)
            let isActive = sqlite3_column_int(stmt, 2) != 0

            guard
                let encPtr = sqlite3_column_text(stmt, 1),
                let quotaJSON = try? decrypt(String(cString: encPtr), key: key),
                let data = quotaJSON.data(using: .utf8),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let models = root["models"] as? [String: [String: Any]]
            else { continue }

            let pools = groupPools(from: models)
            accounts.append(AntigravityAccount(email: email, isActive: isActive, pools: pools))
        }

        return accounts
    }

    private func readSymmetricKey() throws -> SymmetricKey {
        guard let keyHex = try? String(contentsOf: keyURL, encoding: .utf8) else {
            throw ServiceProviderError.unavailable("Could not read Antigravity key file.")
        }
        let trimmed = keyHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64, let keyData = Data(hexString: trimmed) else {
            throw ServiceProviderError.unavailable(
                "Antigravity key file has unexpected format. Only the 32-byte hex file-based key is supported."
            )
        }
        return SymmetricKey(data: keyData)
    }

    private func decrypt(_ encrypted: String, key: SymmetricKey) throws -> String {
        let parts = encrypted.split(separator: ":", maxSplits: 2).map(String.init)
        guard
            parts.count == 3,
            let ivData = Data(hexString: parts[0]),
            let tagData = Data(hexString: parts[1]),
            let ctData = Data(hexString: parts[2])
        else {
            throw ServiceProviderError.invalidPayload("Unexpected encrypted field format.")
        }
        let nonce = try AES.GCM.Nonce(data: ivData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ctData, tag: tagData)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return String(data: plaintext, encoding: .utf8) ?? ""
    }

    // MARK: - Direct path (cloudcode-pa API)

    private func readAccountsDirect() async throws -> [AntigravityAccount] {
        let accessToken = try readAccessTokenFromStateDb()
        let models = try await fetchModelsFromAPI(accessToken: accessToken)
        let pools = groupPools(from: models)
        return [AntigravityAccount(email: "", isActive: true, pools: pools)]
    }

    private func readAccessTokenFromStateDb() throws -> String {
        var db: OpaquePointer?

        // Use the immutable URI mode so we can read the database while Antigravity has
        // it open in WAL mode. Spaces in the path must be percent-encoded for URI mode.
        let encoded = stateDbURL.path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stateDbURL.path
        let uri = "file:\(encoded)?immutable=1"

        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            throw ServiceProviderError.unavailable(
                "Could not open Antigravity editor database at \(stateDbURL.path)."
            )
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'antigravityAuthStatus'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ServiceProviderError.unavailable(
                "Could not query Antigravity editor database. Error: \(String(cString: sqlite3_errmsg(db)))"
            )
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let valuePtr = sqlite3_column_text(stmt, 0)
        else {
            throw ServiceProviderError.unavailable(
                "Antigravity editor has no auth status. Open Antigravity and sign in."
            )
        }

        let json = String(cString: valuePtr)
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let apiKey = root["apiKey"] as? String,
            !apiKey.isEmpty
        else {
            throw ServiceProviderError.unavailable(
                "Could not read access token from Antigravity editor. Try signing in to Antigravity again."
            )
        }

        return apiKey
    }

    private func fetchModelsFromAPI(accessToken: String) async throws -> [String: [String: Any]] {
        let url = cloudCodeBaseURL.appending(path: "/v1internal:fetchAvailableModels")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Antigravity fetchAvailableModels")

        // The API returns either an "availableModels" array or a "models" object.
        if let modelsObject = root["models"] as? [String: [String: Any]] {
            return modelsObject
        }

        if let modelsArray = root["availableModels"] as? [[String: Any]] {
            return parseModelsArray(modelsArray)
        }

        throw ServiceProviderError.invalidPayload(
            "Unexpected response format from Antigravity API."
        )
    }

    private func parseModelsArray(_ array: [[String: Any]]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for model in array {
            guard let name = ProviderSupport.string(model["modelName"] ?? model["name"]) else {
                continue
            }
            var info: [String: Any] = [:]

            // Map API fields to the internal format used by groupPools().
            if let quota = model["quotaInfo"] as? [String: Any] {
                if let fraction = ProviderSupport.double(quota["remainingFraction"]) {
                    info["percentage"] = Int(fraction * 100)
                }
                if let resetTime = ProviderSupport.string(quota["resetTime"] ?? quota["reset_time"]) {
                    info["resetTime"] = resetTime
                }
            } else {
                if let fraction = ProviderSupport.double(model["remainingFraction"] ?? model["remaining_fraction"]) {
                    info["percentage"] = Int(fraction * 100)
                }
                if let resetTime = ProviderSupport.string(model["resetTime"] ?? model["reset_time"]) {
                    info["resetTime"] = resetTime
                }
            }

            result[name] = info
        }
        return result
    }

    // MARK: - Pool grouping

    private func groupPools(from models: [String: [String: Any]]) -> [QuotaPool] {
        var byCategory: [QuotaPool.Category: [(name: String, remaining: Int, resetTime: Date?)]] = [:]
        let isoFormatter = ISO8601DateFormatter()

        for (name, info) in models {
            let remaining = (info["percentage"] as? Int) ?? 100
            let resetTime = (info["resetTime"] as? String).flatMap { isoFormatter.date(from: $0) }
            let lower = name.lowercased()

            let category: QuotaPool.Category
            if lower.contains("claude") {
                category = .anthropic
            } else if lower.contains("flash") {
                category = .geminiFlash
            } else if lower.contains("pro") {
                category = .geminiPro
            } else {
                continue
            }

            byCategory[category, default: []].append((name, remaining, resetTime))
        }

        return [QuotaPool.Category.anthropic, .geminiFlash, .geminiPro].compactMap { category in
            guard let entries = byCategory[category], !entries.isEmpty else { return nil }
            // Use the most-depleted model as the representative for this pool.
            let constraining = entries.min(by: { $0.remaining < $1.remaining })!
            return QuotaPool(
                category: category,
                remainingPercent: constraining.remaining,
                resetTime: constraining.resetTime,
                modelNames: entries.map(\.name).sorted()
            )
        }
    }
}

// MARK: - Helpers

private extension Data {
    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
