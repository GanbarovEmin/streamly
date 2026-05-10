import CineFlowCore
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

public struct SearchView: View {
    @ObservedObject private var viewModel: SearchViewModel
    @ObservedObject private var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject private var languageSettingsStore: LanguageSettingsStore

    public init(viewModel: SearchViewModel, navigationCoordinator: NavigationCoordinator) {
        self.viewModel = viewModel
        self.navigationCoordinator = navigationCoordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                filterBar
                stateContent
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
            .padding(.bottom, 46)
        }
        .scrollIndicators(.hidden)
        .background(CFColors.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Text(t(.searchTitle))
                .font(CFTypography.heroTitle)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(t(.searchSubtitle))
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(spacing: CFSpacing.sm) {
                Text(t(.searchFilters).uppercased())
                    .font(CFTypography.overline)
                    .tracking(1.2)
                    .foregroundStyle(CFColors.accentPrimary)

                Spacer()

                Picker(t(.searchSort), selection: Binding(
                    get: { viewModel.sortOption },
                    set: { viewModel.setSortOption($0) }
                )) {
                    ForEach(SearchSortOption.allCases) { option in
                        Text(sortTitle(option)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.sm) {
                    Picker(t(.searchFilterType), selection: Binding(
                        get: { viewModel.filters.mediaType },
                        set: {
                            viewModel.filters.mediaType = $0
                            viewModel.refreshWithCurrentFilters()
                        }
                    )) {
                        Text(t(.searchFilterAll)).tag(SearchMediaType.all)
                        Text(t(.searchFilterMovies)).tag(SearchMediaType.movies)
                        Text(t(.searchFilterSeries)).tag(SearchMediaType.series)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    qualityToggle(.hd, title: "720p")
                    qualityToggle(.fullHD, title: "1080p")
                    qualityToggle(.ultraHD, title: "2160p")
                    hdrToggle

                    SearchFilterMenu(
                        title: t(.searchFilterSource),
                        selection: viewModel.filters.source ?? t(.searchFilterAll),
                        options: [nil] + viewModel.availableSources.map(Optional.some),
                        emptyTitle: t(.searchFilterAll)
                    ) { value in
                        viewModel.filters.source = value
                        viewModel.refreshWithCurrentFilters()
                    }

                    SearchFilterMenu(
                        title: t(.searchFilterYear),
                        selection: viewModel.filters.year.map(String.init) ?? t(.searchFilterAll),
                        options: [nil] + viewModel.availableYears.map { Optional.some(String($0)) },
                        emptyTitle: t(.searchFilterAll)
                    ) { value in
                        viewModel.filters.year = value.flatMap(Int.init)
                        viewModel.refreshWithCurrentFilters()
                    }

                    SearchFilterMenu(
                        title: t(.searchFilterAudio),
                        selection: viewModel.filters.audioLanguage ?? t(.searchFilterAll),
                        options: [nil] + viewModel.availableAudioLanguages.map(Optional.some),
                        emptyTitle: t(.searchFilterAll)
                    ) { value in
                        viewModel.filters.audioLanguage = value
                        viewModel.refreshWithCurrentFilters()
                    }

                    SearchFilterMenu(
                        title: t(.searchFilterSubtitles),
                        selection: viewModel.filters.subtitleLanguage ?? t(.searchFilterAll),
                        options: [nil] + viewModel.availableSubtitleLanguages.map(Optional.some),
                        emptyTitle: t(.searchFilterAll)
                    ) { value in
                        viewModel.filters.subtitleLanguage = value
                        viewModel.refreshWithCurrentFilters()
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .padding(CFSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.backgroundSecondary.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )
        )
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(CFColors.horizontalGradient)
                .frame(width: 78, height: 2)
                .padding(.leading, CFSpacing.lg)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle:
            EmptyState(
                title: t(.searchStateIdleTitle),
                message: t(.searchStateIdleMessage),
                systemImage: "magnifyingglass"
            )
            .frame(maxWidth: .infinity, minHeight: 420)
        case .loading:
            SearchLoadingView(title: t(.searchStateLoading))
        case .empty:
            EmptyState(
                title: t(.searchStateEmptyTitle),
                message: t(.searchStateEmptyMessage),
                systemImage: "rectangle.stack.badge.minus"
            )
            .frame(maxWidth: .infinity, minHeight: 420)
        case .failed(let message):
            if let error = viewModel.lastError {
                ErrorCard(title: t(.searchStateErrorTitle), error: error) {
                    Task { await viewModel.retryLastSearch() }
                }
            } else {
                ErrorState(title: t(.searchStateErrorTitle), message: message)
            }
        case .loaded:
            resultsContent
        }
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            mediaSection(t(.searchSectionTopMatches), items: viewModel.results.topMatches)
            mediaSection(t(.searchSectionMovies), items: viewModel.results.movies)
            mediaSection(t(.searchSectionSeries), items: viewModel.results.series)
            torrentReleaseSection
        }
    }

    private func mediaSection(_ title: String, items: [SearchMediaResult]) -> some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(title)
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            if items.isEmpty {
                EmptyInlineRow(title: title)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: CFSpacing.md) {
                        ForEach(items) { item in
                            PosterCard(
                                model: CFMediaCardModel(
                                    id: item.id,
                                    title: item.title,
                                    metadata: item.metadata,
                                    badge: item.quality,
                                    artworkURL: item.artworkURL
                                )
                            ) {
                                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                            }
                            .frame(width: 190)
                        }
                    }
                    .padding(.vertical, CFSpacing.xs)
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var torrentReleaseSection: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            Text(t(.searchSectionReleases))
                .font(CFTypography.sectionTitle)
                .foregroundStyle(CFColors.textPrimary)

            if viewModel.results.torrentReleases.isEmpty {
                EmptyInlineRow(title: t(.searchSectionReleases))
            } else {
                LazyVStack(spacing: CFSpacing.md) {
                    ForEach(viewModel.results.torrentReleases) { release in
                        TorrentReleaseRow(
                            release: release,
                            seedersText: L10n.format(
                                .searchReleaseSeedersFormat,
                                language: selectedLanguage,
                                release.seeders,
                                release.leechers
                            ),
                            languagesText: L10n.format(
                                .searchReleaseLanguagesFormat,
                                language: selectedLanguage,
                                release.audioLanguages.joined(separator: ", "),
                                release.subtitleLanguages.joined(separator: ", ")
                            ),
                            playTitle: t(.searchActionPlay),
                            addTitle: t(.searchActionAddLibrary),
                            onOpen: {
                                navigationCoordinator.navigate(to: .mediaDetail(id: release.mediaID))
                            },
                            onPlay: {
                                navigationCoordinator.navigate(to: .player(mediaID: release.mediaID))
                            },
                            onAdd: {
                                navigationCoordinator.navigate(to: .mediaDetail(id: release.mediaID))
                            }
                        )
                    }
                }
            }
        }
    }

    private func qualityToggle(_ quality: ReleaseQuality, title: String) -> some View {
        FilterToggleButton(
            title: title,
            isSelected: viewModel.filters.qualities.contains(quality)
        ) {
            if viewModel.filters.qualities.contains(quality) {
                viewModel.filters.qualities.remove(quality)
            } else {
                viewModel.filters.qualities.insert(quality)
            }
            viewModel.refreshWithCurrentFilters()
        }
    }

    private var hdrToggle: some View {
        FilterToggleButton(title: t(.searchFilterHDR), isSelected: viewModel.filters.requiresHDR) {
            viewModel.filters.requiresHDR.toggle()
            viewModel.refreshWithCurrentFilters()
        }
    }

    private var selectedLanguage: AppLanguage {
        languageSettingsStore.selectedLanguage
    }

    private func sortTitle(_ option: SearchSortOption) -> String {
        switch option {
        case .best:
            "Best"
        case .seeders:
            "Seeders"
        case .quality:
            "Quality"
        case .size:
            "Size"
        case .date:
            "Date"
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }
}

private struct FilterToggleButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(isSelected ? CFColors.textPrimary : CFColors.textSecondary)
                .padding(.horizontal, CFSpacing.md)
                .frame(height: 30)
                .background(
                    Capsule()
                        .fill(isSelected ? CFColors.activeFill : CFColors.elevatedFill)
                        .overlay(Capsule().stroke(isSelected ? CFColors.focusRing.opacity(0.52) : CFColors.separator, lineWidth: CFSeparators.width))
                )
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Capsule()
                            .fill(CFColors.horizontalGradient)
                            .frame(width: 32, height: 2)
                            .padding(.bottom, 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .cfFocusRing(cornerRadius: CFRadius.pill)
    }
}

private struct SearchFilterMenu: View {
    let title: String
    let selection: String
    let options: [String?]
    let emptyTitle: String
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                Button(options[index] ?? emptyTitle) {
                    onSelect(options[index])
                }
            }
        } label: {
            HStack(spacing: CFSpacing.xs) {
                Text(title)
                    .foregroundStyle(CFColors.textMuted)
                Text(selection)
                    .foregroundStyle(CFColors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CFColors.textMuted)
            }
            .font(CFTypography.caption)
            .padding(.horizontal, CFSpacing.md)
            .frame(height: 30)
            .background(
                Capsule()
                    .fill(CFColors.elevatedFill)
                    .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
            )
        }
        .menuStyle(.borderlessButton)
    }
}

private struct TorrentReleaseRow: View {
    let release: SearchTorrentRelease
    let seedersText: String
    let languagesText: String
    let playTitle: String
    let addTitle: String
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onAdd: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: CFSpacing.lg) {
                VStack(alignment: .leading, spacing: CFSpacing.sm) {
                    HStack(spacing: CFSpacing.sm) {
                        Text(release.title)
                            .font(CFTypography.bodyEmphasis)
                            .foregroundStyle(CFColors.textPrimary)
                            .lineLimit(1)

                        QualityBadge(release.qualityLabel)
                        SourceBadge(release.source)
                    }

                    Text("\(release.mediaTitle) · \(release.mediaYear) · \(release.sizeLabel)")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                        .lineLimit(1)

                    Text(languagesText)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: CFSpacing.lg)

                SeedersBadge(release.seeders)

                Text(seedersText)
                    .font(CFTypography.compactNumber)
                    .foregroundStyle(CFColors.textSecondary)
                    .frame(width: 170, alignment: .leading)

                HStack(spacing: CFSpacing.sm) {
                    IconButton(systemImage: "play.fill", accessibilityLabel: playTitle, action: onPlay)
                    IconButton(systemImage: "plus", accessibilityLabel: addTitle, action: onAdd)
                }
            }
            .padding(CFSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(isHovering ? CFColors.hoverFill : CFColors.elevatedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .stroke(isHovering ? CFColors.focusRing.opacity(0.40) : CFColors.separator, lineWidth: CFSeparators.width)
                    )
            )
            .overlay(alignment: .bottomLeading) {
                if isHovering {
                    Capsule()
                        .fill(CFColors.horizontalGradient)
                        .frame(width: 96, height: 2)
                        .padding(.leading, CFSpacing.lg)
                        .padding(.bottom, CFSpacing.sm)
                }
            }
            .scaleEffect(isHovering ? 1.006 : 1)
            .animation(CFMotion.spring, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(playTitle, systemImage: "play.fill", action: onPlay)
            Button(addTitle, systemImage: "plus", action: onAdd)
            Button("Open Details", systemImage: "info.circle", action: onOpen)
        }
        .help(release.rankingExplanation.isEmpty ? release.title : release.rankingExplanation)
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }
}

private struct SearchLoadingView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            LoadingSkeleton(height: 24, cornerRadius: CFRadius.component)
                .frame(width: 240)
                .accessibilityLabel(title)

            ForEach(0..<5, id: \.self) { _ in
                LoadingSkeleton(height: 86, cornerRadius: CFRadius.panel)
            }
        }
    }
}

private struct EmptyInlineRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(CFTypography.caption)
            .foregroundStyle(CFColors.textMuted)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(CFColors.elevatedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width)
                    )
            )
    }
}
