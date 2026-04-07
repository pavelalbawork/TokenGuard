import XCTest
@testable import UsageTool

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
}
