import AVFoundation
import CineFlowCore
import Foundation

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
            playbackSpeed: 1,
            qualityLabel: source.qualityLabel,
            sourceName: source.sourceName
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

    public func selectAudioTrack(id: String?) async throws {}

    public func selectSubtitleTrack(id: String?) async throws {}

    public func setFullscreen(_ isFullscreen: Bool) async throws {
        status = statusWithPlayerTime(isFullscreen: isFullscreen)
    }

    public func setPictureInPicture(_ isActive: Bool) async throws {
        throw PlaybackServiceError.unsupported(operation: "picture-in-picture")
    }

    public nonisolated func statusUpdates() -> AsyncThrowingStream<PlaybackStatus, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                continuation.yield(await self.currentStatus)
                continuation.finish()
            }
        }
    }

    private func statusWithPlayerTime(
        playbackSpeed: Double? = nil,
        state: PlaybackRunState? = nil,
        isFullscreen: Bool? = nil
    ) -> PlaybackStatus {
        let item = avPlayer.currentItem
        return PlaybackStatus(
            media: status.media,
            state: state ?? status.state,
            currentTime: avPlayer.currentTime().seconds.finiteOrZero,
            duration: Self.duration(from: item) ?? status.duration,
            bufferingState: item == nil ? .idle : .ready,
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
            sourceName: status.sourceName
        )
    }

    private static func duration(from item: AVPlayerItem?) -> Double? {
        guard let item else { return nil }
        let seconds = item.asset.duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}

private extension Double {
    var finiteOrZero: Double {
        isFinite ? self : 0
    }
}
