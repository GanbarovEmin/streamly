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

@MainActor
public final class MediaCatalogViewModel: ObservableObject {
    @Published public private(set) var state: MediaCatalogViewState = .loading
    @Published public private(set) var items: [MediaItem] = []
    @Published public var searchQuery = ""

    private let kind: MediaCatalogKind
    private let metadataService: any MetadataServiceProtocol

    public init(kind: MediaCatalogKind, metadataService: any MetadataServiceProtocol) {
        self.kind = kind
        self.metadataService = metadataService
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

    private func catalogItems() async throws -> [MediaItem] {
        async let primary = primaryCatalog()
        async let trending = metadataService.trending()
        let groups = try await [primary, trending.filter { $0.kind == kind.mediaKind }]

        var seen: Set<String> = []
        var uniqueItems: [MediaItem] = []
        for item in groups.flatMap({ $0 }) {
            guard item.kind == kind.mediaKind, seen.insert(item.id).inserted else { continue }
            uniqueItems.append(item)
        }
        return uniqueItems
    }

    private func primaryCatalog() async throws -> [MediaItem] {
        switch kind {
        case .movies:
            try await metadataService.popularMovies()
        case .series:
            try await metadataService.popularSeries()
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
