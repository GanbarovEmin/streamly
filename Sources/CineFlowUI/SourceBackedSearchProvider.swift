import CineFlowCore
import CineFlowSources
import Foundation

public struct SourceBackedSearchProvider: SearchProviderProtocol {
    private let mediaProvider: any SearchProviderProtocol
    private let torrentAggregator: TorrentSearchAggregator

    public init(
        mediaProvider: any SearchProviderProtocol = MockSearchProvider(),
        torrentAggregator: TorrentSearchAggregator
    ) {
        self.mediaProvider = mediaProvider
        self.torrentAggregator = torrentAggregator
    }

    public func search(query: String) async throws -> SearchProviderResponse {
        let mediaResponse = try await mediaProvider.search(query: query)
        let aggregation = try await torrentAggregator.search(query: query)
        let releases = aggregation.rankedReleases.map { rankedRelease in
            SearchTorrentRelease(
                rankedRelease: rankedRelease,
                media: bestMediaMatch(for: rankedRelease.release, in: mediaResponse.media)
            )
        }

        return SearchProviderResponse(media: mediaResponse.media, releases: releases)
    }

    private func bestMediaMatch(
        for release: TorrentRelease,
        in media: [SearchMediaResult]
    ) -> SearchMediaResult? {
        let releaseTitle = release.title.lowercased()
        return media.first { item in
            releaseTitle.contains(item.title.lowercased()) ||
                item.title.lowercased().contains(releaseTitle)
        } ?? media.first
    }
}

private extension SearchTorrentRelease {
    init(rankedRelease: RankedRelease, media: SearchMediaResult?) {
        let release = rankedRelease.release
        self.init(
            id: release.id,
            mediaID: media?.id ?? "source:\(release.sourceId):\(release.id)",
            mediaTitle: media?.title ?? release.title,
            mediaKind: media?.kind ?? .movie,
            mediaYear: media?.year ?? 0,
            title: release.title,
            source: release.sourceName,
            magnetURI: release.magnetURI,
            torrentFileURL: release.torrentFileURL,
            quality: release.quality,
            isHDR: release.hdr != .none && release.hdr != .unknown,
            seeders: release.seeders,
            leechers: release.leechers,
            sizeBytes: release.sizeBytes ?? 0,
            uploadDate: release.uploadDate ?? Date(timeIntervalSince1970: 0),
            audioLanguages: release.audioLanguages,
            subtitleLanguages: release.subtitleLanguages,
            availability: release.availability,
            rankingScore: rankedRelease.score,
            rankingReasons: rankedRelease.reasons
        )
    }
}
