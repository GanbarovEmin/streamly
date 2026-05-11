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
                            onQueryChange: { query in
                                searchViewModel.updateQuery(query)
                                navigationCoordinator.selectSidebarRoute(.search)
                            },
                            onSearchFocus: {
                                navigationCoordinator.selectSidebarRoute(.search)
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
        }
        .background(CFColors.clear)
        .environment(\.cfReduceMotion, reduceMotion)
        .cfAnimation(.easeInOut(duration: 0.22), value: navigationCoordinator.currentRoute, reduceMotion: reduceMotion)
        .task {
            await viewModel.load()
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
            imagePipeline: imagePipeline
        )
        .id(navigationCoordinator.currentRoute.id)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.995)))
    }
}
