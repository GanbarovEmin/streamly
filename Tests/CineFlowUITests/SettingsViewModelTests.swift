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
        UserDefaults.standard.removeObject(forKey: "streamly.reduceMotion")
        defer { UserDefaults.standard.removeObject(forKey: "streamly.reduceMotion") }

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
        await viewModel.updatePreferredAudioOrder(.custom)
        await viewModel.updatePreferredQuality(.p1080)
        await viewModel.updateHDRPreference(.avoidHDR)
        await viewModel.updateCodecPreference(.avoidUnsupportedAV1)
        await viewModel.updateMaxFileSizeGB(12)
        await viewModel.updatePreferHighSeedersOverHighestQuality(true)
        await viewModel.updateSeekStep(30)
        await viewModel.updateStartFromLastPosition(false)
        await viewModel.updateDimBackgroundAroundVideo(true)
        await viewModel.updateTimelinePreviewsEnabled(false)
        await viewModel.updateAutoplayNextEpisode(false)
        await viewModel.updateRememberedVolume(0.7)
        await viewModel.updateDefaultPlaybackSpeed(1.25)
        await viewModel.updateAudioBoost(1.5)
        await viewModel.updateSubtitleLanguages(["en", "ru"])
        await viewModel.updateSubtitleAutoMode(.onlyForeignAudio)
        await viewModel.updateSubtitleDelay(1.5)
        await viewModel.updateSubtitleVisualStyle(.cinematic)
        await viewModel.updateSubtitlePlacement(.higher)
        await viewModel.updateBetterReleaseNotificationsEnabled(false)
        await viewModel.updateBetterReleaseDigestMode(false)
        await viewModel.updateMacOSBetterReleaseNotificationsEnabled(true)
        await viewModel.updateNotificationCategory(.cache, isEnabled: false)

        let persisted = await settingsRepository.appSettings
        let persistedSubtitles = await settingsRepository.subtitleSettings

        XCTAssertEqual(persisted.general.language, .english)
        XCTAssertEqual(persisted.appearance.reduceMotion, true)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "streamly.reduceMotion"), true)
        XCTAssertEqual(persisted.playback.preferredAudioLanguages, ["en", "ru"])
        XCTAssertEqual(persisted.playback.preferredAudioOrder, .custom)
        XCTAssertEqual(persisted.playback.preferredQuality, .p1080)
        XCTAssertEqual(persisted.playback.hdrPreference, .avoidHDR)
        XCTAssertEqual(persisted.playback.codecPreference, .avoidUnsupportedAV1)
        XCTAssertEqual(persisted.playback.maxFileSizeBytes, 12_000_000_000)
        XCTAssertEqual(persisted.playback.preferHighSeedersOverHighestQuality, true)
        XCTAssertEqual(persisted.playback.seekStepSeconds, 30)
        XCTAssertEqual(persisted.playback.startFromLastPosition, false)
        XCTAssertEqual(persisted.playback.dimBackgroundAroundVideo, true)
        XCTAssertEqual(persisted.playback.enableTimelinePreviews, false)
        XCTAssertEqual(persisted.playback.autoplayNextEpisode, false)
        XCTAssertEqual(persisted.playback.rememberedVolume, 0.7, accuracy: 0.001)
        XCTAssertEqual(persisted.playback.playbackSpeed, 1.25, accuracy: 0.001)
        XCTAssertEqual(persisted.playback.audioBoost, 1.5, accuracy: 0.001)
        XCTAssertEqual(persistedSubtitles.languagePreference.languageCodes, ["en", "ru"])
        XCTAssertEqual(persistedSubtitles.autoMode, .onlyForeignAudio)
        XCTAssertEqual(persistedSubtitles.subtitleDelaySeconds, 1.5)
        XCTAssertEqual(persistedSubtitles.visualStyle, .cinematic)
        XCTAssertEqual(persistedSubtitles.placement, .higher)
        XCTAssertFalse(persisted.notifications.betterReleaseNotificationsEnabled)
        XCTAssertFalse(persisted.notifications.betterReleaseDigestMode)
        XCTAssertTrue(persisted.notifications.macOSBetterReleaseNotificationsEnabled)
        XCTAssertFalse(persisted.notifications.isCategoryEnabled(.cache))
    }

    func testHomePersonalizationPersistsAndResetsDefaults() async {
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
        await viewModel.updateHomeSection("continueWatching", isEnabled: false)
        await viewModel.updateHomeSection("trendingNow", isEnabled: false)
        await viewModel.moveHomeSection("recommended", direction: .up)
        await viewModel.updateHomeLayoutDensity(.compact)
        await viewModel.updateHomePosterSize(.large)
        await viewModel.updateLocalRecommendationsEnabled(false)
        await viewModel.updateTasteGenre("Sci-Fi", preference: .more)
        await viewModel.updateTasteGenre("Horror", preference: .hidden)

        let customized = await settingsRepository.appSettings.home
        let customizedSettings = await settingsRepository.appSettings
        XCTAssertFalse(customized.isSectionEnabled("continueWatching"))
        XCTAssertFalse(customized.isSectionEnabled("trendingNow"))
        XCTAssertEqual(customized.layoutDensity, .compact)
        XCTAssertEqual(customized.posterSize, .large)
        XCTAssertGreaterThan(customized.syncRevision, 0)
        XCTAssertFalse(customizedSettings.recommendations.localRecommendationsEnabled)
        XCTAssertEqual(customizedSettings.tasteProfile.preference(forGenre: "sci-fi"), .more)
        XCTAssertEqual(customizedSettings.tasteProfile.preference(forGenre: "Horror"), .hidden)

        await viewModel.resetHomePreferences()

        let reset = await settingsRepository.appSettings.home
        XCTAssertEqual(reset, HomePreferences())
        XCTAssertEqual(viewModel.settings.home, HomePreferences())
    }

    func testHiddenRecommendationItemsCanBeRestoredFromSettings() async {
        var settings = AppSettings()
        settings.tasteProfile.hideTitle(
            mediaID: "tmdb:movie:31",
            title: "Hidden Space",
            genres: ["Sci-Fi"],
            reason: .notInterested,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let settingsRepository = CoreMockSettingsRepository(settings: settings)
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

        XCTAssertEqual(viewModel.hiddenRecommendationItems.map(\.title), ["Hidden Space"])
        await viewModel.restoreHiddenRecommendationItem(mediaID: "tmdb:movie:31")

        let persisted = await settingsRepository.appSettings
        XCTAssertTrue(persisted.tasteProfile.hiddenItems.isEmpty)
        XCTAssertTrue(viewModel.hiddenRecommendationItems.isEmpty)
    }

    func testTMDBCredentialsCanBeSavedAndClearedFromSettings() async {
        let settingsRepository = CoreMockSettingsRepository()
        let keychainService = MockKeychainService()
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
                keychainService: keychainService
            )
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.tmdbCredentialSummary.statusText, "TMDB credentials missing")

        await viewModel.saveTMDBCredentials(readAccessToken: " token ", apiKey: " key ")

        let savedToken = await settingsRepository.metadataCredential(forKey: "tmdb_read_access_token")
        let savedAPIKey = await settingsRepository.metadataCredential(forKey: "tmdb_api_key")
        let keychainToken = try? await keychainService.readCredential(accountID: TMDBCredentialAccountIDs.readAccessToken)
        let keychainAPIKey = try? await keychainService.readCredential(accountID: TMDBCredentialAccountIDs.apiKey)
        XCTAssertNil(savedToken)
        XCTAssertNil(savedAPIKey)
        XCTAssertEqual(keychainToken?.token, "token")
        XCTAssertEqual(keychainAPIKey?.token, "key")
        XCTAssertEqual(viewModel.tmdbCredentialSummary.statusText, "TMDB read access token saved")

        await viewModel.clearTMDBCredentials()

        let clearedToken = await settingsRepository.metadataCredential(forKey: "tmdb_read_access_token")
        let clearedAPIKey = await settingsRepository.metadataCredential(forKey: "tmdb_api_key")
        let clearedKeychainToken = try? await keychainService.readCredential(accountID: TMDBCredentialAccountIDs.readAccessToken)
        let clearedKeychainAPIKey = try? await keychainService.readCredential(accountID: TMDBCredentialAccountIDs.apiKey)
        XCTAssertNil(clearedToken)
        XCTAssertNil(clearedAPIKey)
        XCTAssertNil(clearedKeychainToken)
        XCTAssertNil(clearedKeychainAPIKey)
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

    func testSmartCacheDashboardPersistsPolicyAndRoutesSafeActions() async {
        let settingsRepository = CoreMockSettingsRepository()
        let smartCacheManager = TestSmartCacheManager()
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
                smartCacheManager: smartCacheManager
            )
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.cacheSummary.imageBytes, 1_000)
        XCTAssertEqual(viewModel.cacheSummary.torrentBytes, 2_000)
        XCTAssertEqual(viewModel.cacheSummary.subtitleBytes, 3_000)
        XCTAssertEqual(viewModel.cacheSummary.metadataBytes, 4_000)
        XCTAssertEqual(viewModel.cacheSummary.timelinePreviewBytes, 5_000)
        XCTAssertEqual(viewModel.cacheSummary.totalBytes, 15_000)
        XCTAssertEqual(viewModel.cacheSummary.titleItems.map(\.title), ["Cached Movie"])

        await viewModel.updateCacheRetentionDays(14)
        await viewModel.updateMaxCacheSizeGB(12)
        await viewModel.updateKeepUnfinishedCache(false)
        await viewModel.updateRemoveCompletedCache(true)
        await viewModel.updateTorrentDownloadLimitMBps(25)
        await viewModel.updateTorrentUploadLimitMBps(5)

        let persisted = await settingsRepository.appSettings
        XCTAssertEqual(persisted.storage.cacheRetentionDays, 14)
        XCTAssertEqual(persisted.storage.maxCacheSizeBytes, 12 * 1_024 * 1_024 * 1_024)
        XCTAssertFalse(persisted.storage.keepUnfinishedCache)
        XCTAssertTrue(persisted.storage.removeCompletedCache)
        XCTAssertEqual(persisted.storage.torrentDownloadLimitBytesPerSecond, 25 * 1_024 * 1_024)
        XCTAssertEqual(persisted.storage.torrentUploadLimitBytesPerSecond, 5 * 1_024 * 1_024)

        await viewModel.setTitleCacheKeepForLater(itemID: "torrents:/tmp/Cached.Movie", keep: true)
        await viewModel.clearTitleCache(itemID: "torrents:/tmp/Cached.Movie")
        await viewModel.runCacheAutoClean()
        await viewModel.clearMetadataCache()
        await viewModel.clearTimelinePreviewCache()

        let calls = await smartCacheManager.calls()
        XCTAssertTrue(calls.contains("keep:torrents:/tmp/Cached.Movie:true"))
        XCTAssertTrue(calls.contains("clearTitle:torrents:/tmp/Cached.Movie"))
        XCTAssertTrue(calls.contains("autoClean:14"))
        XCTAssertTrue(calls.contains("clear:metadata"))
        XCTAssertTrue(calls.contains("clear:timelinePreviews"))
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

private actor TestSmartCacheManager: SmartCacheManagerProtocol {
    private var recordedCalls: [String] = []

    func summary(policy: SmartCachePolicy, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheSummary {
        recordedCalls.append("summary:\(policy.retentionDays)")
        return SmartCacheSummary(
            buckets: [
                SmartCacheBucketSummary(category: .images, sizeBytes: 1_000, itemCount: 1),
                SmartCacheBucketSummary(category: .torrents, sizeBytes: 2_000, itemCount: 1, path: scope.torrentCacheURL.path),
                SmartCacheBucketSummary(category: .subtitles, sizeBytes: 3_000, itemCount: 1, path: scope.subtitleCacheURL.path),
                SmartCacheBucketSummary(category: .metadata, sizeBytes: 4_000, itemCount: 1),
                SmartCacheBucketSummary(category: .timelinePreviews, sizeBytes: 5_000, itemCount: 1, path: scope.timelinePreviewCacheURL.path)
            ],
            titleItems: [
                SmartTitleCacheItem(
                    id: "torrents:/tmp/Cached.Movie",
                    title: "Cached Movie",
                    category: .torrents,
                    sizeBytes: 2_000,
                    isCompleted: true,
                    path: "/tmp/Cached.Movie"
                )
            ],
            maxSizeBytes: policy.maxSizeBytes
        )
    }

    func clear(category: SmartCacheCategory, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheCleanupResult {
        recordedCalls.append("clear:\(category.rawValue)")
        return SmartCacheCleanupResult(removedItemCount: 1, freedBytes: 512)
    }

    func clearTitleCache(itemID: String, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheCleanupResult {
        recordedCalls.append("clearTitle:\(itemID)")
        return SmartCacheCleanupResult(removedItemCount: 1, freedBytes: 512)
    }

    func setKeepForLater(itemID: String, keep: Bool) async throws {
        recordedCalls.append("keep:\(itemID):\(keep)")
    }

    func runAutoClean(policy: SmartCachePolicy, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheCleanupResult {
        recordedCalls.append("autoClean:\(policy.retentionDays)")
        return SmartCacheCleanupResult(removedItemCount: 1, freedBytes: 512)
    }

    func calls() -> [String] {
        recordedCalls
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
