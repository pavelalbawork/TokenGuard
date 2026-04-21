import Foundation
import XCTest
@testable import TokenGuard

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

    func testSkipsMalformedSessionFiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let malformedFile = tempDirectory.appendingPathComponent("malformed.jsonl")
        let validFile = tempDirectory.appendingPathComponent("valid.jsonl")

        try """
        {"timestamp":"2026-02-27T17:48:52.624Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"broken
        """.write(to: malformedFile, atomically: true, encoding: .utf8)

        try """
        {"timestamp":"2026-04-07T02:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":72.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":68.0,"window_minutes":10080,"resets_at":1775754682}}}}
        """.write(to: validFile, atomically: true, encoding: .utf8)

        let reader = CodexSessionSnapshotReader(rootDirectoryURL: tempDirectory)
        let windows = try XCTUnwrap(reader.windows(for: .codex))

        XCTAssertEqual(windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 72, accuracy: 0.1)
        XCTAssertEqual(windows.first(where: { $0.windowType == .weekly })?.used ?? -1, 68, accuracy: 0.1)
    }

    func testParsesFlattenedRateLimitShapeWithOffByOneWindowMinutes() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sessionFile = tempDirectory.appendingPathComponent("flattened.jsonl")

        try """
        {"timestamp":"2026-04-11T02:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary_used_percent":41.0,"secondary_used_percent":68.0,"primary_to_secondary_ratio_percent":60.29,"primary_window_minutes":299,"secondary_window_minutes":10079}}}
        """.write(to: sessionFile, atomically: true, encoding: .utf8)

        let reader = CodexSessionSnapshotReader(rootDirectoryURL: tempDirectory)
        let windows = try XCTUnwrap(reader.windows(for: .codex))

        XCTAssertEqual(windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 41, accuracy: 0.1)
        XCTAssertEqual(windows.first(where: { $0.windowType == .weekly })?.used ?? -1, 68, accuracy: 0.1)
    }

    func testUsesLatestTokenCountEvenWhenTrailingNonUsageEventsExist() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sessionFile = tempDirectory.appendingPathComponent("session.jsonl")

        try """
        {"timestamp":"2026-04-11T01:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":18.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":25.0,"window_minutes":10080,"resets_at":1775754682}}}}
        {"timestamp":"2026-04-11T02:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":44.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":61.0,"window_minutes":10080,"resets_at":1775754682}}}}
        {"timestamp":"2026-04-11T02:52:23.820Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"done"}]}}
        """.write(to: sessionFile, atomically: true, encoding: .utf8)

        let reader = CodexSessionSnapshotReader(rootDirectoryURL: tempDirectory)
        let windows = try XCTUnwrap(reader.windows(for: .codex))

        XCTAssertEqual(windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 44, accuracy: 0.1)
        XCTAssertEqual(windows.first(where: { $0.windowType == .weekly })?.used ?? -1, 61, accuracy: 0.1)
    }

    func testIgnoresSessionSnapshotsOlderThanCurrentAuthState() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let authFile = tempDirectory.appendingPathComponent("auth.json")
        let sessionFile = tempDirectory.appendingPathComponent("session.jsonl")

        try "{}".write(to: authFile, atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-03-11T02:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":44.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":61.0,"window_minutes":10080,"resets_at":1775754682}}}}
        """.write(to: sessionFile, atomically: true, encoding: .utf8)

        let fileManager = FileManager.default
        let sessionDate = Date(timeIntervalSince1970: 1_775_000_000)
        let authDate = sessionDate.addingTimeInterval(120)
        try fileManager.setAttributes([.modificationDate: sessionDate], ofItemAtPath: sessionFile.path)
        try fileManager.setAttributes([.modificationDate: authDate], ofItemAtPath: authFile.path)

        let reader = CodexSessionSnapshotReader(rootDirectoryURL: tempDirectory, authURL: authFile)

        XCTAssertNil(try reader.windows(for: .codex))
    }

    func testUsesSessionSnapshotsWrittenAfterCurrentAuthState() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let authFile = tempDirectory.appendingPathComponent("auth.json")
        let sessionFile = tempDirectory.appendingPathComponent("session.jsonl")

        try "{}".write(to: authFile, atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-04-11T03:51:23.820Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":27.0,"window_minutes":300,"resets_at":1775542206},"secondary":{"used_percent":39.0,"window_minutes":10080,"resets_at":1775754682}}}}
        """.write(to: sessionFile, atomically: true, encoding: .utf8)

        let fileManager = FileManager.default
        let authDate = Date(timeIntervalSince1970: 1_775_000_000)
        let sessionDate = authDate.addingTimeInterval(120)
        try fileManager.setAttributes([.modificationDate: authDate], ofItemAtPath: authFile.path)
        try fileManager.setAttributes([.modificationDate: sessionDate], ofItemAtPath: sessionFile.path)

        let reader = CodexSessionSnapshotReader(rootDirectoryURL: tempDirectory, authURL: authFile)
        let windows = try XCTUnwrap(reader.windows(for: .codex))

        XCTAssertEqual(windows.first(where: { $0.windowType == .rolling5h })?.used ?? -1, 27, accuracy: 0.1)
        XCTAssertEqual(windows.first(where: { $0.windowType == .weekly })?.used ?? -1, 39, accuracy: 0.1)
    }
}
