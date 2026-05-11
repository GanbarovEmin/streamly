import CineFlowCore
import Foundation

public final class LocalSmartCacheManager: SmartCacheManagerProtocol, @unchecked Sendable {
    private let cacheRepository: CacheRepository
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let keptItemsKey = "streamly.smartCache.keptItems"
    private let activeSessionGraceInterval: TimeInterval = 15 * 60

    public init(
        cacheRepository: CacheRepository,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.cacheRepository = cacheRepository
        self.fileManager = fileManager
        self.userDefaults = userDefaults
    }

    public func summary(
        policy: SmartCachePolicy,
        scope: SmartCacheScope,
        protection: SmartCacheProtection
    ) async throws -> SmartCacheSummary {
        let imageRecords = try await cacheRepository.cachedImageRecords()
        let metadataRecords = try await cacheRepository.metadataCacheRecords()
        let torrentItems = fileItems(category: .torrents, root: scope.torrentCacheURL, protection: protection)
        let subtitleItems = fileItems(category: .subtitles, root: scope.subtitleCacheURL, protection: protection)
        let timelinePreviewItems = fileItems(category: .timelinePreviews, root: scope.timelinePreviewCacheURL, protection: protection)
        let keptIDs = keptItemIDs()

        let imageBytes = imageRecords.reduce(Int64(0)) { $0 + $1.fileSize }
        let metadataBytes = metadataRecords.reduce(Int64(0)) { $0 + $1.payloadSize }

        let imageItem = SmartTitleCacheItem(
            id: itemID(category: .images, value: "all"),
            title: "Artwork cache",
            category: .images,
            sizeBytes: imageBytes,
            lastAccessedAt: imageRecords.compactMap { date(from: $0.lastAccessedAt) }.max(),
            isKeptForLater: keptIDs.contains(itemID(category: .images, value: "all"))
        )

        let metadataItems = Dictionary(grouping: metadataRecords, by: \.provider)
            .map { provider, records in
                let id = itemID(category: .metadata, value: provider)
                return SmartTitleCacheItem(
                    id: id,
                    title: "\(provider.uppercased()) metadata",
                    category: .metadata,
                    sizeBytes: records.reduce(Int64(0)) { $0 + $1.payloadSize },
                    lastAccessedAt: records.compactMap { date(from: $0.updatedAt) }.max(),
                    isKeptForLater: keptIDs.contains(id)
                )
            }

        let fileBackedItems = (torrentItems + subtitleItems + timelinePreviewItems).map { item in
            SmartTitleCacheItem(
                id: item.id,
                title: item.title,
                category: item.category,
                sizeBytes: item.sizeBytes,
                lastAccessedAt: item.lastAccessedAt,
                isActive: item.isActive,
                isCompleted: item.isCompleted,
                isKeptForLater: keptIDs.contains(item.id),
                path: item.path
            )
        }

        let buckets = [
            SmartCacheBucketSummary(category: .images, sizeBytes: imageBytes, itemCount: imageRecords.count),
            SmartCacheBucketSummary(
                category: .torrents,
                sizeBytes: torrentItems.reduce(Int64(0)) { $0 + $1.sizeBytes },
                itemCount: torrentItems.count,
                path: scope.torrentCacheURL.path
            ),
            SmartCacheBucketSummary(
                category: .subtitles,
                sizeBytes: subtitleItems.reduce(Int64(0)) { $0 + $1.sizeBytes },
                itemCount: subtitleItems.count,
                path: scope.subtitleCacheURL.path
            ),
            SmartCacheBucketSummary(
                category: .timelinePreviews,
                sizeBytes: timelinePreviewItems.reduce(Int64(0)) { $0 + $1.sizeBytes },
                itemCount: timelinePreviewItems.count,
                path: scope.timelinePreviewCacheURL.path
            ),
            SmartCacheBucketSummary(category: .metadata, sizeBytes: metadataBytes, itemCount: metadataRecords.count)
        ]

        var titleItems = fileBackedItems + metadataItems
        if imageBytes > 0 {
            titleItems.append(imageItem)
        }

        return SmartCacheSummary(
            buckets: buckets,
            titleItems: titleItems.sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
                return lhs.sizeBytes > rhs.sizeBytes
            },
            maxSizeBytes: policy.maxSizeBytes
        )
    }

    public func clear(
        category: SmartCacheCategory,
        scope: SmartCacheScope,
        protection: SmartCacheProtection
    ) async throws -> SmartCacheCleanupResult {
        switch category {
        case .images:
            return try await removeImages(olderThan: nil, force: !keptItemIDs().contains(itemID(category: .images, value: "all")))
        case .metadata:
            return try await removeMetadata(provider: nil, olderThan: nil, force: false)
        case .torrents:
            return removeFileItems(root: scope.torrentCacheURL, category: .torrents, protection: protection, force: false)
        case .subtitles:
            return removeFileItems(root: scope.subtitleCacheURL, category: .subtitles, protection: protection, force: false)
        case .timelinePreviews:
            return removeFileItems(root: scope.timelinePreviewCacheURL, category: .timelinePreviews, protection: protection, force: false)
        }
    }

    public func clearTitleCache(
        itemID: String,
        scope: SmartCacheScope,
        protection: SmartCacheProtection
    ) async throws -> SmartCacheCleanupResult {
        guard !keptItemIDs().contains(itemID) else {
            return SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0, protectedItemCount: 1)
        }
        if itemID == self.itemID(category: .images, value: "all") {
            return try await removeImages(olderThan: nil, force: true)
        }
        if let provider = value(from: itemID, category: .metadata) {
            return try await removeMetadata(provider: provider, olderThan: nil, force: true)
        }
        if let path = value(from: itemID, category: .torrents) {
            return removeFileItem(URL(fileURLWithPath: path), category: .torrents, protection: protection, force: true)
        }
        if let path = value(from: itemID, category: .subtitles) {
            return removeFileItem(URL(fileURLWithPath: path), category: .subtitles, protection: protection, force: true)
        }
        if let path = value(from: itemID, category: .timelinePreviews) {
            return removeFileItem(URL(fileURLWithPath: path), category: .timelinePreviews, protection: protection, force: true)
        }
        return SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0)
    }

    public func setKeepForLater(itemID: String, keep: Bool) async throws {
        var ids = keptItemIDs()
        if keep {
            ids.insert(itemID)
        } else {
            ids.remove(itemID)
        }
        userDefaults.set(Array(ids).sorted(), forKey: keptItemsKey)
        userDefaults.synchronize()
    }

    public func runAutoClean(
        policy: SmartCachePolicy,
        scope: SmartCacheScope,
        protection: SmartCacheProtection
    ) async throws -> SmartCacheCleanupResult {
        var total = SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0)
        total += try await removeImages(olderThan: policy.cutoffDate, force: false)
        total += try await removeMetadata(provider: nil, olderThan: policy.cutoffDate, force: false)
        total += removeFileItems(
            root: scope.torrentCacheURL,
            category: .torrents,
            protection: protection,
            olderThan: policy.cutoffDate,
            keepUnfinished: policy.keepUnfinished,
            removeCompleted: policy.removeCompleted,
            force: false
        )
        total += removeFileItems(
            root: scope.subtitleCacheURL,
            category: .subtitles,
            protection: protection,
            olderThan: policy.cutoffDate,
            keepUnfinished: false,
            removeCompleted: true,
            force: false
        )
        total += removeFileItems(
            root: scope.timelinePreviewCacheURL,
            category: .timelinePreviews,
            protection: protection,
            olderThan: policy.cutoffDate,
            keepUnfinished: false,
            removeCompleted: true,
            force: false
        )

        var current = try await summary(policy: policy, scope: scope, protection: protection)
        guard current.totalBytes > policy.maxSizeBytes else { return total }

        for item in current.titleItems.sorted(by: olderAndLargerFirst) where current.totalBytes > policy.maxSizeBytes {
            guard !item.isActive, !item.isKeptForLater else { continue }
            guard item.isCompleted || !policy.keepUnfinished else { continue }
            let result = try await clearTitleCache(itemID: item.id, scope: scope, protection: protection)
            total += result
            current = try await summary(policy: policy, scope: scope, protection: protection)
        }

        return total
    }

    private func fileItems(
        category: SmartCacheCategory,
        root: URL,
        protection: SmartCacheProtection
    ) -> [SmartTitleCacheItem] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentAccessDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.map { url in
            let size = directorySize(url)
            let id = itemID(category: category, value: url.path)
            return SmartTitleCacheItem(
                id: id,
                title: readableTitle(for: url),
                category: category,
                sizeBytes: size,
                lastAccessedAt: accessDate(url),
                isActive: isProtected(url, itemID: id, protection: protection),
                isCompleted: isCompleted(url),
                isKeptForLater: keptItemIDs().contains(id),
                path: url.path
            )
        }
    }

    private func removeFileItems(
        root: URL,
        category: SmartCacheCategory,
        protection: SmartCacheProtection,
        olderThan cutoff: Date? = nil,
        keepUnfinished: Bool = false,
        removeCompleted: Bool = true,
        force: Bool
    ) -> SmartCacheCleanupResult {
        fileItems(category: category, root: root, protection: protection).reduce(SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0)) { partial, item in
            guard let path = item.path else { return partial }
            if item.isActive || (!force && item.isKeptForLater) {
                return partial + SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0, protectedItemCount: 1)
            }
            if !force {
                guard cutoff.map({ (item.lastAccessedAt ?? .distantPast) < $0 }) == true || (removeCompleted && item.isCompleted) else {
                    return partial
                }
                guard item.isCompleted || !keepUnfinished else {
                    return partial + SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0, protectedItemCount: 1)
                }
            }
            return partial + removeFileItem(URL(fileURLWithPath: path), category: category, protection: protection, force: force)
        }
    }

    private func removeFileItem(
        _ url: URL,
        category: SmartCacheCategory,
        protection: SmartCacheProtection,
        force: Bool
    ) -> SmartCacheCleanupResult {
        let id = itemID(category: category, value: url.path)
        guard !isProtected(url, itemID: id, protection: protection), !isRecentlyActive(url) else {
            return SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0, protectedItemCount: 1)
        }
        guard force || !keptItemIDs().contains(id) else {
            return SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0, protectedItemCount: 1)
        }
        let size = directorySize(url)
        try? fileManager.removeItem(at: url)
        return SmartCacheCleanupResult(removedItemCount: 1, freedBytes: size)
    }

    private func removeImages(olderThan cutoff: Date?, force: Bool) async throws -> SmartCacheCleanupResult {
        let allID = itemID(category: .images, value: "all")
        guard force || !keptItemIDs().contains(allID) else {
            return SmartCacheCleanupResult(removedItemCount: 0, freedBytes: 0, protectedItemCount: 1)
        }
        let records = if let cutoff {
            try await cacheRepository.cachedImageRecordsUnused(before: timestamp(cutoff))
        } else {
            try await cacheRepository.cachedImageRecords()
        }
        var freedBytes: Int64 = 0
        for record in records {
            try? fileManager.removeItem(atPath: record.localPath)
            try await cacheRepository.removeCachedImage(url: record.url)
            freedBytes += record.fileSize
        }
        return SmartCacheCleanupResult(removedItemCount: records.count, freedBytes: freedBytes)
    }

    private func removeMetadata(provider: String?, olderThan cutoff: Date?, force: Bool) async throws -> SmartCacheCleanupResult {
        var records = if let cutoff {
            try await cacheRepository.metadataCacheRecordsUnused(before: timestamp(cutoff))
        } else {
            try await cacheRepository.metadataCacheRecords()
        }
        if let provider {
            records = records.filter { $0.provider == provider }
        }
        let keptIDs = keptItemIDs()
        let removable = records.filter { force || !keptIDs.contains(itemID(category: .metadata, value: $0.provider)) }
        for record in removable {
            try await cacheRepository.removeMetadata(cacheKey: record.cacheKey)
        }
        return SmartCacheCleanupResult(
            removedItemCount: removable.count,
            freedBytes: removable.reduce(Int64(0)) { $0 + $1.payloadSize },
            protectedItemCount: records.count - removable.count
        )
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else {
            return 0
        }
        if values.isDirectory != true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return enumerator.reduce(Int64(0)) { partial, item in
            guard
                let fileURL = item as? URL,
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else {
                return partial
            }
            return partial + Int64(values.fileSize ?? 0)
        }
    }

    private func accessDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        return values?.contentAccessDate ?? values?.contentModificationDate
    }

    private func isCompleted(_ url: URL) -> Bool {
        let incompleteMarkers = ["part", "crdownload", "download", "tmp"]
        if incompleteMarkers.contains(url.pathExtension.lowercased()) || url.lastPathComponent.hasSuffix(".!qB") {
            return false
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return true
        }
        for case let fileURL as URL in enumerator {
            if incompleteMarkers.contains(fileURL.pathExtension.lowercased()) || fileURL.lastPathComponent.hasSuffix(".!qB") {
                return false
            }
        }
        return true
    }

    private func isProtected(_ url: URL, itemID: String, protection: SmartCacheProtection) -> Bool {
        if protection.activeIDs.contains(itemID) { return true }
        let path = url.standardizedFileURL.path
        return protection.activeFileURLs.contains { activeURL in
            let activePath = activeURL.standardizedFileURL.path
            return activePath == path || activePath.hasPrefix(path + "/")
        }
    }

    private func isRecentlyActive(_ url: URL) -> Bool {
        guard let accessDate = accessDate(url) else { return false }
        return Date().timeIntervalSince(accessDate) < activeSessionGraceInterval
    }

    private func readableTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private func itemID(category: SmartCacheCategory, value: String) -> String {
        "\(category.rawValue):\(value)"
    }

    private func value(from itemID: String, category: SmartCacheCategory) -> String? {
        let prefix = "\(category.rawValue):"
        guard itemID.hasPrefix(prefix) else { return nil }
        return String(itemID.dropFirst(prefix.count))
    }

    private func keptItemIDs() -> Set<String> {
        Set(userDefaults.stringArray(forKey: keptItemsKey) ?? [])
    }

    private func olderAndLargerFirst(_ lhs: SmartTitleCacheItem, _ rhs: SmartTitleCacheItem) -> Bool {
        switch (lhs.lastAccessedAt, rhs.lastAccessedAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        default:
            return lhs.sizeBytes > rhs.sizeBytes
        }
    }
}

private func += (lhs: inout SmartCacheCleanupResult, rhs: SmartCacheCleanupResult) {
    lhs = lhs + rhs
}

private func + (lhs: SmartCacheCleanupResult, rhs: SmartCacheCleanupResult) -> SmartCacheCleanupResult {
    SmartCacheCleanupResult(
        removedItemCount: lhs.removedItemCount + rhs.removedItemCount,
        freedBytes: lhs.freedBytes + rhs.freedBytes,
        protectedItemCount: lhs.protectedItemCount + rhs.protectedItemCount
    )
}
