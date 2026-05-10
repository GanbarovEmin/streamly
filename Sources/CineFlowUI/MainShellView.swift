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
        _viewModel = StateObject(wrappedValue: CineFlowRootViewModel(environment: environment))
        _searchViewModel = StateObject(wrappedValue: SearchViewModel(provider: searchProvider, diagnosticsService: environment.diagnosticsService))
    }

    public var body: some View {
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

                ContentContainerView(
                    route: navigationCoordinator.currentRoute,
                    environment: environment,
                    viewModel: viewModel,
                    searchViewModel: searchViewModel,
                    navigationCoordinator: navigationCoordinator,
                    sourceManager: sourceManager,
                    playbackProgressRecorder: playbackProgressRecorder
                )
                .id(navigationCoordinator.currentRoute.id)
                .transition(.opacity.combined(with: .scale(scale: 0.995)))
            }
        }
        .background(CFColors.clear)
        .animation(.easeInOut(duration: 0.22), value: navigationCoordinator.currentRoute)
        .task {
            await viewModel.load()
        }
    }
}
