import AppKit
import SwiftUI

public struct CFColorToken: Equatable, Sendable {
    public let hex: String
    public let color: Color
    public let nsColor: NSColor

    public init(hex: String, red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.hex = hex
        self.color = Color(red: red, green: green, blue: blue, opacity: alpha)
        self.nsColor = NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    public static let backgroundPrimary = CFColorToken(hex: "#0A0B0F", red: 0.039, green: 0.043, blue: 0.059)
    public static let backgroundSecondary = CFColorToken(hex: "#111318", red: 0.067, green: 0.075, blue: 0.094)
    public static let backgroundTertiary = CFColorToken(hex: "#0E1626", red: 0.055, green: 0.086, blue: 0.149)
    public static let surfaceOverlay = CFColorToken(hex: "#1B1E3F", red: 0.106, green: 0.118, blue: 0.247)
    public static let accentPrimary = CFColorToken(hex: "#2563FF", red: 0.145, green: 0.388, blue: 1.000)
    public static let accentSecondary = CFColorToken(hex: "#7B3DFF", red: 0.482, green: 0.239, blue: 1.000)
    public static let accentTertiary = CFColorToken(hex: "#FF2DB2", red: 1.000, green: 0.176, blue: 0.698)
    public static let textPrimary = CFColorToken(hex: "#F2F4F8", red: 0.949, green: 0.957, blue: 0.973)
    public static let textSecondary = CFColorToken(hex: "#A7ADB8", red: 0.655, green: 0.678, blue: 0.722)
    public static let textMuted = CFColorToken(hex: "rgba(242, 244, 248, 0.56)", red: 0.949, green: 0.957, blue: 0.973, alpha: 0.56)
    public static let success = CFColorToken(hex: "#45D483", red: 0.271, green: 0.831, blue: 0.514)
    public static let warning = CFColorToken(hex: "#E6B15A", red: 0.902, green: 0.694, blue: 0.353)
    public static let error = CFColorToken(hex: "#F26D78", red: 0.949, green: 0.427, blue: 0.471)
}

public enum CFColors {
    public static let backgroundPrimary = CFColorToken.backgroundPrimary.color
    public static let backgroundSecondary = CFColorToken.backgroundSecondary.color
    public static let backgroundTertiary = CFColorToken.backgroundTertiary.color
    public static let surfaceOverlay = CFColorToken.surfaceOverlay.color
    public static let accentPrimary = CFColorToken.accentPrimary.color
    public static let accentSecondary = CFColorToken.accentSecondary.color
    public static let accentTertiary = CFColorToken.accentTertiary.color
    public static let textPrimary = CFColorToken.textPrimary.color
    public static let textSecondary = CFColorToken.textSecondary.color
    public static let textMuted = CFColorToken.textMuted.color
    public static let success = CFColorToken.success.color
    public static let warning = CFColorToken.warning.color
    public static let error = CFColorToken.error.color
    public static let separator = Color.white.opacity(CFSeparators.primaryOpacity)
    public static let separatorSubtle = Color.white.opacity(CFSeparators.subtleOpacity)
    public static let focusRing = CFColorToken.accentPrimary.color.opacity(0.72)
    public static let hoverFill = Color.white.opacity(0.055)
    public static let activeFill = CFColorToken.accentPrimary.color.opacity(0.16)
    public static let elevatedFill = Color.white.opacity(0.065)
    public static let clear = Color.clear

    public static let windowBackgroundNSColor = CFColorToken.backgroundPrimary.nsColor

    public static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [
                CFColorToken.accentPrimary.color,
                CFColorToken.accentSecondary.color,
                CFColorToken.accentTertiary.color
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var horizontalGradient: LinearGradient {
        LinearGradient(
            colors: [
                CFColorToken.accentPrimary.color,
                CFColorToken.accentSecondary.color,
                CFColorToken.accentTertiary.color
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
