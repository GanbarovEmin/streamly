import AppKit
import SwiftUI

public struct MPVRenderView: NSViewRepresentable {
    private let onAttach: @Sendable (NSView) -> Void

    public init(onAttach: @escaping @Sendable (NSView) -> Void = { _ in }) {
        self.onAttach = onAttach
    }

    public func makeNSView(context: Context) -> NSView {
        let view = MPVPlaceholderRenderView()
        onAttach(view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MPVPlaceholderRenderView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
}
