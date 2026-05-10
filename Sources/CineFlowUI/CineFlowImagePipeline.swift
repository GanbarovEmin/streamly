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

        activeRequestCount += 1
        defer { activeRequestCount = max(0, activeRequestCount - 1) }

        let data: Data
        if let imageCacheService {
            data = try await imageCacheService.imageData(for: url, kind: .poster)
        } else {
            data = try await fallbackLoader(url)
        }

        store(data, for: url)
        loadedImageCount += 1
        return data
    }

    public func prefetch(_ urls: [URL], limit: Int = 18) async {
        let candidates = Array(urls.filter { memoryCache[$0] == nil }.prefix(limit))
        guard !candidates.isEmpty else { return }

        for url in candidates {
            guard !Task.isCancelled else { return }
            _ = try? await data(for: url)
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
