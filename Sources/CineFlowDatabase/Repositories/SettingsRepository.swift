import CineFlowCore
import Foundation
import GRDB

public final class DatabaseSettingsRepository: SettingsRepositoryProtocol {
    private enum Keys {
        static let appSettings = "app_settings"
        static let subtitleLanguagePriority = "subtitle_language_priority"
        static let subtitleSettings = "subtitle_settings"
    }

    private let databaseManager: DatabaseManager

    public init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    public var appSettings: AppSettings {
        get async {
            (try? await value(forKey: Keys.appSettings, as: AppSettings.self)) ?? AppSettings()
        }
    }

    public var subtitleLanguagePriority: [String] {
        get async {
            (try? await stringArray(forKey: Keys.subtitleLanguagePriority)) ?? ["ru", "en"]
        }
    }

    public var subtitleSettings: SubtitleSettings {
        get async {
            if let settings = try? await value(forKey: Keys.subtitleSettings, as: SubtitleSettings.self) {
                return settings
            }
            return SubtitleSettings(languagePreference: SubtitleLanguagePreference(await subtitleLanguagePriority))
        }
    }

    public func setSubtitleLanguagePriority(_ languages: [String]) async {
        try? await setStringArray(languages, forKey: Keys.subtitleLanguagePriority)
        var settings = await subtitleSettings
        settings.languagePreference = SubtitleLanguagePreference(languages)
        await setSubtitleSettings(settings)
    }

    public func setSubtitleSettings(_ settings: SubtitleSettings) async {
        try? await setCodable(settings, forKey: Keys.subtitleSettings)
        try? await setStringArray(settings.languagePreference.languageCodes, forKey: Keys.subtitleLanguagePriority)
    }

    public func setAppSettings(_ settings: AppSettings) async {
        try? await setCodable(settings, forKey: Keys.appSettings)
    }

    public func clearAllLocalData() async {
        try? databaseManager.write { db in
            try db.execute(sql: "DELETE FROM diagnostics_events")
            try db.execute(sql: "DELETE FROM source_accounts")
            try db.execute(sql: "DELETE FROM app_settings")
            try db.execute(sql: "DELETE FROM metadata_cache")
            try db.execute(sql: "DELETE FROM cached_images")
            try db.execute(sql: "DELETE FROM user_list_items")
            try db.execute(sql: "DELETE FROM user_lists")
            try db.execute(sql: "DELETE FROM user_ratings")
            try db.execute(sql: "DELETE FROM favorite_items")
            try db.execute(sql: "DELETE FROM watch_history")
            try db.execute(sql: "DELETE FROM playback_progress")
            try db.execute(sql: "DELETE FROM library_items")
            try db.execute(sql: "DELETE FROM torrent_releases")
        }
    }

    public func setString(_ value: String, forKey key: String) async throws {
        try databaseManager.write { db in
            try setValueJSON(DatabaseEncoding.jsonString(value), forKey: key, in: db)
        }
    }

    public func string(forKey key: String) async throws -> String? {
        try await value(forKey: key, as: String.self)
    }

    public func setStringArray(_ value: [String], forKey key: String) async throws {
        try databaseManager.write { db in
            try setValueJSON(DatabaseEncoding.jsonString(value), forKey: key, in: db)
        }
    }

    public func setCodable<T: Encodable>(_ value: T, forKey key: String) async throws {
        try databaseManager.write { db in
            try setValueJSON(DatabaseEncoding.jsonString(value), forKey: key, in: db)
        }
    }

    public func stringArray(forKey key: String) async throws -> [String]? {
        try await value(forKey: key, as: [String].self)
    }

    private func value<T: Decodable>(forKey key: String, as type: T.Type) async throws -> T? {
        try databaseManager.read { db in
            guard let json = try String.fetchOne(db, sql: "SELECT value_json FROM app_settings WHERE key = ?", arguments: [key]) else {
                return nil
            }
            return try DatabaseEncoding.decode(type, from: json)
        }
    }

    private func setValueJSON(_ json: String, forKey key: String, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO app_settings (key, value_json, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at
                """,
            arguments: [key, json, timestamp()]
        )
    }
}
