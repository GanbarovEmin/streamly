import Foundation

public enum AppPowerShortcut: Equatable, Sendable {
    case commandF
    case commandL
    case commandK
    case space
    case escape
    case f
    case s
    case a
    case r
}

@MainActor
public final class NavigationCoordinator: ObservableObject {
    @Published public private(set) var currentRoute: AppRoute
    @Published public private(set) var selectedSidebarRoute: AppRoute
    @Published public private(set) var backStack: [AppRoute]
    @Published public private(set) var isPlayerPaused: Bool
    @Published public private(set) var searchFocusRequestID: Int
    @Published public private(set) var refreshRequestID: Int
    @Published public private(set) var fullscreenShortcutRequestID: Int

    public init(initialRoute: AppRoute = .home) {
        let sidebarRoute = initialRoute.isSidebarRoute ? initialRoute : .home
        self.currentRoute = initialRoute
        self.selectedSidebarRoute = sidebarRoute
        self.backStack = []
        self.isPlayerPaused = false
        self.searchFocusRequestID = 0
        self.refreshRequestID = 0
        self.fullscreenShortcutRequestID = 0
    }

    public func selectSidebarRoute(_ route: AppRoute) {
        guard route.isSidebarRoute else { return }
        selectedSidebarRoute = route
        currentRoute = route
        backStack.removeAll()
    }

    public func navigate(to route: AppRoute) {
        guard route != currentRoute else { return }

        if route.isSidebarRoute {
            selectSidebarRoute(route)
            return
        }

        backStack.append(currentRoute)
        currentRoute = route
    }

    public func goBack() {
        guard let previous = backStack.popLast() else {
            return
        }

        currentRoute = previous
        if previous.isSidebarRoute {
            selectedSidebarRoute = previous
        }
    }

    public func closeOverlayOrGoBack() {
        goBack()
    }

    public func focusSearchField() {
        selectSidebarRoute(.search)
        searchFocusRequestID += 1
    }

    public func togglePlayPause() {
        guard case .player = currentRoute else { return }
        isPlayerPaused.toggle()
    }

    public func handleShortcut(_ shortcut: AppPowerShortcut) {
        switch shortcut {
        case .commandF, .commandL, .commandK, .s:
            focusSearchField()
        case .space:
            togglePlayPause()
        case .escape:
            closeOverlayOrGoBack()
        case .f:
            fullscreenShortcutRequestID += 1
        case .a:
            selectSidebarRoute(.library)
        case .r:
            refreshRequestID += 1
        }
    }
}
