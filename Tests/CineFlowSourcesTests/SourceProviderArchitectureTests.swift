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

    func testTorrentioConfigurationURLBuilderUsesConfiguredStremioPath() throws {
        let settings = TorrentioSettings(
            providers: [.rutor, .rutracker],
            priorityLanguage: .russian,
            excludedQualities: [.screener, .cam],
            resultLimit: 10
        )

        let url = try TorrentioConfigurationURLBuilder().streamURL(
            type: .movie,
            id: "tt0133093",
            settings: settings
        )

        XCTAssertEqual(
            url.path,
            "/providers=rutor,rutracker|language=russian|qualityfilter=scr,cam|limit=10/stream/movie/tt0133093.json"
        )
    }

    func testTorrentioStreamResponseNormalizesIntoTorrentRelease() throws {
        let json = """
        {
          "streams": [
            {
              "name": "Torrentio\\n4k DV | HDR",
              "title": "The Matrix 1999 WEB-DL 2160p H265 DV HDR\\n👤 14 💾 18.45 GB ⚙️ Rutracker\\n🇬🇧 / 🇷🇺",
              "infoHash": "61065ea115b7cc3e8db9fb5ab1f6f327f08bd1c9",
              "fileIdx": 0,
              "behaviorHints": {
                "bingeGroup": "torrentio|4k|WEB-DL|h265|DV|HDR",
                "filename": "The.Matrix.1999.WEB-DL.2160p.mkv"
              },
              "sources": [
                "tracker:http://bt4.t-ru.org/ann?magnet",
                "dht:61065ea115b7cc3e8db9fb5ab1f6f327f08bd1c9",
                "tracker:udp://tracker.opentrackr.org:1337/announce"
              ]
            }
          ]
        }
        """
        let response = try JSONDecoder().decode(StremioStreamResponse.self, from: Data(json.utf8))

        let releases = TorrentioStreamMapper().releases(from: response, mediaID: "tt0133093")

        XCTAssertEqual(releases.count, 1)
        let release = try XCTUnwrap(releases.first)
        XCTAssertEqual(release.id, "torrentio:tt0133093:61065ea115b7cc3e8db9fb5ab1f6f327f08bd1c9:0")
        XCTAssertEqual(release.sourceId, "torrentio")
        XCTAssertEqual(release.sourceName, "Rutracker")
        XCTAssertEqual(release.title, "The.Matrix.1999.WEB-DL.2160p.mkv")
        XCTAssertEqual(release.quality, .ultraHD)
        XCTAssertEqual(release.codec, .h265)
        XCTAssertEqual(release.hdr, .dolbyVision)
        XCTAssertEqual(release.audioLanguages, ["en", "ru"])
        XCTAssertEqual(release.seeders, 14)
        XCTAssertEqual(release.sizeBytes, 18_450_000_000)
        XCTAssertTrue(release.magnetURI?.contains("xt=urn:btih:61065ea115b7cc3e8db9fb5ab1f6f327f08bd1c9") == true)
        XCTAssertTrue(release.magnetURI?.contains("tr=http%3A%2F%2Fbt4.t-ru.org%2Fann%3Fmagnet") == true)
        XCTAssertTrue(release.magnetURI?.contains("tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce") == true)
    }

    func testTorrentioProviderIsVisibleButInactiveByDefault() async throws {
        let settingsStore = InMemoryTorrentioSettingsStore()
        let catalog = SourceProviderCatalog.providers(
            featureFlags: SourceProviderFeatureFlags(
                mockProvider: false,
                torrentioProvider: true
            ),
            torrentioSettingsStore: settingsStore
        )
        let manager = SourceManager(
            providers: catalog.makeProviders(),
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )

        let settings = try await manager.settings(for: "torrentio")
        let initiallyActive = try await manager.activeProviders().map(\.sourceId)

        XCTAssertEqual(catalog.providerIds, ["torrentio"])
        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(initiallyActive.isEmpty)

        try await manager.setSourceEnabled(true, sourceId: "torrentio")

        let enabledActive = try await manager.activeProviders().map(\.sourceId)
        XCTAssertEqual(enabledActive, ["torrentio"])
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
