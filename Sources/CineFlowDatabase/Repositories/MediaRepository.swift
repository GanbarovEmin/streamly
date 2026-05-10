import CineFlowCore
import Foundation
import GRDB

public final class MediaRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func upsert(_ item: MediaItem) async throws {
        try databaseManager.write { db in
            try upsert(item, in: db)
        }
    }

    public func item(id: String) async throws -> MediaItem? {
        try databaseManager.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM media_items WHERE id = ?", arguments: [id]).map(mediaItem(from:))
        }
    }

    public func allItems() async throws -> [MediaItem] {
        try databaseManager.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM media_items ORDER BY title COLLATE NOCASE").map(mediaItem(from:))
        }
    }

    public func search(query: String) async throws -> [MediaItem] {
        let likeQuery = "%\(query)%"
        return try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM media_items WHERE title LIKE ? ORDER BY title COLLATE NOCASE",
                arguments: [likeQuery]
            ).map(mediaItem(from:))
        }
    }

    func upsert(_ item: MediaItem, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO media_items (id, title, kind, overview, release_year, poster_path, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    kind = excluded.kind,
                    overview = excluded.overview,
                    release_year = excluded.release_year,
                    poster_path = excluded.poster_path,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                item.id,
                item.title,
                item.kind.rawValue,
                item.overview,
                item.releaseYear,
                item.posterPath,
                timestamp()
            ]
        )
    }
}
