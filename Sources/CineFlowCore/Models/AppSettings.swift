import Foundation

public enum AppLanguageSetting: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case system
    case russian
    case english

    public var id: String { rawValue }
}

public enum HomeLayoutDensity: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case compact
    case comfortable

    public var id: String { rawValue }
}

public enum HomePosterSizePreference: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }
}

public struct HomeSectionPreference: Codable, Equatable, Identifiable, Sendable {
    public let sectionID: String
    public var isEnabled: Bool
    public var order: Int

    public var id: String { sectionID }

    public init(sectionID: String, isEnabled: Bool = true, order: Int) {
        self.sectionID = sectionID
        self.isEnabled = isEnabled
        self.order = max(0, order)
    }
}

public struct HomePreferences: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 5

    public static let defaultSectionIDs: [String] = [
        "continueWatching",
        "newEpisodes",
        "recommendedTonight",
        "recommended",
        "moreLikeThis",
        "collections",
        "trendingNow",
        "popularMovies",
        "popularSeries",
        "newMovies",
        "newSeries",
        "featuredMovies",
        "featuredSeries",
        "watchNext",
        "fromFavoriteGenres",
        "continueSeries",
        "hiddenGems",
        "popularInFavoriteGenres",
        "notFinishedYet",
        "recentlyAdded",
        "trendingMovies",
        "trendingSeries",
        "topQuality",
        "ultraHDR",
        "favoriteGenres",
        "unfinishedMovies",
        "forgottenInLibrary",
        "moodDiscovery",
        "upcomingCalendar"
    ]

    public static let defaultCollapsedSectionIDs: Set<String> = [
        "watchNext",
        "fromFavoriteGenres",
        "continueSeries",
        "hiddenGems",
        "popularInFavoriteGenres",
        "notFinishedYet",
        "recentlyAdded",
        "trendingMovies",
        "trendingSeries",
        "topQuality",
        "ultraHDR",
        "favoriteGenres",
        "unfinishedMovies",
        "forgottenInLibrary",
        "moodDiscovery",
        "upcomingCalendar"
    ]

    public var sections: [HomeSectionPreference]
    public var layoutDensity: HomeLayoutDensity
    public var posterSize: HomePosterSizePreference
    public var schemaVersion: Int
    public var syncRevision: Int
    public var updatedAt: Date

    public init(
        sections: [HomeSectionPreference] = Self.defaultSections(),
        layoutDensity: HomeLayoutDensity = .comfortable,
        posterSize: HomePosterSizePreference = .medium,
        schemaVersion: Int = Self.currentSchemaVersion,
        syncRevision: Int = 0,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        let normalizedSections = Self.normalizedSections(sections)
        if schemaVersion < Self.currentSchemaVersion {
            self.sections = Self.netflixFocusMigratedSections(normalizedSections)
            self.schemaVersion = Self.currentSchemaVersion
        } else {
            self.sections = normalizedSections
            self.schemaVersion = schemaVersion
        }
        self.layoutDensity = layoutDensity
        self.posterSize = posterSize
        self.syncRevision = max(0, syncRevision)
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sections
        case layoutDensity
        case posterSize
        case schemaVersion
        case syncRevision
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sections: try container.decodeIfPresent([HomeSectionPreference].self, forKey: .sections) ?? Self.defaultSections(),
            layoutDensity: try container.decodeIfPresent(HomeLayoutDensity.self, forKey: .layoutDensity) ?? .comfortable,
            posterSize: try container.decodeIfPresent(HomePosterSizePreference.self, forKey: .posterSize) ?? .medium,
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            syncRevision: try container.decodeIfPresent(Int.self, forKey: .syncRevision) ?? 0,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        )
    }

    public var orderedSections: [HomeSectionPreference] {
        sections.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.sectionID < rhs.sectionID
            }
            return lhs.order < rhs.order
        }
    }

    public func isSectionEnabled(_ sectionID: String) -> Bool {
        sections.first { $0.sectionID == sectionID }?.isEnabled ?? true
    }

    public func order(for sectionID: String) -> Int {
        sections.first { $0.sectionID == sectionID }?.order ?? Int.max
    }

    public mutating func setSection(
        _ sectionID: String,
        isEnabled: Bool,
        updatedAt: Date = Date()
    ) {
        ensureSectionExists(sectionID)
        guard let index = sections.firstIndex(where: { $0.sectionID == sectionID }) else { return }
        guard sections[index].isEnabled != isEnabled else { return }
        sections[index].isEnabled = isEnabled
        touch(updatedAt: updatedAt)
    }

    public mutating func moveSection(
        _ sectionID: String,
        to destinationIndex: Int,
        updatedAt: Date = Date()
    ) {
        ensureSectionExists(sectionID)
        var ordered = orderedSections
        guard let currentIndex = ordered.firstIndex(where: { $0.sectionID == sectionID }) else { return }
        let boundedDestination = min(max(destinationIndex, 0), max(ordered.count - 1, 0))
        guard currentIndex != boundedDestination else { return }
        let moved = ordered.remove(at: currentIndex)
        ordered.insert(moved, at: boundedDestination)
        sections = ordered.enumerated().map { index, preference in
            HomeSectionPreference(sectionID: preference.sectionID, isEnabled: preference.isEnabled, order: index)
        }
        touch(updatedAt: updatedAt)
    }

    public mutating func touch(updatedAt: Date = Date()) {
        syncRevision += 1
        self.updatedAt = updatedAt
    }

    private mutating func ensureSectionExists(_ sectionID: String) {
        guard !sectionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if sections.contains(where: { $0.sectionID == sectionID }) {
            return
        }
        sections.append(HomeSectionPreference(sectionID: sectionID, order: sections.count))
    }

    public static func defaultSections() -> [HomeSectionPreference] {
        defaultSectionIDs.enumerated().map { index, sectionID in
            HomeSectionPreference(
                sectionID: sectionID,
                isEnabled: !defaultCollapsedSectionIDs.contains(sectionID),
                order: index
            )
        }
    }

    private static func normalizedSections(_ sections: [HomeSectionPreference]) -> [HomeSectionPreference] {
        var firstByID: [String: HomeSectionPreference] = [:]
        for section in sections where !section.sectionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if firstByID[section.sectionID] == nil {
                firstByID[section.sectionID] = section
            }
        }

        let defaultByID = Dictionary(uniqueKeysWithValues: defaultSections().map { ($0.sectionID, $0) })
        var normalized = defaultSectionIDs.enumerated().map { index, sectionID in
            firstByID.removeValue(forKey: sectionID)
                ?? defaultByID[sectionID]
                ?? HomeSectionPreference(sectionID: sectionID, isEnabled: true, order: index)
        }
        let unknownSections = firstByID.values.sorted { lhs, rhs in
            if lhs.order == rhs.order {
                return lhs.sectionID < rhs.sectionID
            }
            return lhs.order < rhs.order
        }
        normalized.append(contentsOf: unknownSections)
        normalized.sort { lhs, rhs in
            if lhs.order == rhs.order {
                let lhsDefaultIndex = defaultSectionIDs.firstIndex(of: lhs.sectionID) ?? Int.max
                let rhsDefaultIndex = defaultSectionIDs.firstIndex(of: rhs.sectionID) ?? Int.max
                if lhsDefaultIndex == rhsDefaultIndex {
                    return lhs.sectionID < rhs.sectionID
                }
                return lhsDefaultIndex < rhsDefaultIndex
            }
            return lhs.order < rhs.order
        }
        return normalized.enumerated().map { index, preference in
            HomeSectionPreference(sectionID: preference.sectionID, isEnabled: preference.isEnabled, order: index)
        }
    }

    private static func netflixFocusMigratedSections(_ sections: [HomeSectionPreference]) -> [HomeSectionPreference] {
        sections.map { section in
            HomeSectionPreference(
                sectionID: section.sectionID,
                isEnabled: !defaultCollapsedSectionIDs.contains(section.sectionID),
                order: section.order
            )
        }
    }
}

public struct RecommendationSettings: Codable, Equatable, Sendable {
    public var localRecommendationsEnabled: Bool

    public init(localRecommendationsEnabled: Bool = true) {
        self.localRecommendationsEnabled = localRecommendationsEnabled
    }
}

public enum NotificationCategory: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case betterRelease
    case newEpisode
    case sync
    case update
    case sourceAuth
    case cache
    case announcement

    public var id: String { rawValue }
}

public struct NotificationCategoryPreference: Codable, Equatable, Identifiable, Sendable {
    public let category: NotificationCategory
    public var isEnabled: Bool

    public var id: NotificationCategory { category }

    public init(category: NotificationCategory, isEnabled: Bool = true) {
        self.category = category
        self.isEnabled = isEnabled
    }
}

public struct NotificationSettings: Codable, Equatable, Sendable {
    public var betterReleaseNotificationsEnabled: Bool
    public var betterReleaseDigestMode: Bool
    public var macOSBetterReleaseNotificationsEnabled: Bool
    public var categoryPreferences: [NotificationCategoryPreference]

    public init(
        betterReleaseNotificationsEnabled: Bool = true,
        betterReleaseDigestMode: Bool = true,
        macOSBetterReleaseNotificationsEnabled: Bool = false,
        categoryPreferences: [NotificationCategoryPreference] = NotificationSettings.defaultCategoryPreferences()
    ) {
        self.betterReleaseNotificationsEnabled = betterReleaseNotificationsEnabled
        self.betterReleaseDigestMode = betterReleaseDigestMode
        self.macOSBetterReleaseNotificationsEnabled = macOSBetterReleaseNotificationsEnabled
        self.categoryPreferences = Self.normalizedCategoryPreferences(categoryPreferences)
    }

    private enum CodingKeys: String, CodingKey {
        case betterReleaseNotificationsEnabled
        case betterReleaseDigestMode
        case macOSBetterReleaseNotificationsEnabled
        case categoryPreferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            betterReleaseNotificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .betterReleaseNotificationsEnabled) ?? true,
            betterReleaseDigestMode: try container.decodeIfPresent(Bool.self, forKey: .betterReleaseDigestMode) ?? true,
            macOSBetterReleaseNotificationsEnabled: try container.decodeIfPresent(Bool.self, forKey: .macOSBetterReleaseNotificationsEnabled) ?? false,
            categoryPreferences: try container.decodeIfPresent([NotificationCategoryPreference].self, forKey: .categoryPreferences) ?? Self.defaultCategoryPreferences()
        )
    }

    public func isCategoryEnabled(_ category: NotificationCategory) -> Bool {
        categoryPreferences.first { $0.category == category }?.isEnabled ?? true
    }

    public mutating func setCategory(_ category: NotificationCategory, isEnabled: Bool) {
        if let index = categoryPreferences.firstIndex(where: { $0.category == category }) {
            categoryPreferences[index].isEnabled = isEnabled
        } else {
            categoryPreferences.append(NotificationCategoryPreference(category: category, isEnabled: isEnabled))
            categoryPreferences = Self.normalizedCategoryPreferences(categoryPreferences)
        }
        if category == .betterRelease {
            betterReleaseNotificationsEnabled = isEnabled
        }
    }

    public static func defaultCategoryPreferences() -> [NotificationCategoryPreference] {
        NotificationCategory.allCases.map { NotificationCategoryPreference(category: $0, isEnabled: true) }
    }

    private static func normalizedCategoryPreferences(_ preferences: [NotificationCategoryPreference]) -> [NotificationCategoryPreference] {
        var valuesByCategory: [NotificationCategory: NotificationCategoryPreference] = [:]
        for preference in preferences {
            valuesByCategory[preference.category] = preference
        }
        return NotificationCategory.allCases.map { category in
            valuesByCategory[category] ?? NotificationCategoryPreference(category: category)
        }
    }
}

public enum TastePreferenceLevel: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case more
    case less
    case hidden

    public var id: String { rawValue }
}

public struct TasteGenrePreference: Codable, Equatable, Identifiable, Sendable {
    public var genre: String
    public var preference: TastePreferenceLevel

    public var id: String { normalizedGenre }

    public init(genre: String, preference: TastePreferenceLevel) {
        self.genre = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preference = preference
    }

    public var normalizedGenre: String {
        genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public enum TasteDurationPreference: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case any
    case short
    case featureLength
    case long

    public var id: String { rawValue }
}

public enum HiddenRecommendationReason: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case hiddenTitle
    case notInterested
    case removedFromRecommendations

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .hiddenTitle:
            "Hidden title"
        case .notInterested:
            "Not interested"
        case .removedFromRecommendations:
            "Removed from recommendations"
        }
    }
}

public struct HiddenRecommendationItem: Codable, Equatable, Identifiable, Sendable {
    public var mediaID: String
    public var title: String
    public var genres: [String]
    public var reason: HiddenRecommendationReason
    public var createdAt: Date

    public var id: String { mediaID }

    public init(
        mediaID: String,
        title: String,
        genres: [String] = [],
        reason: HiddenRecommendationReason,
        createdAt: Date = Date()
    ) {
        self.mediaID = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.genres = Self.normalizedGenres(genres)
        self.reason = reason
        self.createdAt = createdAt
    }

    private static func normalizedGenres(_ genres: [String]) -> [String] {
        var seen = Set<String>()
        return genres
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

public struct TasteProfileSettings: Codable, Equatable, Sendable {
    public var genrePreferences: [TasteGenrePreference]
    public var hiddenItems: [HiddenRecommendationItem]
    public var preferredActorIDs: [String]
    public var preferredDirectorIDs: [String]
    public var preferredMediaKinds: Set<MediaKind>
    public var preferredDuration: TasteDurationPreference
    public var preferredLanguages: [String]
    public var schemaVersion: Int
    public var syncRevision: Int
    public var updatedAt: Date

    public init(
        genrePreferences: [TasteGenrePreference] = [],
        hiddenItems: [HiddenRecommendationItem] = [],
        preferredActorIDs: [String] = [],
        preferredDirectorIDs: [String] = [],
        preferredMediaKinds: Set<MediaKind> = [],
        preferredDuration: TasteDurationPreference = .any,
        preferredLanguages: [String] = [],
        schemaVersion: Int = 1,
        syncRevision: Int = 0,
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.genrePreferences = Self.normalizedGenrePreferences(genrePreferences)
        self.hiddenItems = Self.normalizedHiddenItems(hiddenItems)
        self.preferredActorIDs = Self.normalizedUnique(preferredActorIDs)
        self.preferredDirectorIDs = Self.normalizedUnique(preferredDirectorIDs)
        self.preferredMediaKinds = preferredMediaKinds
        self.preferredDuration = preferredDuration
        self.preferredLanguages = Self.normalizedUnique(preferredLanguages)
        self.schemaVersion = schemaVersion
        self.syncRevision = max(0, syncRevision)
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case genrePreferences
        case hiddenItems
        case preferredActorIDs
        case preferredDirectorIDs
        case preferredMediaKinds
        case preferredDuration
        case preferredLanguages
        case schemaVersion
        case syncRevision
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            genrePreferences: try container.decodeIfPresent([TasteGenrePreference].self, forKey: .genrePreferences) ?? [],
            hiddenItems: try container.decodeIfPresent([HiddenRecommendationItem].self, forKey: .hiddenItems) ?? [],
            preferredActorIDs: try container.decodeIfPresent([String].self, forKey: .preferredActorIDs) ?? [],
            preferredDirectorIDs: try container.decodeIfPresent([String].self, forKey: .preferredDirectorIDs) ?? [],
            preferredMediaKinds: try container.decodeIfPresent(Set<MediaKind>.self, forKey: .preferredMediaKinds) ?? [],
            preferredDuration: try container.decodeIfPresent(TasteDurationPreference.self, forKey: .preferredDuration) ?? .any,
            preferredLanguages: try container.decodeIfPresent([String].self, forKey: .preferredLanguages) ?? [],
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            syncRevision: try container.decodeIfPresent(Int.self, forKey: .syncRevision) ?? 0,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        )
    }

    public func preference(forGenre genre: String) -> TastePreferenceLevel? {
        let normalized = Self.normalizedKey(genre)
        return genrePreferences.first { $0.normalizedGenre == normalized }?.preference
    }

    public mutating func setGenre(
        _ genre: String,
        preference: TastePreferenceLevel?,
        updatedAt: Date = Date()
    ) {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = Self.normalizedKey(trimmed)
        genrePreferences.removeAll { $0.normalizedGenre == normalized }
        if let preference {
            genrePreferences.append(TasteGenrePreference(genre: trimmed, preference: preference))
        }
        genrePreferences = Self.normalizedGenrePreferences(genrePreferences)
        touch(updatedAt: updatedAt)
    }

    public func hiddenItem(for mediaID: String) -> HiddenRecommendationItem? {
        let normalized = Self.normalizedKey(mediaID)
        return hiddenItems.first { Self.normalizedKey($0.mediaID) == normalized }
    }

    public func isHidden(mediaID: String) -> Bool {
        hiddenItem(for: mediaID) != nil
    }

    public var hiddenMediaIDs: Set<String> {
        Set(hiddenItems.map(\.mediaID))
    }

    public mutating func hideTitle(
        mediaID: String,
        title: String,
        genres: [String] = [],
        reason: HiddenRecommendationReason,
        updatedAt: Date = Date()
    ) {
        let trimmedID = mediaID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        hiddenItems.removeAll { Self.normalizedKey($0.mediaID) == Self.normalizedKey(trimmedID) }
        hiddenItems.append(HiddenRecommendationItem(
            mediaID: trimmedID,
            title: title.isEmpty ? trimmedID : title,
            genres: genres,
            reason: reason,
            createdAt: updatedAt
        ))
        hiddenItems = Self.normalizedHiddenItems(hiddenItems)
        touch(updatedAt: updatedAt)
    }

    public mutating func restoreHiddenTitle(mediaID: String, updatedAt: Date = Date()) {
        let normalized = Self.normalizedKey(mediaID)
        let previousCount = hiddenItems.count
        hiddenItems.removeAll { Self.normalizedKey($0.mediaID) == normalized }
        guard hiddenItems.count != previousCount else { return }
        touch(updatedAt: updatedAt)
    }

    public mutating func touch(updatedAt: Date = Date()) {
        syncRevision += 1
        self.updatedAt = updatedAt
    }

    private static func normalizedGenrePreferences(_ preferences: [TasteGenrePreference]) -> [TasteGenrePreference] {
        var byGenre: [String: TasteGenrePreference] = [:]
        for preference in preferences where !preference.normalizedGenre.isEmpty {
            byGenre[preference.normalizedGenre] = preference
        }
        return byGenre.values.sorted { $0.genre.localizedCaseInsensitiveCompare($1.genre) == .orderedAscending }
    }

    private static func normalizedHiddenItems(_ items: [HiddenRecommendationItem]) -> [HiddenRecommendationItem] {
        var byID: [String: HiddenRecommendationItem] = [:]
        for item in items where !item.mediaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            byID[normalizedKey(item.mediaID)] = item
        }
        return byID.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func normalizedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var general: GeneralSettings
    public var appearance: AppearanceSettings
    public var home: HomePreferences
    public var recommendations: RecommendationSettings
    public var notifications: NotificationSettings
    public var tasteProfile: TasteProfileSettings
    public var playback: PlaybackSettings
    public var updates: UpdateSettings
    public var privacy: PrivacySettings
    public var storage: StorageSettings

    public init(
        general: GeneralSettings = GeneralSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        home: HomePreferences = HomePreferences(),
        recommendations: RecommendationSettings = RecommendationSettings(),
        notifications: NotificationSettings = NotificationSettings(),
        tasteProfile: TasteProfileSettings = TasteProfileSettings(),
        playback: PlaybackSettings = PlaybackSettings(),
        updates: UpdateSettings = UpdateSettings(),
        privacy: PrivacySettings = PrivacySettings(),
        storage: StorageSettings = StorageSettings()
    ) {
        self.general = general
        self.appearance = appearance
        self.home = home
        self.recommendations = recommendations
        self.notifications = notifications
        self.tasteProfile = tasteProfile
        self.playback = playback
        self.updates = updates
        self.privacy = privacy
        self.storage = storage
    }

    private enum CodingKeys: String, CodingKey {
        case general
        case appearance
        case home
        case recommendations
        case notifications
        case tasteProfile
        case playback
        case updates
        case privacy
        case storage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = try container.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? GeneralSettings()
        appearance = try container.decodeIfPresent(AppearanceSettings.self, forKey: .appearance) ?? AppearanceSettings()
        home = try container.decodeIfPresent(HomePreferences.self, forKey: .home) ?? HomePreferences()
        recommendations = try container.decodeIfPresent(RecommendationSettings.self, forKey: .recommendations) ?? RecommendationSettings()
        notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? NotificationSettings()
        tasteProfile = try container.decodeIfPresent(TasteProfileSettings.self, forKey: .tasteProfile) ?? TasteProfileSettings()
        playback = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playback) ?? PlaybackSettings()
        updates = try container.decodeIfPresent(UpdateSettings.self, forKey: .updates) ?? UpdateSettings()
        privacy = try container.decodeIfPresent(PrivacySettings.self, forKey: .privacy) ?? PrivacySettings()
        storage = try container.decodeIfPresent(StorageSettings.self, forKey: .storage) ?? StorageSettings()
    }
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public var language: AppLanguageSetting
    public var launchAtLogin: Bool
    public var openLastScreenOnLaunch: Bool

    public init(
        language: AppLanguageSetting = .system,
        launchAtLogin: Bool = false,
        openLastScreenOnLaunch: Bool = false
    ) {
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.openLastScreenOnLaunch = openLastScreenOnLaunch
    }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var darkModeOnly: Bool
    public var accentColorName: String
    public var reduceMotion: Bool

    public init(
        darkModeOnly: Bool = true,
        accentColorName: String = "neonPurple",
        reduceMotion: Bool = false
    ) {
        self.darkModeOnly = darkModeOnly
        self.accentColorName = accentColorName
        self.reduceMotion = reduceMotion
    }
}

public enum PreferredQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case p720
    case p1080
    case p2160
    case highestAvailable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            "Auto"
        case .p720:
            "720p"
        case .p1080:
            "1080p"
        case .p2160:
            "2160p"
        case .highestAvailable:
            "Highest available"
        }
    }

    public var targetQuality: ReleaseQuality? {
        switch self {
        case .auto, .highestAvailable:
            nil
        case .p720:
            .hd
        case .p1080:
            .fullHD
        case .p2160:
            .ultraHD
        }
    }
}

public enum HDRPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case preferHDR
    case avoidHDR

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            "Auto"
        case .preferHDR:
            "Prefer HDR"
        case .avoidHDR:
            "Avoid HDR"
        }
    }
}

public enum CodecPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case preferHEVC
    case avoidUnsupportedAV1

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto:
            "Auto"
        case .preferHEVC:
            "Prefer HEVC"
        case .avoidUnsupportedAV1:
            "Avoid AV1 if unsupported"
        }
    }
}

public enum PreferredAudioOrder: String, Codable, CaseIterable, Identifiable, Equatable, Sendable {
    case russianEnglishOriginal
    case englishRussianOriginal
    case originalRussianEnglish
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .russianEnglishOriginal:
            "Russian -> English -> Original"
        case .englishRussianOriginal:
            "English -> Russian -> Original"
        case .originalRussianEnglish:
            "Original -> Russian -> English"
        case .custom:
            "Custom order"
        }
    }

    public func languagePriority(customLanguages: [String]) -> [String] {
        switch self {
        case .russianEnglishOriginal:
            ["ru", "en", "original"]
        case .englishRussianOriginal:
            ["en", "ru", "original"]
        case .originalRussianEnglish:
            ["original", "ru", "en"]
        case .custom:
            Self.normalizedCustomLanguages(customLanguages)
        }
    }

    private static func normalizedCustomLanguages(_ languages: [String]) -> [String] {
        var result = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if !result.contains("original") {
            result.append("original")
        }
        return result.isEmpty ? ["ru", "en", "original"] : Array(NSOrderedSet(array: result)) as? [String] ?? result
    }
}

public struct AudioSelectionOverride: Codable, Equatable, Sendable {
    public var trackID: String?
    public var languageCode: String?
    public var isOriginal: Bool
    public var updatedAt: Date

    public init(
        trackID: String? = nil,
        languageCode: String? = nil,
        isOriginal: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.trackID = trackID
        self.languageCode = languageCode?.lowercased()
        self.isOriginal = isOriginal
        self.updatedAt = updatedAt
    }
}

public struct PlaybackSettings: Codable, Equatable, Sendable {
    public var preferredAudioOrder: PreferredAudioOrder
    public var preferredAudioLanguages: [String]
    public var preferredQuality: PreferredQuality
    public var hdrPreference: HDRPreference
    public var codecPreference: CodecPreference
    public var maxFileSizeBytes: Int64?
    public var preferHighSeedersOverHighestQuality: Bool
    public var hardwareAccelerationEnabled: Bool
    public var startFromLastPosition: Bool
    public var defaultFullscreen: Bool
    public var seekStepSeconds: Int
    public var rememberedVolume: Double
    public var rememberedAudioLanguage: String?
    public var rememberedSubtitleLanguage: String?
    public var subtitlesEnabled: Bool
    public var playbackSpeed: Double
    public var audioBoost: Double
    public var dimBackgroundAroundVideo: Bool
    public var enableTimelinePreviews: Bool
    public var autoplayNextEpisode: Bool
    public var manualAudioOverridesByMediaID: [String: AudioSelectionOverride]

    public init(
        preferredAudioOrder: PreferredAudioOrder = .russianEnglishOriginal,
        preferredAudioLanguages: [String] = ["ru", "en"],
        preferredQuality: PreferredQuality = .auto,
        hdrPreference: HDRPreference = .auto,
        codecPreference: CodecPreference = .auto,
        maxFileSizeBytes: Int64? = nil,
        preferHighSeedersOverHighestQuality: Bool = false,
        hardwareAccelerationEnabled: Bool = true,
        startFromLastPosition: Bool = true,
        defaultFullscreen: Bool = false,
        seekStepSeconds: Int = 10,
        rememberedVolume: Double = 1,
        rememberedAudioLanguage: String? = nil,
        rememberedSubtitleLanguage: String? = nil,
        subtitlesEnabled: Bool = true,
        playbackSpeed: Double = 1,
        audioBoost: Double = 1,
        dimBackgroundAroundVideo: Bool = false,
        enableTimelinePreviews: Bool = true,
        autoplayNextEpisode: Bool = true,
        manualAudioOverridesByMediaID: [String: AudioSelectionOverride] = [:]
    ) {
        self.preferredAudioOrder = preferredAudioOrder
        self.preferredAudioLanguages = Self.normalizedLanguages(preferredAudioLanguages)
        self.preferredQuality = preferredQuality
        self.hdrPreference = hdrPreference
        self.codecPreference = codecPreference
        self.maxFileSizeBytes = maxFileSizeBytes.map { max(0, $0) }
        self.preferHighSeedersOverHighestQuality = preferHighSeedersOverHighestQuality
        self.hardwareAccelerationEnabled = hardwareAccelerationEnabled
        self.startFromLastPosition = startFromLastPosition
        self.defaultFullscreen = defaultFullscreen
        self.seekStepSeconds = seekStepSeconds
        self.rememberedVolume = min(max(rememberedVolume, 0), 1)
        self.rememberedAudioLanguage = rememberedAudioLanguage?.lowercased()
        self.rememberedSubtitleLanguage = rememberedSubtitleLanguage?.lowercased()
        self.subtitlesEnabled = subtitlesEnabled
        self.playbackSpeed = min(max(playbackSpeed, 0.25), 4)
        self.audioBoost = min(max(audioBoost, 1), 2.5)
        self.dimBackgroundAroundVideo = dimBackgroundAroundVideo
        self.enableTimelinePreviews = enableTimelinePreviews
        self.autoplayNextEpisode = autoplayNextEpisode
        self.manualAudioOverridesByMediaID = manualAudioOverridesByMediaID
    }

    private enum CodingKeys: String, CodingKey {
        case preferredAudioOrder
        case preferredAudioLanguages
        case preferredQuality
        case hdrPreference
        case codecPreference
        case maxFileSizeBytes
        case preferHighSeedersOverHighestQuality
        case hardwareAccelerationEnabled
        case startFromLastPosition
        case defaultFullscreen
        case seekStepSeconds
        case rememberedVolume
        case rememberedAudioLanguage
        case rememberedSubtitleLanguage
        case subtitlesEnabled
        case playbackSpeed
        case audioBoost
        case dimBackgroundAroundVideo
        case enableTimelinePreviews
        case autoplayNextEpisode
        case manualAudioOverridesByMediaID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredAudioOrder = try container.decodeIfPresent(PreferredAudioOrder.self, forKey: .preferredAudioOrder) ?? .russianEnglishOriginal
        preferredAudioLanguages = Self.normalizedLanguages(try container.decodeIfPresent([String].self, forKey: .preferredAudioLanguages) ?? ["ru", "en"])
        preferredQuality = try container.decodeIfPresent(PreferredQuality.self, forKey: .preferredQuality) ?? .auto
        hdrPreference = try container.decodeIfPresent(HDRPreference.self, forKey: .hdrPreference) ?? .auto
        codecPreference = try container.decodeIfPresent(CodecPreference.self, forKey: .codecPreference) ?? .auto
        maxFileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .maxFileSizeBytes).map { max(0, $0) }
        preferHighSeedersOverHighestQuality = try container.decodeIfPresent(Bool.self, forKey: .preferHighSeedersOverHighestQuality) ?? false
        hardwareAccelerationEnabled = try container.decodeIfPresent(Bool.self, forKey: .hardwareAccelerationEnabled) ?? true
        startFromLastPosition = try container.decodeIfPresent(Bool.self, forKey: .startFromLastPosition) ?? true
        defaultFullscreen = try container.decodeIfPresent(Bool.self, forKey: .defaultFullscreen) ?? false
        seekStepSeconds = try container.decodeIfPresent(Int.self, forKey: .seekStepSeconds) ?? 10
        rememberedVolume = min(max(try container.decodeIfPresent(Double.self, forKey: .rememberedVolume) ?? 1, 0), 1)
        rememberedAudioLanguage = try container.decodeIfPresent(String.self, forKey: .rememberedAudioLanguage)?.lowercased()
        rememberedSubtitleLanguage = try container.decodeIfPresent(String.self, forKey: .rememberedSubtitleLanguage)?.lowercased()
        subtitlesEnabled = try container.decodeIfPresent(Bool.self, forKey: .subtitlesEnabled) ?? true
        playbackSpeed = min(max(try container.decodeIfPresent(Double.self, forKey: .playbackSpeed) ?? 1, 0.25), 4)
        audioBoost = min(max(try container.decodeIfPresent(Double.self, forKey: .audioBoost) ?? 1, 1), 2.5)
        dimBackgroundAroundVideo = try container.decodeIfPresent(Bool.self, forKey: .dimBackgroundAroundVideo) ?? false
        enableTimelinePreviews = try container.decodeIfPresent(Bool.self, forKey: .enableTimelinePreviews) ?? true
        autoplayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoplayNextEpisode) ?? true
        manualAudioOverridesByMediaID = try container.decodeIfPresent([String: AudioSelectionOverride].self, forKey: .manualAudioOverridesByMediaID) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preferredAudioOrder, forKey: .preferredAudioOrder)
        try container.encode(preferredAudioLanguages, forKey: .preferredAudioLanguages)
        try container.encode(preferredQuality, forKey: .preferredQuality)
        try container.encode(hdrPreference, forKey: .hdrPreference)
        try container.encode(codecPreference, forKey: .codecPreference)
        try container.encodeIfPresent(maxFileSizeBytes, forKey: .maxFileSizeBytes)
        try container.encode(preferHighSeedersOverHighestQuality, forKey: .preferHighSeedersOverHighestQuality)
        try container.encode(hardwareAccelerationEnabled, forKey: .hardwareAccelerationEnabled)
        try container.encode(startFromLastPosition, forKey: .startFromLastPosition)
        try container.encode(defaultFullscreen, forKey: .defaultFullscreen)
        try container.encode(seekStepSeconds, forKey: .seekStepSeconds)
        try container.encode(rememberedVolume, forKey: .rememberedVolume)
        try container.encodeIfPresent(rememberedAudioLanguage, forKey: .rememberedAudioLanguage)
        try container.encodeIfPresent(rememberedSubtitleLanguage, forKey: .rememberedSubtitleLanguage)
        try container.encode(subtitlesEnabled, forKey: .subtitlesEnabled)
        try container.encode(playbackSpeed, forKey: .playbackSpeed)
        try container.encode(audioBoost, forKey: .audioBoost)
        try container.encode(dimBackgroundAroundVideo, forKey: .dimBackgroundAroundVideo)
        try container.encode(enableTimelinePreviews, forKey: .enableTimelinePreviews)
        try container.encode(autoplayNextEpisode, forKey: .autoplayNextEpisode)
        try container.encode(manualAudioOverridesByMediaID, forKey: .manualAudioOverridesByMediaID)
    }

    public func rankingPreferences(
        preferredSubtitleLanguages: [String] = [],
        supportsHDR: Bool = true
    ) -> RankingPreferences {
        RankingPreferences(
            preferredAudioLanguages: preferredAudioLanguages,
            preferredSubtitleLanguages: preferredSubtitleLanguages,
            supportsHDR: supportsHDR,
            preferredQuality: preferredQuality,
            hdrPreference: hdrPreference,
            codecPreference: codecPreference,
            maxFileSizeBytes: maxFileSizeBytes,
            preferHighSeedersOverHighestQuality: preferHighSeedersOverHighestQuality || preferredQuality == .auto
        )
    }

    public var resolvedAudioLanguagePriority: [String] {
        preferredAudioOrder.languagePriority(customLanguages: preferredAudioLanguages)
    }

    private static func normalizedLanguages(_ languages: [String]) -> [String] {
        let normalized = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? ["ru", "en"] : Array(NSOrderedSet(array: normalized)) as? [String] ?? normalized
    }
}

public struct UpdateSettings: Codable, Equatable, Sendable {
    public var automaticChecksEnabled: Bool
    public var sparkleStatus: String

    public init(
        automaticChecksEnabled: Bool = true,
        sparkleStatus: String = "GitHub Releases status checks"
    ) {
        self.automaticChecksEnabled = automaticChecksEnabled
        self.sparkleStatus = sparkleStatus
    }
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public var telemetryEnabled: Bool

    public init(telemetryEnabled: Bool = false) {
        self.telemetryEnabled = telemetryEnabled
    }
}

public struct StorageSettings: Codable, Equatable, Sendable {
    public var torrentCacheFolderPath: String
    public var downloadsFolderPath: String?
    public var cacheRetentionDays: Int
    public var maxCacheSizeBytes: Int64
    public var keepUnfinishedCache: Bool
    public var removeCompletedCache: Bool
    public var torrentDownloadLimitBytesPerSecond: Int64?
    public var torrentUploadLimitBytesPerSecond: Int64?

    public init(
        torrentCacheFolderPath: String = TorrentCacheLocation.defaultStorageURL().path,
        downloadsFolderPath: String? = nil,
        cacheRetentionDays: Int = 30,
        maxCacheSizeBytes: Int64 = 50 * 1_024 * 1_024 * 1_024,
        keepUnfinishedCache: Bool = true,
        removeCompletedCache: Bool = false,
        torrentDownloadLimitBytesPerSecond: Int64? = nil,
        torrentUploadLimitBytesPerSecond: Int64? = nil
    ) {
        self.torrentCacheFolderPath = torrentCacheFolderPath
        self.downloadsFolderPath = downloadsFolderPath
        self.cacheRetentionDays = min(max(cacheRetentionDays, 7), 30)
        self.maxCacheSizeBytes = max(maxCacheSizeBytes, 1_024 * 1_024 * 1_024)
        self.keepUnfinishedCache = keepUnfinishedCache
        self.removeCompletedCache = removeCompletedCache
        self.torrentDownloadLimitBytesPerSecond = torrentDownloadLimitBytesPerSecond
        self.torrentUploadLimitBytesPerSecond = torrentUploadLimitBytesPerSecond
    }

    private enum CodingKeys: String, CodingKey {
        case torrentCacheFolderPath
        case downloadsFolderPath
        case cacheRetentionDays
        case maxCacheSizeBytes
        case keepUnfinishedCache
        case removeCompletedCache
        case torrentDownloadLimitBytesPerSecond
        case torrentUploadLimitBytesPerSecond
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            torrentCacheFolderPath: try container.decodeIfPresent(String.self, forKey: .torrentCacheFolderPath) ?? TorrentCacheLocation.defaultStorageURL().path,
            downloadsFolderPath: try container.decodeIfPresent(String.self, forKey: .downloadsFolderPath),
            cacheRetentionDays: try container.decodeIfPresent(Int.self, forKey: .cacheRetentionDays) ?? 30,
            maxCacheSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .maxCacheSizeBytes) ?? 50 * 1_024 * 1_024 * 1_024,
            keepUnfinishedCache: try container.decodeIfPresent(Bool.self, forKey: .keepUnfinishedCache) ?? true,
            removeCompletedCache: try container.decodeIfPresent(Bool.self, forKey: .removeCompletedCache) ?? false,
            torrentDownloadLimitBytesPerSecond: try container.decodeIfPresent(Int64.self, forKey: .torrentDownloadLimitBytesPerSecond),
            torrentUploadLimitBytesPerSecond: try container.decodeIfPresent(Int64.self, forKey: .torrentUploadLimitBytesPerSecond)
        )
    }

    public var smartCachePolicy: SmartCachePolicy {
        SmartCachePolicy(
            retentionDays: cacheRetentionDays,
            maxSizeBytes: maxCacheSizeBytes,
            keepUnfinished: keepUnfinishedCache,
            removeCompleted: removeCompletedCache
        )
    }

    public var torrentBandwidthLimits: TorrentBandwidthLimits {
        TorrentBandwidthLimits(
            downloadBytesPerSecond: torrentDownloadLimitBytesPerSecond,
            uploadBytesPerSecond: torrentUploadLimitBytesPerSecond
        )
    }
}
