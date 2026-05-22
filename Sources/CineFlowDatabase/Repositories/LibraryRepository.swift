import CineFlowCore
import Foundation
import GRDB

public final class DatabaseLibraryRepository: LibraryRepositoryProtocol {
    private let databaseManager: DatabaseManager
    private let mediaRepository: MediaRepository
    private let defaultListID = "default-watchlist"
    private let defaultListName = "Хочу посмотреть"
    private let defaultListDescription = "Фильмы и сериалы, которые вы хотите посмотреть позже."

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        mediaRepository = MediaRepository(databaseManager: databaseManager)
    }

    public func items() async throws -> [MediaItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT media_items.*
                    FROM media_items
                    INNER JOIN library_items ON library_items.media_id = media_items.id
                    ORDER BY library_items.added_at DESC
                    """
            ).map(CineFlowDatabase.mediaItem(from:))
        }
    }

    public func mediaItem(id: String) async throws -> MediaItem? {
        try await mediaRepository.item(id: id)
    }

    public func libraryEntries() async throws -> [LibraryItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT media_id, added_at, source
                    FROM library_items
                    ORDER BY added_at DESC
                    """
            ).map { row in
                LibraryItem(
                    mediaID: row["media_id"],
                    addedAt: date(from: row["added_at"]),
                    source: row["source"] ?? "manual"
                )
            }
        }
    }

    public func add(_ item: MediaItem) async throws {
        try databaseManager.write { db in
            try mediaRepository.upsert(item, in: db)
            try db.execute(
                sql: """
                    INSERT INTO library_items (media_id, added_at)
                    VALUES (?, ?)
                    ON CONFLICT(media_id) DO UPDATE SET added_at = excluded.added_at
                    """,
                arguments: [item.id, timestamp()]
            )
        }
    }

    public func remove(mediaID: String) async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM library_items WHERE media_id = ?", arguments: [mediaID])
            try db.execute(sql: "DELETE FROM favorite_items WHERE media_id = ?", arguments: [mediaID])
            try db.execute(sql: "DELETE FROM user_list_items WHERE media_id = ?", arguments: [mediaID])
            try db.execute(sql: "DELETE FROM watch_history WHERE media_id = ?", arguments: [mediaID])
            try db.execute(sql: "DELETE FROM user_ratings WHERE media_id = ?", arguments: [mediaID])
        }
    }

    public func favorites() async throws -> [MediaItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT media_items.*
                    FROM media_items
                    INNER JOIN favorite_items ON favorite_items.media_id = media_items.id
                    ORDER BY favorite_items.added_at DESC
                    """
            ).map(CineFlowDatabase.mediaItem(from:))
        }
    }

    public func addFavorite(_ item: MediaItem) async throws {
        try databaseManager.write { db in
            try mediaRepository.upsert(item, in: db)
            try db.execute(
                sql: """
                    INSERT INTO library_items (media_id, added_at)
                    VALUES (?, ?)
                    ON CONFLICT(media_id) DO NOTHING
                    """,
                arguments: [item.id, timestamp()]
            )
            try db.execute(
                sql: """
                    INSERT INTO favorite_items (media_id, added_at)
                    VALUES (?, ?)
                    ON CONFLICT(media_id) DO UPDATE SET added_at = excluded.added_at
                    """,
                arguments: [item.id, timestamp()]
            )
        }
    }

    public func removeFavorite(mediaID: String) async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM favorite_items WHERE media_id = ?", arguments: [mediaID])
        }
    }

    public func watchedItems() async throws -> [WatchedMediaItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT media_items.*, watch_history.watched_at AS history_watched_at, watch_history.position_seconds AS history_position_seconds
                    FROM watch_history
                    INNER JOIN media_items ON media_items.id = watch_history.media_id
                    INNER JOIN (
                        SELECT media_id, MAX(watched_at) AS latest_watched_at
                        FROM watch_history
                        GROUP BY media_id
                    ) latest ON latest.media_id = watch_history.media_id AND latest.latest_watched_at = watch_history.watched_at
                    ORDER BY watch_history.watched_at DESC
                    """
            ).map { row in
                WatchedMediaItem(
                    item: CineFlowDatabase.mediaItem(from: row),
                    watchedAt: date(from: row["history_watched_at"]),
                    positionSeconds: row["history_position_seconds"]
                )
            }
        }
    }

    public func markWatched(_ item: MediaItem, positionSeconds: Double) async throws {
        try databaseManager.write { db in
            try mediaRepository.upsert(item, in: db)
            try db.execute(
                sql: """
                    INSERT INTO library_items (media_id, added_at)
                    VALUES (?, ?)
                    ON CONFLICT(media_id) DO NOTHING
                    """,
                arguments: [item.id, timestamp()]
            )
            try db.execute(
                sql: """
                    INSERT INTO watch_history (id, media_id, watched_at, position_seconds)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, item.id, timestamp(), positionSeconds]
            )
        }
    }

    public func removeFromHistory(mediaID: String) async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM watch_history WHERE media_id = ?", arguments: [mediaID])
            try db.execute(sql: "DELETE FROM playback_progress WHERE media_id = ?", arguments: [mediaID])
        }
    }

    public func ratedItems() async throws -> [RatedMediaItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT media_items.*, user_ratings.rating AS user_rating, user_ratings.updated_at AS rating_updated_at
                    FROM user_ratings
                    INNER JOIN media_items ON media_items.id = user_ratings.media_id
                    ORDER BY user_ratings.updated_at DESC
                    """
            ).map { row in
                RatedMediaItem(
                    item: CineFlowDatabase.mediaItem(from: row),
                    rating: row["user_rating"],
                    updatedAt: date(from: row["rating_updated_at"])
                )
            }
        }
    }

    public func setRating(_ item: MediaItem, rating: Int) async throws {
        let boundedRating = min(max(rating, 1), 10)
        try databaseManager.write { db in
            try mediaRepository.upsert(item, in: db)
            try db.execute(
                sql: """
                    INSERT INTO library_items (media_id, added_at)
                    VALUES (?, ?)
                    ON CONFLICT(media_id) DO NOTHING
                    """,
                arguments: [item.id, timestamp()]
            )
            try db.execute(
                sql: """
                    INSERT INTO user_ratings (media_id, rating, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(media_id) DO UPDATE SET
                        rating = excluded.rating,
                        updated_at = excluded.updated_at
                    """,
                arguments: [item.id, boundedRating, timestamp()]
            )
        }
    }

    public func lists() async throws -> [UserList] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, name, description, created_at, updated_at, is_default FROM user_lists ORDER BY is_default DESC, updated_at DESC"
            ).map { row in
                try userList(from: row, db: db)
            }
        }
    }

    public func defaultList() async throws -> UserList {
        if let existing = try await list(id: defaultListID) {
            return existing
        }

        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_lists (id, name, description, created_at, updated_at, is_default)
                    VALUES (?, ?, ?, ?, ?, 1)
                    ON CONFLICT(id) DO NOTHING
                    """,
                arguments: [defaultListID, defaultListName, defaultListDescription, timestamp(), timestamp()]
            )
        }

        return try await list(id: defaultListID) ?? UserList(
            id: defaultListID,
            name: defaultListName,
            description: defaultListDescription,
            isDefault: true
        )
    }

    public func createList(name: String) async throws -> UserList {
        try await createList(name: name, description: nil)
    }

    public func createList(name: String, description: String?) async throws -> UserList {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = UserList(
            name: trimmedName.isEmpty ? "New List" : trimmedName,
            description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription
        )
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_lists (id, name, description, created_at, updated_at, is_default)
                    VALUES (?, ?, ?, ?, ?, 0)
                    """,
                arguments: [list.id, list.name, list.description, timestamp(list.createdAt), timestamp(list.updatedAt)]
            )
        }
        return list
    }

    public func renameList(id: String, name: String, description: String?) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    UPDATE user_lists
                    SET name = ?, description = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    trimmedName.isEmpty ? "Untitled List" : trimmedName,
                    trimmedDescription?.isEmpty == true ? nil : trimmedDescription,
                    timestamp(),
                    id
                ]
            )
        }
    }

    public func deleteList(id: String) async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM user_lists WHERE id = ? AND is_default = 0", arguments: [id])
        }
    }

    public func add(_ item: MediaItem, to listID: String) async throws {
        try databaseManager.write { db in
            try mediaRepository.upsert(item, in: db)
            try db.execute(
                sql: """
                    INSERT INTO library_items (media_id, added_at)
                    VALUES (?, ?)
                    ON CONFLICT(media_id) DO NOTHING
                    """,
                arguments: [item.id, timestamp()]
            )
            try db.execute(
                sql: """
                    INSERT INTO user_list_items (list_id, media_id, added_at, priority, initial_quality, initial_hdr)
                    VALUES (?, ?, ?, 'normal', ?, ?)
                    ON CONFLICT(list_id, media_id) DO NOTHING
                    """,
                arguments: [
                    listID,
                    item.id,
                    timestamp(),
                    item.bestWatchlistReleaseSnapshot.quality.rawValue,
                    item.bestWatchlistReleaseSnapshot.hdr.rawValue
                ]
            )
            try db.execute(sql: "UPDATE user_lists SET updated_at = ? WHERE id = ?", arguments: [timestamp(), listID])
        }
    }

    public func remove(_ mediaID: String, from listID: String) async throws {
        try databaseManager.write { db in
            try db.execute(
                sql: "DELETE FROM user_list_items WHERE list_id = ? AND media_id = ?",
                arguments: [listID, mediaID]
            )
            try db.execute(sql: "UPDATE user_lists SET updated_at = ? WHERE id = ?", arguments: [timestamp(), listID])
        }
    }

    public func items(in listID: String) async throws -> [MediaItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT media_items.*
                    FROM media_items
                    INNER JOIN user_list_items ON user_list_items.media_id = media_items.id
                    WHERE user_list_items.list_id = ?
                    ORDER BY user_list_items.added_at DESC
                    """,
                arguments: [listID]
            ).map(CineFlowDatabase.mediaItem(from:))
        }
    }

    public func watchlistItems(in listID: String) async throws -> [WatchlistItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT list_id, media_id, added_at, priority, remind_later_at, initial_quality, initial_hdr
                    FROM user_list_items
                    WHERE list_id = ?
                    ORDER BY added_at DESC
                    """,
                arguments: [listID]
            ).map { row in
                let qualityRaw: Int = row["initial_quality"]
                let hdrRaw: String = row["initial_hdr"]
                let reminder: String? = row["remind_later_at"]
                return WatchlistItem(
                    listID: row["list_id"],
                    mediaID: row["media_id"],
                    priority: WatchlistPriority(rawValue: row["priority"]) ?? .normal,
                    remindLaterAt: reminder.map(date(from:)),
                    addedAt: date(from: row["added_at"]),
                    initialQuality: ReleaseQuality(rawValue: qualityRaw) ?? .unknown,
                    initialHDR: HDRFormat(rawValue: hdrRaw) ?? .unknown
                )
            }
        }
    }

    public func updateWatchlistItem(listID: String, mediaID: String, priority: WatchlistPriority, remindLaterAt: Date?) async throws {
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    UPDATE user_list_items
                    SET priority = ?, remind_later_at = ?
                    WHERE list_id = ? AND media_id = ?
                    """,
                arguments: [priority.rawValue, remindLaterAt.map(timestamp), listID, mediaID]
            )
            try db.execute(sql: "UPDATE user_lists SET updated_at = ? WHERE id = ?", arguments: [timestamp(), listID])
        }
    }

    private func list(id: String) async throws -> UserList? {
        try databaseManager.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT id, name, description, created_at, updated_at, is_default FROM user_lists WHERE id = ?",
                arguments: [id]
            ).map { row in
                try userList(from: row, db: db)
            }
        }
    }

    private func userList(from row: Row, db: Database) throws -> UserList {
        let listID: String = row["id"]
        let itemIDs = try String.fetchAll(
            db,
            sql: "SELECT media_id FROM user_list_items WHERE list_id = ? ORDER BY added_at DESC",
            arguments: [listID]
        )
        return UserList(
            id: listID,
            name: row["name"],
            description: row["description"],
            itemIDs: itemIDs,
            createdAt: date(from: row["created_at"]),
            updatedAt: date(from: row["updated_at"]),
            isDefault: (row["is_default"] as Int) == 1
        )
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
