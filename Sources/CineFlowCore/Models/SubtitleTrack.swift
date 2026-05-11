import Foundation

public struct SubtitleTrack: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let languageCode: String
    public let displayName: String
    public let source: SubtitleSource
    public let localURL: URL?
    public let externalID: String?
    public let isForced: Bool

    public init(
        id: String,
        languageCode: String,
        displayName: String,
        source: SubtitleSource,
        localURL: URL? = nil,
        externalID: String? = nil,
        isForced: Bool? = nil
    ) {
        self.id = id
        self.languageCode = languageCode.lowercased()
        self.displayName = displayName
        self.source = source
        self.localURL = localURL
        self.externalID = externalID
        self.isForced = isForced ?? Self.detectForcedFlag(id: id, displayName: displayName, localURL: localURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case languageCode
        case displayName
        case source
        case localURL
        case externalID
        case isForced
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        languageCode = try container.decode(String.self, forKey: .languageCode).lowercased()
        displayName = try container.decode(String.self, forKey: .displayName)
        source = try container.decode(SubtitleSource.self, forKey: .source)
        localURL = try container.decodeIfPresent(URL.self, forKey: .localURL)
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
        isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced)
            ?? Self.detectForcedFlag(id: id, displayName: displayName, localURL: localURL)
    }

    private static func detectForcedFlag(id: String, displayName: String, localURL: URL?) -> Bool {
        let text = [id, displayName, localURL?.lastPathComponent]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("forced") || text.contains("форс") || text.contains(".forc")
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

public enum SubtitleVisualStyle: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case system
    case highContrast
    case cinematic
    case compact

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:
            "System"
        case .highContrast:
            "High contrast"
        case .cinematic:
            "Cinematic"
        case .compact:
            "Compact"
        }
    }
}

public enum SubtitlePlacement: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case lower
    case standard
    case higher

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lower:
            "Lower"
        case .standard:
            "Standard"
        case .higher:
            "Higher"
        }
    }

    public var mpvSubPosition: Int {
        switch self {
        case .lower:
            96
        case .standard:
            90
        case .higher:
            82
        }
    }
}

public enum SubtitleAutoMode: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case alwaysOn
    case onlyForeignAudio
    case offByDefault

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alwaysOn:
            "Always on"
        case .onlyForeignAudio:
            "Only foreign audio"
        case .offByDefault:
            "Off by default"
        }
    }
}

public struct SubtitleSelectionOverride: Codable, Equatable, Sendable {
    public var trackID: String?
    public var languageCode: String?
    public var source: SubtitleSource?
    public var isDisabled: Bool
    public var updatedAt: Date

    public init(
        trackID: String? = nil,
        languageCode: String? = nil,
        source: SubtitleSource? = nil,
        isDisabled: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.trackID = trackID
        self.languageCode = languageCode?.lowercased()
        self.source = source
        self.isDisabled = isDisabled
        self.updatedAt = updatedAt
    }
}

public struct SubtitleSettings: Codable, Equatable, Sendable {
    public var languagePreference: SubtitleLanguagePreference
    public var autoLoadSubtitles: Bool
    public var autoSearchSubtitles: Bool
    public var fontSize: Double
    public var subtitleDelaySeconds: Double
    public var visualStyle: SubtitleVisualStyle
    public var placement: SubtitlePlacement
    public var autoMode: SubtitleAutoMode
    public var manualOverridesByMediaID: [String: SubtitleSelectionOverride]

    public init(
        languagePreference: SubtitleLanguagePreference = SubtitleLanguagePreference(),
        autoLoadSubtitles: Bool = true,
        autoSearchSubtitles: Bool = true,
        fontSize: Double = 42,
        subtitleDelaySeconds: Double = 0,
        visualStyle: SubtitleVisualStyle = .system,
        placement: SubtitlePlacement = .standard,
        autoMode: SubtitleAutoMode = .alwaysOn,
        manualOverridesByMediaID: [String: SubtitleSelectionOverride] = [:]
    ) {
        self.languagePreference = languagePreference
        self.autoLoadSubtitles = autoLoadSubtitles
        self.autoSearchSubtitles = autoSearchSubtitles
        self.fontSize = fontSize
        self.subtitleDelaySeconds = subtitleDelaySeconds
        self.visualStyle = visualStyle
        self.placement = placement
        self.autoMode = autoMode
        self.manualOverridesByMediaID = manualOverridesByMediaID
    }

    private enum CodingKeys: String, CodingKey {
        case languagePreference
        case autoLoadSubtitles
        case autoSearchSubtitles
        case fontSize
        case subtitleDelaySeconds
        case visualStyle
        case placement
        case autoMode
        case manualOverridesByMediaID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languagePreference = try container.decodeIfPresent(SubtitleLanguagePreference.self, forKey: .languagePreference) ?? SubtitleLanguagePreference()
        autoLoadSubtitles = try container.decodeIfPresent(Bool.self, forKey: .autoLoadSubtitles) ?? true
        autoSearchSubtitles = try container.decodeIfPresent(Bool.self, forKey: .autoSearchSubtitles) ?? true
        fontSize = min(max(try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 42, 24), 72)
        subtitleDelaySeconds = min(max(try container.decodeIfPresent(Double.self, forKey: .subtitleDelaySeconds) ?? 0, -10), 10)
        visualStyle = try container.decodeIfPresent(SubtitleVisualStyle.self, forKey: .visualStyle) ?? .system
        placement = try container.decodeIfPresent(SubtitlePlacement.self, forKey: .placement) ?? .standard
        autoMode = try container.decodeIfPresent(SubtitleAutoMode.self, forKey: .autoMode) ?? .alwaysOn
        manualOverridesByMediaID = try container.decodeIfPresent([String: SubtitleSelectionOverride].self, forKey: .manualOverridesByMediaID) ?? [:]
    }
}

public struct CachedSubtitleItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let fileName: String
    public let languageCode: String
    public let fileExtension: String
    public let sizeBytes: Int64
    public let createdAt: Date?
    public let url: URL

    public init(
        id: String,
        fileName: String,
        languageCode: String,
        fileExtension: String,
        sizeBytes: Int64,
        createdAt: Date? = nil,
        url: URL
    ) {
        self.id = id
        self.fileName = fileName
        self.languageCode = languageCode.lowercased()
        self.fileExtension = fileExtension.lowercased()
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.url = url
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
