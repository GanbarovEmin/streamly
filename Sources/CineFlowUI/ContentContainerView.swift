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

    public init(
        route: AppRoute,
        environment: AppEnvironment,
        viewModel: CineFlowRootViewModel,
        searchViewModel: SearchViewModel,
        navigationCoordinator: NavigationCoordinator,
        sourceManager: SourceManager? = nil,
        playbackProgressRecorder: PlaybackProgressRecorder? = nil
    ) {
        self.route = route
        self.viewModel = viewModel
        self.searchViewModel = searchViewModel
        self.navigationCoordinator = navigationCoordinator
        self.environment = environment
        self.sourceManager = sourceManager
        self.playbackProgressRecorder = playbackProgressRecorder
        _homeViewModel = StateObject(wrappedValue: HomeViewModel(progressRepository: environment.playbackProgressRepository))
        _libraryViewModel = StateObject(wrappedValue: LibraryViewModel(repository: environment.libraryRepository))
    }

    public var body: some View {
        if route == .home {
            HomeView(viewModel: homeViewModel, navigationCoordinator: navigationCoordinator)
        } else if route == .search {
            SearchView(viewModel: searchViewModel, navigationCoordinator: navigationCoordinator)
        } else if route == .library {
            LibraryView(viewModel: libraryViewModel, navigationCoordinator: navigationCoordinator, initialSection: .favorites)
        } else if route == .lists {
            UserListsView(
                viewModel: UserListsViewModel(repository: environment.libraryRepository),
                navigationCoordinator: navigationCoordinator
            )
        } else if route == .history {
            if let historyRepository = environment.watchHistoryRepository {
                WatchHistoryView(
                    viewModel: WatchHistoryViewModel(repository: historyRepository),
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                LibraryView(viewModel: libraryViewModel, navigationCoordinator: navigationCoordinator, initialSection: .watched)
            }
        } else if route == .continueWatching {
            if let progressRepository = environment.playbackProgressRepository {
                ContinueWatchingView(
                    viewModel: ContinueWatchingViewModel(repository: progressRepository),
                    navigationCoordinator: navigationCoordinator
                )
            } else {
                LibraryView(viewModel: libraryViewModel, navigationCoordinator: navigationCoordinator, initialSection: .watched)
            }
        } else if route == .settings {
            SettingsView(
                viewModel: SettingsViewModel(
                    environment: environment,
                    sourceManager: sourceManager
                )
            )
        } else if case .mediaDetail(let id) = route {
            if id.contains(":tv:") {
                SeriesDetailView(seriesID: id, navigationCoordinator: navigationCoordinator, libraryRepository: environment.libraryRepository)
            } else {
                MovieDetailView(mediaID: id, navigationCoordinator: navigationCoordinator, libraryRepository: environment.libraryRepository)
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
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .animation(CFMotion.standard, value: route)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    navigationCoordinator.navigate(to: .mediaDetail(id: "tmdb:movie:603"))
                }

                SecondaryButton(t(.heroOpenPlayer), systemImage: "play.fill") {
                    navigationCoordinator.navigate(to: .player(mediaID: "tmdb:movie:603"))
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 318, alignment: .bottomLeading)
        .background(CFHeroSurface())
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
                subtitle: id,
                systemImage: "info.circle.fill",
                actionTitle: t(.deepLinkOpenPlayer)
            ) {
                navigationCoordinator.navigate(to: .player(mediaID: id))
            }
        case .player(let mediaID):
            PlayerView(
                viewModel: PlayerViewModel(
                    service: viewModel.playbackService,
                    mediaSource: PlaybackMediaSource(
                        id: mediaID,
                        title: mediaID,
                        url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cineflow-mock-player.mkv"),
                        qualityLabel: "Mock 2160p",
                        sourceName: "Mock Source"
                    ),
                    diagnosticsService: environment.diagnosticsService,
                    progressRecorder: playbackProgressRecorder,
                    progressRepository: environment.playbackProgressRepository
                )
            ) {
                navigationCoordinator.goBack()
            }
        case .settingsSection(let id):
            DeepLinkPlaceholderView(
                title: t(.navigationSettingsSection),
                subtitle: id,
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
                .fill(CFColors.elevatedFill)
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

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text("Image Cache")
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text("Posters, backdrops and thumbnails stored locally for smoother browsing.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }

                Spacer()

                Text(viewModel.imageCacheSizeLabel)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .monospacedDigit()
            }

            if let error = viewModel.imageCacheErrorDescription {
                InlineErrorState(
                    CineFlowError(
                        category: .cache,
                        technicalDescription: error,
                        userMessage: error,
                        recoverySuggestion: CineFlowError.defaultRecoverySuggestion(for: .cache),
                        logLevel: .error
                    )
                )
            }

            HStack(spacing: CFSpacing.sm) {
                SecondaryButton("Clear unused", systemImage: "clock.badge.xmark") {
                    Task { await viewModel.clearUnusedImageCache() }
                }
                .disabled(viewModel.isClearingImageCache)

                SecondaryButton("Clear cache", systemImage: "trash") {
                    Task { await viewModel.clearImageCache() }
                }
                .disabled(viewModel.isClearingImageCache)
            }
        }
        .padding(CFSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.elevatedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .task {
            await viewModel.refreshImageCacheSize()
        }
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
                .fill(CFColors.elevatedFill)
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
                .fill(CFColors.elevatedFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }
}
