import CineFlowLocalization
import SwiftUI

public struct ProgressBar: View {
    private let value: Double

    public init(value: Double) {
        self.value = min(max(value, 0), 1)
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CFColors.elevatedFill)
                Capsule()
                    .fill(CFColors.horizontalGradient)
                    .frame(width: proxy.size.width * value)
                    .animation(CFMotion.standard, value: value)
            }
        }
        .frame(height: 5)
        .accessibilityLabel(L10n.string(.accessibilityProgress))
        .accessibilityValue(L10n.format(.accessibilityProgressFormat, Int(value * 100)))
    }
}

public struct EmptyState: View {
    private let title: String
    private let message: String
    private let systemImage: String
    private let actionTitle: String?
    private let actionSystemImage: String
    private let action: (() -> Void)?

    public init(
        title: String,
        message: String,
        systemImage: String = "tray",
        actionTitle: String? = nil,
        actionSystemImage: String = "arrow.right",
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.action = action
    }

    public var body: some View {
        VStack(spacing: CFSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(CFColors.accentSecondary)
            Text(title)
                .font(CFTypography.title)
                .foregroundStyle(CFColors.textPrimary)
            Text(message)
                .font(CFTypography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(CFColors.textSecondary)
                .frame(maxWidth: 360)

            if let actionTitle, let action {
                SecondaryButton(actionTitle, systemImage: actionSystemImage, action: action)
                    .padding(.top, CFSpacing.xs)
            }
        }
        .padding(CFSpacing.xl)
    }
}

public struct ErrorState: View {
    private let title: String
    private let message: String
    private let recoverySuggestion: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        title: String,
        message: String,
        recoverySuggestion: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .top, spacing: CFSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CFColors.error)

            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(title)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text(message)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)

                if let recoverySuggestion, !recoverySuggestion.isEmpty {
                    Text(recoverySuggestion)
                        .font(CFTypography.caption)
                        .foregroundStyle(CFColors.textMuted)
                }
            }

            if let actionTitle, let action {
                Spacer(minLength: CFSpacing.md)
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(CFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.error.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.error.opacity(0.24), lineWidth: CFSeparators.width)
                )
        )
    }
}

public struct LoadingSkeleton: View {
    private let height: CGFloat
    private let cornerRadius: CGFloat

    @State private var phase = false

    public init(height: CGFloat = 18, cornerRadius: CGFloat = CFRadius.component) {
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        CFColors.elevatedFill,
                        CFColors.accentSecondary.opacity(0.14),
                        CFColors.elevatedFill
                    ],
                    startPoint: phase ? .leading : .trailing,
                    endPoint: phase ? .trailing : .leading
                )
            )
            .frame(height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
            .accessibilityLabel(L10n.string(.accessibilityLoading))
    }
}

public struct TooltipHint<Content: View>: View {
    private let hint: String
    private let content: Content

    public init(_ hint: String, @ViewBuilder content: () -> Content) {
        self.hint = hint
        self.content = content()
    }

    public var body: some View {
        content.help(hint)
    }
}
