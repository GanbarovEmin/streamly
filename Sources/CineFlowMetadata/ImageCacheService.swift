import CineFlowCore
import CineFlowDatabase
import Foundation

public struct ImageCacheConfiguration: Sendable {
    public let cacheDirectory: URL
    public let maxCacheSizeBytes: Int64?

    public init(cacheDirectory: URL = Self.defaultCacheDirectory, maxCacheSizeBytes: Int64? = nil) {
        self.cacheDirectory = cacheDirectory
        self.maxCacheSizeBytes = maxCacheSizeBytes
    }

    public static var defaultCacheDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Streamly", isDirectory: true)
            .appendingPathComponent("ImageCache", isDirectory: true)
    }
}

public enum ImageCacheError: LocalizedError, Equatable {
    case invalidResponse
    case requestFailed(Int)
    case networkUnavailable
    case fileSystemFailure

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Image response was invalid."
        case let .requestFailed(statusCode):
            "Image request failed with HTTP \(statusCode)."
        case .networkUnavailable:
            "Network is unavailable."
        case .fileSystemFailure:
            "Image cache file operation failed."
        }
    }
}

extension ImageCacheError: CineFlowErrorConvertible {
    public var cineFlowError: CineFlowError {
        switch self {
        case .networkUnavailable:
            CineFlowError(
                category: .network,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: CineFlowError.defaultUserMessage(for: .network),
                recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .network),
                logLevel: .warning
            )
        default:
            CineFlowError(
                category: .cache,
                technicalDescription: errorDescription ?? String(describing: self),
                userMessage: CineFlowError.defaultUserMessage(for: .cache),
                recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .cache),
                logLevel: CineFlowError.defaultLogLevel(for: .cache)
            )
        }
    }
}

public actor ImageCacheService: ImageCacheServiceProtocol {
    private let cacheRepository: CacheRepository
    private let configuration: ImageCacheConfiguration
    private let session: URLSession
    private let fileManager: FileManager
    private var memoryCache: [URL: Data] = [:]

    public init(
        cacheRepository: CacheRepository,
        configuration: ImageCacheConfiguration = ImageCacheConfiguration(),
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.cacheRepository = cacheRepository
        self.configuration = configuration
        self.session = session
        self.fileManager = fileManager
    }

    public var memoryCacheCount: Int {
        memoryCache.count
    }

    public func imageData(for url: URL, kind: CachedImageKind) async throws -> Data {
        if let data = memoryCache[url] {
            _ = try await cacheRepository.cachedImageRecord(url: url.absoluteString, touch: true)
            return data
        }

        if let record = try await cacheRepository.cachedImageRecord(url: url.absoluteString, touch: true),
           fileManager.fileExists(atPath: record.localPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: record.localPath)) {
            memoryCache[url] = data
            return data
        }

        let data = try await downloadImageData(from: url)
        let fileURL = cacheFileURL(for: url, kind: kind)

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ImageCacheError.fileSystemFailure
        }

        let now = ISO8601DateFormatter().string(from: Date())
        try await cacheRepository.upsertCachedImage(
            url: url.absoluteString,
            localPath: fileURL.path,
            fileSize: Int64(data.count),
            createdAt: now,
            lastAccessedAt: now
        )
        memoryCache[url] = data
        try await enforceMaxCacheSize()
        return data
    }

    public func cacheSizeBytes() async throws -> Int64 {
        try await cacheRepository.imageCacheSizeBytes()
    }

    public func clearAll() async throws {
        for record in try await cacheRepository.cachedImageRecords() {
            removeFile(atPath: record.localPath)
        }
        try await cacheRepository.clearImageCache()
        memoryCache.removeAll()
    }

    public func clearUnused(olderThan date: Date) async throws {
        let cutoff = ISO8601DateFormatter().string(from: date)
        let records = try await cacheRepository.cachedImageRecordsUnused(before: cutoff)

        for record in records {
            removeFile(atPath: record.localPath)
            try await cacheRepository.removeCachedImage(url: record.url)
            if let url = URL(string: record.url) {
                memoryCache.removeValue(forKey: url)
            }
        }
    }

    private func downloadImageData(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImageCacheError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ImageCacheError.requestFailed(httpResponse.statusCode)
            }

            return data
        } catch let error as ImageCacheError {
            throw error
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw ImageCacheError.networkUnavailable
        } catch {
            throw error
        }
    }

    private func enforceMaxCacheSize() async throws {
        guard let maxCacheSizeBytes = configuration.maxCacheSizeBytes else { return }

        var currentSize = try await cacheRepository.imageCacheSizeBytes()
        guard currentSize > maxCacheSizeBytes else { return }

        for record in try await cacheRepository.cachedImageRecords() {
            guard currentSize > maxCacheSizeBytes else { break }

            removeFile(atPath: record.localPath)
            try await cacheRepository.removeCachedImage(url: record.url)
            currentSize -= record.fileSize
            if let url = URL(string: record.url) {
                memoryCache.removeValue(forKey: url)
            }
        }
    }

    private func cacheFileURL(for url: URL, kind: CachedImageKind) -> URL {
        let extensionCandidate = url.pathExtension.isEmpty ? "img" : url.pathExtension
        let filename = "\(Self.cacheKey(for: url)).\(extensionCandidate)"
        return configuration.cacheDirectory
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(filename)
    }

    private func removeFile(atPath path: String) {
        try? fileManager.removeItem(atPath: path)
    }

    private static func cacheKey(for url: URL) -> String {
        Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
