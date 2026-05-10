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

    init() {
        let liveDatabaseManager = try? DatabaseManager.live()
        if let liveDatabaseManager {
            try? DatabaseSeeder.seedDevelopmentData(in: liveDatabaseManager)
        }

        databaseManager = liveDatabaseManager
        let libraryRepository: LibraryRepositoryProtocol = liveDatabaseManager
            .map(DatabaseLibraryRepository.init(databaseManager:)) ?? MockLibraryRepository()
        let settingsRepository: SettingsRepositoryProtocol = liveDatabaseManager
            .map(DatabaseSettingsRepository.init(databaseManager:)) ?? MockSettingsRepository()
        let metadataService: MetadataServiceProtocol
        if let liveDatabaseManager {
            let cacheRepository = CacheRepository(databaseManager: liveDatabaseManager)
            let settingsCredentialProvider = DatabaseTMDBCredentialProvider(
                settingsRepository: DatabaseSettingsRepository(databaseManager: liveDatabaseManager)
            )
            metadataService = TMDBMetadataService(
                credentialProvider: CompositeTMDBCredentialProvider([
                    settingsCredentialProvider,
                    LocalTMDBCredentialProvider()
                ]),
                cacheRepository: cacheRepository
            )
        } else {
            metadataService = MockMetadataService()
        }
        let imageCacheService: ImageCacheServiceProtocol? = liveDatabaseManager
            .map { ImageCacheService(cacheRepository: CacheRepository(databaseManager: $0)) }
        let playbackProgressRepository = liveDatabaseManager
            .map(PlaybackProgressRepository.init(databaseManager:))
        let watchHistoryRepository = liveDatabaseManager
            .map(WatchHistoryRepository.init(databaseManager:))
        self.playbackProgressRepository = playbackProgressRepository
        self.watchHistoryRepository = watchHistoryRepository

        let keychainService = KeychainService()
        self.keychainService = keychainService
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
                "v8_user_media_sources"
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
        let updateService = SparkleUpdateService()
        self.updateService = updateService
        let userMediaSourceRepository = liveDatabaseManager
            .map(DatabaseUserMediaSourceRepository.init(databaseManager:))

        let appEnvironment = AppEnvironment(
            metadataService: metadataService,
            torrentEngine: EmbeddedLibtorrentTorrentEngine(),
            playbackService: AVFoundationPlaybackService(),
            subtitleService: MockSubtitleService(),
            libraryRepository: libraryRepository,
            settingsRepository: settingsRepository,
            diagnosticsService: diagnosticsService,
            updateService: updateService,
            imageCacheService: imageCacheService,
            playbackProgressRepository: playbackProgressRepository,
            watchHistoryRepository: watchHistoryRepository,
            keychainService: keychainService,
            userMediaSourceRepository: userMediaSourceRepository
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
                .task { updateService.startUpdaterIfNeeded() }
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
                    navigationCoordinator.selectSidebarRoute(.search)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button(L10n.string(.commandFocusSearch, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.focusSearchField()
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button(L10n.string(.commandSettings, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.selectSidebarRoute(.settings)
                }
                .keyboardShortcut(",", modifiers: [.command])

                Divider()

                Button(L10n.string(.commandPlayPause, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button(L10n.string(.commandBackCloseOverlay, language: languageSettingsStore.selectedLanguage)) {
                    navigationCoordinator.closeOverlayOrGoBack()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }
}

private final class CineFlowAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
