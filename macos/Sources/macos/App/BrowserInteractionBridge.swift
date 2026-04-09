import SwiftUI
import AppKit

struct BrowserInteractionBridge: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, CGPoint, NSEvent.ModifierFlags) -> Void
    let onDelete: () -> Void
    let onMoveSelection: (Double, Double) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onFit: () -> Void

    func makeNSView(context: Context) -> BrowserInteractionNSView {
        let view = BrowserInteractionNSView()
        view.onScroll = onScroll
        view.onDelete = onDelete
        view.onMoveSelection = onMoveSelection
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onFit = onFit
        return view
    }

    func updateNSView(_ nsView: BrowserInteractionNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onDelete = onDelete
        nsView.onMoveSelection = onMoveSelection
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.onFit = onFit
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                guard nsView.window?.firstResponder !== nsView else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class BrowserInteractionNSView: NSView {
    var onScroll: ((CGFloat, CGFloat, CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onDelete: (() -> Void)?
    var onMoveSelection: ((Double, Double) -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onFit: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onMoveSelection?(-0.02, 0)
        case 124:
            onMoveSelection?(0.02, 0)
        case 125:
            onMoveSelection?(0, 0.02)
        case 126:
            onMoveSelection?(0, -0.02)
        case 51, 117:
            onDelete?()
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            if event.modifierFlags.contains(.command), chars == "+" || chars == "=" {
                onZoomIn?()
            } else if event.modifierFlags.contains(.command), chars == "-" {
                onZoomOut?()
            } else if event.modifierFlags.contains(.command), chars.lowercased() == "0" {
                onFit?()
            } else {
                interpretKeyEvents([event])
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, point, event.modifierFlags)
    }
}
