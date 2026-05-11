import CineFlowCore
import Foundation

public enum PlaybackStreamAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

public protocol PlaybackStreamAvailabilityChecking: Sendable {
    func check(_ url: URL, timeoutSeconds: TimeInterval) async -> PlaybackStreamAvailability
}

public struct DefaultPlaybackStreamAvailabilityChecker: PlaybackStreamAvailabilityChecking {
    public init() {}

    public func check(_ url: URL, timeoutSeconds: TimeInterval = 8) async -> PlaybackStreamAvailability {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .available
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeoutSeconds

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .available
            }
            if (200..<400).contains(httpResponse.statusCode) || httpResponse.statusCode == 405 {
                return .available
            }
            return .unavailable(reason: "HTTP \(httpResponse.statusCode)")
        } catch {
            var fallbackRequest = URLRequest(url: url)
            fallbackRequest.httpMethod = "GET"
            fallbackRequest.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            fallbackRequest.timeoutInterval = timeoutSeconds

            do {
                let (_, response) = try await URLSession.shared.data(for: fallbackRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .available
                }
                return (200..<400).contains(httpResponse.statusCode)
                    ? .available
                    : .unavailable(reason: "HTTP \(httpResponse.statusCode)")
            } catch {
                return .unavailable(reason: String(describing: error))
            }
        }
    }
}

public struct PlaybackDebugLogger: Sendable {
    public let enabled: Bool

    public static let disabled = PlaybackDebugLogger(enabled: false)

    public init(enabled: Bool = PlaybackDebugLogger.defaultEnabled) {
        self.enabled = enabled
    }

    public static var defaultEnabled: Bool {
        let processInfo = ProcessInfo.processInfo.environment
        if processInfo["STREAMLY_PLAYBACK_DEBUG"] == "1" || processInfo["CINEFLOW_PLAYBACK_DEBUG"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: "streamly.playback.debugEnabled")
    }

    public func log(
        diagnostics: (any DiagnosticsServiceProtocol)?,
        event: String,
        metadata: [String: String] = [:]
    ) async {
        guard enabled, let diagnostics else { return }
        var payload = metadata
        payload["event"] = event
        await diagnostics.log(
            level: .debug,
            subsystem: .playback,
            message: "Playback debug: \(event)",
            metadata: payload
        )
    }
}

public struct PlaybackPipelineRequest: Sendable {
    public let mediaID: String
    public let selectionContext: PlaybackSelectionContext?
    public let primaryRelease: TorrentRelease
    public let fallbackReleases: [TorrentRelease]
    public let bandwidthLimits: TorrentBandwidthLimits
    public let maxAutomaticFallbacks: Int
    public let torrentStartTimeoutSeconds: TimeInterval
    public let metadataTimeoutSeconds: TimeInterval
    public let fileSelectionTimeoutSeconds: TimeInterval
    public let streamURLTimeoutSeconds: TimeInterval
    public let availabilityTimeoutSeconds: TimeInterval
    public let rankingPreferences: RankingPreferences

    public init(
        mediaID: String,
        selectionContext: PlaybackSelectionContext? = nil,
        primaryRelease: TorrentRelease,
        fallbackReleases: [TorrentRelease] = [],
        bandwidthLimits: TorrentBandwidthLimits = .unlimited,
        maxAutomaticFallbacks: Int = 2,
        torrentStartTimeoutSeconds: TimeInterval = 10,
        metadataTimeoutSeconds: TimeInterval = 35,
        fileSelectionTimeoutSeconds: TimeInterval = 10,
        streamURLTimeoutSeconds: TimeInterval = 5,
        availabilityTimeoutSeconds: TimeInterval = 8,
        rankingPreferences: RankingPreferences = RankingPreferences()
    ) {
        self.mediaID = mediaID
        self.selectionContext = selectionContext
        self.primaryRelease = primaryRelease
        self.fallbackReleases = fallbackReleases
        self.bandwidthLimits = bandwidthLimits
        self.maxAutomaticFallbacks = max(0, maxAutomaticFallbacks)
        self.torrentStartTimeoutSeconds = max(1, torrentStartTimeoutSeconds)
        self.metadataTimeoutSeconds = max(1, metadataTimeoutSeconds)
        self.fileSelectionTimeoutSeconds = max(1, fileSelectionTimeoutSeconds)
        self.streamURLTimeoutSeconds = max(1, streamURLTimeoutSeconds)
        self.availabilityTimeoutSeconds = max(1, availabilityTimeoutSeconds)
        self.rankingPreferences = rankingPreferences
    }
}

public struct PlaybackPipelineAttempt: Equatable, Sendable {
    public let release: TorrentRelease
    public let state: PlaybackRunState
    public let error: CineFlowError?
    public let resolvedURL: URL?

    public init(
        release: TorrentRelease,
        state: PlaybackRunState,
        error: CineFlowError? = nil,
        resolvedURL: URL? = nil
    ) {
        self.release = release
        self.state = state
        self.error = error
        self.resolvedURL = resolvedURL
    }
}

public enum PlaybackPipelineResult: Equatable, Sendable {
    case ready(PlaybackMediaSource, TorrentSession, [PlaybackPipelineAttempt])
    case needsMediaFileSelection(TorrentSession, TorrentRelease, [TorrentMediaFileOption], [PlaybackPipelineAttempt])
    case failed(CineFlowError, ReleaseFallbackSuggestion?, [PlaybackPipelineAttempt])
}

public actor PlaybackPipeline {
    private let torrentEngine: any TorrentEngineProtocol
    private let availabilityChecker: any PlaybackStreamAvailabilityChecking
    private let debugLogger: PlaybackDebugLogger
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?

    public init(
        torrentEngine: any TorrentEngineProtocol,
        availabilityChecker: any PlaybackStreamAvailabilityChecking = DefaultPlaybackStreamAvailabilityChecker(),
        debugLogger: PlaybackDebugLogger = PlaybackDebugLogger(),
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil
    ) {
        self.torrentEngine = torrentEngine
        self.availabilityChecker = availabilityChecker
        self.debugLogger = debugLogger
        self.diagnosticsService = diagnosticsService
    }

    public func resolve(_ request: PlaybackPipelineRequest) async -> PlaybackPipelineResult {
        let candidates = candidateReleases(for: request)
        var attempts: [PlaybackPipelineAttempt] = []

        for (index, release) in candidates.enumerated() {
            if Task.isCancelled {
                return .failed(cancelledError(), nil, attempts)
            }

            if index > 0 {
                await log(
                    "fallback.retry",
                    request: request,
                    release: release,
                    metadata: ["attempt": "\(index + 1)"]
                )
            }

            await log(
                "source.selected",
                request: request,
                release: release,
                metadata: [
                    "attempt": "\(index + 1)",
                    "seeders": "\(release.seeders)",
                    "quality": release.qualityLabel
                ]
            )

            let startDate = Date()
            do {
                let resolved = try await resolveRelease(release, request: request)
                if let mediaSelection = resolved.mediaSelection, mediaSelection.manualOptions.count > 1 {
                    attempts.append(PlaybackPipelineAttempt(release: release, state: .ready))
                    return .needsMediaFileSelection(
                        resolved.session,
                        release,
                        mediaSelection.manualOptions,
                        attempts
                    )
                }

                attempts.append(
                    PlaybackPipelineAttempt(
                        release: release,
                        state: .ready,
                        resolvedURL: resolved.source.url
                    )
                )
                await log(
                    "stream.ready",
                    request: request,
                    release: release,
                    metadata: [
                        "durationMs": "\(elapsedMilliseconds(since: startDate))",
                        "streamURL": debugURL(resolved.source.url),
                        "urlScheme": resolved.source.url.scheme ?? "file"
                    ]
                )
                return .ready(resolved.source, resolved.session, attempts)
            } catch {
                let cineFlowError = categorize(error)
                attempts.append(
                    PlaybackPipelineAttempt(
                        release: release,
                        state: .failed(reason: String(describing: error)),
                        error: cineFlowError
                    )
                )
                await log(
                    "stream.failed",
                    request: request,
                    release: release,
                    metadata: [
                        "durationMs": "\(elapsedMilliseconds(since: startDate))",
                        "category": cineFlowError.category.rawValue,
                        "reason": cineFlowError.technicalDescription
                    ]
                )
            }
        }

        let finalError = attempts.last?.error ?? CineFlowError.defaultPlaybackPipelineFailure
        let suggestion = fallbackSuggestion(
            request: request,
            failedRelease: attempts.last?.release ?? request.primaryRelease,
            attemptedIDs: Set(attempts.map(\.release.id))
        )
        return .failed(finalError, suggestion, attempts)
    }

    private func resolveRelease(
        _ release: TorrentRelease,
        request: PlaybackPipelineRequest
    ) async throws -> ResolvedPlaybackSource {
        try validate(release)
        await log("stream.resolve.start", request: request, release: release)

        let engine = torrentEngine
        var startedSession: TorrentSession?
        do {
            let session = try await withTimeout(seconds: request.torrentStartTimeoutSeconds, operationName: "torrent.start") {
                try await engine.startStreaming(release)
            }
            startedSession = session
        await log(
            "torrent.session.started",
            request: request,
            release: release,
            metadata: ["sessionID": session.id]
        )

        try await withTimeout(seconds: request.fileSelectionTimeoutSeconds, operationName: "setBandwidthLimits") {
            try await engine.setBandwidthLimits(sessionId: session.id, request.bandwidthLimits)
        }
        let files = try await withTimeout(seconds: request.metadataTimeoutSeconds, operationName: "torrent.metadata.fileList") {
            try await engine.getFileList(sessionId: session.id)
        }
        let status = try? await withTimeout(seconds: min(2, request.metadataTimeoutSeconds), operationName: "torrent.status") {
            try await engine.getStatus(sessionId: session.id)
        }
        var metadataPayload = ["sessionID": session.id, "fileCount": "\(files.count)"]
        if let status {
            metadataPayload["torrentState"] = String(describing: status.state)
            metadataPayload["peersCount"] = "\(status.health.connectedPeers)"
            metadataPayload["seedersCount"] = "\(status.health.seeders)"
            metadataPayload["leechersCount"] = "\(status.health.leechers)"
            metadataPayload["bufferedBytes"] = "\(status.progress.bufferedBytes)"
            metadataPayload["downloadSpeedBytesPerSecond"] = "\(status.progress.downloadSpeedBytesPerSecond)"
        } else {
            metadataPayload["peersCount"] = "unknown"
        }
        await log(
            "torrent.metadata.ready",
            request: request,
            release: release,
            metadata: metadataPayload
        )
        let selection = try await ensureMediaFileSelected(
            session: session,
            release: release,
            files: files,
            operationTimeoutSeconds: request.fileSelectionTimeoutSeconds
        )

        let streamingURL = try await withTimeout(seconds: request.streamURLTimeoutSeconds, operationName: "stream.url") {
            try await engine.getStreamingURL(sessionId: session.id)
        }
        guard streamingURL.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }
        await log(
            "stream.url.ready",
            request: request,
            release: release,
            metadata: [
                "sessionID": session.id,
                "streamURL": debugURL(streamingURL),
                "urlScheme": streamingURL.scheme ?? "file"
            ]
        )

        if streamingURL.isStreamlyLocalTorrentStreamURL {
            await log(
                "stream.availability.skipped",
                request: request,
                release: release,
                metadata: [
                    "sessionID": session.id,
                    "reason": "local_torrent_stream",
                    "streamURL": debugURL(streamingURL),
                    "urlScheme": streamingURL.scheme ?? "file"
                ]
            )
        } else {
            await log(
                "stream.availability.start",
                request: request,
                release: release,
                metadata: ["urlScheme": streamingURL.scheme ?? "file"]
            )
            let availability = await availabilityChecker.check(
                streamingURL,
                timeoutSeconds: request.availabilityTimeoutSeconds
            )
            switch availability {
            case .available:
                break
            case .unavailable(let reason):
                throw PlaybackServiceError.unsupported(operation: "stream availability check failed: \(reason)")
            }
        }

        let source = PlaybackMediaSource(
            id: request.selectionContext?.episodeID ?? request.mediaID,
            title: request.selectionContext?.displayTitle ?? release.title,
            url: streamingURL,
            release: release,
            qualityLabel: release.qualityLabel,
            sourceName: release.sourceName,
            selectionContext: request.selectionContext
        )
        return ResolvedPlaybackSource(source: source, session: session, mediaSelection: selection)
        } catch {
            if let startedSession {
                try? await engine.remove(sessionId: startedSession.id, deleteFiles: false)
                await log(
                    "torrent.session.cleaned",
                    request: request,
                    release: release,
                    metadata: ["sessionID": startedSession.id, "reason": "resolve.failure"]
                )
            }
            throw error
        }
    }

    private func ensureMediaFileSelected(
        session: TorrentSession,
        release: TorrentRelease,
        files: [TorrentFile],
        operationTimeoutSeconds: TimeInterval
    ) async throws -> TorrentMediaFileSelection? {
        guard session.selectedFileId == nil else { return nil }
        guard let selection = TorrentMediaFileSelector.selection(for: release, files: files) else {
            throw PlaybackServiceError.unsupported(operation: ReleaseFallbackReason.missingMediaFile.userFacingSummary)
        }

        if selection.manualOptions.count > 1 {
            if release.preferredFileIndex == nil {
                return selection
            }
        }

        let engine = torrentEngine
        try await withTimeout(seconds: operationTimeoutSeconds, operationName: "selectMediaFile") {
            try await engine.selectMediaFile(sessionId: session.id, fileId: selection.selectedFile.id)
        }
        await logSelectedFile(session: session, release: release, file: selection.selectedFile)
        try await prioritize(files: files, selectedFileID: selection.selectedFile.id, sessionID: session.id, timeout: operationTimeoutSeconds)
        return selection
    }

    private func logSelectedFile(session: TorrentSession, release: TorrentRelease, file: TorrentFile) async {
        await debugLogger.log(
            diagnostics: diagnosticsService,
            event: "torrent.file.selected",
            metadata: [
                "sessionID": session.id,
                "releaseID": release.id,
                "preferredFileIndex": release.preferredFileIndex.map(String.init) ?? "none",
                "fileID": file.id,
                "fileName": file.name,
                "fileSize": "\(file.lengthBytes)"
            ]
        )
    }

    private func prioritize(
        files: [TorrentFile],
        selectedFileID: String,
        sessionID: String,
        timeout: TimeInterval
    ) async throws {
        let engine = torrentEngine
        let priorityOrder = files.sorted { lhs, rhs in
            if lhs.id == selectedFileID { return true }
            if rhs.id == selectedFileID { return false }
            if lhs.isMediaFile != rhs.isMediaFile { return lhs.isMediaFile && !rhs.isMediaFile }
            return lhs.lengthBytes > rhs.lengthBytes
        }

        for file in priorityOrder {
            let priority: TorrentFilePriority = if file.id == selectedFileID {
                .high
            } else if file.isMediaFile {
                .low
            } else {
                .disabled
            }
            try await withTimeout(seconds: timeout, operationName: "setDownloadPriority") {
                try await engine.setDownloadPriority(sessionId: sessionID, fileId: file.id, priority: priority)
            }
        }
    }

    private func validate(_ release: TorrentRelease) throws {
        guard release.magnetURI != nil || release.torrentFileURL != nil else {
            throw TorrentEngineError.invalidTorrentFile
        }
    }

    private func candidateReleases(for request: PlaybackPipelineRequest) -> [TorrentRelease] {
        let primary = request.primaryRelease
        let rankedFallbacks = ReleaseRankingEngine(preferences: request.rankingPreferences)
            .rank(request.fallbackReleases.filter { $0.id != primary.id })
            .map(\.release)

        var unique: [TorrentRelease] = [primary]
        var seen = Set([primary.id])
        for release in rankedFallbacks where !seen.contains(release.id) {
            unique.append(release)
            seen.insert(release.id)
        }

        return Array(unique.prefix(1 + request.maxAutomaticFallbacks))
    }

    private func fallbackSuggestion(
        request: PlaybackPipelineRequest,
        failedRelease: TorrentRelease,
        attemptedIDs: Set<String>
    ) -> ReleaseFallbackSuggestion? {
        let remaining = request.fallbackReleases.filter { !attemptedIDs.contains($0.id) }
        guard !remaining.isEmpty else { return nil }
        return ReleaseFallbackPlanner.suggestion(
            for: failedRelease,
            in: [failedRelease] + remaining,
            reason: .failedToStart,
            preferences: request.rankingPreferences
        )
    }

    private func categorize(_ error: Error) -> CineFlowError {
        if error is PlaybackServiceError {
            return CineFlowError.from(error, fallbackCategory: .playback)
        }
        return CineFlowError.from(error, fallbackCategory: .torrent)
    }

    private func cancelledError() -> CineFlowError {
        CineFlowError(
            category: .playback,
            technicalDescription: "Playback pipeline was cancelled.",
            userMessage: CineFlowError.defaultUserMessage(for: .playback),
            recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .playback),
            logLevel: .warning
        )
    }

    private func log(
        _ event: String,
        request: PlaybackPipelineRequest,
        release: TorrentRelease,
        metadata: [String: String] = [:]
    ) async {
        var payload = metadata
        payload["mediaID"] = request.mediaID
        payload["selectionMediaID"] = request.selectionContext?.mediaID
        payload["episodeID"] = request.selectionContext?.episodeID
        payload["season"] = request.selectionContext?.seasonNumber.map(String.init)
        payload["episode"] = request.selectionContext?.episodeNumber.map(String.init)
        payload["releaseID"] = release.id
        payload["sourceID"] = release.sourceId
        payload["sourceName"] = release.sourceName
        payload["preferredFileIndex"] = release.preferredFileIndex.map(String.init)
        payload["infoHash"] = infoHash(from: release)
        await debugLogger.log(diagnostics: diagnosticsService, event: event, metadata: payload)
    }

    private func infoHash(from release: TorrentRelease) -> String? {
        guard let magnetURI = release.magnetURI,
              let components = URLComponents(string: magnetURI),
              let exactTopic = components.queryItems?.first(where: { $0.name == "xt" })?.value
        else {
            return nil
        }
        let hash = exactTopic
            .replacingOccurrences(of: "urn:btih:", with: "", options: [.caseInsensitive])
        return hash.isEmpty ? nil : hash
    }

    private func elapsedMilliseconds(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }

    private func debugURL(_ url: URL) -> String {
        if url.isFileURL {
            let fileName = url.lastPathComponent.isEmpty ? "media" : url.lastPathComponent
            return "file://<local-file>/\(fileName)"
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    private func withTimeout<Value: Sendable>(
        seconds: TimeInterval,
        operationName: String,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            defer { group.cancelAll() }
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw PlaybackPipelineTimeoutError(operationName: operationName, timeoutSeconds: seconds)
            }

            guard let result = try await group.next() else {
                throw PlaybackPipelineTimeoutError(operationName: operationName, timeoutSeconds: seconds)
            }
            return result
        }
    }
}

private struct ResolvedPlaybackSource: Sendable {
    let source: PlaybackMediaSource
    let session: TorrentSession
    let mediaSelection: TorrentMediaFileSelection?
}

private struct PlaybackPipelineTimeoutError: Error, CustomStringConvertible, Sendable {
    let operationName: String
    let timeoutSeconds: TimeInterval

    var description: String {
        "Playback pipeline operation \(operationName) timed out after \(Int(timeoutSeconds))s"
    }
}

private extension CineFlowError {
    static let defaultPlaybackPipelineFailure = CineFlowError(
        category: .playback,
        technicalDescription: "No playback candidate could be resolved.",
        userMessage: CineFlowError.defaultUserMessage(for: .playback),
        recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .playback),
        logLevel: .error
    )
}

private extension URL {
    var isStreamlyLocalTorrentStreamURL: Bool {
        guard let scheme = scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              host == "127.0.0.1" || host == "localhost"
        else {
            return false
        }
        return path.hasPrefix("/stream/")
    }
}
