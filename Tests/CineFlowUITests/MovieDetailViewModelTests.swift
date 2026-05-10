import CineFlowCore
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
    func testStaleMovieDetailLoadDoesNotOverwriteNewerResult() async throws {
        let provider = SequencedMovieDetailProvider(steps: [
            MovieDetailLoadStep(delayNanoseconds: 120_000_000, response: .empty),
            MovieDetailLoadStep(delayNanoseconds: 0, response: .matrix)
        ])
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: provider)

        let firstLoad = Task { await viewModel.load() }
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.load()
        await firstLoad.value

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.movie?.title, "The Matrix")
    }

    @MainActor
    func testMovieDetailFailureLogsDiagnostics() async {
        let diagnostics = MovieDetailCapturingDiagnosticsService()
        let viewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: FailingMovieDetailProvider(),
            diagnosticsService: diagnostics
        )

        await viewModel.load()

        let events = await diagnostics.events()
        XCTAssertEqual(viewModel.state, .failed("Movie details are temporarily unavailable."))
        XCTAssertEqual(events.first?.metadata["operation"], "movieDetail.load")
        XCTAssertEqual(events.first?.metadata["mediaID"], "tmdb:movie:603")
        XCTAssertTrue(events.first?.metadata["technicalDescription"]?.contains("Fixture metadata failure") == true)
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
    func testLocalUserSourceSelectionIsStoredAndLoadedForMovie() async throws {
        let repository = InMemoryUserMediaSourceRepository()
        let viewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            userMediaSourceRepository: repository
        )
        let localURL = URL(fileURLWithPath: "/tmp/The Matrix.mkv")

        await viewModel.load()
        XCTAssertTrue(viewModel.userSources.isEmpty)

        await viewModel.addLocalSource(url: localURL)

        XCTAssertEqual(viewModel.userSources.map(\.displayName), ["The Matrix"])
        XCTAssertEqual(viewModel.userSources.first?.url, localURL)
        XCTAssertEqual(viewModel.selectedUserSourceID, viewModel.userSources.first?.id)
        XCTAssertEqual(viewModel.userSources.first?.playbackMediaSource?.url, localURL)
    }

    @MainActor
    func testUnknownMovieUsesEmptyState() async {
        let viewModel = MovieDetailViewModel(mediaID: "missing", provider: MockMovieDetailProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertNil(viewModel.movie)
    }
}

private struct MovieDetailLoadStep: Sendable {
    enum Response: Sendable {
        case empty
        case matrix
    }

    let delayNanoseconds: UInt64
    let response: Response
}

private actor SequencedMovieDetailProvider: MovieDetailProviderProtocol {
    private var steps: [MovieDetailLoadStep]
    private var index = 0

    init(steps: [MovieDetailLoadStep]) {
        self.steps = steps
    }

    func movieDetail(id: String) async throws -> MovieDetailResponse? {
        let step = nextStep()
        if step.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: step.delayNanoseconds)
        }
        switch step.response {
        case .empty:
            return nil
        case .matrix:
            return try await MockMovieDetailProvider().movieDetail(id: id)
        }
    }

    private func nextStep() -> MovieDetailLoadStep {
        let step = steps[min(index, steps.count - 1)]
        index += 1
        return step
    }
}

private struct FailingMovieDetailProvider: MovieDetailProviderProtocol {
    func movieDetail(id: String) async throws -> MovieDetailResponse? {
        throw MovieDetailFixtureError()
    }
}

private struct MovieDetailFixtureError: Error, CineFlowErrorConvertible {
    var cineFlowError: CineFlowError {
        CineFlowError(
            category: .metadata,
            technicalDescription: "Fixture metadata failure",
            userMessage: "Movie details are temporarily unavailable.",
            recoverySuggestion: "Try again in a moment.",
            logLevel: .error
        )
    }
}

private actor MovieDetailCapturingDiagnosticsService: DiagnosticsServiceProtocol {
    private var storedEvents: [DiagnosticsEvent] = []

    func log(level: DiagnosticsLogLevel, subsystem: DiagnosticsSubsystem, message: String, metadata: [String: String]) async {
        storedEvents.append(DiagnosticsEvent(level: level, subsystem: subsystem, message: message, metadata: metadata))
    }

    func exportDiagnostics() async -> String {
        ""
    }

    func exportDiagnosticsPackage() async throws -> URL {
        URL(fileURLWithPath: "/tmp/movie-detail-diagnostics.zip")
    }

    func recentEvents(limit: Int) async -> [DiagnosticsEvent] {
        Array(storedEvents.prefix(limit))
    }

    func events() -> [DiagnosticsEvent] {
        storedEvents
    }
}

private actor InMemoryUserMediaSourceRepository: UserMediaSourceRepositoryProtocol {
    private var sourcesByID: [String: UserMediaSource] = [:]

    func sources(for mediaID: String) async throws -> [UserMediaSource] {
        sourcesByID.values
            .filter { $0.mediaID == mediaID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func source(id: String) async throws -> UserMediaSource? {
        sourcesByID[id]
    }

    func save(_ source: UserMediaSource) async throws {
        sourcesByID[source.id] = source
    }

    func delete(id: String) async throws {
        sourcesByID.removeValue(forKey: id)
    }
}
