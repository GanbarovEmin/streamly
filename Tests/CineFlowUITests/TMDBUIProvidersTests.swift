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

    private static func movie(imdbID: String?) -> Movie {
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
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: metadata.overview,
            releaseYear: 1999,
            posterPath: nil,
            metadata: metadata
        )
        return Movie(id: item.id, mediaItem: item, metadata: metadata)
    }
}

private final class StubMetadataService: MetadataServiceProtocol {
    private let searchResults: [MediaItem]
    private let trendingResults: [MediaItem]
    private let popularMovieResults: [MediaItem]
    private let popularSeriesResults: [MediaItem]
    private let movieDetails: [Int: Movie]
    private let similarResults: [MediaItem]
    private let trailers: [Trailer]
    private let cast: [CastMember]

    init(
        searchResults: [MediaItem] = [],
        trendingResults: [MediaItem] = [],
        popularMovieResults: [MediaItem] = [],
        popularSeriesResults: [MediaItem] = [],
        movieDetails: [Int: Movie] = [:],
        similarResults: [MediaItem] = [],
        trailers: [Trailer] = [],
        cast: [CastMember] = []
    ) {
        self.searchResults = searchResults
        self.trendingResults = trendingResults
        self.popularMovieResults = popularMovieResults
        self.popularSeriesResults = popularSeriesResults
        self.movieDetails = movieDetails
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
