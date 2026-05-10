import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum UserListsState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
public final class UserListsViewModel: ObservableObject {
    @Published public private(set) var state: UserListsState = .loading
    @Published public private(set) var lists: [UserList] = []
    @Published public private(set) var selectedListID: String?
    @Published public private(set) var visibleItems: [MediaItem] = []
    @Published public private(set) var errorMessage: String?

    private let repository: any LibraryRepositoryProtocol

    public init(repository: any LibraryRepositoryProtocol) {
        self.repository = repository
    }

    public var selectedList: UserList? {
        guard let selectedListID else { return lists.first }
        return lists.first { $0.id == selectedListID } ?? lists.first
    }

    public func load() async {
        state = .loading
        errorMessage = nil

        do {
            _ = try await repository.defaultList()
            lists = try await repository.lists()
            selectedListID = selectedListID ?? lists.first?.id
            try await refreshVisibleItems()
            state = lists.isEmpty ? .empty : .loaded
        } catch {
            lists = []
            visibleItems = []
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .database)
            errorMessage = cineFlowError.userMessage
            state = .failed(cineFlowError.userMessage)
        }
    }

    public func selectList(_ list: UserList) async {
        selectedListID = list.id
        try? await refreshVisibleItems()
    }

    @discardableResult
    public func createList(name: String, description: String?) async throws -> UserList {
        let list = try await repository.createList(name: name, description: description)
        selectedListID = list.id
        await load()
        selectedListID = list.id
        try await refreshVisibleItems()
        return list
    }

    public func renameSelectedList(name: String, description: String?) async throws {
        guard let selectedList else { return }
        try await repository.renameList(id: selectedList.id, name: name, description: description)
        await load()
        selectedListID = selectedList.id
        try await refreshVisibleItems()
    }

    public func deleteSelectedList() async throws {
        guard let selectedList, !selectedList.isDefault else { return }
        try await repository.deleteList(id: selectedList.id)
        selectedListID = nil
        await load()
    }

    public func add(_ item: MediaItem, to list: UserList) async throws {
        try await repository.add(item, to: list.id)
        selectedListID = list.id
        await load()
        selectedListID = list.id
        try await refreshVisibleItems()
    }

    public func remove(_ mediaID: String) async throws {
        guard let selectedList else { return }
        try await repository.remove(mediaID, from: selectedList.id)
        await load()
        selectedListID = selectedList.id
        try await refreshVisibleItems()
    }

    public func cardModel(for item: MediaItem) -> CFMediaCardModel {
        CFMediaCardModel(
            id: item.id,
            title: item.displayTitle,
            metadata: "\(item.displayYear) · \(item.kind == .movie ? "Movie" : "Series")",
            badge: nil,
            accentIndex: abs(item.id.hashValue),
            artworkURL: item.bestPosterURL
        )
    }

    private func refreshVisibleItems() async throws {
        guard let selectedListID = selectedList?.id else {
            visibleItems = []
            return
        }
        visibleItems = try await repository.items(in: selectedListID)
    }
}
