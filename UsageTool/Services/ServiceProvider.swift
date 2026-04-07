import Foundation

protocol ServiceProvider: Sendable {
    var serviceType: ServiceType { get }
    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot
    func validateCredentials(account: Account, credential: String) async throws -> Bool
}

protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkSession {}

protocol ConsumerUsageSnapshotReading: Sendable {
    func windows(for serviceType: ServiceType) throws -> [UsageWindow]?
}

struct ConsumerAccountIdentity: Sendable, Equatable {
    let email: String?
    let externalID: String?
}

protocol ConsumerAccountDetecting: Sendable {
    func currentConsumerIdentity() async throws -> ConsumerAccountIdentity?
}

struct CodexAuthIdentityReader: Sendable {
    private let authURL: URL

    init(
        authURL: URL = URL(fileURLWithPath: NSString(string: "~/.codex/auth.json").expandingTildeInPath)
    ) {
        self.authURL = authURL
    }

    func readIdentity() throws -> ConsumerAccountIdentity? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: authURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: authURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        let root = try ProviderSupport.dictionary(payload, context: "Codex auth")
        let tokens = try ProviderSupport.dictionary(root["tokens"] as Any, context: "Codex auth tokens")

        let externalID = ProviderSupport.string(tokens["account_id"])
        let email = ProviderSupport.jwtClaim("email", from: ProviderSupport.string(tokens["id_token"]))

        if email == nil, externalID == nil {
            return nil
        }

        return ConsumerAccountIdentity(email: email, externalID: externalID)
    }
}

struct CompositeConsumerUsageSnapshotReader: ConsumerUsageSnapshotReading {
    private let readers: [any ConsumerUsageSnapshotReading]

    init(readers: [any ConsumerUsageSnapshotReading]) {
        self.readers = readers
    }

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        for reader in readers {
            if let windows = try reader.windows(for: serviceType), !windows.isEmpty {
                return windows
            }
        }

        return nil
    }
}

struct CodexSessionSnapshotReader: ConsumerUsageSnapshotReading {
    private struct TimestampedWindows {
        let timestamp: Date
        let windows: [UsageWindow]
    }

    private let rootDirectoryURL: URL

    init(
        rootDirectoryURL: URL = URL(fileURLWithPath: NSString(string: "~/.codex/sessions").expandingTildeInPath)
    ) {
        self.rootDirectoryURL = rootDirectoryURL
    }

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        guard serviceType == .codex else {
            return nil
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else {
            return nil
        }

        let enumerator = fileManager.enumerator(
            at: rootDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var sessionFiles: [(url: URL, modifiedAt: Date)] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            sessionFiles.append((fileURL, values.contentModificationDate ?? .distantPast))
        }

        var latest: TimestampedWindows?
        for candidate in sessionFiles.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
            if let parsed = try windows(from: candidate.url, fallbackTimestamp: candidate.modifiedAt) {
                if latest == nil || parsed.timestamp > latest!.timestamp {
                    latest = parsed
                }
            }
        }

        return latest?.windows
    }

    private func windows(from fileURL: URL, fallbackTimestamp: Date) throws -> TimestampedWindows? {
        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var latest: TimestampedWindows?
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8) else { continue }
            let payload = try JSONSerialization.jsonObject(with: lineData)
            guard
                let object = payload as? [String: Any],
                ProviderSupport.string(object["type"]) == "event_msg",
                let message = object["payload"] as? [String: Any],
                ProviderSupport.string(message["type"]) == "token_count",
                let rateLimits = message["rate_limits"] as? [String: Any]
            else {
                continue
            }

            let windows = ["primary", "secondary", "tertiary"].compactMap { key in
                makeWindow(from: rateLimits[key] as? [String: Any])
            }

            if !windows.isEmpty {
                let timestamp = ProviderSupport.isoDate(object["timestamp"]) ?? fallbackTimestamp
                if latest == nil || timestamp > latest!.timestamp {
                    latest = TimestampedWindows(timestamp: timestamp, windows: windows)
                }
            }
        }

        return latest
    }

    private func makeWindow(from limit: [String: Any]?) -> UsageWindow? {
        guard
            let limit,
            let usedPercent = ProviderSupport.double(limit["used_percent"])
        else {
            return nil
        }

        let resetDate = unixDate(limit["resets_at"])
        let windowMinutes = ProviderSupport.int(limit["window_minutes"])

        return UsageWindow(
            windowType: windowType(for: windowMinutes),
            used: min(max(usedPercent, 0), 100),
            limit: 100,
            unit: .percent,
            resetDate: resetDate,
            label: nil
        )
    }

    private func windowType(for windowMinutes: Int?) -> WindowType {
        switch windowMinutes {
        case 300:
            return .rolling5h
        case 10_080:
            return .weekly
        case 1_440:
            return .daily
        default:
            return .monthly
        }
    }

    private func unixDate(_ value: Any?) -> Date? {
        guard let timestamp = ProviderSupport.double(value) else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }
}

struct CodexBarWidgetSnapshotReader: ConsumerUsageSnapshotReading {
    private let snapshotURL: URL

    init(
        snapshotURL: URL = URL(fileURLWithPath: NSString(string: "~/Library/Group Containers/group.com.steipete.codexbar/widget-snapshot.json").expandingTildeInPath)
    ) {
        self.snapshotURL = snapshotURL
    }

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: snapshotURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        let root = try ProviderSupport.dictionary(payload, context: "CodexBar widget snapshot")
        let entries = try ProviderSupport.array(root["entries"], context: "CodexBar widget snapshot entries")
        guard let entry = entries.first(where: { ProviderSupport.string($0["provider"]) == serviceType.rawValue }) else {
            return nil
        }

        let windows = ["primary", "secondary", "tertiary"]
            .compactMap { key -> UsageWindow? in
                guard let limit = entry[key] else { return nil }
                return makeWindow(from: limit)
            }

        return windows.isEmpty ? nil : windows
    }

    private func makeWindow(from rawValue: Any) -> UsageWindow? {
        guard let limit = rawValue as? [String: Any],
              let usedPercent = ProviderSupport.double(limit["usedPercent"]) else {
            return nil
        }

        let windowMinutes = ProviderSupport.int(limit["windowMinutes"])
        return UsageWindow(
            windowType: windowType(for: windowMinutes),
            used: min(max(usedPercent, 0), 100),
            limit: 100,
            unit: .percent,
            resetDate: ProviderSupport.isoDate(limit["resetsAt"]),
            label: nil
        )
    }

    private func windowType(for windowMinutes: Int?) -> WindowType {
        switch windowMinutes {
        case 300:
            return .rolling5h
        case 10_080:
            return .weekly
        case 1_440:
            return .daily
        default:
            return .monthly
        }
    }
}

enum ServiceProviderError: LocalizedError, Equatable, Sendable {
    case missingConfiguration(String)
    case invalidResponse
    case unauthorized
    case unexpectedStatus(Int, String?)
    case unavailable(String)
    case agentNotRunning(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case let .missingConfiguration(message):
            return message
        case .invalidResponse:
            return "The service returned an invalid response."
        case .unauthorized:
            return "The provided credentials were rejected."
        case let .unexpectedStatus(code, message):
            return "Unexpected HTTP status \(code). \(message ?? "")".trimmingCharacters(in: .whitespaces)
        case let .unavailable(message):
            return message
        case let .agentNotRunning(message):
            return message
        case let .invalidPayload(message):
            return message
        }
    }
}

enum ProviderSupport {
    static func performJSONRequest(
        session: NetworkSession,
        request: URLRequest
    ) async throws -> Any {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceProviderError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ServiceProviderError.unauthorized
            }

            let message = String(data: data, encoding: .utf8)
            throw ServiceProviderError.unexpectedStatus(httpResponse.statusCode, message)
        }

        return try JSONSerialization.jsonObject(with: data)
    }

    static func startOfCurrentUTCDay(from now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.startOfDay(for: now)
    }

    static func endOfCurrentUTCDay(from now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? now
    }

    static func monthlyResetDate(
        resetDayOfMonth: Int?,
        resetHourUTC: Int?,
        from now: Date = Date()
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let currentComponents = calendar.dateComponents([.year, .month], from: now)
        let targetDay = max(1, min(resetDayOfMonth ?? 1, 28))
        let targetHour = max(0, min(resetHourUTC ?? 0, 23))

        var nextComponents = DateComponents()
        nextComponents.year = currentComponents.year
        nextComponents.month = currentComponents.month
        nextComponents.day = targetDay
        nextComponents.hour = targetHour
        nextComponents.minute = 0
        nextComponents.second = 0

        let candidate = calendar.date(from: nextComponents) ?? now
        if candidate > now {
            return candidate
        }

        return calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
    }

    static func nextWeeklyResetDate(
        weekday: Int?,
        hourUTC: Int?,
        from now: Date = Date()
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let targetWeekday = weekday ?? 2
        let targetHour = max(0, min(hourUTC ?? 0, 23))

        var next = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: targetHour, minute: 0, second: 0, weekday: targetWeekday),
            matchingPolicy: .nextTime,
            direction: .forward
        )

        if next == nil {
            next = calendar.date(byAdding: .day, value: 7, to: now)
        }

        return next ?? now
    }

    static func dictionary(_ value: Any, context: String) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw ServiceProviderError.invalidPayload("Expected object for \(context).")
        }
        return dictionary
    }

    static func array(_ value: Any?, context: String) throws -> [[String: Any]] {
        guard let array = value as? [[String: Any]] else {
            throw ServiceProviderError.invalidPayload("Expected array for \(context).")
        }
        return array
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    static func isoDate(_ value: Any?) -> Date? {
        guard let string = string(value) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func jwtClaim(_ key: String, from jwt: String?) -> String? {
        guard let jwt else { return nil }
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
              let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any]
        else {
            return nil
        }

        return string(object[key])
    }

    static func isConnectionRefused(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut:
            return true
        default:
            return false
        }
    }

    static func manualWindow(
        type: WindowType,
        account: Account,
        usedKey: String,
        limitKey: String,
        unit: UsageUnit,
        resetDate: Date?,
        label: String? = nil
    ) -> UsageWindow {
        UsageWindow(
            windowType: type,
            used: account.configurationDouble(for: usedKey) ?? 0,
            limit: account.configurationDouble(for: limitKey),
            unit: unit,
            resetDate: resetDate,
            label: label ?? type.defaultLabel
        )
    }
}
