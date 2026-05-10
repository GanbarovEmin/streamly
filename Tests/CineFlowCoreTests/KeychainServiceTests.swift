import XCTest
@testable import CineFlowCore

final class KeychainServiceTests: XCTestCase {
    func testMockKeychainServiceSupportsCredentialLifecycleAndCredentialKinds() async throws {
        let keychain = MockKeychainService()
        let sourceCredential = KeychainCredential(
            accountID: "source:rutracker",
            kind: .sourceLoginPassword,
            sourceID: "rutracker",
            username: "user",
            password: "secret-password"
        )

        let keychainID = try await keychain.saveCredential(sourceCredential)
        let stored = try await keychain.readCredential(accountID: sourceCredential.accountID)

        XCTAssertEqual(keychainID, "mock-keychain:source:rutracker")
        XCTAssertEqual(stored, sourceCredential)

        var updated = sourceCredential
        updated.password = "updated-password"
        updated.token = "session-token"
        try await keychain.updateCredential(updated)

        let updatedStored = try await keychain.readCredential(accountID: sourceCredential.accountID)
        XCTAssertEqual(updatedStored?.password, "updated-password")
        XCTAssertEqual(updatedStored?.token, "session-token")

        let supportedKinds: [KeychainCredentialKind] = [
            .sourceLoginPassword,
            .sourceSessionCookies,
            .apiToken,
            .openSubtitles,
            .futureSync
        ]
        XCTAssertEqual(Set(supportedKinds), Set(KeychainCredentialKind.allCases))

        try await keychain.deleteCredential(accountID: sourceCredential.accountID)
        let deletedSourceCredential = try await keychain.readCredential(accountID: sourceCredential.accountID)
        XCTAssertNil(deletedSourceCredential)

        _ = try await keychain.saveCredential(KeychainCredential(accountID: "api:tmdb", kind: .apiToken, token: "api-secret"))
        _ = try await keychain.saveCredential(KeychainCredential(accountID: "subtitles:opensubtitles", kind: .openSubtitles, username: "sub", password: "sub-secret"))
        try await keychain.deleteAllCineFlowCredentials()

        let deletedAPIToken = try await keychain.readCredential(accountID: "api:tmdb")
        let deletedOpenSubtitles = try await keychain.readCredential(accountID: "subtitles:opensubtitles")
        XCTAssertNil(deletedAPIToken)
        XCTAssertNil(deletedOpenSubtitles)
    }
}
