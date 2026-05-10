import SwiftUI

public struct CFBrandMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(CFColors.surfaceOverlay.opacity(0.52))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(CFColors.primaryGradient)
                .offset(x: size * 0.03)
        }
        .frame(width: size, height: size)
        .cfShadow(.hover)
        .accessibilityHidden(true)
    }
}
