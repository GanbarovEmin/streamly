import CineFlowCore
import XCTest
@testable import CineFlowUI

final class MediaCatalogViewModelTests: XCTestCase {
    @MainActor
    func testMoviesCatalogLoadsUniqueLiveItemsAndCards() async throws {
        let posterURL = try XCTUnwrap(URL(string: "https://images.example.com/dune.jpg"))
        let dune = Self.item(
            id: "imdb:movie:tt15239678",
            title: "Dune: Part Two",
            kind: .movie,
            posterURL: posterURL,
            genres: ["Sci-Fi", "Adventure"],
            rating: 8.5
        )
        let matrix = Self.item(id: "imdb:movie:tt0133093", title: "The Matrix", kind: .movie)
        let service = CatalogFixtureMetadataService(
            popularMovies: [dune, matrix],
            popularSeries: [],
            trending: [dune, Self.item(id: "imdb:series:tt0944947", title: "Game of Thrones", kind: .series)]
        )
        let viewModel = MediaCatalogViewModel(kind: .movies, metadataService: service)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.items.map(\.id), ["imdb:movie:tt15239678", "imdb:movie:tt0133093"])
        XCTAssertEqual(viewModel.cards.map(\.title), ["Dune: Part Two", "The Matrix"])
        XCTAssertEqual(viewModel.cards.first?.artworkURL, posterURL)
        XCTAssertFalse(viewModel.cards.map(\.title).contains("Blade Runner 2049"))
    }

    @MainActor
    func testSeriesCatalogFiltersTrendingToSeriesOnlyAndSearchesVisibleItems() async {
        let throne = Self.item(id: "imdb:series:tt0944947", title: "Game of Thrones", kind: .series, genres: ["Drama"])
        let severance = Self.item(id: "imdb:series:tt11280740", title: "Severance", kind: .series, genres: ["Mystery"])
        let service = CatalogFixtureMetadataService(
            popularMovies: [],
            popularSeries: [throne],
            trending: [severance, Self.item(id: "imdb:movie:tt0133093", title: "The Matrix", kind: .movie)]
        )
        let viewModel = MediaCatalogViewModel(kind: .series, metadataService: service)

        await viewModel.load()
        viewModel.searchQuery = "mystery"

        XCTAssertEqual(viewModel.items.map(\.title), ["Game of Thrones", "Severance"])
        XCTAssertEqual(viewModel.visibleItems.map(\.title), ["Severance"])
    }

    private static func item(
        id: String,
        title: String,
        kind: MediaKind,
        posterURL: URL? = nil,
        genres: [String] = [],
        rating: Double? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: kind,
            overview: "\(title) overview",
            releaseYear: 2026,
            posterPath: posterURL?.absoluteString,
            metadata: MediaMetadata(
                tmdbId: abs(id.hashValue),
                title: title,
                originalTitle: title,
                overview: "\(title) overview",
                year: 2026,
                genres: genres,
                rating: rating,
                posterURL: posterURL
            )
        )
    }
}

private struct CatalogFixtureMetadataService: MetadataServiceProtocol {
    let popularMovieItems: [MediaItem]
    let popularSeriesItems: [MediaItem]
    let trendingItems: [MediaItem]

    init(popularMovies: [MediaItem], popularSeries: [MediaItem], trending: [MediaItem]) {
        self.popularMovieItems = popularMovies
        self.popularSeriesItems = popularSeries
        self.trendingItems = trending
    }

    func search(query: String) async throws -> [MediaItem] {
        []
    }

    func popularMovies() async throws -> [MediaItem] {
        popularMovieItems
    }

    func popularSeries() async throws -> [MediaItem] {
        popularSeriesItems
    }

    func trending() async throws -> [MediaItem] {
        trendingItems
    }
}
