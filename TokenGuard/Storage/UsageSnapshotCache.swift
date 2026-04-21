import Foundation

struct UsageSnapshotCache {
    private static let storageDirectoryName = "TokenGuard"
    private static let legacyStorageDirectoryName = "UsageTool"

    private let storageDirectoryURL: URL
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
        self.storageDirectoryURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)

        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> [UUID: UsageSnapshot] {
        try migrateLegacyFileIfNeeded()

        guard directoryExists(at: storageDirectoryURL) else {
            return [:]
        }

        var snapshots: [UUID: UsageSnapshot] = [:]
        let enumerator = fileManager.enumerator(
            at: storageDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "json" else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard let accountID = UUID(uuidString: fileURL.deletingPathExtension().lastPathComponent) else {
                continue
            }
            let data = try Data(contentsOf: fileURL)
            snapshots[accountID] = try decoder.decode(UsageSnapshot.self, from: data)
        }

        return snapshots
    }

    func save(snapshot: UsageSnapshot) throws {
        try migrateLegacyFileIfNeeded()
        try ensureDirectoryExists()

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.accountId), options: .atomic)
    }

    func remove(accountID: UUID) throws {
        try migrateLegacyFileIfNeeded()
        let snapshotURL = fileURL(for: accountID)

        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        try fileManager.removeItem(at: snapshotURL)
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
    }

    private func fileURL(for accountID: UUID) -> URL {
        storageDirectoryURL.appendingPathComponent(accountID.uuidString).appendingPathExtension("json")
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let storageDirectory = appSupport.appendingPathComponent(storageDirectoryName, isDirectory: true)
        return storageDirectory.appendingPathComponent("usage-snapshots", isDirectory: true)
    }

    private func migrateLegacyFileIfNeeded() throws {
        if directoryExists(at: storageDirectoryURL) {
            return
        }

        let legacyCandidates = legacyFileCandidates()
        guard let legacyFileURL = legacyCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return
        }

        let data = try Data(contentsOf: legacyFileURL)
        let raw = try decoder.decode([String: UsageSnapshot].self, from: data)

        try fileManager.removeItem(at: legacyFileURL)
        try ensureDirectoryExists()

        for (key, snapshot) in raw {
            guard let accountID = UUID(uuidString: key) else { continue }
            let snapshotData = try encoder.encode(snapshot)
            try snapshotData.write(to: fileURL(for: accountID), options: .atomic)
        }
    }

    private func legacyFileCandidates() -> [URL] {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let currentLegacyURL = appSupport
            .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
            .appendingPathComponent("usage-snapshots.json", isDirectory: false)
        let oldAppURL = appSupport
            .appendingPathComponent(Self.legacyStorageDirectoryName, isDirectory: true)
            .appendingPathComponent("usage-snapshots.json", isDirectory: false)
        return [storageDirectoryURL, currentLegacyURL, oldAppURL]
    }
}
