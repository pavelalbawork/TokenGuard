import Foundation

struct CodexCLIParser: CLIParser {
    private let runner: any CommandRunning
    private let now: @Sendable () -> Date

    init(
        runner: any CommandRunning = SystemCommandRunner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runner = runner
        self.now = now
    }

    func parseUsageOutput() async throws -> [UsageWindow] {
        let output = try await runner.run("codex", arguments: ["/status"])
        return try UsageWindowTextParser.parse(output: output, now: now())
    }
}
