import CineFlowCore
@testable import CineFlowUI
import XCTest

final class RatingAggregationTests: XCTestCase {
    @MainActor
    func testMovieRatingSummaryShowsAvailableSourcesUserRatingAndQualityBadges() async {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = MovieDetailViewModel(
            mediaID: "tmdb:movie:603",
            provider: MockMovieDetailProvider(),
            libraryRepository: repository
        )

        await viewModel.load()
        viewModel.setUserRating(9)

        XCTAssertEqual(viewModel.ratingSummary.sources.map(\.source), [.tmdb, .imdb, .user])
        XCTAssertEqual(viewModel.ratingSummary.sources.map(\.label), ["TMDB 8.2", "IMDb 8.7", "You 9/10"])
        XCTAssertEqual(viewModel.ratingSummary.badges.map(\.title), ["Highly Rated", "Classic"])
        XCTAssertFalse(viewModel.ratingSummary.sources.contains { $0.source == .trakt })
    }

    @MainActor
    func testMissingRatingSourcesAreOmittedAndMixedNewBadgesRemainReadable() async {
        let viewModel = MovieDetailViewModel(mediaID: "movie:mixed-new", provider: MixedNewMovieProvider())

        await viewModel.load()

        XCTAssertEqual(viewModel.ratingSummary.sources.map(\.source), [.tmdb])
        XCTAssertEqual(viewModel.ratingSummary.sources.map(\.label), ["TMDB 5.8"])
        XCTAssertEqual(viewModel.ratingSummary.badges.map(\.title), ["Mixed", "New"])
    }

    @MainActor
    func testSeriesRatingSummaryIncludesStoredUserRating() async {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = SeriesDetailViewModel(
            seriesID: "tmdb:tv:1399",
            provider: MockSeriesDetailProvider(),
            libraryRepository: repository
        )

        await viewModel.load()
        viewModel.setUserRating(8)

        XCTAssertEqual(viewModel.ratingSummary.sources.map(\.label), ["TMDB 8.4", "You 8/10"])
        XCTAssertEqual(viewModel.ratingSummary.badges.map(\.title), ["Highly Rated"])
    }

    @MainActor
    func testSearchCanFilterAndSortMediaByRating() async {
        let viewModel = SearchViewModel(
            provider: RatingSearchProvider(),
            debounceNanoseconds: 0,
            preferencesStore: InMemorySearchPreferencesStore()
        )

        viewModel.filters.minimumRating = 7.0
        await viewModel.searchNow(query: "ratings")

        XCTAssertEqual(viewModel.results.movies.count, 2)
        XCTAssertFalse(viewModel.results.movies.map(\.title).contains("Mixed Movie"))
        XCTAssertFalse(viewModel.results.movies.map(\.title).contains("Unrated Movie"))

        viewModel.setSortOption(.rating)
        XCTAssertEqual(viewModel.results.topMatches.map(\.title), ["Highly Rated Movie"])
        XCTAssertEqual(viewModel.results.movies.map(\.title), ["Highly Rated Movie", "Solid Movie"])
        XCTAssertEqual(viewModel.results.movies.map(\.ratingScore), [8.8, 7.1])
    }
}

private struct MixedNewMovieProvider: MovieDetailProviderProtocol {
    func movieDetail(id: String) async throws -> MovieDetailResponse? {
        MovieDetailResponse(
            movie: MovieDetail(
                id: id,
                title: "New Mixed Movie",
                originalTitle: "New Mixed Movie",
                year: 2026,
                runtime: "1h 44m",
                genres: ["Drama"],
                tmdbRating: "5.8",
                imdbRating: "",
                overview: "A recent film with divided ratings.",
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

private struct RatingSearchProvider: SearchProviderProtocol {
    func search(query: String) async throws -> SearchProviderResponse {
        SearchProviderResponse(
            media: [
                media(id: "tmdb:movie:1", title: "Unrated Movie", rating: nil),
                media(id: "tmdb:movie:2", title: "Solid Movie", rating: 7.1),
                media(id: "tmdb:movie:3", title: "Highly Rated Movie", rating: 8.8),
                media(id: "tmdb:movie:4", title: "Mixed Movie", rating: 5.9)
            ],
            releases: []
        )
    }

    private func media(id: String, title: String, rating: Double?) -> SearchMediaResult {
        SearchMediaResult(mediaItem: MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "Fixture",
            releaseYear: 2024,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
                title: title,
                originalTitle: title,
                overview: "Fixture",
                year: 2024,
                rating: rating
            )
        ))
    }
}
