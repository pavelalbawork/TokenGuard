import Foundation

protocol CLIParser: Sendable {
    func parseUsageOutput() async throws -> [UsageWindow]
}

protocol CommandRunning: Sendable {
    func run(_ command: String, arguments: [String]) async throws -> String
}

enum CLIParserError: LocalizedError, Equatable, Sendable {
    case commandFailed(String)
    case noWindowsFound

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            return message
        case .noWindowsFound:
            return "The CLI output did not contain any recognizable usage windows."
        }
    }
}

struct SystemCommandRunner: CommandRunning {
    func run(_ command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: CLIParserError.commandFailed(stderr.isEmpty ? stdout : stderr))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum UsageWindowTextParser {
    static func parse(output: String, now: Date = Date()) throws -> [UsageWindow] {
        let windows = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> UsageWindow? in
                let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return parse(line: text, now: now)
            }

        guard !windows.isEmpty else {
            throw CLIParserError.noWindowsFound
        }

        return windows
    }

    private static func parse(line: String, now: Date) -> UsageWindow? {
        let lowercased = line.lowercased()
        guard let windowType = windowType(in: lowercased) else { return nil }

        let values = usedLimit(in: line)
        let unit = usageUnit(in: lowercased)
        let resetDate = resetDate(in: lowercased, now: now)

        if values.used == nil, values.limit == nil {
            return UsageWindow(
                windowType: windowType,
                used: 0,
                limit: nil,
                unit: unit,
                resetDate: resetDate,
                label: windowType.defaultLabel
            )
        }

        return UsageWindow(
            windowType: windowType,
            used: values.used ?? 0,
            limit: values.limit,
            unit: unit,
            resetDate: resetDate,
            label: windowType.defaultLabel
        )
    }

    private static func windowType(in line: String) -> WindowType? {
        if line.contains("5h") || line.contains("5-hour") || line.contains("5 hour") || line.contains("rolling") {
            return .rolling5h
        }
        if line.contains("weekly") || line.contains("week") || line.contains("wk") {
            return .weekly
        }
        if line.contains("monthly") || line.contains("month") || line.contains("mo") {
            return .monthly
        }
        if line.contains("daily") || line.contains("day") || line.contains("rpd") {
            return .daily
        }
        return nil
    }

    private static func usageUnit(in line: String) -> UsageUnit {
        if line.contains("$") || line.contains("usd") || line.contains("dollar") {
            return .dollars
        }
        if line.contains("message") || line.contains("msg") {
            return .messages
        }
        if line.contains("credit") {
            return .credits
        }
        if line.contains("request") || line.contains("req") {
            return .requests
        }
        return .tokens
    }

    private static func usedLimit(in line: String) -> (used: Double?, limit: Double?) {
        let pattern = #"([$]?[0-9][0-9,]*(?:\.[0-9]+)?)\s*/\s*([$]?[0-9][0-9,]*(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (nil, nil)
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let usedRange = Range(match.range(at: 1), in: line),
              let limitRange = Range(match.range(at: 2), in: line) else {
            return (nil, nil)
        }

        return (parseNumber(String(line[usedRange])), parseNumber(String(line[limitRange])))
    }

    private static func parseNumber(_ text: String) -> Double? {
        let filtered = text
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(filtered)
    }

    private static func resetDate(in line: String, now: Date) -> Date? {
        if let range = line.range(of: "resets in ") {
            let tail = String(line[range.upperBound...])
            let hours = capture(#"([0-9]+)\s*h"#, in: tail).flatMap(Int.init) ?? 0
            let minutes = capture(#"([0-9]+)\s*m"#, in: tail).flatMap(Int.init) ?? 0
            let days = capture(#"([0-9]+)\s*d"#, in: tail).flatMap(Int.init) ?? 0
            let total = TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60)
            return total > 0 ? now.addingTimeInterval(total) : nil
        }

        if let weekdayName = capture(#"resets\s+(mon|tue|wed|thu|fri|sat|sun)"#, in: line) {
            let weekdayMap = [
                "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7
            ]
            return ProviderSupport.nextWeeklyResetDate(weekday: weekdayMap[weekdayName], hourUTC: 0, from: now)
        }

        return nil
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange]).lowercased()
    }
}
