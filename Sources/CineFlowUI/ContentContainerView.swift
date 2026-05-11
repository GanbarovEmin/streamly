import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import CineFlowPlayback
import CineFlowSources
import SwiftUI

public struct ContentContainerView: View {
    public let route: AppRoute

    @ObservedObject private var viewModel: CineFlowRootViewModel
    @ObservedObject private var searchViewModel: SearchViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @StateObject private var homeViewModel: HomeViewModel
    @StateObject private var libraryViewModel: LibraryViewModel
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    private let environment: AppEnvironment
    private let sourceManager: SourceManager?
    private let playbackProgressRecorder: PlaybackProgressRecorder?
    private let imagePipeline: CineFlowImagePipeline

    public init(
        route: AppRoute,
        environment: AppEnvironment,
        viewModel: CineFlowRootViewModel,
        searchViewModel: SearchViewModel,
        navigationCoordinator: NavigationCoordinator,
        sourceManager: SourceManager? = nil,
        playbackProgressRecorder: PlaybackProgressRecorder? = nil,
        imagePipeline: CineFlowImagePipeline
    ) {
        self.route = route
        self.viewModel = viewModel
        self.searchViewModel = searchViewModel
        self.navigationCoordinator = navigationCoordinator
        self.environment = environment
        self.sourceManager = sourceManager
        self.playbackProgressRecorder = playbackProgressRecorder
        self.imagePipeline = imagePipeline
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(
            metadataService: environment.metadataService,
            progressRepository: environment.playbackProgressRepository,
            libraryRepository: environment.libraryRepository
        ))
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(repository: environment.libraryRepository))
    }

    public var body: some View {
        if route == .home {
            HomeView(viewModel: homeViewModel, navigationCoordinator: navigationCoordinator, imagePipeline: imagePipeline)
        } else if route == .search {
            SearchView(viewModel: searchViewModel, navigationCoordinator: navigationCoordinator)
        } else if route == .library {
            LibraryView(viewModel: libraryViewModel, navigationCoordinator: navigationCoordinator, initialSection: .favorites, imagePipeline: imagePipeline)
        } else if route == .lists {
            UserListsView(
                viewModel: UserListsViewModel(repository: environment.libraryRepository),
                navigationCoordinator: navigationCoordinator,
                imagePipeline: imagePipeline
            )
        } else if route == .history {
            if let historyRepository = environment.watchHistoryRepository {
                WatchHistoryView(
                    viewModel: WatchHistoryViewModel(repository: historyRepository),
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                LibraryView(viewModel: libraryViewModel, navigationCoordinator: navigationCoordinator, initialSection: .watched, imagePipeline: imagePipeline)
            }
        } else if route == .continueWatching {
            if let progressRepository = environment.playbackProgressRepository {
                ContinueWatchingView(
                    viewModel: ContinueWatchingViewModel(repository: progressRepository),
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                LibraryView(viewModel: libraryViewModel, navigationCoordinator: navigationCoordinator, initialSection: .watched, imagePipeline: imagePipeline)
            }
        } else if route == .settings {
            SettingsView(
                viewModel: SettingsViewModel(
                    environment: environment,
                    sourceManager: sourceManager
                )
            )
        } else if case .mediaDetail(let id) = route {
            if id.contains(":tv:") || id.contains(":series:") {
                SeriesDetailView(
                    seriesID: id,
                    navigationCoordinator: navigationCoordinator,
                    libraryRepository: environment.libraryRepository,
                    detailProvider: TMDBSeriesDetailProvider(
                        metadataService: environment.metadataService,
                        torrentAggregator: sourceManager.map { TorrentSearchAggregator(sourceManager: $0) }
                    ),
                    userMediaSourceRepository: environment.userMediaSourceRepository,
                    settingsRepository: environment.settingsRepository,
                    diagnosticsService: environment.diagnosticsService
                )
            } else {
                MovieDetailView(
                    mediaID: id,
                    navigationCoordinator: navigationCoordinator,
                    libraryRepository: environment.libraryRepository,
                    detailProvider: TMDBMovieDetailProvider(
                        metadataService: environment.metadataService,
                        torrentAggregator: sourceManager.map { TorrentSearchAggregator(sourceManager: $0) }
                    ),
                    userMediaSourceRepository: environment.userMediaSourceRepository,
                    settingsRepository: environment.settingsRepository,
                    diagnosticsService: environment.diagnosticsService
                )
            }
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                hero

                contentBody
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .animation(CFMotion.standard, value: route)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(t(route.titleKey).uppercased())
                .font(CFTypography.overline)
                .tracking(1.4)
                .foregroundStyle(CFColors.accentPrimary)

            Text(viewModel.headline)
                .font(CFTypography.heroTitle)
                .foregroundStyle(CFColors.textPrimary)

            Text(heroSubtitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(CFColors.textSecondary)

            HStack(spacing: 12) {
                ShellMetric(title: t(.heroBestRelease), value: releaseSummary)
                ShellMetric(title: t(.heroMode), value: t(.heroModeValue))
                ShellMetric(title: t(.heroLanguage), value: languageSummary)
            }
            .padding(.top, 4)

            HStack(spacing: CFSpacing.md) {
                PrimaryButton(t(.heroOpenDetail), systemImage: "info.circle.fill") {
                    navigationCoordinator.navigate(to: .mediaDetail(id: heroMediaID))
                }

                SecondaryButton(t(.heroOpenPlayer), systemImage: "play.fill") {
                    navigationCoordinator.navigate(
                        to: .player(
                            mediaID: heroMediaID,
                            selectionContext: heroPlaybackContext
                        )
                    )
                }
            }
        }
        .padding(CFSpacing.xl)
        .frame(maxWidth: .infinity, minHeight: 318, alignment: .bottomLeading)
        .background(CFHeroSurface())
    }

    private var heroMediaID: String {
        homeViewModel.selectedFeaturedItem?.id ?? "tmdb:movie:693134"
    }

    private var heroPlaybackContext: PlaybackSelectionContext {
        PlaybackSelectionContext(
            mediaID: heroMediaID,
            displayTitle: homeViewModel.selectedFeaturedItem?.title ?? viewModel.headline,
            mediaKind: heroMediaID.contains(":tv:") ? .series : .movie
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 164, maximum: 220), spacing: 16)]
    }

    @ViewBuilder
    private var contentBody: some View {
        switch route {
        case .mediaDetail(let id):
            DeepLinkPlaceholderView(
                title: t(.navigationMediaDetail),
                subtitle: "Откройте экран детализации из поиска, библиотеки или домашней подборки.",
                systemImage: "info.circle.fill",
                actionTitle: t(.deepLinkOpenPlayer)
            ) {
                navigationCoordinator.navigate(to: .player(mediaID: id))
            }
        case .player(let mediaID, let sourceID, let release, let fallbackReleases, let selectionContext, let nextEpisodePrompt):
            PlayerRouteView(
                mediaID: mediaID,
                sourceID: sourceID,
                release: release,
                fallbackReleases: fallbackReleases,
                selectionContext: selectionContext,
                nextEpisodePrompt: nextEpisodePrompt,
                environment: environment,
                sourceManager: sourceManager,
                playbackService: viewModel.playbackService,
                playbackProgressRecorder: playbackProgressRecorder,
                language: selectedLanguage,
                onExit: {
                    navigationCoordinator.goBack()
                },
                onNextEpisode: { action in
                    if action.requiresManualReleaseSelection || action.release == nil {
                        navigationCoordinator.goBack()
                    } else {
                        navigationCoordinator.navigate(to: .player(
                            mediaID: action.mediaID,
                            sourceID: action.sourceID,
                            release: action.release,
                            fallbackReleases: action.fallbackReleases,
                            selectionContext: action.selectionContext
                        ))
                    }
                }
            )
        case .settingsSection:
            DeepLinkPlaceholderView(
                title: t(.navigationSettingsSection),
                subtitle: "Расширенный раздел настроек.",
                systemImage: "slider.horizontal.3",
                actionTitle: t(.deepLinkBack)
            ) {
                navigationCoordinator.goBack()
            }
        case .settings:
            settingsBody
        default:
            routeGrid
        }
    }

    private var routeGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t(sectionTitleKey))
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(sampleCards) { card in
                    PosterCard(model: card) {
                        navigationCoordinator.navigate(to: .mediaDetail(id: card.id))
                    } imageDataLoader: { url in
                        try await imagePipeline.data(for: url)
                    }
                }
            }
        }
    }

    private var settingsBody: some View {
        VStack(alignment: .leading, spacing: CFSpacing.lg) {
            Text(t(.sectionSettings))
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            LanguageSettingsCard()

            SubtitleSettingsCard(viewModel: viewModel)

            ImageCacheSettingsCard(viewModel: viewModel)

            if let sourceManager {
                SourceSettingsCard(manager: sourceManager)
            }

            SecondaryButton(t(.settingsOpenAdvanced), systemImage: "slider.horizontal.3") {
                navigationCoordinator.navigate(to: .settingsSection(id: "language"))
            }
        }
    }

    private var sectionTitleKey: L10nKey {
        switch route {
        case .home:
            .sectionFeaturedLibrary
        case .search:
            .sectionSearchPreview
        case .movies:
            .sectionMovies
        case .series:
            .sectionSeries
        case .library:
            .sectionLocalLibrary
        case .continueWatching:
            .sectionContinueWatching
        case .lists:
            .sectionLists
        case .history:
            .sectionHistory
        case .settings:
            .sectionSettings
        case .mediaDetail:
            .navigationMediaDetail
        case .player:
            .navigationPlayer
        case .settingsSection:
            .navigationSettingsSection
        }
    }

    private var sampleCards: [CFMediaCardModel] {
        [
            CFMediaCardModel(id: "matrix", title: t(.sampleMatrixTitle), metadata: sampleMetadata(quality: "2160p", seeders: 88), badge: "2160p"),
            CFMediaCardModel(id: "arrival", title: t(.sampleArrivalTitle), metadata: sampleMetadata(quality: "2160p", seeders: 64), badge: "2160p"),
            CFMediaCardModel(id: "blade", title: t(.sampleBladeRunnerTitle), metadata: sampleMetadata(quality: "1080p", seeders: 140), badge: "1080p"),
            CFMediaCardModel(id: "dune", title: t(.sampleDuneTitle), metadata: sampleMetadata(quality: "2160p", seeders: 102), badge: "2160p"),
            CFMediaCardModel(id: "heat", title: t(.sampleHeatTitle), metadata: sampleMetadata(quality: "1080p", seeders: 73), badge: "1080p")
        ]
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private var heroSubtitle: String {
        if viewModel.didFailToLoad {
            return t(.heroLoadFailedSubtitle)
        }
        guard viewModel.didLoadMetadata else {
            return t(.heroNativeShellSubtitle)
        }

        let year = viewModel.releaseYear.map(String.init) ?? t(.heroUnknownYear)
        let kind = t(mediaKindKey)
        return "\(year) · \(kind)"
    }

    private var mediaKindKey: L10nKey {
        switch viewModel.mediaKind {
        case .movie:
            .mediaKindMovie
        case .series:
            .mediaKindSeries
        case nil:
            .mediaKindMovie
        }
    }

    private var releaseSummary: String {
        guard let title = viewModel.bestReleaseTitle, let seeders = viewModel.bestReleaseSeeders else {
            return t(.bestReleaseUnavailable)
        }

        return L10n.format(.bestReleaseFormat, language: selectedLanguage, title, seeders)
    }

    private var languageSummary: String {
        guard !viewModel.subtitleLanguagePriority.isEmpty else {
            return t(.subtitleLanguageUnavailable)
        }

        return L10n.format(.subtitleLanguageFormat, language: selectedLanguage, viewModel.subtitleLanguagePriority.joined(separator: " -> "))
    }

    private func sampleMetadata(quality: String, seeders: Int) -> String {
        L10n.format(.sampleMetadataFormat, language: selectedLanguage, quality, seeders)
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct PlayerRouteView: View {
    let mediaID: String
    let sourceID: String?
    let release: TorrentRelease?
    let fallbackReleases: [TorrentRelease]
    let selectionContext: PlaybackSelectionContext?
    let nextEpisodePrompt: PlayerNextEpisodePrompt?
    let environment: AppEnvironment
    let sourceManager: SourceManager?
    let playbackService: any PlaybackServiceProtocol
    let playbackProgressRecorder: PlaybackProgressRecorder?
    let language: AppLanguage
    let onExit: () -> Void
    let onNextEpisode: (PlayerNextEpisodeAction) -> Void

    @State private var state: RouteState = .loading
    @State private var rankingPreferences = RankingPreferences()
    @State private var activeFallbackReleases: [TorrentRelease] = []
    @State private var activeSelectionContext: PlaybackSelectionContext?
    @StateObject private var sessionCoordinator = PlaybackSessionCoordinator()

    var body: some View {
        Group {
            switch state {
            case .loading:
                playbackRouteLoadingView
            case .missingSource:
                EmptyState(
                    title: t(.playerMissingSourceTitle),
                    message: t(.playerMissingSourceMessage),
                    systemImage: "play.slash",
                    actionTitle: t(.playerMissingSourceAction),
                    actionSystemImage: "chevron.left",
                    action: onExit
                )
                .frame(maxWidth: .infinity, minHeight: 520)
            case .unsupportedSource:
                ErrorState(
                    title: t(.playerUnsupportedSourceTitle),
                    message: t(.playerUnsupportedSourceMessage),
                    recoverySuggestion: t(.playerUnsupportedSourceRecovery),
                    actionTitle: t(.playerMissingSourceAction),
                    action: onExit
                )
                .padding(CFSpacing.xl)
            case .torrentFailed(let message, let suggestion):
                ErrorState(
                    title: t(.playerTorrentErrorTitle),
                    message: message.isEmpty ? t(.playerTorrentErrorMessage) : message,
                    recoverySuggestion: t(.playerTorrentErrorRecovery),
                    actionTitle: suggestion?.nextBestRelease == nil ? t(.playerMissingSourceAction) : t(.playerFallbackTryNext),
                    action: {
                        if let release = suggestion?.nextBestRelease?.release {
                            Task { await loadTorrentRelease(release) }
                        } else {
                            onExit()
                        }
                    }
                )
                .padding(CFSpacing.xl)
            case .chooseMediaFile(let session, let release, let options):
                mediaFileSelectionView(session: session, release: release, options: options)
            case .ready(let source, let torrentSession):
                PlayerView(
                    viewModel: PlayerViewModel(
                        service: playbackService,
                        mediaSource: source,
                        torrentEngine: torrentSession == nil ? nil : environment.torrentEngine,
                        torrentSession: torrentSession,
                        subtitleService: environment.subtitleService,
                        settingsRepository: environment.settingsRepository,
                        timelinePreviewService: environment.timelinePreviewService,
                        diagnosticsService: environment.diagnosticsService,
                        progressRecorder: playbackProgressRecorder,
                        progressRepository: environment.playbackProgressRepository,
                        fallbackReleases: effectiveFallbackReleases,
                        fallbackPreferences: rankingPreferences,
                        fallbackHandler: { release in
                            await loadTorrentRelease(release)
                        },
                        nextEpisodePrompt: nextEpisodePrompt
                    ),
                    onExit: onExit,
                    onNextEpisode: onNextEpisode
                )
            }
        }
        .task(id: "\(mediaID):\(sourceID ?? "auto"):\(release?.id ?? "no-release"):\(fallbackReleases.map(\.id).joined(separator: ",")):\(selectionContext?.episodeID ?? selectionContext?.mediaID ?? "no-context"):\(nextEpisodePrompt?.title ?? "no-next")") {
            await load()
        }
        .onDisappear {
            Task {
                await sessionCoordinator.cleanup(
                    torrentEngine: environment.torrentEngine,
                    playbackService: playbackService,
                    diagnosticsService: environment.diagnosticsService,
                    mediaID: mediaID,
                    reason: "route.disappear"
                )
            }
        }
    }

    private var playbackRouteLoadingView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CFColors.backgroundPrimary,
                    CFColors.backgroundSecondary.opacity(0.94),
                    CFColors.backgroundPrimary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))

            VStack(spacing: CFSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                    .tint(CFColors.accentPrimary)
                Text(t(.playerBufferingTitle))
                    .font(CFTypography.title.weight(.semibold))
                    .foregroundStyle(CFColors.textPrimary)
                Text(L10n.format(.playerBufferingMessageFormat, language: language, 0))
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textSecondary)
            }
            .padding(CFSpacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: 520)
        .padding(CFSpacing.xl)
    }

    private func load() async {
        activeSelectionContext = selectionContext
        activeFallbackReleases = fallbackReleases

        if let release {
            await loadTorrentRelease(release)
            return
        }

        let requestID = await sessionCoordinator.beginNewSession(
            torrentEngine: environment.torrentEngine,
            playbackService: playbackService,
            diagnosticsService: environment.diagnosticsService,
            mediaID: mediaID,
            reason: "local.source.load"
        )

        if sourceID == nil,
           let sourceManager,
           let resolution = await PlaybackAutoSourceResolver(
            metadataService: environment.metadataService,
            sourceManager: sourceManager,
            diagnosticsService: environment.diagnosticsService
           ).resolveBestRelease(mediaID: mediaID, selectionContext: selectionContext) {
            guard sessionCoordinator.isCurrent(requestID) else { return }
            activeSelectionContext = resolution.selectionContext
            activeFallbackReleases = resolution.fallbackReleases
            await loadTorrentRelease(
                resolution.release,
                fallbackReleases: resolution.fallbackReleases,
                selectionContext: resolution.selectionContext
            )
            return
        }

        guard let repository = environment.userMediaSourceRepository else {
            await environment.diagnosticsService.log(
                level: .warning,
                subsystem: .playback,
                message: "Playback source repository is unavailable.",
                metadata: ["operation": "player.route.localSource", "mediaID": mediaID]
            )
            state = .missingSource
            return
        }

        do {
            let source: UserMediaSource?
            if let sourceID {
                source = try await repository.source(id: sourceID)
            } else {
                source = try await repository.sources(for: mediaID).first
            }

            guard let source else {
                guard sessionCoordinator.isCurrent(requestID) else { return }
                state = .missingSource
                return
            }

            guard sessionCoordinator.isCurrent(requestID) else { return }
            if let playbackSource = source.playbackMediaSource {
                state = .ready(
                    PlaybackMediaSource(
                        id: effectiveSelectionContext?.episodeID ?? playbackSource.id,
                        title: effectiveSelectionContext?.displayTitle ?? playbackSource.title,
                        url: playbackSource.url,
                        release: playbackSource.release,
                        qualityLabel: playbackSource.qualityLabel,
                        sourceName: playbackSource.sourceName,
                        selectionContext: effectiveSelectionContext
                    ),
                    nil
                )
            } else {
                state = .unsupportedSource(source.displayName)
            }
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .database)
            await environment.diagnosticsService.log(cineFlowError, operation: "player.route.localSource", metadata: ["mediaID": mediaID])
            state = .missingSource
        }
    }

    private var effectiveFallbackReleases: [TorrentRelease] {
        activeFallbackReleases.isEmpty ? fallbackReleases : activeFallbackReleases
    }

    private var effectiveSelectionContext: PlaybackSelectionContext? {
        activeSelectionContext ?? selectionContext
    }

    private func loadTorrentRelease(
        _ release: TorrentRelease,
        fallbackReleases overrideFallbackReleases: [TorrentRelease]? = nil,
        selectionContext overrideSelectionContext: PlaybackSelectionContext? = nil
    ) async {
        let resolvedFallbackReleases = overrideFallbackReleases ?? effectiveFallbackReleases
        let resolvedSelectionContext = overrideSelectionContext ?? effectiveSelectionContext
        activeFallbackReleases = resolvedFallbackReleases
        activeSelectionContext = resolvedSelectionContext

        let requestID = await sessionCoordinator.beginNewSession(
            torrentEngine: environment.torrentEngine,
            playbackService: playbackService,
            diagnosticsService: environment.diagnosticsService,
            mediaID: mediaID,
            reason: "source.switch"
        )
        state = .loading

        let appSettings = await environment.settingsRepository.appSettings
        let subtitleLanguages = await environment.settingsRepository.subtitleLanguagePriority
        let preferences = appSettings.playback.rankingPreferences(
            preferredSubtitleLanguages: subtitleLanguages,
            supportsHDR: true
        )
        rankingPreferences = preferences

        let pipeline = PlaybackPipeline(
            torrentEngine: environment.torrentEngine,
            debugLogger: PlaybackDebugLogger(),
            diagnosticsService: environment.diagnosticsService
        )
        let result = await pipeline.resolve(
            PlaybackPipelineRequest(
                mediaID: mediaID,
                selectionContext: resolvedSelectionContext,
                primaryRelease: release,
                fallbackReleases: resolvedFallbackReleases,
                bandwidthLimits: appSettings.storage.torrentBandwidthLimits,
                maxAutomaticFallbacks: 2,
                rankingPreferences: preferences
            )
        )

        guard !Task.isCancelled, sessionCoordinator.isCurrent(requestID) else { return }

        switch result {
        case .ready(let source, let session, _):
            sessionCoordinator.activate(session)
            state = .ready(source, session)
        case .needsMediaFileSelection(let session, let release, let options, _):
            sessionCoordinator.activate(session)
            state = .chooseMediaFile(session, release, options)
        case .failed(let error, let suggestion, _):
            state = .torrentFailed(error.userMessage, suggestion ?? fallbackSuggestion(for: release, reason: .failedToStart))
            await environment.diagnosticsService.log(
                error,
                operation: "player.route.torrent",
                metadata: ["mediaID": mediaID, "releaseID": release.id, "sourceID": release.sourceId]
            )
        }
    }

    private func finishTorrentPlayback(session: TorrentSession, release: TorrentRelease) async throws {
        let streamingURL = try await environment.torrentEngine.getStreamingURL(sessionId: session.id)
        guard streamingURL.isCineFlowPlayableMediaURL else {
            throw PlaybackServiceError.invalidMediaURL
        }
        if !streamingURL.isStreamlyLocalTorrentStreamURL {
            switch await DefaultPlaybackStreamAvailabilityChecker().check(streamingURL, timeoutSeconds: 8) {
            case .available:
                break
            case .unavailable(let reason):
                throw PlaybackServiceError.unsupported(operation: "stream availability check failed: \(reason)")
            }
        }
        state = .ready(
            PlaybackMediaSource(
                id: effectiveSelectionContext?.episodeID ?? mediaID,
                title: effectiveSelectionContext?.displayTitle ?? release.title,
                url: streamingURL,
                release: release,
                qualityLabel: release.qualityLabel,
                sourceName: release.sourceName,
                selectionContext: effectiveSelectionContext
            ),
            session
        )
    }

    private func chooseMediaFile(session: TorrentSession, release: TorrentRelease, fileID: String) async {
        do {
            try await environment.torrentEngine.selectMediaFile(sessionId: session.id, fileId: fileID)
            try await finishTorrentPlayback(session: session, release: release)
        } catch {
            let cineFlowError = CineFlowError.from(error, fallbackCategory: .torrent)
            state = .torrentFailed(cineFlowError.userMessage, fallbackSuggestion(for: release, reason: .unsupportedFile))
            await logFallbackFailure(release: release, reason: .unsupportedFile, error: error)
        }
    }

    private func mediaFileSelectionView(session: TorrentSession, release: TorrentRelease, options: [TorrentMediaFileOption]) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.lg) {
            EmptyState(
                title: t(.playerFileSelectionTitle),
                message: t(.playerFileSelectionMessage),
                systemImage: "film.stack",
                actionTitle: options.first.map { fileOptionTitle($0) } ?? t(.playerMissingSourceAction),
                actionSystemImage: "play.fill"
            ) {
                if let option = options.first {
                    Task { await chooseMediaFile(session: session, release: release, fileID: option.file.id) }
                } else {
                    onExit()
                }
            }

            VStack(spacing: CFSpacing.sm) {
                ForEach(options) { option in
                    Button {
                        Task { await chooseMediaFile(session: session, release: release, fileID: option.file.id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.file.name)
                                    .font(CFTypography.body.weight(.semibold))
                                    .foregroundStyle(CFColors.textPrimary)
                                Text(fileOptionTitle(option))
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .foregroundStyle(CFColors.accentPrimary)
                        }
                        .padding(CFSpacing.md)
                        .background(CFColors.panelFill, in: RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(CFSpacing.xl)
    }

    private func fileOptionTitle(_ option: TorrentMediaFileOption) -> String {
        "\(option.file.lengthBytes / 1_000_000_000) GB · \(option.file.path)"
    }

    private func fallbackSuggestion(for release: TorrentRelease, reason: ReleaseFallbackReason) -> ReleaseFallbackSuggestion? {
        ReleaseFallbackPlanner.suggestion(
            for: release,
            in: effectiveFallbackReleases,
            reason: reason,
            preferences: rankingPreferences
        )
    }

    private func logFallbackFailure(release: TorrentRelease, reason: ReleaseFallbackReason, error: Error? = nil) async {
        await environment.diagnosticsService.log(
            level: .warning,
            subsystem: .playback,
            message: error.map { CineFlowError.from($0, fallbackCategory: .torrent).technicalDescription } ?? reason.userFacingSummary,
            metadata: [
                "operation": "player.fallback.suggest",
                "mediaID": mediaID,
                "releaseID": release.id,
                "sourceID": release.sourceId,
                "reason": reason.rawValue
            ]
        )
    }

    private enum RouteState: Equatable {
        case loading
        case missingSource
        case unsupportedSource(String)
        case torrentFailed(String, ReleaseFallbackSuggestion?)
        case chooseMediaFile(TorrentSession, TorrentRelease, [TorrentMediaFileOption])
        case ready(PlaybackMediaSource, TorrentSession?)
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: language)
    }
}

@MainActor
private final class PlaybackSessionCoordinator: ObservableObject {
    private(set) var currentToken = 0
    private var activeTorrentSessionID: String?

    func beginNewSession(
        torrentEngine: any TorrentEngineProtocol,
        playbackService: any PlaybackServiceProtocol,
        diagnosticsService: any DiagnosticsServiceProtocol,
        mediaID: String,
        reason: String
    ) async -> Int {
        currentToken += 1
        let token = currentToken
        await cleanup(
            torrentEngine: torrentEngine,
            playbackService: playbackService,
            diagnosticsService: diagnosticsService,
            mediaID: mediaID,
            reason: reason
        )
        return token
    }

    func isCurrent(_ token: Int) -> Bool {
        token == currentToken
    }

    func activate(_ session: TorrentSession) {
        activeTorrentSessionID = session.id
    }

    func cleanup(
        torrentEngine: any TorrentEngineProtocol,
        playbackService: any PlaybackServiceProtocol,
        diagnosticsService: any DiagnosticsServiceProtocol,
        mediaID: String,
        reason: String
    ) async {
        let sessionID = activeTorrentSessionID
        activeTorrentSessionID = nil
        try? await playbackService.stop()
        guard let sessionID else { return }
        do {
            try await torrentEngine.remove(sessionId: sessionID, deleteFiles: false)
            await diagnosticsService.log(
                level: .debug,
                subsystem: .playback,
                message: "Playback session cleaned.",
                metadata: [
                    "operation": "player.session.cleanup",
                    "mediaID": mediaID,
                    "sessionID": sessionID,
                    "reason": reason
                ]
            )
        } catch {
            await diagnosticsService.log(
                CineFlowError.from(error, fallbackCategory: .torrent),
                operation: "player.session.cleanup",
                metadata: ["mediaID": mediaID, "sessionID": sessionID, "reason": reason]
            )
        }
    }
}

private struct LanguageSettingsCard: View {
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(t(.settingsLanguageTitle))
                    .font(CFTypography.title)
                    .foregroundStyle(CFColors.textPrimary)

                Text(t(.settingsLanguageMessage))
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textSecondary)
            }

            Picker(t(.settingsLanguagePicker), selection: Binding(
                get: { languageSettingsStore.selectedLanguage },
                set: { languageSettingsStore.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(L10n.string(language.displayNameKey, language: languageSettingsStore.selectedLanguage))
                        .tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Text(t(.settingsLanguageRestartNotice))
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
        }
        .padding(CFSpacing.xl)
        .frame(maxWidth: 680, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: languageSettingsStore.selectedLanguage)
    }
}

private struct ImageCacheSettingsCard: View {
    @ObservedObject var viewModel: CineFlowRootViewModel
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text(t(.cacheHeaderTitle))
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text(t(.cacheHeaderSubtitle))
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }

                Spacer()

                Text(viewModel.imageCacheSizeLabel)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .monospacedDigit()
            }

            if viewModel.imageCacheErrorDescription != nil {
                ErrorState(
                    title: t(.cacheErrorTitle),
                    message: t(.cacheErrorMessage),
                    recoverySuggestion: t(.cacheErrorRecovery)
                )
            }

            HStack(spacing: CFSpacing.sm) {
                SecondaryButton(t(.cacheClearUnused), systemImage: "clock.badge.xmark") {
                    Task { await viewModel.clearUnusedImageCache() }
                }
                .disabled(viewModel.isClearingImageCache)

                SecondaryButton(t(.cacheClearAll), systemImage: "trash") {
                    Task { await viewModel.clearImageCache() }
                }
                .disabled(viewModel.isClearingImageCache)
            }
        }
        .padding(CFSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .task {
            await viewModel.refreshImageCacheSize()
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: languageSettingsStore.selectedLanguage)
    }
}

private struct SubtitleSettingsCard: View {
    @ObservedObject var viewModel: CineFlowRootViewModel
    @State private var settings = SubtitleSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text("Subtitles")
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text("Language priority, auto-load, online search, font size and timing.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }

                Spacer()

                Text(settings.languagePreference.languageCodes.joined(separator: " -> "))
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }

            HStack(spacing: CFSpacing.md) {
                Toggle("Auto-load", isOn: binding(\.autoLoadSubtitles))
                Toggle("Auto-search", isOn: binding(\.autoSearchSubtitles))
            }

            Picker("Mode", selection: Binding(
                get: { settings.autoMode },
                set: {
                    settings.autoMode = $0
                    persist()
                }
            )) {
                ForEach(SubtitleAutoMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: CFSpacing.md) {
                Picker("Priority", selection: Binding(
                    get: { settings.languagePreference.languageCodes.joined(separator: ",") },
                    set: { value in
                        settings.languagePreference = SubtitleLanguagePreference(value.split(separator: ",").map(String.init))
                        persist()
                    }
                )) {
                    Text("RU -> EN").tag("ru,en")
                    Text("EN -> RU").tag("en,ru")
                }
                .frame(width: 180)

                Stepper("Size \(Int(settings.fontSize))", value: Binding(
                    get: { settings.fontSize },
                    set: {
                        settings.fontSize = $0
                        persist()
                    }
                ), in: 24...64, step: 2)

                Stepper("Delay \(settings.subtitleDelaySeconds, specifier: "%.1f")s", value: Binding(
                    get: { settings.subtitleDelaySeconds },
                    set: {
                        settings.subtitleDelaySeconds = $0
                        persist()
                    }
                ), in: -5...5, step: 0.5)
            }
        }
        .padding(CFSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .task {
            settings = viewModel.subtitleSettings
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SubtitleSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                persist()
            }
        )
    }

    private func persist() {
        let updated = settings
        Task { await viewModel.updateSubtitleSettings(updated) }
    }
}

private struct DeepLinkPlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(CFColors.accentPrimary)

            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(title)
                    .font(CFTypography.largeTitle)
                    .foregroundStyle(CFColors.textPrimary)

                Text(subtitle)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textSecondary)
            }

            SecondaryButton(actionTitle, systemImage: "chevron.left", action: action)
        }
        .padding(CFSpacing.xl)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background(CFHeroSurface())
    }
}

private struct ShellMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(CFTypography.overline)
                .foregroundStyle(CFColors.textMuted)

            Text(value)
                .font(CFTypography.callout)
                .lineLimit(2)
                .foregroundStyle(CFColors.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 172, minHeight: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }
}

private extension URL {
    var isStreamlyLocalTorrentStreamURL: Bool {
        guard let scheme = scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              host == "127.0.0.1" || host == "localhost"
        else {
            return false
        }
        return path.hasPrefix("/stream/")
    }
}
