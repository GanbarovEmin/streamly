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
            VStack(alignment: .leading, spacing: CFSpacing.lg) {
                header
                recentSearchesBar
                suggestionsPanel
                moodDiscoveryBar
                filterBar
                stateContent
            }
            .cfSectionPadding()
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

                    SearchFilterMenu(
                        title: t(.searchFilterCodec),
                        selection: viewModel.filters.codec?.rawValue ?? t(.searchFilterAll),
                        options: [nil] + viewModel.availableCodecs.map { Optional.some($0.rawValue) },
                        emptyTitle: t(.searchFilterAll)
                    ) { value in
                        viewModel.filters.codec = value.flatMap(VideoCodec.init(rawValue:))
                        viewModel.refreshWithCurrentFilters()
                    }

                    SearchFilterMenu(
                        title: t(.searchFilterMinRating),
                        selection: viewModel.filters.minimumRating.map { String(format: "%.1f+", $0) } ?? t(.searchFilterAll),
                        options: [nil, "6.0+", "7.0+", "8.0+"],
                        emptyTitle: t(.searchFilterAll)
                    ) { value in
                        viewModel.filters.minimumRating = value.flatMap { Double($0.replacingOccurrences(of: "+", with: "")) }
                        viewModel.refreshWithCurrentFilters()
                    }

                    Menu {
                        ForEach(sizeFilterOptions.indices, id: \.self) { index in
                            Button(sizeFilterOptions[index].title) {
                                applySizeFilter(sizeFilterOptions[index])
                            }
                        }
                    } label: {
                        HStack(spacing: CFSpacing.xs) {
                            Text(t(.searchFilterSize))
                                .foregroundStyle(CFColors.textMuted)
                            Text(sizeFilterSelection)
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
                                .fill(CFColors.panelFill)
                                .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
                        )
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
        .padding(CFSpacing.lg)
        .cfPanelBackground(fill: CFColors.panelFill)
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(CFColors.horizontalGradient)
                .frame(width: 78, height: 2)
                .padding(.leading, CFSpacing.lg)
        }
    }

    @ViewBuilder
    private var recentSearchesBar: some View {
        if !viewModel.recentSearches.isEmpty {
            HStack(spacing: CFSpacing.sm) {
                Text(t(.searchRecent))
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)

                ScrollView(.horizontal) {
                    HStack(spacing: CFSpacing.xs) {
                        ForEach(viewModel.recentSearches, id: \.self) { query in
                            Button {
                                Task { await viewModel.runRecentSearch(query) }
                            } label: {
                                Text(query)
                                    .font(CFTypography.caption)
                                    .foregroundStyle(CFColors.textPrimary)
                                    .padding(.horizontal, CFSpacing.md)
                                    .frame(height: 28)
                                    .background(
                                        Capsule()
                                            .fill(CFColors.panelFill)
                                            .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Button(t(.searchClear)) {
                    viewModel.clearRecentSearches()
                }
                .font(CFTypography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(CFColors.textMuted)
            }
        }
    }

    @ViewBuilder
    private var suggestionsPanel: some View {
        if !viewModel.searchSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: CFSpacing.md) {
                Text(t(.searchSuggestions).uppercased())
                    .font(CFTypography.overline)
                    .tracking(1.2)
                    .foregroundStyle(CFColors.textMuted)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: CFSpacing.sm)],
                    alignment: .leading,
                    spacing: CFSpacing.sm
                ) {
                    ForEach(viewModel.searchSuggestions.prefix(12)) { suggestion in
                        Button {
                            Task { await viewModel.selectSuggestion(suggestion) }
                        } label: {
                            HStack(spacing: CFSpacing.sm) {
                                Image(systemName: suggestionIcon(suggestion))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CFColors.accentPrimary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestionTitle(suggestion))
                                        .font(CFTypography.caption)
                                        .foregroundStyle(CFColors.textPrimary)
                                        .lineLimit(1)

                                    Text(suggestionSubtitle(suggestion))
                                        .font(CFTypography.caption)
                                        .foregroundStyle(CFColors.textMuted)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: CFSpacing.xs)
                            }
                            .padding(.horizontal, CFSpacing.md)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                    .fill(CFColors.panelFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                                            .stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .help(suggestionSubtitle(suggestion))
                    }
                }
            }
            .padding(CFSpacing.lg)
            .cfPanelBackground(fill: CFColors.panelFill.opacity(0.72))
        }
    }

    @ViewBuilder
    private var moodDiscoveryBar: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            Text("What to Watch Today?".uppercased())
                .font(CFTypography.overline)
                .tracking(1.2)
                .foregroundStyle(CFColors.textMuted)

            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.xs) {
                    ForEach(viewModel.moodFilters) { filter in
                        Button {
                            Task { await viewModel.applyMoodFilter(filter) }
                        } label: {
                            Label(filter.title, systemImage: moodIcon(filter))
                                .font(CFTypography.caption)
                                .foregroundStyle(CFColors.textPrimary)
                                .padding(.horizontal, CFSpacing.md)
                                .frame(height: 32)
                                .background(
                                    Capsule()
                                        .fill(CFColors.panelFill)
                                        .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .idle:
            EmptyState(
                title: t(.searchStateIdleTitle),
                message: t(.searchStateIdleMessage),
                systemImage: "magnifyingglass",
                actionTitle: t(.searchStateIdleAction),
                actionSystemImage: "magnifyingglass"
            ) {
                navigationCoordinator.focusSearchField()
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        case .loading:
            SearchLoadingView(title: t(.searchStateLoading))
        case .empty:
            EmptyState(
                title: t(.searchStateEmptyTitle),
                message: t(.searchStateEmptyMessage),
                systemImage: "rectangle.stack.badge.minus",
                actionTitle: t(.searchStateEmptyAction),
                actionSystemImage: "line.3.horizontal.decrease.circle"
            ) {
                viewModel.filters = SearchFilters()
                viewModel.refreshWithCurrentFilters()
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        case .failed:
            if let error = viewModel.lastError {
                ErrorState(
                    title: t(.searchStateErrorTitle),
                    message: t(.searchStateErrorMessage),
                    recoverySuggestion: error.recoverySuggestion,
                    actionTitle: t(.commonRetry)
                ) {
                    Task { await viewModel.retryLastSearch() }
                }
            } else {
                ErrorState(
                    title: t(.searchStateErrorTitle),
                    message: t(.searchStateErrorMessage),
                    recoverySuggestion: t(.searchStateErrorRecovery),
                    actionTitle: t(.commonRetry)
                ) {
                    Task { await viewModel.retryLastSearch() }
                }
            }
        case .loaded:
            resultsContent
        }
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: CFSpacing.xl) {
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
                                ),
                                action: {
                                    navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
                                },
                                menuActions: searchCardMenuActions
                            )
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

    private var searchCardMenuActions: CFMediaCardMenuActions {
        CFMediaCardMenuActions(
            availability: CFMediaCardMenuAvailability(
                canHide: false,
                canClearProgress: false,
                canTuneRecommendations: false
            ),
            watch: { item in
                navigationCoordinator.navigate(to: .mediaDetail(id: item.id))
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
                            seedersHelp: t(.tooltipSeeders),
                            rankingHelp: t(.tooltipRankingScore),
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
                            healthText: releaseHealthText(release.releaseHealth),
                            playTitle: t(.searchActionPlay),
                            addTitle: t(.searchActionAddLibrary),
                            onOpen: {
                                navigationCoordinator.navigate(to: .mediaDetail(id: release.mediaID))
                            },
                            onPlay: {
                                navigationCoordinator.navigate(to: .player(
                                    mediaID: release.mediaID,
                                    release: release.torrentRelease,
                                    fallbackReleases: viewModel.results.torrentReleases
                                        .filter { $0.mediaID == release.mediaID }
                                        .map(\.torrentRelease),
                                    selectionContext: PlaybackSelectionContext(
                                        mediaID: release.mediaID,
                                        displayTitle: release.mediaTitle,
                                        mediaKind: release.mediaKind == .series ? .series : .movie
                                    )
                                ))
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

    private var sizeFilterOptions: [(title: String, minimum: Int64?, maximum: Int64?)] {
        [
            (t(.searchFilterSizeAny), nil, nil),
            (t(.searchFilterSizeUnder8), nil, 8_000_000_000),
            (t(.searchFilterSize8To25), 8_000_000_000, 25_000_000_000),
            (t(.searchFilterSize25To50), 25_000_000_000, 50_000_000_000),
            (t(.searchFilterSizeOver50), 50_000_000_000, nil)
        ]
    }

    private var sizeFilterSelection: String {
        sizeFilterOptions.first {
            $0.minimum == viewModel.filters.minimumSizeBytes && $0.maximum == viewModel.filters.maximumSizeBytes
        }?.title ?? t(.searchFilterSize)
    }

    private func applySizeFilter(_ option: (title: String, minimum: Int64?, maximum: Int64?)) {
        viewModel.filters.minimumSizeBytes = option.minimum
        viewModel.filters.maximumSizeBytes = option.maximum
        viewModel.refreshWithCurrentFilters()
    }

    private func sortTitle(_ option: SearchSortOption) -> String {
        switch option {
        case .bestMatch:
            t(.searchSortBestMatch)
        case .bestQuality:
            t(.searchSortBestQuality)
        case .mostSeeders:
            t(.searchSortMostSeeders)
        case .smallestSize:
            t(.searchSortSmallestSize)
        case .newest:
            t(.searchSortNewest)
        case .preferredLanguage:
            t(.searchSortPreferredLanguage)
        case .rating:
            t(.searchSortRating)
        }
    }

    private func suggestionTitle(_ suggestion: SearchSuggestion) -> String {
        guard let quickFilter = suggestion.quickFilter else {
            return suggestion.title
        }

        switch quickFilter {
        case .movies:
            return t(.searchQuickFilterMovies)
        case .series:
            return t(.searchQuickFilterSeries)
        case .ultraHD:
            return t(.searchQuickFilter4K)
        case .russianAudio:
            return t(.searchQuickFilterRussianAudio)
        }
    }

    private func suggestionSubtitle(_ suggestion: SearchSuggestion) -> String {
        if suggestion.quickFilter != nil {
            return t(.searchSuggestionQuickFilter)
        }

        switch suggestion.kind {
        case .recent:
            return t(.searchSuggestionRecent)
        case .trending:
            return t(.searchSuggestionTrending)
        case .title:
            return t(.searchSuggestionTitle)
        case .originalTitle:
            return t(.searchSuggestionOriginalTitle)
        case .localizedTitle:
            return t(.searchSuggestionLocalizedTitle)
        case .actor:
            return t(.searchSuggestionActor)
        case .director:
            return t(.searchSuggestionDirector)
        case .genre:
            return t(.searchSuggestionGenre)
        case .year:
            return t(.searchSuggestionYear)
        case .typoCorrection:
            return t(.searchSuggestionTypo)
        case .quickFilter:
            return t(.searchSuggestionQuickFilter)
        }
    }

    private func suggestionIcon(_ suggestion: SearchSuggestion) -> String {
        if let quickFilter = suggestion.quickFilter {
            switch quickFilter {
            case .movies:
                return "film"
            case .series:
                return "rectangle.stack"
            case .ultraHD:
                return "4k.tv"
            case .russianAudio:
                return "speaker.wave.2"
            }
        }

        switch suggestion.kind {
        case .recent:
            return "clock"
        case .trending:
            return "chart.line.uptrend.xyaxis"
        case .title, .originalTitle, .localizedTitle:
            return "text.magnifyingglass"
        case .actor:
            return "person"
        case .director:
            return "megaphone"
        case .genre:
            return "tag"
        case .year:
            return "calendar"
        case .typoCorrection:
            return "wand.and.stars"
        case .quickFilter:
            return "line.3.horizontal.decrease.circle"
        }
    }

    private func moodIcon(_ filter: MoodDiscoveryFilter) -> String {
        switch filter {
        case .lightEvening:
            "moon"
        case .epic:
            "sparkles"
        case .shortMovie, .runtime30To60, .under90Minutes:
            "clock"
        case .backgroundSeries:
            "rectangle.on.rectangle"
        case .highRated:
            "star"
        case .new:
            "calendar"
        case .fourKHDR:
            "4k.tv"
        case .drama:
            "theatermasks"
        case .action:
            "bolt"
        case .comedy:
            "face.smiling"
        case .longWeekendPicks:
            "sofa"
        }
    }

    private func t(_ key: L10nKey) -> String {
        L10n.string(key, language: selectedLanguage)
    }

    private func releaseHealthText(_ health: ReleaseHealth) -> String {
        switch health {
        case .excellent:
            return t(.releaseHealthExcellent)
        case .good:
            return t(.releaseHealthGood)
        case .weak:
            return t(.releaseHealthWeak)
        case .noSeeders:
            return t(.releaseHealthNoSeeders)
        case .unknown:
            return t(.releaseHealthUnknown)
        }
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
                    .fill(isSelected ? CFColors.activeFill : CFColors.panelFill)
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
                    .fill(CFColors.panelFill)
                    .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
            )
        }
        .menuStyle(.borderlessButton)
    }
}

private struct TorrentReleaseRow: View {
    let release: SearchTorrentRelease
    let seedersHelp: String
    let rankingHelp: String
    let seedersText: String
    let languagesText: String
    let healthText: String
    let playTitle: String
    let addTitle: String
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onAdd: () -> Void

    @Environment(\.cfReduceMotion) private var reduceMotion
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
                        HealthBadge(healthText, tone: healthTone(release.releaseHealth))
                    }

                    Text("\(release.mediaTitle) · \(release.mediaYear) · \(release.sizeLabel)")
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                        .lineLimit(1)

                    Text(release.comparisonSummary)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                        .lineLimit(1)

                    Text(languagesText)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: CFSpacing.lg)

                SeedersBadge(release.seeders)
                    .help(seedersHelp)

                VStack(alignment: .leading, spacing: 3) {
                    Text(release.codecLabel)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textPrimary)
                    Text(release.hdrLabel)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
                .frame(width: 92, alignment: .leading)

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
                    .fill(isHovering ? CFColors.hoverFill : CFColors.panelFill)
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
            .scaleEffect(reduceMotion ? 1 : (isHovering ? 1.006 : 1))
            .cfAnimation(CFMotion.spring, value: isHovering, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(playTitle)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(playTitle, systemImage: "play.fill", action: onPlay)
            Button(addTitle, systemImage: "plus", action: onAdd)
            Button("Open Details", systemImage: "info.circle", action: onOpen)
        }
        .help(release.rankingExplanation.isEmpty ? rankingHelp : "\(release.rankingExplanation)\n\(rankingHelp)")
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }

    private var accessibilityLabel: String {
        "\(release.title), \(release.mediaTitle), \(release.qualityLabel), \(healthText), \(release.sizeLabel), \(seedersText)"
    }

    private func healthTone(_ health: ReleaseHealth) -> CFBadgeTone {
        switch health {
        case .excellent, .good:
            return .success
        case .weak, .unknown:
            return .warning
        case .noSeeders:
            return .error
        }
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
                    .fill(CFColors.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .stroke(CFColors.separatorSubtle, lineWidth: CFSeparators.width)
                    )
            )
    }
}
