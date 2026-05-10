import CineFlowCore
import Foundation

public struct SourceProviderCatalog {
    public let providerNames: [String]
    public let providerIds: [String]
    private let providers: [any TorrentSourceProviderProtocol]

    public init(providers: [any TorrentSourceProviderProtocol]) {
        self.providers = providers
        self.providerNames = providers.map(\.displayName)
        self.providerIds = providers.map(\.sourceId)
    }

    public init(providerNames: [String]) {
        self.providerNames = providerNames
        self.providerIds = []
        self.providers = []
    }

    public static let mock = SourceProviderCatalog(providers: [MockTorrentSourceProvider()])

    public static func providers(featureFlags: SourceProviderFeatureFlags = .development) -> SourceProviderCatalog {
        var providers: [any TorrentSourceProviderProtocol] = []
        if featureFlags.mockProvider {
            providers.append(MockTorrentSourceProvider())
        }
        if featureFlags.rutorProvider {
            providers.append(RutorSourceProvider())
        }
        if featureFlags.ruTrackerProvider {
            providers.append(RuTrackerSourceProvider())
        }
        return SourceProviderCatalog(providers: providers)
    }

    public func makeProviders() -> [any TorrentSourceProviderProtocol] {
        providers
    }
}
