import CineFlowCore
import Foundation

public struct SourceProviderDescriptor: Equatable, Sendable {
    public let sourceId: String
    public let displayName: String
    public let requiresAuthentication: Bool

    public init(sourceId: String, displayName: String, requiresAuthentication: Bool) {
        self.sourceId = sourceId
        self.displayName = displayName
        self.requiresAuthentication = requiresAuthentication
    }
}

public struct ActiveSourceProvider: Sendable {
    public let provider: any TorrentSourceProviderProtocol
    public let settings: SourceSettings

    public init(provider: any TorrentSourceProviderProtocol, settings: SourceSettings) {
        self.provider = provider
        self.settings = settings
    }
}

public actor SourceManager {
    private let providersBySourceID: [String: any TorrentSourceProviderProtocol]
    private let settingsStore: any SourceSettingsStoreProtocol
    private let credentialStore: any SourceCredentialStoreProtocol

    public init(
        providers: [any TorrentSourceProviderProtocol],
        settingsStore: any SourceSettingsStoreProtocol = UserDefaultsSourceSettingsStore(),
        credentialStore: any SourceCredentialStoreProtocol = KeychainSourceCredentialStore()
    ) {
        providersBySourceID = Dictionary(uniqueKeysWithValues: providers.map { ($0.sourceId, $0) })
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
    }

    public static func development(
        featureFlags: SourceProviderFeatureFlags = .development,
        settingsStore: any SourceSettingsStoreProtocol = UserDefaultsSourceSettingsStore(),
        credentialStore: any SourceCredentialStoreProtocol = KeychainSourceCredentialStore(),
        torrentioSettingsStore: any TorrentioSettingsStoreProtocol = UserDefaultsTorrentioSettingsStore()
    ) -> SourceManager {
        SourceManager(
            providers: SourceProviderCatalog.providers(
                featureFlags: featureFlags,
                torrentioSettingsStore: torrentioSettingsStore
            ).makeProviders(),
            settingsStore: settingsStore,
            credentialStore: credentialStore
        )
    }

    public func providerDescriptors() -> [SourceProviderDescriptor] {
        providersBySourceID.values
            .map { SourceProviderDescriptor(sourceId: $0.sourceId, displayName: $0.displayName, requiresAuthentication: $0.requiresAuthentication) }
            .sorted { $0.sourceId < $1.sourceId }
    }

    public func activeProviders() async throws -> [any TorrentSourceProviderProtocol] {
        try await activeSourceProviders().map(\.provider)
    }

    public func activeSourceProviders() async throws -> [ActiveSourceProvider] {
        var entries: [ActiveSourceProvider] = []
        for provider in providersBySourceID.values.sorted(by: { $0.sourceId < $1.sourceId }) {
            guard provider.isEnabled else { continue }
            let settings = try await settings(for: provider.sourceId)
            guard settings.isEnabled else { continue }
            guard settings.healthStatus != .needsAuthentication else { continue }
            if provider.requiresAuthentication, settings.authenticationStatus != .authenticated(username: nil) {
                switch settings.authenticationStatus {
                case .authenticated:
                    break
                default:
                    continue
                }
            }
            entries.append(ActiveSourceProvider(provider: provider, settings: settings))
        }
        return entries
    }

    public func settings(for sourceId: String) async throws -> SourceSettings {
        guard let provider = providersBySourceID[sourceId] else {
            throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Provider is not registered.")
        }

        if let settings = try await settingsStore.settings(for: sourceId) {
            return settings
        }

        let settings = SourceSettings(
            sourceId: sourceId,
            isEnabled: provider.defaultIsEnabled,
            authenticationStatus: provider.requiresAuthentication ? .unauthenticated : .notRequired
        )
        try await settingsStore.save(settings)
        return settings
    }

    public func setSourceEnabled(_ isEnabled: Bool, sourceId: String) async throws {
        var settings = try await settings(for: sourceId)
        settings.isEnabled = isEnabled
        settings.lastCheckedAt = Date()
        if isEnabled {
            settings.errorState = nil
        }
        try await settingsStore.save(settings)
    }

    public func authenticate(sourceId: String, credentials: SourceCredentials) async throws {
        guard let provider = providersBySourceID[sourceId] else {
            throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Provider is not registered.")
        }

        let status = try await provider.authenticate(credentials: credentials)
        var settings = try await settings(for: sourceId)
        guard case .authenticated = status else {
            try await credentialStore.deleteCredentials(for: sourceId)
            settings.authenticationStatus = status
            settings.credentialKeychainID = nil
            settings.lastCheckedAt = Date()
            settings.errorState = SourceErrorState(message: "Sign in again for this source.")
            try await settingsStore.save(settings)
            throw SourceProviderError.authenticationRequired(sourceId: sourceId)
        }

        let keychainID = try await credentialStore.save(credentials: credentials, for: sourceId)
        settings.authenticationStatus = status
        settings.credentialKeychainID = keychainID
        settings.lastCheckedAt = Date()
        settings.errorState = nil
        try await settingsStore.save(settings)
    }

    public func testConnection(sourceId: String) async throws -> SourceAuthenticationStatus {
        guard let provider = providersBySourceID[sourceId] else {
            throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Provider is not registered.")
        }

        let status = try await provider.validateSession()
        var settings = try await settings(for: sourceId)
        settings.authenticationStatus = status
        settings.lastCheckedAt = Date()
        if case .invalid = status {
            try await credentialStore.deleteCredentials(for: sourceId)
            settings.credentialKeychainID = nil
            settings.errorState = SourceErrorState(message: "Sign in again for this source.")
        } else {
            settings.errorState = nil
        }
        try await settingsStore.save(settings)
        return status
    }

    public func clearSession(sourceId: String) async throws {
        try await credentialStore.deleteCredentials(for: sourceId)
        var settings = try await settings(for: sourceId)
        settings.credentialKeychainID = nil
        settings.authenticationStatus = providersBySourceID[sourceId]?.requiresAuthentication == true ? .unauthenticated : .notRequired
        settings.lastCheckedAt = Date()
        settings.errorState = nil
        try await settingsStore.save(settings)
    }

    public func recordSuccessfulSync(
        sourceId: String,
        responseTimeMilliseconds: Double? = nil,
        date: Date = Date()
    ) async throws {
        var settings = try await settings(for: sourceId)
        settings.lastSyncAt = date
        settings.lastCheckedAt = date
        settings.errorState = nil
        settings.successfulCheckCount += 1
        if let responseTimeMilliseconds {
            settings.averageResponseTimeMilliseconds = smoothedResponseTime(
                current: settings.averageResponseTimeMilliseconds,
                next: responseTimeMilliseconds
            )
        }
        try await settingsStore.save(settings)
    }

    public func recordError(sourceId: String, message: String, date: Date = Date()) async throws {
        var settings = try await settings(for: sourceId)
        settings.lastCheckedAt = date
        settings.errorState = SourceErrorState(message: message, occurredAt: date)
        settings.failedCheckCount += 1
        try await settingsStore.save(settings)
    }

    public func updateSourcePolicy(
        sourceId: String,
        requestTimeoutSeconds: Double,
        maxRetryCount: Int
    ) async throws {
        var settings = try await settings(for: sourceId)
        settings.requestTimeoutSeconds = max(0.1, requestTimeoutSeconds)
        settings.maxRetryCount = max(0, maxRetryCount)
        settings.lastCheckedAt = Date()
        try await settingsStore.save(settings)
    }

    private func smoothedResponseTime(current: Double?, next: Double) -> Double {
        guard let current else { return max(0, next) }
        return max(0, (current * 0.7) + (next * 0.3))
    }
}
