import CineFlowCore
import Foundation
import GRDB

public final class DatabaseLibraryPortabilityService: LibraryPortabilityServiceProtocol {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func exportLibraryJSON() async throws -> Data {
        let snapshot = try exportSnapshot()
        return try JSONEncoder.libraryPortability.encode(snapshot)
    }

    public func previewImport(_ data: Data) async throws -> LibraryImportPreview {
        let snapshot = try JSONDecoder.libraryPortability.decode(LibraryExportSnapshot.self, from: data)
        let validationIssues = validate(snapshot)
        let summary = LibraryImportSummary(
            mediaItems: snapshot.mediaItems.count,
            libraryItems: snapshot.libraryItems.count,
            favorites: snapshot.favoriteMediaIDs.count,
            lists: snapshot.lists.count,
            listItems: snapshot.watchlistItems.count,
            watchHistory: snapshot.watchHistory.count,
            ratings: snapshot.ratings.count,
            playbackProgress: snapshot.playbackProgress.count
        )
        return LibraryImportPreview(
            summary: summary,
            duplicateCount: try duplicateCount(for: snapshot),
            validationIssues: validationIssues
        )
    }

    public func importLibraryJSON(_ data: Data, options: LibraryImportOptions = LibraryImportOptions()) async throws -> LibraryImportResult {
        let snapshot = try JSONDecoder.libraryPortability.decode(LibraryExportSnapshot.self, from: data)
        let preview = try await previewImport(data)
        guard preview.canImport else {
            throw LibraryImportError.validationFailed(preview.validationIssues)
        }

        let backupData = options.createBackupBeforeImport ? try await exportLibraryJSON() : nil
        try importSnapshot(snapshot)
        return LibraryImportResult(preview: preview, backupData: backupData)
    }

    private func exportSnapshot() throws -> LibraryExportSnapshot {
        try databaseManager.read { db in
            let referencedMediaIDs = try portableMediaIDs(db)
            let mediaItems = try mediaItems(for: referencedMediaIDs, db: db)
            let libraryItems = try libraryItems(db)
            let favoriteMediaIDs = try String.fetchAll(db, sql: "SELECT media_id FROM favorite_items ORDER BY added_at DESC")
            let lists = try userLists(db)
            let watchlistItems = try watchlistItems(db)
            let watchHistory = try Row.fetchAll(db, sql: "SELECT * FROM watch_history ORDER BY watched_at DESC").map(watchHistoryItem(from:))
            let ratings = try Row.fetchAll(db, sql: "SELECT media_id, rating, updated_at FROM user_ratings ORDER BY updated_at DESC").map { row in
                UserRating(
                    mediaID: row["media_id"],
                    rating: row["rating"],
                    updatedAt: date(from: row["updated_at"])
                )
            }
            let progress = try Row.fetchAll(db, sql: "SELECT * FROM playback_progress ORDER BY updated_at DESC").map(playbackProgress(from:))

            return LibraryExportSnapshot(
                mediaItems: mediaItems,
                libraryItems: libraryItems,
                favoriteMediaIDs: favoriteMediaIDs,
                lists: lists,
                watchlistItems: watchlistItems,
                watchHistory: watchHistory,
                ratings: ratings,
                playbackProgress: progress
            )
        }
    }

    private func importSnapshot(_ snapshot: LibraryExportSnapshot) throws {
        try databaseManager.write { db in
            let listIDMap = try importLists(snapshot.lists, db: db)

            for item in snapshot.mediaItems {
                try upsertPortableMediaItem(item, db: db)
            }
            for item in snapshot.libraryItems {
                try db.execute(
                    sql: """
                        INSERT INTO library_items (media_id, added_at, source)
                        VALUES (?, ?, ?)
                        ON CONFLICT(media_id) DO UPDATE SET
                            added_at = MIN(library_items.added_at, excluded.added_at),
                            source = CASE
                                WHEN library_items.source = 'manual' THEN library_items.source
                                ELSE excluded.source
                            END
                        """,
                    arguments: [item.mediaID, timestamp(item.addedAt), item.source]
                )
            }
            for mediaID in snapshot.favoriteMediaIDs {
                try db.execute(
                    sql: """
                        INSERT INTO favorite_items (media_id, added_at)
                        VALUES (?, ?)
                        ON CONFLICT(media_id) DO NOTHING
                        """,
                    arguments: [mediaID, timestamp()]
                )
            }
            for item in snapshot.watchlistItems {
                let listID = listIDMap[item.listID] ?? item.listID
                try db.execute(
                    sql: """
                        INSERT INTO user_list_items (
                            list_id,
                            media_id,
                            added_at,
                            priority,
                            remind_later_at,
                            initial_quality,
                            initial_hdr
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(list_id, media_id) DO UPDATE SET
                            added_at = MIN(user_list_items.added_at, excluded.added_at),
                            priority = excluded.priority,
                            remind_later_at = COALESCE(excluded.remind_later_at, user_list_items.remind_later_at),
                            initial_quality = excluded.initial_quality,
                            initial_hdr = excluded.initial_hdr
                        """,
                    arguments: [
                        listID,
                        item.mediaID,
                        timestamp(item.addedAt),
                        item.priority.rawValue,
                        item.remindLaterAt.map(timestamp),
                        item.initialQuality.rawValue,
                        item.initialHDR.rawValue
                    ]
                )
                try db.execute(sql: "UPDATE user_lists SET updated_at = ? WHERE id = ?", arguments: [timestamp(), listID])
            }
            for entry in snapshot.watchHistory {
                let existingEventCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM watch_history
                        WHERE media_id = ?
                          AND COALESCE(episode_id, '') = ?
                          AND COALESCE(release_id, '') = ?
                          AND watched_at = ?
                        """,
                    arguments: [
                        entry.mediaID,
                        entry.episodeID ?? "",
                        entry.releaseID ?? "",
                        timestamp(entry.lastWatchedAt)
                    ]
                ) ?? 0
                guard existingEventCount == 0 else { continue }

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
                        ON CONFLICT(id) DO NOTHING
                        """,
                    arguments: [
                        entry.id,
                        entry.mediaID,
                        entry.episodeID,
                        entry.releaseID,
                        timestamp(entry.lastWatchedAt),
                        entry.positionSeconds,
                        entry.durationSeconds,
                        entry.progressPercent,
                        entry.completed ? 1 : 0
                    ]
                )
            }
            for rating in snapshot.ratings {
                try db.execute(
                    sql: """
                        INSERT INTO user_ratings (media_id, rating, updated_at)
                        VALUES (?, ?, ?)
                        ON CONFLICT(media_id) DO UPDATE SET
                            rating = excluded.rating,
                            updated_at = excluded.updated_at
                        WHERE excluded.updated_at >= user_ratings.updated_at
                        """,
                    arguments: [rating.mediaID, rating.rating, timestamp(rating.updatedAt)]
                )
            }
            for progress in snapshot.playbackProgress {
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
                            release_id = excluded.release_id,
                            position_seconds = excluded.position_seconds,
                            duration_seconds = excluded.duration_seconds,
                            progress_percent = excluded.progress_percent,
                            last_watched_at = excluded.last_watched_at,
                            completed = excluded.completed,
                            updated_at = excluded.updated_at
                        WHERE excluded.updated_at >= playback_progress.updated_at
                        """,
                    arguments: [
                        portabilityProgressKey(mediaID: progress.mediaID, episodeID: progress.episodeID),
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
    }

    private func importLists(_ lists: [UserList], db: Database) throws -> [String: String] {
        let existing = try Row.fetchAll(
            db,
            sql: "SELECT id, name, is_default FROM user_lists"
        )
        let existingIDs = Set(existing.map { $0["id"] as String })
        let defaultListID = existing.first { ($0["is_default"] as Int) == 1 }.map { $0["id"] as String }
        var namesToIDs: [String: String] = [:]
        for row in existing {
            namesToIDs[normalizeListName(row["name"] as String)] = row["id"] as String
        }

        var listIDMap: [String: String] = [:]
        for list in lists {
            let targetID: String
            if list.isDefault, let defaultListID {
                targetID = defaultListID
            } else if existingIDs.contains(list.id) {
                targetID = list.id
            } else if let existingNamedID = namesToIDs[normalizeListName(list.name)] {
                targetID = existingNamedID
            } else {
                targetID = list.id
                try db.execute(
                    sql: """
                        INSERT INTO user_lists (id, name, description, created_at, updated_at, is_default)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        list.id,
                        list.name,
                        list.description,
                        timestamp(list.createdAt),
                        timestamp(list.updatedAt),
                        list.isDefault ? 1 : 0
                    ]
                )
                namesToIDs[normalizeListName(list.name)] = list.id
            }

            listIDMap[list.id] = targetID
            try db.execute(
                sql: """
                    UPDATE user_lists
                    SET
                        description = COALESCE(description, ?),
                        updated_at = MAX(updated_at, ?)
                    WHERE id = ?
                    """,
                arguments: [list.description, timestamp(list.updatedAt), targetID]
            )
        }
        return listIDMap
    }

    private func duplicateCount(for snapshot: LibraryExportSnapshot) throws -> Int {
        try databaseManager.read { db in
            var count = 0
            count += try existingCount(table: "media_items", column: "id", values: snapshot.mediaItems.map(\.id), db: db)
            count += try existingCount(table: "library_items", column: "media_id", values: snapshot.libraryItems.map(\.mediaID), db: db)
            count += try existingCount(table: "favorite_items", column: "media_id", values: snapshot.favoriteMediaIDs, db: db)
            count += try existingCount(table: "user_lists", column: "id", values: snapshot.lists.map(\.id), db: db)
            count += try existingCount(table: "watch_history", column: "id", values: snapshot.watchHistory.map(\.id), db: db)
            count += try existingCount(table: "user_ratings", column: "media_id", values: snapshot.ratings.map(\.mediaID), db: db)
            count += try existingCount(
                table: "playback_progress",
                column: "progress_key",
                values: snapshot.playbackProgress.map { portabilityProgressKey(mediaID: $0.mediaID, episodeID: $0.episodeID) },
                db: db
            )
            return count
        }
    }

    private func validate(_ snapshot: LibraryExportSnapshot) -> [String] {
        var issues: [String] = []
        if snapshot.schemaVersion != 1 {
            issues.append("Unsupported library export schema version: \(snapshot.schemaVersion).")
        }

        let mediaIDs = Set(snapshot.mediaItems.map(\.id))
        let listIDs = Set(snapshot.lists.map(\.id))
        appendDuplicateIssues(values: snapshot.mediaItems.map(\.id), label: "Media item", issues: &issues)
        appendDuplicateIssues(values: snapshot.lists.map(\.id), label: "List", issues: &issues)
        appendDuplicateIssues(values: snapshot.watchHistory.map(\.id), label: "Watch history entry", issues: &issues)

        for item in snapshot.mediaItems {
            if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Media item has an empty id.")
            }
            if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append("Media item \(item.id) has an empty title.")
            }
        }
        for mediaID in snapshot.libraryItems.map(\.mediaID) + snapshot.favoriteMediaIDs {
            if !mediaIDs.contains(mediaID) {
                issues.append("Missing media item: \(mediaID).")
            }
        }
        for list in snapshot.lists where list.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("List \(list.id) has an empty name.")
        }
        for item in snapshot.watchlistItems {
            if !listIDs.contains(item.listID) {
                issues.append("Missing list: \(item.listID).")
            }
            if !mediaIDs.contains(item.mediaID) {
                issues.append("Missing media item: \(item.mediaID).")
            }
        }
        for entry in snapshot.watchHistory {
            validateMediaReference(entry.mediaID, mediaIDs: mediaIDs, issues: &issues)
            validateProgressNumbers(
                mediaID: entry.mediaID,
                positionSeconds: entry.positionSeconds,
                durationSeconds: entry.durationSeconds,
                progressPercent: entry.progressPercent,
                issues: &issues
            )
        }
        for rating in snapshot.ratings {
            validateMediaReference(rating.mediaID, mediaIDs: mediaIDs, issues: &issues)
            if !(1...10).contains(rating.rating) {
                issues.append("Rating must be between 1 and 10 for \(rating.mediaID).")
            }
        }
        for progress in snapshot.playbackProgress {
            validateMediaReference(progress.mediaID, mediaIDs: mediaIDs, issues: &issues)
            validateProgressNumbers(
                mediaID: progress.mediaID,
                positionSeconds: progress.positionSeconds,
                durationSeconds: progress.durationSeconds,
                progressPercent: progress.progressPercent,
                issues: &issues
            )
        }
        return issues
    }

    private func portableMediaIDs(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: """
                SELECT media_id FROM library_items
                UNION
                SELECT media_id FROM favorite_items
                UNION
                SELECT media_id FROM user_list_items
                UNION
                SELECT media_id FROM watch_history
                UNION
                SELECT media_id FROM user_ratings
                UNION
                SELECT media_id FROM playback_progress
                ORDER BY media_id
                """
        )
    }

    private func mediaItems(for ids: [String], db: Database) throws -> [MediaItem] {
        guard !ids.isEmpty else { return [] }
        return try Row.fetchAll(
            db,
            sql: "SELECT * FROM media_items WHERE id IN \(placeholders(count: ids.count)) ORDER BY id",
            arguments: StatementArguments(ids)
        ).map(mediaItem(from:))
    }

    private func libraryItems(_ db: Database) throws -> [LibraryItem] {
        try Row.fetchAll(db, sql: "SELECT media_id, added_at, source FROM library_items ORDER BY added_at DESC").map { row in
            LibraryItem(
                mediaID: row["media_id"],
                addedAt: date(from: row["added_at"]),
                source: row["source"] ?? "manual"
            )
        }
    }

    private func userLists(_ db: Database) throws -> [UserList] {
        try Row.fetchAll(
            db,
            sql: "SELECT id, name, description, created_at, updated_at, is_default FROM user_lists ORDER BY is_default DESC, updated_at DESC"
        ).map { row in
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

    private func watchlistItems(_ db: Database) throws -> [WatchlistItem] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT list_id, media_id, added_at, priority, remind_later_at, initial_quality, initial_hdr
                FROM user_list_items
                ORDER BY list_id, added_at DESC
                """
        ).map { row in
            let reminder: String? = row["remind_later_at"]
            return WatchlistItem(
                listID: row["list_id"],
                mediaID: row["media_id"],
                priority: WatchlistPriority(rawValue: row["priority"]) ?? .normal,
                remindLaterAt: reminder.map(date(from:)),
                addedAt: date(from: row["added_at"]),
                initialQuality: ReleaseQuality(rawValue: row["initial_quality"] as Int) ?? .unknown,
                initialHDR: HDRFormat(rawValue: row["initial_hdr"] as String) ?? .unknown
            )
        }
    }

    private func upsertPortableMediaItem(_ item: MediaItem, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO media_items (id, title, kind, overview, release_year, poster_path, metadata_json, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    kind = excluded.kind,
                    overview = excluded.overview,
                    release_year = excluded.release_year,
                    poster_path = excluded.poster_path,
                    metadata_json = excluded.metadata_json,
                    updated_at = excluded.updated_at
                """,
            arguments: [
                item.id,
                item.title,
                item.kind.rawValue,
                item.overview,
                item.releaseYear,
                item.posterPath,
                try item.metadata.map(DatabaseEncoding.jsonString),
                timestamp()
            ]
        )
    }
}

private func appendDuplicateIssues(values: [String], label: String, issues: inout [String]) {
    var seen = Set<String>()
    for value in values where !seen.insert(value).inserted {
        issues.append("\(label) appears more than once: \(value).")
    }
}

private func validateMediaReference(_ mediaID: String, mediaIDs: Set<String>, issues: inout [String]) {
    if !mediaIDs.contains(mediaID) {
        issues.append("Missing media item: \(mediaID).")
    }
}

private func validateProgressNumbers(
    mediaID: String,
    positionSeconds: Double,
    durationSeconds: Double?,
    progressPercent: Double,
    issues: inout [String]
) {
    if !positionSeconds.isFinite || positionSeconds < 0 {
        issues.append("Position must be a non-negative number for \(mediaID).")
    }
    if let durationSeconds, (!durationSeconds.isFinite || durationSeconds < 0) {
        issues.append("Duration must be a non-negative number for \(mediaID).")
    }
    if !progressPercent.isFinite || progressPercent < 0 || progressPercent > 100 {
        issues.append("Progress percent must be between 0 and 100 for \(mediaID).")
    }
}

private func existingCount(table: String, column: String, values: [String], db: Database) throws -> Int {
    let uniqueValues = Array(Set(values))
    guard !uniqueValues.isEmpty else { return 0 }
    return try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM \(table) WHERE \(column) IN \(placeholders(count: uniqueValues.count))",
        arguments: StatementArguments(uniqueValues)
    ) ?? 0
}

private func normalizeListName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func portabilityProgressKey(mediaID: String, episodeID: String?) -> String {
    guard let episodeID, !episodeID.isEmpty else { return mediaID }
    return "\(mediaID):\(episodeID)"
}

private func placeholders(count: Int) -> String {
    "(\(Array(repeating: "?", count: count).joined(separator: ",")))"
}
