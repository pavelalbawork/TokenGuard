import XCTest
@testable import TokenGuard

final class KeychainManagerTests: XCTestCase {
    func testSaveReadUpdateDeleteCredential() throws {
        let backingStore = InMemoryKeychainBackingStore()
        let keychain = KeychainManager(serviceName: "test.credentials", backingStore: backingStore)

        try keychain.saveSecret("first-token", reference: "openai-work")
        XCTAssertEqual(try keychain.readSecret(reference: "openai-work"), "first-token")

        try keychain.saveSecret("updated-token", reference: "openai-work")
        XCTAssertEqual(try keychain.readSecret(reference: "openai-work"), "updated-token")

        try keychain.deleteSecret(reference: "openai-work")
        XCTAssertNil(try keychain.readSecret(reference: "openai-work"))
    }

    func testReadsAndMigratesLegacyCredentialService() throws {
        let backingStore = InMemoryKeychainBackingStore()
        let legacyKeychain = KeychainManager(
            serviceName: "legacy.credentials",
            legacyServiceNames: [],
            backingStore: backingStore
        )
        try legacyKeychain.saveSecret("legacy-token", reference: "codex-work")

        let keychain = KeychainManager(
            serviceName: "current.credentials",
            legacyServiceNames: ["legacy.credentials"],
            backingStore: backingStore
        )

        XCTAssertEqual(try keychain.readSecret(reference: "codex-work"), "legacy-token")
        XCTAssertEqual(try keychain.readSecret(reference: "codex-work"), "legacy-token")
    }
}
