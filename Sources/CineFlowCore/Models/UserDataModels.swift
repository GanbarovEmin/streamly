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

public enum WatchlistPriority: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case high
    case normal
    case later

    public var id: String { rawValue }

    public var rank: Int {
        switch self {
        case .high:
            0
        case .normal:
            1
        case .later:
            2
        }
    }
}

public enum WatchlistSortOrder: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case priority
    case addedDate
    case rating
    case runtime
    case quality
    case mood

    public var id: String { rawValue }
}

public enum WatchlistBadge: String, Codable, CaseIterable, Equatable, Sendable {
    case availableIn4KHDR
    case betterReleaseAvailable
    case russianAudioAvailable
}

public struct WatchlistItem: Identifiable, Codable, Equatable, Sendable {
    public let listID: String
    public let mediaID: String
    public let priority: WatchlistPriority
    public let remindLaterAt: Date?
    public let addedAt: Date
    public let initialQuality: ReleaseQuality
    public let initialHDR: HDRFormat

    public var id: String {
        "\(listID):\(mediaID)"
    }

    public init(
        listID: String,
        mediaID: String,
        priority: WatchlistPriority = .normal,
        remindLaterAt: Date? = nil,
        addedAt: Date = Date(),
        initialQuality: ReleaseQuality = .unknown,
        initialHDR: HDRFormat = .unknown
    ) {
        self.listID = listID
        self.mediaID = mediaID
        self.priority = priority
        self.remindLaterAt = remindLaterAt
        self.addedAt = addedAt
        self.initialQuality = initialQuality
        self.initialHDR = initialHDR
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
    public let isOriginal: Bool

    public init(
        id: String,
        languageCode: String,
        displayName: String,
        codec: String? = nil,
        channels: String? = nil,
        isOriginal: Bool? = nil
    ) {
        self.id = id
        self.languageCode = languageCode.lowercased()
        self.displayName = displayName
        self.codec = codec
        self.channels = channels
        self.isOriginal = isOriginal ?? Self.detectOriginalFlag(id: id, languageCode: languageCode, displayName: displayName)
    }

    public var qualityLabel: String {
        let normalizedChannels = normalizedChannelLabel
        let codecFamily = normalizedCodecFamily
        switch (normalizedChannels, codecFamily) {
        case let (channels?, codec?):
            return "\(channels) \(codec)"
        case let (channels?, nil):
            return channels
        case let (nil, codec?):
            return codec
        case (nil, nil):
            return "Audio"
        }
    }

    public var menuTitle: String {
        "\(displayName) · \(qualityLabel)"
    }

    public var qualityScore: Int {
        var score = 0
        switch normalizedChannelLabel {
        case "7.1":
            score += 70
        case "5.1":
            score += 50
        case "Stereo":
            score += 20
        default:
            score += 10
        }

        switch normalizedCodecFamily {
        case "DTS":
            score += 18
        case "Dolby":
            score += 16
        default:
            score += 0
        }
        return score
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case languageCode
        case displayName
        case codec
        case channels
        case isOriginal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        languageCode = try container.decode(String.self, forKey: .languageCode).lowercased()
        displayName = try container.decode(String.self, forKey: .displayName)
        codec = try container.decodeIfPresent(String.self, forKey: .codec)
        channels = try container.decodeIfPresent(String.self, forKey: .channels)
        isOriginal = try container.decodeIfPresent(Bool.self, forKey: .isOriginal)
            ?? Self.detectOriginalFlag(id: id, languageCode: languageCode, displayName: displayName)
    }

    private var normalizedChannelLabel: String? {
        let value = (channels ?? displayName).lowercased()
        if value.contains("7.1") || value.contains("8ch") || value.contains("8 ch") {
            return "7.1"
        }
        if value.contains("5.1") || value.contains("6ch") || value.contains("6 ch") {
            return "5.1"
        }
        if value.contains("stereo") || value.contains("2.0") || value.contains("2ch") || value.contains("2 ch") {
            return "Stereo"
        }
        return channels?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    private var normalizedCodecFamily: String? {
        let value = (codec ?? displayName).lowercased()
        if value.contains("dts") {
            return "DTS"
        }
        if value.contains("dolby") || value.contains("truehd") || value.contains("atmos") || value.contains("ac-3") || value.contains("ac3") || value.contains("e-ac-3") || value.contains("eac3") {
            return "Dolby"
        }
        return nil
    }

    private static func detectOriginalFlag(id: String, languageCode: String, displayName: String) -> Bool {
        let text = "\(id) \(languageCode) \(displayName)".lowercased()
        return languageCode.caseInsensitiveCompare("und") == .orderedSame
            || text.contains("original")
            || text.contains("оригинал")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
