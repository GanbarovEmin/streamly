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

public enum SourceHealthStatus: String, Codable, Equatable, Sendable {
    case disabled
    case healthy
    case needsAuthentication
    case degraded
    case unavailable
}

public enum SourceStatus: String, Codable, Equatable, Sendable {
    case online
    case slow
    case authRequired
    case error
    case disabled
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
    public var requestTimeoutSeconds: Double
    public var maxRetryCount: Int
    public var successfulCheckCount: Int
    public var failedCheckCount: Int
    public var averageResponseTimeMilliseconds: Double?

    public init(
        sourceId: String,
        isEnabled: Bool = true,
        authenticationStatus: SourceAuthenticationStatus = .notRequired,
        lastSyncAt: Date? = nil,
        lastCheckedAt: Date? = nil,
        errorState: SourceErrorState? = nil,
        credentialKeychainID: String? = nil,
        requestTimeoutSeconds: Double = 8,
        maxRetryCount: Int = 1,
        successfulCheckCount: Int = 0,
        failedCheckCount: Int = 0,
        averageResponseTimeMilliseconds: Double? = nil
    ) {
        self.sourceId = sourceId
        self.isEnabled = isEnabled
        self.authenticationStatus = authenticationStatus
        self.lastSyncAt = lastSyncAt
        self.lastCheckedAt = lastCheckedAt
        self.errorState = errorState
        self.credentialKeychainID = credentialKeychainID
        self.requestTimeoutSeconds = max(0.1, requestTimeoutSeconds)
        self.maxRetryCount = max(0, maxRetryCount)
        self.successfulCheckCount = max(0, successfulCheckCount)
        self.failedCheckCount = max(0, failedCheckCount)
        self.averageResponseTimeMilliseconds = averageResponseTimeMilliseconds
    }

    public var healthStatus: SourceHealthStatus {
        guard isEnabled else { return .disabled }

        switch authenticationStatus {
        case .unauthenticated, .invalid:
            return .needsAuthentication
        case .authenticated, .notRequired:
            break
        }

        if let errorState {
            return errorState.isRecoverable ? .degraded : .unavailable
        }

        return .healthy
    }

    public var sourceStatus: SourceStatus {
        guard isEnabled else { return .disabled }

        switch authenticationStatus {
        case .unauthenticated, .invalid:
            return .authRequired
        case .authenticated, .notRequired:
            break
        }

        if errorState != nil {
            if errorState?.message.localizedCaseInsensitiveContains("too long") == true {
                return .slow
            }
            if let averageResponseTimeMilliseconds,
               averageResponseTimeMilliseconds > requestTimeoutSeconds * 1_000 * 0.8 {
                return .slow
            }
            return .error
        }

        if let averageResponseTimeMilliseconds,
           averageResponseTimeMilliseconds > requestTimeoutSeconds * 1_000 * 0.8 {
            return .slow
        }

        return .online
    }

    public var successRate: Double {
        let total = successfulCheckCount + failedCheckCount
        guard total > 0 else { return 0 }
        return Double(successfulCheckCount) / Double(total)
    }
}

public enum SourceProviderError: LocalizedError, Equatable {
    case authenticationUnsupported(sourceId: String)
    case authenticationRequired(sourceId: String)
    case releaseNotFound(sourceId: String, releaseId: String)
    case providerUnavailable(sourceId: String, reason: String)
    case timedOut(sourceId: String, seconds: Double)

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
        case .timedOut(let sourceId, let seconds):
            "Source \(sourceId) timed out after \(seconds) seconds."
        }
    }
}

private extension SourceSettings {
    enum CodingKeys: String, CodingKey {
        case sourceId
        case isEnabled
        case authenticationStatus
        case lastSyncAt
        case lastCheckedAt
        case errorState
        case credentialKeychainID
        case requestTimeoutSeconds
        case maxRetryCount
        case successfulCheckCount
        case failedCheckCount
        case averageResponseTimeMilliseconds
    }
}

public extension SourceSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sourceId: try container.decode(String.self, forKey: .sourceId),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            authenticationStatus: try container.decodeIfPresent(SourceAuthenticationStatus.self, forKey: .authenticationStatus) ?? .notRequired,
            lastSyncAt: try container.decodeIfPresent(Date.self, forKey: .lastSyncAt),
            lastCheckedAt: try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt),
            errorState: try container.decodeIfPresent(SourceErrorState.self, forKey: .errorState),
            credentialKeychainID: try container.decodeIfPresent(String.self, forKey: .credentialKeychainID),
            requestTimeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 8,
            maxRetryCount: try container.decodeIfPresent(Int.self, forKey: .maxRetryCount) ?? 1,
            successfulCheckCount: try container.decodeIfPresent(Int.self, forKey: .successfulCheckCount) ?? 0,
            failedCheckCount: try container.decodeIfPresent(Int.self, forKey: .failedCheckCount) ?? 0,
            averageResponseTimeMilliseconds: try container.decodeIfPresent(Double.self, forKey: .averageResponseTimeMilliseconds)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(authenticationStatus, forKey: .authenticationStatus)
        try container.encodeIfPresent(lastSyncAt, forKey: .lastSyncAt)
        try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
        try container.encodeIfPresent(errorState, forKey: .errorState)
        try container.encodeIfPresent(credentialKeychainID, forKey: .credentialKeychainID)
        try container.encode(requestTimeoutSeconds, forKey: .requestTimeoutSeconds)
        try container.encode(maxRetryCount, forKey: .maxRetryCount)
        try container.encode(successfulCheckCount, forKey: .successfulCheckCount)
        try container.encode(failedCheckCount, forKey: .failedCheckCount)
        try container.encodeIfPresent(averageResponseTimeMilliseconds, forKey: .averageResponseTimeMilliseconds)
    }
}

public protocol TorrentSourceProviderProtocol: Sendable {
    var sourceId: String { get }
    var displayName: String { get }
    var requiresAuthentication: Bool { get }
    var isEnabled: Bool { get }
    var defaultIsEnabled: Bool { get }

    func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease]
    func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails
    func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus
    func validateSession() async throws -> SourceAuthenticationStatus
}

public extension TorrentSourceProviderProtocol {
    var defaultIsEnabled: Bool {
        isEnabled
    }

    func authenticate(credentials: SourceCredentials) async throws -> SourceAuthenticationStatus {
        throw SourceProviderError.authenticationUnsupported(sourceId: sourceId)
    }

    func validateSession() async throws -> SourceAuthenticationStatus {
        requiresAuthentication ? .unauthenticated : .notRequired
    }
}
