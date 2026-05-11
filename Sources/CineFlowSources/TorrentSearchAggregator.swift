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
    private let diagnosticsService: (any DiagnosticsServiceProtocol)?

    public init(
        sourceManager: SourceManager,
        rankingEngine: ReleaseRankingEngine = ReleaseRankingEngine(),
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil
    ) {
        self.sourceManager = sourceManager
        self.rankingEngine = rankingEngine
        self.diagnosticsService = diagnosticsService
    }

    public func search(
        query: String,
        filters: TorrentSourceSearchFilters = TorrentSourceSearchFilters()
    ) async throws -> TorrentSearchAggregationResult {
        let providers = try await sourceManager.activeSourceProviders()
        var releases: [TorrentRelease] = []
        var errors: [SourceAggregationError] = []

        await withTaskGroup(of: ProviderSearchResult.self) { group in
            for entry in providers {
                group.addTask {
                    await Self.searchProvider(entry, query: query, filters: filters)
                }
            }

            for await result in group {
                switch result {
                case .success(let sourceId, _, let providerReleases, let responseTimeMilliseconds):
                    releases.append(contentsOf: providerReleases)
                    try? await sourceManager.recordSuccessfulSync(
                        sourceId: sourceId,
                        responseTimeMilliseconds: responseTimeMilliseconds
                    )
                case .failure(let sourceId, let displayName, let message):
                    errors.append(SourceAggregationError(sourceId: sourceId, displayName: displayName, message: message))
                    try? await sourceManager.recordError(sourceId: sourceId, message: message)
                    await diagnosticsService?.log(
                        CineFlowError(
                            category: .source,
                            technicalDescription: message,
                            userMessage: message,
                            recoverySuggestion: "Check this source in Settings.",
                            logLevel: .warning
                        ),
                        operation: "source.healthCheck",
                        metadata: [
                            "sourceId": sourceId,
                            "sourceName": displayName
                        ]
                    )
                }
            }
        }

        return TorrentSearchAggregationResult(
            rankedReleases: rankingEngine.rank(releases),
            sourceErrors: errors.sorted { $0.sourceId < $1.sourceId }
        )
    }

    private static func searchProvider(
        _ entry: ActiveSourceProvider,
        query: String,
        filters: TorrentSourceSearchFilters
    ) async -> ProviderSearchResult {
        let provider = entry.provider
        let attempts = max(0, entry.settings.maxRetryCount) + 1
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                let startedAt = ContinuousClock.now
                let releases = try await withTimeout(
                    seconds: entry.settings.requestTimeoutSeconds,
                    sourceId: provider.sourceId
                ) {
                    try await provider.search(query: query, filters: filters)
                }
                .map { $0.normalized(sourceId: provider.sourceId, sourceName: provider.displayName) }
                let elapsed = startedAt.duration(to: .now).milliseconds
                return .success(
                    sourceId: provider.sourceId,
                    displayName: provider.displayName,
                    releases: releases,
                    responseTimeMilliseconds: elapsed
                )
            } catch {
                lastError = error
                guard attempt < attempts - 1, shouldRetry(error) else { break }
            }
        }

        let cineFlowError = CineFlowError.from(lastError ?? SourceProviderError.providerUnavailable(sourceId: provider.sourceId, reason: "Unknown source error."), fallbackCategory: .source)
        return .failure(
            sourceId: provider.sourceId,
            displayName: provider.displayName,
            message: cineFlowError.userMessage
        )
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let sourceError = error as? SourceProviderError {
            switch sourceError {
            case .authenticationRequired, .authenticationUnsupported, .releaseNotFound:
                return false
            case .providerUnavailable, .timedOut:
                return true
            }
        }

        let cineFlowError = CineFlowError.from(error, fallbackCategory: .source)
        return cineFlowError.category != .authentication
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        sourceId: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                let nanoseconds = UInt64(max(0.1, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw SourceProviderError.timedOut(sourceId: sourceId, seconds: seconds)
            }

            guard let result = try await group.next() else {
                throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Source task did not return.")
            }
            group.cancelAll()
            return result
        }
    }
}

private enum ProviderSearchResult: Sendable {
    case success(sourceId: String, displayName: String, releases: [TorrentRelease], responseTimeMilliseconds: Double)
    case failure(sourceId: String, displayName: String, message: String)
}

private extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension TorrentRelease {
    func normalized(sourceId: String, sourceName: String) -> TorrentRelease {
        TorrentRelease(
            id: id,
            sourceId: sourceId,
            sourceName: self.sourceId == sourceId ? self.sourceName : sourceName,
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
            availability: availability,
            rankScore: rankScore
        )
    }
}
