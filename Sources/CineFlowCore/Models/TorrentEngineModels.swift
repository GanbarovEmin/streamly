import Foundation

public enum TorrentEngineError: LocalizedError, Equatable, Sendable {
    case unsupported(operation: String)
    case invalidMagnetURI
    case invalidTorrentFile
    case sessionNotFound(String)
    case fileNotFound(sessionId: String, fileId: String)
    case streamingURLUnavailable(sessionId: String)
    case libtorrentUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupported(let operation):
            "Torrent engine operation is not supported: \(operation)."
        case .invalidMagnetURI:
            "Magnet URI is invalid."
        case .invalidTorrentFile:
            "Torrent file is invalid."
        case .sessionNotFound(let sessionId):
            "Torrent session was not found: \(sessionId)."
        case .fileNotFound(let sessionId, let fileId):
            "Torrent file \(fileId) was not found in session \(sessionId)."
        case .streamingURLUnavailable(let sessionId):
            "Streaming URL is unavailable for session \(sessionId)."
        case .libtorrentUnavailable:
            "Embedded libtorrent bridge is not available yet."
        }
    }
}

public enum TorrentSessionState: Codable, Equatable, Sendable {
    case idle
    case checking
    case downloading
    case streaming
    case paused
    case seeding
    case stopped
    case failed(reason: String)
}

public enum TorrentFilePriority: Int, Codable, Comparable, Sendable {
    case disabled = 0
    case low = 1
    case normal = 2
    case high = 3

    public static func < (lhs: TorrentFilePriority, rhs: TorrentFilePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TorrentProgress: Codable, Equatable, Sendable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64
    public let bufferedBytes: Int64
    public let downloadSpeedBytesPerSecond: Int64
    public let uploadSpeedBytesPerSecond: Int64

    public init(
        downloadedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        bufferedBytes: Int64 = 0,
        downloadSpeedBytesPerSecond: Int64 = 0,
        uploadSpeedBytesPerSecond: Int64 = 0
    ) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.bufferedBytes = bufferedBytes
        self.downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond
        self.uploadSpeedBytesPerSecond = uploadSpeedBytesPerSecond
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }

    public var bufferFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bufferedBytes) / Double(totalBytes)))
    }
}

public struct TorrentHealth: Codable, Equatable, Sendable {
    public let seeders: Int
    public let leechers: Int
    public let connectedPeers: Int
    public let availability: Double

    public init(
        seeders: Int = 0,
        leechers: Int = 0,
        connectedPeers: Int = 0,
        availability: Double = 0
    ) {
        self.seeders = seeders
        self.leechers = leechers
        self.connectedPeers = connectedPeers
        self.availability = availability
    }
}

public struct TorrentFile: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let lengthBytes: Int64
    public let isMediaFile: Bool
    public var priority: TorrentFilePriority
    public var progress: TorrentProgress

    public init(
        id: String,
        path: String,
        name: String,
        lengthBytes: Int64,
        isMediaFile: Bool,
        priority: TorrentFilePriority = .normal,
        progress: TorrentProgress = TorrentProgress()
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.lengthBytes = lengthBytes
        self.isMediaFile = isMediaFile
        self.priority = priority
        self.progress = progress
    }
}

public struct TorrentSession: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let releaseId: String?
    public let sourceId: String?
    public let magnetURI: String?
    public let torrentFileURL: URL?
    public let storageURL: URL
    public var selectedFileId: String?
    public var streamingURL: URL?
    public var isSequentialDownloadEnabled: Bool
    public let createdAt: Date

    public init(
        id: String,
        releaseId: String? = nil,
        sourceId: String? = nil,
        magnetURI: String? = nil,
        torrentFileURL: URL? = nil,
        storageURL: URL,
        selectedFileId: String? = nil,
        streamingURL: URL? = nil,
        isSequentialDownloadEnabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.releaseId = releaseId
        self.sourceId = sourceId
        self.magnetURI = magnetURI
        self.torrentFileURL = torrentFileURL
        self.storageURL = storageURL
        self.selectedFileId = selectedFileId
        self.streamingURL = streamingURL
        self.isSequentialDownloadEnabled = isSequentialDownloadEnabled
        self.createdAt = createdAt
    }
}

public struct TorrentStatus: Codable, Equatable, Sendable {
    public let sessionId: String
    public let state: TorrentSessionState
    public let progress: TorrentProgress
    public let health: TorrentHealth
    public let selectedFileId: String?
    public let isSequentialDownloadEnabled: Bool
    public let streamingURL: URL?
    public let updatedAt: Date

    public init(
        sessionId: String,
        state: TorrentSessionState,
        progress: TorrentProgress = TorrentProgress(),
        health: TorrentHealth = TorrentHealth(),
        selectedFileId: String? = nil,
        isSequentialDownloadEnabled: Bool = false,
        streamingURL: URL? = nil,
        updatedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.state = state
        self.progress = progress
        self.health = health
        self.selectedFileId = selectedFileId
        self.isSequentialDownloadEnabled = isSequentialDownloadEnabled
        self.streamingURL = streamingURL
        self.updatedAt = updatedAt
    }
}

public enum TorrentCleanupPolicy: Codable, Equatable, Sendable {
    case all
    case olderThan(Date)
    case exceedingCacheSize(maxBytes: Int64)
}

public struct TorrentCleanupResult: Codable, Equatable, Sendable {
    public let removedSessionIds: [String]
    public let freedBytes: Int64

    public init(removedSessionIds: [String], freedBytes: Int64) {
        self.removedSessionIds = removedSessionIds
        self.freedBytes = freedBytes
    }
}

public enum TorrentCacheLocation {
    public static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Streamly", isDirectory: true)
            .appendingPathComponent("TorrentCache", isDirectory: true)
    }
}
