import CineFlowCore
import Foundation

public enum TorrentioProviderOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case rutor
    case rutracker

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rutor:
            "Rutor"
        case .rutracker:
            "RuTracker"
        }
    }
}

public enum TorrentioPriorityLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case russian

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            "None"
        case .russian:
            "Russian"
        }
    }
}

public enum TorrentioExcludedQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case screener = "scr"
    case cam
    case fourK = "4k"
    case fullHD = "1080p"
    case hd = "720p"
    case sd = "480p"
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .screener:
            "Screener"
        case .cam:
            "Cam"
        case .fourK:
            "4K"
        case .fullHD:
            "1080p"
        case .hd:
            "720p"
        case .sd:
            "480p"
        case .unknown:
            "Unknown"
        }
    }
}

public struct TorrentioSettings: Codable, Equatable, Sendable {
    public var providers: [TorrentioProviderOption]
    public var priorityLanguage: TorrentioPriorityLanguage
    public var excludedQualities: [TorrentioExcludedQuality]
    public var resultLimit: Int?

    public init(
        providers: [TorrentioProviderOption] = [.rutor, .rutracker],
        priorityLanguage: TorrentioPriorityLanguage = .russian,
        excludedQualities: [TorrentioExcludedQuality] = [.screener, .cam],
        resultLimit: Int? = 10
    ) {
        self.providers = Self.unique(providers)
        self.priorityLanguage = priorityLanguage
        self.excludedQualities = Self.unique(excludedQualities)
        self.resultLimit = resultLimit.map { min(max($0, 1), 999) }
    }

    public static let defaults = TorrentioSettings()

    private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }
}

public protocol TorrentioSettingsStoreProtocol: Sendable {
    func settings() async throws -> TorrentioSettings
    func save(_ settings: TorrentioSettings) async throws
}

public actor InMemoryTorrentioSettingsStore: TorrentioSettingsStoreProtocol {
    private var value: TorrentioSettings

    public init(settings: TorrentioSettings = .defaults) {
        value = settings
    }

    public func settings() async throws -> TorrentioSettings {
        value
    }

    public func save(_ settings: TorrentioSettings) async throws {
        value = settings
    }
}

public actor UserDefaultsTorrentioSettingsStore: TorrentioSettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let key: String

    public init(userDefaults: UserDefaults = .standard, key: String = "cineflow.source.torrentio.settings") {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func settings() async throws -> TorrentioSettings {
        guard let data = userDefaults.data(forKey: key) else { return .defaults }
        return try JSONDecoder().decode(TorrentioSettings.self, from: data)
    }

    public func save(_ settings: TorrentioSettings) async throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: key)
    }
}

public enum TorrentioStreamType: String, Sendable {
    case movie
    case series
    case anime
}

public struct TorrentioConfigurationURLBuilder: Sendable {
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "https://torrentio.strem.fun")!) {
        self.baseURL = baseURL
    }

    public func manifestURL(settings: TorrentioSettings) throws -> URL {
        try configuredURL(settings: settings, suffix: "manifest.json")
    }

    public func streamURL(type: TorrentioStreamType, id: String, settings: TorrentioSettings) throws -> URL {
        guard id.range(of: #"^[A-Za-z0-9:_-]+$"#, options: .regularExpression) != nil else {
            throw SourceProviderError.providerUnavailable(sourceId: "torrentio", reason: "Unsupported Stremio stream id.")
        }
        return try configuredURL(settings: settings, suffix: "stream/\(type.rawValue)/\(id).json")
    }

    public func configurationPath(settings: TorrentioSettings) -> String {
        let providers = settings.providers.map(\.rawValue).joined(separator: ",")
        let excludedQualities = settings.excludedQualities.map(\.rawValue).joined(separator: ",")
        var segments: [String] = []

        if !providers.isEmpty {
            segments.append("providers=\(providers)")
        }
        if settings.priorityLanguage != .none {
            segments.append("language=\(settings.priorityLanguage.rawValue)")
        }
        if !excludedQualities.isEmpty {
            segments.append("qualityfilter=\(excludedQualities)")
        }
        if let resultLimit = settings.resultLimit {
            segments.append("limit=\(min(max(resultLimit, 1), 999))")
        }

        return segments.joined(separator: "|")
    }

    private func configuredURL(settings: TorrentioSettings, suffix: String) throws -> URL {
        let root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let configurationPath = configurationPath(settings: settings)
        let urlString: String
        if configurationPath.isEmpty {
            urlString = "\(root)/\(suffix)"
        } else {
            urlString = "\(root)/\(configurationPath)/\(suffix)"
        }

        guard let url = URL(string: urlString) else {
            throw SourceProviderError.providerUnavailable(sourceId: "torrentio", reason: "Unable to build Torrentio URL.")
        }
        return url
    }
}

public struct StremioStreamResponse: Decodable, Equatable, Sendable {
    public let streams: [StremioStream]

    public init(streams: [StremioStream]) {
        self.streams = streams
    }
}

public struct StremioStream: Decodable, Equatable, Sendable {
    public let name: String?
    public let title: String?
    public let url: URL?
    public let infoHash: String?
    public let fileIdx: Int?
    public let sources: [String]?
    public let behaviorHints: StremioStreamBehaviorHints?

    public init(
        name: String? = nil,
        title: String? = nil,
        url: URL? = nil,
        infoHash: String? = nil,
        fileIdx: Int? = nil,
        sources: [String]? = nil,
        behaviorHints: StremioStreamBehaviorHints? = nil
    ) {
        self.name = name
        self.title = title
        self.url = url
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.sources = sources
        self.behaviorHints = behaviorHints
    }
}

public struct StremioStreamBehaviorHints: Decodable, Equatable, Sendable {
    public let bingeGroup: String?
    public let filename: String?
}

public struct TorrentioStreamMapper: Sendable {
    public init() {}

    public func releases(from response: StremioStreamResponse, mediaID: String) -> [TorrentRelease] {
        response.streams.compactMap { release(from: $0, mediaID: mediaID) }
    }

    private func release(from stream: StremioStream, mediaID: String) -> TorrentRelease? {
        guard let infoHash = stream.infoHash?.trimmedNonEmpty else { return nil }
        let fileIndex = stream.fileIdx ?? 0
        let title = stream.behaviorHints?.filename?.trimmedNonEmpty ?? stream.title?.firstLine ?? stream.name?.firstLine ?? infoHash
        let searchText = [
            stream.name,
            stream.title,
            stream.behaviorHints?.bingeGroup,
            stream.behaviorHints?.filename
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return TorrentRelease(
            id: "torrentio:\(mediaID):\(infoHash):\(fileIndex)",
            sourceId: "torrentio",
            sourceName: providerName(from: stream.title) ?? "Torrentio",
            title: title,
            magnetURI: magnetURI(infoHash: infoHash, displayName: title, sources: stream.sources ?? []),
            quality: quality(from: searchText),
            codec: codec(from: searchText),
            hdr: hdr(from: searchText),
            audioLanguages: languageCodes(from: searchText),
            subtitleLanguages: languageCodes(from: searchText),
            seeders: seeders(from: stream.title),
            leechers: 0,
            sizeBytes: sizeBytes(from: stream.title)
        )
    }

    private func magnetURI(infoHash: String, displayName: String, sources: [String]) -> String {
        var parts = ["magnet:?xt=urn:btih:\(infoHash)"]
        if let encodedName = displayName.percentEncodedForMagnet {
            parts.append("dn=\(encodedName)")
        }

        let trackers = sources
            .compactMap { source -> String? in
                guard source.hasPrefix("tracker:") else { return nil }
                return String(source.dropFirst("tracker:".count)).trimmedNonEmpty
            }
            .uniqued()

        for tracker in trackers {
            if let encodedTracker = tracker.percentEncodedForMagnet {
                parts.append("tr=\(encodedTracker)")
            }
        }

        return parts.joined(separator: "&")
    }

    private func quality(from text: String) -> ReleaseQuality {
        let value = text.uppercased()
        if value.contains("2160") || value.contains("4K") {
            return .ultraHD
        }
        if value.contains("1080") {
            return .fullHD
        }
        if value.contains("720") {
            return .hd
        }
        if value.contains("480") {
            return .standardDefinition
        }
        return .unknown
    }

    private func codec(from text: String) -> VideoCodec {
        let value = text.uppercased()
        if value.contains("H265") || value.contains("X265") || value.contains("H.265") {
            return .h265
        }
        if value.contains("HEVC") {
            return .hevc
        }
        if value.contains("H264") || value.contains("X264") || value.contains("H.264") {
            return .h264
        }
        if value.contains("AV1") {
            return .av1
        }
        if value.contains("MPEG4") || value.contains("MPEG-4") {
            return .mpeg4
        }
        return .unknown
    }

    private func hdr(from text: String) -> HDRFormat {
        let value = text.uppercased()
        if value.contains("DOLBY VISION") || value.contains("DV") {
            return .dolbyVision
        }
        if value.contains("HDR") {
            return .hdr10
        }
        return .none
    }

    private func seeders(from title: String?) -> Int {
        integer(in: title, pattern: #"👤\s*([0-9]+)"#) ?? 0
    }

    private func sizeBytes(from title: String?) -> Int64? {
        guard let title,
              let match = firstMatch(in: title, pattern: #"💾\s*([0-9]+(?:\.[0-9]+)?)\s*(TB|GB|MB)"#),
              match.count == 3,
              let value = Double(match[1])
        else {
            return nil
        }

        let multiplier: Double = switch match[2].uppercased() {
        case "TB":
            1_000_000_000_000
        case "GB":
            1_000_000_000
        case "MB":
            1_000_000
        default:
            1
        }
        return Int64(value * multiplier)
    }

    private func providerName(from title: String?) -> String? {
        firstMatch(in: title ?? "", pattern: #"⚙️\s*([^\n\r]+)"#)?.dropFirst().first?.trimmedNonEmpty
    }

    private func languageCodes(from text: String) -> [String] {
        let flags: [(String, String)] = [
            ("🇬🇧", "en"),
            ("🇺🇸", "en"),
            ("🇷🇺", "ru"),
            ("🇮🇹", "it"),
            ("🇪🇸", "es"),
            ("🇫🇷", "fr"),
            ("🇩🇪", "de"),
            ("🇵🇹", "pt"),
            ("🇯🇵", "ja"),
            ("🇰🇷", "ko"),
            ("🇨🇳", "zh"),
            ("🇵🇱", "pl"),
            ("🇺🇦", "uk")
        ]
        return flags.compactMap { flag, code in text.contains(flag) ? code : nil }.uniqued()
    }

    private func integer(in text: String?, pattern: String) -> Int? {
        guard let match = firstMatch(in: text ?? "", pattern: pattern), match.count > 1 else { return nil }
        return Int(match[1])
    }

    private func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

public struct TorrentioSourceProvider: TorrentSourceProviderProtocol {
    public let sourceId = "torrentio"
    public let displayName = "Torrentio"
    public let requiresAuthentication = false
    public let isEnabled = true
    public let defaultIsEnabled = false

    private let settingsStore: any TorrentioSettingsStoreProtocol
    private let session: URLSession
    private let urlBuilder: TorrentioConfigurationURLBuilder
    private let mapper: TorrentioStreamMapper

    public init(
        settingsStore: any TorrentioSettingsStoreProtocol = UserDefaultsTorrentioSettingsStore(),
        session: URLSession = .shared,
        urlBuilder: TorrentioConfigurationURLBuilder = TorrentioConfigurationURLBuilder(),
        mapper: TorrentioStreamMapper = TorrentioStreamMapper()
    ) {
        self.settingsStore = settingsStore
        self.session = session
        self.urlBuilder = urlBuilder
        self.mapper = mapper
    }

    public func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        let stremioID = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stremioID.range(of: #"^tt[0-9]+$"#, options: .regularExpression) != nil else {
            return []
        }

        let settings = try await settingsStore.settings()
        let url = try urlBuilder.streamURL(type: .movie, id: stremioID, settings: settings)
        let response: StremioStreamResponse = try await fetch(url)
        return mapper.releases(from: response, mediaID: stremioID).filtered(by: filters)
    }

    public func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        throw SourceProviderError.releaseNotFound(sourceId: sourceId, releaseId: releaseId)
    }

    public func validateSession() async throws -> SourceAuthenticationStatus {
        let settings = try await settingsStore.settings()
        let manifestURL = try urlBuilder.manifestURL(settings: settings)
        let _: StremioManifestResponse = try await fetch(manifestURL)
        return .notRequired
    }

    private func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Torrentio returned an invalid response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: "Torrentio returned HTTP \(httpResponse.statusCode).")
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as SourceProviderError {
            throw error
        } catch {
            throw SourceProviderError.providerUnavailable(sourceId: sourceId, reason: error.localizedDescription)
        }
    }
}

private struct StremioManifestResponse: Decodable {
    let id: String
    let version: String
}

private extension Array where Element == TorrentRelease {
    func filtered(by filters: TorrentSourceSearchFilters) -> [TorrentRelease] {
        filter { release in
            if !filters.qualities.isEmpty, !filters.qualities.contains(release.quality) {
                return false
            }
            if filters.requiresHDR, release.hdr == .none || release.hdr == .unknown {
                return false
            }
            if let minimumSeeders = filters.minimumSeeders, release.seeders < minimumSeeders {
                return false
            }
            if let audioLanguage = filters.audioLanguage,
               !release.audioLanguages.map({ $0.lowercased() }).contains(audioLanguage.lowercased()) {
                return false
            }
            if let subtitleLanguage = filters.subtitleLanguage,
               !release.subtitleLanguages.map({ $0.lowercased() }).contains(subtitleLanguage.lowercased()) {
                return false
            }
            return true
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var firstLine: String? {
        split(whereSeparator: \.isNewline).first.map(String.init)?.trimmedNonEmpty
    }

    var percentEncodedForMagnet: String? {
        addingPercentEncoding(withAllowedCharacters: .magnetQueryValueAllowed)
    }
}

private extension CharacterSet {
    static let magnetQueryValueAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
