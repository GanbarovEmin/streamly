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
}
