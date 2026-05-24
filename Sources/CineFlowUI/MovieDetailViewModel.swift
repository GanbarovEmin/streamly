import CineFlowCore
import Foundation

public enum MovieDetailState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum MovieDetailTab: String, CaseIterable, Identifiable, Equatable, Sendable {
    case releases
    case trailers
    case similar
    case cast
    case details

    public var id: String { rawValue }
}

public struct MovieDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let originalTitle: String
    public let year: Int
    public let runtime: String
    public let genres: [String]
    public let tmdbRating: String
    public let imdbRating: String
    public let overview: String
    public let backdropAccentIndex: Int
    public let posterURL: URL?
    public let backdropURL: URL?
    public let logoURL: URL?

    public init(
        id: String,
        title: String,
        originalTitle: String,
        year: Int,
        runtime: String,
        genres: [String],
        tmdbRating: String,
        imdbRating: String,
        overview: String,
        backdropAccentIndex: Int,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.runtime = runtime
        self.genres = genres
        self.tmdbRating = tmdbRating
        self.imdbRating = imdbRating
        self.overview = overview
        self.backdropAccentIndex = backdropAccentIndex
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
    }
}

public struct MovieCastMember: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: String

    public let profileURL: URL?

    public init(id: String, name: String, role: String, profileURL: URL? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.profileURL = profileURL
    }
}

public struct MovieTrailer: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: String
}

public struct MovieDetailResponse: Equatable, Sendable {
    public let movie: MovieDetail
    public let releases: [TorrentRelease]
    public let trailers: [MovieTrailer]
    public let similar: [SearchMediaResult]
    public let cast: [MovieCastMember]
    public let progress: PlaybackProgress?
}

public protocol MovieDetailProviderProtocol: Sendable {
    func movieDetail(id: String) async throws -> MovieDetailResponse?
    func refreshMovieDetail(id: String) async throws -> MovieDetailResponse?
    func clearMetadataCache(id: String) async throws
}

public extension MovieDetailProviderProtocol {
    func refreshMovieDetail(id: String) async throws -> MovieDetailResponse? {
        try await movieDetail(id: id)
    }

    func clearMetadataCache(id: String) async throws {}
}

public struct MockMovieDetailProvider: MovieDetailProviderProtocol {
    public init() {}

    public func movieDetail(id: String) async throws -> MovieDetailResponse? {
        guard id == "tmdb:movie:603" else { return nil }

        let movie = MovieDetail(
            id: "tmdb:movie:603",
            title: "The Matrix",
            originalTitle: "The Matrix",
            year: 1999,
            runtime: "2h 16m",
            genres: ["Sci-Fi", "Action"],
            tmdbRating: "8.2",
            imdbRating: "8.7",
            overview: "A hacker discovers that reality is a simulated world controlled by machines, then joins a rebellion to fight back.",
            backdropAccentIndex: 2
        )

        return MovieDetailResponse(
            movie: movie,
            releases: [
                TorrentRelease(
                    id: "matrix-1080p-bluray",
                    sourceId: "cinemahub",
                    sourceName: "CinemaHub",
                    title: "The Matrix 1080p BluRay",
                    magnetURI: "magnet:?xt=urn:btih:matrix1080",
                    quality: .fullHD,
                    codec: .h264,
                    hdr: .none,
                    audioLanguages: ["en", "ru"],
                    subtitleLanguages: ["en", "ru", "az"],
                    seeders: 1_200,
                    leechers: 84,
                    sizeBytes: 12_200_000_000,
                    uploadDate: Date(timeIntervalSince1970: 1_799_200_000),
                    trustedUploader: true
                ),
                TorrentRelease(
                    id: "matrix-2160p-web",
                    sourceId: "cinemahub",
                    sourceName: "CinemaHub",
                    title: "The Matrix 2160p WEB-DL",
                    magnetURI: "magnet:?xt=urn:btih:matrix2160web",
                    quality: .ultraHD,
                    codec: .hevc,
                    hdr: .none,
                    audioLanguages: ["en"],
                    subtitleLanguages: ["en"],
                    seeders: 410,
                    leechers: 36,
                    sizeBytes: 24_800_000_000,
                    uploadDate: Date(timeIntervalSince1970: 1_799_800_000)
                ),
                TorrentRelease(
                    id: "matrix-2160p-hdr-remux",
                    sourceId: "archive",
                    sourceName: "Archive",
                    title: "The Matrix 2160p HDR REMUX",
                    magnetURI: "magnet:?xt=urn:btih:matrix2160hdr",
                    quality: .ultraHD,
                    codec: .hevc,
                    hdr: .dolbyVision,
                    audioLanguages: ["en", "ru"],
                    subtitleLanguages: ["en", "ru"],
                    seeders: 92,
                    leechers: 12,
                    sizeBytes: 78_400_000_000,
                    uploadDate: Date(timeIntervalSince1970: 1_798_800_000),
                    trustedUploader: true
                )
            ],
            trailers: [
                MovieTrailer(id: "trailer-main", title: "Official Trailer", source: "YouTube"),
                MovieTrailer(id: "trailer-legacy", title: "Theatrical Trailer", source: "Apple TV")
            ],
            similar: Self.similarItems(ids: ["tmdb:movie:27205", "tmdb:movie:157336"]),
            cast: [
                MovieCastMember(id: "keanu", name: "Keanu Reeves", role: "Neo"),
                MovieCastMember(id: "carrie", name: "Carrie-Anne Moss", role: "Trinity"),
                MovieCastMember(id: "laurence", name: "Laurence Fishburne", role: "Morpheus")
            ],
            progress: PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 3_400, durationSeconds: 8_160)
        )
    }

    private static func similarItems(ids: [String]) -> [SearchMediaResult] {
        ids.compactMap { id in
            HomeSeedLibrary.developmentItems
                .first { $0.id == id }
                .map(SearchMediaResult.init(item:))
        }
    }
}

@MainActor
public final class MovieDetailViewModel: ObservableObject {
    @Published public private(set) var state: MovieDetailState = .loading
    @Published public private(set) var movie: MovieDetail?
    @Published public private(set) var releases: [RankedRelease] = []
    @Published public private(set) var trailers: [MovieTrailer] = []
    @Published public private(set) var similar: [SearchMediaResult] = []
    @Published public private(set) var cast: [MovieCastMember] = []
    @Published public private(set) var progress: PlaybackProgress?
    @Published public private(set) var mediaItem: MediaItem?
    @Published public private(set) var isFavorite = false
    @Published public private(set) var isInLibrary = false
    @Published public private(set) var isWatched = false
    @Published public private(set) var selectedListName: String?
    @Published public private(set) var userRating: Int?
    @Published public private(set) var lastPlayedReleaseID: String?
    @Published public private(set) var copiedMagnetURI: String?
    @Published public private(set) var userSources: [UserMediaSource] = []
    @Published public private(set) var selectedUserSourceID: String?
    @Published public private(set) var manualOverrideReleaseID: String?
    @Published public var selectedTab: MovieDetailTab = .details

    public let tabs: [MovieDetailTab] = [.trailers, .similar, .cast, .details]

    private let mediaID: String
    private let provider: any MovieDetailProviderProtocol
    private let rankingEngine: ReleaseRankingEngine
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let settingsRepository: (any SettingsRepositoryProtocol)?
    private let recommendationService: (any RecommendationServiceProtocol)?
    private let userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)?
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let releaseSelectionStore: ReleaseSelectionStoreProtocol
    private var rankingPreferences: RankingPreferences?
    private var loadGeneration = 0

    public init(
        mediaID: String,
        provider: any MovieDetailProviderProtocol = MockMovieDetailProvider(),
        rankingEngine: ReleaseRankingEngine = ReleaseRankingEngine(preferences: RankingPreferences(preferredAudioLanguages: ["ru"], preferredSubtitleLanguages: ["ru"], supportsHDR: true)),
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        recommendationService: (any RecommendationServiceProtocol)? = nil,
        userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        releaseSelectionStore: ReleaseSelectionStoreProtocol = UserDefaultsReleaseSelectionStore()
    ) {
        self.mediaID = mediaID
        self.provider = provider
        self.rankingEngine = rankingEngine
        self.libraryRepository = libraryRepository
        self.settingsRepository = settingsRepository
        self.recommendationService = recommendationService
        self.userMediaSourceRepository = userMediaSourceRepository
        self.diagnosticsService = diagnosticsService
        self.releaseSelectionStore = releaseSelectionStore
    }

    public var hasContinueWatching: Bool {
        progress != nil
    }

    public var progressValue: Double {
        guard let progress, let durationSeconds = progress.durationSeconds, durationSeconds > 0 else { return 0 }
        return min(max(progress.positionSeconds / durationSeconds, 0), 1)
    }

    public var sourceSummary: String {
        guard !releases.isEmpty else {
            return userSources.isEmpty ? "Локальный файл не выбран" : "\(userSources.count) локальных источников"
        }

        let best = releases[0].release
        let quality = best.qualityLabel
        let providerCount = Set(releases.map(\.release.sourceName)).count
        return "\(releases.count) sources · best \(quality) · \(best.seeders) seeders · \(providerCount) provider\(providerCount == 1 ? "" : "s")"
    }

    public var bestPlayableRelease: RankedRelease? {
        if let manualOverrideReleaseID,
           let manual = releases.first(where: { $0.release.id == manualOverrideReleaseID }) {
            return manual
        }
        return releases.first
    }

    public var bestReleaseHighlight: DetailReleaseHighlight? {
        guard let ranked = releases.first else { return nil }
        return DetailReleaseHighlight(
            releaseID: ranked.release.id,
            title: ranked.release.title,
            badge: "Best Release",
            primaryMetadata: Self.primaryMetadataLine(for: ranked.release),
            secondaryMetadata: Self.secondaryMetadataLine(for: ranked.release)
        )
    }

    public var primaryWatchActionTitle: String {
        if bestPlayableRelease != nil {
            return "Смотреть лучший релиз"
        }
        if userSources.contains(where: \.isPlayableLocalFile) {
            return "Смотреть локальный файл"
        }
        return "Выбрать локальный файл"
    }

    public var heroMetadataBadges: [DetailHeroBadge] {
        guard let movie else { return [] }
        var badges: [String] = [
            movie.year > 0 ? String(movie.year) : "Год неизвестен",
            movie.runtime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Runtime n/a" : movie.runtime,
            movie.imdbRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "IMDb n/a" : "IMDb \(movie.imdbRating)"
        ]
        badges.append(contentsOf: movie.genres.prefix(3))
        return badges.map(DetailHeroBadge.init(title:))
    }

    public var ratingSummary: RatingSummary {
        guard let movie else { return .empty }
        return RatingAggregator.summary(
            tmdbRating: movie.tmdbRating,
            imdbRating: movie.imdbRating,
            userRating: userRating,
            year: movie.year > 0 ? movie.year : nil
        )
    }

    public var releaseFallbackTitle: String? {
        releases.isEmpty ? "Релизы пока не найдены" : nil
    }

    public var castFallbackTitle: String? {
        cast.isEmpty ? "Актёры пока не загружены" : nil
    }

    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        do {
            guard let response = try await provider.movieDetail(id: mediaID) else {
                guard generation == loadGeneration, !Task.isCancelled else { return }
                movie = nil
                releases = []
                trailers = []
                similar = []
                cast = []
                progress = nil
                mediaItem = nil
                state = .empty
                return
            }

            guard generation == loadGeneration, !Task.isCancelled else { return }
            await refreshRankingPreferences()
            movie = response.movie
            mediaItem = response.movie.mediaItem()
            releases = currentRankingEngine.rank(response.releases)
            refreshManualOverride()
            trailers = response.trailers
            similar = await resolvedSimilarItems(for: response)
            cast = response.cast
            progress = response.progress
            await refreshLibraryState()
            await refreshUserSources()
            guard generation == loadGeneration, !Task.isCancelled else { return }
            state = .loaded
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .metadata)
            state = .failed(cineFlowError.userMessage)
            await diagnosticsService?.log(cineFlowError, operation: "movieDetail.load", metadata: ["mediaID": mediaID])
        }
    }

    public func refreshMetadata() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            guard let response = try await provider.refreshMovieDetail(id: mediaID) else {
                guard generation == loadGeneration, !Task.isCancelled else { return }
                state = .empty
                return
            }
            guard generation == loadGeneration, !Task.isCancelled else { return }
            await apply(response: response)
            state = .loaded
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .metadata)
            await diagnosticsService?.log(cineFlowError, operation: "movieDetail.refreshMetadata", metadata: ["mediaID": mediaID])
        }
    }

    public func clearMetadataCacheForItem() async {
        do {
            try await provider.clearMetadataCache(id: mediaID)
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .cache)
            await diagnosticsService?.log(cineFlowError, operation: "movieDetail.clearMetadataCache", metadata: ["mediaID": mediaID])
        }
    }

    public func play(_ release: TorrentRelease) {
        lastPlayedReleaseID = release.id
    }

    @discardableResult
    public func playBestRelease() -> TorrentRelease? {
        guard let release = releases.first?.release else { return nil }
        play(release)
        return release
    }

    public func playManualRelease(_ release: TorrentRelease) {
        releaseSelectionStore.setReleaseID(release.id, for: mediaID)
        manualOverrideReleaseID = release.id
        play(release)
    }

    public func clearManualReleaseOverride() {
        releaseSelectionStore.setReleaseID(nil, for: mediaID)
        manualOverrideReleaseID = nil
    }

    public func selectUserSource(_ source: UserMediaSource) {
        selectedUserSourceID = source.id
    }

    public func addLocalSource(url: URL) async {
        guard let userMediaSourceRepository else { return }
        let source = UserMediaSource(
            mediaID: mediaID,
            displayName: url.deletingPathExtension().lastPathComponent,
            kind: .localFile,
            url: url
        )
        try? await userMediaSourceRepository.save(source)
        selectedUserSourceID = source.id
        await refreshUserSources()
    }

    private var currentRankingEngine: ReleaseRankingEngine {
        rankingPreferences.map(ReleaseRankingEngine.init(preferences:)) ?? rankingEngine
    }

    private func apply(response: MovieDetailResponse) async {
        await refreshRankingPreferences()
        movie = response.movie
        mediaItem = response.movie.mediaItem()
        releases = currentRankingEngine.rank(response.releases)
        refreshManualOverride()
        trailers = response.trailers
        similar = await resolvedSimilarItems(for: response)
        cast = response.cast
        progress = response.progress
        await refreshLibraryState()
        await refreshUserSources()
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

    private func resolvedSimilarItems(for response: MovieDetailResponse) async -> [SearchMediaResult] {
        guard await localRecommendationsEnabled else { return [] }
        guard let recommendationService else { return response.similar }
        let seedSimilar = response.similar.map(Self.mediaItem)
        let recommendations = (try? await recommendationService.recommendations(
            for: response.movie.mediaItem(),
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
        return MediaItem(
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
        guard let releaseID = releaseSelectionStore.releaseID(for: mediaID),
              releases.contains(where: { $0.release.id == releaseID }) else {
            manualOverrideReleaseID = nil
            return
        }
        manualOverrideReleaseID = releaseID
    }

    public func continueWatching() {
        lastPlayedReleaseID = bestPlayableRelease?.release.id
    }

    public func addToLibrary() {
        isInLibrary = true
        guard let mediaItem, let libraryRepository else { return }
        Task {
            try? await libraryRepository.add(mediaItem)
        }
    }

    public func markWatched() {
        isWatched = true
        guard let mediaItem, let libraryRepository else { return }
        Task {
            try? await libraryRepository.markWatched(mediaItem, positionSeconds: 0)
        }
    }

    public func removeFromHistory() async {
        progress = nil
        isWatched = false
        guard let libraryRepository else { return }
        try? await libraryRepository.removeFromHistory(mediaID: mediaID)
    }

    public func toggleFavorite() {
        isFavorite.toggle()
        guard let mediaItem, let libraryRepository else { return }
        let shouldFavorite = isFavorite
        Task {
            if shouldFavorite {
                try? await libraryRepository.addFavorite(mediaItem)
            } else {
                try? await libraryRepository.removeFavorite(mediaID: mediaItem.id)
            }
        }
    }

    public func addToList(_ name: String) {
        selectedListName = name
        guard let mediaItem, let libraryRepository else { return }
        Task {
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

    public func copyMagnet(_ release: TorrentRelease) {
        copiedMagnetURI = release.magnetURI
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

    private func refreshLibraryState() async {
        guard let libraryRepository, let mediaItem else { return }
        do {
            async let libraryItems = libraryRepository.items()
            async let favoriteItems = libraryRepository.favorites()
            async let watchedItems = libraryRepository.watchedItems()
            async let ratedItems = libraryRepository.ratedItems()

            let loadedLibraryItems = try await libraryItems
            let loadedFavoriteItems = try await favoriteItems
            let loadedWatchedItems = try await watchedItems
            let loadedRatedItems = try await ratedItems
            isInLibrary = loadedLibraryItems.contains { $0.id == mediaItem.id }
            isFavorite = loadedFavoriteItems.contains { $0.id == mediaItem.id }
            isWatched = loadedWatchedItems.contains { $0.item.id == mediaItem.id }
            userRating = loadedRatedItems.first { $0.item.id == mediaItem.id }?.rating
        } catch {
            isInLibrary = false
            isFavorite = false
            isWatched = false
            userRating = nil
        }
    }

    private func refreshUserSources() async {
        guard let userMediaSourceRepository else {
            userSources = []
            selectedUserSourceID = nil
            return
        }
        do {
            userSources = try await userMediaSourceRepository.sources(for: mediaID)
            if selectedUserSourceID == nil {
                selectedUserSourceID = userSources.first?.id
            }
        } catch {
            userSources = []
            selectedUserSourceID = nil
        }
    }
}

private extension MovieDetail {
    func mediaItem() -> MediaItem {
        let metadata = MediaMetadata(
            tmdbId: Self.metadataNumericID(from: id),
            imdbId: Self.imdbID(from: id),
            title: title,
            originalTitle: originalTitle.isEmpty ? title : originalTitle,
            overview: overview,
            year: year > 0 ? year : nil,
            genres: genres,
            runtime: Self.runtimeMinutes(from: runtime),
            rating: Double(imdbRating) ?? Double(tmdbRating),
            posterURL: posterURL,
            backdropURL: backdropURL,
            logoURL: logoURL,
            posterCandidates: posterURL.map { [MetadataArtworkCandidate(url: $0, score: 1)] } ?? [],
            backdropCandidates: backdropURL.map { [MetadataArtworkCandidate(url: $0, score: 1)] } ?? []
        )
        return MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: overview,
            releaseYear: year > 0 ? year : nil,
            posterPath: posterURL?.absoluteString,
            metadata: metadata
        )
    }

    static func metadataNumericID(from id: String) -> Int {
        let digits = id.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    static func imdbID(from id: String) -> String? {
        id.split(separator: ":").last.map(String.init).flatMap { $0.hasPrefix("tt") ? $0 : nil }
    }

    static func runtimeMinutes(from runtime: String) -> Int? {
        let lowercased = runtime.lowercased()
        let hours = lowercased.range(of: #"(\d+)\s*h"#, options: .regularExpression)
            .flatMap { Int(lowercased[$0].filter(\.isNumber)) } ?? 0
        let minutes = lowercased.range(of: #"(\d+)\s*m"#, options: .regularExpression)
            .flatMap { Int(lowercased[$0].filter(\.isNumber)) } ?? 0
        let total = hours * 60 + minutes
        return total > 0 ? total : nil
    }
}
