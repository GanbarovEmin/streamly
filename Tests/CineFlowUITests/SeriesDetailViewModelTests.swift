import XCTest
import CineFlowCore
@testable import CineFlowUI

final class SeriesDetailViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsSeriesHeroMetadataAndTabsFromMockProvider() async {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.series?.title, "Game of Thrones")
        XCTAssertEqual(viewModel.series?.yearRange, "2011-2019")
        XCTAssertEqual(viewModel.series?.seasonsCount, 2)
        XCTAssertEqual(viewModel.series?.rating, "8.4")
        XCTAssertEqual(viewModel.series?.genres, ["Drama", "Fantasy"])
        XCTAssertEqual(viewModel.tabs, [.seasons, .releases, .trailers, .similar, .cast, .details])
    }

    @MainActor
    func testSelectSeasonAndEpisodeUpdatesVisibleEpisodes() async {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())
        await viewModel.load()

        XCTAssertEqual(viewModel.selectedSeason?.seasonNumber, 1)
        XCTAssertEqual(viewModel.visibleEpisodes.map(\.episodeNumber), [1, 2])

        viewModel.selectSeason(id: "got-s2")
        viewModel.selectEpisode(id: "got-s2-e2")

        XCTAssertEqual(viewModel.selectedSeason?.seasonNumber, 2)
        XCTAssertEqual(viewModel.visibleEpisodes.map(\.episodeNumber), [1, 2])
        XCTAssertEqual(viewModel.selectedEpisode?.title, "Blackwater")
    }

    @MainActor
    func testEpisodePlaybackContinueAndProgressPersistence() async {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())
        await viewModel.load()

        XCTAssertEqual(viewModel.lastWatchedEpisode?.id, "got-s1-e2")
        XCTAssertEqual(viewModel.overallProgress, 0.375, accuracy: 0.001)

        viewModel.continueWatching()

        XCTAssertEqual(viewModel.lastPlayedEpisodeID, "got-s1-e2")

        viewModel.updateProgress(episodeID: "got-s2-e2", positionSeconds: 1800, durationSeconds: 3600)
        viewModel.playEpisode(id: "got-s2-e2")

        XCTAssertEqual(viewModel.progressValue(for: "got-s2-e2"), 0.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.lastWatchedEpisode?.id, "got-s2-e2")
        XCTAssertEqual(viewModel.lastPlayedEpisodeID, "got-s2-e2")
    }

    @MainActor
    func testSeriesCanBeAddedToLibraryAndList() async {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())
        await viewModel.load()

        viewModel.addToLibrary()
        viewModel.addToList("Weekend")

        XCTAssertTrue(viewModel.isInLibrary)
        XCTAssertEqual(viewModel.selectedListName, "Weekend")
    }

    @MainActor
    func testReleasesSupportSeriesSeasonAndEpisodeScopesSortedByRankingEngine() async {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())
        await viewModel.load()

        XCTAssertEqual(viewModel.releases.map(\.release.id), [
            "got-series-2160p",
            "got-s2-1080p",
            "got-s1-e2-1080p"
        ])
        XCTAssertEqual(viewModel.releases.map(\.scope), [.series, .season("got-s2"), .episode("got-s1-e2")])
        XCTAssertFalse(viewModel.releases.first?.ranked.explanation.isEmpty ?? true)
    }

    @MainActor
    func testSmartWatchUsesSelectedEpisodeBestReleaseAndPersistsManualOverride() async throws {
        let selectionStore = InMemoryReleaseSelectionStore()
        let first = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            releaseSelectionStore: selectionStore
        )
        await first.load()

        let automaticRelease = try XCTUnwrap(first.playBestRelease())
        XCTAssertEqual(automaticRelease.id, "got-series-2160p")
        XCTAssertEqual(first.lastPlayedEpisodeID, "got-s1-e1")

        let manualRelease = try XCTUnwrap(first.releases.first { $0.release.id == "got-s1-e2-1080p" }?.release)
        first.playManualRelease(manualRelease)

        XCTAssertEqual(selectionStore.releaseID(for: "tmdb:tv:1399:got-s1-e1"), "got-s1-e2-1080p")

        let second = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            releaseSelectionStore: selectionStore
        )
        await second.load()

        XCTAssertEqual(second.bestPlayableRelease?.release.id, "got-s1-e2-1080p")
    }

    @MainActor
    func testSelectingEpisodeReloadsReleasesForThatEpisode() async {
        let provider = EpisodeReleaseProvider()
        let viewModel = SeriesDetailViewModel(seriesID: "imdb:series:tt0944947", provider: provider)

        await viewModel.load()
        XCTAssertEqual(viewModel.releases.map(\.release.id), ["release-tt0944947-1-1"])

        await viewModel.selectEpisodeAndLoadReleases(id: "tt0944947:1:2")

        XCTAssertEqual(viewModel.selectedEpisode?.id, "tt0944947:1:2")
        XCTAssertEqual(viewModel.releases.map(\.release.id), ["release-tt0944947-1-2"])
        XCTAssertEqual(viewModel.releases.map(\.scope), [.episode("tt0944947:1:2")])
        let recordedEpisodeIDs = await provider.recordedEpisodeIDs()
        XCTAssertEqual(recordedEpisodeIDs, ["tt0944947:1:2"])
    }

    @MainActor
    func testFutureEpisodeIsUpcomingAndDoesNotLoadReleases() async {
        let provider = FutureEpisodeProvider()
        let viewModel = SeriesDetailViewModel(seriesID: "series:future", provider: provider)

        await viewModel.load()

        let upcoming = viewModel.visibleEpisodes[1]
        XCTAssertTrue(upcoming.isUpcoming)

        await viewModel.selectEpisodeAndLoadReleases(id: upcoming.id)

        let recordedEpisodeIDs = await provider.recordedEpisodeIDs()
        XCTAssertEqual(viewModel.selectedEpisode?.id, upcoming.id)
        XCTAssertTrue(viewModel.releases.isEmpty)
        XCTAssertTrue(recordedEpisodeIDs.isEmpty)
    }

    @MainActor
    func testEpisodeNotificationTogglePersistsPerSeries() async {
        let store = UserDefaultsSeriesNotificationStore(
            userDefaults: UserDefaults(suiteName: "SeriesDetailViewModelTests.notifications")!
        )
        await store.setNotificationsEnabled(false, seriesID: "tmdb:tv:1399")
        let first = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            notificationStore: store
        )

        await first.load()
        XCTAssertFalse(first.episodeNotificationsEnabled)

        await first.setEpisodeNotificationsEnabled(true)

        let second = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            notificationStore: store
        )
        await second.load()

        XCTAssertTrue(second.episodeNotificationsEnabled)
    }

    @MainActor
    func testStaleEpisodeReleaseLoadDoesNotOverwriteNewerEpisodeSelection() async throws {
        let provider = EpisodeReleaseProvider(delayByEpisodeID: ["tt0944947:1:1": 120_000_000])
        let viewModel = SeriesDetailViewModel(seriesID: "imdb:series:tt0944947", provider: provider)

        await viewModel.load()
        let staleLoad = Task { await viewModel.selectEpisodeAndLoadReleases(id: "tt0944947:1:1") }
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.selectEpisodeAndLoadReleases(id: "tt0944947:1:2")
        await staleLoad.value

        XCTAssertEqual(viewModel.selectedEpisode?.id, "tt0944947:1:2")
        XCTAssertEqual(viewModel.releases.map(\.release.id), ["release-tt0944947-1-2"])
        XCTAssertEqual(viewModel.releases.map(\.scope), [.episode("tt0944947:1:2")])
    }

    @MainActor
    func testUnknownSeriesUsesEmptyState() async {
        let viewModel = SeriesDetailViewModel(seriesID: "missing", provider: MockSeriesDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.series)
    }
}

private actor EpisodeReleaseProvider: SeriesDetailProviderProtocol {
    private var episodeIDs: [String] = []
    private let delayByEpisodeID: [String: UInt64]

    init(delayByEpisodeID: [String: UInt64] = [:]) {
        self.delayByEpisodeID = delayByEpisodeID
    }

    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        let firstEpisode = SeriesEpisode(
            id: "tt0944947:1:1",
            seasonID: "season-1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Winter Is Coming",
            runtime: "62m",
            overview: "Pilot."
        )
        let secondEpisode = SeriesEpisode(
            id: "tt0944947:1:2",
            seasonID: "season-1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "The Kingsroad",
            runtime: "56m",
            overview: "The journey begins."
        )
        return SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Game of Thrones",
                yearRange: "2011-2019",
                seasonsCount: 1,
                rating: "9.2",
                genres: ["Drama"],
                overview: "Noble families fight for control.",
                backdropAccentIndex: 1
            ),
            seasons: [
                SeriesSeason(id: "season-1", seasonNumber: 1, title: "Season 1", episodes: [firstEpisode, secondEpisode])
            ],
            releases: [(Self.release(id: "release-tt0944947-1-1", title: "Game of Thrones S01E01"), .episode("tt0944947:1:1"))],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }

    func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        episodeIDs.append(episodeID)
        if let delay = delayByEpisodeID[episodeID], delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return [(Self.release(id: "release-\(episodeID.replacingOccurrences(of: ":", with: "-"))", title: "Game of Thrones \(episodeID)"), .episode(episodeID))]
    }

    func recordedEpisodeIDs() -> [String] {
        episodeIDs
    }

    fileprivate static func release(id: String, title: String) -> TorrentRelease {
        TorrentRelease(
            id: id,
            sourceId: "torrentio",
            sourceName: "Torrentio",
            title: title,
            magnetURI: "magnet:?xt=urn:btih:\(id)",
            quality: .fullHD,
            seeders: 100
        )
    }
}

private actor FutureEpisodeProvider: SeriesDetailProviderProtocol {
    private var episodeIDs: [String] = []

    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        let releasedEpisode = SeriesEpisode(
            id: "future-s1-e1",
            seasonID: "future-s1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "Already Here",
            runtime: "44m",
            overview: "Released episode.",
            airDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let futureEpisode = SeriesEpisode(
            id: "future-s1-e2",
            seasonID: "future-s1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Tomorrow",
            runtime: "44m",
            overview: "Upcoming episode.",
            airDate: Date().addingTimeInterval(86_400)
        )
        return SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Future Show",
                yearRange: "2026-",
                seasonsCount: 1,
                rating: "7.1",
                genres: ["Drama"],
                overview: "Future episodes.",
                backdropAccentIndex: 2
            ),
            seasons: [
                SeriesSeason(id: "future-s1", seasonNumber: 1, title: "Season 1", episodes: [releasedEpisode, futureEpisode])
            ],
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }

    func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        episodeIDs.append(episodeID)
        return [(EpisodeReleaseProvider.release(id: "release-\(episodeID)", title: "Future Show \(episodeID)"), .episode(episodeID))]
    }

    func recordedEpisodeIDs() -> [String] {
        episodeIDs
    }
}
