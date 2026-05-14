import CineFlowCore
import Foundation

public enum FranchiseWatchOrderMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case release
    case chronological
    case recommended

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .release:
            "Release"
        case .chronological:
            "Chronological"
        case .recommended:
            "Recommended"
        }
    }
}

public struct FranchiseWatchOrderItem: Identifiable, Equatable, Sendable {
    public let collectionItem: CollectionMediaItem
    public let orderNumber: Int
    public let isWatched: Bool

    public var id: String { collectionItem.id }
    public var mediaItem: MediaItem { collectionItem.mediaItem }

    public init(collectionItem: CollectionMediaItem, orderNumber: Int, isWatched: Bool) {
        self.collectionItem = collectionItem
        self.orderNumber = orderNumber
        self.isWatched = isWatched
    }
}

public struct FranchiseWatchOrderPlan: Equatable, Sendable {
    public let collectionID: String
    public let title: String
    public let selectedMode: FranchiseWatchOrderMode
    public let availableModes: [FranchiseWatchOrderMode]
    public let items: [FranchiseWatchOrderItem]

    public var totalCount: Int { items.count }
    public var completedCount: Int { items.filter(\.isWatched).count }
    public var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
    public var progressLabel: String {
        "\(completedCount) of \(totalCount) watched"
    }
    public var nextItem: FranchiseWatchOrderItem? {
        items.first { !$0.isWatched }
    }
}

public enum FranchiseWatchOrderResolver {
    public static func plan(
        for collection: MediaCollection,
        selectedMode: FranchiseWatchOrderMode? = nil,
        progressRecords: [PlaybackProgress]
    ) -> FranchiseWatchOrderPlan? {
        guard let definition = FranchiseWatchOrderDefinition.definitions[collection.id] else {
            return nil
        }

        let mode = selectedMode.flatMap { definition.availableModes.contains($0) ? $0 : nil } ?? definition.defaultMode
        let watchedIDs = Set(progressRecords.filter(isCompleted).map(\.mediaID))
        let orderedItems = collection.items.compactMap { item -> FranchiseWatchOrderItem? in
            guard let entry = definition.entry(for: item.mediaItem),
                  let orderNumber = entry.order(for: mode)
            else { return nil }
            return FranchiseWatchOrderItem(
                collectionItem: item,
                orderNumber: orderNumber,
                isWatched: watchedIDs.contains(item.mediaItem.id)
            )
        }
        .sorted { lhs, rhs in
            if lhs.orderNumber == rhs.orderNumber {
                return lhs.collectionItem.year < rhs.collectionItem.year
            }
            return lhs.orderNumber < rhs.orderNumber
        }

        guard !orderedItems.isEmpty else { return nil }
        return FranchiseWatchOrderPlan(
            collectionID: collection.id,
            title: collection.title,
            selectedMode: mode,
            availableModes: definition.availableModes,
            items: orderedItems
        )
    }

    private static func isCompleted(_ progress: PlaybackProgress) -> Bool {
        progress.completed || progress.progressPercent > 90
    }
}

private struct FranchiseWatchOrderDefinition {
    let collectionID: String
    let defaultMode: FranchiseWatchOrderMode
    let entries: [FranchiseWatchOrderEntry]

    var availableModes: [FranchiseWatchOrderMode] {
        FranchiseWatchOrderMode.allCases.filter { mode in
            entries.contains { $0.order(for: mode) != nil }
        }
    }

    func entry(for item: MediaItem) -> FranchiseWatchOrderEntry? {
        let haystack = [
            item.displayTitle,
            item.metadata?.originalTitle,
            item.metadata?.alternativeTitles.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        return entries.first { entry in
            entry.matchKeys.contains { haystack.contains($0.lowercased()) }
        }
    }

    static let definitions: [String: FranchiseWatchOrderDefinition] = {
        let definitions = [
            FranchiseWatchOrderDefinition(
                collectionID: "automatic-star-wars",
                defaultMode: .recommended,
                entries: [
                    .init(["phantom menace"], release: 4, chronological: 1, recommended: 4),
                    .init(["attack of the clones"], release: 5, chronological: 2, recommended: 5),
                    .init(["revenge of the sith"], release: 6, chronological: 3, recommended: 6),
                    .init(["solo"], release: 10, chronological: 4, recommended: 10),
                    .init(["rogue one"], release: 8, chronological: 5, recommended: 8),
                    .init(["a new hope"], release: 1, chronological: 6, recommended: 1),
                    .init(["empire strikes back"], release: 2, chronological: 7, recommended: 2),
                    .init(["return of the jedi"], release: 3, chronological: 8, recommended: 3),
                    .init(["force awakens"], release: 7, chronological: 9, recommended: 7),
                    .init(["last jedi"], release: 9, chronological: 10, recommended: 9),
                    .init(["rise of skywalker"], release: 11, chronological: 11, recommended: 11)
                ]
            ),
            FranchiseWatchOrderDefinition(
                collectionID: "automatic-lord-of-the-rings",
                defaultMode: .release,
                entries: [
                    .init(["fellowship of the ring"], release: 1, chronological: 4, recommended: 4),
                    .init(["two towers"], release: 2, chronological: 5, recommended: 5),
                    .init(["return of the king"], release: 3, chronological: 6, recommended: 6),
                    .init(["unexpected journey"], release: 4, chronological: 1, recommended: 1),
                    .init(["desolation of smaug"], release: 5, chronological: 2, recommended: 2),
                    .init(["battle of the five armies"], release: 6, chronological: 3, recommended: 3)
                ]
            ),
            FranchiseWatchOrderDefinition(
                collectionID: "automatic-harry-potter",
                defaultMode: .release,
                entries: [
                    .init(["sorcerer's stone", "philosopher's stone"], release: 1, chronological: 1, recommended: 1),
                    .init(["chamber of secrets"], release: 2, chronological: 2, recommended: 2),
                    .init(["prisoner of azkaban"], release: 3, chronological: 3, recommended: 3),
                    .init(["goblet of fire"], release: 4, chronological: 4, recommended: 4),
                    .init(["order of the phoenix"], release: 5, chronological: 5, recommended: 5),
                    .init(["half-blood prince"], release: 6, chronological: 6, recommended: 6),
                    .init(["deathly hallows: part 1"], release: 7, chronological: 7, recommended: 7),
                    .init(["deathly hallows: part 2"], release: 8, chronological: 8, recommended: 8),
                    .init(["fantastic beasts and where to find them"], release: 9, chronological: 9, recommended: 9),
                    .init(["crimes of grindelwald"], release: 10, chronological: 10, recommended: 10),
                    .init(["secrets of dumbledore"], release: 11, chronological: 11, recommended: 11)
                ]
            ),
            FranchiseWatchOrderDefinition(
                collectionID: "automatic-fast-and-furious",
                defaultMode: .release,
                entries: [
                    .init(["the fast and the furious"], release: 1, chronological: 1, recommended: 1),
                    .init(["2 fast 2 furious"], release: 2, chronological: 2, recommended: 2),
                    .init(["tokyo drift"], release: 3, chronological: 6, recommended: 6),
                    .init(["fast & furious"], release: 4, chronological: 3, recommended: 3),
                    .init(["fast five"], release: 5, chronological: 4, recommended: 4),
                    .init(["fast & furious 6"], release: 6, chronological: 5, recommended: 5),
                    .init(["furious 7"], release: 7, chronological: 7, recommended: 7),
                    .init(["fate of the furious"], release: 8, chronological: 8, recommended: 8),
                    .init(["hobbs & shaw"], release: 9, chronological: 9, recommended: 9),
                    .init(["f9"], release: 10, chronological: 10, recommended: 10),
                    .init(["fast x"], release: 11, chronological: 11, recommended: 11)
                ]
            ),
            FranchiseWatchOrderDefinition(
                collectionID: "automatic-marvel",
                defaultMode: .release,
                entries: [
                    .init(["iron man"], release: 1, chronological: 3, recommended: 1),
                    .init(["incredible hulk"], release: 2, chronological: 5, recommended: 2),
                    .init(["iron man 2"], release: 3, chronological: 4, recommended: 3),
                    .init(["thor"], release: 4, chronological: 6, recommended: 4),
                    .init(["captain america: the first avenger"], release: 5, chronological: 1, recommended: 5),
                    .init(["the avengers"], release: 6, chronological: 7, recommended: 6),
                    .init(["guardians of the galaxy"], release: 10, chronological: 11, recommended: 10),
                    .init(["doctor strange"], release: 14, chronological: 19, recommended: 14),
                    .init(["black panther"], release: 18, chronological: 18, recommended: 18),
                    .init(["avengers: infinity war"], release: 19, chronological: 23, recommended: 19),
                    .init(["avengers: endgame"], release: 22, chronological: 24, recommended: 22)
                ]
            )
        ]
        return Dictionary(uniqueKeysWithValues: definitions.map { ($0.collectionID, $0) })
    }()
}

private struct FranchiseWatchOrderEntry {
    let matchKeys: [String]
    let releaseOrder: Int?
    let chronologicalOrder: Int?
    let recommendedOrder: Int?

    init(_ matchKeys: [String], release: Int?, chronological: Int?, recommended: Int?) {
        self.matchKeys = matchKeys
        self.releaseOrder = release
        self.chronologicalOrder = chronological
        self.recommendedOrder = recommended
    }

    func order(for mode: FranchiseWatchOrderMode) -> Int? {
        switch mode {
        case .release:
            releaseOrder
        case .chronological:
            chronologicalOrder
        case .recommended:
            recommendedOrder
        }
    }
}
