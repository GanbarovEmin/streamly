import AppKit
import CineFlowCore
import CineFlowDatabase
import CineFlowDiagnostics
import CineFlowLocalization
import CineFlowMetadata
import CineFlowPlayback
import CineFlowSettings
import CineFlowSources
import CineFlowSubtitles
import CineFlowTorrent
import CineFlowUI
import CineFlowUpdater
import SwiftUI

@main
struct CineFlowApplication: App {
    @NSApplicationDelegateAdaptor(CineFlowAppDelegate.self) private var appDelegate
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var languageSettingsStore = LanguageSettingsStore()
    @StateObject private var macOSIntegrationViewModel: MacOSIntegrationViewModel

    private let environment: AppEnvironment
    private let databaseManager: DatabaseManager?
    private let sourceManager: SourceManager
    private let searchProvider: any SearchProviderProtocol
    private let playbackProgressRecorder: PlaybackProgressRecorder
    private let playbackProgressRepository: (any PlaybackProgressRepositoryProtocol)?
    private let watchHistoryRepository: (any WatchHistoryRepositoryProtocol)?
    private let keychainService: any KeychainServiceProtocol
    private let updateService: SparkleUpdateService
    private static let environment = ProcessInfo.processInfo.environment

    init() {
        let liveDatabaseManager = try? DatabaseManager.live()
        if let liveDatabaseManager, Self.shouldSeedDevelopmentData {
            try? DatabaseSeeder.seedDevelopmentData(in: liveDatabaseManager)
        }

        databaseManager = liveDatabaseManager
        let libraryRepository: LibraryRepositoryProtocol = liveDatabaseManager
            .map(DatabaseLibraryRepository.init(databaseManager:)) ?? MockLibraryRepository()
        let settingsRepository: SettingsRepositoryProtocol = liveDatabaseManager
            .map(DatabaseSettingsRepository.init(databaseManager:)) ?? MockSettingsRepository()
        let keychainService = KeychainService()
        self.keychainService = keychainService
        let metadataService: MetadataServiceProtocol
        if let liveDatabaseManager {
            let cacheRepository = CacheRepository(databaseManager: liveDatabaseManager)
            let legacySettingsRepository = DatabaseSettingsRepository(databaseManager: liveDatabaseManager)
            let keychainCredentialProvider = KeychainTMDBCredentialProvider(
                keychainService: keychainService,
                legacySettingsRepository: legacySettingsRepository
            )
            let tmdbMetadataService = TMDBMetadataService(
                credentialProvider: CompositeTMDBCredentialProvider([
                    keychainCredentialProvider,
                    LocalTMDBCredentialProvider()
                ]),
                cacheRepository: cacheRepository
            )
            metadataService = CompositeMetadataService(
                primary: CinemetaMetadataService(cacheRepository: cacheRepository),
                fallback: tmdbMetadataService
            )
        } else {
            metadataService = MockMetadataService()
        }
        let imageCacheService: ImageCacheServiceProtocol? = liveDatabaseManager
            .map { ImageCacheService(cacheRepository: CacheRepository(databaseManager: $0)) }
        let smartCacheManager: SmartCacheManagerProtocol? = liveDatabaseManager
            .map { LocalSmartCacheManager(cacheRepository: CacheRepository(databaseManager: $0)) }
        let playbackProgressRepository = liveDatabaseManager
            .map(PlaybackProgressRepository.init(databaseManager:))
        let watchHistoryRepository = liveDatabaseManager
            .map(WatchHistoryRepository.init(databaseManager:))
        self.playbackProgressRepository = playbackProgressRepository
        self.watchHistoryRepository = watchHistoryRepository

        let torrentioSettingsStore = UserDefaultsTorrentioSettingsStore()
        let diagnosticsService = LocalDiagnosticsService(
            settingsSummaryProvider: {
                DiagnosticsSettingsSummary(
                    language: "system",
                    telemetryEnabled: false,
                    sourceCount: SourceProviderCatalog.providers(
                        featureFlags: SourceProviderFeatureFlags(mockProvider: false, rutorProvider: false, ruTrackerProvider: false, torrentioProvider: true),
                        torrentioSettingsStore: torrentioSettingsStore
                    ).providerIds.count
                )
            },
            cacheSummaryProvider: {
                DiagnosticsCacheSummary()
            },
            databaseSchemaVersionProvider: {
                "v10_media_item_metadata_json"
            }
        )
        let sourceManager = SourceManager.development(
            featureFlags: SourceProviderFeatureFlags(mockProvider: false, rutorProvider: false, ruTrackerProvider: false, torrentioProvider: true),
            credentialStore: KeychainSourceCredentialStore(keychainService: keychainService),
            torrentioSettingsStore: torrentioSettingsStore
        )
        self.sourceManager = sourceManager
        searchProvider = TMDBSearchProvider(metadataService: metadataService)
        playbackProgressRecorder = PlaybackProgressRecorder(
            store: playbackProgressRepository ?? InMemoryPlaybackProgressStore(),
            historyStore: watchHistoryRepository
        )
        let updateService = SparkleUpdateService(startingUpdater: true)
        self.updateService = updateService
        let userMediaSourceRepository = liveDatabaseManager
            .map(DatabaseUserMediaSourceRepository.init(databaseManager:))
        let libraryPortabilityService = liveDatabaseManager
            .map(DatabaseLibraryPortabilityService.init(databaseManager:))
        let personalStatsService = liveDatabaseManager
            .map { DatabasePersonalStatsService(databaseManager: $0) }
        let playbackService: any PlaybackServiceProtocol = TranscodingAVPlaybackService()
        let timelinePreviewService = TimelinePreviewService()

        let torrentEngine = EmbeddedLibtorrentTorrentEngine(bridge: NativeLibtorrentBridge())
        CineFlowAppDelegate.terminationHandler = {
            try? await torrentEngine.shutdown()
        }

        let appEnvironment = AppEnvironment(
            metadataService: metadataService,
            torrentEngine: torrentEngine,
            playbackService: playbackService,
            subtitleService: SubtitleService(),
            libraryRepository: libraryRepository,
            settingsRepository: settingsRepository,
            diagnosticsService: diagnosticsService,
            updateService: updateService,
            imageCacheService: imageCacheService,
            timelinePreviewService: timelinePreviewService,
            smartCacheManager: smartCacheManager,
            playbackProgressRepository: playbackProgressRepository,
            watchHistoryRepository: watchHistoryRepository,
            keychainService: keychainService,
            userMediaSourceRepository: userMediaSourceRepository,
            libraryPortabilityService: libraryPortabilityService,
            personalStatsService: personalStatsService
        )
        environment = appEnvironment
        _macOSIntegrationViewModel = StateObject(wrappedValue: MacOSIntegrationViewModel(environment: appEnvironment))
        Task {
            await diagnosticsService.log(level: .info, subsystem: .app, message: "Streamly app launch", metadata: [:])
        }
    }

    var body: some Scene {
        WindowGroup(L10n.string(.appName, language: languageSettingsStore.selectedLanguage)) {
            AppWindowRootView(
                environment: environment,
                navigationCoordinator: navigationCoordinator,
                searchProvider: searchProvider,
                sourceManager: sourceManager,
                playbackProgressRecorder: playbackProgressRecorder,
                macOSIntegrationViewModel: macOSIntegrationViewModel
            )
                .environmentObject(languageSettingsStore)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1200, minHeight: 760)
                .onOpenURL { url in
                    Task { await macOSIntegrationViewModel.handleOpenURL(url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Torrent...") {
                    macOSIntegrationViewModel.openTorrentPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Magnet Link...") {
                    macOSIntegrationViewModel.promptForMagnetLink()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }

            CommandGroup(after: .windowArrangement) {
                Button("Fullscreen") {
                    macOSIntegrationViewModel.toggleFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }

            CommandGroup(after: .help) {
                Button("Export Diagnostics") {
                    Task { await macOSIntegrationViewModel.exportDiagnosticsFromMenu() }
                }
            }

            CommandMenu(L10n.string(.appName, language: languageSettingsStore.selectedLanguage)) {
                Button(L10n.string(.commandSearch, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.handleShortcut(.commandF)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button(L10n.string(.commandFocusSearch, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.handleShortcut(.commandL)
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Command Search") {
                    navigationCoordinator.handleShortcut(.commandK)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button(L10n.string(.commandSettings, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.selectSidebarRoute(.settings)
                }
                .keyboardShortcut(",", modifiers: [.command])

                Divider()

                Button(L10n.string(.commandPlayPause, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.handleShortcut(.space)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button(L10n.string(.commandBackCloseOverlay, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.handleShortcut(.escape)
                }
                .keyboardShortcut(.cancelAction)

                Button("Toggle Fullscreen") {
                    navigationCoordinator.handleShortcut(.f)
                    macOSIntegrationViewModel.toggleFullscreen()
                }
                .keyboardShortcut("f", modifiers: [])

                Button("Search") {
                    navigationCoordinator.handleShortcut(.s)
                }
                .keyboardShortcut("s", modifiers: [])

                Button("Library") {
                    navigationCoordinator.handleShortcut(.a)
                }
                .keyboardShortcut("a", modifiers: [])

                Button("Refresh") {
                    navigationCoordinator.handleShortcut(.r)
                }
                .keyboardShortcut("r", modifiers: [])
            }
        }
    }

    private static var shouldSeedDevelopmentData: Bool {
        environment["STREAMLY_SEED_DEVELOPMENT_DATA"] == "1"
            || environment["CINEFLOW_SEED_DEVELOPMENT_DATA"] == "1"
    }
}

private final class CineFlowAppDelegate: NSObject, NSApplicationDelegate {
    static var terminationHandler: (@Sendable () async -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationHandler = Self.terminationHandler else {
            return .terminateNow
        }
        Task {
            await terminationHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
