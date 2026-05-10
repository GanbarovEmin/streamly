import CineFlowCore
import Foundation

public struct RutorSourceProvider: TorrentSourceProviderProtocol {
    public let sourceId = "rutor"
    public let displayName = "Rutor"
    public let requiresAuthentication = false
    public let isEnabled = true

    public init() {}

    public func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        throw SourceProviderError.providerUnavailable(
            sourceId: sourceId,
            reason: "Placeholder provider. Live Rutor integration is intentionally not implemented in v1 architecture."
        )
    }

    public func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        throw SourceProviderError.providerUnavailable(
            sourceId: sourceId,
            reason: "Placeholder provider. Live Rutor integration is intentionally not implemented in v1 architecture."
        )
    }
}

public struct RuTrackerSourceProvider: TorrentSourceProviderProtocol {
    public let sourceId = "rutracker"
    public let displayName = "RuTracker"
    public let requiresAuthentication = true
    public let isEnabled = true

    public init() {}

    public func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        throw SourceProviderError.providerUnavailable(
            sourceId: sourceId,
            reason: "Placeholder provider. Live RuTracker integration is intentionally not implemented in v1 architecture."
        )
    }

    public func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        throw SourceProviderError.providerUnavailable(
            sourceId: sourceId,
            reason: "Placeholder provider. Live RuTracker integration is intentionally not implemented in v1 architecture."
        )
    }

    public func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus {
        .authenticated(username: credentials.username)
    }
}
