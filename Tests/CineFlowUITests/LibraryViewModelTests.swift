import CineFlowCore
import XCTest
@testable import CineFlowUI

final class LibraryViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsLibrarySectionsFromRepository() async throws {
        let repository = InMemoryLibraryRepository(items: [
            Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999),
            Self.series(id: "tmdb:tv:1399", title: "Game of Thrones", year: 2011)
        ])
        try await repository.addFavorite(Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999))
        try await repository.markWatched(Self.series(id: "tmdb:tv:1399", title: "Game of Thrones", year: 2011), positionSeconds: 120)
        try await repository.setRating(Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999), rating: 9)

        let viewModel = LibraryViewModel(repository: repository)
        await viewModel.load()

        XCTAssertEqual(viewModel.summary.favoriteCount, 1)
        XCTAssertEqual(viewModel.summary.movieCount, 1)
        XCTAssertEqual(viewModel.summary.seriesCount, 1)
        XCTAssertEqual(viewModel.summary.watchedCount, 1)
        XCTAssertEqual(viewModel.summary.ratingCount, 1)

        viewModel.selectSection(.favorites)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["tmdb:movie:603"])

        viewModel.selectSection(.series)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), ["tmdb:tv:1399"])
    }

    @MainActor
    func testLoadToleratesDuplicateLibraryStateRows() async {
        let movie = Self.movie(id: "imdb:movie:tt29552248", title: "Project Hail Mary", year: 2026)
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_800_000_000)
        let repository = InMemoryLibraryRepository(
            items: [movie],
            libraryEntries: [
                CineFlowCore.LibraryItem(mediaID: movie.id, addedAt: olderDate),
                CineFlowCore.LibraryItem(mediaID: movie.id, addedAt: newerDate)
            ],
            watchedItems: [
                WatchedMediaItem(item: movie, watchedAt: olderDate, positionSeconds: 120),
                WatchedMediaItem(item: movie, watchedAt: newerDate, positionSeconds: 960)
            ],
            ratedItems: [
                RatedMediaItem(item: movie, rating: 7, updatedAt: olderDate),
                RatedMediaItem(item: movie, rating: 9, updatedAt: newerDate)
            ]
        )
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()
        viewModel.selectSection(.all)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [movie.id])
        XCTAssertEqual(viewModel.summary.watchedCount, 2)
        XCTAssertEqual(viewModel.summary.ratingCount, 2)
    }

    @MainActor
    func testSearchSortAndKindFilterApplyInsideSelectedSection() async {
        let repository = InMemoryLibraryRepository(items: [
            Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999),
            Self.movie(id: "tmdb:movie:329865", title: "Arrival", year: 2016),
            Self.series(id: "tmdb:tv:1399", title: "Game of Thrones", year: 2011)
        ])
        let viewModel = LibraryViewModel(repository: repository)
        await viewModel.load()

        viewModel.selectSection(.all)
        viewModel.updateSearchQuery("the")
        viewModel.setKindFilter(.movies)
        viewModel.setSortOrder(.titleAscending)

        XCTAssertEqual(viewModel.visibleItems.map(\.title), ["The Matrix"])

        viewModel.updateSearchQuery("")
        viewModel.setSortOrder(.yearDescending)

        XCTAssertEqual(viewModel.visibleItems.map(\.title), ["Arrival", "The Matrix"])
    }

    @MainActor
    func testLibraryActionsPersistThroughRepositoryAndRefreshState() async throws {
        let movie = Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999)
        let repository = InMemoryLibraryRepository(items: [movie])
        let viewModel = LibraryViewModel(repository: repository)
        await viewModel.load()

        try await viewModel.addFavorite(movie)
        try await viewModel.markWatched(movie)
        try await viewModel.rate(movie, rating: 8)
        let list = try await viewModel.createList(named: "Sci-Fi")
        try await viewModel.add(movie, to: list)

        XCTAssertEqual(viewModel.summary.favoriteCount, 1)
        XCTAssertEqual(viewModel.summary.watchedCount, 1)
        XCTAssertEqual(viewModel.summary.ratingCount, 1)
        XCTAssertEqual(viewModel.lists.first?.itemIDs, [movie.id])

        try await viewModel.removeFromLibrary(mediaID: movie.id)

        XCTAssertFalse(viewModel.items.contains { $0.id == movie.id })
        XCTAssertFalse(viewModel.visibleItems.contains { $0.id == movie.id })
    }

    @MainActor
    func testLargeLibraryFilteringUsesCachedVisibleItemsAndArtworkPrefetchList() async {
        let items = (0..<1_500).map { index in
            MediaItem(
                id: "tmdb:movie:\(index)",
                title: index.isMultiple(of: 2) ? "Matrix \(index)" : "Arrival \(index)",
                kind: .movie,
                overview: "Fixture",
                releaseYear: 1980 + (index % 40),
                posterPath: "https://images.example.com/poster-\(index).jpg"
            )
        }
        let repository = InMemoryLibraryRepository(items: items)
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()
        viewModel.selectSection(.all)
        XCTAssertEqual(viewModel.visibleItems.count, 1_500)

        viewModel.updateSearchQuery("Matrix")
        XCTAssertEqual(viewModel.visibleItems.count, 750)
        XCTAssertEqual(viewModel.prefetchArtworkURLs.count, 48)
        XCTAssertFalse(viewModel.artworkPrefetchKey.isEmpty)

        viewModel.setSortOrder(.yearDescending)
        XCTAssertGreaterThanOrEqual(viewModel.visibleItems.first?.releaseYear ?? 0, viewModel.visibleItems.last?.releaseYear ?? 0)
    }

    @MainActor
    func testAdvancedFiltersSavedViewsAndSortingKeepLargeLibraryManageable() async throws {
        let matrix = Self.movie(
            id: "tmdb:movie:603",
            title: "The Matrix",
            year: 1999,
            genres: ["Sci-Fi", "Action"],
            metadataRating: 8.7,
            quality: .ultraHD
        )
        let arrival = Self.movie(
            id: "tmdb:movie:329865",
            title: "Arrival",
            year: 2016,
            genres: ["Sci-Fi", "Drama"],
            metadataRating: 7.9,
            quality: .fullHD
        )
        let severance = Self.series(
            id: "tmdb:tv:95396",
            title: "Severance",
            year: 2022,
            genres: ["Sci-Fi"],
            metadataRating: 8.5,
            quality: .ultraHD
        )
        let repository = InMemoryLibraryRepository(items: [arrival, matrix, severance])
        try await repository.markWatched(matrix, positionSeconds: 7_200)
        try await repository.markWatched(arrival, positionSeconds: 1_800)
        try await repository.setRating(matrix, rating: 9)
        try await repository.addFavorite(severance)
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()
        viewModel.selectSection(.all)
        viewModel.setGenreFilter("Sci-Fi")
        viewModel.setYearRange(1990...2020)
        viewModel.setMinimumRating(8)
        viewModel.setWatchStateFilter(.watched)
        viewModel.setQualityFilter(.ultraHD)

        XCTAssertEqual(viewModel.visibleItems.map(\.id), [matrix.id])

        viewModel.applySavedView(.inProgress)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [arrival.id])

        viewModel.applySavedView(.favorites)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [severance.id])

        viewModel.applySavedView(.movies)
        viewModel.setSortOrder(.titleAscending)
        XCTAssertEqual(viewModel.visibleItems.map(\.title), ["Arrival", "The Matrix"])

        viewModel.setSortOrder(.progressDescending)
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [matrix.id, arrival.id])

        viewModel.setSortOrder(.recentlyWatched)
        XCTAssertEqual(viewModel.visibleItems.first?.id, arrival.id)
    }

    @MainActor
    func testBulkActionsRequireConfirmationForDestructiveOperations() async throws {
        let matrix = Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999, genres: ["Sci-Fi"])
        let arrival = Self.movie(id: "tmdb:movie:329865", title: "Arrival", year: 2016, genres: ["Sci-Fi"])
        let repository = InMemoryLibraryRepository(items: [matrix, arrival])
        try await repository.markWatched(arrival, positionSeconds: 1_800)
        let watchlist = try await repository.defaultList()
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()
        viewModel.selectSection(.all)
        viewModel.selectItems([matrix.id, arrival.id])

        try await viewModel.performBulkAction(.markWatched)
        XCTAssertEqual(viewModel.summary.watchedCount, 2)

        try await viewModel.performBulkAction(.addToList(watchlist.id))
        let watchlistItems = try await repository.items(in: watchlist.id)
        XCTAssertEqual(watchlistItems.map(\.id), [matrix.id, arrival.id])

        try await viewModel.performBulkAction(.clearProgress)
        XCTAssertEqual(viewModel.pendingBulkConfirmation?.action, .clearProgress)
        let watchedBeforeClear = try await repository.watchedItems()
        XCTAssertEqual(watchedBeforeClear.count, 2)

        try await viewModel.confirmPendingBulkAction()
        let watchedAfterClear = try await repository.watchedItems()
        XCTAssertTrue(watchedAfterClear.isEmpty)

        viewModel.selectItems([matrix.id])
        try await viewModel.performBulkAction(.remove)
        XCTAssertEqual(viewModel.pendingBulkConfirmation?.action, .remove)
        var repositoryItems = try await repository.items()
        XCTAssertTrue(repositoryItems.contains { $0.id == matrix.id })

        try await viewModel.cancelPendingBulkAction()
        XCTAssertNil(viewModel.pendingBulkConfirmation)
        repositoryItems = try await repository.items()
        XCTAssertTrue(repositoryItems.contains { $0.id == matrix.id })

        try await viewModel.performBulkAction(.remove)
        try await viewModel.confirmPendingBulkAction()
        repositoryItems = try await repository.items()
        XCTAssertFalse(repositoryItems.contains { $0.id == matrix.id })
    }

    @MainActor
    func testQuickActionStateKeepsCardActionsInViewModel() async throws {
        let matrix = Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999, genres: ["Sci-Fi"], quality: .ultraHD)
        let repository = InMemoryLibraryRepository(items: [matrix])
        try await repository.markWatched(matrix, positionSeconds: 1_800)
        let viewModel = LibraryViewModel(repository: repository)

        await viewModel.load()
        let state = viewModel.quickActionState(for: matrix)

        XCTAssertTrue(state.canWatch)
        XCTAssertTrue(state.canOpenDetails)
        XCTAssertFalse(state.canAddToLibrary)
        XCTAssertTrue(state.canAddToWatchlist)
        XCTAssertTrue(state.canAddToList)
        XCTAssertTrue(state.canRate)
        XCTAssertFalse(state.canHide)
        XCTAssertTrue(state.canFixMetadata)
        XCTAssertTrue(state.canFindBestRelease)
        XCTAssertTrue(state.canClearProgress)
        XCTAssertTrue(state.clearProgressRequiresConfirmation)

        try await viewModel.clearProgress(mediaID: matrix.id)
        let updatedState = viewModel.quickActionState(for: matrix)
        XCTAssertFalse(updatedState.canClearProgress)
    }

    @MainActor
    func testLoadFetchesPersonalStatsForStatsSection() async {
        let repository = InMemoryLibraryRepository(items: [
            Self.movie(id: "tmdb:movie:603", title: "The Matrix", year: 1999, genres: ["Sci-Fi"])
        ])
        let statsService = InMemoryPersonalStatsService(
            stats: PersonalWatchStats(
                watchedMoviesCount: 12,
                watchedEpisodesCount: 24,
                monthlyWatchTimeSeconds: 36_000,
                completionRate: 0.8,
                longestBingeSession: PersonalBingeSession(
                    startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    endedAt: Date(timeIntervalSince1970: 1_800_010_800),
                    durationSeconds: 10_800,
                    itemCount: 3
                ),
                favoriteGenres: [PersonalStatsRankedItem(name: "Sci-Fi", count: 7)],
                favoriteActors: [PersonalStatsRankedItem(name: "Keanu Reeves", count: 4)]
            )
        )
        let viewModel = LibraryViewModel(repository: repository, personalStatsService: statsService)

        await viewModel.load()
        viewModel.selectSection(.stats)

        XCTAssertEqual(viewModel.personalStats.watchedMoviesCount, 12)
        XCTAssertEqual(viewModel.personalStats.favoriteGenres.map(\.name), ["Sci-Fi"])
        XCTAssertEqual(viewModel.selectedSection, .stats)
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    private static func movie(
        id: String,
        title: String,
        year: Int,
        genres: [String] = [],
        metadataRating: Double? = nil,
        quality: ReleaseQuality = .unknown
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .movie,
            overview: "Fixture",
            releaseYear: year,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: abs(id.hashValue % 100_000),
                title: title,
                originalTitle: title,
                overview: "Fixture",
                year: year,
                genres: genres,
                rating: metadataRating
            ),
            torrentReleases: quality == .unknown ? [] : [
                TorrentRelease(id: "\(id):release", title: title, quality: quality, seeders: 40)
            ]
        )
    }

    private static func series(
        id: String,
        title: String,
        year: Int,
        genres: [String] = [],
        metadataRating: Double? = nil,
        quality: ReleaseQuality = .unknown
    ) -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            kind: .series,
            overview: "Fixture",
            releaseYear: year,
            posterPath: nil,
            metadata: MediaMetadata(
                tmdbId: abs(id.hashValue % 100_000),
                title: title,
                originalTitle: title,
                overview: "Fixture",
                year: year,
                genres: genres,
                rating: metadataRating
            ),
            torrentReleases: quality == .unknown ? [] : [
                TorrentRelease(id: "\(id):release", title: title, quality: quality, seeders: 40)
            ]
        )
    }
}

private actor InMemoryLibraryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedLibraryEntries: [CineFlowCore.LibraryItem]
    private var favoriteItems: [MediaItem] = []
    private var watchedMediaItems: [WatchedMediaItem] = []
    private var ratedMediaItems: [RatedMediaItem] = []
    private var storedLists: [UserList] = []

    init(
        items: [MediaItem],
        libraryEntries: [CineFlowCore.LibraryItem]? = nil,
        watchedItems: [WatchedMediaItem] = [],
        ratedItems: [RatedMediaItem] = []
    ) {
        storedItems = items
        storedLibraryEntries = libraryEntries ?? items.map { CineFlowCore.LibraryItem(mediaID: $0.id) }
        watchedMediaItems = watchedItems
        ratedMediaItems = ratedItems
    }

    func items() async throws -> [MediaItem] {
        storedItems
    }

    func libraryEntries() async throws -> [CineFlowCore.LibraryItem] {
        storedLibraryEntries
    }

    func add(_ item: MediaItem) async throws {
        upsert(item)
    }

    func remove(mediaID: String) async throws {
        storedItems.removeAll { $0.id == mediaID }
        favoriteItems.removeAll { $0.id == mediaID }
        watchedMediaItems.removeAll { $0.item.id == mediaID }
        ratedMediaItems.removeAll { $0.item.id == mediaID }
        storedLists = storedLists.map { list in
            UserList(id: list.id, name: list.name, itemIDs: list.itemIDs.filter { $0 != mediaID }, createdAt: list.createdAt)
        }
    }

    func favorites() async throws -> [MediaItem] {
        favoriteItems
    }

    func addFavorite(_ item: MediaItem) async throws {
        upsert(item)
        if !favoriteItems.contains(where: { $0.id == item.id }) {
            favoriteItems.append(item)
        }
    }

    func removeFavorite(mediaID: String) async throws {
        favoriteItems.removeAll { $0.id == mediaID }
    }

    func watchedItems() async throws -> [WatchedMediaItem] {
        watchedMediaItems
    }

    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {
        upsert(item)
        watchedMediaItems.removeAll { $0.item.id == item.id }
        watchedMediaItems.insert(WatchedMediaItem(item: item, watchedAt: Date(), positionSeconds: positionSeconds), at: 0)
    }

    func removeFromHistory(mediaID: String) async throws {
        watchedMediaItems.removeAll { $0.item.id == mediaID }
    }

    func ratedItems() async throws -> [RatedMediaItem] {
        ratedMediaItems
    }

    func setRating(_ item: MediaItem, rating: Int) async throws {
        upsert(item)
        ratedMediaItems.removeAll { $0.item.id == item.id }
        ratedMediaItems.append(RatedMediaItem(item: item, rating: rating, updatedAt: Date()))
    }

    func lists() async throws -> [UserList] {
        storedLists
    }

    func defaultList() async throws -> UserList {
        if let existing = storedLists.first(where: { $0.isDefault }) {
            return existing
        }
        let list = UserList(
            id: "default-watchlist",
            name: "Хочу посмотреть",
            description: "Фильмы и сериалы, которые вы хотите посмотреть позже.",
            isDefault: true
        )
        storedLists.insert(list, at: 0)
        return list
    }

    func createList(name: String) async throws -> UserList {
        try await createList(name: name, description: nil)
    }

    func createList(name: String, description: String?) async throws -> UserList {
        let list = UserList(name: name, description: description)
        storedLists.append(list)
        return list
    }

    func renameList(id: String, name: String, description: String?) async throws {
        storedLists = storedLists.map { list in
            guard list.id == id else { return list }
            return UserList(
                id: list.id,
                name: name,
                description: description,
                itemIDs: list.itemIDs,
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    func deleteList(id: String) async throws {
        storedLists.removeAll { $0.id == id && !$0.isDefault }
    }

    func add(_ item: MediaItem, to listID: String) async throws {
        upsert(item)
        storedLists = storedLists.map { list in
            guard list.id == listID, !list.itemIDs.contains(item.id) else { return list }
            return UserList(
                id: list.id,
                name: list.name,
                description: list.description,
                itemIDs: list.itemIDs + [item.id],
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    func remove(_ mediaID: String, from listID: String) async throws {
        storedLists = storedLists.map { list in
            guard list.id == listID else { return list }
            return UserList(
                id: list.id,
                name: list.name,
                description: list.description,
                itemIDs: list.itemIDs.filter { $0 != mediaID },
                createdAt: list.createdAt,
                updatedAt: Date(),
                isDefault: list.isDefault
            )
        }
    }

    func items(in listID: String) async throws -> [MediaItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return storedItems.filter { list.itemIDs.contains($0.id) }
    }

    private func upsert(_ item: MediaItem) {
        storedItems.removeAll { $0.id == item.id }
        storedItems.append(item)
    }
}

private struct InMemoryPersonalStatsService: PersonalStatsServiceProtocol {
    let stats: PersonalWatchStats

    func personalStats(referenceDate: Date) async throws -> PersonalWatchStats {
        stats
    }
}
