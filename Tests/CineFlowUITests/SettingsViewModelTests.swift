import CineFlowCore
import CineFlowSources
import XCTest
@testable import CineFlowUI

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testLoadBuildsAllSettingsSectionsWithPersistedDefaults() async {
        let settingsRepository = CoreMockSettingsRepository()
        let viewModel = SettingsViewModel(
            environment: AppEnvironment(
                metadataService: CoreMockMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: settingsRepository,
                diagnosticsService: CoreMockDiagnosticsService(),
                updateService: CoreMockUpdateService(),
                imageCacheService: TestSettingsImageCacheService(sizeBytes: 2_048)
            ),
            sourceManager: SourceManager(
                providers: [MockTorrentSourceProvider(sourceId: "mock", displayName: "Mock", requiresAuthentication: false)],
                settingsStore: InMemorySourceSettingsStore(),
                credentialStore: InMemorySourceCredentialStore()
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.sections.map(\.id), SettingsSectionID.allCases)
        XCTAssertEqual(viewModel.settings.general.language, .system)
        XCTAssertEqual(viewModel.settings.appearance.darkModeOnly, true)
        XCTAssertEqual(viewModel.settings.appearance.accentColorName, "neonPurple")
        XCTAssertEqual(viewModel.settings.playback.preferredAudioLanguages, ["ru", "en"])
        XCTAssertEqual(viewModel.subtitleSettings.languagePreference.languageCodes, ["ru", "en"])
        XCTAssertEqual(viewModel.cacheSummary.imageBytes, 2_048)
        XCTAssertEqual(viewModel.sourceRows.map(\.displayName), ["Mock"])
        XCTAssertEqual(viewModel.about.appName, "Streamly")
    }

    func testUpdatePersistsPlaybackSubtitlesAndGeneralSettings() async {
        let settingsRepository = CoreMockSettingsRepository()
        let viewModel = SettingsViewModel(
            environment: AppEnvironment(
                metadataService: CoreMockMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: settingsRepository,
                diagnosticsService: CoreMockDiagnosticsService(),
                updateService: CoreMockUpdateService()
            )
        )

        await viewModel.load()
        await viewModel.updateLanguage(.english)
        await viewModel.updateReduceMotion(true)
        await viewModel.updatePreferredAudioLanguages(["en", "ru"])
        await viewModel.updateSeekStep(30)
        await viewModel.updateStartFromLastPosition(false)
        await viewModel.updateSubtitleLanguages(["en", "ru"])
        await viewModel.updateSubtitleDelay(1.5)

        let persisted = await settingsRepository.appSettings
        let persistedSubtitles = await settingsRepository.subtitleSettings

        XCTAssertEqual(persisted.general.language, .english)
        XCTAssertEqual(persisted.appearance.reduceMotion, true)
        XCTAssertEqual(persisted.playback.preferredAudioLanguages, ["en", "ru"])
        XCTAssertEqual(persisted.playback.seekStepSeconds, 30)
        XCTAssertEqual(persisted.playback.startFromLastPosition, false)
        XCTAssertEqual(persistedSubtitles.languagePreference.languageCodes, ["en", "ru"])
        XCTAssertEqual(persistedSubtitles.subtitleDelaySeconds, 1.5)
    }

    func testTMDBCredentialsCanBeSavedAndClearedFromSettings() async {
        let settingsRepository = CoreMockSettingsRepository()
        let viewModel = SettingsViewModel(
            environment: AppEnvironment(
                metadataService: CoreMockMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: settingsRepository,
                diagnosticsService: CoreMockDiagnosticsService(),
                updateService: CoreMockUpdateService()
            )
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.tmdbCredentialSummary.statusText, "TMDB credentials missing")

        await viewModel.saveTMDBCredentials(readAccessToken: " token ", apiKey: " key ")

        let savedToken = await settingsRepository.metadataCredential(forKey: "tmdb_read_access_token")
        let savedAPIKey = await settingsRepository.metadataCredential(forKey: "tmdb_api_key")
        XCTAssertEqual(savedToken, "token")
        XCTAssertEqual(savedAPIKey, "key")
        XCTAssertEqual(viewModel.tmdbCredentialSummary.statusText, "TMDB read access token saved")

        await viewModel.clearTMDBCredentials()

        let clearedToken = await settingsRepository.metadataCredential(forKey: "tmdb_read_access_token")
        let clearedAPIKey = await settingsRepository.metadataCredential(forKey: "tmdb_api_key")
        XCTAssertNil(clearedToken)
        XCTAssertNil(clearedAPIKey)
        XCTAssertEqual(viewModel.tmdbCredentialSummary.statusText, "TMDB credentials missing")
    }

    func testTorrentioSettingsLoadPersistAndExposeConfiguredManifestURL() async throws {
        let torrentioSettingsStore = InMemoryTorrentioSettingsStore()
        let viewModel = SettingsViewModel(
            environment: AppEnvironment(
                metadataService: CoreMockMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: CoreMockSettingsRepository(),
                diagnosticsService: CoreMockDiagnosticsService(),
                updateService: CoreMockUpdateService()
            ),
            torrentioSettingsStore: torrentioSettingsStore
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.torrentioSettings.providers, [.rutor, .rutracker])
        XCTAssertEqual(viewModel.torrentioSettings.priorityLanguage, .russian)
        XCTAssertEqual(viewModel.torrentioSettings.excludedQualities, [.screener, .cam])
        XCTAssertEqual(
            viewModel.torrentioConfiguredManifestURL?.path,
            "/providers=rutor,rutracker|language=russian|qualityfilter=scr,cam|limit=10/manifest.json"
        )

        await viewModel.updateTorrentioProvider(.rutor, isSelected: false)
        await viewModel.updateTorrentioPriorityLanguage(.none)
        await viewModel.updateTorrentioExcludedQuality(.fourK, isExcluded: true)
        await viewModel.updateTorrentioResultLimit(25)

        let saved = try await torrentioSettingsStore.settings()
        XCTAssertEqual(saved.providers, [.rutracker])
        XCTAssertEqual(saved.priorityLanguage, .none)
        XCTAssertEqual(saved.excludedQualities, [.screener, .cam, .fourK])
        XCTAssertEqual(saved.resultLimit, 25)
        XCTAssertEqual(
            viewModel.torrentioConfiguredManifestURL?.path,
            "/providers=rutracker|qualityfilter=scr,cam,4k|limit=25/manifest.json"
        )
    }

    func testActionsClearCacheCheckUpdatesAndExportDiagnostics() async {
        let imageCache = TestSettingsImageCacheService(sizeBytes: 4_096)
        let diagnostics = TestDiagnosticsService()
        let updates = TestUpdateService()
        let keychain = MockKeychainService()
        _ = try? await keychain.saveCredential(KeychainCredential(accountID: "api:tmdb", kind: .apiToken, token: "secret-token"))
        let viewModel = SettingsViewModel(
            environment: AppEnvironment(
                metadataService: CoreMockMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: CoreMockSettingsRepository(),
                diagnosticsService: diagnostics,
                updateService: updates,
                imageCacheService: imageCache,
                keychainService: keychain
            )
        )

        await viewModel.load()
        await viewModel.clearImageCache()
        await viewModel.checkForUpdates()
        await viewModel.exportDiagnostics()

        XCTAssertEqual(viewModel.cacheSummary.imageBytes, 0)
        XCTAssertEqual(viewModel.updateStatus, .upToDate)
        XCTAssertEqual(viewModel.diagnosticsExport, "diagnostics-export.txt")
        let didClearAll = await imageCache.clearAllWasCalled()
        let didCheck = await updates.checkWasCalled()
        XCTAssertTrue(didClearAll)
        XCTAssertTrue(didCheck)

        await viewModel.clearAllLocalData()
        let storedToken = try? await keychain.readCredential(accountID: "api:tmdb")
        XCTAssertNil(storedToken)
    }

    func testUpdateSectionReflectsSparkleStateAndPersistsAutomaticChecks() async {
        let lastCheckedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updates = TestUpdateService(
            automaticallyChecksForUpdates: false,
            lastCheckedAt: lastCheckedAt
        )
        let viewModel = SettingsViewModel(
            environment: AppEnvironment(
                metadataService: CoreMockMetadataService(),
                torrentEngine: CoreMockTorrentEngine(),
                playbackService: CoreMockPlaybackService(),
                subtitleService: CoreMockSubtitleService(),
                libraryRepository: CoreMockLibraryRepository(),
                settingsRepository: CoreMockSettingsRepository(),
                diagnosticsService: CoreMockDiagnosticsService(),
                updateService: updates
            )
        )

        await viewModel.load()

        XCTAssertFalse(viewModel.settings.updates.automaticChecksEnabled)
        XCTAssertEqual(viewModel.lastUpdateCheckedAt, lastCheckedAt)

        await viewModel.updateAutomaticUpdateChecks(true)
        await viewModel.checkForUpdates()

        let automaticChecksEnabled = await updates.automaticChecksEnabled()
        let serviceLastCheckedAt = await updates.serviceLastCheckedAt()
        XCTAssertTrue(automaticChecksEnabled)
        XCTAssertEqual(viewModel.updateStatus, .upToDate)
        XCTAssertEqual(viewModel.lastUpdateCheckedAt, serviceLastCheckedAt)
    }
}

final class SettingsSourceManagerTests: XCTestCase {
    func testClearSourceSessionDeletesCredentialsAndKeepsSettingsSecretFree() async throws {
        let credentialStore = InMemorySourceCredentialStore()
        let manager = SourceManager(
            providers: [MockTorrentSourceProvider(sourceId: "private", displayName: "Private", requiresAuthentication: true)],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: credentialStore
        )

        try await manager.authenticate(
            sourceId: "private",
            credentials: SourceCredentials(username: "user", password: "secret-password")
        )
        try await manager.clearSession(sourceId: "private")

        let settings = try await manager.settings(for: "private")
        let credentials = try await credentialStore.credentials(for: "private")

        XCTAssertNil(credentials)
        XCTAssertEqual(settings.authenticationStatus, .unauthenticated)
        XCTAssertNil(settings.credentialKeychainID)
        XCTAssertFalse(String(describing: settings).contains("secret-password"))
    }
}

private actor TestSettingsImageCacheService: ImageCacheServiceProtocol {
    private(set) var didClearAll = false
    private var sizeBytes: Int64

    init(sizeBytes: Int64) {
        self.sizeBytes = sizeBytes
    }

    func imageData(for url: URL, kind: CachedImageKind) async throws -> Data {
        Data()
    }

    func cacheSizeBytes() async throws -> Int64 {
        sizeBytes
    }

    func clearAll() async throws {
        didClearAll = true
        sizeBytes = 0
    }

    func clearUnused(olderThan date: Date) async throws {}

    func clearAllWasCalled() -> Bool {
        didClearAll
    }
}

private struct TestDiagnosticsService: DiagnosticsServiceProtocol {
    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {}

    func exportDiagnostics() async -> String {
        "diagnostics-export.txt"
    }

    func exportDiagnosticsPackage() async throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics.zip")
    }

    func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        []
    }
}

private actor TestUpdateService: UpdateServiceProtocol {
    private(set) var didCheck = false
    var automaticallyChecksForUpdates: Bool
    var lastCheckedAt: Date?

    init(automaticallyChecksForUpdates: Bool = true, lastCheckedAt: Date? = nil) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.lastCheckedAt = lastCheckedAt
    }

    var currentStatus: UpdateStatus {
        get async { .idle }
    }

    func checkForUpdates() async -> UpdateStatus {
        didCheck = true
        lastCheckedAt = Date(timeIntervalSince1970: 1_800_000_100)
        return .upToDate
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) async {
        automaticallyChecksForUpdates = enabled
    }

    func checkWasCalled() -> Bool {
        didCheck
    }

    func automaticChecksEnabled() -> Bool {
        automaticallyChecksForUpdates
    }

    func serviceLastCheckedAt() -> Date? {
        lastCheckedAt
    }
}
