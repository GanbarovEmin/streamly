import CineFlowCore
import Foundation
import GRDB

public enum DatabaseSeeder {
    public static func seedDevelopmentData(in databaseManager: DatabaseManager) throws {
        let existingCount = try databaseManager.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_items") ?? 0
        }
        guard existingCount == 0 else { return }

        try databaseManager.write { db in
            let mediaRepository = MediaRepository(databaseManager: databaseManager)
            let matrix = MediaItem(
                id: "tmdb:movie:603",
                title: "The Matrix",
                kind: .movie,
                overview: "A computer hacker learns about the true nature of reality.",
                releaseYear: 1999,
                posterPath: nil
            )
            let arrival = MediaItem(
                id: "tmdb:movie:329865",
                title: "Arrival",
                kind: .movie,
                overview: "A linguist works with the military to communicate with alien lifeforms.",
                releaseYear: 2016,
                posterPath: nil
            )

            try mediaRepository.upsert(matrix, in: db)
            try mediaRepository.upsert(arrival, in: db)
            try db.execute(sql: "INSERT INTO library_items (media_id, added_at) VALUES (?, ?)", arguments: [matrix.id, timestamp()])
            try db.execute(sql: "INSERT INTO library_items (media_id, added_at) VALUES (?, ?)", arguments: [arrival.id, timestamp()])
            try db.execute(sql: "INSERT INTO user_lists (id, name, created_at, updated_at) VALUES (?, ?, ?, ?)", arguments: ["dev-favorites", "Favorites", timestamp(), timestamp()])
            try db.execute(sql: "INSERT INTO user_list_items (list_id, media_id, added_at) VALUES (?, ?, ?)", arguments: ["dev-favorites", matrix.id, timestamp()])
            try db.execute(sql: "INSERT INTO playback_progress (media_id, position_seconds, duration_seconds, updated_at) VALUES (?, ?, ?, ?)", arguments: [matrix.id, 1840, 8160, timestamp()])
        }
    }
}
