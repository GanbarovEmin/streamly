import SwiftUI

public struct SidebarItem: View {
    private let title: String
    private let systemImage: String
    private let isSelected: Bool
    private let action: () -> Void

    @State private var isHovering = false

    public init(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: CFSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)

                Text(title)
                    .font(CFTypography.callout)

                Spacer()
            }
            .foregroundStyle(isSelected ? CFColors.textPrimary : CFColors.textSecondary)
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                            .stroke(isSelected ? CFColors.focusRing.opacity(0.34) : .clear, lineWidth: CFSeparators.width)
                    )
                    .cfShadow(isSelected ? .hover : .none)
            )
            .overlay(alignment: .bottomLeading) {
                if isSelected {
                    Capsule()
                        .fill(CFColors.horizontalGradient)
                        .frame(width: 62, height: 2)
                        .padding(.leading, 13)
                        .padding(.bottom, 4)
                }
            }
            .scaleEffect(isHovering ? CFMotion.hoverScale : 1)
            .animation(CFMotion.spring, value: isHovering)
            .animation(CFMotion.spring, value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cfFocusRing()
    }

    private var backgroundColor: Color {
        if isSelected {
            return CFColors.activeFill.opacity(0.82)
        }

        return isHovering ? CFColors.hoverFill : .clear
    }
}
