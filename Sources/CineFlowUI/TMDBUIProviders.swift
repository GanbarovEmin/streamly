@preconcurrency import CineFlowCore
import CineFlowSources
import Foundation

public struct TMDBSearchProvider: SearchProviderProtocol {
    private let metadataService: any MetadataServiceProtocol

    public init(metadataService: any MetadataServiceProtocol) {
        self.metadataService = metadataService
    }

    public func search(query: String) async throws -> SearchProviderResponse {
        let media = try await metadataService.search(query: query).map(SearchMediaResult.init(mediaItem:))
        return SearchProviderResponse(media: media, releases: [])
    }
}

public struct TMDBHomeContentProvider: Sendable {
    private let metadataService: any MetadataServiceProtocol

    public init(metadataService: any MetadataServiceProtocol) {
        self.metadataService = metadataService
    }

    public func loadHomeItems() async throws -> [HomeSeedItem] {
        async let trending = metadataService.trending()
        async let popularMovies = metadataService.popularMovies()
        async let popularSeries = metadataService.popularSeries()

        let groups = try await [trending, popularMovies, popularSeries]
        var seen: Set<String> = []
        var items: [HomeSeedItem] = []

        for (groupIndex, group) in groups.enumerated() {
            for item in group {
                guard !seen.contains(item.id) else { continue }
                seen.insert(item.id)
                let rank = items.count + 1
                items.append(
                    HomeSeedItem(
                        mediaItem: item,
                        popularityRank: rank,
                        isFeatured: rank <= 4,
                        isRecentlyAdded: groupIndex == 0 || rank <= 6,
                        isRecommended: groupIndex != 2 || rank <= 10
                    )
                )
            }
        }

        return items
    }
}

public struct TMDBPersonDetailProvider: PersonDetailProviderProtocol {
    private let metadataService: any MetadataServiceProtocol

    public init(metadataService: any MetadataServiceProtocol) {
        self.metadataService = metadataService
    }

    public func personDetail(for person: PersonRoutePayload) async throws -> PersonDetailResponse? {
        let searchedItems = try await metadataService.search(query: person.name)
        var filmographyItems: [MediaItem] = []
        if let sourceMedia = person.sourceMedia?.mediaItem {
            filmographyItems.append(sourceMedia)
        }
        for item in searchedItems where !filmographyItems.contains(where: { $0.id == item.id }) {
            filmographyItems.append(item)
        }
        let credits = filmographyItems.enumerated().map { index, item in
            PersonFilmographyCredit(
                mediaItem: item,
                role: person.role ?? (person.id.hasPrefix("director:") ? "Director" : "Cast"),
                popularityScore: Double(max(0, 100 - index)),
                isAvailableInSources: !item.torrentReleases.isEmpty
            )
        }

        let knownFor = Array(filmographyItems.prefix(4))
        let detail = PersonDetail(
            id: person.id,
            name: person.name,
            kind: person.id.hasPrefix("director:") ? .director : .actor,
            role: person.role,
            photoURL: person.profileURL,
            shortBio: "",
            knownFor: knownFor
        )
        return PersonDetailResponse(detail: detail, filmography: credits)
    }
}

public struct TMDBMovieDetailProvider: MovieDetailProviderProtocol {
    private let metadataService: any MetadataServiceProtocol
    private let torrentAggregator: TorrentSearchAggregator?

    public init(
        metadataService: any MetadataServiceProtocol,
        torrentAggregator: TorrentSearchAggregator? = nil
    ) {
        self.metadataService = metadataService
        self.torrentAggregator = torrentAggregator
    }

    public func movieDetail(id: String) async throws -> MovieDetailResponse? {
        let movie: Movie
        if let tmdbID = TMDBMediaID(id), tmdbID.kind == .movie {
            movie = try await metadataService.movieDetail(tmdbID: tmdbID.numericID)
        } else if let imdbID = IMDbMediaID(id), imdbID.kind == .movie {
            movie = try await metadataService.movieDetail(imdbID: imdbID.value)
        } else {
            return nil
        }

        async let similarItems = try? metadataService.similar(to: id)
        async let trailerItems = try? metadataService.videos(for: id)
        async let castItems = try? metadataService.credits(for: id)
        let metadata = movie.metadata
        let trailers = await trailerItems ?? []
        let cast = await castItems ?? []
        let releases = await torrentReleases(for: metadata) + movie.mediaItem.torrentReleases

        return MovieDetailResponse(
            movie: MovieDetail(mediaItem: movie.mediaItem),
            releases: releases,
            trailers: trailers.isEmpty ? metadata.trailerURLs.enumerated().map { index, url in
                MovieTrailer(id: url.absoluteString, title: index == 0 ? "Official Trailer" : "Trailer \(index + 1)", source: url.host ?? "Video")
            } : trailers.map { trailer in
                MovieTrailer(id: trailer.id, title: trailer.title, source: trailer.site ?? trailer.url.host ?? "Video")
            },
            similar: (await similarItems ?? []).map(SearchMediaResult.init(mediaItem:)),
            cast: (cast.isEmpty ? metadata.cast : cast).prefix(12).map { member in
                MovieCastMember(id: member.id, name: member.name, role: member.characterName ?? "Cast", profileURL: member.profileURL)
            },
            progress: nil
        )
    }

    public func refreshMovieDetail(id: String) async throws -> MovieDetailResponse? {
        if let cacheControl = metadataService as? MetadataCacheControlProtocol {
            try await cacheControl.refreshMetadata(for: id)
        }
        return try await movieDetail(id: id)
    }

    public func clearMetadataCache(id: String) async throws {
        try await (metadataService as? MetadataCacheControlProtocol)?.clearMetadataCache(for: id)
    }

    private func torrentReleases(for metadata: MediaMetadata) async -> [TorrentRelease] {
        guard let torrentAggregator,
              let imdbID = metadata.imdbId?.nilIfBlank
        else {
            return []
        }

        do {
            let result = try await torrentAggregator.search(query: imdbID)
            return result.rankedReleases.map(\.release)
        } catch {
            return []
        }
    }
}

public struct TMDBSeriesDetailProvider: SeriesDetailProviderProtocol {
    private let metadataService: any MetadataServiceProtocol
    private let torrentAggregator: TorrentSearchAggregator?

    public init(
        metadataService: any MetadataServiceProtocol,
        torrentAggregator: TorrentSearchAggregator? = nil
    ) {
        self.metadataService = metadataService
        self.torrentAggregator = torrentAggregator
    }

    public func seriesDetail(id: String) async throws -> SeriesDetailResponse? {
        let series: Series
        let tmdbSeriesID: Int?
        if let parsedID = TMDBMediaID(id), parsedID.kind == .series {
            series = try await metadataService.seriesDetail(tmdbID: parsedID.numericID)
            tmdbSeriesID = parsedID.numericID
        } else if let imdbID = IMDbMediaID(id), imdbID.kind == .series {
            series = try await metadataService.seriesDetail(imdbID: imdbID.value)
            tmdbSeriesID = nil
        } else {
            return nil
        }

        let seasonSummaries = series.seasons.filter { $0.seasonNumber > 0 }
        var seasons: [SeriesSeason] = []

        for summary in seasonSummaries.prefix(3) {
            if let tmdbSeriesID,
               let detail = try? await metadataService.seasonDetail(seriesTMDBID: tmdbSeriesID, seasonNumber: summary.seasonNumber) {
                seasons.append(SeriesSeason(season: detail))
            } else {
                seasons.append(SeriesSeason(season: summary))
            }
        }

        async let similarItems = try? metadataService.similar(to: id)
        async let trailerItems = try? metadataService.videos(for: id)
        async let castItems = try? metadataService.credits(for: id)
        let metadata = series.metadata
        let trailers = await trailerItems ?? []
        let cast = await castItems ?? []
        let releases = await episodeScopedReleases(for: seasons.flatMap(\.episodes).first?.id)

        return SeriesDetailResponse(
            series: SeriesDetail(series: series),
            seasons: seasons,
            releases: releases,
            trailers: trailers.isEmpty ? metadata.trailerURLs.enumerated().map { index, url in
                MovieTrailer(id: url.absoluteString, title: index == 0 ? "Official Trailer" : "Trailer \(index + 1)", source: url.host ?? "Video")
            } : trailers.map { trailer in
                MovieTrailer(id: trailer.id, title: trailer.title, source: trailer.site ?? trailer.url.host ?? "Video")
            },
            similar: (await similarItems ?? []).map(SearchMediaResult.init(mediaItem:)),
            cast: (cast.isEmpty ? metadata.cast : cast).prefix(12).map { member in
                MovieCastMember(id: member.id, name: member.name, role: member.characterName ?? "Cast", profileURL: member.profileURL)
            },
            progressByEpisodeID: [:],
            lastWatchedEpisodeID: nil
        )
    }

    public func episodeReleases(seriesID: String, episodeID: String) async throws -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        await episodeScopedReleases(for: episodeID)
    }

    public func refreshSeriesDetail(id: String) async throws -> SeriesDetailResponse? {
        if let cacheControl = metadataService as? MetadataCacheControlProtocol {
            try await cacheControl.refreshMetadata(for: id)
        }
        return try await seriesDetail(id: id)
    }

    public func clearMetadataCache(id: String) async throws {
        try await (metadataService as? MetadataCacheControlProtocol)?.clearMetadataCache(for: id)
    }

    private func episodeScopedReleases(for episodeID: String?) async -> [(release: TorrentRelease, scope: SeriesReleaseScope)] {
        guard let torrentAggregator,
              let episodeID,
              episodeID.range(of: #"^tt[0-9]+:[0-9]+:[0-9]+$"#, options: .regularExpression) != nil
        else {
            return []
        }

        do {
            let result = try await torrentAggregator.search(query: episodeID)
            return result.rankedReleases.map { ($0.release, .episode(episodeID)) }
        } catch {
            return []
        }
    }
}

private struct TMDBMediaID {
    let kind: MediaKind
    let numericID: Int

    init?(_ value: String) {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "tmdb", let id = Int(parts[2]) else {
            return nil
        }
        switch parts[1] {
        case "movie":
            kind = .movie
        case "tv":
            kind = .series
        default:
            return nil
        }
        numericID = id
    }
}

private struct IMDbMediaID {
    let kind: MediaKind
    let value: String

    init?(_ value: String) {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "imdb" else {
            return nil
        }
        switch parts[1] {
        case "movie":
            kind = .movie
        case "series":
            kind = .series
        default:
            return nil
        }
        guard parts[2].range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        self.value = parts[2]
    }
}

private extension HomeSeedItem {
    init(
        mediaItem: MediaItem,
        popularityRank: Int,
        isFeatured: Bool,
        isRecentlyAdded: Bool,
        isRecommended: Bool
    ) {
        let metadata = mediaItem.metadata
        self.init(
            id: mediaItem.id,
            title: mediaItem.displayTitle,
            kind: mediaItem.kind == .series ? .series : .movie,
            year: metadata?.year ?? mediaItem.releaseYear ?? 0,
            rating: metadata?.rating.map { String(format: "\(ratingProviderLabel(for: mediaItem)) %.1f", $0) } ?? ratingProviderLabel(for: mediaItem),
            runtime: runtimeLabel(minutes: metadata?.runtime, kind: mediaItem.kind),
            genre: metadata?.genres.first ?? (mediaItem.kind == .series ? "Series" : "Movie"),
            overview: metadata?.overview.nilIfBlank ?? mediaItem.overview,
            quality: mediaItem.kind == .series ? "Series" : "Movie",
            popularityRank: popularityRank,
            isFeatured: isFeatured,
            isRecentlyAdded: isRecentlyAdded,
            isRecommended: isRecommended,
            artworkURL: mediaItem.bestPosterURL,
            backdropURL: mediaItem.bestBackdropURL
        )
    }
}

private extension MovieDetail {
    init(mediaItem: MediaItem) {
        let metadata = mediaItem.metadata
        self.init(
            id: mediaItem.id,
            title: mediaItem.displayTitle,
            originalTitle: metadata?.originalTitle ?? mediaItem.title,
            year: metadata?.year ?? mediaItem.releaseYear ?? 0,
            runtime: runtimeLabel(minutes: metadata?.runtime, kind: .movie),
            genres: metadata?.genres ?? [],
            tmdbRating: metadata?.rating.map { String(format: "%.1f", $0) } ?? "N/A",
            imdbRating: metadata?.imdbId ?? "N/A",
            overview: metadata?.overview.nilIfBlank ?? mediaItem.overview,
            backdropAccentIndex: abs(mediaItem.id.hashValue),
            posterURL: mediaItem.bestPosterURL,
            backdropURL: mediaItem.bestBackdropURL
        )
    }
}

private extension SeriesDetail {
    init(series: Series) {
        let metadata = series.metadata
        self.init(
            id: series.id,
            title: series.mediaItem.displayTitle,
            yearRange: metadata.year.map(String.init) ?? "Unknown",
            seasonsCount: series.seasons.filter { $0.seasonNumber > 0 }.count,
            rating: metadata.rating.map { String(format: "%.1f", $0) } ?? "N/A",
            genres: metadata.genres,
            overview: metadata.overview.nilIfBlank ?? series.mediaItem.overview,
            backdropAccentIndex: abs(series.id.hashValue),
            posterURL: series.mediaItem.bestPosterURL,
            backdropURL: series.mediaItem.bestBackdropURL
        )
    }
}

private extension SeriesSeason {
    init(season: Season) {
        self.init(
            id: season.id,
            seasonNumber: season.seasonNumber,
            title: season.title?.nilIfBlank ?? "Season \(season.seasonNumber)",
            episodes: season.episodes.map(SeriesEpisode.init(episode:))
        )
    }
}

private extension SeriesEpisode {
    init(episode: Episode) {
        self.init(
            id: episode.id,
            seasonID: episode.seasonID,
            seasonNumber: Int(episode.seasonID.split(separator: ":").last ?? "0") ?? 0,
            episodeNumber: episode.episodeNumber,
            title: episode.title,
            runtime: runtimeLabel(minutes: episode.runtimeMinutes, kind: .series),
            overview: episode.overview ?? "",
            airDate: episode.airDate,
            thumbnailURL: episode.thumbnailURL
        )
    }
}

private func runtimeLabel(minutes: Int?, kind: MediaKind) -> String {
    guard let minutes, minutes > 0 else {
        return kind == .series ? "Series" : "Movie"
    }
    if minutes < 60 {
        return "\(minutes)m"
    }
    return "\(minutes / 60)h \(minutes % 60)m"
}

private func ratingProviderLabel(for mediaItem: MediaItem) -> String {
    mediaItem.id.hasPrefix("imdb:") ? "IMDb" : "TMDB"
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
