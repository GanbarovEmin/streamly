import AppKit
import CineFlowCore
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

public struct PlaceholderMPVBridge: MPVBridgeProtocol {
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

public actor MPVPlaybackService: PlaybackServiceProtocol {
    public nonisolated let options: MPVPlaybackOptions

    private let bridge: any MPVBridgeProtocol
    private var status = PlaybackStatus()
    private var legacyState: PlaybackState = .idle

    public init(
        bridge: any MPVBridgeProtocol = PlaceholderMPVBridge(),
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
        guard source.url.isFileURL else {
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
