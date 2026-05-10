import Foundation

public struct PlaybackProgress: Identifiable, Codable, Equatable, Sendable {
    public let mediaID: String
    public let episodeID: String?
    public let releaseID: String?
    public let positionSeconds: Double
    public let durationSeconds: Double?
    public let progressPercent: Double
    public let lastWatchedAt: Date
    public let completed: Bool
    public let updatedAt: Date

    public var id: String {
        episodeID.map { "\(mediaID):\($0)" } ?? mediaID
    }

    public init(
        mediaID: String,
        episodeID: String? = nil,
        releaseID: String? = nil,
        positionSeconds: Double,
        durationSeconds: Double?,
        progressPercent: Double? = nil,
        lastWatchedAt: Date = Date(),
        completed: Bool? = nil,
        updatedAt: Date? = nil
    ) {
        self.mediaID = mediaID
        self.episodeID = episodeID
        self.releaseID = releaseID
        self.positionSeconds = max(positionSeconds, 0)
        self.durationSeconds = durationSeconds
        let calculatedPercent: Double
        if let progressPercent {
            calculatedPercent = progressPercent
        } else if let durationSeconds, durationSeconds > 0 {
            calculatedPercent = min(max((max(positionSeconds, 0) / durationSeconds) * 100, 0), 100)
        } else {
            calculatedPercent = 0
        }
        self.progressPercent = calculatedPercent
        self.lastWatchedAt = updatedAt ?? lastWatchedAt
        self.completed = completed ?? (calculatedPercent > 90)
        self.updatedAt = updatedAt ?? lastWatchedAt
    }
}

public struct WatchHistoryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaID: String
    public let episodeID: String?
    public let releaseID: String?
    public let positionSeconds: Double
    public let durationSeconds: Double?
    public let progressPercent: Double
    public let lastWatchedAt: Date
    public let completed: Bool

    public var watchedAt: Date {
        lastWatchedAt
    }

    public init(
        id: String = UUID().uuidString,
        mediaID: String,
        episodeID: String? = nil,
        releaseID: String? = nil,
        watchedAt: Date? = nil,
        positionSeconds: Double,
        durationSeconds: Double? = nil,
        progressPercent: Double? = nil,
        lastWatchedAt: Date? = nil,
        completed: Bool? = nil
    ) {
        self.id = id
        self.mediaID = mediaID
        self.episodeID = episodeID
        self.releaseID = releaseID
        self.positionSeconds = max(positionSeconds, 0)
        self.durationSeconds = durationSeconds
        let calculatedPercent: Double
        if let progressPercent {
            calculatedPercent = progressPercent
        } else if let durationSeconds, durationSeconds > 0 {
            calculatedPercent = min(max((max(positionSeconds, 0) / durationSeconds) * 100, 0), 100)
        } else {
            calculatedPercent = 0
        }
        self.progressPercent = calculatedPercent
        self.lastWatchedAt = lastWatchedAt ?? watchedAt ?? Date()
        self.completed = completed ?? (calculatedPercent > 90)
    }

    public init(progress: PlaybackProgress, id: String = UUID().uuidString) {
        self.init(
            id: id,
            mediaID: progress.mediaID,
            episodeID: progress.episodeID,
            releaseID: progress.releaseID,
            positionSeconds: progress.positionSeconds,
            durationSeconds: progress.durationSeconds,
            progressPercent: progress.progressPercent,
            lastWatchedAt: progress.lastWatchedAt,
            completed: progress.completed
        )
    }
}

public struct LibraryItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaID: String
    public let addedAt: Date
    public let source: String

    public init(mediaID: String, addedAt: Date = Date(), source: String = "manual") {
        self.id = mediaID
        self.mediaID = mediaID
        self.addedAt = addedAt
        self.source = source
    }
}

public struct UserList: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let itemIDs: [String]
    public let createdAt: Date
    public let updatedAt: Date
    public let isDefault: Bool

    public var itemsCount: Int {
        itemIDs.count
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        itemIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.itemIDs = itemIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDefault = isDefault
    }
}

public struct UserRating: Codable, Equatable, Sendable {
    public let mediaID: String
    public let rating: Int
    public let updatedAt: Date

    public init(mediaID: String, rating: Int, updatedAt: Date = Date()) {
        self.mediaID = mediaID
        self.rating = rating
        self.updatedAt = updatedAt
    }
}

public struct WatchedMediaItem: Identifiable, Codable, Equatable, Sendable {
    public let item: MediaItem
    public let watchedAt: Date
    public let positionSeconds: Double

    public init(item: MediaItem, watchedAt: Date = Date(), positionSeconds: Double = 0) {
        self.item = item
        self.watchedAt = watchedAt
        self.positionSeconds = positionSeconds
    }

    public var id: String {
        item.id
    }
}

public struct RatedMediaItem: Identifiable, Codable, Equatable, Sendable {
    public let item: MediaItem
    public let rating: Int
    public let updatedAt: Date

    public init(item: MediaItem, rating: Int, updatedAt: Date = Date()) {
        self.item = item
        self.rating = min(max(rating, 1), 10)
        self.updatedAt = updatedAt
    }

    public var id: String {
        item.id
    }
}

public struct AudioTrack: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let languageCode: String
    public let displayName: String
    public let codec: String?
    public let channels: String?

    public init(id: String, languageCode: String, displayName: String, codec: String? = nil, channels: String? = nil) {
        self.id = id
        self.languageCode = languageCode
        self.displayName = displayName
        self.codec = codec
        self.channels = channels
    }
}
