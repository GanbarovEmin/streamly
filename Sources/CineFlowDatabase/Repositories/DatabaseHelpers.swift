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
    MediaItem(
        id: row["id"],
        title: row["title"],
        kind: MediaKind(rawValue: row["kind"]) ?? .movie,
        overview: row["overview"],
        releaseYear: row["release_year"],
        posterPath: row["poster_path"]
    )
}

func timestamp(_ date: Date = Date()) -> String {
    ISO8601DateFormatter().string(from: date)
}

func date(from timestamp: String) -> Date {
    ISO8601DateFormatter().date(from: timestamp) ?? Date(timeIntervalSince1970: 0)
}
