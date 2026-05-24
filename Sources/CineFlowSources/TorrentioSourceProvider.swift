import CineFlowCore
import Foundation

public enum TorrentioProviderOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case yts
    case eztv
    case rarbg
    case one337x = "1337x"
    case thePirateBay = "thepiratebay"
    case kickassTorrents = "kickasstorrents"
    case torrentGalaxy = "torrentgalaxy"
    case magnetDL = "magnetdl"
    case horribleSubs = "horriblesubs"
    case nyaaSi = "nyaasi"
    case tokyoTosho = "tokyotosho"
    case aniDex = "anidex"
    case rutor
    case rutracker
    case comando
    case bluDV = "bludv"
    case micoLeaoDublado = "micoleaodublado"
    case torrent9
    case ilCorSaRoNeRo = "ilcorsaronero"
    case mejorTorrent = "mejortorrent"
    case wolfmax4k
    case cinecalidad
    case bestTorrents = "besttorrents"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yts:
            "YTS"
        case .eztv:
            "EZTV"
        case .rarbg:
            "RARBG"
        case .one337x:
            "1337x"
        case .thePirateBay:
            "ThePirateBay"
        case .kickassTorrents:
            "KickassTorrents"
        case .torrentGalaxy:
            "TorrentGalaxy"
        case .magnetDL:
            "MagnetDL"
        case .horribleSubs:
            "HorribleSubs"
        case .nyaaSi:
            "NyaaSi"
        case .tokyoTosho:
            "TokyoTosho"
        case .aniDex:
            "AniDex"
        case .rutor:
            "Rutor"
        case .rutracker:
            "RuTracker"
        case .comando:
            "Comando"
        case .bluDV:
            "BluDV"
        case .micoLeaoDublado:
            "MicoLeaoDublado"
        case .torrent9:
            "Torrent9"
        case .ilCorSaRoNeRo:
            "ilCorSaRoNeRo"
        case .mejorTorrent:
            "MejorTorrent"
        case .wolfmax4k:
            "Wolfmax4k"
        case .cinecalidad:
            "Cinecalidad"
        case .bestTorrents:
            "BestTorrents"
        }
    }
}

public enum TorrentioSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case quality
    case qualitySize = "qualitysize"
    case seeders
    case size

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .quality:
            "Quality"
        case .qualitySize:
            "Quality + size"
        case .seeders:
            "Seeders"
        case .size:
            "Size"
        }
    }
}

public enum TorrentioDebridProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case realDebrid = "realdebrid"
    case premiumize
    case allDebrid = "alldebrid"
    case debridLink = "debridlink"
    case easyDebrid = "easydebrid"
    case offcloud
    case torBox = "torbox"
    case putIO = "putio"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            "None"
        case .realDebrid:
            "RealDebrid"
        case .premiumize:
            "Premiumize"
        case .allDebrid:
            "AllDebrid"
        case .debridLink:
            "DebridLink"
        case .easyDebrid:
            "EasyDebrid"
        case .offcloud:
            "Offcloud"
        case .torBox:
            "TorBox"
        case .putIO:
            "Put.io"
        }
    }
}

public enum TorrentioDebridOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case hideDownloadLinks = "nodownloadlinks"
    case hideCatalog = "nocatalog"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hideDownloadLinks:
            "Cached streams only"
        case .hideCatalog:
            "Hide debrid catalog"
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
    public var sortMode: TorrentioSortMode
    public var priorityLanguage: TorrentioPriorityLanguage
    public var excludedQualities: [TorrentioExcludedQuality]
    public var resultLimit: Int?
    public var sizeLimit: String?
    public var debridProvider: TorrentioDebridProvider
    public var debridOptions: [TorrentioDebridOption]

    public init(
        providers: [TorrentioProviderOption] = TorrentioProviderOption.allCases,
        sortMode: TorrentioSortMode = .seeders,
        priorityLanguage: TorrentioPriorityLanguage = .russian,
        excludedQualities: [TorrentioExcludedQuality] = [.screener, .cam],
        resultLimit: Int? = 50,
        sizeLimit: String? = nil,
        debridProvider: TorrentioDebridProvider = .none,
        debridOptions: [TorrentioDebridOption] = [.hideDownloadLinks]
    ) {
        self.providers = Self.unique(providers)
        self.sortMode = sortMode
        self.priorityLanguage = priorityLanguage
        self.excludedQualities = Self.unique(excludedQualities)
        self.resultLimit = resultLimit.map { min(max($0, 1), 999) }
        self.sizeLimit = Self.normalizedSizeLimit(sizeLimit)
        self.debridProvider = debridProvider
        self.debridOptions = Self.unique(debridOptions)
    }

    public static let defaults = TorrentioSettings()

    private enum CodingKeys: String, CodingKey {
        case providers
        case sortMode
        case priorityLanguage
        case excludedQualities
        case resultLimit
        case sizeLimit
        case debridProvider
        case debridOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProviders = try container.decodeIfPresent([TorrentioProviderOption].self, forKey: .providers)
        let decodedResultLimit = try container.decodeIfPresent(Int.self, forKey: .resultLimit)
        let hasModernSort = container.contains(.sortMode)
        let looksLikeLegacyDefault = !hasModernSort
            && decodedProviders == [.rutor, .rutracker]
            && (decodedResultLimit == nil || decodedResultLimit == 10)

        self.init(
            providers: looksLikeLegacyDefault ? TorrentioProviderOption.allCases : (decodedProviders ?? TorrentioSettings.defaults.providers),
            sortMode: try container.decodeIfPresent(TorrentioSortMode.self, forKey: .sortMode) ?? TorrentioSettings.defaults.sortMode,
            priorityLanguage: try container.decodeIfPresent(TorrentioPriorityLanguage.self, forKey: .priorityLanguage) ?? TorrentioSettings.defaults.priorityLanguage,
            excludedQualities: try container.decodeIfPresent([TorrentioExcludedQuality].self, forKey: .excludedQualities) ?? TorrentioSettings.defaults.excludedQualities,
            resultLimit: looksLikeLegacyDefault ? TorrentioSettings.defaults.resultLimit : decodedResultLimit,
            sizeLimit: try container.decodeIfPresent(String.self, forKey: .sizeLimit),
            debridProvider: try container.decodeIfPresent(TorrentioDebridProvider.self, forKey: .debridProvider) ?? .none,
            debridOptions: try container.decodeIfPresent([TorrentioDebridOption].self, forKey: .debridOptions) ?? TorrentioSettings.defaults.debridOptions
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providers, forKey: .providers)
        try container.encode(sortMode, forKey: .sortMode)
        try container.encode(priorityLanguage, forKey: .priorityLanguage)
        try container.encode(excludedQualities, forKey: .excludedQualities)
        try container.encodeIfPresent(resultLimit, forKey: .resultLimit)
        try container.encodeIfPresent(sizeLimit, forKey: .sizeLimit)
        try container.encode(debridProvider, forKey: .debridProvider)
        try container.encode(debridOptions, forKey: .debridOptions)
    }

    private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func normalizedSizeLimit(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    public init(baseURL: URL = TorrentioConfigurationURLBuilder.defaultBaseURL) {
        self.baseURL = baseURL
    }

    public static var defaultBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "torrentio.strem.fun"
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public func manifestURL(settings: TorrentioSettings, credentials: SourceCredentials? = nil) throws -> URL {
        try configuredURL(settings: settings, credentials: credentials, suffix: "manifest.json")
    }

    public func streamURL(
        type: TorrentioStreamType,
        id: String,
        settings: TorrentioSettings,
        credentials: SourceCredentials? = nil
    ) throws -> URL {
        guard id.range(of: #"^[A-Za-z0-9:_-]+$"#, options: .regularExpression) != nil else {
            throw SourceProviderError.providerUnavailable(sourceId: "torrentio", reason: "Unsupported Stremio stream id.")
        }
        return try configuredURL(settings: settings, credentials: credentials, suffix: "stream/\(type.rawValue)/\(id).json")
    }

    public func configurationPath(settings: TorrentioSettings, credentials: SourceCredentials? = nil) -> String {
        let selectedProviders = settings.providers
        let providers = selectedProviders.count == TorrentioProviderOption.allCases.count
            ? ""
            : selectedProviders.map(\.rawValue).joined(separator: ",")
        let excludedQualities = settings.excludedQualities.map(\.rawValue).joined(separator: ",")
        let debridToken = credentials?.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        var segments: [String] = []

        if !providers.isEmpty {
            segments.append("providers=\(providers)")
        }
        if settings.sortMode != .quality {
            segments.append("sort=\(settings.sortMode.rawValue)")
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
        if let sizeLimit = settings.sizeLimit {
            segments.append("sizefilter=\(sizeLimit)")
        }
        if settings.debridProvider != .none, let debridToken, !debridToken.isEmpty {
            let debridOptions = settings.debridOptions.map(\.rawValue).joined(separator: ",")
            if !debridOptions.isEmpty {
                segments.append("debridoptions=\(debridOptions)")
            }
            segments.append("\(settings.debridProvider.rawValue)=\(debridToken)")
        }

        return segments.joined(separator: "|")
    }

    private func configuredURL(settings: TorrentioSettings, credentials: SourceCredentials?, suffix: String) throws -> URL {
        let root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let configurationPath = configurationPath(settings: settings, credentials: credentials)
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
    private static let defaultPublicTrackers = [
        "udp://tracker.opentrackr.org:1337/announce",
        "udp://open.demonii.com:1337/announce",
        "udp://wepzone.net:6969/announce",
        "udp://vito-tracker.space:6969/announce",
        "udp://vito-tracker.duckdns.org:6969/announce",
        "udp://udp.tracker.projectk.org:23333/announce",
        "udp://tracker.tryhackx.org:6969/announce",
        "udp://tracker.t-1.org:6969/announce",
        "udp://tracker.srv00.com:6969/announce",
        "udp://tracker.qu.ax:6969/announce",
        "udp://tracker.plx.im:6969/announce",
        "udp://tracker.opentorrent.top:6969/announce",
        "udp://tracker.gmi.gd:6969/announce",
        "udp://tracker.ducks.party:1984/announce",
        "udp://tracker.bittor.pw:1337/announce"
    ]

    public init() {}

    public func releases(from response: StremioStreamResponse, mediaID: String) -> [TorrentRelease] {
        response.streams.compactMap { release(from: $0, mediaID: mediaID) }
    }

    private func release(from stream: StremioStream, mediaID: String) -> TorrentRelease? {
        let infoHash = stream.infoHash?.trimmedNonEmpty
        let directStreamURL = stream.url?.isCineFlowPlayableMediaURL == true ? stream.url : nil
        guard infoHash != nil || directStreamURL != nil else { return nil }
        let fileIndexIdentifier = stream.fileIdx.map(String.init) ?? "auto"
        let title = stream.behaviorHints?.filename?.trimmedNonEmpty
            ?? stream.title?.firstLine
            ?? stream.name?.firstLine
            ?? infoHash
            ?? directStreamURL?.lastPathComponent.trimmedNonEmpty
            ?? directStreamURL?.host
            ?? "Torrentio Stream"
        let searchText = [
            stream.name,
            stream.title,
            stream.behaviorHints?.bingeGroup,
            stream.behaviorHints?.filename
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let parsedSeeders = seeders(from: stream.title)
        let releaseID: String
        if let infoHash {
            releaseID = "torrentio:\(mediaID):\(infoHash):\(fileIndexIdentifier)"
        } else if let directStreamURL {
            releaseID = "torrentio:\(mediaID):direct:\(stableIdentifier(for: directStreamURL.absoluteString))"
        } else {
            return nil
        }

        return TorrentRelease(
            id: releaseID,
            sourceId: "torrentio",
            sourceName: providerName(from: stream.title) ?? (directStreamURL == nil ? "Torrentio" : "Torrentio Cached"),
            title: title,
            magnetURI: infoHash.map { magnetURI(infoHash: $0, displayName: title, sources: stream.sources ?? []) },
            directStreamURL: directStreamURL,
            quality: quality(from: searchText),
            codec: codec(from: searchText),
            hdr: hdr(from: searchText),
            audioLanguages: languageCodes(from: searchText),
            subtitleLanguages: languageCodes(from: searchText),
            seeders: parsedSeeders,
            leechers: 0,
            sizeBytes: sizeBytes(from: stream.title),
            preferredFileIndex: stream.fileIdx,
            availability: directStreamURL == nil ? nil : 1,
            rankScore: directStreamURL == nil ? nil : 100_000 + Double(parsedSeeders)
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
            + Self.defaultPublicTrackers

        for tracker in trackers.uniqued() {
            guard let encodedTracker = tracker.percentEncodedForMagnet else { continue }
            parts.append("tr=\(encodedTracker)")
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

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct TorrentioSourceProvider: TorrentSourceProviderProtocol {
    public let sourceId = "torrentio"
    public let displayName = "Torrentio"
    public let requiresAuthentication = false
    public let isEnabled = true
    public let defaultIsEnabled = true

    private let settingsStore: any TorrentioSettingsStoreProtocol
    private let credentialStore: any SourceCredentialStoreProtocol
    private let session: URLSession
    private let urlBuilder: TorrentioConfigurationURLBuilder
    private let mapper: TorrentioStreamMapper

    public init(
        settingsStore: any TorrentioSettingsStoreProtocol = UserDefaultsTorrentioSettingsStore(),
        credentialStore: any SourceCredentialStoreProtocol = KeychainSourceCredentialStore(),
        session: URLSession = .shared,
        urlBuilder: TorrentioConfigurationURLBuilder = TorrentioConfigurationURLBuilder(),
        mapper: TorrentioStreamMapper = TorrentioStreamMapper()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
        self.session = session
        self.urlBuilder = urlBuilder
        self.mapper = mapper
    }

    public func search(query: String, filters: TorrentSourceSearchFilters) async throws -> [TorrentRelease] {
        let stremioID = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stremioID.range(of: #"^tt[0-9]+(?::[0-9]+:[0-9]+)?$"#, options: .regularExpression) != nil else {
            return []
        }

        let settings = try await settingsStore.settings()
        let credentials = try await credentials(for: settings)
        let streamType: TorrentioStreamType = stremioID.contains(":") ? .series : .movie
        let url = try urlBuilder.streamURL(type: streamType, id: stremioID, settings: settings, credentials: credentials)
        let response: StremioStreamResponse = try await fetch(url)
        return mapper.releases(from: response, mediaID: stremioID).filtered(by: filters)
    }

    public func fetchDetails(releaseId: String) async throws -> TorrentReleaseDetails {
        throw SourceProviderError.releaseNotFound(sourceId: sourceId, releaseId: releaseId)
    }

    public func validateSession() async throws -> SourceAuthenticationStatus {
        let settings = try await settingsStore.settings()
        let credentials = try await credentials(for: settings)
        let manifestURL = try urlBuilder.manifestURL(settings: settings, credentials: credentials)
        let _: StremioManifestResponse = try await fetch(manifestURL)
        return .notRequired
    }

    private func credentials(for settings: TorrentioSettings) async throws -> SourceCredentials? {
        guard settings.debridProvider != .none else { return nil }
        return try await credentialStore.credentials(for: sourceId)
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
