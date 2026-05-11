import AVFoundation
import CineFlowCore
import Foundation
import Network

@MainActor
public protocol AVPlayerProviding: AnyObject {
    var avPlayer: AVPlayer { get }
}

@MainActor
public final class AVFoundationPlaybackService: PlaybackServiceProtocol, AVPlayerProviding {
    public let avPlayer = AVPlayer()

    private var status = PlaybackStatus()
    private var legacyState: PlaybackState = .idle

    public init() {}

    public var currentState: PlaybackState {
        get async { legacyState }
    }

    public var currentStatus: PlaybackStatus {
        get async {
            statusWithPlayerTime()
        }
    }

    public func play(_ source: PlaybackMediaSource) async throws {
        guard source.url.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }

        let item = AVPlayerItem(url: source.url)
        item.preferredForwardBufferDuration = source.url.isStreamlyLocalTorrentStreamURL ? 30 : 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        avPlayer.replaceCurrentItem(with: item)
        avPlayer.play()

        status = PlaybackStatus(
            media: source,
            state: .playing,
            currentTime: 0,
            duration: Self.duration(from: item),
            bufferingState: .ready,
            volume: Double(avPlayer.volume),
            isMuted: avPlayer.isMuted,
            playbackSpeed: status.playbackSpeed,
            qualityLabel: source.qualityLabel,
            sourceName: source.sourceName,
            audioBoost: status.audioBoost,
            subtitleDelaySeconds: status.subtitleDelaySeconds,
            subtitleFontSize: status.subtitleFontSize,
            subtitleStyle: status.subtitleStyle
        )
        legacyState = source.release.map { .playing($0) } ?? .preparing
    }

    public func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
        legacyState = .playing(release)
    }

    public func pause() async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        avPlayer.pause()
        status = statusWithPlayerTime(state: .paused)
        if case .playing(let release) = legacyState {
            legacyState = .paused(release)
        }
    }

    public func resume() async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        avPlayer.play()
        status = statusWithPlayerTime(state: .playing)
        if case .paused(let release) = legacyState {
            legacyState = .playing(release)
        }
    }

    public func stop() async throws {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        status = PlaybackStatus()
        legacyState = .idle
    }

    public func seek(to time: Double) async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        await avPlayer.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
        status = statusWithPlayerTime()
    }

    public func setVolume(_ volume: Double) async throws {
        avPlayer.volume = Float(min(max(volume, 0), 1))
        status = statusWithPlayerTime()
    }

    public func setMuted(_ isMuted: Bool) async throws {
        avPlayer.isMuted = isMuted
        status = statusWithPlayerTime()
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        let bounded = Float(max(0.25, min(speed, 4)))
        avPlayer.rate = bounded
        status = statusWithPlayerTime(playbackSpeed: Double(bounded), state: bounded == 0 ? .paused : .playing)
    }

    public func setAudioBoost(_ boost: Double) async throws {
        status = statusWithPlayerTime(audioBoost: max(1, min(boost, 2.5)))
    }

    public func selectAudioTrack(id: String?) async throws {}

    public func selectSubtitleTrack(id: String?) async throws {}

    public func setSubtitleDelay(_ seconds: Double) async throws {
        status = statusWithPlayerTime(subtitleDelaySeconds: max(-10, min(seconds, 10)))
    }

    public func setSubtitleFontSize(_ fontSize: Double) async throws {
        status = statusWithPlayerTime(subtitleFontSize: max(24, min(fontSize, 72)))
    }

    public func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {
        status = statusWithPlayerTime(subtitleStyle: style)
    }

    public func setFullscreen(_ isFullscreen: Bool) async throws {
        status = statusWithPlayerTime(isFullscreen: isFullscreen)
    }

    public func setPictureInPicture(_ isActive: Bool) async throws {
        throw PlaybackServiceError.unsupported(operation: "picture-in-picture")
    }

    public nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                while !Task.isCancelled {
                    let monitoredStatus = self.statusWithPlayerTime(state: self.monitoredRunState())
                    continuation.yield(monitoredStatus)

                    if monitoredStatus.media == nil || monitoredStatus.state.isTerminal {
                        continuation.finish()
                        return
                    }

                    try? await Task.sleep(nanoseconds: 750_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func monitoredRunState() -> PlaybackRunState {
        guard let item = avPlayer.currentItem else { return .idle }
        if let error = item.error ?? avPlayer.error {
            return .failed(reason: error.localizedDescription)
        }
        if let duration = Self.duration(from: item), duration > 0 {
            let currentTime = avPlayer.currentTime().seconds.finiteOrZero
            if currentTime >= max(0, duration - 0.35) {
                return .completed
            }
        }

        switch avPlayer.timeControlStatus {
        case .paused:
            return status.state == .playing ? .playing : .paused
        case .waitingToPlayAtSpecifiedRate:
            return .buffering
        case .playing:
            return .playing
        @unknown default:
            return status.state
        }
    }

    private func statusWithPlayerTime(
        playbackSpeed: Double? = nil,
        state: PlaybackRunState? = nil,
        isFullscreen: Bool? = nil,
        audioBoost: Double? = nil,
        subtitleDelaySeconds: Double? = nil,
        subtitleFontSize: Double? = nil,
        subtitleStyle: SubtitleVisualStyle? = nil
    ) -> PlaybackStatus {
        let item = avPlayer.currentItem
        let runState = state ?? status.state
        return PlaybackStatus(
            media: status.media,
            state: runState,
            currentTime: avPlayer.currentTime().seconds.finiteOrZero,
            duration: Self.duration(from: item) ?? status.duration,
            bufferingState: bufferingState(for: item, runState: runState),
            volume: Double(avPlayer.volume),
            isMuted: avPlayer.isMuted,
            playbackSpeed: playbackSpeed ?? status.playbackSpeed,
            audioTracks: status.audioTracks,
            subtitleTracks: status.subtitleTracks,
            selectedAudioTrackId: status.selectedAudioTrackId,
            selectedSubtitleTrackId: status.selectedSubtitleTrackId,
            isFullscreen: isFullscreen ?? status.isFullscreen,
            isPictureInPictureActive: status.isPictureInPictureActive,
            qualityLabel: status.qualityLabel,
            sourceName: status.sourceName,
            chapters: status.chapters,
            audioBoost: audioBoost ?? status.audioBoost,
            subtitleDelaySeconds: subtitleDelaySeconds ?? status.subtitleDelaySeconds,
            subtitleFontSize: subtitleFontSize ?? status.subtitleFontSize,
            subtitleStyle: subtitleStyle ?? status.subtitleStyle
        )
    }

    private func bufferingState(for item: AVPlayerItem?, runState: PlaybackRunState) -> PlaybackBufferingState {
        guard let item else { return .idle }
        if runState == .buffering {
            return .buffering(progress: bufferedFraction(for: item))
        }
        return .ready
    }

    private func bufferedFraction(for item: AVPlayerItem) -> Double {
        guard let duration = Self.duration(from: item), duration > 0 else { return 0 }
        let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }
        guard let furthest = ranges.map({ $0.start.seconds + $0.duration.seconds }).max(), furthest.isFinite else {
            return 0
        }
        return min(max(furthest / duration, 0), 1)
    }

    private static func duration(from item: AVPlayerItem?) -> Double? {
        guard let item else { return nil }
        let seconds = item.asset.duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

@MainActor
public final class TranscodingAVPlaybackService: PlaybackServiceProtocol, AVPlayerProviding {
    public var avPlayer: AVPlayer { directService.avPlayer }

    private let directService: AVFoundationPlaybackService
    private let ffmpegExecutableURL: URL?
    private let fileManager: FileManager
    private var transcodeProcess: Process?
    private var transcodeDirectoryURL: URL?
    private var hlsServer: LocalHLSFileServer?
    private var originalSource: PlaybackMediaSource?
    private let hlsStartupTimeoutSeconds: TimeInterval = 120
    private let maxHLSStartupAttempts = 6

    public init(
        directService: AVFoundationPlaybackService? = nil,
        ffmpegExecutableURL: URL? = FFmpegRuntimeLocator.defaultExecutableURL(),
        fileManager: FileManager = .default
    ) {
        self.directService = directService ?? AVFoundationPlaybackService()
        self.ffmpegExecutableURL = ffmpegExecutableURL
        self.fileManager = fileManager
    }

    deinit {
        transcodeProcess?.terminate()
    }

    public var currentState: PlaybackState {
        get async { await directService.currentState }
    }

    public var currentStatus: PlaybackStatus {
        get async {
            await statusPreservingOriginalSource(directService.currentStatus)
        }
    }

    public func play(_ source: PlaybackMediaSource) async throws {
        try await stopTranscodeIfNeeded()
        originalSource = source

        if source.url.requiresLocalHLSBridge {
            guard let ffmpegExecutableURL else {
                throw PlaybackServiceError.unsupported(operation: "ffmpeg runtime unavailable")
            }
            let playlistURL = try await startHLSBridge(source: source, ffmpegExecutableURL: ffmpegExecutableURL)
            var bridgedSource = source
            bridgedSource = PlaybackMediaSource(
                id: source.id,
                title: source.title,
                url: playlistURL,
                release: source.release,
                qualityLabel: source.qualityLabel,
                sourceName: source.sourceName,
                selectionContext: source.selectionContext
            )
            try await directService.play(bridgedSource)
            return
        }

        try await directService.play(source)
    }

    public func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
    }

    public func pause() async throws {
        try await directService.pause()
    }

    public func resume() async throws {
        try await directService.resume()
    }

    public func stop() async throws {
        try await stopTranscodeIfNeeded()
        try await directService.stop()
        originalSource = nil
    }

    public func seek(to time: Double) async throws {
        try await directService.seek(to: time)
    }

    public func setVolume(_ volume: Double) async throws {
        try await directService.setVolume(volume)
    }

    public func setMuted(_ isMuted: Bool) async throws {
        try await directService.setMuted(isMuted)
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        try await directService.setPlaybackSpeed(speed)
    }

    public func setAudioBoost(_ boost: Double) async throws {
        try await directService.setAudioBoost(boost)
    }

    public func selectAudioTrack(id: String?) async throws {
        try await directService.selectAudioTrack(id: id)
    }

    public func selectSubtitleTrack(id: String?) async throws {
        try await directService.selectSubtitleTrack(id: id)
    }

    public func setSubtitleDelay(_ seconds: Double) async throws {
        try await directService.setSubtitleDelay(seconds)
    }

    public func setSubtitleFontSize(_ fontSize: Double) async throws {
        try await directService.setSubtitleFontSize(fontSize)
    }

    public func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {
        try await directService.setSubtitleStyle(style)
    }

    public func setFullscreen(_ isFullscreen: Bool) async throws {
        try await directService.setFullscreen(isFullscreen)
    }

    public func setPictureInPicture(_ isActive: Bool) async throws {
        try await directService.setPictureInPicture(isActive)
    }

    public nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    for try await status in self.directService.statusUpdates() {
                        continuation.yield(await self.statusPreservingOriginalSource(status))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func startHLSBridge(source: PlaybackMediaSource, ffmpegExecutableURL: URL) async throws -> URL {
        let directoryURL = try makeTranscodeDirectory()
        let playlistURL = directoryURL.appendingPathComponent("stream.m3u8")
        let segmentPatternURL = directoryURL.appendingPathComponent("segment_%05d.ts")
        transcodeDirectoryURL = directoryURL
        let startupDeadline = Date().addingTimeInterval(hlsStartupTimeoutSeconds)
        var attempt = 0
        var lastStartupError: PlaybackServiceError?

        while Date() < startupDeadline, attempt < maxHLSStartupAttempts {
            attempt += 1
            try removeStaleHLSOutputs(in: directoryURL)

            let logURL = directoryURL.appendingPathComponent("ffmpeg-attempt-\(attempt).log")
            let logPipe = Pipe()
            let process = makeFFmpegHLSProcess(
                executableURL: ffmpegExecutableURL,
                sourceURL: source.url,
                playlistURL: playlistURL,
                segmentPatternURL: segmentPatternURL,
                logPipe: logPipe
            )

            try process.run()
            transcodeProcess = process

            do {
                try await waitForPlayablePlaylist(
                    at: playlistURL,
                    process: process,
                    timeoutSeconds: startupDeadline.timeIntervalSinceNow
                )
                streamFFmpegLog(from: logPipe, to: logURL)
                let server = try LocalHLSFileServer(rootURL: directoryURL)
                hlsServer = server
                return server.url(for: "stream.m3u8")
            } catch {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                let logText = captureFFmpegLog(from: logPipe, to: logURL)
                lastStartupError = transcodeStartupError(
                    from: error,
                    logText: logText,
                    attempt: attempt
                )
                transcodeProcess = nil

                guard shouldRetryTranscodeStartup(after: error, logText: logText),
                      attempt < maxHLSStartupAttempts,
                      Date() < startupDeadline
                else {
                    throw lastStartupError ?? PlaybackServiceError.unsupported(operation: "ffmpeg HLS startup failed")
                }

                let delay = min(2.0, 0.5 + (Double(attempt) * 0.35))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastStartupError ?? PlaybackServiceError.unsupported(operation: "ffmpeg HLS startup timeout")
    }

    private func makeFFmpegHLSProcess(
        executableURL: URL,
        sourceURL: URL,
        playlistURL: URL,
        segmentPatternURL: URL,
        logPipe: Pipe
    ) -> Process {
        let process = Process()
        process.executableURL = executableURL
        let isLocalTorrentStream = sourceURL.isStreamlyLocalTorrentStreamURL
        let readTimeoutMicros = isLocalTorrentStream ? "120000000" : "8000000"
        var arguments = [
            "-hide_banner",
            "-loglevel", "warning",
            "-nostdin",
            "-fflags", "+genpts",
            "-rw_timeout", readTimeoutMicros,
            "-i", sourceURL.absoluteString,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-sn",
            "-c:v", "h264_videotoolbox",
            "-b:v", "8000k",
            "-maxrate", "10000k",
            "-bufsize", "16000k",
            "-allow_sw", "1",
            "-c:a", "aac",
            "-ac", "2",
            "-b:a", "192k",
            "-f", "hls",
            "-hls_time", "2",
        ]
        if isLocalTorrentStream {
            arguments += [
                "-hls_playlist_type", "event",
                "-hls_list_size", "0",
                "-hls_flags", "independent_segments+temp_file"
            ]
        } else {
            arguments += [
                "-hls_list_size", "8",
                "-hls_flags", "delete_segments+independent_segments+temp_file"
            ]
        }
        arguments += [
            "-hls_segment_filename", segmentPatternURL.path,
            playlistURL.path
        ]
        process.arguments = arguments
        process.standardOutput = logPipe
        process.standardError = logPipe
        return process
    }

    private func removeStaleHLSOutputs(in directoryURL: URL) throws {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents where url.pathExtension == "m3u8" || url.pathExtension == "ts" || url.lastPathComponent.hasSuffix(".tmp") {
            try? fileManager.removeItem(at: url)
        }
    }

    private func makeTranscodeDirectory() throws -> URL {
        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Streamly", isDirectory: true)
        .appendingPathComponent("Transcode", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        return cacheRoot
    }

    private func waitForPlayablePlaylist(at playlistURL: URL, process: Process, timeoutSeconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(max(0.25, timeoutSeconds))
        while Date() < deadline {
            if fileManager.fileExists(atPath: playlistURL.path),
               let data = try? Data(contentsOf: playlistURL),
               let text = String(data: data, encoding: .utf8),
               Self.playlistIsReadyForStartup(text) {
                return
            }

            if !process.isRunning {
                throw TranscodeStartupFailure.exitedEarly
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw TranscodeStartupFailure.timedOut
    }

    static func playlistIsReadyForStartup(_ text: String) -> Bool {
        var segmentCount = 0
        var duration = 0.0
        for line in text.split(separator: "\n") {
            guard line.hasPrefix("#EXTINF:") else { continue }
            segmentCount += 1
            let rawValue = line
                .dropFirst("#EXTINF:".count)
                .split(separator: ",", maxSplits: 1)
                .first
            if let rawValue, let seconds = Double(rawValue) {
                duration += seconds
            }
        }
        return segmentCount >= 4 && duration >= 8
    }

    private func shouldRetryTranscodeStartup(after error: Error, logText: String) -> Bool {
        guard matchesTranscodeFailure(error, .exitedEarly) else { return false }
        let lowercasedLog = logText.lowercased()
        return lowercasedLog.contains("503")
            || lowercasedLog.contains("5xx")
            || lowercasedLog.contains("service unavailable")
            || lowercasedLog.contains("stream ends prematurely")
            || lowercasedLog.contains("partial file")
            || lowercasedLog.contains("cannot determine format")
            || lowercasedLog.contains("input/output error")
            || lowercasedLog.contains("operation timed out")
            || lowercasedLog.contains("connection timed out")
    }

    private func transcodeStartupError(from error: Error, logText: String, attempt: Int) -> PlaybackServiceError {
        let detail = summarizedFFmpegLog(logText)
        let baseMessage: String
        if matchesTranscodeFailure(error, .timedOut) {
            baseMessage = "ffmpeg HLS startup timeout"
        } else {
            baseMessage = "ffmpeg exited before HLS playback became ready"
        }

        if detail.isEmpty {
            return PlaybackServiceError.unsupported(operation: "\(baseMessage) after attempt \(attempt)")
        }
        return PlaybackServiceError.unsupported(operation: "\(baseMessage) after attempt \(attempt): \(detail)")
    }

    private func matchesTranscodeFailure(_ error: Error, _ expected: TranscodeStartupFailure) -> Bool {
        guard let failure = error as? TranscodeStartupFailure else { return false }
        return failure == expected
    }

    private func captureFFmpegLog(from pipe: Pipe, to logURL: URL) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try? data.write(to: logURL)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func streamFFmpegLog(from pipe: Pipe, to logURL: URL) {
        Task.detached(priority: .utility) {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try? data.write(to: logURL)
        }
    }

    private func summarizedFFmpegLog(_ logText: String) -> String {
        logText
            .split(separator: "\n")
            .suffix(3)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    private func stopTranscodeIfNeeded() async throws {
        if let transcodeProcess, transcodeProcess.isRunning {
            transcodeProcess.terminate()
            try? await Task.sleep(nanoseconds: 250_000_000)
            if transcodeProcess.isRunning {
                transcodeProcess.interrupt()
            }
        }
        transcodeProcess = nil

        hlsServer?.stop()
        hlsServer = nil

        if let transcodeDirectoryURL {
            try? fileManager.removeItem(at: transcodeDirectoryURL)
        }
        transcodeDirectoryURL = nil
    }

    private func statusPreservingOriginalSource(_ status: PlaybackStatus) async -> PlaybackStatus {
        guard let originalSource else { return status }
        return PlaybackStatus(
            media: originalSource,
            state: status.state,
            currentTime: status.currentTime,
            duration: status.duration,
            bufferingState: status.bufferingState,
            volume: status.volume,
            isMuted: status.isMuted,
            playbackSpeed: status.playbackSpeed,
            audioTracks: status.audioTracks,
            subtitleTracks: status.subtitleTracks,
            selectedAudioTrackId: status.selectedAudioTrackId,
            selectedSubtitleTrackId: status.selectedSubtitleTrackId,
            isFullscreen: status.isFullscreen,
            isPictureInPictureActive: status.isPictureInPictureActive,
            qualityLabel: originalSource.qualityLabel,
            sourceName: originalSource.sourceName,
            chapters: status.chapters,
            audioBoost: status.audioBoost,
            subtitleDelaySeconds: status.subtitleDelaySeconds,
            subtitleFontSize: status.subtitleFontSize,
            subtitleStyle: status.subtitleStyle
        )
    }
}

private final class LocalHLSFileServer: @unchecked Sendable {
    private let rootURL: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "streamly.hls.file-server", qos: .userInitiated)
    private let fileManager: FileManager
    private var port: UInt16 = 0

    init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        listener = try NWListener(using: .tcp, on: .any)

        let ready = DispatchSemaphore(value: 0)
        var startupError: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                startupError = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)

        if let startupError {
            throw startupError
        }
        guard let port = listener.port?.rawValue else {
            throw PlaybackServiceError.unsupported(operation: "hls local server startup")
        }
        self.port = port
    }

    func url(for path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/\(path)")!
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let response = self.response(for: data ?? Data())
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for requestData: Data) -> Data {
        guard let request = String(data: requestData, encoding: .utf8),
              let requestLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else {
            return httpResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("bad_request".utf8))
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("bad_request".utf8))
        }

        let method = parts[0]
        guard method == "GET" || method == "HEAD" else {
            return httpResponse(status: "405 Method Not Allowed", contentType: "text/plain", body: Data("method_not_allowed".utf8))
        }

        let path = sanitizedPath(String(parts[1]))
        guard let path else {
            return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data("not_found".utf8))
        }

        let fileURL = rootURL.appendingPathComponent(path, isDirectory: false)
        guard fileURL.path.hasPrefix(rootURL.path),
              fileManager.fileExists(atPath: fileURL.path),
              let body = try? Data(contentsOf: fileURL)
        else {
            return httpResponse(status: "404 Not Found", contentType: "text/plain", body: Data("not_found".utf8))
        }

        let contentType = contentType(for: fileURL)
        if let range = byteRange(from: request, size: body.count) {
            let responseBody = method == "HEAD" ? Data() : body.subdata(in: range)
            return httpResponse(
                status: "206 Partial Content",
                contentType: contentType,
                headers: ["Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)"],
                body: responseBody,
                contentLength: range.count
            )
        }

        return httpResponse(
            status: "200 OK",
            contentType: contentType,
            body: method == "HEAD" ? Data() : body,
            contentLength: body.count
        )
    }

    private func sanitizedPath(_ rawPath: String) -> String? {
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let value = decoded.isEmpty ? "stream.m3u8" : decoded
        guard !value.contains(".."), !value.hasPrefix("/") else { return nil }
        return value
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8":
            "application/vnd.apple.mpegurl"
        case "ts":
            "video/mp2t"
        default:
            "application/octet-stream"
        }
    }

    private func byteRange(from request: String, size: Int) -> Range<Int>? {
        guard let line = request.components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("range:") }),
            let value = line.components(separatedBy: "bytes=").dropFirst().first
        else {
            return nil
        }

        let rangeText = value.trimmingCharacters(in: .whitespaces)
            .split(separator: ",", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let parts = rangeText.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let startText = parts.first,
              let start = Int(startText)
        else {
            return nil
        }

        let end = parts.count > 1 ? Int(parts[1]) ?? (size - 1) : (size - 1)
        guard start >= 0, start < size else { return nil }
        return start..<(min(end, size - 1) + 1)
    }

    private func httpResponse(
        status: String,
        contentType: String,
        headers: [String: String] = [:],
        body: Data,
        contentLength: Int? = nil
    ) -> Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status)\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Accept-Ranges: bytes\r\n".utf8))
        for (key, value) in headers {
            response.append(Data("\(key): \(value)\r\n".utf8))
        }
        response.append(Data("Content-Length: \(contentLength ?? body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        return response
    }
}

private enum TranscodeStartupFailure: Error, Equatable {
    case exitedEarly
    case timedOut
}

public enum FFmpegRuntimeLocator {
    public static func defaultExecutableURL(fileManager: FileManager = .default) -> URL? {
        let environmentPath = ProcessInfo.processInfo.environment["STREAMLY_FFMPEG_EXECUTABLE"]
        if let environmentPath, fileManager.isExecutableFile(atPath: environmentPath) {
            return URL(fileURLWithPath: environmentPath)
        }

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ffmpeg"),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ffmpeg"),
            URL(fileURLWithPath: "/Applications/Stremio.app/Contents/MacOS/ffmpeg"),
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        ]

        return candidates.compactMap { $0 }.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

private extension Double {
    var finiteOrZero: Double {
        isFinite ? self : 0
    }
}

private extension URL {
    var requiresLocalHLSBridge: Bool {
        guard let scheme = scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost"
    }

    var isStreamlyLocalTorrentStreamURL: Bool {
        guard requiresLocalHLSBridge else {
            return false
        }
        return path.hasPrefix("/stream/")
    }
}
