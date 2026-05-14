import XCTest
@testable import CineFlowCore
@testable import CineFlowDatabase
@testable import CineFlowMetadata

final class ImageCacheServiceTests: XCTestCase {
    override func tearDown() {
        ImageCacheURLProtocol.reset()
        super.tearDown()
    }

    func testDownloadsImageOnceThenUsesMemoryAndDiskCacheAcrossServiceRestart() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let databaseURL = workspace.appendingPathComponent("CineFlow.sqlite")
        var databaseManager: DatabaseManager? = try DatabaseManager(path: databaseURL.path)
        let repository = CacheRepository(databaseManager: databaseManager!)
        let posterURL = URL(string: "https://image.tmdb.org/t/p/w500/poster.jpg")!
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        let requestCounter = LockedCounter()

        ImageCacheURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url, posterURL)
            requestCounter.increment()
            return (200, imageData)
        }

        let service = ImageCacheService(
            cacheRepository: repository,
            configuration: ImageCacheConfiguration(cacheDirectory: workspace.appendingPathComponent("ImageCache")),
            session: Self.urlProtocolSession()
        )

        let firstLoad = try await service.imageData(for: posterURL, kind: .poster)
        let secondLoad = try await service.imageData(for: posterURL, kind: .poster)

        XCTAssertEqual(firstLoad, imageData)
        XCTAssertEqual(secondLoad, imageData)
        XCTAssertEqual(requestCounter.value, 1)
        let memoryCacheCount = await service.memoryCacheCount
        let cacheSize = try await service.cacheSizeBytes()
        XCTAssertEqual(memoryCacheCount, 1)
        XCTAssertEqual(cacheSize, Int64(imageData.count))

        databaseManager = nil
        let reopenedRepository = CacheRepository(databaseManager: try DatabaseManager(path: databaseURL.path))
        ImageCacheURLProtocol.requestHandler = { _ in
            XCTFail("Expected disk cache hit after service restart")
            return (200, Data())
        }
        let restartedService = ImageCacheService(
            cacheRepository: reopenedRepository,
            configuration: ImageCacheConfiguration(cacheDirectory: workspace.appendingPathComponent("ImageCache")),
            session: Self.urlProtocolSession()
        )

        let restartedLoad = try await restartedService.imageData(for: posterURL, kind: .poster)
        XCTAssertEqual(restartedLoad, imageData)
        XCTAssertEqual(requestCounter.value, 1)
    }

    func testClearAllAndClearUnusedRemoveFilesMetadataAndMemory() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let repository = CacheRepository(databaseManager: try DatabaseManager.inMemory())
        let oldURL = URL(string: "https://image.tmdb.org/t/p/w500/old.jpg")!
        let recentURL = URL(string: "https://image.tmdb.org/t/p/w500/recent.jpg")!
        let payloads: [URL: Data] = [
            oldURL: Data([1, 2, 3]),
            recentURL: Data([4, 5, 6, 7])
        ]

        ImageCacheURLProtocol.requestHandler = { request in
            (200, payloads[request.url!] ?? Data())
        }

        let service = ImageCacheService(
            cacheRepository: repository,
            configuration: ImageCacheConfiguration(cacheDirectory: workspace.appendingPathComponent("ImageCache")),
            session: Self.urlProtocolSession()
        )

        _ = try await service.imageData(for: oldURL, kind: .poster)
        let fetchedOldRecord = try await repository.cachedImageRecord(url: oldURL.absoluteString)
        let oldRecordBeforeRewrite = try XCTUnwrap(fetchedOldRecord)
        try await repository.upsertCachedImage(
            url: oldURL.absoluteString,
            localPath: oldRecordBeforeRewrite.localPath,
            fileSize: 3,
            createdAt: "2024-01-01T00:00:00Z",
            lastAccessedAt: "2024-01-01T00:00:00Z"
        )
        _ = try await service.imageData(for: recentURL, kind: .poster)

        try await service.clearUnused(olderThan: ISO8601DateFormatter().date(from: "2024-06-01T00:00:00Z")!)
        let oldRecordAfterClearUnused = try await repository.cachedImageRecord(url: oldURL.absoluteString)
        let recentRecordAfterClearUnused = try await repository.cachedImageRecord(url: recentURL.absoluteString)
        XCTAssertNil(oldRecordAfterClearUnused)
        XCTAssertNotNil(recentRecordAfterClearUnused)

        _ = try await service.imageData(for: oldURL, kind: .poster)
        let repopulatedCacheSize = try await service.cacheSizeBytes()
        XCTAssertGreaterThan(repopulatedCacheSize, 0)

        try await service.clearAll()
        let clearedCacheSize = try await service.cacheSizeBytes()
        let clearedMemoryCacheCount = await service.memoryCacheCount
        XCTAssertEqual(clearedCacheSize, 0)
        XCTAssertEqual(clearedMemoryCacheCount, 0)
    }

    func testMaxCacheSizeTrimsLeastRecentlyAccessedImages() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let repository = CacheRepository(databaseManager: try DatabaseManager.inMemory())
        let firstURL = URL(string: "https://image.tmdb.org/t/p/w500/first.jpg")!
        let secondURL = URL(string: "https://image.tmdb.org/t/p/w500/second.jpg")!

        ImageCacheURLProtocol.requestHandler = { request in
            switch request.url {
            case firstURL:
                return (200, Data(repeating: 1, count: 6))
            case secondURL:
                return (200, Data(repeating: 2, count: 6))
            default:
                return (404, Data())
            }
        }

        let service = ImageCacheService(
            cacheRepository: repository,
            configuration: ImageCacheConfiguration(
                cacheDirectory: workspace.appendingPathComponent("ImageCache"),
                maxCacheSizeBytes: 8
            ),
            session: Self.urlProtocolSession()
        )

        _ = try await service.imageData(for: firstURL, kind: .poster)
        _ = try await service.imageData(for: secondURL, kind: .poster)

        let firstRecord = try await repository.cachedImageRecord(url: firstURL.absoluteString)
        let secondRecord = try await repository.cachedImageRecord(url: secondURL.absoluteString)
        let cacheSize = try await service.cacheSizeBytes()
        XCTAssertNil(firstRecord)
        XCTAssertNotNil(secondRecord)
        XCTAssertLessThanOrEqual(cacheSize, 8)
    }

    func testBrokenImageIsNotDownloadedRepeatedlyAndCachedRecordIsRemoved() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let repository = CacheRepository(databaseManager: try DatabaseManager.inMemory())
        let brokenURL = URL(string: "https://image.tmdb.org/t/p/w500/broken.jpg")!
        let requestCounter = LockedCounter()

        ImageCacheURLProtocol.requestHandler = { _ in
            requestCounter.increment()
            return (404, Data())
        }

        let service = ImageCacheService(
            cacheRepository: repository,
            configuration: ImageCacheConfiguration(cacheDirectory: workspace.appendingPathComponent("ImageCache")),
            session: Self.urlProtocolSession()
        )

        await XCTAssertThrowsErrorAsync(try await service.imageData(for: brokenURL, kind: .poster))
        await XCTAssertThrowsErrorAsync(try await service.imageData(for: brokenURL, kind: .poster))

        XCTAssertEqual(requestCounter.value, 1)
        let cachedRecord = try await repository.cachedImageRecord(url: brokenURL.absoluteString)
        XCTAssertNil(cachedRecord)
    }

    private static func urlProtocolSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageCacheURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Sendable,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async error", file: file, line: line)
    } catch {}
}

private final class ImageCacheURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: (@Sendable (URLRequest) throws -> (Int, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (status, data) = try requestHandler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
