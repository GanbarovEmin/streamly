import CineFlowCore
@preconcurrency import CineFlowDatabase
import Foundation

public enum MetadataServiceError: LocalizedError, Equatable {
    case networkUnavailable
    case rateLimited
    case invalidAPIKey
    case notFound
    case decodingFailed
    case missingCredentials
    case unsupportedProvider
    case requestFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            "Network is unavailable."
        case .rateLimited:
            "Metadata provider rate limit was reached."
        case .invalidAPIKey:
            "TMDB API credentials are invalid."
        case .notFound:
            "Metadata item was not found."
        case .decodingFailed:
            "Metadata response could not be decoded."
        case .missingCredentials:
            "TMDB API credentials are missing."
        case .unsupportedProvider:
            "Metadata provider is not supported."
        case let .requestFailed(statusCode):
            "Metadata request failed with HTTP \(statusCode)."
        }
    }
}

extension MetadataServiceError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        switch self {
        case .networkUnavailable:
            CineFlowError(
                category: .network,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: CineFlowError.defaultUserMessage(for: .network),
                recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .network),
                logLevel: .warning
            )
        case .invalidAPIKey, .missingCredentials:
            CineFlowError(
                category: .authentication,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: "Metadata credentials need attention.",
                recoverySuggestion: "Open settings and update TMDB credentials.",
                logLevel: .warning
            )
        default:
            CineFlowError(
                category: .metadata,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: CineFlowError.defaultUserMessage(for: .metadata),
                recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .metadata),
                logLevel: CineFlowError.defaultLogLevel(for: .metadata)
            )
        }
    }
}

public enum TMDBSettingsKeys {
    public static let readAccessToken = "tmdb_read_access_token"
    public static let apiKey = "tmdb_api_key"
}

public protocol TMDBCredentialProviding: Sendable {
    var readAccessToken: String? { get async }
    var apiKey: String? { get async }
}

public struct StaticTMDBCredentialProvider: TMDBCredentialProviding {
    private let token: String?
    private let key: String?

    public init(readAccessToken: String? = nil, apiKey: String? = nil) {
        token = readAccessToken
        key = apiKey
    }

    public var readAccessToken: String? {
        get async { token?.nilIfBlank }
    }

    public var apiKey: String? {
        get async { key?.nilIfBlank }
    }
}

public struct CompositeTMDBCredentialProvider: TMDBCredentialProviding {
    private let providers: [any TMDBCredentialProviding]

    public init(_ providers: [any TMDBCredentialProviding]) {
        self.providers = providers
    }

    public var readAccessToken: String? {
        get async {
            for provider in providers {
                if let token = await provider.readAccessToken {
                    return token
                }
            }
            return nil
        }
    }

    public var apiKey: String? {
        get async {
            for provider in providers {
                if let key = await provider.apiKey {
                    return key
                }
            }
            return nil
        }
    }
}

public final class KeychainTMDBCredentialProvider: TMDBCredentialProviding {
    private let keychainService: any KeychainServiceProtocol
    private let legacySettingsRepository: DatabaseSettingsRepository?

    public init(
        keychainService: any KeychainServiceProtocol,
        legacySettingsRepository: DatabaseSettingsRepository? = nil
    ) {
        self.keychainService = keychainService
        self.legacySettingsRepository = legacySettingsRepository
    }

    public var readAccessToken: String? {
        get async {
            await credentialValue(
                accountID: TMDBCredentialAccountIDs.readAccessToken,
                legacyKey: TMDBSettingsKeys.readAccessToken
            )
        }
    }

    public var apiKey: String? {
        get async {
            await credentialValue(
                accountID: TMDBCredentialAccountIDs.apiKey,
                legacyKey: TMDBSettingsKeys.apiKey
            )
        }
    }

    private func credentialValue(accountID: String, legacyKey: String) async -> String? {
        if let credential = try? await keychainService.readCredential(accountID: accountID),
           let token = credential.token?.nilIfBlank {
            return token
        }

        guard let legacySettingsRepository,
              let legacyValue = try? await legacySettingsRepository.string(forKey: legacyKey),
              let legacyValue = legacyValue.nilIfBlank
        else {
            return nil
        }

        _ = try? await keychainService.saveCredential(
            KeychainCredential(
                accountID: accountID,
                kind: .apiToken,
                sourceID: "tmdb",
                token: legacyValue
            )
        )
        await legacySettingsRepository.setMetadataCredential(nil, forKey: legacyKey)
        return legacyValue
    }
}

public struct LocalTMDBCredentialProvider: TMDBCredentialProviding {
    private let configURL: URL
    private let legacyConfigURL: URL?
    private let environment: [String: String]

    public init(
        configURL: URL = URL(fileURLWithPath: ".streamly/tmdb.local.json"),
        legacyConfigURL: URL? = URL(fileURLWithPath: ".cineflow/tmdb.local.json"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.configURL = configURL
        self.legacyConfigURL = legacyConfigURL
        self.environment = environment
    }

    public var readAccessToken: String? {
        get async {
            environment["TMDB_READ_ACCESS_TOKEN"]?.nilIfBlank ?? localConfig?.readAccessToken?.nilIfBlank
        }
    }

    public var apiKey: String? {
        get async {
            environment["TMDB_API_KEY"]?.nilIfBlank ?? localConfig?.apiKey?.nilIfBlank
        }
    }

    private var localConfig: TMDBLocalConfig? {
        for url in [configURL, legacyConfigURL].compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(TMDBLocalConfig.self, from: data)
            else {
                continue
            }
            return config
        }
        return nil
    }
}

public struct TMDBImageURLBuilder: Sendable {
    public enum ImageSize: Sendable {
        case poster
        case backdrop
        case profile
        case original
    }

    private let baseURL: URL

    public init(baseURL: URL = TMDBImageURLBuilder.defaultBaseURL) {
        self.baseURL = baseURL
    }

    public static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "image.tmdb.org"
        components.path = "/t/p"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public func url(path: String?, size: ImageSize) -> URL? {
        guard let path = path?.nilIfBlank else { return nil }
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return baseURL
            .appendingPathComponent(size.pathComponent)
            .appendingPathComponent(normalizedPath)
    }
}

public final class TMDBMetadataService: MetadataServiceProtocol {
    private let credentialProvider: any TMDBCredentialProviding
    private let cacheRepository: CacheRepository?
    private let session: URLSession
    private let baseURL: URL
    private let imageURLBuilder: TMDBImageURLBuilder
    private let decoder: JSONDecoder

    public init(
        credentialProvider: any TMDBCredentialProviding,
        cacheRepository: CacheRepository? = nil,
        session: URLSession = .shared,
        baseURL: URL = TMDBMetadataService.defaultBaseURL,
        imageURLBuilder: TMDBImageURLBuilder = TMDBImageURLBuilder()
    ) {
        self.credentialProvider = credentialProvider
        self.cacheRepository = cacheRepository
        self.session = session
        self.baseURL = baseURL
        self.imageURLBuilder = imageURLBuilder
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Self.tmdbDateFormatter)
    }

    public static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.themoviedb.org"
        components.path = "/3"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public func search(query: String) async throws -> [MediaItem] {
        async let movies = searchMovies(query: query)
        async let series = searchSeries(query: query)
        return try await movies + series
    }

    public func searchMovies(query: String) async throws -> [MediaItem] {
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(
            path: "/search/movie",
            queryItems: [URLQueryItem(name: "query", value: query)]
        )
        return response.results.map { $0.mediaItem(kindHint: .movie, imageURLBuilder: imageURLBuilder) }
    }

    public func searchSeries(query: String) async throws -> [MediaItem] {
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(
            path: "/search/tv",
            queryItems: [URLQueryItem(name: "query", value: query)]
        )
        return response.results.map { $0.mediaItem(kindHint: .series, imageURLBuilder: imageURLBuilder) }
    }

    public func movieDetail(tmdbID: Int) async throws -> Movie {
        let dto: TMDBMovieDetailDTO = try await fetch(
            path: "/movie/\(tmdbID)",
            queryItems: [URLQueryItem(name: "append_to_response", value: "videos,credits,recommendations")]
        )
        return dto.movie(imageURLBuilder: imageURLBuilder)
    }

    public func seriesDetail(tmdbID: Int) async throws -> Series {
        let dto: TMDBSeriesDetailDTO = try await fetch(
            path: "/tv/\(tmdbID)",
            queryItems: [URLQueryItem(name: "append_to_response", value: "videos,credits,recommendations")]
        )
        return dto.series(imageURLBuilder: imageURLBuilder)
    }

    public func seasonDetail(seriesTMDBID: Int, seasonNumber: Int) async throws -> Season {
        let dto: TMDBSeasonDetailDTO = try await fetch(path: "/tv/\(seriesTMDBID)/season/\(seasonNumber)")
        return dto.season(seriesTMDBID: seriesTMDBID)
    }

    public func episodeDetail(seriesTMDBID: Int, seasonNumber: Int, episodeNumber: Int) async throws -> Episode {
        let dto: TMDBEpisodeDTO = try await fetch(path: "/tv/\(seriesTMDBID)/season/\(seasonNumber)/episode/\(episodeNumber)")
        return dto.episode(seriesTMDBID: seriesTMDBID, seasonNumber: seasonNumber)
    }

    public func popularMovies() async throws -> [MediaItem] {
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(path: "/movie/popular")
        return response.results.map { $0.mediaItem(kindHint: .movie, imageURLBuilder: imageURLBuilder) }
    }

    public func popularSeries() async throws -> [MediaItem] {
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(path: "/tv/popular")
        return response.results.map { $0.mediaItem(kindHint: .series, imageURLBuilder: imageURLBuilder) }
    }

    public func trending() async throws -> [MediaItem] {
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(path: "/trending/all/week")
        return response.results.compactMap { $0.mediaItemFromMediaType(imageURLBuilder: imageURLBuilder) }
    }

    public func recommendations(for mediaID: String) async throws -> [MediaItem] {
        let endpoint = try TMDBEndpoint(mediaID: mediaID, suffix: "recommendations")
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(path: endpoint.path)
        return response.results.map { $0.mediaItem(kindHint: endpoint.kind, imageURLBuilder: imageURLBuilder) }
    }

    public func similar(to mediaID: String) async throws -> [MediaItem] {
        let endpoint = try TMDBEndpoint(mediaID: mediaID, suffix: "similar")
        let response: TMDBPagedResponse<TMDBMediaDTO> = try await fetch(path: endpoint.path)
        return response.results.map { $0.mediaItem(kindHint: endpoint.kind, imageURLBuilder: imageURLBuilder) }
    }

    public func videos(for mediaID: String) async throws -> [Trailer] {
        let endpoint = try TMDBEndpoint(mediaID: mediaID, suffix: "videos")
        let response: TMDBVideosResponse = try await fetch(path: endpoint.path)
        return response.results.compactMap(\.trailer)
    }

    public func credits(for mediaID: String) async throws -> [CastMember] {
        let endpoint = try TMDBEndpoint(mediaID: mediaID, suffix: "credits")
        let response: TMDBCreditsResponse = try await fetch(path: endpoint.path)
        return response.cast.map { $0.castMember(imageURLBuilder: imageURLBuilder) }
    }

    private func fetch<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try await request(path: path, queryItems: queryItems)
        let cacheKey = request.url?.absoluteString ?? path

        if let payload = try await cacheRepository?.metadata(cacheKey: cacheKey),
           let data = payload.data(using: .utf8) {
            return try decode(Response.self, from: data)
        }

        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response)

            if let payload = String(data: data, encoding: .utf8) {
                try await cacheRepository?.setMetadata(cacheKey: cacheKey, provider: "tmdb", payloadJSON: payload)
            }

            return try decode(Response.self, from: data)
        } catch let error as MetadataServiceError {
            throw error
        } catch let error as URLError {
            throw Self.map(urlError: error)
        } catch is DecodingError {
            throw MetadataServiceError.decodingFailed
        } catch {
            throw error
        }
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> URLRequest {
        let components = URLComponents(url: baseURL.appendingPathComponent(path.trimmedLeadingSlash), resolvingAgainstBaseURL: false)
        var items = queryItems

        if let token = await credentialProvider.readAccessToken {
            var request = URLRequest(url: try url(from: components, queryItems: items))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }

        if let apiKey = await credentialProvider.apiKey {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
            var request = URLRequest(url: try url(from: components, queryItems: items))
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return request
        }

        throw MetadataServiceError.missingCredentials
    }

    private func url(from components: URLComponents?, queryItems: [URLQueryItem]) throws -> URL {
        guard var components else { throw MetadataServiceError.requestFailed(-1) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems.sorted { $0.name < $1.name }
        guard let url = components.url else { throw MetadataServiceError.requestFailed(-1) }
        return url
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw MetadataServiceError.invalidAPIKey
        case 404:
            throw MetadataServiceError.notFound
        case 429:
            throw MetadataServiceError.rateLimited
        default:
            throw MetadataServiceError.requestFailed(httpResponse.statusCode)
        }
    }

    private func decode<Response: Decodable>(_ response: Response.Type, from data: Data) throws -> Response {
        do {
            return try decoder.decode(response, from: data)
        } catch {
            throw MetadataServiceError.decodingFailed
        }
    }

    private static func map(urlError: URLError) -> MetadataServiceError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut:
            .networkUnavailable
        default:
            .requestFailed(urlError.errorCode)
        }
    }

    fileprivate static let tmdbDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct TMDBLocalConfig: Decodable {
    let readAccessToken: String?
    let apiKey: String?
}

private struct TMDBEndpoint {
    let kind: MediaKind
    let path: String

    init(mediaID: String, suffix: String) throws {
        let parts = mediaID.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "tmdb", let tmdbID = Int(parts[2]) else {
            throw MetadataServiceError.unsupportedProvider
        }

        switch parts[1] {
        case "movie":
            kind = .movie
            path = "/movie/\(tmdbID)/\(suffix)"
        case "tv":
            kind = .series
            path = "/tv/\(tmdbID)/\(suffix)"
        default:
            throw MetadataServiceError.unsupportedProvider
        }
    }
}

private struct TMDBPagedResponse<Result: Decodable>: Decodable {
    let results: [Result]
}

private struct TMDBMediaDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let genreIDs: [Int]?
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case overview
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
        case mediaType = "media_type"
    }

    func mediaItemFromMediaType(imageURLBuilder: TMDBImageURLBuilder) -> MediaItem? {
        switch mediaType {
        case "movie":
            mediaItem(kindHint: .movie, imageURLBuilder: imageURLBuilder)
        case "tv":
            mediaItem(kindHint: .series, imageURLBuilder: imageURLBuilder)
        default:
            nil
        }
    }

    func mediaItem(kindHint: MediaKind, imageURLBuilder: TMDBImageURLBuilder) -> MediaItem {
        let title = displayTitle(for: kindHint)
        let originalTitle = originalDisplayTitle(for: kindHint)
        let year = Self.year(from: kindHint == .movie ? releaseDate : firstAirDate)
        let resolvedReleaseDate = Self.date(from: kindHint == .movie ? releaseDate : firstAirDate)
        let metadata = MediaMetadata(
            tmdbId: id,
            title: title,
            originalTitle: originalTitle,
            overview: overview ?? "",
            year: year,
            releaseDate: resolvedReleaseDate,
            genres: (genreIDs ?? []).compactMap { Self.genreNames[$0] },
            rating: voteAverage,
            posterURL: imageURLBuilder.url(path: posterPath, size: .poster),
            backdropURL: imageURLBuilder.url(path: backdropPath, size: .backdrop)
        )

        return MediaItem(
            id: kindHint == .movie ? "tmdb:movie:\(id)" : "tmdb:tv:\(id)",
            title: title,
            kind: kindHint,
            overview: overview ?? "",
            releaseYear: year,
            posterPath: imageURLBuilder.url(path: posterPath, size: .poster)?.absoluteString,
            metadata: metadata
        )
    }

    private func displayTitle(for kind: MediaKind) -> String {
        switch kind {
        case .movie:
            (title ?? name ?? originalTitle ?? originalName ?? "").nilIfBlank ?? "Untitled"
        case .series:
            (name ?? title ?? originalName ?? originalTitle ?? "").nilIfBlank ?? "Untitled"
        }
    }

    private func originalDisplayTitle(for kind: MediaKind) -> String {
        switch kind {
        case .movie:
            (originalTitle ?? title ?? originalName ?? name ?? "").nilIfBlank ?? "Untitled"
        case .series:
            (originalName ?? name ?? originalTitle ?? title ?? "").nilIfBlank ?? "Untitled"
        }
    }

    static func year(from date: String?) -> Int? {
        guard let prefix = date?.prefix(4), prefix.count == 4 else { return nil }
        return Int(prefix)
    }

    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return TMDBMetadataService.tmdbDateFormatter.date(from: value)
    }

    static let genreNames: [Int: String] = [
        12: "Adventure",
        14: "Fantasy",
        16: "Animation",
        18: "Drama",
        27: "Horror",
        28: "Action",
        35: "Comedy",
        36: "History",
        37: "Western",
        53: "Thriller",
        80: "Crime",
        99: "Documentary",
        878: "Sci-Fi",
        9648: "Mystery",
        10402: "Music",
        10749: "Romance",
        10751: "Family",
        10752: "War",
        10759: "Action & Adventure",
        10765: "Sci-Fi & Fantasy"
    ]
}

private struct TMDBGenreDTO: Decodable {
    let id: Int
    let name: String
}

private struct TMDBMovieDetailDTO: Decodable {
    let id: Int
    let imdbID: String?
    let title: String
    let originalTitle: String?
    let overview: String?
    let releaseDate: String?
    let runtime: Int?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let genres: [TMDBGenreDTO]?
    let videos: TMDBVideosResponse?
    let credits: TMDBCreditsResponse?

    enum CodingKeys: String, CodingKey {
        case id
        case imdbID = "imdb_id"
        case title
        case originalTitle = "original_title"
        case overview
        case releaseDate = "release_date"
        case runtime
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case genres
        case videos
        case credits
    }

    func movie(imageURLBuilder: TMDBImageURLBuilder) -> Movie {
        let year = TMDBMediaDTO.year(from: releaseDate)
        let metadata = MediaMetadata(
            tmdbId: id,
            imdbId: imdbID,
            title: title,
            originalTitle: originalTitle ?? title,
            overview: overview ?? "",
            year: year,
            releaseDate: TMDBMediaDTO.date(from: releaseDate),
            genres: genres?.map(\.name) ?? [],
            runtime: runtime,
            rating: voteAverage,
            posterURL: imageURLBuilder.url(path: posterPath, size: .poster),
            backdropURL: imageURLBuilder.url(path: backdropPath, size: .backdrop),
            trailerURLs: videos?.results.compactMap(\.trailerURL) ?? [],
            cast: credits?.cast.map { $0.castMember(imageURLBuilder: imageURLBuilder) } ?? []
        )
        let item = MediaItem(
            id: "tmdb:movie:\(id)",
            title: title,
            kind: .movie,
            overview: overview ?? "",
            releaseYear: year,
            posterPath: imageURLBuilder.url(path: posterPath, size: .poster)?.absoluteString,
            metadata: metadata
        )
        return Movie(id: item.id, mediaItem: item, metadata: metadata)
    }
}

private struct TMDBSeriesDetailDTO: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let genres: [TMDBGenreDTO]?
    let seasons: [TMDBSeasonSummaryDTO]?
    let videos: TMDBVideosResponse?
    let credits: TMDBCreditsResponse?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case originalName = "original_name"
        case overview
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case genres
        case seasons
        case videos
        case credits
    }

    func series(imageURLBuilder: TMDBImageURLBuilder) -> Series {
        let year = TMDBMediaDTO.year(from: firstAirDate)
        let metadata = MediaMetadata(
            tmdbId: id,
            title: name,
            originalTitle: originalName ?? name,
            overview: overview ?? "",
            year: year,
            releaseDate: TMDBMediaDTO.date(from: firstAirDate),
            genres: genres?.map(\.name) ?? [],
            rating: voteAverage,
            posterURL: imageURLBuilder.url(path: posterPath, size: .poster),
            backdropURL: imageURLBuilder.url(path: backdropPath, size: .backdrop),
            trailerURLs: videos?.results.compactMap(\.trailerURL) ?? [],
            cast: credits?.cast.map { $0.castMember(imageURLBuilder: imageURLBuilder) } ?? []
        )
        let item = MediaItem(
            id: "tmdb:tv:\(id)",
            title: name,
            kind: .series,
            overview: overview ?? "",
            releaseYear: year,
            posterPath: imageURLBuilder.url(path: posterPath, size: .poster)?.absoluteString,
            metadata: metadata
        )
        return Series(
            id: item.id,
            mediaItem: item,
            metadata: metadata,
            seasons: seasons?.map { $0.season(seriesTMDBID: id) } ?? []
        )
    }
}

private struct TMDBSeasonSummaryDTO: Decodable {
    let seasonNumber: Int
    let name: String?
    let overview: String?

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case name
        case overview
    }

    func season(seriesTMDBID: Int) -> Season {
        Season(
            id: "tmdb:tv:\(seriesTMDBID):season:\(seasonNumber)",
            seriesID: "tmdb:tv:\(seriesTMDBID)",
            seasonNumber: seasonNumber,
            title: name,
            overview: overview
        )
    }
}

private struct TMDBSeasonDetailDTO: Decodable {
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let episodes: [TMDBEpisodeDTO]

    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case name
        case overview
        case episodes
    }

    func season(seriesTMDBID: Int) -> Season {
        Season(
            id: "tmdb:tv:\(seriesTMDBID):season:\(seasonNumber)",
            seriesID: "tmdb:tv:\(seriesTMDBID)",
            seasonNumber: seasonNumber,
            title: name,
            overview: overview,
            episodes: episodes.map { $0.episode(seriesTMDBID: seriesTMDBID, seasonNumber: seasonNumber) }
        )
    }
}

private struct TMDBEpisodeDTO: Decodable {
    let episodeNumber: Int
    let name: String?
    let overview: String?
    let runtime: Int?
    let airDate: Date?

    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number"
        case name
        case overview
        case runtime
        case airDate = "air_date"
    }

    func episode(seriesTMDBID: Int, seasonNumber: Int) -> Episode {
        let seasonID = "tmdb:tv:\(seriesTMDBID):season:\(seasonNumber)"
        return Episode(
            id: "\(seasonID):episode:\(episodeNumber)",
            seriesID: "tmdb:tv:\(seriesTMDBID)",
            seasonID: seasonID,
            episodeNumber: episodeNumber,
            title: name ?? "Episode \(episodeNumber)",
            overview: overview,
            runtimeMinutes: runtime,
            airDate: airDate
        )
    }
}

private struct TMDBVideosResponse: Decodable {
    let results: [TMDBVideoDTO]
}

private struct TMDBVideoDTO: Decodable {
    let id: String
    let name: String
    let site: String?
    let key: String

    var trailerURL: URL? {
        guard site?.lowercased() == "youtube" else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    var trailer: Trailer? {
        guard let trailerURL else { return nil }
        return Trailer(id: id, title: name, url: trailerURL, site: site)
    }
}

private struct TMDBCreditsResponse: Decodable {
    let cast: [TMDBCastDTO]
}

private struct TMDBCastDTO: Decodable {
    let id: Int
    let name: String
    let character: String?
    let profilePath: String?
    let order: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case character
        case profilePath = "profile_path"
        case order
    }

    func castMember(imageURLBuilder: TMDBImageURLBuilder) -> CastMember {
        CastMember(
            id: "tmdb:person:\(id)",
            name: name,
            characterName: character,
            profileURL: imageURLBuilder.url(path: profilePath, size: .profile),
            order: order
        )
    }
}

private extension TMDBImageURLBuilder.ImageSize {
    var pathComponent: String {
        switch self {
        case .poster:
            "w500"
        case .backdrop:
            "w1280"
        case .profile:
            "w185"
        case .original:
            "original"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedLeadingSlash: String {
        hasPrefix("/") ? String(dropFirst()) : self
    }
}
