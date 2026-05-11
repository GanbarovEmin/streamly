import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct HomeView: View {
    @ObservedObject private var viewModel: HomeViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(viewModel: HomeViewModel, navigationCoordinator: NavigationCoordinator, imagePipeline: CineFlowImagePipeline) {
        self.viewModel = viewModel
        self.navigationCoordinator = navigationCoordinator
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                content
            }
            .cfSectionPadding()
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
                    libraryTitle: t(.homeAddToLibrary),
                    onWatch: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    onLibrary: {
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

            ForEach(viewModel.sections) { section in
                if section.items.isEmpty {
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
                        action: { item in
                            navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
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
        case .continueWatching:
            t(.homeSectionContinueWatching)
        case .popularMovies:
            t(.homeSectionPopularMovies)
        case .popularSeries:
            t(.homeSectionPopularSeries)
        case .recentlyAdded:
            t(.homeSectionRecentlyAdded)
        case .recommended:
            t(.homeSectionRecommended)
        case .topQuality:
            t(.homeSectionTopQuality)
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }
}

private struct HomeHeroView: View {
    let item: HomeFeaturedItem
    let featuredItems: [HomeFeaturedItem]
    let selectedIndex: Int
    let eyebrow: String
    let watchTitle: String
    let libraryTitle: String
    let onWatch: () -> Void
    let onLibrary: () -> Void
    let onSelectFeatured: (String) -> Void
    let imageDataLoader: (@Sendable (URL) async throws -> Data)?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                HomeBackdrop(item: item)
                    .overlay {
                        if let backdropURL = item.backdropURL {
                            CFCachedAsyncImage(url: backdropURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                                .opacity(0.38)
                                .overlay(CFColors.backgroundPrimary.opacity(0.26))
                        }
                    }

                LinearGradient(
                    colors: [
                        CFColors.clear,
                        CFColors.backgroundPrimary.opacity(0.38),
                        CFColors.backgroundPrimary.opacity(0.82)
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
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
                    .stroke(CFColors.separator, lineWidth: CFSeparators.width)
            )
            .cfShadow(.elevated)
        }
        .frame(minHeight: 390, idealHeight: 460, maxHeight: 500)
    }

    private func heroCopy(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(eyebrow.uppercased())
                .font(CFTypography.overline)
                .tracking(1.4)
                .foregroundStyle(CFColors.accentPrimary)

            Text(item.title)
                .font(width < 840 ? .system(size: 42, weight: .bold, design: .rounded) : CFTypography.heroTitle)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            HStack(spacing: 10) {
                QualityBadge(item.qualityBadge)

                Text(item.metadataLine)
                    .font(CFTypography.callout)
                    .foregroundStyle(CFColors.textSecondary)
                    .lineLimit(1)
            }

            Text(item.overview)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(width < 760 ? 2 : 3)
                .frame(maxWidth: width < 840 ? 520 : 640, alignment: .leading)

            HStack(spacing: CFSpacing.md) {
                PrimaryButton(watchTitle, systemImage: "play.fill", action: onWatch)
                SecondaryButton(libraryTitle, systemImage: "plus", action: onLibrary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: width < 840 ? .infinity : 680, alignment: .leading)
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
