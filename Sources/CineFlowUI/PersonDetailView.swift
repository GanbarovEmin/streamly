import CineFlowCore
import CineFlowDesignSystem
import SwiftUI

public struct PersonDetailView: View {
    @StateObject private var viewModel: PersonDetailViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    private let imageDataLoader: CFImageDataLoader?

    public init(
        person: PersonRoutePayload,
        navigationCoordinator: NavigationCoordinator,
        provider: any PersonDetailProviderProtocol,
        libraryRepository: (any LibraryRepositoryProtocol)? = nil,
        imageDataLoader: CFImageDataLoader? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(
            person: person,
            provider: provider,
            libraryRepository: libraryRepository
        ))
        self.navigationCoordinator = navigationCoordinator
        self.imageDataLoader = imageDataLoader
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CFSpacing.xl) {
                switch viewModel.state {
                case .loading:
                    ProgressView("Loading person")
                        .frame(maxWidth: .infinity, minHeight: 360)
                case .empty:
                    DetailFallbackBlock(title: "Персона не найдена", systemImage: "person.crop.circle.badge.questionmark")
                case .failed(let message):
                    DetailFallbackBlock(title: message, systemImage: "exclamationmark.triangle")
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
        if let detail = viewModel.detail {
            hero(detail)
            controls
            filmographySection
        }
    }

    private func hero(_ detail: PersonDetail) -> some View {
        HStack(alignment: .top, spacing: CFSpacing.xl) {
            ZStack {
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(CFColors.panelFill)
                if let photoURL = detail.photoURL {
                    CFCachedAsyncImage(url: photoURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                } else {
                    Text(viewModel.photoFallbackInitials)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(CFColors.textPrimary)
                }
            }
            .frame(width: 176, height: 242)
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .stroke(CFColors.separator, lineWidth: CFSeparators.width)
            )

            VStack(alignment: .leading, spacing: CFSpacing.md) {
                Text(detail.kind == .director ? "Director" : "Actor")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                Text(detail.name)
                    .font(CFTypography.heroTitle)
                    .foregroundStyle(CFColors.textPrimary)
                if let role = detail.role {
                    RatingBadge(role)
                }
                if let fallback = viewModel.bioFallbackTitle {
                    DetailFallbackBlock(title: fallback, systemImage: "text.book.closed")
                        .frame(maxWidth: 520)
                } else {
                    Text(detail.shortBio)
                        .font(CFTypography.body)
                        .foregroundStyle(CFColors.textSecondary)
                        .frame(maxWidth: 680, alignment: .leading)
                }
                knownForRail
            }
        }
    }

    private var knownForRail: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Text("Known for")
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)
            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.md) {
                    ForEach(viewModel.knownFor) { item in
                        Button {
                            navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                        } label: {
                            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                                Text(item.displayTitle)
                                    .font(CFTypography.body)
                                    .foregroundStyle(CFColors.textPrimary)
                                    .lineLimit(1)
                                Text(item.displayYear)
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textSecondary)
                            }
                            .frame(width: 180, alignment: .leading)
                            .padding(CFSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                    .fill(CFColors.surfaceOverlay)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var controls: some View {
        HStack(spacing: CFSpacing.md) {
            Picker("Sort", selection: $viewModel.sort) {
                Text("Popularity").tag(PersonFilmographySort.popularity)
                Text("Year").tag(PersonFilmographySort.year)
                Text("Rating").tag(PersonFilmographySort.rating)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            Picker("Availability", selection: $viewModel.availabilityFilter) {
                Text("All").tag(PersonAvailabilityFilter.all)
                Text("Available").tag(PersonAvailabilityFilter.available)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
    }

    private var filmographySection: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text("Filmography")
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)
            if let fallback = viewModel.filmographyFallbackTitle {
                DetailFallbackBlock(title: fallback, systemImage: "film.stack")
            } else {
                LazyVStack(spacing: CFSpacing.md) {
                    ForEach(viewModel.visibleFilmography) { credit in
                        PersonFilmographyRow(credit: credit) {
                            navigationCoordinator.navigate(to: .mediaDetail(id: credit.mediaItem.id))
                        } addToWatchlist: {
                            Task { try? await viewModel.addToWatchlist(credit.mediaItem) }
                        }
                    }
                }
            }
        }
    }
}

private struct PersonFilmographyRow: View {
    let credit: PersonFilmographyCredit
    let open: () -> Void
    let addToWatchlist: () -> Void

    var body: some View {
        HStack(spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(credit.mediaItem.displayTitle)
                    .font(CFTypography.body)
                    .foregroundStyle(CFColors.textPrimary)
                Text("\(credit.year == 0 ? "Unknown" : String(credit.year)) · \(credit.role)")
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }
            Spacer()
            if credit.rating > 0 {
                RatingBadge(String(format: "%.1f", credit.rating))
            }
            if credit.isAvailableInLibrary {
                RatingBadge("Library")
            } else if credit.isAvailableInSources {
                RatingBadge("Available")
            }
            SecondaryButton("Add to Watchlist", systemImage: "plus") {
                addToWatchlist()
            }
            SecondaryButton("Open", systemImage: "chevron.right") {
                open()
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
