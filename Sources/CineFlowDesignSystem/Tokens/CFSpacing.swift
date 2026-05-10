import Foundation

public struct CFSpacingToken: Equatable, Sendable {
    public let value: CGFloat

    public init(_ value: CGFloat) {
        self.value = value
    }

    public static let xxs = CFSpacingToken(4)
    public static let xs = CFSpacingToken(4)
    public static let sm = CFSpacingToken(8)
    public static let md = CFSpacingToken(16)
    public static let lg = CFSpacingToken(24)
    public static let xl = CFSpacingToken(32)
    public static let xxl = CFSpacingToken(48)
}

public enum CFSpacing {
    public static let xxs = CFSpacingToken.xxs.value
    public static let xs = CFSpacingToken.xs.value
    public static let sm = CFSpacingToken.sm.value
    public static let md = CFSpacingToken.md.value
    public static let lg = CFSpacingToken.lg.value
    public static let xl = CFSpacingToken.xl.value
    public static let xxl = CFSpacingToken.xxl.value
}
