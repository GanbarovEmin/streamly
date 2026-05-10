import Foundation
import GRDB

public final class RatingsRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func setRating(mediaID: String, rating: Int) async throws {
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_ratings (media_id, rating, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(media_id) DO UPDATE SET
                        rating = excluded.rating,
                        updated_at = excluded.updated_at
                    """,
                arguments: [mediaID, rating, timestamp()]
            )
        }
    }

    public func rating(mediaID: String) async throws -> Int? {
        try databaseManager.read { db in
            try Int.fetchOne(db, sql: "SELECT rating FROM user_ratings WHERE media_id = ?", arguments: [mediaID])
        }
    }
}
