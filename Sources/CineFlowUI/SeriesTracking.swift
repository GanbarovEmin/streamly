import CineFlowCore
import Foundation

public enum SeriesEpisodeSourceAvailability: Equatable, Sendable {
    case metadataReleasedNoSource
    case sourceAvailable(bestReleaseID: String, qualityLabel: String, sourceName: String)

    public var bestReleaseID: String? {
        switch self {
        case .metadataReleasedNoSource:
            nil
        case .sourceAvailable(let bestReleaseID, _, _):
            bestReleaseID
        }
    }

    public var qualityLabel: String? {
        switch self {
        case .metadataReleasedNoSource:
            nil
        case .sourceAvailable(_, let qualityLabel, _):
            qualityLabel
        }
    }

    public var sourceName: String? {
        switch self {
        case .metadataReleasedNoSource:
            nil
        case .sourceAvailable(_, _, let sourceName):
            sourceName
        }
    }

    public var userFacingSourceText: String {
        switch self {
        case .metadataReleasedNoSource:
            "Waiting for sources"
        case .sourceAvailable(_, _, let sourceName):
            sourceName
        }
    }

    var qualityRank: Int {
        switch qualityLabel?.lowercased() {
        case "2160p", "4k", "uhd":
            4
        case "1080p", "full hd", "fhd":
            3
        case "720p", "hd":
            2
        case "sd":
            1
        default:
            0
        }
    }
}

public struct NewSeriesEpisode: Identifiable, Equatable, Sendable {
    public let seriesID: String
    public let seriesTitle: String
    public let episode: SeriesEpisode
    public let availability: SeriesEpisodeSourceAvailability
    public let releasedAt: Date?

    public var id: String {
        "\(seriesID):\(episode.id)"
    }

    public var metadataBadgeText: String {
        "New Episode Available"
    }

    public var sourceBadgeText: String {
        availability.userFacingSourceText
    }

    public init(
        seriesID: String,
        seriesTitle: String,
        episode: SeriesEpisode,
        availability: SeriesEpisodeSourceAvailability,
        releasedAt: Date?
    ) {
        self.seriesID = seriesID
        self.seriesTitle = seriesTitle
        self.episode = episode
        self.availability = availability
        self.releasedAt = releasedAt
    }
}

public enum SeriesTrackingNotificationKind: Equatable, Sendable {
    case newEpisodeAvailable
    case newReleaseFound
    case betterReleaseFound
}

public struct SeriesTrackingNotification: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: SeriesTrackingNotificationKind
    public let episode: NewSeriesEpisode

    public init(kind: SeriesTrackingNotificationKind, episode: NewSeriesEpisode) {
        self.kind = kind
        self.episode = episode
        id = Self.notificationID(kind: kind, episode: episode)
    }

    static func notificationID(kind: SeriesTrackingNotificationKind, episode: NewSeriesEpisode) -> String {
        switch kind {
        case .newEpisodeAvailable:
            "new-episode:\(episode.seriesID):\(episode.episode.id)"
        case .newReleaseFound:
            "new-release:\(episode.seriesID):\(episode.episode.id):\(episode.availability.bestReleaseID ?? "none")"
        case .betterReleaseFound:
            "better-release:\(episode.seriesID):\(episode.episode.id):\(episode.availability.bestReleaseID ?? "none")"
        }
    }
}

public struct SeriesTrackingDigest: Equatable, Sendable {
    public static let empty = SeriesTrackingDigest(items: [])

    public let items: [SeriesTrackingNotification]

    public init(items: [SeriesTrackingNotification]) {
        self.items = items
    }
}

public protocol NewEpisodesProviderProtocol {
    func newEpisodes() async -> [NewSeriesEpisode]
    func notificationDigest(for episodes: [NewSeriesEpisode]) async -> SeriesTrackingDigest
}

public extension NewEpisodesProviderProtocol {
    func notificationDigest(for episodes: [NewSeriesEpisode]) async -> SeriesTrackingDigest {
        _ = episodes
        return .empty
    }
}

public protocol SeriesTrackingStoreProtocol: Sendable {
    func trackedSeriesIDs() async -> Set<String>
    func isTracked(seriesID: String) async -> Bool
    func setTracked(_ tracked: Bool, seriesID: String) async
}

public actor UserDefaultsSeriesTrackingStore: SeriesTrackingStoreProtocol {
    private let userDefaults: UserDefaults
    private let key = "streamly.series.tracked.ids"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func trackedSeriesIDs() async -> Set<String> {
        Set(userDefaults.stringArray(forKey: key) ?? [])
    }

    public func isTracked(seriesID: String) async -> Bool {
        await trackedSeriesIDs().contains(seriesID)
    }

    public func setTracked(_ tracked: Bool, seriesID: String) async {
        var ids = await trackedSeriesIDs()
        if tracked {
            ids.insert(seriesID)
        } else {
            ids.remove(seriesID)
        }
        userDefaults.set(Array(ids).sorted(), forKey: key)
    }
}

public actor InMemorySeriesTrackingStore: SeriesTrackingStoreProtocol {
    private var ids: Set<String>

    public init(ids: Set<String> = []) {
        self.ids = ids
    }

    public func trackedSeriesIDs() async -> Set<String> {
        ids
    }

    public func isTracked(seriesID: String) async -> Bool {
        ids.contains(seriesID)
    }

    public func setTracked(_ tracked: Bool, seriesID: String) async {
        if tracked {
            ids.insert(seriesID)
        } else {
            ids.remove(seriesID)
        }
    }
}

public struct SeriesTrackedReleaseSnapshot: Codable, Equatable, Sendable {
    public let bestReleaseID: String
    public let qualityRank: Int

    public init(bestReleaseID: String, qualityRank: Int) {
        self.bestReleaseID = bestReleaseID
        self.qualityRank = qualityRank
    }
}

public protocol SeriesTrackingNotificationStoreProtocol: Sendable {
    func hasSeenNotification(id: String) async -> Bool
    func markNotificationSeen(id: String) async
    func releaseSnapshot(for episodeKey: String) async -> SeriesTrackedReleaseSnapshot?
    func setReleaseSnapshot(_ snapshot: SeriesTrackedReleaseSnapshot, episodeKey: String) async
}

public actor UserDefaultsSeriesTrackingNotificationStore: SeriesTrackingNotificationStoreProtocol {
    private let userDefaults: UserDefaults
    private let seenKey = "streamly.series.tracking.seenNotificationIDs"
    private let snapshotKey = "streamly.series.tracking.releaseSnapshots"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func hasSeenNotification(id: String) async -> Bool {
        seenIDs().contains(id)
    }

    public func markNotificationSeen(id: String) async {
        var ids = seenIDs()
        ids.insert(id)
        userDefaults.set(Array(ids).sorted(), forKey: seenKey)
    }

    public func releaseSnapshot(for episodeKey: String) async -> SeriesTrackedReleaseSnapshot? {
        snapshots()[episodeKey]
    }

    public func setReleaseSnapshot(_ snapshot: SeriesTrackedReleaseSnapshot, episodeKey: String) async {
        var values = snapshots()
        values[episodeKey] = snapshot
        if let data = try? JSONEncoder().encode(values) {
            userDefaults.set(data, forKey: snapshotKey)
        }
    }

    private func seenIDs() -> Set<String> {
        Set(userDefaults.stringArray(forKey: seenKey) ?? [])
    }

    private func snapshots() -> [String: SeriesTrackedReleaseSnapshot] {
        guard let data = userDefaults.data(forKey: snapshotKey),
              let values = try? JSONDecoder().decode([String: SeriesTrackedReleaseSnapshot].self, from: data) else {
            return [:]
        }
        return values
    }
}

public actor InMemorySeriesTrackingNotificationStore: SeriesTrackingNotificationStoreProtocol {
    private var seenIDs: Set<String>
    private var snapshots: [String: SeriesTrackedReleaseSnapshot]

    public init(
        seenIDs: Set<String> = [],
        snapshots: [String: SeriesTrackedReleaseSnapshot] = [:]
    ) {
        self.seenIDs = seenIDs
        self.snapshots = snapshots
    }

    public func hasSeenNotification(id: String) async -> Bool {
        seenIDs.contains(id)
    }

    public func markNotificationSeen(id: String) async {
        seenIDs.insert(id)
    }

    public func releaseSnapshot(for episodeKey: String) async -> SeriesTrackedReleaseSnapshot? {
        snapshots[episodeKey]
    }

    public func setReleaseSnapshot(_ snapshot: SeriesTrackedReleaseSnapshot, episodeKey: String) async {
        snapshots[episodeKey] = snapshot
    }
}

public struct SeriesTrackingEpisodeProvider: NewEpisodesProviderProtocol {
    private let libraryRepository: any LibraryRepositoryProtocol
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private let seriesDetailProvider: any SeriesDetailProviderProtocol
    private let trackingStore: any SeriesTrackingStoreProtocol
    private let notificationStore: any SeriesTrackingNotificationStoreProtocol
    private let now: @Sendable () -> Date

    public init(
        libraryRepository: any LibraryRepositoryProtocol,
        progressRepository: (any PlaybackProgressRepositoryProtocol)?,
        seriesDetailProvider: any SeriesDetailProviderProtocol,
        trackingStore: any SeriesTrackingStoreProtocol = UserDefaultsSeriesTrackingStore(),
        notificationStore: any SeriesTrackingNotificationStoreProtocol = UserDefaultsSeriesTrackingNotificationStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.libraryRepository = libraryRepository
        self.progressRepository = progressRepository
        self.seriesDetailProvider = seriesDetailProvider
        self.trackingStore = trackingStore
        self.notificationStore = notificationStore
        self.now = now
    }

    public func newEpisodes() async -> [NewSeriesEpisode] {
        let progressRecords = (try? await progressRepository?.continueWatching(includeCompleted: true)) ?? []
        let progressByMediaID = Dictionary(grouping: progressRecords, by: \.mediaID)
        let trackedItems = await trackedSeriesItems()
        var episodes: [NewSeriesEpisode] = []

        for item in trackedItems.prefix(12) {
            guard let response = try? await seriesDetailProvider.seriesDetail(id: item.id) else { continue }
            let progressByEpisodeID = progressByMediaID[item.id]?.reduce(into: response.progressByEpisodeID) { partial, progress in
                if let episodeID = progress.episodeID {
                    partial[episodeID] = progress
                }
            } ?? response.progressByEpisodeID

            guard let episode = latestNewEpisode(in: response.seasons, progressByEpisodeID: progressByEpisodeID) else {
                continue
            }

            let releases = (try? await seriesDetailProvider.episodeReleases(seriesID: item.id, episodeID: episode.id)) ?? []
            let rankedReleases = ReleaseRankingEngine().rank(releases.map(\.release))
            let availability: SeriesEpisodeSourceAvailability
            if let best = rankedReleases.first?.release {
                availability = .sourceAvailable(
                    bestReleaseID: best.id,
                    qualityLabel: best.qualityLabel,
                    sourceName: best.sourceName
                )
            } else {
                availability = .metadataReleasedNoSource
            }

            episodes.append(NewSeriesEpisode(
                seriesID: response.series.id,
                seriesTitle: response.series.title,
                episode: episode,
                availability: availability,
                releasedAt: episode.airDate
            ))
        }

        return episodes.sorted { lhs, rhs in
            (lhs.releasedAt ?? .distantPast) > (rhs.releasedAt ?? .distantPast)
        }
    }

    public func notificationDigest(for episodes: [NewSeriesEpisode]) async -> SeriesTrackingDigest {
        var notifications: [SeriesTrackingNotification] = []

        for episode in episodes {
            let newEpisode = SeriesTrackingNotification(kind: .newEpisodeAvailable, episode: episode)
            if await notificationStore.hasSeenNotification(id: newEpisode.id) == false {
                notifications.append(newEpisode)
                await notificationStore.markNotificationSeen(id: newEpisode.id)
            }

            guard let bestReleaseID = episode.availability.bestReleaseID else { continue }
            let episodeKey = "\(episode.seriesID):\(episode.episode.id)"
            let currentSnapshot = SeriesTrackedReleaseSnapshot(
                bestReleaseID: bestReleaseID,
                qualityRank: episode.availability.qualityRank
            )

            if let previousSnapshot = await notificationStore.releaseSnapshot(for: episodeKey) {
                if currentSnapshot.qualityRank > previousSnapshot.qualityRank || (
                    currentSnapshot.qualityRank == previousSnapshot.qualityRank
                        && currentSnapshot.bestReleaseID != previousSnapshot.bestReleaseID
                ) {
                    let improved = SeriesTrackingNotification(kind: .betterReleaseFound, episode: episode)
                    if await notificationStore.hasSeenNotification(id: improved.id) == false {
                        notifications.append(improved)
                        await notificationStore.markNotificationSeen(id: improved.id)
                    }
                }
            } else {
                let found = SeriesTrackingNotification(kind: .newReleaseFound, episode: episode)
                if await notificationStore.hasSeenNotification(id: found.id) == false {
                    notifications.append(found)
                    await notificationStore.markNotificationSeen(id: found.id)
                }
            }

            await notificationStore.setReleaseSnapshot(currentSnapshot, episodeKey: episodeKey)
        }

        return SeriesTrackingDigest(items: notifications)
    }

    private func trackedSeriesItems() async -> [MediaItem] {
        var mediaByID: [String: MediaItem] = [:]
        let libraryItems = (try? await libraryRepository.items()) ?? []
        for item in libraryItems where item.kind == .series {
            mediaByID[item.id] = item
        }

        let lists = (try? await libraryRepository.lists()) ?? []
        let watchlist = lists.first { $0.isDefault || $0.name.localizedCaseInsensitiveCompare("Хочу посмотреть") == .orderedSame }
        if let watchlist,
           let listItems = try? await libraryRepository.items(in: watchlist.id) {
            for item in listItems where item.kind == .series {
                mediaByID[item.id] = item
            }
        }

        for id in await trackingStore.trackedSeriesIDs() where mediaByID[id] == nil {
            mediaByID[id] = MediaItem(id: id, title: id, kind: .series, overview: "", releaseYear: nil, posterPath: nil)
        }

        return mediaByID.values.sorted { $0.displayTitle < $1.displayTitle }
    }

    private func latestNewEpisode(
        in seasons: [SeriesSeason],
        progressByEpisodeID: [String: PlaybackProgress]
    ) -> SeriesEpisode? {
        seasons
            .flatMap(\.episodes)
            .filter { hasMetadataReleased($0) }
            .filter { progressByEpisodeID[$0.id]?.completed != true }
            .sorted {
                if ($0.airDate ?? .distantPast) != ($1.airDate ?? .distantPast) {
                    return ($0.airDate ?? .distantPast) > ($1.airDate ?? .distantPast)
                }
                if $0.seasonNumber != $1.seasonNumber {
                    return $0.seasonNumber > $1.seasonNumber
                }
                return $0.episodeNumber > $1.episodeNumber
            }
            .first
    }

    private func hasMetadataReleased(_ episode: SeriesEpisode) -> Bool {
        guard let airDate = episode.airDate else { return true }
        return airDate <= now()
    }
}
