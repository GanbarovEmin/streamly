import Foundation
import GRDB

public final class DatabaseManager {
    public static let fileName = "Streamly.sqlite"
    private static let legacyFileName = "CineFlow.sqlite"

    let databaseQueue: DatabaseQueue

    public init(path: String) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        databaseQueue = try DatabaseQueue(path: path, configuration: configuration)
        try Self.migrator.migrate(databaseQueue)
    }

    public static func live() throws -> DatabaseManager {
        let directory = try applicationSupportDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try DatabaseManager(path: directory.appendingPathComponent(fileName).path)
    }

    public static func inMemory() throws -> DatabaseManager {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let manager = DatabaseManager(databaseQueue: try DatabaseQueue(configuration: configuration))
        try Self.migrator.migrate(manager.databaseQueue)
        return manager
    }

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try databaseQueue.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try databaseQueue.write(block)
    }

    private static func applicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try migrateLegacyApplicationSupportIfNeeded(baseURL: baseURL)
        return baseURL.appendingPathComponent("Streamly", isDirectory: true)
    }

    static func migrateLegacyApplicationSupportIfNeeded(baseURL: URL, fileManager: FileManager = .default) throws {
        let legacyDirectory = baseURL.appendingPathComponent("CineFlow", isDirectory: true)
        let streamlyDirectory = baseURL.appendingPathComponent("Streamly", isDirectory: true)
        let legacyDatabaseInOldDirectory = legacyDirectory.appendingPathComponent(legacyFileName)
        let legacyDatabaseInNewDirectory = streamlyDirectory.appendingPathComponent(legacyFileName)
        let streamlyDatabase = streamlyDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: legacyDirectory.path), !fileManager.fileExists(atPath: streamlyDirectory.path) {
            try fileManager.moveItem(at: legacyDirectory, to: streamlyDirectory)
        }

        if fileManager.fileExists(atPath: legacyDatabaseInOldDirectory.path), !fileManager.fileExists(atPath: streamlyDatabase.path) {
            try fileManager.createDirectory(at: streamlyDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacyDatabaseInOldDirectory, to: streamlyDatabase)
        }

        if fileManager.fileExists(atPath: legacyDatabaseInNewDirectory.path), !fileManager.fileExists(atPath: streamlyDatabase.path) {
            try fileManager.moveItem(at: legacyDatabaseInNewDirectory, to: streamlyDatabase)
        }
    }
}
