import CineFlowCore
@preconcurrency import CineFlowDatabase
import Foundation

public final class CinemetaMetadataService: MetadataServiceProtocol, MetadataCacheControlProtocol {
    private static let topCatalogPageSize = 50
    private static let topCatalogPageLimit = 4

    private let cacheRepository: CacheRepository?
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    public init(
        cacheRepository: CacheRepository? = nil,
        session: URLSession = .shared,
        baseURL: URL = CinemetaMetadataService.defaultBaseURL
    ) {
        self.cacheRepository = cacheRepository
        self.session = session
        self.baseURL = baseURL
        decoder = JSONDecoder()
    }

    public static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "v3-cinemeta.strem.io"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public func search(query: String) async throws -> [MediaItem] {
        async let movies = searchMovies(query: query)
        async let series = searchSeries(query: query)
        return try await movies + series
    }

    public func matchCandidates(query: String, kind: MediaKind, year: Int? = nil) async throws -> [MetadataMatchCandidate] {
        let items: [MediaItem]
        switch kind {
        case .movie:
            items = try await searchMovies(query: query)
        case .series:
            items = try await searchSeries(query: query)
        }

        return items
            .compactMap { item in
                MetadataMatcher.candidate(for: item, query: query, kind: kind, year: year)
            }
            .sorted {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return $0.item.displayTitle < $1.item.displayTitle
            }
    }

    public func searchMovies(query: String) async throws -> [MediaItem] {
        try await catalog(type: .movie, id: "top", extraPath: "search=\(Self.pathEncoded(query))")
    }

    public func searchSeries(query: String) async throws -> [MediaItem] {
        try await catalog(type: .series, id: "top", extraPath: "search=\(Self.pathEncoded(query))")
    }

    public func movieDetail(imdbID: String) async throws -> Movie {
        let response: CinemetaMetaResponse = try await fetch(path: "/meta/movie/\(Self.pathEncoded(imdbID)).json")
        let meta = try response.requireMeta()
        return meta.movie()
    }

    public func seriesDetail(imdbID: String) async throws -> Series {
        let response: CinemetaMetaResponse = try await fetch(path: "/meta/series/\(Self.pathEncoded(imdbID)).json")
        let meta = try response.requireMeta()
        return meta.series()
    }

    public func popularMovies() async throws -> [MediaItem] {
        try await topCatalog(type: .movie)
    }

    public func popularSeries() async throws -> [MediaItem] {
        try await topCatalog(type: .series)
    }

    public func catalog(kind: MetadataCatalogKind, mediaKind: MediaKind) async throws -> [MediaItem] {
        let type = CinemetaMediaType(mediaKind: mediaKind)
        switch kind {
        case .popular:
            return try await topCatalog(type: type)
        case .newByYear(let year):
            return try await pagedCatalog(type: type, id: "year", firstExtraPath: "genre=\(year)")
        case .featuredByIMDbRating:
            return try await pagedCatalog(type: type, id: "imdbRating")
        }
    }

    public func trending() async throws -> [MediaItem] {
        async let movies = catalog(type: .movie, id: "top")
        async let series = catalog(type: .series, id: "top")
        return try await movies + series
    }

    public func videos(for mediaID: String) async throws -> [Trailer] {
        let meta = try await meta(for: mediaID)
        return meta.trailerObjects
    }

    public func credits(for mediaID: String) async throws -> [CastMember] {
        let meta = try await meta(for: mediaID)
        return meta.castMembers
    }

    public func refreshMetadata(for mediaID: String) async throws {
        try await clearMetadataCache(for: mediaID)
        _ = try await meta(for: mediaID)
    }

    public func clearMetadataCache(for mediaID: String) async throws {
        guard let id = CinemetaMediaID(mediaID) else {
            throw MetadataServiceError.unsupportedProvider
        }
        let path = "/meta/\(id.type.rawValue)/\(Self.pathEncoded(id.imdbID)).json"
        let url = baseURL.appendingPathComponent(path.trimmedLeadingSlash)
        try await cacheRepository?.removeMetadata(cacheKey: url.absoluteString)
    }

    private func catalog(type: CinemetaMediaType, id: String, extraPath: String? = nil) async throws -> [MediaItem] {
        let path: String
        if let extraPath {
            path = "/catalog/\(type.rawValue)/\(id)/\(extraPath).json"
        } else {
            path = "/catalog/\(type.rawValue)/\(id).json"
        }
        let response: CinemetaCatalogResponse = try await fetch(path: path)
        return response.metas.compactMap { $0.mediaItem(typeHint: type) }
    }

    private func topCatalog(type: CinemetaMediaType) async throws -> [MediaItem] {
        try await pagedCatalog(type: type, id: "top")
    }

    private func pagedCatalog(type: CinemetaMediaType, id: String, firstExtraPath: String? = nil) async throws -> [MediaItem] {
        var seen: Set<String> = []
        var items: [MediaItem] = []

        for pageIndex in 0..<Self.topCatalogPageLimit {
            let skip = pageIndex * Self.topCatalogPageSize
            let extraPath = skip == 0 ? firstExtraPath : Self.appendingSkip(skip, to: firstExtraPath)
            let pageItems = try await catalog(type: type, id: id, extraPath: extraPath)
            guard !pageItems.isEmpty else { break }

            for item in pageItems where seen.insert(item.id).inserted {
                items.append(item)
            }
        }

        return items
    }

    private static func appendingSkip(_ skip: Int, to extraPath: String?) -> String {
        guard let extraPath, !extraPath.isEmpty else {
            return "skip=\(skip)"
        }
        return "\(extraPath)&skip=\(skip)"
    }

    private func meta(for mediaID: String) async throws -> CinemetaMetaDTO {
        guard let id = CinemetaMediaID(mediaID) else {
            throw MetadataServiceError.unsupportedProvider
        }
        let response: CinemetaMetaResponse = try await fetch(path: "/meta/\(id.type.rawValue)/\(Self.pathEncoded(id.imdbID)).json")
        return try response.requireMeta()
    }

    private func fetch<Response: Decodable>(path: String) async throws -> Response {
        let url = baseURL.appendingPathComponent(path.trimmedLeadingSlash)
        let cacheKey = url.absoluteString

        if let payload = try await cacheRepository?.metadata(cacheKey: cacheKey),
           let data = payload.data(using: .utf8) {
            return try decode(Response.self, from: data)
        }

        do {
            let (data, response) = try await session.data(from: url)
            try validate(response: response)

            if let payload = String(data: data, encoding: .utf8) {
                try await cacheRepository?.setMetadata(cacheKey: cacheKey, provider: "cinemeta", payloadJSON: payload)
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

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200..<300:
            return
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

    private static func pathEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

public struct CompositeMetadataService: MetadataServiceProtocol {
    private let primary: any MetadataServiceProtocol
    private let fallback: any MetadataServiceProtocol

    public init(primary: any MetadataServiceProtocol, fallback: any MetadataServiceProtocol) {
        self.primary = primary
        self.fallback = fallback
    }

    public func search(query: String) async throws -> [MediaItem] {
        try await withFallback { try await primary.search(query: query) } fallback: { try await fallback.search(query: query) }
    }

    public func searchMovies(query: String) async throws -> [MediaItem] {
        try await withFallback { try await primary.searchMovies(query: query) } fallback: { try await fallback.searchMovies(query: query) }
    }

    public func searchSeries(query: String) async throws -> [MediaItem] {
        try await withFallback { try await primary.searchSeries(query: query) } fallback: { try await fallback.searchSeries(query: query) }
    }

    public func movieDetail(tmdbID: Int) async throws -> Movie {
        try await withFallback { try await primary.movieDetail(tmdbID: tmdbID) } fallback: { try await fallback.movieDetail(tmdbID: tmdbID) }
    }

    public func movieDetail(imdbID: String) async throws -> Movie {
        try await withFallback { try await primary.movieDetail(imdbID: imdbID) } fallback: { try await fallback.movieDetail(imdbID: imdbID) }
    }

    public func seriesDetail(tmdbID: Int) async throws -> Series {
        try await withFallback { try await primary.seriesDetail(tmdbID: tmdbID) } fallback: { try await fallback.seriesDetail(tmdbID: tmdbID) }
    }

    public func seriesDetail(imdbID: String) async throws -> Series {
        try await withFallback { try await primary.seriesDetail(imdbID: imdbID) } fallback: { try await fallback.seriesDetail(imdbID: imdbID) }
    }

    public func seasonDetail(seriesTMDBID: Int, seasonNumber: Int) async throws -> Season {
        try await withFallback { try await primary.seasonDetail(seriesTMDBID: seriesTMDBID, seasonNumber: seasonNumber) } fallback: { try await fallback.seasonDetail(seriesTMDBID: seriesTMDBID, seasonNumber: seasonNumber) }
    }

    public func episodeDetail(seriesTMDBID: Int, seasonNumber: Int, episodeNumber: Int) async throws -> Episode {
        try await withFallback { try await primary.episodeDetail(seriesTMDBID: seriesTMDBID, seasonNumber: seasonNumber, episodeNumber: episodeNumber) } fallback: { try await fallback.episodeDetail(seriesTMDBID: seriesTMDBID, seasonNumber: seasonNumber, episodeNumber: episodeNumber) }
    }

    public func popularMovies() async throws -> [MediaItem] {
        try await withFallback { try await primary.popularMovies() } fallback: { try await fallback.popularMovies() }
    }

    public func popularSeries() async throws -> [MediaItem] {
        try await withFallback { try await primary.popularSeries() } fallback: { try await fallback.popularSeries() }
    }

    public func catalog(kind: MetadataCatalogKind, mediaKind: MediaKind) async throws -> [MediaItem] {
        try await withFallback { try await primary.catalog(kind: kind, mediaKind: mediaKind) } fallback: { try await fallback.catalog(kind: kind, mediaKind: mediaKind) }
    }

    public func trending() async throws -> [MediaItem] {
        try await withFallback { try await primary.trending() } fallback: { try await fallback.trending() }
    }

    public func recommendations(for mediaID: String) async throws -> [MediaItem] {
        try await withFallback { try await primary.recommendations(for: mediaID) } fallback: { try await fallback.recommendations(for: mediaID) }
    }

    public func similar(to mediaID: String) async throws -> [MediaItem] {
        try await withFallback { try await primary.similar(to: mediaID) } fallback: { try await fallback.similar(to: mediaID) }
    }

    public func videos(for mediaID: String) async throws -> [Trailer] {
        try await withFallback { try await primary.videos(for: mediaID) } fallback: { try await fallback.videos(for: mediaID) }
    }

    public func credits(for mediaID: String) async throws -> [CastMember] {
        try await withFallback { try await primary.credits(for: mediaID) } fallback: { try await fallback.credits(for: mediaID) }
    }

    private func withFallback<Value>(
        _ primaryOperation: () async throws -> Value,
        fallback fallbackOperation: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await primaryOperation()
        } catch {
            return try await fallbackOperation()
        }
    }
}

private enum CinemetaMediaType: String {
    case movie
    case series

    init(mediaKind: MediaKind) {
        switch mediaKind {
        case .movie:
            self = .movie
        case .series:
            self = .series
        }
    }

    var kind: MediaKind {
        switch self {
        case .movie: .movie
        case .series: .series
        }
    }
}

private struct CinemetaMediaID {
    let type: CinemetaMediaType
    let imdbID: String

    init?(_ value: String) {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "imdb" else { return nil }
        switch parts[1] {
        case "movie":
            type = .movie
        case "series":
            type = .series
        default:
            return nil
        }
        guard parts[2].range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        imdbID = parts[2]
    }
}

private struct CinemetaCatalogResponse: Decodable {
    let metas: [CinemetaMetaDTO]
}

private struct CinemetaMetaResponse: Decodable {
    let meta: CinemetaMetaDTO?

    func requireMeta() throws -> CinemetaMetaDTO {
        guard let meta else { throw MetadataServiceError.notFound }
        return meta
    }
}

private struct CinemetaMetaDTO: Decodable {
    let id: String?
    let imdbID: String?
    let moviedbID: Int?
    let type: String?
    let name: String?
    let description: String?
    let genre: [String]?
    let genres: [String]?
    let imdbRating: String?
    let poster: String?
    let background: String?
    let logo: String?
    let releaseInfo: String?
    let released: String?
    let runtime: CinemetaRuntime?
    let trailers: [CinemetaTrailerDTO]?
    let cast: [String]?
    let videos: [CinemetaVideoDTO]?
    let aliases: [String]?
    let alias: [String]?
    let alternativeTitles: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case imdbID = "imdb_id"
        case moviedbID = "moviedb_id"
        case type
        case name
        case description
        case genre
        case genres
        case imdbRating
        case poster
        case background
        case logo
        case releaseInfo
        case released
        case runtime
        case trailers
        case cast
        case videos
        case aliases
        case alias
        case alternativeTitles
    }

    func mediaItem(typeHint: CinemetaMediaType? = nil) -> MediaItem? {
        guard let mediaType = resolvedType(typeHint: typeHint),
              let imdbID = resolvedIMDbID
        else {
            return nil
        }
        let title = name?.nilIfBlank ?? "Untitled"
        let metadata = metadata(type: mediaType)
        return MediaItem(
            id: "imdb:\(mediaType.rawValue):\(imdbID)",
            title: title,
            kind: mediaType.kind,
            overview: description ?? "",
            releaseYear: metadata.year,
            posterPath: poster,
            metadata: metadata
        )
    }

    func movie() -> Movie {
        let metadata = metadata(type: .movie)
        let item = MediaItem(
            id: "imdb:movie:\(metadata.imdbId ?? resolvedIMDbID ?? "")",
            title: metadata.title,
            kind: .movie,
            overview: metadata.overview,
            releaseYear: metadata.year,
            posterPath: poster,
            metadata: metadata
        )
        return Movie(id: item.id, mediaItem: item, metadata: metadata)
    }

    func series() -> Series {
        let metadata = metadata(type: .series)
        let seriesID = "imdb:series:\(metadata.imdbId ?? resolvedIMDbID ?? "")"
        let item = MediaItem(
            id: seriesID,
            title: metadata.title,
            kind: .series,
            overview: metadata.overview,
            releaseYear: metadata.year,
            posterPath: poster,
            metadata: metadata
        )
        return Series(id: item.id, mediaItem: item, metadata: metadata, seasons: seasons(seriesID: seriesID))
    }

    var trailerObjects: [Trailer] {
        (trailers ?? []).compactMap { trailer in
            guard let source = trailer.source?.nilIfBlank,
                  let url = URL(string: "https://www.youtube.com/watch?v=\(source)")
            else {
                return nil
            }
            return Trailer(id: source, title: trailer.type?.nilIfBlank ?? "Trailer", url: url, site: "YouTube")
        }
    }

    var castMembers: [CastMember] {
        (cast ?? []).enumerated().map { index, name in
            CastMember(id: "cinemeta-cast-\(index)-\(name)", name: name, order: index)
        }
    }

    private func metadata(type: CinemetaMediaType) -> MediaMetadata {
        let imdbID = resolvedIMDbID
        let title = name?.nilIfBlank ?? "Untitled"
        return MediaMetadata(
            tmdbId: moviedbID ?? Self.numericIMDbFallback(imdbID),
            imdbId: imdbID,
            title: title,
            originalTitle: title,
            overview: description ?? "",
            year: year,
            releaseDate: releaseDate,
            genres: genre ?? genres ?? [],
            runtime: runtime?.minutes,
            rating: imdbRating.flatMap(Double.init),
            posterURL: poster.flatMap(URL.init(string:)),
            backdropURL: background.flatMap(URL.init(string:)),
            logoURL: logo.flatMap(URL.init(string:)),
            trailerURLs: trailerObjects.map(\.url),
            cast: castMembers,
            alternativeTitles: resolvedAlternativeTitles,
            posterCandidates: poster.flatMap { URL(string: $0) }.map { [MetadataArtworkCandidate(url: $0, score: 1)] } ?? [],
            backdropCandidates: background.flatMap { URL(string: $0) }.map { [MetadataArtworkCandidate(url: $0, score: 1)] } ?? []
        )
    }

    private var resolvedAlternativeTitles: [String] {
        Array(NSOrderedSet(array: (aliases ?? []) + (alias ?? []) + (alternativeTitles ?? []))) as? [String] ?? []
    }

    private func seasons(seriesID: String) -> [Season] {
        let grouped = Dictionary(grouping: videos ?? []) { $0.season ?? 0 }
        return grouped.keys.sorted().compactMap { seasonNumber in
            guard seasonNumber > 0 else { return nil }
            let episodes = (grouped[seasonNumber] ?? [])
                .sorted { ($0.episode ?? $0.number ?? 0) < ($1.episode ?? $1.number ?? 0) }
                .map { $0.episodeModel(seriesID: seriesID, seasonNumber: seasonNumber) }
            return Season(
                id: "\(seriesID):season:\(seasonNumber)",
                seriesID: seriesID,
                seasonNumber: seasonNumber,
                title: "Season \(seasonNumber)",
                episodes: episodes
            )
        }
    }

    private func resolvedType(typeHint: CinemetaMediaType?) -> CinemetaMediaType? {
        switch type {
        case "movie":
            return .movie
        case "series":
            return .series
        default:
            return typeHint
        }
    }

    private var resolvedIMDbID: String? {
        (imdbID ?? id)?.nilIfBlank
    }

    private var year: Int? {
        let candidates = [released, releaseInfo]
        for candidate in candidates {
            guard let prefix = candidate?.prefix(4), prefix.count == 4, let year = Int(prefix) else { continue }
            return year
        }
        return nil
    }

    private var releaseDate: Date? {
        Self.date(from: released ?? releaseInfo)
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func numericIMDbFallback(_ imdbID: String?) -> Int {
        guard let digits = imdbID?.dropFirst(2), let value = Int(digits) else { return 0 }
        return value
    }
}

private struct CinemetaTrailerDTO: Decodable {
    let source: String?
    let type: String?
}

private struct CinemetaVideoDTO: Decodable {
    let id: String?
    let name: String?
    let title: String?
    let season: Int?
    let number: Int?
    let episode: Int?
    let overview: String?
    let description: String?
    let runtime: Int?
    let firstAired: String?
    let released: String?
    let thumbnail: String?
    let poster: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case title
        case season
        case number
        case episode
        case overview
        case description
        case runtime
        case firstAired
        case released
        case thumbnail
        case poster
    }

    func episodeModel(seriesID: String, seasonNumber: Int) -> Episode {
        let episodeNumber = episode ?? number ?? 0
        return Episode(
            id: id ?? "\(seriesID):\(seasonNumber):\(episodeNumber)",
            seriesID: seriesID,
            seasonID: "\(seriesID):season:\(seasonNumber)",
            episodeNumber: episodeNumber,
            title: name ?? title ?? "Episode \(episodeNumber)",
            overview: overview ?? description,
            runtimeMinutes: runtime,
            airDate: Self.date(from: firstAired ?? released),
            thumbnailURL: Self.url(from: thumbnail ?? poster)
        )
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func url(from value: String?) -> URL? {
        guard let value = value?.nilIfBlank else { return nil }
        return URL(string: value)
    }
}

private enum CinemetaRuntime: Decodable {
    case minutes(Int)

    var minutes: Int? {
        switch self {
        case .minutes(let value):
            value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .minutes(intValue)
            return
        }
        let stringValue = try container.decode(String.self)
        let match = stringValue.firstMatch(pattern: #"([0-9]+)"#)
        self = .minutes(match.flatMap(Int.init) ?? 0)
    }
}

private enum MetadataMatcher {
    static func candidate(
        for item: MediaItem,
        query: String,
        kind: MediaKind,
        year: Int?
    ) -> MetadataMatchCandidate? {
        guard item.kind == kind else { return nil }

        let normalizedQuery = normalize(query)
        let title = normalize(item.displayTitle)
        let originalTitle = normalize(item.metadata?.originalTitle ?? "")
        let alternativeTitles = item.metadata?.alternativeTitles.map(normalize) ?? []

        var score = 0.15
        var reasons: [MetadataMatchReason] = [.mediaTypeMatch]

        if title == normalizedQuery || normalize(item.title) == normalizedQuery {
            score += 0.58
            reasons.append(.exactTitle)
        } else if originalTitle == normalizedQuery {
            score += 0.54
            reasons.append(.originalTitle)
        } else if alternativeTitles.contains(normalizedQuery) {
            score += 0.52
            reasons.append(.alternativeTitle)
        } else if title.contains(normalizedQuery) || normalizedQuery.contains(title) {
            score += 0.38
            reasons.append(.fuzzyTitle)
        } else if alternativeTitles.contains(where: { $0.contains(normalizedQuery) || normalizedQuery.contains($0) }) {
            score += 0.34
            reasons.append(.alternativeTitle)
        } else {
            return nil
        }

        if let expectedYear = year {
            let actualYear = item.metadata?.year ?? item.releaseYear
            if actualYear == expectedYear {
                score += 0.22
                reasons.append(.yearMatch)
            } else {
                score -= 0.14
                reasons.append(.yearMismatch(expected: expectedYear, actual: actualYear))
            }
        }

        return MetadataMatchCandidate(item: item, confidence: score, reasons: reasons)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"^\s*the\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var trimmedLeadingSlash: String {
        hasPrefix("/") ? String(dropFirst()) : self
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func firstMatch(pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = expression.firstMatch(in: self, range: range),
              let matchRange = Range(match.range(at: 1), in: self)
        else {
            return nil
        }
        return String(self[matchRange])
    }
}
