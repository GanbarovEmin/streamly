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
    case best
    case seeders
    case quality
    case size
    case date

    public var id: String { rawValue }
}

public struct SearchFilters: Equatable, Sendable {
    public var mediaType: SearchMediaType = .all
    public var qualities: Set<ReleaseQuality> = []
    public var requiresHDR = false
    public var source: String?
    public var year: Int?
    public var audioLanguage: String?
    public var subtitleLanguage: String?

    public init() {}

    public var hasActiveFilters: Bool {
        mediaType != .all ||
            !qualities.isEmpty ||
            requiresHDR ||
            source?.isEmpty == false ||
            year != nil ||
            audioLanguage?.isEmpty == false ||
            subtitleLanguage?.isEmpty == false
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

    public init(item: HomeSeedItem) {
        self.id = item.id
        self.title = item.title
        self.kind = item.kind
        self.year = item.year
        self.metadata = "\(item.year) · \(item.rating) · \(item.runtime) · \(item.genre)"
        self.overview = item.overview
        self.quality = item.quality
        self.artworkURL = item.artworkURL
    }

    public init(mediaItem: MediaItem) {
        self.id = mediaItem.id
        self.title = mediaItem.displayTitle
        self.kind = mediaItem.kind == .series ? .series : .movie
        self.year = mediaItem.metadata?.year ?? mediaItem.releaseYear ?? 0
        self.overview = mediaItem.metadata?.overview ?? mediaItem.overview
        self.quality = mediaItem.kind == .series ? "Series" : "Movie"
        self.artworkURL = mediaItem.bestPosterURL

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
        isHDR ? "\(quality.qualityLabel) HDR" : quality.qualityLabel
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
            codec: .unknown,
            hdr: isHDR ? .hdr10 : .none,
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

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return SearchProviderResponse(media: [], releases: [])
        }

        let media = HomeSeedLibrary.developmentItems
            .filter { item in
                item.title.lowercased().contains(normalizedQuery) ||
                    item.genre.lowercased().contains(normalizedQuery) ||
                    item.overview.lowercased().contains(normalizedQuery)
            }
            .map(SearchMediaResult.init(item:))

        let releases = Self.releases.filter { release in
            release.title.lowercased().contains(normalizedQuery) ||
                release.mediaTitle.lowercased().contains(normalizedQuery)
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

    private static func release(
        id: String,
        mediaID: String,
        mediaTitle: String,
        mediaKind: SeedMediaKind,
        mediaYear: Int,
        title: String,
        source: String,
        quality: ReleaseQuality,
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
    @Published public private(set) var sortOption: SearchSortOption = .best
    @Published public private(set) var results = SearchResults()
    @Published public private(set) var availableSources: [String] = []
    @Published public private(set) var availableYears: [Int] = []
    @Published public private(set) var availableAudioLanguages: [String] = []
    @Published public private(set) var availableSubtitleLanguages: [String] = []
    @Published public private(set) var lastError: CineFlowError?

    private let provider: any SearchProviderProtocol
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let settingsRepository: (any SettingsRepositoryProtocol)?
    private let debounceNanoseconds: UInt64
    private var debounceTask: Task<Void, Never>?
    private var lastResponse = SearchProviderResponse(media: [], releases: [])
    private var searchGeneration = 0
    private var globalRankingPreferences = RankingPreferences(supportsHDR: true)

    public init(
        provider: any SearchProviderProtocol = MockSearchProvider(),
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        debounceNanoseconds: UInt64 = 350_000_000
    ) {
        self.provider = provider
        self.diagnosticsService = diagnosticsService
        self.settingsRepository = settingsRepository
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit {
        debounceTask?.cancel()
    }

    public func updateQuery(_ query: String) {
        queryText = query
        debounceTask?.cancel()
        let generation = nextSearchGeneration()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            results = SearchResults()
            lastResponse = SearchProviderResponse(media: [], releases: [])
            lastError = nil
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

    private func nextSearchGeneration() -> Int {
        searchGeneration += 1
        return searchGeneration
    }

    public func setSortOption(_ option: SearchSortOption) {
        sortOption = option
        applyCurrentFiltersAndSort()
    }

    public func refreshWithCurrentFilters() {
        applyCurrentFiltersAndSort()
    }

    private func applyCurrentFiltersAndSort() {
        let media = filteredMedia(lastResponse.media)
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

            return true
        }
    }

    private func sort(_ releases: [SearchTorrentRelease]) -> [SearchTorrentRelease] {
        if sortOption == .best {
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
            case .best:
                return lhs.id < rhs.id
            case .quality:
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                if lhs.isHDR != rhs.isHDR {
                    return lhs.isHDR && !rhs.isHDR
                }
                return lhs.seeders > rhs.seeders
            case .seeders:
                return lhs.seeders > rhs.seeders
            case .size:
                return lhs.sizeBytes > rhs.sizeBytes
            case .date:
                return lhs.uploadDate > rhs.uploadDate
            }
        }
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

private enum SearchResultsBuilder {
    static func build(
        response: SearchProviderResponse,
        filters: SearchFilters,
        sortOption: SearchSortOption,
        rankingPreferences: RankingPreferences = RankingPreferences(supportsHDR: true)
    ) -> SearchResults {
        let media = filteredMedia(response.media, filters: filters)
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

            return true
        }
    }

    private static func sort(
        _ releases: [SearchTorrentRelease],
        filters: SearchFilters,
        sortOption: SearchSortOption,
        rankingPreferences: RankingPreferences
    ) -> [SearchTorrentRelease] {
        if sortOption == .best {
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
            case .best:
                return lhs.id < rhs.id
            case .quality:
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                if lhs.isHDR != rhs.isHDR {
                    return lhs.isHDR && !rhs.isHDR
                }
                return lhs.seeders > rhs.seeders
            case .seeders:
                return lhs.seeders > rhs.seeders
            case .size:
                return lhs.sizeBytes > rhs.sizeBytes
            case .date:
                return lhs.uploadDate > rhs.uploadDate
            }
        }
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
