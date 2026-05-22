import Foundation

public enum MediaKind: String, Codable, Equatable, Hashable, Sendable {
    case movie
    case series
}

public struct MediaItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: MediaKind
    public let overview: String
    public let releaseYear: Int?
    public let posterPath: String?
    public let metadata: MediaMetadata?
    public let torrentReleases: [TorrentRelease]

    public init(
        id: String,
        title: String,
        kind: MediaKind,
        overview: String,
        releaseYear: Int?,
        posterPath: String?,
        metadata: MediaMetadata? = nil,
        torrentReleases: [TorrentRelease] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.overview = overview
        self.releaseYear = releaseYear
        self.posterPath = posterPath
        self.metadata = metadata
        self.torrentReleases = torrentReleases
    }

    public var displayTitle: String {
        let candidate = metadata?.title ?? title
        return candidate.isEmpty ? "Untitled" : candidate
    }

    public var displayYear: String {
        guard let year = metadata?.year ?? releaseYear else { return "Unknown" }
        return String(year)
    }

    public var bestPosterURL: URL? {
        metadata?.posterURL ?? posterPath.flatMap(URL.init(string:))
    }

    public var bestBackdropURL: URL? {
        metadata?.backdropURL
    }

    public var rankedReleases: [TorrentRelease] {
        torrentReleases.sortedByCineFlowRank()
    }
}

public struct Movie: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaItem: MediaItem
    public let metadata: MediaMetadata

    public init(id: String, mediaItem: MediaItem, metadata: MediaMetadata) {
        self.id = id
        self.mediaItem = mediaItem
        self.metadata = metadata
    }
}

public struct Series: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let mediaItem: MediaItem
    public let metadata: MediaMetadata
    public let seasons: [Season]

    public init(id: String, mediaItem: MediaItem, metadata: MediaMetadata, seasons: [Season] = []) {
        self.id = id
        self.mediaItem = mediaItem
        self.metadata = metadata
        self.seasons = seasons
    }
}

public struct Season: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let seriesID: String
    public let seasonNumber: Int
    public let title: String?
    public let overview: String?
    public let episodes: [Episode]

    public init(
        id: String,
        seriesID: String,
        seasonNumber: Int,
        title: String? = nil,
        overview: String? = nil,
        episodes: [Episode] = []
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.title = title
        self.overview = overview
        self.episodes = episodes
    }
}

public struct Episode: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let seriesID: String
    public let seasonID: String
    public let episodeNumber: Int
    public let title: String
    public let overview: String?
    public let runtimeMinutes: Int?
    public let airDate: Date?
    public let thumbnailURL: URL?

    public init(
        id: String,
        seriesID: String,
        seasonID: String,
        episodeNumber: Int,
        title: String,
        overview: String? = nil,
        runtimeMinutes: Int? = nil,
        airDate: Date? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seasonID = seasonID
        self.episodeNumber = episodeNumber
        self.title = title
        self.overview = overview
        self.runtimeMinutes = runtimeMinutes
        self.airDate = airDate
        self.thumbnailURL = thumbnailURL
    }
}
