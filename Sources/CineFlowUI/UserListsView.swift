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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: CFSpacing.md)], spacing: CFSpacing.md) {
                            ForEach(viewModel.visibleItems) { item in
                                PosterCard(model: viewModel.cardModel(for: item)) {
                                    navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                                } imageDataLoader: { url in
                                    try await imagePipeline.data(for: url)
                                }
                                .contextMenu {
                                    Button("Открыть", systemImage: "info.circle") {
                                        navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                                    }
                                    Button("Удалить из списка", systemImage: "minus.circle") {
                                        Task { try? await viewModel.remove(item.id) }
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

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
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
