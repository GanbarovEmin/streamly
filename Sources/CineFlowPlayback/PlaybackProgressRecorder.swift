import CineFlowCore
import Foundation

public actor PlaybackProgressRecorder {
    private let store: any PlaybackProgressStoreProtocol
    private let historyStore: (any WatchHistoryRepositoryProtocol)?
    private let saveIntervalSeconds: Double
    private var lastSavedPositionByMediaID: [String: Double] = [:]

    public init(
        store: any PlaybackProgressStoreProtocol,
        historyStore: (any WatchHistoryRepositoryProtocol)? = nil,
        saveIntervalSeconds: Double = 5
    ) {
        self.store = store
        self.historyStore = historyStore
        self.saveIntervalSeconds = saveIntervalSeconds
    }

    public func recordIfNeeded(status: PlaybackStatus, force: Bool = false) async throws {
        guard let media = status.media else { return }
        guard force || status.state == .playing || status.state == .paused else { return }
        let progressMediaID = media.selectionContext?.mediaID ?? media.id
        let progressEpisodeID = media.selectionContext?.episodeID
        let progressKey = progressEpisodeID.map { "\(progressMediaID):\($0)" } ?? progressMediaID

        let lastSavedPosition = lastSavedPositionByMediaID[progressKey] ?? 0
        guard force || status.currentTime - lastSavedPosition >= saveIntervalSeconds else { return }

        try await store.saveProgress(
            PlaybackProgress(
                mediaID: progressMediaID,
                episodeID: progressEpisodeID,
                releaseID: media.release?.id,
                positionSeconds: status.currentTime,
                durationSeconds: status.duration
            )
        )
        if force {
            try await historyStore?.record(
                PlaybackProgress(
                    mediaID: progressMediaID,
                    episodeID: progressEpisodeID,
                    releaseID: media.release?.id,
                    positionSeconds: status.currentTime,
                    durationSeconds: status.duration
                )
            )
        }
        lastSavedPositionByMediaID[progressKey] = status.currentTime
    }
}

public actor InMemoryPlaybackProgressStore: PlaybackProgressStoreProtocol {
    public private(set) var records: [PlaybackProgress] = []

    public init() {}

    public func saveProgress(_ progress: PlaybackProgress) async throws {
        records.append(progress)
    }
}
