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
            "runtime": 62
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
