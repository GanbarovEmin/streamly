import CineFlowCore
import CineFlowLocalization
import Foundation

public enum AppRoute: Hashable, Identifiable, Sendable {
    case home
    case search
    case movies
    case series
    case library
    case continueWatching
    case lists
    case history
    case settings
    case mediaDetail(id: String)
    case collectionDetail(id: String)
    case personDetail(PersonRoutePayload)
    case player(
        mediaID: String,
        sourceID: String? = nil,
        release: TorrentRelease? = nil,
        fallbackReleases: [TorrentRelease] = [],
        selectionContext: PlaybackSelectionContext? = nil,
        nextEpisodePrompt: PlayerNextEpisodePrompt? = nil
    )
    case settingsSection(id: String)

    public var id: String {
        switch self {
        case .home:
            "home"
        case .search:
            "search"
        case .movies:
            "movies"
        case .series:
            "series"
        case .library:
            "library"
        case .continueWatching:
            "continueWatching"
        case .lists:
            "lists"
        case .history:
            "history"
        case .settings:
            "settings"
        case .mediaDetail(let id):
            "mediaDetail:\(id)"
        case .collectionDetail(let id):
            "collectionDetail:\(id)"
        case .personDetail(let person):
            "personDetail:\(person.id)"
        case .player(let mediaID, let sourceID, let release, let fallbackReleases, let selectionContext, let nextEpisodePrompt):
            "player:\(mediaID):\(sourceID ?? "auto"):\(release?.id ?? "no-release"):\(fallbackReleases.map(\.id).joined(separator: ",")):\(selectionContext?.episodeID ?? selectionContext?.mediaID ?? "no-context"):\(nextEpisodePrompt?.title ?? "no-next")"
        case .settingsSection(let id):
            "settingsSection:\(id)"
        }
    }

    public var isSidebarRoute: Bool {
        Self.sidebarRoutes.contains(self)
    }

    public var titleKey: L10nKey {
        switch self {
        case .home:
            .navigationHome
        case .search:
            .navigationSearch
        case .movies:
            .navigationMovies
        case .series:
            .navigationSeries
        case .library:
            .navigationLibrary
        case .continueWatching:
            .navigationContinueWatching
        case .lists:
            .navigationLists
        case .history:
            .navigationHistory
        case .settings:
            .navigationSettings
        case .mediaDetail:
            .navigationMediaDetail
        case .collectionDetail:
            .navigationMediaDetail
        case .personDetail:
            .navigationMediaDetail
        case .player:
            .navigationPlayer
        case .settingsSection:
            .navigationSettingsSection
        }
    }

    public var systemImage: String {
        switch self {
        case .home:
            "house.fill"
        case .search:
            "magnifyingglass"
        case .movies:
            "film.fill"
        case .series:
            "tv.fill"
        case .library:
            "rectangle.stack.fill"
        case .continueWatching:
            "play.rectangle.fill"
        case .lists:
            "list.bullet.rectangle.fill"
        case .history:
            "clock.arrow.circlepath"
        case .settings:
            "gearshape.fill"
        case .mediaDetail:
            "info.circle.fill"
        case .collectionDetail:
            "rectangle.stack.fill.badge.person.crop"
        case .personDetail:
            "person.crop.rectangle.stack.fill"
        case .player:
            "play.circle.fill"
        case .settingsSection:
            "slider.horizontal.3"
        }
    }

    public static let sidebarRoutes: [AppRoute] = [
        .home,
        .search,
        .movies,
        .series,
        .library,
        .continueWatching,
        .lists,
        .history,
        .settings
    ]
}

public struct ShellTopControl: Identifiable, Equatable, Sendable {
    public let id: String
    public let titleKey: L10nKey
    public let systemImage: String

    public init(id: String, titleKey: L10nKey, systemImage: String) {
        self.id = id
        self.titleKey = titleKey
        self.systemImage = systemImage
    }
}

public struct MainShellState: Equatable, Sendable {
    public var selectedRoute: AppRoute
    public var topControls: [ShellTopControl]

    public init(
        selectedRoute: AppRoute = .home,
        topControls: [ShellTopControl] = MainShellState.defaultTopControls
    ) {
        self.selectedRoute = selectedRoute
        self.topControls = topControls
    }

    public static let defaultTopControls: [ShellTopControl] = [
        ShellTopControl(id: "updates", titleKey: .topControlUpdates, systemImage: "arrow.triangle.2.circlepath"),
        ShellTopControl(id: "notifications", titleKey: .topControlNotifications, systemImage: "bell.fill"),
        ShellTopControl(id: "profile", titleKey: .topControlProfile, systemImage: "person.crop.circle.fill")
    ]
}
