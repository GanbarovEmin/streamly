import CineFlowCore
import XCTest
@testable import CineFlowSources

final class SourceProviderArchitectureTests: XCTestCase {
    override func tearDown() {
        TorrentioMockURLProtocol.reset()
        super.tearDown()
    }

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

    func testAggregatorTimesOutOneSourceRetriesSafelyAndKeepsOtherResults() async throws {
        let slow = ControlledTorrentSourceProvider(
            sourceId: "slow",
            displayName: "Slow Source",
            outcomes: [
                .delayThenFail(nanoseconds: 200_000_000, SourceProviderError.providerUnavailable(sourceId: "slow", reason: "socket hung")),
                .success([
                    TorrentRelease(id: "slow-result", sourceId: "slow", sourceName: "Slow Source", title: "Matrix slow", quality: .fullHD, seeders: 20)
                ])
            ]
        )
        let healthy = ControlledTorrentSourceProvider(
            sourceId: "healthy",
            displayName: "Healthy Source",
            outcomes: [
                .success([
                    TorrentRelease(id: "healthy-result", sourceId: "healthy", sourceName: "Healthy Source", title: "Matrix healthy", quality: .ultraHD, seeders: 50)
                ])
            ]
        )
        let manager = SourceManager(
            providers: [slow, healthy],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        try await manager.updateSourcePolicy(sourceId: "slow", requestTimeoutSeconds: 0.03, maxRetryCount: 1)

        let result = try await TorrentSearchAggregator(sourceManager: manager).search(query: "matrix")
        let slowSettings = try await manager.settings(for: "slow")
        let healthySettings = try await manager.settings(for: "healthy")

        XCTAssertEqual(result.rankedReleases.map(\.release.id), ["healthy-result", "slow-result"])
        XCTAssertTrue(result.sourceErrors.isEmpty)
        let slowCallCount = await slow.recordedSearchCallCount()
        XCTAssertEqual(slowCallCount, 2)
        XCTAssertEqual(slowSettings.healthStatus, .healthy)
        XCTAssertEqual(healthySettings.healthStatus, .healthy)
    }

    func testAggregatorReportsTimedOutSourceWithoutBreakingOtherSources() async throws {
        let timedOut = ControlledTorrentSourceProvider(
            sourceId: "timeout",
            displayName: "Timeout Source",
            outcomes: [.delayThenSuccess(nanoseconds: 300_000_000, [])]
        )
        let healthy = ControlledTorrentSourceProvider(
            sourceId: "healthy",
            displayName: "Healthy Source",
            outcomes: [
                .success([
                    TorrentRelease(id: "healthy-result", sourceId: "healthy", sourceName: "Healthy Source", title: "Matrix healthy", quality: .fullHD, seeders: 40)
                ])
            ]
        )
        let manager = SourceManager(
            providers: [timedOut, healthy],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        try await manager.updateSourcePolicy(sourceId: "timeout", requestTimeoutSeconds: 0.03, maxRetryCount: 0)

        let result = try await TorrentSearchAggregator(sourceManager: manager).search(query: "matrix")
        let timedOutSettings = try await manager.settings(for: "timeout")

        XCTAssertEqual(result.rankedReleases.map(\.release.id), ["healthy-result"])
        XCTAssertEqual(result.sourceErrors.map(\.sourceId), ["timeout"])
        XCTAssertEqual(result.sourceErrors.first?.message, "This source took too long to respond.")
        XCTAssertEqual(timedOutSettings.healthStatus, .degraded)
        XCTAssertEqual(timedOutSettings.sourceStatus, .slow)
        XCTAssertEqual(timedOutSettings.errorState?.message, "This source took too long to respond.")
        XCTAssertEqual(timedOutSettings.successRate, 0)
    }

    func testSourceHealthTracksResponseTimeSuccessRateAndStatus() async throws {
        let source = ControlledTorrentSourceProvider(
            sourceId: "measured",
            displayName: "Measured Source",
            outcomes: [
                .success([
                    TorrentRelease(id: "measured-result", sourceId: "measured", sourceName: "Measured Source", title: "Matrix", quality: .fullHD, seeders: 12)
                ])
            ]
        )
        let manager = SourceManager(
            providers: [source],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        try await manager.updateSourcePolicy(sourceId: "measured", requestTimeoutSeconds: 2, maxRetryCount: 0)

        _ = try await TorrentSearchAggregator(sourceManager: manager).search(query: "matrix")
        let online = try await manager.settings(for: "measured")

        XCTAssertEqual(online.sourceStatus, .online)
        XCTAssertEqual(online.successRate, 1)
        XCTAssertNotNil(online.averageResponseTimeMilliseconds)

        try await manager.recordError(sourceId: "measured", message: "Manual health check failed")
        let errored = try await manager.settings(for: "measured")

        XCTAssertEqual(errored.sourceStatus, .error)
        XCTAssertEqual(errored.successRate, 0.5, accuracy: 0.001)
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

    func testTorrentioConfigurationURLBuilderSupportsSeriesEpisodeVideoIDs() throws {
        let settings = TorrentioSettings(resultLimit: 5)

        let url = try TorrentioConfigurationURLBuilder().streamURL(
            type: .series,
            id: "tt0944947:1:1",
            settings: settings
        )

        XCTAssertEqual(
            url.path,
            "/providers=rutor,rutracker|language=russian|qualityfilter=scr,cam|limit=5/stream/series/tt0944947:1:1.json"
        )
    }

    func testTorrentioProviderUsesSeriesStreamEndpointForEpisodeVideoIDQueries() async throws {
        let settingsStore = InMemoryTorrentioSettingsStore(settings: TorrentioSettings(resultLimit: 3))
        let provider = TorrentioSourceProvider(
            settingsStore: settingsStore,
            session: URLSession(configuration: .torrentioMock),
            urlBuilder: TorrentioConfigurationURLBuilder(baseURL: URL(string: "https://torrentio.example")!)
        )
        TorrentioMockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/providers=rutor,rutracker|language=russian|qualityfilter=scr,cam|limit=3/stream/series/tt0944947:1:1.json")
            return (200, #"{"streams":[{"title":"Game of Thrones S01E01 1080p\n👤 42 💾 4.2 GB ⚙️ Rutracker","infoHash":"abcdef1234567890abcdef1234567890abcdef12","fileIdx":0}]}"#)
        }

        let releases = try await provider.search(query: "tt0944947:1:1", filters: TorrentSourceSearchFilters())

        XCTAssertEqual(releases.map(\.id), ["torrentio:tt0944947:1:1:abcdef1234567890abcdef1234567890abcdef12:0"])
        XCTAssertEqual(releases.first?.sourceName, "Rutracker")
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
        XCTAssertEqual(release.preferredFileIndex, 0)
        XCTAssertTrue(release.magnetURI?.contains("xt=urn:btih:61065ea115b7cc3e8db9fb5ab1f6f327f08bd1c9") == true)
        XCTAssertTrue(release.magnetURI?.contains("tr=http%3A%2F%2Fbt4.t-ru.org%2Fann%3Fmagnet") == true)
        XCTAssertTrue(release.magnetURI?.contains("tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce") == true)
    }

    func testTorrentioStreamWithoutFileIndexLetsPlaybackSelectBestMediaFile() throws {
        let json = """
        {
          "streams": [
            {
              "title": "Apex 2021 1080p BluRay\\n👤 1096 💾 6.1 GB ⚙️ Rutor",
              "infoHash": "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
              "behaviorHints": {
                "filename": "Apex.2021.1080p.BluRay.mkv"
              }
            }
          ]
        }
        """
        let response = try JSONDecoder().decode(StremioStreamResponse.self, from: Data(json.utf8))

        let release = try XCTUnwrap(TorrentioStreamMapper().releases(from: response, mediaID: "tt16431404").first)

        XCTAssertEqual(release.id, "torrentio:tt16431404:abcdefabcdefabcdefabcdefabcdefabcdefabcd:auto")
        XCTAssertNil(release.preferredFileIndex)
    }

    func testTorrentioProviderIsVisibleAndActiveByDefault() async throws {
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
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(initiallyActive, ["torrentio"])

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

    func testInvalidCredentialsAreNotLeftInCredentialStoreAndSourceNeedsAuthentication() async throws {
        let credentialStore = InMemorySourceCredentialStore()
        let manager = SourceManager(
            providers: [
                ControlledTorrentSourceProvider(
                    sourceId: "private",
                    displayName: "Private Source",
                    requiresAuthentication: true,
                    authenticationResult: .invalid(reason: "bad password")
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: credentialStore
        )

        do {
            try await manager.authenticate(
                sourceId: "private",
                credentials: SourceCredentials(username: "user", password: "wrong-password")
            )
            XCTFail("Expected invalid credentials to fail authentication.")
        } catch SourceProviderError.authenticationRequired(let sourceId) {
            XCTAssertEqual(sourceId, "private")
        }

        let settings = try await manager.settings(for: "private")
        let storedCredentials = try await credentialStore.credentials(for: "private")

        XCTAssertNil(storedCredentials)
        XCTAssertNil(settings.credentialKeychainID)
        XCTAssertEqual(settings.authenticationStatus, .invalid(reason: "bad password"))
        XCTAssertEqual(settings.healthStatus, .needsAuthentication)
        XCTAssertEqual(settings.sourceStatus, .authRequired)
        XCTAssertFalse(String(describing: settings).contains("wrong-password"))
    }

    func testExpiredSessionDisablesActiveProviderUntilUserSignsInAgain() async throws {
        let credentialStore = InMemorySourceCredentialStore()
        let manager = SourceManager(
            providers: [
                ControlledTorrentSourceProvider(
                    sourceId: "private",
                    displayName: "Private Source",
                    requiresAuthentication: true,
                    authenticationResult: .authenticated(username: "user"),
                    validationResult: .invalid(reason: "session expired")
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: credentialStore
        )

        try await manager.authenticate(
            sourceId: "private",
            credentials: SourceCredentials(username: "user", password: "secret")
        )
        let status = try await manager.testConnection(sourceId: "private")
        let activeProviders = try await manager.activeProviders()
        let settings = try await manager.settings(for: "private")
        let storedCredentials = try await credentialStore.credentials(for: "private")

        XCTAssertEqual(status, .invalid(reason: "session expired"))
        XCTAssertTrue(activeProviders.isEmpty)
        XCTAssertNil(storedCredentials)
        XCTAssertNil(settings.credentialKeychainID)
        XCTAssertEqual(settings.healthStatus, .needsAuthentication)
        XCTAssertEqual(settings.sourceStatus, .authRequired)
        XCTAssertEqual(settings.errorState?.message, "Sign in again for this source.")
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

private actor ControlledTorrentSourceProvider: TorrentSourceProviderProtocol {
    enum Outcome: Sendable {
        case success([TorrentRelease])
        case delayThenSuccess(nanoseconds: UInt64, [TorrentRelease])
        case delayThenFail(nanoseconds: UInt64, Error)
        case failure(Error)
    }

    let sourceId: String
    let displayName: String
    let requiresAuthentication: Bool
    let isEnabled: Bool
    private let authenticationResult: SourceAuthenticationStatus
    private let validationResult: SourceAuthenticationStatus
    private var outcomes: [Outcome]
    private(set) var searchCallCount = 0

    init(
        sourceId: String,
        displayName: String,
        requiresAuthentication: Bool = false,
        isEnabled: Bool = true,
        authenticationResult: SourceAuthenticationStatus = .notRequired,
        validationResult: SourceAuthenticationStatus = .notRequired,
        outcomes: [Outcome] = [.success([])]
    ) {
        self.sourceId = sourceId
        self.displayName = displayName
        self.requiresAuthentication = requiresAuthentication
        self.isEnabled = isEnabled
        self.authenticationResult = authenticationResult
        self.validationResult = validationResult
        self.outcomes = outcomes
    }

    func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        searchCallCount += 1
        let outcome = outcomes.isEmpty ? Outcome.success([]) : outcomes.removeFirst()
        switch outcome {
        case .success(let releases):
            return releases
        case .delayThenSuccess(let nanoseconds, let releases):
            try await Task.sleep(nanoseconds: nanoseconds)
            return releases
        case .delayThenFail(let nanoseconds, let error):
            try await Task.sleep(nanoseconds: nanoseconds)
            throw error
        case .failure(let error):
            throw error
        }
    }

    func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        throw SourceProviderError.releaseNotFound(sourceId: sourceId, releaseId: releaseId)
    }

    func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus {
        authenticationResult
    }

    func validateSession() async throws -> SourceAuthenticationStatus {
        validationResult
    }

    func recordedSearchCallCount() -> Int {
        searchCallCount
    }
}

private extension URLSessionConfiguration {
    static var torrentioMock: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TorrentioMockURLProtocol.self]
        return configuration
    }
}

private final class TorrentioMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (Int, String))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (status, body) = try requestHandler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
