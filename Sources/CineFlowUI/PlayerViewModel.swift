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

public struct PlayerNextEpisodePrompt: Hashable, Sendable {
    public let title: String
    public let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct PlayerBufferingPresentation: Equatable, Sendable {
    public let title: String
    public let message: String
    public let progress: Double?
    public let advancedDetails: [String]

    public init(title: String, message: String, progress: Double? = nil, advancedDetails: [String] = []) {
        self.title = title
        self.message = message
        self.progress = progress
        self.advancedDetails = advancedDetails
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
    case escape
}

@MainActor
public final class PlayerViewModel: ObservableObject {
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

    private let service: any PlaybackServiceProtocol
    private let mediaSource: PlaybackMediaSource
    private let subtitleService: (any SubtitleServiceProtocol)?
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let progressRecorder: PlaybackProgressRecorder?
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private let fallbackReleases: [TorrentRelease]
    private let fallbackPreferences: RankingPreferences
    private let fallbackHandler: ((TorrentRelease) async -> Void)?
    private let configuredNextEpisodePrompt: PlayerNextEpisodePrompt?
    private var statusTask: Task<Void, Never>?
    private var controlsHideTask: Task<Void, Never>?

    public init(
        service: any PlaybackServiceProtocol,
        mediaSource: PlaybackMediaSource,
        subtitleService: (any SubtitleServiceProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        progressRecorder: PlaybackProgressRecorder? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        fallbackReleases: [TorrentRelease] = [],
        fallbackPreferences: RankingPreferences = RankingPreferences(),
        fallbackHandler: ((TorrentRelease) async -> Void)? = nil,
        nextEpisodePrompt: PlayerNextEpisodePrompt? = nil
    ) {
        self.service = service
        self.mediaSource = mediaSource
        self.subtitleService = subtitleService
        self.diagnosticsService = diagnosticsService
        self.progressRecorder = progressRecorder
        self.progressRepository = progressRepository
        self.fallbackReleases = fallbackReleases
        self.fallbackPreferences = fallbackPreferences
        self.fallbackHandler = fallbackHandler
        self.configuredNextEpisodePrompt = nextEpisodePrompt
        self.status = PlaybackStatus(media: mediaSource, state: .idle)
        self.fallbackSuggestion = mediaSource.release.flatMap {
            ReleaseFallbackPlanner.seedWarning(for: $0, in: fallbackReleases, preferences: fallbackPreferences)
        }
    }

    deinit {
        statusTask?.cancel()
        controlsHideTask?.cancel()
    }

    public var audioTracks: [AudioTrack] {
        status.audioTracks
    }

    public var subtitleTracks: [SubtitleTrack] {
        status.subtitleTracks + loadedSubtitleTracks
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
            var details: [String] = []
            if advancedDebugVisible, let release = status.media?.release ?? mediaSource.release {
                details.append("Download speed: unavailable")
                details.append("Seeders: \(release.seeders)")
                details.append("Source health: \(release.releaseHealth.label)")
                details.append("Health: \(release.releaseHealth.label)")
                details.append("Source: \(release.sourceName)")
            }
            return PlayerBufferingPresentation(
                title: "Buffering",
                message: "Preparing stream · \(Int(progress * 100))%",
                progress: progress,
                advancedDetails: details
            )
        }
    }

    public var avPlayer: AVPlayer? {
        (service as? AVPlayerProviding)?.avPlayer
    }

    public func start() async {
        status = PlaybackStatus(media: mediaSource, state: .loading, bufferingState: .buffering(progress: 0))
        await perform {
            self.resumeProgress = try await self.progressRepository?.progress(mediaID: self.mediaSource.id, episodeID: nil)
            try await self.service.play(self.mediaSource)
            if let resumeProgress = self.resumeProgress, resumeProgress.positionSeconds > 5, !resumeProgress.completed {
                self.resumePrompt = PlayerResumePrompt(
                    positionSeconds: resumeProgress.positionSeconds,
                    positionLabel: Self.timeLabel(resumeProgress.positionSeconds)
                )
            }
            await self.refreshStatus()
            self.startStatusUpdates()
        }
    }

    public func continueFromResume() async {
        guard let resumePrompt else { return }
        await seek(to: resumePrompt.positionSeconds)
        self.resumePrompt = nil
    }

    public func startOverFromBeginning() async {
        await seek(to: 0)
        resumePrompt = nil
    }

    public func togglePlayPause() async {
        await perform {
            switch self.status.state {
            case .playing:
                try await self.service.pause()
            case .paused, .idle, .stopped:
                if self.status.media == nil || self.status.state == .idle {
                    try await self.service.play(self.mediaSource)
                } else {
                    try await self.service.resume()
                }
            case .loading, .failed:
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
        }
    }

    public func selectAudioTrack(id: String?) async {
        await perform {
            try await self.service.selectAudioTrack(id: id)
            await self.refreshStatus()
        }
    }

    public func selectSubtitleTrack(id: String?) async {
        await perform {
            try await self.service.selectSubtitleTrack(id: id)
            await self.refreshStatus()
        }
    }

    public func findOnlineSubtitles() async {
        guard let subtitleService else { return }
        await perform(subsystem: .subtitle, operation: "findOnlineSubtitles") {
            let query = SubtitleSearchQuery(title: self.mediaSource.title)
            self.onlineSubtitleResults = try await subtitleService.searchOnlineSubtitles(
                query: query,
                languages: ["ru", "en"]
            )
        }
    }

    public func downloadSubtitle(_ result: SubtitleSearchResult) async {
        guard let subtitleService else { return }
        await perform(subsystem: .subtitle, operation: "downloadSubtitle") {
            let track = try await subtitleService.downloadSubtitle(result)
            self.loadedSubtitleTracks.append(track)
            try? await self.service.selectSubtitleTrack(id: track.id)
            await self.refreshStatusPreservingLoadedSubtitleSelection(track.id)
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
    }

    public func disableSubtitles() async {
        await perform {
            try await self.service.selectSubtitleTrack(id: nil)
            await self.refreshStatusPreservingLoadedSubtitleSelection(nil)
        }
    }

    public func toggleFullscreen() async {
        await perform {
            try await self.service.setFullscreen(!self.status.isFullscreen)
            await self.refreshStatus()
        }
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
        case .subtitles, .audio, .escape:
            showControls()
        }
    }

    public func stop() async {
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
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self?.controlsAreVisible = false
            }
        }
    }

    public func dismissNextEpisodePrompt() {
        nextEpisodePrompt = nil
    }

    private func seek(by delta: Double) async {
        await seek(to: status.currentTime + delta)
    }

    private func refreshStatus() async {
        status = await service.currentStatus
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
            sourceName: latest.sourceName
        )
    }

    private func startStatusUpdates() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await status in service.statusUpdates() {
                    await MainActor.run {
                        self.status = status
                        self.updateFallbackSuggestionIfNeeded(for: status)
                        self.updateNextEpisodePromptIfNeeded(for: status)
                    }
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

    private func perform(
        subsystem: DiagnosticsSubsystem = .playback,
        operation name: String = "playbackOperation",
        _ operation: @escaping () async throws -> Void
    ) async {
        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = CineFlowError.from(error, fallbackCategory: .playback).userMessage
            await logError(error, subsystem: subsystem, operation: name)
        }
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
                preferences: fallbackPreferences
              )
        else { return }

        fallbackSuggestion = suggestion
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

    private func updateNextEpisodePromptIfNeeded(for status: PlaybackStatus) {
        guard nextEpisodePrompt == nil, let configuredNextEpisodePrompt else { return }
        guard status.progressFraction >= 0.92 || status.state == .stopped else { return }
        nextEpisodePrompt = configuredNextEpisodePrompt
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

    private static func languageCode(from url: URL) -> String? {
        url.deletingPathExtension().lastPathComponent
            .split(separator: ".")
            .map { String($0).lowercased() }
            .reversed()
            .first { $0.count == 2 || $0.count == 3 }
    }
}
