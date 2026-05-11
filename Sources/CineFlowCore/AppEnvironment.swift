import Foundation

public struct AppEnvironment {
    public let metadataService: any MetadataServiceProtocol
    public let torrentEngine: any TorrentEngineProtocol
    public let playbackService: any PlaybackServiceProtocol
    public let subtitleService: any SubtitleServiceProtocol
    public let libraryRepository: any LibraryRepositoryProtocol
    public let settingsRepository: any SettingsRepositoryProtocol
    public let diagnosticsService: any DiagnosticsServiceProtocol
    public let updateService: any UpdateServiceProtocol
    public let imageCacheService: (any ImageCacheServiceProtocol)?
    public let smartCacheManager: (any SmartCacheManagerProtocol)?
    public let playbackProgressRepository: (any PlaybackProgressRepositoryProtocol)?
    public let watchHistoryRepository: (any WatchHistoryRepositoryProtocol)?
    public let keychainService: (any KeychainServiceProtocol)?
    public let userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)?

    public init(
        metadataService: any MetadataServiceProtocol,
        torrentEngine: any TorrentEngineProtocol,
        playbackService: any PlaybackServiceProtocol,
        subtitleService: any SubtitleServiceProtocol,
        libraryRepository: any LibraryRepositoryProtocol,
        settingsRepository: any SettingsRepositoryProtocol,
        diagnosticsService: any DiagnosticsServiceProtocol,
        updateService: any UpdateServiceProtocol,
        imageCacheService: (any ImageCacheServiceProtocol)? = nil,
        smartCacheManager: (any SmartCacheManagerProtocol)? = nil,
        playbackProgressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        watchHistoryRepository: (any WatchHistoryRepositoryProtocol)? = nil,
        keychainService: (any KeychainServiceProtocol)? = nil,
        userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)? = nil
    ) {
        self.metadataService = metadataService
        self.torrentEngine = torrentEngine
        self.playbackService = playbackService
        self.subtitleService = subtitleService
        self.libraryRepository = libraryRepository
        self.settingsRepository = settingsRepository
        self.diagnosticsService = diagnosticsService
        self.updateService = updateService
        self.imageCacheService = imageCacheService
        self.smartCacheManager = smartCacheManager
        self.playbackProgressRepository = playbackProgressRepository
        self.watchHistoryRepository = watchHistoryRepository
        self.keychainService = keychainService
        self.userMediaSourceRepository = userMediaSourceRepository
    }
}
