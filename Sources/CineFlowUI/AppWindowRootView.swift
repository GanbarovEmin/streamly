import CineFlowCore
import CineFlowDesignSystem
import CineFlowPlayback
import CineFlowSources
import SwiftUI
import UniformTypeIdentifiers

public struct AppWindowRootView: View {
    private let environment: AppEnvironment
    private let navigationCoordinator: NavigationCoordinator
    private let searchProvider: any SearchProviderProtocol
    private let sourceManager: SourceManager?
    private let playbackProgressRecorder: PlaybackProgressRecorder?
    @ObservedObject private var macOSIntegrationViewModel: MacOSIntegrationViewModel

    public init(
        environment: AppEnvironment,
        navigationCoordinator: NavigationCoordinator,
        searchProvider: any SearchProviderProtocol = MockSearchProvider(),
        sourceManager: SourceManager? = nil,
        playbackProgressRecorder: PlaybackProgressRecorder? = nil,
        macOSIntegrationViewModel: MacOSIntegrationViewModel
    ) {
        self.environment = environment
        self.navigationCoordinator = navigationCoordinator
        self.searchProvider = searchProvider
        self.sourceManager = sourceManager
        self.playbackProgressRecorder = playbackProgressRecorder
        self.macOSIntegrationViewModel = macOSIntegrationViewModel
    }

    public var body: some View {
        ZStack {
            CFGlobalBackground()

            MainShellView(
                environment: environment,
                navigationCoordinator: navigationCoordinator,
                searchProvider: searchProvider,
                sourceManager: sourceManager,
                playbackProgressRecorder: playbackProgressRecorder
            )

            if macOSIntegrationViewModel.isDropTargeted {
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .stroke(CFColors.accentPrimary, lineWidth: 2)
                    .background(CFColors.accentPrimary.opacity(0.08))
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.plainText.identifier],
            isTargeted: Binding(
                get: { macOSIntegrationViewModel.isDropTargeted },
                set: { macOSIntegrationViewModel.setDropTargeted($0) }
            ),
            perform: macOSIntegrationViewModel.handleDropProviders
        )
        .preferredColorScheme(.dark)
        .frame(minWidth: 1200, minHeight: 760)
        .background(
            AppWindowConfigurator(
                defaultSize: CGSize(width: 1440, height: 900),
                minimumSize: CGSize(width: 1200, height: 760)
            )
        )
    }
}
