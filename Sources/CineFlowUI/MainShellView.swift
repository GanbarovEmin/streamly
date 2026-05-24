import CineFlowCore
import CineFlowDesignSystem
import CineFlowPlayback
import CineFlowSources
import SwiftUI

public struct MainShellView: View {
    private let environment: AppEnvironment
    private let sourceManager: SourceManager?
    private let playbackProgressRecorder: PlaybackProgressRecorder?

    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var viewModel: CineFlowRootViewModel
    @StateObject private var searchViewModel: SearchViewModel
    @StateObject private var imagePipeline: CineFlowImagePipeline
    @StateObject private var notificationCenterViewModel: BetterReleaseNotificationCenterViewModel
    @State private var showsNotificationCenter = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("streamly.reduceMotion") private var appReduceMotion = false
    private let showsPerformanceOverlay: Bool

    public init(
        environment: AppEnvironment,
        navigationCoordinator: NavigationCoordinator,
        searchProvider: any SearchProviderProtocol = MockSearchProvider(),
        sourceManager: SourceManager? = nil,
        playbackProgressRecorder: PlaybackProgressRecorder? = nil
    ) {
        self.environment = environment
        self.sourceManager = sourceManager
        self.playbackProgressRecorder = playbackProgressRecorder
        self.navigationCoordinator = navigationCoordinator
        _viewModel = StateObject(wrappedValue: CineFlowRootViewModel(environment: environment, sourceManager: sourceManager))
        _searchViewModel = StateObject(wrappedValue: SearchViewModel(
            provider: searchProvider,
            diagnosticsService: environment.diagnosticsService,
            settingsRepository: environment.settingsRepository
        ))
        _imagePipeline = StateObject(wrappedValue: CineFlowImagePipeline(imageCacheService: environment.imageCacheService))
        let notificationStore = UserDefaultsNotificationCenterStore()
        _notificationCenterViewModel = StateObject(wrappedValue: NotificationCenterViewModel(
            store: notificationStore,
            service: BetterReleaseNotificationService(
                libraryRepository: environment.libraryRepository,
                settingsRepository: environment.settingsRepository,
                store: notificationStore
            ),
            settingsRepository: environment.settingsRepository
        ))
        showsPerformanceOverlay = ProcessInfo.processInfo.environment["CINEFLOW_PERFORMANCE_OVERLAY"] == "1"
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            if isPlayerRoute {
                contentContainer
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    SidebarView(navigationCoordinator: navigationCoordinator)
                        .frame(width: 244)

                    VStack(spacing: 0) {
                        TopSearchBarView(
                            controls: MainShellState.defaultTopControls,
                            focusRequestID: navigationCoordinator.searchFocusRequestID,
                            queryText: searchViewModel.queryText,
                            isLoading: searchViewModel.state == .loading,
                            controlBadges: ["notifications": notificationCenterViewModel.unreadCount],
                            onQueryChange: { query in
                                searchViewModel.updateQuery(query)
                            },
                            onClear: {
                                searchViewModel.clearQuery()
                            },
                            onSearchFocus: {
                                navigationCoordinator.focusSearchField()
                            },
                            onControlAction: { control in
                                handleTopControl(control)
                            }
                        )
                            .frame(height: 92)

                        contentContainer
                    }
                }
            }

            if showsPerformanceOverlay {
                PerformanceDebugOverlay(imagePipeline: imagePipeline, environment: environment)
            }

            if showsNotificationCenter {
                NotificationCenterView(viewModel: notificationCenterViewModel) { route in
                    navigationCoordinator.navigate(to: route)
                    showsNotificationCenter = false
                }
                .padding(.top, 74)
                .padding(.trailing, CFSpacing.xl)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(CFColors.clear)
        .environment(\.cfReduceMotion, reduceMotion)
        .cfAnimation(.easeInOut(duration: 0.22), value: navigationCoordinator.currentRoute, reduceMotion: reduceMotion)
        .task {
            await viewModel.load()
            await notificationCenterViewModel.load()
        }
    }

    private func handleTopControl(_ control: ShellTopControl) {
        switch control.id {
        case "notifications":
            showsNotificationCenter.toggle()
            if showsNotificationCenter {
                Task { await notificationCenterViewModel.refresh() }
            }
        case "refresh":
            navigationCoordinator.requestRefresh()
        case "profile":
            navigationCoordinator.selectSidebarRoute(.settings)
        default:
            break
        }
    }

    private var reduceMotion: Bool {
        systemReduceMotion || appReduceMotion
    }

    private var isPlayerRoute: Bool {
        if case .player = navigationCoordinator.currentRoute {
            return true
        }
        return false
    }

    private var contentContainer: some View {
        ContentContainerView(
            route: navigationCoordinator.currentRoute,
            environment: environment,
            viewModel: viewModel,
            searchViewModel: searchViewModel,
            navigationCoordinator: navigationCoordinator,
            sourceManager: sourceManager,
            playbackProgressRecorder: playbackProgressRecorder,
            imagePipeline: imagePipeline,
            notificationCenterViewModel: notificationCenterViewModel
        )
        .id(navigationCoordinator.currentRoute.id)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.995)))
    }
}
