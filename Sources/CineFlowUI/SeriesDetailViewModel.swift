import CineFlowCore
import Foundation

public enum SeriesDetailState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum SeriesDetailTab: String, CaseIterable, Identifiable, Equatable, Sendable {
    case seasons
    case releases
    case trailers
    case similar
    case cast
    case details

    public var id: String { rawValue }
}

public struct SeriesDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let yearRange: String
    public let seasonsCount: Int
    public let rating: String
    public let genres: [String]
    public let overview: String
    public let backdropAccentIndex: Int
    public let posterURL: URL?
    public let backdropURL: URL?

    public init(
        id: String,
        title: String,
        yearRange: String,
        seasonsCount: Int,
        rating: String,
        genres: [String],
        overview: String,
        backdropAccentIndex: Int,
        posterURL: URL? = nil,
        backdropURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.yearRange = yearRange
        self.seasonsCount = seasonsCount
        self.rating = rating
        self.genres = genres
        self.overview = overview
        self.backdropAccentIndex = backdropAccentIndex
        self.posterURL = posterURL
        self.backdropURL = backdropURL
    }
}

public struct SeriesEpisode: Identifiable, Equatable, Sendable {
    public let id: String
    public let seasonID: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let title: String
    public let runtime: String
    public let overview: String
    public let airDate: Date?
    public let thumbnailURL: URL?

    public var isUpcoming: Bool {
        guard let airDate else { return false }
        return airDate > Date()
    }

    public var isReleased: Bool {
        !isUpcoming
    }

    public init(
        id: String,
        seasonID: String,
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        runtime: String,
        overview: String,
        airDate: Date? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.seasonID = seasonID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.runtime = runtime
        self.overview = overview
        self.airDate = airDate
        self.thumbnailURL = thumbnailURL
    }
}

public struct SeriesSeason: Identifiable, Equatable, Sendable {
    public let id: String
    public let seasonNumber: Int
    public let title: String
    public let episodes: [SeriesEpisode]
}

public enum SeriesReleaseScope: Equatable, Sendable {
    case series
    case season(String)
    case episode(String)
}

public struct ScopedSeriesRelease: Equatable, Sendable {
    public let ranked: RankedRelease
    public let scope: SeriesReleaseScope

    public var release: TorrentRelease {
        ranked.release
    }
}

public struct SeriesDetailResponse: Sendable {
    public let series: SeriesDetail
    public let seasons: [SeriesSeason]
    public let releases: [(release: TorrentRelease, scope: SeriesReleaseScope)]
    public let trailers: [MovieTrailer]
    public let similar: [SearchMediaResult]
    public let cast: [MovieCastMember]
    public let progressByEpisodeID: [String: PlaybackProgress]
    public let lastWatchedEpisodeID: String?
}

public protocol SeriesDetailProviderProtocol: Sendable {
    func seriesDetail(id: String) async throws -> SeriesDetailResponse?
    func refreshSeriesDetail(id: String) async throws -> SeriesDetailResponse?
    func clearMetadataCache(id: String) async throws
    func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)]
}

public extension SeriesDetailProviderProtocol {
    func refreshSeriesDetail(id: String) async throws -> SeriesDetailResponse? {
        try await seriesDetail(id: id)
    }

    func clearMetadataCache(id: String) async throws {}

    func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        []
    }
}

public protocol SeriesNotificationStoreProtocol: Sendable {
    func notificationsEnabled(seriesID: String) async -> Bool
    func setNotificationsEnabled(_ enabled: Bool, seriesID: String) async
}

public actor UserDefaultsSeriesNotificationStore: SeriesNotificationStoreProtocol {
    private let userDefaults: UserDefaults
    private let keyPrefix = "streamly.series.notifications."

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func notificationsEnabled(seriesID: String) async -> Bool {
        userDefaults.bool(forKey: keyPrefix + seriesID)
    }

    public func setNotificationsEnabled(_ enabled: Bool, seriesID: String) async {
        userDefaults.set(enabled, forKey: keyPrefix + seriesID)
    }
}

public struct MockSeriesDetailProvider: SeriesDetailProviderProtocol {
    public init() {}

    public func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        guard id == "tmdb:tv:1399" else { return nil }

        let s1e1 = SeriesEpisode(
            id: "got-s1-e1",
            seasonID: "got-s1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Winter Is Coming",
            runtime: "62m",
            overview: "The Stark family is pulled into royal politics as danger grows beyond the Wall."
        )
        let s1e2 = SeriesEpisode(
            id: "got-s1-e2",
            seasonID: "got-s1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "The Kingsroad",
            runtime: "56m",
            overview: "Ned travels south while Jon heads north and Daenerys begins to understand her new life."
        )
        let s2e1 = SeriesEpisode(
            id: "got-s2-e1",
            seasonID: "got-s2",
            seasonNumber: 2,
            episodeNumber: 1,
            title: "The North Remembers",
            runtime: "53m",
            overview: "The war expands as rival kings claim power and Tyrion arrives in King's Landing."
        )
        let s2e2 = SeriesEpisode(
            id: "got-s2-e2",
            seasonID: "got-s2",
            seasonNumber: 2,
            episodeNumber: 2,
            title: "Blackwater",
            runtime: "55m",
            overview: "King's Landing faces a decisive siege as wildfire changes the battle."
        )

        return SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Game of Thrones",
                yearRange: "2011-2019",
                seasonsCount: 2,
                rating: "8.4",
                genres: ["Drama", "Fantasy"],
                overview: "Noble families fight for control of Westeros while an ancient threat gathers beyond the Wall.",
                backdropAccentIndex: 3
            ),
            seasons: [
                SeriesSeason(id: "got-s1", seasonNumber: 1, title: "Season 1", episodes: [s1e1, s1e2]),
                SeriesSeason(id: "got-s2", seasonNumber: 2, title: "Season 2", episodes: [s2e1, s2e2])
            ],
            releases: [
                (
                    TorrentRelease(
                        id: "got-s1-e2-1080p",
                        sourceId: "episode",
                        sourceName: "Episode Vault",
                        title: "Game of Thrones S01E02 1080p",
                        magnetURI: "magnet:?xt=urn:btih:gots1e2",
                        quality: .fullHD,
                        codec: .h264,
                        hdr: .none,
                        audioLanguages: ["en", "ru"],
                        subtitleLanguages: ["en", "ru"],
                        seeders: 580,
                        sizeBytes: 4_800_000_000
                    ),
                    .episode("got-s1-e2")
                ),
                (
                    TorrentRelease(
                        id: "got-series-2160p",
                        sourceId: "series",
                        sourceName: "Archive",
                        title: "Game of Thrones Complete Series 2160p HDR",
                        magnetURI: "magnet:?xt=urn:btih:gotseries2160",
                        quality: .ultraHD,
                        codec: .hevc,
                        hdr: .dolbyVision,
                        audioLanguages: ["en", "ru"],
                        subtitleLanguages: ["en", "ru"],
                        seeders: 220,
                        sizeBytes: 420_000_000_000,
                        trustedUploader: true
                    ),
                    .series
                ),
                (
                    TorrentRelease(
                        id: "got-s2-1080p",
                        sourceId: "season",
                        sourceName: "Season Source",
                        title: "Game of Thrones Season 2 1080p",
                        magnetURI: "magnet:?xt=urn:btih:gots2",
                        quality: .fullHD,
                        codec: .hevc,
                        hdr: .none,
                        audioLanguages: ["en"],
                        subtitleLanguages: ["en", "ru"],
                        seeders: 940,
                        sizeBytes: 38_000_000_000
                    ),
                    .season("got-s2")
                )
            ],
            trailers: [MovieTrailer(id: "got-trailer", title: "Series Trailer", source: "HBO")],
            similar: Self.similarItems(ids: ["tmdb:tv:94997"]),
            cast: [
                MovieCastMember(id: "kit", name: "Kit Harington", role: "Jon Snow"),
                MovieCastMember(id: "emilia", name: "Emilia Clarke", role: "Daenerys Targaryen")
            ],
            progressByEpisodeID: [
                "got-s1-e1": PlaybackProgress(mediaID: "got-s1-e1", positionSeconds: 3_600, durationSeconds: 3_600),
                "got-s1-e2": PlaybackProgress(mediaID: "got-s1-e2", positionSeconds: 1_800, durationSeconds: 3_600)
            ],
            lastWatchedEpisodeID: "got-s1-e2"
        )
    }

    private static func similarItems(ids: [String]) -> [SearchMediaResult] {
        ids.compactMap { id in
            HomeSeedLibrary.developmentItems
                .first { $0.id == id }
                .map(SearchMediaResult.init(item:))
        }
    }

    public func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        guard let response = try await seriesDetail(id: seriesID) else { return [] }
        return response.releases.filter { _, scope in
            switch scope {
            case .series:
                true
            case .season(let seasonID):
                response.seasons.first { $0.id == seasonID }?.episodes.contains { $0.id == episodeID } == true
            case .episode(let scopedEpisodeID):
                scopedEpisodeID == episodeID
            }
        }
    }
}

@MainActor
public final class SeriesDetailViewModel: ObservableObject {
    @Published public private(set) var state: SeriesDetailState = .loading
    @Published public private(set) var series: SeriesDetail?
    @Published public private(set) var seasons: [SeriesSeason] = []
    @Published public private(set) var releases: [ScopedSeriesRelease] = []
    @Published public private(set) var trailers: [MovieTrailer] = []
    @Published public private(set) var similar: [SearchMediaResult] = []
    @Published public private(set) var cast: [MovieCastMember] = []
    @Published public private(set) var progressByEpisodeID: [String: PlaybackProgress] = [:]
    @Published public private(set) var lastWatchedEpisodeID: String?
    @Published public private(set) var selectedSeasonID: String?
    @Published public private(set) var selectedEpisodeID: String?
    @Published public private(set) var mediaItem: MediaItem?
    @Published public private(set) var isInLibrary = false
    @Published public private(set) var isSeriesTracked = false
    @Published public private(set) var episodeNotificationsEnabled = false
    @Published public private(set) var selectedListName: String?
    @Published public private(set) var userRating: Int?
    @Published public private(set) var lastPlayedEpisodeID: String?
    @Published public private(set) var userSources: [UserMediaSource] = []
    @Published public private(set) var selectedUserSourceID: String?
    @Published public private(set) var manualOverrideReleaseID: String?
    @Published public var selectedTab: SeriesDetailTab = .releases

    public let tabs: [SeriesDetailTab] = [.releases, .trailers, .similar, .cast, .details]

    private let seriesID: String
    private let provider: any SeriesDetailProviderProtocol
    private let rankingEngine: ReleaseRankingEngine
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)?
    private let settingsRepository: (any SettingsRepositoryProtocol)?
    private let recommendationService: (any RecommendationServiceProtocol)?
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let notificationStore: any SeriesNotificationStoreProtocol
    private let trackingStore: any SeriesTrackingStoreProtocol
    private let releaseSelectionStore: ReleaseSelectionStoreProtocol
    private var loadGeneration = 0
    private var episodeReleaseGeneration = 0
    private var rankingPreferences: RankingPreferences?

    public init(
        seriesID: String,
        provider: any SeriesDetailProviderProtocol = MockSeriesDetailProvider(),
        rankingEngine: ReleaseRankingEngine = ReleaseRankingEngine(preferences: RankingPreferences(preferredAudioLanguages: ["ru"], preferredSubtitleLanguages: ["ru"], supportsHDR: true)),
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        recommendationService: (any RecommendationServiceProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        notificationStore: any SeriesNotificationStoreProtocol = UserDefaultsSeriesNotificationStore(),
        trackingStore: any SeriesTrackingStoreProtocol = UserDefaultsSeriesTrackingStore(),
        releaseSelectionStore: ReleaseSelectionStoreProtocol = UserDefaultsReleaseSelectionStore()
    ) {
        self.seriesID = seriesID
        self.provider = provider
        self.rankingEngine = rankingEngine
        self.libraryRepository = libraryRepository
        self.userMediaSourceRepository = userMediaSourceRepository
        self.settingsRepository = settingsRepository
        self.recommendationService = recommendationService
        self.diagnosticsService = diagnosticsService
        self.notificationStore = notificationStore
        self.trackingStore = trackingStore
        self.releaseSelectionStore = releaseSelectionStore
    }

    public var selectedSeason: SeriesSeason? {
        guard let selectedSeasonID else { return seasons.first }
        return seasons.first { $0.id == selectedSeasonID } ?? seasons.first
    }

    public var visibleEpisodes: [SeriesEpisode] {
        selectedSeason?.episodes ?? []
    }

    public var selectedEpisode: SeriesEpisode? {
        guard let selectedEpisodeID else { return visibleEpisodes.first }
        return allEpisodes.first { $0.id == selectedEpisodeID } ?? visibleEpisodes.first
    }

    public var lastWatchedEpisode: SeriesEpisode? {
        guard let lastWatchedEpisodeID else { return nil }
        return allEpisodes.first { $0.id == lastWatchedEpisodeID }
    }

    public var watchNextEpisode: WatchNextEpisode? {
        guard let series else { return nil }
        return WatchNextResolver.resolve(
            series: series,
            seasons: seasons,
            progressByEpisodeID: progressByEpisodeID,
            lastWatchedEpisodeID: lastWatchedEpisodeID
        )
    }

    public var continueWatchingTitle: String {
        watchNextEpisode?.ctaTitle ?? "Continue"
    }

    public var newEpisodeBadgeText: String? {
        guard isSeriesTracked,
              let next = watchNextEpisode,
              !progressByEpisodeID.isEmpty,
              next.episode.isReleased else {
            return nil
        }
        return "New Episode Available"
    }

    public var seasonProgressSummaries: [WatchNextSeasonProgress] {
        WatchNextResolver.seasonProgressSummaries(
            seasons: seasons,
            progressByEpisodeID: progressByEpisodeID
        )
    }

    public var overallProgress: Double {
        guard !allEpisodes.isEmpty else { return 0 }

        let watchedFractions = allEpisodes.reduce(0.0) { result, episode in
            result + progressValue(for: episode.id)
        }

        return min(max(watchedFractions / Double(allEpisodes.count), 0), 1)
    }

    private var allEpisodes: [SeriesEpisode] {
        seasons.flatMap(\.episodes)
    }

    public var allReleasedEpisodes: [SeriesEpisode] {
        allEpisodes
            .filter(\.isReleased)
            .sorted {
                if $0.seasonNumber != $1.seasonNumber {
                    return $0.seasonNumber < $1.seasonNumber
                }
                return $0.episodeNumber < $1.episodeNumber
            }
    }

    public var bestPlayableRelease: ScopedSeriesRelease? {
        if let manualOverrideReleaseID,
           let manual = releases.first(where: { $0.release.id == manualOverrideReleaseID }) {
            return manual
        }
        return releases.first
    }

    public var bestReleaseHighlight: DetailReleaseHighlight? {
        guard let scoped = bestPlayableRelease else { return nil }
        return DetailReleaseHighlight(
            releaseID: scoped.release.id,
            title: scoped.release.title,
            badge: "Best Release",
            primaryMetadata: Self.primaryMetadataLine(for: scoped.release),
            secondaryMetadata: Self.secondaryMetadataLine(for: scoped.release),
            scopeLabel: Self.scopeLabel(for: scoped.scope)
        )
    }

    public var selectedEpisodePresentation: SeriesEpisodePresentation? {
        guard let episode = selectedEpisode else { return nil }
        let progress = progressByEpisodeID[episode.id] == nil ? nil : progressValue(for: episode.id)
        return SeriesEpisodePresentation(
            label: Self.episodeLabel(for: episode),
            title: episode.title,
            progressFraction: progress
        )
    }

    public var continueEpisodeLabel: String? {
        guard let episode = watchNextEpisode?.episode else { return nil }
        return "\(Self.episodeLabel(for: episode)) \(episode.title)"
    }

    public var primaryWatchActionTitle: String {
        if let episode = watchNextEpisode?.episode {
            return "Продолжить \(Self.episodeLabel(for: episode))"
        }
        if bestPlayableRelease != nil {
            return "Смотреть лучший релиз"
        }
        if userSources.contains(where: \.isPlayableLocalFile) {
            return "Смотреть локальный файл"
        }
        return "Выбрать локальный файл"
    }

    public var heroMetadataBadges: [DetailHeroBadge] {
        guard let series else { return [] }
        var badges = [
            series.yearRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Years n/a" : series.yearRange,
            series.seasonsCount == 1 ? "1 season" : "\(series.seasonsCount) seasons",
            series.rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "IMDb n/a" : "IMDb \(series.rating)"
        ]
        badges.append(contentsOf: series.genres.prefix(3))
        return badges.map(DetailHeroBadge.init(title:))
    }

    public var ratingSummary: RatingSummary {
        guard let series else { return .empty }
        return RatingAggregator.summary(
            tmdbRating: series.rating,
            userRating: userRating,
            year: Self.firstYear(from: series.yearRange)
        )
    }

    public var releaseFallbackTitle: String? {
        releases.isEmpty ? "Релизы для серии пока не найдены" : nil
    }

    public var castFallbackTitle: String? {
        cast.isEmpty ? "Актёры пока не загружены" : nil
    }

    public var episodeFallbackTitle: String? {
        allEpisodes.isEmpty ? "Список серий пока пуст" : nil
    }

    public func nextReleasedEpisode(after episode: SeriesEpisode) -> SeriesEpisode? {
        guard let index = allReleasedEpisodes.firstIndex(where: { $0.id == episode.id }) else { return nil }
        let nextIndex = allReleasedEpisodes.index(after: index)
        guard nextIndex < allReleasedEpisodes.endIndex else { return nil }
        return allReleasedEpisodes[nextIndex]
    }

    public func nextEpisodePrompt(after episode: SeriesEpisode) -> PlayerNextEpisodePrompt? {
        guard let series, let next = nextReleasedEpisode(after: episode) else { return nil }
        let scopedRelease = playableRelease(for: next)
        let requiresManualSelection = scopedRelease == nil
        return PlayerNextEpisodePrompt(
            title: "\(Self.episodeLabel(for: next)) \(next.title)",
            subtitle: "Next Episode · \(next.runtime)",
            actionTitle: requiresManualSelection ? "Choose Release" : "Watch Now",
            cancelTitle: "Cancel",
            nextEpisodeAction: PlayerNextEpisodeAction(
                mediaID: series.id,
                release: scopedRelease?.release,
                fallbackReleases: releases.map(\.release),
                selectionContext: PlaybackSelectionContext(
                    mediaID: series.id,
                    displayTitle: series.title,
                    mediaKind: .series,
                    seasonNumber: next.seasonNumber,
                    episodeNumber: next.episodeNumber,
                    episodeID: next.id
                ),
                requiresManualReleaseSelection: requiresManualSelection
            )
        )
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        do {
            guard let response = try await provider.seriesDetail(id: seriesID) else {
                guard generation == loadGeneration, !Task.isCancelled else { return }
                series = nil
                seasons = []
                releases = []
                trailers = []
                similar = []
                cast = []
                progressByEpisodeID = [:]
                lastWatchedEpisodeID = nil
                mediaItem = nil
                state = .empty
                return
            }

            guard generation == loadGeneration, !Task.isCancelled else { return }
            await refreshRankingPreferences()
            series = response.series
            mediaItem = response.series.mediaItem()
            episodeNotificationsEnabled = await notificationStore.notificationsEnabled(seriesID: seriesID)
            seasons = response.seasons
            trailers = response.trailers
            similar = await resolvedSimilarItems(for: response)
            cast = response.cast
            progressByEpisodeID = response.progressByEpisodeID
            lastWatchedEpisodeID = response.lastWatchedEpisodeID
            selectedSeasonID = response.seasons.first?.id
            selectedEpisodeID = response.seasons.first?.episodes.first?.id
            releases = rankScopedReleases(response.releases)
            refreshManualOverride()
            await refreshLibraryState()
            await refreshTrackingState()
            await refreshUserSources()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            state = .loaded
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .metadata)
            state = .failed(cineFlowError.userMessage)
            await diagnosticsService?.log(cineFlowError, operation: "seriesDetail.load", metadata: ["seriesID": seriesID])
        }
    }

    public func refreshMetadata() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            guard let response = try await provider.refreshSeriesDetail(id: seriesID) else {
                guard generation == loadGeneration, !Task.isCancelled else { return }
                state = .empty
                return
            }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            await apply(response: response)
            state = .loaded
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .metadata)
            await diagnosticsService?.log(cineFlowError, operation: "seriesDetail.refreshMetadata", metadata: ["seriesID": seriesID])
        }
    }

    public func clearMetadataCacheForItem() async {
        do {
            try await provider.clearMetadataCache(id: seriesID)
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .cache)
            await diagnosticsService?.log(cineFlowError, operation: "seriesDetail.clearMetadataCache", metadata: ["seriesID": seriesID])
        }
    }

    public func selectSeason(id: String) {
        guard seasons.contains(where: { $0.id == id }) else { return }
        selectedSeasonID = id
        selectedEpisodeID = selectedSeason?.episodes.first?.id
    }

    public func selectEpisode(id: String) {
        guard allEpisodes.contains(where: { $0.id == id }) else { return }
        selectedEpisodeID = id
        refreshManualOverride()
    }

    public func selectSeasonAndLoadReleases(id: String) async {
        selectSeason(id: id)
        if let episodeID = selectedEpisodeID {
            await selectEpisodeAndLoadReleases(id: episodeID)
        }
    }

    public func selectEpisodeAndLoadReleases(id: String) async {
        selectEpisode(id: id)
        guard selectedEpisodeID == id else { return }
        if selectedEpisode?.isUpcoming == true {
            releases = []
            return
        }
        await loadReleasesForEpisode(id: id)
    }

    public func playEpisode(id: String) {
        guard allEpisodes.contains(where: { $0.id == id }) else { return }
        selectedEpisodeID = id
        lastWatchedEpisodeID = id
        lastPlayedEpisodeID = id
        if let mediaItem, let libraryRepository {
            Task {
                try? await libraryRepository.markWatched(mediaItem, positionSeconds: 0)
            }
        }
    }

    @discardableResult
    public func playBestRelease() -> TorrentRelease? {
        guard let release = bestPlayableRelease?.release else { return nil }
        if let episodeID = selectedEpisode?.id {
            playEpisode(id: episodeID)
        }
        return release
    }

    public func playManualRelease(_ release: TorrentRelease) {
        releaseSelectionStore.setReleaseID(release.id, for: releaseSelectionKey)
        manualOverrideReleaseID = release.id
        if let episodeID = selectedEpisode?.id {
            playEpisode(id: episodeID)
        }
    }

    public func clearManualReleaseOverride() {
        releaseSelectionStore.setReleaseID(nil, for: releaseSelectionKey)
        manualOverrideReleaseID = nil
    }

    public func selectUserSource(_ source: UserMediaSource) {
        selectedUserSourceID = source.id
    }

    public func addLocalSource(url: URL) async {
        guard let userMediaSourceRepository else { return }
        let source = UserMediaSource(
            mediaID: seriesID,
            displayName: url.deletingPathExtension().lastPathComponent,
            kind: .localFile,
            url: url
        )
        try? await userMediaSourceRepository.save(source)
        selectedUserSourceID = source.id
        await refreshUserSources()
    }

    public func continueWatching() {
        guard let episodeID = watchNextEpisode?.episode.id ?? lastWatchedEpisodeID else { return }
        playEpisode(id: episodeID)
    }

    public func updateProgress(episodeID: String, positionSeconds: Double, durationSeconds: Double) {
        guard allEpisodes.contains(where: { $0.id == episodeID }) else { return }
        progressByEpisodeID[episodeID] = PlaybackProgress(
            mediaID: seriesID,
            episodeID: episodeID,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
        lastWatchedEpisodeID = episodeID
    }

    public func removeFromHistory() async {
        progressByEpisodeID = [:]
        lastWatchedEpisodeID = nil
        lastPlayedEpisodeID = nil
        guard let libraryRepository else { return }
        try? await libraryRepository.removeFromHistory(mediaID: seriesID)
    }

    public func progressValue(for episodeID: String) -> Double {
        guard
            let progress = progressByEpisodeID[episodeID],
            let duration = progress.durationSeconds,
            duration > 0
        else {
            return 0
        }

        return min(max(progress.positionSeconds / duration, 0), 1)
    }

    public func addToLibrary() {
        isInLibrary = true
        isSeriesTracked = true
        guard let mediaItem, let libraryRepository else { return }
        Task {
            await trackingStore.setTracked(true, seriesID: seriesID)
            try? await libraryRepository.add(mediaItem)
        }
    }

    public func setEpisodeNotificationsEnabled(_ enabled: Bool) async {
        episodeNotificationsEnabled = enabled
        if enabled {
            await setSeriesTracked(true)
        }
        await notificationStore.setNotificationsEnabled(enabled, seriesID: seriesID)
    }

    public func setSeriesTracked(_ tracked: Bool) async {
        isSeriesTracked = tracked
        await trackingStore.setTracked(tracked, seriesID: seriesID)
    }

    public func addToList(_ name: String) {
        selectedListName = name
        isSeriesTracked = true
        guard let mediaItem, let libraryRepository else { return }
        Task {
            await trackingStore.setTracked(true, seriesID: seriesID)
            let lists = try await libraryRepository.lists()
            let list: UserList
            if name == "Хочу посмотреть" {
                list = try await libraryRepository.defaultList()
            } else if let existingList = lists.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                list = existingList
            } else {
                list = try await libraryRepository.createList(name: name)
            }
            try await libraryRepository.add(mediaItem, to: list.id)
        }
    }

    public func setUserRating(_ rating: Int) {
        let boundedRating = min(max(rating, 1), 10)
        userRating = boundedRating
        guard let mediaItem, let libraryRepository else { return }
        Task {
            try? await libraryRepository.setRating(mediaItem, rating: boundedRating)
        }
    }

    private func rankScopedReleases(_ releases: [(release: TorrentRelease, scope: SeriesReleaseScope)]) -> [ScopedSeriesRelease] {
        let scopeByReleaseID = Dictionary(uniqueKeysWithValues: releases.map { ($0.release.id, $0.scope) })

        return currentRankingEngine.rank(releases.map(\.release)).compactMap { ranked in
            guard let scope = scopeByReleaseID[ranked.release.id] else { return nil }
            return ScopedSeriesRelease(ranked: ranked, scope: scope)
        }
    }

    private static func primaryMetadataLine(for release: TorrentRelease) -> String {
        var values = [release.qualityLabel]
        if release.hdr != .none, release.hdr != .unknown {
            values.append(release.hdr.displayLabel)
        }
        if release.codec != .unknown {
            values.append(release.codec.rawValue)
        }
        return values.joined(separator: " · ")
    }

    private static func secondaryMetadataLine(for release: TorrentRelease) -> String {
        "\(release.seeders) seeders · \(release.compactSizeLabel) · \(release.sourceName)"
    }

    private static func firstYear(from yearRange: String) -> Int? {
        yearRange
            .split(separator: "-")
            .first
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func scopeLabel(for scope: SeriesReleaseScope) -> String {
        switch scope {
        case .series:
            "Whole series"
        case .season:
            "Season"
        case .episode:
            "Episode"
        }
    }

    private var currentRankingEngine: ReleaseRankingEngine {
        rankingPreferences.map(ReleaseRankingEngine.init(preferences:)) ?? rankingEngine
    }

    private func apply(response: SeriesDetailResponse) async {
        await refreshRankingPreferences()
        series = response.series
        mediaItem = response.series.mediaItem()
        episodeNotificationsEnabled = await notificationStore.notificationsEnabled(seriesID: seriesID)
        seasons = response.seasons
        trailers = response.trailers
        similar = await resolvedSimilarItems(for: response)
        cast = response.cast
        progressByEpisodeID = response.progressByEpisodeID
        lastWatchedEpisodeID = response.lastWatchedEpisodeID
        selectedSeasonID = response.seasons.first?.id
        selectedEpisodeID = response.seasons.first?.episodes.first?.id
        releases = rankScopedReleases(response.releases)
        refreshManualOverride()
        await refreshLibraryState()
        await refreshTrackingState()
        await refreshUserSources()
    }

    private var releaseSelectionKey: String {
        guard let selectedEpisodeID else { return seriesID }
        return "\(seriesID):\(selectedEpisodeID)"
    }

    private func refreshRankingPreferences() async {
        guard let settingsRepository else {
            rankingPreferences = nil
            return
        }
        let settings = await settingsRepository.appSettings
        let subtitleLanguages = await settingsRepository.subtitleLanguagePriority
        rankingPreferences = settings.playback.rankingPreferences(
            preferredSubtitleLanguages: subtitleLanguages,
            supportsHDR: true
        )
    }

    private func resolvedSimilarItems(for response: SeriesDetailResponse) async -> [SearchMediaResult] {
        guard await localRecommendationsEnabled else { return [] }
        guard let recommendationService else { return response.similar }
        let seedSimilar = response.similar.map(Self.mediaItem)
        let recommendations = (try? await recommendationService.recommendations(
            for: response.series.mediaItem(),
            seedSimilar: seedSimilar,
            limit: 12
        )) ?? []
        return recommendations.map(SearchMediaResult.init(mediaItem:))
    }

    private var localRecommendationsEnabled: Bool {
        get async {
            guard let settingsRepository else { return true }
            return await settingsRepository.appSettings.recommendations.localRecommendationsEnabled
        }
    }

    private static func mediaItem(from result: SearchMediaResult) -> MediaItem {
        MediaItem(
            id: result.id,
            title: result.title,
            kind: result.kind == .series ? .series : .movie,
            overview: result.overview,
            releaseYear: result.year > 0 ? result.year : nil,
            posterPath: result.artworkURL?.absoluteString,
            metadata: MediaMetadata(
                tmdbId: abs(result.id.hashValue % 10_000),
                title: result.title,
                originalTitle: result.title,
                overview: result.overview,
                year: result.year > 0 ? result.year : nil,
                rating: result.ratingScore,
                posterURL: result.artworkURL
            )
        )
    }

    private func refreshManualOverride() {
        guard let releaseID = releaseSelectionStore.releaseID(for: releaseSelectionKey),
              releases.contains(where: { $0.release.id == releaseID }) else {
            manualOverrideReleaseID = nil
            return
        }
        manualOverrideReleaseID = releaseID
    }

    private func loadReleasesForEpisode(id: String) async {
        episodeReleaseGeneration += 1
        let generation = episodeReleaseGeneration
        do {
            await refreshRankingPreferences()
            let episodeReleases = try await provider.episodeReleases(seriesID: seriesID, episodeID: id)
            guard generation == episodeReleaseGeneration, selectedEpisodeID == id, !Task.isCancelled else { return }
            releases = rankScopedReleases(episodeReleases)
            refreshManualOverride()
        } catch {
            guard generation == episodeReleaseGeneration, selectedEpisodeID == id, !Task.isCancelled else { return }
            releases = []
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .source)
            await diagnosticsService?.log(
                cineFlowError,
                operation: "seriesDetail.episodeReleases",
                metadata: ["seriesID": seriesID, "episodeID": id]
            )
        }
    }

    private func refreshLibraryState() async {
        guard let libraryRepository, let mediaItem else { return }
        do {
            async let items = libraryRepository.items()
            async let ratedItems = libraryRepository.ratedItems()
            isInLibrary = try await items.contains { $0.id == mediaItem.id }
            userRating = try await ratedItems.first { $0.item.id == mediaItem.id }?.rating
        } catch {
            isInLibrary = false
            userRating = nil
        }
    }

    private func refreshTrackingState() async {
        let stored = await trackingStore.isTracked(seriesID: seriesID)
        if stored || isInLibrary {
            isSeriesTracked = true
            if isInLibrary && !stored {
                await trackingStore.setTracked(true, seriesID: seriesID)
            }
        } else {
            isSeriesTracked = false
        }
    }

    private func refreshUserSources() async {
        guard let userMediaSourceRepository else {
            userSources = []
            selectedUserSourceID = nil
            return
        }
        do {
            userSources = try await userMediaSourceRepository.sources(for: seriesID)
            if selectedUserSourceID == nil {
                selectedUserSourceID = userSources.first?.id
            }
        } catch {
            userSources = []
            selectedUserSourceID = nil
        }
    }

    private func playableRelease(for episode: SeriesEpisode) -> ScopedSeriesRelease? {
        releases.first { scoped in
            switch scoped.scope {
            case .series:
                true
            case .season(let seasonID):
                seasonID == episode.seasonID
            case .episode(let episodeID):
                episodeID == episode.id
            }
        }
    }

    private static func episodeLabel(for episode: SeriesEpisode) -> String {
        String(format: "S%02dE%02d", episode.seasonNumber, episode.episodeNumber)
    }
}

private extension SeriesDetail {
    func mediaItem() -> MediaItem {
        let startYear = Int(yearRange.prefix(4))
        return MediaItem(
            id: id,
            title: title,
            kind: .series,
            overview: overview,
            releaseYear: startYear,
            posterPath: nil
        )
    }
}
