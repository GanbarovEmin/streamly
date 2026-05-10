import AppKit
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

    public init(
        id: String,
        title: String,
        metadata: String,
        badge: String? = nil,
        progress: Double? = nil,
        accentIndex: Int = 0,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.metadata = metadata
        self.badge = badge
        self.progress = progress.map { min(max($0, 0), 1) }
        self.accentIndex = accentIndex
        self.artworkURL = artworkURL
    }
}

public enum MediaCardStyle: Equatable, Sendable {
    case poster
    case landscape
}

public struct PosterCard: View {
    private let model: CFMediaCardModel
    private let imageDataLoader: CFImageDataLoader?
    private let action: () -> Void

    @State private var isHovering = false

    public init(model: CFMediaCardModel, action: @escaping () -> Void = {}, imageDataLoader: CFImageDataLoader? = nil) {
        self.model = model
        self.imageDataLoader = imageDataLoader
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
            }
            .scaleEffect(isHovering ? CFMotion.hoverScale : 1)
            .animation(CFMotion.spring, value: isHovering)
        }
        .buttonStyle(.plain)
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
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CFRadius.poster, style: .continuous))
            .cfShadow(isHovering ? .hover : .none)
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button("Watch", systemImage: "play.fill", action: action)
        Button("Open Details", systemImage: "info.circle", action: action)
        Button("Add to Library", systemImage: "plus", action: action)
    }
}

public struct LandscapeCard: View {
    private let model: CFMediaCardModel
    private let imageDataLoader: CFImageDataLoader?
    private let action: () -> Void

    @State private var isHovering = false

    public init(model: CFMediaCardModel, action: @escaping () -> Void = {}, imageDataLoader: CFImageDataLoader? = nil) {
        self.model = model
        self.imageDataLoader = imageDataLoader
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
                        .overlay(Image(systemName: "play.fill").foregroundStyle(CFColors.textPrimary))
                        .overlay {
                            if let artworkURL = model.artworkURL {
                                CFCachedAsyncImage(url: artworkURL, contentMode: .fill, imageDataLoader: imageDataLoader)
                                    .clipShape(RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous))
                            }
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
                .frame(width: 180, height: 104)

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
            .scaleEffect(isHovering ? CFMotion.hoverScale : 1)
            .animation(CFMotion.spring, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu { cardContextMenu }
        .cfFocusRing(cornerRadius: CFRadius.panel)
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Button("Resume", systemImage: "play.fill", action: action)
        Button("Open Details", systemImage: "info.circle", action: action)
        Button("Remove from Continue Watching", systemImage: "xmark", action: action)
    }
}

public struct MediaCarousel: View {
    private let title: String
    private let items: [CFMediaCardModel]
    private let cardStyle: MediaCardStyle
    private let imageDataLoader: CFImageDataLoader?
    private let action: (CFMediaCardModel) -> Void

    public init(
        title: String,
        items: [CFMediaCardModel],
        cardStyle: MediaCardStyle = .poster,
        action: @escaping (CFMediaCardModel) -> Void = { _ in },
        imageDataLoader: CFImageDataLoader? = nil
    ) {
        self.title = title
        self.items = items
        self.cardStyle = cardStyle
        self.imageDataLoader = imageDataLoader
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(title)
                    .font(CFTypography.sectionTitle)
                    .foregroundStyle(CFColors.textPrimary)

                Capsule()
                    .fill(CFColors.horizontalGradient)
                    .frame(width: 64, height: 2)
            }

            ScrollView(.horizontal) {
                HStack(spacing: CFSpacing.md) {
                    ForEach(items) { item in
                        switch cardStyle {
                        case .poster:
                            PosterCard(model: item, action: {
                                action(item)
                            }, imageDataLoader: imageDataLoader)
                            .frame(width: 190)
                        case .landscape:
                            LandscapeCard(model: item, action: {
                                action(item)
                            }, imageDataLoader: imageDataLoader)
                            .frame(width: 360)
                        }
                    }
                }
                .padding(.vertical, CFSpacing.xs)
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
    }
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

    @State private var phase: Phase = .idle

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
        .animation(CFMotion.standard, value: phase)
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
            .accessibilityLabel("Loading image")
    }

    private var errorFallback: some View {
        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
            .fill(CFColors.backgroundTertiary)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(CFColors.textMuted)
            }
            .accessibilityLabel("Image unavailable")
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
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
