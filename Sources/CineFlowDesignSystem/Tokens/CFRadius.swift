import Foundation

public struct CFRadiusToken: Equatable, Sendable {
    public let value: CGFloat

    public init(_ value: CGFloat) {
        self.value = value
    }

    public static let control = CFRadiusToken(8)
    public static let badge = CFRadiusToken(6)
    public static let component = CFRadiusToken(12)
    public static let poster = CFRadiusToken(14)
    public static let panel = CFRadiusToken(18)
    public static let hero = CFRadiusToken(24)
    public static let pill = CFRadiusToken(999)
}

public enum CFRadius {
    public static let control = CFRadiusToken.control.value
    public static let badge = CFRadiusToken.badge.value
    public static let component = CFRadiusToken.component.value
    public static let poster = CFRadiusToken.poster.value
    public static let panel = CFRadiusToken.panel.value
    public static let hero = CFRadiusToken.hero.value
    public static let pill = CFRadiusToken.pill.value
}
