import SwiftUI
import AppKit
import MetalKit

struct BrowserSurfaceState: Equatable {
    let contentRevision: Int
    let viewportRevision: Int
    let presentationRevision: Int
    let appearanceSignature: Int
    let dragTranslation: FrievePoint?
    let draggedCardIDs: Set<Int>
    let hoverCardID: Int?
    let selectedCardIDs: Set<Int>
    let inlineEditorCardID: Int?
    let marqueeStartPoint: CGPoint?
    let marqueeCurrentPoint: CGPoint?
    let linkPreviewSourceCardID: Int?
    let linkPreviewCanvasPoint: CGPoint?
    let linkLabelsVisible: Bool
    let labelRectanglesVisible: Bool
    let canvasCenter: FrievePoint
    let zoom: Double
    let viewportSummary: String
}

struct BrowserSurfaceRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: WorkspaceViewModel
    let canvasSize: CGSize

    func makeNSView(context: Context) -> BrowserSurfaceNSView {
        let view = BrowserSurfaceNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: BrowserSurfaceNSView, context: Context) {
        configure(nsView)
        let state = BrowserSurfaceState(
            contentRevision: viewModel.browserSurfaceContentRevision,
            viewportRevision: viewModel.browserSurfaceViewportRevision,
            presentationRevision: viewModel.browserSurfacePresentationRevision,
            appearanceSignature: nsView.browserAppearanceSignature,
            dragTranslation: viewModel.currentDragTranslation,
            draggedCardIDs: Set(viewModel.dragOriginByCardID.keys),
            hoverCardID: viewModel.browserHoverCardID,
            selectedCardIDs: viewModel.selectedCardIDs,
            inlineEditorCardID: viewModel.browserInlineEditorCardID,
            marqueeStartPoint: viewModel.marqueeStartPoint,
            marqueeCurrentPoint: viewModel.marqueeCurrentPoint,
            linkPreviewSourceCardID: viewModel.linkPreviewSourceCardID,
            linkPreviewCanvasPoint: viewModel.linkPreviewCanvasPoint,
            linkLabelsVisible: viewModel.linkLabelsVisible,
            labelRectanglesVisible: viewModel.labelRectanglesVisible,
            canvasCenter: viewModel.canvasCenter,
            zoom: viewModel.zoom,
            viewportSummary: viewModel.browserViewportSummary(in: canvasSize)
        )
        nsView.updateSceneIfNeeded(state: state, canvasSize: canvasSize)
    }

    private func configure(_ view: BrowserSurfaceNSView) {
        view.viewModel = viewModel
        view.updateInteractionMode(viewModel.browserInteractionModeEnabled)
        viewModel.browserInteractionModeRefreshHandler = { [weak view] isEnabled in
            view?.updateInteractionMode(isEnabled)
        }
        viewModel.browserSurfaceContentRefreshHandler = { [weak view] in
            view?.refreshFromViewModel()
        }
        viewModel.browserSurfacePresentationRefreshHandler = { [weak view] in
            view?.refreshFromViewModel()
        }
        viewModel.browserSurfaceViewportRefreshHandler = { [weak view] in
            view?.refreshFromViewModel()
        }
        viewModel.browserSnapshotProvider = { [weak view] in
            view?.snapshotImage()
        }
        view.onScroll = { deltaX, deltaY, location, modifiers in
            viewModel.handleScrollWheel(deltaX: deltaX, deltaY: deltaY, modifiers: modifiers, at: location, in: canvasSize)
        }
        view.onDelete = {
            viewModel.deleteSelectedCard()
        }
        view.onNavigateSelection = { dx, dy in
            viewModel.handleBrowserDirectionalSelection(dx: dx, dy: dy)
        }
        view.onZoomIn = {
            viewModel.zoomIn()
        }
        view.onZoomOut = {
            viewModel.zoomOut()
        }
        view.onFit = {
            viewModel.requestBrowserFit()
        }
        view.onEdit = {
            viewModel.handleBrowserEditShortcut()
        }
        view.onCreateChild = {
            viewModel.handleBrowserCreateChildShortcut()
        }
        view.onCreateSibling = {
            viewModel.handleBrowserCreateSiblingShortcut()
        }
        view.onUndo = {
            viewModel.undoLastDocumentChange()
        }
    }
}

@MainActor
private final class BrowserOverlayHostView: NSView {
    override var isFlipped: Bool { true }
}

enum BrowserSceneUpdateMode: Equatable {
    case full
    case viewportOnly
    case cardsOnly
    case cardsLinksAndText
}

func browserPresentationRefreshMode(selectionChanged: Bool, dragChanged: Bool, hoverChanged: Bool) -> BrowserSceneUpdateMode {
    if selectionChanged || dragChanged {
        return .cardsLinksAndText
    }
    if hoverChanged {
        return .cardsOnly
    }
    return .cardsLinksAndText
}

@MainActor
final class BrowserSurfaceNSView: BrowserInteractionNSView {
    private enum BrowserCardContextAction: Int {
        case edit
        case newChild
        case newSibling
        case toggleFixed
        case toggleFolded
        case webSearch
        case copyGPTPrompt
        case delete
        case undo
    }

    private let pointerDragActivationDistance: CGFloat = 4
    weak var viewModel: WorkspaceViewModel? {
        didSet { renderer.viewModel = viewModel }
    }

    private let metalView: MTKView
    private let overlayView = BrowserOverlayHostView(frame: .zero)
    private let selectionOverlayLayer = CAShapeLayer()
    private let marqueeOverlayLayer = CAShapeLayer()
    private let linkPreviewLayer = CAShapeLayer()
    private let renderer: BrowserMetalRenderer
    private var trackingAreaRef: NSTrackingArea?
    private var mouseDownPoint: CGPoint?
    private var mouseDownCardID: Int?
    private var mouseDownModifiers: NSEvent.ModifierFlags = []
    private var interactionDidDrag = false
    private var middleButtonPanning = false
    private var currentHitRegions: [BrowserCardHitRegion] = []
    private var lastOverlaySignature: Int?
    private var lastSurfaceState: BrowserSurfaceState?
    private var lastSceneSnapshot: BrowserSurfaceSceneSnapshot?
    private var lastCanvasSize: CGSize = .zero
    private var lastAppearanceSignature: Int?

    var browserAppearanceSignature: Int {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0
    }

    override init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required for BrowserSurfaceNSView")
        }
        metalView = MTKView(frame: .zero, device: device)
        renderer = BrowserMetalRenderer(device: device, metalView: metalView)
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required for BrowserSurfaceNSView")
        }
        metalView = MTKView(frame: .zero, device: device)
        renderer = BrowserMetalRenderer(device: device, metalView: metalView)
        super.init(coder: coder)
        commonInit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        handleAppearanceChangeIfNeeded(force: true)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        handleAppearanceChangeIfNeeded(force: false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func layout() {
        super.layout()
        metalView.frame = bounds
        overlayView.frame = bounds
        overlayView.layer?.frame = overlayView.bounds
        selectionOverlayLayer.frame = overlayView.bounds
        marqueeOverlayLayer.frame = overlayView.bounds
        linkPreviewLayer.frame = overlayView.bounds
        metalView.drawableSize = CGSize(
            width: bounds.width * windowBackingScale,
            height: bounds.height * windowBackingScale
        )
    }

    func snapshotImage() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0,
              let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        representation.size = bounds.size
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    override func mouseMoved(with event: NSEvent) {
        guard let viewModel else { return }
        let point = browserEventPoint(from: event)
        viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point))
    }

    override func mouseExited(with event: NSEvent) {
        viewModel?.setBrowserHoverCard(nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = browserEventPoint(from: event)
        return cardContextMenu(atCanvasPoint: point, modifiers: event.modifierFlags)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = browserEventPoint(from: event)
        mouseDownPoint = point
        mouseDownModifiers = event.modifierFlags
        mouseDownCardID = cardID(atCanvasPoint: point)
        interactionDidDrag = false

        if event.clickCount == 2 {
            if let mouseDownCardID {
                viewModel?.handleCardDoubleClick(mouseDownCardID)
            } else {
                viewModel?.addCard(at: point, in: bounds.size)
            }
            resetPointerInteraction()
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else {
            super.otherMouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        beginMiddleButtonCanvasPan(at: browserEventPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewModel, let mouseDownPoint else { return }
        let point = browserEventPoint(from: event)
        let dragDistance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        if dragDistance < pointerDragActivationDistance {
            return
        }
        interactionDidDrag = true

        if let mouseDownCardID {
            viewModel.updateCardInteraction(cardID: mouseDownCardID, from: mouseDownPoint, to: point, in: bounds.size, modifiers: mouseDownModifiers)
        } else {
            if !viewModel.hasActiveBrowserGesture {
                let additiveSelection = mouseDownModifiers.contains(.shift) || mouseDownModifiers.contains(.command)
                viewModel.beginCanvasMarqueeGesture(at: mouseDownPoint, additive: additiveSelection)
            }
            viewModel.updateCanvasGesture(from: mouseDownPoint, to: point, in: bounds.size)
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard middleButtonPanning else {
            super.otherMouseDragged(with: event)
            return
        }
        updateMiddleButtonCanvasPan(to: browserEventPoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetPointerInteraction() }
        guard let viewModel, mouseDownPoint != nil else { return }
        let point = browserEventPoint(from: event)

        if let mouseDownCardID {
            if interactionDidDrag {
                viewModel.endCardInteraction(at: point, in: bounds.size)
            } else {
                viewModel.handleCardTap(mouseDownCardID, modifiers: mouseDownModifiers)
            }
        } else if interactionDidDrag {
            viewModel.endCanvasGesture(in: bounds.size)
        } else if !mouseDownModifiers.contains(.shift) && !mouseDownModifiers.contains(.command) {
            viewModel.clearSelection()
        }

        if !interactionDidDrag {
            viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point))
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard middleButtonPanning else {
            super.otherMouseUp(with: event)
            return
        }
        defer { resetPointerInteraction() }
        endMiddleButtonCanvasPan(at: browserEventPoint(from: event))
    }

    override func magnify(with event: NSEvent) {
        guard let viewModel else { return }
        viewModel.markBrowserInteractionActivity()
        let location = browserEventPoint(from: event)
        let factor = max(0.2, 1.0 + event.magnification)
        viewModel.zoom(by: factor, anchor: location, in: bounds.size)
    }

    func updateSceneIfNeeded(state: BrowserSurfaceState, canvasSize: CGSize) {
        guard let viewModel else { return }
        let lastState = lastSurfaceState
        let contentChanged = lastState.map {
            $0.contentRevision != state.contentRevision ||
            $0.appearanceSignature != state.appearanceSignature ||
            $0.linkLabelsVisible != state.linkLabelsVisible ||
            $0.labelRectanglesVisible != state.labelRectanglesVisible
        } ?? true
        let viewportChanged = lastState.map {
            $0.viewportRevision != state.viewportRevision ||
            $0.marqueeStartPoint != state.marqueeStartPoint ||
            $0.marqueeCurrentPoint != state.marqueeCurrentPoint ||
            $0.linkPreviewSourceCardID != state.linkPreviewSourceCardID ||
            $0.linkPreviewCanvasPoint != state.linkPreviewCanvasPoint ||
            $0.canvasCenter != state.canvasCenter ||
            $0.zoom != state.zoom ||
            $0.viewportSummary != state.viewportSummary
        } ?? true
        let hoverChanged = lastState.map { $0.hoverCardID != state.hoverCardID } ?? true
        let selectionChanged = lastState.map { $0.selectedCardIDs != state.selectedCardIDs } ?? true
        let dragChanged = lastState.map {
            $0.dragTranslation != state.dragTranslation || $0.draggedCardIDs != state.draggedCardIDs
        } ?? true
        let inlineEditorChanged = lastState.map { $0.inlineEditorCardID != state.inlineEditorCardID } ?? true
        let presentationChanged = lastState.map { $0.presentationRevision != state.presentationRevision } ?? true
        let sizeChanged = lastCanvasSize != canvasSize
        lastSurfaceState = state
        lastCanvasSize = canvasSize
        guard contentChanged || viewportChanged || presentationChanged || sizeChanged || hoverChanged || selectionChanged || inlineEditorChanged else { return }

        if contentChanged || sizeChanged || lastSceneSnapshot == nil {
            let scene = viewModel.browserSurfaceScene(in: canvasSize)
            lastSceneSnapshot = scene
            updateScene(scene, canvasSize: canvasSize, mode: .full)
            return
        }

        if viewportChanged, let scene = lastSceneSnapshot {
            let refreshedScene = viewModel.browserSurfaceScene(in: canvasSize)
            lastSceneSnapshot = refreshedScene
            let contentIsStable =
                refreshedScene.cardSnapshotSignature == scene.cardSnapshotSignature &&
                refreshedScene.linkSnapshotSignature == scene.linkSnapshotSignature &&
                refreshedScene.labelGroups == scene.labelGroups
            updateScene(
                refreshedScene,
                canvasSize: canvasSize,
                mode: contentIsStable ? .viewportOnly : .full
            )
            return
        }

        if presentationChanged, let scene = lastSceneSnapshot {
            let updatedScene = presentationScene(
                from: scene,
                state: state,
                updateCards: hoverChanged || selectionChanged || dragChanged,
                updateLinks: selectionChanged || dragChanged
            )
            lastSceneSnapshot = updatedScene
            let mode = browserPresentationRefreshMode(
                selectionChanged: selectionChanged,
                dragChanged: dragChanged,
                hoverChanged: hoverChanged
            )
            updateScene(updatedScene, canvasSize: canvasSize, mode: mode)
        }
    }

    func refreshFromViewModel() {
        guard let viewModel else { return }
        let canvasSize = bounds.size
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let state = BrowserSurfaceState(
            contentRevision: viewModel.browserSurfaceContentRevision,
            viewportRevision: viewModel.browserSurfaceViewportRevision,
            presentationRevision: viewModel.browserSurfacePresentationRevision,
            appearanceSignature: browserAppearanceSignature,
            dragTranslation: viewModel.currentDragTranslation,
            draggedCardIDs: Set(viewModel.dragOriginByCardID.keys),
            hoverCardID: viewModel.browserHoverCardID,
            selectedCardIDs: viewModel.selectedCardIDs,
            inlineEditorCardID: viewModel.browserInlineEditorCardID,
            marqueeStartPoint: viewModel.marqueeStartPoint,
            marqueeCurrentPoint: viewModel.marqueeCurrentPoint,
            linkPreviewSourceCardID: viewModel.linkPreviewSourceCardID,
            linkPreviewCanvasPoint: viewModel.linkPreviewCanvasPoint,
            linkLabelsVisible: viewModel.linkLabelsVisible,
            labelRectanglesVisible: viewModel.labelRectanglesVisible,
            canvasCenter: viewModel.canvasCenter,
            zoom: viewModel.zoom,
            viewportSummary: viewModel.browserViewportSummary(in: canvasSize)
        )
        updateSceneIfNeeded(state: state, canvasSize: canvasSize)
    }

    private func updateScene(_ scene: BrowserSurfaceSceneSnapshot, canvasSize: CGSize, mode: BrowserSceneUpdateMode) {
        let updateStart = CACurrentMediaTime()
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 0.5
        currentHitRegions = scene.hitRegions

        renderer.updateScene(scene, mode: mode)
        metalView.draw()

        if (mode == .full || mode == .viewportOnly), lastOverlaySignature != scene.overlaySignature {
            applyOverlay(scene.overlay)
            lastOverlaySignature = scene.overlaySignature
        }
        viewModel?.recordPerformanceMetric(updateStart, keyPath: \BrowserPerformanceSnapshot.surfaceApply)
    }

    private func commonInit() {
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = true
        rootLayer.cornerRadius = 10
        layer = rootLayer

        metalView.clearColor = MTLClearColor(color: NSColor.textBackgroundColor)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.sampleCount = 1
        metalView.framebufferOnly = false
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.preferredFramesPerSecond = 120
        metalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(metalView)

        overlayView.wantsLayer = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.layer = CALayer()
        overlayView.layer?.masksToBounds = false
        addSubview(overlayView)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        marqueeOverlayLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        marqueeOverlayLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        marqueeOverlayLayer.lineDashPattern = [6, 4]

        linkPreviewLayer.fillColor = nil
        linkPreviewLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor
        linkPreviewLayer.lineDashPattern = [8, 5]
        linkPreviewLayer.lineWidth = 2

        overlayView.layer?.addSublayer(marqueeOverlayLayer)
        overlayView.layer?.addSublayer(linkPreviewLayer)
        handleAppearanceChangeIfNeeded(force: true)
    }

    func updateInteractionMode(_ isEnabled: Bool) {
        if isEnabled {
            if metalView.enableSetNeedsDisplay {
                metalView.enableSetNeedsDisplay = false
            }
            if metalView.isPaused {
                metalView.isPaused = false
            }
        } else {
            if !metalView.enableSetNeedsDisplay {
                metalView.enableSetNeedsDisplay = true
            }
            if !metalView.isPaused {
                metalView.isPaused = true
            }
            metalView.draw()
        }
    }

    private var windowBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    func cardContextMenu(atCanvasPoint point: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSMenu? {
        guard let cardID = cardID(atCanvasPoint: point) else { return nil }
        return cardContextMenu(forCardID: cardID, modifiers: modifiers)
    }

    func cardContextMenu(forCardID cardID: Int, modifiers: NSEvent.ModifierFlags = []) -> NSMenu? {
        guard let viewModel else { return nil }
        synchronizeSelectionForContextMenu(cardID: cardID, modifiers: modifiers)

        let menu = NSMenu(title: "Card")
        let selectedIDs = viewModel.selectedCardIDs.isEmpty ? Set(viewModel.selectedCardID.map { [$0] } ?? []) : viewModel.selectedCardIDs
        let hasSingleSelection = selectedIDs.count == 1
        let selectedCard = viewModel.cardByID(viewModel.selectedCardID)

        menu.addItem(makeContextMenuItem("Edit Card", action: .edit, enabled: hasSingleSelection))
        menu.addItem(makeContextMenuItem("New Child Card", action: .newChild, enabled: viewModel.selectedCardID != nil))
        menu.addItem(makeContextMenuItem("New Sibling Card", action: .newSibling, enabled: viewModel.selectedCardID != nil))
        menu.addItem(.separator())
        menu.addItem(makeContextMenuItem(
            (selectedCard?.isFixed ?? false) ? "Unfix Card" : "Fix Card",
            action: .toggleFixed,
            enabled: hasSingleSelection && selectedCard != nil
        ))
        menu.addItem(makeContextMenuItem(
            (selectedCard?.isFolded ?? false) ? "Unfold Card" : "Fold Card",
            action: .toggleFolded,
            enabled: hasSingleSelection && selectedCard != nil
        ))
        menu.addItem(.separator())
        // Labels submenu
        let labelMenu = NSMenu(title: "Label")
        let noLabelItem = NSMenuItem(title: "No Label", action: #selector(handleSetLabelNone), keyEquivalent: "")
        noLabelItem.target = self
        labelMenu.addItem(noLabelItem)
        if !viewModel.document.cardLabels.isEmpty {
            labelMenu.addItem(.separator())
            for label in viewModel.document.cardLabels {
                let labelItem = NSMenuItem(title: label.name, action: #selector(handleSetLabel(_:)), keyEquivalent: "")
                labelItem.target = self
                labelItem.tag = label.id
                if let selectedCard, selectedCard.labelIDs.contains(label.id) {
                    labelItem.state = .on
                }
                labelMenu.addItem(labelItem)
            }
        }
        let labelMenuItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
        labelMenuItem.submenu = labelMenu
        labelMenuItem.isEnabled = !selectedIDs.isEmpty
        menu.addItem(labelMenuItem)

        // Shape submenu
        let shapeNames = ["Rounded Rectangle", "Ellipse", "Capsule", "Diamond", "Hexagon", "Soft Rectangle"]
        let shapeMenu = NSMenu(title: "Shape")
        for (idx, name) in shapeNames.enumerated() {
            let item = NSMenuItem(title: name, action: #selector(handleSetShape(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            if let selectedCard, (selectedCard.shape % shapeNames.count + shapeNames.count) % shapeNames.count == idx {
                item.state = .on
            }
            shapeMenu.addItem(item)
        }
        let shapeMenuItem = NSMenuItem(title: "Shape", action: nil, keyEquivalent: "")
        shapeMenuItem.submenu = shapeMenu
        shapeMenuItem.isEnabled = !selectedIDs.isEmpty
        menu.addItem(shapeMenuItem)

        // Size submenu
        let sizeOptions: [(String, Int)] = [("Small", 60), ("Normal", 100), ("Large", 140), ("Extra Large", 180)]
        let sizeMenu = NSMenu(title: "Size")
        for (name, size) in sizeOptions {
            let item = NSMenuItem(title: name, action: #selector(handleSetSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = size
            if let selectedCard, selectedCard.size == size {
                item.state = .on
            }
            sizeMenu.addItem(item)
        }
        let sizeMenuItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeMenuItem.submenu = sizeMenu
        sizeMenuItem.isEnabled = !selectedIDs.isEmpty
        menu.addItem(sizeMenuItem)

        menu.addItem(.separator())
        menu.addItem(makeContextMenuItem("Web Search", action: .webSearch, enabled: viewModel.selectedCardID != nil))
        menu.addItem(makeContextMenuItem("Copy GPT Prompt", action: .copyGPTPrompt, enabled: viewModel.selectedCardID != nil))
        menu.addItem(.separator())
        menu.addItem(makeContextMenuItem(
            selectedIDs.count > 1 ? "Delete Selected Cards" : "Delete Card",
            action: .delete,
            enabled: !selectedIDs.isEmpty
        ))
        menu.addItem(makeContextMenuItem("Undo", action: .undo, enabled: viewModel.canUndoLastDocumentChange))
        return menu
    }

    private func synchronizeSelectionForContextMenu(cardID: Int, modifiers: NSEvent.ModifierFlags) {
        guard let viewModel else { return }
        if viewModel.selectedCardIDs.contains(cardID) {
            viewModel.selectedCardID = cardID
            viewModel.document.focusedCardID = cardID
            return
        }
        viewModel.handleCardTap(cardID, modifiers: modifiers)
    }

    private func makeContextMenuItem(_ title: String, action: BrowserCardContextAction, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(handleBrowserCardContextMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = action.rawValue
        item.isEnabled = enabled
        return item
    }

    private func handleAppearanceChangeIfNeeded(force: Bool) {
        let signature = browserAppearanceSignature
        guard force || lastAppearanceSignature != signature else { return }
        lastAppearanceSignature = signature
        renderer.handleAppearanceChange(signature: signature)
        metalView.clearColor = MTLClearColor(color: NSColor.textBackgroundColor)
        refreshFromViewModel()
    }

    @objc
    private func handleBrowserCardContextMenuAction(_ sender: NSMenuItem) {
        guard let action = BrowserCardContextAction(rawValue: sender.tag), let viewModel else { return }
        switch action {
        case .edit:
            viewModel.handleBrowserEditShortcut()
        case .newChild:
            viewModel.handleBrowserCreateChildShortcut()
        case .newSibling:
            viewModel.handleBrowserCreateSiblingShortcut()
        case .toggleFixed:
            if let card = viewModel.cardByID(viewModel.selectedCardID) {
                viewModel.updateSelectedCardFixed(!card.isFixed)
            }
        case .toggleFolded:
            if let card = viewModel.cardByID(viewModel.selectedCardID) {
                viewModel.updateSelectedCardFolded(!card.isFolded)
            }
        case .webSearch:
            viewModel.searchWebForSelection()
        case .copyGPTPrompt:
            viewModel.copyGPTPromptToClipboard()
        case .delete:
            viewModel.deleteSelectedCard()
        case .undo:
            viewModel.undoLastDocumentChange()
        }
    }

    @objc
    private func handleSetLabelNone() {
        guard let viewModel else { return }
        let ids = viewModel.selectedCardIDs.isEmpty ? Set(viewModel.selectedCardID.map { [$0] } ?? []) : viewModel.selectedCardIDs
        viewModel.registerUndoCheckpoint()
        for id in ids {
            viewModel.document.updateCard(id) { $0.labelIDs = [] }
        }
        viewModel.noteDocumentMutation(status: "Cleared labels")
    }

    @objc
    private func handleSetLabel(_ sender: NSMenuItem) {
        guard let viewModel else { return }
        let labelID = sender.tag
        let ids = viewModel.selectedCardIDs.isEmpty ? Set(viewModel.selectedCardID.map { [$0] } ?? []) : viewModel.selectedCardIDs
        viewModel.registerUndoCheckpoint()
        for id in ids {
            viewModel.document.updateCard(id) { card in
                if card.labelIDs.contains(labelID) {
                    card.labelIDs.removeAll { $0 == labelID }
                } else {
                    card.labelIDs.append(labelID)
                }
            }
        }
        viewModel.noteDocumentMutation(status: "Changed label")
    }

    @objc
    private func handleSetShape(_ sender: NSMenuItem) {
        guard let viewModel else { return }
        let shape = sender.tag
        let ids = viewModel.selectedCardIDs.isEmpty ? Set(viewModel.selectedCardID.map { [$0] } ?? []) : viewModel.selectedCardIDs
        viewModel.registerUndoCheckpoint()
        for id in ids {
            viewModel.document.updateCard(id) { $0.shape = shape }
        }
        viewModel.noteDocumentMutation(status: "Changed shape")
    }

    @objc
    private func handleSetSize(_ sender: NSMenuItem) {
        guard let viewModel else { return }
        let size = sender.tag
        let ids = viewModel.selectedCardIDs.isEmpty ? Set(viewModel.selectedCardID.map { [$0] } ?? []) : viewModel.selectedCardIDs
        viewModel.registerUndoCheckpoint()
        for id in ids {
            viewModel.document.updateCard(id) { $0.size = size }
        }
        viewModel.noteDocumentMutation(status: "Changed size")
    }

    func beginMiddleButtonCanvasPan(at point: CGPoint) {
        mouseDownPoint = point
        mouseDownCardID = nil
        mouseDownModifiers = []
        interactionDidDrag = false
        middleButtonPanning = true
    }

    func beginPrimaryCanvasSelection(at point: CGPoint, modifiers: NSEvent.ModifierFlags = []) {
        mouseDownPoint = point
        mouseDownCardID = nil
        mouseDownModifiers = modifiers
        interactionDidDrag = false
        middleButtonPanning = false
    }

    func updatePrimaryCanvasSelection(to point: CGPoint) {
        guard let viewModel, let mouseDownPoint else { return }
        let dragDistance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        if dragDistance < pointerDragActivationDistance {
            return
        }
        interactionDidDrag = true
        if !viewModel.hasActiveBrowserGesture {
            let additiveSelection = mouseDownModifiers.contains(.shift) || mouseDownModifiers.contains(.command)
            viewModel.beginCanvasMarqueeGesture(at: mouseDownPoint, additive: additiveSelection)
        }
        viewModel.updateCanvasGesture(from: mouseDownPoint, to: point, in: bounds.size)
    }

    func endPrimaryCanvasSelection(at point: CGPoint) {
        guard let viewModel, mouseDownPoint != nil else { return }
        if interactionDidDrag {
            viewModel.endCanvasGesture(in: bounds.size)
        } else if !mouseDownModifiers.contains(.shift) && !mouseDownModifiers.contains(.command) {
            viewModel.clearSelection()
            viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point))
        } else {
            viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point))
        }
    }

    func updateMiddleButtonCanvasPan(to point: CGPoint) {
        guard let viewModel, let mouseDownPoint else { return }
        let dragDistance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        if dragDistance < pointerDragActivationDistance {
            return
        }
        interactionDidDrag = true
        if !viewModel.hasActiveBrowserGesture {
            viewModel.beginCanvasPanGesture(at: mouseDownPoint)
        }
        viewModel.updateCanvasGesture(from: mouseDownPoint, to: point, in: bounds.size)
    }

    func endMiddleButtonCanvasPan(at point: CGPoint) {
        guard let viewModel, mouseDownPoint != nil else { return }
        if interactionDidDrag {
            viewModel.endCanvasGesture(in: bounds.size)
        } else {
            viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point))
        }
    }

    private func resetPointerInteraction() {
        mouseDownPoint = nil
        mouseDownCardID = nil
        mouseDownModifiers = []
        interactionDidDrag = false
        middleButtonPanning = false
    }

    private func cardID(atCanvasPoint point: CGPoint) -> Int? {
        for region in currentHitRegions.reversed() where region.frame.contains(point) {
            return region.cardID
        }
        return nil
    }

    private func applyOverlay(_ overlay: BrowserOverlaySnapshot) {
        selectionOverlayLayer.path = nil
        selectionOverlayLayer.isHidden = true

        if let marqueeRect = overlay.marqueeRect {
            marqueeOverlayLayer.path = CGPath(rect: marqueeRect, transform: nil)
            marqueeOverlayLayer.isHidden = false
        } else {
            marqueeOverlayLayer.path = nil
            marqueeOverlayLayer.isHidden = true
        }

        if let preview = overlay.linkPreviewSegment {
            let path = CGMutablePath()
            path.move(to: preview.0)
            path.addLine(to: preview.1)
            linkPreviewLayer.path = path
            linkPreviewLayer.isHidden = false
        } else {
            linkPreviewLayer.path = nil
            linkPreviewLayer.isHidden = true
        }
    }

    private func presentationScene(
        from scene: BrowserSurfaceSceneSnapshot,
        state: BrowserSurfaceState,
        updateCards: Bool,
        updateLinks: Bool
    ) -> BrowserSurfaceSceneSnapshot {
        guard let viewModel else { return scene }
        let selectedCardIDs = state.selectedCardIDs
        let isDraggingSelection = state.dragTranslation != nil && !state.draggedCardIDs.isEmpty
        let cards = updateCards ? scene.cards.map { snapshot in
            let position = isDraggingSelection ? viewModel.currentPosition(for: snapshot.card) : snapshot.position
            return BrowserCardLayerSnapshot(
                card: snapshot.card,
                position: position,
                metadata: snapshot.metadata,
                isSelected: selectedCardIDs.contains(snapshot.id),
                isHovered: state.hoverCardID == snapshot.id,
                detailLevel: snapshot.detailLevel
            )
        } : scene.cards
        let linkBaseScale = CGFloat(max(viewModel.browserScale(in: scene.canvasSize), 1))
        let links = updateLinks ? scene.links.map { snapshot in
            let startPoint = viewModel.cardByID(snapshot.fromCardID).map {
                let point = viewModel.currentPosition(for: $0)
                return CGPoint(x: point.x, y: point.y)
            } ?? snapshot.startPoint
            let endPoint = viewModel.cardByID(snapshot.toCardID).map {
                let point = viewModel.currentPosition(for: $0)
                return CGPoint(x: point.x, y: point.y)
            } ?? snapshot.endPoint
            let labelPoint: CGPoint?
            if snapshot.labelText != nil {
                let verticalOffset = 8 / max(linkBaseScale, 0.0001)
                labelPoint = CGPoint(
                    x: (startPoint.x + endPoint.x) / 2,
                    y: (startPoint.y + endPoint.y) / 2 - verticalOffset
                )
            } else {
                labelPoint = nil
            }
            return BrowserLinkLayerSnapshot(
                id: snapshot.id,
                fromCardID: snapshot.fromCardID,
                toCardID: snapshot.toCardID,
                startPoint: startPoint,
                endPoint: endPoint,
                shapeIndex: snapshot.shapeIndex,
                directionVisible: snapshot.directionVisible,
                labelPoint: labelPoint,
                labelText: snapshot.labelText,
                isHighlighted: selectedCardIDs.contains(snapshot.fromCardID) || selectedCardIDs.contains(snapshot.toCardID)
            )
        } : scene.links
        return BrowserSurfaceSceneSnapshot(
            canvasSize: scene.canvasSize,
            worldToCanvasTransform: scene.worldToCanvasTransform,
            backgroundGuidePath: scene.backgroundGuidePath,
            cards: cards,
            cardSnapshotSignature: updateCards ? viewModel.browserCardSnapshotSignature(cards) : scene.cardSnapshotSignature,
            links: links,
            linkSnapshotSignature: updateLinks ? viewModel.browserLinkSnapshotSignature(links) : scene.linkSnapshotSignature,
            labelGroups: scene.labelGroups,
            hitRegions: scene.hitRegions,
            overlay: scene.overlay,
            overlaySignature: scene.overlaySignature,
            viewportSummary: scene.viewportSummary
        )
    }
}

@MainActor
private final class BrowserMetalRenderer: NSObject, MTKViewDelegate {
    weak var viewModel: WorkspaceViewModel?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let labelGroupPipeline: MTLRenderPipelineState
    private let linkPipeline: MTLRenderPipelineState
    private let cardPipeline: MTLRenderPipelineState
    private let textPipeline: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let fallbackTexture: MTLTexture
    private let atlasTexture: MTLTexture
    private let atlasSide: Int
    private weak var metalView: MTKView?

    private var scene: BrowserSurfaceSceneSnapshot?
    private var solidVertices: [BrowserMetalColorVertex] = []
    private var solidVertexBuffer: MTLBuffer?
    private var labelGroupInstances: [BrowserMetalLabelGroupInstance] = []
    private var labelGroupInstanceBuffer: MTLBuffer?
    private var linkInstances: [BrowserMetalLinkInstance] = []
    private var linkInstanceBuffer: MTLBuffer?
    private var textInstances: [BrowserMetalTextInstance] = []
    private var textInstanceBuffer: MTLBuffer?
    private var cardInstances: [BrowserMetalCardInstance] = []
    private var cardInstanceBuffer: MTLBuffer?
    private var atlasEntries: [String: BrowserMetalAtlasEntry] = [:]
    private var pendingAtlasUploads: [BrowserMetalPendingUpload] = []
    private var pendingAtlasUploadKeys: Set<String> = []
    private var visibleAtlasKeys: Set<String> = []
    private var desiredAtlasKeys: Set<String> = []
    private var labelImageCache: [String: NSImage] = [:]
    private var labelImageOrder: [String] = []
    private var atlasCursorX: Int = 0
    private var atlasCursorY: Int = 0
    private var atlasRowHeight: Int = 0
    private var frameCounter: UInt64 = 0
    private var appearanceSignature: Int = 0

    private let maxAtlasUploadsPerFrame = 4
    private let maxAtlasUploadBytesPerFrame = 12 * 1024 * 1024
    private let maxPendingAtlasUploads = 96

    init(device: MTLDevice, metalView: MTKView) {
        self.device = device
        self.metalView = metalView
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Unable to create Metal command queue")
        }
        self.commandQueue = commandQueue
        atlasSide = 4096
        atlasTexture = BrowserMetalRenderer.makeAtlasTexture(device: device, side: atlasSide)

        guard let library = BrowserMetalRenderer.makeLibrary(device: device) else {
            fatalError("Unable to load Metal shader library")
        }

        let solidDescriptor = MTLRenderPipelineDescriptor()
        solidDescriptor.label = "Browser Solid Pipeline"
        solidDescriptor.vertexFunction = library.makeFunction(name: "browserColorVertex")
        solidDescriptor.fragmentFunction = library.makeFunction(name: "browserColorFragment")
        solidDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        BrowserMetalRenderer.configureAlphaBlending(for: solidDescriptor.colorAttachments[0])
        let solidVertexDescriptor = MTLVertexDescriptor()
        solidVertexDescriptor.attributes[0].format = .float2
        solidVertexDescriptor.attributes[0].offset = 0
        solidVertexDescriptor.attributes[0].bufferIndex = 0
        solidVertexDescriptor.attributes[1].format = .float4
        solidVertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        solidVertexDescriptor.attributes[1].bufferIndex = 0
        solidVertexDescriptor.layouts[0].stride = MemoryLayout<BrowserMetalColorVertex>.stride
        solidDescriptor.vertexDescriptor = solidVertexDescriptor
        solidPipeline = try! device.makeRenderPipelineState(descriptor: solidDescriptor)

        let labelGroupDescriptor = MTLRenderPipelineDescriptor()
        labelGroupDescriptor.label = "Browser Label Group Pipeline"
        labelGroupDescriptor.vertexFunction = library.makeFunction(name: "browserLabelGroupVertex")
        labelGroupDescriptor.fragmentFunction = library.makeFunction(name: "browserLabelGroupFragment")
        labelGroupDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        BrowserMetalRenderer.configureAlphaBlending(for: labelGroupDescriptor.colorAttachments[0])
        labelGroupPipeline = try! device.makeRenderPipelineState(descriptor: labelGroupDescriptor)

        let linkDescriptor = MTLRenderPipelineDescriptor()
        linkDescriptor.label = "Browser Link Pipeline"
        linkDescriptor.vertexFunction = library.makeFunction(name: "browserLinkVertex")
        linkDescriptor.fragmentFunction = library.makeFunction(name: "browserLinkFragment")
        linkDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        linkDescriptor.rasterSampleCount = metalView.sampleCount
        BrowserMetalRenderer.configureAlphaBlending(for: linkDescriptor.colorAttachments[0])
        linkPipeline = try! device.makeRenderPipelineState(descriptor: linkDescriptor)

        let cardDescriptor = MTLRenderPipelineDescriptor()
        cardDescriptor.label = "Browser Card Pipeline"
        cardDescriptor.vertexFunction = library.makeFunction(name: "browserCardVertex")
        cardDescriptor.fragmentFunction = library.makeFunction(name: "browserCardFragment")
        cardDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        cardDescriptor.rasterSampleCount = metalView.sampleCount
        BrowserMetalRenderer.configureAlphaBlending(for: cardDescriptor.colorAttachments[0])
        cardPipeline = try! device.makeRenderPipelineState(descriptor: cardDescriptor)

        let textDescriptor = MTLRenderPipelineDescriptor()
        textDescriptor.label = "Browser Text Pipeline"
        textDescriptor.vertexFunction = library.makeFunction(name: "browserTextVertex")
        textDescriptor.fragmentFunction = library.makeFunction(name: "browserTextFragment")
        textDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        textDescriptor.rasterSampleCount = metalView.sampleCount
        BrowserMetalRenderer.configureAlphaBlending(for: textDescriptor.colorAttachments[0])
        textPipeline = try! device.makeRenderPipelineState(descriptor: textDescriptor)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)!
        fallbackTexture = BrowserMetalRenderer.makeFallbackTexture(device: device)
        super.init()
        metalView.delegate = self
    }

    fileprivate func updateScene(_ scene: BrowserSurfaceSceneSnapshot, mode: BrowserSceneUpdateMode) {
        self.scene = scene
        switch mode {
        case .full:
            rebuildResources()
        case .viewportOnly:
            break
        case .cardsOnly:
            rebuildCardResources(for: scene)
        case .cardsLinksAndText:
            rebuildLinkResources(for: scene)
            rebuildCardResources(for: scene)
            rebuildTextResources(for: scene)
        }
    }

    fileprivate func handleAppearanceChange(signature: Int) {
        appearanceSignature = signature
        resetAtlas()
        visibleAtlasKeys.removeAll(keepingCapacity: true)
        desiredAtlasKeys.removeAll(keepingCapacity: true)
        labelImageCache.removeAll(keepingCapacity: true)
        labelImageOrder.removeAll(keepingCapacity: true)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let scene,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }
        frameCounter &+= 1
        viewModel?.recordBrowserFramePresentation()
        let atlasChanged = processPendingAtlasUploads(
            maxUploadsPerFrame: maxAtlasUploadsPerFrame,
            maxUploadBytesPerFrame: maxAtlasUploadBytesPerFrame
        )
        if atlasChanged {
            desiredAtlasKeys.removeAll(keepingCapacity: true)
            rebuildCardResources(for: scene)
            rebuildTextResources(for: scene)
            applyDesiredAtlasKeys()
        }
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(color: NSColor.textBackgroundColor)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        renderEncoder.label = "Browser Metal Encoder"

        var viewport = BrowserMetalViewportUniforms(
            viewportSize: SIMD2(Float(scene.canvasSize.width), Float(scene.canvasSize.height)),
            worldScale: SIMD2(Float(scene.worldToCanvasTransform.a), Float(scene.worldToCanvasTransform.d)),
            worldOffset: SIMD2(Float(scene.worldToCanvasTransform.tx), Float(scene.worldToCanvasTransform.ty))
        )
        if let solidVertexBuffer, !solidVertices.isEmpty {
            renderEncoder.setRenderPipelineState(solidPipeline)
            renderEncoder.setVertexBuffer(solidVertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&viewport, length: MemoryLayout<BrowserMetalViewportUniforms>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: solidVertices.count)
        }

        if let labelGroupInstanceBuffer, !labelGroupInstances.isEmpty {
            renderEncoder.setRenderPipelineState(labelGroupPipeline)
            renderEncoder.setVertexBytes(&viewport, length: MemoryLayout<BrowserMetalViewportUniforms>.stride, index: 0)
            renderEncoder.setVertexBuffer(labelGroupInstanceBuffer, offset: 0, index: 1)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: labelGroupInstances.count)
        }

        if let linkInstanceBuffer, !linkInstances.isEmpty {
            renderEncoder.setRenderPipelineState(linkPipeline)
            renderEncoder.setVertexBytes(&viewport, length: MemoryLayout<BrowserMetalViewportUniforms>.stride, index: 0)
            renderEncoder.setVertexBuffer(linkInstanceBuffer, offset: 0, index: 1)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: linkInstances.count)
        }

        if let cardInstanceBuffer, !cardInstances.isEmpty {
            renderEncoder.setRenderPipelineState(cardPipeline)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            renderEncoder.setVertexBytes(&viewport, length: MemoryLayout<BrowserMetalViewportUniforms>.stride, index: 0)
            renderEncoder.setVertexBuffer(cardInstanceBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentBuffer(cardInstanceBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(atlasTexture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: cardInstances.count)
        }

        if let textInstanceBuffer, !textInstances.isEmpty {
            renderEncoder.setRenderPipelineState(textPipeline)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            renderEncoder.setVertexBytes(&viewport, length: MemoryLayout<BrowserMetalViewportUniforms>.stride, index: 0)
            renderEncoder.setVertexBuffer(textInstanceBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentBuffer(textInstanceBuffer, offset: 0, index: 0)
            renderEncoder.setFragmentTexture(atlasTexture, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: textInstances.count)
        }

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if atlasChanged || !pendingAtlasUploads.isEmpty {
            view.setNeedsDisplay(view.bounds)
        }
    }

    private func rebuildResources() {
        guard let scene else {
            solidVertices.removeAll(keepingCapacity: true)
            solidVertexBuffer = nil
            labelGroupInstances.removeAll(keepingCapacity: true)
            labelGroupInstanceBuffer = nil
            linkInstances.removeAll(keepingCapacity: true)
            linkInstanceBuffer = nil
            textInstances.removeAll(keepingCapacity: true)
            textInstanceBuffer = nil
            cardInstances.removeAll(keepingCapacity: true)
            cardInstanceBuffer = nil
            visibleAtlasKeys.removeAll(keepingCapacity: true)
            desiredAtlasKeys.removeAll(keepingCapacity: true)
            pendingAtlasUploads.removeAll(keepingCapacity: true)
            pendingAtlasUploadKeys.removeAll(keepingCapacity: true)
            return
        }

        let geometryStart = CACurrentMediaTime()
        solidVertices = buildSolidVertices(for: scene)
        if solidVertices.isEmpty {
            solidVertexBuffer = nil
        } else {
            updateBuffer(
                &solidVertexBuffer,
                with: solidVertices,
                minimumLength: MemoryLayout<BrowserMetalColorVertex>.stride * solidVertices.count
            )
        }
        desiredAtlasKeys.removeAll(keepingCapacity: true)
        rebuildLabelGroupResources(for: scene)
        rebuildLinkResources(for: scene)
        rebuildCardResources(for: scene)
        rebuildTextResources(for: scene)
        applyDesiredAtlasKeys()
        viewModel?.browserPerformance.surfaceScene.record(max((CACurrentMediaTime() - geometryStart) * 1000, 0))
    }

    private func rebuildLabelGroupResources(for scene: BrowserSurfaceSceneSnapshot) {
        labelGroupInstances = buildLabelGroupInstances(for: scene)
        if labelGroupInstances.isEmpty {
            labelGroupInstanceBuffer = nil
        } else {
            updateBuffer(
                &labelGroupInstanceBuffer,
                with: labelGroupInstances,
                minimumLength: MemoryLayout<BrowserMetalLabelGroupInstance>.stride * labelGroupInstances.count
            )
        }
    }

    private func buildLabelGroupInstances(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalLabelGroupInstance] {
        return scene.labelGroups.map { snapshot in
            return BrowserMetalLabelGroupInstance(
                center: SIMD2(Float(snapshot.worldRect.midX), Float(snapshot.worldRect.midY)),
                halfSize: SIMD2(Float(snapshot.worldRect.width / 2), Float(snapshot.worldRect.height / 2)),
                color: NSColor(Color(frieveRGB: snapshot.color)).withAlphaComponent(0.72).rgbaVector,
                strokeWidth: 3,
                cornerRadius: 14,
                padding: SIMD2(repeating: 14)
            )
        }
    }

    private func rebuildLinkResources(for scene: BrowserSurfaceSceneSnapshot) {
        linkInstances = buildLinkInstances(for: scene)
        if linkInstances.isEmpty {
            linkInstanceBuffer = nil
        } else {
            updateBuffer(
                &linkInstanceBuffer,
                with: linkInstances,
                minimumLength: MemoryLayout<BrowserMetalLinkInstance>.stride * linkInstances.count
            )
        }
    }

    private func rebuildCardResources(for scene: BrowserSurfaceSceneSnapshot) {
        cardInstances = buildCardInstances(for: scene)
        if cardInstances.isEmpty {
            cardInstanceBuffer = nil
        } else {
            updateBuffer(
                &cardInstanceBuffer,
                with: cardInstances,
                minimumLength: MemoryLayout<BrowserMetalCardInstance>.stride * cardInstances.count
            )
        }
    }

    private func rebuildTextResources(for scene: BrowserSurfaceSceneSnapshot) {
        textInstances = buildTextInstances(for: scene)
        if textInstances.isEmpty {
            textInstanceBuffer = nil
        } else {
            updateBuffer(
                &textInstanceBuffer,
                with: textInstances,
                minimumLength: MemoryLayout<BrowserMetalTextInstance>.stride * textInstances.count
            )
        }
    }

    private func updateBuffer<Element>(_ buffer: inout MTLBuffer?, with values: [Element], minimumLength: Int) {
        guard minimumLength > 0 else {
            buffer = nil
            return
        }
        if buffer == nil || buffer!.length < minimumLength {
            let currentLength = buffer?.length ?? 0
            var newLength = max(minimumLength, max(currentLength * 2, 4096))
            newLength = ((newLength + 255) / 256) * 256
            buffer = device.makeBuffer(length: newLength, options: .storageModeShared)
        }
        guard let buffer else { return }
        values.withUnsafeBufferPointer { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            memcpy(buffer.contents(), baseAddress, minimumLength)
        }
    }

    private func buildSolidVertices(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalColorVertex] {
        var vertices: [BrowserMetalColorVertex] = []
        appendStrokedPath(
            scene.backgroundGuidePath,
            color: NSColor.secondaryLabelColor.withAlphaComponent(0.08).rgbaVector,
            width: 0.7,
            into: &vertices
        )
        return vertices
    }

    private func buildLinkInstances(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalLinkInstance] {
        let canvasBackground = NSColor.textBackgroundColor
        let linkBaseScale = max(
            max(abs(CGFloat(scene.worldToCanvasTransform.a)), abs(CGFloat(scene.worldToCanvasTransform.d))),
            0.0001
        )
        return scene.links.flatMap { snapshot -> [BrowserMetalLinkInstance] in
            let color = (snapshot.isHighlighted
                ? NSColor.controlAccentColor.browserOpaqueComposite(over: canvasBackground, opacity: 0.85, darkModeLift: 0.04)
                : NSColor.secondaryLabelColor.browserOpaqueComposite(over: canvasBackground, opacity: 0.42, darkModeLift: 0.10)).rgbaVector
            let width: Float = snapshot.isHighlighted ? 3 : 2
            var instances = makeLinkSegmentInstances(
                start: snapshot.startPoint,
                end: snapshot.endPoint,
                shapeIndex: snapshot.shapeIndex,
                lineWidth: width,
                color: color
            )
            if snapshot.directionVisible {
                instances.append(
                    contentsOf: makeArrowInstances(
                        start: snapshot.startPoint,
                        end: snapshot.endPoint,
                        shapeIndex: snapshot.shapeIndex,
                        baseScale: linkBaseScale,
                        lineWidth: width,
                        color: color
                    )
                )
            }
            return instances
        }
    }

    private func buildCardInstances(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalCardInstance] {
        guard let viewModel else {
            visibleAtlasKeys.removeAll(keepingCapacity: true)
            desiredAtlasKeys.removeAll(keepingCapacity: true)
            pendingAtlasUploads.removeAll(keepingCapacity: true)
            pendingAtlasUploadKeys.removeAll(keepingCapacity: true)
            return []
        }
        let transform = scene.worldToCanvasTransform
        var instances: [BrowserMetalCardInstance] = []
        instances.reserveCapacity(scene.cards.count)

        for snapshot in scene.cards {
            let center = CGPoint(x: snapshot.position.x, y: snapshot.position.y)
            let rasterKey = viewModel.browserCardRasterKey(for: snapshot)
            let rasterImage = viewModel.browserCardRasterIfReady(for: snapshot, cacheKey: rasterKey)
            if rasterImage != nil {
                desiredAtlasKeys.insert(rasterKey)
            }
            let priority = atlasPriority(for: snapshot, center: center.applying(transform), canvasSize: scene.canvasSize)
            let atlasEntry = atlasEntry(for: rasterKey, image: rasterImage, priority: priority)
            let fillColor = NSColor(viewModel.color(for: snapshot.card)).rgbaVector
            let strokeColor = NSColor(viewModel.browserCardStrokeColor(for: snapshot.card, isSelected: snapshot.isSelected, isHovered: snapshot.isHovered)).rgbaVector
            let glowColor = NSColor(viewModel.browserCardGlow(for: snapshot.card, isSelected: snapshot.isSelected)).rgbaVector
            let shadowColor = NSColor(viewModel.browserCardShadow(for: snapshot.card, isSelected: snapshot.isSelected, isHovered: snapshot.isHovered)).rgbaVector
            let strokeWidth = viewModel.browserCardStrokeWidth(isSelected: snapshot.isSelected)
            let shadowRadius: Float = 0
            let shadowOffset = SIMD2<Float>(0, 0)
            let padding: Float = 6
            instances.append(
                BrowserMetalCardInstance(
                    center: SIMD2(Float(center.x), Float(center.y)),
                    contentSize: SIMD2(Float(snapshot.metadata.canvasSize.width), Float(snapshot.metadata.canvasSize.height)),
                    paddedSize: SIMD2(Float(snapshot.metadata.canvasSize.width) + padding * 2, Float(snapshot.metadata.canvasSize.height) + padding * 2),
                    shadowOffset: shadowOffset,
                    atlasUVOrigin: atlasEntry?.uvOrigin ?? .zero,
                    atlasUVSize: atlasEntry?.uvSize ?? .zero,
                    fillColor: fillColor,
                    strokeColor: strokeColor,
                    glowColor: glowColor,
                    shadowColor: shadowColor,
                    strokeWidth: strokeWidth,
                    glowRadius: 0,
                    shadowRadius: shadowRadius,
                    shapeIndex: Int32(browserCardVisualShapeIndex(for: snapshot.card)),
                    hasTexture: atlasEntry == nil ? 0 : 1,
                    cornerRadius: Float(min(14, min(snapshot.metadata.canvasSize.width, snapshot.metadata.canvasSize.height) * 0.35)),
                    padding: .zero
                )
            )
        }

        return instances
    }

    private func atlasEntry(for key: String, image: NSImage?, priority: Int) -> BrowserMetalAtlasEntry? {
        if var entry = atlasEntries[key] {
            entry.lastUsedFrame = frameCounter
            atlasEntries[key] = entry
            return entry
        }
        guard let image, let cgImage = image.browserCGImage else { return nil }
        enqueueAtlasUpload(BrowserMetalPendingUpload(key: key, image: cgImage, priority: priority))
        return nil
    }

    private func enqueueAtlasUpload(_ upload: BrowserMetalPendingUpload) {
        if let existingIndex = pendingAtlasUploads.firstIndex(where: { $0.key == upload.key }) {
            if pendingAtlasUploads[existingIndex].priority < upload.priority {
                pendingAtlasUploads[existingIndex].priority = upload.priority
                pendingAtlasUploads.sort { $0.priority > $1.priority }
            }
            return
        }

        pendingAtlasUploads.append(upload)
        pendingAtlasUploadKeys.insert(upload.key)
        pendingAtlasUploads.sort { $0.priority > $1.priority }

        if pendingAtlasUploads.count > maxPendingAtlasUploads {
            let removedUploads = pendingAtlasUploads.suffix(from: maxPendingAtlasUploads)
            for removedUpload in removedUploads {
                pendingAtlasUploadKeys.remove(removedUpload.key)
            }
            pendingAtlasUploads.removeSubrange(maxPendingAtlasUploads...)
        }
    }

    private func trimPendingAtlasUploads(to visibleKeys: Set<String>) {
        guard !pendingAtlasUploads.isEmpty else { return }
        pendingAtlasUploads.removeAll { !visibleKeys.contains($0.key) }
        pendingAtlasUploadKeys = Set(pendingAtlasUploads.map(\.key))
    }

    private func atlasPriority(for snapshot: BrowserCardLayerSnapshot, center: CGPoint, canvasSize: CGSize) -> Int {
        let dx = center.x - canvasSize.width * 0.5
        let dy = center.y - canvasSize.height * 0.5
        let distance = hypot(dx, dy)
        var priority = Int(max(0, 100_000 - distance * 48))
        if snapshot.isSelected {
            priority += 120_000
        }
        if snapshot.isHovered {
            priority += 80_000
        }
        if snapshot.card.hasMedia {
            priority += 12_000
        }
        switch snapshot.detailLevel {
        case .full:
            priority += 8_000
        case .compact:
            priority += 4_000
        case .thumbnail:
            break
        }
        return priority
    }

    private func processPendingAtlasUploads(maxUploadsPerFrame: Int, maxUploadBytesPerFrame: Int) -> Bool {
        guard !pendingAtlasUploads.isEmpty else { return false }

        var atlasChanged = false
        var processedUploads = 0
        var uploadedBytes = 0

        while !pendingAtlasUploads.isEmpty,
              processedUploads < maxUploadsPerFrame,
              uploadedBytes < maxUploadBytesPerFrame {
            let upload = pendingAtlasUploads.removeFirst()
            pendingAtlasUploadKeys.remove(upload.key)

            guard visibleAtlasKeys.contains(upload.key) else {
                continue
            }

            let width = upload.image.width
            let height = upload.image.height
            guard width > 0, height > 0 else {
                continue
            }

            let byteCost = width * height * 4
            if processedUploads > 0, uploadedBytes + byteCost > maxUploadBytesPerFrame {
                enqueueAtlasUpload(upload)
                break
            }

            guard let region = allocateAtlasRegion(for: CGSize(width: width, height: height)) else {
                atlasChanged = repackVisibleAtlas() || atlasChanged
                break
            }

            guard writeAtlasImage(upload.image, forKey: upload.key, region: region) else {
                continue
            }

            uploadedBytes += byteCost
            processedUploads += 1
            atlasChanged = true
        }

        return atlasChanged
    }

    private func repackVisibleAtlas() -> Bool {
        guard let scene, let viewModel else {
            resetAtlas(clearPending: true)
            return false
        }

        resetAtlas(clearPending: false)

        var deferredUploads: [BrowserMetalPendingUpload] = []
        let prioritizedSnapshots = scene.cards.sorted { lhs, rhs in
            let lhsCenter = CGPoint(x: lhs.position.x, y: lhs.position.y).applying(scene.worldToCanvasTransform)
            let rhsCenter = CGPoint(x: rhs.position.x, y: rhs.position.y).applying(scene.worldToCanvasTransform)
            return atlasPriority(for: lhs, center: lhsCenter, canvasSize: scene.canvasSize) > atlasPriority(for: rhs, center: rhsCenter, canvasSize: scene.canvasSize)
        }

        for snapshot in prioritizedSnapshots {
            let rasterKey = viewModel.browserCardRasterKey(for: snapshot)
            guard let rasterImage = viewModel.browserCardRasterIfReady(for: snapshot, cacheKey: rasterKey),
                  let cgImage = rasterImage.browserCGImage else {
                continue
            }
            let center = CGPoint(x: snapshot.position.x, y: snapshot.position.y).applying(scene.worldToCanvasTransform)
            let priority = atlasPriority(for: snapshot, center: center, canvasSize: scene.canvasSize)
            guard let region = allocateAtlasRegion(for: CGSize(width: cgImage.width, height: cgImage.height)) else {
                deferredUploads.append(BrowserMetalPendingUpload(key: rasterKey, image: cgImage, priority: priority))
                continue
            }
            if !writeAtlasImage(cgImage, forKey: rasterKey, region: region) {
                deferredUploads.append(BrowserMetalPendingUpload(key: rasterKey, image: cgImage, priority: priority))
            }
        }

        pendingAtlasUploads.removeAll(keepingCapacity: true)
        pendingAtlasUploadKeys.removeAll(keepingCapacity: true)
        for upload in deferredUploads {
            enqueueAtlasUpload(upload)
        }
        return !atlasEntries.isEmpty
    }

    private func writeAtlasImage(_ image: CGImage, forKey key: String, region: MTLRegion) -> Bool {
        guard let rgba = BrowserMetalRenderer.rgbaBytes(for: image) else { return false }
        rgba.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            atlasTexture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: image.width * 4)
        }
        let uvOrigin = SIMD2<Float>(Float(region.origin.x) / Float(atlasSide), Float(region.origin.y) / Float(atlasSide))
        let uvSize = SIMD2<Float>(Float(region.size.width) / Float(atlasSide), Float(region.size.height) / Float(atlasSide))
        atlasEntries[key] = BrowserMetalAtlasEntry(uvOrigin: uvOrigin, uvSize: uvSize, lastUsedFrame: frameCounter)
        return true
    }

    private func allocateAtlasRegion(for size: CGSize, padding: Int = 2) -> MTLRegion? {
        let width = Int(ceil(size.width))
        let height = Int(ceil(size.height))
        guard width > 0, height > 0, width + padding * 2 <= atlasSide, height + padding * 2 <= atlasSide else {
            return nil
        }
        if atlasCursorX + width + padding * 2 > atlasSide {
            atlasCursorX = 0
            atlasCursorY += atlasRowHeight
            atlasRowHeight = 0
        }
        if atlasCursorY + height + padding * 2 > atlasSide {
            return nil
        }
        let originX = atlasCursorX + padding
        let originY = atlasCursorY + padding
        atlasCursorX += width + padding * 2
        atlasRowHeight = max(atlasRowHeight, height + padding * 2)
        return MTLRegionMake2D(originX, originY, width, height)
    }

    private func resetAtlas(clearPending: Bool = true) {
        atlasEntries.removeAll(keepingCapacity: true)
        atlasCursorX = 0
        atlasCursorY = 0
        atlasRowHeight = 0
        if clearPending {
            pendingAtlasUploads.removeAll(keepingCapacity: true)
            pendingAtlasUploadKeys.removeAll(keepingCapacity: true)
        }
    }

    private func appendStrokedPath(_ path: CGPath, color: SIMD4<Float>, width: CGFloat, into vertices: inout [BrowserMetalColorVertex]) {
        for polyline in path.flattenedPolylines(includeClosedSubpaths: true) where polyline.count >= 2 {
            for (start, end) in zip(polyline, polyline.dropFirst()) {
                appendSegment(from: start, to: end, width: width, color: color, into: &vertices)
            }
        }
    }

    private func appendFilledPath(_ path: CGPath, color: SIMD4<Float>, into vertices: inout [BrowserMetalColorVertex]) {
        for polygon in path.flattenedPolylines(includeClosedSubpaths: true) where polygon.count >= 3 {
            let anchor = polygon[0]
            for index in 1..<(polygon.count - 1) {
                vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(anchor.x), Float(anchor.y)), color: color))
                vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(polygon[index].x), Float(polygon[index].y)), color: color))
                vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(polygon[index + 1].x), Float(polygon[index + 1].y)), color: color))
            }
        }
    }

    private func appendSegment(from start: CGPoint, to end: CGPoint, width: CGFloat, color: SIMD4<Float>, into vertices: inout [BrowserMetalColorVertex]) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.0001)
        let nx = -dy / length * width / 2
        let ny = dx / length * width / 2
        let p0 = CGPoint(x: start.x + nx, y: start.y + ny)
        let p1 = CGPoint(x: start.x - nx, y: start.y - ny)
        let p2 = CGPoint(x: end.x + nx, y: end.y + ny)
        let p3 = CGPoint(x: end.x - nx, y: end.y - ny)
        vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(p0.x), Float(p0.y)), color: color))
        vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(p1.x), Float(p1.y)), color: color))
        vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(p2.x), Float(p2.y)), color: color))
        vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(p2.x), Float(p2.y)), color: color))
        vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(p1.x), Float(p1.y)), color: color))
        vertices.append(BrowserMetalColorVertex(position: SIMD2(Float(p3.x), Float(p3.y)), color: color))
    }

    private static func makeLibrary(device: MTLDevice) -> MTLLibrary? {
        if let library = try? device.makeDefaultLibrary(bundle: .main) {
            return library
        }
        if let library = try? device.makeDefaultLibrary(bundle: .module) {
            return library
        }
        if let metallibURL = Bundle.module.url(forResource: "default", withExtension: "metallib"),
           let library = try? device.makeLibrary(URL: metallibURL) {
            return library
        }
        if let metallibURL = Bundle.main.url(forResource: "default", withExtension: "metallib"),
           let library = try? device.makeLibrary(URL: metallibURL) {
            return library
        }
        guard let shaderURL = Bundle.module.url(forResource: "BrowserMetalShaders", withExtension: "metal")
                ?? Bundle.main.url(forResource: "BrowserMetalShaders", withExtension: "metal"),
              let shaderSource = try? String(contentsOf: shaderURL) else {
            return nil
        }
        let options = MTLCompileOptions()
        if #available(macOS 14.0, *) {
            options.languageVersion = .version3_1
        }
        options.fastMathEnabled = true
        return try? device.makeLibrary(source: shaderSource, options: options)
    }

    private static func makeAtlasTexture(device: MTLDevice, side: Int) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        return device.makeTexture(descriptor: descriptor)!
    }

    private static func configureAlphaBlending(for attachment: MTLRenderPipelineColorAttachmentDescriptor?) {
        guard let attachment else { return }
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    private static func rgbaBytes(for image: CGImage) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = Data(count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? bytes : nil
    }

    private static func makeFallbackTexture(device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var pixel: UInt32 = 0xFFFFFFFF
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: MemoryLayout<UInt32>.stride)
        return texture
    }
}

private struct BrowserMetalAtlasEntry {
    var uvOrigin: SIMD2<Float>
    var uvSize: SIMD2<Float>
    var lastUsedFrame: UInt64
}

private struct BrowserMetalPendingUpload {
    let key: String
    let image: CGImage
    var priority: Int
}

private struct BrowserMetalViewportUniforms {
    var viewportSize: SIMD2<Float>
    var worldScale: SIMD2<Float>
    var worldOffset: SIMD2<Float>
}

private struct BrowserMetalColorVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct BrowserMetalLabelGroupInstance {
    var center: SIMD2<Float>
    var halfSize: SIMD2<Float>
    var color: SIMD4<Float>
    var strokeWidth: Float
    var cornerRadius: Float
    var padding: SIMD2<Float> = .zero
}

private struct BrowserMetalLinkInstance {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var control1: SIMD2<Float>
    var control2: SIMD2<Float>
    var color: SIMD4<Float>
    var lineWidth: Float
    var shapeIndex: Int32
    var isArrow: Float
    var curveOffset: Float
    var padding: SIMD3<Float>
}

private struct BrowserMetalTextInstance {
    var center: SIMD2<Float>
    var size: SIMD2<Float>
    var atlasUVOrigin: SIMD2<Float>
    var atlasUVSize: SIMD2<Float>
    var tintColor: SIMD4<Float>
    var hasTexture: Float
    var cornerRadius: Float
    var yPixelOffset: Float
    var _pad: Float = 0
}

private struct BrowserMetalCardInstance {
    var center: SIMD2<Float>
    var contentSize: SIMD2<Float>
    var paddedSize: SIMD2<Float>
    var shadowOffset: SIMD2<Float>
    var atlasUVOrigin: SIMD2<Float>
    var atlasUVSize: SIMD2<Float>
    var fillColor: SIMD4<Float>
    var strokeColor: SIMD4<Float>
    var glowColor: SIMD4<Float>
    var shadowColor: SIMD4<Float>
    var strokeWidth: Float
    var glowRadius: Float
    var shadowRadius: Float
    var shapeIndex: Int32
    var hasTexture: Float
    var cornerRadius: Float
    var padding: SIMD2<Float>
}

private extension BrowserMetalRenderer {
    func buildTextInstances(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalTextInstance] {
        let hasLinkLabels = scene.links.contains(where: { ($0.labelText?.isEmpty == false) && $0.labelPoint != nil })
        let hasLabelGroupNames = !scene.labelGroups.isEmpty
        guard hasLinkLabels || hasLabelGroupNames else {
            return []
        }

        let transform = scene.worldToCanvasTransform
        let canvasCenter = CGPoint(x: scene.canvasSize.width * 0.5, y: scene.canvasSize.height * 0.5)
        var instances: [BrowserMetalTextInstance] = []
        instances.reserveCapacity(scene.links.count + scene.labelGroups.count)

        // Link labels
        for snapshot in scene.links {
            guard let text = snapshot.labelText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  let labelPoint = snapshot.labelPoint else {
                continue
            }

            let canvasPoint = labelPoint.applying(transform)
            let dx = canvasPoint.x - canvasCenter.x
            let dy = canvasPoint.y - canvasCenter.y
            let priority = Int(max(0, 90_000 - hypot(dx, dy) * 42)) + (snapshot.isHighlighted ? 60_000 : 0)
            let labelKey = browserLabelAtlasKey(for: snapshot)
            let labelImage = atlasLabelImage(text: text, highlighted: snapshot.isHighlighted)
            desiredAtlasKeys.insert(labelKey)
            let atlasEntry = atlasEntry(for: labelKey, image: labelImage, priority: priority)
            let size = labelImage.size
            instances.append(
                BrowserMetalTextInstance(
                    center: SIMD2(Float(labelPoint.x), Float(labelPoint.y)),
                    size: SIMD2(Float(size.width), Float(size.height)),
                    atlasUVOrigin: atlasEntry?.uvOrigin ?? .zero,
                    atlasUVSize: atlasEntry?.uvSize ?? .zero,
                    tintColor: SIMD4<Float>(1, 1, 1, 1),
                    hasTexture: atlasEntry == nil ? 0 : 1,
                    cornerRadius: 7,
                    yPixelOffset: -(Float(size.height) * 0.5 + 2.0)
                )
            )
        }

        // Label group names
        for snapshot in scene.labelGroups {
            let pointSize = max(10, min(CGFloat(snapshot.labelSize) * 0.12, 22))
            let labelKey = "label-group-name|\(snapshot.id)|\(snapshot.name)|\(snapshot.color)|\(Int(pointSize))"
            let strokeColor = NSColor(Color(frieveRGB: snapshot.color)).withAlphaComponent(0.72)
            let labelImage = atlasLabelGroupNameImage(name: snapshot.name, color: strokeColor, pointSize: pointSize)
            desiredAtlasKeys.insert(labelKey)
            let canvasPoint = CGPoint(x: snapshot.worldRect.midX, y: snapshot.worldRect.midY).applying(transform)
            let dx = canvasPoint.x - canvasCenter.x
            let dy = canvasPoint.y - canvasCenter.y
            let priority = Int(max(0, 80_000 - hypot(dx, dy) * 42))
            let atlasEntry = atlasEntry(for: labelKey, image: labelImage, priority: priority)
            let size = labelImage.size
            // Position text at the world-space rect edge; use yPixelOffset for
            // the fixed pixel-space gap (14px label padding + 8px margin + half text height)
            // so the offset stays valid across zoom levels without rebuilding.
            let anchorY: Float
            let yPixelOffset: Float
            if snapshot.prefersNameAbove {
                anchorY = Float(snapshot.worldRect.minY)
                yPixelOffset = -(14 + 8 + Float(size.height) * 0.5)
            } else {
                anchorY = Float(snapshot.worldRect.maxY)
                yPixelOffset = 14 + 8 + Float(size.height) * 0.5
            }
            instances.append(
                BrowserMetalTextInstance(
                    center: SIMD2(Float(snapshot.worldRect.midX), anchorY),
                    size: SIMD2(Float(size.width), Float(size.height)),
                    atlasUVOrigin: atlasEntry?.uvOrigin ?? .zero,
                    atlasUVSize: atlasEntry?.uvSize ?? .zero,
                    tintColor: SIMD4<Float>(1, 1, 1, 1),
                    hasTexture: atlasEntry == nil ? 0 : 1,
                    cornerRadius: 0,
                    yPixelOffset: yPixelOffset
                )
            )
        }

        var activeLabelKeys = scene.links.compactMap { snapshot -> String? in
            guard let text = snapshot.labelText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  snapshot.labelPoint != nil else {
                return nil
            }
            return browserLabelAtlasKey(for: snapshot)
        }
        activeLabelKeys += scene.labelGroups.map { snapshot in
            let pointSize = max(10, min(CGFloat(snapshot.labelSize) * 0.12, 22))
            return "label-group-name|\(snapshot.id)|\(snapshot.name)|\(snapshot.color)|\(Int(pointSize))"
        }
        trimLabelImageCache(activeKeys: activeLabelKeys)
        return instances
    }

    func makeLinkBodyInstance(
        start: CGPoint,
        end: CGPoint,
        shapeIndex: Int,
        lineWidth: Float,
        color: SIMD4<Float>
    ) -> BrowserMetalLinkInstance {
        BrowserMetalLinkInstance(
            start: SIMD2(Float(start.x), Float(start.y)),
            end: SIMD2(Float(end.x), Float(end.y)),
            control1: .zero,
            control2: .zero,
            color: color,
            lineWidth: lineWidth,
            shapeIndex: Int32(shapeIndex),
            isArrow: 0,
            curveOffset: 0,
            padding: .zero
        )
    }

    func makeLinkSegmentInstances(
        start: CGPoint,
        end: CGPoint,
        shapeIndex: Int,
        lineWidth: Float,
        color: SIMD4<Float>
    ) -> [BrowserMetalLinkInstance] {
        switch abs(shapeIndex % 6) {
        case 2, 4:
            let midX = (start.x + end.x) / 2
            let elbowA = CGPoint(x: midX, y: start.y)
            let elbowB = CGPoint(x: midX, y: end.y)
            return [
                makeLinkBodyInstance(start: start, end: elbowA, shapeIndex: shapeIndex, lineWidth: lineWidth, color: color),
                makeLinkBodyInstance(start: elbowA, end: elbowB, shapeIndex: shapeIndex, lineWidth: lineWidth, color: color),
                makeLinkBodyInstance(start: elbowB, end: end, shapeIndex: shapeIndex, lineWidth: lineWidth, color: color)
            ].filter { distanceSquared(from: $0.start, to: $0.end) > 0.00000001 }
        default:
            return [makeLinkBodyInstance(start: start, end: end, shapeIndex: shapeIndex, lineWidth: lineWidth, color: color)]
        }
    }

    func makeArrowInstances(
        start: CGPoint,
        end: CGPoint,
        shapeIndex: Int,
        baseScale: CGFloat = 1,
        lineWidth: Float,
        color: SIMD4<Float>
    ) -> [BrowserMetalLinkInstance] {
        let arrowLineWidth = max(lineWidth * 1.4, lineWidth + 1)
        guard let segments = browserLinkArrowStrokeSegments(
            shapeIndex: shapeIndex,
            start: start,
            end: end,
            baseScale: baseScale
        ) else {
            return []
        }
        return [
            (segments.leftStart, segments.leftEnd),
            (segments.rightStart, segments.rightEnd)
        ]
        .filter {
            distanceSquared(
                from: SIMD2(Float($0.0.x), Float($0.0.y)),
                to: SIMD2(Float($0.1.x), Float($0.1.y))
            ) > 0.00000001
        }
        .map { makeLinkBodyInstance(start: $0.0, end: $0.1, shapeIndex: 0, lineWidth: arrowLineWidth, color: color) }
    }

    func applyDesiredAtlasKeys() {
        visibleAtlasKeys = desiredAtlasKeys
        guard !visibleAtlasKeys.isEmpty else {
            pendingAtlasUploads.removeAll(keepingCapacity: true)
            pendingAtlasUploadKeys.removeAll(keepingCapacity: true)
            return
        }
        pendingAtlasUploads.removeAll { !visibleAtlasKeys.contains($0.key) }
        pendingAtlasUploadKeys = Set(pendingAtlasUploads.map(\.key))
    }

    func browserLabelAtlasKey(for snapshot: BrowserLinkLayerSnapshot) -> String {
        let state = snapshot.isHighlighted ? "selected" : "normal"
        return "link-label|\(appearanceSignature)|\(state)|\(snapshot.labelText ?? "")"
    }

    func atlasLabelImage(text: String, highlighted: Bool) -> NSImage {
        let cacheKey = "\(appearanceSignature)|\(highlighted ? 1 : 0)|\(text)"
        if let cached = labelImageCache[cacheKey] {
            touchLabelImageOrder(cacheKey)
            return cached
        }

        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let foreground = highlighted ? NSColor.white : NSColor.secondaryLabelColor
        let background = highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.92) : NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        let border = highlighted ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.55)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let padding = CGSize(width: 14, height: 6)
        let imageSize = CGSize(width: ceil(textSize.width + padding.width), height: ceil(textSize.height + padding.height))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        let rect = CGRect(origin: .zero, size: imageSize)
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        background.setFill()
        backgroundPath.fill()
        border.setStroke()
        backgroundPath.lineWidth = highlighted ? 1.2 : 1
        backgroundPath.stroke()
        attributed.draw(in: CGRect(
            x: (imageSize.width - textSize.width) / 2,
            y: (imageSize.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        ))
        image.unlockFocus()
        labelImageCache[cacheKey] = image
        touchLabelImageOrder(cacheKey)
        trimLabelImageCache(activeKeys: [cacheKey])
        return image
    }

    func atlasLabelGroupNameImage(name: String, color: NSColor, pointSize: CGFloat) -> NSImage {
        let cacheKey = "lg|\(color.hashValue)|\(Int(pointSize))|\(name)"
        if let cached = labelImageCache[cacheKey] {
            touchLabelImageOrder(cacheKey)
            return cached
        }

        let font = NSFont.systemFont(ofSize: pointSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: name, attributes: attributes)
        let textSize = attributed.size()
        let imageSize = CGSize(width: ceil(textSize.width + 4), height: ceil(textSize.height + 2))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        attributed.draw(in: CGRect(
            x: (imageSize.width - textSize.width) / 2,
            y: (imageSize.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        ))
        image.unlockFocus()
        labelImageCache[cacheKey] = image
        touchLabelImageOrder(cacheKey)
        trimLabelImageCache(activeKeys: [cacheKey])
        return image
    }

    func trimLabelImageCache(activeKeys: [String]) {
        let activeSet = Set(activeKeys)
        labelImageOrder.removeAll { !labelImageCache.keys.contains($0) }
        while labelImageOrder.count > 256 {
            if let removableIndex = labelImageOrder.firstIndex(where: { !activeSet.contains($0) }) {
                let key = labelImageOrder.remove(at: removableIndex)
                labelImageCache.removeValue(forKey: key)
            } else {
                break
            }
        }
    }

    func touchLabelImageOrder(_ key: String) {
        labelImageOrder.removeAll { $0 == key }
        labelImageOrder.append(key)
    }

    func distanceSquared(from start: SIMD2<Float>, to end: SIMD2<Float>) -> Float {
        let delta = end - start
        return simd_length_squared(delta)
    }
}

private extension MTLClearColor {
    init(color: NSColor) {
        let rgba = color.rgbaVector
        self.init(red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z), alpha: Double(rgba.w))
    }
}

private extension NSColor {
    func browserOpaqueComposite(over background: NSColor, opacity: CGFloat, darkModeLift: CGFloat = 0) -> NSColor {
        let foregroundRGB = (usingColorSpace(.deviceRGB) ?? self)
        let backgroundRGB = (background.usingColorSpace(.deviceRGB) ?? background)
        let alpha = max(0, min(1, opacity * foregroundRGB.alphaComponent))
        let inverseAlpha = 1 - alpha
        let composite = NSColor(
            red: foregroundRGB.redComponent * alpha + backgroundRGB.redComponent * inverseAlpha,
            green: foregroundRGB.greenComponent * alpha + backgroundRGB.greenComponent * inverseAlpha,
            blue: foregroundRGB.blueComponent * alpha + backgroundRGB.blueComponent * inverseAlpha,
            alpha: 1
        )
        guard darkModeLift > 0 else { return composite }
        let luminance =
            0.2126 * backgroundRGB.redComponent +
            0.7152 * backgroundRGB.greenComponent +
            0.0722 * backgroundRGB.blueComponent
        guard luminance < 0.5 else { return composite }
        let lift = max(0, min(1, darkModeLift))
        return NSColor(
            red: composite.redComponent + (1 - composite.redComponent) * lift,
            green: composite.greenComponent + (1 - composite.greenComponent) * lift,
            blue: composite.blueComponent + (1 - composite.blueComponent) * lift,
            alpha: 1
        )
    }

    var rgbaVector: SIMD4<Float> {
        let converted = usingColorSpace(.deviceRGB) ?? self
        return SIMD4(
            Float(converted.redComponent),
            Float(converted.greenComponent),
            Float(converted.blueComponent),
            Float(converted.alphaComponent)
        )
    }
}

private extension NSImage {
    var browserCGImage: CGImage? {
        let imageSize = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        var rect = CGRect(origin: .zero, size: imageSize)
        if let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cgImage
        }
        if let cgImage = representations.compactMap({ ($0 as? NSBitmapImageRep)?.cgImage }).first {
            return cgImage
        }
        if let tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffRepresentation),
           let cgImage = bitmap.cgImage {
            return cgImage
        }

        let scale = representations
            .compactMap { rep -> CGFloat? in
                guard rep.size.width > 0,
                      rep.size.height > 0,
                      rep.pixelsWide > 0,
                      rep.pixelsHigh > 0 else {
                    return nil
                }
                return max(
                    CGFloat(rep.pixelsWide) / rep.size.width,
                    CGFloat(rep.pixelsHigh) / rep.size.height
                )
            }
            .max() ?? (NSScreen.main?.backingScaleFactor ?? 2)
        let pixelWidth = max(Int(ceil(imageSize.width * scale)), 1)
        let pixelHeight = max(Int(ceil(imageSize.height * scale)), 1)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = imageSize
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(
            in: CGRect(origin: .zero, size: imageSize),
            from: CGRect(origin: .zero, size: imageSize),
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}

private extension CGPath {
    func flattenedPolylines(includeClosedSubpaths: Bool = false, curveSamples: Int = 16) -> [[CGPoint]] {
        var polylines: [[CGPoint]] = []
        var current: [CGPoint] = []
        var currentPoint: CGPoint = .zero
        var firstPoint: CGPoint?

        forEach { element in
            switch element.type {
            case .moveToPoint:
                if current.count > 1 {
                    polylines.append(current)
                }
                current = [element.points[0]]
                currentPoint = element.points[0]
                firstPoint = element.points[0]
            case .addLineToPoint:
                current.append(element.points[0])
                currentPoint = element.points[0]
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                for sample in 1...curveSamples {
                    let t = CGFloat(sample) / CGFloat(curveSamples)
                    current.append(self.quadraticBezier(from: currentPoint, control: control, to: end, t: t))
                }
                currentPoint = end
            case .addCurveToPoint:
                let c1 = element.points[0]
                let c2 = element.points[1]
                let end = element.points[2]
                for sample in 1...curveSamples {
                    let t = CGFloat(sample) / CGFloat(curveSamples)
                    current.append(self.cubicBezier(from: currentPoint, control1: c1, control2: c2, to: end, t: t))
                }
                currentPoint = end
            case .closeSubpath:
                if includeClosedSubpaths, let firstPoint {
                    current.append(firstPoint)
                }
                if current.count > 1 {
                    polylines.append(current)
                }
                current.removeAll(keepingCapacity: true)
                firstPoint = nil
            @unknown default:
                break
            }
        }

        if current.count > 1 {
            polylines.append(current)
        }
        return polylines
    }

    private func forEach(_ body: @escaping (CGPathElement) -> Void) {
        typealias Body = @convention(block) (CGPathElement) -> Void
        let callback: Body = body
        let unsafeBody = unsafeBitCast(callback, to: UnsafeMutableRawPointer.self)
        apply(info: unsafeBody) { info, element in
            let body = unsafeBitCast(info, to: Body.self)
            body(element.pointee)
        }
    }

    private func quadraticBezier(from start: CGPoint, control: CGPoint, to end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        let x = inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x
        let y = inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private func cubicBezier(from start: CGPoint, control1: CGPoint, control2: CGPoint, to end: CGPoint, t: CGFloat) -> CGPoint {
        let inverse = 1 - t
        let x = inverse * inverse * inverse * start.x
            + 3 * inverse * inverse * t * control1.x
            + 3 * inverse * t * t * control2.x
            + t * t * t * end.x
        let y = inverse * inverse * inverse * start.y
            + 3 * inverse * inverse * t * control1.y
            + 3 * inverse * t * t * control2.y
            + t * t * t * end.y
        return CGPoint(x: x, y: y)
    }
}
