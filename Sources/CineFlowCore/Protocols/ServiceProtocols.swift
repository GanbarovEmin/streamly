import Foundation

public protocol MetadataServiceProtocol {
    func search(query: String) async throws -> [MediaItem]
    func searchMovies(query: String) async throws -> [MediaItem]
    func searchSeries(query: String) async throws -> [MediaItem]
    func movieDetail(tmdbID: Int) async throws -> Movie
    func movieDetail(imdbID: String) async throws -> Movie
    func seriesDetail(tmdbID: Int) async throws -> Series
    func seriesDetail(imdbID: String) async throws -> Series
    func seasonDetail(seriesTMDBID: Int, seasonNumber: Int) async throws -> Season
    func episodeDetail(seriesTMDBID: Int, seasonNumber: Int, episodeNumber: Int) async throws -> Episode
    func popularMovies() async throws -> [MediaItem]
    func popularSeries() async throws -> [MediaItem]
    func trending() async throws -> [MediaItem]
    func recommendations(for mediaID: String) async throws -> [MediaItem]
    func similar(to mediaID: String) async throws -> [MediaItem]
    func videos(for mediaID: String) async throws -> [Trailer]
    func credits(for mediaID: String) async throws -> [CastMember]
}

public enum CachedImageKind: String, Sendable {
    case poster = "posters"
    case backdrop = "backdrops"
    case thumbnail = "thumbnails"
}

public protocol ImageCacheServiceProtocol: Sendable {
    func imageData(for url: URL, kind: CachedImageKind) async throws -> Data
    func cacheSizeBytes() async throws -> Int64
    func clearAll() async throws
    func clearUnused(olderThan date: Date) async throws
}

public protocol TimelinePreviewServiceProtocol: Sendable {
    func preview(for request: TimelinePreviewRequest) async throws -> TimelinePreview?
    func clearPreviewCache() async throws
}

public protocol SmartCacheManagerProtocol: Sendable {
    func summary(policy: SmartCachePolicy, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheSummary
    func clear(category: SmartCacheCategory, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheCleanupResult
    func clearTitleCache(itemID: String, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheCleanupResult
    func setKeepForLater(itemID: String, keep: Bool) async throws
    func runAutoClean(policy: SmartCachePolicy, scope: SmartCacheScope, protection: SmartCacheProtection) async throws -> SmartCacheCleanupResult
}

public enum CoreMetadataServiceError: LocalizedError, Equatable {
    case unsupported

    public var errorDescription: String? {
        "Metadata operation is not supported by this provider."
    }
}

extension CoreMetadataServiceError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        CineFlowError(
            category: .metadata,
            technicalDescription: errorDescription ?? String(describing: self),
            userMessage: CineFlowError.defaultUserMessage(for: .metadata),
            recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .metadata),
            logLevel: CineFlowError.defaultLogLevel(for: .metadata)
        )
    }
}

public extension MetadataServiceProtocol {
    func searchMovies(query: String) async throws -> [MediaItem] {
        try await search(query: query).filter { $0.kind == .movie }
    }

    func searchSeries(query: String) async throws -> [MediaItem] {
        try await search(query: query).filter { $0.kind == .series }
    }

    func movieDetail(tmdbID: Int) async throws -> Movie {
        throw CoreMetadataServiceError.unsupported
    }

    func movieDetail(imdbID: String) async throws -> Movie {
        throw CoreMetadataServiceError.unsupported
    }

    func seriesDetail(tmdbID: Int) async throws -> Series {
        throw CoreMetadataServiceError.unsupported
    }

    func seriesDetail(imdbID: String) async throws -> Series {
        throw CoreMetadataServiceError.unsupported
    }

    func seasonDetail(seriesTMDBID: Int, seasonNumber: Int) async throws -> Season {
        throw CoreMetadataServiceError.unsupported
    }

    func episodeDetail(seriesTMDBID: Int, seasonNumber: Int, episodeNumber: Int) async throws -> Episode {
        throw CoreMetadataServiceError.unsupported
    }

    func popularMovies() async throws -> [MediaItem] {
        throw CoreMetadataServiceError.unsupported
    }

    func popularSeries() async throws -> [MediaItem] {
        throw CoreMetadataServiceError.unsupported
    }

    func trending() async throws -> [MediaItem] {
        throw CoreMetadataServiceError.unsupported
    }

    func recommendations(for mediaID: String) async throws -> [MediaItem] {
        throw CoreMetadataServiceError.unsupported
    }

    func similar(to mediaID: String) async throws -> [MediaItem] {
        throw CoreMetadataServiceError.unsupported
    }

    func videos(for mediaID: String) async throws -> [Trailer] {
        throw CoreMetadataServiceError.unsupported
    }

    func credits(for mediaID: String) async throws -> [CastMember] {
        throw CoreMetadataServiceError.unsupported
    }
}

public protocol IMDbMetadataProviderProtocol: Sendable {
    func movieMetadata(imdbID: String) async throws -> MediaMetadata
}

public protocol TraktMetadataProviderProtocol: Sendable {
    func movieMetadata(traktID: Int) async throws -> MediaMetadata
    func seriesMetadata(traktID: Int) async throws -> MediaMetadata
}

public protocol TorrentEngineProtocol: Sendable {
    var temporaryStorageURL: URL { get }

    func searchReleases(for item: MediaItem) async throws -> [TorrentRelease]
    func addMagnet(uri: String) async throws -> TorrentSession
    func addTorrentFile(url: URL) async throws -> TorrentSession
    func addTorrentFile(data: Data) async throws -> TorrentSession
    func startStreaming(_ release: TorrentRelease) async throws -> TorrentSession
    func pause(sessionId: String) async throws
    func resume(sessionId: String) async throws
    func stop(sessionId: String) async throws
    func remove(sessionId: String, deleteFiles: Bool) async throws
    func getStatus(sessionId: String) async throws -> TorrentStatus
    func getFileList(sessionId: String) async throws -> [TorrentFile]
    func selectMediaFile(sessionId: String, fileId: String) async throws
    func setSequentialDownload(sessionId: String, enabled: Bool) async throws
    func setDownloadPriority(sessionId: String, fileId: String, priority: TorrentFilePriority) async throws
    func setBandwidthLimits(sessionId: String, _ limits: TorrentBandwidthLimits) async throws
    func getStreamingURL(sessionId: String) async throws -> URL
    func statusUpdates(sessionId: String) -> AsyncThrowingStream<TorrentStatus, Error>
    func cleanup(policy: TorrentCleanupPolicy) async throws -> TorrentCleanupResult
    func shutdown() async throws
}

public extension TorrentEngineProtocol {
    var temporaryStorageURL: URL {
        TorrentCacheLocation.defaultStorageURL()
    }

    func addMagnet(uri: String) async throws -> TorrentSession {
        throw TorrentEngineError.unsupported(operation: "addMagnet")
    }

    func addTorrentFile(url: URL) async throws -> TorrentSession {
        throw TorrentEngineError.unsupported(operation: "addTorrentFile(url:)")
    }

    func addTorrentFile(data: Data) async throws -> TorrentSession {
        throw TorrentEngineError.unsupported(operation: "addTorrentFile(data:)")
    }

    func startStreaming(_ release: TorrentRelease) async throws -> TorrentSession {
        throw TorrentEngineError.unsupported(operation: "startStreaming")
    }

    func pause(sessionId: String) async throws {
        throw TorrentEngineError.unsupported(operation: "pause")
    }

    func resume(sessionId: String) async throws {
        throw TorrentEngineError.unsupported(operation: "resume")
    }

    func stop(sessionId: String) async throws {
        throw TorrentEngineError.unsupported(operation: "stop")
    }

    func remove(sessionId: String, deleteFiles: Bool = false) async throws {
        throw TorrentEngineError.unsupported(operation: "remove")
    }

    func getStatus(sessionId: String) async throws -> TorrentStatus {
        throw TorrentEngineError.unsupported(operation: "getStatus")
    }

    func getFileList(sessionId: String) async throws -> [TorrentFile] {
        throw TorrentEngineError.unsupported(operation: "getFileList")
    }

    func selectMediaFile(sessionId: String, fileId: String) async throws {
        throw TorrentEngineError.unsupported(operation: "selectMediaFile")
    }

    func setSequentialDownload(sessionId: String, enabled: Bool) async throws {
        throw TorrentEngineError.unsupported(operation: "setSequentialDownload")
    }

    func setDownloadPriority(sessionId: String, fileId: String, priority: TorrentFilePriority) async throws {
        throw TorrentEngineError.unsupported(operation: "setDownloadPriority")
    }

    func setBandwidthLimits(sessionId: String, _ limits: TorrentBandwidthLimits) async throws {
        _ = sessionId
        _ = limits
    }

    func getStreamingURL(sessionId: String) async throws -> URL {
        throw TorrentEngineError.unsupported(operation: "getStreamingURL")
    }

    func statusUpdates(sessionId: String) -> AsyncThrowingStream<TorrentStatus, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: TorrentEngineError.unsupported(operation: "statusUpdates"))
        }
    }

    func cleanup(policy: TorrentCleanupPolicy) async throws -> TorrentCleanupResult {
        throw TorrentEngineError.unsupported(operation: "cleanup")
    }

    func shutdown() async throws {}
}

public protocol PlaybackServiceProtocol {
    var currentState: PlaybackState { get async }
    var currentStatus: PlaybackStatus { get async }

    func play(_ source: PlaybackMediaSource) async throws
    func play(_ release: TorrentRelease) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func seek(to time: Double) async throws
    func setVolume(_ volume: Double) async throws
    func setMuted(_ isMuted: Bool) async throws
    func setPlaybackSpeed(_ speed: Double) async throws
    func setAudioBoost(_ boost: Double) async throws
    func selectAudioTrack(id: String?) async throws
    func selectSubtitleTrack(id: String?) async throws
    func setSubtitleDelay(_ seconds: Double) async throws
    func setSubtitleFontSize(_ fontSize: Double) async throws
    func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws
    func setFullscreen(_ isFullscreen: Bool) async throws
    func setPictureInPicture(_ isActive: Bool) async throws
    func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error>
}

public extension PlaybackServiceProtocol {
    var currentStatus: PlaybackStatus {
        get async { PlaybackStatus() }
    }

    func play(_ source: PlaybackMediaSource) async throws {
        if let release = source.release {
            try await play(release)
        } else {
            throw PlaybackServiceError.unsupported(operation: "play(source:)")
        }
    }

    func pause() async throws {
        throw PlaybackServiceError.unsupported(operation: "pause")
    }

    func resume() async throws {
        throw PlaybackServiceError.unsupported(operation: "resume")
    }

    func stop() async throws {
        throw PlaybackServiceError.unsupported(operation: "stop")
    }

    func seek(to time: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "seek")
    }

    func setVolume(_ volume: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "setVolume")
    }

    func setMuted(_ isMuted: Bool) async throws {
        throw PlaybackServiceError.unsupported(operation: "setMuted")
    }

    func setPlaybackSpeed(_ speed: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "setPlaybackSpeed")
    }

    func setAudioBoost(_ boost: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "setAudioBoost")
    }

    func selectAudioTrack(id: String?) async throws {
        throw PlaybackServiceError.unsupported(operation: "selectAudioTrack")
    }

    func selectSubtitleTrack(id: String?) async throws {
        throw PlaybackServiceError.unsupported(operation: "selectSubtitleTrack")
    }

    func setSubtitleDelay(_ seconds: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "setSubtitleDelay")
    }

    func setSubtitleFontSize(_ fontSize: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "setSubtitleFontSize")
    }

    func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {
        throw PlaybackServiceError.unsupported(operation: "setSubtitleStyle")
    }

    func setFullscreen(_ isFullscreen: Bool) async throws {
        throw PlaybackServiceError.unsupported(operation: "setFullscreen")
    }

    func setPictureInPicture(_ isActive: Bool) async throws {
        throw PlaybackServiceError.unsupported(operation: "setPictureInPicture")
    }

    func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: PlaybackServiceError.unsupported(operation: "statusUpdates"))
        }
    }
}

public protocol SubtitleServiceProtocol {
    func preferredSubtitles(for item: MediaItem) async throws -> [SubtitleTrack]
    func preferredSubtitles(
        for query: SubtitleSearchQuery,
        embeddedTracks: [SubtitleTrack],
        localSearchDirectory: URL?
    ) async throws -> [SubtitleTrack]
    func embeddedSubtitles(from playbackStatus: PlaybackStatus) async throws -> [SubtitleTrack]
    func localSubtitles(for query: SubtitleSearchQuery, directory: URL?) async throws -> [SubtitleTrack]
    func searchOnlineSubtitles(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult]
    func downloadSubtitle(_ result: SubtitleSearchResult) async throws -> SubtitleTrack
    func cacheSubtitle(data: Data, fileName: String, languageCode: String, source: SubtitleSource) async throws -> SubtitleTrack
    func cachedSubtitles() async throws -> [CachedSubtitleItem]
    func deleteCachedSubtitle(id: String) async throws
    func selectSubtitle(_ track: SubtitleTrack?, playbackService: any PlaybackServiceProtocol) async throws
}

public extension SubtitleServiceProtocol {
    func preferredSubtitles(
        for query: SubtitleSearchQuery,
        embeddedTracks: [SubtitleTrack],
        localSearchDirectory: URL?
    ) async throws -> [SubtitleTrack] {
        throw SubtitleServiceError.unsupported(operation: "preferredSubtitles(query:)")
    }

    func embeddedSubtitles(from playbackStatus: PlaybackStatus) async throws -> [SubtitleTrack] {
        playbackStatus.subtitleTracks.filter { $0.source == .embedded }
    }

    func localSubtitles(for query: SubtitleSearchQuery, directory: URL?) async throws -> [SubtitleTrack] {
        []
    }

    func searchOnlineSubtitles(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        []
    }

    func downloadSubtitle(_ result: SubtitleSearchResult) async throws -> SubtitleTrack {
        throw SubtitleServiceError.unsupported(operation: "downloadSubtitle")
    }

    func cacheSubtitle(data: Data, fileName: String, languageCode: String, source: SubtitleSource) async throws -> SubtitleTrack {
        throw SubtitleServiceError.unsupported(operation: "cacheSubtitle")
    }

    func cachedSubtitles() async throws -> [CachedSubtitleItem] {
        []
    }

    func deleteCachedSubtitle(id: String) async throws {}

    func selectSubtitle(_ track: SubtitleTrack?, playbackService: any PlaybackServiceProtocol) async throws {
        try await playbackService.selectSubtitleTrack(id: track?.id)
    }
}

public protocol LibraryRepositoryProtocol {
    func items() async throws -> [MediaItem]
    func libraryEntries() async throws -> [LibraryItem]
    func add(_ item: MediaItem) async throws
    func remove(mediaID: String) async throws
    func favorites() async throws -> [MediaItem]
    func addFavorite(_ item: MediaItem) async throws
    func removeFavorite(mediaID: String) async throws
    func watchedItems() async throws -> [WatchedMediaItem]
    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws
    func removeFromHistory(mediaID: String) async throws
    func ratedItems() async throws -> [RatedMediaItem]
    func setRating(_ item: MediaItem, rating: Int) async throws
    func lists() async throws -> [UserList]
    func defaultList() async throws -> UserList
    func createList(name: String) async throws -> UserList
    func createList(name: String, description: String?) async throws -> UserList
    func renameList(id: String, name: String, description: String?) async throws
    func deleteList(id: String) async throws
    func add(_ item: MediaItem, to listID: String) async throws
    func remove(_ mediaID: String, from listID: String) async throws
    func items(in listID: String) async throws -> [MediaItem]
    func watchlistItems(in listID: String) async throws -> [WatchlistItem]
    func updateWatchlistItem(listID: String, mediaID: String, priority: WatchlistPriority, remindLaterAt: Date?) async throws
}

public extension LibraryRepositoryProtocol {
    func libraryEntries() async throws -> [LibraryItem] {
        []
    }

    func removeFromHistory(mediaID: String) async throws {}

    func watchlistItems(in listID: String) async throws -> [WatchlistItem] {
        try await items(in: listID).map { item in
            let bestRelease = item.rankedReleases.first
            return WatchlistItem(
                listID: listID,
                mediaID: item.id,
                addedAt: .distantPast,
                initialQuality: bestRelease?.quality ?? .unknown,
                initialHDR: bestRelease?.hdr ?? .unknown
            )
        }
    }

    func updateWatchlistItem(listID: String, mediaID: String, priority: WatchlistPriority, remindLaterAt: Date?) async throws {}
}

public protocol SettingsRepositoryProtocol {
    var appSettings: AppSettings { get async }
    var subtitleLanguagePriority: [String] { get async }
    var subtitleSettings: SubtitleSettings { get async }

    func setAppSettings(_ settings: AppSettings) async
    func setSubtitleLanguagePriority(_ languages: [String]) async
    func setSubtitleSettings(_ settings: SubtitleSettings) async
    func metadataCredential(forKey key: String) async -> String?
    func setMetadataCredential(_ value: String?, forKey key: String) async
    func clearAllLocalData() async
}

public extension SettingsRepositoryProtocol {
    var appSettings: AppSettings {
        get async { AppSettings() }
    }

    var subtitleSettings: SubtitleSettings {
        get async { SubtitleSettings(languagePreference: SubtitleLanguagePreference(await subtitleLanguagePriority)) }
    }

    func setAppSettings(_ settings: AppSettings) async {}

    func setSubtitleSettings(_ settings: SubtitleSettings) async {
        await setSubtitleLanguagePriority(settings.languagePreference.languageCodes)
    }

    func metadataCredential(forKey key: String) async -> String? {
        nil
    }

    func setMetadataCredential(_ value: String?, forKey key: String) async {}

    func clearAllLocalData() async {}
}

public protocol DiagnosticsServiceProtocol: Sendable {
    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async
    func exportDiagnostics() async -> String
    func exportDiagnosticsPackage() async throws -> URL
    func recentEvents(limit: Int) async -> [DiagnosticsEvent]
}

public extension DiagnosticsServiceProtocol {
    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String] = [:]) async {}

    func exportDiagnosticsPackage() async throws -> URL {
        throw CoreMetadataServiceError.unsupported
    }

    func recentEvents(limit: Int = 20) async -> [DiagnosticsEvent] {
        []
    }
}

public protocol UpdateServiceProtocol {
    var currentStatus: UpdateStatus { get async }
    var automaticallyChecksForUpdates: Bool { get async }
    var lastCheckedAt: Date? { get async }

    func checkForUpdates() async -> UpdateStatus
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) async
}

public extension UpdateServiceProtocol {
    var automaticallyChecksForUpdates: Bool {
        get async { true }
    }

    var lastCheckedAt: Date? {
        get async { nil }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) async {}
}
