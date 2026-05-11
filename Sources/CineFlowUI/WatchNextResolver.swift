import CineFlowCore
import Foundation

public enum WatchNextReason: Equatable, Sendable {
    case startSeries
    case continueEpisode
    case nextEpisode
}

public struct WatchNextSeasonProgress: Equatable, Sendable {
    public let seasonID: String
    public let seasonNumber: Int
    public let completedEpisodes: Int
    public let totalEpisodes: Int

    public init(seasonID: String, seasonNumber: Int, completedEpisodes: Int, totalEpisodes: Int) {
        self.seasonID = seasonID
        self.seasonNumber = seasonNumber
        self.completedEpisodes = max(0, completedEpisodes)
        self.totalEpisodes = max(0, totalEpisodes)
    }

    public var progressFraction: Double {
        guard totalEpisodes > 0 else { return 0 }
        return min(max(Double(completedEpisodes) / Double(totalEpisodes), 0), 1)
    }
}

public struct WatchNextEpisode: Identifiable, Equatable, Sendable {
    public let seriesID: String
    public let seriesTitle: String
    public let episode: SeriesEpisode
    public let reason: WatchNextReason
    public let progress: Double
    public let seasonProgress: WatchNextSeasonProgress

    public init(
        seriesID: String,
        seriesTitle: String,
        episode: SeriesEpisode,
        reason: WatchNextReason,
        progress: Double,
        seasonProgress: WatchNextSeasonProgress
    ) {
        self.seriesID = seriesID
        self.seriesTitle = seriesTitle
        self.episode = episode
        self.reason = reason
        self.progress = min(max(progress, 0), 1)
        self.seasonProgress = seasonProgress
    }

    public var id: String {
        episode.id
    }

    public var episodeLabel: String {
        String(format: "S%02dE%02d", episode.seasonNumber, episode.episodeNumber)
    }

    public var ctaTitle: String {
        "Continue \(episodeLabel)"
    }
}

public enum WatchNextResolver {
    public static let completionThresholdPercent = 90.0

    public static func resolve(
        series: SeriesDetail,
        seasons: [SeriesSeason],
        progressByEpisodeID: [String: PlaybackProgress],
        lastWatchedEpisodeID: String?
    ) -> WatchNextEpisode? {
        let releasedEpisodes = orderedReleasedEpisodes(in: seasons)
        guard !releasedEpisodes.isEmpty else { return nil }

        let lastEpisodeID = lastWatchedEpisodeID ?? latestProgress(progressByEpisodeID)?.episodeID
        if let lastEpisodeID,
           let lastEpisode = releasedEpisodes.first(where: { $0.id == lastEpisodeID }),
           let progress = progressByEpisodeID[lastEpisodeID],
           !isCompleted(progress) {
            return makeItem(
                series: series,
                seasons: seasons,
                episode: lastEpisode,
                reason: .continueEpisode,
                progressByEpisodeID: progressByEpisodeID
            )
        }

        if let lastEpisodeID,
           let index = releasedEpisodes.firstIndex(where: { $0.id == lastEpisodeID }) {
            let nextIndex = releasedEpisodes.index(after: index)
            if nextIndex < releasedEpisodes.endIndex {
                return makeItem(
                    series: series,
                    seasons: seasons,
                    episode: releasedEpisodes[nextIndex],
                    reason: .nextEpisode,
                    progressByEpisodeID: progressByEpisodeID
                )
            }
        }

        if let firstIncomplete = releasedEpisodes.first(where: { !isCompleted(progressByEpisodeID[$0.id]) }) {
            let reason: WatchNextReason = progressByEpisodeID.isEmpty ? .startSeries : .nextEpisode
            return makeItem(
                series: series,
                seasons: seasons,
                episode: firstIncomplete,
                reason: reason,
                progressByEpisodeID: progressByEpisodeID
            )
        }

        return nil
    }

    public static func seasonProgressSummaries(
        seasons: [SeriesSeason],
        progressByEpisodeID: [String: PlaybackProgress]
    ) -> [WatchNextSeasonProgress] {
        seasons.sorted { $0.seasonNumber < $1.seasonNumber }.map { season in
            let releasedEpisodes = season.episodes.filter(\.isReleased)
            let completed = releasedEpisodes.filter { isCompleted(progressByEpisodeID[$0.id]) }.count
            return WatchNextSeasonProgress(
                seasonID: season.id,
                seasonNumber: season.seasonNumber,
                completedEpisodes: completed,
                totalEpisodes: releasedEpisodes.count
            )
        }
    }

    public static func isCompleted(_ progress: PlaybackProgress?) -> Bool {
        guard let progress else { return false }
        return progress.completed || progress.progressPercent > completionThresholdPercent
    }

    private static func orderedReleasedEpisodes(in seasons: [SeriesSeason]) -> [SeriesEpisode] {
        seasons
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .flatMap { season in
                season.episodes
                    .filter(\.isReleased)
                    .sorted { $0.episodeNumber < $1.episodeNumber }
            }
    }

    private static func latestProgress(_ progressByEpisodeID: [String: PlaybackProgress]) -> PlaybackProgress? {
        progressByEpisodeID.values.max { lhs, rhs in
            lhs.lastWatchedAt < rhs.lastWatchedAt
        }
    }

    private static func makeItem(
        series: SeriesDetail,
        seasons: [SeriesSeason],
        episode: SeriesEpisode,
        reason: WatchNextReason,
        progressByEpisodeID: [String: PlaybackProgress]
    ) -> WatchNextEpisode {
        let seasonProgress = seasonProgressSummaries(
            seasons: seasons,
            progressByEpisodeID: progressByEpisodeID
        ).first { $0.seasonID == episode.seasonID } ?? WatchNextSeasonProgress(
            seasonID: episode.seasonID,
            seasonNumber: episode.seasonNumber,
            completedEpisodes: 0,
            totalEpisodes: 0
        )
        let progress = progressByEpisodeID[episode.id].map { min(max($0.progressPercent / 100, 0), 1) } ?? 0
        return WatchNextEpisode(
            seriesID: series.id,
            seriesTitle: series.title,
            episode: episode,
            reason: reason,
            progress: progress,
            seasonProgress: seasonProgress
        )
    }
}

public protocol WatchNextProviderProtocol: Sendable {
    func watchNextItems(progressRecords: [PlaybackProgress]) async -> [WatchNextEpisode]
}

public struct SeriesDetailWatchNextProvider: WatchNextProviderProtocol {
    private let provider: any SeriesDetailProviderProtocol

    public init(provider: any SeriesDetailProviderProtocol) {
        self.provider = provider
    }

    public func watchNextItems(progressRecords: [PlaybackProgress]) async -> [WatchNextEpisode] {
        let seriesProgress = Dictionary(grouping: progressRecords.filter { $0.episodeID != nil }, by: \.mediaID)
        var items: [WatchNextEpisode] = []

        for mediaID in seriesProgress.keys.sorted() {
            guard let records = seriesProgress[mediaID] else { continue }
            let progressByEpisodeID = Dictionary(uniqueKeysWithValues: records.compactMap { record in
                record.episodeID.map { ($0, record) }
            })
            let lastWatchedEpisodeID = records.max { $0.lastWatchedAt < $1.lastWatchedAt }?.episodeID
            guard
                let response = try? await provider.seriesDetail(id: mediaID),
                let item = WatchNextResolver.resolve(
                    series: response.series,
                    seasons: response.seasons,
                    progressByEpisodeID: progressByEpisodeID,
                    lastWatchedEpisodeID: lastWatchedEpisodeID
                )
            else { continue }
            items.append(item)
        }

        return items.sorted { lhs, rhs in
            let lhsProgress = seriesProgress[lhs.seriesID]?.max { $0.lastWatchedAt < $1.lastWatchedAt }?.lastWatchedAt ?? .distantPast
            let rhsProgress = seriesProgress[rhs.seriesID]?.max { $0.lastWatchedAt < $1.lastWatchedAt }?.lastWatchedAt ?? .distantPast
            return lhsProgress > rhsProgress
        }
    }
}
