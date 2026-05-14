import CineFlowCore
import Foundation
import GRDB

enum DatabaseEncoding {
    static let jsonEncoder = JSONEncoder()
    static let jsonDecoder = JSONDecoder()

    static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try jsonEncoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try jsonDecoder.decode(T.self, from: Data(json.utf8))
    }
}

func mediaItem(from row: Row) -> MediaItem {
    let metadataJSON: String? = row["metadata_json"]
    let metadata = metadataJSON.flatMap { try? DatabaseEncoding.decode(MediaMetadata.self, from: $0) }
    return MediaItem(
        id: row["id"],
        title: row["title"],
        kind: MediaKind(rawValue: row["kind"]) ?? .movie,
        overview: row["overview"],
        releaseYear: row["release_year"],
        posterPath: row["poster_path"],
        metadata: metadata
    )
}

func ensureMediaItemExists(db: Database, mediaID: String) throws {
    let kind = mediaID.contains(":series:") || mediaID.contains(":tv:") ? MediaKind.series : .movie
    try db.execute(
        sql: """
            INSERT OR IGNORE INTO media_items (
                id,
                title,
                kind,
                overview,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, '', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            """,
        arguments: [mediaID, mediaID, kind.rawValue]
    )
}

func timestamp(_ date: Date = Date()) -> String {
    ISO8601DateFormatter().string(from: date)
}

func date(from timestamp: String) -> Date {
    ISO8601DateFormatter().date(from: timestamp) ?? Date(timeIntervalSince1970: 0)
}
