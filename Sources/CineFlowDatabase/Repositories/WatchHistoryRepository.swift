import CineFlowCore
import Foundation
import GRDB

public typealias WatchHistoryEntry = WatchHistoryItem

public final class WatchHistoryRepository: WatchHistoryRepositoryProtocol {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func record(mediaID: String, positionSeconds: Double, watchedAt: Date = Date()) async throws {
        try await record(
            PlaybackProgress(
                mediaID: mediaID,
                positionSeconds: positionSeconds,
                durationSeconds: nil,
                lastWatchedAt: watchedAt
            )
        )
    }

    public func record(_ progress: PlaybackProgress) async throws {
        try databaseManager.write { db in
            try ensureMediaItemExists(db: db, mediaID: progress.mediaID)
            try db.execute(
                sql: """
                    INSERT INTO watch_history (
                        id,
                        media_id,
                        episode_id,
                        release_id,
                        watched_at,
                        position_seconds,
                        duration_seconds,
                        progress_percent,
                        completed
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    progress.mediaID,
                    progress.episodeID,
                    progress.releaseID,
                    timestamp(progress.lastWatchedAt),
                    progress.positionSeconds,
                    progress.durationSeconds,
                    progress.progressPercent,
                    progress.completed ? 1 : 0
                ]
            )
        }
    }

    public func entries(limit: Int = 50) async throws -> [WatchHistoryItem] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM watch_history ORDER BY watched_at DESC LIMIT ?",
                arguments: [limit]
            ).map(watchHistoryItem(from:))
        }
    }

    public func clear() async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM watch_history")
        }
    }
}

func watchHistoryItem(from row: Row) -> WatchHistoryItem {
    WatchHistoryItem(
        id: row["id"],
        mediaID: row["media_id"],
        episodeID: row["episode_id"],
        releaseID: row["release_id"],
        positionSeconds: row["position_seconds"],
        durationSeconds: row["duration_seconds"],
        progressPercent: row["progress_percent"],
        lastWatchedAt: date(from: row["watched_at"]),
        completed: (row["completed"] as Int) == 1
    )
}
