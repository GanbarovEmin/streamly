import CineFlowCore
import Foundation

public actor MockTorrentEngine: TorrentEngineProtocol {
    public nonisolated let temporaryStorageURL: URL

    private var sessions: [String: MockTorrentSessionRecord] = [:]

    public init(temporaryStorageURL: URL = TorrentCacheLocation.defaultStorageURL()) {
        self.temporaryStorageURL = temporaryStorageURL
    }

    public func searchReleases(for item: MediaItem) async throws -> [TorrentRelease] {
        [
            TorrentRelease(id: "mock-1080p", title: "\(item.title) 1080p", quality: .fullHD, seeders: 140),
            TorrentRelease(id: "mock-2160p", title: "\(item.title) 2160p", quality: .ultraHD, seeders: 88)
        ].sortedByCineFlowRank()
    }

    public func addMagnet(uri: String) async throws -> TorrentSession {
        guard uri.lowercased().hasPrefix("magnet:?") else {
            throw TorrentEngineError.invalidMagnetURI
        }

        return try createSession(
            release: nil,
            magnetURI: uri,
            torrentFileURL: nil,
            state: .downloading,
            sequentialDownload: false
        )
    }

    public func addTorrentFile(url: URL) async throws -> TorrentSession {
        guard url.isFileURL else {
            throw TorrentEngineError.invalidTorrentFile
        }

        return try createSession(
            release: nil,
            magnetURI: nil,
            torrentFileURL: url,
            state: .downloading,
            sequentialDownload: false
        )
    }

    public func addTorrentFile(data: Data) async throws -> TorrentSession {
        guard !data.isEmpty else {
            throw TorrentEngineError.invalidTorrentFile
        }

        let sessionId = "mock-\(UUID().uuidString)"
        let storageURL = try storageURL(for: sessionId)
        let torrentFileURL = storageURL.appendingPathComponent("source.torrent")
        try data.write(to: torrentFileURL)

        return try createSession(
            id: sessionId,
            release: nil,
            magnetURI: nil,
            torrentFileURL: torrentFileURL,
            state: .downloading,
            sequentialDownload: false
        )
    }

    public func startStreaming(_ release: TorrentRelease) async throws -> TorrentSession {
        try createSession(
            release: release,
            magnetURI: release.magnetURI,
            torrentFileURL: release.torrentFileURL,
            state: .streaming,
            sequentialDownload: true
        )
    }

    public func pause(sessionId: String) async throws {
        try updateStatus(sessionId: sessionId) { status in
            status = status.replacing(state: .paused)
        }
    }

    public func resume(sessionId: String) async throws {
        try updateStatus(sessionId: sessionId) { status in
            status = status.replacing(state: .downloading)
        }
    }

    public func stop(sessionId: String) async throws {
        try updateStatus(sessionId: sessionId) { status in
            status = status.replacing(state: .stopped, downloadSpeedBytesPerSecond: 0)
        }
    }

    public func remove(sessionId: String, deleteFiles: Bool = false) async throws {
        guard let record = sessions.removeValue(forKey: sessionId) else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }

        if deleteFiles {
            try? FileManager.default.removeItem(at: record.session.storageURL)
        }
    }

    public func getStatus(sessionId: String) async throws -> TorrentStatus {
        guard let record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        return record.status
    }

    public func getFileList(sessionId: String) async throws -> [TorrentFile] {
        guard let record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        return record.files
    }

    public func selectMediaFile(sessionId: String, fileId: String) async throws {
        guard var record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        guard record.files.contains(where: { $0.id == fileId }) else {
            throw TorrentEngineError.fileNotFound(sessionId: sessionId, fileId: fileId)
        }

        record.session.selectedFileId = fileId
        record.session.streamingURL = record.session.storageURL.appendingPathComponent(fileId)
        record.status = record.status.replacing(selectedFileId: fileId, streamingURL: record.session.streamingURL)
        sessions[sessionId] = record
    }

    public func setSequentialDownload(sessionId: String, enabled: Bool) async throws {
        guard var record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }

        record.session.isSequentialDownloadEnabled = enabled
        record.status = record.status.replacing(isSequentialDownloadEnabled: enabled)
        sessions[sessionId] = record
    }

    public func setDownloadPriority(sessionId: String, fileId: String, priority: TorrentFilePriority) async throws {
        guard var record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        guard let index = record.files.firstIndex(where: { $0.id == fileId }) else {
            throw TorrentEngineError.fileNotFound(sessionId: sessionId, fileId: fileId)
        }

        record.files[index].priority = priority
        sessions[sessionId] = record
    }

    public func getStreamingURL(sessionId: String) async throws -> URL {
        guard let record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        guard let streamingURL = record.session.streamingURL else {
            throw TorrentEngineError.streamingURLUnavailable(sessionId: sessionId)
        }
        return streamingURL
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
        let removedSessionIds: [String]
        switch policy {
        case .all:
            removedSessionIds = Array(sessions.keys).sorted()
        case .olderThan(let date):
            removedSessionIds = sessions.values
                .filter { $0.session.createdAt < date }
                .map(\.session.id)
                .sorted()
        case .exceedingCacheSize(let maxBytes):
            let totalBytes = sessions.values.reduce(Int64(0)) { $0 + $1.sizeBytes }
            guard totalBytes > maxBytes else {
                return TorrentCleanupResult(removedSessionIds: [], freedBytes: 0)
            }
            removedSessionIds = sessions.values
                .sorted { $0.session.createdAt < $1.session.createdAt }
                .map(\.session.id)
        }

        var freedBytes: Int64 = 0
        for sessionId in removedSessionIds {
            if let record = sessions.removeValue(forKey: sessionId) {
                freedBytes += record.sizeBytes
                try? FileManager.default.removeItem(at: record.session.storageURL)
            }
        }

        return TorrentCleanupResult(removedSessionIds: removedSessionIds, freedBytes: freedBytes)
    }

    private func createSession(
        id requestedId: String? = nil,
        release: TorrentRelease?,
        magnetURI: String?,
        torrentFileURL: URL?,
        state: TorrentSessionState,
        sequentialDownload: Bool
    ) throws -> TorrentSession {
        let sessionId = requestedId ?? "mock-\(UUID().uuidString)"
        let storageURL = try storageURL(for: sessionId)
        let files = mockFiles(for: release, storageURL: storageURL)
        let selectedFileId = files.first(where: \.isMediaFile)?.id
        let streamingURL = selectedFileId.map { storageURL.appendingPathComponent($0) }
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.lengthBytes }
        let downloadedBytes = max(Int64(Double(totalBytes) * 0.18), min(totalBytes, 64_000_000))
        let bufferedBytes = max(Int64(Double(totalBytes) * 0.08), min(totalBytes, 24_000_000))
        let progress = TorrentProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            bufferedBytes: bufferedBytes,
            downloadSpeedBytesPerSecond: state == .stopped ? 0 : 8_000_000,
            uploadSpeedBytesPerSecond: 400_000
        )
        let health = TorrentHealth(
            seeders: release?.seeders ?? 32,
            leechers: release?.leechers ?? 4,
            connectedPeers: min(max(release?.seeders ?? 32, 1), 48),
            availability: 1.0
        )
        let session = TorrentSession(
            id: sessionId,
            releaseId: release?.id,
            sourceId: release?.sourceId,
            magnetURI: magnetURI,
            torrentFileURL: torrentFileURL,
            storageURL: storageURL,
            selectedFileId: selectedFileId,
            streamingURL: streamingURL,
            isSequentialDownloadEnabled: sequentialDownload
        )
        let status = TorrentStatus(
            sessionId: sessionId,
            state: state,
            progress: progress,
            health: health,
            selectedFileId: selectedFileId,
            isSequentialDownloadEnabled: sequentialDownload,
            streamingURL: streamingURL
        )

        sessions[sessionId] = MockTorrentSessionRecord(session: session, status: status, files: files)
        return session
    }

    private func storageURL(for sessionId: String) throws -> URL {
        let url = temporaryStorageURL.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func mockFiles(for release: TorrentRelease?, storageURL: URL) -> [TorrentFile] {
        let title = release?.title ?? "Streamly Mock Release"
        let mediaName = sanitizedFileName(title).appending(".mkv")
        let sizeBytes = release?.sizeBytes ?? 8_500_000_000
        let progress = TorrentProgress(
            downloadedBytes: Int64(Double(sizeBytes) * 0.18),
            totalBytes: sizeBytes,
            bufferedBytes: Int64(Double(sizeBytes) * 0.08),
            downloadSpeedBytesPerSecond: 8_000_000,
            uploadSpeedBytesPerSecond: 400_000
        )

        return [
            TorrentFile(
                id: mediaName,
                path: mediaName,
                name: mediaName,
                lengthBytes: sizeBytes,
                isMediaFile: true,
                priority: .high,
                progress: progress
            ),
            TorrentFile(
                id: "sample.nfo",
                path: "sample.nfo",
                name: "sample.nfo",
                lengthBytes: 32_000,
                isMediaFile: false,
                priority: .low,
                progress: TorrentProgress(downloadedBytes: 32_000, totalBytes: 32_000, bufferedBytes: 32_000)
            )
        ]
    }

    private func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateStatus(sessionId: String, transform: (inout TorrentStatus) -> Void) throws {
        guard var record = sessions[sessionId] else {
            throw TorrentEngineError.sessionNotFound(sessionId)
        }
        transform(&record.status)
        sessions[sessionId] = record
    }
}

private struct MockTorrentSessionRecord {
    var session: TorrentSession
    var status: TorrentStatus
    var files: [TorrentFile]

    var sizeBytes: Int64 {
        files.reduce(Int64(0)) { $0 + $1.lengthBytes }
    }
}

private extension TorrentStatus {
    func replacing(
        state: TorrentSessionState? = nil,
        selectedFileId: String? = nil,
        isSequentialDownloadEnabled: Bool? = nil,
        streamingURL: URL? = nil,
        downloadSpeedBytesPerSecond: Int64? = nil
    ) -> TorrentStatus {
        let updatedProgress: TorrentProgress
        if let downloadSpeedBytesPerSecond {
            updatedProgress = TorrentProgress(
                downloadedBytes: progress.downloadedBytes,
                totalBytes: progress.totalBytes,
                bufferedBytes: progress.bufferedBytes,
                downloadSpeedBytesPerSecond: downloadSpeedBytesPerSecond,
                uploadSpeedBytesPerSecond: progress.uploadSpeedBytesPerSecond
            )
        } else {
            updatedProgress = progress
        }

        return TorrentStatus(
            sessionId: sessionId,
            state: state ?? self.state,
            progress: updatedProgress,
            health: health,
            selectedFileId: selectedFileId ?? self.selectedFileId,
            isSequentialDownloadEnabled: isSequentialDownloadEnabled ?? self.isSequentialDownloadEnabled,
            streamingURL: streamingURL ?? self.streamingURL,
            updatedAt: Date()
        )
    }
}
