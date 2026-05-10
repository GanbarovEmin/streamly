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
    func selectAudioTrack(id: String?) async throws
    func selectSubtitleTrack(id: String?) async throws
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

    public func selectAudioTrack(id: String?) async throws {
        throw PlaybackServiceError.mpvUnavailable
    }

    public func selectSubtitleTrack(id: String?) async throws {
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
            volume: 1,
            playbackSpeed: 1
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
        playbackStatus = PlaybackStatus(
            state: playbackStatus.state,
            bufferingState: playbackStatus.bufferingState,
            volume: min(max(volume, 0), 1),
            playbackSpeed: playbackStatus.playbackSpeed
        )
    }

    public func setMuted(_ isMuted: Bool) async throws {
        playbackStatus = PlaybackStatus(
            state: playbackStatus.state,
            bufferingState: playbackStatus.bufferingState,
            volume: playbackStatus.volume,
            isMuted: isMuted,
            playbackSpeed: playbackStatus.playbackSpeed
        )
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        playbackStatus = PlaybackStatus(
            state: playbackStatus.state,
            bufferingState: playbackStatus.bufferingState,
            volume: playbackStatus.volume,
            isMuted: playbackStatus.isMuted,
            playbackSpeed: min(max(speed, 0.25), 4)
        )
    }

    public func selectAudioTrack(id: String?) async throws {
        throw PlaybackServiceError.unsupported(operation: "mpv external audio track selection")
    }

    public func selectSubtitleTrack(id: String?) async throws {
        throw PlaybackServiceError.unsupported(operation: "mpv external subtitle track selection")
    }

    public func status() async throws -> PlaybackStatus {
        if let process, !process.isRunning {
            return status(with: .stopped)
        }
        return playbackStatus
    }

    private func launchArguments(for executableURL: URL, mediaURL: URL) -> [String] {
        let media = mediaURL.absoluteString
        if executableURL.lastPathComponent == "iina-cli" {
            return [
                "--keep-running",
                "--no-stdin",
                media,
                "--",
                "--hwdec=\(configuredOptions.hardwareDecoding)",
                "--sid=auto"
            ]
        }

        return [
            media,
            "--force-window=yes",
            "--hwdec=\(configuredOptions.hardwareDecoding)",
            "--sid=auto"
        ]
    }

    private func status(with state: PlaybackRunState) -> PlaybackStatus {
        PlaybackStatus(
            state: state,
            bufferingState: playbackStatus.bufferingState,
            volume: playbackStatus.volume,
            isMuted: playbackStatus.isMuted,
            playbackSpeed: playbackStatus.playbackSpeed
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
        status = PlaybackStatus(media: source, state: .playing)
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

    public func selectAudioTrack(id: String?) async throws {
        try await bridge.selectAudioTrack(id: id)
        status = try await bridge.status()
    }

    public func selectSubtitleTrack(id: String?) async throws {
        try await bridge.selectSubtitleTrack(id: id)
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
            sourceName: status.sourceName
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
