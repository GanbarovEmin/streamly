import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct LibraryView: View {
    @ObservedObject private var viewModel: LibraryViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    private let initialSection: LibrarySection

    public init(
        viewModel: LibraryViewModel,
        navigationCoordinator: NavigationCoordinator,
        initialSection: LibrarySection = .favorites,
        imagePipeline: CineFlowImagePipeline
    ) {
        self.viewModel = viewModel
        self.navigationCoordinator = navigationCoordinator
        self.initialSection = initialSection
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                header
                controls
                content
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .task {
            viewModel.selectSection(initialSection)
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(t(.libraryEyebrow).uppercased())
                .font(CFTypography.overline)
                .tracking(1.4)
                .foregroundStyle(CFColors.accentPrimary)

            HStack(alignment: .bottom, spacing: CFSpacing.xl) {
                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text(t(.libraryTitle))
                        .font(CFTypography.largeTitle)
                        .foregroundStyle(CFColors.textPrimary)

                    Text(t(.librarySubtitle))
                        .font(CFTypography.body)
                        .foregroundStyle(CFColors.textSecondary)
                }

                Spacer(minLength: CFSpacing.lg)

                summaryGrid
                    .frame(maxWidth: 620)
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

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: CFSpacing.sm)], spacing: CFSpacing.sm) {
            LibraryMetric(title: "Избранное", value: viewModel.summary.favoriteCount)
            LibraryMetric(title: "Фильмы", value: viewModel.summary.movieCount)
            LibraryMetric(title: "Сериалы", value: viewModel.summary.seriesCount)
            LibraryMetric(title: "Списки", value: viewModel.summary.listCount)
            LibraryMetric(title: "Просмотрено", value: viewModel.summary.watchedCount)
            LibraryMetric(title: "Рейтинги", value: viewModel.summary.ratingCount)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.sm) {
                    ForEach(LibrarySection.allCases) { section in
                        DetailTabButton(title: title(for: section), isSelected: viewModel.selectedSection == section) {
                            viewModel.selectSection(section)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: CFSpacing.md) {
                TextField(t(.librarySearchPlaceholder), text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.updateSearchQuery($0) }
                ))
                .textFieldStyle(.plain)
                .font(CFTypography.body)
                .padding(.horizontal, CFSpacing.md)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .fill(CFColors.panelFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                        )
                )

                Picker("Тип", selection: Binding(
                    get: { viewModel.selectedKindFilter },
                    set: { viewModel.setKindFilter($0) }
                )) {
                    ForEach(LibraryKindFilter.allCases) { filter in
                        Text(title(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

                Picker("Сортировка", selection: Binding(
                    get: { viewModel.sortOrder },
                    set: { viewModel.setSortOrder($0) }
                )) {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Text(title(for: order)).tag(order)
                    }
                }
                .frame(width: 210)
            }

            if viewModel.selectedSection == .lists {
                listPicker
            }
        }
    }

    private var listPicker: some View {
        HStack(spacing: CFSpacing.sm) {
            if viewModel.lists.isEmpty {
                SecondaryButton(t(.listsCreateAction), systemImage: "plus") {
                    Task { _ = try? await viewModel.defaultList() }
                }
            } else {
                ForEach(viewModel.lists) { list in
                    DetailTabButton(title: "\(list.name) · \(list.itemIDs.count)", isSelected: viewModel.selectedListID == list.id) {
                        viewModel.selectList(list)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingGrid
        case .failed:
            ErrorState(
                title: t(.libraryErrorTitle),
                message: t(.libraryErrorMessage),
                recoverySuggestion: t(.libraryErrorRecovery),
                actionTitle: t(.commonRetry)
            ) {
                Task { await viewModel.load() }
            }
        case .empty:
            emptyState
        case .loaded:
            if viewModel.isCurrentSectionEmpty {
                emptyState
            } else {
                posterGrid
            }
        }
    }

    private var posterGrid: some View {
        LazyVGrid(columns: columns, spacing: CFSpacing.md) {
            ForEach(viewModel.visibleItems) { item in
                LibraryPosterCard(
                    model: viewModel.cardModel(for: item),
                    isFavorite: viewModel.isFavorite(item.id),
                    rating: viewModel.rating(for: item.id),
                    open: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    watch: {
                        navigationCoordinator.navigate(to: .player(mediaID: item.id))
                    },
                    continueWatching: {
                        navigationCoordinator.navigate(to: .player(mediaID: item.id))
                    },
                    remove: {
                        Task { try? await viewModel.removeFromLibrary(mediaID: item.id) }
                    },
                    addToList: {
                        Task { await addToDefaultList(item) }
                    },
                    rate: {
                        Task { try? await viewModel.rate(item, rating: 8) }
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

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: CFSpacing.md) {
            ForEach(0..<8, id: \.self) { _ in
                LoadingSkeleton(height: 310, cornerRadius: CFRadius.panel)
            }
        }
    }

    private var emptyState: some View {
        EmptyState(
            title: emptyTitle,
            message: emptyMessage,
            systemImage: emptyIcon,
            actionTitle: emptyActionTitle,
            actionSystemImage: emptyActionIcon
        ) {
            emptyAction()
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: CFSpacing.md)]
    }

    private var emptyTitle: String {
        switch viewModel.selectedSection {
        case .favorites:
            t(.libraryEmptyFavoritesTitle)
        case .lists:
            t(.libraryEmptyListsTitle)
        case .watched:
            t(.libraryEmptyWatchedTitle)
        case .ratings:
            t(.libraryEmptyRatingsTitle)
        case .movies:
            t(.libraryEmptyMoviesTitle)
        case .series:
            t(.libraryEmptySeriesTitle)
        case .all:
            t(.libraryEmptyAllTitle)
        }
    }

    private var emptyMessage: String {
        switch viewModel.selectedSection {
        case .favorites:
            t(.libraryEmptyFavoritesMessage)
        case .lists:
            t(.libraryEmptyListsMessage)
        case .watched:
            t(.libraryEmptyWatchedMessage)
        case .ratings:
            t(.libraryEmptyRatingsMessage)
        case .movies:
            t(.libraryEmptyMoviesMessage)
        case .series:
            t(.libraryEmptySeriesMessage)
        default:
            t(.libraryEmptyAllMessage)
        }
    }

    private var emptyActionTitle: String {
        viewModel.selectedSection == .lists ? t(.libraryEmptyActionList) : t(.libraryEmptyActionSearch)
    }

    private var emptyActionIcon: String {
        viewModel.selectedSection == .lists ? "plus" : "magnifyingglass"
    }

    private func emptyAction() {
        if viewModel.selectedSection == .lists {
            navigationCoordinator.selectSidebarRoute(.lists)
        } else {
            navigationCoordinator.focusSearchField()
        }
    }

    private var emptyIcon: String {
        switch viewModel.selectedSection {
        case .favorites:
            "heart"
        case .lists:
            "list.bullet.rectangle"
        case .watched:
            "clock.arrow.circlepath"
        case .ratings:
            "star"
        case .movies:
            "film"
        case .series:
            "tv"
        case .all:
            "rectangle.stack"
        }
    }

    private func addToDefaultList(_ item: MediaItem) async {
        do {
            let list: UserList
            if let existingList = viewModel.lists.first(where: { $0.isDefault }) ?? viewModel.lists.first {
                list = existingList
            } else {
                list = try await viewModel.defaultList()
            }
            try await viewModel.add(item, to: list)
        } catch {
            // The view model exposes repository failures through reload state.
        }
    }

    private func title(for section: LibrarySection) -> String {
        switch section {
        case .favorites:
            "Избранное"
        case .all:
            "Все"
        case .movies:
            "Фильмы"
        case .series:
            "Сериалы"
        case .lists:
            "Списки"
        case .watched:
            "Просмотрено"
        case .ratings:
            "Рейтинги"
        }
    }

    private func title(for filter: LibraryKindFilter) -> String {
        switch filter {
        case .all:
            "Все"
        case .movies:
            "Фильмы"
        case .series:
            "Сериалы"
        }
    }

    private func title(for sortOrder: LibrarySortOrder) -> String {
        switch sortOrder {
        case .recentlyAdded:
            "Недавние"
        case .titleAscending:
            "Название"
        case .yearDescending:
            "Год"
        case .ratingDescending:
            "Оценка"
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct LibraryMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.xs) {
            Text("\(value)")
                .font(CFTypography.title)
                .foregroundStyle(CFColors.textPrimary)
            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
                .lineLimit(1)
        }
        .padding(CFSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct LibraryPosterCard: View {
    let model: CFMediaCardModel
    let isFavorite: Bool
    let rating: Int?
    let open: () -> Void
    let watch: () -> Void
    let continueWatching: () -> Void
    let remove: () -> Void
    let addToList: () -> Void
    let rate: () -> Void
    let imageDataLoader: CFImageDataLoader?

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: CFSpacing.md) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    model.accentIndex.isMultiple(of: 2) ? CFColors.surfaceOverlay : CFColors.backgroundTertiary,
                                    model.accentIndex.isMultiple(of: 3) ? CFColors.accentSecondary.opacity(0.34) : CFColors.backgroundSecondary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                .stroke(isHovering ? CFColors.focusRing.opacity(0.50) : CFColors.separator, lineWidth: CFSeparators.width)
                        )
                        .overlay {
                            if let artworkURL = model.artworkURL {
                                CFCachedAsyncImage(url: artworkURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                                    .clipShape(RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
                            } else {
                                Text(String(model.title.prefix(1)))
                                    .font(.system(size: 74, weight: .black, design: .rounded))
                                    .foregroundStyle(CFColors.textPrimary.opacity(0.18))
                            }
                        }
                        .frame(height: 238)

                    if let progress = model.progress {
                        ProgressBar(value: progress)
                            .padding(.horizontal, CFSpacing.sm)
                            .padding(.bottom, CFSpacing.sm)
                    }

                    HStack {
                        if isFavorite {
                            QualityBadge("★")
                        }
                        Spacer()
                        if let rating {
                            RatingBadge("\(rating)/10")
                        }
                    }
                    .padding(CFSpacing.md)
                    .frame(maxHeight: .infinity, alignment: .top)

                    if isHovering {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(CFColors.textPrimary)
                            .cfShadow(.icon)
                            .padding(CFSpacing.md)
                            .transition(.opacity)
                    }
                }

                Text(model.title)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(1)

                Text(model.metadata)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)
            }
            .scaleEffect(isHovering ? 1.012 : 1)
            .animation(CFMotion.quick, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Смотреть", systemImage: "play.fill", action: watch)
            Button("Продолжить", systemImage: "play.rectangle.fill", action: continueWatching)
            Divider()
            Button("Добавить в список", systemImage: "list.bullet", action: addToList)
            Button("Оценить", systemImage: "star.fill", action: rate)
            Divider()
            Button("Убрать из библиотеки", systemImage: "trash", action: remove)
        }
        .cfFocusRing()
    }
}
