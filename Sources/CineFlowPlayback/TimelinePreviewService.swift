import AppKit
import AVFoundation
import CineFlowCore
import Foundation

public protocol TimelineFrameGenerating: Sendable {
    func frameData(for url: URL, at seconds: Double, width: Int, height: Int) async throws -> Data
}

public struct AVAssetTimelineFrameGenerator: TimelineFrameGenerating {
    public init() {}

    public func frameData(for url: URL, at seconds: Double, width: Int, height: Int) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: width, height: height)
            let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
            guard
                let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData),
                let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
            else {
                throw PlaybackServiceError.unsupported(operation: "timeline preview encoding")
            }
            return data
        }.value
    }
}

public struct TimelinePreviewCache {
    public let storageURL: URL
    private let fileManager: FileManager

    public init(
        storageURL: URL = SmartCacheScope.defaultTimelinePreviewCacheURL(),
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    public func cachedPreview(for request: TimelinePreviewRequest) throws -> TimelinePreview? {
        let url = cacheURL(for: request)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return TimelinePreview(
            mediaID: request.mediaID,
            timeSeconds: request.roundedTimeSeconds,
            imageData: data,
            source: .cache,
            cacheURL: url
        )
    }

    public func store(_ data: Data, for request: TimelinePreviewRequest) throws -> TimelinePreview {
        let url = cacheURL(for: request)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return TimelinePreview(
            mediaID: request.mediaID,
            timeSeconds: request.roundedTimeSeconds,
            imageData: data,
            source: .generated,
            cacheURL: url
        )
    }

    public func clear() throws {
        try? fileManager.removeItem(at: storageURL)
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
    }

    private func cacheURL(for request: TimelinePreviewRequest) -> URL {
        storageURL
            .appendingPathComponent(sanitized(request.mediaID), isDirectory: true)
            .appendingPathComponent("\(stableHash(request.mediaURL.absoluteString))-\(Int(request.roundedTimeSeconds)).jpg")
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0).description : "_" }.joined()
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5_381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

public actor TimelinePreviewService: TimelinePreviewServiceProtocol {
    private let cache: TimelinePreviewCache
    private let generator: any TimelineFrameGenerating

    public init(
        cache: TimelinePreviewCache = TimelinePreviewCache(),
        generator: any TimelineFrameGenerating = AVAssetTimelineFrameGenerator()
    ) {
        self.cache = cache
        self.generator = generator
    }

    public func preview(for request: TimelinePreviewRequest) async throws -> TimelinePreview? {
        guard request.isTimeAvailable else { return nil }
        guard request.mediaURL.isFileURL || request.mediaURL.isLocalNetworkURL else { return nil }
        if let cached = try cache.cachedPreview(for: request) {
            return cached
        }
        let data = try await generator.frameData(
            for: request.mediaURL,
            at: request.roundedTimeSeconds,
            width: request.width,
            height: request.height
        )
        return try cache.store(data, for: request)
    }

    public func clearPreviewCache() async throws {
        try cache.clear()
    }
}

private extension URL {
    var isLocalNetworkURL: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
