import Foundation

/// The `claude /usage` slash command was removed from the Claude CLI (it now returns
/// "Unknown skill: usage").  This parser is kept as a stub so the injection points
/// compile, but it always returns an empty array so the caller falls through to the
/// CodexBar widget-snapshot reader, which is the real consumer data source.
struct ClaudeCodeCLIParser: CLIParser {
    init() {}

    func parseUsageOutput() async throws -> [UsageWindow] {
        return []
    }
}
