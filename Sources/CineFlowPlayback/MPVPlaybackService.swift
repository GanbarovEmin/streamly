import AppKit
import CineFlowCore
import Darwin
import Foundation

public protocol MPVBridgeProtocol: Sendable {
    func configure(options: MPVPlaybackOptions) async throws
    func attachRenderView(_ view: NSView) async throws
    func play(url: URL) async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws
    func seek(to time: Double) async throws
    func setVolume(_ volume: Double) async throws
    func setMuted(_ isMuted: Bool) async throws
    func setPlaybackSpeed(_ speed: Double) async throws
    func setAudioBoost(_ boost: Double) async throws
    func selectAudioTrack(id: String?) async throws
    func selectSubtitleTrack(id: String?) async throws
    func setSubtitleDelay(_ seconds: Double) async throws
    func setSubtitleFontSize(_ fontSize: Double) async throws
    func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws
    func status() async throws -> PlaybackStatus
}

public enum MPVRuntimeLocator {
    public static func defaultExecutableURL(fileManager: FileManager = .default) -> URL? {
        let environmentPath = ProcessInfo.processInfo.environment["STREAMLY_MPV_EXECUTABLE"]
        if let environmentPath, fileManager.isExecutableFile(atPath: environmentPath) {
            return URL(fileURLWithPath: environmentPath)
        }

        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("mpv"),
            URL(fileURLWithPath: "/Applications/IINA.app/Contents/MacOS/iina-cli"),
            URL(fileURLWithPath: "/opt/homebrew/bin/mpv"),
            URL(fileURLWithPath: "/usr/local/bin/mpv"),
            URL(fileURLWithPath: "/usr/bin/mpv")
        ]

        return candidates.compactMap { $0 }.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

public struct UnavailableMPVBridge: MPVBridgeProtocol {
    public init() {}

    public func configure(options: MPVPlaybackOptions) async throws {}

    public func attachRenderView(_ view: NSView) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func play(url: URL) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func pause() async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func resume() async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func stop() async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func seek(to time: Double) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setVolume(_ volume: Double) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setMuted(_ isMuted: Bool) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setAudioBoost(_ boost: Double) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func selectAudioTrack(id: String?) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func selectSubtitleTrack(id: String?) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setSubtitleDelay(_ seconds: Double) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setSubtitleFontSize(_ fontSize: Double) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func status() async throws -> PlaybackStatus {
        throw PlaybackServiceError.mpvUnavailable
    }
}

public actor SystemMPVBridge: MPVBridgeProtocol {
    private let executableURL: URL?
    private var process: Process?
    private var configuredOptions = MPVPlaybackOptions()
    private var playbackStatus = PlaybackStatus()

    public init(executableURL: URL? = MPVRuntimeLocator.defaultExecutableURL()) {
        self.executableURL = executableURL
    }

    public func configure(options: MPVPlaybackOptions) async throws {
        configuredOptions = options
    }

    public func attachRenderView(_ view: NSView) async throws {}

    public func play(url: URL) async throws {
        guard let executableURL else {
            throw PlaybackServiceError.mpvUnavailable
        }

        if let process, process.isRunning {
            process.terminate()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = launchArguments(for: executableURL, mediaURL: url)
        process.standardInput = nil
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()

        self.process = process
        playbackStatus = PlaybackStatus(
            state: .playing,
            bufferingState: .ready,
            volume: playbackStatus.volume,
            isMuted: playbackStatus.isMuted,
            playbackSpeed: playbackStatus.playbackSpeed,
            audioBoost: configuredOptions.audioBoost,
            subtitleDelaySeconds: configuredOptions.subtitleDelaySeconds,
            subtitleFontSize: configuredOptions.subtitleFontSize,
            subtitleStyle: configuredOptions.subtitleStyle
        )
    }

    public func pause() async throws {
        guard let process, process.isRunning else {
            throw PlaybackServiceError.noMediaLoaded
        }
        kill(process.processIdentifier, SIGSTOP)
        playbackStatus = status(with: .paused)
    }

    public func resume() async throws {
        guard let process, process.isRunning else {
            throw PlaybackServiceError.noMediaLoaded
        }
        kill(process.processIdentifier, SIGCONT)
        playbackStatus = status(with: .playing)
    }

    public func stop() async throws {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        playbackStatus = PlaybackStatus()
    }

    public func seek(to time: Double) async throws {
        throw PlaybackServiceError.unsupported(operation: "mpv external seek")
    }

    public func setVolume(_ volume: Double) async throws {
        playbackStatus = statusPreservingPlayerState(volume: min(max(volume, 0), 1))
    }

    public func setMuted(_ isMuted: Bool) async throws {
        playbackStatus = statusPreservingPlayerState(isMuted: isMuted)
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        playbackStatus = PlaybackStatus(
            state: playbackStatus.state,
            bufferingState: playbackStatus.bufferingState,
            volume: playbackStatus.volume,
            isMuted: playbackStatus.isMuted,
            playbackSpeed: min(max(speed, 0.25), 4),
            audioBoost: playbackStatus.audioBoost,
            subtitleDelaySeconds: playbackStatus.subtitleDelaySeconds,
            subtitleFontSize: playbackStatus.subtitleFontSize,
            subtitleStyle: playbackStatus.subtitleStyle
        )
    }

    public func setAudioBoost(_ boost: Double) async throws {
        playbackStatus = statusPreservingPlayerState(audioBoost: min(max(boost, 1), 2.5))
    }

    public func selectAudioTrack(id: String?) async throws {
        playbackStatus = statusPreservingPlayerState(selectedAudioTrackId: id)
    }

    public func selectSubtitleTrack(id: String?) async throws {
        playbackStatus = statusPreservingPlayerState(selectedSubtitleTrackId: id)
    }

    public func setSubtitleDelay(_ seconds: Double) async throws {
        playbackStatus = statusPreservingPlayerState(subtitleDelaySeconds: min(max(seconds, -10), 10))
    }

    public func setSubtitleFontSize(_ fontSize: Double) async throws {
        playbackStatus = statusPreservingPlayerState(subtitleFontSize: min(max(fontSize, 24), 72))
    }

    public func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {
        playbackStatus = statusPreservingPlayerState(subtitleStyle: style)
    }

    public func status() async throws -> PlaybackStatus {
        if let process, !process.isRunning {
            return status(with: .stopped)
        }
        return playbackStatus
    }

    private func launchArguments(for executableURL: URL, mediaURL: URL) -> [String] {
        let media = mediaURL.absoluteString
        let videoOutput = configuredOptions.videoOutput == "libmpv" ? "gpu-next" : configuredOptions.videoOutput
        if executableURL.lastPathComponent == "iina-cli" {
            return [
                "--keep-running",
                "--no-stdin",
                media,
                "--",
                "--hwdec=\(configuredOptions.hardwareDecoding)",
                "--vo=\(videoOutput)",
                "--gpu-api=metal",
                "--profile=gpu-hq",
                "--scale=\(configuredOptions.scalingProfile)",
                "--tone-mapping=bt.2446a",
                "--hdr-compute-peak=yes",
                "--alang=\(configuredOptions.preferredAudioLanguage ?? "ru,en")",
                "--slang=\(configuredOptions.preferredSubtitleLanguage ?? "ru,en")",
                "--sid=auto",
                "--sub-auto=fuzzy",
                "--sub-font-size=\(Int(configuredOptions.subtitleFontSize))",
                "--sub-delay=\(configuredOptions.subtitleDelaySeconds)",
                "--sub-pos=\(configuredOptions.subtitlePlacement.mpvSubPosition)",
                "--sub-border-size=\(subtitleBorderSize)",
                "--sub-shadow-offset=\(subtitleShadowOffset)",
                "--sub-shadow-color=0.0/0.0/0.0/0.75",
                "--sub-back-color=\(subtitleBackgroundColor)",
                "--volume-max=250",
                "--volume=\(Int(configuredOptions.audioBoost * 100))"
            ]
        }

        return [
            media,
            "--force-window=yes",
            "--hwdec=\(configuredOptions.hardwareDecoding)",
            "--vo=\(videoOutput)",
            "--gpu-api=metal",
            "--profile=gpu-hq",
            "--scale=\(configuredOptions.scalingProfile)",
            "--tone-mapping=bt.2446a",
            "--hdr-compute-peak=yes",
            "--alang=\(configuredOptions.preferredAudioLanguage ?? "ru,en")",
            "--slang=\(configuredOptions.preferredSubtitleLanguage ?? "ru,en")",
            "--sid=auto",
            "--aid=auto",
            "--sub-auto=fuzzy",
            "--sub-font-size=\(Int(configuredOptions.subtitleFontSize))",
            "--sub-delay=\(configuredOptions.subtitleDelaySeconds)",
            "--sub-pos=\(configuredOptions.subtitlePlacement.mpvSubPosition)",
            "--sub-border-size=\(subtitleBorderSize)",
            "--sub-shadow-offset=\(subtitleShadowOffset)",
            "--sub-shadow-color=0.0/0.0/0.0/0.75",
            "--sub-back-color=\(subtitleBackgroundColor)",
            "--volume-max=250",
            "--volume=\(Int(configuredOptions.audioBoost * 100))"
        ]
    }

    private var subtitleBorderSize: Int {
        switch configuredOptions.subtitleStyle {
        case .system:
            3
        case .highContrast:
            5
        case .cinematic:
            4
        case .compact:
            2
        }
    }

    private var subtitleShadowOffset: Int {
        switch configuredOptions.subtitleStyle {
        case .system:
            1
        case .highContrast:
            2
        case .cinematic:
            1
        case .compact:
            0
        }
    }

    private var subtitleBackgroundColor: String {
        switch configuredOptions.subtitleStyle {
        case .system, .compact:
            "0.0/0.0/0.0/0.0"
        case .highContrast:
            "0.0/0.0/0.0/0.45"
        case .cinematic:
            "0.0/0.0/0.0/0.30"
        }
    }

    private func status(with state: PlaybackRunState) -> PlaybackStatus {
        PlaybackStatus(
            state: state,
            bufferingState: playbackStatus.bufferingState,
            volume: playbackStatus.volume,
            isMuted: playbackStatus.isMuted,
            playbackSpeed: playbackStatus.playbackSpeed,
            audioBoost: playbackStatus.audioBoost,
            subtitleDelaySeconds: playbackStatus.subtitleDelaySeconds,
            subtitleFontSize: playbackStatus.subtitleFontSize,
            subtitleStyle: playbackStatus.subtitleStyle
        )
    }

    private func statusPreservingPlayerState(
        volume: Double? = nil,
        isMuted: Bool? = nil,
        selectedAudioTrackId: String?? = nil,
        selectedSubtitleTrackId: String?? = nil,
        audioBoost: Double? = nil,
        subtitleDelaySeconds: Double? = nil,
        subtitleFontSize: Double? = nil,
        subtitleStyle: SubtitleVisualStyle? = nil
    ) -> PlaybackStatus {
        PlaybackStatus(
            state: playbackStatus.state,
            bufferingState: playbackStatus.bufferingState,
            volume: volume ?? playbackStatus.volume,
            isMuted: isMuted ?? playbackStatus.isMuted,
            playbackSpeed: playbackStatus.playbackSpeed,
            audioTracks: playbackStatus.audioTracks,
            subtitleTracks: playbackStatus.subtitleTracks,
            selectedAudioTrackId: selectedAudioTrackId ?? playbackStatus.selectedAudioTrackId,
            selectedSubtitleTrackId: selectedSubtitleTrackId ?? playbackStatus.selectedSubtitleTrackId,
            isFullscreen: playbackStatus.isFullscreen,
            isPictureInPictureActive: playbackStatus.isPictureInPictureActive,
            qualityLabel: playbackStatus.qualityLabel,
            sourceName: playbackStatus.sourceName,
            chapters: playbackStatus.chapters,
            audioBoost: audioBoost ?? playbackStatus.audioBoost,
            subtitleDelaySeconds: subtitleDelaySeconds ?? playbackStatus.subtitleDelaySeconds,
            subtitleFontSize: subtitleFontSize ?? playbackStatus.subtitleFontSize,
            subtitleStyle: subtitleStyle ?? playbackStatus.subtitleStyle
        )
    }
}

public actor MPVPlaybackService: PlaybackServiceProtocol {
    public nonisolated let options: MPVPlaybackOptions

    private let bridge: any MPVBridgeProtocol
    private var status = PlaybackStatus()
    private var legacyState: PlaybackState = .idle

    public init(
        bridge: any MPVBridgeProtocol = SystemMPVBridge(),
        options: MPVPlaybackOptions = MPVPlaybackOptions(preferredAudioLanguage: "ru", preferredSubtitleLanguage: "ru")
    ) {
        self.bridge = bridge
        self.options = options
    }

    public var currentState: PlaybackState {
        get async { legacyState }
    }

    public var currentStatus: PlaybackStatus {
        get async { status }
    }

    public func attachRenderView(_ view: NSView) async throws {
        try await bridge.configure(options: options)
        try await bridge.attachRenderView(view)
    }

    public func play(_ source: PlaybackMediaSource) async throws {
        guard source.url.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }
        try await bridge.configure(options: options)
        try await bridge.play(url: source.url)
        let bridgeStatus = try await bridge.status()
        status = PlaybackStatus(
            media: source,
            state: bridgeStatus.state,
            currentTime: bridgeStatus.currentTime,
            duration: bridgeStatus.duration,
            bufferingState: bridgeStatus.bufferingState,
            volume: bridgeStatus.volume,
            isMuted: bridgeStatus.isMuted,
            playbackSpeed: bridgeStatus.playbackSpeed,
            audioTracks: bridgeStatus.audioTracks,
            subtitleTracks: bridgeStatus.subtitleTracks,
            selectedAudioTrackId: bridgeStatus.selectedAudioTrackId,
            selectedSubtitleTrackId: bridgeStatus.selectedSubtitleTrackId,
            isFullscreen: bridgeStatus.isFullscreen,
            isPictureInPictureActive: bridgeStatus.isPictureInPictureActive,
            qualityLabel: source.qualityLabel,
            sourceName: source.sourceName,
            chapters: bridgeStatus.chapters,
            audioBoost: bridgeStatus.audioBoost,
            subtitleDelaySeconds: bridgeStatus.subtitleDelaySeconds,
            subtitleFontSize: bridgeStatus.subtitleFontSize,
            subtitleStyle: bridgeStatus.subtitleStyle
        )
        legacyState = source.release.map { .playing($0) } ?? .preparing
    }

    public func play(_ release: TorrentRelease) async throws {
        try await play(PlaybackMediaSource(release: release))
        legacyState = .playing(release)
    }

    public func pause() async throws {
        try await bridge.pause()
        status = try await bridge.status()
    }

    public func resume() async throws {
        try await bridge.resume()
        status = try await bridge.status()
    }

    public func stop() async throws {
        try await bridge.stop()
        status = PlaybackStatus()
        legacyState = .idle
    }

    public func seek(to time: Double) async throws {
        try await bridge.seek(to: time)
        status = try await bridge.status()
    }

    public func setVolume(_ volume: Double) async throws {
        try await bridge.setVolume(volume)
        status = try await bridge.status()
    }

    public func setMuted(_ isMuted: Bool) async throws {
        try await bridge.setMuted(isMuted)
        status = try await bridge.status()
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        try await bridge.setPlaybackSpeed(speed)
        status = try await bridge.status()
    }

    public func setAudioBoost(_ boost: Double) async throws {
        try await bridge.setAudioBoost(boost)
        status = try await bridge.status()
    }

    public func selectAudioTrack(id: String?) async throws {
        try await bridge.selectAudioTrack(id: id)
        status = try await bridge.status()
    }

    public func selectSubtitleTrack(id: String?) async throws {
        try await bridge.selectSubtitleTrack(id: id)
        status = try await bridge.status()
    }

    public func setSubtitleDelay(_ seconds: Double) async throws {
        try await bridge.setSubtitleDelay(seconds)
        status = try await bridge.status()
    }

    public func setSubtitleFontSize(_ fontSize: Double) async throws {
        try await bridge.setSubtitleFontSize(fontSize)
        status = try await bridge.status()
    }

    public func setSubtitleStyle(_ style: SubtitleVisualStyle) async throws {
        try await bridge.setSubtitleStyle(style)
        status = try await bridge.status()
    }

    public func setFullscreen(_ isFullscreen: Bool) async throws {
        status = PlaybackStatus(
            media: status.media,
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
            isFullscreen: isFullscreen,
            isPictureInPictureActive: status.isPictureInPictureActive,
            qualityLabel: status.qualityLabel,
            sourceName: status.sourceName,
            chapters: status.chapters,
            audioBoost: status.audioBoost,
            subtitleDelaySeconds: status.subtitleDelaySeconds,
            subtitleFontSize: status.subtitleFontSize,
            subtitleStyle: status.subtitleStyle
        )
    }

    public func setPictureInPicture(_ isActive: Bool) async throws {
        throw PlaybackServiceError.unsupported(operation: "picture-in-picture")
    }

    public nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let status = await self.currentStatus
                continuation.yield(status)
                continuation.finish()
            }
        }
    }
}
