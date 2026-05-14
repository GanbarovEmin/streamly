import CineFlowCore
import Foundation

public enum CollectionAutomaticCategory: String, Equatable, Sendable {
    case franchise
    case award
    case topRated
    case quality
}

public enum CollectionKind: Equatable, Sendable {
    case automatic(CollectionAutomaticCategory)
    case userCreated

    public var title: String {
        switch self {
        case .automatic(.franchise):
            "Franchise"
        case .automatic(.award):
            "Award"
        case .automatic(.topRated):
            "Top Rated"
        case .automatic(.quality):
            "Quality"
        case .userCreated:
            "User Collection"
        }
    }
}

public enum CollectionSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case storyOrder
    case releaseYear
    case rating
    case title

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .storyOrder:
            "Story order"
        case .releaseYear:
            "Release year"
        case .rating:
            "Rating"
        case .title:
            "Title"
        }
    }
}

public enum CollectionItemFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case inLibrary
    case inWatchlist
    case available

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All"
        case .inLibrary:
            "Library"
        case .inWatchlist:
            "Watchlist"
        case .available:
            "Available"
        }
    }
}

public struct CollectionMediaItem: Identifiable, Equatable, Sendable {
    public let mediaItem: MediaItem
    public let storyOrder: Int?
    public let isInLibrary: Bool
    public let isInWatchlist: Bool
    public let isAvailableInSources: Bool

    public var id: String { mediaItem.id }

    public init(
        mediaItem: MediaItem,
        storyOrder: Int? = nil,
        isInLibrary: Bool = false,
        isInWatchlist: Bool = false,
        isAvailableInSources: Bool? = nil
    ) {
        self.mediaItem = mediaItem
        self.storyOrder = storyOrder
        self.isInLibrary = isInLibrary
        self.isInWatchlist = isInWatchlist
        self.isAvailableInSources = isAvailableInSources ?? !mediaItem.torrentReleases.isEmpty
    }

    public var year: Int {
        mediaItem.metadata?.year ?? mediaItem.releaseYear ?? 0
    }

    public var rating: Double {
        mediaItem.metadata?.rating ?? 0
    }

    public var has4KHDR: Bool {
        mediaItem.torrentReleases.contains { release in
            release.quality == .ultraHD && (release.hdr == .hdr10 || release.hdr == .dolbyVision || release.title.localizedCaseInsensitiveContains("HDR"))
        }
    }

    public var availabilityBadges: [String] {
        var badges: [String] = []
        if isInLibrary {
            badges.append("Library")
        }
        if isInWatchlist {
            badges.append("Watchlist")
        }
        if has4KHDR {
            badges.append("4K HDR")
        } else if isAvailableInSources {
            badges.append("Available")
        }
        return badges
    }
}

public struct MediaCollection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let kind: CollectionKind
    public var sort: CollectionSort
    public var filter: CollectionItemFilter
    public let items: [CollectionMediaItem]

    public init(
        id: String,
        title: String,
        description: String,
        kind: CollectionKind,
        sort: CollectionSort = .storyOrder,
        filter: CollectionItemFilter = .all,
        items: [CollectionMediaItem]
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.sort = sort
        self.filter = filter
        self.items = items
    }

    public var visibleItems: [CollectionMediaItem] {
        sorted(filteredItems)
    }

    public var posterCollageURLs: [URL] {
        Array(items.compactMap { $0.mediaItem.bestPosterURL }.prefix(6))
    }

    public var itemCountLabel: String {
        "\(items.count) \(items.count == 1 ? "title" : "titles")"
    }

    private var filteredItems: [CollectionMediaItem] {
        switch filter {
        case .all:
            items
        case .inLibrary:
            items.filter(\.isInLibrary)
        case .inWatchlist:
            items.filter(\.isInWatchlist)
        case .available:
            items.filter { $0.isAvailableInSources || $0.isInLibrary || $0.isInWatchlist }
        }
    }

    private func sorted(_ items: [CollectionMediaItem]) -> [CollectionMediaItem] {
        items.sorted { lhs, rhs in
            switch sort {
            case .storyOrder:
                let lhsOrder = lhs.storyOrder ?? Int.max
                let rhsOrder = rhs.storyOrder ?? Int.max
                if lhsOrder == rhsOrder {
                    if lhs.year == rhs.year { return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle }
                    return lhs.year < rhs.year
                }
                return lhsOrder < rhsOrder
            case .releaseYear:
                if lhs.year == rhs.year { return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle }
                return lhs.year < rhs.year
            case .rating:
                if lhs.rating == rhs.rating { return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle }
                return lhs.rating > rhs.rating
            case .title:
                return lhs.mediaItem.displayTitle < rhs.mediaItem.displayTitle
            }
        }
    }
}

public protocol CollectionDiscoveryProviderProtocol {
    func collections() async -> [MediaCollection]
    func collection(id: String) async -> MediaCollection?
}

public struct LocalCollectionDiscoveryProvider: CollectionDiscoveryProviderProtocol {
    private let metadataService: (any MetadataServiceProtocol)?
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let seedItems: [HomeSeedItem]
    private let userCollections: [MediaCollection]

    public init(
        metadataService: (any MetadataServiceProtocol)? = nil,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        seedItems: [HomeSeedItem] = HomeSeedLibrary.developmentItems,
        userCollections: [MediaCollection] = []
    ) {
        self.metadataService = metadataService
        self.libraryRepository = libraryRepository
        self.seedItems = seedItems
        self.userCollections = userCollections
    }

    public func collections() async -> [MediaCollection] {
        let libraryItems = (try? await libraryRepository?.items()) ?? []
        let libraryIDs = Set(libraryItems.map(\.id))
        let watchlistItems = await existingWatchlistItems()
        let watchlistIDs = Set(watchlistItems.map(\.id))
        var candidates = seedItems.map(CollectionDiscoveryBuilder.mediaItem(from:))
        candidates.append(contentsOf: (try? await metadataService?.trending()) ?? [])
        candidates.append(contentsOf: (try? await metadataService?.popularMovies()) ?? [])
        candidates.append(contentsOf: (try? await metadataService?.popularSeries()) ?? [])
        candidates.append(contentsOf: libraryItems)
        candidates.append(contentsOf: watchlistItems)
        return CollectionDiscoveryBuilder.automaticCollections(
            candidates: candidates,
            libraryIDs: libraryIDs,
            watchlistIDs: watchlistIDs
        ) + userCollections
    }

    public func collection(id: String) async -> MediaCollection? {
        await collections().first { $0.id == id }
    }

    private func existingWatchlistItems() async -> [MediaItem] {
        guard let libraryRepository,
              let defaultList = try? await libraryRepository.lists().first(where: \.isDefault)
        else { return [] }
        return (try? await libraryRepository.items(in: defaultList.id)) ?? []
    }
}

public enum CollectionDiscoveryBuilder {
    public static func automaticCollections(
        candidates: [MediaItem],
        libraryIDs: Set<String>,
        watchlistIDs: Set<String>
    ) -> [MediaCollection] {
        let deduped = dedupe(candidates)
        return definitions.map { definition in
            let items = deduped
                .filter(definition.matches)
                .map { item in
                    CollectionMediaItem(
                        mediaItem: item,
                        storyOrder: definition.storyOrder(item),
                        isInLibrary: libraryIDs.contains(item.id),
                        isInWatchlist: watchlistIDs.contains(item.id)
                    )
                }
            return MediaCollection(
                id: definition.id,
                title: definition.title,
                description: definition.description,
                kind: .automatic(definition.category),
                sort: definition.defaultSort,
                items: items
            )
        }
    }

    public static func automaticCollections(
        candidates: [MediaItem],
        libraryIDs: [String],
        watchlistIDs: [String]
    ) -> [MediaCollection] {
        automaticCollections(candidates: candidates, libraryIDs: Set(libraryIDs), watchlistIDs: Set(watchlistIDs))
    }

    public static func mediaItem(from seedItem: HomeSeedItem) -> MediaItem {
        let release = release(from: seedItem)
        return MediaItem(
            id: seedItem.id,
            title: seedItem.title,
            kind: seedItem.kind == .series ? .series : .movie,
            overview: seedItem.overview,
            releaseYear: seedItem.year,
            posterPath: seedItem.artworkURL?.absoluteString,
            metadata: MediaMetadata(
                tmdbId: Int(seedItem.id.split(separator: ":").last ?? "0") ?? 0,
                title: seedItem.title,
                originalTitle: seedItem.title,
                overview: seedItem.overview,
                year: seedItem.year,
                genres: [seedItem.genre],
                posterURL: seedItem.artworkURL,
                backdropURL: seedItem.backdropURL
            ),
            torrentReleases: release.map { [$0] } ?? []
        )
    }

    private static var definitions: [AutomaticCollectionDefinition] {
        [
            AutomaticCollectionDefinition(
                id: "automatic-marvel",
                title: "Marvel",
                description: "Heroes, teams, and connected Marvel stories from your local catalog.",
                category: .franchise,
                keywords: ["marvel", "avengers", "iron man", "captain america", "thor", "black panther", "spider-man", "guardians of the galaxy", "doctor strange"]
            ),
            AutomaticCollectionDefinition(
                id: "automatic-dc",
                title: "DC",
                description: "DC heroes, villains, and standalone comic-book films.",
                category: .franchise,
                keywords: ["dc", "batman", "superman", "wonder woman", "justice league", "aquaman", "joker", "the flash"]
            ),
            AutomaticCollectionDefinition(
                id: "automatic-lord-of-the-rings",
                title: "Lord of the Rings",
                description: "Middle-earth films and series, with story order when it can be inferred.",
                category: .franchise,
                keywords: ["lord of the rings", "the hobbit", "rings of power"],
                storyOrder: [
                    "The Hobbit": 1,
                    "The Lord of the Rings: The Fellowship of the Ring": 4,
                    "The Lord of the Rings: The Two Towers": 5,
                    "The Lord of the Rings: The Return of the King": 6
                ]
            ),
            AutomaticCollectionDefinition(
                id: "automatic-harry-potter",
                title: "Harry Potter",
                description: "Wizarding World films, including Harry Potter and Fantastic Beasts.",
                category: .franchise,
                keywords: ["harry potter", "fantastic beasts"]
            ),
            AutomaticCollectionDefinition(
                id: "automatic-fast-and-furious",
                title: "Fast & Furious",
                description: "Street races, heists, and family-order marathons from the Fast saga.",
                category: .franchise,
                keywords: ["fast & furious", "fast and furious", "the fast and the furious", "2 fast 2 furious", "tokyo drift", "fast five", "furious 7", "f9", "fast x", "hobbs & shaw"]
            ),
            AutomaticCollectionDefinition(
                id: "automatic-star-wars",
                title: "Star Wars",
                description: "Star Wars movies and series sorted by saga story order.",
                category: .franchise,
                keywords: ["star wars", "phantom menace", "attack of the clones", "revenge of the sith", "a new hope", "empire strikes back", "return of the jedi", "force awakens", "last jedi", "rise of skywalker", "rogue one", "solo"],
                storyOrder: [
                    "Star Wars: The Phantom Menace": 1,
                    "Star Wars: Attack of the Clones": 2,
                    "Star Wars: Revenge of the Sith": 3,
                    "Solo": 4,
                    "Rogue One": 5,
                    "Star Wars: A New Hope": 6,
                    "Star Wars: The Empire Strikes Back": 7,
                    "Star Wars: Return of the Jedi": 8,
                    "Star Wars: The Force Awakens": 9,
                    "Star Wars: The Last Jedi": 10,
                    "Star Wars: The Rise of Skywalker": 11
                ]
            ),
            AutomaticCollectionDefinition(
                id: "automatic-oscar-winners",
                title: "Oscar Winners",
                description: "Best Picture winners and Oscar favorites found locally or through metadata.",
                category: .award,
                keywords: oscarWinnerTitles,
                defaultSort: .releaseYear
            ),
            AutomaticCollectionDefinition(
                id: "automatic-imdb-top-rated",
                title: "IMDb Top Rated",
                description: "Highly rated classics and modern favorites, ready for rating-based browsing.",
                category: .topRated,
                defaultSort: .rating,
                matches: { ($0.metadata?.rating ?? 0) >= 8.5 }
            ),
            AutomaticCollectionDefinition(
                id: "automatic-4k-hdr",
                title: "4K HDR",
                description: "Titles with 4K HDR releases available from local/source metadata.",
                category: .quality,
                defaultSort: .releaseYear,
                matches: { item in
                    item.torrentReleases.contains { release in
                        release.quality == .ultraHD && (release.hdr == .hdr10 || release.hdr == .dolbyVision || release.title.localizedCaseInsensitiveContains("HDR"))
                    }
                }
            )
        ]
    }

    private static let oscarWinnerTitles = [
        "oppenheimer",
        "everything everywhere all at once",
        "coda",
        "nomadland",
        "parasite",
        "green book",
        "the shape of water",
        "moonlight",
        "spotlight",
        "birdman",
        "12 years a slave",
        "argo",
        "the artist",
        "the king's speech",
        "slumdog millionaire",
        "no country for old men",
        "the departed",
        "the lord of the rings: the return of the king",
        "gladiator",
        "american beauty",
        "titanic",
        "forrest gump",
        "the silence of the lambs",
        "the godfather"
    ]

    private static func release(from seedItem: HomeSeedItem) -> TorrentRelease? {
        let lowercased = seedItem.quality.lowercased()
        guard lowercased.contains("2160") || lowercased.contains("4k") else { return nil }
        return TorrentRelease(
            id: "\(seedItem.id):quality",
            sourceName: "Local Metadata",
            title: "\(seedItem.title) \(seedItem.quality)",
            quality: .ultraHD,
            hdr: lowercased.contains("hdr") ? .hdr10 : .none,
            seeders: 0
        )
    }

    private static func dedupe(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        var result: [MediaItem] = []
        for item in items where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }
}

private struct AutomaticCollectionDefinition {
    let id: String
    let title: String
    let description: String
    let category: CollectionAutomaticCategory
    let defaultSort: CollectionSort
    private let matcher: @Sendable (MediaItem) -> Bool
    private let storyOrderByTitle: [String: Int]

    init(
        id: String,
        title: String,
        description: String,
        category: CollectionAutomaticCategory,
        keywords: [String] = [],
        defaultSort: CollectionSort = .storyOrder,
        storyOrder: [String: Int] = [:],
        matches: (@Sendable (MediaItem) -> Bool)? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.defaultSort = defaultSort
        self.storyOrderByTitle = storyOrder
        self.matcher = matches ?? { item in
            let haystack = [
                item.displayTitle,
                item.metadata?.originalTitle,
                item.metadata?.alternativeTitles.joined(separator: " "),
                item.metadata?.genres.joined(separator: " ")
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
            return keywords.contains { haystack.contains($0.lowercased()) }
        }
    }

    func matches(_ item: MediaItem) -> Bool {
        matcher(item)
    }

    func storyOrder(_ item: MediaItem) -> Int? {
        storyOrderByTitle.first { key, _ in
            item.displayTitle.localizedCaseInsensitiveContains(key)
        }?.value
    }
}
