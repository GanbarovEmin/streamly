import CineFlowCore
import Foundation

public actor MockPlaybackService: PlaybackServiceProtocol {
    private var legacyState: PlaybackState = .idle
    private var status = PlaybackStatus()

    public init() {}

    public var currentState: PlaybackState {
        get async { legacyState }
    }

    public var currentStatus: PlaybackStatus {
        get async { status }
    }

    public func play(_ source: PlaybackMediaSource) async throws {
        guard source.url.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }

        status = PlaybackStatus(
            media: source,
            state: .playing,
            currentTime: 0,
            duration: 7_200,
            bufferingState: .ready,
            volume: status.volume,
            isMuted: status.isMuted,
            playbackSpeed: status.playbackSpeed,
            audioTracks: Self.mockAudioTracks,
            subtitleTracks: Self.mockSubtitleTracks,
            selectedAudioTrackId: Self.mockAudioTracks.first?.id,
            selectedSubtitleTrackId: Self.mockSubtitleTracks.first?.id,
            isFullscreen: status.isFullscreen,
            qualityLabel: source.qualityLabel,
            sourceName: source.sourceName
        )
        legacyState = source.release.map { .playing($0) } ?? .preparing
    }

    public func play(_ release: TorrentRelease) async throws {
        let source = PlaybackMediaSource(release: release)
        try await play(source)
        legacyState = .playing(release)
    }

    public func pause() async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        status = status.replacing(state: .paused)
        if case .playing(let release) = legacyState {
            legacyState = .paused(release)
        }
    }

    public func resume() async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        status = status.replacing(state: .playing)
        if case .paused(let release) = legacyState {
            legacyState = .playing(release)
        }
    }

    public func stop() async throws {
        status = PlaybackStatus()
        legacyState = .idle
    }

    public func seek(to time: Double) async throws {
        guard status.media != nil else { throw PlaybackServiceError.noMediaLoaded }
        let duration = status.duration ?? time
        status = status.replacing(currentTime: min(max(time, 0), duration))
    }

    public func setVolume(_ volume: Double) async throws {
        status = status.replacing(volume: min(max(volume, 0), 1))
    }

    public func setMuted(_ isMuted: Bool) async throws {
        status = status.replacing(isMuted: isMuted)
    }

    public func setPlaybackSpeed(_ speed: Double) async throws {
        status = status.replacing(playbackSpeed: max(0.25, min(speed, 4)))
    }

    public func selectAudioTrack(id: String?) async throws {
        if let id, !status.audioTracks.contains(where: { $0.id == id }) {
            throw PlaybackServiceError.trackNotFound(id)
        }
        status = status.replacing(selectedAudioTrackId: id)
    }

    public func selectSubtitleTrack(id: String?) async throws {
        if let id, !status.subtitleTracks.contains(where: { $0.id == id }) {
            throw PlaybackServiceError.trackNotFound(id)
        }
        status = status.replacing(selectedSubtitleTrackId: id)
    }

    public func setFullscreen(_ isFullscreen: Bool) async throws {
        status = status.replacing(isFullscreen: isFullscreen)
    }

    public func setPictureInPicture(_ isActive: Bool) async throws {
        status = status.replacing(isPictureInPictureActive: isActive)
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

    private static let mockAudioTracks = [
        AudioTrack(id: "audio-en", languageCode: "en", displayName: "English", codec: "AAC", channels: "5.1"),
        AudioTrack(id: "audio-ru", languageCode: "ru", displayName: "Russian", codec: "AAC", channels: "5.1")
    ]

    private static let mockSubtitleTracks = [
        SubtitleTrack(id: "sub-en", languageCode: "en", displayName: "English", source: .embedded),
        SubtitleTrack(id: "sub-ru", languageCode: "ru", displayName: "Russian", source: .embedded)
    ]
}

private extension PlaybackStatus {
    func replacing(
        state: PlaybackRunState? = nil,
        currentTime: Double? = nil,
        volume: Double? = nil,
        isMuted: Bool? = nil,
        playbackSpeed: Double? = nil,
        selectedAudioTrackId: String? = nil,
        selectedSubtitleTrackId: String? = nil,
        isFullscreen: Bool? = nil,
        isPictureInPictureActive: Bool? = nil
    ) -> PlaybackStatus {
        PlaybackStatus(
            media: media,
            state: state ?? self.state,
            currentTime: currentTime ?? self.currentTime,
            duration: duration,
            bufferingState: bufferingState,
            volume: volume ?? self.volume,
            isMuted: isMuted ?? self.isMuted,
            playbackSpeed: playbackSpeed ?? self.playbackSpeed,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioTrackId: selectedAudioTrackId ?? self.selectedAudioTrackId,
            selectedSubtitleTrackId: selectedSubtitleTrackId ?? self.selectedSubtitleTrackId,
            isFullscreen: isFullscreen ?? self.isFullscreen,
            isPictureInPictureActive: isPictureInPictureActive ?? self.isPictureInPictureActive,
            qualityLabel: qualityLabel,
            sourceName: sourceName
        )
    }
}
