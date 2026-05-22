import CineFlowCore
import XCTest
@testable import CineFlowUI

final class CollectionDiscoveryTests: XCTestCase {
    func testAutomaticCollectionsGroupFranchisesAwardsTopRatedAndQuality() {
        let collections = CollectionDiscoveryBuilder.automaticCollections(
            candidates: Self.fixtureItems(),
            libraryIDs: ["tmdb:movie:155"],
            watchlistIDs: ["tmdb:movie:603"]
        )

        let marvel = collections.first { $0.id == "automatic-marvel" }
        XCTAssertEqual(marvel?.items.map(\.mediaItem.displayTitle), ["Iron Man"])

        let lotr = collections.first { $0.id == "automatic-lord-of-the-rings" }
        XCTAssertEqual(lotr?.items.map(\.mediaItem.displayTitle), ["The Lord of the Rings: The Fellowship of the Ring"])

        let oscars = collections.first { $0.id == "automatic-oscar-winners" }
        XCTAssertTrue(oscars?.items.contains { $0.mediaItem.displayTitle == "Oppenheimer" } == true)

        let topRated = collections.first { $0.id == "automatic-imdb-top-rated" }
        XCTAssertEqual(topRated?.visibleItems.map(\.mediaItem.displayTitle), ["The Dark Knight", "The Matrix"])

        let quality = collections.first { $0.id == "automatic-4k-hdr" }
        XCTAssertEqual(quality?.items.map(\.mediaItem.displayTitle), ["The Matrix"])
        XCTAssertEqual(quality?.items.first?.availabilityBadges, ["Watchlist", "4K HDR"])
    }

    func testCollectionDetailSortsByReleaseYearAndStoryOrder() {
        var collection = CollectionDiscoveryBuilder.automaticCollections(
            candidates: Self.starWarsFixture(),
            libraryIDs: [],
            watchlistIDs: []
        ).first { $0.id == "automatic-star-wars" }!

        collection.sort = .releaseYear
        XCTAssertEqual(collection.visibleItems.map(\.mediaItem.displayTitle), [
            "Star Wars: A New Hope",
            "Star Wars: The Phantom Menace",
            "Star Wars: Revenge of the Sith"
        ])

        collection.sort = .storyOrder
        XCTAssertEqual(collection.visibleItems.map(\.mediaItem.displayTitle), [
            "Star Wars: The Phantom Menace",
            "Star Wars: Revenge of the Sith",
            "Star Wars: A New Hope"
        ])
    }

    @MainActor
    func testCollectionDetailViewModelAddsVisibleItemsToWatchlistWithoutUserCollectionMutation() async throws {
        let repository = CoreMockLibraryRepository(storedItems: [])
        let provider = InMemoryCollectionProvider(collections: [
            MediaCollection(
                id: "user-weekend",
                title: "Weekend",
                description: "Local picks",
                kind: .userCreated,
                items: Self.fixtureItems().prefix(2).enumerated().map { index, item in
                    CollectionMediaItem(mediaItem: item, storyOrder: index + 1)
                }
            )
        ])
        let viewModel = CollectionDetailViewModel(
            collectionID: "user-weekend",
            provider: provider,
            libraryRepository: repository
        )

        await viewModel.load()
        try await viewModel.addVisibleItemsToWatchlist()

        let watchlist = try await repository.defaultList()
        let items = try await repository.items(in: watchlist.id)
        XCTAssertEqual(Set(items.map(\.id)), Set(["tmdb:movie:603", "tmdb:movie:155"]))
        XCTAssertEqual(viewModel.collection?.kind, .userCreated)
    }

    @MainActor
    func testHomeViewModelShowsCollectionsRowAndCollectionRouteIsDeepLink() async throws {
        var settings = AppSettings()
        settings.home.setSection("collections", isEnabled: true)
        let viewModel = HomeViewModel(
            seedItems: HomeSeedLibrary.developmentItems,
            settingsRepository: CoreMockSettingsRepository(settings: settings)
        )

        await viewModel.load()

        let section = try XCTUnwrap(viewModel.sections.first { $0.kind == .collections })
        XCTAssertEqual(section.title, "Collections")
        XCTAssertFalse(section.items.isEmpty)

        let route = AppRoute.collectionDetail(id: "automatic-4k-hdr")
        XCTAssertFalse(route.isSidebarRoute)
        XCTAssertEqual(route.id, "collectionDetail:automatic-4k-hdr")
    }

    @MainActor
    func testCollectionDetailFallbackKeepsEmptyCollectionReadable() async {
        let provider = InMemoryCollectionProvider(collections: [
            MediaCollection(
                id: "automatic-empty",
                title: "Missing Franchise",
                description: "No local matches yet.",
                kind: .automatic(.franchise),
                items: []
            )
        ])
        let viewModel = CollectionDetailViewModel(collectionID: "automatic-empty", provider: provider)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.emptyFallbackTitle, "No matching titles yet")
        XCTAssertTrue(viewModel.posterCollageItems.isEmpty)
    }

    private static func fixtureItems() -> [MediaItem] {
        [
            media(id: "tmdb:movie:603", title: "The Matrix", year: 1999, rating: 8.7, release: .ultraHD, hdr: .hdr10),
            media(id: "tmdb:movie:155", title: "The Dark Knight", year: 2008, rating: 9.0),
            media(id: "tmdb:movie:1726", title: "Iron Man", year: 2008, rating: 7.9),
            media(id: "tmdb:movie:120", title: "The Lord of the Rings: The Fellowship of the Ring", year: 2001, rating: 8.4),
            media(id: "tmdb:movie:872585", title: "Oppenheimer", year: 2023, rating: 8.4)
        ]
    }

    private static func starWarsFixture() -> [MediaItem] {
        [
            media(id: "tmdb:movie:11", title: "Star Wars: A New Hope", year: 1977, rating: 8.6),
            media(id: "tmdb:movie:1893", title: "Star Wars: The Phantom Menace", year: 1999, rating: 6.5),
            media(id: "tmdb:movie:1895", title: "Star Wars: Revenge of the Sith", year: 2005, rating: 7.6)
        ]
    }

    private static func media(
        id: String,
        title: String,
        year: Int,
        rating: Double,
        release: ReleaseQuality? = nil,
        hdr: HDRFormat = .none
    ) -> MediaItem {
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
            ),
            torrentReleases: release.map {
                [
                    TorrentRelease(
                        id: "\(id)-release",
                        sourceName: "Torrentio",
                        title: "\(title) \($0.qualityLabel)",
                        quality: $0,
                        hdr: hdr,
                        seeders: 120
                    )
                ]
            } ?? []
        )
    }
}

private struct InMemoryCollectionProvider: CollectionDiscoveryProviderProtocol {
    let collections: [MediaCollection]

    func collections() async -> [MediaCollection] {
        collections
    }

    func collection(id: String) async -> MediaCollection? {
        collections.first { $0.id == id }
    }
}
