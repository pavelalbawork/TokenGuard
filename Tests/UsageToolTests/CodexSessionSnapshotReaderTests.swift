import Foundation
import XCTest
@testable import UsageTool

final class CodexSessionSnapshotReaderTests: XCTestCase {
    func testUsesNewestTokenCountEventAcrossAllSessionFiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let olderFile = tempDirectory.appendingPathComponent("older.jsonl")
        let newerFile = tempDirectory.appendingPathComponent("newer.jsonl")

        try """
        {"timestamp":"2026-04-06T20:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":30.0,"window_minutes":10080,"resets_at":1775754682}}}}
        """.write(to: olderFile, atomically: true, encoding: .utf8)

        try """
        {"timestamp":"2026-04-07T02:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":72.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":68.0,"window_minutes":10080,"resets_at":1775754682}}}}
        """.write(to: newerFile, atomically: true, encoding: .utf8)

        let reader = CodexSessionSnapshotReader(rootDirectoryURL: tempDirectory)
        let windows = try XCTUnwrap(reader.windows(for: .codex))

        XCTAssertEqual(windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 72, accuracy: 0.1)
        XCTAssertEqual(windows.first(where: { $0.windowType == .weekly })?.used ?? -1, 68, accuracy: 0.1)
    }
}
