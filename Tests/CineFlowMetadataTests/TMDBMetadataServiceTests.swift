import XCTest
@testable import CineFlowCore
@testable import CineFlowDatabase
@testable import CineFlowMetadata

final class TMDBMetadataServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testSearchMoviesMapsDTOToDomainMediaItemsAndCachesResponse() async throws {
        let fixture = try TestFixtures.string("tmdb_search_movie_matrix.json")
        let database = try DatabaseManager.inMemory()
        let service = makeService(database: database) { request in
            XCTAssertEqual(request.url?.path, "/3/search/movie")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer dev-token")
            return (200, fixture)
        }

        let results = try await service.searchMovies(query: "matrix")

        XCTAssertEqual(results.map(\.id), ["tmdb:movie:603"])
        XCTAssertEqual(results.first?.metadata?.title, "The Matrix")
        XCTAssertEqual(results.first?.metadata?.releaseDate, Self.date("1999-03-31"))
        XCTAssertEqual(results.first?.metadata?.posterURL?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Expected cache hit, not a second network request")
            return (200, "{}")
        }

        let cached = try await service.searchMovies(query: "matrix")
        XCTAssertEqual(cached.map(\.id), ["tmdb:movie:603"])
    }

    func testSearchSeriesAndMovieDetailMapNestedCreditsVideosAndRecommendations() async throws {
        let seriesFixture = try TestFixtures.string("tmdb_search_series_game_of_thrones.json")
        let movieFixture = try TestFixtures.string("tmdb_movie_detail_matrix.json")
        let recommendationsFixture = try TestFixtures.string("tmdb_movie_recommendations_matrix.json")
        let service = makeService { request in
            switch request.url?.path {
            case "/3/search/tv":
                return (200, seriesFixture)
            case "/3/movie/603":
                return (200, movieFixture)
            case "/3/movie/603/recommendations":
                return (200, recommendationsFixture)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, #"{"status_message":"Not found"}"#)
            }
        }

        let series = try await service.searchSeries(query: "game")
        let movie = try await service.movieDetail(tmdbID: 603)
        let recommendations = try await service.recommendations(for: "tmdb:movie:603")

        XCTAssertEqual(series.first?.id, "tmdb:tv:1399")
        XCTAssertEqual(series.first?.kind, .series)
        XCTAssertEqual(movie.metadata.genres, ["Action", "Sci-Fi"])
        XCTAssertEqual(movie.metadata.releaseDate, Self.date("1999-03-31"))
        XCTAssertEqual(movie.metadata.trailerURLs.map(\.absoluteString), ["https://www.youtube.com/watch?v=abc"])
        XCTAssertEqual(movie.metadata.cast.first?.name, "Keanu Reeves")
        XCTAssertEqual(recommendations.map(\.id), ["tmdb:movie:27205"])
    }

    func testSeasonEpisodePopularTrendingSimilarVideosCreditsAndImageBuilder() async throws {
        let service = makeService { request in
            switch request.url?.path {
            case "/3/tv/1399/season/1":
                return (200, #"{"id":10,"season_number":1,"name":"Season 1","overview":"Start","episodes":[{"id":101,"episode_number":1,"name":"Winter Is Coming","overview":"Pilot","runtime":62,"air_date":"2011-04-17","still_path":"/winter.jpg"}]}"#)
            case "/3/tv/1399/season/1/episode/1":
                return (200, #"{"id":101,"episode_number":1,"name":"Winter Is Coming","overview":"Pilot","runtime":62,"air_date":"2011-04-17","still_path":"/winter.jpg"}"#)
            case "/3/movie/popular", "/3/tv/popular", "/3/trending/all/week", "/3/movie/603/similar":
                return (200, #"{"page":1,"results":[],"total_pages":1,"total_results":0}"#)
            case "/3/movie/603/videos":
                return (200, #"{"id":603,"results":[{"id":"v1","name":"Trailer","site":"YouTube","key":"abc","type":"Trailer"}]}"#)
            case "/3/movie/603/credits":
                return (200, #"{"id":603,"cast":[{"id":1,"name":"Keanu Reeves","character":"Neo","profile_path":"/neo.jpg","order":0}]}"#)
            default:
                XCTFail("Unexpected path \(request.url?.path ?? "nil")")
                return (404, #"{}"#)
            }
        }

        let season = try await service.seasonDetail(seriesTMDBID: 1399, seasonNumber: 1)
        let episode = try await service.episodeDetail(seriesTMDBID: 1399, seasonNumber: 1, episodeNumber: 1)
        _ = try await service.popularMovies()
        _ = try await service.popularSeries()
        _ = try await service.trending()
        _ = try await service.similar(to: "tmdb:movie:603")
        let videos = try await service.videos(for: "tmdb:movie:603")
        let credits = try await service.credits(for: "tmdb:movie:603")

        XCTAssertEqual(season.id, "tmdb:tv:1399:season:1")
        XCTAssertEqual(season.episodes.first?.title, "Winter Is Coming")
        XCTAssertEqual(season.episodes.first?.thumbnailURL?.absoluteString, "https://image.tmdb.org/t/p/w1280/winter.jpg")
        XCTAssertEqual(episode.id, "tmdb:tv:1399:season:1:episode:1")
        XCTAssertEqual(episode.thumbnailURL?.absoluteString, "https://image.tmdb.org/t/p/w1280/winter.jpg")
        XCTAssertEqual(videos.first?.url.absoluteString, "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(credits.first?.profileURL?.absoluteString, "https://image.tmdb.org/t/p/w185/neo.jpg")
        XCTAssertEqual(TMDBImageURLBuilder().url(path: "/poster.jpg", size: .poster)?.absoluteString, "https://image.tmdb.org/t/p/w500/poster.jpg")
    }

    func testErrorMappingForInvalidAPIKeyRateLimitNotFoundAndNetworkUnavailable() async throws {
        for (status, expected) in [(401, MetadataServiceError.invalidAPIKey), (404, .notFound), (429, .rateLimited)] {
            let service = makeService { _ in (status, #"{"status_message":"error"}"#) }

            do {
                _ = try await service.searchMovies(query: "matrix")
                XCTFail("Expected \(expected)")
            } catch let error as MetadataServiceError {
                XCTAssertEqual(error, expected)
            }
        }

        let service = makeService { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await service.searchMovies(query: "matrix")
            XCTFail("Expected network unavailable")
        } catch let error as MetadataServiceError {
            XCTAssertEqual(error, .networkUnavailable)
        }
    }

    func testMissingCredentialsFailBeforeNetworkRequest() async throws {
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Missing credentials should not issue a TMDB request")
            return (200, "{}")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = TMDBMetadataService(
            credentialProvider: StaticTMDBCredentialProvider(),
            session: URLSession(configuration: configuration)
        )

        do {
            _ = try await service.searchMovies(query: "matrix")
            XCTFail("Expected missing credentials")
        } catch let error as MetadataServiceError {
            XCTAssertEqual(error, .missingCredentials)
        }
    }

    func testCredentialProvidersUseKeychainAndLocalConfigWithoutHardcodingSecrets() async throws {
        let keychainService = MockKeychainService()
        _ = try await keychainService.saveCredential(
            KeychainCredential(
                accountID: TMDBCredentialAccountIDs.readAccessToken,
                kind: .apiToken,
                sourceID: "tmdb",
                token: "keychain-token"
            )
        )
        let keychainProvider = KeychainTMDBCredentialProvider(keychainService: keychainService)
        let keychainToken = await keychainProvider.readAccessToken
        XCTAssertEqual(keychainToken, "keychain-token")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try #"{"readAccessToken":"file-token","apiKey":"file-key"}"#.write(to: tempURL, atomically: true, encoding: .utf8)
        let localProvider = LocalTMDBCredentialProvider(configURL: tempURL, environment: [:])

        let localToken = await localProvider.readAccessToken
        let localAPIKey = await localProvider.apiKey
        XCTAssertEqual(localToken, "file-token")
        XCTAssertEqual(localAPIKey, "file-key")
    }

    func testCompositeCredentialProviderPrefersKeychainAndFallsBackToLocalConfig() async throws {
        let keychainService = MockKeychainService()
        let keychainProvider = KeychainTMDBCredentialProvider(keychainService: keychainService)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try #"{"readAccessToken":"file-token","apiKey":"file-key"}"#.write(to: tempURL, atomically: true, encoding: .utf8)
        let localProvider = LocalTMDBCredentialProvider(configURL: tempURL, environment: [:])

        let fallbackProvider = CompositeTMDBCredentialProvider([keychainProvider, localProvider])
        let fallbackToken = await fallbackProvider.readAccessToken
        XCTAssertEqual(fallbackToken, "file-token")

        _ = try await keychainService.saveCredential(
            KeychainCredential(
                accountID: TMDBCredentialAccountIDs.readAccessToken,
                kind: .apiToken,
                sourceID: "tmdb",
                token: "keychain-token"
            )
        )
        let keychainToken = await fallbackProvider.readAccessToken
        XCTAssertEqual(keychainToken, "keychain-token")
    }

    func testKeychainTMDBCredentialProviderMigratesLegacyDatabaseCredentials() async throws {
        let database = try DatabaseManager.inMemory()
        let settings = DatabaseSettingsRepository(databaseManager: database)
        try await settings.setString("legacy-token", forKey: TMDBSettingsKeys.readAccessToken)
        try await settings.setString("legacy-key", forKey: TMDBSettingsKeys.apiKey)
        let keychainService = MockKeychainService()
        let provider = KeychainTMDBCredentialProvider(
            keychainService: keychainService,
            legacySettingsRepository: settings
        )

        let token = await provider.readAccessToken
        let apiKey = await provider.apiKey
        let storedToken = try await keychainService.readCredential(accountID: TMDBCredentialAccountIDs.readAccessToken)
        let storedAPIKey = try await keychainService.readCredential(accountID: TMDBCredentialAccountIDs.apiKey)
        let legacyToken = try await settings.string(forKey: TMDBSettingsKeys.readAccessToken)
        let legacyAPIKey = try await settings.string(forKey: TMDBSettingsKeys.apiKey)

        XCTAssertEqual(token, "legacy-token")
        XCTAssertEqual(apiKey, "legacy-key")
        XCTAssertEqual(storedToken?.token, "legacy-token")
        XCTAssertEqual(storedAPIKey?.token, "legacy-key")
        XCTAssertNil(legacyToken)
        XCTAssertNil(legacyAPIKey)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func makeService(
        database: DatabaseManager? = nil,
        handler: @escaping @Sendable (URLRequest) throws -> (Int, String)
    ) -> TMDBMetadataService {
        MockURLProtocol.requestHandler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return TMDBMetadataService(
            credentialProvider: StaticTMDBCredentialProvider(readAccessToken: "dev-token"),
            cacheRepository: database.map(CacheRepository.init(databaseManager:)),
            session: session
        )
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
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
