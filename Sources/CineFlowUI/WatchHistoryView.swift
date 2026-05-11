import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct ContinueWatchingView: View {
    @StateObject private var viewModel: ContinueWatchingViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(viewModel: ContinueWatchingViewModel, navigationCoordinator: NavigationCoordinator) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigationCoordinator = navigationCoordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                header(title: "Продолжить просмотр", subtitle: "Незавершенные фильмы и эпизоды, отсортированные по последнему просмотру.")
                content
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingSkeleton(height: 260, cornerRadius: CFRadius.panel)
        case .failed:
            ErrorState(
                title: t(.continueErrorTitle),
                message: t(.continueErrorMessage),
                recoverySuggestion: t(.continueErrorRecovery),
                actionTitle: t(.commonRetry)
            ) {
                Task { await viewModel.load() }
            }
        case .empty:
            EmptyState(
                title: t(.continueEmptyTitle),
                message: t(.continueEmptyMessage),
                systemImage: "play.rectangle",
                actionTitle: t(.continueEmptyAction),
                actionSystemImage: "rectangle.stack"
            ) {
                navigationCoordinator.selectSidebarRoute(.library)
            }
                .frame(maxWidth: .infinity, minHeight: 360)
        case .loaded:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 430), spacing: CFSpacing.md)], spacing: CFSpacing.md) {
                ForEach(viewModel.items, id: \.id) { progress in
                    LandscapeCard(model: viewModel.cardModel(for: progress)) {
                        navigationCoordinator.navigate(to: .player(mediaID: progress.episodeID ?? progress.mediaID))
                    }
                    .contextMenu {
                        Button("Продолжить", systemImage: "play.fill") {
                            navigationCoordinator.navigate(to: .player(mediaID: progress.episodeID ?? progress.mediaID))
                        }
                        Button("Убрать из продолжения", systemImage: "xmark") {
                            Task { await viewModel.clear(progress) }
                        }
                    }
                }
            }
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

public struct WatchHistoryView: View {
    @StateObject private var viewModel: WatchHistoryViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(viewModel: WatchHistoryViewModel, navigationCoordinator: NavigationCoordinator) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigationCoordinator = navigationCoordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                HStack(alignment: .bottom, spacing: CFSpacing.lg) {
                    header(title: "История просмотра", subtitle: "Просмотры сгруппированы по дате, завершенные элементы остаются в истории.")
                    Spacer()
                    SecondaryButton("Очистить историю", systemImage: "trash") {
                        Task { await viewModel.clearHistory() }
                    }
                }

                Picker("Фильтр", selection: Binding(
                    get: { viewModel.selectedFilter },
                    set: { viewModel.setFilter($0) }
                )) {
                    ForEach(WatchHistoryFilter.allCases) { filter in
                        Text(title(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                content
            }
            .cfSectionPadding()
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingSkeleton(height: 320, cornerRadius: CFRadius.panel)
        case .failed:
            ErrorState(
                title: t(.historyErrorTitle),
                message: t(.historyErrorMessage),
                recoverySuggestion: t(.historyErrorRecovery),
                actionTitle: t(.commonRetry)
            ) {
                Task { await viewModel.load() }
            }
        case .empty:
            EmptyState(
                title: t(.historyEmptyTitle),
                message: t(.historyEmptyMessage),
                systemImage: "clock.arrow.circlepath",
                actionTitle: t(.historyEmptyAction),
                actionSystemImage: "rectangle.stack"
            ) {
                navigationCoordinator.selectSidebarRoute(.library)
            }
                .frame(maxWidth: .infinity, minHeight: 360)
        case .loaded:
            if viewModel.visibleEntries.isEmpty {
                EmptyState(
                    title: t(.historyFilterEmptyTitle),
                    message: t(.historyFilterEmptyMessage),
                    systemImage: "line.3.horizontal.decrease.circle",
                    actionTitle: t(.historyFilterEmptyAction),
                    actionSystemImage: "line.3.horizontal.decrease.circle"
                ) {
                    viewModel.setFilter(.all)
                }
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                VStack(alignment: .leading, spacing: CFSpacing.xl) {
                    ForEach(viewModel.groups) { group in
                        VStack(alignment: .leading, spacing: CFSpacing.md) {
                            Text(group.title)
                                .font(CFTypography.sectionTitle)
                                .foregroundStyle(CFColors.textPrimary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 430), spacing: CFSpacing.md)], spacing: CFSpacing.md) {
                                ForEach(group.entries) { entry in
                                    LandscapeCard(model: viewModel.cardModel(for: entry)) {
                                        navigationCoordinator.navigate(to: .player(mediaID: entry.episodeID ?? entry.mediaID))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func title(for filter: WatchHistoryFilter) -> String {
        switch filter {
        case .all:
            "Все"
        case .movies:
            "Фильмы"
        case .series:
            "Сериалы"
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private func header(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: CFSpacing.xs) {
        Text(title)
            .font(CFTypography.largeTitle)
            .foregroundStyle(CFColors.textPrimary)

        Text(subtitle)
            .font(CFTypography.body)
            .foregroundStyle(CFColors.textSecondary)
    }
}
