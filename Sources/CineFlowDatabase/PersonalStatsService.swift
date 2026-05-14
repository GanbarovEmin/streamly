import CineFlowCore
import Foundation
import GRDB

public final class DatabasePersonalStatsService: PersonalStatsServiceProtocol {
    private let databaseManager: DatabaseManager
    private let calendar: Calendar
    private let bingeGapSeconds: TimeInterval = 2 * 60 * 60

    public init(databaseManager: DatabaseManager, calendar: Calendar = .current) {
        self.databaseManager = databaseManager
        self.calendar = calendar
    }

    public func personalStats(referenceDate: Date = Date()) async throws -> PersonalWatchStats {
        try databaseManager.read { db in
            let mediaItems = try mediaItemsByID(db)
            let history = try Row.fetchAll(db, sql: "SELECT * FROM watch_history ORDER BY watched_at ASC")
                .map(watchHistoryItem(from:))
            let progress = try Row.fetchAll(db, sql: "SELECT * FROM playback_progress ORDER BY updated_at DESC")
                .map(playbackProgress(from:))

            let completedHistory = history.filter(\.completed)
            let watchedMovieIDs = Set(completedHistory.compactMap { entry -> String? in
                guard entry.episodeID == nil, mediaItems[entry.mediaID]?.kind == .movie else { return nil }
                return entry.mediaID
            })
            let watchedEpisodeIDs = Set(completedHistory.compactMap { entry -> String? in
                guard let episodeID = entry.episodeID else { return nil }
                return "\(entry.mediaID):\(episodeID)"
            })

            let monthlyWatchTimeSeconds = history
                .filter { calendar.isDate($0.lastWatchedAt, equalTo: referenceDate, toGranularity: .month) }
                .reduce(0) { $0 + watchedSeconds($1) }
            let completionRate = completionRate(history: history, progress: progress)
            let rankedGenres = rankedCounts(from: history, mediaItems: mediaItems) { item in
                item.metadata?.genres ?? []
            }
            let rankedActors = rankedCounts(from: history, mediaItems: mediaItems) { item in
                (item.metadata?.cast ?? []).map(\.name)
            }

            return PersonalWatchStats(
                watchedMoviesCount: watchedMovieIDs.count,
                watchedEpisodesCount: watchedEpisodeIDs.count,
                monthlyWatchTimeSeconds: monthlyWatchTimeSeconds,
                completionRate: completionRate,
                longestBingeSession: longestBingeSession(history),
                favoriteGenres: rankedGenres,
                favoriteActors: rankedActors,
                yearRecapStatus: .collectingSignals,
                sharesPrivateAnalytics: false
            )
        }
    }

    private func mediaItemsByID(_ db: Database) throws -> [String: MediaItem] {
        let items = try Row.fetchAll(db, sql: "SELECT * FROM media_items").map(mediaItem(from:))
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private func completionRate(history: [WatchHistoryItem], progress: [PlaybackProgress]) -> Double {
        if !history.isEmpty {
            return Double(history.filter(\.completed).count) / Double(history.count)
        }
        guard !progress.isEmpty else { return 0 }
        return Double(progress.filter(\.completed).count) / Double(progress.count)
    }

    private func rankedCounts(
        from history: [WatchHistoryItem],
        mediaItems: [String: MediaItem],
        values: (MediaItem) -> [String]
    ) -> [PersonalStatsRankedItem] {
        let counts = history.reduce(into: [String: Int]()) { partial, entry in
            guard let item = mediaItems[entry.mediaID] else { return }
            for value in values(item) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                partial[trimmed, default: 0] += 1
            }
        }

        return counts
            .map(PersonalStatsRankedItem.init(name:count:))
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func longestBingeSession(_ history: [WatchHistoryItem]) -> PersonalBingeSession? {
        let sortedHistory = history.sorted { $0.lastWatchedAt < $1.lastWatchedAt }
        guard let firstEntry = sortedHistory.first else { return nil }

        var currentStart = firstEntry.lastWatchedAt
        var currentEnd = firstEntry.lastWatchedAt
        var currentDuration = watchedSeconds(firstEntry)
        var currentCount = 1
        var best = PersonalBingeSession(
            startedAt: currentStart,
            endedAt: currentEnd,
            durationSeconds: currentDuration,
            itemCount: currentCount
        )

        for entry in sortedHistory.dropFirst() {
            let gap = entry.lastWatchedAt.timeIntervalSince(currentEnd)
            if gap <= bingeGapSeconds {
                currentEnd = entry.lastWatchedAt
                currentDuration += watchedSeconds(entry)
                currentCount += 1
            } else {
                currentStart = entry.lastWatchedAt
                currentEnd = entry.lastWatchedAt
                currentDuration = watchedSeconds(entry)
                currentCount = 1
            }

            if currentDuration > best.durationSeconds || (currentDuration == best.durationSeconds && currentCount > best.itemCount) {
                best = PersonalBingeSession(
                    startedAt: currentStart,
                    endedAt: currentEnd,
                    durationSeconds: currentDuration,
                    itemCount: currentCount
                )
            }
        }

        return best
    }
}

private func watchedSeconds(_ entry: WatchHistoryItem) -> Double {
    let position = max(entry.positionSeconds, 0)
    guard let duration = entry.durationSeconds, duration > 0 else {
        return position
    }
    return min(position, duration)
}
