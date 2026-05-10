import Foundation

public struct TorrentSourceSearchFilters: Equatable, Sendable {
    public var qualities: Set<ReleaseQuality>
    public var requiresHDR: Bool
    public var minimumSeeders: Int?
    public var audioLanguage: String?
    public var subtitleLanguage: String?

    public init(
        qualities: Set<ReleaseQuality> = [],
        requiresHDR: Bool = false,
        minimumSeeders: Int? = nil,
        audioLanguage: String? = nil,
        subtitleLanguage: String? = nil
    ) {
        self.qualities = qualities
        self.requiresHDR = requiresHDR
        self.minimumSeeders = minimumSeeders
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
    }
}

public struct TorrentReleaseDetails: Equatable, Sendable {
    public let release: TorrentRelease
    public let description: String?
    public let files: [String]
    public let sourceURL: URL?

    public init(
        release: TorrentRelease,
        description: String? = nil,
        files: [String] = [],
        sourceURL: URL? = nil
    ) {
        self.release = release
        self.description = description
        self.files = files
        self.sourceURL = sourceURL
    }
}

public struct SourceCredentials: Codable, Equatable, Sendable {
    public let username: String?
    public let password: String?
    public let token: String?
    public let cookies: [String: String]

    public init(
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        cookies: [String: String] = [:]
    ) {
        self.username = username
        self.password = password
        self.token = token
        self.cookies = cookies
    }
}

public enum SourceAuthenticationStatus: Codable, Equatable, Sendable {
    case notRequired
    case unauthenticated
    case authenticated(username: String?)
    case invalid(reason: String)
}

public struct SourceErrorState: Codable, Equatable, Sendable {
    public let message: String
    public let occurredAt: Date
    public let isRecoverable: Bool

    public init(message: String, occurredAt: Date = Date(), isRecoverable: Bool = true) {
        self.message = message
        self.occurredAt = occurredAt
        self.isRecoverable = isRecoverable
    }
}

public struct SourceSettings: Codable, Equatable, Sendable {
    public let sourceId: String
    public var isEnabled: Bool
    public var authenticationStatus: SourceAuthenticationStatus
    public var lastSyncAt: Date?
    public var lastCheckedAt: Date?
    public var errorState: SourceErrorState?
    public var credentialKeychainID: String?

    public init(
        sourceId: String,
        isEnabled: Bool = true,
        authenticationStatus: SourceAuthenticationStatus = .notRequired,
        lastSyncAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        errorState: SourceErrorState? = nil,
        credentialKeychainID: String? = nil
    ) {
        self.sourceId = sourceId
        self.isEnabled = isEnabled
        self.authenticationStatus = authenticationStatus
        self.lastSyncAt = lastSyncAt
        self.lastCheckedAt = lastCheckedAt
        self.errorState = errorState
        self.credentialKeychainID = credentialKeychainID
    }
}

public enum SourceProviderError: LocalizedError, Equatable {
    case authenticationUnsupported(sourceId: String)
    case authenticationRequired(sourceId: String)
    case releaseNotFound(sourceId: String, releaseId: String)
    case providerUnavailable(sourceId: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .authenticationUnsupported(let sourceId):
            "Source \(sourceId) does not support authentication."
        case .authenticationRequired(let sourceId):
            "Source \(sourceId) requires authentication."
        case .releaseNotFound(let sourceId, let releaseId):
            "Release \(releaseId) was not found in source \(sourceId)."
        case .providerUnavailable(let sourceId, let reason):
            "Source \(sourceId) is unavailable: \(reason)"
        }
    }
}

public protocol TorrentSourceProviderProtocol: Sendable {
    var sourceId: String { get }
    var displayName: String { get }
    var requiresAuthentication: Bool { get }
    var isEnabled: Bool { get }

    func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease]
    func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails
    func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus
    func validateSession() async throws -> SourceAuthenticationStatus
}

public extension TorrentSourceProviderProtocol {
    func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus {
        throw SourceProviderError.authenticationUnsupported(sourceId: sourceId)
    }

    func validateSession() async throws -> SourceAuthenticationStatus {
        requiresAuthentication ? .unauthenticated : .notRequired
    }
}
