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
}

private actor UserListsMemoryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedLists: [UserList] = []

    init(items: [MediaItem]) {
        storedItems = items
    }

    func items() async throws -> [MediaItem] { storedItems }
    func add(_ item: MediaItem) async throws { upsert(item) }
    func remove(mediaID: String) async throws { storedItems.removeAll { $0.id == mediaID } }
    func favorites() async throws -> [MediaItem] { [] }
    func addFavorite(_ item: MediaItem) async throws { upsert(item) }
    func removeFavorite(mediaID: String) async throws {}
    func watchedItems() async throws -> [WatchedMediaItem] { [] }
    func markWatched(_ item: MediaItem, positionSeconds: Double) async throws { upsert(item) }
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
