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
        XCTAssertEqual(viewModel.tabs, [.trailers, .similar, .cast, .details])
        XCTAssertEqual(viewModel.selectedTab, .details)
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
        XCTAssertEqual(viewModel.watchNextEpisode?.episode.id, "got-s1-e2")
        XCTAssertEqual(viewModel.continueWatchingTitle, "Continue S01E02")
        XCTAssertEqual(viewModel.seasonProgressSummaries.first?.completedEpisodes, 1)

        viewModel.continueWatching()

        XCTAssertEqual(viewModel.lastPlayedEpisodeID, "got-s1-e2")

        viewModel.updateProgress(episodeID: "got-s2-e2", positionSeconds: 1800, durationSeconds: 3600)
        viewModel.playEpisode(id: "got-s2-e2")

        XCTAssertEqual(viewModel.progressValue(for: "got-s2-e2"), 0.5, accuracy: 0.001)
        XCTAssertEqual(viewModel.lastWatchedEpisode?.id, "got-s2-e2")
        XCTAssertEqual(viewModel.lastPlayedEpisodeID, "got-s2-e2")
    }

    @MainActor
    func testPremiumSeriesPresentationShowsContinueEpisodeAndBestReleaseScope() async throws {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())

        await viewModel.load()

        let episode = try XCTUnwrap(viewModel.selectedEpisodePresentation)
        let highlight = try XCTUnwrap(viewModel.bestReleaseHighlight)
        XCTAssertEqual(viewModel.heroMetadataBadges.map(\.title), ["2011-2019", "2 seasons", "IMDb 8.4", "Drama", "Fantasy"])
        XCTAssertEqual(episode.label, "S01E01")
        XCTAssertEqual(episode.progressFraction ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(viewModel.continueEpisodeLabel, "S01E02 The Kingsroad")
        XCTAssertEqual(highlight.releaseID, "got-series-2160p")
        XCTAssertEqual(highlight.badge, "Best Release")
        XCTAssertEqual(highlight.scopeLabel, "Whole series")
        XCTAssertEqual(viewModel.primaryWatchActionTitle, "Продолжить S01E02")
    }

    @MainActor
    func testSeriesFallbackPresentationKeepsDetailReadableWithoutReleasesCastOrEpisodes() async {
        let viewModel = SeriesDetailViewModel(seriesID: "series:sparse", provider: SparseSeriesDetailProvider())

        await viewModel.load()

        XCTAssertNil(viewModel.selectedEpisodePresentation)
        XCTAssertNil(viewModel.bestReleaseHighlight)
        XCTAssertEqual(viewModel.primaryWatchActionTitle, "Выбрать локальный файл")
        XCTAssertEqual(viewModel.releaseFallbackTitle, "Релизы для серии пока не найдены")
        XCTAssertEqual(viewModel.castFallbackTitle, "Актёры пока не загружены")
        XCTAssertEqual(viewModel.episodeFallbackTitle, "Список серий пока пуст")
    }

    @MainActor
    func testSeriesDetailUsesLocalRecommendationServiceForSimilarSeries() async {
        let localRecommendation = MediaItem(
            id: "tmdb:tv:900",
            title: "Local Similar Series",
            kind: .series,
            overview: "Fixture",
            releaseYear: 2025,
            posterPath: nil
        )
        let viewModel = SeriesDetailViewModel(
            seriesID: "series:sparse",
            provider: SparseSeriesDetailProvider(),
            settingsRepository: CoreMockSettingsRepository(settings: AppSettings()),
            recommendationService: SeriesRecommendationFixtureService(items: [localRecommendation])
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.similar.map(\.title), ["Local Similar Series"])
    }

    @MainActor
    func testContinueWatchingAdvancesToNextEpisodeAfterCompletionThreshold() async {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())
        await viewModel.load()

        viewModel.updateProgress(episodeID: "got-s1-e2", positionSeconds: 3_400, durationSeconds: 3_600)
        XCTAssertEqual(viewModel.watchNextEpisode?.episode.id, "got-s2-e1")
        XCTAssertEqual(viewModel.continueWatchingTitle, "Continue S02E01")

        viewModel.continueWatching()

        XCTAssertEqual(viewModel.lastPlayedEpisodeID, "got-s2-e1")
    }

    @MainActor
    func testNextEpisodePromptCarriesWatchNowActionForMatchedRelease() async throws {
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: MockSeriesDetailProvider())
        await viewModel.load()

        let current = try XCTUnwrap(viewModel.allReleasedEpisodes.first { $0.id == "got-s1-e2" })
        let prompt = try XCTUnwrap(viewModel.nextEpisodePrompt(after: current))

        XCTAssertEqual(prompt.title, "S02E01 The North Remembers")
        XCTAssertEqual(prompt.subtitle, "Next Episode · 53m")
        XCTAssertEqual(prompt.actionTitle, "Watch Now")
        XCTAssertEqual(prompt.nextEpisodeAction?.selectionContext?.episodeID, "got-s2-e1")
        XCTAssertEqual(prompt.nextEpisodeAction?.release?.id, "got-series-2160p")
        XCTAssertFalse(prompt.requiresManualReleaseSelection)
    }

    @MainActor
    func testNextEpisodePromptFallsBackToManualReleaseSelectionWhenNoScopedReleaseMatches() async throws {
        let viewModel = SeriesDetailViewModel(seriesID: "series:manual", provider: ManualReleaseSelectionSeriesProvider())
        await viewModel.load()

        let current = try XCTUnwrap(viewModel.allReleasedEpisodes.first { $0.id == "manual-s1-e1" })
        let prompt = try XCTUnwrap(viewModel.nextEpisodePrompt(after: current))

        XCTAssertEqual(prompt.title, "S01E02 Second")
        XCTAssertEqual(prompt.actionTitle, "Choose Release")
        XCTAssertNil(prompt.nextEpisodeAction?.release)
        XCTAssertTrue(prompt.requiresManualReleaseSelection)
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
    func testSeriesRatingPersistsThroughLibraryRepository() async throws {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            libraryRepository: repository
        )
        await viewModel.load()

        viewModel.setUserRating(9)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(viewModel.userRating, 9)
        let ratedItems = try await repository.ratedItems()
        XCTAssertEqual(ratedItems.map(\.item.id), ["tmdb:tv:1399"])
        XCTAssertEqual(ratedItems.first?.rating, 9)
    }

    @MainActor
    func testRemoveFromHistoryClearsSeriesProgressWithoutRemovingLibraryState() async throws {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            libraryRepository: repository
        )
        await viewModel.load()
        viewModel.addToLibrary()
        viewModel.updateProgress(episodeID: "got-s1-e2", positionSeconds: 1_800, durationSeconds: 3_600)
        viewModel.playEpisode(id: "got-s1-e2")
        try await Task.sleep(nanoseconds: 20_000_000)

        await viewModel.removeFromHistory()

        XCTAssertTrue(viewModel.isInLibrary)
        XCTAssertTrue(viewModel.progressByEpisodeID.isEmpty)
        XCTAssertNil(viewModel.lastWatchedEpisodeID)
        XCTAssertNil(viewModel.selectedEpisodePresentation?.progressFraction)
        let watchedItems = try await repository.watchedItems()
        XCTAssertTrue(watchedItems.isEmpty)
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

    @MainActor
    func testRefreshMetadataAndClearItemCacheDelegateToProviderWithoutBreakingLoadedUI() async {
        let provider = RefreshableSeriesDetailProvider()
        let viewModel = SeriesDetailViewModel(seriesID: "tmdb:tv:1399", provider: provider)

        await viewModel.load()
        await viewModel.refreshMetadata()
        await viewModel.clearMetadataCacheForItem()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.series?.title, "Game of Thrones Refreshed")
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            "detail:tmdb:tv:1399",
            "refresh:tmdb:tv:1399",
            "clear:tmdb:tv:1399"
        ])
    }
}

private actor RefreshableSeriesDetailProvider: SeriesDetailProviderProtocol {
    private var calls: [String] = []

    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        calls.append("detail:\(id)")
        return response(id: id, title: "Game of Thrones")
    }

    func refreshSeriesDetail(id: String) async throws -> SeriesDetailResponse? {
        calls.append("refresh:\(id)")
        return response(id: id, title: "Game of Thrones Refreshed")
    }

    func clearMetadataCache(id: String) async throws {
        calls.append("clear:\(id)")
    }

    func recordedCalls() -> [String] {
        calls
    }

    private func response(id: String, title: String) -> SeriesDetailResponse {
        SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: title,
                yearRange: "2011-2019",
                seasonsCount: 1,
                rating: "8.4",
                genres: ["Drama", "Fantasy"],
                overview: "Noble families fight for control.",
                backdropAccentIndex: 1
            ),
            seasons: [
                SeriesSeason(
                    id: "got-s1",
                    seasonNumber: 1,
                    title: "Season 1",
                    episodes: [
                        SeriesEpisode(
                            id: "got-s1-e1",
                            seasonID: "got-s1",
                            seasonNumber: 1,
                            episodeNumber: 1,
                            title: "Winter Is Coming",
                            runtime: "62m",
                            overview: "Pilot."
                        )
                    ]
                )
            ],
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }
}

private struct SparseSeriesDetailProvider: SeriesDetailProviderProtocol {
    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Untitled Show",
                yearRange: "",
                seasonsCount: 0,
                rating: "",
                genres: [],
                overview: "",
                backdropAccentIndex: 0
            ),
            seasons: [],
            releases: [],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }
}

private struct SeriesRecommendationFixtureService: RecommendationServiceProtocol {
    let items: [MediaItem]

    func homeRecommendations(limit: Int) async throws -> [RecommendationSection] {
        []
    }

    func recommendations(for item: MediaItem, seedSimilar: [MediaItem], limit: Int) async throws -> [MediaItem] {
        Array(items.prefix(limit))
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

private struct ManualReleaseSelectionSeriesProvider: SeriesDetailProviderProtocol {
    func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        let firstEpisode = SeriesEpisode(
            id: "manual-s1-e1",
            seasonID: "manual-s1",
            seasonNumber: 1,
            episodeNumber: 1,
            title: "First",
            runtime: "45m",
            overview: "First episode."
        )
        let secondEpisode = SeriesEpisode(
            id: "manual-s1-e2",
            seasonID: "manual-s1",
            seasonNumber: 1,
            episodeNumber: 2,
            title: "Second",
            runtime: "46m",
            overview: "Second episode."
        )
        return SeriesDetailResponse(
            series: SeriesDetail(
                id: id,
                title: "Manual Show",
                yearRange: "2024-",
                seasonsCount: 1,
                rating: "7.4",
                genres: ["Drama"],
                overview: "Needs manual release selection.",
                backdropAccentIndex: 4
            ),
            seasons: [
                SeriesSeason(id: "manual-s1", seasonNumber: 1, title: "Season 1", episodes: [firstEpisode, secondEpisode])
            ],
            releases: [
                (
                    TorrentRelease(
                        id: "manual-s1-e1-release",
                        sourceId: "manual",
                        sourceName: "Manual",
                        title: "Manual Show S01E01",
                        magnetURI: "magnet:?xt=urn:btih:manuals1e1",
                        quality: .fullHD,
                        seeders: 80
                    ),
                    .episode("manual-s1-e1")
                )
            ],
            trailers: [],
            similar: [],
            cast: [],
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }
}
