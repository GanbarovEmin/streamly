import CineFlowCore
import XCTest
@testable import CineFlowUI

final class HomeViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsFeaturedHeroAndRequiredSectionsFromSeedData() async {
        let viewModel = HomeViewModel(seedItems: HomeSeedLibrary.developmentItems)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.featuredItems.count, 4)
        XCTAssertEqual(viewModel.selectedFeaturedItem?.title, "Dune: Part Two")
        XCTAssertEqual(
            viewModel.selectedFeaturedItem?.metadataLine,
            "2024 · PG-13 · 2h 46m · Sci-Fi"
        )
        XCTAssertEqual(
            viewModel.sections.map(\.kind),
            [
                .continueWatching,
                .watchNext,
                .recommendedTonight,
                .trendingNow
            ]
        )
        XCTAssertEqual(viewModel.sections.map(\.title), [
            "Continue Watching",
            "Watch Next",
            "Recommended Tonight",
            "Trending Now"
        ])
        XCTAssertEqual(viewModel.sections[0].cardStyle, .landscape)
        XCTAssertEqual(viewModel.sections[1].cardStyle, .landscape)
        XCTAssertEqual(viewModel.sections[2].cardStyle, .landscape)
        XCTAssertTrue(viewModel.sections[0].items.allSatisfy { $0.progress != nil })
        XCTAssertEqual(viewModel.sections.map(\.personalizationID), viewModel.sections.map { $0.kind.personalizationID })
    }

    @MainActor
    func testSmartSectionsUseStreamingDashboardLabelsAndBecauseYouWatchedAvoidsActiveProgressDuplicates() async throws {
        let progressRepository = InMemoryHomeProgressRepository(records: [
            PlaybackProgress(mediaID: "tmdb:movie:693134", positionSeconds: 50, durationSeconds: 100)
        ])
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            progressRepository: progressRepository
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.sections.map(\.title).contains("Continue Watching"))
        XCTAssertTrue(viewModel.sections.map(\.title).contains("Trending Now"))
        XCTAssertFalse(viewModel.sections.map(\.title).contains("Recently Added"))
        XCTAssertFalse(viewModel.sections.map(\.title).contains("Trending Movies"))
        XCTAssertTrue(viewModel.sections.map(\.title).contains("Trending Now"))
        XCTAssertFalse(viewModel.sections.map(\.title).contains("Because You Watched"))
        XCTAssertFalse(viewModel.sections.map(\.title).contains("Best Quality Available"))

        let trendingNow = try XCTUnwrap(viewModel.sections.first { $0.kind == .trendingNow })
        XCTAssertTrue(trendingNow.items.contains { $0.id.contains(":movie:") })
        XCTAssertTrue(trendingNow.items.contains { $0.id.contains(":tv:") })
    }

    @MainActor
    func testHomeRowsAreReorderReadyAndHideEmptyPersonalRows() async throws {
        let viewModel = HomeViewModel(seedItems: [
            HomeSeedItem(
                id: "tmdb:movie:1",
                title: "Only Trending",
                kind: .movie,
                year: 2026,
                rating: "PG-13",
                runtime: "1h 40m",
                genre: "Drama",
                overview: "Small fixture.",
                quality: "1080p",
                popularityRank: 1,
                isFeatured: true
            )
        ])

        await viewModel.load()

        XCTAssertTrue(viewModel.sections.map(\.title).contains("Trending Now"))
        XCTAssertTrue(viewModel.sections.map(\.personalizationID).contains("trendingNow"))
        XCTAssertEqual(
            viewModel.sections.map { $0.kind.defaultOrderIndex },
            viewModel.sections.map { $0.kind.defaultOrderIndex }.sorted()
        )
        XCTAssertFalse(viewModel.sections.contains { $0.items.isEmpty })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .continueWatching })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .watchNext })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .favoriteGenres })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .unfinishedMovies })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .forgottenInLibrary })
    }

    @MainActor
    func testHomeAppliesPersistedSectionVisibilityAndOrder() async throws {
        var settings = AppSettings()
        settings.home.setSection("continueWatching", isEnabled: false, updatedAt: Date(timeIntervalSince1970: 10))
        settings.home.setSection("trendingNow", isEnabled: false, updatedAt: Date(timeIntervalSince1970: 20))
        settings.home.setSection("recommended", isEnabled: true, updatedAt: Date(timeIntervalSince1970: 25))
        settings.home.moveSection("recommended", to: 0, updatedAt: Date(timeIntervalSince1970: 30))
        let settingsRepository = CoreMockSettingsRepository(settings: settings)
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: settingsRepository
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.homePreferences.layoutDensity, .comfortable)
        XCTAssertEqual(viewModel.homePreferences.posterSize, .medium)
        XCTAssertEqual(viewModel.sections.first?.kind, .recommended)
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .continueWatching })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .trendingNow })

        await settingsRepository.setAppSettings(AppSettings())
        await viewModel.refreshHomePreferences()

        XCTAssertTrue(viewModel.sections.contains { $0.kind == .continueWatching })
        XCTAssertTrue(viewModel.sections.contains { $0.kind == .trendingNow })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .recommended })
    }

    @MainActor
    func testOlderHomePreferenceSchemaMigratesToNetflixFocusDefaults() async throws {
        var settings = AppSettings()
        settings.home = HomePreferences(
            sections: HomePreferences.defaultSectionIDs.enumerated().map { index, sectionID in
                HomeSectionPreference(sectionID: sectionID, isEnabled: true, order: index)
            },
            schemaVersion: 2
        )
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: CoreMockSettingsRepository(settings: settings)
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.sections.contains { $0.kind == .trendingNow })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .recommended })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .recentlyAdded })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .trendingMovies })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .trendingSeries })
    }

    @MainActor
    func testHomeUsesLocalRecommendationServiceAndSettingCanDisableRows() async throws {
        var enabledSettings = AppSettings()
        enabledSettings.recommendations.localRecommendationsEnabled = true
        enabledSettings.home.setSection("moreLikeThis", isEnabled: true)
        enabledSettings.home.setSection("fromFavoriteGenres", isEnabled: true)
        let settingsRepository = CoreMockSettingsRepository(settings: enabledSettings)
        let recommendationService = HomeRecommendationFixtureService(sections: [
            RecommendationSection(
                kind: .moreLikeThis,
                title: "More Like This",
                items: [makeLibraryItem(id: "tmdb:movie:900", title: "Local Match", kind: .movie, year: 2025, genres: ["Sci-Fi"])]
            ),
            RecommendationSection(
                kind: .fromFavoriteGenres,
                title: "From Your Favorite Genres",
                items: [makeLibraryItem(id: "tmdb:movie:901", title: "Genre Match", kind: .movie, year: 2025, genres: ["Action"])]
            )
        ])
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: settingsRepository,
            recommendationService: recommendationService
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.sections.first { $0.kind == .moreLikeThis }?.items.map(\.title), ["Local Match"])
        XCTAssertEqual(viewModel.sections.first { $0.kind == .fromFavoriteGenres }?.items.map(\.title), ["Genre Match"])

        var disabledSettings = enabledSettings
        disabledSettings.recommendations.localRecommendationsEnabled = false
        await settingsRepository.setAppSettings(disabledSettings)
        await viewModel.load()

        XCTAssertFalse(viewModel.sections.contains { $0.kind == .moreLikeThis })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .fromFavoriteGenres })
        XCTAssertFalse(viewModel.sections.contains { $0.kind == .recommended })
    }

    @MainActor
    func testHomeNegativeFeedbackHidesCardsAndUndoRestoresThem() async throws {
        let targetID = "tmdb:movie:693134"
        let settingsRepository = CoreMockSettingsRepository(settings: AppSettings())
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: settingsRepository
        )

        await viewModel.load()
        XCTAssertTrue(viewModel.sections.flatMap(\.items).contains { $0.id == targetID })

        await viewModel.hideTitle(itemID: targetID)

        var persisted = await settingsRepository.appSettings
        XCTAssertEqual(persisted.tasteProfile.hiddenItem(for: targetID)?.reason, .hiddenTitle)
        XCTAssertFalse(viewModel.sections.flatMap(\.items).contains { $0.id == targetID })
        XCTAssertNotNil(viewModel.personalizationUndo)

        await viewModel.undoLastPersonalizationAction()

        persisted = await settingsRepository.appSettings
        XCTAssertNil(persisted.tasteProfile.hiddenItem(for: targetID))
        XCTAssertTrue(viewModel.sections.flatMap(\.items).contains { $0.id == targetID })
        XCTAssertNil(viewModel.personalizationUndo)
    }

    @MainActor
    func testHomeNotInterestedCanShowLessGenreAndRemoveRecommendation() async throws {
        let targetID = "tmdb:movie:693134"
        let settingsRepository = CoreMockSettingsRepository(settings: AppSettings())
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: settingsRepository
        )

        await viewModel.load()
        await viewModel.markNotInterested(itemID: targetID)
        await viewModel.showLessOfPrimaryGenre(itemID: targetID)
        await viewModel.removeFromRecommendations(itemID: targetID)

        let persisted = await settingsRepository.appSettings
        XCTAssertEqual(persisted.tasteProfile.hiddenItem(for: targetID)?.reason, .removedFromRecommendations)
        XCTAssertEqual(persisted.tasteProfile.preference(forGenre: "Sci-Fi"), .less)
    }

    @MainActor
    func testHomeBuildsLocalPersonalRowsFromLibraryAndProgressSignals() async throws {
        let libraryMovie = makeLibraryItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            year: 1999,
            genres: ["Sci-Fi", "Action"]
        )
        let forgottenMovie = makeLibraryItem(
            id: "local:movie:quiet",
            title: "Quiet Archive",
            kind: .movie,
            year: 2018,
            genres: ["Drama"]
        )
        let repository = CoreMockLibraryRepository(storedItems: [libraryMovie, forgottenMovie])
        try await repository.addFavorite(libraryMovie)
        let progressRepository = InMemoryHomeProgressRepository(records: [
            PlaybackProgress(mediaID: libraryMovie.id, positionSeconds: 1_800, durationSeconds: 7_200)
        ])
        var settings = AppSettings()
        settings.home.setSection("favoriteGenres", isEnabled: true)
        settings.home.setSection("unfinishedMovies", isEnabled: true)
        settings.home.setSection("forgottenInLibrary", isEnabled: true)
        settings.home.setSection("ultraHDR", isEnabled: true)
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: CoreMockSettingsRepository(settings: settings),
            progressRepository: progressRepository,
            libraryRepository: repository
        )

        await viewModel.load()

        let titles = viewModel.sections.map(\.title)
        XCTAssertTrue(titles.contains("Favorite Genres"))
        XCTAssertTrue(titles.contains("Unfinished Movies"))
        XCTAssertTrue(titles.contains("Forgotten in Library"))
        XCTAssertTrue(titles.contains("Recommended Tonight"))
        XCTAssertTrue(titles.contains("4K/HDR Available"))

        let favoriteGenres = try XCTUnwrap(viewModel.sections.first { $0.kind == .favoriteGenres })
        XCTAssertTrue(favoriteGenres.items.contains { $0.metadata.contains("Sci-Fi") })

        let unfinishedMovies = try XCTUnwrap(viewModel.sections.first { $0.kind == .unfinishedMovies })
        XCTAssertEqual(unfinishedMovies.items.first?.title, "The Matrix")

        let forgotten = try XCTUnwrap(viewModel.sections.first { $0.kind == .forgottenInLibrary })
        XCTAssertEqual(forgotten.items.map(\.title), ["Quiet Archive"])
    }

    @MainActor
    func testSelectFeaturedItemUpdatesHeroPagination() async {
        let viewModel = HomeViewModel(seedItems: HomeSeedLibrary.developmentItems)
        await viewModel.load()

        viewModel.selectFeaturedItem(id: "tmdb:movie:155")

        XCTAssertEqual(viewModel.selectedFeaturedItem?.id, "tmdb:movie:155")
        XCTAssertEqual(viewModel.selectedFeaturedIndex, 2)
    }

    @MainActor
    func testLoadUsesEmptyStateWhenSeedLayerHasNoMedia() async {
        let viewModel = HomeViewModel(seedItems: [])

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertTrue(viewModel.featuredItems.isEmpty)
        XCTAssertTrue(viewModel.sections.isEmpty)
    }

    @MainActor
    func testLoadUsesErrorStateWhenSeedLayerThrows() async {
        let viewModel = HomeViewModel(seedProvider: { throw HomeSeedError.unavailable })

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .failed("Metadata could not be loaded."))
        XCTAssertTrue(viewModel.featuredItems.isEmpty)
        XCTAssertTrue(viewModel.sections.isEmpty)
    }

    @MainActor
    func testContinueWatchingResolvesStoredMediaTitleAndArtworkInsteadOfRawID() async throws {
        let posterURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w500/matrix.jpg"))
        let metadata = MediaMetadata(
            tmdbId: 603,
            title: "The Matrix",
            originalTitle: "The Matrix",
            overview: "A hacker discovers the truth.",
            year: 1999,
            posterURL: posterURL
        )
        let mediaItem = MediaItem(
            id: "tmdb:movie:603",
            title: "tmdb:movie:603",
            kind: .movie,
            overview: "Fallback overview",
            releaseYear: 1999,
            posterPath: nil,
            metadata: metadata
        )
        let progressRepository = InMemoryHomeProgressRepository(records: [
            PlaybackProgress(mediaID: mediaItem.id, positionSeconds: 50, durationSeconds: 100)
        ])
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            progressRepository: progressRepository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [mediaItem])
        )

        await viewModel.load()

        let continueSection = try XCTUnwrap(viewModel.sections.first { $0.kind == .continueWatching })
        let card = try XCTUnwrap(continueSection.items.first)
        XCTAssertEqual(card.title, "The Matrix")
        XCTAssertEqual(card.metadata, "50% watched")
        XCTAssertEqual(card.progress, 0.5)
        XCTAssertEqual(card.artworkURL, posterURL)
    }

    @MainActor
    func testContinueWatchingFallsBackToSeedTitleAndArtworkForSparseLibraryItem() async throws {
        let backdropURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w780/seed-backdrop.jpg"))
        let seedItem = HomeSeedItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            year: 1999,
            rating: "R",
            runtime: "2h 16m",
            genre: "Sci-Fi",
            overview: "A hacker discovers that reality is a simulated world controlled by machines.",
            quality: "2160p",
            popularityRank: 1,
            backdropURL: backdropURL
        )
        let sparseItem = MediaItem(
            id: seedItem.id,
            title: seedItem.id,
            kind: .movie,
            overview: "",
            releaseYear: 1999,
            posterPath: nil
        )
        let progressRepository = InMemoryHomeProgressRepository(records: [
            PlaybackProgress(mediaID: seedItem.id, positionSeconds: 25, durationSeconds: 100)
        ])
        let viewModel = HomeViewModel(
            seedItems: [seedItem],
            progressRepository: progressRepository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [sparseItem])
        )

        await viewModel.load()

        let continueSection = try XCTUnwrap(viewModel.sections.first { $0.kind == .continueWatching })
        let card = try XCTUnwrap(continueSection.items.first)
        XCTAssertEqual(card.title, "The Matrix")
        XCTAssertEqual(card.metadata, "25% watched")
        XCTAssertEqual(card.artworkURL, backdropURL)
    }

    @MainActor
    func testContinueWatchingSeriesCardsKeepSeriesNavigationID() async throws {
        let series = MediaItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            overview: "Noble families fight for control.",
            releaseYear: 2011,
            posterPath: nil
        )
        let progressRepository = InMemoryHomeProgressRepository(records: [
            PlaybackProgress(mediaID: series.id, episodeID: "tt0944947:1:1", positionSeconds: 50, durationSeconds: 100)
        ])
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            progressRepository: progressRepository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [series])
        )

        await viewModel.load()

        let continueSection = try XCTUnwrap(viewModel.sections.first { $0.kind == .continueWatching })
        let card = try XCTUnwrap(continueSection.items.first)
        XCTAssertEqual(card.id, series.id)
        XCTAssertEqual(card.title, "Game of Thrones")
    }

    @MainActor
    func testWatchNextSectionUsesEpisodeLevelSeriesProgressAndHidesCompletedSeries() async throws {
        let backdropURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w780/got-backdrop.jpg"))
        let series = MediaItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            overview: "Noble families fight for control.",
            releaseYear: 2011,
            posterPath: nil
        )
        let seedItem = HomeSeedItem(
            id: series.id,
            title: series.title,
            kind: .series,
            year: 2011,
            rating: "TV-MA",
            runtime: "8 seasons",
            genre: "Drama",
            overview: "Noble families fight for control.",
            quality: "1080p",
            popularityRank: 1,
            backdropURL: backdropURL
        )
        let provider = InMemoryWatchNextProvider(items: [
            WatchNextEpisode(
                seriesID: series.id,
                seriesTitle: series.title,
                episode: SeriesEpisode(id: "got-s2-e1", seasonID: "got-s2", seasonNumber: 2, episodeNumber: 1, title: "The North Remembers", runtime: "53m", overview: ""),
                reason: .nextEpisode,
                progress: 0,
                seasonProgress: WatchNextSeasonProgress(seasonID: "got-s2", seasonNumber: 2, completedEpisodes: 0, totalEpisodes: 2)
            )
        ])
        let progressRepository = InMemoryHomeProgressRepository(records: [
            PlaybackProgress(mediaID: series.id, episodeID: "got-s1-e2", positionSeconds: 3_500, durationSeconds: 3_600)
        ])
        let viewModel = HomeViewModel(
            seedItems: [seedItem],
            progressRepository: progressRepository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [series]),
            watchNextProvider: provider
        )

        await viewModel.load()

        let watchNext = try XCTUnwrap(viewModel.sections.first { $0.kind == .watchNext })
        XCTAssertEqual(watchNext.items.first?.id, series.id)
        XCTAssertEqual(watchNext.items.first?.title, "Game of Thrones")
        XCTAssertEqual(watchNext.items.first?.metadata, "Continue S02E01 · The North Remembers")
        XCTAssertEqual(watchNext.items.first?.artworkURL, backdropURL)

        XCTAssertNil(viewModel.sections.first { $0.kind == .continueWatching })
    }

    @MainActor
    func testNewEpisodesSectionUsesTrackedSeriesProviderBeforeWatchNext() async throws {
        let backdropURL = try XCTUnwrap(URL(string: "https://image.tmdb.org/t/p/w780/got-new-episode.jpg"))
        let seedItem = HomeSeedItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            year: 2011,
            rating: "TV-MA",
            runtime: "8 seasons",
            genre: "Drama",
            overview: "Noble families fight for control.",
            quality: "1080p",
            popularityRank: 1,
            backdropURL: backdropURL
        )
        let newEpisode = NewSeriesEpisode(
            seriesID: "tmdb:tv:1399",
            seriesTitle: "Game of Thrones",
            episode: SeriesEpisode(
                id: "got-s2-e1",
                seasonID: "got-s2",
                seasonNumber: 2,
                episodeNumber: 1,
                title: "The North Remembers",
                runtime: "53m",
                overview: ""
            ),
            availability: .sourceAvailable(bestReleaseID: "got-s2-e1-2160p", qualityLabel: "2160p", sourceName: "Torrentio"),
            releasedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let viewModel = HomeViewModel(
            seedItems: [seedItem],
            newEpisodesProvider: InMemoryNewEpisodesProvider(items: [newEpisode])
        )

        await viewModel.load()

        let section = try XCTUnwrap(viewModel.sections.first { $0.kind == .newEpisodes })
        XCTAssertEqual(section.title, "New Episodes")
        XCTAssertLessThan(
            viewModel.sections.firstIndex { $0.kind == .newEpisodes } ?? Int.max,
            viewModel.sections.firstIndex { $0.kind == .recommendedTonight } ?? Int.max
        )
        XCTAssertEqual(section.items.first?.id, "tmdb:tv:1399")
        XCTAssertEqual(section.items.first?.title, "Game of Thrones")
        XCTAssertEqual(section.items.first?.metadata, "S02E01 · The North Remembers · Torrentio")
        XCTAssertEqual(section.items.first?.badge, "New Episode Available")
        XCTAssertEqual(section.items.first?.artworkURL, backdropURL)
        XCTAssertEqual(viewModel.episodeNotificationDigest.items.map(\.kind), [.newEpisodeAvailable, .newReleaseFound])
    }

    @MainActor
    func testUpcomingCalendarSectionAppearsAfterNewEpisodesAndSupportsWatchlistAction() async throws {
        let repository = CoreMockLibraryRepository(storedItems: [])
        let upcoming = UpcomingCalendarItem(
            id: "tmdb:movie:66",
            title: "Soon Movie",
            subtitle: "Movie",
            kind: .movie,
            releaseDate: Date(timeIntervalSince1970: 1_800_000_000),
            window: .thisWeek,
            posterURL: nil,
            seriesID: nil,
            isStale: false
        )
        let provider = InMemoryUpcomingCalendarProvider(items: [upcoming])
        var settings = AppSettings()
        settings.home.setSection("upcomingCalendar", isEnabled: true)
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: CoreMockSettingsRepository(settings: settings),
            libraryRepository: repository,
            upcomingCalendarProvider: provider
        )

        await viewModel.load()
        await viewModel.addUpcomingToWatchlist(itemID: upcoming.id)

        let section = try XCTUnwrap(viewModel.sections.first { $0.kind == .upcomingCalendar })
        XCTAssertEqual(section.title, "Upcoming Calendar")
        XCTAssertEqual(section.items.first?.title, "Soon Movie")
        XCTAssertEqual(section.items.first?.metadata, "Coming this week · Movie · Add to Watchlist")
        let watchlist = try await repository.defaultList()
        let watchlistItems = try await repository.items(in: watchlist.id)
        XCTAssertEqual(watchlistItems.map(\.id), ["tmdb:movie:66"])
    }

    @MainActor
    func testHomeCardActionsAddSeedItemToLibraryAndWatchlist() async throws {
        let repository = CoreMockLibraryRepository(storedItems: [])
        let seedItem = HomeSeedItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            year: 1999,
            rating: "R",
            runtime: "2h 16m",
            genre: "Sci-Fi",
            overview: "A hacker discovers that reality is a simulated world controlled by machines.",
            quality: "2160p",
            popularityRank: 1
        )
        let viewModel = HomeViewModel(seedItems: [seedItem], libraryRepository: repository)

        await viewModel.load()
        await viewModel.addToLibrary(itemID: seedItem.id)
        await viewModel.addToWatchlist(itemID: seedItem.id)

        let libraryItems = try await repository.items()
        let watchlist = try await repository.defaultList()
        let watchlistItems = try await repository.items(in: watchlist.id)
        XCTAssertEqual(libraryItems.map(\.id), [seedItem.id])
        XCTAssertEqual(watchlistItems.map(\.id), [seedItem.id])
    }

    @MainActor
    func testLargeHomeDatasetKeepsSectionsAndPrefetchBounded() async {
        let items = (0..<1_000).map { index in
            HomeSeedItem(
                id: index.isMultiple(of: 3) ? "tmdb:tv:\(index)" : "tmdb:movie:\(index)",
                title: "Fixture \(index)",
                kind: index.isMultiple(of: 3) ? .series : .movie,
                year: 1980 + (index % 45),
                rating: index.isMultiple(of: 2) ? "PG-13" : "TV-MA",
                runtime: index.isMultiple(of: 3) ? "2 seasons" : "2h 02m",
                genre: index.isMultiple(of: 2) ? "Drama" : "Sci-Fi",
                overview: "Fixture overview",
                quality: index.isMultiple(of: 4) ? "2160p HDR" : "1080p",
                popularityRank: index,
                isFeatured: index < 50,
                isRecentlyAdded: index.isMultiple(of: 5),
                isRecommended: index.isMultiple(of: 7),
                progress: index.isMultiple(of: 9) ? 0.25 : nil,
                artworkURL: URL(string: "https://images.example.com/poster-\(index).jpg")
            )
        }
        let viewModel = HomeViewModel(seedItems: items)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.featuredItems.count, 4)
        XCTAssertLessThanOrEqual(viewModel.sections.count, 6)
        XCTAssertTrue(viewModel.sections.allSatisfy { $0.items.count <= 8 })
        XCTAssertLessThanOrEqual(viewModel.prefetchArtworkURLs.count, 24)
    }
}

private struct InMemoryWatchNextProvider: WatchNextProviderProtocol {
    let items: [WatchNextEpisode]

    func watchNextItems(progressRecords: [PlaybackProgress]) async -> [WatchNextEpisode] {
        items
    }
}

private struct HomeRecommendationFixtureService: RecommendationServiceProtocol {
    let sections: [RecommendationSection]

    func homeRecommendations(limit: Int) async throws -> [RecommendationSection] {
        sections
    }

    func recommendations(for item: MediaItem, seedSimilar: [MediaItem], limit: Int) async throws -> [MediaItem] {
        []
    }
}

private func makeLibraryItem(
    id: String,
    title: String,
    kind: MediaKind,
    year: Int,
    genres: [String]
) -> MediaItem {
    MediaItem(
        id: id,
        title: title,
        kind: kind,
        overview: "Library fixture.",
        releaseYear: year,
        posterPath: nil,
        metadata: MediaMetadata(
            tmdbId: abs(id.hashValue % 10_000),
            title: title,
            originalTitle: title,
            overview: "Library fixture.",
            year: year,
            genres: genres
        )
    )
}

private struct InMemoryNewEpisodesProvider: NewEpisodesProviderProtocol {
    let items: [NewSeriesEpisode]

    func newEpisodes() async -> [NewSeriesEpisode] {
        items
    }

    func notificationDigest(for episodes: [NewSeriesEpisode]) async -> SeriesTrackingDigest {
        SeriesTrackingDigest(items: episodes.flatMap { episode in
            [
                SeriesTrackingNotification(kind: .newEpisodeAvailable, episode: episode),
                SeriesTrackingNotification(kind: .newReleaseFound, episode: episode)
            ]
        })
    }
}

private actor InMemoryUpcomingCalendarProvider: UpcomingCalendarProviderProtocol {
    let items: [UpcomingCalendarItem]
    private var mediaByID: [String: MediaItem]

    init(items: [UpcomingCalendarItem]) {
        self.items = items
        mediaByID = Dictionary(uniqueKeysWithValues: items.map {
            (
                $0.id,
                MediaItem(
                    id: $0.id,
                    title: $0.title,
                    kind: $0.kind == .movie ? .movie : .series,
                    overview: "",
                    releaseYear: Calendar(identifier: .gregorian).component(.year, from: $0.releaseDate),
                    posterPath: $0.posterURL?.absoluteString
                )
            )
        })
    }

    func upcomingItems() async -> [UpcomingCalendarItem] {
        items
    }

    func addToWatchlist(itemID: String, libraryRepository: any LibraryRepositoryProtocol) async throws {
        guard let item = mediaByID[itemID] else { return }
        let list = try await libraryRepository.defaultList()
        try await libraryRepository.add(item, to: list.id)
    }
}

private actor InMemoryHomeProgressRepository: PlaybackProgressRepositoryProtocol {
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
