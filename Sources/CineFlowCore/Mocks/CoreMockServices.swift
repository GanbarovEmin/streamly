import Foundation

public extension AppEnvironment {
    static func mock() -> AppEnvironment {
        AppEnvironment(
            metadataService: CoreMockMetadataService(),
            torrentEngine: CoreMockTorrentEngine(),
            playbackService: CoreMockPlaybackService(),
            subtitleService: CoreMockSubtitleService(),
            libraryRepository: CoreMockLibraryRepository(),
            settingsRepository: CoreMockSettingsRepository(),
            diagnosticsService: CoreMockDiagnosticsService(),
            updateService: CoreMockUpdateService(),
            keychainService: MockKeychainService()
        )
    }
}

public struct CoreMockMetadataService: MetadataServiceProtocol {
    public init() {}

    public func search(query: String) async throws -> [MediaItem] {
        [
            MediaItem(
                id: "tmdb:movie:603",
                title: "The Matrix",
                kind: .movie,
                overview: "A mock metadata result used while real TMDB integration is not wired.",
                releaseYear: 1999,
                posterPath: nil
            )
        ]
    }
}

public struct CoreMockTorrentEngine: TorrentEngineProtocol {
    public init() {}

    public func searchReleases(for item: MediaItem) async throws -> [TorrentRelease] {
        [
            TorrentRelease(id: "mock-1080p", title: "\(item.title) 1080p", quality: .fullHD, seeders: 120),
            TorrentRelease(id: "mock-2160p", title: "\(item.title) 2160p", quality: .ultraHD, seeders: 80)
        ].sortedByCineFlowRank()
    }
}

public final class CoreMockPlaybackService: PlaybackServiceProtocol {
    private var state: PlaybackState = .idle
    private var status = PlaybackStatus()

    public init() {}

    public var currentState: PlaybackState {
        get async { state }
    }

    public var currentStatus: PlaybackStatus {
        get async { status }
    }

    public func play(_ source: PlaybackMediaSource) async throws {
        status = PlaybackStatus(media: source, state: .playing, duration: 7_200)
        state = source.release.map { .playing($0) } ?? .preparing
    }

    public func play(_ release: TorrentRelease) async throws {
        status = PlaybackStatus(media: PlaybackMediaSource(release: release), state: .playing, duration: 7_200)
        state = .playing(release)
    }

    public func stop() async throws {
        status = PlaybackStatus()
        state = .idle
    }
}

public struct CoreMockSubtitleService: SubtitleServiceProtocol {
    public init() {}

    public func preferredSubtitles(for item: MediaItem) async throws -> [SubtitleTrack] {
        [
            SubtitleTrack(id: "sub-ru", languageCode: "ru", displayName: "Russian", source: .embedded),
            SubtitleTrack(id: "sub-en", languageCode: "en", displayName: "English", source: .openSubtitles)
        ]
    }
}

public final class CoreMockLibraryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedFavorites: [MediaItem]
    private var storedWatchedItems: [WatchedMediaItem]
    private var storedRatedItems: [RatedMediaItem]
    private var storedLists: [UserList]

    public init(storedItems: [MediaItem] = [
        MediaItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: "A local mock library item.",
            releaseYear: 1999,
            posterPath: nil
        )
    ]) {
        self.storedItems = storedItems
        storedFavorites = []
        storedWatchedItems = []
        storedRatedItems = []
        storedLists = []
    }

    public func items() async throws -> [MediaItem] {
        storedItems
    }

    public func add(_ item: MediaItem) async throws {
        upsert(item)
    }

    public func remove(mediaID: String) async throws {
        storedItems.removeAll { $0.id == mediaID }
        storedFavorites.removeAll { $0.id == mediaID }
        storedWatchedItems.removeAll { $0.item.id == mediaID }
        storedRatedItems.removeAll { $0.item.id == mediaID }
        storedLists = storedLists.map { list in
            UserList(
                id: list.id,
                name: list.name,
                itemIDs: list.itemIDs.filter { $0 != mediaID },
                createdAt: list.createdAt,
                updatedAt: Date()
            )
        }
    }

    public func favorites() async throws -> [MediaItem] {
        storedFavorites
    }

    public func addFavorite(_ item: MediaItem) async throws {
        upsert(item)
        if !storedFavorites.contains(where: { $0.id == item.id }) {
            storedFavorites.insert(item, at: 0)
        }
    }

    public func removeFavorite(mediaID: String) async throws {
        storedFavorites.removeAll { $0.id == mediaID }
    }

    public func watchedItems() async throws -> [WatchedMediaItem] {
        storedWatchedItems
    }

    public func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {
        upsert(item)
        storedWatchedItems.removeAll { $0.item.id == item.id }
        storedWatchedItems.insert(WatchedMediaItem(item: item, positionSeconds: positionSeconds), at: 0)
    }

    public func ratedItems() async throws -> [RatedMediaItem] {
        storedRatedItems
    }

    public func setRating(_ item: MediaItem, rating: Int) async throws {
        upsert(item)
        storedRatedItems.removeAll { $0.item.id == item.id }
        storedRatedItems.insert(RatedMediaItem(item: item, rating: rating), at: 0)
    }

    public func lists() async throws -> [UserList] {
        storedLists
    }

    public func defaultList() async throws -> UserList {
        if let existing = storedLists.first(where: { $0.isDefault }) {
            return existing
        }
        let list = UserList(
            id: "default-watchlist",
            name: "Хочу посмотреть",
            description: "Фильмы и сериалы, которые вы хотите посмотреть позже.",
            isDefault: true
        )
        storedLists.insert(list, at: 0)
        return list
    }

    public func createList(name: String) async throws -> UserList {
        try await createList(name: name, description: nil)
    }

    public func createList(name: String, description: String?) async throws -> UserList {
        let list = UserList(name: name, description: description)
        storedLists.insert(list, at: 0)
        return list
    }

    public func renameList(id: String, name: String, description: String?) async throws {
        storedLists = storedLists.map { list in
            guard list.id == id else { return list }
            return UserList(
                id: list.id,
                name: name,
                description: description,
                itemIDs: list.itemIDs,
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    public func deleteList(id: String) async throws {
        storedLists.removeAll { $0.id == id && !$0.isDefault }
    }

    public func add(_ item: MediaItem, to listID: String) async throws {
        upsert(item)
        storedLists = storedLists.map { list in
            guard list.id == listID, !list.itemIDs.contains(item.id) else { return list }
            return UserList(
                id: list.id,
                name: list.name,
                description: list.description,
                itemIDs: list.itemIDs + [item.id],
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    public func remove(_ mediaID: String, from listID: String) async throws {
        storedLists = storedLists.map { list in
            guard list.id == listID else { return list }
            return UserList(
                id: list.id,
                name: list.name,
                description: list.description,
                itemIDs: list.itemIDs.filter { $0 != mediaID },
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    public func items(in listID: String) async throws -> [MediaItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return storedItems.filter { list.itemIDs.contains($0.id) }
    }

    private func upsert(_ item: MediaItem) {
        storedItems.removeAll { $0.id == item.id }
        storedItems.insert(item, at: 0)
    }
}

public final class CoreMockSettingsRepository: SettingsRepositoryProtocol {
    private var settings: AppSettings
    private var subtitleSettingsValue: SubtitleSettings
    private var languages: [String]
    private var metadataCredentials: [String: String]

    public init(settings: AppSettings = AppSettings(), languages: [String] = ["ru", "en"]) {
        self.settings = settings
        subtitleSettingsValue = SubtitleSettings(languagePreference: SubtitleLanguagePreference(languages))
        self.languages = languages
        metadataCredentials = [:]
    }

    public var appSettings: AppSettings {
        get async { settings }
    }

    public var subtitleLanguagePriority: [String] {
        get async { languages }
    }

    public var subtitleSettings: SubtitleSettings {
        get async { subtitleSettingsValue }
    }

    public func setAppSettings(_ settings: AppSettings) async {
        self.settings = settings
    }

    public func setSubtitleLanguagePriority(_ languages: [String]) async {
        self.languages = languages
        subtitleSettingsValue.languagePreference = SubtitleLanguagePreference(languages)
    }

    public func setSubtitleSettings(_ settings: SubtitleSettings) async {
        subtitleSettingsValue = settings
        languages = settings.languagePreference.languageCodes
    }

    public func metadataCredential(forKey key: String) async -> String? {
        metadataCredentials[key]
    }

    public func setMetadataCredential(_ value: String?, forKey key: String) async {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            metadataCredentials[key] = trimmed
        } else {
            metadataCredentials.removeValue(forKey: key)
        }
    }

    public func clearAllLocalData() async {
        settings = AppSettings()
        subtitleSettingsValue = SubtitleSettings()
        languages = ["ru", "en"]
        metadataCredentials.removeAll()
    }
}

public struct CoreMockDiagnosticsService: DiagnosticsServiceProtocol {
    public init() {}

    public func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {}

    public func exportDiagnostics() async -> String {
        "Streamly diagnostics: mock environment, no external engines initialized."
    }

    public func exportDiagnosticsPackage() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Streamly-CoreMock-Diagnostics")
            .appendingPathExtension("zip")
        try Data("core mock diagnostics".utf8).write(to: url)
        return url
    }

    public func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        []
    }
}

public struct CoreMockUpdateService: UpdateServiceProtocol {
    public init() {}

    public var currentStatus: UpdateStatus {
        get async { .idle }
    }

    public var automaticallyChecksForUpdates: Bool {
        get async { true }
    }

    public var lastCheckedAt: Date? {
        get async { nil }
    }

    public func checkForUpdates() async -> UpdateStatus {
        .upToDate
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) async {}
}
