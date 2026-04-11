import SwiftUI
import AppKit

struct BrowserInteractionBridge: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, CGPoint, NSEvent.ModifierFlags) -> Void
    let onDelete: () -> Void
    let onMoveSelection: (Double, Double) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onFit: () -> Void
    let onEdit: () -> Void
    let onCreateChild: () -> Void

    func makeNSView(context: Context) -> BrowserInteractionNSView {
        let view = BrowserInteractionNSView()
        view.onScroll = onScroll
        view.onDelete = onDelete
        view.onMoveSelection = onMoveSelection
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onFit = onFit
        view.onEdit = onEdit
        view.onCreateChild = onCreateChild
        return view
    }

    func updateNSView(_ nsView: BrowserInteractionNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onDelete = onDelete
        nsView.onMoveSelection = onMoveSelection
        nsView.onZoomIn = onZoomIn
        nsView.onZoomOut = onZoomOut
        nsView.onFit = onFit
        nsView.onEdit = onEdit
        nsView.onCreateChild = onCreateChild
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
    var onEdit: (() -> Void)?
    var onCreateChild: (() -> Void)?

    func browserEventPoint(from event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

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
        case 36, 76:
            if event.modifierFlags.contains(.shift) {
                onCreateChild?()
            } else {
                onEdit?()
            }
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
        let point = browserEventPoint(from: event)
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, point, event.modifierFlags)
    }
}
