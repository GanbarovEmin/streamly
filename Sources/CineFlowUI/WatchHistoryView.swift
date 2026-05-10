import CineFlowDesignSystem
import SwiftUI

public struct ContinueWatchingView: View {
    @StateObject private var viewModel: ContinueWatchingViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator

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
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
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
        case .failed(let message):
            ErrorState(title: "Не удалось загрузить прогресс", message: message)
        case .empty:
            EmptyState(title: "Нет незавершенного просмотра", message: "Начните просмотр, и CineFlow сохранит позицию для продолжения.", systemImage: "play.rectangle")
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
}

public struct WatchHistoryView: View {
    @StateObject private var viewModel: WatchHistoryViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator

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
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
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
        case .failed(let message):
            ErrorState(title: "Не удалось загрузить историю", message: message)
        case .empty:
            EmptyState(title: "История пуста", message: "После просмотра фильмы и серии появятся здесь.", systemImage: "clock.arrow.circlepath")
                .frame(maxWidth: .infinity, minHeight: 360)
        case .loaded:
            if viewModel.visibleEntries.isEmpty {
                EmptyState(title: "Нет элементов по фильтру", message: "Выберите другой тип контента.", systemImage: "line.3.horizontal.decrease.circle")
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
