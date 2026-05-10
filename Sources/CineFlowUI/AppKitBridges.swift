import AppKit
import CineFlowDesignSystem
import CineFlowLocalization
import SwiftUI

struct AppWindowConfigurator: NSViewRepresentable {
    let defaultSize: CGSize
    let minimumSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = CFColors.windowBackgroundNSColor.cgColor

        DispatchQueue.main.async {
            configureWindow(for: view, context: context)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, context: context)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configureWindow(for view: NSView, context: Context) {
        guard let window = view.window else { return }

        window.title = L10n.string(.windowTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .resizable, .titled, .closable, .miniaturizable])
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isMovableByWindowBackground = true
        window.backgroundColor = CFColors.windowBackgroundNSColor
        window.isOpaque = true
        window.minSize = minimumSize

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false

        guard !context.coordinator.didSetInitialFrame else { return }
        context.coordinator.didSetInitialFrame = true

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let fittedSize = CGSize(
            width: min(defaultSize.width, max(minimumSize.width, visibleFrame.width - 48)),
            height: min(defaultSize.height, max(minimumSize.height, visibleFrame.height - 48))
        )
        let origin = CGPoint(
            x: visibleFrame.midX - fittedSize.width / 2,
            y: visibleFrame.midY - fittedSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: fittedSize), display: true)
    }

    final class Coordinator {
        var didSetInitialFrame = false
    }
}

struct SidebarVibrancyBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = CFBlur.sidebarMaterial
        view.blendingMode = CFBlur.blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = CFBlur.sidebarMaterial
        nsView.blendingMode = CFBlur.blendingMode
        nsView.state = .active
    }
}
