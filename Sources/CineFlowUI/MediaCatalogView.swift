import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct MediaCatalogView: View {
    @ObservedObject private var viewModel: MediaCatalogViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    private let kind: MediaCatalogKind

    public init(
        kind: MediaCatalogKind,
        viewModel: MediaCatalogViewModel,
        navigationCoordinator: NavigationCoordinator,
        imagePipeline: CineFlowImagePipeline
    ) {
        self.kind = kind
        self.viewModel = viewModel
        self.navigationCoordinator = navigationCoordinator
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.lg) {
                controls
                content
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .task {
            await viewModel.load()
        }
        .task(id: viewModel.prefetchArtworkURLs.map(\.absoluteString).joined(separator: "|")) {
            await imagePipeline.prefetch(viewModel.prefetchArtworkURLs, limit: 32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(title.uppercased())
                .font(CFTypography.overline)
                .tracking(1.4)
                .foregroundStyle(CFColors.accentPrimary)

            HStack(alignment: .bottom, spacing: CFSpacing.lg) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text(title)
                        .font(CFTypography.largeTitle)
                        .foregroundStyle(CFColors.textPrimary)

                    Text(subtitle)
                        .font(CFTypography.body)
                        .foregroundStyle(CFColors.textSecondary)
                }

                Spacer(minLength: CFSpacing.lg)

                CatalogMetric(title: metricTitle, value: viewModel.visibleItems.count)
            }
        }
        .padding(CFSpacing.xl)
        .cfPanelBackground(radius: CFRadius.hero, fill: CFColors.panelFill, shadow: .panel)
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(CFColors.horizontalGradient)
                .frame(width: 92, height: 2)
                .padding(.leading, CFSpacing.xl)
        }
    }

    private var controls: some View {
        HStack(spacing: CFSpacing.md) {
            TextField(searchPlaceholder, text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(CFTypography.body)
                .padding(.horizontal, CFSpacing.md)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .fill(CFColors.panelFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                        )
                )

            Text(countLabel)
                .font(CFTypography.caption.weight(.semibold))
                .foregroundStyle(CFColors.textMuted)
                .lineLimit(1)
                .padding(.horizontal, CFSpacing.md)
                .frame(height: 42)
                .background(
                    Capsule()
                        .fill(CFColors.panelFill.opacity(0.72))
                        .overlay(Capsule().stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width))
                )

            SecondaryButton(refreshTitle, systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 280)
        case .failed(let message):
            CatalogPlaceholderView(
                title: title,
                subtitle: message,
                systemImage: "exclamationmark.triangle.fill",
                actionTitle: refreshTitle
            ) {
                Task { await viewModel.refresh() }
            }
        case .empty:
            CatalogPlaceholderView(
                title: title,
                subtitle: emptySubtitle,
                systemImage: kind == .movies ? "film.fill" : "tv.fill",
                actionTitle: refreshTitle
            ) {
                Task { await viewModel.refresh() }
            }
        case .loaded:
            catalogGrid
        }
    }

    private var catalogGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 164, maximum: 220), spacing: 16)], spacing: 18) {
            ForEach(viewModel.cards) { card in
                PosterCard(model: card) {
                    navigationCoordinator.navigate(to: .mediaDetail(id: card.id))
                } imageDataLoader: { url in
                    try await imagePipeline.data(for: url)
                }
            }
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private var title: String {
        switch kind {
        case .movies:
            L10n.string(.navigationMovies, language: selectedLanguage)
        case .series:
            L10n.string(.navigationSeries, language: selectedLanguage)
        }
    }

    private var subtitle: String {
        switch selectedLanguage {
        case .ru:
            kind == .movies ? "Живой каталог фильмов из подключенного источника метаданных." : "Живой каталог сериалов из подключенного источника метаданных."
        case .system, .en:
            kind == .movies ? "Live movie catalog from the connected metadata source." : "Live series catalog from the connected metadata source."
        }
    }

    private var emptySubtitle: String {
        switch selectedLanguage {
        case .ru:
            "Каталог пока пуст. Проверьте интернет или источник метаданных."
        case .system, .en:
            "The catalog is empty. Check the network or metadata source."
        }
    }

    private var searchPlaceholder: String {
        switch selectedLanguage {
        case .ru:
            kind == .movies ? "Поиск по фильмам" : "Поиск по сериалам"
        case .system, .en:
            kind == .movies ? "Search movies" : "Search series"
        }
    }

    private var refreshTitle: String {
        switch selectedLanguage {
        case .ru:
            "Обновить"
        case .system, .en:
            "Refresh"
        }
    }

    private var metricTitle: String {
        switch selectedLanguage {
        case .ru:
            "В каталоге"
        case .system, .en:
            "In Catalog"
        }
    }

    private var countLabel: String {
        switch selectedLanguage {
        case .ru:
            kind == .movies ? "\(viewModel.visibleItems.count) фильмов" : "\(viewModel.visibleItems.count) сериалов"
        case .system, .en:
            kind == .movies ? "\(viewModel.visibleItems.count) movies" : "\(viewModel.visibleItems.count) series"
        }
    }
}

private struct CatalogMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
            Text("\(value)")
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)
        }
        .padding(.horizontal, CFSpacing.lg)
        .padding(.vertical, CFSpacing.md)
        .frame(minWidth: 116, alignment: .leading)
        .cfPanelBackground(radius: CFRadius.component, fill: CFColors.backgroundSecondary, shadow: .none)
    }
}

private struct CatalogPlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: CFSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(CFColors.accentPrimary)
            Text(title)
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)
            Text(subtitle)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            SecondaryButton(actionTitle, systemImage: "arrow.clockwise", action: action)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(CFSpacing.xl)
        .cfPanelBackground(radius: CFRadius.panel, fill: CFColors.panelFill, shadow: .none)
    }
}
