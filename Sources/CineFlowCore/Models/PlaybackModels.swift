import Foundation

public enum PlaybackServiceError: LocalizedError, Equatable, Sendable {
    case unsupported(operation: String)
    case invalidMediaURL
    case noMediaLoaded
    case trackNotFound(String)
    case mpvUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupported(let operation):
            "Playback operation is not supported: \(operation)."
        case .invalidMediaURL:
            "Playback media URL is invalid."
        case .noMediaLoaded:
            "No media is loaded."
        case .trackNotFound(let trackId):
            "Playback track was not found: \(trackId)."
        case .mpvUnavailable:
            "Embedded mpv bridge is not available yet."
        }
    }
}

public enum PlaybackRunState: Codable, Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case failed(reason: String)
}

public enum PlaybackBufferingState: Codable, Equatable, Sendable {
    case idle
    case buffering(progress: Double)
    case ready
}

public enum SubtitleRenderingMode: Codable, Equatable, Sendable {
    case enabled
    case disabled
}

public struct PlaybackMediaSource: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let release: TorrentRelease?
    public let qualityLabel: String?
    public let sourceName: String?

    public init(
        id: String,
        title: String,
        url: URL,
        release: TorrentRelease? = nil,
        qualityLabel: String? = nil,
        sourceName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.release = release
        self.qualityLabel = qualityLabel
        self.sourceName = sourceName
    }

    public init(release: TorrentRelease, url: URL? = nil) {
        self.id = release.id
        self.title = release.title
        self.url = url ?? release.torrentFileURL ?? URL(fileURLWithPath: "/tmp/\(release.id).mkv")
        self.release = release
        self.qualityLabel = release.qualityLabel
        self.sourceName = release.sourceName
    }
}

public extension URL {
    var isCineFlowPlayableMediaURL: Bool {
        guard let scheme = scheme?.lowercased() else { return isFileURL }
        return isFileURL || scheme == "http" || scheme == "https"
    }
}

public struct PlaybackStatus: Codable, Equatable, Sendable {
    public let media: PlaybackMediaSource?
    public let state: PlaybackRunState
    public let currentTime: Double
    public let duration: Double?
    public let bufferingState: PlaybackBufferingState
    public let volume: Double
    public let isMuted: Bool
    public let playbackSpeed: Double
    public let audioTracks: [AudioTrack]
    public let subtitleTracks: [SubtitleTrack]
    public let selectedAudioTrackId: String?
    public let selectedSubtitleTrackId: String?
    public let isFullscreen: Bool
    public let isPictureInPictureActive: Bool
    public let qualityLabel: String?
    public let sourceName: String?

    public init(
        media: PlaybackMediaSource? = nil,
        state: PlaybackRunState = .idle,
        currentTime: Double = 0,
        duration: Double? = nil,
        bufferingState: PlaybackBufferingState = .idle,
        volume: Double = 1,
        isMuted: Bool = false,
        playbackSpeed: Double = 1,
        audioTracks: [AudioTrack] = [],
        subtitleTracks: [SubtitleTrack] = [],
        selectedAudioTrackId: String? = nil,
        selectedSubtitleTrackId: String? = nil,
        isFullscreen: Bool = false,
        isPictureInPictureActive: Bool = false,
        qualityLabel: String? = nil,
        sourceName: String? = nil
    ) {
        self.media = media
        self.state = state
        self.currentTime = currentTime
        self.duration = duration
        self.bufferingState = bufferingState
        self.volume = min(max(volume, 0), 1)
        self.isMuted = isMuted
        self.playbackSpeed = playbackSpeed
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.selectedAudioTrackId = selectedAudioTrackId
        self.selectedSubtitleTrackId = selectedSubtitleTrackId
        self.isFullscreen = isFullscreen
        self.isPictureInPictureActive = isPictureInPictureActive
        self.qualityLabel = qualityLabel ?? media?.qualityLabel
        self.sourceName = sourceName ?? media?.sourceName
    }

    public var progressFraction: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
}

public struct MPVPlaybackOptions: Codable, Equatable, Sendable {
    public let hardwareDecoding: String
    public let videoOutput: String
    public let scalingProfile: String
    public let hdrMode: String
    public let subtitleRendering: SubtitleRenderingMode
    public let preferredAudioLanguage: String?
    public let preferredSubtitleLanguage: String?

    public init(
        hardwareDecoding: String = "videotoolbox-copy",
        videoOutput: String = "libmpv",
        scalingProfile: String = "ewa_lanczossharp",
        hdrMode: String = "auto tone-map when passthrough is unavailable",
        subtitleRendering: SubtitleRenderingMode = .enabled,
        preferredAudioLanguage: String? = nil,
        preferredSubtitleLanguage: String? = nil
    ) {
        self.hardwareDecoding = hardwareDecoding
        self.videoOutput = videoOutput
        self.scalingProfile = scalingProfile
        self.hdrMode = hdrMode
        self.subtitleRendering = subtitleRendering
        self.preferredAudioLanguage = preferredAudioLanguage
        self.preferredSubtitleLanguage = preferredSubtitleLanguage
    }
}

public protocol PlaybackProgressStoreProtocol {
    func saveProgress(_ progress: PlaybackProgress) async throws
}

public protocol PlaybackProgressRepositoryProtocol: PlaybackProgressStoreProtocol {
    func progress(mediaID: String, episodeID: String?) async throws -> PlaybackProgress?
    func continueWatching(includeCompleted: Bool) async throws -> [PlaybackProgress]
    func clearProgress(mediaID: String, episodeID: String?) async throws
}

public protocol WatchHistoryRepositoryProtocol {
    func record(_ progress: PlaybackProgress) async throws
    func entries(limit: Int) async throws -> [WatchHistoryItem]
    func clear() async throws
}
