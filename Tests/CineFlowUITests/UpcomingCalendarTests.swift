import CineFlowCore
import XCTest
@testable import CineFlowUI

final class UpcomingCalendarTests: XCTestCase {
    func testCalendarShowsUpcomingEpisodesForFollowedSeriesAndUpcomingMoviesFromMetadataDates() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let series = Self.seriesItem(id: "tmdb:tv:66", title: "Followed Show")
        let movieThisWeek = Self.movieItem(id: "tmdb:movie:66", title: "Soon Movie", releaseDate: now.addingTimeInterval(3 * 86_400))
        let movieNextMonth = Self.movieItem(id: "tmdb:movie:67", title: "Month Movie", releaseDate: now.addingTimeInterval(20 * 86_400))
        let undatedMovie = Self.movieItem(id: "tmdb:movie:68", title: "No Date", releaseDate: nil)
        let provider = UpcomingCalendarProvider(
            metadataService: UpcomingMetadataService(popularMovies: [movieThisWeek, movieNextMonth, undatedMovie]),
            libraryRepository: CoreMockLibraryRepository(storedItems: [series]),
            seriesDetailProvider: UpcomingSeriesDetailProvider(now: now),
            trackingStore: InMemorySeriesTrackingStore(ids: [series.id]),
            cacheStore: InMemoryUpcomingCalendarCacheStore(),
            now: { now }
        )

        let items = await provider.upcomingItems()

        XCTAssertEqual(items.map(\.id), [
            "tmdb:tv:66:episode:followed-s1-e2",
            "tmdb:movie:66",
            "tmdb:movie:67"
        ])
        XCTAssertEqual(items.map(\.window), [.thisWeek, .thisWeek, .nextMonth])
        XCTAssertEqual(items.first?.badgeText, "Coming this week")
        XCTAssertEqual(items.last?.badgeText, "Coming next month")
        XCTAssertEqual(items.first?.kind, .episode)
        XCTAssertEqual(items.first?.seriesID, series.id)
        XCTAssertFalse(items.contains { $0.title == "No Date" })
        XCTAssertTrue(items.allSatisfy { !$0.isStale })
    }

    func testOfflineFallbackReturnsCachedUpcomingMarkedStale() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = InMemoryUpcomingCalendarCacheStore(items: [
            UpcomingCalendarItem(
                id: "tmdb:movie:cached",
                title: "Cached Movie",
                subtitle: "Movie",
                kind: .movie,
                releaseDate: now.addingTimeInterval(4 * 86_400),
                window: .thisWeek,
                posterURL: nil,
                seriesID: nil,
                isStale: false
            )
        ])
        let provider = UpcomingCalendarProvider(
            metadataService: UpcomingMetadataService(shouldFail: true),
            libraryRepository: CoreMockLibraryRepository(storedItems: []),
            seriesDetailProvider: UpcomingSeriesDetailProvider(now: now),
            trackingStore: InMemorySeriesTrackingStore(),
            cacheStore: cache,
            now: { now }
        )

        let items = await provider.upcomingItems()

        XCTAssertEqual(items.map(\.title), ["Cached Movie"])
        XCTAssertEqual(items.first?.badgeText, "Stale · Coming this week")
        XCTAssertTrue(items.first?.isStale == true)
    }

    func testAddToWatchlistFromUpcomingCardPersistsDefaultWatchlistItem() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = CoreMockLibraryRepository(storedItems: [])
        let movie = Self.movieItem(id: "tmdb:movie:66", title: "Soon Movie", releaseDate: now.addingTimeInterval(3 * 86_400))
        let provider = UpcomingCalendarProvider(
            metadataService: UpcomingMetadataService(popularMovies: [movie]),
            libraryRepository: repository,
            seriesDetailProvider: UpcomingSeriesDetailProvider(now: now),
            trackingStore: InMemorySeriesTrackingStore(),
            cacheStore: InMemoryUpcomingCalendarCacheStore(),
            now: { now }
        )

        let items = await provider.upcomingItems()
        try await provider.addToWatchlist(itemID: "tmdb:movie:66")

        let watchlist = try await repository.defaultList()
        let watchlistItems = try await repository.items(in: watchlist.id)
        XCTAssertEqual(items.first?.watchlistActionTitle, "Add to Watchlist")
        XCTAssertEqual(watchlistItems.map(\.id), ["tmdb:movie:66"])
    }

    private static func movieItem(id: String, title: String, releaseDate: Date?) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "Upcoming movie.",
            releaseYear: 2026,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
                title: title,
                originalTitle: title,
                overview: "Upcoming movie.",
                year: 2026,
                releaseDate: releaseDate,
                genres: ["Drama"]
            )
        )
    }

    private static func seriesItem(id: String, title: String) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .series,
            overview: "Followed series.",
            releaseYear: 2026,
            posterPath: nil
        )
    }
}

private final class UpcomingMetadataService: MetadataServiceProtocol {
    private let popularMoviesResults: [MediaItem]
    private let shouldFail: Bool

    init(popularMovies: [MediaItem] = [], shouldFail: Bool = false) {
        self.popularMoviesResults = popularMovies
        self.shouldFail = shouldFail
    }

    func search(query: String) async throws -> [MediaItem] {
        []
    }

    func popularMovies() async throws -> [MediaItem] {
        if shouldFail {
            throw CoreMetadataServiceError.unsupported
        }
        return popularMoviesResults
    }

    func trending() async throws -> [MediaItem] {
        if shouldFail {
            throw CoreMetadataServiceError.unsupported
        }
        return []
    }
}

private struct UpcomingSeriesDetailProvider: SeriesDetailProviderProtocol {
    let now: Date

    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        let upcomingEpisode = SeriesEpisode(
            id: "followed-s1-e2",
            seasonID: "followed-s1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Return",
            runtime: "50m",
            overview: "",
            airDate: now.addingTimeInterval(2 * 86_400)
        )
        let farEpisode = SeriesEpisode(
            id: "followed-s1-e9",
            seasonID: "followed-s1",
            seasonNumber: 1,
            episodeNumber: 9,
            title: "Too Far",
            runtime: "50m",
            overview: "",
            airDate: now.addingTimeInterval(50 * 86_400)
        )
        return SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Followed Show",
                yearRange: "2026-",
                seasonsCount: 1,
                rating: "8.0",
                genres: ["Drama"],
                overview: "",
                backdropAccentIndex: 1
            ),
            seasons: [SeriesSeason(id: "followed-s1", seasonNumber: 1, title: "Season 1", episodes: [upcomingEpisode, farEpisode])],
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }
}
