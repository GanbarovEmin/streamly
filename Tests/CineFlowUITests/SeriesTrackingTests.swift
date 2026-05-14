import CineFlowCore
import XCTest
@testable import CineFlowUI

final class SeriesTrackingTests: XCTestCase {
    func testTrackedLibrarySeriesUsesMetadataReleaseDateSeparatelyFromSourceAvailability() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let series = MediaItem(id: "tmdb:tv:65", title: "Tracked Show", kind: .series, overview: "", releaseYear: 2026, posterPath: nil)
        let provider = SeriesTrackingEpisodeProvider(
            libraryRepository: CoreMockLibraryRepository(storedItems: [series]),
            progressRepository: InMemoryTrackingProgressRepository(records: [
                PlaybackProgress(mediaID: series.id, episodeID: "tracked-s1-e1", positionSeconds: 2_800, durationSeconds: 3_000)
            ]),
            seriesDetailProvider: TrackingFixtureSeriesProvider(releasesByEpisodeID: [:], now: now),
            trackingStore: InMemorySeriesTrackingStore(),
            notificationStore: InMemorySeriesTrackingNotificationStore(),
            now: { now }
        )

        let episodes = await provider.newEpisodes()

        XCTAssertEqual(episodes.map(\.episode.id), ["tracked-s1-e2"])
        XCTAssertEqual(episodes.first?.availability, .metadataReleasedNoSource)
        XCTAssertEqual(episodes.first?.metadataBadgeText, "New Episode Available")
        XCTAssertEqual(episodes.first?.sourceBadgeText, "Waiting for sources")
    }

    func testDigestDoesNotRepeatSeenEpisodesAndEmitsBetterReleaseWhenQualityImproves() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let series = MediaItem(id: "tmdb:tv:65", title: "Tracked Show", kind: .series, overview: "", releaseYear: 2026, posterPath: nil)
        let notificationStore = InMemorySeriesTrackingNotificationStore()
        let fixtureProvider = TrackingFixtureSeriesProvider(
            releasesByEpisodeID: [
                "tracked-s1-e2": [Self.release(id: "tracked-s1-e2-1080p", quality: .fullHD)]
            ],
            now: now
        )
        let provider = SeriesTrackingEpisodeProvider(
            libraryRepository: CoreMockLibraryRepository(storedItems: [series]),
            progressRepository: InMemoryTrackingProgressRepository(records: []),
            seriesDetailProvider: fixtureProvider,
            trackingStore: InMemorySeriesTrackingStore(),
            notificationStore: notificationStore,
            now: { now }
        )

        let initialEpisodes = await provider.newEpisodes()
        let initialDigest = await provider.notificationDigest(for: initialEpisodes)
        let repeatedDigest = await provider.notificationDigest(for: initialEpisodes)

        XCTAssertEqual(initialDigest.items.map(\.kind), [.newEpisodeAvailable, .newReleaseFound])
        XCTAssertTrue(repeatedDigest.items.isEmpty)

        await fixtureProvider.setReleases(
            [Self.release(id: "tracked-s1-e2-2160p", quality: .ultraHD)],
            episodeID: "tracked-s1-e2"
        )
        let upgradedEpisodes = await provider.newEpisodes()
        let upgradedDigest = await provider.notificationDigest(for: upgradedEpisodes)

        XCTAssertEqual(upgradedDigest.items.map(\.kind), [.betterReleaseFound])
        XCTAssertEqual(upgradedDigest.items.first?.episode.availability.sourceName, "Torrentio")
        XCTAssertEqual(upgradedDigest.items.first?.episode.availability.qualityLabel, "2160p")
    }

    private static func release(id: String, quality: ReleaseQuality) -> TorrentRelease {
        TorrentRelease(
            id: id,
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: "Tracked Show \(quality.qualityLabel)",
            magnetURI: "magnet:?xt=urn:btih:\(id)",
            quality: quality,
            seeders: 100
        )
    }
}

private actor TrackingFixtureSeriesProvider: SeriesDetailProviderProtocol {
    private var releasesByEpisodeID: [String: [TorrentRelease]]
    private let now: Date

    init(releasesByEpisodeID: [String: [TorrentRelease]], now: Date) {
        self.releasesByEpisodeID = releasesByEpisodeID
        self.now = now
    }

    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        let first = SeriesEpisode(
            id: "tracked-s1-e1",
            seasonID: "tracked-s1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Pilot",
            runtime: "50m",
            overview: "",
            airDate: now.addingTimeInterval(-14 * 86_400)
        )
        let second = SeriesEpisode(
            id: "tracked-s1-e2",
            seasonID: "tracked-s1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "New Drop",
            runtime: "51m",
            overview: "",
            airDate: now.addingTimeInterval(-3_600)
        )
        let future = SeriesEpisode(
            id: "tracked-s1-e3",
            seasonID: "tracked-s1",
            seasonNumber: 1,
            episodeNumber: 3,
            title: "Future",
            runtime: "52m",
            overview: "",
            airDate: now.addingTimeInterval(86_400)
        )
        return SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Tracked Show",
                yearRange: "2026-",
                seasonsCount: 1,
                rating: "8.0",
                genres: ["Drama"],
                overview: "",
                backdropAccentIndex: 1
            ),
            seasons: [SeriesSeason(id: "tracked-s1", seasonNumber: 1, title: "Season 1", episodes: [first, second, future])],
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }

    func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        (releasesByEpisodeID[episodeID] ?? []).map { ($0, .episode(episodeID)) }
    }

    func setReleases(_ releases: [TorrentRelease], episodeID: String) {
        releasesByEpisodeID[episodeID] = releases
    }
}

private actor InMemoryTrackingProgressRepository: PlaybackProgressRepositoryProtocol {
    private var records: [PlaybackProgress]

    init(records: [PlaybackProgress]) {
        self.records = records
    }

    func saveProgress(_ progress: PlaybackProgress) async throws {
        records.removeAll { $0.mediaID == progress.mediaID && $0.episodeID == progress.episodeID }
        records.append(progress)
    }

    func progress(mediaID: String, episodeID: String?) async throws -> PlaybackProgress? {
        records.first { $0.mediaID == mediaID && $0.episodeID == episodeID }
    }

    func continueWatching(includeCompleted: Bool) async throws -> [PlaybackProgress] {
        records.filter { includeCompleted || !$0.completed }
    }

    func clearProgress(mediaID: String, episodeID: String?) async throws {
        records.removeAll { $0.mediaID == mediaID && $0.episodeID == episodeID }
    }
}
