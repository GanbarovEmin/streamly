import CineFlowCore
import Foundation

public enum CollectionDetailState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
public final class CollectionDetailViewModel: ObservableObject {
    @Published public private(set) var state: CollectionDetailState = .loading
    @Published public private(set) var collection: MediaCollection?
    @Published public private(set) var watchOrderPlan: FranchiseWatchOrderPlan?

    private let collectionID: String
    private let provider: any CollectionDiscoveryProviderProtocol
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let progressRepository: (any PlaybackProgressRepositoryProtocol)?
    private var progressRecords: [PlaybackProgress] = []
    private var selectedWatchOrderMode: FranchiseWatchOrderMode?

    public init(
        collectionID: String,
        provider: any CollectionDiscoveryProviderProtocol,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil
    ) {
        self.collectionID = collectionID
        self.provider = provider
        self.libraryRepository = libraryRepository
        self.progressRepository = progressRepository
    }

    public var visibleItems: [CollectionMediaItem] {
        collection?.visibleItems ?? []
    }

    public var posterCollageItems: [CollectionMediaItem] {
        Array((collection?.items ?? []).prefix(6))
    }

    public var emptyFallbackTitle: String? {
        guard collection?.items.isEmpty == true else { return nil }
        return "No matching titles yet"
    }

    public var nextFranchiseItem: FranchiseWatchOrderItem? {
        watchOrderPlan?.nextItem
    }

    public func load() async {
        state = .loading
        guard let loaded = await provider.collection(id: collectionID) else {
            collection = nil
            watchOrderPlan = nil
            state = .empty
            return
        }
        progressRecords = (try? await progressRepository?.continueWatching(includeCompleted: true)) ?? []
        collection = loaded
        refreshWatchOrderPlan()
        state = .loaded
    }

    public func setSort(_ sort: CollectionSort) {
        collection?.sort = sort
    }

    public func setFilter(_ filter: CollectionItemFilter) {
        collection?.filter = filter
    }

    public func setWatchOrder(_ mode: FranchiseWatchOrderMode) {
        selectedWatchOrderMode = mode
        refreshWatchOrderPlan()
    }

    public func addToWatchlist(_ item: CollectionMediaItem) async throws {
        guard let libraryRepository else { return }
        let list = try await libraryRepository.defaultList()
        try await libraryRepository.add(item.mediaItem, to: list.id)
    }

    public func addVisibleItemsToWatchlist() async throws {
        guard let libraryRepository else { return }
        let list = try await libraryRepository.defaultList()
        for item in visibleItems {
            try await libraryRepository.add(item.mediaItem, to: list.id)
        }
    }

    private func refreshWatchOrderPlan() {
        guard let collection else {
            watchOrderPlan = nil
            return
        }
        watchOrderPlan = FranchiseWatchOrderResolver.plan(
            for: collection,
            selectedMode: selectedWatchOrderMode,
            progressRecords: progressRecords
        )
    }
}
