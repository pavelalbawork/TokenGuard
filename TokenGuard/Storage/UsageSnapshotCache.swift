import Foundation

struct UsageSnapshotCache {
    private static let storageDirectoryName = "TokenGuard"
    private static let legacyStorageDirectoryName = "UsageTool"

    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)

        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [UUID: UsageSnapshot] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: storageURL)
        let raw = try decoder.decode([String: UsageSnapshot].self, from: data)
        var snapshots: [UUID: UsageSnapshot] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) {
                snapshots[id] = value
            }
        }
        return snapshots
    }

    func save(snapshot: UsageSnapshot) throws {
        var snapshots = try loadRaw()
        snapshots[snapshot.accountId.uuidString] = snapshot
        try persist(raw: snapshots)
    }

    func remove(accountID: UUID) throws {
        var snapshots = try loadRaw()
        snapshots.removeValue(forKey: accountID.uuidString)
        try persist(raw: snapshots)
    }

    private func loadRaw() throws -> [String: UsageSnapshot] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: storageURL)
        return try decoder.decode([String: UsageSnapshot].self, from: data)
    }

    private func persist(raw: [String: UsageSnapshot]) throws {
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(raw)
        try data.write(to: storageURL, options: .atomic)
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let storageDirectory = appSupport.appendingPathComponent(storageDirectoryName, isDirectory: true)
        let storageURL = storageDirectory.appendingPathComponent("usage-snapshots.json", isDirectory: false)
        let legacyURL = appSupport
            .appendingPathComponent(legacyStorageDirectoryName, isDirectory: true)
            .appendingPathComponent("usage-snapshots.json", isDirectory: false)

        migrateLegacyFileIfNeeded(from: legacyURL, to: storageURL, fileManager: fileManager)
        return storageURL
    }

    private static func migrateLegacyFileIfNeeded(from legacyURL: URL, to storageURL: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: storageURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacyURL, to: storageURL)
        } catch {
            try? fileManager.copyItem(at: legacyURL, to: storageURL)
        }
    }
}
