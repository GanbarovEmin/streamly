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
        XCTAssertEqual(viewModel.tabs, [.trailers, .similar, .cast, .details])
        XCTAssertEqual(viewModel.selectedTab, .details)
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
    func testPremiumPresentationHighlightsBestReleaseAndHeroMetadata() async throws {
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: MockMovieDetailProvider())

        await viewModel.load()

        let highlight = try XCTUnwrap(viewModel.bestReleaseHighlight)
        XCTAssertEqual(highlight.releaseID, "matrix-2160p-hdr-remux")
        XCTAssertEqual(highlight.badge, "Best Release")
        XCTAssertEqual(highlight.primaryMetadata, "2160p · Dolby Vision · HEVC")
        XCTAssertEqual(highlight.secondaryMetadata, "92 seeders · 78.4 GB · Archive")
        XCTAssertEqual(viewModel.primaryWatchActionTitle, "Смотреть лучший релиз")
        XCTAssertNil(viewModel.releaseFallbackTitle)
        XCTAssertEqual(viewModel.heroMetadataBadges.map(\.title), ["1999", "2h 16m", "IMDb 8.7", "Sci-Fi", "Action"])
    }

    @MainActor
    func testMovieFallbackPresentationKeepsDetailReadableWithoutReleasesCastOrMetadata() async {
        let viewModel = MovieDetailViewModel(mediaID: "movie:sparse", provider: SparseMovieDetailProvider())

        await viewModel.load()

        XCTAssertNil(viewModel.bestReleaseHighlight)
        XCTAssertEqual(viewModel.primaryWatchActionTitle, "Выбрать локальный файл")
        XCTAssertEqual(viewModel.releaseFallbackTitle, "Релизы пока не найдены")
        XCTAssertEqual(viewModel.castFallbackTitle, "Актёры пока не загружены")
        XCTAssertEqual(viewModel.heroMetadataBadges.map(\.title), ["Год неизвестен", "Runtime n/a", "IMDb n/a"])
    }

    @MainActor
    func testMovieDetailUsesLocalRecommendationServiceAndDisableSettingHidesSimilar() async {
        let localRecommendation = MediaItem(
            id: "tmdb:movie:900",
            title: "Local Similar",
            kind: .movie,
            overview: "Fixture",
            releaseYear: 2025,
            posterPath: nil
        )
        let recommendationService = DetailRecommendationFixtureService(items: [localRecommendation])
        let enabledViewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: SparseMovieDetailProvider(),
            settingsRepository: CoreMockSettingsRepository(settings: AppSettings()),
            recommendationService: recommendationService
        )

        await enabledViewModel.load()

        XCTAssertEqual(enabledViewModel.similar.map(\.title), ["Local Similar"])

        var settings = AppSettings()
        settings.recommendations.localRecommendationsEnabled = false
        let disabledViewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: SparseMovieDetailProvider(),
            settingsRepository: CoreMockSettingsRepository(settings: settings),
            recommendationService: recommendationService
        )

        await disabledViewModel.load()

        XCTAssertTrue(disabledViewModel.similar.isEmpty)
    }

    @MainActor
    func testGlobalQualityPreferencesAffectDetailReleaseRanking() async {
        let settingsRepository = CoreMockSettingsRepository(
            settings: AppSettings(
                playback: PlaybackSettings(
                    preferredQuality: .p1080,
                    maxFileSizeBytes: 20_000_000_000
                )
            )
        )
        let viewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            settingsRepository: settingsRepository
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.releases.first?.release.id, "matrix-1080p-bluray")
        XCTAssertTrue(viewModel.releases.first?.reasons.contains(.preferredQuality(.p1080)) == true)
        XCTAssertTrue(viewModel.releases.dropFirst().allSatisfy { $0.reasons.contains(.maxFileSizeLimit(20_000_000_000)) })
    }

    @MainActor
    func testSmartWatchUsesBestReleaseAndRemembersManualOverridePerMovie() async throws {
        let selectionStore = InMemoryReleaseSelectionStore()
        let first = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            releaseSelectionStore: selectionStore
        )
        await first.load()

        let automaticRelease = try XCTUnwrap(first.playBestRelease())
        XCTAssertEqual(automaticRelease.id, "matrix-2160p-hdr-remux")
        XCTAssertEqual(first.lastPlayedReleaseID, "matrix-2160p-hdr-remux")
        XCTAssertNil(selectionStore.releaseID(for: "tmdb:movie:603"))

        let manualRelease = try XCTUnwrap(first.releases.first { $0.release.id == "matrix-1080p-bluray" }?.release)
        first.playManualRelease(manualRelease)

        XCTAssertEqual(first.lastPlayedReleaseID, "matrix-1080p-bluray")
        XCTAssertEqual(selectionStore.releaseID(for: "tmdb:movie:603"), "matrix-1080p-bluray")

        let second = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            releaseSelectionStore: selectionStore
        )
        await second.load()

        XCTAssertEqual(second.bestPlayableRelease?.release.id, "matrix-1080p-bluray")
        XCTAssertEqual(second.releases.map(\.release.id), [
            "matrix-2160p-hdr-remux",
            "matrix-2160p-web",
            "matrix-1080p-bluray"
        ])
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
    func testMarkWatchedUpdatesMovieStateAndRepositoryHistory() async throws {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            libraryRepository: repository
        )
        await viewModel.load()

        XCTAssertFalse(viewModel.isWatched)

        viewModel.markWatched()
        try await Task.sleep(nanoseconds: 20_000_000)

        let watchedItems = try await repository.watchedItems()
        XCTAssertTrue(viewModel.isWatched)
        XCTAssertEqual(watchedItems.map(\.item.id), ["tmdb:movie:603"])
        XCTAssertEqual(watchedItems.first?.positionSeconds, 0)
    }

    @MainActor
    func testRemoveFromHistoryClearsMovieProgressWithoutRemovingLibraryState() async throws {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            libraryRepository: repository
        )
        await viewModel.load()
        viewModel.addToLibrary()
        viewModel.markWatched()
        try await Task.sleep(nanoseconds: 20_000_000)

        await viewModel.removeFromHistory()

        XCTAssertTrue(viewModel.isInLibrary)
        XCTAssertFalse(viewModel.isWatched)
        XCTAssertNil(viewModel.progress)
        let watchedItems = try await repository.watchedItems()
        XCTAssertTrue(watchedItems.isEmpty)
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

    @MainActor
    func testRefreshMetadataAndClearItemCacheDelegateToProviderWithoutBreakingLoadedUI() async {
        let provider = RefreshableMovieDetailProvider()
        let viewModel = MovieDetailViewModel(mediaID: "tmdb:movie:603", provider: provider)

        await viewModel.load()
        XCTAssertEqual(viewModel.movie?.title, "The Matrix")

        await viewModel.refreshMetadata()
        XCTAssertEqual(viewModel.movie?.title, "The Matrix Refreshed")
        XCTAssertEqual(viewModel.state, .loaded)

        await viewModel.clearMetadataCacheForItem()
        let calls = await provider.calls()
        XCTAssertEqual(calls, ["detail:tmdb:movie:603", "refresh:tmdb:movie:603", "clear:tmdb:movie:603"])
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

private actor RefreshableMovieDetailProvider: MovieDetailProviderProtocol {
    private var storedCalls: [String] = []
    private var refreshed = false

    func movieDetail(id: String) async throws -> MovieDetailResponse? {
        storedCalls.append("detail:\(id)")
        return response(id: id, title: refreshed ? "The Matrix Refreshed" : "The Matrix")
    }

    func refreshMovieDetail(id: String) async throws -> MovieDetailResponse? {
        storedCalls.append("refresh:\(id)")
        refreshed = true
        return response(id: id, title: "The Matrix Refreshed")
    }

    func clearMetadataCache(id: String) async throws {
        storedCalls.append("clear:\(id)")
    }

    func calls() -> [String] {
        storedCalls
    }

    private func response(id: String, title: String) -> MovieDetailResponse {
        MovieDetailResponse(
            movie: MovieDetail(
                id: id,
                title: title,
                originalTitle: "The Matrix",
                year: 1999,
                runtime: "2h 16m",
                genres: ["Sci-Fi"],
                tmdbRating: "8.2",
                imdbRating: "8.7",
                overview: "Fixture.",
                backdropAccentIndex: 1
            ),
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progress: nil
        )
    }
}

private struct SparseMovieDetailProvider: MovieDetailProviderProtocol {
    func movieDetail(id: String) async throws -> MovieDetailResponse? {
        MovieDetailResponse(
            movie: MovieDetail(
                id: id,
                title: "Untitled",
                originalTitle: "",
                year: 0,
                runtime: "",
                genres: [],
                tmdbRating: "",
                imdbRating: "",
                overview: "",
                backdropAccentIndex: 0
            ),
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progress: nil
        )
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

private struct DetailRecommendationFixtureService: RecommendationServiceProtocol {
    let items: [MediaItem]

    func homeRecommendations(limit: Int) async throws -> [RecommendationSection] {
        []
    }

    func recommendations(for item: MediaItem, seedSimilar: [MediaItem], limit: Int) async throws -> [MediaItem] {
        Array(items.prefix(limit))
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

final class InMemoryReleaseSelectionStore: ReleaseSelectionStoreProtocol {
    private var releaseIDByMediaID: [String: String] = [:]

    func releaseID(for mediaID: String) -> String? {
        releaseIDByMediaID[mediaID]
    }

    func setReleaseID(_ releaseID: String?, for mediaID: String) {
        releaseIDByMediaID[mediaID] = releaseID
    }
}

actor MovieDetailInMemoryLibraryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem] = []
    private var storedFavorites: [MediaItem] = []
    private var storedWatchedItems: [WatchedMediaItem] = []
    private var storedRatedItems: [RatedMediaItem] = []
    private var storedLists: [UserList] = []

    func items() async throws -> [MediaItem] { storedItems }

    func add(_ item: MediaItem) async throws {
        upsert(item)
    }

    func remove(mediaID: String) async throws {
        storedItems.removeAll { $0.id == mediaID }
        storedFavorites.removeAll { $0.id == mediaID }
        storedWatchedItems.removeAll { $0.item.id == mediaID }
        storedRatedItems.removeAll { $0.item.id == mediaID }
    }

    func removeFromHistory(mediaID: String) async throws {
        storedWatchedItems.removeAll { $0.item.id == mediaID }
    }

    func favorites() async throws -> [MediaItem] { storedFavorites }

    func addFavorite(_ item: MediaItem) async throws {
        upsert(item)
        storedFavorites.removeAll { $0.id == item.id }
        storedFavorites.insert(item, at: 0)
    }

    func removeFavorite(mediaID: String) async throws {
        storedFavorites.removeAll { $0.id == mediaID }
    }

    func watchedItems() async throws -> [WatchedMediaItem] { storedWatchedItems }

    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {
        upsert(item)
        storedWatchedItems.removeAll { $0.item.id == item.id }
        storedWatchedItems.insert(WatchedMediaItem(item: item, positionSeconds: positionSeconds), at: 0)
    }

    func ratedItems() async throws -> [RatedMediaItem] { storedRatedItems }

    func setRating(_ item: MediaItem, rating: Int) async throws {
        upsert(item)
        storedRatedItems.removeAll { $0.item.id == item.id }
        storedRatedItems.insert(RatedMediaItem(item: item, rating: rating), at: 0)
    }

    func lists() async throws -> [UserList] { storedLists }

    func defaultList() async throws -> UserList {
        if let existing = storedLists.first(where: \.isDefault) { return existing }
        let list = UserList(id: "default-watchlist", name: "Хочу посмотреть", isDefault: true)
        storedLists.insert(list, at: 0)
        return list
    }

    func createList(name: String) async throws -> UserList {
        try await createList(name: name, description: nil)
    }

    func createList(name: String, description: String?) async throws -> UserList {
        let list = UserList(name: name, description: description)
        storedLists.insert(list, at: 0)
        return list
    }

    func renameList(id: String, name: String, description: String?) async throws {}

    func deleteList(id: String) async throws {
        storedLists.removeAll { $0.id == id && !$0.isDefault }
    }

    func add(_ item: MediaItem, to listID: String) async throws {
        upsert(item)
        storedLists = storedLists.map { list in
            guard list.id == listID, !list.itemIDs.contains(item.id) else { return list }
            return UserList(
                id: list.id,
                name: list.name,
                description: list.description,
                itemIDs: list.itemIDs + [item.id],
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    func remove(_ mediaID: String, from listID: String) async throws {}

    func items(in listID: String) async throws -> [MediaItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return storedItems.filter { list.itemIDs.contains($0.id) }
    }

    private func upsert(_ item: MediaItem) {
        storedItems.removeAll { $0.id == item.id }
        storedItems.insert(item, at: 0)
    }
}
