import XCTest
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
    func testUnknownSeriesUsesEmptyState() async {
        let viewModel = SeriesDetailViewModel(seriesID: "missing", provider: MockSeriesDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.series)
    }
}
