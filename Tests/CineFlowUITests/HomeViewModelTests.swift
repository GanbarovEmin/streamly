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
            [.watchNext, .continueWatching, .popularMovies, .popularSeries, .recentlyAdded, .recommended, .topQuality]
        )
        XCTAssertEqual(viewModel.sections.map(\.title), [
            "Watch Next",
            "Continue Watching",
            "Popular - Movies",
            "Popular - Series",
            "Recently Added to Library",
            "Recommended",
            "Top Quality"
        ])
        XCTAssertEqual(viewModel.sections[0].cardStyle, .landscape)
        XCTAssertEqual(viewModel.sections[1].cardStyle, .landscape)
        XCTAssertTrue(viewModel.sections[1].items.allSatisfy { $0.progress != nil })
        XCTAssertTrue(viewModel.sections.dropFirst(2).allSatisfy { $0.cardStyle == .poster })
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
    func testWatchNextSectionUsesEpisodeLevelSeriesProgressAndHidesCompletedSeries() async throws {
        let series = MediaItem(
            id: "tmdb:tv:1399",
            title: "Game of Thrones",
            kind: .series,
            overview: "Noble families fight for control.",
            releaseYear: 2011,
            posterPath: nil
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
            seedItems: HomeSeedLibrary.developmentItems,
            progressRepository: progressRepository,
            libraryRepository: CoreMockLibraryRepository(storedItems: [series]),
            watchNextProvider: provider
        )

        await viewModel.load()

        let watchNext = try XCTUnwrap(viewModel.sections.first { $0.kind == .watchNext })
        XCTAssertEqual(watchNext.items.first?.id, "got-s2-e1")
        XCTAssertEqual(watchNext.items.first?.title, "Game of Thrones")
        XCTAssertEqual(watchNext.items.first?.metadata, "Continue S02E01 · The North Remembers")

        let continueWatching = try XCTUnwrap(viewModel.sections.first { $0.kind == .continueWatching })
        XCTAssertTrue(continueWatching.items.isEmpty)
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
        XCTAssertEqual(viewModel.sections.count, 7)
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
