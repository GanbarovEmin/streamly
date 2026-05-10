import Foundation
import GRDB

public struct CachedImageRecord: Equatable, Sendable {
    public let url: String
    public let localPath: String
    public let fileSize: Int64
    public let createdAt: String
    public let lastAccessedAt: String

    public init(url: String, localPath: String, fileSize: Int64, createdAt: String, lastAccessedAt: String) {
        self.url = url
        self.localPath = localPath
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
    }
}

public final class CacheRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func setMetadata(cacheKey: String, provider: String, payloadJSON: String, expiresAt: String? = nil) async throws {
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO metadata_cache (cache_key, provider, payload_json, expires_at, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(cache_key) DO UPDATE SET
                        provider = excluded.provider,
                        payload_json = excluded.payload_json,
                        expires_at = excluded.expires_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: [cacheKey, provider, payloadJSON, expiresAt, timestamp()]
            )
        }
    }

    public func metadata(cacheKey: String) async throws -> String? {
        try databaseManager.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT payload_json FROM metadata_cache WHERE cache_key = ?",
                arguments: [cacheKey]
            )
        }
    }

    public func setCachedImage(url: String, localPath: String, width: Int? = nil, height: Int? = nil) async throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? NSNumber)?.int64Value ?? 0
        let now = timestamp()
        try await upsertCachedImage(url: url, localPath: localPath, fileSize: size, createdAt: now, lastAccessedAt: now, width: width, height: height)
    }

    public func upsertCachedImage(
        url: String,
        localPath: String,
        fileSize: Int64,
        createdAt: String? = nil,
        lastAccessedAt: String? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) async throws {
        let createdAt = createdAt ?? timestamp()
        let lastAccessedAt = lastAccessedAt ?? timestamp()
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cached_images (url, local_path, width, height, cached_at, file_size, created_at, last_accessed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(url) DO UPDATE SET
                        local_path = excluded.local_path,
                        width = excluded.width,
                        height = excluded.height,
                        cached_at = excluded.cached_at,
                        file_size = excluded.file_size,
                        last_accessed_at = excluded.last_accessed_at
                    """,
                arguments: [url, localPath, width, height, createdAt, fileSize, createdAt, lastAccessedAt]
            )
        }
    }

    public func cachedImage(url: String) async throws -> String? {
        try databaseManager.read { db in
            try String.fetchOne(db, sql: "SELECT local_path FROM cached_images WHERE url = ?", arguments: [url])
        }
    }

    public func cachedImageRecord(url: String, touch: Bool = false) async throws -> CachedImageRecord? {
        try databaseManager.write { db in
            if touch {
                try db.execute(
                    sql: "UPDATE cached_images SET last_accessed_at = ? WHERE url = ?",
                    arguments: [timestamp(), url]
                )
            }

            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT url, local_path, file_size, created_at, last_accessed_at
                    FROM cached_images
                    WHERE url = ?
                    """,
                arguments: [url]
            ) else {
                return nil
            }
            return makeCachedImageRecord(from: row)
        }
    }

    public func cachedImageRecords() async throws -> [CachedImageRecord] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT url, local_path, file_size, created_at, last_accessed_at
                    FROM cached_images
                    ORDER BY last_accessed_at ASC
                    """
            ).map(makeCachedImageRecord(from:))
        }
    }

    public func cachedImageRecordsUnused(before timestamp: String) async throws -> [CachedImageRecord] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT url, local_path, file_size, created_at, last_accessed_at
                    FROM cached_images
                    WHERE last_accessed_at < ?
                    ORDER BY last_accessed_at ASC
                    """,
                arguments: [timestamp]
            ).map(makeCachedImageRecord(from:))
        }
    }

    public func imageCacheSizeBytes() async throws -> Int64 {
        try databaseManager.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(file_size), 0) FROM cached_images") ?? 0
        }
    }

    public func removeCachedImage(url: String) async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM cached_images WHERE url = ?", arguments: [url])
        }
    }

    public func clearImageCache() async throws {
        try databaseManager.write { db in
            try db.execute(sql: "DELETE FROM cached_images")
        }
    }
}

private func makeCachedImageRecord(from row: Row) -> CachedImageRecord {
    CachedImageRecord(
        url: row["url"],
        localPath: row["local_path"],
        fileSize: row["file_size"],
        createdAt: row["created_at"],
        lastAccessedAt: row["last_accessed_at"]
    )
}
