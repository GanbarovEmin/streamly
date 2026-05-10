import XCTest
import CineFlowCore
import CineFlowSources
@testable import CineFlowUI

final class SearchViewModelTests: XCTestCase {
    @MainActor
    func testSearchGroupsMediaAndTorrentResultsFromMockProvider() async {
        let viewModel = SearchViewModel(provider: MockSearchProvider(), debounceNanoseconds: 1_000_000)

        await viewModel.searchNow(query: "dune")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.queryText, "dune")
        XCTAssertEqual(viewModel.results.topMatches.map(\.title), ["Dune: Part Two"])
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["Dune: Part Two"])
        XCTAssertEqual(viewModel.results.series.map(\.title), ["Dune: Prophecy"])
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.qualityLabel), ["2160p HDR", "2160p", "1080p"])
        XCTAssertEqual(viewModel.availableSources, ["Archive", "CinemaHub", "SceneVault"])
        XCTAssertEqual(viewModel.availableAudioLanguages, ["en", "ru"])
        XCTAssertEqual(viewModel.availableSubtitleLanguages, ["az", "en", "ru"])
    }

    @MainActor
    func testDefaultSortUsesBestQualityThenHighestSeeders() async {
        let viewModel = SearchViewModel(provider: MockSearchProvider(), debounceNanoseconds: 1_000_000)

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.sortOption, .best)
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.title), [
            "The Matrix 2160p HDR REMUX",
            "The Matrix 2160p WEB-DL",
            "The Matrix 1080p BluRay"
        ])
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.seeders), [92, 410, 1200])
    }

    @MainActor
    func testFiltersConstrainTypeQualitySourceYearAndLanguages() async {
        let viewModel = SearchViewModel(provider: MockSearchProvider(), debounceNanoseconds: 1_000_000)

        viewModel.filters.mediaType = .movies
        viewModel.filters.qualities = [.ultraHD]
        viewModel.filters.requiresHDR = true
        viewModel.filters.source = "Archive"
        viewModel.filters.year = 1999
        viewModel.filters.audioLanguage = "en"
        viewModel.filters.subtitleLanguage = "ru"
        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])
        XCTAssertTrue(viewModel.results.series.isEmpty)
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.title), ["The Matrix 2160p HDR REMUX"])
    }

    @MainActor
    func testSortOptionsCanOrderBySeedersQualitySizeAndDate() async {
        let viewModel = SearchViewModel(provider: MockSearchProvider(), debounceNanoseconds: 1_000_000)
        await viewModel.searchNow(query: "matrix")

        viewModel.setSortOption(.seeders)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 1080p BluRay")

        viewModel.setSortOption(.size)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 2160p HDR REMUX")

        viewModel.setSortOption(.date)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 2160p WEB-DL")
    }

    @MainActor
    func testDebouncedQueryDoesNotBlockAndEventuallyLoads() async throws {
        let viewModel = SearchViewModel(provider: MockSearchProvider(), debounceNanoseconds: 10_000_000)

        viewModel.updateQuery("arrival")

        XCTAssertEqual(viewModel.queryText, "arrival")
        XCTAssertEqual(viewModel.state, .loading)

        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.results.topMatches.map(\.title), ["Arrival"])
    }

    @MainActor
    func testEmptyAndErrorStatesAreRepresented() async {
        let emptyViewModel = SearchViewModel(provider: MockSearchProvider(), debounceNanoseconds: 1_000_000)
        await emptyViewModel.searchNow(query: "nothing")

        XCTAssertEqual(emptyViewModel.state, .empty)

        let failingViewModel = SearchViewModel(
            provider: MockSearchProvider(shouldFail: true),
            debounceNanoseconds: 1_000_000
        )
        await failingViewModel.searchNow(query: "dune")

        XCTAssertEqual(failingViewModel.state, .failed("Search is temporarily unavailable."))
    }

    @MainActor
    func testSourceBackedProviderAggregatesTorrentSourcesWithoutChangingSearchViewModel() async throws {
        let sourceManager = SourceManager(
            providers: [
                MockTorrentSourceProvider(
                    sourceId: "archive",
                    displayName: "Archive",
                    releases: [
                        TorrentRelease(id: "archive-1080p", title: "Matrix 1080p", quality: .fullHD, seeders: 2_000),
                        TorrentRelease(id: "archive-2160p", title: "Matrix 2160p", quality: .ultraHD, seeders: 10)
                    ]
                )
            ],
            settingsStore: InMemorySourceSettingsStore(),
            credentialStore: InMemorySourceCredentialStore()
        )
        let provider = SourceBackedSearchProvider(
            mediaProvider: MockSearchProvider(),
            torrentAggregator: TorrentSearchAggregator(sourceManager: sourceManager)
        )
        let viewModel = SearchViewModel(provider: provider, debounceNanoseconds: 1_000_000)

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.results.torrentReleases.map(\.id), ["archive-2160p", "archive-1080p"])
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.source), ["Archive", "Archive"])
        XCTAssertGreaterThan(
            viewModel.results.torrentReleases[0].rankingScore,
            viewModel.results.torrentReleases[1].rankingScore
        )
    }
}
