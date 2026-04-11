import SwiftUI
import AppKit
import MetalKit

struct BrowserSurfaceState: Equatable {
    let contentRevision: Int
    let viewportRevision: Int
    let presentationRevision: Int
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
        viewModel.browserSurfaceViewportRefreshHandler = { [weak view] in
            view?.refreshFromViewModel()
        }
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

@MainActor
private final class BrowserOverlayHostView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class BrowserSurfaceNSView: BrowserInteractionNSView {
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
    private var currentHitRegions: [BrowserCardHitRegion] = []
    private var lastOverlaySignature: Int?
    private var lastSurfaceState: BrowserSurfaceState?
    private var lastCanvasSize: CGSize = .zero
    private var labelGroupTextFields: [Int: NSTextField] = [:]

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

    override func mouseMoved(with event: NSEvent) {
        guard let viewModel else { return }
        let point = browserEventPoint(from: event)
        viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point) ?? viewModel.hitTestCard(at: point, in: bounds.size)?.id)
    }

    override func mouseExited(with event: NSEvent) {
        viewModel?.setBrowserHoverCard(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = browserEventPoint(from: event)
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
                viewModel.beginCanvasGesture(at: mouseDownPoint, modifiers: mouseDownModifiers)
            }
            viewModel.updateCanvasGesture(from: mouseDownPoint, to: point, in: bounds.size)
        }
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
            viewModel.setBrowserHoverCard(cardID(atCanvasPoint: point) ?? viewModel.hitTestCard(at: point, in: bounds.size)?.id)
        }
    }

    override func magnify(with event: NSEvent) {
        guard let viewModel else { return }
        let location = browserEventPoint(from: event)
        let factor = max(0.2, 1.0 + event.magnification)
        viewModel.zoom(by: factor, anchor: location, in: bounds.size)
    }

    func updateSceneIfNeeded(state: BrowserSurfaceState, canvasSize: CGSize) {
        guard let viewModel else { return }
        let needsScene = lastSurfaceState.map {
            $0.contentRevision != state.contentRevision ||
            $0.viewportRevision != state.viewportRevision ||
            $0.presentationRevision != state.presentationRevision ||
            $0.hoverCardID != state.hoverCardID ||
            $0.selectedCardIDs != state.selectedCardIDs ||
            $0.inlineEditorCardID != state.inlineEditorCardID ||
            $0.marqueeStartPoint != state.marqueeStartPoint ||
            $0.marqueeCurrentPoint != state.marqueeCurrentPoint ||
            $0.linkPreviewSourceCardID != state.linkPreviewSourceCardID ||
            $0.linkPreviewCanvasPoint != state.linkPreviewCanvasPoint ||
            $0.linkLabelsVisible != state.linkLabelsVisible ||
            $0.labelRectanglesVisible != state.labelRectanglesVisible ||
            $0.canvasCenter != state.canvasCenter ||
            $0.zoom != state.zoom ||
            $0.viewportSummary != state.viewportSummary
        } ?? true
        let sizeChanged = lastCanvasSize != canvasSize
        lastSurfaceState = state
        lastCanvasSize = canvasSize
        guard needsScene || sizeChanged else { return }
        updateScene(viewModel.browserSurfaceScene(in: canvasSize), canvasSize: canvasSize)
    }

    func refreshFromViewModel() {
        guard let viewModel else { return }
        let canvasSize = bounds.size
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let state = BrowserSurfaceState(
            contentRevision: viewModel.browserSurfaceContentRevision,
            viewportRevision: viewModel.browserSurfaceViewportRevision,
            presentationRevision: viewModel.browserSurfacePresentationRevision,
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

    func updateScene(_ scene: BrowserSurfaceSceneSnapshot, canvasSize: CGSize) {
        let updateStart = CACurrentMediaTime()
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 0.5
        currentHitRegions = scene.hitRegions

        renderer.updateScene(scene)
        metalView.draw()

        if lastOverlaySignature != scene.overlaySignature {
            applyOverlay(scene.overlay)
            lastOverlaySignature = scene.overlaySignature
        }
        applyLabelGroups(scene.labelGroups, transform: scene.worldToCanvasTransform)
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
    }

    private var windowBackingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func resetPointerInteraction() {
        mouseDownPoint = nil
        mouseDownCardID = nil
        mouseDownModifiers = []
        interactionDidDrag = false
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

    private func applyLabelGroups(_ groups: [BrowserLabelGroupLayerSnapshot], transform: CGAffineTransform) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let activeIDs = Set(groups.map(\.id))
        for (id, field) in labelGroupTextFields where !activeIDs.contains(id) {
            field.removeFromSuperview()
            labelGroupTextFields.removeValue(forKey: id)
        }

        for snapshot in groups {
            let strokeColor = NSColor(Color(frieveRGB: snapshot.color)).withAlphaComponent(0.72)
            let canvasRect = snapshot.worldRect
                .applying(transform)
                .insetBy(dx: -14, dy: -14)
                .integral

            let pointSize = max(10, min(CGFloat(snapshot.labelSize) * 0.12, 22))
            let textField = labelGroupTextFields[snapshot.id] ?? {
                let field = NSTextField(labelWithString: "")
                field.isBezeled = false
                field.isBordered = false
                field.isEditable = false
                field.isSelectable = false
                field.drawsBackground = false
                field.backgroundColor = .clear
                field.lineBreakMode = .byClipping
                field.maximumNumberOfLines = 1
                overlayView.addSubview(field)
                labelGroupTextFields[snapshot.id] = field
                return field
            }()
            textField.stringValue = snapshot.name
            textField.textColor = strokeColor
            textField.font = NSFont.systemFont(ofSize: pointSize, weight: .semibold)
            textField.alignment = .center
            textField.sizeToFit()

            let fitting = textField.fittingSize
            let originY = snapshot.prefersNameAbove
                ? canvasRect.minY - fitting.height - 8
                : canvasRect.maxY + 8
            textField.frame = CGRect(
                x: canvasRect.midX - fitting.width * 0.5,
                y: originY,
                width: fitting.width,
                height: fitting.height
            ).integral
            textField.isHidden = false
        }
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

    func updateScene(_ scene: BrowserSurfaceSceneSnapshot) {
        self.scene = scene
        rebuildResources()
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

        var viewport = BrowserMetalViewportUniforms(viewportSize: SIMD2(Float(scene.canvasSize.width), Float(scene.canvasSize.height)))
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
            solidVertexBuffer = device.makeBuffer(bytes: solidVertices, length: MemoryLayout<BrowserMetalColorVertex>.stride * solidVertices.count)
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
            labelGroupInstanceBuffer = device.makeBuffer(bytes: labelGroupInstances, length: MemoryLayout<BrowserMetalLabelGroupInstance>.stride * labelGroupInstances.count)
        }
    }

    private func buildLabelGroupInstances(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalLabelGroupInstance] {
        let transform = scene.worldToCanvasTransform
        return scene.labelGroups.map { snapshot in
            let canvasRect = snapshot.worldRect.applying(transform).insetBy(dx: -14, dy: -14).integral
            return BrowserMetalLabelGroupInstance(
                center: SIMD2(Float(canvasRect.midX), Float(canvasRect.midY)),
                halfSize: SIMD2(Float(canvasRect.width / 2), Float(canvasRect.height / 2)),
                color: NSColor(Color(frieveRGB: snapshot.color)).withAlphaComponent(0.72).rgbaVector,
                strokeWidth: 3,
                cornerRadius: Float(min(14, min(canvasRect.width, canvasRect.height) * 0.12)),
                padding: .zero
            )
        }
    }

    private func rebuildLinkResources(for scene: BrowserSurfaceSceneSnapshot) {
        linkInstances = buildLinkInstances(for: scene)
        if linkInstances.isEmpty {
            linkInstanceBuffer = nil
        } else {
            linkInstanceBuffer = device.makeBuffer(bytes: linkInstances, length: MemoryLayout<BrowserMetalLinkInstance>.stride * linkInstances.count)
        }
    }

    private func rebuildCardResources(for scene: BrowserSurfaceSceneSnapshot) {
        cardInstances = buildCardInstances(for: scene)
        if cardInstances.isEmpty {
            cardInstanceBuffer = nil
        } else {
            cardInstanceBuffer = device.makeBuffer(bytes: cardInstances, length: MemoryLayout<BrowserMetalCardInstance>.stride * cardInstances.count)
        }
    }

    private func rebuildTextResources(for scene: BrowserSurfaceSceneSnapshot) {
        textInstances = buildTextInstances(for: scene)
        if textInstances.isEmpty {
            textInstanceBuffer = nil
        } else {
            textInstanceBuffer = device.makeBuffer(bytes: textInstances, length: MemoryLayout<BrowserMetalTextInstance>.stride * textInstances.count)
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
        let transform = scene.worldToCanvasTransform
        let canvasBackground = NSColor.textBackgroundColor
        return scene.links.flatMap { snapshot -> [BrowserMetalLinkInstance] in
            let startPoint = snapshot.startPoint.applying(transform)
            let endPoint = snapshot.endPoint.applying(transform)
            let color = (snapshot.isHighlighted
                ? NSColor.controlAccentColor.browserOpaqueComposite(over: canvasBackground, opacity: 0.85, darkModeLift: 0.04)
                : NSColor.secondaryLabelColor.browserOpaqueComposite(over: canvasBackground, opacity: 0.42, darkModeLift: 0.10)).rgbaVector
            let width: Float = snapshot.isHighlighted ? 3 : 2
            var instances = makeLinkSegmentInstances(
                start: startPoint,
                end: endPoint,
                shapeIndex: snapshot.shapeIndex,
                lineWidth: width,
                color: color
            )
            if snapshot.directionVisible {
                instances.append(
                    contentsOf: makeArrowInstances(
                        start: startPoint,
                        end: endPoint,
                        shapeIndex: snapshot.shapeIndex,
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
            let center = CGPoint(x: snapshot.position.x, y: snapshot.position.y).applying(transform)
            let rasterKey = viewModel.browserCardRasterKey(for: snapshot)
            let rasterImage = viewModel.browserCardRasterIfReady(for: snapshot, cacheKey: rasterKey)
            if rasterImage != nil {
                desiredAtlasKeys.insert(rasterKey)
            }
            let priority = atlasPriority(for: snapshot, center: center, canvasSize: scene.canvasSize)
            let atlasEntry = atlasEntry(for: rasterKey, image: rasterImage, priority: priority)
            let fillColor = NSColor(viewModel.color(for: snapshot.card)).rgbaVector
            let strokeColor = NSColor(viewModel.browserCardStrokeColor(for: snapshot.card, isSelected: snapshot.isSelected, isHovered: snapshot.isHovered)).rgbaVector
            let glowColor = NSColor(viewModel.browserCardGlow(for: snapshot.card, isSelected: snapshot.isSelected)).rgbaVector
            let shadowColor = NSColor(viewModel.browserCardShadow(for: snapshot.card, isSelected: snapshot.isSelected, isHovered: snapshot.isHovered)).rgbaVector
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
                    strokeWidth: 1,
                    glowRadius: 0,
                    shadowRadius: shadowRadius,
                    shapeIndex: Int32(browserCardVisualShapeIndex(for: snapshot.card)),
                    hasTexture: atlasEntry == nil ? 0 : 1,
                    padding: SIMD3<Float>(repeating: 0)
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
    var padding: SIMD2<Float>
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
    var padding: SIMD3<Float>
}

private extension BrowserMetalRenderer {
    func buildTextInstances(for scene: BrowserSurfaceSceneSnapshot) -> [BrowserMetalTextInstance] {
        guard scene.links.contains(where: { ($0.labelText?.isEmpty == false) && $0.labelPoint != nil }) else {
            return []
        }

        let transform = scene.worldToCanvasTransform
        let canvasCenter = CGPoint(x: scene.canvasSize.width * 0.5, y: scene.canvasSize.height * 0.5)
        var instances: [BrowserMetalTextInstance] = []
        instances.reserveCapacity(scene.links.count)

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
                    center: SIMD2(Float(canvasPoint.x), Float(canvasPoint.y - size.height * 0.5 - 2)),
                    size: SIMD2(Float(size.width), Float(size.height)),
                    atlasUVOrigin: atlasEntry?.uvOrigin ?? .zero,
                    atlasUVSize: atlasEntry?.uvSize ?? .zero,
                    tintColor: SIMD4<Float>(1, 1, 1, 1),
                    hasTexture: atlasEntry == nil ? 0 : 1,
                    cornerRadius: 7,
                    padding: .zero
                )
            )
        }

        trimLabelImageCache(activeKeys: scene.links.compactMap { snapshot in
            guard let text = snapshot.labelText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  snapshot.labelPoint != nil else {
                return nil
            }
            return browserLabelAtlasKey(for: snapshot)
        })
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
            ].filter { distanceSquared(from: $0.start, to: $0.end) > 0.25 }
        default:
            return [makeLinkBodyInstance(start: start, end: end, shapeIndex: shapeIndex, lineWidth: lineWidth, color: color)]
        }
    }

    func makeArrowInstances(
        start: CGPoint,
        end: CGPoint,
        shapeIndex: Int,
        lineWidth: Float,
        color: SIMD4<Float>
    ) -> [BrowserMetalLinkInstance] {
        guard let geometry = browserLinkArrowGeometry(shapeIndex: shapeIndex, start: start, end: end) else {
            return []
        }
        let arrowLineWidth = max(lineWidth * 1.4, lineWidth + 1)
        let trimDistance = CGFloat(arrowLineWidth) * 0.5
        let leftTip = browserTrimmedSegmentEnd(start: geometry.leftWing, end: geometry.tip, trimDistance: trimDistance)
        let rightTip = browserTrimmedSegmentEnd(start: geometry.rightWing, end: geometry.tip, trimDistance: trimDistance)
        return [
            makeLinkBodyInstance(start: geometry.leftWing, end: leftTip, shapeIndex: 0, lineWidth: arrowLineWidth, color: color),
            makeLinkBodyInstance(start: geometry.rightWing, end: rightTip, shapeIndex: 0, lineWidth: arrowLineWidth, color: color)
        ]
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
        return "link-label|\(state)|\(snapshot.labelText ?? "")"
    }

    func atlasLabelImage(text: String, highlighted: Bool) -> NSImage {
        let cacheKey = "\(highlighted ? 1 : 0)|\(text)"
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
