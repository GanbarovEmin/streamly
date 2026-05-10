import XCTest
@testable import CineFlowUI

final class MovieDetailViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsMovieHeroMetadataAndTabsFromMockProvider() async {
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: MockMovieDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.movie?.title, "The Matrix")
        XCTAssertEqual(viewModel.movie?.originalTitle, "The Matrix")
        XCTAssertEqual(viewModel.movie?.year, 1999)
        XCTAssertEqual(viewModel.movie?.runtime, "2h 16m")
        XCTAssertEqual(viewModel.movie?.genres, ["Sci-Fi", "Action"])
        XCTAssertEqual(viewModel.movie?.tmdbRating, "8.2")
        XCTAssertEqual(viewModel.tabs, [.releases, .trailers, .similar, .cast, .details])
    }

    @MainActor
    func testReleasesAreSortedByRankingEngineByDefault() async {
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: MockMovieDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.releases.map(\.release.id), [
            "matrix-2160p-hdr-remux",
            "matrix-2160p-web",
            "matrix-1080p-bluray"
        ])
        XCTAssertFalse(viewModel.releases.first?.explanation.isEmpty ?? true)
    }

    @MainActor
    func testLibraryActionsAndRatingMutateViewModelState() async {
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: MockMovieDetailProvider())
        await viewModel.load()

        viewModel.toggleFavorite()
        viewModel.addToLibrary()
        viewModel.addToList("Watchlist")
        viewModel.setUserRating(8)

        XCTAssertTrue(viewModel.isFavorite)
        XCTAssertTrue(viewModel.isInLibrary)
        XCTAssertEqual(viewModel.selectedListName, "Watchlist")
        XCTAssertEqual(viewModel.userRating, 8)

        viewModel.toggleFavorite()

        XCTAssertFalse(viewModel.isFavorite)
    }

    @MainActor
    func testContinueWatchingStateUsesPlaybackProgress() async {
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: MockMovieDetailProvider())

        await viewModel.load()

        XCTAssertTrue(viewModel.hasContinueWatching)
        XCTAssertEqual(viewModel.progress?.positionSeconds, 3_400)
        XCTAssertEqual(viewModel.progress?.durationSeconds, 8_160)
        XCTAssertEqual(viewModel.progressValue, 0.416, accuracy: 0.001)
    }

    @MainActor
    func testPlayAndCopyMagnetActionsAreRecordedThroughViewModel() async throws {
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: MockMovieDetailProvider())
        await viewModel.load()
        let firstRelease = try XCTUnwrap(viewModel.releases.first?.release)

        viewModel.play(firstRelease)
        viewModel.copyMagnet(firstRelease)

        XCTAssertEqual(viewModel.lastPlayedReleaseID, firstRelease.id)
        XCTAssertEqual(viewModel.copiedMagnetURI, firstRelease.magnetURI)
    }

    @MainActor
    func testUnknownMovieUsesEmptyState() async {
        let viewModel = MovieDetailViewModel(mediaID: "missing", provider: MockMovieDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.movie)
    }
}
