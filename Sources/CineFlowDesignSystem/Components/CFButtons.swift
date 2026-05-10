import SwiftUI

public struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: CFSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(CFTypography.callout)
            .foregroundStyle(CFColors.textPrimary)
            .padding(.horizontal, CFSpacing.lg)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .fill(CFColors.primaryGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                            .stroke(CFColors.textPrimary.opacity(CFSeparators.subtleOpacity), lineWidth: CFSeparators.width)
                    )
            )
            .scaleEffect(isPressed ? CFMotion.activeScale : (isHovering ? CFMotion.hoverScale : 1))
            .cfShadow(isHovering ? .hover : .none)
            .animation(CFMotion.spring, value: isHovering)
            .animation(CFMotion.quick, value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .cfFocusRing()
    }
}

public struct SecondaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    @State private var isHovering = false

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: CFSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(CFTypography.callout)
            .foregroundStyle(CFColors.textPrimary)
            .padding(.horizontal, CFSpacing.lg)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .fill(isHovering ? CFColors.hoverFill : CFColors.elevatedFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                            .stroke(isHovering ? CFColors.focusRing.opacity(0.56) : CFColors.separator, lineWidth: CFSeparators.width)
                    )
            )
            .scaleEffect(isHovering ? CFMotion.hoverScale : 1)
            .animation(CFMotion.spring, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cfFocusRing()
    }
}

public struct IconButton: View {
    private let systemImage: String
    private let accessibilityLabel: String
    private let action: () -> Void

    @State private var isHovering = false

    public init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isHovering ? CFColors.textPrimary : CFColors.textSecondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(isHovering ? CFColors.hoverFill : CFColors.elevatedFill)
                        .overlay(Circle().stroke(isHovering ? CFColors.focusRing.opacity(0.56) : CFColors.separator, lineWidth: CFSeparators.width))
                )
                .scaleEffect(isHovering ? CFMotion.hoverScale : 1)
                .animation(CFMotion.spring, value: isHovering)
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovering = $0 }
        .cfFocusRing(cornerRadius: CFRadius.pill)
    }
}
