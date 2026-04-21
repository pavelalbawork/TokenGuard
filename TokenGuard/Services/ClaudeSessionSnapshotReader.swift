import Foundation

/// Reads token usage directly from Claude Code's session JSONL files stored under
/// `~/.claude/projects/`.  Every `assistant` entry in those files records the exact
/// token counts returned by the Anthropic API, so we can aggregate rolling 5-hour
/// and 7-day totals without relying on CodexBar or any other external application.
///
/// File layout (per session):
/// ```
/// ~/.claude/projects/{sanitised-path}/{session-uuid}.jsonl
/// ~/.claude/projects/{sanitised-path}/{session-uuid}/subagents/{agent}.jsonl
/// ```
/// Each line is a JSON object; we only count lines where `type == "assistant"`,
/// `message.model != "<synthetic>"`, and `message.usage` contains real token counts.
struct ClaudeSessionSnapshotReader: ConsumerUsageSnapshotReading {
    private let rootDirectoryURL: URL
    private let now: @Sendable () -> Date
    private let cache: SnapshotReaderTTLCache
    private let cacheTTL: TimeInterval

    init(
        rootDirectoryURL: URL = URL(fileURLWithPath:
            NSString(string: "~/.claude/projects").expandingTildeInPath),
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
        guard serviceType == .claude else { return nil }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else { return nil }

        let currentTime = now()
        let cacheKey = "\(serviceType.rawValue):\(rootDirectoryURL.path)"
        if let cached = cache.value(key: cacheKey, now: currentTime, ttl: cacheTTL) {
            return cached
        }

        let cutoff5h = currentTime.addingTimeInterval(-5 * 3600)
        let cutoff7d  = currentTime.addingTimeInterval(-7 * 24 * 3600)

        // Enumerate every JSONL file under the projects tree.
        let enumerator = fileManager.enumerator(
            at: rootDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var sessionFiles: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "jsonl" else { continue }
            let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            // Quick pre-filter: skip files not touched in the last 7 days.
            guard modified >= cutoff7d else { continue }
            sessionFiles.append(fileURL)
        }

        var tokens5h: Double = 0
        var tokens7d: Double  = 0

        for fileURL in sessionFiles {
            try accumulateRecentUsage(
                from: fileURL,
                cutoff5h: cutoff5h,
                cutoff7d: cutoff7d,
                tokens5h: &tokens5h,
                tokens7d: &tokens7d
            )
        }

        guard tokens7d > 0 else {
            cache.store(nil, key: cacheKey, now: currentTime)
            return nil
        }

        let result = [
            UsageWindow(
                windowType: .rolling5h,
                used: tokens5h,
                limit: nil,
                unit: .tokens,
                resetDate: nil,
                label: "5-hour tokens"
            ),
            UsageWindow(
                windowType: .weekly,
                used: tokens7d,
                limit: nil,
                unit: .tokens,
                resetDate: nil,
                label: "7-day tokens"
            )
        ]
        cache.store(result, key: cacheKey, now: currentTime)
        return result
    }

    // MARK: - Private

    private func accumulateRecentUsage(
        from fileURL: URL,
        cutoff5h: Date,
        cutoff7d: Date,
        tokens5h: inout Double,
        tokens7d: inout Double
    ) throws {
        try ReverseJSONLFileReader.scanLines(in: fileURL) { line in
            accumulate(
                line: line,
                cutoff5h: cutoff5h,
                cutoff7d: cutoff7d,
                tokens5h: &tokens5h,
                tokens7d: &tokens7d
            )
        }
    }

    private func accumulate(
        line: String,
        cutoff5h: Date,
        cutoff7d: Date,
        tokens5h: inout Double,
        tokens7d: inout Double
    ) -> ReverseJSONLFileReader.Control {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return .continue }

        guard let timestampStr = json["timestamp"] as? String,
              let timestamp = ProviderSupport.isoDate(timestampStr) else {
            return .continue
        }

        if timestamp < cutoff7d {
            return .stop
        }

        // Only count assistant entries that came from real API calls.
        guard json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return .continue }

        // "<synthetic>" entries are compact/summarised recaps — skip them.
        if let model = message["model"] as? String, model == "<synthetic>" { return .continue }

        let count = tokenCount(from: usage)
        guard count > 0 else { return .continue }

        if timestamp >= cutoff7d { tokens7d  += count }
        if timestamp >= cutoff5h { tokens5h += count }
        return .continue
    }

    /// Sum all token dimensions that represent real Anthropic API processing.
    private func tokenCount(from usage: [String: Any]) -> Double {
        var total = 0.0
        total += ProviderSupport.double(usage["input_tokens"])                  ?? 0
        total += ProviderSupport.double(usage["output_tokens"])                 ?? 0
        total += ProviderSupport.double(usage["cache_creation_input_tokens"])   ?? 0
        total += ProviderSupport.double(usage["cache_read_input_tokens"])       ?? 0
        return total
    }
}
