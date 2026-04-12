import SwiftUI
import AppKit

let drawingToolOptions = ["Cursor", "FreeHand", "Line", "Rect", "Circle"]

struct EditorWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Card title", text: viewModel.bindingForSelectedTitle())
                    .textFieldStyle(.roundedBorder)
                Button("Web Search") { viewModel.searchWebForSelection() }
            }
            TextEditor(text: viewModel.bindingForSelectedBody())
                .font(.body.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 8) {
                Text("Linked Cards")
                    .font(.headline)
                if viewModel.editorRelatedCardLines().isEmpty {
                    Text("リンクしているカードはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(viewModel.editorRelatedCardLines()) { line in
                                Text(line.text)
                                    .font(.body.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 92, maxHeight: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                }
            }
            if !viewModel.lastGPTPrompt.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last GPT Prompt")
                        .font(.headline)
                    ScrollView {
                        Text(viewModel.lastGPTPrompt)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor)))
                }
            }
        }
        .padding(16)
    }
}

struct DrawingWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var pendingStrokeColorRawValue: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Tool")
                        .foregroundStyle(.secondary)
                    Picker("Tool", selection: $viewModel.selectedDrawingTool) {
                        ForEach(drawingToolOptions, id: \.self) { tool in
                            Text(tool).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Text("Color")
                        .foregroundStyle(.secondary)
                    Button("Auto") {
                        pendingStrokeColorRawValue = nil
                        viewModel.setSelectedDrawingStrokeColor(nil)
                    }
                    .buttonStyle(.bordered)
                    ColorPicker("", selection: drawingStrokeColorBinding, supportsOpacity: false)
                        .labelsHidden()
                }
            }
            if viewModel.selectedCard != nil {
                DrawingCanvasEditor(
                    drawingText: viewModel.bindingForSelectedDrawing(),
                    selectedTool: $viewModel.selectedDrawingTool,
                    activeStrokeColorRawValue: pendingStrokeColorRawValue ?? viewModel.selectedDrawingStrokeColorRawValue()
                )
                .id(viewModel.selectedCardID ?? -1)
            } else {
                ContentUnavailableView(
                    "Select a card",
                    systemImage: "scribble.variable",
                    description: Text("Choose a card in the browser before editing its drawing.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .onAppear(perform: syncPendingDrawingColorFromSelection)
        .onChange(of: viewModel.selectedCardID) { _, _ in
            syncPendingDrawingColorFromSelection()
        }
        .onChange(of: viewModel.selectedCard?.drawingEncoded ?? "") { _, newValue in
            let explicitColor = viewModel.selectedDrawingStrokeColorRawValue()
            if let explicitColor {
                pendingStrokeColorRawValue = explicitColor
            } else if !newValue.trimmed.isEmpty {
                pendingStrokeColorRawValue = nil
            }
        }
    }

    private var drawingStrokeColorBinding: Binding<Color> {
        Binding(
            get: {
                let rawValue = pendingStrokeColorRawValue ?? viewModel.selectedDrawingStrokeColorRawValue()
                return rawValue.map { Color(frieveRGB: $0) } ?? .accentColor
            },
            set: { newValue in
                let rawValue = newValue.frieveRGBValue
                pendingStrokeColorRawValue = rawValue
                viewModel.setSelectedDrawingStrokeColor(rawValue)
            }
        )
    }

    private func syncPendingDrawingColorFromSelection() {
        pendingStrokeColorRawValue = viewModel.selectedDrawingStrokeColorRawValue()
    }
}

struct DrawingCanvasEditor: View {
    @Binding var drawingText: String
    @Binding var selectedTool: String
    let activeStrokeColorRawValue: Int?

    @State private var drawingDocument = DrawingEditorDocument(encoded: "")
    @State private var selectedShapeIndices: Set<Int> = []
    @State private var primarySelectedShapeIndex: Int?
    @State private var interaction: DrawingCanvasInteraction?
    @State private var lastSyncedDrawing = ""
    @State private var viewport = DrawingCanvasViewport()
    @State private var canvasFrameInWindow: CGRect = .zero
    @State private var scrollMonitor: Any?
    @State private var magnifyMonitor: Any?
    @State private var middleMouseMonitor: Any?
    @State private var middleMouseDragMonitor: Any?
    @State private var middleMouseUpMonitor: Any?
    @State private var middlePanStartLocationInWindow: CGPoint?
    @State private var middlePanStartOffset: CGSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Canvas")
                .font(.headline)
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .textBackgroundColor))
                    drawingGrid(viewport: viewport)
                    ForEach(Array(drawingDocument.shapes.enumerated()), id: \.offset) { index, shape in
                        DrawingShapeLayer(
                            shape: shape,
                            canvasSize: geometry.size,
                            viewport: viewport,
                            isSelected: selectedShapeIndices.contains(index)
                        )
                    }
                    ForEach(Array(selectedShapes.enumerated()), id: \.offset) { offset, shape in
                        DrawingSelectionOverlay(
                            shape: shape,
                            canvasSize: geometry.size,
                            viewport: viewport,
                            showsHandles: selectedShapeIndices.count == 1 && offset == 0
                        )
                    }
                    if let marqueeRect = selectionMarqueeRect(in: geometry.size) {
                        DrawingSelectionMarqueeOverlay(rect: marqueeRect)
                    }
                }
                .contentShape(Rectangle())
                .overlay(alignment: .bottomLeading) {
                    Text(selectionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .background(DrawingCanvasFrameReporter(frameInWindow: $canvasFrameInWindow))
                .gesture(drawingGesture(in: geometry.size))
            }
            .frame(minHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15))
            )
            .focusable()
            .onDeleteCommand(perform: deleteSelectedShape)
        }
        .onAppear {
            synchronizeDocument(from: drawingText)
            installScrollMonitorIfNeeded()
            installMagnifyMonitorIfNeeded()
            installMiddleMousePanMonitorsIfNeeded()
        }
        .onDisappear {
            removeScrollMonitor()
            removeMagnifyMonitor()
            removeMiddleMousePanMonitors()
        }
        .onChange(of: drawingText) { _, newValue in
            guard interaction == nil, newValue != lastSyncedDrawing else { return }
            synchronizeDocument(from: newValue)
        }
    }

    private var selectedShapes: [DrawingEditorShape] {
        selectedShapeIndices.sorted().compactMap { index in
            drawingDocument.shapes.indices.contains(index) ? drawingDocument.shapes[index] : nil
        }
    }

    private var selectionHint: String {
        if selectedTool == "Cursor" {
            return selectedShapeIndices.isEmpty
                ? "Click a shape to select it. Drag empty space to marquee-select shapes."
                : "Drag selected shapes to move them, use a handle to resize one shape, or delete the selection."
        }
        return "Drag on the canvas to draw a \(selectedTool.lowercased()) shape."
    }

    private func drawingGrid(viewport: DrawingCanvasViewport) -> some View {
        GeometryReader { geometry in
            Path { path in
                let columns = 8
                let rows = 6
                for column in 1..<columns {
                    let x = CGFloat(column) / CGFloat(columns)
                    path.move(to: viewport.canvasPoint(from: CGPoint(x: x, y: 0), in: geometry.size))
                    path.addLine(to: viewport.canvasPoint(from: CGPoint(x: x, y: 1), in: geometry.size))
                }
                for row in 1..<rows {
                    let y = CGFloat(row) / CGFloat(rows)
                    path.move(to: viewport.canvasPoint(from: CGPoint(x: 0, y: y), in: geometry.size))
                    path.addLine(to: viewport.canvasPoint(from: CGPoint(x: 1, y: y), in: geometry.size))
                }
            }
            .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        }
    }

    private func drawingGesture(in canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let location = value.location.clamped(to: canvasSize)
                if interaction == nil {
                    beginInteraction(at: location, in: canvasSize)
                }
                updateInteraction(at: location)
            }
            .onEnded { value in
                let location = value.location.clamped(to: canvasSize)
                if interaction == nil {
                    beginInteraction(at: location, in: canvasSize)
                }
                updateInteraction(at: location)
                finishInteraction()
            }
    }

    private func beginInteraction(at location: CGPoint, in canvasSize: CGSize) {
        let normalizedPoint = viewport.normalizedPoint(from: location, in: canvasSize)

        if selectedTool == "Cursor" {
            if selectedShapeIndices.count == 1,
               let primarySelectedShapeIndex,
               drawingDocument.shapes.indices.contains(primarySelectedShapeIndex),
               let handle = drawingDocument.shapes[primarySelectedShapeIndex].handleHitTest(
                   at: location,
                   in: canvasSize,
                   viewport: viewport,
                   radius: 8
               ) {
                interaction = DrawingCanvasInteraction(
                    mode: .resizing(
                        index: primarySelectedShapeIndex,
                        handle: handle,
                        originalShape: drawingDocument.shapes[primarySelectedShapeIndex]
                    ),
                    canvasSize: canvasSize
                )
                return
            }

            if let hitIndex = drawingDocument.hitTestShape(at: location, in: canvasSize, viewport: viewport, tolerance: 10) {
                if !selectedShapeIndices.contains(hitIndex) {
                    selectedShapeIndices = [hitIndex]
                }
                primarySelectedShapeIndex = hitIndex
                interaction = DrawingCanvasInteraction(
                    mode: .moving(
                        indices: selectedShapeIndices.sorted(),
                        startPoint: normalizedPoint,
                        originalShapes: Dictionary(uniqueKeysWithValues: selectedShapeIndices.compactMap { index in
                            guard drawingDocument.shapes.indices.contains(index) else { return nil }
                            return (index, drawingDocument.shapes[index])
                        })
                    ),
                    canvasSize: canvasSize
                )
                return
            }

            selectedShapeIndices = []
            primarySelectedShapeIndex = nil
            interaction = DrawingCanvasInteraction(
                mode: .selecting(startPoint: normalizedPoint, currentPoint: normalizedPoint),
                canvasSize: canvasSize
            )
            return
        }

        guard let newShape = DrawingEditorShape(tool: selectedTool, startPoint: normalizedPoint, strokeColor: activeStrokeColorRawValue) else {
            return
        }
        drawingDocument.shapes.append(newShape)
        primarySelectedShapeIndex = drawingDocument.shapes.count - 1
        selectedShapeIndices = [drawingDocument.shapes.count - 1]
        interaction = DrawingCanvasInteraction(
            mode: .drawing(index: drawingDocument.shapes.count - 1, tool: selectedTool),
            canvasSize: canvasSize
        )
    }

    private func updateInteraction(at location: CGPoint) {
        guard let activeInteraction = interaction else { return }
        let normalizedPoint = viewport.normalizedPoint(from: location, in: activeInteraction.canvasSize)

        switch activeInteraction.mode {
        case let .drawing(index, tool):
            guard drawingDocument.shapes.indices.contains(index) else { return }
            drawingDocument.shapes[index].updateDraft(tool: tool, with: normalizedPoint)
        case let .moving(indices, startPoint, originalShapes):
            let delta = CGSize(width: normalizedPoint.x - startPoint.x, height: normalizedPoint.y - startPoint.y)
            for index in indices {
                guard drawingDocument.shapes.indices.contains(index), let originalShape = originalShapes[index] else { continue }
                drawingDocument.shapes[index] = originalShape.moved(by: delta)
            }
        case let .resizing(index, handle, originalShape):
            guard drawingDocument.shapes.indices.contains(index) else { return }
            drawingDocument.shapes[index] = originalShape.resized(using: handle, to: normalizedPoint)
        case let .selecting(startPoint, _):
            interaction = DrawingCanvasInteraction(
                mode: .selecting(startPoint: startPoint, currentPoint: normalizedPoint),
                canvasSize: activeInteraction.canvasSize
            )
            updateMarqueeSelection(from: startPoint, to: normalizedPoint)
        }
    }

    private func finishInteraction() {
        defer { interaction = nil }

        if let primarySelectedShapeIndex,
           drawingDocument.shapes.indices.contains(primarySelectedShapeIndex),
           drawingDocument.shapes[primarySelectedShapeIndex].isDegenerate {
            drawingDocument.shapes.remove(at: primarySelectedShapeIndex)
            selectedShapeIndices = normalizedSelectionIndices(afterRemoving: [primarySelectedShapeIndex])
            self.primarySelectedShapeIndex = selectedShapeIndices.sorted().last
        }

        guard let interaction else {
            synchronizeDocument(from: drawingText)
            return
        }

        switch interaction.mode {
        case .drawing, .moving, .resizing:
            commitDrawing()
        case .selecting:
            break
        }
    }

    private func deleteSelectedShape() {
        let indices = selectedShapeIndices.sorted()
        guard !indices.isEmpty else { return }
        for index in indices.reversed() where drawingDocument.shapes.indices.contains(index) {
            drawingDocument.shapes.remove(at: index)
        }
        selectedShapeIndices = []
        primarySelectedShapeIndex = nil
        commitDrawing()
    }

    private func commitDrawing() {
        let encoded = drawingDocument.encoded
        lastSyncedDrawing = encoded
        drawingText = encoded
    }

    private func synchronizeDocument(from encoded: String) {
        drawingDocument = DrawingEditorDocument(encoded: encoded)
        lastSyncedDrawing = encoded
        selectedShapeIndices = Set(selectedShapeIndices.filter { drawingDocument.shapes.indices.contains($0) })
        if let primarySelectedShapeIndex, !drawingDocument.shapes.indices.contains(primarySelectedShapeIndex) {
            self.primarySelectedShapeIndex = selectedShapeIndices.sorted().last
        }
    }

    private func selectionMarqueeRect(in canvasSize: CGSize) -> CGRect? {
        guard case let .selecting(startPoint, currentPoint)? = interaction?.mode else { return nil }
        let start = viewport.canvasPoint(from: startPoint, in: canvasSize)
        let current = viewport.canvasPoint(from: currentPoint, in: canvasSize)
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        return rect.width > 0 || rect.height > 0 ? rect : nil
    }

    private func updateMarqueeSelection(from startPoint: CGPoint, to currentPoint: CGPoint) {
        let selectionRect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        let nextSelection = Set(drawingDocument.shapes.indices.filter { index in
            selectionRect.intersects(drawingDocument.shapes[index].bounds)
        })
        selectedShapeIndices = nextSelection
        primarySelectedShapeIndex = nextSelection.sorted().last
    }

    private func normalizedSelectionIndices(afterRemoving removedIndices: [Int]) -> Set<Int> {
        let removed = Set(removedIndices)
        return Set(selectedShapeIndices.compactMap { index in
            guard !removed.contains(index) else { return nil }
            let shift = removed.filter { $0 < index }.count
            return index - shift
        })
    }

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard canvasFrameInWindow.contains(event.locationInWindow) else { return event }
            handleScrollEvent(event)
            return nil
        }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    private func installMagnifyMonitorIfNeeded() {
        guard magnifyMonitor == nil else { return }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
            guard canvasFrameInWindow.contains(event.locationInWindow) else { return event }
            let anchor = CGPoint(
                x: event.locationInWindow.x - canvasFrameInWindow.minX,
                y: canvasFrameInWindow.height - (event.locationInWindow.y - canvasFrameInWindow.minY)
            )
            let zoomFactor = max(0.2, 1.0 + event.magnification)
            viewport.zoom(by: zoomFactor, anchor: anchor, in: canvasFrameInWindow.size)
            return nil
        }
    }

    private func removeMagnifyMonitor() {
        if let magnifyMonitor {
            NSEvent.removeMonitor(magnifyMonitor)
            self.magnifyMonitor = nil
        }
    }

    private func installMiddleMousePanMonitorsIfNeeded() {
        guard middleMouseMonitor == nil, middleMouseDragMonitor == nil, middleMouseUpMonitor == nil else { return }

        middleMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber == 2, canvasFrameInWindow.contains(event.locationInWindow) else { return event }
            middlePanStartLocationInWindow = event.locationInWindow
            middlePanStartOffset = viewport.contentOffset
            return nil
        }

        middleMouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { event in
            guard event.buttonNumber == 2,
                  let startLocation = middlePanStartLocationInWindow,
                  let startOffset = middlePanStartOffset else {
                return event
            }
            let delta = CGSize(
                width: event.locationInWindow.x - startLocation.x,
                height: event.locationInWindow.y - startLocation.y
            )
            viewport.setContentOffset(
                CGSize(
                width: startOffset.width + delta.width,
                height: startOffset.height + delta.height
                ),
                in: canvasFrameInWindow.size
            )
            return nil
        }

        middleMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2 else { return event }
            middlePanStartLocationInWindow = nil
            middlePanStartOffset = nil
            return canvasFrameInWindow.contains(event.locationInWindow) ? nil : event
        }
    }

    private func removeMiddleMousePanMonitors() {
        if let middleMouseMonitor {
            NSEvent.removeMonitor(middleMouseMonitor)
            self.middleMouseMonitor = nil
        }
        if let middleMouseDragMonitor {
            NSEvent.removeMonitor(middleMouseDragMonitor)
            self.middleMouseDragMonitor = nil
        }
        if let middleMouseUpMonitor {
            NSEvent.removeMonitor(middleMouseUpMonitor)
            self.middleMouseUpMonitor = nil
        }
        middlePanStartLocationInWindow = nil
        middlePanStartOffset = nil
    }

    private func handleScrollEvent(_ event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let zoomFactor = exp(-event.scrollingDeltaY / 280.0)
            let anchor = CGPoint(
                x: event.locationInWindow.x - canvasFrameInWindow.minX,
                y: canvasFrameInWindow.height - (event.locationInWindow.y - canvasFrameInWindow.minY)
            )
            viewport.zoom(by: zoomFactor, anchor: anchor, in: canvasFrameInWindow.size)
        } else {
            viewport.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY), in: canvasFrameInWindow.size)
        }
    }
}

struct DrawingEditorDocument: Equatable {
    var shapes: [DrawingEditorShape]
    var passthroughChunks: [String]

    init(encoded: String) {
        let chunks = encoded
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }

        var parsedShapes: [DrawingEditorShape] = []
        var preservedChunks: [String] = []
        for chunk in chunks {
            if let shape = DrawingEditorShape(chunk: chunk) {
                parsedShapes.append(shape)
            } else {
                preservedChunks.append(chunk)
            }
        }

        shapes = parsedShapes
        passthroughChunks = preservedChunks
    }

    var encoded: String {
        (shapes.map(\.encodedChunk) + passthroughChunks).joined(separator: "\n")
    }

    func hitTestShape(at point: CGPoint, in canvasSize: CGSize, viewport: DrawingCanvasViewport, tolerance: CGFloat) -> Int? {
        for index in shapes.indices.reversed() {
            if shapes[index].contains(point: point, in: canvasSize, viewport: viewport, tolerance: tolerance) {
                return index
            }
        }
        return nil
    }
}

struct DrawingEditorShape: Equatable {
    var tool: String
    var points: [CGPoint]
    var strokeColor: Int?
    var fillColor: Int?

    init?(tool: String, startPoint: CGPoint, strokeColor: Int?) {
        switch tool {
        case "FreeHand":
            self.tool = tool
            points = [startPoint]
        case "Line", "Rect", "Circle":
            self.tool = tool
            points = [startPoint, startPoint]
        default:
            return nil
        }
        self.strokeColor = strokeColor
        fillColor = nil
    }

    init?(chunk: String) {
        let lower = chunk.lowercased()
        let numbers = DrawingEditorCodec.numbers(in: chunk)
        let strokeColor = DrawingEditorCodec.color(in: chunk, prefixes: ["stroke=", "pen=", "color="])
        let fillColor = DrawingEditorCodec.color(in: chunk, prefixes: ["fill=", "brush="])

        if lower.hasPrefix("freehand") || lower.hasPrefix("polyline") || lower.hasPrefix("1,") {
            let points = DrawingEditorCodec.points(from: numbers)
            guard points.count >= 2 else { return nil }
            self.tool = "FreeHand"
            self.points = points
            self.strokeColor = strokeColor
            self.fillColor = fillColor
            return
        }

        if lower.hasPrefix("line") || lower.hasPrefix("2,") {
            guard numbers.count >= 4 else { return nil }
            self.tool = "Line"
            points = [
                CGPoint(x: numbers[0], y: numbers[1]).clampedNormalized(),
                CGPoint(x: numbers[2], y: numbers[3]).clampedNormalized(),
            ]
            self.strokeColor = strokeColor
            self.fillColor = fillColor
            return
        }

        if lower.hasPrefix("rect") || lower.hasPrefix("rectangle") || lower.hasPrefix("3,") {
            guard numbers.count >= 4 else { return nil }
            self.tool = "Rect"
            points = [
                CGPoint(x: numbers[0], y: numbers[1]).clampedNormalized(),
                CGPoint(x: numbers[2], y: numbers[3]).clampedNormalized(),
            ]
            self.strokeColor = strokeColor
            self.fillColor = fillColor
            return
        }

        if lower.hasPrefix("circle") || lower.hasPrefix("ellipse") || lower.hasPrefix("oval") || lower.hasPrefix("4,") {
            guard numbers.count >= 4 else { return nil }
            self.tool = "Circle"
            points = [
                CGPoint(x: numbers[0], y: numbers[1]).clampedNormalized(),
                CGPoint(x: numbers[2], y: numbers[3]).clampedNormalized(),
            ]
            self.strokeColor = strokeColor
            self.fillColor = fillColor
            return
        }

        return nil
    }

    var encodedChunk: String {
        let prefix: String
        switch tool {
        case "FreeHand":
            prefix = "freehand"
        case "Line":
            prefix = "line"
        case "Rect":
            prefix = "rect"
        case "Circle":
            prefix = "circle"
        default:
            prefix = "freehand"
        }

        let coordinateTokens: [String]
        switch tool {
        case "FreeHand":
            coordinateTokens = points.flatMap { [DrawingEditorCodec.format($0.x), DrawingEditorCodec.format($0.y)] }
        default:
            guard points.count >= 2 else { return prefix }
            coordinateTokens = [
                DrawingEditorCodec.format(points[0].x),
                DrawingEditorCodec.format(points[0].y),
                DrawingEditorCodec.format(points[1].x),
                DrawingEditorCodec.format(points[1].y),
            ]
        }

        var tokens = [prefix] + coordinateTokens
        if let strokeColor {
            tokens.append(String(format: "color=%06X", strokeColor & 0xFFFFFF))
        }
        if let fillColor {
            tokens.append(String(format: "fill=%06X", fillColor & 0xFFFFFF))
        }
        return tokens.joined(separator: " ")
    }

    var bounds: CGRect {
        switch tool {
        case "FreeHand":
            return DrawingEditorCodec.bounds(for: points)
        default:
            guard points.count >= 2 else { return .zero }
            return CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
        }
    }

    var isDegenerate: Bool {
        switch tool {
        case "FreeHand":
            guard points.count >= 2 else { return true }
            return points.adjacentPairs().allSatisfy { lhs, rhs in hypot(rhs.x - lhs.x, rhs.y - lhs.y) < 0.003 }
        default:
            guard points.count >= 2 else { return true }
            return hypot(points[1].x - points[0].x, points[1].y - points[0].y) < 0.003
        }
    }

    func path(in canvasSize: CGSize, viewport: DrawingCanvasViewport) -> Path {
        var path = Path()
        switch tool {
        case "FreeHand":
            guard let first = points.first else { return path }
            path.move(to: viewport.canvasPoint(from: first, in: canvasSize))
            for point in points.dropFirst() {
                path.addLine(to: viewport.canvasPoint(from: point, in: canvasSize))
            }
        case "Line":
            guard points.count >= 2 else { return path }
            path.move(to: viewport.canvasPoint(from: points[0], in: canvasSize))
            path.addLine(to: viewport.canvasPoint(from: points[1], in: canvasSize))
        case "Rect":
            path.addRect(bounds.canvasRect(in: canvasSize, viewport: viewport))
        case "Circle":
            path.addEllipse(in: bounds.canvasRect(in: canvasSize, viewport: viewport))
        default:
            break
        }
        return path
    }

    func contains(point: CGPoint, in canvasSize: CGSize, viewport: DrawingCanvasViewport, tolerance: CGFloat) -> Bool {
        switch tool {
        case "FreeHand":
            return points.canvasSegmentsContain(point: point, in: canvasSize, viewport: viewport, tolerance: tolerance)
        case "Line":
            guard points.count >= 2 else { return false }
            return DrawingEditorCodec.distanceFromSegment(
                point,
                viewport.canvasPoint(from: points[0], in: canvasSize),
                viewport.canvasPoint(from: points[1], in: canvasSize)
            ) <= tolerance
        case "Rect", "Circle":
            return bounds.canvasRect(in: canvasSize, viewport: viewport).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        default:
            return false
        }
    }

    func handleHitTest(at point: CGPoint, in canvasSize: CGSize, viewport: DrawingCanvasViewport, radius: CGFloat) -> DrawingEditorHandle? {
        handlePoints(in: canvasSize, viewport: viewport).first { _, handlePoint in
            hypot(handlePoint.x - point.x, handlePoint.y - point.y) <= radius
        }?.0
    }

    func handlePoints(in canvasSize: CGSize, viewport: DrawingCanvasViewport) -> [(DrawingEditorHandle, CGPoint)] {
        switch tool {
        case "Line":
            guard points.count >= 2 else { return [] }
            return [
                (.lineStart, viewport.canvasPoint(from: points[0], in: canvasSize)),
                (.lineEnd, viewport.canvasPoint(from: points[1], in: canvasSize)),
            ]
        default:
            let rect = bounds.canvasRect(in: canvasSize, viewport: viewport)
            return [
                (.topLeading, CGPoint(x: rect.minX, y: rect.minY)),
                (.topTrailing, CGPoint(x: rect.maxX, y: rect.minY)),
                (.bottomLeading, CGPoint(x: rect.minX, y: rect.maxY)),
                (.bottomTrailing, CGPoint(x: rect.maxX, y: rect.maxY)),
            ]
        }
    }

    mutating func updateDraft(tool: String, with point: CGPoint) {
        let point = point.clampedNormalized()
        switch tool {
        case "FreeHand":
            if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 0.002 {
                points[points.count - 1] = point
            } else {
                points.append(point)
            }
        case "Line", "Rect", "Circle":
            if points.count < 2 {
                points = [point, point]
            } else {
                points[1] = point
            }
        default:
            break
        }
    }

    func moved(by delta: CGSize) -> DrawingEditorShape {
        let bounds = bounds
        let limitedDelta = CGSize(
            width: min(max(delta.width, -bounds.minX), 1 - bounds.maxX),
            height: min(max(delta.height, -bounds.minY), 1 - bounds.maxY)
        )
        var movedShape = self
        movedShape.points = points.map {
            CGPoint(x: $0.x + limitedDelta.width, y: $0.y + limitedDelta.height).clampedNormalized()
        }
        return movedShape
    }

    func resized(using handle: DrawingEditorHandle, to point: CGPoint) -> DrawingEditorShape {
        let point = point.clampedNormalized()
        switch tool {
        case "Line":
            guard points.count >= 2 else { return self }
            var resizedShape = self
            switch handle {
            case .lineStart:
                resizedShape.points[0] = point
            case .lineEnd:
                resizedShape.points[1] = point
            default:
                break
            }
            return resizedShape
        case "Rect", "Circle":
            let opposite = oppositeCorner(for: handle)
            return resizedRectLikeShape(oppositeCorner: opposite, draggedCorner: point)
        case "FreeHand":
            let originalBounds = bounds
            let opposite = oppositeCorner(for: handle)
            let targetRect = CGRect(
                x: min(opposite.x, point.x),
                y: min(opposite.y, point.y),
                width: abs(point.x - opposite.x),
                height: abs(point.y - opposite.y)
            )
            let sourceRect = CGRect(
                x: originalBounds.minX,
                y: originalBounds.minY,
                width: max(originalBounds.width, 0.0001),
                height: max(originalBounds.height, 0.0001)
            )
            var resizedShape = self
            resizedShape.points = points.map { sourcePoint in
                let u = (sourcePoint.x - sourceRect.minX) / sourceRect.width
                let v = (sourcePoint.y - sourceRect.minY) / sourceRect.height
                return CGPoint(
                    x: targetRect.minX + targetRect.width * u,
                    y: targetRect.minY + targetRect.height * v
                ).clampedNormalized()
            }
            return resizedShape
        default:
            return self
        }
    }

    private func resizedRectLikeShape(oppositeCorner: CGPoint, draggedCorner: CGPoint) -> DrawingEditorShape {
        var resizedShape = self
        resizedShape.points = [oppositeCorner, draggedCorner]
        return resizedShape
    }

    private func oppositeCorner(for handle: DrawingEditorHandle) -> CGPoint {
        let rect = bounds
        return switch handle {
        case .topLeading:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .topTrailing:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeading:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomTrailing:
            CGPoint(x: rect.minX, y: rect.minY)
        case .lineStart:
            points.count >= 2 ? points[1] : .zero
        case .lineEnd:
            points.first ?? .zero
        }
    }
}

enum DrawingEditorHandle: CaseIterable {
    case lineStart
    case lineEnd
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct DrawingCanvasInteraction {
    enum Mode {
        case drawing(index: Int, tool: String)
        case moving(indices: [Int], startPoint: CGPoint, originalShapes: [Int: DrawingEditorShape])
        case resizing(index: Int, handle: DrawingEditorHandle, originalShape: DrawingEditorShape)
        case selecting(startPoint: CGPoint, currentPoint: CGPoint)
    }

    let mode: Mode
    let canvasSize: CGSize
}

struct DrawingCanvasViewport: Equatable {
    var zoomScale: CGFloat = 1
    var contentOffset: CGSize = .zero

    mutating func pan(by delta: CGSize, in canvasSize: CGSize) {
        setContentOffset(
            CGSize(
                width: contentOffset.width + delta.width,
                height: contentOffset.height + delta.height
            ),
            in: canvasSize
        )
    }

    mutating func setContentOffset(_ proposedOffset: CGSize, in canvasSize: CGSize) {
        contentOffset = clampedContentOffset(proposedOffset, in: canvasSize)
    }

    mutating func zoom(by factor: CGFloat, anchor: CGPoint, in canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let currentZoom = max(zoomScale, 0.5)
        let nextZoom = min(max(currentZoom * factor, 0.5), 4.0)
        guard abs(nextZoom - currentZoom) > 0.0001 else { return }
        zoomScale = nextZoom
        let proposedOffset = CGSize(
            width: anchor.x - ((anchor.x - contentOffset.width) / currentZoom) * nextZoom,
            height: anchor.y - ((anchor.y - contentOffset.height) / currentZoom) * nextZoom
        )
        contentOffset = clampedContentOffset(proposedOffset, in: canvasSize)
    }

    func canvasPoint(from normalizedPoint: CGPoint, in canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * canvasSize.width * zoomScale + contentOffset.width,
            y: normalizedPoint.y * canvasSize.height * zoomScale + contentOffset.height
        )
    }

    func normalizedPoint(from canvasPoint: CGPoint, in canvasSize: CGSize) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0, zoomScale > 0 else { return .zero }
        return CGPoint(
            x: (canvasPoint.x - contentOffset.width) / (canvasSize.width * zoomScale),
            y: (canvasPoint.y - contentOffset.height) / (canvasSize.height * zoomScale)
        ).clampedNormalized()
    }

    private func clampedContentOffset(_ proposedOffset: CGSize, in canvasSize: CGSize) -> CGSize {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        let contentWidth = canvasSize.width * zoomScale
        let contentHeight = canvasSize.height * zoomScale

        let widthOffset: CGFloat
        if contentWidth <= canvasSize.width {
            widthOffset = (canvasSize.width - contentWidth) * 0.5
        } else {
            widthOffset = min(max(proposedOffset.width, canvasSize.width - contentWidth), 0)
        }

        let heightOffset: CGFloat
        if contentHeight <= canvasSize.height {
            heightOffset = (canvasSize.height - contentHeight) * 0.5
        } else {
            heightOffset = min(max(proposedOffset.height, canvasSize.height - contentHeight), 0)
        }

        return CGSize(width: widthOffset, height: heightOffset)
    }
}

private struct DrawingCanvasFrameReporter: NSViewRepresentable {
    @Binding var frameInWindow: CGRect

    func makeNSView(context: Context) -> DrawingCanvasFrameReporterView {
        let view = DrawingCanvasFrameReporterView()
        view.onFrameChange = { frame in
            self.frameInWindow = frame
        }
        return view
    }

    func updateNSView(_ nsView: DrawingCanvasFrameReporterView, context: Context) {
        nsView.onFrameChange = { frame in
            self.frameInWindow = frame
        }
        nsView.reportFrameIfNeeded()
    }
}

private final class DrawingCanvasFrameReporterView: NSView {
    var onFrameChange: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        reportFrameIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrameIfNeeded()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func reportFrameIfNeeded() {
        let rect = convert(bounds, to: nil)
        onFrameChange?(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height))
    }
}

private struct DrawingShapeLayer: View {
    let shape: DrawingEditorShape
    let canvasSize: CGSize
    let viewport: DrawingCanvasViewport
    let isSelected: Bool

    var body: some View {
        let path = shape.path(in: canvasSize, viewport: viewport)
        ZStack {
            if let fillColor = shape.fillColor, shape.tool == "Rect" || shape.tool == "Circle" {
                path.fill(Color(frieveRGB: fillColor).opacity(0.16))
            }
            path.stroke(
                resolvedStrokeColor,
                style: StrokeStyle(
                    lineWidth: isSelected ? 2.5 : 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private var resolvedStrokeColor: Color {
        shape.strokeColor.map { Color(frieveRGB: $0) } ?? .accentColor
    }
}

private struct DrawingSelectionOverlay: View {
    let shape: DrawingEditorShape
    let canvasSize: CGSize
    let viewport: DrawingCanvasViewport
    let showsHandles: Bool

    var body: some View {
        ZStack {
            if shape.tool != "Line" {
                Path { path in
                    path.addRect(shape.bounds.canvasRect(in: canvasSize, viewport: viewport))
                }
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            if showsHandles {
                ForEach(Array(shape.handlePoints(in: canvasSize, viewport: viewport).enumerated()), id: \.offset) { _, entry in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .position(entry.1)
                }
            }
        }
    }
}

private struct DrawingSelectionMarqueeOverlay: View {
    let rect: CGRect

    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.10))
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

enum DrawingEditorCodec {
    static func numbers(in text: String) -> [Double] {
        var values: [Double] = []
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            if let value = Double(buffer) {
                values.append(value)
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if CharacterSet(charactersIn: "+-.0123456789").contains(scalar) {
                buffer.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()

        return values
    }

    static func points(from numbers: [Double]) -> [CGPoint] {
        guard numbers.count >= 2 else { return [] }
        return stride(from: 0, to: numbers.count - 1, by: 2).map {
            CGPoint(x: numbers[$0], y: numbers[$0 + 1]).clampedNormalized()
        }
    }

    static func color(in text: String, prefixes: [String]) -> Int? {
        let lower = text.lowercased()
        for prefix in prefixes {
            guard let range = lower.range(of: prefix) else { continue }
            let suffix = lower[range.upperBound...]
            let token = suffix.prefix { !$0.isWhitespace && $0 != "," && $0 != ";" }
            let cleaned = token.replacingOccurrences(of: "#", with: "")
            if let value = Int(cleaned, radix: 16) {
                return value
            }
            if let value = Int(cleaned) {
                return value
            }
        }
        return nil
    }

    static func bounds(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func format(_ value: CGFloat) -> String {
        let normalizedValue = Double(value)
        let rounded = (normalizedValue * 10_000).rounded() / 10_000
        var text = String(format: "%.4f", rounded)
        while text.contains("."), text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
    }

    static func distanceFromSegment(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projectedPoint = CGPoint(x: start.x + dx * projection, y: start.y + dy * projection)
        return hypot(point.x - projectedPoint.x, point.y - projectedPoint.y)
    }
}

private extension CGRect {
    func canvasRect(in size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    func canvasRect(in size: CGSize, viewport: DrawingCanvasViewport) -> CGRect {
        let origin = viewport.canvasPoint(from: CGPoint(x: minX, y: minY), in: size)
        let opposite = viewport.canvasPoint(from: CGPoint(x: maxX, y: maxY), in: size)
        return CGRect(
            x: min(origin.x, opposite.x),
            y: min(origin.y, opposite.y),
            width: abs(opposite.x - origin.x),
            height: abs(opposite.y - origin.y)
        )
    }
}

private extension CGPoint {
    func clamped(to size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(x, 0), size.width),
            y: min(max(y, 0), size.height)
        )
    }

    func normalized(in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGPoint(x: x / size.width, y: y / size.height).clampedNormalized()
    }

    func canvasPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    func clampedNormalized() -> CGPoint {
        CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

private extension Array where Element == CGPoint {
    func canvasSegmentsContain(point: CGPoint, in size: CGSize, viewport: DrawingCanvasViewport, tolerance: CGFloat) -> Bool {
        guard count >= 2 else { return false }
        for index in 1..<count {
            if DrawingEditorCodec.distanceFromSegment(
                point,
                viewport.canvasPoint(from: self[index - 1], in: size),
                viewport.canvasPoint(from: self[index], in: size)
            ) <= tolerance {
                return true
            }
        }
        return false
    }

    func adjacentPairs() -> [(CGPoint, CGPoint)] {
        guard count >= 2 else { return [] }
        return (1..<count).map { (self[$0 - 1], self[$0]) }
    }
}

struct StatisticsWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    private let labelColumnWidth: CGFloat = 220

    var body: some View {
        let buckets = viewModel.statisticsBuckets
        let maxCount = max(buckets.map(\.count).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Key")
                Menu(viewModel.statisticsKey.title) {
                    Button("Label") { viewModel.statisticsKey = .label }
                    Menu("Number of Link") {
                        Button("Total") { viewModel.statisticsKey = .totalLinks }
                        Button("Source") { viewModel.statisticsKey = .sourceLinks }
                        Button("Destination") { viewModel.statisticsKey = .destinationLinks }
                    }
                    Menu("Created Date") {
                        Button("Year") { viewModel.statisticsKey = .createdYear }
                        Button("Month") { viewModel.statisticsKey = .createdMonth }
                        Button("Day") { viewModel.statisticsKey = .createdDay }
                        Button("Week") { viewModel.statisticsKey = .createdWeekday }
                        Button("Hour") { viewModel.statisticsKey = .createdHour }
                    }
                    Menu("Edited Date") {
                        Button("Year") { viewModel.statisticsKey = .editedYear }
                        Button("Month") { viewModel.statisticsKey = .editedMonth }
                        Button("Day") { viewModel.statisticsKey = .editedDay }
                        Button("Week") { viewModel.statisticsKey = .editedWeekday }
                        Button("Hour") { viewModel.statisticsKey = .editedHour }
                    }
                    Menu("Viewed Date") {
                        Button("Year") { viewModel.statisticsKey = .viewedYear }
                        Button("Month") { viewModel.statisticsKey = .viewedMonth }
                        Button("Day") { viewModel.statisticsKey = .viewedDay }
                        Button("Week") { viewModel.statisticsKey = .viewedWeekday }
                        Button("Hour") { viewModel.statisticsKey = .viewedHour }
                    }
                }
                .fixedSize()
                Toggle("Sort", isOn: $viewModel.statisticsSortByCount)
                    .toggleStyle(.button)

                Spacer()
            }

            HStack(spacing: 12) {
                Text("Item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)
                StatisticsScaleHeaderView(maxCount: maxCount)
            }
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        StatisticsBarRowView(
                            bucket: bucket,
                            isSelected: bucket.id == viewModel.selectedStatisticsBucketID,
                            maxCount: maxCount,
                            rowIndex: index,
                            labelColumnWidth: labelColumnWidth
                        )
                        .onTapGesture {
                            viewModel.selectStatisticsBucket(bucket)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.18))
            )

            if let selectedBucket = viewModel.selectedStatisticsBucket {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selectedBucket.name)
                            .font(.headline)
                        Text("\(selectedBucket.count) cards")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Table(
                        viewModel.statisticsCards(for: selectedBucket),
                        selection: Binding<Int?>(
                            get: { viewModel.selectedStatisticsCardID(in: selectedBucket) },
                            set: { viewModel.selectStatisticsCard($0) }
                        )
                    ) {
                        TableColumn("Title", value: \.title)
                        TableColumn("Body") { card in
                            Text(card.bodyText)
                                .lineLimit(2)
                        }
                    }
                    .frame(minHeight: 220)
                }
            } else {
                ContentUnavailableView(
                    "Select a bar",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Cards for the selected statistic bucket will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
    }
}

private struct StatisticsScaleHeaderView: View {
    let maxCount: Int

    var body: some View {
        GeometryReader { geometry in
            let steps = max(4, min(maxCount, 8))
            ZStack(alignment: .topLeading) {
                ForEach(0 ... steps, id: \.self) { step in
                    let fraction = CGFloat(step) / CGFloat(steps)
                    let scaledValue = Int((Double(maxCount) * Double(step)) / Double(steps))
                    VStack(spacing: 4) {
                        Text("\(scaledValue)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .position(x: geometry.size.width * fraction, y: geometry.size.height / 2)
                }
            }
        }
        .frame(height: 26)
    }
}

private struct StatisticsBarRowView: View {
    let bucket: DocumentStatisticBucket
    let isSelected: Bool
    let maxCount: Int
    let rowIndex: Int
    let labelColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Text(bucket.name)
                .lineLimit(1)
                .frame(width: labelColumnWidth, alignment: .leading)

            GeometryReader { geometry in
                let barWidth = geometry.size.width * CGFloat(bucket.count) / CGFloat(max(maxCount, 1))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(barColor)
                        .frame(width: barWidth)
                    if bucket.count > 0 {
                        Text("\(bucket.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: barWidth > 56 ? .trailing : .leading)
                            .offset(x: labelOffset(for: geometry.size.width, barWidth: barWidth))
                    }
                }
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if rowIndex.isMultiple(of: 2) {
            return Color.clear
        }
        return Color.secondary.opacity(0.05)
    }

    private var barColor: Color {
        if let color = bucket.color {
            return Color(frieveRGB: color)
        }
        let hue = rowCountHue
        return Color(hue: hue, saturation: 0.86, brightness: 0.95)
    }

    private var rowCountHue: Double {
        guard maxCount > 0 else { return 0.58 }
        return Double((rowIndex * 37) % 100) / 100.0
    }

    private func labelOffset(for totalWidth: CGFloat, barWidth: CGFloat) -> CGFloat {
        if barWidth > 56 {
            return 0
        }
        let preferred = min(barWidth + 8, max(totalWidth - 42, 0))
        return preferred
    }
}

struct InspectorPaneView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inspector")
                    .font(.headline)
                if let card = viewModel.selectedCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .foregroundStyle(.secondary)
                        TextField("Card title", text: viewModel.bindingForSelectedTitle())
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Labels")
                            .foregroundStyle(.secondary)
                        TextField("Comma-separated labels", text: viewModel.bindingForSelectedLabels())
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Created", value: card.created)
                    LabeledContent("Updated", value: card.updated)

                    Picker("Shape", selection: viewModel.bindingForSelectedShape()) {
                        Text("Rect").tag(0)
                        Text("Capsule").tag(1)
                        Text("Round").tag(2)
                        Text("Diamond").tag(3)
                        Text("Hexagon").tag(4)
                        Text("Note").tag(5)
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 4) {
                        let sizeStep = browserCardSizeStep(forStoredSize: card.size)
                        HStack {
                            Text("Card Size")
                            Spacer()
                            Text("\(sizeStep)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: viewModel.bindingForSelectedSize(), in: -8 ... 8, step: 1)
                    }

                    TextField("Image path", text: viewModel.bindingForSelectedImagePath())
                        .textFieldStyle(.roundedBorder)
                    TextField("Video path", text: viewModel.bindingForSelectedVideoPath())
                        .textFieldStyle(.roundedBorder)

                    Toggle("Top Card", isOn: .constant(card.isTop))
                        .disabled(true)
                    Toggle("Fixed", isOn: viewModel.bindingForSelectedFixed())
                    Toggle("Folded", isOn: viewModel.bindingForSelectedFolded())

                    Button("Focus Browser") {
                        viewModel.selectedTab = .browser
                        viewModel.focusBrowser(on: card.id)
                    }
                } else {
                    Text("No card selected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollContentBackground(.hidden)
    }
}

struct StatusBarView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(viewModel.statusMessage)
            Spacer()
            Text("Cards: \(viewModel.document.cardCount)")
            Text("Links: \(viewModel.document.linkCount)")
            Text("Focus: \(viewModel.selectedCard?.title ?? "None")")
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
