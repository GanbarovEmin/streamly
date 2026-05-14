import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct UserListsView: View {
    @StateObject private var viewModel: UserListsViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @State private var newListName = ""
    @State private var newListDescription = ""
    @State private var renameName = ""
    @State private var renameDescription = ""
    @ObservedObject private var imagePipeline: CineFlowImagePipeline
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(viewModel: UserListsViewModel, navigationCoordinator: NavigationCoordinator, imagePipeline: CineFlowImagePipeline) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigationCoordinator = navigationCoordinator
        self.imagePipeline = imagePipeline
    }

    public var body: some View {
        HStack(spacing: 0) {
            listSidebar
                .frame(width: 320)

            Divider()
                .overlay(CFColors.separator)

            detail
        }
        .background(CFColors.clear)
        .task { await viewModel.load() }
    }

    private var listSidebar: some View {
        VStack(alignment: .leading, spacing: CFSpacing.lg) {
            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(t(.listsTitle))
                    .font(CFTypography.largeTitle)
                    .foregroundStyle(CFColors.textPrimary)
                Text(t(.listsSubtitle))
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }
            .padding(.top, 28)

            createControls

            ScrollView {
                VStack(spacing: CFSpacing.sm) {
                    ForEach(viewModel.lists) { list in
                        Button {
                            Task { await viewModel.selectList(list) }
                        } label: {
                            UserListRow(list: list, isSelected: viewModel.selectedList?.id == list.id)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Переименовать", systemImage: "pencil") {
                                renameName = list.name
                                renameDescription = list.description ?? ""
                                Task { await viewModel.selectList(list) }
                            }
                            if !list.isDefault {
                                Button("Удалить список", systemImage: "trash") {
                                    Task {
                                        await viewModel.selectList(list)
                                        try? await viewModel.deleteSelectedList()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CFSpacing.lg)
        .padding(.bottom, CFSpacing.lg)
    }

    private var createControls: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            TextField(t(.listsCreateNamePlaceholder), text: $newListName)
                .textFieldStyle(.roundedBorder)
            TextField(t(.listsCreateDescriptionPlaceholder), text: $newListDescription)
                .textFieldStyle(.roundedBorder)
            SecondaryButton(t(.listsCreateAction), systemImage: "plus") {
                let name = newListName
                let description = newListDescription
                Task {
                    _ = try? await viewModel.createList(name: name, description: description)
                    newListName = ""
                    newListDescription = ""
                }
            }
            .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch viewModel.state {
        case .loading:
            LoadingSkeleton(height: 420, cornerRadius: CFRadius.panel)
                .padding(CFSpacing.xl)
        case .failed:
            ErrorState(
                title: t(.listsErrorTitle),
                message: t(.listsErrorMessage),
                recoverySuggestion: t(.listsErrorRecovery),
                actionTitle: t(.commonRetry)
            ) {
                Task { await viewModel.load() }
            }
                .padding(CFSpacing.xl)
        case .empty:
            EmptyState(
                title: t(.listsEmptyTitle),
                message: t(.listsEmptyMessage),
                systemImage: "list.bullet.rectangle",
                actionTitle: t(.listsEmptyAction),
                actionSystemImage: "plus"
            ) {
                Task { await viewModel.createDefaultList() }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            selectedListDetail
        }
    }

    private var selectedListDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                if let list = viewModel.selectedList {
                    VStack(alignment: .leading, spacing: CFSpacing.md) {
                        HStack(alignment: .top, spacing: CFSpacing.lg) {
                            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                                Text(list.name)
                                    .font(CFTypography.largeTitle)
                                    .foregroundStyle(CFColors.textPrimary)
                                Text(list.description ?? "Без описания")
                                    .font(CFTypography.body)
                                    .foregroundStyle(CFColors.textSecondary)
                                Text("\(list.itemsCount) items · \(dateLabel(list.updatedAt))")
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textMuted)
                            }

                            Spacer()

                            SecondaryButton("Сохранить", systemImage: "checkmark") {
                                Task {
                                    try? await viewModel.renameSelectedList(
                                        name: renameName.isEmpty ? list.name : renameName,
                                        description: renameDescription.isEmpty ? list.description : renameDescription
                                    )
                                }
                            }
                        }

                        HStack(spacing: CFSpacing.md) {
                            TextField("Название", text: Binding(
                                get: { renameName.isEmpty ? list.name : renameName },
                                set: { renameName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField("Описание", text: Binding(
                                get: { renameDescription.isEmpty ? (list.description ?? "") : renameDescription },
                                set: { renameDescription = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        if list.isDefault {
                            watchlistToolbar
                        }
                    }
                    .padding(CFSpacing.xl)
                    .cfPanelBackground(fill: CFColors.panelFill)

                    if viewModel.visibleItems.isEmpty {
                        EmptyState(
                            title: t(.listsSelectedEmptyTitle),
                            message: t(.listsSelectedEmptyMessage),
                            systemImage: "rectangle.stack.badge.plus",
                            actionTitle: t(.listsSelectedEmptyAction),
                            actionSystemImage: "magnifyingglass"
                        ) {
                            navigationCoordinator.focusSearchField()
                        }
                            .frame(maxWidth: .infinity, minHeight: 340)
                    } else {
                        if let suggestion = viewModel.cleanupSuggestions.first {
                            watchlistCleanupBanner(suggestion)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: CFSpacing.md)], spacing: CFSpacing.md) {
                            ForEach(viewModel.watchlistItems) { watchlistItem in
                                VStack(alignment: .leading, spacing: CFSpacing.sm) {
                                    PosterCard(
                                        model: viewModel.cardModel(for: watchlistItem.item),
                                        action: {
                                            navigationCoordinator.navigate(to: .mediaDetail(id: watchlistItem.item.id))
                                        },
                                        menuActions: watchlistCardMenuActions(for: watchlistItem.item),
                                        imageDataLoader: { url in
                                            try await imagePipeline.data(for: url)
                                        }
                                    )

                                    watchlistMetadataRow(watchlistItem)
                                }
                                .contextMenu {
                                    Button("Открыть", systemImage: "info.circle") {
                                        navigationCoordinator.navigate(to: .mediaDetail(id: watchlistItem.item.id))
                                    }
                                    Menu("Priority") {
                                        ForEach(WatchlistPriority.allCases) { priority in
                                            Button(priorityTitle(priority)) {
                                                Task {
                                                    try? await viewModel.setWatchlistPriority(
                                                        mediaID: watchlistItem.item.id,
                                                        priority: priority
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    Menu("Remind me later") {
                                        Button("Tomorrow") {
                                            Task {
                                                try? await viewModel.remindLater(
                                                    mediaID: watchlistItem.item.id,
                                                    until: Date().addingTimeInterval(24 * 60 * 60)
                                                )
                                            }
                                        }
                                        Button("Next week") {
                                            Task {
                                                try? await viewModel.remindLater(
                                                    mediaID: watchlistItem.item.id,
                                                    until: Date().addingTimeInterval(7 * 24 * 60 * 60)
                                                )
                                            }
                                        }
                                        Button("Clear reminder") {
                                            Task { try? await viewModel.remindLater(mediaID: watchlistItem.item.id, until: nil) }
                                        }
                                    }
                                    Button("Удалить из списка", systemImage: "minus.circle") {
                                        Task { try? await viewModel.remove(watchlistItem.item.id) }
                                    }
                                }
                            }
                        }
                        .task(id: viewModel.artworkPrefetchKey) {
                            await imagePipeline.prefetch(viewModel.prefetchArtworkURLs)
                        }
                    }
                }
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
    }

    private var watchlistToolbar: some View {
        HStack(spacing: CFSpacing.md) {
            Picker("Sort", selection: Binding(
                get: { viewModel.watchlistSortOrder },
                set: { viewModel.setWatchlistSortOrder($0) }
            )) {
                ForEach(WatchlistSortOrder.allCases) { order in
                    Text(sortTitle(order)).tag(order)
                }
            }
            .frame(width: 220)

            Text("Priority, reminders and release badges stay local and sync-ready.")
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)

            Spacer()
        }
    }

    private func watchlistCardMenuActions(for item: MediaItem) -> CFMediaCardMenuActions {
        CFMediaCardMenuActions(
            availability: CFMediaCardMenuAvailability(
                canAddToLibrary: false,
                canAddToWatchlist: false,
                canAddToList: false,
                canHide: false,
                canFindBestRelease: !item.rankedReleases.isEmpty,
                canClearProgress: false,
                canTuneRecommendations: false
            ),
            watch: { item in
                navigationCoordinator.navigate(to: .player(mediaID: item.id))
            },
            details: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            library: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            watchlist: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            list: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            rate: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            hideTitle: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            fixMetadata: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            },
            findBestRelease: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
            }
        )
    }

    private func watchlistCleanupBanner(_ suggestion: WatchlistPresentationItem) -> some View {
        HStack(spacing: CFSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CFColors.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Already watched")
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text("\(suggestion.item.displayTitle) can be removed from Watchlist.")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }
            Spacer()
            SecondaryButton("Keep", systemImage: "bookmark") {}
            PrimaryButton("Remove", systemImage: "minus.circle") {
                Task { try? await viewModel.acceptCleanupSuggestion(mediaID: suggestion.item.id) }
            }
        }
        .padding(CFSpacing.lg)
        .cfPanelBackground(fill: CFColors.panelFill)
    }

    private func watchlistMetadataRow(_ item: WatchlistPresentationItem) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.xs) {
            HStack(spacing: CFSpacing.xs) {
                QualityBadge(priorityTitle(item.priority))
                ForEach(item.badges, id: \.self) { badge in
                    QualityBadge(badgeTitle(badge))
                }
            }
            .lineLimit(1)

            if let remindLaterAt = item.remindLaterAt {
                Label("Remind \(dateLabel(remindLaterAt))", systemImage: "bell")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func sortTitle(_ order: WatchlistSortOrder) -> String {
        switch order {
        case .priority:
            "Priority"
        case .addedDate:
            "Added"
        case .rating:
            "Rating"
        case .runtime:
            "Runtime"
        case .quality:
            "Quality"
        case .mood:
            "Mood"
        }
    }

    private func priorityTitle(_ priority: WatchlistPriority) -> String {
        switch priority {
        case .high:
            "High"
        case .normal:
            "Normal"
        case .later:
            "Later"
        }
    }

    private func badgeTitle(_ badge: WatchlistBadge) -> String {
        switch badge {
        case .availableIn4KHDR:
            "4K/HDR"
        case .betterReleaseAvailable:
            "Better"
        case .russianAudioAvailable:
            "RU Audio"
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct UserListRow: View {
    let list: UserList
    let isSelected: Bool

    var body: some View {
        HStack(spacing: CFSpacing.md) {
            Image(systemName: list.isDefault ? "bookmark.fill" : "list.bullet.rectangle")
                .foregroundStyle(isSelected ? CFColors.textPrimary : CFColors.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(1)
                Text("\(list.itemsCount) items")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
            }

            Spacer()
        }
        .padding(CFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(isSelected ? CFColors.activeFill : CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(isSelected ? CFColors.focusRing : CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }
}
