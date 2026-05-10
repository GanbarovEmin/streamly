import CineFlowCore
import CineFlowDesignSystem
import Foundation

@MainActor
public final class CineFlowImagePipeline: ObservableObject {
    @Published public private(set) var loadedImageCount = 0
    @Published public private(set) var activeRequestCount = 0

    private let imageCacheService: (any ImageCacheServiceProtocol)?
    private let fallbackLoader: CFImageDataLoader
    private var memoryCache: [URL: Data] = [:]
    private var memoryOrder: [URL] = []
    private var inFlightRequests: [URL: Task<Data, Error>] = [:]
    private let memoryLimit: Int

    public init(
        imageCacheService: (any ImageCacheServiceProtocol)? = nil,
        memoryLimit: Int = 160,
        fallbackLoader: CFImageDataLoader? = nil
    ) {
        self.imageCacheService = imageCacheService
        self.memoryLimit = memoryLimit
        self.fallbackLoader = fallbackLoader ?? { url in
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        }
    }

    public func data(for url: URL) async throws -> Data {
        if let cached = memoryCache[url] {
            return cached
        }
        if let inFlightRequest = inFlightRequests[url] {
            return try await inFlightRequest.value
        }

        activeRequestCount += 1
        let request = Task<Data, Error> { [imageCacheService, fallbackLoader] in
            if let imageCacheService {
                return try await imageCacheService.imageData(for: url, kind: .poster)
            }
            return try await fallbackLoader(url)
        }
        inFlightRequests[url] = request
        defer {
            inFlightRequests[url] = nil
            activeRequestCount = max(0, activeRequestCount - 1)
        }

        let data = try await request.value
        store(data, for: url)
        loadedImageCount += 1
        return data
    }

    public func prefetch(_ urls: [URL], limit: Int = 18) async {
        let candidates = Array(urls.filter { memoryCache[$0] == nil }.prefix(limit))
        guard !candidates.isEmpty else { return }

        let batchSize = 4
        for startIndex in stride(from: 0, to: candidates.count, by: batchSize) {
            guard !Task.isCancelled else { return }
            let batch = candidates[startIndex..<min(startIndex + batchSize, candidates.count)]
            await withTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask { [weak self] in
                        _ = try? await self?.data(for: url)
                    }
                }
            }
        }
    }

    public func clearMemoryCache() {
        memoryCache.removeAll(keepingCapacity: true)
        memoryOrder.removeAll(keepingCapacity: true)
        loadedImageCount = 0
    }

    private func store(_ data: Data, for url: URL) {
        if memoryCache[url] == nil {
            memoryOrder.append(url)
        }
        memoryCache[url] = data

        while memoryOrder.count > memoryLimit, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
    }
}
