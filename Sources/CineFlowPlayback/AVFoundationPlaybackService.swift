import AVFoundation
import CineFlowCore
import Darwin
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
    private var durationOverride: Double?
    private var audioTracksOverride: [AudioTrack] = []
    private var subtitleTracksOverride: [SubtitleTrack] = []
    private var selectedAudioTrackId: String?
    private var selectedSubtitleTrackId: String?

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
        try await play(
            source,
            durationOverride: nil,
            audioTracks: [],
            subtitleTracks: [],
            selectedAudioTrackId: nil,
            selectedSubtitleTrackId: nil,
            autoplay: true,
            preferredForwardBufferDuration: nil
        )
    }

    func play(
        _ source: PlaybackMediaSource,
        durationOverride: Double?,
        audioTracks: [AudioTrack],
        subtitleTracks: [SubtitleTrack],
        selectedAudioTrackId: String?,
        selectedSubtitleTrackId: String?,
        autoplay: Bool,
        preferredForwardBufferDuration: TimeInterval?
    ) async throws {
        guard source.url.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }

        let item = AVPlayerItem(url: source.url)
        let isLocalTorrentStream = source.url.isStreamlyLocalTorrentStreamURL
        let isLocalHLSBridge = source.url.isStreamlyLocalHLSBridgePlaylistURL
        let isLocalStreamingSource = isLocalTorrentStream || isLocalHLSBridge
        item.preferredForwardBufferDuration = isLocalStreamingSource ? (preferredForwardBufferDuration ?? (isLocalHLSBridge ? 8 : 2)) : 0
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        avPlayer.automaticallyWaitsToMinimizeStalling = !isLocalTorrentStream
        self.durationOverride = durationOverride.flatMap(Self.validDuration)
        self.audioTracksOverride = audioTracks
        self.subtitleTracksOverride = subtitleTracks
        self.selectedAudioTrackId = selectedAudioTrackId ?? audioTracks.first?.id
        self.selectedSubtitleTrackId = selectedSubtitleTrackId
        avPlayer.replaceCurrentItem(with: item)
        if autoplay {
            avPlayer.play()
        }

        status = PlaybackStatus(
            media: source,
            state: autoplay ? .playing : .buffering,
            currentTime: 0,
            duration: Self.duration(from: item, mediaURL: source.url, durationOverride: self.durationOverride),
            bufferingState: autoplay ? .ready : .buffering(progress: 0),
            volume: Double(avPlayer.volume),
            isMuted: avPlayer.isMuted,
            playbackSpeed: status.playbackSpeed,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioTrackId: self.selectedAudioTrackId,
            selectedSubtitleTrackId: self.selectedSubtitleTrackId,
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
        durationOverride = nil
        audioTracksOverride = []
        subtitleTracksOverride = []
        selectedAudioTrackId = nil
        selectedSubtitleTrackId = nil
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

    public func selectAudioTrack(id: String?) async throws {
        if let id, !audioTracksOverride.contains(where: { $0.id == id }) {
            throw PlaybackServiceError.trackNotFound(id)
        }
        selectedAudioTrackId = id
        status = statusWithPlayerTime()
    }

    public func selectSubtitleTrack(id: String?) async throws {
        if let id, !subtitleTracksOverride.contains(where: { $0.id == id }) && !Self.isExternalSubtitleTrackID(id) {
            throw PlaybackServiceError.trackNotFound(id)
        }
        selectedSubtitleTrackId = id
        status = statusWithPlayerTime()
    }

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
        if let duration = Self.duration(from: item, mediaURL: status.media?.url, durationOverride: durationOverride), duration > 0 {
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
        let mediaURL = status.media?.url
        let measuredDuration = Self.duration(from: item, mediaURL: mediaURL, durationOverride: durationOverride)
        let duration = measuredDuration ?? (mediaURL?.isStreamlyLocalHLSBridgePlaylistURL == true ? nil : status.duration)
        let runState = state ?? status.state
        return PlaybackStatus(
            media: status.media,
            state: runState,
            currentTime: avPlayer.currentTime().seconds.finiteOrZero,
            duration: duration,
            bufferingState: bufferingState(for: item, runState: runState),
            volume: Double(avPlayer.volume),
            isMuted: avPlayer.isMuted,
            playbackSpeed: playbackSpeed ?? status.playbackSpeed,
            audioTracks: audioTracksOverride.isEmpty ? status.audioTracks : audioTracksOverride,
            subtitleTracks: subtitleTracksOverride.isEmpty ? status.subtitleTracks : subtitleTracksOverride,
            selectedAudioTrackId: selectedAudioTrackId,
            selectedSubtitleTrackId: selectedSubtitleTrackId,
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
        guard let duration = Self.duration(from: item, mediaURL: status.media?.url, durationOverride: durationOverride), duration > 0 else { return 0 }
        let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }
        guard let furthest = ranges.map({ $0.start.seconds + $0.duration.seconds }).max(), furthest.isFinite else {
            return 0
        }
        return min(max(furthest / duration, 0), 1)
    }

    private static func duration(from item: AVPlayerItem?, mediaURL: URL?) -> Double? {
        guard let item else { return nil }
        return effectiveDuration(item.duration.seconds, mediaURL: mediaURL)
    }

    private static func duration(from item: AVPlayerItem?, mediaURL: URL?, durationOverride: Double?) -> Double? {
        guard let item else { return validDuration(durationOverride) }
        return effectiveDuration(item.duration.seconds, mediaURL: mediaURL, durationOverride: durationOverride)
    }

    static func effectiveDuration(_ seconds: Double?, mediaURL: URL?, durationOverride: Double? = nil) -> Double? {
        if let override = validDuration(durationOverride) {
            return override
        }
        guard mediaURL?.isStreamlyLocalHLSBridgePlaylistURL != true else { return nil }
        return validDuration(seconds)
    }

    private static func validDuration(_ seconds: Double?) -> Double? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    private static func isExternalSubtitleTrackID(_ id: String) -> Bool {
        id.hasPrefix("local:") || id.hasPrefix("cached:") || id.hasPrefix("opensubtitles:")
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
    private var transcodeLogCapture: FFmpegLogCapture?
    private var hlsServer: LocalHLSFileServer?
    private var originalSource: PlaybackMediaSource?
    private var hlsPlaybackBaseTimeSeconds: Double = 0
    private var hlsSourceDurationSeconds: Double?
    private var hlsAudioTracks: [AudioTrack] = []
    private var hlsSubtitleTracks: [SubtitleTrack] = []
    private var selectedAudioTrackId: String?
    private var selectedSubtitleTrackId: String?
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
        hlsPlaybackBaseTimeSeconds = 0
        hlsSourceDurationSeconds = nil
        hlsAudioTracks = []
        hlsSubtitleTracks = []
        selectedAudioTrackId = nil
        selectedSubtitleTrackId = nil

        if source.url.requiresLocalHLSBridge {
            guard let ffmpegExecutableURL else {
                throw PlaybackServiceError.unsupported(operation: "ffmpeg runtime unavailable")
            }
            let startup = try await startHLSBridge(
                source: source,
                ffmpegExecutableURL: ffmpegExecutableURL,
                startTimeSeconds: 0,
                selectedAudioTrackId: nil
            )
            hlsSourceDurationSeconds = startup.metadata.durationSeconds
            hlsAudioTracks = startup.metadata.audioTracks
            hlsSubtitleTracks = startup.metadata.subtitleTracks
            selectedAudioTrackId = startup.metadata.audioTracks.first?.id
            var bridgedSource = source
            bridgedSource = PlaybackMediaSource(
                id: source.id,
                title: source.title,
                url: startup.playlistURL,
                release: source.release,
                qualityLabel: source.qualityLabel,
                sourceName: source.sourceName,
                selectionContext: source.selectionContext
            )
            try await directService.play(
                bridgedSource,
                durationOverride: remainingHLSDuration(from: 0),
                audioTracks: hlsAudioTracks,
                subtitleTracks: hlsSubtitleTracks,
                selectedAudioTrackId: selectedAudioTrackId,
                selectedSubtitleTrackId: selectedSubtitleTrackId,
                autoplay: false,
                preferredForwardBufferDuration: 2.5
            )
            await restartBridgedPlaybackAtBeginning()
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
        hlsPlaybackBaseTimeSeconds = 0
        hlsSourceDurationSeconds = nil
        hlsAudioTracks = []
        hlsSubtitleTracks = []
        selectedAudioTrackId = nil
        selectedSubtitleTrackId = nil
    }

    public func seek(to time: Double) async throws {
        if originalSource?.url.requiresLocalHLSBridge == true {
            try await restartHLSPlayback(at: time, autoplay: true)
            return
        }
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
        if originalSource?.url.requiresLocalHLSBridge == true {
            if let id, !hlsAudioTracks.contains(where: { $0.id == id }) {
                throw PlaybackServiceError.trackNotFound(id)
            }
            selectedAudioTrackId = id
            let current = await currentStatus.currentTime
            try await restartHLSPlayback(at: current, autoplay: true)
            return
        }
        try await directService.selectAudioTrack(id: id)
    }

    public func selectSubtitleTrack(id: String?) async throws {
        if originalSource?.url.requiresLocalHLSBridge == true {
            let isEmbeddedTrack = id.map { selectedID in
                hlsSubtitleTracks.contains(where: { $0.id == selectedID })
            } ?? false
            if let id, !isEmbeddedTrack && !Self.isExternalSubtitleTrackID(id) {
                throw PlaybackServiceError.trackNotFound(id)
            }
            selectedSubtitleTrackId = id
            try await directService.selectSubtitleTrack(id: isEmbeddedTrack ? id : nil)
            return
        }
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

    private func restartBridgedPlaybackAtBeginning() async {
        guard let item = directService.avPlayer.currentItem else { return }
        await waitForDirectItemReadyForInitialSeek(item)
        let seekableRanges = item.seekableTimeRanges.map(\.timeRangeValue)
        let target = Self.initialHLSSeekTargetSeconds(from: seekableRanges)
        try? await directService.seek(to: target)
        try? await directService.resume()
    }

    private func restartHLSPlayback(at time: Double, autoplay: Bool) async throws {
        guard let originalSource, let ffmpegExecutableURL else {
            try await directService.seek(to: time)
            return
        }

        let target = clampedHLSTime(time)
        try await stopTranscodeIfNeeded()
        hlsPlaybackBaseTimeSeconds = target
        let startup = try await startHLSBridge(
            source: originalSource,
            ffmpegExecutableURL: ffmpegExecutableURL,
            startTimeSeconds: target,
            selectedAudioTrackId: selectedAudioTrackId
        )
        if let duration = startup.metadata.durationSeconds {
            hlsSourceDurationSeconds = duration
        }
        if !startup.metadata.audioTracks.isEmpty {
            hlsAudioTracks = startup.metadata.audioTracks
            if let selectedAudioTrackId, !hlsAudioTracks.contains(where: { $0.id == selectedAudioTrackId }) {
                self.selectedAudioTrackId = hlsAudioTracks.first?.id
            } else if selectedAudioTrackId == nil {
                selectedAudioTrackId = hlsAudioTracks.first?.id
            }
        }
        if !startup.metadata.subtitleTracks.isEmpty {
            hlsSubtitleTracks = startup.metadata.subtitleTracks
        }

        let bridgedSource = PlaybackMediaSource(
            id: originalSource.id,
            title: originalSource.title,
            url: startup.playlistURL,
            release: originalSource.release,
            qualityLabel: originalSource.qualityLabel,
            sourceName: originalSource.sourceName,
            selectionContext: originalSource.selectionContext
        )
        try await directService.play(
            bridgedSource,
            durationOverride: remainingHLSDuration(from: target),
            audioTracks: hlsAudioTracks,
            subtitleTracks: hlsSubtitleTracks,
            selectedAudioTrackId: selectedAudioTrackId,
            selectedSubtitleTrackId: selectedSubtitleTrackId,
            autoplay: false,
            preferredForwardBufferDuration: 2.5
        )

        guard autoplay else { return }
        await restartBridgedPlaybackAtBeginning()
    }

    private func clampedHLSTime(_ time: Double) -> Double {
        let lowerBound = max(0, time)
        guard let duration = hlsSourceDurationSeconds, duration > 0 else { return lowerBound }
        return min(lowerBound, max(0, duration - 1))
    }

    private func remainingHLSDuration(from startTime: Double) -> Double? {
        guard let duration = hlsSourceDurationSeconds, duration > 0 else { return nil }
        return max(1, duration - max(0, startTime))
    }

    private func waitForDirectItemReadyForInitialSeek(_ item: AVPlayerItem) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if item.status == .readyToPlay || !item.seekableTimeRanges.isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    static func initialHLSSeekTargetSeconds(from ranges: [CMTimeRange]) -> Double {
        ranges
            .map { $0.start.seconds }
            .filter { $0.isFinite && $0 >= 0 }
            .min() ?? 0
    }

    private func startHLSBridge(
        source: PlaybackMediaSource,
        ffmpegExecutableURL: URL,
        startTimeSeconds: Double,
        selectedAudioTrackId: String?
    ) async throws -> HLSBridgeStartup {
        let directoryURL = try makeTranscodeDirectory()
        let playlistURL = directoryURL.appendingPathComponent("stream.m3u8")
        let segmentPatternURL = directoryURL.appendingPathComponent("segment_%05d.ts")
        transcodeDirectoryURL = directoryURL
        let isLocalTorrentStream = source.url.isStreamlyLocalTorrentStreamURL
        let startupDeadline = Date().addingTimeInterval(
            Self.hlsStartupTimeoutSeconds(isLocalTorrentStream: isLocalTorrentStream)
        )
        let maxAttempts = Self.maxHLSStartupAttempts(isLocalTorrentStream: isLocalTorrentStream)
        var attempt = 0
        var lastStartupError: PlaybackServiceError?

        while Date() < startupDeadline, attempt < maxAttempts {
            attempt += 1
            try removeStaleHLSOutputs(in: directoryURL)

            let logURL = directoryURL.appendingPathComponent("ffmpeg-attempt-\(attempt).log")
            let logPipe = Pipe()
            let process = makeFFmpegHLSProcess(
                executableURL: ffmpegExecutableURL,
                sourceURL: source.url,
                playlistURL: playlistURL,
                segmentPatternURL: segmentPatternURL,
                startTimeSeconds: startTimeSeconds,
                selectedAudioTrackId: selectedAudioTrackId,
                videoMode: videoMode(for: attempt, isLocalTorrentStream: isLocalTorrentStream),
                logPipe: logPipe
            )

            try process.run()
            transcodeProcess = process
            let logCapture = FFmpegLogCapture(pipe: logPipe, logURL: logURL)
            logCapture.start()

            do {
                try await waitForPlayablePlaylist(
                    at: playlistURL,
                    process: process,
                    timeoutSeconds: startupDeadline.timeIntervalSinceNow
                )
                transcodeLogCapture = logCapture
                let server = try LocalHLSFileServer(rootURL: directoryURL)
                hlsServer = server
                let metadata = Self.mediaMetadata(fromFFmpegLog: logCapture.text)
                return HLSBridgeStartup(playlistURL: server.url(for: "stream.m3u8"), metadata: metadata)
            } catch {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                let logText = logCapture.stopAndFlush()
                lastStartupError = transcodeStartupError(
                    from: error,
                    logText: logText,
                    attempt: attempt
                )
                transcodeProcess = nil

                guard shouldRetryTranscodeStartup(
                    after: error,
                    logText: logText,
                    isLocalTorrentStream: isLocalTorrentStream
                ),
                      attempt < maxAttempts,
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
        startTimeSeconds: Double,
        selectedAudioTrackId: String?,
        videoMode: FFmpegHLSVideoMode,
        logPipe: Pipe
    ) -> Process {
        let process = Process()
        process.executableURL = executableURL
        let isLocalTorrentStream = sourceURL.isStreamlyLocalTorrentStreamURL
        var arguments = [
            "-hide_banner",
            "-loglevel", "info",
            "-nostdin",
            "-fflags", "+genpts",
            "-rw_timeout", Self.hlsReadTimeoutMicros(isLocalTorrentStream: isLocalTorrentStream),
        ]
        arguments += Self.hlsInputProbeArguments(isLocalTorrentStream: isLocalTorrentStream)
        arguments += Self.hlsInputReadRateArguments(isLocalTorrentStream: isLocalTorrentStream)
        if startTimeSeconds > 0 {
            arguments += ["-ss", Self.ffmpegTimeLabel(startTimeSeconds)]
        }
        if isLocalTorrentStream {
            arguments += ["-seekable", "0"]
        }
        arguments += [
            "-i", sourceURL.absoluteString,
            "-map", "0:v:0",
            "-sn",
        ]
        arguments += ["-map", "0:a:\(Self.audioOrdinal(from: selectedAudioTrackId) ?? 0)?"]
        arguments += videoMode.arguments
        arguments += [
            "-c:a", "aac",
            "-ac", "2",
            "-b:a", "192k",
            "-f", "hls",
            "-hls_time", "1",
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

    static func hlsInputProbeArguments(isLocalTorrentStream: Bool) -> [String] {
        [
            "-probesize", isLocalTorrentStream ? "1048576" : "5000000",
            "-analyzeduration", isLocalTorrentStream ? "1500000" : "5000000"
        ]
    }

    static func hlsInputReadRateArguments(isLocalTorrentStream: Bool) -> [String] {
        // Local torrent streams are live producers: keep ffmpeg near playback
        // time after a small startup burst so AVPlayer's event playlist does
        // not race far ahead and stall.
        isLocalTorrentStream ? ["-readrate", "1", "-readrate_initial_burst", "12"] : []
    }

    static func hlsReadTimeoutMicros(isLocalTorrentStream: Bool) -> String {
        isLocalTorrentStream ? "15000000" : "8000000"
    }

    static func hlsStartupTimeoutSeconds(isLocalTorrentStream: Bool) -> TimeInterval {
        isLocalTorrentStream ? 24 : 120
    }

    static func maxHLSStartupAttempts(isLocalTorrentStream: Bool) -> Int {
        isLocalTorrentStream ? 2 : 6
    }

    private func videoMode(for attempt: Int, isLocalTorrentStream: Bool) -> FFmpegHLSVideoMode {
        if isLocalTorrentStream {
            switch attempt {
            case 1:
                return .hardwareH264
            default:
                return .softwareH264
            }
        }

        return attempt == 1 ? .hardwareH264 : .softwareH264
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
        return segmentCount >= 1 && duration >= 1
    }

    static func mediaMetadata(fromFFmpegLog text: String) -> HLSMediaMetadata {
        HLSMediaMetadata.parse(ffmpegLog: text)
    }

    static func localTorrentStartupFailureIsFallbackEligible(logText: String) -> Bool {
        let lowercasedLog = logText.lowercased()
        return lowercasedLog.contains("server returned 5xx")
            || lowercasedLog.contains("503")
            || lowercasedLog.contains("service unavailable")
            || lowercasedLog.contains("startup_buffer_timeout")
            || lowercasedLog.contains("buffer_timeout")
            || lowercasedLog.contains("media_header_unavailable")
    }

    private static func audioOrdinal(from trackId: String?) -> Int? {
        guard let trackId, trackId.hasPrefix("audio:") else { return nil }
        return Int(trackId.dropFirst("audio:".count))
    }

    private static func ffmpegTimeLabel(_ seconds: Double) -> String {
        String(format: "%.3f", max(0, seconds))
    }

    private func shouldRetryTranscodeStartup(after error: Error, logText: String, isLocalTorrentStream: Bool = false) -> Bool {
        guard matchesTranscodeFailure(error, .exitedEarly) else { return false }
        let lowercasedLog = logText.lowercased()
        if isLocalTorrentStream, Self.localTorrentStartupFailureIsFallbackEligible(logText: logText) {
            return false
        }
        return lowercasedLog.contains("503")
            || lowercasedLog.contains("5xx")
            || lowercasedLog.contains("service unavailable")
            || lowercasedLog.contains("stream ends prematurely")
            || lowercasedLog.contains("partial file")
            || lowercasedLog.contains("cannot determine format")
            || lowercasedLog.contains("input/output error")
            || lowercasedLog.contains("operation timed out")
            || lowercasedLog.contains("connection timed out")
            || lowercasedLog.contains("invalid argument")
            || lowercasedLog.contains("nothing was written")
            || lowercasedLog.contains("could not write header")
            || lowercasedLog.contains("error initializing output stream")
            || lowercasedLog.contains("unknown encoder")
            || lowercasedLog.contains("codec")
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
            await waitForProcessExit(transcodeProcess, timeoutSeconds: 0.75)
            if transcodeProcess.isRunning {
                transcodeProcess.interrupt()
                await waitForProcessExit(transcodeProcess, timeoutSeconds: 1.25)
            }
            if transcodeProcess.isRunning {
                kill(transcodeProcess.processIdentifier, SIGKILL)
                await waitForProcessExit(transcodeProcess, timeoutSeconds: 0.75)
            }
        }
        _ = transcodeLogCapture?.stopAndFlush()
        transcodeLogCapture = nil
        transcodeProcess = nil

        hlsServer?.stop()
        hlsServer = nil

        if let transcodeDirectoryURL {
            try? fileManager.removeItem(at: transcodeDirectoryURL)
        }
        transcodeDirectoryURL = nil
    }

    private func waitForProcessExit(_ process: Process, timeoutSeconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(max(0.1, timeoutSeconds))
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func statusPreservingOriginalSource(_ status: PlaybackStatus) async -> PlaybackStatus {
        guard let originalSource else { return status }
        refreshHLSMetadataFromActiveLogIfNeeded()
        let logicalTime = hlsPlaybackBaseTimeSeconds + status.currentTime
        let logicalDuration = hlsSourceDurationSeconds ?? status.duration
        return PlaybackStatus(
            media: originalSource,
            state: status.state,
            currentTime: min(logicalTime, logicalDuration ?? logicalTime),
            duration: logicalDuration,
            bufferingState: status.bufferingState,
            volume: status.volume,
            isMuted: status.isMuted,
            playbackSpeed: status.playbackSpeed,
            audioTracks: hlsAudioTracks.isEmpty ? status.audioTracks : hlsAudioTracks,
            subtitleTracks: hlsSubtitleTracks.isEmpty ? status.subtitleTracks : hlsSubtitleTracks,
            selectedAudioTrackId: selectedAudioTrackId ?? status.selectedAudioTrackId,
            selectedSubtitleTrackId: selectedSubtitleTrackId ?? status.selectedSubtitleTrackId,
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

    private func refreshHLSMetadataFromActiveLogIfNeeded() {
        guard let text = transcodeLogCapture?.text, !text.isEmpty else { return }
        let metadata = Self.mediaMetadata(fromFFmpegLog: text)
        if hlsSourceDurationSeconds == nil {
            hlsSourceDurationSeconds = metadata.durationSeconds
        }
        if hlsAudioTracks.isEmpty, !metadata.audioTracks.isEmpty {
            hlsAudioTracks = metadata.audioTracks
            selectedAudioTrackId = selectedAudioTrackId ?? metadata.audioTracks.first?.id
        }
        if hlsSubtitleTracks.isEmpty, !metadata.subtitleTracks.isEmpty {
            hlsSubtitleTracks = metadata.subtitleTracks
        }
    }

    private static func isExternalSubtitleTrackID(_ id: String) -> Bool {
        id.hasPrefix("local:") || id.hasPrefix("cached:") || id.hasPrefix("opensubtitles:")
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
        let headers = cacheHeaders(for: fileURL)
        if let range = byteRange(from: request, size: body.count) {
            let responseBody = method == "HEAD" ? Data() : body.subdata(in: range)
            return httpResponse(
                status: "206 Partial Content",
                contentType: contentType,
                headers: headers.merging(["Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(body.count)"]) { _, new in new },
                body: responseBody,
                contentLength: range.count
            )
        }

        return httpResponse(
            status: "200 OK",
            contentType: contentType,
            headers: headers,
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

    private func cacheHeaders(for url: URL) -> [String: String] {
        guard url.pathExtension.lowercased() == "m3u8" else { return [:] }
        return [
            "Cache-Control": "no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0"
        ]
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

struct HLSMediaMetadata: Equatable, Sendable {
    let durationSeconds: Double?
    let audioTracks: [AudioTrack]
    let subtitleTracks: [SubtitleTrack]

    static let empty = HLSMediaMetadata(durationSeconds: nil, audioTracks: [], subtitleTracks: [])

    static func parse(ffmpegLog text: String) -> HLSMediaMetadata {
        var durationSeconds: Double?
        var audioTracks: [AudioTrack] = []
        var subtitleTracks: [SubtitleTrack] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if durationSeconds == nil, let duration = parseDuration(from: line) {
                durationSeconds = duration
            }

            guard let stream = parseStream(from: line) else { continue }
            switch stream.kind {
            case "Audio":
                let ordinal = audioTracks.count
                audioTracks.append(
                    AudioTrack(
                        id: "audio:\(ordinal)",
                        languageCode: normalizeLanguage(stream.languageCode),
                        displayName: streamDisplayName(prefix: "Audio", ordinal: ordinal, languageCode: stream.languageCode, codec: stream.codec),
                        codec: stream.codec,
                        channels: stream.channels
                    )
                )
            case "Subtitle":
                let ordinal = subtitleTracks.count
                subtitleTracks.append(
                    SubtitleTrack(
                        id: "subtitle:\(ordinal)",
                        languageCode: normalizeLanguage(stream.languageCode),
                        displayName: streamDisplayName(prefix: "Subtitle", ordinal: ordinal, languageCode: stream.languageCode, codec: stream.codec),
                        source: .embedded
                    )
                )
            default:
                continue
            }
        }

        return HLSMediaMetadata(
            durationSeconds: durationSeconds,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
    }

    private static func parseDuration(from line: String) -> Double? {
        guard let range = line.range(of: "Duration:") else { return nil }
        let tail = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let value = tail.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return (parts[0] * 3_600) + (parts[1] * 60) + parts[2]
    }

    private static func parseStream(from line: String) -> FFmpegStreamInfo? {
        guard line.contains("Stream #0:") else { return nil }
        guard let colon = line.range(of: ": ") else { return nil }
        let header = String(line[..<colon.lowerBound])
        let detail = String(line[colon.upperBound...])
        let kind: String
        if detail.hasPrefix("Audio:") {
            kind = "Audio"
        } else if detail.hasPrefix("Subtitle:") {
            kind = "Subtitle"
        } else {
            return nil
        }

        let languageCode: String? = {
            guard let open = header.lastIndex(of: "("),
                  let close = header.lastIndex(of: ")"),
                  open < close
            else { return nil }
            return String(header[header.index(after: open)..<close])
        }()

        let codecTail = detail.dropFirst("\(kind):".count).trimmingCharacters(in: .whitespaces)
        let codec = codecTail.split(separator: ",", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) }
        let channels = channelLabel(from: codecTail)
        return FFmpegStreamInfo(kind: kind, languageCode: languageCode, codec: codec, channels: channels)
    }

    private static func channelLabel(from text: String) -> String? {
        let lowercased = text.lowercased()
        if lowercased.contains("7.1") || lowercased.contains("8ch") || lowercased.contains("8 ch") {
            return "7.1"
        }
        if lowercased.contains("5.1") || lowercased.contains("6ch") || lowercased.contains("6 ch") {
            return "5.1"
        }
        if lowercased.contains("stereo") || lowercased.contains("2.0") || lowercased.contains("2ch") || lowercased.contains("2 ch") {
            return "Stereo"
        }
        if lowercased.contains("mono") || lowercased.contains("1ch") || lowercased.contains("1 ch") {
            return "Mono"
        }
        return nil
    }

    private static func normalizeLanguage(_ code: String?) -> String {
        switch code?.lowercased() {
        case "rus", "ru":
            "ru"
        case "eng", "en":
            "en"
        case "aze", "az":
            "az"
        case "jpn", "ja":
            "ja"
        case "deu", "ger", "de":
            "de"
        case "fra", "fre", "fr":
            "fr"
        case "spa", "es":
            "es"
        case let code?:
            code
        case nil:
            "und"
        }
    }

    private static func streamDisplayName(prefix: String, ordinal: Int, languageCode: String?, codec: String?) -> String {
        let language = normalizeLanguage(languageCode).uppercased()
        let codecPart = codec.map { " · \($0)" } ?? ""
        return "\(prefix) \(ordinal + 1) · \(language)\(codecPart)"
    }
}

private struct FFmpegStreamInfo {
    let kind: String
    let languageCode: String?
    let codec: String?
    let channels: String?
}

private struct HLSBridgeStartup {
    let playlistURL: URL
    let metadata: HLSMediaMetadata
}

private final class FFmpegLogCapture: @unchecked Sendable {
    private let pipe: Pipe
    private let logURL: URL
    private let lock = NSLock()
    private var data = Data()

    init(pipe: Pipe, logURL: URL) {
        self.pipe = pipe
        self.logURL = logURL
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.append(chunk)
        }
    }

    func stopAndFlush() -> String {
        pipe.fileHandleForReading.readabilityHandler = nil
        let capturedText = self.text
        try? Data(capturedText.utf8).write(to: logURL)
        return capturedText
    }

    private func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }
}

private enum FFmpegHLSVideoMode {
    case copy
    case hardwareH264
    case softwareH264

    var arguments: [String] {
        switch self {
        case .copy:
            [
                "-c:v", "copy"
            ]
        case .hardwareH264:
            [
                "-c:v", "h264_videotoolbox",
                "-b:v", "8000k",
                "-maxrate", "10000k",
                "-bufsize", "16000k",
                "-g", "24",
                "-force_key_frames", "expr:gte(t,n_forced*1)",
                "-allow_sw", "1"
            ]
        case .softwareH264:
            [
                "-c:v", "libx264",
                "-preset", "veryfast",
                "-tune", "zerolatency",
                "-pix_fmt", "yuv420p",
                "-g", "24",
                "-sc_threshold", "0",
                "-force_key_frames", "expr:gte(t,n_forced*1)",
                "-b:v", "8000k",
                "-maxrate", "10000k",
                "-bufsize", "16000k"
            ]
        }
    }
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

    var isStreamlyLocalHLSBridgePlaylistURL: Bool {
        guard requiresLocalHLSBridge else {
            return false
        }
        return lastPathComponent == "stream.m3u8"
    }
}
