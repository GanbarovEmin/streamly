import CineFlowCore
import CineFlowDesignSystem
import Foundation

public enum MediaCatalogKind: String, Equatable, Sendable {
    case movies
    case series

    public var mediaKind: MediaKind {
        switch self {
        case .movies:
            .movie
        case .series:
            .series
        }
    }
}

public enum MediaCatalogViewState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

public enum MediaCatalogSource: String, CaseIterable, Identifiable, Equatable, Sendable {
    case popular
    case newByYear
    case featured

    public var id: String { rawValue }
}

@MainActor
public final class MediaCatalogViewModel: ObservableObject {
    @Published public private(set) var state: MediaCatalogViewState = .loading
    @Published public private(set) var items: [MediaItem] = []
    @Published public private(set) var selectedCatalog: MediaCatalogSource = .popular
    @Published public private(set) var selectedYear: Int
    @Published public var searchQuery = ""

    private let kind: MediaCatalogKind
    private let metadataService: any MetadataServiceProtocol

    public init(
        kind: MediaCatalogKind,
        metadataService: any MetadataServiceProtocol,
        currentYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())
    ) {
        self.kind = kind
        self.metadataService = metadataService
        selectedYear = currentYear
    }

    public var visibleItems: [MediaItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.displayTitle.lowercased().contains(query)
                || item.overview.lowercased().contains(query)
                || item.displayYear.lowercased().contains(query)
                || (item.metadata?.genres.joined(separator: " ").lowercased().contains(query) ?? false)
        }
    }

    public var cards: [CFMediaCardModel] {
        visibleItems.enumerated().map { index, item in
            card(for: item, index: index)
        }
    }

    public var prefetchArtworkURLs: [URL] {
        Array(visibleItems.lazy.compactMap(\.bestPosterURL).prefix(64))
    }

    public func load() async {
        state = .loading
        do {
            let loadedItems = try await catalogItems()
            items = loadedItems
            state = loadedItems.isEmpty ? .empty : .loaded
        } catch {
            items = []
            state = .failed(CineFlowError.from(error, fallbackCategory: .metadata).userMessage)
        }
    }

    public func refresh() async {
        await load()
    }

    public func selectCatalog(_ catalog: MediaCatalogSource) async {
        guard selectedCatalog != catalog else { return }
        selectedCatalog = catalog
        await load()
    }

    public func selectYear(_ year: Int) async {
        let normalizedYear = min(max(year, supportedYearRange.lowerBound), supportedYearRange.upperBound)
        guard selectedYear != normalizedYear else { return }
        selectedYear = normalizedYear
        if selectedCatalog == .newByYear {
            await load()
        }
    }

    public var supportedYearRange: ClosedRange<Int> {
        1920...Calendar(identifier: .gregorian).component(.year, from: Date())
    }

    private func catalogItems() async throws -> [MediaItem] {
        let primary = try await primaryCatalog()
        let supplemental: [MediaItem]
        if selectedCatalog == .popular, primary.count < 80 {
            supplemental = try await metadataService.trending().filter { $0.kind == kind.mediaKind }
        } else {
            supplemental = []
        }
        return Self.uniqueItems(from: [primary, supplemental], mediaKind: kind.mediaKind)
    }

    private static func uniqueItems(from groups: [[MediaItem]], mediaKind: MediaKind) -> [MediaItem] {
        var seen: Set<String> = []
        var uniqueItems: [MediaItem] = []
        for item in groups.flatMap({ $0 }) {
            guard item.kind == mediaKind, seen.insert(item.id).inserted else { continue }
            uniqueItems.append(item)
        }
        return uniqueItems
    }

    private func primaryCatalog() async throws -> [MediaItem] {
        switch selectedCatalog {
        case .popular:
            try await metadataService.catalog(kind: .popular, mediaKind: kind.mediaKind)
        case .newByYear:
            try await metadataService.catalog(kind: .newByYear(selectedYear), mediaKind: kind.mediaKind)
        case .featured:
            try await metadataService.catalog(kind: .featuredByIMDbRating, mediaKind: kind.mediaKind)
        }
    }

    private func card(for item: MediaItem, index: Int) -> CFMediaCardModel {
        let genres = item.metadata?.genres ?? []
        let genreLine = genres.prefix(2).joined(separator: ", ")
        let metadataParts = [
            item.displayYear,
            genreLine.isEmpty ? nil : genreLine,
            item.metadata?.rating.map { String(format: "%.1f", $0) }
        ].compactMap { $0 }.filter { !$0.isEmpty }

        return CFMediaCardModel(
            id: item.id,
            title: item.displayTitle,
            metadata: metadataParts.joined(separator: " · "),
            badge: item.metadata?.rating.map { String(format: "%.1f", $0) },
            accentIndex: index,
            artworkURL: item.bestPosterURL,
            genres: genres
        )
    }
}
