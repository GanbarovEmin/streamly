import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct MovieDetailView: View {
    @StateObject private var viewModel: MovieDetailViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(
        mediaID: String,
        navigationCoordinator: NavigationCoordinator,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        detailProvider: (any MovieDetailProviderProtocol)? = nil,
        userMediaSourceRepository: (any UserMediaSourceRepositoryProtocol)? = nil,
        settingsRepository: (any SettingsRepositoryProtocol)? = nil,
        diagnosticsService: (any DiagnosticsServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(
            mediaID: mediaID,
            provider: detailProvider ?? MockMovieDetailProvider(),
            libraryRepository: libraryRepository,
            settingsRepository: settingsRepository,
            userMediaSourceRepository: userMediaSourceRepository,
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
                title: t(.detailEmptyTitle),
                message: t(.detailEmptyMessage),
                systemImage: "film",
                actionTitle: t(.detailEmptyAction),
                actionSystemImage: "magnifyingglass"
            ) {
                navigationCoordinator.focusSearchField()
            }
                .frame(maxWidth: .infinity, minHeight: 520)
        case .failed:
            ErrorState(
                title: t(.detailErrorTitle),
                message: t(.detailErrorMessage),
                recoverySuggestion: t(.detailErrorRecovery),
                actionTitle: t(.detailEmptyAction)
            ) {
                navigationCoordinator.focusSearchField()
            }
        case .loaded:
            if let movie = viewModel.movie {
                cinematicMovie(movie)
            }
        }
    }

    private func cinematicMovie(_ movie: MovieDetail) -> some View {
        GeometryReader { proxy in
            let railWidth = max(360, min(430, proxy.size.width * 0.28))
            ZStack(alignment: .bottomLeading) {
                MovieBackdrop(accentIndex: movie.backdropAccentIndex, title: movie.title, backdropURL: movie.backdropURL)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        CFColors.backgroundPrimary.opacity(0.86),
                        CFColors.backgroundPrimary.opacity(0.50),
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
                    movieMetadataPanel(movie, compact: proxy.size.width < 1180)
                        .padding(.leading, CFSpacing.xxl)
                        .padding(.top, CFSpacing.xxl + CFSpacing.md)
                        .padding(.bottom, 116)

                    Spacer(minLength: CFSpacing.lg)

                    SourceRail(
                        releases: viewModel.releases,
                        copyTitle: t(.detailCopyMagnet),
                        playTitle: t(.detailWatch),
                        seedersHelp: t(.tooltipSeeders),
                        rankingHelp: t(.tooltipRankingScore),
                        advancedTitle: t(.releaseExplanationAdvanced),
                        language: selectedLanguage,
                        sourcesTitle: t(.detailSourcesTitle),
                        sourcesSubtitle: sourceRailSubtitle(count: viewModel.releases.count),
                        sourcesEmptyMessage: t(.sourcesEmptyMessage),
                        onPlay: { release in
                            playManualMovieRelease(release, movieID: movie.id)
                        },
                        onCopy: { release in
                            viewModel.copyMagnet(release)
                        }
                    )
                    .frame(width: railWidth)
                    .padding(.trailing, CFSpacing.xl)
                    .padding(.top, CFSpacing.xxl + CFSpacing.xs)
                    .padding(.bottom, CFSpacing.xl)
                }

                movieActionDock(movie)
                    .frame(maxWidth: max(420, proxy.size.width - railWidth - 132), alignment: .leading)
                    .padding(.leading, CFSpacing.xxl)
                    .padding(.bottom, CFSpacing.xl)
            }
        }
        .frame(minHeight: 720)
    }

    private func movieMetadataPanel(_ movie: MovieDetail, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(movie.title)
                    .font(compact ? .system(size: 48, weight: .bold, design: .rounded) : CFTypography.heroTitle)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 26) {
                    Text(movie.runtime)
                    Text(String(movie.year))
                    Text(movie.imdbRating)
                    IMDbBadge()
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(CFColors.textPrimary)
            }

            metadataSection(title: "ЖАНРЫ", values: movie.genres)
            metadataSection(title: "АКТЁРЫ", values: viewModel.cast.prefix(3).map(\.name))

            VStack(alignment: .leading, spacing: 9) {
                Text("ОПИСАНИЕ")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                Text(movie.overview)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textPrimary.opacity(0.92))
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: compact ? 620 : 760, alignment: .leading)
            }
        }
        .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
    }

    private func metadataSection<T: Sequence>(title: String, values: T) -> some View where T.Element == String {
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

    private func movieActionDock(_ movie: MovieDetail) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: CFSpacing.sm) {
                DockButton(title: "Трейлер", systemImage: "movieclapper") {
                    viewModel.selectedTab = .trailers
                }
                DockIconButton(systemImage: "folder.badge.plus", title: viewModel.isInLibrary ? "В библиотеке" : "Добавить в библиотеку") {
                    viewModel.addToLibrary()
                }
                DockIconButton(systemImage: viewModel.isWatched ? "eye.fill" : "eye", title: "Отметить просмотренным") {
                    viewModel.markWatched()
                }
                DockIconButton(systemImage: "hand.thumbsup", title: "Оценить") {
                    viewModel.setUserRating(8)
                }
                DockIconButton(systemImage: viewModel.isFavorite ? "heart.fill" : "heart", title: "Избранное") {
                    viewModel.toggleFavorite()
                }
                DockIconButton(systemImage: "play.fill", title: t(.detailWatchBest)) {
                    playBestMovie(movie)
                }
                DockIconButton(systemImage: "square.and.arrow.up", title: "Поделиться") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(movie.title, forType: .string)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func hero(_ movie: MovieDetail) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                MovieBackdrop(accentIndex: movie.backdropAccentIndex, title: movie.title, backdropURL: movie.backdropURL)

                LinearGradient(
                    colors: [CFColors.clear, CFColors.backgroundPrimary.opacity(0.48), CFColors.backgroundPrimary.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 28) {
                    poster(movie)
                    heroCopy(movie, compact: proxy.size.width < 920)
                    Spacer(minLength: 0)
                    SourceRail(
                        releases: viewModel.releases,
                        copyTitle: t(.detailCopyMagnet),
                        playTitle: t(.detailWatch),
                        seedersHelp: t(.tooltipSeeders),
                        rankingHelp: t(.tooltipRankingScore),
                        advancedTitle: t(.releaseExplanationAdvanced),
                        language: selectedLanguage,
                        sourcesTitle: t(.detailSourcesTitle),
                        sourcesSubtitle: sourceRailSubtitle(count: viewModel.releases.count),
                        sourcesEmptyMessage: t(.sourcesEmptyMessage),
                        onPlay: { release in
                            playManualMovieRelease(release, movieID: movie.id)
                        },
                        onCopy: { release in
                            viewModel.copyMagnet(release)
                        }
                    )
                    .frame(width: proxy.size.width < 1100 ? 330 : 390)
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

    private func poster(_ movie: MovieDetail) -> some View {
        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [CFColors.backgroundTertiary, CFColors.surfaceOverlay.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let posterURL = movie.posterURL {
                    CFCachedAsyncImage(url: posterURL, contentMode: .fill)
                } else {
                    Text(String(movie.title.prefix(1)))
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

    private func heroCopy(_ movie: MovieDetail, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(movie.title)
                .font(compact ? .system(size: 40, weight: .bold, design: .rounded) : CFTypography.heroTitle)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.76)

            Text(movie.originalTitle)
                .font(CFTypography.bodyEmphasis)
                .foregroundStyle(CFColors.textSecondary)

            Label(viewModel.sourceSummary, systemImage: "dot.radiowaves.left.and.right")
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, CFSpacing.md)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(CFColors.surfaceOverlay.opacity(0.72))
                        .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
                )

            HStack(spacing: CFSpacing.sm) {
                CFBadge(String(movie.year), tone: .source)
                CFBadge(movie.runtime, tone: .source)
                ForEach(movie.genres, id: \.self) { genre in
                    CFBadge(genre, tone: .source)
                }
                RatingBadge("\(t(.detailRatingTMDB)) \(movie.tmdbRating)")
                RatingBadge("\(t(.detailRatingIMDB)) \(movie.imdbRating)")
            }

            Text(movie.overview)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(compact ? 3 : 4)
                .frame(maxWidth: 760, alignment: .leading)

                    if viewModel.hasContinueWatching {
                        VStack(alignment: .leading, spacing: CFSpacing.xs) {
                            ProgressBar(value: viewModel.progressValue)
                                .frame(maxWidth: 420)
                            SecondaryButton(t(.detailContinue), systemImage: "play.fill") {
                                viewModel.continueWatching()
                                playBestMovie(movie)
                            }
                        }
                    }

            HStack(spacing: CFSpacing.md) {
                PrimaryButton(t(.detailWatchBest), systemImage: "play.fill") {
                    playBestMovie(movie)
                }
                SecondaryButton(t(.detailChooseRelease), systemImage: "list.bullet.rectangle") {
                    viewModel.selectedTab = .releases
                }
                SecondaryButton(t(.detailLibrary), systemImage: "plus") {
                    viewModel.addToLibrary()
                }
                SecondaryButton(t(.detailAddList), systemImage: "list.bullet") {
                    viewModel.addToList("Хочу посмотреть")
                }
                SecondaryButton(t(.detailRate), systemImage: "star.fill") {
                    viewModel.setUserRating(8)
                }
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
    }

    private func playBestMovie(_ movie: MovieDetail) {
        if let release = viewModel.playBestRelease() {
            navigationCoordinator.navigate(to: .player(
                mediaID: movie.id,
                release: release,
                fallbackReleases: viewModel.releases.map(\.release),
                selectionContext: playbackContext(for: movie)
            ))
            return
        }

        playLocalMovie(movie)
    }

    private func playManualMovieRelease(_ release: TorrentRelease, movieID: String) {
        viewModel.playManualRelease(release)
        navigationCoordinator.navigate(to: .player(
            mediaID: movieID,
            release: release,
            fallbackReleases: viewModel.releases.map(\.release),
            selectionContext: viewModel.movie.map(playbackContext(for:))
        ))
    }

    private func playLocalMovie(_ movie: MovieDetail) {
        if let source = viewModel.userSources.first(where: \.isPlayableLocalFile) {
            viewModel.selectUserSource(source)
            navigationCoordinator.navigate(to: .player(
                mediaID: movie.id,
                sourceID: source.id,
                selectionContext: playbackContext(for: movie)
            ))
            return
        }
        openLocalMediaPanel(mediaID: movie.id)
    }

    private func playbackContext(for movie: MovieDetail) -> PlaybackSelectionContext {
        PlaybackSelectionContext(
            mediaID: movie.id,
            displayTitle: movie.title,
            mediaKind: .movie
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
                    selectionContext: viewModel.movie.map(playbackContext(for:))
                ))
            }
        }
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
        case .releases:
            releasesTab
        case .trailers:
            simpleList(title: t(.detailTabTrailers), items: viewModel.trailers.map { "\($0.title) · \($0.source)" })
        case .similar:
            MediaCarousel(
                title: t(.detailTabSimilar),
                items: viewModel.similar.map {
                    CFMediaCardModel(id: $0.id, title: $0.title, metadata: $0.metadata, badge: $0.quality, artworkURL: $0.artworkURL)
                }
            ) { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            }
        case .cast:
            simpleList(title: t(.detailTabCast), items: viewModel.cast.map { "\($0.name) · \($0.role)" })
        case .details:
            if let movie = viewModel.movie {
                simpleList(title: t(.detailTabDetails), items: [
                    "\(t(.detailRatingTMDB)): \(movie.tmdbRating)",
                    "\(t(.detailRatingIMDB)): \(movie.imdbRating)",
                    "\(movie.year) · \(movie.runtime)",
                    movie.genres.joined(separator: ", ")
                ])
            }
        }
    }

    private var releasesTab: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(t(.detailTabReleases))
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            LazyVStack(spacing: CFSpacing.md) {
                ForEach(viewModel.releases, id: \.release.id) { ranked in
                    MovieReleaseRow(
                        ranked: ranked,
                        languagesText: L10n.format(
                            .detailReleaseLanguagesFormat,
                            language: selectedLanguage,
                            ranked.release.audioLanguages.joined(separator: ", "),
                            ranked.release.subtitleLanguages.joined(separator: ", ")
                        ),
                        copyTitle: t(.detailCopyMagnet),
                        playTitle: t(.detailWatch),
                        seedersHelp: t(.tooltipSeeders),
                        rankingHelp: t(.tooltipRankingScore),
                        advancedTitle: t(.releaseExplanationAdvanced),
                        language: selectedLanguage,
                        onPlay: {
                            if let movieID = viewModel.movie?.id {
                                playManualMovieRelease(ranked.release, movieID: movieID)
                            }
                        },
                        onCopy: {
                            viewModel.copyMagnet(ranked.release)
                        }
                    )
                }
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

    private func tabTitle(_ tab: MovieDetailTab) -> String {
        switch tab {
        case .releases:
            t(.detailTabReleases)
        case .trailers:
            t(.detailTabTrailers)
        case .similar:
            t(.detailTabSimilar)
        case .cast:
            t(.detailTabCast)
        case .details:
            t(.detailTabDetails)
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }

    private func sourceRailSubtitle(count: Int) -> String {
        count == 0 ? t(.detailSourcesEmptySubtitle) : L10n.format(.detailSourcesCountFormat, language: selectedLanguage, count)
    }
}

struct DetailTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(isSelected ? CFColors.textPrimary : CFColors.textSecondary)
                .padding(.horizontal, CFSpacing.lg)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(isSelected ? CFColors.activeFill : CFColors.panelFill)
                        .overlay(Capsule().stroke(isSelected ? CFColors.focusRing.opacity(0.52) : CFColors.separator, lineWidth: CFSeparators.width))
                )
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(CFColors.horizontalGradient)
                            .frame(width: 44, height: 2)
                            .padding(.bottom, 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .cfFocusRing(cornerRadius: CFRadius.pill)
    }
}

struct MovieBackdrop: View {
    let accentIndex: Int
    let title: String
    let backdropURL: URL?

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    CFColors.backgroundPrimary,
                    CFColors.backgroundTertiary,
                    accentIndex.isMultiple(of: 2) ? CFColors.surfaceOverlay.opacity(0.84) : CFColors.backgroundSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [CFColors.accentSecondary.opacity(0.26), CFColors.accentTertiary.opacity(0.09), CFColors.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 620
            )

            Text(String(title.prefix(1)))
                .font(.system(size: 280, weight: .black, design: .rounded))
                .foregroundStyle(CFColors.textPrimary.opacity(0.05))
                .offset(x: -70, y: -20)
        }
        .overlay {
            if let backdropURL {
                CFCachedAsyncImage(url: backdropURL, contentMode: .fill)
                    .opacity(0.36)
                    .overlay(CFColors.backgroundPrimary.opacity(0.30))
            }
        }
    }
}

private struct SourceRail: View {
    let releases: [RankedRelease]
    let copyTitle: String
    let playTitle: String
    let seedersHelp: String
    let rankingHelp: String
    let advancedTitle: String
    let language: AppLanguage
    let sourcesTitle: String
    let sourcesSubtitle: String
    let sourcesEmptyMessage: String
    let onPlay: (TorrentRelease) -> Void
    let onCopy: (TorrentRelease) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sourcesTitle)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                    Text(sourcesSubtitle)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }

                Spacer()

                if let best = releases.first?.release {
                    CFBadge(best.qualityLabel, tone: .quality)
                }
            }

            if releases.isEmpty {
                VStack(alignment: .leading, spacing: CFSpacing.sm) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(CFColors.textMuted)
                    Text(sourcesEmptyMessage)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(releases, id: \.release.id) { ranked in
                            SourceRailRow(
                                ranked: ranked,
                                playTitle: playTitle,
                                copyTitle: copyTitle,
                                seedersHelp: seedersHelp,
                                rankingHelp: rankingHelp,
                                advancedTitle: advancedTitle,
                                language: language,
                                onPlay: { onPlay(ranked.release) },
                                onCopy: { onCopy(ranked.release) }
                            )
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .padding(CFSpacing.lg)
        .frame(maxHeight: .infinity)
        .cfPanelBackground(fill: CFColors.railFill, shadow: .panel)
    }
}

struct IMDbBadge: View {
    var body: some View {
        Text("IMDb")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: CFRadius.badge, style: .continuous).fill(Color.yellow))
    }
}

struct DockButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.cfReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: CFSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .lineLimit(1)
            }
            .font(CFTypography.callout)
            .foregroundStyle(CFColors.textPrimary)
            .padding(.horizontal, CFSpacing.lg)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(isHovering ? CFColors.dockHoverFill : CFColors.dockFill)
                    .overlay(Capsule().stroke(isHovering ? CFColors.focusRing.opacity(0.48) : CFColors.separatorSubtle, lineWidth: CFSeparators.width))
            )
            .scaleEffect(scaleValue)
            .cfAnimation(CFMotion.spring, value: isHovering, reduceMotion: reduceMotion)
            .cfAnimation(CFMotion.quick, value: isPressed, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .cfFocusRing(cornerRadius: CFRadius.pill)
    }

    private var scaleValue: CGFloat {
        if reduceMotion { return 1 }
        return isPressed ? CFMotion.activeScale : (isHovering ? CFMotion.hoverScale : 1)
    }
}

struct DockIconButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    @Environment(\.cfReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CFColors.textPrimary)
                .frame(width: 52, height: 52)
                .background(
                    Capsule()
                        .fill(isHovering ? CFColors.dockHoverFill : CFColors.dockFill)
                        .overlay(Capsule().stroke(isHovering ? CFColors.focusRing.opacity(0.48) : CFColors.separatorSubtle, lineWidth: CFSeparators.width))
                )
                .scaleEffect(scaleValue)
                .cfAnimation(CFMotion.spring, value: isHovering, reduceMotion: reduceMotion)
                .cfAnimation(CFMotion.quick, value: isPressed, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .cfFocusRing(cornerRadius: CFRadius.pill)
    }

    private var scaleValue: CGFloat {
        if reduceMotion { return 1 }
        return isPressed ? CFMotion.activeScale : (isHovering ? CFMotion.hoverScale : 1)
    }
}

private struct SourceRailRow: View {
    let ranked: RankedRelease
    let playTitle: String
    let copyTitle: String
    let seedersHelp: String
    let rankingHelp: String
    let advancedTitle: String
    let language: AppLanguage
    let onPlay: () -> Void
    let onCopy: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: 5) {
                Text(ranked.release.sourceName)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(1)
                Text(sourceSubtitle)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .lineLimit(2)
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(ranked.release.title)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(1)

                ReleaseExplanationBadges(ranked: ranked, language: language)

                HStack(spacing: 6) {
                    Label("\(ranked.release.seeders)", systemImage: "person.fill")
                        .help(seedersHelp)
                    Label(ranked.release.humanReadableSize, systemImage: "externaldrive.fill")
                }
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(1)

                Text(languageLine)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)

                ReleaseExplanationSummary(ranked: ranked, language: language)
            }

            Spacer(minLength: 0)

            if ranked.release.magnetURI != nil {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CFColors.textSecondary)
                .help(copyTitle)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous)
                .fill(isHovering ? CFColors.hoverFill : CFColors.surfaceOverlay.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous)
                        .stroke(isHovering ? CFColors.focusRing.opacity(0.34) : CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: CFRadius.control, style: .continuous))
        .onTapGesture(perform: onPlay)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(playTitle)
        .help(localizedReleaseTooltip(for: ranked, language: language, rankingHelp: rankingHelp))
    }

    private var accessibilityLabel: String {
        "\(ranked.release.title), \(ranked.release.sourceName), \(sourceSubtitle), \(ranked.release.humanReadableSize), \(ranked.release.seeders) seeders"
    }

    private var sourceSubtitle: String {
        var values = [ranked.release.qualityLabel]
        if ranked.release.hdr != .none, ranked.release.hdr != .unknown {
            values.append(ranked.release.hdr.rawValue)
        }
        if ranked.release.codec != .unknown {
            values.append(ranked.release.codec.rawValue)
        }
        return values.joined(separator: " | ")
    }

    private var languageLine: String {
        let audio = ranked.release.audioLanguages.isEmpty ? "audio n/a" : ranked.release.audioLanguages.joined(separator: "/")
        let subtitles = ranked.release.subtitleLanguages.isEmpty ? "subs n/a" : ranked.release.subtitleLanguages.joined(separator: "/")
        return "\(audio) · \(subtitles)"
    }
}

private struct MovieReleaseRow: View {
    let ranked: RankedRelease
    let languagesText: String
    let copyTitle: String
    let playTitle: String
    let seedersHelp: String
    let rankingHelp: String
    let advancedTitle: String
    let language: AppLanguage
    let onPlay: () -> Void
    let onCopy: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: CFSpacing.lg) {
            VStack(alignment: .leading, spacing: CFSpacing.sm) {
                Text(ranked.release.title)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: CFSpacing.sm) {
                    ReleaseExplanationBadges(ranked: ranked, language: language)
                    QualityBadge(ranked.release.qualityLabel)
                    if ranked.release.hdr != .none, ranked.release.hdr != .unknown {
                        CFBadge(ranked.release.hdr.rawValue, tone: .quality)
                    }
                    CFBadge(ranked.release.codec.rawValue, tone: .source)
                    SeedersBadge(ranked.release.seeders)
                        .help(seedersHelp)
                SourceBadge(ranked.release.sourceName)
                    CFBadge(ranked.release.humanReadableSize, tone: .source)
                }

                Text(languagesText)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .lineLimit(1)

                ReleaseExplanationSummary(ranked: ranked, language: language)
                ReleaseAdvancedDetails(ranked: ranked, title: advancedTitle, language: language)
            }

            Spacer()

            IconButton(systemImage: "play.fill", accessibilityLabel: playTitle, action: onPlay)

            if ranked.release.magnetURI != nil {
                IconButton(systemImage: "doc.on.doc", accessibilityLabel: copyTitle, action: onCopy)
            }
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
        .accessibilityHint(playTitle)
        .help(localizedReleaseTooltip(for: ranked, language: language, rankingHelp: rankingHelp))
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }

    private var accessibilityLabel: String {
        "\(ranked.release.title), \(ranked.release.sourceName), \(ranked.release.qualityLabel), \(ranked.release.humanReadableSize), \(ranked.release.seeders) seeders"
    }
}

struct MovieDetailLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            LoadingSkeleton(height: 430, cornerRadius: CFRadius.hero)

            HStack(spacing: CFSpacing.sm) {
                ForEach(0..<5, id: \.self) { _ in
                    LoadingSkeleton(height: 32, cornerRadius: CFRadius.pill)
                        .frame(width: 110)
                }
            }

            ForEach(0..<4, id: \.self) { _ in
                LoadingSkeleton(height: 86, cornerRadius: CFRadius.panel)
            }
        }
    }
}
