import CineFlowCore
import Foundation
import XCTest
@testable import CineFlowUI

@MainActor
final class CineFlowImagePipelineTests: XCTestCase {
    func testImagePipelineUsesCacheServiceAndAvoidsDuplicateMemoryLoads() async throws {
        let service = CountingImageCacheService(data: Data([0x01, 0x02, 0x03]))
        let pipeline = CineFlowImagePipeline(imageCacheService: service)
        let url = URL(string: "https://images.example.com/poster.jpg")!

        let first = try await pipeline.data(for: url)
        let second = try await pipeline.data(for: url)

        XCTAssertEqual(first, second)
        XCTAssertEqual(pipeline.loadedImageCount, 1)
        XCTAssertEqual(pipeline.activeRequestCount, 0)
        let requestCount = await service.requests()
        XCTAssertEqual(requestCount, 1)
    }

    func testPrefetchWarmsMemoryCacheWithLimit() async {
        let service = CountingImageCacheService(data: Data([0x04]))
        let pipeline = CineFlowImagePipeline(imageCacheService: service)
        let urls = (0..<5).map { URL(string: "https://images.example.com/poster-\($0).jpg")! }

        await pipeline.prefetch(urls, limit: 3)
        _ = try? await pipeline.data(for: urls[0])

        XCTAssertEqual(pipeline.loadedImageCount, 3)
        let requestCount = await service.requests()
        XCTAssertEqual(requestCount, 3)
    }
}

private actor CountingImageCacheService: ImageCacheServiceProtocol {
    private let data: Data
    private(set) var requestCount = 0

    init(data: Data) {
        self.data = data
    }

    func imageData(for url: URL, kind: CachedImageKind) async throws -> Data {
        requestCount += 1
        return data
    }

    func cacheSizeBytes() async throws -> Int64 {
        Int64(data.count)
    }

    func clearAll() async throws {}

    func clearUnused(olderThan date: Date) async throws {}

    func requests() -> Int {
        requestCount
    }
}
