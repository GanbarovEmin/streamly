import Foundation

public struct MediaMetadata: Codable, Equatable, Sendable {
    public let tmdbId: Int
    public let imdbId: String?
    public let traktId: Int?
    public let title: String
    public let originalTitle: String
    public let overview: String
    public let year: Int?
    public let releaseDate: Date?
    public let genres: [String]
    public let runtime: Int?
    public let rating: Double?
    public let posterURL: URL?
    public let backdropURL: URL?
    public let logoURL: URL?
    public let trailerURLs: [URL]
    public let cast: [CastMember]
    public let alternativeTitles: [String]
    public let posterCandidates: [MetadataArtworkCandidate]
    public let backdropCandidates: [MetadataArtworkCandidate]

    public init(
        tmdbId: Int,
        imdbId: String? = nil,
        traktId: Int? = nil,
        title: String,
        originalTitle: String,
        overview: String,
        year: Int?,
        releaseDate: Date? = nil,
        genres: [String] = [],
        runtime: Int? = nil,
        rating: Double? = nil,
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        logoURL: URL? = nil,
        trailerURLs: [URL] = [],
        cast: [CastMember] = [],
        alternativeTitles: [String] = [],
        posterCandidates: [MetadataArtworkCandidate] = [],
        backdropCandidates: [MetadataArtworkCandidate] = []
    ) {
        self.tmdbId = tmdbId
        self.imdbId = imdbId
        self.traktId = traktId
        self.title = title
        self.originalTitle = originalTitle
        self.overview = overview
        self.year = year
        self.releaseDate = releaseDate
        self.genres = genres
        self.runtime = runtime
        self.rating = rating
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.trailerURLs = trailerURLs
        self.cast = cast
        self.alternativeTitles = alternativeTitles
        self.posterCandidates = posterCandidates
        self.backdropCandidates = backdropCandidates
    }

    public var displayTitle: String {
        title.isEmpty ? originalTitle : title
    }

    public var displayYear: String {
        year.map(String.init) ?? "Unknown"
    }

    public var bestPosterURL: URL? {
        posterURL
    }

    public var bestBackdropURL: URL? {
        backdropURL
    }
}

public struct CastMember: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let characterName: String?
    public let profileURL: URL?
    public let order: Int?

    public init(id: String, name: String, characterName: String? = nil, profileURL: URL? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.characterName = characterName
        self.profileURL = profileURL
        self.order = order
    }
}

public struct Trailer: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let site: String?

    public init(id: String, title: String, url: URL, site: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.site = site
    }
}
