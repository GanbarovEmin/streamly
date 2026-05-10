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
        backdropURL: URL? = nil
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
    }
}

public struct MovieCastMember: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: String
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
            similar: [
                SearchMediaResult(item: HomeSeedLibrary.developmentItems.first { $0.id == "tmdb:movie:27205" }!),
                SearchMediaResult(item: HomeSeedLibrary.developmentItems.first { $0.id == "tmdb:movie:157336" }!)
            ],
            cast: [
                MovieCastMember(id: "keanu", name: "Keanu Reeves", role: "Neo"),
                MovieCastMember(id: "carrie", name: "Carrie-Anne Moss", role: "Trinity"),
                MovieCastMember(id: "laurence", name: "Laurence Fishburne", role: "Morpheus")
            ],
            progress: PlaybackProgress(mediaID: "tmdb:movie:603", positionSeconds: 3_400, durationSeconds: 8_160)
        )
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
    @Published public private(set) var selectedListName: String?
    @Published public private(set) var userRating: Int?
    @Published public private(set) var lastPlayedReleaseID: String?
    @Published public private(set) var copiedMagnetURI: String?
    @Published public private(set) var userSources: [UserMediaSource] = []
    @Published public private(set) var selectedUserSourceID: String?
    @Published public var selectedTab: MovieDetailTab = .releases

    public let tabs: [MovieDetailTab] = MovieDetailTab.allCases

    private let mediaID: String
    private let provider: any MovieDetailProviderProtocol
    private let rankingEngine: ReleaseRankingEngine
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)?

    public init(
        mediaID: String,
        provider: any MovieDetailProviderProtocol = MockMovieDetailProvider(),
        rankingEngine: ReleaseRankingEngine = ReleaseRankingEngine(preferences: RankingPreferences(preferredAudioLanguages: ["ru"], preferredSubtitleLanguages: ["ru"], supportsHDR: true)),
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)? = nil
    ) {
        self.mediaID = mediaID
        self.provider = provider
        self.rankingEngine = rankingEngine
        self.libraryRepository = libraryRepository
        self.userMediaSourceRepository = userMediaSourceRepository
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
            return userSources.isEmpty ? "No sources selected" : "\(userSources.count) local source\(userSources.count == 1 ? "" : "s")"
        }

        let best = releases[0].release
        let quality = best.qualityLabel
        let providerCount = Set(releases.map(\.release.sourceName)).count
        return "\(releases.count) sources · best \(quality) · \(best.seeders) seeders · \(providerCount) provider\(providerCount == 1 ? "" : "s")"
    }

    public func load() async {
        state = .loading

        do {
            guard let response = try await provider.movieDetail(id: mediaID) else {
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

            movie = response.movie
            mediaItem = response.movie.mediaItem()
            releases = rankingEngine.rank(response.releases)
            trailers = response.trailers
            similar = response.similar
            cast = response.cast
            progress = response.progress
            await refreshLibraryState()
            await refreshUserSources()
            state = .loaded
        } catch {
            state = .failed(CineFlowError.from(error, fallbackCategory: .metadata).userMessage)
        }
    }

    public func play(_ release: TorrentRelease) {
        lastPlayedReleaseID = release.id
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

    public func continueWatching() {
        lastPlayedReleaseID = releases.first?.release.id
    }

    public func addToLibrary() {
        isInLibrary = true
        guard let mediaItem, let libraryRepository else { return }
        Task {
            try? await libraryRepository.add(mediaItem)
        }
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

    private func refreshLibraryState() async {
        guard let libraryRepository, let mediaItem else { return }
        do {
            async let libraryItems = libraryRepository.items()
            async let favoriteItems = libraryRepository.favorites()
            async let ratedItems = libraryRepository.ratedItems()

            let loadedLibraryItems = try await libraryItems
            let loadedFavoriteItems = try await favoriteItems
            let loadedRatedItems = try await ratedItems
            isInLibrary = loadedLibraryItems.contains { $0.id == mediaItem.id }
            isFavorite = loadedFavoriteItems.contains { $0.id == mediaItem.id }
            userRating = loadedRatedItems.first { $0.item.id == mediaItem.id }?.rating
        } catch {
            isInLibrary = false
            isFavorite = false
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
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: overview,
            releaseYear: year,
            posterPath: nil
        )
    }
}
