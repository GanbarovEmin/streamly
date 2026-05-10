import CineFlowCore
import Foundation

public struct MockTorrentSourceProvider: TorrentSourceProviderProtocol {
    public let sourceId: String
    public let displayName: String
    public let requiresAuthentication: Bool
    public let isEnabled: Bool

    private let releases: [TorrentRelease]
    private let shouldFail: Bool

    public init(
        sourceId: String = "mock",
        displayName: String = "Mock Source Provider",
        requiresAuthentication: Bool = false,
        isEnabled: Bool = true,
        releases: [TorrentRelease]? = nil,
        shouldFail: Bool = false
    ) {
        self.sourceId = sourceId
        self.displayName = displayName
        self.requiresAuthentication = requiresAuthentication
        self.isEnabled = isEnabled
        self.releases = releases ?? Self.defaultReleases(sourceId: sourceId, sourceName: displayName)
        self.shouldFail = shouldFail
    }

    public func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        if shouldFail {
            throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Mock failure.")
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        return releases.filter { release in
            guard release.title.lowercased().contains(normalizedQuery) else { return false }
            if !filters.qualities.isEmpty, !filters.qualities.contains(release.quality) {
                return false
            }
            if filters.requiresHDR, release.hdr == .none || release.hdr == .unknown {
                return false
            }
            if let minimumSeeders = filters.minimumSeeders, release.seeders < minimumSeeders {
                return false
            }
            if let audioLanguage = filters.audioLanguage, !release.audioLanguages.contains(audioLanguage) {
                return false
            }
            if let subtitleLanguage = filters.subtitleLanguage, !release.subtitleLanguages.contains(subtitleLanguage) {
                return false
            }
            return true
        }
    }

    public func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        guard let release = releases.first(where: { $0.id == releaseId }) else {
            throw SourceProviderError.releaseNotFound(sourceId: sourceId, releaseId: releaseId)
        }
        return TorrentReleaseDetails(release: release, description: "Development mock release.")
    }

    public func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus {
        guard requiresAuthentication else { return .notRequired }
        return .authenticated(username: credentials.username)
    }

    public func validateSession() async throws -> SourceAuthenticationStatus {
        requiresAuthentication ? .unauthenticated : .notRequired
    }

    private static func defaultReleases(sourceId: String, sourceName: String) -> [TorrentRelease] {
        [
            TorrentRelease(
                id: "mock-matrix-2160p",
                sourceId: sourceId,
                sourceName: sourceName,
                title: "The Matrix 2160p HDR",
                quality: .ultraHD,
                codec: .hevc,
                hdr: .hdr10,
                audioLanguages: ["en", "ru"],
                subtitleLanguages: ["en", "ru"],
                seeders: 90,
                leechers: 10,
                sizeBytes: 32_000_000_000,
                uploadDate: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            TorrentRelease(
                id: "mock-matrix-1080p",
                sourceId: sourceId,
                sourceName: sourceName,
                title: "The Matrix 1080p BluRay",
                quality: .fullHD,
                codec: .h264,
                hdr: .none,
                audioLanguages: ["en", "ru"],
                subtitleLanguages: ["en"],
                seeders: 1_200,
                leechers: 80,
                sizeBytes: 12_000_000_000,
                uploadDate: Date(timeIntervalSince1970: 1_800_086_400)
            )
        ]
    }
}
