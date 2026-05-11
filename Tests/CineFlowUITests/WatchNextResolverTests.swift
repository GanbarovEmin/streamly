import CineFlowCore
import XCTest
@testable import CineFlowUI

final class WatchNextResolverTests: XCTestCase {
    func testContinuesLastIncompleteEpisodeBeforeAdvancing() {
        let fixture = WatchNextFixture()
        let progress = [
            "s1e1": PlaybackProgress(
                mediaID: fixture.series.id,
                episodeID: "s1e1",
                positionSeconds: 1_200,
                durationSeconds: 3_600
            )
        ]

        let next = WatchNextResolver.resolve(
            series: fixture.series,
            seasons: fixture.seasons,
            progressByEpisodeID: progress,
            lastWatchedEpisodeID: "s1e1"
        )

        XCTAssertEqual(next?.episode.id, "s1e1")
        XCTAssertEqual(next?.reason, .continueEpisode)
        XCTAssertEqual(next?.ctaTitle, "Continue S01E01")
        XCTAssertEqual(next?.seasonProgress.completedEpisodes, 0)
        XCTAssertEqual(next?.seasonProgress.totalEpisodes, 2)
    }

    func testAdvancesToNextEpisodeWhenCurrentIsOverNinetyPercent() {
        let fixture = WatchNextFixture()
        let progress = [
            "s1e1": PlaybackProgress(
                mediaID: fixture.series.id,
                episodeID: "s1e1",
                positionSeconds: 3_300,
                durationSeconds: 3_600
            )
        ]

        let next = WatchNextResolver.resolve(
            series: fixture.series,
            seasons: fixture.seasons,
            progressByEpisodeID: progress,
            lastWatchedEpisodeID: "s1e1"
        )

        XCTAssertEqual(next?.episode.id, "s1e2")
        XCTAssertEqual(next?.reason, .nextEpisode)
        XCTAssertEqual(next?.ctaTitle, "Continue S01E02")
        XCTAssertEqual(next?.seasonProgress.completedEpisodes, 1)
    }

    func testAdvancesToNextSeasonWhenSeasonIsCompleted() {
        let fixture = WatchNextFixture()
        let progress = [
            "s1e1": PlaybackProgress(mediaID: fixture.series.id, episodeID: "s1e1", positionSeconds: 3_600, durationSeconds: 3_600),
            "s1e2": PlaybackProgress(mediaID: fixture.series.id, episodeID: "s1e2", positionSeconds: 3_600, durationSeconds: 3_600)
        ]

        let next = WatchNextResolver.resolve(
            series: fixture.series,
            seasons: fixture.seasons,
            progressByEpisodeID: progress,
            lastWatchedEpisodeID: "s1e2"
        )

        XCTAssertEqual(next?.episode.id, "s2e1")
        XCTAssertEqual(next?.reason, .nextEpisode)
        XCTAssertEqual(next?.episodeLabel, "S02E01")
        XCTAssertEqual(next?.seasonProgress.seasonNumber, 2)
        XCTAssertEqual(next?.seasonProgress.completedEpisodes, 0)
    }

    func testReturnsNilWhenEveryReleasedEpisodeIsCompleted() {
        let fixture = WatchNextFixture()
        let progress = [
            "s1e1": PlaybackProgress(mediaID: fixture.series.id, episodeID: "s1e1", positionSeconds: 3_600, durationSeconds: 3_600),
            "s1e2": PlaybackProgress(mediaID: fixture.series.id, episodeID: "s1e2", positionSeconds: 3_600, durationSeconds: 3_600),
            "s2e1": PlaybackProgress(mediaID: fixture.series.id, episodeID: "s2e1", positionSeconds: 3_600, durationSeconds: 3_600)
        ]

        let next = WatchNextResolver.resolve(
            series: fixture.series,
            seasons: fixture.seasons,
            progressByEpisodeID: progress,
            lastWatchedEpisodeID: "s2e1"
        )

        XCTAssertNil(next)
    }
}

private struct WatchNextFixture {
    let series = SeriesDetail(
        id: "tmdb:tv:1",
        title: "Fixture Series",
        yearRange: "2020-",
        seasonsCount: 2,
        rating: "8.1",
        genres: ["Drama"],
        overview: "Fixture overview.",
        backdropAccentIndex: 0
    )

    let seasons: [SeriesSeason]

    init() {
        seasons = [
            SeriesSeason(id: "s1", seasonNumber: 1, title: "Season 1", episodes: [
                SeriesEpisode(id: "s1e1", seasonID: "s1", seasonNumber: 1, episodeNumber: 1, title: "Pilot", runtime: "60m", overview: "Pilot."),
                SeriesEpisode(id: "s1e2", seasonID: "s1", seasonNumber: 1, episodeNumber: 2, title: "Second", runtime: "60m", overview: "Second.")
            ]),
            SeriesSeason(id: "s2", seasonNumber: 2, title: "Season 2", episodes: [
                SeriesEpisode(id: "s2e1", seasonID: "s2", seasonNumber: 2, episodeNumber: 1, title: "Return", runtime: "60m", overview: "Return.")
            ])
        ]
    }
}
