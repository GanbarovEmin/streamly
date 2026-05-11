import SwiftUI

public struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.cfReduceMotion) private var reduceMotion
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
            .scaleEffect(scaleValue)
            .cfShadow(isHovering && !reduceMotion ? .hover : .none)
            .opacity(isEnabled ? 1 : 0.46)
            .cfAnimation(CFMotion.spring, value: isHovering, reduceMotion: reduceMotion)
            .cfAnimation(CFMotion.quick, value: isPressed, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .cfFocusRing()
    }

    private var scaleValue: CGFloat {
        if reduceMotion { return CFMotion.reducedHoverScale }
        return isPressed ? CFMotion.activeScale : (isHovering ? CFMotion.hoverScale : 1)
    }
}

public struct SecondaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.cfReduceMotion) private var reduceMotion
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
                    .lineLimit(1)
            }
            .font(CFTypography.callout)
            .foregroundStyle(CFColors.textPrimary)
            .padding(.horizontal, CFSpacing.lg)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                    .fill(isHovering ? CFColors.hoverFill : CFColors.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: CFRadius.component, style: .continuous)
                            .stroke(isHovering ? CFColors.focusRing.opacity(0.56) : CFColors.separator, lineWidth: CFSeparators.width)
                    )
            )
            .scaleEffect(scaleValue)
            .opacity(isEnabled ? 1 : 0.46)
            .cfAnimation(CFMotion.spring, value: isHovering, reduceMotion: reduceMotion)
            .cfAnimation(CFMotion.quick, value: isPressed, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .cfFocusRing()
    }

    private var scaleValue: CGFloat {
        if reduceMotion { return CFMotion.reducedHoverScale }
        return isPressed ? CFMotion.activeScale : (isHovering ? CFMotion.hoverScale : 1)
    }
}

public struct IconButton: View {
    private let systemImage: String
    private let accessibilityLabel: String
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.cfReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

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
                        .fill(isHovering ? CFColors.hoverFill : CFColors.panelFill)
                        .overlay(Circle().stroke(isHovering ? CFColors.focusRing.opacity(0.56) : CFColors.separator, lineWidth: CFSeparators.width))
                )
                .scaleEffect(scaleValue)
                .opacity(isEnabled ? 1 : 0.44)
                .cfAnimation(CFMotion.spring, value: isHovering, reduceMotion: reduceMotion)
                .cfAnimation(CFMotion.quick, value: isPressed, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .cfFocusRing(cornerRadius: CFRadius.pill)
    }

    private var scaleValue: CGFloat {
        if reduceMotion { return CFMotion.reducedHoverScale }
        return isPressed ? CFMotion.activeScale : (isHovering ? CFMotion.hoverScale : 1)
    }
}
