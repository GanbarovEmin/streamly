import Foundation

public struct SubtitleTrack: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let languageCode: String
    public let displayName: String
    public let source: SubtitleSource
    public let localURL: URL?
    public let externalID: String?

    public init(
        id: String,
        languageCode: String,
        displayName: String,
        source: SubtitleSource,
        localURL: URL? = nil,
        externalID: String? = nil
    ) {
        self.id = id
        self.languageCode = languageCode
        self.displayName = displayName
        self.source = source
        self.localURL = localURL
        self.externalID = externalID
    }
}

public enum SubtitleSource: String, Codable, Equatable, Sendable {
    case embedded
    case localFile
    case openSubtitles
}

public struct SubtitleLanguagePreference: Codable, Equatable, Sendable {
    public var languageCodes: [String]

    public init(_ languageCodes: [String] = ["ru", "en"]) {
        self.languageCodes = languageCodes.map { $0.lowercased() }
    }

    public func priority(for languageCode: String) -> Int {
        languageCodes.firstIndex(of: languageCode.lowercased()) ?? languageCodes.count
    }
}

public struct SubtitleSettings: Codable, Equatable, Sendable {
    public var languagePreference: SubtitleLanguagePreference
    public var autoLoadSubtitles: Bool
    public var autoSearchSubtitles: Bool
    public var fontSize: Double
    public var subtitleDelaySeconds: Double

    public init(
        languagePreference: SubtitleLanguagePreference = SubtitleLanguagePreference(),
        autoLoadSubtitles: Bool = true,
        autoSearchSubtitles: Bool = true,
        fontSize: Double = 42,
        subtitleDelaySeconds: Double = 0
    ) {
        self.languagePreference = languagePreference
        self.autoLoadSubtitles = autoLoadSubtitles
        self.autoSearchSubtitles = autoSearchSubtitles
        self.fontSize = fontSize
        self.subtitleDelaySeconds = subtitleDelaySeconds
    }
}

public struct SubtitleSearchQuery: Codable, Equatable, Sendable {
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let fileHash: String?
    public let localVideoURL: URL?

    public init(
        title: String,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        fileHash: String? = nil,
        localVideoURL: URL? = nil
    ) {
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.fileHash = fileHash
        self.localVideoURL = localVideoURL
    }
}

public struct SubtitleSearchResult: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let languageCode: String
    public let source: SubtitleSource
    public let score: Double
    public let downloadURL: URL?
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let fileHash: String?

    public init(
        id: String,
        title: String,
        languageCode: String,
        source: SubtitleSource,
        score: Double,
        downloadURL: URL? = nil,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        fileHash: String? = nil
    ) {
        self.id = id
        self.title = title
        self.languageCode = languageCode.lowercased()
        self.source = source
        self.score = score
        self.downloadURL = downloadURL
        self.year = year
        self.season = season
        self.episode = episode
        self.fileHash = fileHash
    }
}

public enum SubtitleServiceError: LocalizedError, Equatable, Sendable {
    case unsupported(operation: String)
    case invalidSubtitleFile(URL)
    case missingDownloadURL(String)
    case openSubtitlesCredentialsMissing

    public var errorDescription: String? {
        switch self {
        case .unsupported(let operation):
            "Subtitle operation is not supported: \(operation)."
        case .invalidSubtitleFile(let url):
            "Subtitle file is invalid: \(url.lastPathComponent)."
        case .missingDownloadURL(let id):
            "Subtitle result has no download URL: \(id)."
        case .openSubtitlesCredentialsMissing:
            "OpenSubtitles credentials are missing."
        }
    }
}
