import CineFlowCore
import XCTest
@testable import CineFlowSources

final class SourceProviderArchitectureTests: XCTestCase {
    func testAggregatorQueriesEnabledSourcesAndRanksAfterAggregation() async throws {
        let archive = MockTorrentSourceProvider(
            sourceId: "archive",
            displayName: "Archive",
            releases: [
                TorrentRelease(id: "archive-1080p", sourceId: "wrong", sourceName: "Wrong", title: "Matrix 1080p", quality: .fullHD, seeders: 2_000),
                TorrentRelease(id: "archive-2160p", sourceId: "wrong", sourceName: "Wrong", title: "Matrix 2160p", quality: .ultraHD, seeders: 10)
            ]
        )
        let disabled = MockTorrentSourceProvider(
            sourceId: "disabled",
            displayName: "Disabled",
            releases: [
                TorrentRelease(id: "disabled-2160p", title: "Matrix disabled", quality: .ultraHD, seeders: 9_000)
            ]
        )
        let manager = SourceManager(
            providers: [archive, disabled],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        try await manager.setSourceEnabled(false, sourceId: "disabled")

        let result = try await TorrentSearchAggregator(sourceManager: manager).search(query: "matrix")

        XCTAssertEqual(result.rankedReleases.map(\.release.id), ["archive-2160p", "archive-1080p"])
        XCTAssertEqual(result.rankedReleases.map(\.release.sourceId), ["archive", "archive"])
        XCTAssertEqual(result.rankedReleases.map(\.release.sourceName), ["Archive", "Archive"])
        XCTAssertGreaterThan(result.rankedReleases[0].score, result.rankedReleases[1].score)
        XCTAssertTrue(result.sourceErrors.isEmpty)
    }

    func testSourceManagerSettingsEnableAndDisableSources() async throws {
        let manager = SourceManager(
            providers: [MockTorrentSourceProvider()],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )

        let initiallyActiveProviderIds = try await manager.activeProviders().map(\.sourceId)
        XCTAssertEqual(initiallyActiveProviderIds, ["mock"])

        try await manager.setSourceEnabled(false, sourceId: "mock")

        let activeProviderIds = try await manager.activeProviders().map(\.sourceId)
        let settings = try await manager.settings(for: "mock")
        XCTAssertTrue(activeProviderIds.isEmpty)
        XCTAssertEqual(settings.isEnabled, false)
    }

    func testFeatureFlagsControlConcreteProviderRegistration() {
        let catalog = SourceProviderCatalog.providers(
            featureFlags: SourceProviderFeatureFlags(
                mockProvider: true,
                rutorProvider: false,
                ruTrackerProvider: true
            )
        )

        XCTAssertEqual(catalog.providerNames, ["Mock Source Provider", "RuTracker"])
        XCTAssertEqual(catalog.providerIds, ["mock", "rutracker"])
    }

    func testAuthenticationStoresSecretsInCredentialStoreAndSettingsKeepOnlyKeychainReference() async throws {
        let credentialStore = InMemorySourceCredentialStore()
        let manager = SourceManager(
            providers: [
                MockTorrentSourceProvider(sourceId: "account", displayName: "Account Source", requiresAuthentication: true)
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: credentialStore
        )
        let credentials = SourceCredentials(username: "user", password: "secret-password")

        try await manager.authenticate(sourceId: "account", credentials: credentials)

        let settings = try await manager.settings(for: "account")
        let storedCredentials = try await credentialStore.credentials(for: "account")

        XCTAssertEqual(settings.authenticationStatus, .authenticated(username: "user"))
        XCTAssertEqual(settings.credentialKeychainID, "memory:account")
        XCTAssertEqual(storedCredentials, credentials)
        XCTAssertFalse(String(describing: settings).contains("secret-password"))
    }

    func testSourceCredentialStoreUsesKeychainServiceWithoutExposingSecretsInSettings() async throws {
        let keychain = MockKeychainService()
        let credentialStore = KeychainSourceCredentialStore(keychainService: keychain)
        let manager = SourceManager(
            providers: [
                MockTorrentSourceProvider(sourceId: "private", displayName: "Private Source", requiresAuthentication: true)
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: credentialStore
        )

        try await manager.authenticate(
            sourceId: "private",
            credentials: SourceCredentials(
                username: "source-user",
                password: "source-password",
                token: "source-token",
                cookies: ["session": "cookie-secret"]
            )
        )

        let settings = try await manager.settings(for: "private")
        let keychainCredential = try await keychain.readCredential(accountID: "source:private")

        XCTAssertEqual(settings.credentialKeychainID, "mock-keychain:source:private")
        XCTAssertEqual(settings.authenticationStatus, .authenticated(username: "source-user"))
        XCTAssertEqual(keychainCredential?.password, "source-password")
        XCTAssertEqual(keychainCredential?.token, "source-token")
        XCTAssertEqual(keychainCredential?.cookies["session"], "cookie-secret")
        XCTAssertFalse(String(describing: settings).contains("source-password"))
        XCTAssertFalse(String(describing: settings).contains("source-token"))
        XCTAssertFalse(String(describing: settings).contains("cookie-secret"))
    }
}
