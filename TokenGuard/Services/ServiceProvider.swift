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

final class SnapshotReaderTTLCache: @unchecked Sendable {
    private struct Entry {
        let savedAt: Date
        let windows: [UsageWindow]?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func value(key: String, now: Date, ttl: TimeInterval) -> [UsageWindow]?? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[key] else {
            return nil
        }

        if now.timeIntervalSince(entry.savedAt) < ttl {
            return .some(entry.windows)
        }

        entries.removeValue(forKey: key)
        return nil
    }

    func store(_ windows: [UsageWindow]?, key: String, now: Date) {
        lock.lock()
        entries[key] = Entry(savedAt: now, windows: windows)
        lock.unlock()
    }
}

enum ReverseJSONLFileReader {
    enum Control {
        case `continue`
        case stop
    }

    static func scanLines(
        in fileURL: URL,
        chunkSize: Int = 16_384,
        _ body: (String) throws -> Control
    ) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        var position = Int(fileSize)
        var carry = Data()

        while position > 0 {
            let readSize = min(chunkSize, position)
            position -= readSize

            try handle.seek(toOffset: UInt64(position))
            guard let chunk = try handle.read(upToCount: readSize), !chunk.isEmpty else {
                break
            }

            var combined = Data()
            combined.reserveCapacity(chunk.count + carry.count)
            combined.append(chunk)
            combined.append(carry)

            let segments = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
            var linesToProcess: [Data] = []
            if position > 0 {
                carry = Data(segments.first ?? Data())
                var index = segments.endIndex
                while index > segments.startIndex {
                    index = segments.index(before: index)
                    if index == segments.startIndex {
                        break
                    }
                    linesToProcess.append(Data(segments[index]))
                }
            } else {
                carry.removeAll(keepingCapacity: false)
                var index = segments.endIndex
                while index > segments.startIndex {
                    index = segments.index(before: index)
                    linesToProcess.append(Data(segments[index]))
                }
            }

            for lineData in linesToProcess {
                let normalizedLine = normalizedLineString(from: lineData)
                guard !normalizedLine.isEmpty else { continue }

                if try body(normalizedLine) == .stop {
                    return
                }
            }
        }
    }

    private static func normalizedLineString(from data: Data) -> String {
        var line = String(decoding: data, as: UTF8.self)
        if line.last == "\r" {
            line.removeLast()
        }
        return line
    }
}

struct CodexConsumerSnapshot: Sendable, Equatable {
    let windows: [UsageWindow]
    let identity: ConsumerAccountIdentity?
    let tier: String?
}

enum CodexConnectionStatus: String, Sendable {
    case connecting
    case live
    case staleFallback
    case error
}

struct CodexLiveState: Sendable, Equatable {
    var snapshot: CodexConsumerSnapshot?
    var identity: ConsumerAccountIdentity?
    var status: CodexConnectionStatus
    var lastUpdateAt: Date?
    var lastErrorText: String?
}

protocol CodexLiveStateProviding: Sendable {
    func currentState() async -> CodexLiveState
}

enum CodexAppServerEvent: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    case terminated(Int32)
}

protocol CodexAppServerSession: AnyObject, Sendable {
    var events: AsyncStream<CodexAppServerEvent> { get }
    func send(jsonLine: String) throws
    func stop()
}

protocol CodexAppServerSessionFactory: Sendable {
    func makeSession() throws -> CodexAppServerSession
}

struct SystemCodexAppServerSessionFactory: CodexAppServerSessionFactory {
    func makeSession() throws -> CodexAppServerSession {
        let session = SystemCodexAppServerSession()
        try session.start()
        return session
    }
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

enum CodexAppServerPayloadParser {
    static func parseIdentity(from accountResult: [String: Any]) -> ConsumerAccountIdentity? {
        guard let account = accountResult["account"] as? [String: Any] else {
            return nil
        }

        guard let email = ProviderSupport.string(account["email"]) else {
            return nil
        }

        return ConsumerAccountIdentity(email: email, externalID: nil)
    }

    static func parseSnapshot(rateLimitResult: [String: Any], accountResult: [String: Any]? = nil) -> CodexConsumerSnapshot? {
        let identity = accountResult.flatMap(parseIdentity(from:))
        let tier = parseTier(from: rateLimitResult, accountResult: accountResult)
        let windows = parseWindows(from: rateLimitResult)
        guard !windows.isEmpty else { return nil }
        return CodexConsumerSnapshot(windows: windows, identity: identity, tier: tier)
    }

    static func parseSnapshot(notificationParams: [String: Any]) -> CodexConsumerSnapshot? {
        guard let rateLimits = notificationParams["rateLimits"] as? [String: Any] else {
            return nil
        }
        let tier = ProviderSupport.string(rateLimits["planType"])?.capitalized
        let windows = [
            makeWindow(from: rateLimits["primary"] as? [String: Any]),
            makeWindow(from: rateLimits["secondary"] as? [String: Any])
        ].compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        return CodexConsumerSnapshot(windows: windows, identity: nil, tier: tier)
    }

    private static func parseTier(from rateLimitResult: [String: Any], accountResult: [String: Any]?) -> String? {
        if let rateLimits = selectedRateLimitSnapshot(from: rateLimitResult),
           let tier = ProviderSupport.string(rateLimits["planType"]) {
            return tier.capitalized
        }

        if let account = accountResult?["account"] as? [String: Any],
           let tier = ProviderSupport.string(account["planType"]) {
            return tier.capitalized
        }

        return nil
    }

    private static func parseWindows(from rateLimitResult: [String: Any]) -> [UsageWindow] {
        guard let snapshot = selectedRateLimitSnapshot(from: rateLimitResult) else {
            return []
        }

        return [
            makeWindow(from: snapshot["primary"] as? [String: Any]),
            makeWindow(from: snapshot["secondary"] as? [String: Any])
        ].compactMap { $0 }
    }

    private static func selectedRateLimitSnapshot(from result: [String: Any]) -> [String: Any]? {
        if let byLimitID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byLimitID["codex"] as? [String: Any] {
            return codex
        }

        return result["rateLimits"] as? [String: Any]
    }

    private static func makeWindow(from limit: [String: Any]?) -> UsageWindow? {
        guard
            let limit,
            let usedPercent = ProviderSupport.double(limit["usedPercent"])
        else {
            return nil
        }

        let windowMinutes = ProviderSupport.int(limit["windowDurationMins"])
        let resetDate = unixDate(limit["resetsAt"])

        return UsageWindow(
            windowType: windowType(for: windowMinutes),
            used: min(max(usedPercent, 0), 100),
            limit: 100,
            unit: .percent,
            resetDate: resetDate,
            label: nil
        )
    }

    private static func windowType(for windowMinutes: Int?) -> WindowType {
        ProviderSupport.consumerWindowType(for: windowMinutes)
    }

    private static func unixDate(_ value: Any?) -> Date? {
        guard let timestamp = ProviderSupport.double(value) else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }
}

final class SystemCodexAppServerSession: NSObject, CodexAppServerSession, @unchecked Sendable {
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe
    private let continuation: AsyncStream<CodexAppServerEvent>.Continuation
    let events: AsyncStream<CodexAppServerEvent>
    private let stdoutLock = NSLock()
    private let stderrLock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    override init() {
        process = Process()
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()
        var streamContinuation: AsyncStream<CodexAppServerEvent>.Continuation!
        events = AsyncStream { continuation in
            streamContinuation = continuation
        }
        continuation = streamContinuation
        super.init()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server"]

        // GUI apps on macOS have a stripped PATH that doesn't include Homebrew
        // or other user-installed paths. Augment the child process environment
        // so that `env codex` can find the binary regardless of install location.
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/opt/homebrew/bin",          // Homebrew on Apple Silicon
            "/opt/homebrew/sbin",
            "/usr/local/bin",             // Homebrew on Intel / manual installs
            "/usr/local/sbin",
            (environment["HOME"] ?? "") + "/.local/bin",   // pipx / mise / etc.
            (environment["HOME"] ?? "") + "/.cargo/bin",   // cargo-installed binaries
        ].filter { !$0.isEmpty }
        let systemPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = (extraPaths + [systemPath]).joined(separator: ":")
        process.environment = environment

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, stdout: true)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.append(handle.availableData, stdout: false)
        }

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.flushBuffers()
            self.continuation.yield(.terminated(process.terminationStatus))
            self.continuation.finish()
        }

    }

    func start() throws {
        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            continuation.yield(.terminated(process.terminationStatus))
            continuation.finish()
            throw error
        }
    }

    func send(jsonLine: String) throws {
        stdinPipe.fileHandleForWriting.write(Data((jsonLine + "\n").utf8))
    }

    func stop() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func append(_ data: Data, stdout: Bool) {
        guard !data.isEmpty else { return }

        let lock = stdout ? stdoutLock : stderrLock
        lock.lock()
        defer { lock.unlock() }

        if stdout {
            stdoutBuffer.append(data)
            drainBuffer(&stdoutBuffer, eventFactory: CodexAppServerEvent.stdout)
        } else {
            stderrBuffer.append(data)
            drainBuffer(&stderrBuffer, eventFactory: CodexAppServerEvent.stderr)
        }
    }

    private func drainBuffer(_ buffer: inout Data, eventFactory: (String) -> CodexAppServerEvent) {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard !lineData.isEmpty else { continue }
            let line = String(decoding: lineData, as: UTF8.self)
            continuation.yield(eventFactory(line))
        }
    }

    private func flushBuffers() {
        stdoutLock.lock()
        if !stdoutBuffer.isEmpty {
            continuation.yield(.stdout(String(decoding: stdoutBuffer, as: UTF8.self)))
            stdoutBuffer.removeAll()
        }
        stdoutLock.unlock()

        stderrLock.lock()
        if !stderrBuffer.isEmpty {
            continuation.yield(.stderr(String(decoding: stderrBuffer, as: UTF8.self)))
            stderrBuffer.removeAll()
        }
        stderrLock.unlock()
    }
}

actor CodexAppServerClient: CodexLiveStateProviding {
    private let sessionFactory: any CodexAppServerSessionFactory
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let reconnectBackoff: [TimeInterval]

    private var state: CodexLiveState
    private var runTask: Task<Void, Never>?
    private var currentSession: CodexAppServerSession?
    private var continuations: [UUID: AsyncStream<CodexLiveState>.Continuation] = [:]
    private var reconnectRequested = false

    init(
        sessionFactory: any CodexAppServerSessionFactory = SystemCodexAppServerSessionFactory(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        reconnectBackoff: [TimeInterval] = [0, 2, 5, 10, 30]
    ) {
        self.sessionFactory = sessionFactory
        self.now = now
        self.sleep = sleep
        self.reconnectBackoff = reconnectBackoff
        self.state = CodexLiveState(
            snapshot: nil,
            identity: nil,
            status: .connecting,
            lastUpdateAt: nil,
            lastErrorText: nil
        )
    }

    func currentState() async -> CodexLiveState {
        state
    }

    func updates() -> AsyncStream<CodexLiveState> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(state)
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        currentSession?.stop()
        currentSession = nil
    }

    func requestImmediateRefresh() async {
        start()
        if let currentSession {
            try? sendBootstrapRequests(on: currentSession)
        } else {
            reconnectRequested = true
        }
    }

    func restart() {
        currentSession?.stop()
        currentSession = nil
        reconnectRequested = true
        start()
    }

    private func runLoop() async {
        var attempt = 0

        while !Task.isCancelled {
            let delay = reconnectRequested ? 0 : reconnectBackoff[min(attempt, reconnectBackoff.count - 1)]
            reconnectRequested = false

            if delay > 0 {
                await sleep(delay)
            }

            if Task.isCancelled { break }

            updateStatus(snapshot: state.snapshot, status: state.snapshot == nil ? .connecting : .staleFallback, error: state.lastErrorText)

            do {
                let session = try sessionFactory.makeSession()
                currentSession = session
                try sendBootstrapRequests(on: session)
                try await consume(session: session)
                attempt = 0
            } catch is CancellationError {
                break
            } catch {
                currentSession?.stop()
                currentSession = nil
                attempt += 1
                updateStatus(
                    snapshot: state.snapshot,
                    status: state.snapshot == nil ? .error : .staleFallback,
                    error: codexErrorText(error)
                )
            }
        }
    }

    private func consume(session: CodexAppServerSession) async throws {
        for await event in session.events {
            try Task.checkCancellation()

            switch event {
            case let .stdout(line):
                try await handleStdout(line)
            case let .stderr(line):
                await handleStderr(line)
            case let .terminated(code):
                throw ServiceProviderError.unavailable("Codex app-server terminated with status \(code).")
            }
        }

        throw ServiceProviderError.unavailable("Codex app-server stream ended unexpectedly.")
    }

    private func sendBootstrapRequests(on session: CodexAppServerSession) throws {
        try session.send(jsonLine: Self.jsonLine([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "TokenGuard",
                    "version": "1.0"
                ],
                "capabilities": NSNull()
            ]
        ]))

        try session.send(jsonLine: Self.jsonLine([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "account/read",
            "params": [
                "refreshToken": true
            ]
        ]))

        try session.send(jsonLine: Self.jsonLine([
            "jsonrpc": "2.0",
            "id": 3,
            "method": "account/rateLimits/read",
            "params": NSNull()
        ]))
    }

    private func handleStdout(_ line: String) async throws {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data),
              let object = payload as? [String: Any] else {
            return
        }

        if let id = ProviderSupport.int(object["id"]),
           let result = object["result"] as? [String: Any] {
            if id == 2 {
                state.identity = CodexAppServerPayloadParser.parseIdentity(from: result)
                publish()
                return
            }

            if id == 3,
               let snapshot = CodexAppServerPayloadParser.parseSnapshot(rateLimitResult: result) {
                state.snapshot = CodexConsumerSnapshot(
                    windows: snapshot.windows,
                    identity: state.identity ?? snapshot.identity,
                    tier: snapshot.tier
                )
                state.status = .live
                state.lastUpdateAt = now()
                state.lastErrorText = nil
                publish()
            }
            return
        }

        if let method = ProviderSupport.string(object["method"]),
           let params = object["params"] as? [String: Any] {
            switch method {
            case "account/rateLimits/updated":
                if let snapshot = CodexAppServerPayloadParser.parseSnapshot(notificationParams: params) {
                    state.snapshot = CodexConsumerSnapshot(
                        windows: snapshot.windows,
                        identity: state.identity ?? snapshot.identity,
                        tier: snapshot.tier
                    )
                    state.status = .live
                    state.lastUpdateAt = now()
                    state.lastErrorText = nil
                    publish()
                }
            case "account/updated":
                if let planType = ProviderSupport.string(params["planType"]),
                   let snapshot = state.snapshot {
                    state.snapshot = CodexConsumerSnapshot(
                        windows: snapshot.windows,
                        identity: snapshot.identity ?? state.identity,
                        tier: planType.capitalized
                    )
                    publish()
                }
            default:
                break
            }
        }
    }

    private func handleStderr(_ line: String) async {
        guard !line.isEmpty else { return }
        if line.contains("failed to sync curated plugins repo") || line.contains("plugins::startup_sync") {
            return
        }

        state.lastErrorText = line
        publish()
    }

    private func updateStatus(snapshot: CodexConsumerSnapshot?, status: CodexConnectionStatus, error: String?) {
        state.snapshot = snapshot
        state.status = status
        state.lastErrorText = error
        publish()
    }

    private func publish() {
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func codexErrorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
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
    private let now: @Sendable () -> Date
    private let cache: SnapshotReaderTTLCache
    private let cacheTTL: TimeInterval

    init(
        rootDirectoryURL: URL = URL(fileURLWithPath: NSString(string: "~/.codex/sessions").expandingTildeInPath),
        now: @escaping @Sendable () -> Date = Date.init,
        cache: SnapshotReaderTTLCache = SnapshotReaderTTLCache(),
        cacheTTL: TimeInterval = 30
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.now = now
        self.cache = cache
        self.cacheTTL = cacheTTL
    }

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        guard serviceType == .codex else {
            return nil
        }

        let currentTime = now()
        let cacheKey = "\(serviceType.rawValue):\(rootDirectoryURL.path)"
        if let cached = cache.value(key: cacheKey, now: currentTime, ttl: cacheTTL) {
            return cached
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
        var latest: TimestampedWindows?
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if let parsed = try? windows(from: fileURL, fallbackTimestamp: values.contentModificationDate ?? .distantPast) {
                if latest == nil || parsed.timestamp > latest!.timestamp {
                    latest = parsed
                }
            }
        }

        let result = latest?.windows
        cache.store(result, key: cacheKey, now: currentTime)
        return result
    }

    private func windows(from fileURL: URL, fallbackTimestamp: Date) throws -> TimestampedWindows? {
        var latest: TimestampedWindows?

        try ReverseJSONLFileReader.scanLines(in: fileURL) { line in
            guard let lineData = line.data(using: .utf8) else {
                return .continue
            }
            guard let payload = try? JSONSerialization.jsonObject(with: lineData) else {
                return .continue
            }
            guard
                let object = payload as? [String: Any],
                ProviderSupport.string(object["type"]) == "event_msg",
                let message = object["payload"] as? [String: Any],
                ProviderSupport.string(message["type"]) == "token_count",
                let rateLimits = message["rate_limits"] as? [String: Any]
            else {
                return .continue
            }

            let windows = windows(from: rateLimits)
            guard !windows.isEmpty else {
                return .continue
            }

            let timestamp = ProviderSupport.isoDate(object["timestamp"]) ?? fallbackTimestamp
            latest = TimestampedWindows(timestamp: timestamp, windows: windows)
            return .stop
        }

        return latest
    }

    private func windows(from rateLimits: [String: Any]) -> [UsageWindow] {
        let nestedWindows = ["primary", "secondary", "tertiary"].compactMap { key in
            makeWindow(from: rateLimits[key] as? [String: Any])
        }
        if !nestedWindows.isEmpty {
            return nestedWindows
        }

        let flattenedWindows = [
            makeFlattenedWindow(prefix: "primary", from: rateLimits),
            makeFlattenedWindow(prefix: "secondary", from: rateLimits),
            makeFlattenedWindow(prefix: "tertiary", from: rateLimits)
        ].compactMap { $0 }

        return flattenedWindows
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

    private func makeFlattenedWindow(prefix: String, from rateLimits: [String: Any]) -> UsageWindow? {
        guard let usedPercent = ProviderSupport.double(rateLimits["\(prefix)_used_percent"]) else {
            return nil
        }

        let resetDate = unixDate(rateLimits["\(prefix)_resets_at"])
        let windowMinutes = ProviderSupport.int(rateLimits["\(prefix)_window_minutes"])

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
        ProviderSupport.consumerWindowType(for: windowMinutes)
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
        ProviderSupport.consumerWindowType(for: windowMinutes)
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
    static func consumerWindowType(for windowMinutes: Int?) -> WindowType {
        guard let windowMinutes else {
            return .monthly
        }

        switch windowMinutes {
        case 295...305:
            return .rolling5h
        case 1_435...1_445:
            return .daily
        case 10_075...10_085:
            return .weekly
        default:
            return .monthly
        }
    }

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
