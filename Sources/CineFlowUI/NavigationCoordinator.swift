import Foundation

@MainActor
public final class NavigationCoordinator: ObservableObject {
    @Published public private(set) var currentRoute: AppRoute
    @Published public private(set) var selectedSidebarRoute: AppRoute
    @Published public private(set) var backStack: [AppRoute]
    @Published public private(set) var isPlayerPaused: Bool
    @Published public private(set) var searchFocusRequestID: Int

    public init(initialRoute: AppRoute = .home) {
        let sidebarRoute = initialRoute.isSidebarRoute ? initialRoute : .home
        self.currentRoute = initialRoute
        self.selectedSidebarRoute = sidebarRoute
        self.backStack = []
        self.isPlayerPaused = false
        self.searchFocusRequestID = 0
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
}
