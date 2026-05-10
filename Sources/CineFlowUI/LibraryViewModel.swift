import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum LibraryViewState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum LibrarySection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case favorites
    case all
    case movies
    case series
    case lists
    case watched
    case ratings

    public var id: String { rawValue }
}

public enum LibraryKindFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case movies
    case series

    public var id: String { rawValue }
}

public enum LibrarySortOrder: String, CaseIterable, Identifiable, Equatable, Sendable {
    case recentlyAdded
    case titleAscending
    case yearDescending
    case ratingDescending

    public var id: String { rawValue }
}

public struct LibrarySummary: Equatable, Sendable {
    public var favoriteCount: Int
    public var movieCount: Int
    public var seriesCount: Int
    public var listCount: Int
    public var watchedCount: Int
    public var ratingCount: Int

    public static let empty = LibrarySummary(
        favoriteCount: 0,
        movieCount: 0,
        seriesCount: 0,
        listCount: 0,
        watchedCount: 0,
        ratingCount: 0
    )
}

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public private(set) var state: LibraryViewState = .loading
    @Published public private(set) var items: [MediaItem] = []
    @Published public private(set) var favorites: [MediaItem] = []
    @Published public private(set) var watchedItems: [WatchedMediaItem] = []
    @Published public private(set) var ratedItems: [RatedMediaItem] = []
    @Published public private(set) var lists: [UserList] = []
    @Published public private(set) var selectedSection: LibrarySection = .favorites
    @Published public private(set) var selectedKindFilter: LibraryKindFilter = .all
    @Published public private(set) var sortOrder: LibrarySortOrder = .recentlyAdded
    @Published public private(set) var selectedListID: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var visibleItems: [MediaItem] = []
    @Published public private(set) var summary: LibrarySummary = .empty
    @Published public var searchQuery = ""

    private let repository: any LibraryRepositoryProtocol
    private var listItemsByID: [String: [MediaItem]] = [:]
    private var favoriteIDs: Set<String> = []
    private var ratingsByID: [String: Int] = [:]
    private var progressByID: [String: Double] = [:]

    public init(repository: any LibraryRepositoryProtocol) {
        self.repository = repository
    }

    public var isCurrentSectionEmpty: Bool {
        visibleItems.isEmpty
    }

    public var prefetchArtworkURLs: [URL] {
        Array(visibleItems.lazy.compactMap(\.bestPosterURL).prefix(48))
    }

    public var artworkPrefetchKey: String {
        prefetchArtworkURLs.map(\.absoluteString).joined(separator: "|")
    }

    public func load() async {
        state = .loading
        errorMessage = nil

        do {
            async let libraryItems = repository.items()
            async let favoriteItems = repository.favorites()
            async let watched = repository.watchedItems()
            async let rated = repository.ratedItems()
            async let userLists = repository.lists()

            items = try await libraryItems
            favorites = try await favoriteItems
            watchedItems = try await watched
            ratedItems = try await rated
            lists = try await userLists

            var loadedListItems: [String: [MediaItem]] = [:]
            for list in lists {
                loadedListItems[list.id] = try await repository.items(in: list.id)
            }
            listItemsByID = loadedListItems
            rebuildLookupTables()
            rebuildSummary()
            selectedListID = selectedListID ?? lists.first?.id
            rebuildVisibleItems()
            state = items.isEmpty && favorites.isEmpty && lists.isEmpty && watchedItems.isEmpty && ratedItems.isEmpty ? .empty : .loaded
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .database)
            errorMessage = cineFlowError.userMessage
            visibleItems = []
            summary = .empty
            state = .failed(cineFlowError.userMessage)
        }
    }

    public func selectSection(_ section: LibrarySection) {
        selectedSection = section
        if section == .lists, selectedListID == nil {
            selectedListID = lists.first?.id
        }
        rebuildVisibleItems()
    }

    public func updateSearchQuery(_ query: String) {
        searchQuery = query
        rebuildVisibleItems()
    }

    public func setKindFilter(_ filter: LibraryKindFilter) {
        selectedKindFilter = filter
        rebuildVisibleItems()
    }

    public func setSortOrder(_ order: LibrarySortOrder) {
        sortOrder = order
        rebuildVisibleItems()
    }

    public func selectList(_ list: UserList) {
        selectedListID = list.id
        selectedSection = .lists
        rebuildVisibleItems()
    }

    public func add(_ item: MediaItem) async throws {
        try await repository.add(item)
        await load()
    }

    public func removeFromLibrary(mediaID: String) async throws {
        try await repository.remove(mediaID: mediaID)
        await load()
    }

    public func addFavorite(_ item: MediaItem) async throws {
        try await repository.addFavorite(item)
        await load()
    }

    public func removeFavorite(mediaID: String) async throws {
        try await repository.removeFavorite(mediaID: mediaID)
        await load()
    }

    public func markWatched(_ item: MediaItem) async throws {
        try await repository.markWatched(item, positionSeconds: 0)
        await load()
    }

    public func rate(_ item: MediaItem, rating: Int) async throws {
        try await repository.setRating(item, rating: rating)
        await load()
    }

    public func createList(named name: String) async throws -> UserList {
        let list = try await repository.createList(name: name)
        await load()
        selectedListID = list.id
        return list
    }

    public func defaultList() async throws -> UserList {
        let list = try await repository.defaultList()
        await load()
        selectedListID = list.id
        return list
    }

    public func add(_ item: MediaItem, to list: UserList) async throws {
        try await repository.add(item, to: list.id)
        await load()
        selectedListID = list.id
    }

    public func rating(for mediaID: String) -> Int? {
        ratingsByID[mediaID]
    }

    public func isFavorite(_ mediaID: String) -> Bool {
        favoriteIDs.contains(mediaID)
    }

    public func cardModel(for item: MediaItem) -> CFMediaCardModel {
        let ratingSuffix = rating(for: item.id).map { " · \($0)/10" } ?? ""
        return CFMediaCardModel(
            id: item.id,
            title: item.displayTitle,
            metadata: "\(item.displayYear) · \(kindTitle(for: item.kind))\(ratingSuffix)",
            badge: isFavorite(item.id) ? "★" : nil,
            progress: progress(for: item.id),
            accentIndex: abs(item.id.hashValue),
            artworkURL: item.bestPosterURL
        )
    }

    private func baseItems(for section: LibrarySection) -> [MediaItem] {
        switch section {
        case .favorites:
            return favorites
        case .all:
            return items
        case .movies:
            return items.filter { $0.kind == .movie }
        case .series:
            return items.filter { $0.kind == .series }
        case .lists:
            guard let selectedListID else { return [] }
            return listItemsByID[selectedListID] ?? []
        case .watched:
            return watchedItems.map(\.item)
        case .ratings:
            return ratedItems.map(\.item)
        }
    }

    private func rebuildVisibleItems() {
        visibleItems = sort(filter(baseItems(for: selectedSection)))
    }

    private func rebuildLookupTables() {
        favoriteIDs = Set(favorites.map(\.id))
        ratingsByID = Dictionary(uniqueKeysWithValues: ratedItems.map { ($0.item.id, $0.rating) })
        progressByID = Dictionary(
            uniqueKeysWithValues: watchedItems.compactMap { watchedItem in
                guard watchedItem.positionSeconds > 0 else { return nil }
                return (watchedItem.item.id, min(watchedItem.positionSeconds / 7_200, 1))
            }
        )
    }

    private func rebuildSummary() {
        var movieCount = 0
        var seriesCount = 0
        for item in items {
            switch item.kind {
            case .movie:
                movieCount += 1
            case .series:
                seriesCount += 1
            }
        }

        summary = LibrarySummary(
            favoriteCount: favorites.count,
            movieCount: movieCount,
            seriesCount: seriesCount,
            listCount: lists.count,
            watchedCount: watchedItems.count,
            ratingCount: ratedItems.count
        )
    }

    private func filter(_ baseItems: [MediaItem]) -> [MediaItem] {
        let kindFiltered = baseItems.filter { item in
            switch selectedKindFilter {
            case .all:
                true
            case .movies:
                item.kind == .movie
            case .series:
                item.kind == .series
            }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return kindFiltered }
        return kindFiltered.filter { item in
            item.displayTitle.lowercased().contains(query)
                || item.overview.lowercased().contains(query)
                || item.displayYear.lowercased().contains(query)
        }
    }

    private func sort(_ baseItems: [MediaItem]) -> [MediaItem] {
        switch sortOrder {
        case .recentlyAdded:
            baseItems
        case .titleAscending:
            baseItems.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .yearDescending:
            baseItems.sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
        case .ratingDescending:
            baseItems.sorted { (ratingsByID[$0.id] ?? 0) > (ratingsByID[$1.id] ?? 0) }
        }
    }

    private func progress(for mediaID: String) -> Double? {
        progressByID[mediaID]
    }

    private func kindTitle(for kind: MediaKind) -> String {
        switch kind {
        case .movie:
            "Movie"
        case .series:
            "Series"
        }
    }
}
