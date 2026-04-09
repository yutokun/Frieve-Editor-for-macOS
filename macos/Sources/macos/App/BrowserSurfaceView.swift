import SwiftUI
import AppKit

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
        nsView.updateScene(viewModel.browserSurfaceScene(in: canvasSize), canvasSize: canvasSize)
    }

    private func configure(_ view: BrowserSurfaceNSView) {
        view.viewModel = viewModel
        view.onScroll = { deltaX, deltaY, location, modifiers in
            viewModel.handleScrollWheel(deltaX: deltaX, deltaY: deltaY, modifiers: modifiers, at: location, in: canvasSize)
        }
        view.onDelete = {
            viewModel.deleteSelectedCard()
        }
        view.onMoveSelection = { dx, dy in
            viewModel.nudgeSelection(dx: dx, dy: dy)
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
    }
}

final class BrowserSurfaceNSView: BrowserInteractionNSView {
    weak var viewModel: WorkspaceViewModel?

    private let guideLayer = CAShapeLayer()
    private let contentTransformLayer = CALayer()
    private let linksLayer = BrowserLinkSceneLayer()
    private let cardsLayer = CALayer()
    private let linkLabelsLayer = CALayer()
    private let selectionOverlayLayer = CAShapeLayer()
    private let marqueeOverlayLayer = CAShapeLayer()
    private let linkPreviewLayer = CAShapeLayer()
    private var cardLayers: [Int: BrowserCardHostLayer] = [:]
    private var labelLayers: [UUID: CATextLayer] = [:]
    private var trackingAreaRef: NSTrackingArea?
    private var mouseDownPoint: CGPoint?
    private var mouseDownCardID: Int?
    private var mouseDownModifiers: NSEvent.ModifierFlags = []
    private var interactionDidDrag = false
    private var currentHitRegions: [BrowserCardHitRegion] = []
    private var lastViewportSummary: String?
    private var lastTransform: CGAffineTransform = .identity
    private var lastCardSnapshotHash: Int?
    private var lastLinkSnapshotHash: Int?
    private var lastOverlaySignature: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
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
        layer?.frame = bounds
        guideLayer.frame = bounds
        contentTransformLayer.frame = bounds
        linksLayer.frame = bounds
        cardsLayer.frame = bounds
        linkLabelsLayer.frame = bounds
        selectionOverlayLayer.frame = bounds
        marqueeOverlayLayer.frame = bounds
        linkPreviewLayer.frame = bounds
    }

    override func mouseMoved(with event: NSEvent) {
        guard let viewModel else { return }
        let point = convert(event.locationInWindow, from: nil)
        viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point) ?? viewModel.hitTestCard(at: point, in: bounds.size)?.id)
    }

    override func mouseExited(with event: NSEvent) {
        viewModel?.setBrowserHoverCard(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        mouseDownModifiers = event.modifierFlags
        mouseDownCardID = cardID(atCanvasPoint: point) ?? viewModel?.hitTestCard(at: point, in: bounds.size)?.id
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

    override func mouseDragged(with event: NSEvent) {
        guard let viewModel, let mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 1 {
            interactionDidDrag = true
        }

        if let mouseDownCardID {
            viewModel.updateCardInteraction(cardID: mouseDownCardID, from: mouseDownPoint, to: point, in: bounds.size, modifiers: mouseDownModifiers)
        } else {
            if !viewModel.hasActiveBrowserGesture {
                viewModel.beginCanvasGesture(at: mouseDownPoint, modifiers: mouseDownModifiers)
            }
            viewModel.updateCanvasGesture(from: mouseDownPoint, to: point, in: bounds.size)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetPointerInteraction() }
        guard let viewModel, let mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)

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
            viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point) ?? viewModel.hitTestCard(at: point, in: bounds.size)?.id)
        }
        _ = mouseDownPoint
    }

    override func magnify(with event: NSEvent) {
        guard let viewModel else { return }
        let location = convert(event.locationInWindow, from: nil)
        let factor = max(0.2, 1.0 + event.magnification)
        viewModel.zoom(by: factor, anchor: location, in: bounds.size)
    }

    func updateScene(_ scene: BrowserSurfaceSceneSnapshot, canvasSize: CGSize) {
        let sceneScale = max(abs(scene.worldToCanvasTransform.a), 1)
        let cardSnapshotHash = hashCardSnapshots(scene.cards)
        let linkSnapshotHash = hashLinkSnapshots(scene.links)
        let overlaySignature = hashOverlay(scene.overlay)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 1

        if lastViewportSummary != scene.viewportSummary {
            guideLayer.path = scene.backgroundGuidePath
            lastViewportSummary = scene.viewportSummary
        }
        if lastTransform != scene.worldToCanvasTransform {
            contentTransformLayer.setAffineTransform(scene.worldToCanvasTransform)
            lastTransform = scene.worldToCanvasTransform
        }

        if lastLinkSnapshotHash != linkSnapshotHash || linksLayer.sceneScale != sceneScale {
            linksLayer.sceneScale = sceneScale
            linksLayer.linkSnapshots = scene.links
            synchronizeLabelLayers(for: scene.links, transform: scene.worldToCanvasTransform)
            lastLinkSnapshotHash = linkSnapshotHash
        }
        currentHitRegions = scene.hitRegions
        if lastCardSnapshotHash != cardSnapshotHash {
            synchronizeCardLayers(for: scene.cards, sceneScale: sceneScale)
            lastCardSnapshotHash = cardSnapshotHash
        }
        if lastOverlaySignature != overlaySignature {
            applyOverlay(scene.overlay)
            lastOverlaySignature = overlaySignature
        }

        CATransaction.commit()
    }

    private func commonInit() {
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.masksToBounds = true
        rootLayer.cornerRadius = 12
        layer = rootLayer

        guideLayer.fillColor = nil
        guideLayer.strokeColor = NSColor.secondaryLabelColor.withAlphaComponent(0.08).cgColor
        guideLayer.lineWidth = 0.7

        contentTransformLayer.anchorPoint = .zero
        contentTransformLayer.position = .zero
        contentTransformLayer.masksToBounds = false

        linksLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        cardsLayer.masksToBounds = false
        linkLabelsLayer.masksToBounds = false

        selectionOverlayLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
        selectionOverlayLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
        selectionOverlayLayer.lineDashPattern = [7, 4]

        marqueeOverlayLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        marqueeOverlayLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        marqueeOverlayLayer.lineDashPattern = [6, 4]

        linkPreviewLayer.fillColor = nil
        linkPreviewLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor
        linkPreviewLayer.lineDashPattern = [8, 5]
        linkPreviewLayer.lineWidth = 2

        contentTransformLayer.addSublayer(linksLayer)
        contentTransformLayer.addSublayer(cardsLayer)

        rootLayer.addSublayer(guideLayer)
        rootLayer.addSublayer(contentTransformLayer)
        rootLayer.addSublayer(linkLabelsLayer)
        rootLayer.addSublayer(selectionOverlayLayer)
        rootLayer.addSublayer(marqueeOverlayLayer)
        rootLayer.addSublayer(linkPreviewLayer)
    }

    private func resetPointerInteraction() {
        mouseDownPoint = nil
        mouseDownCardID = nil
        mouseDownModifiers = []
        interactionDidDrag = false
    }

    private func cardID(atCanvasPoint point: CGPoint) -> Int? {
        for region in currentHitRegions.reversed() {
            if region.frame.contains(point) {
                return region.cardID
            }
        }
        guard let hitLayer = layer?.hitTest(point) else { return nil }
        var current: CALayer? = hitLayer
        while let layer = current {
            if let host = layer as? BrowserCardHostLayer {
                return host.cardID
            }
            current = layer.superlayer
        }
        return nil
    }

    private func hashCardSnapshots(_ snapshots: [BrowserCardLayerSnapshot]) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshots.count)
        for snapshot in snapshots {
            hasher.combine(snapshot)
        }
        return hasher.finalize()
    }

    private func hashLinkSnapshots(_ snapshots: [BrowserLinkLayerSnapshot]) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshots.count)
        for snapshot in snapshots {
            hasher.combine(snapshot.id)
            hasher.combine(snapshot.labelText)
            hasher.combine(snapshot.isHighlighted)
            if let labelPoint = snapshot.labelPoint {
                hasher.combine(labelPoint.x)
                hasher.combine(labelPoint.y)
            } else {
                hasher.combine(-1.0)
                hasher.combine(-1.0)
            }
            let pathBox = snapshot.path.boundingBoxOfPath
            hasher.combine(pathBox.minX)
            hasher.combine(pathBox.minY)
            hasher.combine(pathBox.width)
            hasher.combine(pathBox.height)
            let arrowBox = snapshot.arrowHead?.boundingBoxOfPath ?? .null
            hasher.combine(arrowBox.minX)
            hasher.combine(arrowBox.minY)
            hasher.combine(arrowBox.width)
            hasher.combine(arrowBox.height)
        }
        return hasher.finalize()
    }

    private func hashOverlay(_ overlay: BrowserOverlaySnapshot) -> Int {
        var hasher = Hasher()
        if let selectionFrame = overlay.selectionFrame {
            hasher.combine(selectionFrame.minX)
            hasher.combine(selectionFrame.minY)
            hasher.combine(selectionFrame.width)
            hasher.combine(selectionFrame.height)
        } else {
            hasher.combine(-1.0)
        }
        if let marqueeRect = overlay.marqueeRect {
            hasher.combine(marqueeRect.minX)
            hasher.combine(marqueeRect.minY)
            hasher.combine(marqueeRect.width)
            hasher.combine(marqueeRect.height)
        } else {
            hasher.combine(-2.0)
        }
        if let preview = overlay.linkPreviewSegment {
            hasher.combine(preview.0.x)
            hasher.combine(preview.0.y)
            hasher.combine(preview.1.x)
            hasher.combine(preview.1.y)
        } else {
            hasher.combine(-3.0)
        }
        return hasher.finalize()
    }

    private func synchronizeCardLayers(for snapshots: [BrowserCardLayerSnapshot], sceneScale: CGFloat) {
        guard let viewModel else { return }
        var activeIDs = Set<Int>()
        for snapshot in snapshots {
            activeIDs.insert(snapshot.id)
            let layer = cardLayers[snapshot.id] ?? {
                let layer = BrowserCardHostLayer()
                cardsLayer.addSublayer(layer)
                cardLayers[snapshot.id] = layer
                return layer
            }()
            let rasterKey = viewModel.browserCardRasterKey(for: snapshot)
            let raster = layer.needsRasterUpdate(for: snapshot, rasterKey: rasterKey, sceneScale: sceneScale)
                ? viewModel.cachedBrowserCardRaster(for: snapshot, cacheKey: rasterKey)
                : nil
            layer.apply(snapshot: snapshot, rasterKey: rasterKey, rasterImage: raster, sceneScale: sceneScale, viewModel: viewModel)
        }

        for removedID in cardLayers.keys.filter({ !activeIDs.contains($0) }) {
            cardLayers[removedID]?.removeFromSuperlayer()
            cardLayers.removeValue(forKey: removedID)
        }
    }

    private func synchronizeLabelLayers(for snapshots: [BrowserLinkLayerSnapshot], transform: CGAffineTransform) {
        var activeIDs = Set<UUID>()
        for snapshot in snapshots {
            guard let text = snapshot.labelText, !text.isEmpty, let labelPoint = snapshot.labelPoint else { continue }
            activeIDs.insert(snapshot.id)
            let layer = labelLayers[snapshot.id] ?? {
                let layer = CATextLayer()
                layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                layer.alignmentMode = .center
                layer.truncationMode = .end
                layer.foregroundColor = NSColor.secondaryLabelColor.cgColor
                linkLabelsLayer.addSublayer(layer)
                labelLayers[snapshot.id] = layer
                return layer
            }()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributed.size()
            let canvasPoint = labelPoint.applying(transform)
            layer.string = attributed
            layer.frame = CGRect(
                x: canvasPoint.x - textSize.width / 2 - 6,
                y: canvasPoint.y - textSize.height - 2,
                width: textSize.width + 12,
                height: textSize.height + 4
            )
        }

        for removedID in labelLayers.keys.filter({ !activeIDs.contains($0) }) {
            labelLayers[removedID]?.removeFromSuperlayer()
            labelLayers.removeValue(forKey: removedID)
        }
    }

    private func applyOverlay(_ overlay: BrowserOverlaySnapshot) {
        if let selectionFrame = overlay.selectionFrame {
            selectionOverlayLayer.path = CGPath(roundedRect: selectionFrame.insetBy(dx: -9, dy: -9), cornerWidth: 18, cornerHeight: 18, transform: nil)
            selectionOverlayLayer.isHidden = false
        } else {
            selectionOverlayLayer.path = nil
            selectionOverlayLayer.isHidden = true
        }

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
}

private final class BrowserLinkSceneLayer: CALayer {
    var linkSnapshots: [BrowserLinkLayerSnapshot] = [] {
        didSet { setNeedsDisplay() }
    }
    var sceneScale: CGFloat = 1 {
        didSet { setNeedsDisplay() }
    }

    override init() {
        super.init()
        contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(in context: CGContext) {
        context.setShouldAntialias(true)
        for snapshot in linkSnapshots {
            let color = snapshot.isHighlighted
                ? NSColor.controlAccentColor.withAlphaComponent(0.85)
                : NSColor.secondaryLabelColor.withAlphaComponent(0.42)
            context.addPath(snapshot.path)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth((snapshot.isHighlighted ? 3 : 2) / max(sceneScale, 1))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()

            if let arrowHead = snapshot.arrowHead {
                context.addPath(arrowHead)
                context.setFillColor(color.cgColor)
                context.fillPath()
            }
        }
    }
}

private final class BrowserCardHostLayer: CALayer {
    var cardID: Int?

    private let glowLayer = CAShapeLayer()
    private let rasterLayer = CALayer()
    private let strokeLayer = CAShapeLayer()
    private let maskLayerShape = CAShapeLayer()
    private var lastSnapshot: BrowserCardLayerSnapshot?
    private var lastRasterKey: String?
    private var lastSceneScale: CGFloat = 0

    override init() {
        super.init()
        masksToBounds = false
        rasterLayer.contentsGravity = .resize
        rasterLayer.masksToBounds = true
        rasterLayer.mask = maskLayerShape
        addSublayer(glowLayer)
        addSublayer(rasterLayer)
        addSublayer(strokeLayer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func needsRasterUpdate(for snapshot: BrowserCardLayerSnapshot, rasterKey: String, sceneScale: CGFloat) -> Bool {
        guard let lastSnapshot else { return true }
        if lastSnapshot.card != snapshot.card || lastSnapshot.metadata != snapshot.metadata || lastSnapshot.detailLevel != snapshot.detailLevel {
            return true
        }
        return lastRasterKey != rasterKey
    }

    @MainActor
    func apply(snapshot: BrowserCardLayerSnapshot, rasterKey: String, rasterImage: NSImage?, sceneScale: CGFloat, viewModel: WorkspaceViewModel) {
        if lastSnapshot == snapshot,
           lastRasterKey == rasterKey,
           abs(lastSceneScale - sceneScale) < 0.0001 {
            return
        }

        cardID = snapshot.id
        let normalizedScale = max(sceneScale, 1)
        let worldSize = CGSize(
            width: snapshot.metadata.canvasSize.width / normalizedScale,
            height: snapshot.metadata.canvasSize.height / normalizedScale
        )
        bounds = CGRect(origin: .zero, size: worldSize)
        position = CGPoint(x: snapshot.position.x, y: snapshot.position.y)

        let shapePath = BrowserCardShape.cgPath(in: bounds, shapeIndex: snapshot.card.shape)
        glowLayer.frame = bounds
        glowLayer.path = shapePath
        glowLayer.fillColor = NSColor(viewModel.browserCardGlow(for: snapshot.card, isSelected: snapshot.isSelected)).cgColor

        rasterLayer.frame = bounds
        rasterLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        maskLayerShape.frame = bounds
        maskLayerShape.path = shapePath
        rasterLayer.contents = rasterImage?.browserCGImage ?? rasterLayer.contents

        strokeLayer.frame = bounds
        strokeLayer.path = shapePath
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = NSColor(
            viewModel.browserCardStrokeColor(
                for: snapshot.card,
                isSelected: snapshot.isSelected,
                isHovered: snapshot.isHovered
            )
        ).cgColor
        strokeLayer.lineWidth = (snapshot.isSelected ? 3 : (snapshot.isHovered ? 2 : 1)) / normalizedScale

        shadowPath = shapePath
        shadowColor = NSColor(
            viewModel.browserCardShadow(
                for: snapshot.card,
                isSelected: snapshot.isSelected,
                isHovered: snapshot.isHovered
            )
        ).cgColor
        shadowOpacity = 1
        shadowRadius = (snapshot.isSelected ? 12 : (snapshot.isHovered ? 10 : 8)) / normalizedScale
        shadowOffset = CGSize(width: 0, height: 3 / normalizedScale)
        lastSnapshot = snapshot
        lastRasterKey = rasterKey
        lastSceneScale = sceneScale
    }
}

private extension NSImage {
    var browserCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
