import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct SeriesDetailView: View {
    @StateObject private var viewModel: SeriesDetailViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(
        seriesID: String,
        navigationCoordinator: NavigationCoordinator,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: SeriesDetailViewModel(seriesID: seriesID, libraryRepository: libraryRepository))
        self.navigationCoordinator = navigationCoordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                content
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 46)
        }
        .scrollIndicators(.hidden)
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
            EmptyState(title: t(.seriesStateEmptyTitle), message: t(.seriesStateEmptyMessage), systemImage: "tv")
                .frame(maxWidth: .infinity, minHeight: 520)
        case .failed(let message):
            ErrorState(title: t(.seriesStateErrorTitle), message: message)
        case .loaded:
            if let series = viewModel.series {
                hero(series)
                tabs
                tabContent
            }
        }
    }

    private func hero(_ series: SeriesDetail) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                MovieBackdrop(accentIndex: series.backdropAccentIndex, title: series.title)

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
                .padding(30)
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
                Text(String(series.title.prefix(1)))
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .foregroundStyle(CFColors.textPrimary.opacity(0.22))
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
                        navigationCoordinator.navigate(to: .player(mediaID: episode.id))
                    }
                }
                SecondaryButton(t(.seriesActionContinue), systemImage: "play.rectangle.fill") {
                    viewModel.continueWatching()
                    if let episodeID = viewModel.lastPlayedEpisodeID {
                        navigationCoordinator.navigate(to: .player(mediaID: episodeID))
                    }
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
                    CFMediaCardModel(id: $0.id, title: $0.title, metadata: $0.metadata, badge: $0.quality)
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
                            viewModel.selectSeason(id: season.id)
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
                        viewModel.selectEpisode(id: episode.id)
                    } play: {
                        viewModel.playEpisode(id: episode.id)
                        navigationCoordinator.navigate(to: .player(mediaID: episode.id))
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
                        onPlay: {
                            if let episode = viewModel.selectedEpisode {
                                viewModel.playEpisode(id: episode.id)
                                navigationCoordinator.navigate(to: .player(mediaID: episode.id))
                            }
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
                            .fill(CFColors.elevatedFill)
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
                    .fill(isSelected ? CFColors.activeFill.opacity(0.84) : CFColors.elevatedFill)
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
                    QualityBadge(scoped.release.qualityLabel)
                    if scoped.release.hdr != .none, scoped.release.hdr != .unknown {
                        CFBadge(scoped.release.hdr.rawValue, tone: .quality)
                    }
                    CFBadge(scoped.release.codec.rawValue, tone: .source)
                    SeedersBadge(scoped.release.seeders)
                    SourceBadge(scoped.release.sourceName)
                    CFBadge(scoped.release.humanReadableSize, tone: .source)
                }
            }

            Spacer()

            IconButton(systemImage: "play.fill", accessibilityLabel: "Play", action: onPlay)
        }
        .padding(CFSpacing.lg)
        .background(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(isHovering ? CFColors.hoverFill : CFColors.elevatedFill)
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
        .help(scoped.ranked.explanation)
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }
}
