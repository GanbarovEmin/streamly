import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct LibraryView: View {
    @ObservedObject private var viewModel: LibraryViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore
    @State private var showsBulkConfirmation = false
    @State private var pendingCardDestructiveAction: LibraryCardDestructiveAction?
    @State private var showsCardConfirmation = false

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
        .onChange(of: viewModel.pendingBulkConfirmation) { confirmation in
            showsBulkConfirmation = confirmation != nil
        }
        .confirmationDialog(
            bulkConfirmationTitle,
            isPresented: $showsBulkConfirmation,
            titleVisibility: .visible
        ) {
            Button(bulkConfirmationButtonTitle, role: .destructive) {
                Task { try? await viewModel.confirmPendingBulkAction() }
            }
            Button("Cancel", role: .cancel) {
                Task { try? await viewModel.cancelPendingBulkAction() }
            }
        } message: {
            Text("This action affects \(viewModel.pendingBulkConfirmation?.itemCount ?? 0) selected items.")
        }
        .confirmationDialog(
            cardConfirmationTitle,
            isPresented: $showsCardConfirmation,
            titleVisibility: .visible
        ) {
            Button(cardConfirmationButtonTitle, role: .destructive) {
                Task { await confirmCardDestructiveAction() }
            }
            Button("Cancel", role: .cancel) {
                pendingCardDestructiveAction = nil
            }
        } message: {
            Text("This change stays local and can be rebuilt from your library import or sync later.")
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
                    ForEach(LibrarySavedView.allCases) { savedView in
                        DetailTabButton(title: title(for: savedView), isSelected: viewModel.activeSavedView == savedView) {
                            viewModel.applySavedView(savedView)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)

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

                filtersMenu
                    .frame(width: 132)

                bulkMenu
                    .frame(width: 132)
            }

            if viewModel.selectedSection == .lists {
                listPicker
            }

            if viewModel.hasSelection {
                HStack(spacing: CFSpacing.sm) {
                    Text("\(viewModel.selectedItemIDs.count) selected")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                    SecondaryButton("Clear selection", systemImage: "xmark.circle") {
                        viewModel.clearSelection()
                    }
                }
            }
        }
    }

    private var filtersMenu: some View {
        Menu {
            Button("Reset filters") { viewModel.resetFilters() }
            Divider()
            Menu("Genre") {
                Button("Any") { viewModel.setGenreFilter(nil) }
                ForEach(viewModel.availableGenres.prefix(16), id: \.self) { genre in
                    Button(genre) { viewModel.setGenreFilter(genre) }
                }
            }
            Menu("Year") {
                Button("Any") { viewModel.setYearRange(nil) }
                Button("1990-1999") { viewModel.setYearRange(1990...1999) }
                Button("2000-2009") { viewModel.setYearRange(2000...2009) }
                Button("2010-2019") { viewModel.setYearRange(2010...2019) }
                Button("2020-2026") { viewModel.setYearRange(2020...2026) }
            }
            Menu("Rating") {
                Button("Any") { viewModel.setMinimumRating(nil) }
                Button("7+") { viewModel.setMinimumRating(7) }
                Button("8+") { viewModel.setMinimumRating(8) }
                Button("9+") { viewModel.setMinimumRating(9) }
            }
            Menu("Watch state") {
                ForEach(LibraryWatchStateFilter.allCases) { filter in
                    Button(title(for: filter)) { viewModel.setWatchStateFilter(filter) }
                }
            }
            Menu("Added") {
                ForEach(LibraryAddedDateFilter.allCases) { filter in
                    Button(title(for: filter)) { viewModel.setAddedDateFilter(filter) }
                }
            }
            Menu("Quality") {
                ForEach(LibraryQualityFilter.allCases) { filter in
                    Button(title(for: filter)) { viewModel.setQualityFilter(filter) }
                }
            }
        } label: {
            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
    }

    private var bulkMenu: some View {
        Menu {
            Button("Select visible") { viewModel.selectVisibleItems() }
            Button("Clear selection") { viewModel.clearSelection() }
            Divider()
            Button("Mark watched") {
                Task { try? await viewModel.performBulkAction(.markWatched) }
            }
            Button("Add to list") {
                Task { await bulkAddToDefaultList() }
            }
            Divider()
            Button("Clear progress", role: .destructive) {
                Task {
                    try? await viewModel.performBulkAction(.clearProgress)
                    showsBulkConfirmation = viewModel.pendingBulkConfirmation != nil
                }
            }
            Button("Remove", role: .destructive) {
                Task {
                    try? await viewModel.performBulkAction(.remove)
                    showsBulkConfirmation = viewModel.pendingBulkConfirmation != nil
                }
            }
        } label: {
            Label("Bulk", systemImage: "checklist")
        }
        .menuStyle(.borderlessButton)
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
            if viewModel.selectedSection == .stats {
                personalStatsView
            } else if viewModel.isCurrentSectionEmpty {
                emptyState
            } else {
                posterGrid
            }
        }
    }

    private var personalStatsView: some View {
        VStack(alignment: .leading, spacing: CFSpacing.lg) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: CFSpacing.md)], spacing: CFSpacing.md) {
                LibraryMetric(title: "Фильмов", value: viewModel.personalStats.watchedMoviesCount)
                LibraryMetric(title: "Серий", value: viewModel.personalStats.watchedEpisodesCount)
                LibraryMetric(title: "За месяц", value: watchTimeText(viewModel.personalStats.monthlyWatchTimeSeconds))
                LibraryMetric(title: "Completion", value: percentText(viewModel.personalStats.completionRate))
                LibraryMetric(title: "Binge", value: bingeText(viewModel.personalStats.longestBingeSession))
                LibraryMetric(title: "Year Recap", value: yearRecapText(viewModel.personalStats.yearRecapStatus))
            }

            HStack(alignment: .top, spacing: CFSpacing.md) {
                PersonalStatsRankCard(title: "Любимые жанры", items: viewModel.personalStats.favoriteGenres)
                PersonalStatsRankCard(title: "Любимые актёры", items: viewModel.personalStats.favoriteActors)
            }

            Text("Статистика считается только на этом Mac из локальной истории и прогресса. Эти данные не отправляются в аналитику владельца без отдельного согласия.")
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
        }
    }

    private var posterGrid: some View {
        LazyVGrid(columns: columns, spacing: CFSpacing.md) {
            ForEach(viewModel.visibleItems) { item in
                LibraryPosterCard(
                    model: viewModel.cardModel(for: item),
                    quickActionState: viewModel.quickActionState(for: item),
                    isFavorite: viewModel.isFavorite(item.id),
                    rating: viewModel.rating(for: item.id),
                    isSelected: viewModel.selectedItemIDs.contains(item.id),
                    open: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    details: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    toggleSelection: {
                        viewModel.toggleSelection(mediaID: item.id)
                    },
                    watch: {
                        navigationCoordinator.navigate(to: .player(mediaID: item.id))
                    },
                    continueWatching: {
                        navigationCoordinator.navigate(to: .player(mediaID: item.id))
                    },
                    addToLibrary: {
                        Task { try? await viewModel.add(item) }
                    },
                    addToWatchlist: {
                        Task { await addToDefaultList(item) }
                    },
                    remove: {
                        requestCardConfirmation(.remove(item.id))
                    },
                    addToList: {
                        Task { await addToDefaultList(item) }
                    },
                    rate: {
                        Task { try? await viewModel.rate(item, rating: 8) }
                    },
                    fixMetadata: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    findBestRelease: {
                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                    },
                    clearProgress: {
                        requestCardConfirmation(.clearProgress(item.id))
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
        case .stats:
            "Статистика появится после просмотра"
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
        case .stats:
            "Streamly считает только локальную историю просмотра и прогресс."
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
        case .stats:
            "chart.bar.xaxis"
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

    private func bulkAddToDefaultList() async {
        do {
            let list: UserList
            if let existingList = viewModel.lists.first(where: { $0.isDefault }) ?? viewModel.lists.first {
                list = existingList
            } else {
                list = try await viewModel.defaultList()
            }
            try await viewModel.performBulkAction(.addToList(list.id))
        } catch {
            // The view model exposes repository failures through reload state.
        }
    }

    private func requestCardConfirmation(_ action: LibraryCardDestructiveAction) {
        pendingCardDestructiveAction = action
        showsCardConfirmation = true
    }

    private func confirmCardDestructiveAction() async {
        guard let action = pendingCardDestructiveAction else { return }
        pendingCardDestructiveAction = nil
        switch action {
        case .remove(let mediaID):
            try? await viewModel.removeFromLibrary(mediaID: mediaID)
        case .clearProgress(let mediaID):
            try? await viewModel.clearProgress(mediaID: mediaID)
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
        case .stats:
            "Статистика"
        }
    }

    private func watchTimeText(_ seconds: Double) -> String {
        let hours = Int(seconds / 3_600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3_600)) / 60)
        if hours > 0 {
            return minutes > 0 ? "\(hours)ч \(minutes)м" : "\(hours)ч"
        }
        return "\(minutes)м"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func bingeText(_ session: PersonalBingeSession?) -> String {
        guard let session else { return "0м" }
        return "\(watchTimeText(session.durationSeconds)) · \(session.itemCount)"
    }

    private func yearRecapText(_ status: YearRecapStatus) -> String {
        switch status {
        case .collectingSignals:
            "Собирается"
        case .readyLater:
            "Позже"
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
        case .recentlyWatched:
            "Просмотр"
        case .titleAscending:
            "Название"
        case .yearDescending:
            "Год"
        case .ratingDescending:
            "Оценка"
        case .progressDescending:
            "Прогресс"
        }
    }

    private func title(for savedView: LibrarySavedView) -> String {
        switch savedView {
        case .movies:
            "Movies"
        case .series:
            "Series"
        case .unwatched:
            "Unwatched"
        case .inProgress:
            "In Progress"
        case .favorites:
            "Favorites"
        }
    }

    private func title(for filter: LibraryWatchStateFilter) -> String {
        switch filter {
        case .all:
            "All"
        case .watched:
            "Watched"
        case .unwatched:
            "Unwatched"
        case .inProgress:
            "In progress"
        }
    }

    private func title(for filter: LibraryAddedDateFilter) -> String {
        switch filter {
        case .all:
            "Any"
        case .last7Days:
            "Last 7 days"
        case .last30Days:
            "Last 30 days"
        }
    }

    private func title(for filter: LibraryQualityFilter) -> String {
        switch filter {
        case .all:
            "Any"
        case .hd:
            "HD+"
        case .fullHD:
            "1080p+"
        case .ultraHD:
            "4K"
        case .hdr:
            "HDR"
        }
    }

    private var bulkConfirmationTitle: String {
        switch viewModel.pendingBulkConfirmation?.action {
        case .remove:
            "Remove selected items?"
        case .clearProgress:
            "Clear progress?"
        default:
            "Confirm action"
        }
    }

    private var bulkConfirmationButtonTitle: String {
        switch viewModel.pendingBulkConfirmation?.action {
        case .remove:
            "Remove"
        case .clearProgress:
            "Clear progress"
        default:
            "Confirm"
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private enum LibraryCardDestructiveAction: Equatable {
    case remove(String)
    case clearProgress(String)
}

private extension LibraryView {
    var cardConfirmationTitle: String {
        switch pendingCardDestructiveAction {
        case .remove:
            "Remove from library?"
        case .clearProgress:
            "Clear progress?"
        case nil:
            "Confirm action"
        }
    }

    var cardConfirmationButtonTitle: String {
        switch pendingCardDestructiveAction {
        case .remove:
            "Remove"
        case .clearProgress:
            "Clear progress"
        case nil:
            "Confirm"
        }
    }
}

private struct LibraryMetric: View {
    let title: String
    let value: String

    init(title: String, value: Int) {
        self.title = title
        self.value = "\(value)"
    }

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.xs) {
            Text(value)
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

private struct PersonalStatsRankCard: View {
    let title: String
    let items: [PersonalStatsRankedItem]

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(title)
                .font(CFTypography.bodyEmphasis)
                .foregroundStyle(CFColors.textPrimary)

            if items.isEmpty {
                Text("Недостаточно локальной истории.")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            } else {
                ForEach(items.prefix(5)) { item in
                    HStack(spacing: CFSpacing.sm) {
                        Text(item.name)
                            .font(CFTypography.body)
                            .foregroundStyle(CFColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.count)")
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textMuted)
                    }
                }
            }
        }
        .padding(CFSpacing.lg)
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
    let quickActionState: LibraryCardQuickActionState
    let isFavorite: Bool
    let rating: Int?
    let isSelected: Bool
    let open: () -> Void
    let details: () -> Void
    let toggleSelection: () -> Void
    let watch: () -> Void
    let continueWatching: () -> Void
    let addToLibrary: () -> Void
    let addToWatchlist: () -> Void
    let remove: () -> Void
    let addToList: () -> Void
    let rate: () -> Void
    let fixMetadata: () -> Void
    let findBestRelease: () -> Void
    let clearProgress: () -> Void
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
                        Button(action: toggleSelection) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isSelected ? CFColors.accentPrimary : CFColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSelected ? "Deselect \(model.title)" : "Select \(model.title)")

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
            Button("Watch", systemImage: "play.fill", action: watch)
                .disabled(!quickActionState.canWatch)
            Button("Details", systemImage: "info.circle", action: details)
                .disabled(!quickActionState.canOpenDetails)
            Divider()
            Button("Library", systemImage: "books.vertical", action: addToLibrary)
                .disabled(!quickActionState.canAddToLibrary)
            Button("Watchlist", systemImage: "bookmark", action: addToWatchlist)
                .disabled(!quickActionState.canAddToWatchlist)
            Button("Add to List", systemImage: "list.bullet", action: addToList)
                .disabled(!quickActionState.canAddToList)
            Button("Rate", systemImage: "star.fill", action: rate)
                .disabled(!quickActionState.canRate)
            Divider()
            Button("Hide", systemImage: "eye.slash") {}
                .disabled(!quickActionState.canHide)
            Button("Fix Metadata", systemImage: "wand.and.stars", action: fixMetadata)
                .disabled(!quickActionState.canFixMetadata)
            Button("Find Better Release", systemImage: "arrow.triangle.2.circlepath", action: findBestRelease)
                .disabled(!quickActionState.canFindBestRelease)
            Button(role: .destructive) {
                clearProgress()
            } label: {
                Label("Clear Progress", systemImage: "clock.arrow.circlepath")
            }
            .disabled(!quickActionState.canClearProgress)
            Divider()
            Button(role: .destructive) {
                remove()
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
        .cfFocusRing()
    }
}
