import AppKit
import SwiftUI

public struct CFBrandMark: View {
    private let size: CGFloat
    private static let logoImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "streamly-mark", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(CFColors.backgroundSecondary.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(CFColors.separator, lineWidth: CFSeparators.width)
                )

            if let image = Self.logoImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.36, weight: .black))
                    .foregroundStyle(CFColors.primaryGradient)
                    .offset(x: size * 0.03)
            }
        }
        .frame(width: size, height: size)
        .cfShadow(.hover)
        .accessibilityHidden(true)
    }
}
