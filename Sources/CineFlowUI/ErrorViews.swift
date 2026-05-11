import CineFlowCore
import CineFlowDesignSystem
import SwiftUI

public struct ErrorBanner: View {
    private let error: CineFlowError
    private let retryTitle: String?
    private let onRetry: (() -> Void)?

    public init(_ error: CineFlowError, retryTitle: String? = nil, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: CFSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CFColors.error)

            VStack(alignment: .leading, spacing: CFSpacing.xs) {
                Text(error.userMessage)
                    .font(CFTypography.bodyEmphasis)
                    .foregroundStyle(CFColors.textPrimary)
                Text(error.recoverySuggestion)
                    .font(CFTypography.caption)
                    .foregroundStyle(CFColors.textSecondary)
            }

            Spacer(minLength: CFSpacing.md)

            if let onRetry {
                RetryButton(title: retryTitle ?? "Retry", action: onRetry)
            }
        }
        .padding(CFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.error.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                        .stroke(CFColors.error.opacity(0.26), lineWidth: CFSeparators.width)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

public struct ErrorCard: View {
    private let title: String
    private let error: CineFlowError
    private let retryTitle: String?
    private let onRetry: (() -> Void)?

    public init(title: String, error: CineFlowError, retryTitle: String? = nil, onRetry: (() -> Void)? = nil) {
        self.title = title
        self.error = error
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CFSpacing.md) {
            HStack(spacing: CFSpacing.sm) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CFColors.error)
                Text(title)
                    .font(CFTypography.title)
                    .foregroundStyle(CFColors.textPrimary)
            }

            Text(error.userMessage)
                .font(CFTypography.body)
                .foregroundStyle(CFColors.textSecondary)

            Text(error.recoverySuggestion)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textMuted)

            if let onRetry {
                RetryButton(title: retryTitle ?? "Retry", action: onRetry)
            }
        }
        .padding(CFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                .fill(CFColors.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: CFRadius.panel, style: .continuous)
                        .stroke(CFColors.error.opacity(0.24), lineWidth: CFSeparators.width)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

public struct RetryButton: View {
    private let title: String
    private let action: () -> Void

    public init(title: String = "Retry", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}

public struct InlineErrorState: View {
    private let error: CineFlowError

    public init(_ error: CineFlowError) {
        self.error = error
    }

    public var body: some View {
        HStack(spacing: CFSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(CFColors.error)
            Text(error.userMessage)
                .font(CFTypography.caption)
                .foregroundStyle(CFColors.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(CFSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                .fill(CFColors.error.opacity(0.08))
        )
    }
}
