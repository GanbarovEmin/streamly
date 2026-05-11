import SwiftUI

public struct CFFocusRingModifier: ViewModifier {
    private let cornerRadius: CGFloat

    @FocusState private var isFocused: Bool

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .focusable(true)
            .focused($isFocused)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isFocused ? CFColors.focusRing : .clear, lineWidth: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                    .stroke(isFocused ? CFColors.accentPrimary.opacity(0.28) : .clear, lineWidth: 5)
            )
    }
}

public extension View {
    func cfFocusRing(cornerRadius: CGFloat = CFRadius.component) -> some View {
        modifier(CFFocusRingModifier(cornerRadius: cornerRadius))
    }
}
