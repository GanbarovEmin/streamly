import CineFlowCore
import Foundation

public struct SourceAggregationError: Equatable, Sendable {
    public let sourceId: String
    public let displayName: String
    public let message: String

    public init(sourceId: String, displayName: String, message: String) {
        self.sourceId = sourceId
        self.displayName = displayName
        self.message = message
    }
}

public struct TorrentSearchAggregationResult: Equatable, Sendable {
    public let rankedReleases: [RankedRelease]
    public let sourceErrors: [SourceAggregationError]

    public init(rankedReleases: [RankedRelease], sourceErrors: [SourceAggregationError] = []) {
        self.rankedReleases = rankedReleases
        self.sourceErrors = sourceErrors
    }
}

public struct TorrentSearchAggregator: Sendable {
    private let sourceManager: SourceManager
    private let rankingEngine: ReleaseRankingEngine

    public init(
        sourceManager: SourceManager,
        rankingEngine: ReleaseRankingEngine = ReleaseRankingEngine()
    ) {
        self.sourceManager = sourceManager
        self.rankingEngine = rankingEngine
    }

    public func search(
        query: String,
        filters: TorrentSourceSearchFilters = TorrentSourceSearchFilters()
    ) async throws -> TorrentSearchAggregationResult {
        let providers = try await sourceManager.activeProviders()
        var releases: [TorrentRelease] = []
        var errors: [SourceAggregationError] = []

        await withTaskGroup(of: ProviderSearchResult.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let releases = try await provider.search(query: query, filters: filters)
                            .map { $0.normalized(sourceId: provider.sourceId, sourceName: provider.displayName) }
                        return .success(sourceId: provider.sourceId, displayName: provider.displayName, releases: releases)
                    } catch {
                        let cineFlowError = CineFlowError.from(error, fallbackCategory: .source)
                        return .failure(
                            sourceId: provider.sourceId,
                            displayName: provider.displayName,
                            message: cineFlowError.userMessage
                        )
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let sourceId, _, let providerReleases):
                    releases.append(contentsOf: providerReleases)
                    try? await sourceManager.recordSuccessfulSync(sourceId: sourceId)
                case .failure(let sourceId, let displayName, let message):
                    errors.append(SourceAggregationError(sourceId: sourceId, displayName: displayName, message: message))
                    try? await sourceManager.recordError(sourceId: sourceId, message: message)
                }
            }
        }

        return TorrentSearchAggregationResult(
            rankedReleases: rankingEngine.rank(releases),
            sourceErrors: errors.sorted { $0.sourceId < $1.sourceId }
        )
    }
}

private enum ProviderSearchResult: Sendable {
    case success(sourceId: String, displayName: String, releases: [TorrentRelease])
    case failure(sourceId: String, displayName: String, message: String)
}

private extension TorrentRelease {
    func normalized(sourceId: String, sourceName: String) -> TorrentRelease {
        TorrentRelease(
            id: id,
            sourceId: sourceId,
            sourceName: sourceName,
            title: title,
            magnetURI: magnetURI,
            torrentFileURL: torrentFileURL,
            quality: quality,
            codec: codec,
            hdr: hdr,
            audioLanguages: audioLanguages,
            subtitleLanguages: subtitleLanguages,
            seeders: seeders,
            leechers: leechers,
            sizeBytes: sizeBytes,
            uploadDate: uploadDate,
            trustedUploader: trustedUploader,
            rankScore: rankScore
        )
    }
}
