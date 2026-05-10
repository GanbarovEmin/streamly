import CineFlowCore
import Foundation
import GRDB

public final class DatabaseUserMediaSourceRepository: UserMediaSourceRepositoryProtocol {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func sources(for mediaID: String) async throws -> [UserMediaSource] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM user_media_sources
                    WHERE media_id = ?
                    ORDER BY updated_at DESC
                    """,
                arguments: [mediaID]
            ).compactMap(source(from:))
        }
    }

    public func source(id: String) async throws -> UserMediaSource? {
        try databaseManager.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM user_media_sources WHERE id = ?", arguments: [id]).flatMap(source(from:))
        }
    }

    public func save(_ source: UserMediaSource) async throws {
        try databaseManager.write { db in
            let updatedAt = timestamp(source.updatedAt)
            try db.execute(
                sql: """
                    INSERT INTO user_media_sources (
                        id, media_id, display_name, kind, url, magnet_uri, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        media_id = excluded.media_id,
                        display_name = excluded.display_name,
                        kind = excluded.kind,
                        url = excluded.url,
                        magnet_uri = excluded.magnet_uri,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    source.id,
                    source.mediaID,
                    source.displayName,
                    source.kind.rawValue,
                    source.url?.absoluteString,
                    source.magnetURI,
                    timestamp(source.createdAt),
                    updatedAt
                ]
            )
        }
    }

    public func delete(id: String) async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM user_media_sources WHERE id = ?", arguments: [id])
        }
    }
}

private func source(from row: Row) -> UserMediaSource? {
    guard
        let kindRaw: String = row["kind"],
        let kind = UserMediaSourceKind(rawValue: kindRaw)
    else {
        return nil
    }

    let urlString: String? = row["url"]
    let createdAt: String = row["created_at"]
    let updatedAt: String = row["updated_at"]

    return UserMediaSource(
        id: row["id"],
        mediaID: row["media_id"],
        displayName: row["display_name"],
        kind: kind,
        url: urlString.flatMap(URL.init(string:)),
        magnetURI: row["magnet_uri"],
        createdAt: date(from: createdAt),
        updatedAt: date(from: updatedAt)
    )
}
