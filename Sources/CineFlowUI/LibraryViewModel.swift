import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum LibraryViewState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum LibrarySection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case favorites
    case all
    case movies
    case series
    case lists
    case watched
    case ratings
    case stats

    public var id: String { rawValue }
}

public enum LibraryKindFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case movies
    case series

    public var id: String { rawValue }
}

public enum LibraryWatchStateFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case watched
    case unwatched
    case inProgress

    public var id: String { rawValue }
}

public enum LibraryAddedDateFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case last7Days
    case last30Days

    public var id: String { rawValue }
}

public enum LibraryQualityFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case hd
    case fullHD
    case ultraHD
    case hdr

    public var id: String { rawValue }
}

public enum LibrarySortOrder: String, CaseIterable, Identifiable, Equatable, Sendable {
    case recentlyAdded
    case recentlyWatched
    case titleAscending
    case yearDescending
    case ratingDescending
    case progressDescending

    public var id: String { rawValue }
}

public enum LibrarySavedView: String, CaseIterable, Identifiable, Equatable, Sendable {
    case movies
    case series
    case unwatched
    case inProgress
    case favorites

    public var id: String { rawValue }
}

public enum LibraryBulkAction: Equatable, Sendable {
    case markWatched
    case remove
    case addToList(String)
    case clearProgress

    var requiresConfirmation: Bool {
        switch self {
        case .remove, .clearProgress:
            true
        case .markWatched, .addToList:
            false
        }
    }
}

public struct LibraryBulkConfirmation: Equatable, Sendable {
    public let action: LibraryBulkAction
    public let itemCount: Int
}

public struct LibraryCardQuickActionState: Equatable, Sendable {
    public var canWatch: Bool
    public var canOpenDetails: Bool
    public var canAddToLibrary: Bool
    public var canAddToWatchlist: Bool
    public var canAddToList: Bool
    public var canRate: Bool
    public var canHide: Bool
    public var canFixMetadata: Bool
    public var canFindBestRelease: Bool
    public var canClearProgress: Bool
    public var clearProgressRequiresConfirmation: Bool

    public init(
        canWatch: Bool = true,
        canOpenDetails: Bool = true,
        canAddToLibrary: Bool = false,
        canAddToWatchlist: Bool = true,
        canAddToList: Bool = true,
        canRate: Bool = true,
        canHide: Bool = false,
        canFixMetadata: Bool = true,
        canFindBestRelease: Bool = true,
        canClearProgress: Bool = false,
        clearProgressRequiresConfirmation: Bool = true
    ) {
        self.canWatch = canWatch
        self.canOpenDetails = canOpenDetails
        self.canAddToLibrary = canAddToLibrary
        self.canAddToWatchlist = canAddToWatchlist
        self.canAddToList = canAddToList
        self.canRate = canRate
        self.canHide = canHide
        self.canFixMetadata = canFixMetadata
        self.canFindBestRelease = canFindBestRelease
        self.canClearProgress = canClearProgress
        self.clearProgressRequiresConfirmation = clearProgressRequiresConfirmation
    }

    public var menuAvailability: CFMediaCardMenuAvailability {
        CFMediaCardMenuAvailability(
            canWatch: canWatch,
            canOpenDetails: canOpenDetails,
            canAddToLibrary: canAddToLibrary,
            canAddToWatchlist: canAddToWatchlist,
            canAddToList: canAddToList,
            canRate: canRate,
            canHide: canHide,
            canFixMetadata: canFixMetadata,
            canFindBestRelease: canFindBestRelease,
            canClearProgress: canClearProgress,
            canTuneRecommendations: false
        )
    }
}

public struct LibraryAdvancedFilters: Equatable, Sendable {
    public var genre: String?
    public var yearRange: ClosedRange<Int>?
    public var minimumRating: Double?
    public var watchState: LibraryWatchStateFilter
    public var addedDate: LibraryAddedDateFilter
    public var quality: LibraryQualityFilter

    public init(
        genre: String? = nil,
        yearRange: ClosedRange<Int>? = nil,
        minimumRating: Double? = nil,
        watchState: LibraryWatchStateFilter = .all,
        addedDate: LibraryAddedDateFilter = .all,
        quality: LibraryQualityFilter = .all
    ) {
        self.genre = genre
        self.yearRange = yearRange
        self.minimumRating = minimumRating
        self.watchState = watchState
        self.addedDate = addedDate
        self.quality = quality
    }
}

public struct LibrarySummary: Equatable, Sendable {
    public var favoriteCount: Int
    public var movieCount: Int
    public var seriesCount: Int
    public var listCount: Int
    public var watchedCount: Int
    public var ratingCount: Int

    public static let empty = LibrarySummary(
        favoriteCount: 0,
        movieCount: 0,
        seriesCount: 0,
        listCount: 0,
        watchedCount: 0,
        ratingCount: 0
    )
}

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public private(set) var state: LibraryViewState = .loading
    @Published public private(set) var items: [MediaItem] = []
    @Published public private(set) var favorites: [MediaItem] = []
    @Published public private(set) var watchedItems: [WatchedMediaItem] = []
    @Published public private(set) var ratedItems: [RatedMediaItem] = []
    @Published public private(set) var lists: [UserList] = []
    @Published public private(set) var selectedSection: LibrarySection = .favorites
    @Published public private(set) var activeSavedView: LibrarySavedView?
    @Published public private(set) var selectedKindFilter: LibraryKindFilter = .all
    @Published public private(set) var filters = LibraryAdvancedFilters()
    @Published public private(set) var sortOrder: LibrarySortOrder = .recentlyAdded
    @Published public private(set) var selectedListID: String?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var visibleItems: [MediaItem] = []
    @Published public private(set) var selectedItemIDs: Set<String> = []
    @Published public private(set) var pendingBulkConfirmation: LibraryBulkConfirmation?
    @Published public private(set) var summary: LibrarySummary = .empty
    @Published public private(set) var personalStats: PersonalWatchStats = .empty
    @Published public var searchQuery = ""

    private let repository: any LibraryRepositoryProtocol
    private let personalStatsService: (any PersonalStatsServiceProtocol)?
    private let metadataService: (any MetadataServiceProtocol)?
    private var listItemsByID: [String: [MediaItem]] = [:]
    private var favoriteIDs: Set<String> = []
    private var ratingsByID: [String: Int] = [:]
    private var progressByID: [String: Double] = [:]
    private var watchedAtByID: [String: Date] = [:]
    private var addedAtByID: [String: Date] = [:]
    private var metadataRepairAttemptedIDs: Set<String> = []
    private let metadataRepairBatchLimit = 8

    public init(
        repository: any LibraryRepositoryProtocol,
        personalStatsService: (any PersonalStatsServiceProtocol)? = nil,
        metadataService: (any MetadataServiceProtocol)? = nil
    ) {
        self.repository = repository
        self.personalStatsService = personalStatsService
        self.metadataService = metadataService
    }

    public var isCurrentSectionEmpty: Bool {
        visibleItems.isEmpty
    }

    public var hasSelection: Bool {
        !selectedItemIDs.isEmpty
    }

    public var selectedItems: [MediaItem] {
        items.filter { selectedItemIDs.contains($0.id) }
    }

    public var availableGenres: [String] {
        let genres = items.flatMap { $0.metadata?.genres ?? [] }
        return Array(Set(genres)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public var prefetchArtworkURLs: [URL] {
        Array(visibleItems.lazy.compactMap(\.bestPosterURL).prefix(48))
    }

    public var artworkPrefetchKey: String {
        prefetchArtworkURLs.map(\.absoluteString).joined(separator: "|")
    }

    public func load() async {
        state = .loading
        errorMessage = nil

        do {
            async let libraryItems = repository.items()
            async let libraryEntries = repository.libraryEntries()
            async let favoriteItems = repository.favorites()
            async let watched = repository.watchedItems()
            async let rated = repository.ratedItems()
            async let userLists = repository.lists()
            async let stats = personalStatsService?.personalStats(referenceDate: Date())

            items = try await libraryItems
            let entries = try await libraryEntries
            favorites = try await favoriteItems
            watchedItems = try await watched
            ratedItems = try await rated
            lists = try await userLists
            personalStats = (try await stats) ?? .empty
            addedAtByID = Dictionary(entries.map { ($0.mediaID, $0.addedAt) }, uniquingKeysWith: max)

            var loadedListItems: [String: [MediaItem]] = [:]
            for list in lists {
                loadedListItems[list.id] = try await repository.items(in: list.id)
            }
            if try await repairPosterlessIMDbItems(listItems: loadedListItems) {
                items = try await repository.items()
                favorites = try await repository.favorites()
                watchedItems = try await repository.watchedItems()
                ratedItems = try await repository.ratedItems()
                loadedListItems = [:]
                for list in lists {
                    loadedListItems[list.id] = try await repository.items(in: list.id)
                }
            }
            listItemsByID = loadedListItems
            rebuildLookupTables()
            rebuildSummary()
            selectedListID = selectedListID ?? lists.first?.id
            rebuildVisibleItems()
            state = items.isEmpty && favorites.isEmpty && lists.isEmpty && watchedItems.isEmpty && ratedItems.isEmpty ? .empty : .loaded
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .database)
            errorMessage = cineFlowError.userMessage
            visibleItems = []
            summary = .empty
            state = .failed(cineFlowError.userMessage)
        }
    }

    public func selectSection(_ section: LibrarySection) {
        activeSavedView = nil
        selectedSection = section
        if section == .lists, selectedListID == nil {
            selectedListID = lists.first?.id
        }
        rebuildVisibleItems()
    }

    public func updateSearchQuery(_ query: String) {
        activeSavedView = nil
        searchQuery = query
        rebuildVisibleItems()
    }

    public func setKindFilter(_ filter: LibraryKindFilter) {
        activeSavedView = nil
        selectedKindFilter = filter
        rebuildVisibleItems()
    }

    public func setGenreFilter(_ genre: String?) {
        activeSavedView = nil
        let trimmed = genre?.trimmingCharacters(in: .whitespacesAndNewlines)
        filters.genre = (trimmed?.isEmpty == false) ? trimmed : nil
        rebuildVisibleItems()
    }

    public func setYearRange(_ range: ClosedRange<Int>?) {
        activeSavedView = nil
        filters.yearRange = range
        rebuildVisibleItems()
    }

    public func setMinimumRating(_ rating: Double?) {
        activeSavedView = nil
        filters.minimumRating = rating
        rebuildVisibleItems()
    }

    public func setWatchStateFilter(_ filter: LibraryWatchStateFilter) {
        activeSavedView = nil
        filters.watchState = filter
        rebuildVisibleItems()
    }

    public func setAddedDateFilter(_ filter: LibraryAddedDateFilter) {
        activeSavedView = nil
        filters.addedDate = filter
        rebuildVisibleItems()
    }

    public func setQualityFilter(_ filter: LibraryQualityFilter) {
        activeSavedView = nil
        filters.quality = filter
        rebuildVisibleItems()
    }

    public func resetFilters() {
        activeSavedView = nil
        selectedKindFilter = .all
        filters = LibraryAdvancedFilters()
        searchQuery = ""
        rebuildVisibleItems()
    }

    public func setSortOrder(_ order: LibrarySortOrder) {
        sortOrder = order
        rebuildVisibleItems()
    }

    public func applySavedView(_ view: LibrarySavedView) {
        resetFilters()
        activeSavedView = view
        switch view {
        case .movies:
            selectedSection = .all
            selectedKindFilter = .movies
        case .series:
            selectedSection = .all
            selectedKindFilter = .series
        case .unwatched:
            selectedSection = .all
            filters.watchState = .unwatched
        case .inProgress:
            selectedSection = .all
            filters.watchState = .inProgress
            sortOrder = .progressDescending
        case .favorites:
            selectedSection = .favorites
        }
        rebuildVisibleItems()
    }

    public func selectList(_ list: UserList) {
        activeSavedView = nil
        selectedListID = list.id
        selectedSection = .lists
        rebuildVisibleItems()
    }

    public func add(_ item: MediaItem) async throws {
        try await repository.add(item)
        await load()
    }

    public func removeFromLibrary(mediaID: String) async throws {
        try await repository.remove(mediaID: mediaID)
        await load()
    }

    public func clearProgress(mediaID: String) async throws {
        try await repository.removeFromHistory(mediaID: mediaID)
        await load()
    }

    public func addFavorite(_ item: MediaItem) async throws {
        try await repository.addFavorite(item)
        await load()
    }

    public func removeFavorite(mediaID: String) async throws {
        try await repository.removeFavorite(mediaID: mediaID)
        await load()
    }

    public func markWatched(_ item: MediaItem) async throws {
        try await repository.markWatched(item, positionSeconds: 0)
        await load()
    }

    public func rate(_ item: MediaItem, rating: Int) async throws {
        try await repository.setRating(item, rating: rating)
        await load()
    }

    public func createList(named name: String) async throws -> UserList {
        let list = try await repository.createList(name: name)
        await load()
        selectedListID = list.id
        return list
    }

    public func defaultList() async throws -> UserList {
        let list = try await repository.defaultList()
        await load()
        selectedListID = list.id
        return list
    }

    public func add(_ item: MediaItem, to list: UserList) async throws {
        try await repository.add(item, to: list.id)
        await load()
        selectedListID = list.id
    }

    public func selectItems(_ mediaIDs: [String]) {
        selectedItemIDs = Set(mediaIDs)
    }

    public func toggleSelection(mediaID: String) {
        if selectedItemIDs.contains(mediaID) {
            selectedItemIDs.remove(mediaID)
        } else {
            selectedItemIDs.insert(mediaID)
        }
    }

    public func selectVisibleItems() {
        selectedItemIDs = Set(visibleItems.map(\.id))
    }

    public func clearSelection() {
        selectedItemIDs.removeAll()
    }

    public func performBulkAction(_ action: LibraryBulkAction) async throws {
        let count = selectedItemIDs.count
        guard count > 0 else { return }
        if action.requiresConfirmation {
            pendingBulkConfirmation = LibraryBulkConfirmation(action: action, itemCount: count)
            return
        }
        try await applyBulkAction(action)
    }

    public func confirmPendingBulkAction() async throws {
        guard let confirmation = pendingBulkConfirmation else { return }
        pendingBulkConfirmation = nil
        try await applyBulkAction(confirmation.action)
    }

    public func cancelPendingBulkAction() async throws {
        pendingBulkConfirmation = nil
    }

    public func rating(for mediaID: String) -> Int? {
        ratingsByID[mediaID]
    }

    public func isFavorite(_ mediaID: String) -> Bool {
        favoriteIDs.contains(mediaID)
    }

    public func quickActionState(for item: MediaItem) -> LibraryCardQuickActionState {
        LibraryCardQuickActionState(
            canAddToLibrary: !items.contains { $0.id == item.id },
            canFindBestRelease: !item.rankedReleases.isEmpty,
            canClearProgress: progressByID[item.id] != nil || watchedAtByID[item.id] != nil
        )
    }

    public func cardModel(for item: MediaItem) -> CFMediaCardModel {
        let ratingSuffix = rating(for: item.id).map { " · \($0)/10" } ?? ""
        return CFMediaCardModel(
            id: item.id,
            title: item.displayTitle,
            metadata: "\(item.displayYear) · \(kindTitle(for: item.kind))\(ratingSuffix)",
            badge: isFavorite(item.id) ? "★" : nil,
            progress: progress(for: item.id),
            accentIndex: abs(item.id.hashValue),
            artworkURL: item.bestPosterURL,
            genres: item.metadata?.genres ?? []
        )
    }

    private func baseItems(for section: LibrarySection) -> [MediaItem] {
        switch section {
        case .favorites:
            return favorites
        case .all:
            return items
        case .movies:
            return items.filter { $0.kind == .movie }
        case .series:
            return items.filter { $0.kind == .series }
        case .lists:
            guard let selectedListID else { return [] }
            return listItemsByID[selectedListID] ?? []
        case .watched:
            return watchedItems.map(\.item)
        case .ratings:
            return ratedItems.map(\.item)
        case .stats:
            return []
        }
    }

    private func rebuildVisibleItems() {
        visibleItems = sort(filter(baseItems(for: selectedSection)))
    }

    private func rebuildLookupTables() {
        favoriteIDs = Set(favorites.map(\.id))
        ratingsByID = Dictionary(ratedItems.map { ($0.item.id, $0.rating) }, uniquingKeysWith: { _, latest in latest })
        watchedAtByID = Dictionary(watchedItems.map { ($0.item.id, $0.watchedAt) }, uniquingKeysWith: max)
        progressByID = Dictionary(
            watchedItems.compactMap { watchedItem in
                guard watchedItem.positionSeconds > 0 else { return nil }
                return (watchedItem.item.id, min(watchedItem.positionSeconds / 7_200, 1))
            },
            uniquingKeysWith: max
        )
    }

    private func rebuildSummary() {
        var movieCount = 0
        var seriesCount = 0
        for item in items {
            switch item.kind {
            case .movie:
                movieCount += 1
            case .series:
                seriesCount += 1
            }
        }

        summary = LibrarySummary(
            favoriteCount: favorites.count,
            movieCount: movieCount,
            seriesCount: seriesCount,
            listCount: lists.count,
            watchedCount: watchedItems.count,
            ratingCount: ratedItems.count
        )
    }

    private func repairPosterlessIMDbItems(listItems: [String: [MediaItem]]) async throws -> Bool {
        guard let metadataService else { return false }
        let candidates = posterlessIMDbRepairCandidates(listItems: listItems)
        guard !candidates.isEmpty else { return false }

        var repairedAny = false
        for item in candidates {
            metadataRepairAttemptedIDs.insert(item.id)
            do {
                let refreshedItem: MediaItem
                switch imdbRepairTarget(for: item) {
                case .movie(let imdbID):
                    refreshedItem = try await metadataService.movieDetail(imdbID: imdbID).mediaItem
                case .series(let imdbID):
                    refreshedItem = try await metadataService.seriesDetail(imdbID: imdbID).mediaItem
                case .none:
                    continue
                }
                guard refreshedItem.bestPosterURL != nil || refreshedItem.bestBackdropURL != nil else {
                    continue
                }
                try await repository.refreshMediaItemMetadata(refreshedItem)
                repairedAny = true
            } catch {
                continue
            }
        }
        return repairedAny
    }

    private func posterlessIMDbRepairCandidates(listItems: [String: [MediaItem]]) -> [MediaItem] {
        var result: [MediaItem] = []
        var seenIDs: Set<String> = []
        let candidates = items
            + favorites
            + watchedItems.map(\.item)
            + ratedItems.map(\.item)
            + listItems.values.flatMap { $0 }

        for item in candidates {
            guard item.bestPosterURL == nil,
                  imdbRepairTarget(for: item) != nil,
                  !metadataRepairAttemptedIDs.contains(item.id),
                  !seenIDs.contains(item.id)
            else { continue }
            seenIDs.insert(item.id)
            result.append(item)
            if result.count >= metadataRepairBatchLimit {
                break
            }
        }
        return result
    }

    private enum IMDbRepairTarget: Equatable {
        case movie(String)
        case series(String)
    }

    private func imdbRepairTarget(for item: MediaItem) -> IMDbRepairTarget? {
        let parts = item.id.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[0] == "imdb", parts[2].hasPrefix("tt") else { return nil }
        switch (parts[1], item.kind) {
        case ("movie", .movie):
            return .movie(parts[2])
        case ("series", .series), ("tv", .series):
            return .series(parts[2])
        default:
            return nil
        }
    }

    private func filter(_ baseItems: [MediaItem]) -> [MediaItem] {
        let kindFiltered = baseItems.filter { item in
            switch selectedKindFilter {
            case .all:
                true
            case .movies:
                item.kind == .movie
            case .series:
                item.kind == .series
            }
        }

        let advancedFiltered = kindFiltered.filter { item in
            passesAdvancedFilters(item)
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return advancedFiltered }
        return advancedFiltered.filter { item in
            item.displayTitle.lowercased().contains(query)
                || item.overview.lowercased().contains(query)
                || item.displayYear.lowercased().contains(query)
        }
    }

    private func sort(_ baseItems: [MediaItem]) -> [MediaItem] {
        switch sortOrder {
        case .recentlyAdded:
            guard !addedAtByID.isEmpty else { return baseItems }
            return baseItems.sorted { (addedAtByID[$0.id] ?? .distantPast) > (addedAtByID[$1.id] ?? .distantPast) }
        case .recentlyWatched:
            return baseItems.sorted { (watchedAtByID[$0.id] ?? .distantPast) > (watchedAtByID[$1.id] ?? .distantPast) }
        case .titleAscending:
            return baseItems.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .yearDescending:
            return baseItems.sorted { ($0.releaseYear ?? 0) > ($1.releaseYear ?? 0) }
        case .ratingDescending:
            return baseItems.sorted { (ratingsByID[$0.id] ?? 0) > (ratingsByID[$1.id] ?? 0) }
        case .progressDescending:
            return baseItems.sorted { (progressByID[$0.id] ?? 0) > (progressByID[$1.id] ?? 0) }
        }
    }

    private func passesAdvancedFilters(_ item: MediaItem) -> Bool {
        if let genre = filters.genre?.lowercased(),
           !(item.metadata?.genres ?? []).contains(where: { $0.lowercased() == genre }) {
            return false
        }
        if let yearRange = filters.yearRange {
            guard let year = item.metadata?.year ?? item.releaseYear, yearRange.contains(year) else { return false }
        }
        if let minimumRating = filters.minimumRating {
            let userRating = ratingsByID[item.id].map(Double.init)
            let metadataRating = item.metadata?.rating
            guard max(userRating ?? 0, metadataRating ?? 0) >= minimumRating else { return false }
        }
        switch filters.watchState {
        case .all:
            break
        case .watched:
            guard watchedAtByID[item.id] != nil else { return false }
        case .unwatched:
            guard watchedAtByID[item.id] == nil else { return false }
        case .inProgress:
            guard let progress = progressByID[item.id], progress > 0, progress < 0.9 else { return false }
        }
        switch filters.addedDate {
        case .all:
            break
        case .last7Days:
            guard !addedAtByID.isEmpty else { break }
            guard let addedAt = addedAtByID[item.id], addedAt >= Date().addingTimeInterval(-7 * 24 * 60 * 60) else { return false }
        case .last30Days:
            guard !addedAtByID.isEmpty else { break }
            guard let addedAt = addedAtByID[item.id], addedAt >= Date().addingTimeInterval(-30 * 24 * 60 * 60) else { return false }
        }
        switch filters.quality {
        case .all:
            return true
        case .hd:
            return item.rankedReleases.contains { $0.quality >= .hd }
        case .fullHD:
            return item.rankedReleases.contains { $0.quality >= .fullHD }
        case .ultraHD:
            return item.rankedReleases.contains { $0.quality >= .ultraHD }
        case .hdr:
            return item.rankedReleases.contains { $0.hdr != .none && $0.hdr != .unknown }
        }
    }

    private func applyBulkAction(_ action: LibraryBulkAction) async throws {
        let selected = selectedItems
        switch action {
        case .markWatched:
            for item in selected {
                try await repository.markWatched(item, positionSeconds: 7_200)
            }
        case .remove:
            for id in selectedItemIDs {
                try await repository.remove(mediaID: id)
            }
        case .addToList(let listID):
            for item in selected {
                try await repository.add(item, to: listID)
            }
            selectedListID = listID
        case .clearProgress:
            for id in selectedItemIDs {
                try await repository.removeFromHistory(mediaID: id)
            }
        }
        if case .remove = action {
            clearSelection()
        }
        await load()
    }

    private func progress(for mediaID: String) -> Double? {
        progressByID[mediaID]
    }

    private func kindTitle(for kind: MediaKind) -> String {
        switch kind {
        case .movie:
            "Movie"
        case .series:
            "Series"
        }
    }
}
