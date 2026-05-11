import SwiftUI

public struct CFGlobalBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            CFColors.backgroundPrimary

            LinearGradient(
                colors: [
                    CFColors.backgroundPrimary,
                    CFColors.backgroundTertiary.opacity(0.56),
                    CFColors.backgroundPrimary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    CFColors.accentPrimary.opacity(0.16),
                    CFColors.accentSecondary.opacity(0.08),
                    .clear
                ],
                center: UnitPoint(x: 0.32, y: 0.02),
                startRadius: 20,
                endRadius: 840
            )

            RadialGradient(
                colors: [
                    CFColors.accentTertiary.opacity(0.10),
                    .clear
                ],
                center: UnitPoint(x: 0.94, y: 0.82),
                startRadius: 20,
                endRadius: 720
            )
        }
        .ignoresSafeArea()
    }
}

public struct CFHeroSurface: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        CFColors.backgroundSecondary.opacity(0.96),
                        CFColors.backgroundTertiary.opacity(0.92),
                        CFColors.surfaceOverlay.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                RadialGradient(
                    colors: [CFColors.accentSecondary.opacity(0.24), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 440
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: CFRadius.hero, style: .continuous)
                    .stroke(CFColors.separator, lineWidth: CFSeparators.width)
            )
            .cfShadow(.elevated)
    }
}

public extension View {
    func cfPanelBackground(
        radius: CGFloat = CFRadius.panel,
        fill: Color = CFColors.panelFill,
        stroke: Color = CFColors.separator,
        shadow: CFShadowToken = .none
    ) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(stroke, lineWidth: CFSeparators.width)
                )
        )
        .cfShadow(shadow)
    }

    func cfSectionPadding() -> some View {
        padding(.horizontal, CFSpacing.xl)
            .padding(.top, CFSpacing.lg)
            .padding(.bottom, CFSpacing.xxl)
    }
}
