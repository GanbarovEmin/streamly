import CineFlowCore
import Foundation

public protocol SourceSettingsStoreProtocol: Sendable {
    func settings(for sourceId: String) async throws -> SourceSettings?
    func save(_ settings: SourceSettings) async throws
}

public actor InMemorySourceSettingsStore: SourceSettingsStoreProtocol {
    private var settingsBySourceID: [String: SourceSettings]

    public init(settings: [SourceSettings] = []) {
        settingsBySourceID = Dictionary(uniqueKeysWithValues: settings.map { ($0.sourceId, $0) })
    }

    public func settings(for sourceId: String) async throws -> SourceSettings? {
        settingsBySourceID[sourceId]
    }

    public func save(_ settings: SourceSettings) async throws {
        settingsBySourceID[settings.sourceId] = settings
    }
}

public actor UserDefaultsSourceSettingsStore: SourceSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(userDefaults: UserDefaults = .standard, keyPrefix: String = "cineflow.source.settings.") {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    public func settings(for sourceId: String) async throws -> SourceSettings? {
        guard let data = userDefaults.data(forKey: key(sourceId)) else { return nil }
        return try JSONDecoder().decode(SourceSettings.self, from: data)
    }

    public func save(_ settings: SourceSettings) async throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: key(settings.sourceId))
    }

    private func key(_ sourceId: String) -> String {
        "\(keyPrefix)\(sourceId)"
    }
}
