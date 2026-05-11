import SwiftUI

public struct CFShadowToken: Equatable, Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }

    public static let none = CFShadowToken(color: .clear, radius: 0, x: 0, y: 0)
    public static let hover = CFShadowToken(color: CFColors.accentSecondary.opacity(0.24), radius: 22, x: 0, y: 0)
    public static let elevated = CFShadowToken(color: CFColors.backgroundTertiary.opacity(0.42), radius: 34, x: 0, y: 18)
    public static let panel = CFShadowToken(color: CFColors.backgroundPrimary.opacity(0.34), radius: 24, x: 0, y: 12)
    public static let softGlow = CFShadowToken(color: CFColors.accentSecondary.opacity(0.18), radius: 28, x: 0, y: 0)
    public static let icon = CFShadowToken(color: CFColors.backgroundPrimary.opacity(0.35), radius: 8, x: 0, y: 4)
}

public extension View {
    func cfShadow(_ token: CFShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}
