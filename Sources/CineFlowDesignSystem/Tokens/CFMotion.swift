import SwiftUI

public struct CFMotionToken: Equatable, Sendable {
    public let duration: Double
    public let response: Double
    public let dampingFraction: Double

    public init(duration: Double, response: Double, dampingFraction: Double) {
        self.duration = duration
        self.response = response
        self.dampingFraction = dampingFraction
    }

    public static let quick = CFMotionToken(duration: 0.14, response: 0.24, dampingFraction: 0.86)
    public static let standard = CFMotionToken(duration: 0.22, response: 0.30, dampingFraction: 0.84)
    public static let spring = CFMotionToken(duration: 0.28, response: 0.34, dampingFraction: 0.82)
}

public enum CFMotion {
    public static let quick = Animation.easeInOut(duration: CFMotionToken.quick.duration)
    public static let standard = Animation.easeInOut(duration: CFMotionToken.standard.duration)
    public static let spring = Animation.spring(
        response: CFMotionToken.spring.response,
        dampingFraction: CFMotionToken.spring.dampingFraction
    )
    public static let hoverScale: CGFloat = 1.02
    public static let activeScale: CGFloat = 0.98
    public static let reducedHoverScale: CGFloat = 1
    public static let reducedActiveScale: CGFloat = 1
}
