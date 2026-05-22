import CineFlowCore
import CineFlowPlayback
import AVFoundation
import Foundation

public struct PlayerResumePrompt: Equatable, Sendable {
    public let positionSeconds: Double
    public let positionLabel: String

    public init(positionSeconds: Double, positionLabel: String) {
        self.positionSeconds = positionSeconds
        self.positionLabel = positionLabel
    }
}

public struct PlayerNextEpisodeAction: Hashable, Sendable {
    public let mediaID: String
    public let sourceID: String?
    public let release: TorrentRelease?
    public let fallbackReleases: [TorrentRelease]
    public let selectionContext: PlaybackSelectionContext?
    public let requiresManualReleaseSelection: Bool

    public init(
        mediaID: String,
        sourceID: String? = nil,
        release: TorrentRelease? = nil,
        fallbackReleases: [TorrentRelease] = [],
        selectionContext: PlaybackSelectionContext? = nil,
        requiresManualReleaseSelection: Bool = false
    ) {
        self.mediaID = mediaID
        self.sourceID = sourceID
        self.release = release
        self.fallbackReleases = fallbackReleases
        self.selectionContext = selectionContext
        self.requiresManualReleaseSelection = requiresManualReleaseSelection
    }
}

public struct PlayerNextEpisodePrompt: Hashable, Sendable {
    public let title: String
    public let subtitle: String
    public let actionTitle: String
    public let cancelTitle: String
    public let nextEpisodeAction: PlayerNextEpisodeAction?

    public init(
        title: String,
        subtitle: String,
        actionTitle: String = "Watch Now",
        cancelTitle: String = "Cancel",
        nextEpisodeAction: PlayerNextEpisodeAction? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.cancelTitle = cancelTitle
        self.nextEpisodeAction = nextEpisodeAction
    }

    public var requiresManualReleaseSelection: Bool {
        nextEpisodeAction?.requiresManualReleaseSelection == true
    }
}

public struct PlayerBufferingPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let progress: Double?
    public let primaryDetails: [String]
    public let advancedDetails: [String]

    public init(
        title: String,
        message: String,
        progress: Double? = nil,
        primaryDetails: [String] = [],
        advancedDetails: [String] = []
    ) {
        self.title = title
        self.message = message
        self.progress = progress
        self.primaryDetails = primaryDetails
        self.advancedDetails = advancedDetails
    }
}

public struct TimelinePreviewPresentation: Equatable, Sendable {
    public let timeSeconds: Double
    public let timeLabel: String
    public let imageData: Data?
    public let isLoading: Bool
    public let isUnavailable: Bool
    public let message: String

    public init(
        timeSeconds: Double = 0,
        timeLabel: String = "",
        imageData: Data? = nil,
        isLoading: Bool = false,
        isUnavailable: Bool = false,
        message: String = ""
    ) {
        self.timeSeconds = max(0, timeSeconds)
        self.timeLabel = timeLabel
        self.imageData = imageData
        self.isLoading = isLoading
        self.isUnavailable = isUnavailable
        self.message = message
    }

    public static let hidden = TimelinePreviewPresentation()

    public var isHidden: Bool {
        timeLabel.isEmpty && imageData == nil && !isLoading && !isUnavailable
    }
}

private struct PlayerSubtitleCue: Equatable, Sendable {
    let startTime: Double
    let endTime: Double
    let text: String
}

public struct AudioMenuTrack: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let languageLabel: String
    public let qualityLabel: String
    public let isOriginal: Bool
    public let isSelected: Bool

    public init(track: AudioTrack, isSelected: Bool) {
        id = track.id
        title = track.displayName
        languageLabel = Self.languageLabel(for: track)
        qualityLabel = track.qualityLabel
        isOriginal = track.isOriginal
        self.isSelected = isSelected
    }

    private static func languageLabel(for track: AudioTrack) -> String {
        if track.isOriginal {
            return "Original"
        }
        switch track.languageCode.lowercased() {
        case "ru", "rus":
            return "Russian"
        case "en", "eng":
            return "English"
        default:
            return track.languageCode.uppercased()
        }
    }
}

public enum PlayerKeyboardShortcut: Equatable, Sendable {
    case space
    case left
    case right
    case shiftLeft
    case shiftRight
    case up
    case down
    case mute
    case fullscreen
    case subtitles
    case audio
    case speedDown
    case speedUp
    case subtitleDelayDown
    case subtitleDelayUp
    case audioBoostDown
    case audioBoostUp
    case escape
}

@MainActor
public final class PlayerViewModel: ObservableObject {
    static let startupPlayableBufferTargetBytes: Int64 = 4 * 1024 * 1024

    @Published public private(set) var status: PlaybackStatus
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var controlsAreVisible = true
    @Published public private(set) var onlineSubtitleResults: [SubtitleSearchResult] = []
    @Published private var loadedSubtitleTracks: [SubtitleTrack] = []
    @Published public private(set) var resumeProgress: PlaybackProgress?
    @Published public private(set) var resumePrompt: PlayerResumePrompt?
    @Published public private(set) var nextEpisodePrompt: PlayerNextEpisodePrompt?
    @Published public private(set) var fallbackSuggestion: ReleaseFallbackSuggestion?
    @Published public private(set) var advancedDebugVisible = false
    @Published public private(set) var appSettings = AppSettings()
    @Published public private(set) var subtitleSettings = SubtitleSettings()
    @Published public private(set) var audioSelectionSummary = "Audio: Auto"
    @Published public private(set) var timelinePreview = TimelinePreviewPresentation.hidden
    @Published public private(set) var nextEpisodeCountdownSeconds: Int?
    @Published public private(set) var torrentStatus: TorrentStatus?
    @Published public private(set) var activeSubtitleText: String?

    private let service: any PlaybackServiceProtocol
    private let mediaSource: PlaybackMediaSource
    private let torrentEngine: (any TorrentEngineProtocol)?
    private let torrentSession: TorrentSession?
    private let subtitleService: (any SubtitleServiceProtocol)?
    private let timelinePreviewService: (any TimelinePreviewServiceProtocol)?
    private let settingsRepository: (any SettingsRepositoryProtocol)?
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let progressRecorder: PlaybackProgressRecorder?
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private let fallbackReleases: [TorrentRelease]
    private let fallbackPreferences: RankingPreferences
    private let fallbackHandler: ((TorrentRelease) async -> Void)?
    private let configuredNextEpisodePrompt: PlayerNextEpisodePrompt?
    private let debugLogger: PlaybackDebugLogger
    private var statusTask: Task<Void, Never>?
    private var torrentStatusTask: Task<Void, Never>?
    private var controlsHideTask: Task<Void, Never>?
    private var timelinePreviewTask: Task<Void, Never>?
    private var nextEpisodeCountdownTask: Task<Void, Never>?
    private var lastTimelinePreviewBucket: Double?
    private var automaticallyTriedFallbackReleaseIDs = Set<String>()
    private var subtitleCueCache: [String: [PlayerSubtitleCue]] = [:]

    public init(
        service: any PlaybackServiceProtocol,
        mediaSource: PlaybackMediaSource,
        torrentEngine: (any TorrentEngineProtocol)? = nil,
        torrentSession: TorrentSession? = nil,
        subtitleService: (any SubtitleServiceProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        timelinePreviewService: (any TimelinePreviewServiceProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        progressRecorder: PlaybackProgressRecorder? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        fallbackReleases: [TorrentRelease] = [],
        fallbackPreferences: RankingPreferences = RankingPreferences(),
        fallbackHandler: ((TorrentRelease) async -> Void)? = nil,
        nextEpisodePrompt: PlayerNextEpisodePrompt? = nil,
        debugLogger: PlaybackDebugLogger = PlaybackDebugLogger()
    ) {
        self.service = service
        self.mediaSource = mediaSource
        self.torrentEngine = torrentEngine
        self.torrentSession = torrentSession
        self.subtitleService = subtitleService
        self.timelinePreviewService = timelinePreviewService
        self.settingsRepository = settingsRepository
        self.diagnosticsService = diagnosticsService
        self.progressRecorder = progressRecorder
        self.progressRepository = progressRepository
        self.fallbackReleases = fallbackReleases
        self.fallbackPreferences = fallbackPreferences
        self.fallbackHandler = fallbackHandler
        self.configuredNextEpisodePrompt = nextEpisodePrompt
        self.debugLogger = debugLogger
        self.status = PlaybackStatus(media: mediaSource, state: .idle)
        self.fallbackSuggestion = mediaSource.release.flatMap {
            ReleaseFallbackPlanner.seedWarning(for: $0, in: fallbackReleases, preferences: fallbackPreferences)
        }
    }

    deinit {
        statusTask?.cancel()
        torrentStatusTask?.cancel()
        controlsHideTask?.cancel()
        timelinePreviewTask?.cancel()
        nextEpisodeCountdownTask?.cancel()
    }

    public var audioTracks: [AudioTrack] {
        status.audioTracks
    }

    public var audioMenuTracks: [AudioMenuTrack] {
        sortAudioCandidates(status.audioTracks).map {
            AudioMenuTrack(track: $0, isSelected: $0.id == status.selectedAudioTrackId)
        }
    }

    public var subtitleTracks: [SubtitleTrack] {
        status.subtitleTracks + loadedSubtitleTracks
    }

    public var embeddedSubtitleTracks: [SubtitleTrack] {
        subtitleTracks.filter { $0.source == .embedded }
    }

    public var localSubtitleTracks: [SubtitleTrack] {
        subtitleTracks.filter { $0.source == .localFile }
    }

    public var onlineSubtitleTracks: [SubtitleTrack] {
        subtitleTracks.filter { $0.source == .openSubtitles }
    }

    public var chapters: [PlaybackChapter] {
        status.chapters
    }

    public var speedChoices: [Double] {
        [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    }

    public var dimBackgroundAroundVideo: Bool {
        appSettings.playback.dimBackgroundAroundVideo
    }

    public var timelinePreviewsEnabled: Bool {
        appSettings.playback.enableTimelinePreviews
    }

    public var elapsedLabel: String {
        Self.timeLabel(status.currentTime)
    }

    public var durationLabel: String {
        status.duration.map(Self.timeLabel) ?? "--:--"
    }

    public var shouldOfferResume: Bool {
        resumePrompt != nil
    }

    public var shouldOfferNextEpisode: Bool {
        nextEpisodePrompt != nil
    }

    public var bufferingPresentation: PlayerBufferingPresentation {
        switch status.bufferingState {
        case .idle, .ready:
            return PlayerBufferingPresentation(title: "", message: "")
        case .buffering(let progress):
            let transfer = torrentBufferingDetails(playbackProgress: progress)
            var details: [String] = []
            if advancedDebugVisible, let release = status.media?.release ?? mediaSource.release {
                details.append("Seeders: \(release.seeders)")
                if let torrentStatus {
                    details.append("Peers: \(torrentStatus.health.connectedPeers)")
                    if let selectedFileId = torrentStatus.selectedFileId {
                        details.append("Selected file: \(selectedFileId)")
                    }
                }
                details.append("Source health: \(release.releaseHealth.label)")
                details.append("Health: \(release.releaseHealth.label)")
                details.append("Source: \(release.sourceName)")
            }
            return PlayerBufferingPresentation(
                title: "Buffering",
                message: transfer.message,
                progress: transfer.progress,
                primaryDetails: transfer.primaryDetails,
                advancedDetails: details
            )
        }
    }

    private func torrentBufferingDetails(playbackProgress: Double) -> (message: String, progress: Double?, primaryDetails: [String]) {
        guard let torrentStatus else {
            let percent = Int(playbackProgress * 100)
            return ("Preparing stream · \(percent)%", playbackProgress, [])
        }

        let torrentProgress = torrentStatus.progress
        let downloadProgress = torrentProgress.totalBytes > 0 ? torrentProgress.progressFraction : nil
        let playableBytes = max(0, torrentProgress.bufferedBytes)
        let playableProgress = min(Double(playableBytes) / Double(Self.startupPlayableBufferTargetBytes), 1)
        let playablePercent = Int(playableProgress * 100)
        let downloadPercent = downloadProgress.map { Int($0 * 100) }
        var primaryDetails: [String] = []

        if torrentProgress.downloadSpeedBytesPerSecond > 0 {
            primaryDetails.append("Download speed: \(Self.byteRateLabel(torrentProgress.downloadSpeedBytesPerSecond))")
        } else {
            primaryDetails.append("Download speed: Connecting to peers...")
        }

        if torrentProgress.totalBytes > 0 {
            primaryDetails.append(
                "Loaded: \(Self.byteCountLabel(torrentProgress.downloadedBytes)) / \(Self.byteCountLabel(torrentProgress.totalBytes)) (\(downloadPercent ?? 0)%)"
            )
        } else {
            primaryDetails.append("Loaded: \(Self.byteCountLabel(torrentProgress.downloadedBytes))")
        }

        primaryDetails.append(
            "Playable start buffer: \(Self.byteCountLabel(playableBytes)) / \(Self.byteCountLabel(Self.startupPlayableBufferTargetBytes))"
        )

        if torrentProgress.totalBytes > torrentProgress.downloadedBytes,
           torrentProgress.downloadSpeedBytesPerSecond > 0 {
            let remainingBytes = torrentProgress.totalBytes - torrentProgress.downloadedBytes
            let seconds = Double(remainingBytes) / Double(torrentProgress.downloadSpeedBytesPerSecond)
            primaryDetails.append("Full file ETA: \(Self.durationLabel(seconds))")
        } else if torrentProgress.totalBytes > 0 && torrentProgress.downloadedBytes >= torrentProgress.totalBytes {
            primaryDetails.append("Full file ETA: Ready")
        } else {
            primaryDetails.append("Full file ETA: Waiting for speed")
        }

        let message: String
        if playableProgress >= 1 {
            message = "Starting player"
        } else if playableBytes > 0 {
            message = "Preparing playable buffer · \(playablePercent)%"
        } else {
            message = "Waiting for playable pieces"
        }

        return (message, playableProgress, primaryDetails)
    }

    public var avPlayer: AVPlayer? {
        (service as? AVPlayerProviding)?.avPlayer
    }

    public func start() async {
        await loadPlayerPreferences()
        status = PlaybackStatus(media: mediaSource, state: .loading, bufferingState: .buffering(progress: 0))
        startTorrentStatusUpdates()
        do {
            self.resumeProgress = try await self.progressRepository?.progress(
                mediaID: self.mediaSource.selectionContext?.mediaID ?? self.mediaSource.id,
                episodeID: self.mediaSource.selectionContext?.episodeID
            )
            try await self.service.play(self.mediaSource)
            await self.applyRememberedPreferences()
            if let resumeProgress = self.resumeProgress, resumeProgress.positionSeconds > 5, !resumeProgress.completed {
                self.resumePrompt = PlayerResumePrompt(
                    positionSeconds: resumeProgress.positionSeconds,
                    positionLabel: Self.timeLabel(resumeProgress.positionSeconds)
                )
            }
            await self.refreshStatus()
            self.startStatusUpdates()
        } catch {
            await handlePlaybackFailure(
                error,
                subsystem: .playback,
                operation: "playbackOperation",
                allowAutomaticFallback: true
            )
        }
    }

    public func continueFromResume() async {
        guard let resumePrompt else { return }
        self.resumePrompt = nil
        await seek(to: resumePrompt.positionSeconds)
    }

    public func startOverFromBeginning() async {
        resumePrompt = nil
        await seek(to: 0)
    }

    public func togglePlayPause() async {
        await perform {
            switch self.status.state {
            case .playing:
                try await self.service.pause()
            case .paused, .idle, .ready, .stopped, .completed:
                if self.status.media == nil || self.status.state == .idle {
                    try await self.service.play(self.mediaSource)
                } else {
                    try await self.service.resume()
                }
            case .loading, .resolving, .buffering, .stalled, .retrying, .failed:
                break
            }
            await self.refreshStatus()
        }
    }

    public func seekForward() async {
        await seek(by: 10)
    }

    public func seekForwardLarge() async {
        await seek(by: 60)
    }

    public func seekBackward() async {
        await seek(by: -10)
    }

    public func seekBackwardLarge() async {
        await seek(by: -60)
    }

    public func seek(to time: Double) async {
        await perform {
            try await self.service.seek(to: time)
            await self.refreshStatus()
        }
    }

    public func volumeUp() async {
        await setVolume(status.volume + 0.1)
    }

    public func volumeDown() async {
        await setVolume(status.volume - 0.1)
    }

    public func setVolume(_ volume: Double) async {
        await perform {
            try await self.service.setVolume(volume)
            await self.refreshStatus()
            await self.updatePlaybackSettings { $0.rememberedVolume = self.status.volume }
        }
    }

    public func toggleMuted() async {
        await perform {
            try await self.service.setMuted(!self.status.isMuted)
            await self.refreshStatus()
        }
    }

    public func setPlaybackSpeed(_ speed: Double) async {
        await perform {
            try await self.service.setPlaybackSpeed(speed)
            await self.refreshStatus()
            await self.updatePlaybackSettings { $0.playbackSpeed = self.status.playbackSpeed }
        }
    }

    public func increasePlaybackSpeed() async {
        let next = speedChoices.first { $0 > status.playbackSpeed + 0.001 } ?? speedChoices.last ?? 1
        await setPlaybackSpeed(next)
    }

    public func decreasePlaybackSpeed() async {
        let previous = speedChoices.reversed().first { $0 < status.playbackSpeed - 0.001 } ?? speedChoices.first ?? 1
        await setPlaybackSpeed(previous)
    }

    public func setAudioBoost(_ boost: Double) async {
        await perform {
            try await self.service.setAudioBoost(boost)
            await self.refreshStatus()
            await self.updatePlaybackSettings { $0.audioBoost = self.status.audioBoost }
        }
    }

    public func increaseAudioBoost() async {
        await setAudioBoost(status.audioBoost + 0.25)
    }

    public func decreaseAudioBoost() async {
        await setAudioBoost(status.audioBoost - 0.25)
    }

    public func selectAudioTrack(id: String?) async {
        await perform {
            try await self.service.selectAudioTrack(id: id)
            await self.refreshStatus()
            await self.rememberAudioSelection(id: id)
        }
    }

    public func selectSubtitleTrack(id: String?) async {
        await perform {
            try await self.service.selectSubtitleTrack(id: id)
            await self.refreshStatus()
            await self.prepareSubtitleCuesForSelectedTrack()
            self.updateActiveSubtitleText(for: self.status)
            await self.rememberSubtitleSelection(id: id)
        }
    }

    public func findOnlineSubtitles() async {
        guard let subtitleService else { return }
        do {
            let query = self.subtitleSearchQuery()
            self.onlineSubtitleResults = try await subtitleService.searchOnlineSubtitles(
                query: query,
                languages: self.subtitleSettings.languagePreference.languageCodes
            )
        } catch {
            onlineSubtitleResults = []
            await logError(error, subsystem: .subtitle, operation: "findOnlineSubtitles")
        }
    }

    public func downloadSubtitle(_ result: SubtitleSearchResult) async {
        guard let subtitleService else { return }
        do {
            let track = try await subtitleService.downloadSubtitle(result)
            self.loadedSubtitleTracks.append(track)
            try? await self.service.selectSubtitleTrack(id: track.id)
            await self.refreshStatusPreservingLoadedSubtitleSelection(track.id)
            await self.prepareSubtitleCues(for: track)
            self.updateActiveSubtitleText(for: self.status)
            await self.rememberSubtitleSelection(id: track.id)
        } catch {
            await logError(error, subsystem: .subtitle, operation: "downloadSubtitle")
        }
    }

    public func reloadLocalSubtitles() async {
        guard let subtitleService else { return }
        do {
            let local = try await subtitleService.localSubtitles(for: subtitleSearchQuery(), directory: nil)
            appendLoadedSubtitleTracks(local)
        } catch {
            await logError(error, subsystem: .subtitle, operation: "reloadLocalSubtitles")
        }
    }

    public func loadLocalSubtitle(url: URL) async {
        guard ["srt", "ass"].contains(url.pathExtension.lowercased()) else {
            let error = SubtitleServiceError.invalidSubtitleFile(url)
            errorMessage = error.cineFlowError.userMessage
            await logError(error, subsystem: .subtitle, operation: "loadLocalSubtitle")
            return
        }
        let track = SubtitleTrack(
            id: "local:\(url.path)",
            languageCode: Self.languageCode(from: url) ?? "und",
            displayName: url.lastPathComponent,
            source: .localFile,
            localURL: url
        )
        loadedSubtitleTracks.append(track)
        try? await service.selectSubtitleTrack(id: track.id)
        await refreshStatusPreservingLoadedSubtitleSelection(track.id)
        await prepareSubtitleCues(for: track)
        updateActiveSubtitleText(for: status)
        await rememberSubtitleSelection(id: track.id)
    }

    public func disableSubtitles() async {
        await perform {
            try await self.service.selectSubtitleTrack(id: nil)
            await self.refreshStatusPreservingLoadedSubtitleSelection(nil)
            self.activeSubtitleText = nil
            await self.updatePlaybackSettings {
                $0.subtitlesEnabled = false
                $0.rememberedSubtitleLanguage = nil
            }
            await self.rememberSubtitleSelection(id: nil)
        }
    }

    public func toggleFullscreen() async {
        await perform {
            try await self.service.setFullscreen(!self.status.isFullscreen)
            await self.refreshStatus()
            await self.updatePlaybackSettings { $0.defaultFullscreen = self.status.isFullscreen }
        }
    }

    public func seekToChapter(_ chapter: PlaybackChapter) async {
        await seek(to: chapter.startTime)
    }

    public func setSubtitleDelay(_ seconds: Double) async {
        await perform(subsystem: .subtitle, operation: "setSubtitleDelay") {
            try await self.service.setSubtitleDelay(seconds)
            await self.refreshStatus()
            self.subtitleSettings.subtitleDelaySeconds = min(max(seconds, -10), 10)
            await self.settingsRepository?.setSubtitleSettings(self.subtitleSettings)
        }
    }

    public func adjustSubtitleDelay(by delta: Double) async {
        await setSubtitleDelay(status.subtitleDelaySeconds + delta)
    }

    public func resetSubtitleDelay() async {
        await setSubtitleDelay(0)
    }

    public func setSubtitleFontSize(_ fontSize: Double) async {
        await perform(subsystem: .subtitle, operation: "setSubtitleFontSize") {
            try await self.service.setSubtitleFontSize(fontSize)
            await self.refreshStatus()
            self.subtitleSettings.fontSize = min(max(fontSize, 24), 72)
            await self.settingsRepository?.setSubtitleSettings(self.subtitleSettings)
        }
    }

    public func setSubtitleStyle(_ style: SubtitleVisualStyle) async {
        await perform(subsystem: .subtitle, operation: "setSubtitleStyle") {
            try await self.service.setSubtitleStyle(style)
            await self.refreshStatus()
            self.subtitleSettings.visualStyle = style
            await self.settingsRepository?.setSubtitleSettings(self.subtitleSettings)
        }
    }

    public func toggleDimBackground() async {
        await updatePlaybackSettings { $0.dimBackgroundAroundVideo.toggle() }
    }

    public func setAdvancedDebugVisible(_ visible: Bool) {
        advancedDebugVisible = visible
    }

    public func handleShortcut(_ shortcut: PlayerKeyboardShortcut) async {
        showControlsTemporarily()
        switch shortcut {
        case .space:
            await togglePlayPause()
        case .left:
            await seekBackward()
        case .right:
            await seekForward()
        case .shiftLeft:
            await seekBackwardLarge()
        case .shiftRight:
            await seekForwardLarge()
        case .up:
            await volumeUp()
        case .down:
            await volumeDown()
        case .mute:
            await toggleMuted()
        case .fullscreen:
            await toggleFullscreen()
        case .speedDown:
            await decreasePlaybackSpeed()
        case .speedUp:
            await increasePlaybackSpeed()
        case .subtitleDelayDown:
            await adjustSubtitleDelay(by: -0.5)
        case .subtitleDelayUp:
            await adjustSubtitleDelay(by: 0.5)
        case .audioBoostDown:
            await decreaseAudioBoost()
        case .audioBoostUp:
            await increaseAudioBoost()
        case .subtitles, .audio, .escape:
            showControls()
        }
    }

    public func stop() async {
        torrentStatusTask?.cancel()
        await perform {
            try await self.progressRecorder?.recordIfNeeded(status: self.status, force: true)
            try await self.service.stop()
            await self.refreshStatus()
        }
    }

    public func tryNextBestRelease() async {
        guard let release = fallbackSuggestion?.nextBestRelease?.release else { return }
        if let fallbackHandler {
            await fallbackHandler(release)
            return
        }

        await perform(operation: "player.fallback.tryNext") {
            try await self.service.play(PlaybackMediaSource(release: release))
            await self.refreshStatus()
            self.fallbackSuggestion = nil
        }
    }

    public func saveProgressOnClose() async {
        try? await progressRecorder?.recordIfNeeded(status: status, force: true)
    }

    public func hideControls() {
        controlsAreVisible = false
    }

    public func showControls() {
        controlsHideTask?.cancel()
        controlsAreVisible = true
    }

    public func showControlsTemporarily(autoHideAfter delay: TimeInterval = 2.4) {
        controlsHideTask?.cancel()
        controlsAreVisible = true
        controlsHideTask = Task { [weak self] in
            guard delay > 0 else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.controlsAreVisible = false
            }
        }
    }

    public func requestTimelinePreview(at timeSeconds: Double) {
        guard timelinePreviewsEnabled else {
            hideTimelinePreview()
            return
        }
        let clamped = clampedTimelinePreviewTime(timeSeconds)
        let bucket = floor(clamped / 10) * 10
        if lastTimelinePreviewBucket == bucket,
           !timelinePreview.isHidden,
           !timelinePreview.isUnavailable {
            return
        }
        lastTimelinePreviewBucket = bucket
        timelinePreviewTask?.cancel()
        timelinePreviewTask = Task(priority: .utility) { [weak self] in
            await self?.loadTimelinePreview(at: clamped)
        }
    }

    public func loadTimelinePreview(at timeSeconds: Double) async {
        guard timelinePreviewsEnabled else {
            timelinePreview = .hidden
            return
        }
        let clamped = clampedTimelinePreviewTime(timeSeconds)
        let label = Self.timeLabel(clamped)
        guard let service = timelinePreviewService else {
            timelinePreview = TimelinePreviewPresentation(
                timeSeconds: clamped,
                timeLabel: label,
                isUnavailable: true,
                message: "Preview unavailable"
            )
            return
        }
        guard let request = timelinePreviewRequest(timeSeconds: clamped), request.isTimeAvailable else {
            timelinePreview = TimelinePreviewPresentation(
                timeSeconds: clamped,
                timeLabel: label,
                isUnavailable: true,
                message: "Preview unavailable"
            )
            return
        }

        timelinePreview = TimelinePreviewPresentation(timeSeconds: clamped, timeLabel: label, isLoading: true, message: "Generating preview")
        do {
            guard let preview = try await service.preview(for: request) else {
                timelinePreview = TimelinePreviewPresentation(
                    timeSeconds: clamped,
                    timeLabel: label,
                    isUnavailable: true,
                    message: "Preview unavailable"
                )
                return
            }
            timelinePreview = TimelinePreviewPresentation(
                timeSeconds: clamped,
                timeLabel: label,
                imageData: preview.imageData
            )
        } catch {
            timelinePreview = TimelinePreviewPresentation(
                timeSeconds: clamped,
                timeLabel: label,
                isUnavailable: true,
                message: "Preview unavailable"
            )
            await logError(error, subsystem: .playback, operation: "timelinePreview")
        }
    }

    public func hideTimelinePreview() {
        timelinePreviewTask?.cancel()
        lastTimelinePreviewBucket = nil
        timelinePreview = .hidden
    }

    public func dismissNextEpisodePrompt() {
        cancelNextEpisodeCountdown()
    }

    public func cancelNextEpisodeCountdown() {
        nextEpisodeCountdownTask?.cancel()
        nextEpisodeCountdownTask = nil
        nextEpisodeCountdownSeconds = nil
        nextEpisodePrompt = nil
    }

    private func seek(by delta: Double) async {
        await seek(to: status.currentTime + delta)
    }

    private func clampedTimelinePreviewTime(_ timeSeconds: Double) -> Double {
        guard let duration = status.duration, duration > 0 else { return max(0, timeSeconds) }
        return min(max(0, timeSeconds), duration)
    }

    private func timelinePreviewRequest(timeSeconds: Double) -> TimelinePreviewRequest? {
        let media = status.media ?? mediaSource
        let bufferedUntil = timelinePreviewBufferedUntilSeconds(for: media)
        return TimelinePreviewRequest(
            mediaID: media.id,
            mediaURL: media.url,
            timeSeconds: timeSeconds,
            durationSeconds: status.duration,
            bufferedUntilSeconds: bufferedUntil,
            isPlaybackActive: status.state == .playing || status.state == .buffering,
            width: 240,
            height: 135
        )
    }

    private func timelinePreviewBufferedUntilSeconds(for media: PlaybackMediaSource) -> Double? {
        if media.url.isFileURL {
            return status.duration ?? .greatestFiniteMagnitude
        }
        guard let duration = status.duration else { return nil }
        switch status.bufferingState {
        case .buffering(let progress):
            return duration * min(max(progress, 0), 1)
        case .ready:
            return max(status.currentTime, min(duration, status.currentTime + 30))
        case .idle:
            return nil
        }
    }

    private func loadPlayerPreferences() async {
        guard let settingsRepository else { return }
        appSettings = await settingsRepository.appSettings
        subtitleSettings = await settingsRepository.subtitleSettings
    }

    private func applyRememberedPreferences() async {
        let playback = appSettings.playback
        try? await service.setVolume(playback.rememberedVolume)
        try? await service.setPlaybackSpeed(playback.playbackSpeed)
        try? await service.setAudioBoost(playback.audioBoost)
        try? await service.setFullscreen(playback.defaultFullscreen)
        try? await service.setSubtitleDelay(subtitleSettings.subtitleDelaySeconds)
        try? await service.setSubtitleFontSize(subtitleSettings.fontSize)
        try? await service.setSubtitleStyle(subtitleSettings.visualStyle)
        await refreshStatus()

        await applySmartAudioSelection()

        await applySmartSubtitleSelection()
        await refreshStatus()
    }

    private func updatePlaybackSettings(_ update: (inout PlaybackSettings) -> Void) async {
        var settings = appSettings
        update(&settings.playback)
        appSettings = settings
        await settingsRepository?.setAppSettings(settings)
    }

    private func rememberAudioSelection(id: String?) async {
        let track = status.audioTracks.first(where: { $0.id == id })
        await updatePlaybackSettings {
            $0.rememberedAudioLanguage = track?.languageCode.lowercased()
            if let track {
                $0.manualAudioOverridesByMediaID[self.mediaAudioOverrideKey] = AudioSelectionOverride(
                    trackID: track.id,
                    languageCode: track.languageCode,
                    isOriginal: track.isOriginal
                )
            } else {
                $0.manualAudioOverridesByMediaID.removeValue(forKey: self.mediaAudioOverrideKey)
            }
        }
        updateAudioSelectionSummary(track: track, reason: track == nil ? "Auto" : "Manual")
    }

    private func applySmartAudioSelection() async {
        guard !status.audioTracks.isEmpty else { return }

        let override = appSettings.playback.manualAudioOverridesByMediaID[mediaAudioOverrideKey]
        if let overrideTrack = override.flatMap(trackMatchingAudioOverride(_:)) {
            try? await service.selectAudioTrack(id: overrideTrack.id)
            await refreshStatus()
            updateAudioSelectionSummary(track: overrideTrack, reason: "Manual")
            return
        }

        let selection = smartAudioSelection()
        guard let track = selection.track else { return }
        try? await service.selectAudioTrack(id: track.id)
        await refreshStatus()
        updateAudioSelectionSummary(track: track, reason: selection.reason)
    }

    private func smartAudioSelection() -> (track: AudioTrack?, reason: String) {
        let sorted = sortAudioCandidates(status.audioTracks)
        let priority = appSettings.playback.resolvedAudioLanguagePriority
        for token in priority {
            if token == "original" {
                if let track = sorted.first(where: \.isOriginal) {
                    return (track, "fallback Original")
                }
                continue
            }
            if let track = sorted.first(where: { $0.languageCode.caseInsensitiveCompare(token) == .orderedSame }) {
                let reason = token == priority.first ? "preferred \(languageLabel(for: track))" : "fallback \(languageLabel(for: track))"
                return (track, reason)
            }
        }
        return (sorted.first, sorted.first.map { "fallback \($0.isOriginal ? "Original" : languageLabel(for: $0))" } ?? "Auto")
    }

    private func trackMatchingAudioOverride(_ override: AudioSelectionOverride) -> AudioTrack? {
        if let trackID = override.trackID,
           let track = status.audioTracks.first(where: { $0.id == trackID }) {
            return track
        }
        if override.isOriginal,
           let track = sortAudioCandidates(status.audioTracks).first(where: \.isOriginal) {
            return track
        }
        if let languageCode = override.languageCode {
            return sortAudioCandidates(status.audioTracks).first {
                $0.languageCode.caseInsensitiveCompare(languageCode) == .orderedSame
            }
        }
        return nil
    }

    private func sortAudioCandidates(_ tracks: [AudioTrack]) -> [AudioTrack] {
        tracks.sorted { lhs, rhs in
            let lhsPriority = audioPriority(for: lhs)
            let rhsPriority = audioPriority(for: rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.qualityScore != rhs.qualityScore {
                return lhs.qualityScore > rhs.qualityScore
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func audioPriority(for track: AudioTrack) -> Int {
        let priority = appSettings.playback.resolvedAudioLanguagePriority
        let languageIndex = priority.firstIndex { token in
            if token == "original" {
                return track.isOriginal
            }
            return track.languageCode.caseInsensitiveCompare(token) == .orderedSame
        }
        return languageIndex ?? priority.count
    }

    private func updateAudioSelectionSummary(track: AudioTrack?, reason: String) {
        guard let track else {
            audioSelectionSummary = "Audio: Auto"
            return
        }
        audioSelectionSummary = "\(reason): \(languageLabel(for: track)) · \(track.qualityLabel)"
    }

    private func languageLabel(for track: AudioTrack) -> String {
        if track.isOriginal {
            return "Original"
        }
        switch track.languageCode.lowercased() {
        case "ru", "rus":
            return "Russian"
        case "en", "eng":
            return "English"
        default:
            return track.languageCode.uppercased()
        }
    }

    private func rememberSubtitleSelection(id: String?) async {
        let track = subtitleTracks.first(where: { $0.id == id })
        await updatePlaybackSettings {
            $0.subtitlesEnabled = id != nil
            $0.rememberedSubtitleLanguage = track?.languageCode.lowercased()
        }

        guard settingsRepository != nil else { return }
        if id == nil {
            subtitleSettings.manualOverridesByMediaID[mediaSubtitleOverrideKey] = SubtitleSelectionOverride(isDisabled: true)
        } else if let track {
            subtitleSettings.manualOverridesByMediaID[mediaSubtitleOverrideKey] = SubtitleSelectionOverride(
                trackID: track.id,
                languageCode: track.languageCode,
                source: track.source,
                isDisabled: false
            )
        }
        await settingsRepository?.setSubtitleSettings(subtitleSettings)
    }

    private func applySmartSubtitleSelection() async {
        guard subtitleSettings.autoLoadSubtitles else {
            await selectSubtitleAutomatically(nil)
            return
        }

        if let override = subtitleSettings.manualOverridesByMediaID[mediaSubtitleOverrideKey] {
            if override.isDisabled {
                await selectSubtitleAutomatically(nil)
                return
            }
            if let track = trackMatchingOverride(override) {
                await selectSubtitleAutomatically(track)
                return
            }
        }

        let candidates = await smartSubtitleCandidates()
        if let forced = candidates.first(where: \.isForced) {
            await selectSubtitleAutomatically(forced)
            return
        }

        switch subtitleSettings.autoMode {
        case .alwaysOn:
            await selectSubtitleAutomatically(candidates.first)
        case .onlyForeignAudio:
            guard selectedAudioIsForeign else {
                await selectSubtitleAutomatically(nil)
                return
            }
            await selectSubtitleAutomatically(candidates.first)
        case .offByDefault:
            await selectSubtitleAutomatically(nil)
        }
    }

    private func smartSubtitleCandidates() async -> [SubtitleTrack] {
        let embedded = sortSubtitleCandidates(status.subtitleTracks.filter { $0.source == .embedded })
        if !embedded.isEmpty { return embedded }

        guard let subtitleService else { return [] }
        let query = subtitleSearchQuery()
        let local = (try? await subtitleService.localSubtitles(for: query, directory: nil)) ?? []
        let sortedLocal = sortSubtitleCandidates(local)
        if !sortedLocal.isEmpty { return sortedLocal }

        guard subtitleSettings.autoSearchSubtitles else { return [] }
        let results = (try? await subtitleService.searchOnlineSubtitles(
            query: query,
            languages: subtitleSettings.languagePreference.languageCodes
        )) ?? []
        guard let best = results.first,
              let downloaded = try? await subtitleService.downloadSubtitle(best)
        else { return [] }

        if !loadedSubtitleTracks.contains(where: { $0.id == downloaded.id }) {
            loadedSubtitleTracks.append(downloaded)
        }
        return [downloaded]
    }

    private func appendLoadedSubtitleTracks(_ tracks: [SubtitleTrack]) {
        for track in tracks where !status.subtitleTracks.contains(where: { $0.id == track.id }) && !loadedSubtitleTracks.contains(where: { $0.id == track.id }) {
            loadedSubtitleTracks.append(track)
        }
    }

    private func prepareSubtitleCuesForSelectedTrack() async {
        guard let track = subtitleTracks.first(where: { $0.id == status.selectedSubtitleTrackId }) else {
            activeSubtitleText = nil
            return
        }
        await prepareSubtitleCues(for: track)
    }

    private func prepareSubtitleCues(for track: SubtitleTrack) async {
        guard subtitleCueCache[track.id] == nil, let localURL = track.localURL else { return }
        guard let text = try? String(contentsOf: localURL, encoding: .utf8) else { return }
        subtitleCueCache[track.id] = Self.parseSubtitleCues(text)
    }

    private func updateActiveSubtitleText(for status: PlaybackStatus) {
        guard let selectedSubtitleTrackId = status.selectedSubtitleTrackId,
              let cues = subtitleCueCache[selectedSubtitleTrackId],
              !cues.isEmpty
        else {
            activeSubtitleText = nil
            return
        }

        let displayTime = max(0, status.currentTime + status.subtitleDelaySeconds)
        activeSubtitleText = cues.first { cue in
            displayTime >= cue.startTime && displayTime <= cue.endTime
        }?.text
    }

    private static func parseSubtitleCues(_ text: String) -> [PlayerSubtitleCue] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .compactMap(parseSubtitleCueBlock)
            .sorted { $0.startTime < $1.startTime }
    }

    private static func parseSubtitleCueBlock(_ block: String) -> PlayerSubtitleCue? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
        let timingParts = lines[timingIndex].components(separatedBy: "-->")
        guard timingParts.count == 2,
              let start = parseSubtitleTimestamp(timingParts[0]),
              let end = parseSubtitleTimestamp(timingParts[1])
        else {
            return nil
        }
        let cueText = lines
            .dropFirst(timingIndex + 1)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !cueText.isEmpty, end > start else { return nil }
        return PlayerSubtitleCue(startTime: start, endTime: end, text: cueText)
    }

    private static func parseSubtitleTimestamp(_ value: String) -> Double? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2])
        else {
            return nil
        }
        return (hours * 3_600) + (minutes * 60) + seconds
    }

    private func selectSubtitleAutomatically(_ track: SubtitleTrack?) async {
        try? await service.selectSubtitleTrack(id: track?.id)
        await refreshStatusPreservingLoadedSubtitleSelection(track?.id)
        if let track {
            await prepareSubtitleCues(for: track)
            updateActiveSubtitleText(for: status)
        } else {
            activeSubtitleText = nil
        }
    }

    private func trackMatchingOverride(_ override: SubtitleSelectionOverride) -> SubtitleTrack? {
        if let trackID = override.trackID,
           let track = subtitleTracks.first(where: { $0.id == trackID }) {
            return track
        }
        if let languageCode = override.languageCode {
            return sortSubtitleCandidates(subtitleTracks).first {
                $0.languageCode.caseInsensitiveCompare(languageCode) == .orderedSame
            }
        }
        return nil
    }

    private func sortSubtitleCandidates(_ tracks: [SubtitleTrack]) -> [SubtitleTrack] {
        tracks.sorted { lhs, rhs in
            if lhs.isForced != rhs.isForced {
                return lhs.isForced
            }
            let languageDifference = subtitleSettings.languagePreference.priority(for: lhs.languageCode)
                - subtitleSettings.languagePreference.priority(for: rhs.languageCode)
            if languageDifference != 0 {
                return languageDifference < 0
            }
            return subtitleSourcePriority(lhs.source) < subtitleSourcePriority(rhs.source)
        }
    }

    private func subtitleSourcePriority(_ source: SubtitleSource) -> Int {
        switch source {
        case .embedded:
            0
        case .localFile:
            1
        case .openSubtitles:
            2
        }
    }

    private var mediaSubtitleOverrideKey: String {
        mediaSource.selectionContext?.episodeID
            ?? mediaSource.selectionContext?.mediaID
            ?? mediaSource.id
    }

    private var mediaAudioOverrideKey: String {
        mediaSource.selectionContext?.episodeID
            ?? mediaSource.selectionContext?.mediaID
            ?? mediaSource.id
    }

    private var selectedAudioIsForeign: Bool {
        guard let selectedAudioLanguage else { return false }
        guard let primaryLanguage = appSettings.playback.preferredAudioLanguages.first?.lowercased() else { return true }
        return selectedAudioLanguage.lowercased() != primaryLanguage
    }

    private var selectedAudioLanguage: String? {
        if let selectedAudioTrackId = status.selectedAudioTrackId,
           let track = status.audioTracks.first(where: { $0.id == selectedAudioTrackId }) {
            return track.languageCode
        }
        return appSettings.playback.rememberedAudioLanguage ?? status.audioTracks.first?.languageCode
    }

    private func subtitleSearchQuery() -> SubtitleSearchQuery {
        SubtitleSearchQuery(
            title: mediaSource.selectionContext?.displayTitle ?? mediaSource.title,
            year: Self.year(from: mediaSource.title) ?? mediaSource.release.flatMap { Self.year(from: $0.title) },
            season: mediaSource.selectionContext?.seasonNumber,
            episode: mediaSource.selectionContext?.episodeNumber,
            localVideoURL: mediaSource.url.isFileURL ? mediaSource.url : nil
        )
    }

    private func refreshStatus() async {
        status = await service.currentStatus
        updateActiveSubtitleText(for: status)
        updateNextEpisodePromptIfNeeded(for: status)
        try? await progressRecorder?.recordIfNeeded(status: status)
    }

    private func refreshStatusPreservingLoadedSubtitleSelection(_ subtitleTrackId: String?) async {
        let latest = await service.currentStatus
        status = PlaybackStatus(
            media: latest.media,
            state: latest.state,
            currentTime: latest.currentTime,
            duration: latest.duration,
            bufferingState: latest.bufferingState,
            volume: latest.volume,
            isMuted: latest.isMuted,
            playbackSpeed: latest.playbackSpeed,
            audioTracks: latest.audioTracks,
            subtitleTracks: latest.subtitleTracks,
            selectedAudioTrackId: latest.selectedAudioTrackId,
            selectedSubtitleTrackId: subtitleTrackId,
            isFullscreen: latest.isFullscreen,
            isPictureInPictureActive: latest.isPictureInPictureActive,
            qualityLabel: latest.qualityLabel,
            sourceName: latest.sourceName,
            chapters: latest.chapters,
            audioBoost: latest.audioBoost,
            subtitleDelaySeconds: latest.subtitleDelaySeconds,
            subtitleFontSize: latest.subtitleFontSize,
            subtitleStyle: latest.subtitleStyle
        )
        updateActiveSubtitleText(for: status)
    }

    private func startStatusUpdates() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await status in service.statusUpdates() {
                    await MainActor.run {
                        self.status = status
                        self.updateActiveSubtitleText(for: status)
                        self.updateFallbackSuggestionIfNeeded(for: status)
                        self.updateNextEpisodePromptIfNeeded(for: status)
                    }
                    await self.debugLogger.log(
                        diagnostics: self.diagnosticsService,
                        event: "player.status",
                        metadata: [
                            "mediaID": self.mediaSource.id,
                            "state": status.state.debugName,
                            "position": "\(Int(status.currentTime))"
                        ]
                    )
                    try? await self.progressRecorder?.recordIfNeeded(status: status)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = CineFlowError.from(error, fallbackCategory: .playback).userMessage
                }
                await self.logError(error, subsystem: .playback, operation: "statusUpdates")
            }
        }
    }

    private func startTorrentStatusUpdates() {
        torrentStatusTask?.cancel()
        guard let torrentEngine, let sessionID = torrentSession?.id else {
            torrentStatus = nil
            return
        }
        torrentStatusTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await update in torrentEngine.statusUpdates(sessionId: sessionID) {
                    guard update.sessionId == sessionID else { continue }
                    await MainActor.run {
                        self.torrentStatus = update
                    }
                }
            } catch {
                await self.logError(error, subsystem: .torrent, operation: "torrentStatusUpdates")
            }
        }
    }

    private func perform(
        subsystem: DiagnosticsSubsystem = .playback,
        operation name: String = "playbackOperation",
        _ operation: @escaping () async throws -> Void
    ) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            await handlePlaybackFailure(
                error,
                subsystem: subsystem,
                operation: name,
                allowAutomaticFallback: false
            )
        }
    }

    private func handlePlaybackFailure(
        _ error: Error,
        subsystem: DiagnosticsSubsystem,
        operation: String,
        allowAutomaticFallback: Bool
    ) async {
        let cineFlowError = CineFlowError.from(error, fallbackCategory: .playback)
        if status.state.shouldFailFastInUI,
           allowAutomaticFallback,
           startAutomaticFallback(reason: .failedToStart, failedStatus: status) {
            await logError(error, subsystem: subsystem, operation: operation)
            return
        }

        errorMessage = cineFlowError.userMessage
        if status.state.shouldFailFastInUI {
            status = PlaybackStatus(
                media: status.media ?? mediaSource,
                state: .failed(reason: cineFlowError.technicalDescription),
                currentTime: status.currentTime,
                duration: status.duration,
                bufferingState: .idle,
                volume: status.volume,
                isMuted: status.isMuted,
                playbackSpeed: status.playbackSpeed,
                audioTracks: status.audioTracks,
                subtitleTracks: status.subtitleTracks,
                selectedAudioTrackId: status.selectedAudioTrackId,
                selectedSubtitleTrackId: status.selectedSubtitleTrackId,
                isFullscreen: status.isFullscreen,
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
        await logError(error, subsystem: subsystem, operation: operation)
    }

    @discardableResult
    private func startAutomaticFallback(reason: ReleaseFallbackReason, failedStatus: PlaybackStatus) -> Bool {
        guard fallbackHandler != nil,
              let release = failedStatus.media?.release ?? mediaSource.release,
              let suggestion = ReleaseFallbackPlanner.suggestion(
                for: release,
                in: fallbackReleases,
                reason: reason,
                preferences: recoveryFallbackPreferences(for: reason)
              ),
              let nextRelease = suggestion.nextBestRelease?.release,
              !automaticallyTriedFallbackReleaseIDs.contains(nextRelease.id)
        else { return false }

        automaticallyTriedFallbackReleaseIDs.insert(nextRelease.id)
        fallbackSuggestion = suggestion
        errorMessage = nil
        status = PlaybackStatus(
            media: failedStatus.media ?? mediaSource,
            state: .retrying,
            currentTime: failedStatus.currentTime,
            duration: failedStatus.duration,
            bufferingState: .buffering(progress: 0),
            volume: failedStatus.volume,
            isMuted: failedStatus.isMuted,
            playbackSpeed: failedStatus.playbackSpeed,
            audioTracks: failedStatus.audioTracks,
            subtitleTracks: failedStatus.subtitleTracks,
            selectedAudioTrackId: failedStatus.selectedAudioTrackId,
            selectedSubtitleTrackId: failedStatus.selectedSubtitleTrackId,
            isFullscreen: failedStatus.isFullscreen,
            isPictureInPictureActive: failedStatus.isPictureInPictureActive,
            qualityLabel: failedStatus.qualityLabel,
            sourceName: failedStatus.sourceName,
            chapters: failedStatus.chapters,
            audioBoost: failedStatus.audioBoost,
            subtitleDelaySeconds: failedStatus.subtitleDelaySeconds,
            subtitleFontSize: failedStatus.subtitleFontSize,
            subtitleStyle: failedStatus.subtitleStyle
        )
        Task { await self.tryNextBestRelease() }
        Task {
            await diagnosticsService?.log(
                level: .warning,
                subsystem: .playback,
                message: reason.userFacingSummary,
                metadata: [
                    "operation": "player.fallback.auto",
                    "mediaID": mediaSource.id,
                    "releaseID": release.id,
                    "fallbackReleaseID": nextRelease.id,
                    "reason": reason.rawValue
                ]
            )
        }
        return true
    }

    private func logError(_ error: Error, subsystem: DiagnosticsSubsystem, operation: String) async {
        let fallbackCategory: CineFlowErrorCategory = subsystem == .subtitle ? .subtitles : .playback
        await diagnosticsService?.log(
            CineFlowError.from(error, fallbackCategory: fallbackCategory),
            operation: operation,
            metadata: ["mediaID": mediaSource.id]
        )
    }

    private func updateFallbackSuggestionIfNeeded(for status: PlaybackStatus) {
        guard fallbackSuggestion == nil else { return }
        guard let release = status.media?.release ?? mediaSource.release else { return }

        let reason: ReleaseFallbackReason?
        switch status.state {
        case .stalled:
            reason = .stalled
        case .failed(let message) where message.localizedCaseInsensitiveContains("stall"):
            reason = .stalled
        case .failed:
            reason = .failedToStart
        default:
            reason = nil
        }

        guard let reason,
              let suggestion = ReleaseFallbackPlanner.suggestion(
                for: release,
                in: fallbackReleases,
                reason: reason,
                preferences: recoveryFallbackPreferences(for: reason)
              )
        else { return }

        fallbackSuggestion = suggestion
        if fallbackHandler != nil,
           let nextRelease = suggestion.nextBestRelease?.release,
           !automaticallyTriedFallbackReleaseIDs.contains(nextRelease.id) {
            automaticallyTriedFallbackReleaseIDs.insert(nextRelease.id)
            self.status = PlaybackStatus(
                media: status.media,
                state: .retrying,
                currentTime: status.currentTime,
                duration: status.duration,
                bufferingState: .buffering(progress: 0),
                volume: status.volume,
                isMuted: status.isMuted,
                playbackSpeed: status.playbackSpeed,
                audioTracks: status.audioTracks,
                subtitleTracks: status.subtitleTracks,
                selectedAudioTrackId: status.selectedAudioTrackId,
                selectedSubtitleTrackId: status.selectedSubtitleTrackId,
                isFullscreen: status.isFullscreen,
                isPictureInPictureActive: status.isPictureInPictureActive,
                qualityLabel: status.qualityLabel,
                sourceName: status.sourceName,
                chapters: status.chapters,
                audioBoost: status.audioBoost,
                subtitleDelaySeconds: status.subtitleDelaySeconds,
                subtitleFontSize: status.subtitleFontSize,
                subtitleStyle: status.subtitleStyle
            )
            Task { await self.tryNextBestRelease() }
        }
        Task {
            await diagnosticsService?.log(
                level: .warning,
                subsystem: .playback,
                message: reason.userFacingSummary,
                metadata: [
                    "operation": "player.fallback.suggest",
                    "mediaID": mediaSource.id,
                    "releaseID": release.id,
                    "reason": reason.rawValue
                ]
            )
        }
    }

    private func recoveryFallbackPreferences(for reason: ReleaseFallbackReason) -> RankingPreferences {
        switch reason {
        case .failedToStart, .noSeeders, .stalled:
            RankingPreferences(
                preferredAudioLanguages: fallbackPreferences.preferredAudioLanguages,
                preferredSubtitleLanguages: fallbackPreferences.preferredSubtitleLanguages,
                supportsHDR: fallbackPreferences.supportsHDR,
                preferredQuality: fallbackPreferences.preferredQuality,
                hdrPreference: fallbackPreferences.hdrPreference,
                codecPreference: fallbackPreferences.codecPreference,
                maxFileSizeBytes: fallbackPreferences.maxFileSizeBytes,
                preferHighSeedersOverHighestQuality: true
            )
        case .unsupportedFile, .missingMediaFile:
            fallbackPreferences
        }
    }

    private func updateNextEpisodePromptIfNeeded(for status: PlaybackStatus) {
        guard nextEpisodePrompt == nil, let configuredNextEpisodePrompt else { return }
        guard status.progressFraction >= 0.92 || status.state == .stopped || status.state == .completed else { return }
        nextEpisodePrompt = configuredNextEpisodePrompt
        if appSettings.playback.autoplayNextEpisode {
            startNextEpisodeCountdown(seconds: 10)
        }
    }

    private func startNextEpisodeCountdown(seconds: Int) {
        nextEpisodeCountdownTask?.cancel()
        nextEpisodeCountdownSeconds = max(0, seconds)
        nextEpisodeCountdownTask = Task { [weak self] in
            var remaining = max(0, seconds)
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
                await MainActor.run {
                    guard self?.nextEpisodePrompt != nil else { return }
                    self?.nextEpisodeCountdownSeconds = remaining
                }
            }
        }
    }

    private static func timeLabel(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private static func byteRateLabel(_ bytesPerSecond: Int64) -> String {
        "\(byteCountLabel(bytesPerSecond))/s"
    }

    private static func byteCountLabel(_ bytes: Int64) -> String {
        let value = Double(max(0, bytes))
        let units = ["B", "KB", "MB", "GB", "TB"]
        var amount = value
        var unitIndex = 0
        while amount >= 1_024, unitIndex < units.count - 1 {
            amount /= 1_024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(amount)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", amount, units[unitIndex])
    }

    private static func languageCode(from url: URL) -> String? {
        url.deletingPathExtension().lastPathComponent
            .split(separator: ".")
            .map { String($0).lowercased() }
            .reversed()
            .first { $0.count == 2 || $0.count == 3 }
    }

    private static func year(from value: String) -> Int? {
        let pattern = #"\b(19\d{2}|20\d{2})\b"#
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(value[range])
    }
}

private extension PlaybackRunState {
    var shouldFailFastInUI: Bool {
        switch self {
        case .loading, .resolving, .buffering, .retrying:
            true
        case .idle, .ready, .playing, .paused, .stalled, .stopped, .failed, .completed:
            false
        }
    }

    var debugName: String {
        switch self {
        case .idle:
            "idle"
        case .loading:
            "loading"
        case .resolving:
            "resolving"
        case .buffering:
            "buffering"
        case .ready:
            "ready"
        case .playing:
            "playing"
        case .paused:
            "paused"
        case .stalled:
            "stalled"
        case .stopped:
            "stopped"
        case .failed:
            "failed"
        case .retrying:
            "retrying"
        case .completed:
            "completed"
        }
    }
}
