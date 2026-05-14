import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum UserListsState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public struct WatchlistPresentationItem: Identifiable, Equatable, Sendable {
    public let item: MediaItem
    public let priority: WatchlistPriority
    public let remindLaterAt: Date?
    public let addedAt: Date
    public let badges: [WatchlistBadge]
    public let cleanupSuggested: Bool

    public var id: String { item.id }
}

@MainActor
public final class UserListsViewModel: ObservableObject {
    @Published public private(set) var state: UserListsState = .loading
    @Published public private(set) var lists: [UserList] = []
    @Published public private(set) var selectedListID: String?
    @Published public private(set) var visibleItems: [MediaItem] = []
    @Published public private(set) var watchlistItems: [WatchlistPresentationItem] = []
    @Published public private(set) var cleanupSuggestions: [WatchlistPresentationItem] = []
    @Published public private(set) var watchlistSortOrder: WatchlistSortOrder = .priority
    @Published public private(set) var errorMessage: String?

    private let repository: any LibraryRepositoryProtocol
    private var ratingsByID: [String: Int] = [:]
    private var watchedIDs: Set<String> = []

    public init(repository: any LibraryRepositoryProtocol) {
        self.repository = repository
    }

    public var selectedList: UserList? {
        guard let selectedListID else { return lists.first }
        return lists.first { $0.id == selectedListID } ?? lists.first
    }

    public var prefetchArtworkURLs: [URL] {
        visibleItems.compactMap(\.bestPosterURL)
    }

    public var artworkPrefetchKey: String {
        prefetchArtworkURLs.prefix(24).map(\.absoluteString).joined(separator: "|")
    }

    public func load() async {
        state = .loading
        errorMessage = nil

        do {
            _ = try await repository.defaultList()
            lists = try await repository.lists()
            selectedListID = selectedListID ?? lists.first?.id
            try await refreshVisibleItems()
            state = lists.isEmpty ? .empty : .loaded
        } catch {
            lists = []
            visibleItems = []
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .database)
            errorMessage = cineFlowError.userMessage
            state = .failed(cineFlowError.userMessage)
        }
    }

    public func selectList(_ list: UserList) async {
        selectedListID = list.id
        try? await refreshVisibleItems()
    }

    @discardableResult
    public func createList(name: String, description: String?) async throws -> UserList {
        let list = try await repository.createList(name: name, description: description)
        selectedListID = list.id
        await load()
        selectedListID = list.id
        try await refreshVisibleItems()
        return list
    }

    public func createDefaultList() async {
        do {
            let list = try await repository.defaultList()
            selectedListID = list.id
            await load()
            selectedListID = list.id
            try await refreshVisibleItems()
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .database)
            errorMessage = cineFlowError.userMessage
            state = .failed(cineFlowError.userMessage)
        }
    }

    public func renameSelectedList(name: String, description: String?) async throws {
        guard let selectedList else { return }
        try await repository.renameList(id: selectedList.id, name: name, description: description)
        await load()
        selectedListID = selectedList.id
        try await refreshVisibleItems()
    }

    public func deleteSelectedList() async throws {
        guard let selectedList, !selectedList.isDefault else { return }
        try await repository.deleteList(id: selectedList.id)
        selectedListID = nil
        await load()
    }

    public func add(_ item: MediaItem, to list: UserList) async throws {
        try await repository.add(item, to: list.id)
        selectedListID = list.id
        await load()
        selectedListID = list.id
        try await refreshVisibleItems()
    }

    public func remove(_ mediaID: String) async throws {
        guard let selectedList else { return }
        try await repository.remove(mediaID, from: selectedList.id)
        await load()
        selectedListID = selectedList.id
        try await refreshVisibleItems()
    }

    public func setWatchlistSortOrder(_ order: WatchlistSortOrder) {
        watchlistSortOrder = order
        sortWatchlistItems()
    }

    public func setWatchlistPriority(mediaID: String, priority: WatchlistPriority) async throws {
        guard let selectedList else { return }
        let reminder = watchlistItems.first { $0.item.id == mediaID }?.remindLaterAt
        try await repository.updateWatchlistItem(
            listID: selectedList.id,
            mediaID: mediaID,
            priority: priority,
            remindLaterAt: reminder
        )
        try await refreshVisibleItems()
    }

    public func remindLater(mediaID: String, until date: Date?) async throws {
        guard let selectedList else { return }
        let priority = watchlistItems.first { $0.item.id == mediaID }?.priority ?? .normal
        try await repository.updateWatchlistItem(
            listID: selectedList.id,
            mediaID: mediaID,
            priority: priority,
            remindLaterAt: date
        )
        try await refreshVisibleItems()
    }

    public func acceptCleanupSuggestion(mediaID: String) async throws {
        guard let selectedList else { return }
        try await repository.remove(mediaID, from: selectedList.id)
        try await refreshVisibleItems()
    }

    public func cardModel(for item: MediaItem) -> CFMediaCardModel {
        CFMediaCardModel(
            id: item.id,
            title: item.displayTitle,
            metadata: "\(item.displayYear) · \(item.kind == .movie ? "Movie" : "Series")",
            badge: watchlistItems.first { $0.item.id == item.id }?.badges.first.map(title(for:)),
            accentIndex: abs(item.id.hashValue),
            artworkURL: item.bestPosterURL,
            genres: item.metadata?.genres ?? []
        )
    }

    private func refreshVisibleItems() async throws {
        guard let selectedListID = selectedList?.id else {
            visibleItems = []
            watchlistItems = []
            cleanupSuggestions = []
            return
        }
        async let listItems = repository.items(in: selectedListID)
        async let listMetadata = repository.watchlistItems(in: selectedListID)
        async let rated = repository.ratedItems()
        async let watched = repository.watchedItems()

        let loadedItems = try await listItems
        let loadedMetadata = try await listMetadata
        let loadedRatings = try await rated
        let loadedWatched = try await watched
        visibleItems = loadedItems
        let metadataByID = Dictionary(uniqueKeysWithValues: loadedMetadata.map { ($0.mediaID, $0) })
        ratingsByID = Dictionary(uniqueKeysWithValues: loadedRatings.map { ($0.item.id, $0.rating) })
        watchedIDs = Set(loadedWatched.map(\.item.id))
        watchlistItems = visibleItems.map { item in
            let metadata = metadataByID[item.id] ?? WatchlistItem(
                listID: selectedListID,
                mediaID: item.id,
                initialQuality: item.bestWatchlistReleaseSnapshot.quality,
                initialHDR: item.bestWatchlistReleaseSnapshot.hdr
            )
            return WatchlistPresentationItem(
                item: item,
                priority: metadata.priority,
                remindLaterAt: metadata.remindLaterAt,
                addedAt: metadata.addedAt,
                badges: badges(for: item, metadata: metadata),
                cleanupSuggested: selectedList?.isDefault == true && watchedIDs.contains(item.id)
            )
        }
        sortWatchlistItems()
        cleanupSuggestions = watchlistItems.filter(\.cleanupSuggested)
        visibleItems = watchlistItems.map(\.item)
    }

    private func sortWatchlistItems() {
        watchlistItems = watchlistItems.sorted { lhs, rhs in
            switch watchlistSortOrder {
            case .priority:
                if lhs.priority.rank != rhs.priority.rank {
                    return lhs.priority.rank < rhs.priority.rank
                }
                return lhs.addedAt > rhs.addedAt
            case .addedDate:
                return lhs.addedAt > rhs.addedAt
            case .rating:
                return rating(for: lhs.item) > rating(for: rhs.item)
            case .runtime:
                return runtime(for: lhs.item) > runtime(for: rhs.item)
            case .quality:
                let left = qualityScore(for: lhs.item)
                let right = qualityScore(for: rhs.item)
                if left != right { return left > right }
                return rating(for: lhs.item) > rating(for: rhs.item)
            case .mood:
                let left = moodScore(for: lhs.item)
                let right = moodScore(for: rhs.item)
                if left != right { return left > right }
                return rating(for: lhs.item) > rating(for: rhs.item)
            }
        }
        cleanupSuggestions = watchlistItems.filter(\.cleanupSuggested)
        visibleItems = watchlistItems.map(\.item)
    }

    private func badges(for item: MediaItem, metadata: WatchlistItem) -> [WatchlistBadge] {
        var badges: [WatchlistBadge] = []
        let releases = item.rankedReleases
        let hasPremiumQuality = releases.contains { release in
            release.quality >= .ultraHD || (release.hdr != .none && release.hdr != .unknown)
        }
        if hasPremiumQuality {
            badges.append(.availableIn4KHDR)
        }
        let bestRelease = item.bestWatchlistReleaseSnapshot
        if bestRelease.quality > metadata.initialQuality
            || ((metadata.initialHDR == .none || metadata.initialHDR == .unknown) && bestRelease.hdr != .none && bestRelease.hdr != .unknown) {
            badges.append(.betterReleaseAvailable)
        }
        if releases.contains(where: { release in
            release.audioLanguages.contains(where: Self.isRussianAudioLanguage)
        }) {
            badges.append(.russianAudioAvailable)
        }
        return badges
    }

    private func rating(for item: MediaItem) -> Double {
        max(Double(ratingsByID[item.id] ?? 0), item.metadata?.rating ?? 0)
    }

    private func runtime(for item: MediaItem) -> Int {
        item.metadata?.runtime ?? 0
    }

    private func qualityScore(for item: MediaItem) -> Int {
        guard let release = item.rankedReleases.first else { return 0 }
        let hdrScore = release.hdr == .none || release.hdr == .unknown ? 0 : 1
        return release.quality.rawValue * 10 + hdrScore
    }

    private func moodScore(for item: MediaItem) -> Double {
        let runtimeScore: Double
        switch runtime(for: item) {
        case 1...95:
            runtimeScore = 3
        case 96...130:
            runtimeScore = 2
        default:
            runtimeScore = 1
        }
        return runtimeScore + rating(for: item) / 10
    }

    private func title(for badge: WatchlistBadge) -> String {
        switch badge {
        case .availableIn4KHDR:
            "4K/HDR"
        case .betterReleaseAvailable:
            "Better release"
        case .russianAudioAvailable:
            "RU audio"
        }
    }

    private static func isRussianAudioLanguage(_ language: String) -> Bool {
        let normalized = language.lowercased()
        return normalized == "ru" || normalized == "rus" || normalized.contains("russian")
    }
}

private extension MediaItem {
    var bestWatchlistReleaseSnapshot: (quality: ReleaseQuality, hdr: HDRFormat) {
        guard let release = rankedReleases.first else {
            return (.unknown, .unknown)
        }
        return (release.quality, release.hdr)
    }
}
