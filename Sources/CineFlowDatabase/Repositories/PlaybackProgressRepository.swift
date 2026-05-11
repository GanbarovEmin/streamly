import CineFlowCore
import Foundation
import GRDB

public typealias PlaybackProgressRecord = PlaybackProgress

public final class PlaybackProgressRepository: PlaybackProgressRepositoryProtocol {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func setProgress(mediaID: String, positionSeconds: Double, durationSeconds: Double?) async throws {
        try await saveProgress(
            PlaybackProgress(
                mediaID: mediaID,
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds
            )
        )
    }

    public func saveProgress(_ progress: PlaybackProgress) async throws {
        try databaseManager.write { db in
            try ensureMediaItemExists(db: db, mediaID: progress.mediaID)
            try db.execute(
                sql: """
                    INSERT INTO playback_progress (
                        progress_key,
                        media_id,
                        episode_id,
                        release_id,
                        position_seconds,
                        duration_seconds,
                        progress_percent,
                        last_watched_at,
                        completed,
                        updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(progress_key) DO UPDATE SET
                        episode_id = excluded.episode_id,
                        release_id = excluded.release_id,
                        position_seconds = excluded.position_seconds,
                        duration_seconds = excluded.duration_seconds,
                        progress_percent = excluded.progress_percent,
                        last_watched_at = excluded.last_watched_at,
                        completed = excluded.completed,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    progressKey(mediaID: progress.mediaID, episodeID: progress.episodeID),
                    progress.mediaID,
                    progress.episodeID,
                    progress.releaseID,
                    progress.positionSeconds,
                    progress.durationSeconds,
                    progress.progressPercent,
                    timestamp(progress.lastWatchedAt),
                    progress.completed ? 1 : 0,
                    timestamp(progress.updatedAt)
                ]
            )
        }
    }

    public func progress(mediaID: String) async throws -> PlaybackProgress? {
        try await progress(mediaID: mediaID, episodeID: nil)
    }

    public func progress(mediaID: String, episodeID: String?) async throws -> PlaybackProgress? {
        try databaseManager.read { db in
            if let episodeID {
                return try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM playback_progress WHERE progress_key = ?",
                    arguments: [progressKey(mediaID: mediaID, episodeID: episodeID)]
                ).map(playbackProgress(from:))
            }

            return try Row.fetchOne(
                db,
                sql: "SELECT * FROM playback_progress WHERE media_id = ?",
                arguments: [mediaID]
            ).map(playbackProgress(from:))
        }
    }

    public func continueWatching(includeCompleted: Bool = false) async throws -> [PlaybackProgress] {
        try databaseManager.read { db in
            let sql: String
            let arguments: StatementArguments
            if includeCompleted {
                sql = "SELECT * FROM playback_progress ORDER BY last_watched_at DESC"
                arguments = []
            } else {
                sql = "SELECT * FROM playback_progress WHERE completed = 0 ORDER BY last_watched_at DESC"
                arguments = []
            }
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(playbackProgress(from:))
        }
    }

    public func clearProgress(mediaID: String, episodeID: String?) async throws {
        try databaseManager.write { db in
            if let episodeID {
                try db.execute(
                    sql: "DELETE FROM playback_progress WHERE progress_key = ?",
                    arguments: [progressKey(mediaID: mediaID, episodeID: episodeID)]
                )
            } else {
                try db.execute(sql: "DELETE FROM playback_progress WHERE media_id = ?", arguments: [mediaID])
            }
        }
    }
}

func playbackProgress(from row: Row) -> PlaybackProgress {
    PlaybackProgress(
        mediaID: row["media_id"],
        episodeID: row["episode_id"],
        releaseID: row["release_id"],
        positionSeconds: row["position_seconds"],
        durationSeconds: row["duration_seconds"],
        progressPercent: row["progress_percent"],
        lastWatchedAt: date(from: row["last_watched_at"] ?? row["updated_at"]),
        completed: (row["completed"] as Int) == 1,
        updatedAt: date(from: row["updated_at"])
    )
}

private func progressKey(mediaID: String, episodeID: String?) -> String {
    guard let episodeID, !episodeID.isEmpty else { return mediaID }
    return "\(mediaID):\(episodeID)"
}
