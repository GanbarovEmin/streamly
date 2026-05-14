import CineFlowDesignSystem
import SwiftUI

struct DetailReleaseHighlightView: View {
    let highlight: DetailReleaseHighlight
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CFSpacing.sm) {
                Text(highlight.badge)
                    .font(CFTypography.caption)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(Capsule().fill(CFColors.success))

                if let scopeLabel = highlight.scopeLabel {
                    Text(scopeLabel)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
            }

            Text(highlight.title)
                .font(CFTypography.bodyEmphasis)
                .foregroundStyle(CFColors.textPrimary)
                .lineLimit(1)

            Text(highlight.primaryMetadata)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(1)

            Text(highlight.secondaryMetadata)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)
                .lineLimit(1)

            SecondaryButton(actionTitle, systemImage: "play.fill", action: action)
                .padding(.top, CFSpacing.xs)
        }
        .padding(CFSpacing.lg)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.activeFill.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.focusRing.opacity(0.45), lineWidth: CFSeparators.width)
                )
        )
    }
}

struct DetailFallbackBlock: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: CFSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CFColors.textMuted)
                .frame(width: 32, height: 32)
                .background(Circle().fill(CFColors.surfaceOverlay.opacity(0.64)))

            Text(title)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
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
