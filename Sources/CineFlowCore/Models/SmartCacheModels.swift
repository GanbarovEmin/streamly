import Foundation

public enum SmartCacheCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case images
    case torrents
    case subtitles
    case metadata

    public var id: String { rawValue }
}

public struct SmartCachePolicy: Codable, Equatable, Sendable {
    public var retentionDays: Int
    public var maxSizeBytes: Int64
    public var keepUnfinished: Bool
    public var removeCompleted: Bool

    public init(
        retentionDays: Int = 30,
        maxSizeBytes: Int64 = 50 * 1_024 * 1_024 * 1_024,
        keepUnfinished: Bool = true,
        removeCompleted: Bool = false
    ) {
        self.retentionDays = min(max(retentionDays, 7), 30)
        self.maxSizeBytes = max(maxSizeBytes, 1_024 * 1_024 * 1_024)
        self.keepUnfinished = keepUnfinished
        self.removeCompleted = removeCompleted
    }

    public var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
    }
}

public struct SmartCacheProtection: Equatable, Sendable {
    public var activeFileURLs: [URL]
    public var activeIDs: [String]

    public init(activeFileURLs: [URL] = [], activeIDs: [String] = []) {
        self.activeFileURLs = activeFileURLs
        self.activeIDs = activeIDs
    }
}

public struct SmartCacheScope: Equatable, Sendable {
    public var torrentCacheURL: URL
    public var subtitleCacheURL: URL

    public init(
        torrentCacheURL: URL = TorrentCacheLocation.defaultStorageURL(),
        subtitleCacheURL: URL? = nil
    ) {
        self.torrentCacheURL = torrentCacheURL
        self.subtitleCacheURL = subtitleCacheURL ?? Self.defaultSubtitleCacheURL()
    }

    public static func defaultSubtitleCacheURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Streamly", isDirectory: true)
            .appendingPathComponent("Subtitles", isDirectory: true)
    }
}

public struct SmartCacheBucketSummary: Codable, Equatable, Identifiable, Sendable {
    public let category: SmartCacheCategory
    public let sizeBytes: Int64
    public let itemCount: Int
    public let path: String?

    public init(category: SmartCacheCategory, sizeBytes: Int64, itemCount: Int = 0, path: String? = nil) {
        self.category = category
        self.sizeBytes = sizeBytes
        self.itemCount = itemCount
        self.path = path
    }

    public var id: String { category.rawValue }
}

public struct SmartTitleCacheItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: SmartCacheCategory
    public let sizeBytes: Int64
    public let lastAccessedAt: Date?
    public let isActive: Bool
    public let isCompleted: Bool
    public let isKeptForLater: Bool
    public let path: String?

    public init(
        id: String,
        title: String,
        category: SmartCacheCategory,
        sizeBytes: Int64,
        lastAccessedAt: Date? = nil,
        isActive: Bool = false,
        isCompleted: Bool = true,
        isKeptForLater: Bool = false,
        path: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.sizeBytes = sizeBytes
        self.lastAccessedAt = lastAccessedAt
        self.isActive = isActive
        self.isCompleted = isCompleted
        self.isKeptForLater = isKeptForLater
        self.path = path
    }
}

public struct SmartCacheSummary: Codable, Equatable, Sendable {
    public var buckets: [SmartCacheBucketSummary]
    public var titleItems: [SmartTitleCacheItem]
    public var maxSizeBytes: Int64

    public init(
        buckets: [SmartCacheBucketSummary] = [],
        titleItems: [SmartTitleCacheItem] = [],
        maxSizeBytes: Int64 = SmartCachePolicy().maxSizeBytes
    ) {
        self.buckets = buckets
        self.titleItems = titleItems
        self.maxSizeBytes = maxSizeBytes
    }

    public var totalBytes: Int64 {
        buckets.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    public var isAlmostFull: Bool {
        guard maxSizeBytes > 0 else { return false }
        return Double(totalBytes) / Double(maxSizeBytes) >= 0.9
    }
}

public struct SmartCacheCleanupResult: Codable, Equatable, Sendable {
    public let removedItemCount: Int
    public let freedBytes: Int64
    public let protectedItemCount: Int

    public init(removedItemCount: Int, freedBytes: Int64, protectedItemCount: Int = 0) {
        self.removedItemCount = removedItemCount
        self.freedBytes = freedBytes
        self.protectedItemCount = protectedItemCount
    }
}
