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

    public func streamingURL(handle: String) async throws -> URL {
        throw TorrentEngineError.libtorrentUnavailable
    }
}

public actor EmbeddedLibtorrentTorrentEngine: TorrentEngineProtocol {
    public nonisolated let temporaryStorageURL: URL

    private let bridge: any LibtorrentBridgeProtocol
    private var handlesBySessionID: [String: String] = [:]

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
        handlesBySessionID[sessionId] = handle

        return TorrentSession(id: sessionId, magnetURI: uri, storageURL: storageURL)
    }

    public func addTorrentFile(url: URL) async throws -> TorrentSession {
        guard url.isFileURL else {
            throw TorrentEngineError.invalidTorrentFile
        }

        let sessionId = UUID().uuidString
        let storageURL = try storageURL(for: sessionId)
        let handle = try await bridge.addTorrentFile(url: url, storageURL: storageURL)
        handlesBySessionID[sessionId] = handle

        return TorrentSession(id: sessionId, torrentFileURL: url, storageURL: storageURL)
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
        handlesBySessionID[sessionId] = handle

        return TorrentSession(id: sessionId, torrentFileURL: torrentURL, storageURL: storageURL)
    }

    public func startStreaming(_ release: TorrentRelease) async throws -> TorrentSession {
        let session = if let magnetURI = release.magnetURI {
            try await addMagnet(uri: magnetURI)
        } else if let torrentFileURL = release.torrentFileURL {
            try await addTorrentFile(url: torrentFileURL)
        } else {
            throw TorrentEngineError.invalidTorrentFile
        }

        guard let handle = handlesBySessionID[session.id] else {
            throw TorrentEngineError.sessionNotFound(session.id)
        }
        try await bridge.setSequentialDownload(handle: handle, enabled: true)
        try await bridge.start(handle: handle)

        return TorrentSession(
            id: session.id,
            releaseId: release.id,
            sourceId: release.sourceId,
            magnetURI: session.magnetURI,
            torrentFileURL: session.torrentFileURL,
            storageURL: session.storageURL,
            isSequentialDownloadEnabled: true
        )
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
        handlesBySessionID[sessionId] = nil
    }

    public func getStatus(sessionId: String) async throws -> TorrentStatus {
        try await bridge.status(handle: try handle(for: sessionId))
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

    public func getStreamingURL(sessionId: String) async throws -> URL {
        try await bridge.streamingURL(handle: try handle(for: sessionId))
    }

    public nonisolated func statusUpdates(sessionId: String) -> AsyncThrowingStream<TorrentStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let status = try await self.getStatus(sessionId: sessionId)
                    continuation.yield(status)
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
            let ids = Array(handlesBySessionID.keys).sorted()
            for id in ids {
                try await remove(sessionId: id, deleteFiles: true)
            }
            return TorrentCleanupResult(removedSessionIds: ids, freedBytes: 0)
        case .olderThan, .exceedingCacheSize:
            return TorrentCleanupResult(removedSessionIds: [], freedBytes: 0)
        }
    }

    private func handle(for sessionId: String) throws -> String {
        guard let handle = handlesBySessionID[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        return handle
    }

    private func storageURL(for sessionId: String) throws -> URL {
        let url = temporaryStorageURL.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
