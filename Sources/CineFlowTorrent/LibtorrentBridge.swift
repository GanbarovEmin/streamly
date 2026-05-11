import CineFlowCore
import Foundation

public protocol LibtorrentBridgeProtocol: Sendable {
    func addMagnet(uri: String, storageURL: URL) async throws -> String
    func addTorrentFile(url: URL, storageURL: URL) async throws -> String
    func start(handle: String) async throws
    func pause(handle: String) async throws
    func resume(handle: String) async throws
    func stop(handle: String) async throws
    func remove(handle: String, deleteFiles: Bool) async throws
    func status(handle: String) async throws -> TorrentStatus
    func files(handle: String) async throws -> [TorrentFile]
    func selectFile(handle: String, fileId: String) async throws
    func setSequentialDownload(handle: String, enabled: Bool) async throws
    func setDownloadPriority(handle: String, fileId: String, priority: TorrentFilePriority) async throws
    func setBandwidthLimits(handle: String, limits: TorrentBandwidthLimits) async throws
    func streamingURL(handle: String) async throws -> URL
}

public struct PlaceholderLibtorrentBridge: LibtorrentBridgeProtocol {
    public init() {}

    public func addMagnet(uri: String, storageURL: URL) async throws -> String {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func addTorrentFile(url: URL, storageURL: URL) async throws -> String {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func start(handle: String) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func pause(handle: String) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func resume(handle: String) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func stop(handle: String) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func remove(handle: String, deleteFiles: Bool) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func status(handle: String) async throws -> TorrentStatus {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func files(handle: String) async throws -> [TorrentFile] {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func selectFile(handle: String, fileId: String) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func setSequentialDownload(handle: String, enabled: Bool) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func setDownloadPriority(handle: String, fileId: String, priority: TorrentFilePriority) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func setBandwidthLimits(handle: String, limits: TorrentBandwidthLimits) async throws {
        throw TorrentEngineError.libtorrentUnavailable
    }

    public func streamingURL(handle: String) async throws -> URL {
        throw TorrentEngineError.libtorrentUnavailable
    }
}

public actor EmbeddedLibtorrentTorrentEngine: TorrentEngineProtocol {
    public nonisolated let temporaryStorageURL: URL

    private let bridge: any LibtorrentBridgeProtocol
    private var sessionsByID: [String: EmbeddedTorrentSessionRecord] = [:]

    public init(
        bridge: any LibtorrentBridgeProtocol = PlaceholderLibtorrentBridge(),
        temporaryStorageURL: URL = TorrentCacheLocation.defaultStorageURL()
    ) {
        self.bridge = bridge
        self.temporaryStorageURL = temporaryStorageURL
    }

    public func searchReleases(for item: MediaItem) async throws -> [TorrentRelease] {
        []
    }

    public func addMagnet(uri: String) async throws -> TorrentSession {
        guard uri.lowercased().hasPrefix("magnet:?") else {
            throw TorrentEngineError.invalidMagnetURI
        }

        let sessionId = UUID().uuidString
        let storageURL = try storageURL(for: sessionId)
        let handle = try await bridge.addMagnet(uri: uri, storageURL: storageURL)
        let session = TorrentSession(id: sessionId, magnetURI: uri, storageURL: storageURL)
        sessionsByID[sessionId] = EmbeddedTorrentSessionRecord(session: session, handle: handle)

        return session
    }

    public func addTorrentFile(url: URL) async throws -> TorrentSession {
        guard url.isFileURL else {
            throw TorrentEngineError.invalidTorrentFile
        }

        let sessionId = UUID().uuidString
        let storageURL = try storageURL(for: sessionId)
        let handle = try await bridge.addTorrentFile(url: url, storageURL: storageURL)
        let session = TorrentSession(id: sessionId, torrentFileURL: url, storageURL: storageURL)
        sessionsByID[sessionId] = EmbeddedTorrentSessionRecord(session: session, handle: handle)

        return session
    }

    public func addTorrentFile(data: Data) async throws -> TorrentSession {
        guard !data.isEmpty else {
            throw TorrentEngineError.invalidTorrentFile
        }

        let sessionId = UUID().uuidString
        let storageURL = try storageURL(for: sessionId)
        let torrentURL = storageURL.appendingPathComponent("source.torrent")
        try data.write(to: torrentURL)
        let handle = try await bridge.addTorrentFile(url: torrentURL, storageURL: storageURL)
        let session = TorrentSession(id: sessionId, torrentFileURL: torrentURL, storageURL: storageURL)
        sessionsByID[sessionId] = EmbeddedTorrentSessionRecord(session: session, handle: handle)

        return session
    }

    public func startStreaming(_ release: TorrentRelease) async throws -> TorrentSession {
        let session = if let magnetURI = release.magnetURI {
            try await addMagnet(uri: magnetURI)
        } else if let torrentFileURL = release.torrentFileURL {
            try await addTorrentFile(url: torrentFileURL)
        } else {
            throw TorrentEngineError.invalidTorrentFile
        }

        guard let handle = sessionsByID[session.id]?.handle else {
            throw TorrentEngineError.sessionNotFound(session.id)
        }
        try await bridge.setSequentialDownload(handle: handle, enabled: true)
        try await bridge.start(handle: handle)

        let streamSession = TorrentSession(
            id: session.id,
            releaseId: release.id,
            sourceId: release.sourceId,
            magnetURI: session.magnetURI,
            torrentFileURL: session.torrentFileURL,
            storageURL: session.storageURL,
            isSequentialDownloadEnabled: true
        )
        sessionsByID[session.id] = EmbeddedTorrentSessionRecord(session: streamSession, handle: handle)
        return streamSession
    }

    public func pause(sessionId: String) async throws {
        try await bridge.pause(handle: try handle(for: sessionId))
    }

    public func resume(sessionId: String) async throws {
        try await bridge.resume(handle: try handle(for: sessionId))
    }

    public func stop(sessionId: String) async throws {
        try await bridge.stop(handle: try handle(for: sessionId))
    }

    public func remove(sessionId: String, deleteFiles: Bool = false) async throws {
        let handle = try handle(for: sessionId)
        try await bridge.remove(handle: handle, deleteFiles: deleteFiles)
        sessionsByID[sessionId] = nil
    }

    public func getStatus(sessionId: String) async throws -> TorrentStatus {
        let raw = try await bridge.status(handle: try handle(for: sessionId))
        let record = sessionsByID[sessionId]
        return TorrentStatus(
            sessionId: sessionId,
            state: raw.state,
            progress: raw.progress,
            health: raw.health,
            selectedFileId: raw.selectedFileId ?? record?.session.selectedFileId,
            isSequentialDownloadEnabled: raw.isSequentialDownloadEnabled || record?.session.isSequentialDownloadEnabled == true,
            streamingURL: raw.streamingURL ?? record?.session.streamingURL,
            bandwidthLimits: record?.bandwidthLimits ?? raw.bandwidthLimits,
            updatedAt: raw.updatedAt
        )
    }

    public func getFileList(sessionId: String) async throws -> [TorrentFile] {
        try await bridge.files(handle: try handle(for: sessionId))
    }

    public func selectMediaFile(sessionId: String, fileId: String) async throws {
        try await bridge.selectFile(handle: try handle(for: sessionId), fileId: fileId)
    }

    public func setSequentialDownload(sessionId: String, enabled: Bool) async throws {
        try await bridge.setSequentialDownload(handle: try handle(for: sessionId), enabled: enabled)
    }

    public func setDownloadPriority(sessionId: String, fileId: String, priority: TorrentFilePriority) async throws {
        try await bridge.setDownloadPriority(handle: try handle(for: sessionId), fileId: fileId, priority: priority)
    }

    public func setBandwidthLimits(sessionId: String, _ limits: TorrentBandwidthLimits) async throws {
        let handle = try handle(for: sessionId)
        try await bridge.setBandwidthLimits(handle: handle, limits: limits)
        guard var record = sessionsByID[sessionId] else { return }
        record.bandwidthLimits = limits
        sessionsByID[sessionId] = record
    }

    public func getStreamingURL(sessionId: String) async throws -> URL {
        try await bridge.streamingURL(handle: try handle(for: sessionId))
    }

    public nonisolated func statusUpdates(sessionId: String) -> AsyncThrowingStream<TorrentStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    while !Task.isCancelled {
                        let status = try await self.getStatus(sessionId: sessionId)
                        continuation.yield(status)
                        if status.state.isTerminal {
                            continuation.finish()
                            return
                        }
                        try await Task.sleep(nanoseconds: 500_000_000)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cleanup(policy: TorrentCleanupPolicy) async throws -> TorrentCleanupResult {
        switch policy {
        case .all:
            let ids = Array(sessionsByID.keys).sorted()
            for id in ids {
                try await remove(sessionId: id, deleteFiles: true)
            }
            return TorrentCleanupResult(removedSessionIds: ids, freedBytes: 0)
        case .olderThan(let date, let protecting):
            let ids = sessionsByID.values
                .filter { $0.session.createdAt < date }
                .filter { !protecting.contains($0.session.id) }
                .map(\.session.id)
                .sorted()
            for id in ids {
                try await remove(sessionId: id, deleteFiles: true)
            }
            return TorrentCleanupResult(removedSessionIds: ids, freedBytes: 0)
        case .exceedingCacheSize(let maxBytes, let protecting):
            var currentSize = directorySize(temporaryStorageURL)
            var removed: [String] = []
            let candidates = sessionsByID.values
                .filter { !protecting.contains($0.session.id) }
                .sorted { $0.session.createdAt < $1.session.createdAt }
            for candidate in candidates where currentSize > maxBytes {
                try await remove(sessionId: candidate.session.id, deleteFiles: true)
                removed.append(candidate.session.id)
                currentSize = directorySize(temporaryStorageURL)
            }
            return TorrentCleanupResult(removedSessionIds: removed, freedBytes: 0)
        }
    }

    public func shutdown() async throws {
        for id in sessionsByID.keys {
            try? await stop(sessionId: id)
        }
    }

    private func handle(for sessionId: String) throws -> String {
        guard let handle = sessionsByID[sessionId]?.handle else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        return handle
    }

    private func storageURL(for sessionId: String) throws -> URL {
        let url = temporaryStorageURL.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
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
}

private struct EmbeddedTorrentSessionRecord {
    var session: TorrentSession
    let handle: String
    var bandwidthLimits: TorrentBandwidthLimits?
}

private extension TorrentSessionState {
    var isTerminal: Bool {
        switch self {
        case .stopped, .completed, .error, .failed:
            true
        default:
            false
        }
    }
}
