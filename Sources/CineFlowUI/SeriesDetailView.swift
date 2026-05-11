import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct SeriesDetailView: View {
    @StateObject private var viewModel: SeriesDetailViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    @State private var episodeSearchQuery = ""
    @State private var showingEpisodeReleases = false

    public init(
        seriesID: String,
        navigationCoordinator: NavigationCoordinator,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        detailProvider: (any SeriesDetailProviderProtocol)? = nil,
        userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(
            seriesID: seriesID,
            provider: detailProvider ?? MockSeriesDetailProvider(),
            libraryRepository: libraryRepository,
            userMediaSourceRepository: userMediaSourceRepository,
            settingsRepository: settingsRepository,
            diagnosticsService: diagnosticsService
        ))
        self.navigationCoordinator = navigationCoordinator
    }

    public var body: some View {
        content
        .background(CFColors.clear)
        .task {
            if viewModel.state == .loading {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            MovieDetailLoadingView()
        case .empty:
            EmptyState(
                title: t(.seriesStateEmptyTitle),
                message: t(.seriesStateEmptyMessage),
                systemImage: "tv",
                actionTitle: t(.seriesStateEmptyAction),
                actionSystemImage: "magnifyingglass"
            ) {
                navigationCoordinator.focusSearchField()
            }
                .frame(maxWidth: .infinity, minHeight: 520)
        case .failed:
            ErrorState(
                title: t(.seriesStateErrorTitle),
                message: t(.seriesStateErrorMessage),
                recoverySuggestion: t(.seriesStateErrorRecovery),
                actionTitle: t(.seriesStateEmptyAction)
            ) {
                navigationCoordinator.focusSearchField()
            }
        case .loaded:
            if let series = viewModel.series {
                cinematicSeries(series)
            }
        }
    }

    private func cinematicSeries(_ series: SeriesDetail) -> some View {
        GeometryReader { proxy in
            let railWidth = max(380, min(460, proxy.size.width * 0.29))
            ZStack(alignment: .bottomLeading) {
                MovieBackdrop(accentIndex: series.backdropAccentIndex, title: series.title, backdropURL: series.backdropURL)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        CFColors.backgroundPrimary.opacity(0.86),
                        CFColors.backgroundPrimary.opacity(0.48),
                        CFColors.backgroundPrimary.opacity(0.18)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [CFColors.clear, CFColors.backgroundPrimary.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                HStack(alignment: .top, spacing: CFSpacing.lg) {
                    seriesMetadataPanel(series, compact: proxy.size.width < 1180)
                        .padding(.leading, CFSpacing.xxl)
                        .padding(.top, CFSpacing.xxl + CFSpacing.md)
                        .padding(.bottom, 116)

                    Spacer(minLength: CFSpacing.lg)

                    seriesRightRail
                        .frame(width: railWidth)
                        .padding(.trailing, CFSpacing.xl)
                        .padding(.top, CFSpacing.xxl + CFSpacing.xs)
                        .padding(.bottom, CFSpacing.xl)
                }

                seriesActionDock(series)
                    .frame(maxWidth: max(420, proxy.size.width - railWidth - 132), alignment: .leading)
                    .padding(.leading, CFSpacing.xxl)
                    .padding(.bottom, CFSpacing.xl)
            }
        }
        .frame(minHeight: 720)
    }

    private func seriesMetadataPanel(_ series: SeriesDetail, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(series.title)
                    .font(compact ? .system(size: 48, weight: .bold, design: .rounded) : CFTypography.heroTitle)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 26) {
                    if let episode = viewModel.selectedEpisode {
                        Text(episode.runtime)
                    }
                    Text(series.yearRange)
                    Text(series.rating)
                    IMDbBadge()
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(CFColors.textPrimary)
            }

            seriesMetadataSection(title: "ЖАНРЫ", values: series.genres)
            seriesMetadataSection(title: "АКТЁРЫ", values: viewModel.cast.prefix(3).map(\.name))

            VStack(alignment: .leading, spacing: 9) {
                Text("ОПИСАНИЕ")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                Text(viewModel.selectedEpisode?.overview.isEmpty == false ? viewModel.selectedEpisode?.overview ?? series.overview : series.overview)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textPrimary.opacity(0.92))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: compact ? 620 : 760, alignment: .leading)
            }
        }
        .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
    }

    private func seriesMetadataSection<T: Sequence>(title: String, values: T) -> some View where T.Element == String {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
            HStack(spacing: 10) {
                ForEach(Array(values), id: \.self) { value in
                    Text(value)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Capsule().fill(CFColors.dockFill))
                }
            }
        }
    }

    @ViewBuilder
    private var seriesRightRail: some View {
        if showingEpisodeReleases, let episode = viewModel.selectedEpisode {
            SeriesEpisodeReleaseRail(
                episode: episode,
                releases: viewModel.releases,
                scopeTitle: { scopeTitle($0) },
                seedersHelp: t(.tooltipSeeders),
                rankingHelp: t(.tooltipRankingScore),
                advancedTitle: t(.releaseExplanationAdvanced),
                language: selectedLanguage,
                backTitle: t(.seriesEpisodeBack),
                emptyTitle: t(.seriesReleaseEmptyTitle),
                emptyMessage: t(.seriesReleaseEmptyMessage),
                onBack: { showingEpisodeReleases = false },
                onPlay: { release in
                    playManualSeriesRelease(release, episode: episode)
                }
            )
        } else {
            episodeBrowserRail
        }
    }

    private var episodeBrowserRail: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: Binding(
                get: { viewModel.episodeNotificationsEnabled },
                set: { value in Task { await viewModel.setEpisodeNotificationsEnabled(value) } }
            )) {
                Text("Получать уведомления о новых эпизодах")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textPrimary)
            }
            .toggleStyle(.switch)

            HStack {
                Button {
                    selectAdjacentEpisode(offset: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Пред.")

                Spacer()

                Menu(viewModel.selectedSeason.map { "Сезон \($0.seasonNumber)" } ?? "Сезон") {
                    ForEach(viewModel.seasons) { season in
                        Button("Сезон \(season.seasonNumber)") {
                            Task { await viewModel.selectSeasonAndLoadReleases(id: season.id) }
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                Spacer()

                Button {
                    selectAdjacentEpisode(offset: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .help("След.")
            }
            .font(CFTypography.bodyEmphasis)
            .foregroundStyle(CFColors.textSecondary)

            HStack(spacing: 10) {
                TextField("ПОИСК ВИДЕО", text: $episodeSearchQuery)
                    .textFieldStyle(.plain)
                    .font(CFTypography.caption)
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CFColors.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(
                Capsule()
                    .fill(CFColors.dockFill)
                    .overlay(Capsule().stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width))
            )

            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(filteredEpisodes) { episode in
                        SeriesEpisodeRailRow(
                            episode: episode,
                            progress: viewModel.progressValue(for: episode.id),
                            isSelected: viewModel.selectedEpisode?.id == episode.id,
                            dateText: episodeDateText(episode),
                            upcomingBadge: t(.seriesEpisodeUpcomingBadge),
                            upcomingHelp: t(.seriesEpisodeUpcomingHelp),
                            openHelp: t(.seriesEpisodeOpenSourcesHelp),
                            onSelect: {
                                Task {
                                    await viewModel.selectEpisodeAndLoadReleases(id: episode.id)
                                    showingEpisodeReleases = episode.isReleased
                                }
                            }
                        )
                    }
                }
            }
            .scrollIndicators(.visible)
        }
        .padding(CFSpacing.lg)
        .cfPanelBackground(fill: CFColors.railFill, shadow: .panel)
    }

    private var filteredEpisodes: [SeriesEpisode] {
        let query = episodeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.visibleEpisodes }
        return viewModel.visibleEpisodes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || "\($0.episodeNumber)".contains(query)
        }
    }

    private func selectAdjacentEpisode(offset: Int) {
        guard
            let current = viewModel.selectedEpisode,
            let currentIndex = viewModel.visibleEpisodes.firstIndex(where: { $0.id == current.id })
        else { return }
        let nextIndex = min(max(currentIndex + offset, 0), viewModel.visibleEpisodes.count - 1)
        let next = viewModel.visibleEpisodes[nextIndex]
        Task {
            await viewModel.selectEpisodeAndLoadReleases(id: next.id)
            showingEpisodeReleases = next.isReleased
        }
    }

    private func episodeDateText(_ episode: SeriesEpisode) -> String {
        guard let airDate = episode.airDate else { return "" }
        return airDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func seriesActionDock(_ series: SeriesDetail) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: CFSpacing.sm) {
                DockButton(title: "Трейлер", systemImage: "movieclapper") {
                    viewModel.selectedTab = .trailers
                }
                DockIconButton(systemImage: "folder.badge.plus", title: viewModel.isInLibrary ? "В библиотеке" : "Добавить в библиотеку") {
                    viewModel.addToLibrary()
                }
                DockIconButton(systemImage: "eye", title: "Отметить серию просмотренной") {
                    if let episode = viewModel.selectedEpisode {
                        viewModel.playEpisode(id: episode.id)
                    }
                }
                DockIconButton(systemImage: "hand.thumbsup", title: "Продолжить") {
                    viewModel.continueWatching()
                    if let episode = viewModel.selectedEpisode, episode.isReleased {
                        playBestSeries(series, episode: episode)
                    } else {
                        playSeries(series)
                    }
                }
                DockIconButton(systemImage: "heart", title: "В список") {
                    viewModel.addToList("Хочу посмотреть")
                }
                DockIconButton(systemImage: "play.fill", title: t(.seriesActionWatchBest)) {
                    if let episode = viewModel.selectedEpisode, episode.isReleased {
                        playBestSeries(series, episode: episode)
                    }
                }
                DockIconButton(systemImage: "list.bullet.rectangle", title: t(.seriesActionChooseRelease)) {
                    if viewModel.selectedEpisode?.isReleased == true {
                        showingEpisodeReleases = true
                        viewModel.selectedTab = .releases
                    }
                }
                DockIconButton(systemImage: "square.and.arrow.up", title: "Поделиться") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(series.title, forType: .string)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func hero(_ series: SeriesDetail) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                MovieBackdrop(accentIndex: series.backdropAccentIndex, title: series.title, backdropURL: series.backdropURL)

                LinearGradient(
                    colors: [CFColors.clear, CFColors.backgroundPrimary.opacity(0.48), CFColors.backgroundPrimary.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 28) {
                    poster(series)
                    heroCopy(series, compact: proxy.size.width < 920)
                    Spacer(minLength: 0)
                }
                .padding(CFSpacing.xl)
            }
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
                    .stroke(CFColors.separator, lineWidth: CFSeparators.width)
            )
            .cfShadow(.elevated)
        }
        .frame(minHeight: 430, idealHeight: 500, maxHeight: 540)
    }

    private func poster(_ series: SeriesDetail) -> some View {
        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [CFColors.backgroundTertiary, CFColors.surfaceOverlay.opacity(0.84)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let posterURL = series.posterURL {
                    CFCachedAsyncImage(url: posterURL, contentMode: .fill)
                } else {
                    Text(String(series.title.prefix(1)))
                        .font(.system(size: 86, weight: .black, design: .rounded))
                        .foregroundStyle(CFColors.textPrimary.opacity(0.22))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .stroke(CFColors.separator, lineWidth: CFSeparators.width)
            )
            .frame(width: 190, height: 286)
    }

    private func heroCopy(_ series: SeriesDetail, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(series.title)
                .font(compact ? .system(size: 40, weight: .bold, design: .rounded) : CFTypography.heroTitle)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            HStack(spacing: CFSpacing.sm) {
                CFBadge(series.yearRange, tone: .source)
                CFBadge("\(series.seasonsCount) seasons", tone: .source)
                RatingBadge(series.rating)
                ForEach(series.genres, id: \.self) { genre in
                    CFBadge(genre, tone: .source)
                }
            }

            Text(series.overview)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(compact ? 3 : 4)
                .frame(maxWidth: 760, alignment: .leading)

            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                ProgressBar(value: viewModel.overallProgress)
                    .frame(maxWidth: 420)

                if let episode = viewModel.lastWatchedEpisode {
                    Text("\(t(.seriesLastWatched)): S\(episode.seasonNumber) E\(episode.episodeNumber) · \(episode.title)")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
            }

            HStack(spacing: CFSpacing.md) {
                PrimaryButton(t(.seriesActionWatch), systemImage: "play.fill") {
                    if let episode = viewModel.selectedEpisode {
                        viewModel.playEpisode(id: episode.id)
                        playSeries(series)
                    }
                }
                SecondaryButton(t(.seriesActionContinue), systemImage: "play.rectangle.fill") {
                    viewModel.continueWatching()
                    playSeries(series)
                }
                SecondaryButton(t(.seriesActionLibrary), systemImage: "plus") {
                    viewModel.addToLibrary()
                }
                SecondaryButton(t(.seriesActionAddList), systemImage: "list.bullet") {
                    viewModel.addToList("Хочу посмотреть")
                }
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
    }

    private var tabs: some View {
        HStack(spacing: CFSpacing.sm) {
            ForEach(viewModel.tabs) { tab in
                DetailTabButton(title: tabTitle(tab), isSelected: viewModel.selectedTab == tab) {
                    viewModel.selectedTab = tab
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .seasons:
            seasonsTab
        case .releases:
            releasesTab
        case .trailers:
            simpleList(title: t(.seriesTabTrailers), items: viewModel.trailers.map { "\($0.title) · \($0.source)" })
        case .similar:
            MediaCarousel(
                title: t(.seriesTabSimilar),
                items: viewModel.similar.map {
                    CFMediaCardModel(id: $0.id, title: $0.title, metadata: $0.metadata, badge: $0.quality, artworkURL: $0.artworkURL)
                }
            ) { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            }
        case .cast:
            simpleList(title: t(.seriesTabCast), items: viewModel.cast.map { "\($0.name) · \($0.role)" })
        case .details:
            if let series = viewModel.series {
                simpleList(title: t(.seriesTabDetails), items: [
                    "\(series.yearRange) · \(series.seasonsCount) seasons",
                    series.genres.joined(separator: ", "),
                    "\(t(.seriesProgress)): \(Int(viewModel.overallProgress * 100))%"
                ])
            }
        }
    }

    private var seasonsTab: some View {
        VStack(alignment: .leading, spacing: CFSpacing.lg) {
            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.sm) {
                    ForEach(viewModel.seasons) { season in
                        DetailTabButton(
                            title: L10n.format(.seriesSeasonFormat, language: selectedLanguage, season.seasonNumber),
                            isSelected: viewModel.selectedSeason?.id == season.id
                        ) {
                            Task {
                                await viewModel.selectSeasonAndLoadReleases(id: season.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 430), spacing: CFSpacing.md)], spacing: CFSpacing.md) {
                ForEach(viewModel.visibleEpisodes) { episode in
                    EpisodeCard(
                        episode: episode,
                        progress: viewModel.progressValue(for: episode.id),
                        isSelected: viewModel.selectedEpisode?.id == episode.id,
                        episodeLabel: L10n.format(.seriesEpisodeFormat, language: selectedLanguage, episode.episodeNumber)
                    ) {
                        Task {
                            await viewModel.selectEpisodeAndLoadReleases(id: episode.id)
                        }
                    } play: {
                        Task { @MainActor in
                            await viewModel.selectEpisodeAndLoadReleases(id: episode.id)
                            if let series = viewModel.series {
                                playBestSeries(series, episode: episode)
                            }
                        }
                    }
                }
            }
        }
    }

    private var releasesTab: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(t(.seriesTabReleases))
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            LazyVStack(spacing: CFSpacing.md) {
                ForEach(viewModel.releases, id: \.release.id) { scoped in
                    SeriesReleaseRow(
                        scoped: scoped,
                        scopeTitle: scopeTitle(scoped.scope),
                        seedersHelp: t(.tooltipSeeders),
                        rankingHelp: t(.tooltipRankingScore),
                        advancedTitle: t(.releaseExplanationAdvanced),
                        language: selectedLanguage,
                        onPlay: {
                            if let episode = viewModel.selectedEpisode {
                                playManualSeriesRelease(scoped.release, episode: episode)
                            }
                        }
                    )
                }
            }
        }
    }

    private func playSeries(_ series: SeriesDetail) {
        playSeriesID(series.id)
    }

    private func playBestSeries(_ series: SeriesDetail, episode: SeriesEpisode) {
        if let release = viewModel.playBestRelease() {
            navigationCoordinator.navigate(to: .player(
                mediaID: series.id,
                release: release,
                fallbackReleases: viewModel.releases.map(\.release),
                selectionContext: playbackContext(for: series, episode: episode),
                nextEpisodePrompt: nextEpisodePrompt(after: episode)
            ))
            return
        }

        viewModel.playEpisode(id: episode.id)
        playSeries(series)
    }

    private func playManualSeriesRelease(_ release: TorrentRelease, episode: SeriesEpisode) {
        viewModel.playManualRelease(release)
        navigationCoordinator.navigate(to: .player(
            mediaID: viewModel.series?.id ?? episode.id,
            release: release,
            fallbackReleases: viewModel.releases.map(\.release),
            selectionContext: viewModel.series.map { playbackContext(for: $0, episode: episode) },
            nextEpisodePrompt: nextEpisodePrompt(after: episode)
        ))
    }

    private func playSeriesID(_ mediaID: String) {
        if let source = viewModel.userSources.first(where: \.isPlayableLocalFile) {
            viewModel.selectUserSource(source)
            navigationCoordinator.navigate(to: .player(
                mediaID: mediaID,
                sourceID: source.id,
                selectionContext: selectedSeriesPlaybackContext(mediaID: mediaID)
            ))
            return
        }
        openLocalMediaPanel(mediaID: mediaID)
    }

    private func playbackContext(for series: SeriesDetail, episode: SeriesEpisode) -> PlaybackSelectionContext {
        PlaybackSelectionContext(
            mediaID: series.id,
            displayTitle: series.title,
            mediaKind: .series,
            seasonNumber: episode.seasonNumber,
            episodeNumber: episode.episodeNumber,
            episodeID: episode.id
        )
    }

    private func selectedSeriesPlaybackContext(mediaID: String) -> PlaybackSelectionContext? {
        guard let series = viewModel.series else { return nil }
        guard let episode = viewModel.selectedEpisode else {
            return PlaybackSelectionContext(mediaID: mediaID, displayTitle: series.title, mediaKind: .series)
        }
        return playbackContext(for: series, episode: episode)
    }

    private func nextEpisodePrompt(after episode: SeriesEpisode) -> PlayerNextEpisodePrompt? {
        guard let next = viewModel.nextReleasedEpisode(after: episode) else { return nil }
        return PlayerNextEpisodePrompt(
            title: "S\(next.seasonNumber)E\(next.episodeNumber) \(next.title)",
            subtitle: next.runtime
        )
    }

    private func openLocalMediaPanel(mediaID: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a local video file for Streamly playback."

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await viewModel.addLocalSource(url: url)
                navigationCoordinator.navigate(to: .player(
                    mediaID: mediaID,
                    sourceID: viewModel.selectedUserSourceID,
                    selectionContext: selectedSeriesPlaybackContext(mediaID: mediaID)
                ))
            }
        }
    }

    private func simpleList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(title)
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textSecondary)
                    .padding(CFSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .fill(CFColors.panelFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                                    .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                            )
                    )
            }
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func tabTitle(_ tab: SeriesDetailTab) -> String {
        switch tab {
        case .seasons:
            t(.seriesTabSeasons)
        case .releases:
            t(.seriesTabReleases)
        case .trailers:
            t(.seriesTabTrailers)
        case .similar:
            t(.seriesTabSimilar)
        case .cast:
            t(.seriesTabCast)
        case .details:
            t(.seriesTabDetails)
        }
    }

    private func scopeTitle(_ scope: SeriesReleaseScope) -> String {
        switch scope {
        case .series:
            t(.seriesReleaseScopeSeries)
        case .season:
            t(.seriesReleaseScopeSeason)
        case .episode:
            t(.seriesReleaseScopeEpisode)
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct EpisodeCard: View {
    let episode: SeriesEpisode
    let progress: Double
    let isSelected: Bool
    let episodeLabel: String
    let onSelect: () -> Void
    let play: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: CFSpacing.md) {
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CFColors.surfaceOverlay, CFColors.accentSecondary.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Image(systemName: "play.rectangle.fill").foregroundStyle(CFColors.textPrimary))
                    .frame(height: 140)

                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text(episodeLabel)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                    Text(episode.title)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                        .lineLimit(1)
                    Text(episode.runtime)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                    Text(episode.overview)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                        .lineLimit(3)
                }

                ProgressBar(value: progress)

                SecondaryButton("Play", systemImage: "play.fill", action: play)
            }
            .padding(CFSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(isSelected ? CFColors.activeFill.opacity(0.84) : CFColors.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .stroke(isSelected ? CFColors.focusRing.opacity(0.52) : CFColors.separator, lineWidth: CFSeparators.width)
                    )
            )
            .overlay(alignment: .bottomLeading) {
                if isSelected {
                    Capsule()
                        .fill(CFColors.horizontalGradient)
                        .frame(width: 84, height: 2)
                        .padding(.leading, CFSpacing.md)
                        .padding(.bottom, CFSpacing.sm)
                }
            }
        }
        .buttonStyle(.plain)
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }
}

private struct SeriesReleaseRow: View {
    let scoped: ScopedSeriesRelease
    let scopeTitle: String
    let seedersHelp: String
    let rankingHelp: String
    let advancedTitle: String
    let language: AppLanguage
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: CFSpacing.lg) {
            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                HStack(spacing: CFSpacing.sm) {
                    Text(scoped.release.title)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                        .lineLimit(1)
                    CFBadge(scopeTitle, tone: .source)
                }

                HStack(spacing: CFSpacing.sm) {
                    ReleaseExplanationBadges(ranked: scoped.ranked, language: language)
                    QualityBadge(scoped.release.qualityLabel)
                    if scoped.release.hdr != .none, scoped.release.hdr != .unknown {
                        CFBadge(scoped.release.hdr.rawValue, tone: .quality)
                    }
                    CFBadge(scoped.release.codec.rawValue, tone: .source)
                    SeedersBadge(scoped.release.seeders)
                        .help(seedersHelp)
                    SourceBadge(scoped.release.sourceName)
                    CFBadge(scoped.release.humanReadableSize, tone: .source)
                }

                ReleaseExplanationSummary(ranked: scoped.ranked, language: language)
                ReleaseAdvancedDetails(ranked: scoped.ranked, title: advancedTitle, language: language)
            }

            Spacer()

            IconButton(systemImage: "play.fill", accessibilityLabel: "Play", action: onPlay)
        }
        .padding(CFSpacing.lg)
        .background(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(isHovering ? CFColors.hoverFill : CFColors.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .stroke(isHovering ? CFColors.focusRing.opacity(0.40) : CFColors.separator, lineWidth: CFSeparators.width)
                    )
        )
        .overlay(alignment: .bottomLeading) {
            if isHovering {
                Capsule()
                    .fill(CFColors.horizontalGradient)
                    .frame(width: 96, height: 2)
                    .padding(.leading, CFSpacing.lg)
                    .padding(.bottom, CFSpacing.sm)
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .help(localizedReleaseTooltip(for: scoped.ranked, language: language, rankingHelp: rankingHelp))
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }

    private var accessibilityLabel: String {
        "\(scoped.release.title), \(scopeTitle), \(scoped.release.qualityLabel), \(scoped.release.humanReadableSize), \(scoped.release.seeders) seeders"
    }
}

private struct SeriesEpisodeRailRow: View {
    let episode: SeriesEpisode
    let progress: Double
    let isSelected: Bool
    let dateText: String
    let upcomingBadge: String
    let upcomingHelp: String
    let openHelp: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous)
                        .fill(CFColors.surfaceOverlay.opacity(0.64))
                    if let thumbnailURL = episode.thumbnailURL {
                        CFCachedAsyncImage(url: thumbnailURL, contentMode: .fill)
                    } else {
                        Image(systemName: episode.isUpcoming ? "play.slash.fill" : "play.rectangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CFColors.textMuted)
                    }
                }
                .frame(width: 106, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(episode.episodeNumber). \(episode.title)")
                            .font(CFTypography.body)
                            .foregroundStyle(CFColors.textPrimary)
                            .lineLimit(1)

                        if episode.isUpcoming {
                            Text(upcomingBadge)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(CFColors.success))
                        }
                    }

                    Text(dateText.isEmpty ? episode.runtime : dateText)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)

                    if progress > 0 {
                        ProgressBar(value: progress)
                            .frame(maxWidth: 150)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous)
                    .fill(isSelected ? CFColors.activeFill.opacity(0.72) : CFColors.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(false)
        .help(episode.isUpcoming ? upcomingHelp : openHelp)
    }
}

private struct SeriesEpisodeReleaseRail: View {
    let episode: SeriesEpisode
    let releases: [ScopedSeriesRelease]
    let scopeTitle: (SeriesReleaseScope) -> String
    let seedersHelp: String
    let rankingHelp: String
    let advancedTitle: String
    let language: AppLanguage
    let backTitle: String
    let emptyTitle: String
    let emptyMessage: String
    let onBack: () -> Void
    let onPlay: (TorrentRelease) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help(backTitle)

                Text("S\(episode.seasonNumber)E\(episode.episodeNumber) \(episode.title)")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(1)
            }

            if releases.isEmpty {
                EmptyState(
                    title: emptyTitle,
                    message: emptyMessage,
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    actionTitle: backTitle,
                    actionSystemImage: "chevron.left",
                    action: onBack
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(releases, id: \.release.id) { scoped in
                            Button {
                                onPlay(scoped.release)
                            } label: {
                                HStack(alignment: .center, spacing: 14) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(scoped.release.sourceName)
                                            .font(CFTypography.body)
                                            .foregroundStyle(CFColors.textPrimary)
                                        Text(releaseSubtitle(scoped.release))
                                            .font(CFTypography.caption)
                                            .foregroundStyle(CFColors.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(width: 106, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(scoped.release.title)
                                            .font(CFTypography.caption)
                                            .foregroundStyle(CFColors.textPrimary)
                                            .lineLimit(2)
                                        ReleaseExplanationBadges(ranked: scoped.ranked, language: language)
                                        HStack(spacing: 7) {
                                            Label("\(scoped.release.seeders)", systemImage: "person.fill")
                                                .help(seedersHelp)
                                            Label(scoped.release.humanReadableSize, systemImage: "externaldrive.fill")
                                            Text(scopeTitle(scoped.scope))
                                        }
                                        .font(CFTypography.caption)
                                        .foregroundStyle(CFColors.textMuted)
                                        ReleaseExplanationSummary(ranked: scoped.ranked, language: language)
                                    }

                                    Spacer(minLength: 0)

                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(CFColors.textPrimary)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(CFColors.success))
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                        .fill(CFColors.panelFill)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                                .stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .help(localizedReleaseTooltip(for: scoped.ranked, language: language, rankingHelp: rankingHelp))
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(CFSpacing.lg)
        .cfPanelBackground(fill: CFColors.railFill, shadow: .panel)
    }

    private func releaseSubtitle(_ release: TorrentRelease) -> String {
        var values = [release.qualityLabel]
        if release.hdr != .none, release.hdr != .unknown {
            values.append(release.hdr.rawValue)
        }
        if release.codec != .unknown {
            values.append(release.codec.rawValue)
        }
        return values.joined(separator: " | ")
    }
}
