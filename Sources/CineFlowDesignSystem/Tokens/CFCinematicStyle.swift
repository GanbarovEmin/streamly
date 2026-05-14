import SwiftUI

public enum CFCinematicStyle {
    public static let detailHeroMinHeight: CGFloat = 760
    public static let detailPosterWidth: CGFloat = 206
    public static let detailPosterHeight: CGFloat = 310
    public static let playerControlAutoHideDelay: TimeInterval = 1.8
    public static let dimmedPlayerOpacity: Double = 0.30
    public static let purpleGlowOpacity: Double = 0.30

    public static func backdropBlurRadius(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : 18
    }

    public static func transitionAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : CFMotion.cinematic
    }
}
