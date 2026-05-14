import CineFlowCore
import CineFlowDesignSystem
import SwiftUI

public struct CollectionDetailView: View {
    @StateObject private var viewModel: CollectionDetailViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    private let imageDataLoader: CFImageDataLoader?

    public init(
        collectionID: String,
        provider: any CollectionDiscoveryProviderProtocol,
        navigationCoordinator: NavigationCoordinator,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        progressRepository: (any PlaybackProgressRepositoryProtocol)? = nil,
        imageDataLoader: CFImageDataLoader? = nil
    ) {
        _viewModel = StateObject(wrappedValue: CollectionDetailViewModel(
            collectionID: collectionID,
            provider: provider,
            libraryRepository: libraryRepository,
            progressRepository: progressRepository
        ))
        self.navigationCoordinator = navigationCoordinator
        self.imageDataLoader = imageDataLoader
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                switch viewModel.state {
                case .loading:
                    ProgressView("Loading collection")
                        .frame(maxWidth: .infinity, minHeight: 360)
                case .empty:
                    collectionFallback(title: "Collection not found", systemImage: "rectangle.stack.badge.questionmark")
                case .failed(let message):
                    collectionFallback(title: message, systemImage: "exclamationmark.triangle")
                case .loaded:
                    loadedContent
                }
            }
            .padding(CFSpacing.xxl)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let collection = viewModel.collection {
            hero(collection)
            controls(collection)
            watchOrderSection
            itemsSection(collection)
        }
    }

    private func hero(_ collection: MediaCollection) -> some View {
        HStack(alignment: .bottom, spacing: CFSpacing.xl) {
            posterCollage

            VStack(alignment: .leading, spacing: CFSpacing.md) {
                Text(collection.kind.title.uppercased())
                    .font(CFTypography.overline)
                    .tracking(1.2)
                    .foregroundStyle(CFColors.accentPrimary)
                Text(collection.title)
                    .font(CFTypography.heroTitle)
                    .foregroundStyle(CFColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(collection.description)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textSecondary)
                    .frame(maxWidth: 680, alignment: .leading)
                HStack(spacing: CFSpacing.sm) {
                    RatingBadge(collection.itemCountLabel)
                    RatingBadge(collection.sort.title)
                }
            }

            Spacer(minLength: CFSpacing.md)

            PrimaryButton("Add visible to Watchlist", systemImage: "plus") {
                Task { try? await viewModel.addVisibleItemsToWatchlist() }
            }
            .disabled(viewModel.visibleItems.isEmpty)
        }
    }

    private var posterCollage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
            if viewModel.posterCollageItems.isEmpty {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(CFColors.textMuted)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                    ForEach(viewModel.posterCollageItems.prefix(4)) { item in
                        ZStack {
                            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                .fill(CFColors.surfaceOverlay)
                            if let posterURL = item.mediaItem.bestPosterURL {
                                CFCachedAsyncImage(url: posterURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                            } else {
                                Text(String(item.mediaItem.displayTitle.prefix(1)))
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(CFColors.textPrimary)
                            }
                        }
                        .frame(width: 86, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
                    }
                }
                .padding(CFSpacing.sm)
            }
        }
        .frame(width: 196, height: 276)
        .overlay(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .stroke(CFColors.separator, lineWidth: CFSeparators.width)
        )
    }

    private func controls(_ collection: MediaCollection) -> some View {
        HStack(spacing: CFSpacing.md) {
            Picker("Sort", selection: Binding(
                get: { collection.sort },
                set: { viewModel.setSort($0) }
            )) {
                ForEach(CollectionSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 440)

            Picker("Filter", selection: Binding(
                get: { collection.filter },
                set: { viewModel.setFilter($0) }
            )) {
                ForEach(CollectionItemFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
        }
    }

    @ViewBuilder
    private var watchOrderSection: some View {
        if let plan = viewModel.watchOrderPlan {
            VStack(alignment: .leading, spacing: CFSpacing.md) {
                HStack(alignment: .top, spacing: CFSpacing.lg) {
                    VStack(alignment: .leading, spacing: CFSpacing.xs) {
                        Text("Watch order")
                            .font(CFTypography.sectionTitle)
                            .foregroundStyle(CFColors.textPrimary)
                        Text(plan.progressLabel)
                            .font(CFTypography.caption)
                            .foregroundStyle(CFColors.textSecondary)
                    }

                    Spacer()

                    Picker("Watch order", selection: Binding(
                        get: { plan.selectedMode },
                        set: { viewModel.setWatchOrder($0) }
                    )) {
                        ForEach(plan.availableModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 420)
                }

                ProgressBar(value: plan.progressFraction)

                if let nextItem = plan.nextItem {
                    HStack(spacing: CFSpacing.sm) {
                        RatingBadge("Next movie")
                        Text(nextItem.mediaItem.displayTitle)
                            .font(CFTypography.body)
                            .foregroundStyle(CFColors.textPrimary)
                        Spacer()
                        SecondaryButton("Open", systemImage: "chevron.right") {
                            navigationCoordinator.navigate(to: .mediaDetail(id: nextItem.mediaItem.id))
                        }
                    }
                    .padding(CFSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .fill(CFColors.surfaceOverlay)
                    )
                }

                LazyVStack(spacing: CFSpacing.sm) {
                    ForEach(plan.items) { item in
                        FranchiseWatchOrderRow(item: item) {
                            navigationCoordinator.navigate(to: .mediaDetail(id: item.mediaItem.id))
                        }
                    }
                }
            }
            .padding(CFSpacing.lg)
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

    private func itemsSection(_ collection: MediaCollection) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text("Titles")
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            if let fallback = viewModel.emptyFallbackTitle {
                collectionFallback(title: fallback, systemImage: "film.stack")
            } else if viewModel.visibleItems.isEmpty {
                collectionFallback(title: "No titles match this filter", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                LazyVStack(spacing: CFSpacing.md) {
                    ForEach(viewModel.visibleItems) { item in
                        CollectionItemRow(item: item) {
                            navigationCoordinator.navigate(to: .mediaDetail(id: item.mediaItem.id))
                        } addToWatchlist: {
                            Task { try? await viewModel.addToWatchlist(item) }
                        }
                    }
                }
            }
        }
    }

    private func collectionFallback(title: String, systemImage: String) -> some View {
        VStack(spacing: CFSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(CFColors.textMuted)
            Text(title)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
        }
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

private struct FranchiseWatchOrderRow: View {
    let item: FranchiseWatchOrderItem
    let open: () -> Void

    var body: some View {
        HStack(spacing: CFSpacing.md) {
            Text("\(item.orderNumber)")
                .font(CFTypography.caption.weight(.bold))
                .foregroundStyle(CFColors.textPrimary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CFColors.surfaceOverlay))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.mediaItem.displayTitle)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textPrimary)
                Text(metadataLine)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }

            Spacer()

            if item.isWatched {
                RatingBadge("Watched")
            }

            SecondaryButton("Open", systemImage: "chevron.right", action: open)
        }
        .padding(CFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.surfaceOverlay.opacity(0.72))
        )
    }

    private var metadataLine: String {
        [
            item.collectionItem.year > 0 ? String(item.collectionItem.year) : nil,
            item.collectionItem.rating > 0 ? String(format: "%.1f", item.collectionItem.rating) : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct CollectionItemRow: View {
    let item: CollectionMediaItem
    let open: () -> Void
    let addToWatchlist: () -> Void

    var body: some View {
        HStack(spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(item.mediaItem.displayTitle)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textPrimary)
                Text(metadataLine)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }
            Spacer()
            ForEach(item.availabilityBadges, id: \.self) { badge in
                RatingBadge(badge)
            }
            SecondaryButton("Add to Watchlist", systemImage: "plus", action: addToWatchlist)
            SecondaryButton("Open", systemImage: "chevron.right", action: open)
        }
        .padding(CFSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
    }

    private var metadataLine: String {
        [
            item.year > 0 ? String(item.year) : nil,
            item.storyOrder.map { "Story #\($0)" },
            item.rating > 0 ? String(format: "%.1f", item.rating) : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
