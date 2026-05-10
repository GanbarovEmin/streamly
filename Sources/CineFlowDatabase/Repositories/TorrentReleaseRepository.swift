import CineFlowCore
import Foundation
import GRDB

public final class TorrentReleaseRepository {
    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public func upsert(
        _ release: TorrentRelease,
        mediaID: String,
        sourceProviderID: String = "mock",
        magnetURI: String? = nil,
        sizeBytes: Int64? = nil
    ) async throws {
        try databaseManager.write { db in
            try db.execute(
                sql: """
                    INSERT INTO torrent_releases (id, media_id, title, magnet_uri, source_provider_id, quality, seeders, size_bytes, added_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title,
                        magnet_uri = excluded.magnet_uri,
                        source_provider_id = excluded.source_provider_id,
                        quality = excluded.quality,
                        seeders = excluded.seeders,
                        size_bytes = excluded.size_bytes
                    """,
                arguments: [
                    release.id,
                    mediaID,
                    release.title,
                    magnetURI ?? release.magnetURI,
                    sourceProviderID == "mock" ? release.sourceId : sourceProviderID,
                    release.quality.rawValue,
                    release.seeders,
                    sizeBytes,
                    timestamp()
                ]
            )
        }
    }

    public func releases(mediaID: String) async throws -> [TorrentRelease] {
        try databaseManager.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM torrent_releases
                    WHERE media_id = ?
                    ORDER BY quality DESC, seeders DESC
                    """,
                arguments: [mediaID]
            ).map {
                TorrentRelease(
                    id: $0["id"],
                    sourceId: $0["source_provider_id"],
                    sourceName: $0["source_provider_id"],
                    title: $0["title"],
                    magnetURI: $0["magnet_uri"],
                    quality: ReleaseQuality(rawValue: $0["quality"]) ?? .unknown,
                    seeders: $0["seeders"],
                    sizeBytes: $0["size_bytes"]
                )
            }
        }
    }
}
