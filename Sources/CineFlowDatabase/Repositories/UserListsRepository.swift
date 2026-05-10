import CineFlowCore
import Foundation
import GRDB

public struct UserListRecord: Equatable, Sendable {
    public let id: String
    public let name: String
}

public final class UserListsRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    @discardableResult
    public func createList(name: String, id: String = UUID().uuidString) async throws -> UserListRecord {
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_lists (id, name, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [id, name, timestamp(), timestamp()]
            )
        }
        return UserListRecord(id: id, name: name)
    }

    public func addItem(mediaID: String, to listID: String) async throws {
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_list_items (list_id, media_id, added_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(list_id, media_id) DO NOTHING
                    """,
                arguments: [listID, mediaID, timestamp()]
            )
        }
    }

    public func lists() async throws -> [UserListRecord] {
        try databaseManager.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM user_lists ORDER BY updated_at DESC").map {
                UserListRecord(id: $0["id"], name: $0["name"])
            }
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
            ).map(mediaItem(from:))
        }
    }
}
