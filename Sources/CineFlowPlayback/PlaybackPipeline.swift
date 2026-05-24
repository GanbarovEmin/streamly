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
        if url.isStreamlyLocalTorrentStreamURL {
            return await rangedAvailabilityCheck(
                url,
                timeoutSeconds: max(timeoutSeconds, 13),
                rangeHeader: "bytes=0-4095",
                requireBody: true
            )
        }

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
            return await rangedAvailabilityCheck(
                url,
                timeoutSeconds: timeoutSeconds,
                rangeHeader: "bytes=0-1",
                requireBody: false
            )
        }
    }

    private func rangedAvailabilityCheck(
        _ url: URL,
        timeoutSeconds: TimeInterval,
        rangeHeader: String,
        requireBody: Bool
    ) async -> PlaybackStreamAvailability {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        request.timeoutInterval = timeoutSeconds

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .available
            }
            guard (200..<400).contains(httpResponse.statusCode) else {
                let detail = String(data: data.prefix(160), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let reason = detail.isEmpty ? "HTTP \(httpResponse.statusCode)" : "HTTP \(httpResponse.statusCode): \(detail)"
                return .unavailable(reason: reason)
            }
            if requireBody && data.isEmpty {
                return .unavailable(reason: "empty range response")
            }
            return .available
        } catch {
            return .unavailable(reason: String(describing: error))
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
    public let parallelSwarmProbeTimeoutSeconds: TimeInterval
    public let rankingPreferences: RankingPreferences

    public init(
        mediaID: String,
        selectionContext: PlaybackSelectionContext? = nil,
        primaryRelease: TorrentRelease,
        fallbackReleases: [TorrentRelease] = [],
        bandwidthLimits: TorrentBandwidthLimits = .unlimited,
        maxAutomaticFallbacks: Int = 2,
        torrentStartTimeoutSeconds: TimeInterval = 10,
        metadataTimeoutSeconds: TimeInterval = 16,
        fileSelectionTimeoutSeconds: TimeInterval = 10,
        streamURLTimeoutSeconds: TimeInterval = 9,
        availabilityTimeoutSeconds: TimeInterval = 8,
        parallelSwarmProbeTimeoutSeconds: TimeInterval = 7,
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
        self.parallelSwarmProbeTimeoutSeconds = max(1, parallelSwarmProbeTimeoutSeconds)
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
    case ready(PlaybackMediaSource, TorrentSession?, [PlaybackPipelineAttempt])
    case needsMediaFileSelection(TorrentSession, TorrentRelease, [TorrentMediaFileOption], [PlaybackPipelineAttempt])
    case failed(CineFlowError, ReleaseFallbackSuggestion?, [PlaybackPipelineAttempt])
}

public actor PlaybackPipeline {
    private static let swarmProbeBatchSize = 6
    private static let swarmProbeSoloCandidateCount = 4

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
        let directCandidates = candidates.filter { $0.directStreamURL != nil }
        let torrentCandidates = candidates.filter { $0.directStreamURL == nil }

        var initialAttempts: [PlaybackPipelineAttempt] = []
        if !directCandidates.isEmpty {
            let directResult = await resolveSequentially(
                request: request,
                candidates: directCandidates,
                initialAttempts: initialAttempts
            )
            switch directResult {
            case .ready, .needsMediaFileSelection:
                return directResult
            case .failed(_, _, let attempts):
                initialAttempts = attempts
                guard !torrentCandidates.isEmpty else {
                    return directResult
                }
            }
        }

        if torrentCandidates.count > 1 {
            return await resolveWithParallelSwarmProbes(
                request: request,
                candidates: torrentCandidates,
                initialAttempts: initialAttempts
            )
        }

        return await resolveSequentially(
            request: request,
            candidates: torrentCandidates,
            initialAttempts: initialAttempts
        )
    }

    private func resolveSequentially(
        request: PlaybackPipelineRequest,
        candidates: [TorrentRelease],
        initialAttempts: [PlaybackPipelineAttempt] = []
    ) async -> PlaybackPipelineResult {
        var attempts = initialAttempts

        for (index, release) in candidates.enumerated() {
            if Task.isCancelled {
                return .failed(cancelledError(), nil, attempts)
            }
            let attemptNumber = initialAttempts.count + index + 1

            if index > 0 || !initialAttempts.isEmpty {
                await log(
                    "fallback.retry",
                    request: request,
                    release: release,
                    metadata: ["attempt": "\(attemptNumber)"]
                )
            }

            await log(
                "source.selected",
                request: request,
                release: release,
                metadata: [
                    "attempt": "\(attemptNumber)",
                    "seeders": "\(release.seeders)",
                    "quality": release.qualityLabel
                ]
            )

            let startDate = Date()
            do {
                let resolved = try await resolveRelease(release, request: request)
                if let mediaSelection = resolved.mediaSelection, mediaSelection.requiresManualConfirmation {
                    guard let session = resolved.session else {
                        throw PlaybackServiceError.unsupported(operation: "direct stream cannot require file selection")
                    }
                    attempts.append(PlaybackPipelineAttempt(release: release, state: .ready))
                    return .needsMediaFileSelection(
                        session,
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

    private func resolveWithParallelSwarmProbes(
        request: PlaybackPipelineRequest,
        candidates: [TorrentRelease],
        initialAttempts: [PlaybackPipelineAttempt] = []
    ) async -> PlaybackPipelineResult {
        let attemptOffset = initialAttempts.count
        var attempts = initialAttempts

        var batchStart = 0
        while batchStart < candidates.count {
            let batchSize = batchStart < Self.swarmProbeSoloCandidateCount ? 1 : Self.swarmProbeBatchSize
            let batchEnd = min(batchStart + batchSize, candidates.count)
            let batchCandidates = Array(candidates[batchStart..<batchEnd])
            let probeResults = await probeSwarmCandidates(
                batchCandidates,
                request: request,
                attemptOffset: attemptOffset,
                baseIndex: batchStart
            )
            let successes = probeResults.compactMap { result -> SwarmProbeSuccess? in
                guard case .success(let success) = result else { return nil }
                return success
            }
            let probeFailures = Dictionary(
                uniqueKeysWithValues: probeResults.compactMap { result -> (Int, PlaybackPipelineAttempt)? in
                    guard case .failure(let failure) = result else { return nil }
                    return (
                        failure.index,
                        PlaybackPipelineAttempt(
                            release: failure.release,
                            state: .failed(reason: failure.reason),
                            error: failure.error
                        )
                    )
                }
            )
            var appendedFailureIndexes = Set<Int>()
            var reusableSuccesses = successes.sorted { lhs, rhs in lhs.index < rhs.index }

            for success in successes.sorted(by: { lhs, rhs in lhs.index < rhs.index }) {
                reusableSuccesses.removeAll { $0.session.id == success.session.id }
                appendProbeFailures(
                    before: success.index,
                    probeFailures: probeFailures,
                    appendedIndexes: &appendedFailureIndexes,
                    attempts: &attempts
                )

                if Task.isCancelled {
                    try? await torrentEngine.remove(sessionId: success.session.id, deleteFiles: false)
                    await cleanupProbeSuccesses(reusableSuccesses)
                    return .failed(cancelledError(), nil, attempts)
                }

                await log(
                    "source.selected",
                    request: request,
                    release: success.release,
                    metadata: [
                        "attempt": "\(attemptOffset + success.index + 1)",
                        "seeders": "\(success.release.seeders)",
                        "quality": success.release.qualityLabel,
                        "probe": "parallel"
                    ]
                )

                let startDate = Date()
                do {
                    let resolved = try await resolvePreparedRelease(
                        success.release,
                        session: success.session,
                        files: success.files,
                        request: request
                    )
                    if let mediaSelection = resolved.mediaSelection, mediaSelection.requiresManualConfirmation {
                        guard let session = resolved.session else {
                            throw PlaybackServiceError.unsupported(operation: "direct stream cannot require file selection")
                        }
                        attempts.append(PlaybackPipelineAttempt(release: success.release, state: .ready))
                        await cleanupProbeSuccesses(reusableSuccesses)
                        return .needsMediaFileSelection(
                            session,
                            success.release,
                            mediaSelection.manualOptions,
                            attempts
                        )
                    }

                    attempts.append(
                        PlaybackPipelineAttempt(
                            release: success.release,
                            state: .ready,
                            resolvedURL: resolved.source.url
                        )
                    )
                    await log(
                        "stream.ready",
                        request: request,
                        release: success.release,
                        metadata: [
                            "durationMs": "\(elapsedMilliseconds(since: startDate))",
                            "streamURL": debugURL(resolved.source.url),
                            "urlScheme": resolved.source.url.scheme ?? "file",
                            "probe": "parallel"
                        ]
                    )
                    await cleanupProbeSuccesses(reusableSuccesses)
                    return .ready(resolved.source, resolved.session, attempts)
                } catch {
                    let cineFlowError = categorize(error)
                    attempts.append(
                        PlaybackPipelineAttempt(
                            release: success.release,
                            state: .failed(reason: String(describing: error)),
                            error: cineFlowError
                        )
                    )
                    await log(
                        "stream.failed",
                        request: request,
                        release: success.release,
                        metadata: [
                            "durationMs": "\(elapsedMilliseconds(since: startDate))",
                            "category": cineFlowError.category.rawValue,
                            "reason": cineFlowError.technicalDescription,
                            "probe": "parallel"
                        ]
                    )
                    try? await torrentEngine.remove(sessionId: success.session.id, deleteFiles: false)
                }
            }

            appendProbeFailures(
                before: Int.max,
                probeFailures: probeFailures,
                appendedIndexes: &appendedFailureIndexes,
                attempts: &attempts
            )
            await cleanupProbeSuccesses(reusableSuccesses)
            batchStart = batchEnd
        }

        let finalError = attempts.last?.error ?? CineFlowError.defaultPlaybackPipelineFailure
        let suggestion = fallbackSuggestion(
            request: request,
            failedRelease: attempts.last?.release ?? request.primaryRelease,
            attemptedIDs: Set(attempts.map(\.release.id))
        )
        return .failed(finalError, suggestion, attempts)
    }

    private func cleanupProbeSuccesses(_ successes: [SwarmProbeSuccess]) async {
        for success in successes {
            try? await torrentEngine.remove(sessionId: success.session.id, deleteFiles: false)
        }
    }

    private func appendProbeFailures(
        before index: Int,
        probeFailures: [Int: PlaybackPipelineAttempt],
        appendedIndexes: inout Set<Int>,
        attempts: inout [PlaybackPipelineAttempt]
    ) {
        for failureIndex in probeFailures.keys.sorted() where failureIndex < index && !appendedIndexes.contains(failureIndex) {
            if let attempt = probeFailures[failureIndex] {
                attempts.append(attempt)
                appendedIndexes.insert(failureIndex)
            }
        }
    }

    private func probeSwarmCandidates(
        _ candidates: [TorrentRelease],
        request: PlaybackPipelineRequest,
        attemptOffset: Int,
        baseIndex: Int = 0
    ) async -> [SwarmProbeResult] {
        await withTaskGroup(of: SwarmProbeResult.self) { group in
            for (index, release) in candidates.enumerated() {
                let globalIndex = baseIndex + index
                group.addTask {
                    await self.probeSwarmCandidate(
                        release,
                        index: globalIndex,
                        request: request,
                        attemptOffset: attemptOffset
                    )
                }
            }

            var results: [SwarmProbeResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in lhs.index < rhs.index }
        }
    }

    private func probeSwarmCandidate(
        _ release: TorrentRelease,
        index: Int,
        request: PlaybackPipelineRequest,
        attemptOffset: Int
    ) async -> SwarmProbeResult {
        let startDate = Date()
        var startedSession: TorrentSession?
        do {
            try validate(release)
            await log(
                "swarm.probe.start",
                request: request,
                release: release,
                metadata: [
                    "attempt": "\(attemptOffset + index + 1)",
                    "seeders": "\(release.seeders)",
                    "quality": release.qualityLabel
                ]
            )

            let engine = torrentEngine
            let session = try await withTimeout(seconds: request.torrentStartTimeoutSeconds, operationName: "torrent.start") {
                try await engine.startStreaming(release)
            }
            startedSession = session
            await log(
                "torrent.session.started",
                request: request,
                release: release,
                metadata: ["sessionID": session.id, "probe": "parallel"]
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
            await log(
                "torrent.metadata.ready",
                request: request,
                release: release,
                metadata: metadataPayload(sessionID: session.id, files: files, status: status)
                    .merging(["probe": "parallel"]) { _, new in new }
            )

            return .success(
                SwarmProbeSuccess(
                    index: index,
                    release: release,
                    session: session,
                    files: files,
                    status: status
                )
            )
        } catch {
            if let startedSession {
                try? await torrentEngine.remove(sessionId: startedSession.id, deleteFiles: false)
                await log(
                    "torrent.session.cleaned",
                    request: request,
                    release: release,
                    metadata: ["sessionID": startedSession.id, "reason": "probe.failure"]
                )
            }
            let cineFlowError = categorize(error)
            await log(
                "stream.failed",
                request: request,
                release: release,
                metadata: [
                    "durationMs": "\(elapsedMilliseconds(since: startDate))",
                    "category": cineFlowError.category.rawValue,
                    "reason": cineFlowError.technicalDescription,
                    "probe": "parallel"
                ]
            )
            return .failure(
                SwarmProbeFailure(
                    index: index,
                    release: release,
                    reason: String(describing: error),
                    error: cineFlowError
                )
            )
        }
    }

    private func resolveRelease(
        _ release: TorrentRelease,
        request: PlaybackPipelineRequest
    ) async throws -> ResolvedPlaybackSource {
        try validate(release)
        await log("stream.resolve.start", request: request, release: release)

        if let directStreamURL = release.directStreamURL {
            return try await resolveDirectRelease(release, directStreamURL: directStreamURL, request: request)
        }

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
        await log(
            "torrent.metadata.ready",
            request: request,
            release: release,
            metadata: metadataPayload(sessionID: session.id, files: files, status: status)
        )

        return try await resolvePreparedRelease(
            release,
            session: session,
            files: files,
            request: request
        )
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

    private func resolveDirectRelease(
        _ release: TorrentRelease,
        directStreamURL: URL,
        request: PlaybackPipelineRequest
    ) async throws -> ResolvedPlaybackSource {
        guard directStreamURL.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }
        await log(
            "stream.url.ready",
            request: request,
            release: release,
            metadata: [
                "streamURL": debugURL(directStreamURL),
                "urlScheme": directStreamURL.scheme ?? "file",
                "source": "direct"
            ]
        )
        await log(
            "stream.availability.start",
            request: request,
            release: release,
            metadata: ["urlScheme": directStreamURL.scheme ?? "file", "source": "direct"]
        )
        let availability = await availabilityChecker.check(
            directStreamURL,
            timeoutSeconds: request.availabilityTimeoutSeconds
        )
        switch availability {
        case .available:
            break
        case .unavailable(let reason):
            throw PlaybackServiceError.unsupported(operation: "direct stream availability check failed: \(reason)")
        }

        let source = PlaybackMediaSource(
            id: request.selectionContext?.episodeID ?? request.mediaID,
            title: request.selectionContext?.displayTitle ?? release.title,
            url: directStreamURL,
            release: release,
            qualityLabel: release.qualityLabel,
            sourceName: release.sourceName,
            selectionContext: request.selectionContext
        )
        return ResolvedPlaybackSource(source: source, session: nil, mediaSelection: nil)
    }

    private func resolvePreparedRelease(
        _ release: TorrentRelease,
        session: TorrentSession,
        files: [TorrentFile],
        request: PlaybackPipelineRequest
    ) async throws -> ResolvedPlaybackSource {
        let engine = torrentEngine
        let selection = try await ensureMediaFileSelected(
            session: session,
            release: release,
            files: files,
            selectionContext: request.selectionContext,
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

        await log(
            "stream.availability.start",
            request: request,
            release: release,
            metadata: [
                "sessionID": session.id,
                "streamURL": debugURL(streamingURL),
                "urlScheme": streamingURL.scheme ?? "file",
                "source": streamingURL.isStreamlyLocalTorrentStreamURL ? "local_torrent_stream" : "remote_stream"
            ]
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
    }

    private func ensureMediaFileSelected(
        session: TorrentSession,
        release: TorrentRelease,
        files: [TorrentFile],
        selectionContext: PlaybackSelectionContext?,
        operationTimeoutSeconds: TimeInterval
    ) async throws -> TorrentMediaFileSelection? {
        if let selectedFileID = session.selectedFileId {
            if let selectedFile = files.first(where: { $0.id == selectedFileID }) {
                await logSelectedFile(session: session, release: release, file: selectedFile)
            }
            try await prioritize(
                files: files,
                selectedFileID: selectedFileID,
                sessionID: session.id,
                timeout: operationTimeoutSeconds
            )
            return nil
        }

        guard let selection = TorrentMediaFileSelector.selection(
            for: release,
            files: files,
            selectionContext: selectionContext
        ) else {
            throw PlaybackServiceError.unsupported(operation: ReleaseFallbackReason.missingMediaFile.userFacingSummary)
        }

        if selection.requiresManualConfirmation {
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
        try await withTimeout(seconds: timeout, operationName: "setSequentialDownload") {
            try await engine.setSequentialDownload(sessionId: sessionID, enabled: true)
        }

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
        guard release.magnetURI != nil || release.torrentFileURL != nil || release.directStreamURL != nil else {
            throw TorrentEngineError.invalidTorrentFile
        }
    }

    private func validateSwarmAvailability(_ status: TorrentStatus) throws {
        guard status.health.seeders == 0,
              status.health.availability < 1,
              status.progress.bufferedBytes == 0
        else { return }

        throw TorrentEngineError.unsupported(
            operation: "swarm_unavailable:seeders=0,availability=\(String(format: "%.3f", status.health.availability)),peers=\(status.health.connectedPeers)"
        )
    }

    private func waitForUsableSwarmStatus(
        sessionID: String,
        request: PlaybackPipelineRequest
    ) async throws -> TorrentStatus {
        let engine = torrentEngine
        let deadline = Date().addingTimeInterval(request.parallelSwarmProbeTimeoutSeconds)
        var lastStatus: TorrentStatus?
        var lastError: Error?

        while true {
            do {
                let status = try await withTimeout(seconds: min(2, request.parallelSwarmProbeTimeoutSeconds), operationName: "torrent.status") {
                    try await engine.getStatus(sessionId: sessionID)
                }
                lastStatus = status
                do {
                    try validateSwarmAvailability(status)
                    return status
                } catch {
                    lastError = error
                }
            } catch {
                lastError = error
            }

            if Date() >= deadline {
                if let lastError {
                    throw lastError
                }
                if let lastStatus {
                    try validateSwarmAvailability(lastStatus)
                    return lastStatus
                }
                throw PlaybackPipelineTimeoutError(
                    operationName: "torrent.swarmProbe",
                    timeoutSeconds: request.parallelSwarmProbeTimeoutSeconds
                )
            }

            try await Task.sleep(nanoseconds: 750_000_000)
        }
    }

    private func metadataPayload(
        sessionID: String,
        files: [TorrentFile],
        status: TorrentStatus?
    ) -> [String: String] {
        var payload = ["sessionID": sessionID, "fileCount": "\(files.count)"]
        if let status {
            payload["torrentState"] = String(describing: status.state)
            payload["peersCount"] = "\(status.health.connectedPeers)"
            payload["seedersCount"] = "\(status.health.seeders)"
            payload["leechersCount"] = "\(status.health.leechers)"
            payload["availability"] = String(format: "%.3f", status.health.availability)
            payload["bufferedBytes"] = "\(status.progress.bufferedBytes)"
            payload["downloadSpeedBytesPerSecond"] = "\(status.progress.downloadSpeedBytesPerSecond)"
        } else {
            payload["peersCount"] = "unknown"
        }
        return payload
    }

    private func candidateReleases(for request: PlaybackPipelineRequest) -> [TorrentRelease] {
        let primary = request.primaryRelease
        let rankedFallbacks = ReleaseRankingEngine(preferences: request.rankingPreferences)
            .rank(request.fallbackReleases.filter { $0.id != primary.id })
            .map(\.release)

        var unique: [TorrentRelease] = [primary]
        var seen = Set([ReleaseFallbackPlanner.playbackIdentity(for: primary)])
        for release in rankedFallbacks where seen.insert(ReleaseFallbackPlanner.playbackIdentity(for: release)).inserted {
            unique.append(release)
        }

        return Array(unique.prefix(1 + request.maxAutomaticFallbacks))
    }

    private func fallbackSuggestion(
        request: PlaybackPipelineRequest,
        failedRelease: TorrentRelease,
        attemptedIDs: Set<String>
    ) -> ReleaseFallbackSuggestion? {
        let attemptedIdentities = Set(
            request.fallbackReleases
                .filter { attemptedIDs.contains($0.id) }
                .map { ReleaseFallbackPlanner.playbackIdentity(for: $0) }
        )
        let remaining = request.fallbackReleases.filter {
            !attemptedIDs.contains($0.id)
                && !attemptedIdentities.contains(ReleaseFallbackPlanner.playbackIdentity(for: $0))
        }
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
    let session: TorrentSession?
    let mediaSelection: TorrentMediaFileSelection?
}

private enum SwarmProbeResult: Sendable {
    case success(SwarmProbeSuccess)
    case failure(SwarmProbeFailure)

    var index: Int {
        switch self {
        case .success(let success):
            success.index
        case .failure(let failure):
            failure.index
        }
    }
}

private struct SwarmProbeSuccess: Sendable {
    let index: Int
    let release: TorrentRelease
    let session: TorrentSession
    let files: [TorrentFile]
    let status: TorrentStatus?
}

private struct SwarmProbeFailure: Sendable {
    let index: Int
    let release: TorrentRelease
    let reason: String
    let error: CineFlowError
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
