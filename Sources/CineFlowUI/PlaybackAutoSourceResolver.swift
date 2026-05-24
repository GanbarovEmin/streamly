@preconcurrency import CineFlowCore
import CineFlowSources
import Foundation

struct PlaybackAutoSourceResolution: Sendable {
    let release: TorrentRelease
    let fallbackReleases: [TorrentRelease]
    let selectionContext: PlaybackSelectionContext?
}

struct PlaybackAutoSourceResolver {
    private let metadataService: any MetadataServiceProtocol
    private let sourceManager: SourceManager
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?

    init(
        metadataService: any MetadataServiceProtocol,
        sourceManager: SourceManager,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil
    ) {
        self.metadataService = metadataService
        self.sourceManager = sourceManager
        self.diagnosticsService = diagnosticsService
    }

    func resolveBestRelease(
        mediaID: String,
        selectionContext: PlaybackSelectionContext?,
        rankingPreferences: RankingPreferences = RankingPreferences(preferHighSeedersOverHighestQuality: true)
    ) async -> PlaybackAutoSourceResolution? {
        do {
            try await ensureTorrentioEnabledForPlayback()
            guard let query = try await stremioQuery(for: mediaID, selectionContext: selectionContext) else {
                await log(
                    level: .warning,
                    event: "autoSource.query.missing",
                    message: "Unable to resolve Stremio query id for playback.",
                    metadata: ["mediaID": mediaID]
                )
                return nil
            }

            await log(
                level: .debug,
                event: "autoSource.search.start",
                message: "Searching configured torrent sources for playback.",
                metadata: ["mediaID": mediaID, "query": query.id]
            )

            let result = try await TorrentSearchAggregator(
                sourceManager: sourceManager,
                rankingEngine: ReleaseRankingEngine(preferences: rankingPreferences),
                diagnosticsService: diagnosticsService
            ).search(query: query.id)
            let releases = result.rankedReleases.map(\.release)
            guard let release = releases.first else {
                await log(
                    level: .warning,
                    event: "autoSource.search.empty",
                    message: "No torrent releases were returned for playback.",
                    metadata: ["mediaID": mediaID, "query": query.id]
                )
                return nil
            }

            await log(
                level: .debug,
                event: "autoSource.search.ready",
                message: "Resolved best torrent release for playback.",
                metadata: [
                    "mediaID": mediaID,
                    "query": query.id,
                    "releaseID": release.id,
                    "sourceID": release.sourceId,
                    "releaseCount": "\(releases.count)"
                ]
            )
            return PlaybackAutoSourceResolution(
                release: release,
                fallbackReleases: releases,
                selectionContext: query.selectionContext
            )
        } catch {
            await diagnosticsService?.log(
                CineFlowError.from(error, fallbackCategory: .source),
                operation: "player.route.autoSource",
                metadata: ["mediaID": mediaID]
            )
            return nil
        }
    }

    private func ensureTorrentioEnabledForPlayback() async throws {
        let descriptors = await sourceManager.providerDescriptors()
        guard descriptors.contains(where: { $0.sourceId == "torrentio" }) else { return }
        let settings = try await sourceManager.settings(for: "torrentio")
        guard !settings.isEnabled else { return }
        try await sourceManager.setSourceEnabled(true, sourceId: "torrentio")
        await log(
            level: .info,
            event: "autoSource.torrentio.enabled",
            message: "Enabled Torrentio for direct playback lookup.",
            metadata: ["sourceID": "torrentio"]
        )
    }

    private func stremioQuery(
        for mediaID: String,
        selectionContext: PlaybackSelectionContext?
    ) async throws -> PlaybackAutoSourceQuery? {
        if let episodeID = selectionContext?.episodeID?.streamlyNilIfBlank,
           Self.isStremioEpisodeID(episodeID) {
            return PlaybackAutoSourceQuery(id: episodeID, selectionContext: selectionContext)
        }

        if let imdb = IMDbRouteID(mediaID) {
            switch imdb.kind {
            case .movie:
                return PlaybackAutoSourceQuery(id: imdb.value, selectionContext: selectionContext)
            case .series:
                let series = try await metadataService.seriesDetail(imdbID: imdb.value)
                return try await seriesQuery(
                    imdbID: imdb.value,
                    series: series,
                    mediaID: mediaID,
                    selectionContext: selectionContext
                )
            }
        }

        guard let tmdb = TMDBRouteID(mediaID) else { return nil }
        switch tmdb.kind {
        case .movie:
            let movie = try await metadataService.movieDetail(tmdbID: tmdb.numericID)
            guard let imdbID = movie.metadata.imdbId?.streamlyNilIfBlank else { return nil }
            let context = selectionContext ?? PlaybackSelectionContext(
                mediaID: mediaID,
                displayTitle: movie.mediaItem.displayTitle,
                mediaKind: .movie
            )
            return PlaybackAutoSourceQuery(id: imdbID, selectionContext: context)
        case .series:
            let series = try await metadataService.seriesDetail(tmdbID: tmdb.numericID)
            return try await seriesQuery(
                imdbID: nil,
                series: series,
                mediaID: mediaID,
                selectionContext: selectionContext
            )
        }
    }

    private func seriesQuery(
        imdbID: String?,
        series: Series,
        mediaID: String,
        selectionContext: PlaybackSelectionContext?
    ) async throws -> PlaybackAutoSourceQuery? {
        let resolvedSeries = series
        guard let seriesIMDbID = (imdbID ?? resolvedSeries.metadata.imdbId)?.streamlyNilIfBlank else {
            return nil
        }

        if let season = selectionContext?.seasonNumber,
           let episode = selectionContext?.episodeNumber {
            let queryID = "\(seriesIMDbID):\(season):\(episode)"
            let context = PlaybackSelectionContext(
                mediaID: selectionContext?.mediaID ?? mediaID,
                displayTitle: selectionContext?.displayTitle ?? resolvedSeries.mediaItem.displayTitle,
                mediaKind: .series,
                seasonNumber: season,
                episodeNumber: episode,
                episodeID: queryID
            )
            return PlaybackAutoSourceQuery(id: queryID, selectionContext: context)
        }

        guard let firstEpisode = firstReleasedEpisode(in: resolvedSeries) else {
            return nil
        }
        let queryID = "\(seriesIMDbID):\(firstEpisode.seasonNumber):\(firstEpisode.episode.episodeNumber)"
        let context = PlaybackSelectionContext(
            mediaID: mediaID,
            displayTitle: selectionContext?.displayTitle ?? resolvedSeries.mediaItem.displayTitle,
            mediaKind: .series,
            seasonNumber: firstEpisode.seasonNumber,
            episodeNumber: firstEpisode.episode.episodeNumber,
            episodeID: queryID
        )
        return PlaybackAutoSourceQuery(id: queryID, selectionContext: context)
    }

    private func firstReleasedEpisode(in series: Series) -> (seasonNumber: Int, episode: Episode)? {
        let today = Date()
        for season in series.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }) where season.seasonNumber > 0 {
            if let episode = season.episodes
                .sorted(by: { $0.episodeNumber < $1.episodeNumber })
                .first(where: { $0.airDate.map { $0 <= today } ?? true }) {
                return (season.seasonNumber, episode)
            }
        }
        return nil
    }

    private static func isStremioEpisodeID(_ value: String) -> Bool {
        value.range(of: #"^tt[0-9]+:[0-9]+:[0-9]+$"#, options: .regularExpression) != nil
    }

    private func log(
        level: DiagnosticsLogLevel,
        event: String,
        message: String,
        metadata: [String: String]
    ) async {
        var payload = metadata
        payload["event"] = event
        await diagnosticsService?.log(level: level, subsystem: .playback, message: message, metadata: payload)
    }
}

private struct PlaybackAutoSourceQuery: Sendable {
    let id: String
    let selectionContext: PlaybackSelectionContext?
}

private struct TMDBRouteID {
    let kind: MediaKind
    let numericID: Int

    init?(_ value: String) {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "tmdb", let id = Int(parts[2]) else { return nil }
        switch parts[1] {
        case "movie":
            kind = .movie
        case "tv", "series":
            kind = .series
        default:
            return nil
        }
        numericID = id
    }
}

private struct IMDbRouteID {
    let kind: MediaKind
    let value: String

    init?(_ rawValue: String) {
        if rawValue.range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil {
            kind = .movie
            value = rawValue
            return
        }

        let parts = rawValue.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "imdb" else { return nil }
        switch parts[1] {
        case "movie":
            kind = .movie
        case "series", "tv":
            kind = .series
        default:
            return nil
        }
        guard parts[2].range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        value = parts[2]
    }
}

private extension String {
    var streamlyNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
