import CineFlowCore
import Foundation

public protocol OpenSubtitlesTokenProviding: Sendable {
    func apiToken() async throws -> String?
}

public struct EnvironmentOpenSubtitlesTokenProvider: OpenSubtitlesTokenProviding {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func apiToken() async throws -> String? {
        environment["OPENSUBTITLES_API_TOKEN"]?.nilIfBlank
    }
}

public protocol OpenSubtitlesClientProtocol: Sendable {
    func search(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult]
    func download(result: SubtitleSearchResult) async throws -> Data
}

public struct OpenSubtitlesClient: OpenSubtitlesClientProtocol {
    private let tokenProvider: any OpenSubtitlesTokenProviding

    public init(tokenProvider: any OpenSubtitlesTokenProviding = EnvironmentOpenSubtitlesTokenProvider()) {
        self.tokenProvider = tokenProvider
    }

    public func search(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        guard try await tokenProvider.apiToken() != nil else {
            throw SubtitleServiceError.openSubtitlesCredentialsMissing
        }
        return []
    }

    public func download(result: SubtitleSearchResult) async throws -> Data {
        guard try await tokenProvider.apiToken() != nil else {
            throw SubtitleServiceError.openSubtitlesCredentialsMissing
        }
        guard result.downloadURL != nil else {
            throw SubtitleServiceError.missingDownloadURL(result.id)
        }
        return Data()
    }
}

public struct MockOpenSubtitlesClient: OpenSubtitlesClientProtocol {
    private let results: [SubtitleSearchResult]
    private let downloadData: Data

    public init(results: [SubtitleSearchResult] = [], downloadData: Data = Data("mock subtitle".utf8)) {
        self.results = results
        self.downloadData = downloadData
    }

    public func search(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        results.filter { languages.isEmpty || languages.contains($0.languageCode) }
    }

    public func download(result: SubtitleSearchResult) async throws -> Data {
        downloadData
    }
}

public struct SubtitleCache {
    public let storageURL: URL
    private let fileManager: FileManager

    public init(storageURL: URL = Self.defaultStorageURL(), fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileManager = fileManager
    }

    public static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("Streamly", isDirectory: true)
            .appendingPathComponent("Subtitles", isDirectory: true)
    }

    public func store(data: Data, fileName: String) throws -> URL {
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let safeName = fileName.replacingOccurrences(of: "/", with: "-")
        let url = storageURL.appendingPathComponent(safeName)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func list() throws -> [CachedSubtitleItem] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return try urls
            .filter { ["srt", "ass"].contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                let values = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile != false else { return nil }
                return CachedSubtitleItem(
                    id: url.standardizedFileURL.path,
                    fileName: url.lastPathComponent,
                    languageCode: Self.languageCode(from: url) ?? "und",
                    fileExtension: url.pathExtension,
                    sizeBytes: Int64(values.fileSize ?? 0),
                    createdAt: values.creationDate,
                    url: url
                )
            }
            .sorted { lhs, rhs in
                lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
    }

    public func delete(id: String) throws {
        let target = URL(fileURLWithPath: id).standardizedFileURL
        let root = storageURL.standardizedFileURL.path
        guard target.path.hasPrefix(root) else {
            throw SubtitleServiceError.invalidSubtitleFile(target)
        }
        guard ["srt", "ass"].contains(target.pathExtension.lowercased()) else {
            throw SubtitleServiceError.invalidSubtitleFile(target)
        }
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }

    private static func languageCode(from url: URL) -> String? {
        url.deletingPathExtension().lastPathComponent
            .split(separator: ".")
            .map { String($0).lowercased() }
            .reversed()
            .first { $0.count == 2 || $0.count == 3 }
    }
}

public enum SubtitleFileHasher {
    public static func openSubtitlesHash(for url: URL, fileManager: FileManager = .default) throws -> String? {
        guard url.isFileURL else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile != false,
              let fileSize = values.fileSize,
              fileSize >= 131_072
        else {
            return nil
        }

        let chunkSize = 65_536
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hash = UInt64(fileSize)
        let firstChunk = handle.readData(ofLength: chunkSize)
        hash = hash &+ chunkHash(firstChunk)
        try handle.seek(toOffset: UInt64(fileSize - chunkSize))
        let lastChunk = handle.readData(ofLength: chunkSize)
        hash = hash &+ chunkHash(lastChunk)
        return String(format: "%016llx", hash)
    }

    private static func chunkHash(_ data: Data) -> UInt64 {
        let bytes = Array(data)
        var hash: UInt64 = 0
        var index = 0
        while index + 8 <= bytes.count {
            var value: UInt64 = 0
            for offset in 0..<8 {
                value |= UInt64(bytes[index + offset]) << UInt64(offset * 8)
            }
            hash = hash &+ value
            index += 8
        }
        return hash
    }
}

public struct SubtitleMatcher: Sendable {
    private let languagePreference: SubtitleLanguagePreference

    public init(languagePreference: SubtitleLanguagePreference = SubtitleLanguagePreference()) {
        self.languagePreference = languagePreference
    }

    public func score(_ result: SubtitleSearchResult, for query: SubtitleSearchQuery) -> Double {
        var score = result.score
        let title = query.title.normalizedSubtitleMatchText
        let resultTitle = result.title.normalizedSubtitleMatchText

        if resultTitle.contains(title) || title.contains(resultTitle) {
            score += 100
        }
        if let year = query.year, result.year == year {
            score += 40
        }
        if let season = query.season, result.season == season {
            score += 35
        }
        if let episode = query.episode, result.episode == episode {
            score += 35
        }
        if let fileHash = query.fileHash, result.fileHash == fileHash {
            score += 120
        }
        score += Double(max(0, 20 - languagePreference.priority(for: result.languageCode) * 8))
        return score
    }
}

public struct SubtitleService: SubtitleServiceProtocol {
    private let openSubtitlesClient: any OpenSubtitlesClientProtocol
    private let cache: SubtitleCache
    private let settings: SubtitleSettings
    private let matcher: SubtitleMatcher

    public init(
        openSubtitlesClient: any OpenSubtitlesClientProtocol = OpenSubtitlesClient(),
        cache: SubtitleCache = SubtitleCache(),
        settings: SubtitleSettings = SubtitleSettings()
    ) {
        self.openSubtitlesClient = openSubtitlesClient
        self.cache = cache
        self.settings = settings
        self.matcher = SubtitleMatcher(languagePreference: settings.languagePreference)
    }

    public func preferredSubtitles(for item: MediaItem) async throws -> [SubtitleTrack] {
        let query = SubtitleSearchQuery(title: item.title, year: item.releaseYear)
        return try await preferredSubtitles(for: query, embeddedTracks: [], localSearchDirectory: nil)
    }

    public func preferredSubtitles(
        for query: SubtitleSearchQuery,
        embeddedTracks: [SubtitleTrack],
        localSearchDirectory: URL?
    ) async throws -> [SubtitleTrack] {
        guard settings.autoLoadSubtitles else { return [] }

        let local = try await localSubtitles(for: query, directory: localSearchDirectory)
        let onlineResults = try await searchOnlineSubtitles(
            query: query,
            languages: settings.languagePreference.languageCodes
        )
        let onlineTracks = onlineResults.map { result in
            SubtitleTrack(
                id: result.id,
                languageCode: result.languageCode,
                displayName: result.title,
                source: result.source,
                externalID: result.id
            )
        }

        return (embeddedTracks + local + onlineTracks).sorted { lhs, rhs in
            if lhs.isForced != rhs.isForced {
                return lhs.isForced
            }
            let sourceDifference = sourcePriority(lhs.source) - sourcePriority(rhs.source)
            if sourceDifference != 0 {
                return sourceDifference < 0
            }
            return settings.languagePreference.priority(for: lhs.languageCode)
                < settings.languagePreference.priority(for: rhs.languageCode)
        }
    }

    public func embeddedSubtitles(from playbackStatus: PlaybackStatus) async throws -> [SubtitleTrack] {
        playbackStatus.subtitleTracks.filter { $0.source == .embedded }
    }

    public func localSubtitles(for query: SubtitleSearchQuery, directory: URL?) async throws -> [SubtitleTrack] {
        let searchDirectories = [
            directory,
            query.localVideoURL?.deletingLastPathComponent(),
            cache.storageURL
        ]
            .compactMap { $0 }
            .reduce(into: [URL]()) { directories, url in
                if !directories.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    directories.append(url)
                }
            }

        let urls = searchDirectories.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
        }

        return urls
            .filter { ["srt", "ass"].contains($0.pathExtension.lowercased()) }
            .filter { matchesLocalSubtitle($0, query: query) }
            .map(localTrack)
    }

    public func searchOnlineSubtitles(query: SubtitleSearchQuery, languages: [String]) async throws -> [SubtitleSearchResult] {
        guard settings.autoSearchSubtitles else { return [] }
        let effectiveQuery = queryWithFileHashIfAvailable(query)
        return try await openSubtitlesClient.search(query: effectiveQuery, languages: languages)
            .map { result in
                var copy = result
                let rankedScore = matcher.score(result, for: effectiveQuery)
                copy = SubtitleSearchResult(
                    id: result.id,
                    title: result.title,
                    languageCode: result.languageCode,
                    source: result.source,
                    score: rankedScore,
                    downloadURL: result.downloadURL,
                    year: result.year,
                    season: result.season,
                    episode: result.episode,
                    fileHash: result.fileHash
                )
                return copy
            }
            .sorted { $0.score > $1.score }
    }

    public func downloadSubtitle(_ result: SubtitleSearchResult) async throws -> SubtitleTrack {
        guard result.downloadURL != nil else {
            throw SubtitleServiceError.missingDownloadURL(result.id)
        }
        let data = try await openSubtitlesClient.download(result: result)
        let subtitleExtension = subtitleFileExtension(from: result.downloadURL) ?? "srt"
        return try await cacheSubtitle(
            data: data,
            fileName: "\(safeFileName(result.title)).\(result.languageCode).\(subtitleExtension)",
            languageCode: result.languageCode,
            source: result.source
        )
    }

    public func cacheSubtitle(
        data: Data,
        fileName: String,
        languageCode: String,
        source: SubtitleSource
    ) async throws -> SubtitleTrack {
        let url = try cache.store(data: data, fileName: fileName)
        return SubtitleTrack(
            id: "cached:\(url.lastPathComponent)",
            languageCode: languageCode,
            displayName: url.deletingPathExtension().lastPathComponent,
            source: source,
            localURL: url
        )
    }

    public func selectSubtitle(_ track: SubtitleTrack?, playbackService: any PlaybackServiceProtocol) async throws {
        try await playbackService.selectSubtitleTrack(id: track?.id)
    }

    public func cachedSubtitles() async throws -> [CachedSubtitleItem] {
        try cache.list()
    }

    public func deleteCachedSubtitle(id: String) async throws {
        try cache.delete(id: id)
    }

    private func matchesLocalSubtitle(_ url: URL, query: SubtitleSearchQuery) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.normalizedSubtitleMatchText
        return name.contains(query.title.normalizedSubtitleMatchText) || query.localVideoURL == nil
    }

    private func localTrack(_ url: URL) -> SubtitleTrack {
        let languageCode = languageCodeFromFileName(url) ?? "und"
        return SubtitleTrack(
            id: "local:\(url.path)",
            languageCode: languageCode,
            displayName: url.lastPathComponent,
            source: .localFile,
            localURL: url
        )
    }

    private func languageCodeFromFileName(_ url: URL) -> String? {
        let parts = url.deletingPathExtension().lastPathComponent
            .split(separator: ".")
            .map { String($0).lowercased() }
        return parts.reversed().first { $0.count == 2 || $0.count == 3 }
    }

    private func sourcePriority(_ source: SubtitleSource) -> Int {
        switch source {
        case .embedded:
            0
        case .localFile:
            1
        case .openSubtitles:
            2
        }
    }

    private func safeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? UUID().uuidString : trimmed
        return name.replacingOccurrences(of: "[^A-Za-z0-9._ -]+", with: "-", options: .regularExpression)
    }

    private func subtitleFileExtension(from url: URL?) -> String? {
        guard let ext = url?.pathExtension.lowercased(), ["srt", "ass"].contains(ext) else { return nil }
        return ext
    }

    private func queryWithFileHashIfAvailable(_ query: SubtitleSearchQuery) -> SubtitleSearchQuery {
        guard query.fileHash == nil,
              let localVideoURL = query.localVideoURL,
              let hash = try? SubtitleFileHasher.openSubtitlesHash(for: localVideoURL)
        else {
            return query
        }

        return SubtitleSearchQuery(
            title: query.title,
            year: query.year,
            season: query.season,
            episode: query.episode,
            fileHash: hash,
            localVideoURL: query.localVideoURL
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var normalizedSubtitleMatchText: String {
        lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
