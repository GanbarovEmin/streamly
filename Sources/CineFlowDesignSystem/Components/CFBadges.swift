import CineFlowLocalization
import SwiftUI

public enum CFBadgeTone: Sendable {
    case rating
    case quality
    case source
    case seeders
    case success
    case warning
    case error

    public var accessibilityPrefixKey: L10nKey {
        switch self {
        case .rating:
            .accessibilityBadgeRating
        case .quality:
            .accessibilityBadgeQuality
        case .source:
            .accessibilityBadgeSource
        case .seeders:
            .accessibilityBadgeSeeders
        case .success:
            .accessibilityBadgeSuccess
        case .warning:
            .accessibilityBadgeWarning
        case .error:
            .accessibilityBadgeError
        }
    }

    public var accessibilityPrefix: String {
        L10n.string(accessibilityPrefixKey)
    }

    var foregroundColor: Color {
        switch self {
        case .rating, .quality, .source, .seeders:
            CFColors.textPrimary
        case .success:
            CFColors.success
        case .warning:
            CFColors.warning
        case .error:
            CFColors.error
        }
    }

    var backgroundColor: Color {
        switch self {
        case .rating, .quality:
            CFColors.accentPrimary.opacity(0.14)
        case .source, .seeders:
            CFColors.elevatedFill
        case .success:
            CFColors.success.opacity(0.12)
        case .warning:
            CFColors.warning.opacity(0.12)
        case .error:
            CFColors.error.opacity(0.12)
        }
    }
}

public struct CFBadge: View {
    private let text: String
    private let tone: CFBadgeTone

    public init(_ text: String, tone: CFBadgeTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(CFTypography.compactNumber)
            .foregroundStyle(tone.foregroundColor)
            .padding(.horizontal, CFSpacing.md)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(tone.backgroundColor)
                    .overlay(Capsule().stroke(CFColors.separator, lineWidth: CFSeparators.width))
            )
            .accessibilityLabel("\(L10n.string(tone.accessibilityPrefixKey)): \(text)")
    }
}

public struct RatingBadge: View {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var body: some View {
        CFBadge(value, tone: .rating)
    }
}

public struct QualityBadge: View {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var body: some View {
        CFBadge(value, tone: .quality)
    }
}

public struct SourceBadge: View {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var body: some View {
        CFBadge(value, tone: .source)
    }
}

public struct SeedersBadge: View {
    private let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public var body: some View {
        CFBadge("\(count)", tone: .seeders)
    }
}

public struct HealthBadge: View {
    private let text: String
    private let tone: CFBadgeTone

    public init(_ text: String, tone: CFBadgeTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        CFBadge(text, tone: tone)
    }
}
