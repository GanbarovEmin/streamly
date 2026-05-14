import Foundation

public struct LibraryExportSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let appName: String
    public let exportedAt: Date
    public let mediaItems: [MediaItem]
    public let libraryItems: [LibraryItem]
    public let favoriteMediaIDs: [String]
    public let lists: [UserList]
    public let watchlistItems: [WatchlistItem]
    public let watchHistory: [WatchHistoryItem]
    public let ratings: [UserRating]
    public let playbackProgress: [PlaybackProgress]

    public init(
        schemaVersion: Int = 1,
        appName: String = "Streamly",
        exportedAt: Date = Date(),
        mediaItems: [MediaItem],
        libraryItems: [LibraryItem],
        favoriteMediaIDs: [String],
        lists: [UserList],
        watchlistItems: [WatchlistItem] = [],
        watchHistory: [WatchHistoryItem],
        ratings: [UserRating],
        playbackProgress: [PlaybackProgress]
    ) {
        self.schemaVersion = schemaVersion
        self.appName = appName
        self.exportedAt = exportedAt
        self.mediaItems = mediaItems
        self.libraryItems = libraryItems
        self.favoriteMediaIDs = favoriteMediaIDs
        self.lists = lists
        self.watchlistItems = watchlistItems
        self.watchHistory = watchHistory
        self.ratings = ratings
        self.playbackProgress = playbackProgress
    }
}

public struct LibraryImportSummary: Codable, Equatable, Sendable {
    public var mediaItems: Int
    public var libraryItems: Int
    public var favorites: Int
    public var lists: Int
    public var listItems: Int
    public var watchHistory: Int
    public var ratings: Int
    public var playbackProgress: Int

    public init(
        mediaItems: Int = 0,
        libraryItems: Int = 0,
        favorites: Int = 0,
        lists: Int = 0,
        listItems: Int = 0,
        watchHistory: Int = 0,
        ratings: Int = 0,
        playbackProgress: Int = 0
    ) {
        self.mediaItems = mediaItems
        self.libraryItems = libraryItems
        self.favorites = favorites
        self.lists = lists
        self.listItems = listItems
        self.watchHistory = watchHistory
        self.ratings = ratings
        self.playbackProgress = playbackProgress
    }

    public var totalRecords: Int {
        mediaItems + libraryItems + favorites + lists + listItems + watchHistory + ratings + playbackProgress
    }
}

public struct LibraryImportPreview: Equatable, Sendable {
    public let summary: LibraryImportSummary
    public let duplicateCount: Int
    public let validationIssues: [String]

    public init(summary: LibraryImportSummary, duplicateCount: Int = 0, validationIssues: [String] = []) {
        self.summary = summary
        self.duplicateCount = duplicateCount
        self.validationIssues = validationIssues
    }

    public var canImport: Bool {
        validationIssues.isEmpty
    }
}

public struct LibraryImportOptions: Equatable, Sendable {
    public let createBackupBeforeImport: Bool

    public init(createBackupBeforeImport: Bool = true) {
        self.createBackupBeforeImport = createBackupBeforeImport
    }
}

public struct LibraryImportResult: Equatable, Sendable {
    public let preview: LibraryImportPreview
    public let backupData: Data?

    public init(preview: LibraryImportPreview, backupData: Data? = nil) {
        self.preview = preview
        self.backupData = backupData
    }
}

public enum LibraryImportError: LocalizedError, Equatable {
    case validationFailed([String])

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let issues):
            "Library import validation failed: \(issues.joined(separator: "; "))"
        }
    }
}

public protocol LibraryPortabilityServiceProtocol {
    func exportLibraryJSON() async throws -> Data
    func previewImport(_ data: Data) async throws -> LibraryImportPreview
    func importLibraryJSON(_ data: Data, options: LibraryImportOptions) async throws -> LibraryImportResult
}

public extension JSONEncoder {
    static var libraryPortability: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var libraryPortability: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
