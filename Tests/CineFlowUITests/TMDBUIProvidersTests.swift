import CineFlowCore
import CineFlowSources
import XCTest
@testable import CineFlowUI

final class TMDBUIProvidersTests: XCTestCase {
    func testTMDBSearchProviderMapsMediaMetadataAndPosterURLs() async throws {
        let service = StubMetadataService(searchResults: [
            Self.mediaItem(
                id: "tmdb:movie:603",
                title: "The Matrix",
                kind: .movie,
                poster: "https://image.tmdb.org/t/p/w500/matrix.jpg"
            )
        ])
        let provider = TMDBSearchProvider(metadataService: service)

        let response = try await provider.search(query: "matrix")

        XCTAssertTrue(response.releases.isEmpty)
        XCTAssertEqual(response.media.map(\.id), ["tmdb:movie:603"])
        XCTAssertEqual(response.media.first?.title, "The Matrix")
        XCTAssertEqual(response.media.first?.metadata, "1999 · Sci-Fi, Action · TMDB 8.2")
        XCTAssertEqual(response.media.first?.artworkURL?.absoluteString, "https://image.tmdb.org/t/p/w500/matrix.jpg")
    }

    func testTMDBHomeProviderBuildsRealPosterAndBackdropSeedItems() async throws {
        let service = StubMetadataService(
            trendingResults: [
                Self.mediaItem(
                    id: "tmdb:movie:603",
                    title: "The Matrix",
                    kind: .movie,
                    poster: "https://image.tmdb.org/t/p/w500/matrix.jpg",
                    backdrop: "https://image.tmdb.org/t/p/w1280/matrix-backdrop.jpg"
                )
            ],
            popularMovieResults: [],
            popularSeriesResults: []
        )
        let provider = TMDBHomeContentProvider(metadataService: service)

        let items = try await provider.loadHomeItems()

        XCTAssertEqual(items.map(\.id), ["tmdb:movie:603"])
        XCTAssertEqual(items.first?.title, "The Matrix")
        XCTAssertEqual(items.first?.artworkURL?.absoluteString, "https://image.tmdb.org/t/p/w500/matrix.jpg")
        XCTAssertEqual(items.first?.backdropURL?.absoluteString, "https://image.tmdb.org/t/p/w1280/matrix-backdrop.jpg")
        XCTAssertEqual(items.first?.quality, "Movie")
    }

    func testTMDBPersonProviderKeepsSourceMediaAsFirstKnownForContext() async throws {
        let service = StubMetadataService(searchResults: [
            Self.mediaItem(id: "tmdb:movie:100", title: "Emilia", kind: .movie)
        ])
        let provider = TMDBPersonDetailProvider(metadataService: service)
        let source = PersonSourceMedia(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            year: 2011,
            posterURL: try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/got.jpg"))
        )

        let response = try await provider.personDetail(for: PersonRoutePayload(
            id: "emilia",
            name: "Emilia Clarke",
            role: "Daenerys Targaryen",
            sourceMedia: source
        ))

        XCTAssertEqual(response?.detail.knownFor.first?.id, "tmdb:tv:1399")
        XCTAssertEqual(response?.filmography.first?.mediaItem.displayTitle, "Game of Thrones")
        XCTAssertEqual(response?.filmography.map(\.mediaItem.id), ["tmdb:tv:1399", "tmdb:movie:100"])
    }

    func testTMDBMovieDetailProviderMapsDetailTrailersCastAndSimilarItems() async throws {
        let posterURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/matrix.jpg"))
        let backdropURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w1280/matrix-backdrop.jpg"))
        let metadata = MediaMetadata(
            tmdbId: 603,
            title: "The Matrix",
            originalTitle: "The Matrix",
            overview: "A hacker discovers the truth.",
            year: 1999,
            genres: ["Sci-Fi", "Action"],
            runtime: 136,
            rating: 8.2,
            posterURL: posterURL,
            backdropURL: backdropURL
        )
        let movie = Movie(
            id: "tmdb:movie:603",
            mediaItem: MediaItem(
                id: "tmdb:movie:603",
                title: "The Matrix",
                kind: .movie,
                overview: metadata.overview,
                releaseYear: 1999,
                posterPath: nil,
                metadata: metadata
            ),
            metadata: metadata
        )
        let service = StubMetadataService(
            movieDetails: [603: movie],
            similarResults: [
                Self.mediaItem(id: "tmdb:movie:27205", title: "Inception", kind: .movie)
            ],
            trailers: [
                Trailer(id: "trailer-1", title: "Official Trailer", url: try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=abc")), site: "YouTube")
            ],
            cast: [
                CastMember(id: "cast-1", name: "Keanu Reeves", characterName: "Neo")
            ]
        )
        let provider = TMDBMovieDetailProvider(metadataService: service)

        let response = try await provider.movieDetail(id: "tmdb:movie:603")

        XCTAssertEqual(response?.movie.title, "The Matrix")
        XCTAssertEqual(response?.movie.runtime, "2h 16m")
        XCTAssertEqual(response?.movie.posterURL, posterURL)
        XCTAssertEqual(response?.movie.backdropURL, backdropURL)
        XCTAssertEqual(response?.trailers.first?.source, "YouTube")
        XCTAssertEqual(response?.cast.first?.role, "Neo")
        XCTAssertEqual(response?.similar.map(\.title), ["Inception"])
    }

    func testTMDBMovieDetailProviderFetchesTorrentReleasesByIMDbID() async throws {
        let movie = Self.movie(imdbID: "tt0133093")
        let metadataService = StubMetadataService(movieDetails: [603: movie])
        let sourceProvider = RecordingTorrentProvider(releases: [
            TorrentRelease(
                id: "torrentio-matrix-2160p",
                sourceId: "torrentio",
                sourceName: "Rutracker",
                title: "The Matrix 2160p",
                magnetURI: "magnet:?xt=urn:btih:matrix",
                quality: .ultraHD,
                seeders: 14
            )
        ])
        let sourceManager = SourceManager(
            providers: [sourceProvider],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = TMDBMovieDetailProvider(
            metadataService: metadataService,
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )

        let response = try await provider.movieDetail(id: "tmdb:movie:603")
        let queries = await sourceProvider.recordedQueries()
        let releases = try XCTUnwrap(response?.releases)

        XCTAssertEqual(queries, ["tt0133093"])
        XCTAssertEqual(releases.map(\.id), ["torrentio-matrix-2160p"])
        XCTAssertEqual(releases.first?.sourceName, "Rutracker")
    }

    func testTMDBMovieDetailProviderSupportsIMDbIDsFromCinemetaSearch() async throws {
        let movie = Self.movie(id: "imdb:movie:tt0133093", imdbID: "tt0133093")
        let metadataService = StubMetadataService(movieDetailsByIMDbID: ["tt0133093": movie])
        let sourceProvider = RecordingTorrentProvider(releases: [
            TorrentRelease(
                id: "torrentio-matrix-2160p",
                sourceId: "torrentio",
                sourceName: "Torrentio",
                title: "The Matrix 2160p",
                magnetURI: "magnet:?xt=urn:btih:matrix",
                quality: .ultraHD,
                seeders: 14
            )
        ])
        let sourceManager = SourceManager(
            providers: [sourceProvider],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = TMDBMovieDetailProvider(
            metadataService: metadataService,
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )

        let response = try await provider.movieDetail(id: "imdb:movie:tt0133093")
        let queries = await sourceProvider.recordedQueries()

        XCTAssertEqual(response?.movie.id, "imdb:movie:tt0133093")
        XCTAssertEqual(response?.movie.title, "The Matrix")
        XCTAssertEqual(queries, ["tt0133093"])
        XCTAssertEqual(response?.releases.map(\.id), ["torrentio-matrix-2160p"])
    }

    func testTMDBSeriesDetailProviderSupportsIMDbIDsFromCinemetaSearch() async throws {
        let series = Self.series(id: "imdb:series:tt0944947", imdbID: "tt0944947")
        let metadataService = StubMetadataService(seriesDetailsByIMDbID: ["tt0944947": series])
        let provider = TMDBSeriesDetailProvider(metadataService: metadataService)

        let response = try await provider.seriesDetail(id: "imdb:series:tt0944947")

        XCTAssertEqual(response?.series.id, "imdb:series:tt0944947")
        XCTAssertEqual(response?.series.title, "Game of Thrones")
        XCTAssertEqual(response?.seasons.map(\.seasonNumber), [1])
        XCTAssertEqual(response?.seasons.first?.episodes.first?.id, "tt0944947:1:1")
    }

    func testTMDBSeriesDetailProviderKeepsAllKnownSeasonsInsteadOfTruncatingToThree() async throws {
        let series = Self.series(id: "imdb:series:tt0944947", imdbID: "tt0944947", seasonCount: 8)
        let metadataService = StubMetadataService(seriesDetailsByIMDbID: ["tt0944947": series])
        let provider = TMDBSeriesDetailProvider(metadataService: metadataService)

        let response = try await provider.seriesDetail(id: "imdb:series:tt0944947")

        XCTAssertEqual(response?.series.seasonsCount, 8)
        XCTAssertEqual(response?.seasons.map(\.seasonNumber), Array(1...8))
        XCTAssertEqual(response?.seasons.last?.episodes.first?.id, "tt0944947:8:1")
    }

    func testTMDBSeriesDetailProviderFetchesEpisodeTorrentReleasesByStremioVideoID() async throws {
        let series = Self.series(id: "imdb:series:tt0944947", imdbID: "tt0944947")
        let metadataService = StubMetadataService(seriesDetailsByIMDbID: ["tt0944947": series])
        let sourceProvider = RecordingTorrentProvider(releases: [
            TorrentRelease(
                id: "torrentio-got-s1e1-1080p",
                sourceId: "torrentio",
                sourceName: "Torrentio",
                title: "Game of Thrones S01E01 1080p",
                magnetURI: "magnet:?xt=urn:btih:got",
                quality: .fullHD,
                seeders: 42
            )
        ])
        let sourceManager = SourceManager(
            providers: [sourceProvider],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = TMDBSeriesDetailProvider(
            metadataService: metadataService,
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )

        let response = try await provider.seriesDetail(id: "imdb:series:tt0944947")
        let queries = await sourceProvider.recordedQueries()

        XCTAssertEqual(queries, ["tt0944947:1:1"])
        XCTAssertEqual(response?.releases.map { $0.release.id }, ["torrentio-got-s1e1-1080p"])
        XCTAssertEqual(response?.releases.first?.scope, .episode("tt0944947:1:1"))
    }

    func testTMDBSeriesDetailProviderFetchesSelectedEpisodeTorrentReleasesByStremioVideoID() async throws {
        let metadataService = StubMetadataService()
        let sourceProvider = RecordingTorrentProvider(releases: [
            TorrentRelease(
                id: "torrentio-got-s1e2-1080p",
                sourceId: "torrentio",
                sourceName: "Torrentio",
                title: "Game of Thrones S01E02 1080p",
                magnetURI: "magnet:?xt=urn:btih:got2",
                quality: .fullHD,
                seeders: 77
            )
        ])
        let sourceManager = SourceManager(
            providers: [sourceProvider],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = TMDBSeriesDetailProvider(
            metadataService: metadataService,
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )

        let releases = try await provider.episodeReleases(seriesID: "imdb:series:tt0944947", episodeID: "tt0944947:1:2")
        let queries = await sourceProvider.recordedQueries()

        XCTAssertEqual(queries, ["tt0944947:1:2"])
        XCTAssertEqual(releases.map { $0.release.id }, ["torrentio-got-s1e2-1080p"])
        XCTAssertEqual(releases.first?.scope, .episode("tt0944947:1:2"))
    }

    func testTMDBMovieDetailProviderSkipsTorrentLookupWithoutIMDbID() async throws {
        let movie = Self.movie(imdbID: nil)
        let metadataService = StubMetadataService(movieDetails: [603: movie])
        let sourceProvider = RecordingTorrentProvider(releases: [
            TorrentRelease(id: "unused", title: "Unused", quality: .fullHD, seeders: 1)
        ])
        let sourceManager = SourceManager(
            providers: [sourceProvider],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = TMDBMovieDetailProvider(
            metadataService: metadataService,
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )

        let response = try await provider.movieDetail(id: "tmdb:movie:603")
        let queries = await sourceProvider.recordedQueries()

        XCTAssertTrue(queries.isEmpty)
        XCTAssertTrue(response?.releases.isEmpty == true)
    }

    func testTMDBMovieDetailProviderKeepsMetadataWhenTorrentSourceFails() async throws {
        let movie = Self.movie(imdbID: "tt0133093")
        let metadataService = StubMetadataService(movieDetails: [603: movie])
        let sourceProvider = RecordingTorrentProvider(shouldFail: true)
        let sourceManager = SourceManager(
            providers: [sourceProvider],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = TMDBMovieDetailProvider(
            metadataService: metadataService,
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )

        let response = try await provider.movieDetail(id: "tmdb:movie:603")

        XCTAssertEqual(response?.movie.title, "The Matrix")
        XCTAssertTrue(response?.releases.isEmpty == true)
    }

    private static func mediaItem(
        id: String,
        title: String,
        kind: MediaKind,
        poster: String = "https://image.tmdb.org/t/p/w500/default.jpg",
        backdrop: String? = nil
    ) -> MediaItem {
        let tmdbId = Int(id.split(separator: ":").last ?? "0") ?? 0
        return MediaItem(
            id: id,
            title: title,
            kind: kind,
            overview: "Fixture overview",
            releaseYear: 1999,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: tmdbId,
                title: title,
                originalTitle: title,
                overview: "Fixture overview",
                year: 1999,
                genres: ["Sci-Fi", "Action"],
                runtime: 136,
                rating: 8.2,
                posterURL: URL(string: poster),
                backdropURL: backdrop.flatMap(URL.init(string:))
            )
        )
    }

    private static func movie(id: String = "tmdb:movie:603", imdbID: String?) -> Movie {
        let metadata = MediaMetadata(
            tmdbId: 603,
            imdbId: imdbID,
            title: "The Matrix",
            originalTitle: "The Matrix",
            overview: "A hacker discovers the truth.",
            year: 1999,
            genres: ["Sci-Fi", "Action"],
            runtime: 136,
            rating: 8.2
        )
        let item = MediaItem(
            id: id,
            title: "The Matrix",
            kind: .movie,
            overview: metadata.overview,
            releaseYear: 1999,
            posterPath: nil,
            metadata: metadata
        )
        return Movie(id: item.id, mediaItem: item, metadata: metadata)
    }

    private static func series(id: String, imdbID: String?, seasonCount: Int = 1) -> Series {
        let metadata = MediaMetadata(
            tmdbId: 1399,
            imdbId: imdbID,
            title: "Game of Thrones",
            originalTitle: "Game of Thrones",
            overview: "Noble families fight for control.",
            year: 2011,
            genres: ["Action", "Drama"],
            runtime: 57,
            rating: 9.2
        )
        let item = MediaItem(
            id: id,
            title: "Game of Thrones",
            kind: .series,
            overview: metadata.overview,
            releaseYear: 2011,
            posterPath: nil,
            metadata: metadata
        )
        let seasons = (1...max(1, seasonCount)).map { seasonNumber in
            let episode = Episode(
                id: "tt0944947:\(seasonNumber):1",
                seriesID: id,
                seasonID: "\(id):season:\(seasonNumber)",
                episodeNumber: 1,
                title: seasonNumber == 1 ? "Winter Is Coming" : "Season \(seasonNumber) Premiere",
                overview: "Episode.",
                runtimeMinutes: 62
            )
            return Season(
                id: "\(id):season:\(seasonNumber)",
                seriesID: id,
                seasonNumber: seasonNumber,
                title: "Season \(seasonNumber)",
                episodes: [episode]
            )
        }
        return Series(id: item.id, mediaItem: item, metadata: metadata, seasons: seasons)
    }
}

private final class StubMetadataService: MetadataServiceProtocol {
    private let searchResults: [MediaItem]
    private let trendingResults: [MediaItem]
    private let popularMovieResults: [MediaItem]
    private let popularSeriesResults: [MediaItem]
    private let movieDetails: [Int: Movie]
    private let movieDetailsByIMDbID: [String: Movie]
    private let seriesDetailsByIMDbID: [String: Series]
    private let similarResults: [MediaItem]
    private let trailers: [Trailer]
    private let cast: [CastMember]

    init(
        searchResults: [MediaItem] = [],
        trendingResults: [MediaItem] = [],
        popularMovieResults: [MediaItem] = [],
        popularSeriesResults: [MediaItem] = [],
        movieDetails: [Int: Movie] = [:],
        movieDetailsByIMDbID: [String: Movie] = [:],
        seriesDetailsByIMDbID: [String: Series] = [:],
        similarResults: [MediaItem] = [],
        trailers: [Trailer] = [],
        cast: [CastMember] = []
    ) {
        self.searchResults = searchResults
        self.trendingResults = trendingResults
        self.popularMovieResults = popularMovieResults
        self.popularSeriesResults = popularSeriesResults
        self.movieDetails = movieDetails
        self.movieDetailsByIMDbID = movieDetailsByIMDbID
        self.seriesDetailsByIMDbID = seriesDetailsByIMDbID
        self.similarResults = similarResults
        self.trailers = trailers
        self.cast = cast
    }

    func search(query: String) async throws -> [MediaItem] {
        searchResults
    }

    func popularMovies() async throws -> [MediaItem] {
        popularMovieResults
    }

    func popularSeries() async throws -> [MediaItem] {
        popularSeriesResults
    }

    func trending() async throws -> [MediaItem] {
        trendingResults
    }

    func movieDetail(tmdbID: Int) async throws -> Movie {
        guard let movie = movieDetails[tmdbID] else {
            throw CoreMetadataServiceError.unsupported
        }
        return movie
    }

    func movieDetail(imdbID: String) async throws -> Movie {
        guard let movie = movieDetailsByIMDbID[imdbID] else {
            throw CoreMetadataServiceError.unsupported
        }
        return movie
    }

    func seriesDetail(imdbID: String) async throws -> Series {
        guard let series = seriesDetailsByIMDbID[imdbID] else {
            throw CoreMetadataServiceError.unsupported
        }
        return series
    }

    func similar(to mediaID: String) async throws -> [MediaItem] {
        similarResults
    }

    func videos(for mediaID: String) async throws -> [Trailer] {
        trailers
    }

    func credits(for mediaID: String) async throws -> [CastMember] {
        cast
    }
}

private actor RecordingTorrentProvider: TorrentSourceProviderProtocol {
    let sourceId = "torrentio"
    let displayName = "Torrentio"
    let requiresAuthentication = false
    let isEnabled = true

    private(set) var queries: [String] = []
    private let releases: [TorrentRelease]
    private let shouldFail: Bool

    init(releases: [TorrentRelease] = [], shouldFail: Bool = false) {
        self.releases = releases
        self.shouldFail = shouldFail
    }

    func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        queries.append(query)
        if shouldFail {
            throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Fixture failure.")
        }
        return releases
    }

    func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        throw SourceProviderError.releaseNotFound(sourceId: sourceId, releaseId: releaseId)
    }

    func recordedQueries() -> [String] {
        queries
    }
}
