import XCTest
import CineFlowCore
import CineFlowSources
@testable import CineFlowUI

final class SearchViewModelTests: XCTestCase {
    @MainActor
    func testSearchGroupsMediaAndTorrentResultsFromMockProvider() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

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
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.sortOption, .bestMatch)
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.title), [
            "The Matrix 2160p HDR REMUX",
            "The Matrix 2160p WEB-DL",
            "The Matrix 1080p BluRay"
        ])
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.seeders), [92, 410, 1200])
    }

    @MainActor
    func testSearchTorrentRowsExposeCompactReleaseHealth() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.results.torrentReleases.map(\.releaseHealth), [.excellent, .excellent, .excellent])
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.releaseHealthLabel), ["Excellent", "Excellent", "Excellent"])
    }

    @MainActor
    func testSearchRowsExposeReleaseComparisonMetadata() async throws {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        await viewModel.searchNow(query: "matrix")

        let release = try XCTUnwrap(viewModel.results.torrentReleases.first)
        XCTAssertEqual(release.qualityLabel, "2160p Dolby Vision")
        XCTAssertEqual(release.hdrLabel, "Dolby Vision")
        XCTAssertEqual(release.codecLabel, "HEVC")
        XCTAssertEqual(release.sizeLabel, "78.40 GB")
        XCTAssertEqual(release.source, "Archive")
        XCTAssertEqual(release.audioLanguages, ["en", "ru"])
        XCTAssertEqual(release.subtitleLanguages, ["en", "ru"])
        XCTAssertTrue(release.comparisonSummary.contains("2160p"))
        XCTAssertTrue(release.comparisonSummary.contains("HEVC"))
        XCTAssertFalse(release.rankingExplanation.isEmpty)
    }

    @MainActor
    func testFiltersConstrainTypeQualitySourceYearAndLanguages() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        viewModel.filters.mediaType = .movies
        viewModel.filters.qualities = [.ultraHD]
        viewModel.filters.requiresHDR = true
        viewModel.filters.source = "Archive"
        viewModel.filters.year = 1999
        viewModel.filters.audioLanguage = "en"
        viewModel.filters.subtitleLanguage = "ru"
        viewModel.filters.codec = .hevc
        viewModel.filters.minimumSizeBytes = 70_000_000_000
        viewModel.filters.maximumSizeBytes = 80_000_000_000
        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])
        XCTAssertTrue(viewModel.results.series.isEmpty)
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.title), ["The Matrix 2160p HDR REMUX"])
    }

    @MainActor
    func testSortOptionsCanOrderBySeedersQualitySizeAndDate() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )
        await viewModel.searchNow(query: "matrix")

        viewModel.setSortOption(.mostSeeders)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 1080p BluRay")

        viewModel.setSortOption(.smallestSize)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 1080p BluRay")

        viewModel.setSortOption(.newest)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 2160p WEB-DL")

        viewModel.setSortOption(.bestQuality)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 2160p HDR REMUX")

        viewModel.filters.audioLanguage = "ru"
        viewModel.setSortOption(.preferredLanguage)
        XCTAssertEqual(viewModel.results.torrentReleases.first?.title, "The Matrix 1080p BluRay")
    }

    @MainActor
    func testRecentSearchesAndDefaultSortPersistLocally() async {
        let preferences = InMemorySearchPreferencesStore()
        let firstViewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: preferences
        )

        await firstViewModel.searchNow(query: " matrix ")
        await firstViewModel.searchNow(query: "dune")
        firstViewModel.setSortOption(.newest)

        XCTAssertEqual(firstViewModel.recentSearches, ["dune", "matrix"])
        XCTAssertEqual(preferences.recentSearches, ["dune", "matrix"])
        XCTAssertEqual(preferences.sortOption, .newest)

        let secondViewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: preferences
        )

        XCTAssertEqual(secondViewModel.recentSearches, ["dune", "matrix"])
        XCTAssertEqual(secondViewModel.sortOption, .newest)

        secondViewModel.clearRecentSearches()
        XCTAssertTrue(secondViewModel.recentSearches.isEmpty)
        XCTAssertTrue(preferences.recentSearches.isEmpty)

        await secondViewModel.runRecentSearch("matrix")
        XCTAssertEqual(secondViewModel.queryText, "matrix")
        XCTAssertEqual(secondViewModel.recentSearches, ["matrix"])
    }

    @MainActor
    func testEmptySearchSuggestionsShowRecentTrendingAndQuickFilters() {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore(recentSearches: ["matrix"])
        )

        XCTAssertEqual(viewModel.searchSuggestions.first?.kind, .recent)
        XCTAssertEqual(viewModel.searchSuggestions.first?.query, "matrix")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .trending && $0.title == "Dune: Part Two" })
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.quickFilter == .movies })
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.quickFilter == .series })
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.quickFilter == .ultraHD })
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.quickFilter == .russianAudio })
    }

    @MainActor
    func testTypingSuggestionsCoverTitlesPeopleGenresYearsAndTypoCorrection() {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore(recentSearches: ["dune"])
        )

        viewModel.updateQuery("матри")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .localizedTitle && $0.title == "The Matrix" })

        viewModel.updateQuery("wachowski")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .director && $0.title == "The Matrix" })

        viewModel.updateQuery("keanu")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .actor && $0.title == "The Matrix" })

        viewModel.updateQuery("sci")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .genre && $0.title == "Sci-Fi" })

        viewModel.updateQuery("1999")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .year && $0.query == "1999" })

        viewModel.updateQuery("matrx")
        XCTAssertTrue(viewModel.searchSuggestions.contains { $0.kind == .typoCorrection && $0.query == "The Matrix" })
    }

    @MainActor
    func testSearchMatchesRussianTitleOriginalTitlePeopleGenreYearAndTypoTolerance() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        await viewModel.searchNow(query: "Матрица")
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])

        await viewModel.searchNow(query: "Keanu Reeves")
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])

        await viewModel.searchNow(query: "Wachowski")
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])

        await viewModel.searchNow(query: "Sci-Fi")
        XCTAssertTrue(viewModel.results.movies.map(\.title).contains("Dune: Part Two"))
        XCTAssertTrue(viewModel.results.series.map(\.title).contains("Dune: Prophecy"))

        await viewModel.searchNow(query: "1999")
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])

        await viewModel.searchNow(query: "matrx")
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["The Matrix"])
    }

    @MainActor
    func testQuickFilterSuggestionsApplySearchFilters() async {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        let movies = try! XCTUnwrap(viewModel.searchSuggestions.first { $0.quickFilter == .movies })
        await viewModel.selectSuggestion(movies)
        XCTAssertEqual(viewModel.filters.mediaType, .movies)

        let ultraHD = try! XCTUnwrap(viewModel.searchSuggestions.first { $0.quickFilter == .ultraHD })
        await viewModel.selectSuggestion(ultraHD)
        XCTAssertTrue(viewModel.filters.qualities.contains(.ultraHD))

        let russianAudio = try! XCTUnwrap(viewModel.searchSuggestions.first { $0.quickFilter == .russianAudio })
        await viewModel.selectSuggestion(russianAudio)
        XCTAssertEqual(viewModel.filters.audioLanguage, "ru")
    }

    @MainActor
    func testDebouncedQueryDoesNotBlockAndEventuallyLoads() async throws {
        let viewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 10_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        viewModel.updateQuery("arrival")

        XCTAssertEqual(viewModel.queryText, "arrival")
        XCTAssertEqual(viewModel.state, .loading)

        for _ in 0..<50 where viewModel.state != .loaded {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.results.topMatches.map(\.title), ["Arrival"])
    }

    @MainActor
    func testSlowSearchResponseDoesNotOverwriteNewerQuery() async throws {
        let viewModel = SearchViewModel(
            provider: DelayedSearchProvider(),
            debounceNanoseconds: 0,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        let slowSearch = Task { await viewModel.searchNow(query: "slow") }
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.searchNow(query: "fast")
        await slowSearch.value

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.queryText, "fast")
        XCTAssertEqual(viewModel.results.topMatches.map(\.title), ["Fast"])
    }

    @MainActor
    func testLargeSearchResponseBuildsLoadedStateWithRankedReleases() async {
        let viewModel = SearchViewModel(
            provider: LargeSearchProvider(),
            debounceNanoseconds: 0,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.results.movies.count, 500)
        XCTAssertEqual(viewModel.results.series.count, 500)
        XCTAssertEqual(viewModel.results.torrentReleases.count, 1_200)
        XCTAssertFalse(viewModel.results.torrentReleases.prefix(10).contains { $0.rankingReasons.isEmpty })
    }

    @MainActor
    func testEmptyAndErrorStatesAreRepresented() async {
        let emptyViewModel = SearchViewModel(
            provider: MockSearchProvider(),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )
        await emptyViewModel.searchNow(query: "nothing")

        XCTAssertEqual(emptyViewModel.state, .empty)

        let failingViewModel = SearchViewModel(
            provider: MockSearchProvider(shouldFail: true),
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
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
                        TorrentRelease(
                            id: "archive-2160p",
                            sourceId: "archive",
                            sourceName: "Archive",
                            title: "Matrix 2160p",
                            magnetURI: "magnet:?xt=urn:btih:archive2160p",
                            quality: .ultraHD,
                            seeders: 10
                        )
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
        let viewModel = SearchViewModel(
            provider: provider,
            debounceNanoseconds: 1_000_000,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        await viewModel.searchNow(query: "matrix")

        XCTAssertEqual(viewModel.results.torrentReleases.map(\.id), ["archive-2160p", "archive-1080p"])
        XCTAssertEqual(viewModel.results.torrentReleases.map(\.source), ["Archive", "Archive"])
        XCTAssertEqual(viewModel.results.torrentReleases.first?.torrentRelease.magnetURI, "magnet:?xt=urn:btih:archive2160p")
        XCTAssertGreaterThan(
            viewModel.results.torrentReleases[0].rankingScore,
            viewModel.results.torrentReleases[1].rankingScore
        )
    }
}

private struct DelayedSearchProvider: SearchProviderProtocol {
    func search(query: String) async throws -> SearchProviderResponse {
        if query == "slow" {
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        let title = query.prefix(1).uppercased() + String(query.dropFirst())
        let item = MediaItem(
            id: "test:\(query)",
            title: title,
            kind: .movie,
            overview: "Fixture",
            releaseYear: 2024,
            posterPath: nil
        )
        return SearchProviderResponse(media: [SearchMediaResult(mediaItem: item)], releases: [])
    }
}

private struct LargeSearchProvider: SearchProviderProtocol {
    func search(query: String) async throws -> SearchProviderResponse {
        let media = (0..<1_000).map { index in
            SearchMediaResult(mediaItem: MediaItem(
                id: index.isMultiple(of: 2) ? "tmdb:movie:\(index)" : "tmdb:tv:\(index)",
                title: "Matrix Fixture \(index)",
                kind: index.isMultiple(of: 2) ? .movie : .series,
                overview: "Fixture",
                releaseYear: 1980 + (index % 45),
                posterPath: nil
            ))
        }
        let releases = (0..<1_200).map(Self.release)
        return SearchProviderResponse(media: media, releases: releases)
    }

    private static func release(index: Int) -> SearchTorrentRelease {
        SearchTorrentRelease(
            id: "release-\(index)",
            mediaID: "tmdb:movie:\(index % 500)",
            mediaTitle: "Matrix Fixture \(index)",
            mediaKind: .movie,
            mediaYear: 1980 + (index % 45),
            title: "Matrix \(index) \(index.isMultiple(of: 3) ? "2160p" : "1080p")",
            source: index.isMultiple(of: 2) ? "Archive" : "Torrentio",
            magnetURI: "magnet:?xt=urn:btih:fixture\(index)",
            quality: index.isMultiple(of: 3) ? .ultraHD : .fullHD,
            codec: index.isMultiple(of: 4) ? .hevc : .h264,
            hdrFormat: index.isMultiple(of: 5) ? .hdr10 : HDRFormat.none,
            isHDR: index.isMultiple(of: 5),
            seeders: 1_200 - index,
            leechers: index % 20,
            sizeBytes: Int64(2_000_000_000 + index),
            uploadDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            audioLanguages: ["en", "ru"],
            subtitleLanguages: ["en", "ru"]
        )
    }
}
