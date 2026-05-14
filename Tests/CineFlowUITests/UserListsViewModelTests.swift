import CineFlowCore
import XCTest
@testable import CineFlowUI

final class UserListsViewModelTests: XCTestCase {
    @MainActor
    func testLoadCreatesDefaultWatchlistAndSelectsIt() async throws {
        let repository = UserListsMemoryRepository(items: [])
        let viewModel = UserListsViewModel(repository: repository)

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.lists.map(\.name), ["Хочу посмотреть"])
        XCTAssertEqual(viewModel.selectedList?.name, "Хочу посмотреть")
        XCTAssertTrue(viewModel.visibleItems.isEmpty)
    }

    @MainActor
    func testCreateRenameDeleteAndRemoveMediaRefreshesDetail() async throws {
        let movie = MediaItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: "Fixture",
            releaseYear: 1999,
            posterPath: nil
        )
        let repository = UserListsMemoryRepository(items: [movie])
        let viewModel = UserListsViewModel(repository: repository)
        await viewModel.load()

        let list = try await viewModel.createList(name: "Семейное", description: "Для вечера")
        try await viewModel.add(movie, to: list)

        XCTAssertEqual(viewModel.selectedList?.name, "Семейное")
        XCTAssertEqual(viewModel.selectedList?.description, "Для вечера")
        XCTAssertEqual(viewModel.visibleItems.map(\.id), [movie.id])
        XCTAssertEqual(viewModel.selectedList?.itemsCount, 1)

        try await viewModel.renameSelectedList(name: "Семейное кино", description: "Обновлено")

        XCTAssertEqual(viewModel.selectedList?.name, "Семейное кино")
        XCTAssertEqual(viewModel.selectedList?.description, "Обновлено")

        try await viewModel.remove(movie.id)

        XCTAssertTrue(viewModel.visibleItems.isEmpty)
        XCTAssertEqual(viewModel.selectedList?.itemsCount, 0)

        try await viewModel.deleteSelectedList()

        XCTAssertEqual(viewModel.lists.map(\.name), ["Хочу посмотреть"])
    }

    @MainActor
    func testWatchlistPrioritiesBadgesSortingAndCleanupSuggestions() async throws {
        let arrival = Self.media(
            id: "tmdb:movie:329865",
            title: "Arrival",
            year: 2016,
            runtime: 116,
            rating: 7.9,
            releases: [
                TorrentRelease(id: "arrival-1080p", title: "Arrival 1080p", quality: .fullHD, seeders: 50)
            ]
        )
        let matrix = Self.media(
            id: "tmdb:movie:603",
            title: "The Matrix",
            year: 1999,
            runtime: 136,
            rating: 8.7,
            releases: [
                TorrentRelease(id: "matrix-hdr", title: "The Matrix 1080p HDR RU", quality: .fullHD, hdr: .hdr10, audioLanguages: ["ru", "en"], seeders: 80)
            ]
        )
        let repository = UserListsMemoryRepository(items: [arrival])
        let viewModel = UserListsViewModel(repository: repository)

        await viewModel.load()
        let watchlist = try XCTUnwrap(viewModel.selectedList)
        try await viewModel.add(arrival, to: watchlist)
        let upgradedArrival = Self.media(
            id: arrival.id,
            title: arrival.title,
            year: 2016,
            runtime: 116,
            rating: 7.9,
            releases: [
                TorrentRelease(id: "arrival-4k", title: "Arrival 2160p HDR", quality: .ultraHD, hdr: .dolbyVision, seeders: 90)
            ]
        )
        try await repository.add(upgradedArrival)
        try await repository.add(matrix)
        try await viewModel.add(matrix, to: watchlist)
        try await viewModel.setWatchlistPriority(mediaID: arrival.id, priority: .high)
        try await viewModel.setWatchlistPriority(mediaID: matrix.id, priority: .later)
        let reminderDate = Date().addingTimeInterval(3 * 24 * 60 * 60)
        try await viewModel.remindLater(mediaID: matrix.id, until: reminderDate)
        try await repository.markWatched(upgradedArrival, positionSeconds: 7_200)

        await viewModel.load()

        XCTAssertEqual(viewModel.watchlistItems.map(\.item.id), [arrival.id, matrix.id])
        XCTAssertEqual(viewModel.watchlistItems.first?.priority, .high)
        XCTAssertEqual(viewModel.watchlistItems.last?.priority, .later)
        XCTAssertEqual(viewModel.watchlistItems.last?.remindLaterAt?.timeIntervalSince1970.rounded(), reminderDate.timeIntervalSince1970.rounded())
        XCTAssertTrue(viewModel.watchlistItems.first?.badges.contains(.betterReleaseAvailable) == true)
        XCTAssertTrue(viewModel.watchlistItems.last?.badges.contains(.availableIn4KHDR) == true)
        XCTAssertTrue(viewModel.watchlistItems.last?.badges.contains(.russianAudioAvailable) == true)
        XCTAssertEqual(viewModel.cleanupSuggestions.map(\.item.id), [arrival.id])

        viewModel.setWatchlistSortOrder(.runtime)
        XCTAssertEqual(viewModel.watchlistItems.map(\.item.id), [matrix.id, arrival.id])

        viewModel.setWatchlistSortOrder(.quality)
        XCTAssertEqual(viewModel.watchlistItems.first?.item.id, arrival.id)

        try await viewModel.acceptCleanupSuggestion(mediaID: arrival.id)
        XCTAssertFalse(viewModel.watchlistItems.contains { $0.item.id == arrival.id })
    }

    private static func media(
        id: String,
        title: String,
        year: Int,
        runtime: Int,
        rating: Double,
        releases: [TorrentRelease]
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
                runtime: runtime,
                rating: rating
            ),
            torrentReleases: releases
        )
    }
}

private actor UserListsMemoryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedLists: [UserList] = []
    private var storedWatchlistItems: [String: WatchlistItem] = [:]
    private var storedWatchedItems: [WatchedMediaItem] = []

    init(items: [MediaItem]) {
        storedItems = items
    }

    func items() async throws -> [MediaItem] { storedItems }
    func add(_ item: MediaItem) async throws { upsert(item) }
    func remove(mediaID: String) async throws { storedItems.removeAll { $0.id == mediaID } }
    func favorites() async throws -> [MediaItem] { [] }
    func addFavorite(_ item: MediaItem) async throws { upsert(item) }
    func removeFavorite(mediaID: String) async throws {}
    func watchedItems() async throws -> [WatchedMediaItem] { storedWatchedItems }
    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {
        upsert(item)
        storedWatchedItems.removeAll { $0.item.id == item.id }
        storedWatchedItems.insert(WatchedMediaItem(item: item, positionSeconds: positionSeconds), at: 0)
    }
    func ratedItems() async throws -> [RatedMediaItem] { [] }
    func setRating(_ item: MediaItem, rating: Int) async throws { upsert(item) }

    func lists() async throws -> [UserList] { storedLists }

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
        storedLists.insert(list, at: 0)
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
        let key = watchlistKey(listID: listID, mediaID: item.id)
        if storedWatchlistItems[key] == nil {
            let snapshot = item.bestWatchlistReleaseSnapshot
            storedWatchlistItems[key] = WatchlistItem(
                listID: listID,
                mediaID: item.id,
                initialQuality: snapshot.quality,
                initialHDR: snapshot.hdr
            )
        }
    }

    func remove(_ mediaID: String, from listID: String) async throws {
        storedWatchlistItems.removeValue(forKey: watchlistKey(listID: listID, mediaID: mediaID))
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

    func watchlistItems(in listID: String) async throws -> [WatchlistItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return list.itemIDs.compactMap { mediaID in
            storedWatchlistItems[watchlistKey(listID: listID, mediaID: mediaID)]
        }
    }

    func updateWatchlistItem(listID: String, mediaID: String, priority: WatchlistPriority, remindLaterAt: Date?) async throws {
        let key = watchlistKey(listID: listID, mediaID: mediaID)
        let existing = storedWatchlistItems[key] ?? WatchlistItem(listID: listID, mediaID: mediaID)
        storedWatchlistItems[key] = WatchlistItem(
            listID: listID,
            mediaID: mediaID,
            priority: priority,
            remindLaterAt: remindLaterAt,
            addedAt: existing.addedAt,
            initialQuality: existing.initialQuality,
            initialHDR: existing.initialHDR
        )
    }

    private func upsert(_ item: MediaItem) {
        storedItems.removeAll { $0.id == item.id }
        storedItems.append(item)
    }

    private func watchlistKey(listID: String, mediaID: String) -> String {
        "\(listID):\(mediaID)"
    }
}

private extension MediaItem {
    var bestWatchlistReleaseSnapshot: (quality: ReleaseQuality, hdr: HDRFormat) {
        guard let release = rankedReleases.first else {
            return (.unknown, .unknown)
        }
        return (release.quality, release.hdr)
    }
}
