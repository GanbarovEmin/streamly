import XCTest
@testable import CineFlowCore
@testable import CineFlowDatabase
@testable import CineFlowMetadata

final class CinemetaMetadataServiceTests: XCTestCase {
    override func tearDown() {
        CinemetaMockURLProtocol.reset()
        super.tearDown()
    }

    func testSearchMapsMovieAndSeriesCatalogResultsToIMDbMediaItemsAndCachesResponses() async throws {
        let database = try DatabaseManager.inMemory()
        let service = makeService(database: database) { request in
            switch request.url?.path {
            case "/catalog/movie/top/search=matrix.json":
                return (200, Self.movieSearchFixture)
            case "/catalog/series/top/search=matrix.json":
                return (200, Self.seriesSearchFixture)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, "{}")
            }
        }

        let results = try await service.search(query: "matrix")

        XCTAssertEqual(results.map(\.id), ["imdb:movie:tt0133093", "imdb:series:tt0106062"])
        XCTAssertEqual(results.first?.metadata?.imdbId, "tt0133093")
        XCTAssertEqual(results.first?.metadata?.tmdbId, 603)
        XCTAssertEqual(results.first?.metadata?.title, "The Matrix")
        XCTAssertEqual(results.first?.metadata?.genres, ["Action", "Sci-Fi"])
        XCTAssertEqual(results.first?.metadata?.rating, 8.7)
        XCTAssertEqual(results.first?.bestPosterURL?.absoluteString, "https://images.metahub.space/poster/small/tt0133093/img")

        CinemetaMockURLProtocol.requestHandler = { _ in
            XCTFail("Expected cached Cinemeta response")
            return (200, "{}")
        }

        let cached = try await service.search(query: "matrix")
        XCTAssertEqual(cached.map(\.id), ["imdb:movie:tt0133093", "imdb:series:tt0106062"])
    }

    func testMovieAndSeriesDetailsMapCinemetaMetaResponses() async throws {
        let service = makeService { request in
            switch request.url?.path {
            case "/meta/movie/tt0133093.json":
                return (200, Self.movieDetailFixture)
            case "/meta/series/tt0944947.json":
                return (200, Self.seriesDetailFixture)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, "{}")
            }
        }

        let movie = try await service.movieDetail(imdbID: "tt0133093")
        let series = try await service.seriesDetail(imdbID: "tt0944947")

        XCTAssertEqual(movie.id, "imdb:movie:tt0133093")
        XCTAssertEqual(movie.metadata.title, "The Matrix")
        XCTAssertEqual(movie.metadata.runtime, 136)
        XCTAssertEqual(movie.metadata.trailerURLs.map(\.absoluteString), ["https://www.youtube.com/watch?v=d0XTFAMmhrE"])

        XCTAssertEqual(series.id, "imdb:series:tt0944947")
        XCTAssertEqual(series.metadata.title, "Game of Thrones")
        XCTAssertEqual(series.seasons.map(\.seasonNumber), [1])
        XCTAssertEqual(series.seasons.first?.episodes.map(\.id), ["tt0944947:1:1", "tt0944947:1:2"])
        XCTAssertEqual(series.seasons.first?.episodes.first?.title, "Winter Is Coming")
        XCTAssertEqual(series.seasons.first?.episodes.first?.thumbnailURL?.absoluteString, "https://images.example.com/got-s1e1.jpg")
    }

    func testCompositeMetadataServiceKeepsCinemetaPrimaryWhenBothProvidersCanSearch() async throws {
        let primary = makeService { request in
            switch request.url?.path {
            case "/catalog/movie/top/search=matrix.json":
                return (200, Self.movieSearchFixture)
            case "/catalog/series/top/search=matrix.json":
                return (200, #"{"metas":[]}"#)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, "{}")
            }
        }
        let fallback = StaticMetadataService(searchResults: [
            MediaItem(id: "tmdb:movie:603", title: "The Matrix", kind: .movie, overview: "TMDB fallback.", releaseYear: 1999, posterPath: nil)
        ])
        let composite = CompositeMetadataService(primary: primary, fallback: fallback)

        let results = try await composite.search(query: "matrix")

        XCTAssertEqual(results.map(\.id), ["imdb:movie:tt0133093"])
    }

    func testCompositeMetadataServiceFallsBackToTMDBWhenCinemetaFails() async throws {
        let primary = FailingMetadataService(error: MetadataServiceError.networkUnavailable)
        let fallback = StaticMetadataService(searchResults: [
            MediaItem(id: "tmdb:movie:603", title: "The Matrix", kind: .movie, overview: "TMDB fallback.", releaseYear: 1999, posterPath: nil)
        ])
        let composite = CompositeMetadataService(primary: primary, fallback: fallback)

        let results = try await composite.search(query: "matrix")

        XCTAssertEqual(results.map(\.id), ["tmdb:movie:603"])
    }

    func testPopularMoviesLoadsMultipleTopCatalogPages() async throws {
        let service = makeService { request in
            switch request.url?.path {
            case "/catalog/movie/top.json":
                return (200, Self.pagedCatalogFixture(id: "tt0000001", title: "First Page Movie"))
            case "/catalog/movie/top/skip=50.json":
                return (200, Self.pagedCatalogFixture(id: "tt0000051", title: "Second Page Movie"))
            case "/catalog/movie/top/skip=100.json":
                return (200, #"{"metas":[]}"#)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, "{}")
            }
        }

        let results = try await service.popularMovies()

        XCTAssertEqual(results.map(\.id), ["imdb:movie:tt0000001", "imdb:movie:tt0000051"])
    }

    func testStructuredCatalogsLoadYearIMDbRatingPaginationAndLogo() async throws {
        let service = makeService { request in
            switch request.url?.path {
            case "/catalog/movie/year/genre=2026.json":
                return (200, Self.catalogFixture(
                    id: "tt2026001",
                    title: "First 2026 Movie",
                    type: "movie",
                    releaseInfo: "2026",
                    logo: "https://images.metahub.space/logo/medium/tt2026001/img"
                ))
            case "/catalog/movie/year/genre=2026&skip=50.json":
                return (200, Self.catalogFixture(
                    id: "tt2026051",
                    title: "Second 2026 Movie",
                    type: "movie",
                    releaseInfo: "2026"
                ))
            case "/catalog/movie/year/genre=2026&skip=100.json":
                return (200, #"{"metas":[]}"#)
            case "/catalog/series/imdbRating.json":
                return (200, Self.catalogFixture(
                    id: "tt9000001",
                    title: "Featured Series",
                    type: "series",
                    releaseInfo: "2025-"
                ))
            case "/catalog/series/imdbRating/skip=50.json":
                return (200, #"{"metas":[]}"#)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, "{}")
            }
        }

        let yearResults = try await service.catalog(kind: .newByYear(2026), mediaKind: .movie)
        let featuredResults = try await service.catalog(kind: .featuredByIMDbRating, mediaKind: .series)

        XCTAssertEqual(yearResults.map(\.id), ["imdb:movie:tt2026001", "imdb:movie:tt2026051"])
        XCTAssertEqual(
            yearResults.first?.metadata?.logoURL?.absoluteString,
            "https://images.metahub.space/logo/medium/tt2026001/img"
        )
        XCTAssertEqual(featuredResults.map(\.id), ["imdb:series:tt9000001"])
    }

    func testCinemetaMatchCandidatesScoreExactAlternativeYearAndType() async throws {
        let service = makeService { request in
            switch request.url?.path {
            case "/catalog/movie/top/search=Matrix.json":
                return (200, Self.multipleMovieMatchesFixture)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, "{}")
            }
        }

        let candidates = try await service.matchCandidates(
            query: "Matrix",
            kind: .movie,
            year: 1999
        )

        XCTAssertEqual(candidates.map(\.item.id), ["imdb:movie:tt0133093", "imdb:movie:tt9990001"])
        XCTAssertGreaterThan(candidates[0].confidence, candidates[1].confidence)
        XCTAssertTrue(candidates[0].reasons.contains(.exactTitle))
        XCTAssertTrue(candidates[0].reasons.contains(.yearMatch))
        XCTAssertTrue(candidates[0].reasons.contains(.mediaTypeMatch))
        XCTAssertTrue(candidates[1].reasons.contains(.yearMismatch(expected: 1999, actual: 2003)))
    }

    func testArtworkSelectorPrefersLanguageAndFallsBackGracefully() {
        let selected = MetadataArtworkSelector.select(
            posters: [
                MetadataArtworkCandidate(url: URL(string: "https://images.example.com/en.jpg")!, languageCode: "en", score: 0.9),
                MetadataArtworkCandidate(url: URL(string: "https://images.example.com/ru.jpg")!, languageCode: "ru", score: 0.7)
            ],
            backdrops: [],
            preferredLanguageCodes: ["ru", "en"]
        )

        XCTAssertEqual(selected.posterURL?.absoluteString, "https://images.example.com/ru.jpg")
        XCTAssertEqual(selected.backdropURL?.absoluteString, "https://images.example.com/ru.jpg")
        XCTAssertTrue(selected.usesBackdropFallback)
        XCTAssertFalse(selected.usesNoImagePlaceholder)

        let empty = MetadataArtworkSelector.select(posters: [], backdrops: [], preferredLanguageCodes: ["ru"])
        XCTAssertNil(empty.posterURL)
        XCTAssertNil(empty.backdropURL)
        XCTAssertTrue(empty.usesNoImagePlaceholder)
    }

    private func makeService(
        database: DatabaseManager? = nil,
        handler: @escaping @Sendable (URLRequest) throws -> (Int, String)
    ) -> CinemetaMetadataService {
        CinemetaMockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CinemetaMockURLProtocol.self]
        return CinemetaMetadataService(
            cacheRepository: database.map(CacheRepository.init(databaseManager:)),
            session: URLSession(configuration: configuration),
            baseURL: URL(string: "https://v3-cinemeta.strem.io")!
        )
    }

    private static let movieSearchFixture = """
    {
      "metas": [
        {
          "id": "tt0133093",
          "imdb_id": "tt0133093",
          "type": "movie",
          "name": "The Matrix",
          "description": "A hacker discovers the truth.",
          "genre": ["Action", "Sci-Fi"],
          "imdbRating": "8.7",
          "moviedb_id": 603,
          "poster": "https://images.metahub.space/poster/small/tt0133093/img",
          "background": "https://images.metahub.space/background/medium/tt0133093/img",
          "releaseInfo": "1999",
          "runtime": "136 min"
        }
      ]
    }
    """

    private static let seriesSearchFixture = """
    {
      "metas": [
        {
          "id": "tt0106062",
          "imdb_id": "tt0106062",
          "type": "series",
          "name": "Matrix",
          "description": "Series fixture.",
          "genre": ["Drama"],
          "imdbRating": "7.8",
          "poster": "https://images.metahub.space/poster/small/tt0106062/img",
          "releaseInfo": "1993-"
        }
      ]
    }
    """

    private static func pagedCatalogFixture(id: String, title: String) -> String {
        """
        {
          "metas": [
            {
              "id": "\(id)",
              "imdb_id": "\(id)",
              "type": "movie",
              "name": "\(title)",
              "description": "Paged catalog fixture.",
              "genre": ["Drama"],
              "imdbRating": "7.1",
              "releaseInfo": "2026"
            }
          ]
        }
        """
    }

    private static func catalogFixture(
        id: String,
        title: String,
        type: String,
        releaseInfo: String,
        logo: String? = nil
    ) -> String {
        let logoLine = logo.map { #","logo": "\#($0)""# } ?? ""
        return """
        {
          "metas": [
            {
              "id": "\(id)",
              "imdb_id": "\(id)",
              "type": "\(type)",
              "name": "\(title)",
              "description": "Catalog fixture.",
              "genre": ["Drama"],
              "imdbRating": "8.1",
              "releaseInfo": "\(releaseInfo)"\(logoLine)
            }
          ]
        }
        """
    }

    private static let movieDetailFixture = """
    {
      "meta": {
        "id": "tt0133093",
        "imdb_id": "tt0133093",
        "moviedb_id": 603,
        "type": "movie",
        "name": "The Matrix",
        "description": "A hacker discovers the truth.",
        "genre": ["Action", "Sci-Fi"],
        "imdbRating": "8.7",
        "poster": "https://images.metahub.space/poster/small/tt0133093/img",
        "background": "https://images.metahub.space/background/medium/tt0133093/img",
        "released": "1999-03-31T00:00:00.000Z",
        "runtime": "136 min",
        "trailers": [{ "source": "d0XTFAMmhrE", "type": "Trailer" }]
      }
    }
    """

    private static let seriesDetailFixture = """
    {
      "meta": {
        "id": "tt0944947",
        "imdb_id": "tt0944947",
        "moviedb_id": 1399,
        "type": "series",
        "name": "Game of Thrones",
        "description": "Noble families fight for control.",
        "genre": ["Action", "Adventure", "Drama"],
        "imdbRating": "9.2",
        "poster": "https://images.metahub.space/poster/small/tt0944947/img",
        "background": "https://images.metahub.space/background/medium/tt0944947/img",
        "releaseInfo": "2011-2019",
        "runtime": "57 min",
        "trailers": [{ "source": "KPLWWIOCOOQ", "type": "Trailer" }],
        "videos": [
          {
            "id": "tt0944947:1:1",
            "name": "Winter Is Coming",
            "season": 1,
            "episode": 1,
            "overview": "Pilot.",
            "released": "2011-04-17T05:00:00.000Z",
            "runtime": 62,
            "thumbnail": "https://images.example.com/got-s1e1.jpg"
          },
          {
            "id": "tt0944947:1:2",
            "name": "The Kingsroad",
            "season": 1,
            "episode": 2,
            "overview": "The journey begins.",
            "released": "2011-04-24T05:00:00.000Z"
          }
        ]
      }
    }
    """

    private static let multipleMovieMatchesFixture = """
    {
      "metas": [
        {
          "id": "tt9990001",
          "imdb_id": "tt9990001",
          "type": "movie",
          "name": "Matrix Reloaded",
          "description": "Wrong year fixture.",
          "genre": ["Action"],
          "moviedb_id": 604,
          "poster": "https://images.metahub.space/poster/small/tt9990001/img",
          "releaseInfo": "2003",
          "aliases": ["The Matrix 2"]
        },
        {
          "id": "tt0133093",
          "imdb_id": "tt0133093",
          "type": "movie",
          "name": "The Matrix",
          "description": "A hacker discovers the truth.",
          "genre": ["Action", "Sci-Fi"],
          "moviedb_id": 603,
          "poster": "https://images.metahub.space/poster/small/tt0133093/img",
          "background": "https://images.metahub.space/background/medium/tt0133093/img",
          "releaseInfo": "1999",
          "aliases": ["Matrix"]
        },
        {
          "id": "tt0106062",
          "imdb_id": "tt0106062",
          "type": "series",
          "name": "Matrix",
          "description": "Series fixture.",
          "genre": ["Drama"],
          "releaseInfo": "1993-"
        }
      ]
    }
    """
}

private struct FailingMetadataService: MetadataServiceProtocol {
    let error: Error

    func search(query: String) async throws -> [MediaItem] {
        throw error
    }
}

private struct StaticMetadataService: MetadataServiceProtocol {
    let searchResults: [MediaItem]

    func search(query: String) async throws -> [MediaItem] {
        searchResults
    }
}

private final class CinemetaMockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (Int, String))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (status, body) = try requestHandler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
