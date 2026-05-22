import CineFlowCore
import CineFlowDesignSystem
import Foundation

struct ViewingCardResolver {
    private let seedByID: [String: HomeSeedItem]
    private let seedByTitle: [String: HomeSeedItem]
    private let libraryRepository: (any LibraryRepositoryProtocol)?
    private let metadataService: (any MetadataServiceProtocol)?

    init(
        seedItems: [HomeSeedItem] = HomeSeedLibrary.developmentItems,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        metadataService: (any MetadataServiceProtocol)? = nil
    ) {
        self.seedByID = Dictionary(uniqueKeysWithValues: seedItems.map { ($0.id, $0) })
        self.seedByTitle = seedItems.reduce(into: [String: HomeSeedItem]()) { lookup, item in
            let key = Self.normalizedTitle(item.title)
            if !key.isEmpty, lookup[key] == nil {
                lookup[key] = item
            }
        }
        self.libraryRepository = libraryRepository
        self.metadataService = metadataService
    }

    func card(for progress: PlaybackProgress) async -> CFMediaCardModel {
        let resolved = await resolve(mediaID: progress.mediaID, episodeID: progress.episodeID)
        return CFMediaCardModel(
            id: progress.mediaID,
            title: title(for: progress.mediaID, episodeID: progress.episodeID, resolved: resolved),
            metadata: metadata(progressPercent: progress.progressPercent, episodeID: progress.episodeID, episode: resolved.episode),
            badge: resolved.mediaItem?.rankedReleases.first?.quality.qualityLabel ?? resolved.seedItem?.quality,
            progress: progress.progressPercent / 100,
            accentIndex: abs(progress.id.hashValue),
            artworkURL: artworkURL(resolved: resolved),
            genres: genres(resolved: resolved)
        )
    }

    func card(for entry: WatchHistoryItem, dateTitle: String) async -> CFMediaCardModel {
        let resolved = await resolve(mediaID: entry.mediaID, episodeID: entry.episodeID)
        return CFMediaCardModel(
            id: entry.id,
            title: title(for: entry.mediaID, episodeID: entry.episodeID, resolved: resolved),
            metadata: historyMetadata(progressPercent: entry.progressPercent, dateTitle: dateTitle, episodeID: entry.episodeID, episode: resolved.episode),
            badge: entry.completed ? "Completed" : nil,
            progress: entry.progressPercent / 100,
            accentIndex: abs(entry.id.hashValue),
            artworkURL: artworkURL(resolved: resolved),
            genres: genres(resolved: resolved)
        )
    }

    private func resolve(mediaID: String, episodeID: String?) async -> ViewingResolution {
        let localItem = try? await libraryRepository?.mediaItem(id: mediaID)
        let seedItem = seedItem(for: mediaID, title: localItem?.displayTitle)

        guard shouldLoadMetadata(for: localItem, seedItem: seedItem),
              let metadataService
        else {
            return ViewingResolution(mediaItem: localItem, seedItem: seedItem, episode: nil)
        }

        if let metadata = await metadataResolution(mediaID: mediaID, episodeID: episodeID, metadataService: metadataService) {
            return ViewingResolution(
                mediaItem: metadata.mediaItem ?? localItem,
                seedItem: seedItem ?? self.seedItem(for: mediaID, title: metadata.mediaItem?.displayTitle),
                episode: metadata.episode
            )
        }

        return ViewingResolution(mediaItem: localItem, seedItem: seedItem, episode: nil)
    }

    private func shouldLoadMetadata(for item: MediaItem?, seedItem: HomeSeedItem?) -> Bool {
        guard let item else { return true }
        if Self.isTechnicalMediaIdentifier(item.displayTitle) {
            return true
        }
        return item.bestPosterURL == nil && item.bestBackdropURL == nil && seedItem?.artworkURL == nil && seedItem?.backdropURL == nil
    }

    private func metadataResolution(
        mediaID: String,
        episodeID: String?,
        metadataService: any MetadataServiceProtocol
    ) async -> ViewingMetadataResolution? {
        let isSeries = episodeID != nil || mediaID.contains(":tv:") || mediaID.contains(":series:")

        if let tmdbID = Self.tmdbID(from: mediaID) {
            if isSeries {
                guard let series = try? await metadataService.seriesDetail(tmdbID: tmdbID) else { return nil }
                return ViewingMetadataResolution(mediaItem: series.mediaItem, episode: Self.episode(in: series, episodeID: episodeID))
            }
            guard let movie = try? await metadataService.movieDetail(tmdbID: tmdbID) else { return nil }
            return ViewingMetadataResolution(mediaItem: movie.mediaItem, episode: nil)
        }

        if let imdbID = Self.imdbID(from: mediaID) {
            if isSeries {
                guard let series = try? await metadataService.seriesDetail(imdbID: imdbID) else { return nil }
                return ViewingMetadataResolution(mediaItem: series.mediaItem, episode: Self.episode(in: series, episodeID: episodeID))
            }
            if let movie = try? await metadataService.movieDetail(imdbID: imdbID) {
                return ViewingMetadataResolution(mediaItem: movie.mediaItem, episode: nil)
            }
            if let series = try? await metadataService.seriesDetail(imdbID: imdbID) {
                return ViewingMetadataResolution(mediaItem: series.mediaItem, episode: Self.episode(in: series, episodeID: episodeID))
            }
        }

        return nil
    }

    private func seedItem(for id: String, title: String?) -> HomeSeedItem? {
        if let item = seedByID[id] {
            return item
        }
        guard let title else { return nil }
        return seedByTitle[Self.normalizedTitle(title)]
    }

    private func title(for mediaID: String, episodeID: String?, resolved: ViewingResolution) -> String {
        if let title = resolved.mediaItem?.displayTitle,
           !title.isEmpty,
           !Self.isTechnicalMediaIdentifier(title) {
            return title
        }
        if let title = resolved.seedItem?.title, !title.isEmpty {
            return title
        }
        return episodeID == nil && !Self.seriesLike(mediaID) ? "Без названия" : "Без названия сериала"
    }

    private func metadata(progressPercent: Double, episodeID: String?, episode: Episode?) -> String {
        let progress = "\(Int(progressPercent.rounded()))% watched"
        guard let episodeLine = Self.episodeLine(episodeID: episodeID, episode: episode) else {
            return progress
        }
        return "\(progress) · \(episodeLine)"
    }

    private func historyMetadata(progressPercent: Double, dateTitle: String, episodeID: String?, episode: Episode?) -> String {
        var parts: [String] = []
        if let episodeLine = Self.episodeLine(episodeID: episodeID, episode: episode) {
            parts.append(episodeLine)
        }
        parts.append("\(Int(progressPercent.rounded()))%")
        parts.append(dateTitle)
        return parts.joined(separator: " · ")
    }

    private func artworkURL(resolved: ViewingResolution) -> URL? {
        resolved.episode?.thumbnailURL
            ?? resolved.mediaItem?.bestBackdropURL
            ?? resolved.mediaItem?.bestPosterURL
            ?? resolved.seedItem?.backdropURL
            ?? resolved.seedItem?.artworkURL
    }

    private func genres(resolved: ViewingResolution) -> [String] {
        if let genres = resolved.mediaItem?.metadata?.genres, !genres.isEmpty {
            return genres
        }
        if let genre = resolved.seedItem?.genre, !genre.isEmpty {
            return [genre]
        }
        return []
    }

    private static func episodeLine(episodeID: String?, episode: Episode?) -> String? {
        guard episodeID != nil || episode != nil else { return nil }
        let label = episode.map { "E\($0.episodeNumber)" } ?? episodeNumbers(from: episodeID).map { String(format: "S%02dE%02d", $0.season, $0.episode) }
        if let title = episode?.title, !title.isEmpty {
            return [label, title].compactMap { $0 }.joined(separator: " ")
        }
        return label ?? "Episode"
    }

    private static func episode(in series: Series, episodeID: String?) -> Episode? {
        let episodes = series.seasons.flatMap(\.episodes)
        if let episodeID, let exact = episodes.first(where: { $0.id == episodeID }) {
            return exact
        }
        guard let numbers = episodeNumbers(from: episodeID) else { return nil }
        let seasonID = series.seasons.first { $0.seasonNumber == numbers.season }?.id
        return episodes.first { episode in
            episode.episodeNumber == numbers.episode && (seasonID == nil || episode.seasonID == seasonID)
        }
    }

    private static func episodeNumbers(from episodeID: String?) -> (season: Int, episode: Int)? {
        guard let episodeID else { return nil }
        let parts = episodeID.split(separator: ":").map(String.init)
        let numericParts = parts.compactMap(Int.init)
        if numericParts.count >= 2 {
            return (numericParts[numericParts.count - 2], numericParts[numericParts.count - 1])
        }

        let lowercased = episodeID.lowercased()
        guard let regex = try? NSRegularExpression(pattern: #"s(\d{1,2})[\s._-]*e(\d{1,2})"#) else { return nil }
        let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
        guard let match = regex.firstMatch(in: lowercased, range: range),
              match.numberOfRanges == 3,
              let seasonRange = Range(match.range(at: 1), in: lowercased),
              let episodeRange = Range(match.range(at: 2), in: lowercased),
              let season = Int(lowercased[seasonRange]),
              let episode = Int(lowercased[episodeRange])
        else { return nil }
        return (season, episode)
    }

    private static func tmdbID(from mediaID: String) -> Int? {
        let parts = mediaID.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "tmdb" else { return nil }
        return Int(parts[2])
    }

    private static func imdbID(from mediaID: String) -> String? {
        let parts = mediaID.split(separator: ":").map(String.init)
        if parts.count >= 3, parts[0] == "imdb" {
            return parts[2]
        }
        return rawIMDbID(mediaID)
    }

    private static func rawIMDbID(_ value: String) -> String? {
        value.range(of: #"^tt\d+$"#, options: .regularExpression) == nil ? nil : value
    }

    private static func normalizedTitle(_ title: String) -> String {
        String(title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func isTechnicalMediaIdentifier(_ title: String) -> Bool {
        let normalized = title.lowercased()
        return normalized.hasPrefix("tmdb:")
            || normalized.hasPrefix("imdb:")
            || rawIMDbID(normalized) != nil
    }

    private static func seriesLike(_ mediaID: String) -> Bool {
        mediaID.contains(":tv:") || mediaID.contains(":series:")
    }
}

private struct ViewingResolution {
    let mediaItem: MediaItem?
    let seedItem: HomeSeedItem?
    let episode: Episode?
}

private struct ViewingMetadataResolution {
    let mediaItem: MediaItem?
    let episode: Episode?
}
