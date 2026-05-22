import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct HomeView: View {
    @ObservedObject private var viewModel: HomeViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    private let onEpisodeNotificationDigest: (SeriesTrackingDigest) -> Void

    public init(
        viewModel: HomeViewModel,
        navigationCoordinator: NavigationCoordinator,
        imagePipeline: CineFlowImagePipeline,
        onEpisodeNotificationDigest: @escaping (SeriesTrackingDigest) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.navigationCoordinator = navigationCoordinator
        self.imagePipeline = imagePipeline
        self.onEpisodeNotificationDigest = onEpisodeNotificationDigest
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: homeRowSpacing) {
                content
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .task {
            if viewModel.state == .loading {
                await viewModel.load()
                onEpisodeNotificationDigest(viewModel.episodeNotificationDigest)
            }
        }
        .onAppear {
            Task { await viewModel.refreshHomePreferences() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HomeLoadingView(title: t(.homeLoading))
        case .empty:
            EmptyState(
                title: t(.homeEmptyTitle),
                message: t(.homeEmptyMessage),
                systemImage: "film.stack",
                actionTitle: t(.homeEmptyAction),
                actionSystemImage: "gearshape"
            ) {
                navigationCoordinator.selectSidebarRoute(.settings)
            }
            .frame(maxWidth: .infinity, minHeight: 520)
        case .failed:
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                ErrorState(
                    title: t(.homeErrorTitle),
                    message: t(.homeErrorMessage),
                    recoverySuggestion: t(.homeErrorRecovery),
                    actionTitle: t(.homeEmptyAction)
                ) {
                    navigationCoordinator.selectSidebarRoute(.settings)
                }
                HomeLoadingView(title: t(.homeLoading))
                    .opacity(0.42)
            }
        case .loaded:
            if let item = viewModel.selectedFeaturedItem {
                HomeHeroView(
                    item: item,
                    featuredItems: viewModel.featuredItems,
                    selectedIndex: viewModel.selectedFeaturedIndex,
                    eyebrow: t(.homeHeroEyebrow),
                    watchTitle: t(.homeWatch),
                    detailsTitle: t(.homeHeroDetails),
                    onWatch: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    onDetails: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    onSelectFeatured: { id in
                        viewModel.selectFeaturedItem(id: id)
                    },
                    imageDataLoader: { url in
                        try await imagePipeline.data(for: url)
                    }
                )
            }

            if let undo = viewModel.personalizationUndo {
                HStack(spacing: CFSpacing.md) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .foregroundStyle(CFColors.accentPrimary)
                    Text("Recommendation preferences updated.")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                    Spacer()
                    SecondaryButton(undo.title, systemImage: "arrow.uturn.backward") {
                        Task { await viewModel.undoLastPersonalizationAction() }
                    }
                }
                .padding(.horizontal, CFSpacing.lg)
                .padding(.vertical, CFSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .fill(CFColors.elevatedFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                        )
                )
            }

            ForEach(viewModel.sections) { section in
                if section.kind == .moodDiscovery {
                    MoodDiscoveryHomeSection(
                        title: localizedSectionTitle(section.kind),
                        filters: viewModel.moodFilters,
                        selectedFilter: viewModel.selectedMoodFilter,
                        pick: viewModel.moodPick,
                        items: section.items,
                        onSelectFilter: { filter in
                            viewModel.selectMoodFilter(filter)
                        },
                        onPick: { itemID in
                            navigationCoordinator.navigate(to: .mediaDetail(id: itemID))
                        },
                        onSelectItem: { item in
                            navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                        },
                        imageDataLoader: { url in
                            try await imagePipeline.data(for: url)
                        }
                    )
                } else if section.items.isEmpty {
                    HomeEmptySection(
                        title: localizedSectionTitle(section.kind),
                        message: L10n.format(.emptyInlineMessageFormat, language: selectedLanguage, localizedSectionTitle(section.kind)),
                        actionTitle: t(.emptyInlineAction)
                    ) {
                        navigationCoordinator.focusSearchField()
                    }
                } else {
                    MediaCarousel(
                        title: localizedSectionTitle(section.kind),
                        items: section.items,
                        cardStyle: section.cardStyle,
                        posterWidth: preferredPosterWidth,
                        landscapeWidth: preferredLandscapeWidth,
                        verticalSpacing: viewModel.homePreferences.layoutDensity == .compact ? CFSpacing.sm : CFSpacing.md,
                        menuActions: cardMenuActions(for: section),
                        action: { item in
                            if section.kind == .upcomingCalendar {
                                Task { await viewModel.addUpcomingToWatchlist(itemID: item.id) }
                            } else if section.kind == .collections {
                                navigationCoordinator.navigate(to: .collectionDetail(id: item.id))
                            } else {
                                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                            }
                        },
                        imageDataLoader: { url in
                            try await imagePipeline.data(for: url)
                        }
                    )
                }
            }
            .task(id: viewModel.artworkPrefetchKey) {
                await imagePipeline.prefetch(viewModel.prefetchArtworkURLs)
            }
        }
    }

    private func localizedSectionTitle(_ kind: HomeSectionKind) -> String {
        switch kind {
        case .newEpisodes:
            t(.homeSectionNewEpisodes)
        case .upcomingCalendar:
            t(.homeSectionUpcomingCalendar)
        case .collections:
            "Collections"
        case .moodDiscovery:
            "What to Watch Today?"
        case .watchNext:
            t(.homeSectionWatchNext)
        case .continueWatching:
            t(.homeSectionContinueWatching)
        case .trendingNow:
            "В тренде"
        case .popularMovies:
            t(.homeSectionPopularMovies)
        case .popularSeries:
            t(.homeSectionPopularSeries)
        case .trendingMovies:
            t(.homeSectionTrendingMovies)
        case .trendingSeries:
            t(.homeSectionTrendingSeries)
        case .recentlyAdded:
            t(.homeSectionRecentlyAdded)
        case .recommended:
            t(.homeSectionRecommended)
        case .moreLikeThis:
            "More Like This"
        case .fromFavoriteGenres:
            "From Your Favorite Genres"
        case .continueSeries:
            "Continue Series"
        case .hiddenGems:
            "Hidden Gems"
        case .popularInFavoriteGenres:
            "Popular in Your Favorite Genres"
        case .notFinishedYet:
            "Not Finished Yet"
        case .topQuality:
            t(.homeSectionTopQuality)
        case .ultraHDR:
            t(.homeSectionUltraHDR)
        case .favoriteGenres:
            t(.homeSectionFavoriteGenres)
        case .unfinishedMovies:
            t(.homeSectionUnfinishedMovies)
        case .forgottenInLibrary:
            t(.homeSectionForgottenInLibrary)
        case .recommendedTonight:
            t(.homeSectionRecommendedTonight)
        }
    }

    private func cardMenuActions(for section: HomeSection) -> CFMediaCardMenuActions {
        let isCollection = section.kind == .collections
        return CFMediaCardMenuActions(
            availability: CFMediaCardMenuAvailability(
                canAddToLibrary: !isCollection,
                canAddToWatchlist: !isCollection,
                canAddToList: !isCollection,
                canRate: !isCollection,
                canFixMetadata: !isCollection,
                canFindBestRelease: !isCollection,
                canClearProgress: false
            ),
            watch: { item in
                if section.kind == .upcomingCalendar {
                    Task { await viewModel.addUpcomingToWatchlist(itemID: item.id) }
                } else if section.kind == .collections {
                    navigationCoordinator.navigate(to: .collectionDetail(id: item.id))
                } else {
                    navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                }
            },
            details: { item in
                if section.kind == .collections {
                    navigationCoordinator.navigate(to: .collectionDetail(id: item.id))
                } else {
                    navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                }
            },
            library: { item in
                Task { await viewModel.addToLibrary(itemID: item.id) }
            },
            watchlist: { item in
                if section.kind == .upcomingCalendar {
                    Task { await viewModel.addUpcomingToWatchlist(itemID: item.id) }
                } else {
                    Task { await viewModel.addToWatchlist(itemID: item.id) }
                }
            },
            list: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            rate: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            hideTitle: { item in
                Task { await viewModel.hideTitle(itemID: item.id) }
            },
            fixMetadata: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            findBestRelease: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            notInterested: { item in
                Task { await viewModel.markNotInterested(itemID: item.id) }
            },
            removeFromRecommendations: { item in
                Task { await viewModel.removeFromRecommendations(itemID: item.id) }
            },
            showLessOfGenre: { item in
                Task { await viewModel.showLessOfPrimaryGenre(itemID: item.id) }
            },
            showMoreOfGenre: { item in
                Task { await viewModel.showMoreOfPrimaryGenre(itemID: item.id) }
            }
        )
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private var homeRowSpacing: CGFloat {
        viewModel.homePreferences.layoutDensity == .compact ? CFSpacing.md : CFSpacing.lg
    }

    private var preferredPosterWidth: CGFloat {
        switch viewModel.homePreferences.posterSize {
        case .small:
            return viewModel.homePreferences.layoutDensity == .compact ? 150 : 164
        case .medium:
            return viewModel.homePreferences.layoutDensity == .compact ? 176 : 192
        case .large:
            return viewModel.homePreferences.layoutDensity == .compact ? 204 : 224
        }
    }

    private var preferredLandscapeWidth: CGFloat {
        switch viewModel.homePreferences.layoutDensity {
        case .compact:
            360
        case .comfortable:
            420
        }
    }
}

private struct MoodDiscoveryHomeSection: View {
    let title: String
    let filters: [MoodDiscoveryFilter]
    let selectedFilter: MoodDiscoveryFilter
    let pick: MoodDiscoveryItem?
    let items: [CFMediaCardModel]
    let onSelectFilter: (MoodDiscoveryFilter) -> Void
    let onPick: (String) -> Void
    let onSelectItem: (CFMediaCardModel) -> Void
    let imageDataLoader: (@Sendable (URL) async throws -> Data)?

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(alignment: .center, spacing: CFSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CFTypography.sectionTitle)
                        .foregroundStyle(CFColors.textPrimary)
                    if let pick {
                        Text("Pick: \(pick.title) · \(pick.whySuggested)")
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: CFSpacing.md)

                Button {
                    if let pick {
                        onPick(pick.id)
                    }
                } label: {
                    Label("Pick a movie", systemImage: "sparkles")
                        .font(CFTypography.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pick == nil)
            }

            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.xs) {
                    ForEach(filters) { filter in
                        Button {
                            onSelectFilter(filter)
                        } label: {
                            Text(filter.title)
                                .font(CFTypography.caption)
                                .foregroundStyle(filter == selectedFilter ? CFColors.backgroundPrimary : CFColors.textPrimary)
                                .padding(.horizontal, CFSpacing.md)
                                .frame(height: 30)
                                .background(
                                    Capsule()
                                        .fill(filter == selectedFilter ? CFColors.accentPrimary : CFColors.panelFill)
                                        .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

            if items.isEmpty {
                Text("No local suggestions yet")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(CFSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                            .fill(CFColors.panelFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                    .stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width)
                            )
                    )
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: CFSpacing.md) {
                        ForEach(items) { item in
                            LandscapeCard(
                                model: item,
                                action: {
                                    onSelectItem(item)
                                },
                                imageDataLoader: imageDataLoader
                            )
                            .frame(width: 360)
                        }
                    }
                    .padding(.vertical, CFSpacing.xs)
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
                .accessibilityLabel(title)
            }
        }
        .padding(CFSpacing.lg)
        .cfPanelBackground(fill: CFColors.panelFill.opacity(0.72))
    }
}

private struct HomeHeroView: View {
    let item: HomeFeaturedItem
    let featuredItems: [HomeFeaturedItem]
    let selectedIndex: Int
    let eyebrow: String
    let watchTitle: String
    let detailsTitle: String
    let onWatch: () -> Void
    let onDetails: () -> Void
    let onSelectFeatured: (String) -> Void
    let imageDataLoader: (@Sendable (URL) async throws -> Data)?

    @Environment(\.cfReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                HomeBackdrop(item: item)
                    .overlay {
                        if let backdropURL = item.backdropURL {
                            CFCachedAsyncImage(url: backdropURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                                .opacity(0.72)
                                .saturation(1.08)
                        }
                    }
                    .id(item.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                LinearGradient(
                    colors: [
                        CFColors.backgroundPrimary.opacity(0.94),
                        CFColors.backgroundPrimary.opacity(0.58),
                        CFColors.backgroundPrimary.opacity(0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        CFColors.clear,
                        CFColors.backgroundPrimary.opacity(0.38),
                        CFColors.backgroundPrimary.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: CFSpacing.xl) {
                    heroCopy(width: proxy.size.width)

                    Spacer(minLength: CFSpacing.lg)

                    featuredDots
                }
                .padding(CFSpacing.xl)
            }
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.poster, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.poster, style: .continuous)
                    .stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width)
            )
            .cfAnimation(CFMotion.standard, value: item.id, reduceMotion: reduceMotion)
        }
        .frame(minHeight: 420, idealHeight: 470, maxHeight: 520)
    }

    private func heroCopy(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(eyebrow.uppercased())
                .font(CFTypography.overline)
                .tracking(1.4)
                .foregroundStyle(CFColors.accentPrimary)

            Text(item.title)
                .font(width < 840 ? .system(size: 40, weight: .bold, design: .default) : .system(size: 58, weight: .bold, design: .default))
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            HStack(spacing: 8) {
                QualityBadge(item.qualityBadge)
                ForEach(metadataBadges, id: \.self) { badge in
                    MetadataBadge(badge)
                }
            }
            .lineLimit(1)

            Text(item.overview)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(width < 760 ? 2 : 3)
                .frame(maxWidth: width < 840 ? 500 : 610, alignment: .leading)

            HStack(spacing: CFSpacing.md) {
                PrimaryButton(watchTitle, systemImage: "play.fill", action: onWatch)
                SecondaryButton(detailsTitle, systemImage: "info.circle", action: onDetails)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: width < 840 ? .infinity : 640, alignment: .leading)
    }

    private var metadataBadges: [String] {
        Array(item.metadataLine
            .components(separatedBy: " · ")
            .filter { !$0.isEmpty }
            .prefix(4))
    }

    private var featuredDots: some View {
        HStack(spacing: 8) {
            ForEach(featuredItems.indices, id: \.self) { index in
                Button {
                    onSelectFeatured(featuredItems[index].id)
                } label: {
                    Circle()
                        .fill(index == selectedIndex ? CFColors.textPrimary : CFColors.textMuted.opacity(0.48))
                        .frame(width: index == selectedIndex ? 9 : 7, height: index == selectedIndex ? 9 : 7)
                        .animation(CFMotion.quick, value: selectedIndex)
                }
                .buttonStyle(.plain)
                .help(featuredItems[index].title)
            }
        }
        .padding(.bottom, 8)
    }
}

private struct MetadataBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(CFTypography.caption.weight(.semibold))
            .foregroundStyle(CFColors.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(CFColors.panelFill.opacity(0.72))
                    .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
            )
    }
}

private struct HomeBackdrop: View {
    let item: HomeFeaturedItem

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    CFColors.backgroundPrimary,
                    CFColors.backgroundTertiary,
                    item.accentIndex.isMultiple(of: 2) ? CFColors.surfaceOverlay.opacity(0.88) : CFColors.backgroundSecondary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    CFColors.accentSecondary.opacity(0.28),
                    CFColors.accentTertiary.opacity(0.10),
                    CFColors.clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 560
            )

            Text(String(item.title.prefix(1)))
                .font(.system(size: 250, weight: .black, design: .rounded))
                .foregroundStyle(CFColors.textPrimary.opacity(0.06))
                .offset(x: -50, y: -12)

            Capsule()
                .fill(CFColors.horizontalGradient)
                .frame(width: 320, height: 5)
                .blur(radius: 12)
                .opacity(0.68)
                .offset(x: -220, y: 170)
        }
    }
}

private struct HomeLoadingView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.xl) {
            VStack(alignment: .leading, spacing: CFSpacing.lg) {
                LoadingSkeleton(height: 18, cornerRadius: CFRadius.pill)
                    .frame(width: 126)
                LoadingSkeleton(height: 58, cornerRadius: CFRadius.component)
                    .frame(maxWidth: 420)
                LoadingSkeleton(height: 18, cornerRadius: CFRadius.pill)
                    .frame(width: 340)
                LoadingSkeleton(height: 72, cornerRadius: CFRadius.component)
                    .frame(maxWidth: 560)
            }
            .padding(CFSpacing.xl)
            .frame(maxWidth: .infinity, minHeight: 430, alignment: .bottomLeading)
            .background(CFHeroSurface())
            .accessibilityLabel(title)

            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: CFSpacing.md) {
                    LoadingSkeleton(height: 22, cornerRadius: CFRadius.component)
                        .frame(width: 240)

                    HStack(spacing: CFSpacing.md) {
                        ForEach(0..<5, id: \.self) { _ in
                            LoadingSkeleton(height: 236, cornerRadius: CFRadius.component)
                                .frame(width: 190)
                        }
                    }
                }
            }
        }
    }
}

private struct HomeEmptySection: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(title)
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            EmptyState(
                title: title,
                message: message,
                systemImage: "rectangle.stack.badge.minus",
                actionTitle: actionTitle,
                actionSystemImage: "magnifyingglass",
                action: action
            )
            .frame(maxWidth: .infinity, minHeight: 160)
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
