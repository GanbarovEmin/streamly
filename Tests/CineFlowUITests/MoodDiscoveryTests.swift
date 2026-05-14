import CineFlowCore
import XCTest
@testable import CineFlowUI

final class MoodDiscoveryTests: XCTestCase {
    func testMoodFiltersReturnExplainableResultsFromLibraryMetadataAndReleaseQuality() {
        let engine = MoodDiscoveryEngine()
        let candidates = makeMoodCandidates()

        let highRated = engine.recommendations(
            from: candidates,
            filter: .highRated,
            tasteProfile: MoodDiscoveryTasteProfile(preferredGenres: ["Drama"], libraryIDs: ["tmdb:movie:1"])
        )
        XCTAssertEqual(highRated.first?.title, "Quiet Arrival")
        XCTAssertTrue(highRated.first?.whySuggested.contains("TMDB 8.6") == true)
        XCTAssertTrue(highRated.first?.whySuggested.contains("Drama") == true)

        let ultraHD = engine.recommendations(from: candidates, filter: .fourKHDR)
        XCTAssertEqual(ultraHD.map(\.title), ["Quiet Arrival", "Epic Planet"])
        XCTAssertTrue(ultraHD.allSatisfy { $0.whySuggested.contains("4K/HDR") })
    }

    func testRuntimeAndGenreMoodFiltersStayFocused() {
        let engine = MoodDiscoveryEngine()
        let candidates = makeMoodCandidates()

        let quickMovie = engine.recommendations(from: candidates, filter: .under90Minutes)
        XCTAssertEqual(quickMovie.map(\.title), ["Short Laugh"])
        XCTAssertTrue(quickMovie.first?.whySuggested.contains("under 90 minutes") == true)

        let backgroundSeries = engine.recommendations(from: candidates, filter: .backgroundSeries)
        XCTAssertEqual(backgroundSeries.map(\.title), ["Background Office"])
        XCTAssertTrue(backgroundSeries.first?.whySuggested.contains("series on the background") == true)

        let comedy = engine.recommendations(from: candidates, filter: .comedy)
        XCTAssertEqual(Set(comedy.map(\.title)), Set(["Short Laugh", "Background Office"]))
    }

    func testPickForMeUsesTasteSignalsButWorksWithLocalMockData() {
        let engine = MoodDiscoveryEngine()
        let pick = engine.pickForMe(
            from: makeMoodCandidates(),
            tasteProfile: MoodDiscoveryTasteProfile(
                preferredGenres: ["Drama", "Sci-Fi"],
                libraryIDs: ["tmdb:movie:1"],
                continueWatchingIDs: ["tmdb:series:4"]
            )
        )

        XCTAssertEqual(pick?.title, "Quiet Arrival")
        XCTAssertTrue(pick?.whySuggested.contains("matches your taste") == true)
        XCTAssertTrue(pick?.whySuggested.contains("from your library") == true)
    }

    @MainActor
    func testHomeViewModelLoadsWhatToWatchTodaySection() async throws {
        let viewModel = HomeViewModel(seedItems: HomeSeedLibrary.developmentItems)

        await viewModel.load()

        let moodSection = try XCTUnwrap(viewModel.sections.first { $0.kind == .moodDiscovery })
        XCTAssertEqual(moodSection.title, "What to Watch Today?")
        XCTAssertFalse(moodSection.items.isEmpty)
        XCTAssertEqual(viewModel.moodFilters.first, .lightEvening)
        XCTAssertNotNil(viewModel.moodPick)
        XCTAssertTrue(moodSection.items.first?.metadata.contains("Why:") == true)
    }

    @MainActor
    func testSearchMoodFiltersApplyFastDiscoveryConstraints() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        XCTAssertTrue(viewModel.moodFilters.contains(.fourKHDR))

        await viewModel.applyMoodFilter(.fourKHDR)
        XCTAssertTrue(viewModel.filters.qualities.contains(.ultraHD))
        XCTAssertTrue(viewModel.filters.requiresHDR)
        XCTAssertEqual(viewModel.queryText, "4K HDR")

        await viewModel.applyMoodFilter(.comedy)
        XCTAssertEqual(viewModel.queryText, "Comedy")
        XCTAssertEqual(viewModel.filters.mediaType, .all)

        await viewModel.applyMoodFilter(.under90Minutes)
        XCTAssertEqual(viewModel.filters.mediaType, .movies)
        XCTAssertEqual(viewModel.queryText, "under 90 minutes")
    }
}

private func makeMoodCandidates() -> [MoodDiscoveryCandidate] {
    [
        MoodDiscoveryCandidate(
            id: "tmdb:movie:1",
            title: "Quiet Arrival",
            kind: .movie,
            year: 2016,
            overview: "Thoughtful sci-fi drama.",
            genres: ["Drama", "Sci-Fi"],
            runtimeMinutes: 116,
            ratingScore: 8.6,
            qualityLabel: "2160p HDR",
            artworkURL: nil,
            source: .library
        ),
        MoodDiscoveryCandidate(
            id: "tmdb:movie:2",
            title: "Short Laugh",
            kind: .movie,
            year: 2024,
            overview: "Fast comedy.",
            genres: ["Comedy"],
            runtimeMinutes: 82,
            ratingScore: 7.1,
            qualityLabel: "1080p",
            artworkURL: nil,
            source: .metadata
        ),
        MoodDiscoveryCandidate(
            id: "tmdb:movie:3",
            title: "Epic Planet",
            kind: .movie,
            year: 2021,
            overview: "Large scale adventure.",
            genres: ["Action", "Adventure"],
            runtimeMinutes: 168,
            ratingScore: 7.8,
            qualityLabel: "2160p HDR",
            artworkURL: nil,
            source: .metadata
        ),
        MoodDiscoveryCandidate(
            id: "tmdb:series:4",
            title: "Background Office",
            kind: .series,
            year: 2020,
            overview: "Low stakes workplace comedy.",
            genres: ["Comedy"],
            runtimeMinutes: 30,
            ratingScore: 7.9,
            qualityLabel: "1080p",
            artworkURL: nil,
            source: .library
        )
    ]
}
