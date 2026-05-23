import AppKit
import CineFlowLocalization
import SwiftUI

public typealias CFImageDataLoader = @Sendable (URL) async throws -> Data

public struct CFMediaCardModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let metadata: String
    public let badge: String?
    public let progress: Double?
    public let accentIndex: Int
    public let artworkURL: URL?
    public let genres: [String]

    public init(
        id: String,
        title: String,
        metadata: String,
        badge: String? = nil,
        progress: Double? = nil,
        accentIndex: Int = 0,
        artworkURL: URL? = nil,
        genres: [String] = []
    ) {
        self.id = id
        self.title = title
        self.metadata = metadata
        self.badge = badge
        self.progress = progress.map { min(max($0, 0), 1) }
        self.accentIndex = accentIndex
        self.artworkURL = artworkURL
        self.genres = genres
    }
}

public enum MediaCardStyle: Equatable, Sendable {
    case poster
    case landscape
}

public struct CFMediaCardMenuAvailability: Equatable, Sendable {
    public var canWatch: Bool
    public var canOpenDetails: Bool
    public var canAddToLibrary: Bool
    public var canAddToWatchlist: Bool
    public var canAddToList: Bool
    public var canRate: Bool
    public var canHide: Bool
    public var canFixMetadata: Bool
    public var canFindBestRelease: Bool
    public var canClearProgress: Bool
    public var canTuneRecommendations: Bool

    public init(
        canWatch: Bool = true,
        canOpenDetails: Bool = true,
        canAddToLibrary: Bool = true,
        canAddToWatchlist: Bool = true,
        canAddToList: Bool = true,
        canRate: Bool = true,
        canHide: Bool = true,
        canFixMetadata: Bool = true,
        canFindBestRelease: Bool = true,
        canClearProgress: Bool = false,
        canTuneRecommendations: Bool = true
    ) {
        self.canWatch = canWatch
        self.canOpenDetails = canOpenDetails
        self.canAddToLibrary = canAddToLibrary
        self.canAddToWatchlist = canAddToWatchlist
        self.canAddToList = canAddToList
        self.canRate = canRate
        self.canHide = canHide
        self.canFixMetadata = canFixMetadata
        self.canFindBestRelease = canFindBestRelease
        self.canClearProgress = canClearProgress
        self.canTuneRecommendations = canTuneRecommendations
    }

    public static let all = CFMediaCardMenuAvailability(canClearProgress: true)
}

public struct CFMediaCardMenuActions {
    public var availability: CFMediaCardMenuAvailability
    public var watch: (CFMediaCardModel) -> Void
    public var details: (CFMediaCardModel) -> Void
    public var library: (CFMediaCardModel) -> Void
    public var watchlist: (CFMediaCardModel) -> Void
    public var list: (CFMediaCardModel) -> Void
    public var rate: (CFMediaCardModel) -> Void
    public var hideTitle: (CFMediaCardModel) -> Void
    public var fixMetadata: (CFMediaCardModel) -> Void
    public var findBestRelease: (CFMediaCardModel) -> Void
    public var clearProgress: (CFMediaCardModel) -> Void
    public var notInterested: (CFMediaCardModel) -> Void
    public var removeFromRecommendations: (CFMediaCardModel) -> Void
    public var showLessOfGenre: (CFMediaCardModel) -> Void
    public var showMoreOfGenre: (CFMediaCardModel) -> Void

    public init(
        availability: CFMediaCardMenuAvailability = .all,
        watch: @escaping (CFMediaCardModel) -> Void = { _ in },
        details: @escaping (CFMediaCardModel) -> Void = { _ in },
        library: @escaping (CFMediaCardModel) -> Void = { _ in },
        watchlist: @escaping (CFMediaCardModel) -> Void = { _ in },
        list: @escaping (CFMediaCardModel) -> Void = { _ in },
        rate: @escaping (CFMediaCardModel) -> Void = { _ in },
        hideTitle: @escaping (CFMediaCardModel) -> Void = { _ in },
        fixMetadata: @escaping (CFMediaCardModel) -> Void = { _ in },
        findBestRelease: @escaping (CFMediaCardModel) -> Void = { _ in },
        clearProgress: @escaping (CFMediaCardModel) -> Void = { _ in },
        notInterested: @escaping (CFMediaCardModel) -> Void = { _ in },
        removeFromRecommendations: @escaping (CFMediaCardModel) -> Void = { _ in },
        showLessOfGenre: @escaping (CFMediaCardModel) -> Void = { _ in },
        showMoreOfGenre: @escaping (CFMediaCardModel) -> Void = { _ in }
    ) {
        self.availability = availability
        self.watch = watch
        self.details = details
        self.library = library
        self.watchlist = watchlist
        self.list = list
        self.rate = rate
        self.hideTitle = hideTitle
        self.fixMetadata = fixMetadata
        self.findBestRelease = findBestRelease
        self.clearProgress = clearProgress
        self.notInterested = notInterested
        self.removeFromRecommendations = removeFromRecommendations
        self.showLessOfGenre = showLessOfGenre
        self.showMoreOfGenre = showMoreOfGenre
    }
}

private enum CFGeneratedArtworkStyle {
    case poster
    case landscape
}

private struct CFGeneratedArtworkFallback: View {
    let model: CFMediaCardModel
    let style: CFGeneratedArtworkStyle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: style == .poster ? 8 : 4) {
                Spacer(minLength: 0)
                Text(initials)
                    .font(.system(size: style == .poster ? 52 : 34, weight: .black, design: .rounded))
                    .foregroundStyle(CFColors.textPrimary.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(model.title)
                    .font(style == .poster ? CFTypography.metadata : CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
                    .lineLimit(style == .poster ? 3 : 2)
                    .minimumScaleFactor(0.74)
            }
            .padding(style == .poster ? CFSpacing.md : CFSpacing.sm)

            Image(systemName: style == .poster ? "film.stack.fill" : "play.rectangle.fill")
                .font(.system(size: style == .poster ? 22 : 18, weight: .semibold))
                .foregroundStyle(CFColors.textPrimary.opacity(0.20))
                .padding(style == .poster ? CFSpacing.md : CFSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var initials: String {
        let letters = model.title
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
            .compactMap(\.first)
            .map { String($0) }
            .joined()
        return letters.isEmpty ? "CF" : letters.uppercased()
    }

    private var gradientColors: [Color] {
        switch model.accentIndex % 3 {
        case 0:
            return [CFColors.backgroundTertiary, CFColors.accentPrimary.opacity(0.34), CFColors.backgroundSecondary]
        case 1:
            return [CFColors.backgroundSecondary, CFColors.accentSecondary.opacity(0.30), CFColors.surfaceOverlay]
        default:
            return [CFColors.surfaceOverlay, CFColors.accentTertiary.opacity(0.22), CFColors.backgroundTertiary]
        }
    }
}

public struct PosterCard: View {
    private let model: CFMediaCardModel
    private let imageDataLoader: CFImageDataLoader?
    private let menuActions: CFMediaCardMenuActions
    private let action: () -> Void

    @Environment(\.cfReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(
        model: CFMediaCardModel,
        action: @escaping () -> Void = {},
        menuActions: CFMediaCardMenuActions = CFMediaCardMenuActions(),
        imageDataLoader: CFImageDataLoader? = nil
    ) {
        self.model = model
        self.imageDataLoader = imageDataLoader
        self.menuActions = menuActions
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    posterSurface
                        .frame(height: 236)

                    if isHovering {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(CFColors.textPrimary)
                            .cfShadow(.icon)
                            .padding(CFSpacing.md)
                            .transition(.scale.combined(with: .opacity))
                    }

                    if let badge = model.badge {
                        VStack {
                            HStack {
                                Spacer()
                                QualityBadge(badge)
                            }
                            Spacer()
                        }
                        .padding(CFSpacing.md)
                    }

                    if isHovering {
                        RoundedRectangle(cornerRadius: CFRadius.poster, style: .continuous)
                            .fill(CFColors.backgroundPrimary.opacity(0.18))
                    }

                    if let progress = model.progress {
                        ProgressBar(value: progress)
                            .padding(.horizontal, CFSpacing.sm)
                            .padding(.bottom, CFSpacing.sm)
                    } else if isHovering {
                        Capsule()
                            .fill(CFColors.horizontalGradient)
                            .frame(width: 74, height: 3)
                            .padding(.horizontal, CFSpacing.sm)
                            .padding(.bottom, CFSpacing.sm)
                            .transition(.opacity)
                    }
                }

                Text(model.title)
                    .font(CFTypography.bodyEmphasis)
                    .lineLimit(1)
                    .foregroundStyle(CFColors.textPrimary)

                Text(model.metadata)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textMuted)
                    .lineLimit(1)
            }
            .frame(height: 286, alignment: .top)
            .scaleEffect(reduceMotion ? 1 : (isHovering ? 1.012 : 1))
            .cfAnimation(CFMotion.quick, value: isHovering, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.string(.accessibilityCardOpenDetails))
        .onHover { isHovering = $0 }
        .contextMenu { cardContextMenu }
        .cfFocusRing()
    }

    private var posterSurface: some View {
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
                    .stroke(isHovering ? CFColors.focusRing : CFColors.separator, lineWidth: CFSeparators.width)
            )
            .overlay {
                if let artworkURL = model.artworkURL {
                    CFCachedAsyncImage(url: artworkURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                        .clipShape(RoundedRectangle(cornerRadius: CFRadius.poster, style: .continuous))
                } else {
                    CFGeneratedArtworkFallback(model: model, style: .poster)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.poster, style: .continuous))
            .cfShadow(.none)
    }

    private var accessibilityLabel: String {
        [model.title, model.metadata, model.badge].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: ", ")
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button("Watch", systemImage: "play.fill") { menuActions.watch(model) }
            .disabled(!menuActions.availability.canWatch)
        Button("Details", systemImage: "info.circle") { menuActions.details(model) }
            .disabled(!menuActions.availability.canOpenDetails)
        Divider()
        Button("Library", systemImage: "books.vertical") { menuActions.library(model) }
            .disabled(!menuActions.availability.canAddToLibrary)
        Button("Watchlist", systemImage: "bookmark") { menuActions.watchlist(model) }
            .disabled(!menuActions.availability.canAddToWatchlist)
        Button("Add to List", systemImage: "text.badge.plus") { menuActions.list(model) }
            .disabled(!menuActions.availability.canAddToList)
        Button("Rate", systemImage: "star") { menuActions.rate(model) }
            .disabled(!menuActions.availability.canRate)
        Divider()
        Button("Hide", systemImage: "eye.slash") { menuActions.hideTitle(model) }
            .disabled(!menuActions.availability.canHide)
        Button("Fix Metadata", systemImage: "wand.and.stars") { menuActions.fixMetadata(model) }
            .disabled(!menuActions.availability.canFixMetadata)
        Button("Find Better Release", systemImage: "arrow.triangle.2.circlepath") { menuActions.findBestRelease(model) }
            .disabled(!menuActions.availability.canFindBestRelease)
        Button(role: .destructive) {
            menuActions.clearProgress(model)
        } label: {
            Label("Clear Progress", systemImage: "clock.arrow.circlepath")
        }
        .disabled(!menuActions.availability.canClearProgress || model.progress == nil)
        Divider()
        Button("Not interested", systemImage: "hand.thumbsdown") { menuActions.notInterested(model) }
            .disabled(!menuActions.availability.canTuneRecommendations)
        Button("Remove from recommendations", systemImage: "xmark.circle") { menuActions.removeFromRecommendations(model) }
            .disabled(!menuActions.availability.canTuneRecommendations)
        if let primaryGenre = model.genres.first {
            Divider()
            Button("Show less \(primaryGenre)", systemImage: "minus.circle") { menuActions.showLessOfGenre(model) }
                .disabled(!menuActions.availability.canTuneRecommendations)
            Button("Show more \(primaryGenre)", systemImage: "plus.circle") { menuActions.showMoreOfGenre(model) }
                .disabled(!menuActions.availability.canTuneRecommendations)
        }
    }
}

public struct LandscapeCard: View {
    private let model: CFMediaCardModel
    private let imageDataLoader: CFImageDataLoader?
    private let menuActions: CFMediaCardMenuActions
    private let action: () -> Void

    @Environment(\.cfReduceMotion) private var reduceMotion
    @State private var isHovering = false

    public init(
        model: CFMediaCardModel,
        action: @escaping () -> Void = {},
        menuActions: CFMediaCardMenuActions = CFMediaCardMenuActions(),
        imageDataLoader: CFImageDataLoader? = nil
    ) {
        self.model = model
        self.imageDataLoader = imageDataLoader
        self.menuActions = menuActions
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: CFSpacing.lg) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    CFColors.backgroundTertiary,
                                    model.accentIndex.isMultiple(of: 2) ? CFColors.surfaceOverlay.opacity(0.84) : CFColors.backgroundSecondary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            if let artworkURL = model.artworkURL {
                                CFCachedAsyncImage(url: artworkURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                                    .clipShape(RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
                            } else {
                                CFGeneratedArtworkFallback(model: model, style: .landscape)
                            }
                        }
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(CFColors.textPrimary.opacity(model.artworkURL == nil ? 0.34 : 0.92))
                                .cfShadow(.icon)
                        }
                        .overlay(alignment: .bottomLeading) {
                            if isHovering {
                                Capsule()
                                    .fill(CFColors.horizontalGradient)
                                    .frame(width: 72, height: 3)
                                    .padding(CFSpacing.sm)
                            }
                        }

                    if let progress = model.progress {
                        ProgressBar(value: progress)
                            .padding(.horizontal, CFSpacing.sm)
                            .padding(.bottom, CFSpacing.sm)
                    }
                }
                .frame(width: 210, height: 122)

                VStack(alignment: .leading, spacing: CFSpacing.xs) {
                    Text(model.title)
                        .font(CFTypography.bodyEmphasis)
                        .foregroundStyle(CFColors.textPrimary)
                        .lineLimit(1)
                    Text(model.metadata)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(CFSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                    .fill(isHovering ? CFColors.hoverFill : CFColors.elevatedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                            .stroke(isHovering ? CFColors.focusRing.opacity(0.40) : CFColors.separator, lineWidth: CFSeparators.width)
                    )
            )
            .frame(height: 154)
            .scaleEffect(reduceMotion ? 1 : (isHovering ? 1.008 : 1))
            .cfAnimation(CFMotion.quick, value: isHovering, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.string(.accessibilityCardOpenDetails))
        .onHover { isHovering = $0 }
        .contextMenu { cardContextMenu }
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }

    private var accessibilityLabel: String {
        [model.title, model.metadata, model.badge].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: ", ")
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button("Watch", systemImage: "play.fill") { menuActions.watch(model) }
            .disabled(!menuActions.availability.canWatch)
        Button("Details", systemImage: "info.circle") { menuActions.details(model) }
            .disabled(!menuActions.availability.canOpenDetails)
        Divider()
        Button("Library", systemImage: "books.vertical") { menuActions.library(model) }
            .disabled(!menuActions.availability.canAddToLibrary)
        Button("Watchlist", systemImage: "bookmark") { menuActions.watchlist(model) }
            .disabled(!menuActions.availability.canAddToWatchlist)
        Button("Add to List", systemImage: "text.badge.plus") { menuActions.list(model) }
            .disabled(!menuActions.availability.canAddToList)
        Button("Rate", systemImage: "star") { menuActions.rate(model) }
            .disabled(!menuActions.availability.canRate)
        Divider()
        Button("Hide", systemImage: "eye.slash") { menuActions.hideTitle(model) }
            .disabled(!menuActions.availability.canHide)
        Button("Fix Metadata", systemImage: "wand.and.stars") { menuActions.fixMetadata(model) }
            .disabled(!menuActions.availability.canFixMetadata)
        Button("Find Better Release", systemImage: "arrow.triangle.2.circlepath") { menuActions.findBestRelease(model) }
            .disabled(!menuActions.availability.canFindBestRelease)
        Button(role: .destructive) {
            menuActions.clearProgress(model)
        } label: {
            Label("Clear Progress", systemImage: "clock.arrow.circlepath")
        }
        .disabled(!menuActions.availability.canClearProgress || model.progress == nil)
        Divider()
        Button("Not interested", systemImage: "hand.thumbsdown") { menuActions.notInterested(model) }
            .disabled(!menuActions.availability.canTuneRecommendations)
        Button("Remove from recommendations", systemImage: "xmark.circle") { menuActions.removeFromRecommendations(model) }
            .disabled(!menuActions.availability.canTuneRecommendations)
        if let primaryGenre = model.genres.first {
            Divider()
            Button("Show less \(primaryGenre)", systemImage: "minus.circle") { menuActions.showLessOfGenre(model) }
                .disabled(!menuActions.availability.canTuneRecommendations)
            Button("Show more \(primaryGenre)", systemImage: "plus.circle") { menuActions.showMoreOfGenre(model) }
                .disabled(!menuActions.availability.canTuneRecommendations)
        }
    }
}

public struct MediaCarousel: View {
    private let title: String
    private let items: [CFMediaCardModel]
    private let cardStyle: MediaCardStyle
    private let imageDataLoader: CFImageDataLoader?
    private let posterWidth: CGFloat
    private let landscapeWidth: CGFloat
    private let verticalSpacing: CGFloat
    private let menuActions: CFMediaCardMenuActions
    private let dismissAction: ((CFMediaCardModel) -> Void)?
    private let action: (CFMediaCardModel) -> Void
    @State private var pageIndex = 0

    public init(
        title: String,
        items: [CFMediaCardModel],
        cardStyle: MediaCardStyle = .poster,
        posterWidth: CGFloat = 190,
        landscapeWidth: CGFloat = 360,
        verticalSpacing: CGFloat = CFSpacing.md,
        menuActions: CFMediaCardMenuActions = CFMediaCardMenuActions(),
        dismissAction: ((CFMediaCardModel) -> Void)? = nil,
        action: @escaping (CFMediaCardModel) -> Void = { _ in },
        imageDataLoader: CFImageDataLoader? = nil
    ) {
        self.title = title
        self.items = items
        self.cardStyle = cardStyle
        self.posterWidth = posterWidth
        self.landscapeWidth = landscapeWidth
        self.verticalSpacing = verticalSpacing
        self.menuActions = menuActions
        self.dismissAction = dismissAction
        self.imageDataLoader = imageDataLoader
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            HStack(alignment: .center, spacing: CFSpacing.md) {
                Text(title)
                    .font(CFTypography.sectionTitle)
                    .foregroundStyle(CFColors.textPrimary)
            }

            GeometryReader { proxy in
                let metrics = carouselMetrics(for: proxy.size.width)

                ZStack(alignment: .topTrailing) {
                    HStack(spacing: CFSpacing.md) {
                        ForEach(items) { item in
                            card(for: item)
                                .frame(width: metrics.cardWidth)
                        }
                    }
                    .padding(.vertical, CFSpacing.xs)
                    .offset(x: -CGFloat(metrics.leadingIndex) * metrics.step)
                    .frame(width: proxy.size.width, alignment: .leading)
                    .animation(CFMotion.standard, value: metrics.leadingIndex)

                    pageDots(lastPageIndex: metrics.lastPageIndex)
                        .padding(.top, 1)
                        .padding(.trailing, 56)

                    if metrics.canGoBackward {
                        carouselArrow(systemImage: "chevron.left") {
                            pageIndex = max(pageIndex - 1, 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if metrics.canGoForward {
                        carouselArrow(systemImage: "chevron.right") {
                            pageIndex = min(pageIndex + 1, metrics.lastPageIndex)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .clipped()
                .gesture(
                    DragGesture(minimumDistance: 36)
                        .onEnded { value in
                            if value.translation.width < -48, metrics.canGoForward {
                                pageIndex = min(pageIndex + 1, metrics.lastPageIndex)
                            } else if value.translation.width > 48, metrics.canGoBackward {
                                pageIndex = max(pageIndex - 1, 0)
                            }
                        }
                )
                .onChange(of: items.map(\.id).joined(separator: "|")) { _ in
                    pageIndex = 0
                }
                .onChange(of: metrics.lastPageIndex) { lastPageIndex in
                    pageIndex = min(pageIndex, lastPageIndex)
                }
            }
            .frame(height: carouselHeight)
            .focusable(true)
            .accessibilityLabel(title)
            .accessibilityHint(L10n.string(.accessibilityCarouselHint))
            .task(id: prefetchKey) {
                await prefetchArtwork()
            }
        }
    }

    @ViewBuilder
    private func card(for item: CFMediaCardModel) -> some View {
        ZStack(alignment: .topTrailing) {
            switch cardStyle {
            case .poster:
                PosterCard(model: item, action: {
                    action(item)
                }, menuActions: menuActions, imageDataLoader: imageDataLoader)
            case .landscape:
                LandscapeCard(model: item, action: {
                    action(item)
                }, menuActions: menuActions, imageDataLoader: imageDataLoader)
            }

            if let dismissAction {
                Button {
                    dismissAction(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CFColors.textPrimary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(CFColors.backgroundPrimary.opacity(0.78))
                                .overlay(Circle().stroke(CFColors.separator, lineWidth: CFSeparators.width))
                        )
                }
                .buttonStyle(.plain)
                .padding(8)
                .help("Remove from Continue Watching")
                .accessibilityLabel("Remove \(item.title) from Continue Watching")
                .zIndex(2)
            }
        }
    }

    private func pageDots(lastPageIndex: Int) -> some View {
        HStack(spacing: 6) {
            if lastPageIndex > 0 {
                ForEach(0...lastPageIndex, id: \.self) { index in
                    Capsule()
                        .fill(index == min(pageIndex, lastPageIndex) ? CFColors.textPrimary : CFColors.textMuted.opacity(0.40))
                        .frame(width: index == min(pageIndex, lastPageIndex) ? 18 : 12, height: 2)
                        .animation(CFMotion.quick, value: pageIndex)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func carouselArrow(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CFColors.textPrimary)
                .frame(width: 48, height: carouselHeight)
                .background(
                    LinearGradient(
                        colors: [
                            CFColors.backgroundPrimary.opacity(0.02),
                            CFColors.backgroundPrimary.opacity(0.78)
                        ],
                        startPoint: systemImage == "chevron.left" ? .trailing : .leading,
                        endPoint: systemImage == "chevron.left" ? .leading : .trailing
                    )
                )
        }
        .buttonStyle(.plain)
        .help(systemImage == "chevron.left" ? "Previous" : "Next")
        .accessibilityLabel(systemImage == "chevron.left" ? "Previous page" : "Next page")
    }

    private func carouselMetrics(for width: CGFloat) -> CarouselMetrics {
        let cardWidth = resolvedCardWidth
        let step = cardWidth + CFSpacing.md
        let visibleCount = max(1, Int((max(width, cardWidth) + CFSpacing.md) / step))
        let pageSize = max(1, visibleCount)
        let lastPageIndex = max(0, Int(ceil(Double(max(items.count - visibleCount, 0)) / Double(pageSize))))
        let clampedPageIndex = min(pageIndex, lastPageIndex)
        let leadingIndex = min(clampedPageIndex * pageSize, max(items.count - visibleCount, 0))
        return CarouselMetrics(
            cardWidth: cardWidth,
            step: step,
            leadingIndex: leadingIndex,
            lastPageIndex: lastPageIndex,
            canGoBackward: leadingIndex > 0,
            canGoForward: leadingIndex < max(items.count - visibleCount, 0)
        )
    }

    private var resolvedCardWidth: CGFloat {
        switch cardStyle {
        case .poster:
            posterWidth
        case .landscape:
            landscapeWidth
        }
    }

    private var prefetchKey: String {
        items.compactMap { $0.artworkURL?.absoluteString }.prefix(18).joined(separator: "|")
    }

    private var carouselHeight: CGFloat {
        switch cardStyle {
        case .poster:
            302
        case .landscape:
            170
        }
    }

    private func prefetchArtwork() async {
        guard let imageDataLoader else { return }
        let urls = items.compactMap(\.artworkURL).prefix(18)
        for url in urls {
            guard !Task.isCancelled else { return }
            _ = try? await imageDataLoader(url)
        }
    }
}

private struct CarouselMetrics {
    let cardWidth: CGFloat
    let step: CGFloat
    let leadingIndex: Int
    let lastPageIndex: Int
    let canGoBackward: Bool
    let canGoForward: Bool
}

public struct CFCachedAsyncImage: View {
    private enum Phase: Equatable {
        case idle
        case loading
        case loaded(NSImage)
        case failed
    }

    private let url: URL?
    private let contentMode: ContentMode
    private let imageDataLoader: CFImageDataLoader?
    private static let fallbackMemoryCache = NSCache<NSURL, NSData>()

    @State private var phase: Phase = .idle
    @Environment(\.cfReduceMotion) private var reduceMotion

    public init(url: URL?, contentMode: ContentMode = .fill, imageDataLoader: CFImageDataLoader? = nil) {
        self.url = url
        self.contentMode = contentMode
        self.imageDataLoader = imageDataLoader
    }

    public var body: some View {
        ZStack {
            switch phase {
            case .idle, .loading:
                skeleton
            case let .loaded(image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            case .failed:
                errorFallback
            }
        }
        .clipped()
        .cfAnimation(CFMotion.standard, value: phase, reduceMotion: reduceMotion)
        .task(id: url) {
            await load()
        }
    }

    private var skeleton: some View {
        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
            .fill(CFColors.surfaceOverlay)
            .overlay {
                LinearGradient(
                    colors: [
                        .clear,
                        CFColors.textPrimary.opacity(0.08),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .accessibilityLabel(L10n.string(.accessibilityImageLoading))
    }

    private var errorFallback: some View {
        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
            .fill(CFColors.backgroundTertiary)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(CFColors.textMuted)
            }
            .accessibilityLabel(L10n.string(.accessibilityImageUnavailable))
    }

    @MainActor
    private func load() async {
        guard let url else {
            phase = .failed
            return
        }

        phase = .loading

        do {
            let data: Data
            if let imageDataLoader {
                data = try await imageDataLoader(url)
            } else {
                data = try await Self.defaultImageDataLoader(url: url)
            }

            guard let image = NSImage(data: data) else {
                phase = .failed
                return
            }
            phase = .loaded(image)
        } catch {
            phase = .failed
        }
    }

    private static func defaultImageDataLoader(url: URL) async throws -> Data {
        if let cached = fallbackMemoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        fallbackMemoryCache.setObject(data as NSData, forKey: url as NSURL)
        return data
    }
}
