import CineFlowCore
import CineFlowLocalization
import CineFlowSources
import Foundation

@MainActor
public final class CineFlowRootViewModel: ObservableObject {
    @Published public private(set) var headline = L10n.string(.appName)
    @Published public private(set) var releaseYear: Int?
    @Published public private(set) var mediaKind: MediaKind?
    @Published public private(set) var bestReleaseTitle: String?
    @Published public private(set) var bestReleaseSeeders: Int?
    @Published public private(set) var subtitleLanguagePriority: [String] = []
    @Published public private(set) var subtitleSettings = SubtitleSettings()
    @Published public private(set) var didLoadMetadata = false
    @Published public private(set) var didFailToLoad = false
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var imageCacheSizeBytes: Int64?
    @Published public private(set) var imageCacheErrorDescription: String?
    @Published public private(set) var isClearingImageCache = false

    private let environment: AppEnvironment
    private let sourceManager: SourceManager?

    public init(environment: AppEnvironment, sourceManager: SourceManager? = nil) {
        self.environment = environment
        self.sourceManager = sourceManager
    }

    public var playbackService: any PlaybackServiceProtocol {
        environment.playbackService
    }

    public func updateSubtitleSettings(_ settings: SubtitleSettings) async {
        await environment.settingsRepository.setSubtitleSettings(settings)
        subtitleSettings = settings
        subtitleLanguagePriority = settings.languagePreference.languageCodes
    }

    public func load() async {
        do {
            let items = try await environment.metadataService.search(query: "matrix")
            guard let item = items.first else {
                headline = L10n.string(.appName)
                didLoadMetadata = false
                didFailToLoad = false
                return
            }

            let autoSource: PlaybackAutoSourceResolution?
            if let sourceManager {
                autoSource = await PlaybackAutoSourceResolver(
                    metadataService: environment.metadataService,
                    sourceManager: sourceManager,
                    diagnosticsService: environment.diagnosticsService
                ).resolveBestRelease(mediaID: item.id, selectionContext: nil)
            } else {
                autoSource = nil
            }
            let legacyReleases = autoSource == nil ? (try await environment.torrentEngine.searchReleases(for: item)) : []
            let languages = await environment.settingsRepository.subtitleLanguagePriority
            let subtitleSettings = await environment.settingsRepository.subtitleSettings

            headline = item.title
            releaseYear = item.releaseYear
            mediaKind = item.kind
            bestReleaseTitle = autoSource?.release.title ?? legacyReleases.first?.title
            bestReleaseSeeders = autoSource?.release.seeders ?? legacyReleases.first?.seeders
            subtitleLanguagePriority = languages
            self.subtitleSettings = subtitleSettings
            didLoadMetadata = true
            didFailToLoad = false
            errorDescription = nil
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .metadata)
            await environment.diagnosticsService.log(cineFlowError, operation: "root.load")
            headline = L10n.string(.appName)
            didLoadMetadata = false
            didFailToLoad = true
            errorDescription = cineFlowError.userMessage
        }
    }

    public var imageCacheSizeLabel: String {
        guard let imageCacheSizeBytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: imageCacheSizeBytes, countStyle: .file)
    }

    public func refreshImageCacheSize() async {
        guard let imageCacheService = environment.imageCacheService else {
            imageCacheSizeBytes = nil
            imageCacheErrorDescription = nil
            return
        }

        do {
            imageCacheSizeBytes = try await imageCacheService.cacheSizeBytes()
            imageCacheErrorDescription = nil
        } catch {
            await handleImageCacheError(error, operation: "imageCache.size")
        }
    }

    public func clearImageCache() async {
        guard let imageCacheService = environment.imageCacheService else { return }

        isClearingImageCache = true
        defer { isClearingImageCache = false }

        do {
            try await imageCacheService.clearAll()
            imageCacheSizeBytes = try await imageCacheService.cacheSizeBytes()
            imageCacheErrorDescription = nil
        } catch {
            await handleImageCacheError(error, operation: "imageCache.clearAll")
        }
    }

    public func clearUnusedImageCache() async {
        guard let imageCacheService = environment.imageCacheService else { return }

        isClearingImageCache = true
        defer { isClearingImageCache = false }

        do {
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            try await imageCacheService.clearUnused(olderThan: cutoff)
            imageCacheSizeBytes = try await imageCacheService.cacheSizeBytes()
            imageCacheErrorDescription = nil
        } catch {
            await handleImageCacheError(error, operation: "imageCache.clearUnused")
        }
    }

    private func handleImageCacheError(_ error: Error, operation: String) async {
        let cineFlowError = CineFlowError.from(error, fallbackCategory: .cache)
        await environment.diagnosticsService.log(cineFlowError, operation: operation)
        imageCacheErrorDescription = cineFlowError.userMessage
    }
}
