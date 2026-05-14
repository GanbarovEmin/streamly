import CineFlowDesignSystem
import SwiftUI

struct CinematicAmbientGlow: View {
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    CFColors.accentSecondary.opacity(CFCinematicStyle.purpleGlowOpacity),
                    CFColors.accentTertiary.opacity(0.10),
                    CFColors.clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )
            .blur(radius: CFCinematicStyle.backdropBlurRadius(reduceMotion: reduceMotion))

            RadialGradient(
                colors: [
                    CFColors.accentSecondary.opacity(0.18),
                    CFColors.clear
                ],
                center: .bottomLeading,
                startRadius: 80,
                endRadius: 760
            )
            .blur(radius: CFCinematicStyle.backdropBlurRadius(reduceMotion: reduceMotion) * 0.7)
        }
        .allowsHitTesting(false)
    }
}

struct CinematicScrim: View {
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge

    var body: some View {
        LinearGradient(
            colors: edge == .top
                ? [CFColors.backgroundPrimary.opacity(0.72), CFColors.backgroundPrimary.opacity(0.22), CFColors.clear]
                : [CFColors.clear, CFColors.backgroundPrimary.opacity(0.26), CFColors.backgroundPrimary.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

struct CinematicChromeBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(shape.fill(CFColors.backgroundPrimary.opacity(0.46)))
            .overlay(shape.stroke(CFColors.separator.opacity(0.62), lineWidth: CFSeparators.width))
            .shadow(color: CFColors.accentSecondary.opacity(0.20), radius: 32, x: 0, y: 18)
    }
}

extension View {
    func cinematicChrome<S: Shape>(in shape: S) -> some View {
        modifier(CinematicChromeBackground(shape: shape))
    }
}
