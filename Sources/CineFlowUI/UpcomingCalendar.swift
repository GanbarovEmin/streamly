import CineFlowCore
import Foundation

public enum UpcomingCalendarWindow: String, Codable, Equatable, Sendable {
    case thisWeek
    case nextMonth

    public var label: String {
        switch self {
        case .thisWeek:
            "Coming this week"
        case .nextMonth:
            "Coming next month"
        }
    }
}

public enum UpcomingCalendarItemKind: String, Codable, Equatable, Sendable {
    case episode
    case movie
}

public struct UpcomingCalendarItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let kind: UpcomingCalendarItemKind
    public let releaseDate: Date
    public let window: UpcomingCalendarWindow
    public let posterURL: URL?
    public let seriesID: String?
    public let isStale: Bool

    public var badgeText: String {
        isStale ? "Stale · \(window.label)" : window.label
    }

    public var watchlistActionTitle: String {
        "Add to Watchlist"
    }

    var watchlistMediaID: String {
        seriesID ?? id
    }

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: UpcomingCalendarItemKind,
        releaseDate: Date,
        window: UpcomingCalendarWindow,
        posterURL: URL?,
        seriesID: String?,
        isStale: Bool
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.releaseDate = releaseDate
        self.window = window
        self.posterURL = posterURL
        self.seriesID = seriesID
        self.isStale = isStale
    }

    func withStaleState(_ stale: Bool) -> UpcomingCalendarItem {
        UpcomingCalendarItem(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            releaseDate: releaseDate,
            window: window,
            posterURL: posterURL,
            seriesID: seriesID,
            isStale: stale
        )
    }
}

public protocol UpcomingCalendarProviderProtocol {
    func upcomingItems() async -> [UpcomingCalendarItem]
    func addToWatchlist(itemID: String, libraryRepository: any LibraryRepositoryProtocol) async throws
}

public protocol UpcomingCalendarCacheStoreProtocol: Sendable {
    func cachedItems() async -> [UpcomingCalendarItem]
    func saveCachedItems(_ items: [UpcomingCalendarItem]) async
}

public actor UserDefaultsUpcomingCalendarCacheStore: UpcomingCalendarCacheStoreProtocol {
    private let userDefaults: UserDefaults
    private let key = "streamly.upcoming.calendar.cachedItems"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func cachedItems() async -> [UpcomingCalendarItem] {
        guard let data = userDefaults.data(forKey: key),
              let items = try? JSONDecoder().decode([UpcomingCalendarItem].self, from: data) else {
            return []
        }
        return items
    }

    public func saveCachedItems(_ items: [UpcomingCalendarItem]) async {
        guard let data = try? JSONEncoder().encode(items) else { return }
        userDefaults.set(data, forKey: key)
    }
}

public actor InMemoryUpcomingCalendarCacheStore: UpcomingCalendarCacheStoreProtocol {
    private var items: [UpcomingCalendarItem]

    public init(items: [UpcomingCalendarItem] = []) {
        self.items = items
    }

    public func cachedItems() async -> [UpcomingCalendarItem] {
        items
    }

    public func saveCachedItems(_ items: [UpcomingCalendarItem]) async {
        self.items = items
    }
}

public struct UpcomingCalendarProvider: UpcomingCalendarProviderProtocol {
    private let metadataService: any MetadataServiceProtocol
    private let libraryRepository: any LibraryRepositoryProtocol
    private let seriesDetailProvider: any SeriesDetailProviderProtocol
    private let trackingStore: any SeriesTrackingStoreProtocol
    private let cacheStore: any UpcomingCalendarCacheStoreProtocol
    private let now: @Sendable () -> Date

    public init(
        metadataService: any MetadataServiceProtocol,
        libraryRepository: any LibraryRepositoryProtocol,
        seriesDetailProvider: any SeriesDetailProviderProtocol,
        trackingStore: any SeriesTrackingStoreProtocol = UserDefaultsSeriesTrackingStore(),
        cacheStore: any UpcomingCalendarCacheStoreProtocol = UserDefaultsUpcomingCalendarCacheStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.metadataService = metadataService
        self.libraryRepository = libraryRepository
        self.seriesDetailProvider = seriesDetailProvider
        self.trackingStore = trackingStore
        self.cacheStore = cacheStore
        self.now = now
    }

    public func upcomingItems() async -> [UpcomingCalendarItem] {
        do {
            let items = try await loadLiveItems()
            if !items.isEmpty {
                await cacheStore.saveCachedItems(items.map { $0.withStaleState(false) })
            }
            return items
        } catch {
            return await cacheStore.cachedItems()
                .map { $0.withStaleState(true) }
                .sorted(by: sortUpcoming)
        }
    }

    public func addToWatchlist(itemID: String, libraryRepository overrideRepository: any LibraryRepositoryProtocol) async throws {
        guard let item = await upcomingItems().first(where: { $0.id == itemID }) else { return }
        let list = try await overrideRepository.defaultList()
        try await overrideRepository.add(mediaItem(from: item), to: list.id)
    }

    public func addToWatchlist(itemID: String) async throws {
        try await addToWatchlist(itemID: itemID, libraryRepository: libraryRepository)
    }

    private func loadLiveItems() async throws -> [UpcomingCalendarItem] {
        async let episodes = upcomingEpisodes()
        async let movies = upcomingMovies()
        let items = try await episodes + movies
        return items.sorted(by: sortUpcoming)
    }

    private func upcomingEpisodes() async -> [UpcomingCalendarItem] {
        let seriesItems = await followedSeriesItems()
        var items: [UpcomingCalendarItem] = []

        for seriesItem in seriesItems.prefix(16) {
            guard let response = try? await seriesDetailProvider.seriesDetail(id: seriesItem.id) else { continue }
            for episode in response.seasons.flatMap(\.episodes) {
                guard let releaseDate = episode.airDate,
                      let window = window(for: releaseDate) else { continue }
                items.append(UpcomingCalendarItem(
                    id: "\(response.series.id):episode:\(episode.id)",
                    title: response.series.title,
                    subtitle: "\(episodeLabel(for: episode)) · \(episode.title)",
                    kind: .episode,
                    releaseDate: releaseDate,
                    window: window,
                    posterURL: response.series.posterURL,
                    seriesID: response.series.id,
                    isStale: false
                ))
            }
        }

        return items
    }

    private func upcomingMovies() async throws -> [UpcomingCalendarItem] {
        async let popular = metadataService.popularMovies()
        async let trending = metadataService.trending()
        let candidates = try await popular + trending
        var seen: Set<String> = []
        return candidates.compactMap { item in
            guard item.kind == .movie,
                  !seen.contains(item.id),
                  let releaseDate = item.metadata?.releaseDate,
                  let window = window(for: releaseDate) else {
                return nil
            }
            seen.insert(item.id)
            return UpcomingCalendarItem(
                id: item.id,
                title: item.displayTitle,
                subtitle: "Movie",
                kind: .movie,
                releaseDate: releaseDate,
                window: window,
                posterURL: item.bestPosterURL,
                seriesID: nil,
                isStale: false
            )
        }
    }

    private func followedSeriesItems() async -> [MediaItem] {
        var mediaByID: [String: MediaItem] = [:]
        let libraryItems = (try? await libraryRepository.items()) ?? []
        for item in libraryItems where item.kind == .series {
            mediaByID[item.id] = item
        }

        let lists = (try? await libraryRepository.lists()) ?? []
        if let watchlist = lists.first(where: { $0.isDefault || $0.name.localizedCaseInsensitiveCompare("Хочу посмотреть") == .orderedSame }),
           let listItems = try? await libraryRepository.items(in: watchlist.id) {
            for item in listItems where item.kind == .series {
                mediaByID[item.id] = item
            }
        }

        for id in await trackingStore.trackedSeriesIDs() where mediaByID[id] == nil {
            mediaByID[id] = MediaItem(id: id, title: id, kind: .series, overview: "", releaseYear: nil, posterPath: nil)
        }

        return mediaByID.values.sorted { $0.displayTitle < $1.displayTitle }
    }

    private func mediaItem(from item: UpcomingCalendarItem) -> MediaItem {
        MediaItem(
            id: item.watchlistMediaID,
            title: item.title,
            kind: item.kind == .movie ? .movie : .series,
            overview: "",
            releaseYear: Calendar(identifier: .gregorian).component(.year, from: item.releaseDate),
            posterPath: item.posterURL?.absoluteString,
            metadata: MediaMetadata(
                tmdbId: tmdbID(from: item.watchlistMediaID) ?? 0,
                title: item.title,
                originalTitle: item.title,
                overview: "",
                year: Calendar(identifier: .gregorian).component(.year, from: item.releaseDate),
                releaseDate: item.kind == .movie ? item.releaseDate : nil,
                posterURL: item.posterURL
            )
        )
    }

    private func window(for date: Date) -> UpcomingCalendarWindow? {
        let current = now()
        guard date > current else { return nil }
        let weekEnd = current.addingTimeInterval(7 * 86_400)
        let monthEnd = current.addingTimeInterval(31 * 86_400)
        if date <= weekEnd {
            return .thisWeek
        }
        if date <= monthEnd {
            return .nextMonth
        }
        return nil
    }

    private func sortUpcoming(_ lhs: UpcomingCalendarItem, _ rhs: UpcomingCalendarItem) -> Bool {
        if lhs.releaseDate != rhs.releaseDate {
            return lhs.releaseDate < rhs.releaseDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func episodeLabel(for episode: SeriesEpisode) -> String {
        String(format: "S%02dE%02d", episode.seasonNumber, episode.episodeNumber)
    }

    private func tmdbID(from mediaID: String) -> Int? {
        let parts = mediaID.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "tmdb" else { return nil }
        return Int(parts[2])
    }
}
