import CineFlowCore
import Foundation

public final class MockLibraryRepository: LibraryRepositoryProtocol {
    private var storedItems: [MediaItem]
    private var storedFavorites: [MediaItem]
    private var storedWatchedItems: [WatchedMediaItem]
    private var storedRatedItems: [RatedMediaItem]
    private var storedLists: [UserList]
    private var storedWatchlistItems: [String: WatchlistItem]

    public init(storedItems: [MediaItem] = [
        MediaItem(
            id: "tmdb:movie:603",
            title: "The Matrix",
            kind: .movie,
            overview: "A mock local library item.",
            releaseYear: 1999,
            posterPath: nil
        )
    ]) {
        self.storedItems = storedItems
        storedFavorites = []
        storedWatchedItems = []
        storedRatedItems = []
        storedLists = []
        storedWatchlistItems = [:]
    }

    public func items() async throws -> [MediaItem] {
        storedItems
    }

    public func add(_ item: MediaItem) async throws {
        upsert(item)
    }

    public func remove(mediaID: String) async throws {
        storedItems.removeAll { $0.id == mediaID }
        storedFavorites.removeAll { $0.id == mediaID }
        storedWatchedItems.removeAll { $0.item.id == mediaID }
        storedRatedItems.removeAll { $0.item.id == mediaID }
        storedWatchlistItems = storedWatchlistItems.filter { $0.value.mediaID != mediaID }
        storedLists = storedLists.map { list in
            UserList(
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

    public func favorites() async throws -> [MediaItem] {
        storedFavorites
    }

    public func addFavorite(_ item: MediaItem) async throws {
        upsert(item)
        if !storedFavorites.contains(where: { $0.id == item.id }) {
            storedFavorites.insert(item, at: 0)
        }
    }

    public func removeFavorite(mediaID: String) async throws {
        storedFavorites.removeAll { $0.id == mediaID }
    }

    public func watchedItems() async throws -> [WatchedMediaItem] {
        storedWatchedItems
    }

    public func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {
        upsert(item)
        storedWatchedItems.removeAll { $0.item.id == item.id }
        storedWatchedItems.insert(WatchedMediaItem(item: item, positionSeconds: positionSeconds), at: 0)
    }

    public func removeFromHistory(mediaID: String) async throws {
        storedWatchedItems.removeAll { $0.item.id == mediaID }
    }

    public func ratedItems() async throws -> [RatedMediaItem] {
        storedRatedItems
    }

    public func setRating(_ item: MediaItem, rating: Int) async throws {
        upsert(item)
        storedRatedItems.removeAll { $0.item.id == item.id }
        storedRatedItems.insert(RatedMediaItem(item: item, rating: rating), at: 0)
    }

    public func lists() async throws -> [UserList] {
        storedLists
    }

    public func defaultList() async throws -> UserList {
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

    public func createList(name: String) async throws -> UserList {
        try await createList(name: name, description: nil)
    }

    public func createList(name: String, description: String?) async throws -> UserList {
        let list = UserList(name: name, description: description)
        storedLists.insert(list, at: 0)
        return list
    }

    public func renameList(id: String, name: String, description: String?) async throws {
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

    public func deleteList(id: String) async throws {
        storedLists.removeAll { $0.id == id && !$0.isDefault }
    }

    public func add(_ item: MediaItem, to listID: String) async throws {
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

    public func remove(_ mediaID: String, from listID: String) async throws {
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

    public func items(in listID: String) async throws -> [MediaItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return storedItems.filter { list.itemIDs.contains($0.id) }
    }

    public func watchlistItems(in listID: String) async throws -> [WatchlistItem] {
        guard let list = storedLists.first(where: { $0.id == listID }) else { return [] }
        return list.itemIDs.compactMap { mediaID in
            storedWatchlistItems[watchlistKey(listID: listID, mediaID: mediaID)]
        }
    }

    public func updateWatchlistItem(listID: String, mediaID: String, priority: WatchlistPriority, remindLaterAt: Date?) async throws {
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
        storedItems.insert(item, at: 0)
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
