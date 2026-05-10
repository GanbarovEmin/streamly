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
            [.continueWatching, .popularMovies, .popularSeries, .recentlyAdded, .recommended, .topQuality]
        )
        XCTAssertEqual(viewModel.sections.map(\.title), [
            "Continue Watching",
            "Popular - Movies",
            "Popular - Series",
            "Recently Added to Library",
            "Recommended",
            "Top Quality"
        ])
        XCTAssertEqual(viewModel.sections.first?.cardStyle, .landscape)
        XCTAssertTrue(viewModel.sections.first?.items.allSatisfy { $0.progress != nil } == true)
        XCTAssertTrue(viewModel.sections.dropFirst().allSatisfy { $0.cardStyle == .poster })
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
