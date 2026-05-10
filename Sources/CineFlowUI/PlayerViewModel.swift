import CineFlowCore
import CineFlowPlayback
import Foundation

@MainActor
public final class PlayerViewModel: ObservableObject {
    @Published public private(set) var status: PlaybackStatus
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var controlsAreVisible = true
    @Published public private(set) var onlineSubtitleResults: [SubtitleSearchResult] = []
    @Published private var loadedSubtitleTracks: [SubtitleTrack] = []
    @Published public private(set) var resumeProgress: PlaybackProgress?

    private let service: any PlaybackServiceProtocol
    private let mediaSource: PlaybackMediaSource
    private let subtitleService: (any SubtitleServiceProtocol)?
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?
    private let progressRecorder: PlaybackProgressRecorder?
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private var statusTask: Task<Void, Never>?

    public init(
        service: any PlaybackServiceProtocol,
        mediaSource: PlaybackMediaSource,
        subtitleService: (any SubtitleServiceProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil,
        progressRecorder: PlaybackProgressRecorder? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil
    ) {
        self.service = service
        self.mediaSource = mediaSource
        self.subtitleService = subtitleService
        self.diagnosticsService = diagnosticsService
        self.progressRecorder = progressRecorder
        self.progressRepository = progressRepository
        self.status = PlaybackStatus(media: mediaSource, state: .idle)
    }

    deinit {
        statusTask?.cancel()
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
        guard let resumeProgress else { return false }
        return resumeProgress.positionSeconds > 5 && !resumeProgress.completed
    }

    public func start() async {
        await perform {
            self.resumeProgress = try await self.progressRepository?.progress(mediaID: self.mediaSource.id, episodeID: nil)
            try await self.service.play(self.mediaSource)
            if let resumeProgress = self.resumeProgress, resumeProgress.positionSeconds > 5, !resumeProgress.completed {
                try await self.service.seek(to: resumeProgress.positionSeconds)
            }
            await self.refreshStatus()
            self.startStatusUpdates()
        }
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

    public func seekBackward() async {
        await seek(by: -10)
    }

    public func seek(to time: Double) async {
        await perform {
            try await self.service.seek(to: time)
            await self.refreshStatus()
        }
    }

    public func volumeUp() async {
        await setVolume(status.volume + 0.05)
    }

    public func volumeDown() async {
        await setVolume(status.volume - 0.05)
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

    public func stop() async {
        await perform {
            try await self.progressRecorder?.recordIfNeeded(status: self.status, force: true)
            try await self.service.stop()
            await self.refreshStatus()
        }
    }

    public func saveProgressOnClose() async {
        try? await progressRecorder?.recordIfNeeded(status: status, force: true)
    }

    public func hideControls() {
        controlsAreVisible = false
    }

    public func showControls() {
        controlsAreVisible = true
    }

    private func seek(by delta: Double) async {
        await seek(to: status.currentTime + delta)
    }

    private func refreshStatus() async {
        status = await service.currentStatus
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
