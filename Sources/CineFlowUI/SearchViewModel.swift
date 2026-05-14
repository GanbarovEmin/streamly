import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum SearchViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum SearchMediaType: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case movies
    case series

    public var id: String { rawValue }
}

public enum SearchSortOption: String, CaseIterable, Identifiable, Equatable, Sendable {
    case bestMatch
    case bestQuality
    case mostSeeders
    case smallestSize
    case newest
    case preferredLanguage
    case rating

    public var id: String { rawValue }

    public static var best: SearchSortOption { .bestMatch }
    public static var quality: SearchSortOption { .bestQuality }
    public static var seeders: SearchSortOption { .mostSeeders }
    public static var size: SearchSortOption { .smallestSize }
    public static var date: SearchSortOption { .newest }
}

public struct SearchFilters: Equatable, Sendable {
    public var mediaType: SearchMediaType = .all
    public var qualities: Set<ReleaseQuality> = []
    public var requiresHDR = false
    public var source: String?
    public var year: Int?
    public var audioLanguage: String?
    public var subtitleLanguage: String?
    public var minimumSizeBytes: Int64?
    public var maximumSizeBytes: Int64?
    public var codec: VideoCodec?
    public var minimumRating: Double?

    public init() {}

    public var hasActiveFilters: Bool {
        mediaType != .all ||
            !qualities.isEmpty ||
            requiresHDR ||
            source?.isEmpty == false ||
            year != nil ||
            audioLanguage?.isEmpty == false ||
            subtitleLanguage?.isEmpty == false ||
            minimumSizeBytes != nil ||
            maximumSizeBytes != nil ||
            codec != nil ||
            minimumRating != nil
    }
}

public protocol SearchPreferencesStoreProtocol: AnyObject {
    var recentSearches: [String] { get set }
    var sortOption: SearchSortOption { get set }
}

public final class UserDefaultsSearchPreferencesStore: SearchPreferencesStoreProtocol {
    private let userDefaults: UserDefaults
    private let recentSearchesKey = "streamly.search.recentSearches.v1"
    private let sortOptionKey = "streamly.search.sortOption.v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var recentSearches: [String] {
        get { userDefaults.stringArray(forKey: recentSearchesKey) ?? [] }
        set { userDefaults.set(Array(newValue.prefix(10)), forKey: recentSearchesKey) }
    }

    public var sortOption: SearchSortOption {
        get {
            guard let rawValue = userDefaults.string(forKey: sortOptionKey),
                  let option = SearchSortOption(rawValue: rawValue)
            else { return .bestMatch }
            return option
        }
        set { userDefaults.set(newValue.rawValue, forKey: sortOptionKey) }
    }
}

public final class InMemorySearchPreferencesStore: SearchPreferencesStoreProtocol {
    public var recentSearches: [String]
    public var sortOption: SearchSortOption

    public init(recentSearches: [String] = [], sortOption: SearchSortOption = .bestMatch) {
        self.recentSearches = recentSearches
        self.sortOption = sortOption
    }
}

public enum SearchSuggestionKind: String, Equatable, Sendable {
    case recent
    case trending
    case title
    case originalTitle
    case localizedTitle
    case actor
    case director
    case genre
    case year
    case typoCorrection
    case quickFilter
}

public enum SearchQuickFilter: String, Equatable, Sendable {
    case movies
    case series
    case ultraHD
    case russianAudio
}

public struct SearchSuggestion: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let query: String
    public let kind: SearchSuggestionKind
    public let quickFilter: SearchQuickFilter?

    public init(
        id: String,
        title: String,
        subtitle: String,
        query: String,
        kind: SearchSuggestionKind,
        quickFilter: SearchQuickFilter? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.query = query
        self.kind = kind
        self.quickFilter = quickFilter
    }
}

public struct SearchSuggestionCatalogItem: Equatable, Sendable {
    public let id: String
    public let title: String
    public let originalTitle: String?
    public let localizedTitles: [String]
    public let kind: SeedMediaKind
    public let year: Int
    public let genres: [String]
    public let actors: [String]
    public let directors: [String]
    public let popularityRank: Int
    public let isTrending: Bool

    public init(
        id: String,
        title: String,
        originalTitle: String? = nil,
        localizedTitles: [String] = [],
        kind: SeedMediaKind,
        year: Int,
        genres: [String] = [],
        actors: [String] = [],
        directors: [String] = [],
        popularityRank: Int = 999,
        isTrending: Bool = false
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.localizedTitles = localizedTitles
        self.kind = kind
        self.year = year
        self.genres = genres
        self.actors = actors
        self.directors = directors
        self.popularityRank = popularityRank
        self.isTrending = isTrending
    }
}

public protocol SearchSuggestionProviderProtocol: Sendable {
    func suggestions(query: String, recentSearches: [String]) -> [SearchSuggestion]
}

public struct LocalSearchSuggestionProvider: SearchSuggestionProviderProtocol {
    private let catalogItems: [SearchSuggestionCatalogItem]
    private let quickFilters: [SearchSuggestion]

    public init(catalogItems: [SearchSuggestionCatalogItem]? = nil) {
        self.catalogItems = catalogItems ?? SearchSuggestionCatalog.defaultItems
        self.quickFilters = [
            SearchSuggestion(
                id: "quick-filter-movies",
                title: "Movies",
                subtitle: "Filter results",
                query: "",
                kind: .quickFilter,
                quickFilter: .movies
            ),
            SearchSuggestion(
                id: "quick-filter-series",
                title: "Series",
                subtitle: "Filter results",
                query: "",
                kind: .quickFilter,
                quickFilter: .series
            ),
            SearchSuggestion(
                id: "quick-filter-4k",
                title: "4K",
                subtitle: "Filter releases",
                query: "",
                kind: .quickFilter,
                quickFilter: .ultraHD
            ),
            SearchSuggestion(
                id: "quick-filter-russian-audio",
                title: "Russian audio",
                subtitle: "Filter releases",
                query: "",
                kind: .quickFilter,
                quickFilter: .russianAudio
            )
        ]
    }

    public func suggestions(query: String, recentSearches: [String]) -> [SearchSuggestion] {
        let normalizedQuery = SearchTextMatcher.normalize(query)
        var suggestions: [SearchSuggestion] = []

        suggestions.append(contentsOf: recentSearchSuggestions(query: normalizedQuery, recentSearches: recentSearches))

        if normalizedQuery.isEmpty {
            suggestions.append(contentsOf: trendingSuggestions())
        } else {
            suggestions.append(contentsOf: catalogSuggestions(query: normalizedQuery))
        }

        suggestions.append(contentsOf: quickFilters)
        return uniqueSuggestions(suggestions)
    }

    private func recentSearchSuggestions(query: String, recentSearches: [String]) -> [SearchSuggestion] {
        recentSearches
            .filter { query.isEmpty || SearchTextMatcher.matches(query, in: $0) }
            .prefix(5)
            .map { value in
                SearchSuggestion(
                    id: "recent-\(SearchTextMatcher.normalize(value))",
                    title: value,
                    subtitle: "Recent search",
                    query: value,
                    kind: .recent
                )
            }
    }

    private func trendingSuggestions() -> [SearchSuggestion] {
        catalogItems
            .filter(\.isTrending)
            .sorted { lhs, rhs in lhs.popularityRank < rhs.popularityRank }
            .prefix(6)
            .map { item in
                SearchSuggestion(
                    id: "trending-\(item.id)",
                    title: item.title,
                    subtitle: "Trending \(item.kind == .series ? "series" : "movie")",
                    query: item.title,
                    kind: .trending
                )
            }
    }

    private func catalogSuggestions(query: String) -> [SearchSuggestion] {
        var suggestions: [SearchSuggestion] = []
        var genreSuggestions: [SearchSuggestion] = []
        var yearSuggestions: [SearchSuggestion] = []
        var typoSuggestions: [SearchSuggestion] = []

        for item in catalogItems.sorted(by: { $0.popularityRank < $1.popularityRank }) {
            appendCatalogSuggestion(
                for: item,
                query: query,
                suggestions: &suggestions,
                typoSuggestions: &typoSuggestions
            )

            for genre in item.genres where SearchTextMatcher.matches(query, in: genre) {
                genreSuggestions.append(SearchSuggestion(
                    id: "genre-\(SearchTextMatcher.normalize(genre))",
                    title: genre,
                    subtitle: "Genre",
                    query: genre,
                    kind: .genre
                ))
            }

            let year = String(item.year)
            if SearchTextMatcher.matches(query, in: year) {
                yearSuggestions.append(SearchSuggestion(
                    id: "year-\(year)",
                    title: year,
                    subtitle: "Year",
                    query: year,
                    kind: .year
                ))
            }
        }

        suggestions.append(contentsOf: genreSuggestions)
        suggestions.append(contentsOf: yearSuggestions)
        suggestions.append(contentsOf: typoSuggestions)
        return Array(uniqueSuggestions(suggestions).prefix(10))
    }

    private func appendCatalogSuggestion(
        for item: SearchSuggestionCatalogItem,
        query: String,
        suggestions: inout [SearchSuggestion],
        typoSuggestions: inout [SearchSuggestion]
    ) {
        if SearchTextMatcher.matches(query, in: item.title) {
            suggestions.append(item.suggestion(kind: .title, subtitle: "Title"))
            return
        }

        if let originalTitle = item.originalTitle, SearchTextMatcher.matches(query, in: originalTitle) {
            suggestions.append(item.suggestion(kind: .originalTitle, subtitle: "Original title"))
            return
        }

        if item.localizedTitles.contains(where: { SearchTextMatcher.matches(query, in: $0) }) {
            suggestions.append(item.suggestion(kind: .localizedTitle, subtitle: "Localized title"))
            return
        }

        if item.actors.contains(where: { SearchTextMatcher.matches(query, in: $0) }) {
            suggestions.append(item.suggestion(kind: .actor, subtitle: "Actor"))
            return
        }

        if item.directors.contains(where: { SearchTextMatcher.matches(query, in: $0) }) {
            suggestions.append(item.suggestion(kind: .director, subtitle: "Director"))
            return
        }

        if SearchTextMatcher.isTypoTolerantMatch(query, candidate: item.title) ||
            item.localizedTitles.contains(where: { SearchTextMatcher.isTypoTolerantMatch(query, candidate: $0) }) {
            typoSuggestions.append(item.suggestion(kind: .typoCorrection, subtitle: "Did you mean"))
        }
    }

    private func uniqueSuggestions(_ suggestions: [SearchSuggestion]) -> [SearchSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { suggestion in
            let key = "\(suggestion.kind.rawValue)-\(suggestion.query)-\(suggestion.quickFilter?.rawValue ?? "")"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

private enum SearchSuggestionCatalog {
    static let defaultItems: [SearchSuggestionCatalogItem] = HomeSeedLibrary.developmentItems.map { item in
        SearchSuggestionCatalogItem(
            id: item.id,
            title: item.title,
            originalTitle: originalTitle(for: item.title),
            localizedTitles: localizedTitles(for: item.title),
            kind: item.kind,
            year: item.year,
            genres: [item.genre],
            actors: actors(for: item.title),
            directors: directors(for: item.title),
            popularityRank: item.popularityRank,
            isTrending: item.popularityRank <= 8 || item.isRecentlyAdded
        )
    }

    private static func originalTitle(for title: String) -> String? {
        switch title {
        case "The Matrix":
            return "The Matrix"
        case "Dune: Part Two":
            return "Dune Part Two"
        case "Dune: Prophecy":
            return "Dune Prophecy"
        case "The Dark Knight":
            return "The Dark Knight"
        case "Game of Thrones":
            return "Game of Thrones"
        default:
            return title
        }
    }

    private static func localizedTitles(for title: String) -> [String] {
        switch title {
        case "The Matrix":
            return ["Матрица"]
        case "Dune: Part Two":
            return ["Дюна: Часть вторая", "Дюна"]
        case "Dune: Prophecy":
            return ["Дюна: Пророчество"]
        case "The Dark Knight":
            return ["Темный рыцарь"]
        case "Game of Thrones":
            return ["Игра престолов"]
        case "Inception":
            return ["Начало"]
        case "Interstellar":
            return ["Интерстеллар"]
        case "Arrival":
            return ["Прибытие"]
        default:
            return []
        }
    }

    private static func actors(for title: String) -> [String] {
        switch title {
        case "The Matrix":
            return ["Keanu Reeves", "Carrie-Anne Moss", "Laurence Fishburne"]
        case "Dune: Part Two":
            return ["Timothee Chalamet", "Zendaya", "Rebecca Ferguson"]
        case "The Dark Knight":
            return ["Christian Bale", "Heath Ledger"]
        case "Inception":
            return ["Leonardo DiCaprio", "Joseph Gordon-Levitt"]
        case "Interstellar":
            return ["Matthew McConaughey", "Anne Hathaway"]
        default:
            return []
        }
    }

    private static func directors(for title: String) -> [String] {
        switch title {
        case "The Matrix":
            return ["Lana Wachowski", "Lilly Wachowski", "Wachowski"]
        case "Dune: Part Two", "Arrival":
            return ["Denis Villeneuve"]
        case "The Dark Knight", "Inception", "Interstellar":
            return ["Christopher Nolan"]
        default:
            return []
        }
    }
}

private extension SearchSuggestionCatalogItem {
    func suggestion(kind: SearchSuggestionKind, subtitle: String) -> SearchSuggestion {
        SearchSuggestion(
            id: "\(kind.rawValue)-\(id)",
            title: title,
            subtitle: subtitle,
            query: title,
            kind: kind
        )
    }
}

private enum SearchTextMatcher {
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ query: String, in candidate: String) -> Bool {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        let normalizedCandidate = normalize(candidate)
        return normalizedCandidate.contains(normalizedQuery)
    }

    static func isTypoTolerantMatch(_ query: String, candidate: String) -> Bool {
        let normalizedQuery = normalize(query)
        guard normalizedQuery.count >= 4 else { return false }
        let candidateTokens = normalize(candidate).split(separator: " ").map(String.init)
        guard !candidateTokens.isEmpty else { return false }

        return candidateTokens.contains { token in
            guard abs(token.count - normalizedQuery.count) <= 2 else { return false }
            let distance = levenshtein(normalizedQuery, token)
            return distance <= max(1, min(2, normalizedQuery.count / 4))
        }
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let cost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + cost
                )
            }
            previous = current
        }

        return previous[right.count]
    }
}

public struct SearchMediaResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: SeedMediaKind
    public let year: Int
    public let metadata: String
    public let overview: String
    public let quality: String
    public let artworkURL: URL?
    public let ratingScore: Double?

    public init(item: HomeSeedItem) {
        self.id = item.id
        self.title = item.title
        self.kind = item.kind
        self.year = item.year
        self.metadata = "\(item.year) · \(item.rating) · \(item.runtime) · \(item.genre)"
        self.overview = item.overview
        self.quality = item.quality
        self.artworkURL = item.artworkURL
        self.ratingScore = RatingAggregator.parseRating(item.rating)
    }

    public init(mediaItem: MediaItem) {
        self.id = mediaItem.id
        self.title = mediaItem.displayTitle
        self.kind = mediaItem.kind == .series ? .series : .movie
        self.year = mediaItem.metadata?.year ?? mediaItem.releaseYear ?? 0
        self.overview = mediaItem.metadata?.overview ?? mediaItem.overview
        self.quality = mediaItem.kind == .series ? "Series" : "Movie"
        self.artworkURL = mediaItem.bestPosterURL
        self.ratingScore = mediaItem.metadata?.rating

        let genres = mediaItem.metadata?.genres.prefix(2).joined(separator: ", ")
        let ratingLabel = mediaItem.id.hasPrefix("imdb:") ? "IMDb" : "TMDB"
        let rating = mediaItem.metadata?.rating.map { String(format: "\(ratingLabel) %.1f", $0) }
        self.metadata = [
            year > 0 ? String(year) : nil,
            genres?.isEmpty == false ? genres : nil,
            rating
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

public struct SearchTorrentRelease: Identifiable, Equatable, Sendable {
    public let id: String
    public let mediaID: String
    public let mediaTitle: String
    public let mediaKind: SeedMediaKind
    public let mediaYear: Int
    public let title: String
    public let source: String
    public let magnetURI: String?
    public let torrentFileURL: URL?
    public let quality: ReleaseQuality
    public let codec: VideoCodec
    public let hdrFormat: HDRFormat
    public let isHDR: Bool
    public let seeders: Int
    public let leechers: Int
    public let sizeBytes: Int64
    public let uploadDate: Date
    public let audioLanguages: [String]
    public let subtitleLanguages: [String]
    public let availability: Double?
    public var rankingScore: Double = 0
    public var rankingReasons: [ReleaseRankingReason] = []

    public init(
        id: String,
        mediaID: String,
        mediaTitle: String,
        mediaKind: SeedMediaKind,
        mediaYear: Int,
        title: String,
        source: String,
        magnetURI: String? = nil,
        torrentFileURL: URL? = nil,
        quality: ReleaseQuality,
        codec: VideoCodec = .unknown,
        hdrFormat: HDRFormat? = nil,
        isHDR: Bool,
        seeders: Int,
        leechers: Int,
        sizeBytes: Int64,
        uploadDate: Date,
        audioLanguages: [String],
        subtitleLanguages: [String],
        availability: Double? = nil,
        rankingScore: Double = 0,
        rankingReasons: [ReleaseRankingReason] = []
    ) {
        self.id = id
        self.mediaID = mediaID
        self.mediaTitle = mediaTitle
        self.mediaKind = mediaKind
        self.mediaYear = mediaYear
        self.title = title
        self.source = source
        self.magnetURI = magnetURI
        self.torrentFileURL = torrentFileURL
        self.quality = quality
        self.codec = codec
        self.hdrFormat = hdrFormat ?? (isHDR ? .hdr10 : .none)
        self.isHDR = isHDR
        self.seeders = seeders
        self.leechers = leechers
        self.sizeBytes = sizeBytes
        self.uploadDate = uploadDate
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        self.availability = availability
        self.rankingScore = rankingScore
        self.rankingReasons = rankingReasons
    }

    public var qualityLabel: String {
        switch hdrFormat {
        case .dolbyVision:
            "\(quality.qualityLabel) Dolby Vision"
        case .hdr10:
            "\(quality.qualityLabel) HDR"
        case .none, .unknown:
            quality.qualityLabel
        }
    }

    public var codecLabel: String {
        codec.rawValue
    }

    public var hdrLabel: String {
        switch hdrFormat {
        case .dolbyVision:
            "Dolby Vision"
        case .hdr10:
            "HDR10"
        case .none:
            "SDR"
        case .unknown:
            "HDR unknown"
        }
    }

    public var sizeLabel: String {
        let release = TorrentRelease(
            id: id,
            title: title,
            quality: quality,
            seeders: seeders,
            sizeBytes: sizeBytes
        )
        return release.humanReadableSize
    }

    public var rankingExplanation: String {
        rankingReasons.map(\.explanation).joined(separator: "\n")
    }

    public var comparisonSummary: String {
        [
            qualityLabel,
            codec != .unknown ? codecLabel : nil,
            "\(seeders) seeders",
            sizeLabel,
            source,
            audioLanguages.isEmpty ? nil : "Audio: \(audioLanguages.joined(separator: ", "))",
            subtitleLanguages.isEmpty ? nil : "Subs: \(subtitleLanguages.joined(separator: ", "))"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    public var releaseHealth: ReleaseHealth {
        torrentRelease.releaseHealth
    }

    public var releaseHealthLabel: String {
        releaseHealth.label
    }

    public var torrentRelease: TorrentRelease {
        TorrentRelease(
            id: id,
            sourceId: source.lowercased(),
            sourceName: source,
            title: title,
            magnetURI: magnetURI,
            torrentFileURL: torrentFileURL,
            quality: quality,
            codec: codec,
            hdr: hdrFormat,
            audioLanguages: audioLanguages,
            subtitleLanguages: subtitleLanguages,
            seeders: seeders,
            leechers: leechers,
            sizeBytes: sizeBytes,
            uploadDate: uploadDate,
            availability: availability,
            rankScore: rankingScore
        )
    }
}

public struct SearchResults: Equatable, Sendable {
    public var topMatches: [SearchMediaResult] = []
    public var movies: [SearchMediaResult] = []
    public var series: [SearchMediaResult] = []
    public var torrentReleases: [SearchTorrentRelease] = []

    public init(
        topMatches: [SearchMediaResult] = [],
        movies: [SearchMediaResult] = [],
        series: [SearchMediaResult] = [],
        torrentReleases: [SearchTorrentRelease] = []
    ) {
        self.topMatches = topMatches
        self.movies = movies
        self.series = series
        self.torrentReleases = torrentReleases
    }

    public var isEmpty: Bool {
        topMatches.isEmpty && movies.isEmpty && series.isEmpty && torrentReleases.isEmpty
    }
}

public struct SearchProviderResponse: Equatable, Sendable {
    public let media: [SearchMediaResult]
    public let releases: [SearchTorrentRelease]

    public init(media: [SearchMediaResult], releases: [SearchTorrentRelease]) {
        self.media = media
        self.releases = releases
    }

    public var isEmpty: Bool {
        media.isEmpty && releases.isEmpty
    }
}

public protocol SearchProviderProtocol: Sendable {
    func search(query: String) async throws -> SearchProviderResponse
}

public enum SearchProviderError: LocalizedError, Equatable {
    case mockFailure

    public var errorDescription: String? {
        switch self {
        case .mockFailure:
            "Mock search provider failed."
        }
    }
}

extension SearchProviderError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        CineFlowError(
            category: .metadata,
            technicalDescription: errorDescription ?? String(describing: self),
            userMessage: "Search is temporarily unavailable.",
            recoverySuggestion: "Try again in a moment.",
            logLevel: .warning
        )
    }
}

public struct MockSearchProvider: SearchProviderProtocol {
    private let shouldFail: Bool

    public init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    public func search(query: String) async throws -> SearchProviderResponse {
        if shouldFail {
            throw SearchProviderError.mockFailure
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return SearchProviderResponse(media: [], releases: [])
        }

        let media = HomeSeedLibrary.developmentItems
            .filter { item in
                Self.searchableText(for: item).contains { SearchTextMatcher.matches(normalizedQuery, in: $0) } ||
                    Self.searchableText(for: item).contains { SearchTextMatcher.isTypoTolerantMatch(normalizedQuery, candidate: $0) }
            }
            .map(SearchMediaResult.init(item:))

        let releases = Self.releases.filter { release in
            SearchTextMatcher.matches(normalizedQuery, in: release.title) ||
                SearchTextMatcher.matches(normalizedQuery, in: release.mediaTitle) ||
                SearchTextMatcher.isTypoTolerantMatch(normalizedQuery, candidate: release.mediaTitle)
        }

        return SearchProviderResponse(media: media, releases: releases)
    }

    private static var releases: [SearchTorrentRelease] {
        [
            release(
                id: "matrix-2160p-hdr-remux",
                mediaID: "tmdb:movie:603",
                mediaTitle: "The Matrix",
                mediaKind: .movie,
                mediaYear: 1999,
                title: "The Matrix 2160p HDR REMUX",
                source: "Archive",
                quality: .ultraHD,
                codec: .hevc,
                hdrFormat: .dolbyVision,
                isHDR: true,
                seeders: 92,
                leechers: 12,
                sizeGB: 78.4,
                daysAgo: 14,
                audio: ["en", "ru"],
                subtitles: ["en", "ru"]
            ),
            release(
                id: "matrix-2160p-web",
                mediaID: "tmdb:movie:603",
                mediaTitle: "The Matrix",
                mediaKind: .movie,
                mediaYear: 1999,
                title: "The Matrix 2160p WEB-DL",
                source: "CinemaHub",
                quality: .ultraHD,
                codec: .h264,
                hdrFormat: .none,
                isHDR: false,
                seeders: 410,
                leechers: 36,
                sizeGB: 24.8,
                daysAgo: 2,
                audio: ["en"],
                subtitles: ["en"]
            ),
            release(
                id: "matrix-1080p-bluray",
                mediaID: "tmdb:movie:603",
                mediaTitle: "The Matrix",
                mediaKind: .movie,
                mediaYear: 1999,
                title: "The Matrix 1080p BluRay",
                source: "CinemaHub",
                quality: .fullHD,
                codec: .h264,
                hdrFormat: .none,
                isHDR: false,
                seeders: 1_200,
                leechers: 84,
                sizeGB: 12.2,
                daysAgo: 8,
                audio: ["en", "ru"],
                subtitles: ["en", "ru", "az"]
            ),
            release(
                id: "dune-2160p-hdr",
                mediaID: "tmdb:movie:693134",
                mediaTitle: "Dune: Part Two",
                mediaKind: .movie,
                mediaYear: 2024,
                title: "Dune: Part Two 2160p HDR",
                source: "CinemaHub",
                quality: .ultraHD,
                codec: .hevc,
                hdrFormat: .hdr10,
                isHDR: true,
                seeders: 860,
                leechers: 91,
                sizeGB: 31.6,
                daysAgo: 3,
                audio: ["en", "ru"],
                subtitles: ["en", "ru"]
            ),
            release(
                id: "dune-2160p",
                mediaID: "tmdb:movie:693134",
                mediaTitle: "Dune: Part Two",
                mediaKind: .movie,
                mediaYear: 2024,
                title: "Dune: Part Two 2160p",
                source: "Archive",
                quality: .ultraHD,
                codec: .h265,
                hdrFormat: .none,
                isHDR: false,
                seeders: 940,
                leechers: 104,
                sizeGB: 27.1,
                daysAgo: 5,
                audio: ["en"],
                subtitles: ["en", "az"]
            ),
            release(
                id: "dune-1080p",
                mediaID: "tmdb:movie:693134",
                mediaTitle: "Dune: Part Two",
                mediaKind: .movie,
                mediaYear: 2024,
                title: "Dune: Part Two 1080p",
                source: "SceneVault",
                quality: .fullHD,
                codec: .h264,
                hdrFormat: .none,
                isHDR: false,
                seeders: 1_500,
                leechers: 210,
                sizeGB: 13.4,
                daysAgo: 1,
                audio: ["en", "ru"],
                subtitles: ["ru"]
            ),
            release(
                id: "arrival-2160p-hdr",
                mediaID: "tmdb:movie:329865",
                mediaTitle: "Arrival",
                mediaKind: .movie,
                mediaYear: 2016,
                title: "Arrival 2160p HDR",
                source: "Archive",
                quality: .ultraHD,
                codec: .hevc,
                hdrFormat: .hdr10,
                isHDR: true,
                seeders: 304,
                leechers: 20,
                sizeGB: 22.6,
                daysAgo: 6,
                audio: ["en", "ru"],
                subtitles: ["en", "ru"]
            )
        ]
    }

    private static func searchableText(for item: HomeSeedItem) -> [String] {
        let catalogItem = SearchSuggestionCatalog.defaultItems.first { $0.id == item.id }
        return [
            item.title,
            item.genre,
            item.overview,
            String(item.year),
            catalogItem?.originalTitle
        ]
        .compactMap { $0 } +
            (catalogItem?.localizedTitles ?? []) +
            (catalogItem?.actors ?? []) +
            (catalogItem?.directors ?? [])
    }

    private static func release(
        id: String,
        mediaID: String,
        mediaTitle: String,
        mediaKind: SeedMediaKind,
        mediaYear: Int,
        title: String,
        source: String,
        quality: ReleaseQuality,
        codec: VideoCodec,
        hdrFormat: HDRFormat,
        isHDR: Bool,
        seeders: Int,
        leechers: Int,
        sizeGB: Double,
        daysAgo: Int,
        audio: [String],
        subtitles: [String]
    ) -> SearchTorrentRelease {
        SearchTorrentRelease(
            id: id,
            mediaID: mediaID,
            mediaTitle: mediaTitle,
            mediaKind: mediaKind,
            mediaYear: mediaYear,
            title: title,
            source: source,
            magnetURI: "magnet:?xt=urn:btih:\(id)",
            quality: quality,
            codec: codec,
            hdrFormat: hdrFormat,
            isHDR: isHDR,
            seeders: seeders,
            leechers: leechers,
            sizeBytes: Int64(sizeGB * 1_000_000_000),
            uploadDate: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date(timeIntervalSince1970: 1_800_000_000)) ?? Date(timeIntervalSince1970: 1_800_000_000),
            audioLanguages: audio,
            subtitleLanguages: subtitles
        )
    }
}

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public private(set) var queryText = ""
    @Published public private(set) var state: SearchViewState = .idle
    @Published public var filters = SearchFilters()
    @Published public private(set) var sortOption: SearchSortOption = .bestMatch
    @Published public private(set) var results = SearchResults()
    @Published public private(set) var recentSearches: [String] = []
    @Published public private(set) var searchSuggestions: [SearchSuggestion] = []
    @Published public private(set) var availableSources: [String] = []
    @Published public private(set) var availableYears: [Int] = []
    @Published public private(set) var availableAudioLanguages: [String] = []
    @Published public private(set) var availableSubtitleLanguages: [String] = []
    @Published public private(set) var availableCodecs: [VideoCodec] = []
    @Published public private(set) var lastError: CineFlowError?
    public let moodFilters: [MoodDiscoveryFilter] = MoodDiscoveryFilter.homeFilters

    private let provider: any SearchProviderProtocol
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let settingsRepository: (any SettingsRepositoryProtocol)?
    private let preferencesStore: any SearchPreferencesStoreProtocol
    private let suggestionsProvider: any SearchSuggestionProviderProtocol
    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?
    private var lastResponse = SearchProviderResponse(media: [], releases: [])
    private var searchGeneration = 0
    private var globalRankingPreferences = RankingPreferences(supportsHDR: true)

    public init(
        provider: any SearchProviderProtocol = MockSearchProvider(),
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        debounceNanoseconds: UInt64 = 350_000_000,
        preferencesStore: any SearchPreferencesStoreProtocol = UserDefaultsSearchPreferencesStore(),
        suggestionsProvider: any SearchSuggestionProviderProtocol = LocalSearchSuggestionProvider()
    ) {
        self.provider = provider
        self.diagnosticsService = diagnosticsService
        self.settingsRepository = settingsRepository
        self.debounceNanoseconds = debounceNanoseconds
        self.preferencesStore = preferencesStore
        self.suggestionsProvider = suggestionsProvider
        self.recentSearches = preferencesStore.recentSearches
        self.sortOption = preferencesStore.sortOption
        self.searchSuggestions = suggestionsProvider.suggestions(query: "", recentSearches: recentSearches)
    }

    deinit {
        debounceTask?.cancel()
    }

    public func updateQuery(_ query: String) {
        queryText = query
        refreshSuggestions(for: query)
        debounceTask?.cancel()
        let generation = nextSearchGeneration()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            results = SearchResults()
            lastResponse = SearchProviderResponse(media: [], releases: [])
            lastError = nil
            refreshSuggestions(for: "")
            return
        }

        state = .loading
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.searchNow(query: query, generation: generation)
        }
    }

    public func searchNow(query: String) async {
        let generation = nextSearchGeneration()
        await searchNow(query: query, generation: generation)
    }

    private func searchNow(query: String, generation: Int) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        queryText = normalizedQuery

        guard !normalizedQuery.isEmpty else {
            guard generation == searchGeneration else { return }
            state = .idle
            results = SearchResults()
            lastResponse = SearchProviderResponse(media: [], releases: [])
            lastError = nil
            return
        }

        state = .loading

        do {
            await refreshGlobalRankingPreferences()
            let response = try await provider.search(query: normalizedQuery)
            let filters = filters
            let sortOption = sortOption
            let rankingPreferences = globalRankingPreferences
            let preparedResults = await Task.detached(priority: .userInitiated) {
                SearchResultsBuilder.build(
                    response: response,
                    filters: filters,
                    sortOption: sortOption,
                    rankingPreferences: rankingPreferences
                )
            }.value
            guard generation == searchGeneration, !Task.isCancelled else { return }
            lastResponse = response
            lastError = nil
            rememberSearch(normalizedQuery)
            refreshSuggestions(for: normalizedQuery)
            updateAvailableFilterOptions(from: response)
            results = preparedResults
            state = results.isEmpty ? .empty : .loaded
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .metadata)
            results = SearchResults()
            lastError = cineFlowError
            state = .failed(cineFlowError.userMessage)
            await diagnosticsService?.log(cineFlowError, operation: "search", metadata: ["query": normalizedQuery])
        }
    }

    public func retryLastSearch() async {
        await searchNow(query: queryText)
    }

    public func runRecentSearch(_ query: String) async {
        await searchNow(query: query)
    }

    public func clearQuery() {
        debounceTask?.cancel()
        _ = nextSearchGeneration()
        queryText = ""
        state = .idle
        results = SearchResults()
        lastResponse = SearchProviderResponse(media: [], releases: [])
        lastError = nil
        refreshSuggestions(for: "")
    }

    public func clearRecentSearches() {
        recentSearches = []
        preferencesStore.recentSearches = []
        refreshSuggestions(for: queryText)
    }

    public func selectSuggestion(_ suggestion: SearchSuggestion) async {
        if let quickFilter = suggestion.quickFilter {
            applyQuickFilter(quickFilter)
            refreshSuggestions(for: queryText)
            return
        }

        await searchNow(query: suggestion.query)
    }

    public func applyMoodFilter(_ filter: MoodDiscoveryFilter) async {
        debounceTask?.cancel()
        filters = SearchFilters()

        switch filter {
        case .shortMovie, .under90Minutes:
            filters.mediaType = .movies
        case .backgroundSeries:
            filters.mediaType = .series
        case .highRated:
            filters.minimumRating = 8.0
        case .fourKHDR:
            filters.qualities.insert(.ultraHD)
            filters.requiresHDR = true
        case .lightEvening, .epic, .new, .drama, .action, .comedy, .runtime30To60, .longWeekendPicks:
            break
        }

        await searchNow(query: filter.searchQuery)
    }

    private func nextSearchGeneration() -> Int {
        searchGeneration += 1
        return searchGeneration
    }

    public func setSortOption(_ option: SearchSortOption) {
        sortOption = option
        preferencesStore.sortOption = option
        applyCurrentFiltersAndSort()
    }

    public func refreshWithCurrentFilters() {
        applyCurrentFiltersAndSort()
    }

    private func applyCurrentFiltersAndSort() {
        let media = sortMedia(filteredMedia(lastResponse.media))
        let releases = sort(filteredReleases(lastResponse.releases))

        results = SearchResults(
            topMatches: Array(media.prefix(1)),
            movies: media.filter { $0.kind == .movie },
            series: media.filter { $0.kind == .series },
            torrentReleases: releases
        )
        state = results.isEmpty ? .empty : .loaded
    }

    private func refreshGlobalRankingPreferences() async {
        guard let settingsRepository else {
            globalRankingPreferences = RankingPreferences(supportsHDR: true)
            return
        }

        let settings = await settingsRepository.appSettings
        let subtitleLanguages = await settingsRepository.subtitleLanguagePriority
        globalRankingPreferences = settings.playback.rankingPreferences(
            preferredSubtitleLanguages: subtitleLanguages,
            supportsHDR: true
        )
    }

    private func updateAvailableFilterOptions(from response: SearchProviderResponse) {
        availableSources = Array(Set(response.releases.map(\.source))).sorted()
        availableYears = Array(Set(response.media.map(\.year) + response.releases.map(\.mediaYear))).sorted(by: >)
        availableAudioLanguages = Array(Set(response.releases.flatMap(\.audioLanguages))).sorted()
        availableSubtitleLanguages = Array(Set(response.releases.flatMap(\.subtitleLanguages))).sorted()
        availableCodecs = Array(Set(response.releases.map(\.codec).filter { $0 != .unknown })).sorted { $0.rawValue < $1.rawValue }
    }

    private func filteredMedia(_ media: [SearchMediaResult]) -> [SearchMediaResult] {
        media.filter { item in
            switch filters.mediaType {
            case .all:
                break
            case .movies where item.kind != .movie:
                return false
            case .series where item.kind != .series:
                return false
            default:
                break
            }

            if let year = filters.year, item.year != year {
                return false
            }
            if let minimumRating = filters.minimumRating, (item.ratingScore ?? 0) < minimumRating {
                return false
            }

            return true
        }
    }

    private func filteredReleases(_ releases: [SearchTorrentRelease]) -> [SearchTorrentRelease] {
        releases.filter { release in
            switch filters.mediaType {
            case .all:
                break
            case .movies where release.mediaKind != .movie:
                return false
            case .series where release.mediaKind != .series:
                return false
            default:
                break
            }

            if !filters.qualities.isEmpty, !filters.qualities.contains(release.quality) {
                return false
            }
            if filters.requiresHDR, !release.isHDR {
                return false
            }
            if let source = filters.source, !source.isEmpty, release.source != source {
                return false
            }
            if let year = filters.year, release.mediaYear != year {
                return false
            }
            if let audioLanguage = filters.audioLanguage, !audioLanguage.isEmpty, !release.audioLanguages.contains(audioLanguage) {
                return false
            }
            if let subtitleLanguage = filters.subtitleLanguage, !subtitleLanguage.isEmpty, !release.subtitleLanguages.contains(subtitleLanguage) {
                return false
            }
            if let minimumSizeBytes = filters.minimumSizeBytes, release.sizeBytes < minimumSizeBytes {
                return false
            }
            if let maximumSizeBytes = filters.maximumSizeBytes, release.sizeBytes > maximumSizeBytes {
                return false
            }
            if let codec = filters.codec, release.codec != codec {
                return false
            }

            return true
        }
    }

    private func sortMedia(_ media: [SearchMediaResult]) -> [SearchMediaResult] {
        guard sortOption == .rating else { return media }
        return media.sorted { lhs, rhs in
            let lhsRating = lhs.ratingScore ?? -1
            let rhsRating = rhs.ratingScore ?? -1
            if lhsRating == rhsRating {
                return lhs.title < rhs.title
            }
            return lhsRating > rhsRating
        }
    }

    private func sort(_ releases: [SearchTorrentRelease]) -> [SearchTorrentRelease] {
        if sortOption == .bestMatch {
            let ranked = ReleaseRankingEngine(preferences: searchRankingPreferences)
                .rank(releases.map(\.torrentRelease))
            let byID = Dictionary(uniqueKeysWithValues: releases.map { ($0.id, $0) })

            return ranked.compactMap { rankedRelease in
                guard var release = byID[rankedRelease.release.id] else { return nil }
                release.rankingScore = rankedRelease.score
                release.rankingReasons = rankedRelease.reasons
                return release
            }
        }

        return releases.sorted { lhs, rhs in
            switch sortOption {
            case .bestMatch:
                return lhs.id < rhs.id
            case .bestQuality:
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                if lhs.hdrFormat != rhs.hdrFormat {
                    return hdrSortValue(lhs.hdrFormat) > hdrSortValue(rhs.hdrFormat)
                }
                return lhs.seeders > rhs.seeders
            case .mostSeeders:
                return lhs.seeders > rhs.seeders
            case .smallestSize:
                return lhs.sizeBytes < rhs.sizeBytes
            case .newest:
                return lhs.uploadDate > rhs.uploadDate
            case .preferredLanguage:
                return preferredLanguageSort(lhs, rhs)
            case .rating:
                return lhs.id < rhs.id
            }
        }
    }

    private func rememberSearch(_ query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var searches = recentSearches.filter { $0.caseInsensitiveCompare(normalized) != .orderedSame }
        searches.insert(normalized, at: 0)
        recentSearches = Array(searches.prefix(10))
        preferencesStore.recentSearches = recentSearches
    }

    private func refreshSuggestions(for query: String) {
        searchSuggestions = suggestionsProvider.suggestions(query: query, recentSearches: recentSearches)
    }

    private func applyQuickFilter(_ quickFilter: SearchQuickFilter) {
        switch quickFilter {
        case .movies:
            filters.mediaType = .movies
        case .series:
            filters.mediaType = .series
        case .ultraHD:
            filters.qualities.insert(.ultraHD)
        case .russianAudio:
            filters.audioLanguage = "ru"
        }

        if !lastResponse.isEmpty {
            applyCurrentFiltersAndSort()
        }
    }

    private func preferredLanguageSort(_ lhs: SearchTorrentRelease, _ rhs: SearchTorrentRelease) -> Bool {
        let lhsScore = preferredLanguageScore(lhs)
        let rhsScore = preferredLanguageScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        if lhs.seeders != rhs.seeders {
            return lhs.seeders > rhs.seeders
        }
        if lhs.quality != rhs.quality {
            return lhs.quality > rhs.quality
        }
        return lhs.uploadDate > rhs.uploadDate
    }

    private func preferredLanguageScore(_ release: SearchTorrentRelease) -> Int {
        let audioPreferences = filters.audioLanguage.map { [$0] } ?? globalRankingPreferences.preferredAudioLanguages
        let subtitlePreferences = filters.subtitleLanguage.map { [$0] } ?? globalRankingPreferences.preferredSubtitleLanguages
        let audioScore = audioPreferences.contains { language in
            release.audioLanguages.contains { $0.caseInsensitiveCompare(language) == .orderedSame }
        } ? 2 : 0
        let subtitleScore = subtitlePreferences.contains { language in
            release.subtitleLanguages.contains { $0.caseInsensitiveCompare(language) == .orderedSame }
        } ? 1 : 0
        return audioScore + subtitleScore
    }

    private func hdrSortValue(_ hdr: HDRFormat) -> Int {
        SearchReleaseSortHelpers.hdrSortValue(hdr)
    }

    private var searchRankingPreferences: RankingPreferences {
        RankingPreferences(
            preferredAudioLanguages: filters.audioLanguage.map { [$0] } ?? globalRankingPreferences.preferredAudioLanguages,
            preferredSubtitleLanguages: filters.subtitleLanguage.map { [$0] } ?? globalRankingPreferences.preferredSubtitleLanguages,
            supportsHDR: globalRankingPreferences.supportsHDR,
            preferredQuality: globalRankingPreferences.preferredQuality,
            hdrPreference: filters.requiresHDR ? .preferHDR : globalRankingPreferences.hdrPreference,
            codecPreference: globalRankingPreferences.codecPreference,
            maxFileSizeBytes: globalRankingPreferences.maxFileSizeBytes,
            preferHighSeedersOverHighestQuality: globalRankingPreferences.preferHighSeedersOverHighestQuality
        )
    }
}

private enum SearchReleaseSortHelpers {
    static func hdrSortValue(_ hdr: HDRFormat) -> Int {
        switch hdr {
        case .dolbyVision:
            return 3
        case .hdr10:
            return 2
        case .unknown:
            return 1
        case .none:
            return 0
        }
    }
}

private enum SearchResultsBuilder {
    static func build(
        response: SearchProviderResponse,
        filters: SearchFilters,
        sortOption: SearchSortOption,
        rankingPreferences: RankingPreferences = RankingPreferences(supportsHDR: true)
    ) -> SearchResults {
        let media = sortMedia(filteredMedia(response.media, filters: filters), sortOption: sortOption)
        let releases = sort(
            filteredReleases(response.releases, filters: filters),
            filters: filters,
            sortOption: sortOption,
            rankingPreferences: rankingPreferences
        )

        return SearchResults(
            topMatches: Array(media.prefix(1)),
            movies: media.filter { $0.kind == .movie },
            series: media.filter { $0.kind == .series },
            torrentReleases: releases
        )
    }

    private static func filteredMedia(_ media: [SearchMediaResult], filters: SearchFilters) -> [SearchMediaResult] {
        media.filter { item in
            switch filters.mediaType {
            case .all:
                break
            case .movies where item.kind != .movie:
                return false
            case .series where item.kind != .series:
                return false
            default:
                break
            }

            if let year = filters.year, item.year != year {
                return false
            }
            if let minimumRating = filters.minimumRating, (item.ratingScore ?? 0) < minimumRating {
                return false
            }

            return true
        }
    }

    private static func filteredReleases(_ releases: [SearchTorrentRelease], filters: SearchFilters) -> [SearchTorrentRelease] {
        releases.filter { release in
            switch filters.mediaType {
            case .all:
                break
            case .movies where release.mediaKind != .movie:
                return false
            case .series where release.mediaKind != .series:
                return false
            default:
                break
            }

            if !filters.qualities.isEmpty, !filters.qualities.contains(release.quality) {
                return false
            }
            if filters.requiresHDR, !release.isHDR {
                return false
            }
            if let source = filters.source, !source.isEmpty, release.source != source {
                return false
            }
            if let year = filters.year, release.mediaYear != year {
                return false
            }
            if let audioLanguage = filters.audioLanguage, !audioLanguage.isEmpty, !release.audioLanguages.contains(audioLanguage) {
                return false
            }
            if let subtitleLanguage = filters.subtitleLanguage, !subtitleLanguage.isEmpty, !release.subtitleLanguages.contains(subtitleLanguage) {
                return false
            }
            if let minimumSizeBytes = filters.minimumSizeBytes, release.sizeBytes < minimumSizeBytes {
                return false
            }
            if let maximumSizeBytes = filters.maximumSizeBytes, release.sizeBytes > maximumSizeBytes {
                return false
            }
            if let codec = filters.codec, release.codec != codec {
                return false
            }

            return true
        }
    }

    private static func sort(
        _ releases: [SearchTorrentRelease],
        filters: SearchFilters,
        sortOption: SearchSortOption,
        rankingPreferences: RankingPreferences
    ) -> [SearchTorrentRelease] {
        if sortOption == .bestMatch {
            let ranked = ReleaseRankingEngine(preferences: mergedRankingPreferences(filters: filters, global: rankingPreferences))
                .rank(releases.map(\.torrentRelease))
            let byID = Dictionary(uniqueKeysWithValues: releases.map { ($0.id, $0) })

            return ranked.compactMap { rankedRelease in
                guard var release = byID[rankedRelease.release.id] else { return nil }
                release.rankingScore = rankedRelease.score
                release.rankingReasons = rankedRelease.reasons
                return release
            }
        }

        return releases.sorted { lhs, rhs in
            switch sortOption {
            case .bestMatch:
                return lhs.id < rhs.id
            case .bestQuality:
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                if lhs.hdrFormat != rhs.hdrFormat {
                    return SearchReleaseSortHelpers.hdrSortValue(lhs.hdrFormat) > SearchReleaseSortHelpers.hdrSortValue(rhs.hdrFormat)
                }
                return lhs.seeders > rhs.seeders
            case .mostSeeders:
                return lhs.seeders > rhs.seeders
            case .smallestSize:
                return lhs.sizeBytes < rhs.sizeBytes
            case .newest:
                return lhs.uploadDate > rhs.uploadDate
            case .preferredLanguage:
                let lhsScore = preferredLanguageScore(lhs, filters: filters, global: rankingPreferences)
                let rhsScore = preferredLanguageScore(rhs, filters: filters, global: rankingPreferences)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                if lhs.seeders != rhs.seeders {
                    return lhs.seeders > rhs.seeders
                }
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                return lhs.uploadDate > rhs.uploadDate
            case .rating:
                return lhs.id < rhs.id
            }
        }
    }

    private static func sortMedia(_ media: [SearchMediaResult], sortOption: SearchSortOption) -> [SearchMediaResult] {
        guard sortOption == .rating else { return media }
        return media.sorted { lhs, rhs in
            let lhsRating = lhs.ratingScore ?? -1
            let rhsRating = rhs.ratingScore ?? -1
            if lhsRating == rhsRating {
                return lhs.title < rhs.title
            }
            return lhsRating > rhsRating
        }
    }

    private static func preferredLanguageScore(
        _ release: SearchTorrentRelease,
        filters: SearchFilters,
        global: RankingPreferences
    ) -> Int {
        let audioPreferences = filters.audioLanguage.map { [$0] } ?? global.preferredAudioLanguages
        let subtitlePreferences = filters.subtitleLanguage.map { [$0] } ?? global.preferredSubtitleLanguages
        let audioScore = audioPreferences.contains { language in
            release.audioLanguages.contains { $0.caseInsensitiveCompare(language) == .orderedSame }
        } ? 2 : 0
        let subtitleScore = subtitlePreferences.contains { language in
            release.subtitleLanguages.contains { $0.caseInsensitiveCompare(language) == .orderedSame }
        } ? 1 : 0
        return audioScore + subtitleScore
    }

    private static func mergedRankingPreferences(filters: SearchFilters, global: RankingPreferences) -> RankingPreferences {
        RankingPreferences(
            preferredAudioLanguages: filters.audioLanguage.map { [$0] } ?? global.preferredAudioLanguages,
            preferredSubtitleLanguages: filters.subtitleLanguage.map { [$0] } ?? global.preferredSubtitleLanguages,
            supportsHDR: global.supportsHDR,
            preferredQuality: global.preferredQuality,
            hdrPreference: filters.requiresHDR ? .preferHDR : global.hdrPreference,
            codecPreference: global.codecPreference,
            maxFileSizeBytes: global.maxFileSizeBytes,
            preferHighSeedersOverHighestQuality: global.preferHighSeedersOverHighestQuality
        )
    }
}
