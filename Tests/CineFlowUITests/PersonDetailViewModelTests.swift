import CineFlowCore
import CineFlowUI
import XCTest

final class PersonDetailViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsPersonProfileFilmographyAndAvailability() async throws {
        let repository = MovieDetailInMemoryLibraryRepository()
        try await repository.add(Self.media(id: "tmdb:movie:245891", title: "John Wick", year: 2014, rating: 7.4))
        let viewModel = PersonDetailViewModel(
            person: PersonRoutePayload(id: "keanu", name: "Keanu Reeves", role: "Neo"),
            provider: MockPersonDetailProvider(),
            libraryRepository: repository
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.detail?.name, "Keanu Reeves")
        XCTAssertEqual(viewModel.detail?.shortBio, "Known for focused action roles and modern science-fiction classics.")
        XCTAssertEqual(viewModel.knownFor.map(\.title), ["The Matrix", "John Wick"])
        XCTAssertEqual(viewModel.visibleFilmography.map(\.mediaItem.id), [
            "tmdb:movie:603",
            "tmdb:movie:245891",
            "tmdb:movie:624860"
        ])
        XCTAssertTrue(viewModel.visibleFilmography[0].isAvailableInSources)
        XCTAssertTrue(viewModel.visibleFilmography[1].isAvailableInLibrary)
        XCTAssertFalse(viewModel.visibleFilmography[2].isAvailable)
    }

    @MainActor
    func testFilmographySortFilterAndWatchlistActionUseLocalRepository() async throws {
        let repository = MovieDetailInMemoryLibraryRepository()
        let viewModel = PersonDetailViewModel(
            person: PersonRoutePayload(id: "keanu", name: "Keanu Reeves", role: "Neo"),
            provider: MockPersonDetailProvider(),
            libraryRepository: repository
        )
        await viewModel.load()

        viewModel.sort = .year
        XCTAssertEqual(viewModel.visibleFilmography.map(\.mediaItem.id), [
            "tmdb:movie:624860",
            "tmdb:movie:245891",
            "tmdb:movie:603"
        ])

        viewModel.sort = .rating
        XCTAssertEqual(viewModel.visibleFilmography.map(\.mediaItem.id), [
            "tmdb:movie:603",
            "tmdb:movie:245891",
            "tmdb:movie:624860"
        ])

        viewModel.availabilityFilter = .available
        XCTAssertEqual(viewModel.visibleFilmography.map(\.mediaItem.id), ["tmdb:movie:603"])

        try await viewModel.addToWatchlist(viewModel.visibleFilmography[0].mediaItem)
        let watchlist = try await repository.defaultList()
        let watchlistItems = try await repository.items(in: watchlist.id)
        XCTAssertEqual(watchlistItems.map(\.id), ["tmdb:movie:603"])
    }

    @MainActor
    func testFallbackPresentationKeepsPersonDetailReadableWithoutPhotoBioOrFilmography() async {
        let viewModel = PersonDetailViewModel(
            person: PersonRoutePayload(id: "unknown", name: "Unknown Person", role: nil),
            provider: SparsePersonDetailProvider()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.photoFallbackInitials, "UP")
        XCTAssertEqual(viewModel.bioFallbackTitle, "Биография пока не загружена")
        XCTAssertEqual(viewModel.filmographyFallbackTitle, "Фильмография пока недоступна")
        XCTAssertTrue(viewModel.visibleFilmography.isEmpty)
    }

    @MainActor
    func testPersonRoutePayloadKeepsCastNavigationStable() {
        let route = AppRoute.personDetail(PersonRoutePayload(
            id: "keanu",
            name: "Keanu Reeves",
            role: "Neo",
            profileURL: URL(string: "https://image.tmdb.org/t/p/w185/keanu.jpg")
        ))

        XCTAssertEqual(route.id, "personDetail:keanu")
        XCTAssertFalse(route.isSidebarRoute)
    }

    private static func media(id: String, title: String, year: Int, rating: Double) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "\(title) overview",
            releaseYear: year,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: Int(id.split(separator: ":").last ?? "0") ?? 0,
                title: title,
                originalTitle: title,
                overview: "\(title) overview",
                year: year,
                rating: rating
            )
        )
    }
}

private struct SparsePersonDetailProvider: PersonDetailProviderProtocol {
    func personDetail(for person: PersonRoutePayload) async throws -> PersonDetailResponse? {
        PersonDetailResponse(
            detail: PersonDetail(
                id: person.id,
                name: person.name,
                kind: .actor,
                role: person.role,
                photoURL: nil,
                shortBio: "",
                knownFor: []
            ),
            filmography: []
        )
    }
}
