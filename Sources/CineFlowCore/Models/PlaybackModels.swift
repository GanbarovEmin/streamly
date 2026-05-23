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
    case resolving
    case buffering
    case ready
    case playing
    case paused
    case stalled
    case stopped
    case failed(reason: String)
    case retrying
    case completed

    public static let productionLifecycleStates: [PlaybackRunState] = [
        .idle,
        .loading,
        .resolving,
        .buffering,
        .ready,
        .playing,
        .paused,
        .stalled,
        .failed(reason: "unavailable"),
        .retrying,
        .completed
    ]

    public var isTerminal: Bool {
        switch self {
        case .stopped, .failed, .completed:
            true
        case .idle, .loading, .resolving, .buffering, .ready, .playing, .paused, .stalled, .retrying:
            false
        }
    }
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

public struct PlaybackChapter: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let startTime: Double
    public let endTime: Double?

    public init(id: String, title: String, startTime: Double, endTime: Double? = nil) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Chapter" : title
        self.startTime = max(0, startTime)
        self.endTime = endTime.map { max(startTime, $0) }
    }
}

public struct PlaybackSelectionContext: Codable, Equatable, Hashable, Sendable {
    public let mediaID: String
    public let displayTitle: String
    public let mediaKind: MediaKind
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let episodeID: String?
    public let logoURL: URL?

    public init(
        mediaID: String,
        displayTitle: String,
        mediaKind: MediaKind,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeID: String? = nil,
        logoURL: URL? = nil
    ) {
        self.mediaID = mediaID
        self.displayTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : displayTitle
        self.mediaKind = mediaKind
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeID = episodeID
        self.logoURL = logoURL
    }

    public var episodeLabel: String? {
        guard let seasonNumber, let episodeNumber else { return nil }
        return "S\(seasonNumber)E\(episodeNumber)"
    }
}

public struct PlaybackMediaSource: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let release: TorrentRelease?
    public let qualityLabel: String?
    public let sourceName: String?
    public let selectionContext: PlaybackSelectionContext?

    public init(
        id: String,
        title: String,
        url: URL,
        release: TorrentRelease? = nil,
        qualityLabel: String? = nil,
        sourceName: String? = nil,
        selectionContext: PlaybackSelectionContext? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.release = release
        self.qualityLabel = qualityLabel
        self.sourceName = sourceName
        self.selectionContext = selectionContext
    }

    public init(release: TorrentRelease, url: URL? = nil, selectionContext: PlaybackSelectionContext? = nil) {
        self.id = selectionContext?.episodeID ?? selectionContext?.mediaID ?? release.id
        self.title = selectionContext?.displayTitle ?? release.title
        self.url = url ?? release.torrentFileURL ?? URL(fileURLWithPath: "/tmp/\(release.id).mkv")
        self.release = release
        self.qualityLabel = release.qualityLabel
        self.sourceName = release.sourceName
        self.selectionContext = selectionContext
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
    public let chapters: [PlaybackChapter]
    public let audioBoost: Double
    public let subtitleDelaySeconds: Double
    public let subtitleFontSize: Double
    public let subtitleStyle: SubtitleVisualStyle

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
        sourceName: String? = nil,
        chapters: [PlaybackChapter] = [],
        audioBoost: Double = 1,
        subtitleDelaySeconds: Double = 0,
        subtitleFontSize: Double = 42,
        subtitleStyle: SubtitleVisualStyle = .system
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
        self.chapters = chapters.sorted { $0.startTime < $1.startTime }
        self.audioBoost = min(max(audioBoost, 1), 2.5)
        self.subtitleDelaySeconds = min(max(subtitleDelaySeconds, -10), 10)
        self.subtitleFontSize = min(max(subtitleFontSize, 24), 72)
        self.subtitleStyle = subtitleStyle
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
    public let subtitleFontSize: Double
    public let subtitleDelaySeconds: Double
    public let subtitleStyle: SubtitleVisualStyle
    public let subtitlePlacement: SubtitlePlacement
    public let audioBoost: Double

    public init(
        hardwareDecoding: String = "videotoolbox",
        videoOutput: String = "libmpv",
        scalingProfile: String = "ewa_lanczossharp",
        hdrMode: String = "auto",
        subtitleRendering: SubtitleRenderingMode = .enabled,
        preferredAudioLanguage: String? = nil,
        preferredSubtitleLanguage: String? = nil,
        subtitleFontSize: Double = 42,
        subtitleDelaySeconds: Double = 0,
        subtitleStyle: SubtitleVisualStyle = .system,
        subtitlePlacement: SubtitlePlacement = .standard,
        audioBoost: Double = 1
    ) {
        self.hardwareDecoding = hardwareDecoding
        self.videoOutput = videoOutput
        self.scalingProfile = scalingProfile
        self.hdrMode = hdrMode
        self.subtitleRendering = subtitleRendering
        self.preferredAudioLanguage = preferredAudioLanguage
        self.preferredSubtitleLanguage = preferredSubtitleLanguage
        self.subtitleFontSize = min(max(subtitleFontSize, 24), 72)
        self.subtitleDelaySeconds = min(max(subtitleDelaySeconds, -10), 10)
        self.subtitleStyle = subtitleStyle
        self.subtitlePlacement = subtitlePlacement
        self.audioBoost = min(max(audioBoost, 1), 2.5)
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
