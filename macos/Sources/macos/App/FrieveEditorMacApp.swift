import SwiftUI
import AppKit

@MainActor
private func currentModifierFlags() -> NSEvent.ModifierFlags {
    NSApp.currentEvent?.modifierFlags ?? []
}

@main
struct FrieveEditorMacApp: App {
    @StateObject private var viewModel = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup("Frieve Editor") {
            WorkspaceRootView(viewModel: viewModel)
                .frame(minWidth: 1280, minHeight: 800)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { viewModel.newDocument() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Open…") { viewModel.openDocument() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Save") { viewModel.saveDocument() }
                    .keyboardShortcut("s", modifiers: [.command])
                Button("Save As…") { viewModel.saveDocumentAs() }
                    .keyboardShortcut("S", modifiers: [.command, .shift])
            }

            CommandMenu("Cards") {
                Button("New Root Card") { viewModel.addRootCard() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("New Child Card") { viewModel.addChildCard() }
                    .keyboardShortcut(.return, modifiers: [.command])
                Button("New Sibling Card") { viewModel.addSiblingCard() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                Divider()
                Button("Link to Root") { viewModel.addLinkBetweenSelectionAndRoot() }
                Button("Delete Selected Card") { viewModel.deleteSelectedCard() }
                    .keyboardShortcut(.delete, modifiers: [.command])
            }

            CommandMenu("Layout") {
                Button("Arrange") { viewModel.arrangeCards() }
                Button("Shuffle") { viewModel.shuffleLayout() }
                Toggle("Show Overview", isOn: $viewModel.showOverview)
                Toggle("Show Link Labels", isOn: $viewModel.linkLabelsVisible)
                Toggle("Show File List", isOn: $viewModel.showFileList)
                Toggle("Show Card List", isOn: $viewModel.showCardList)
                Toggle("Show Inspector", isOn: $viewModel.showInspector)
            }

            CommandMenu("Export") {
                Button("Export Card Titles") { viewModel.exportCardTitles() }
                Button("Export Card Bodies") { viewModel.exportCardBodies() }
                Button("Export Hierarchical Text") { viewModel.exportHierarchicalText() }
                Button("Export HTML") { viewModel.exportHTMLDocument() }
                Divider()
                Button("Copy FIP2 to Clipboard") { viewModel.exportFIP2ToClipboard() }
                Button("Copy GPT Prompt") { viewModel.copyGPTPromptToClipboard() }
            }

            CommandMenu("Services") {
                Button("Web Search Selection") { viewModel.searchWebForSelection() }
                Button("Read Selected Card Aloud") { viewModel.readSelectedCardAloud() }
                Button("Stop Reading") { viewModel.stopReadAloud() }
            }

            CommandGroup(after: .help) {
                Button("Frieve Editor Website") { viewModel.browseHelp() }
                Button("Check Latest Release") { viewModel.checkLatestRelease() }
            }
        }
    }
}

struct WorkspaceRootView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
        } content: {
            CardListPane(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
        } detail: {
            WorkspaceContentView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: viewModel.newDocument) {
                    Label("New", systemImage: "doc.badge.plus")
                }
                Button(action: viewModel.openDocument) {
                    Label("Open", systemImage: "folder")
                }
                Button(action: viewModel.saveDocument) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)

                Picker("Arrange", selection: $viewModel.arrangeMode) {
                    Text("Link").tag("Link")
                    Text("Matrix").tag("Matrix")
                    Text("Radial").tag("Radial")
                    Text("Tree").tag("Tree")
                }
                .frame(width: 160)

                Button("Arrange") { viewModel.arrangeCards() }
                Button("Shuffle") { viewModel.shuffleLayout() }
                Button {
                    viewModel.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                Button {
                    viewModel.requestBrowserFit()
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                }
                Button {
                    viewModel.zoomToSelection(in: CGSize(width: 1200, height: 800))
                } label: {
                    Label("Selection", systemImage: "selection.pin.in.out")
                }
                Button {
                    viewModel.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                Toggle("Auto Zoom", isOn: $viewModel.autoZoom)
                Toggle("Overview", isOn: $viewModel.showOverview)
            }
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
                Button(action: viewModel.openDocument) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            TextField("Filter cards", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            List {
                if viewModel.showFileList {
                    Section("Recent") {
                        ForEach(viewModel.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                viewModel.openDocument(url)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Actions") {
                    Button("New Root Card") { viewModel.addRootCard() }
                    Button("New Child Card") { viewModel.addChildCard() }
                    Button("New Sibling Card") { viewModel.addSiblingCard() }
                    Button("Link to Root") { viewModel.addLinkBetweenSelectionAndRoot() }
                    Button("Delete Selected") { viewModel.deleteSelectedCard() }
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CardListPane: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cards")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.document.cardCount)")
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            if viewModel.showCardList {
                List(selection: Binding<Set<Int>>(get: {
                    viewModel.selectedCardIDs
                }, set: { selection in
                    if selection.isEmpty {
                        viewModel.clearSelection()
                    } else {
                        viewModel.selectedCardIDs = selection
                        viewModel.selectedCardID = selection.first
                        if let id = selection.first {
                            viewModel.selectCard(id)
                        }
                    }
                })) {
                    ForEach(viewModel.filteredCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .fontWeight(viewModel.selectedCardIDs.contains(card.id) ? .semibold : .regular)
                            Text(card.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .tag(card.id)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct WorkspaceContentView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    private let maintenanceTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(viewModel.fileDisplayName)
                    .font(.title3.weight(.semibold))
                Spacer()
                TextField("Global Search", text: $viewModel.globalSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Stepper(value: $viewModel.zoom, in: 0.5 ... 2.0, step: 0.1) {
                    Text("Zoom \(viewModel.zoom.formatted(.number.precision(.fractionLength(1))))x")
                }
                .frame(width: 170)
            }
            .padding(12)

            HStack(spacing: 0) {
                Group {
                    switch viewModel.selectedTab {
                    case .browser:
                        BrowserWorkspaceView(viewModel: viewModel)
                    case .editor:
                        EditorWorkspaceView(viewModel: viewModel)
                    case .drawing:
                        DrawingWorkspaceView(viewModel: viewModel)
                    case .statistics:
                        StatisticsWorkspaceView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.showInspector {
                    InspectorPaneView(viewModel: viewModel)
                        .frame(width: 280)
                        .background(Color(nsColor: .controlBackgroundColor))
                }
            }

            StatusBarView(viewModel: viewModel)
        }
        .onReceive(maintenanceTimer) { now in
            viewModel.performAutomaticMaintenance(now: now)
        }
    }
}

private struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                BrowserLayerSurfaceView(viewModel: viewModel)
                    .padding(12)

                VStack(alignment: .trailing, spacing: 10) {
                    BrowserCanvasHUD(viewModel: viewModel, canvasSize: geometry.size)
                    if viewModel.showOverview {
                        OverviewMiniMapView(viewModel: viewModel, size: geometry.size)
                            .frame(width: 220, height: 150)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct BrowserLayerSurfaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var browserFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            ZStack {
                BrowserSurfaceRepresentable(viewModel: viewModel, canvasSize: canvasSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let editingCard = viewModel.browserInlineEditorCard {
                    if let connector = viewModel.inlineEditorConnectorPoints(for: editingCard, in: canvasSize) {
                        Path { path in
                            path.move(to: connector.0)
                            path.addLine(to: connector.1)
                        }
                        .stroke(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .allowsHitTesting(false)
                    }

                    BrowserInlineEditorOverlay(
                        viewModel: viewModel,
                        card: editingCard,
                        canvasSize: canvasSize,
                        cardFrame: viewModel.cardFrame(for: editingCard, in: canvasSize)
                    )
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        if let hoverCard = viewModel.browserHoverCard {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Image(systemName: hoverCard.shapeSymbolName)
                                        .foregroundStyle(Color.accentColor)
                                    Text(hoverCard.title)
                                        .font(.caption.weight(.semibold))
                                }
                                Text(viewModel.cardDisplaySummary(for: hoverCard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Spacer()
                        Text(viewModel.browserViewportSummary(in: canvasSize))
                            .font(.caption2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(16)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .clipped()
            .focusable()
            .focused($browserFocused)
            .onAppear {
                browserFocused = true
                viewModel.resetCanvasToFit(in: canvasSize)
            }
            .onTapGesture {
                browserFocused = true
            }
            .onChange(of: viewModel.browserViewportRevision) { _ in
                viewModel.resetCanvasToFit(in: canvasSize)
            }
        }
    }
}

private struct BrowserCardShape: Shape {
    let shapeIndex: Int

    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect, shapeIndex: shapeIndex))
    }

    static func cgPath(in rect: CGRect, shapeIndex: Int) -> CGPath {
        switch ((shapeIndex % 6) + 6) % 6 {
        case 0:
            return CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        case 1:
            return CGPath(ellipseIn: rect, transform: nil)
        case 2:
            return CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        case 3:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case 4:
            let inset = rect.width * 0.14
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        default:
            return CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        }
    }
}

struct BrowserCardRasterContentView: View {
    let card: FrieveCard
    let metadata: BrowserCardMetadata
    let detailLevel: BrowserCardDetailLevel
    let fillColor: Color
    let previewImage: NSImage?
    let drawingPreviewImage: NSImage?

    var body: some View {
        let labelLine = detailLevel == .thumbnail ? "" : metadata.labelLine
        let detailSummary = detailLevel == .thumbnail ? "" : metadata.detailSummary
        let badges = detailLevel == .full ? metadata.badges : Array(metadata.badges.prefix(2))
        let summaryLineLimit = detailLevel == .compact ? 2 : 3

        VStack(alignment: .leading, spacing: detailLevel == .thumbnail ? 6 : 8) {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: detailLevel == .thumbnail ? 58 : 72)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if detailLevel != .thumbnail {
                            Label(metadata.mediaBadgeText, systemImage: "photo")
                                .font(.caption2)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: card.shapeSymbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.title)
                            .font(detailLevel == .thumbnail ? .subheadline.weight(.semibold) : .headline)
                            .lineLimit(1)
                    }

                    if detailLevel != .thumbnail {
                        if card.isFolded {
                            Label("Folded", systemImage: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(metadata.summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(summaryLineLimit)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    if card.isFixed && detailLevel != .thumbnail {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("#\(card.id)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !labelLine.isEmpty {
                Text(labelLine)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }

            if !detailSummary.isEmpty {
                Text(detailSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.35)))
                    }
                }
            }

            HStack(spacing: 10) {
                Label("\(metadata.linkCount)", systemImage: "point.3.connected.trianglepath.dotted")
                Label(card.score.formatted(.number.precision(.fractionLength(1))), systemImage: "chart.bar")
                if detailLevel != .thumbnail {
                    Label(card.shapeName, systemImage: card.shapeSymbolName)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let drawingPreviewImage, detailLevel == .full {
                HStack {
                    Spacer(minLength: 0)
                    Image(nsImage: drawingPreviewImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .frame(width: 96, height: 72)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(detailLevel == .thumbnail ? 10 : 12)
        .frame(width: metadata.canvasSize.width, height: metadata.canvasSize.height, alignment: .topLeading)
        .background(BrowserCardShape(shapeIndex: card.shape).fill(fillColor))
        .clipShape(BrowserCardShape(shapeIndex: card.shape))
    }
}

private struct BrowserMediaPreviewView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard
    let badgeText: String

    var body: some View {
        Group {
            if let image = viewModel.cachedPreviewImage(for: card) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Label(badgeText, systemImage: "photo")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
            } else if let url = viewModel.mediaURL(for: card.videoPath) {
                ZStack {
                    LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 26))
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.15)))
    }
}

private struct BrowserDrawingOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard

    var body: some View {
        Group {
            if let image = viewModel.cachedDrawingPreviewImage(for: card, targetSize: CGSize(width: 96, height: 72)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                EmptyView()
            }
        }
        .frame(width: 96, height: 72)
        .allowsHitTesting(false)
    }
}

private struct BrowserInlineEditorOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard
    let canvasSize: CGSize
    let cardFrame: CGRect

    var body: some View {
        let editorFrame = viewModel.browserInlineEditorFrame(for: card, in: canvasSize)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inline Browser Editor")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.selectedTab = .editor
                } label: {
                    Label("Editor", systemImage: "sidebar.right")
                }
                .buttonStyle(.borderless)
                Button {
                    viewModel.dismissBrowserInlineEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }

            TextField("Card title", text: viewModel.bindingForSelectedTitle())
                .textFieldStyle(.roundedBorder)

            TextEditor(text: viewModel.bindingForSelectedBody())
                .font(.body)
                .frame(minHeight: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))

            HStack {
                Button("Web Search") { viewModel.searchWebForSelection() }
                Button("Read") { viewModel.readSelectedCardAloud() }
                Spacer()
                Text(card.updated)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(width: editorFrame.width, height: editorFrame.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.22)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .position(x: editorFrame.midX, y: editorFrame.midY)
    }
}

private struct BrowserCanvasHUD: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let canvasSize: CGSize

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 12) {
                Label("AppKit", systemImage: "square.3.layers.3d")
                Label("\(viewModel.selectedCardIDs.count)", systemImage: "checkmark.circle")
                Label("\(viewModel.zoom.formatted(.number.precision(.fractionLength(2))))×", systemImage: "magnifyingglass")
                Label(viewModel.autoScroll ? "Follow" : "Free", systemImage: viewModel.autoScroll ? "scope" : "hand.draw")
            }
            HStack(spacing: 12) {
                Button("Fit") { viewModel.requestBrowserFit() }
                Button("Selection") { viewModel.zoomToSelection(in: canvasSize) }
                Toggle("Auto Scroll", isOn: $viewModel.autoScroll)
                    .toggleStyle(.checkbox)
                Toggle("Auto Zoom", isOn: $viewModel.autoZoom)
                    .toggleStyle(.checkbox)
                Toggle("Link Labels", isOn: $viewModel.linkLabelsVisible)
                    .toggleStyle(.checkbox)
            }
            Text(viewModel.browserPerformanceSummary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct BrowserInteractionBridge: NSViewRepresentable {
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

private struct BrowserSurfaceRepresentable: NSViewRepresentable {
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

private final class BrowserSurfaceNSView: BrowserInteractionNSView {
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

private struct CanvasGridView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, size in
            let visible = viewModel.visibleWorldRect(in: size)
            let gridStep = 0.05
            let startX = floor(visible.minX / gridStep) * gridStep
            let endX = ceil(visible.maxX / gridStep) * gridStep
            let startY = floor(visible.minY / gridStep) * gridStep
            let endY = ceil(visible.maxY / gridStep) * gridStep

            var x = startX
            while x <= endX {
                let point = viewModel.canvasPoint(for: FrievePoint(x: x, y: visible.minY), in: size)
                var path = Path()
                path.move(to: CGPoint(x: point.x, y: 0))
                path.addLine(to: CGPoint(x: point.x, y: size.height))
                let isMajor = abs((x * 100).truncatingRemainder(dividingBy: 25)) < 0.001
                context.stroke(path, with: .color(.secondary.opacity(isMajor ? 0.12 : 0.06)), lineWidth: isMajor ? 1.0 : 0.6)
                x += gridStep
            }

            var y = startY
            while y <= endY {
                let point = viewModel.canvasPoint(for: FrievePoint(x: visible.minX, y: y), in: size)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: point.y))
                path.addLine(to: CGPoint(x: size.width, y: point.y))
                let isMajor = abs((y * 100).truncatingRemainder(dividingBy: 25)) < 0.001
                context.stroke(path, with: .color(.secondary.opacity(isMajor ? 0.12 : 0.06)), lineWidth: isMajor ? 1.0 : 0.6)
                y += gridStep
            }
        }
    }
}

private extension NSImage {
    var browserCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private struct OverviewMiniMapView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let size: CGSize

    var body: some View {
        let snapshot = viewModel.overviewSnapshot()
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
            Canvas { context, canvasSize in
                for link in snapshot.links {
                    var path = Path()
                    path.move(to: viewModel.overviewPoint(for: link.from, in: canvasSize, snapshot: snapshot))
                    path.addLine(to: viewModel.overviewPoint(for: link.to, in: canvasSize, snapshot: snapshot))
                    context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                }

                for cardPoint in snapshot.cards {
                    let point = viewModel.overviewPoint(for: cardPoint.point, in: canvasSize, snapshot: snapshot)
                    let rect = CGRect(x: point.x - 6, y: point.y - 4, width: 12, height: 8)
                    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(viewModel.selectedCardIDs.contains(cardPoint.cardID) ? .accentColor : .secondary.opacity(0.45)))
                }

                let viewport = viewModel.overviewViewportRect(overviewSize: canvasSize, canvasSize: size, snapshot: snapshot)
                context.fill(Path(roundedRect: viewport, cornerRadius: 4), with: .color(.accentColor.opacity(0.14)))
                context.stroke(Path(roundedRect: viewport, cornerRadius: 4), with: .color(.accentColor.opacity(0.85)), lineWidth: 1.5)
            }
            .padding(10)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    viewModel.recenterFromOverview(location: value.location, overviewSize: CGSize(width: 220, height: 150))
                }
        )
    }
}

private struct EditorWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Card title", text: viewModel.bindingForSelectedTitle())
                    .textFieldStyle(.roundedBorder)
                Button("Web Search") { viewModel.searchWebForSelection() }
                Button("Read Aloud") { viewModel.readSelectedCardAloud() }
                Button("Stop") { viewModel.stopReadAloud() }
            }
            TextEditor(text: viewModel.bindingForSelectedBody())
                .font(.body.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
            HStack {
                Text("Related links: \(viewModel.selectedCardLinks.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy FIP2") { viewModel.exportFIP2ToClipboard() }
                Button("Copy GPT Prompt") { viewModel.copyGPTPromptToClipboard() }
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

private struct DrawingWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Tool", selection: $viewModel.selectedDrawingTool) {
                    Text("Cursor").tag("Cursor")
                    Text("FreeHand").tag("FreeHand")
                    Text("Line").tag("Line")
                    Text("Rect").tag("Rect")
                    Text("Circle").tag("Circle")
                    Text("Text").tag("Text")
                }
                .pickerStyle(.segmented)
                Spacer()
                Text("Encoded drawing payload")
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: viewModel.bindingForSelectedDrawing())
                .font(.body.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        }
        .padding(16)
    }
}

private struct StatisticsWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        Table(viewModel.statisticsRows) {
            TableColumn("Title", value: \.title)
            TableColumn("Body") { row in
                Text("\(row.bodyLength)")
            }
            TableColumn("Links") { row in
                Text("\(row.linkCount)")
            }
            TableColumn("Labels") { row in
                Text(row.labelNames.joined(separator: ", "))
            }
            TableColumn("Size") { row in
                Text("\(row.size)")
            }
            TableColumn("Score") { row in
                Text(row.score.formatted(.number.precision(.fractionLength(2))))
            }
        }
        .padding(16)
    }
}

private struct InspectorPaneView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)
            if let card = viewModel.selectedCard {
                LabeledContent("Title", value: card.title)
                LabeledContent("Card ID", value: String(card.id))
                LabeledContent("Labels", value: viewModel.cardLabelNames(for: card).joined(separator: ", "))
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
                    HStack {
                        Text("Card Size")
                        Spacer()
                        Text("\(card.size)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: viewModel.bindingForSelectedSize(), in: 80 ... 320, step: 10)
                }

                TextField("Image path", text: viewModel.bindingForSelectedImagePath())
                    .textFieldStyle(.roundedBorder)
                TextField("Video path", text: viewModel.bindingForSelectedVideoPath())
                    .textFieldStyle(.roundedBorder)

                Toggle("Top Card", isOn: .constant(card.isTop))
                    .disabled(true)
                Toggle("Fixed", isOn: viewModel.bindingForSelectedFixed())
                Toggle("Folded", isOn: viewModel.bindingForSelectedFolded())

                HStack {
                    Button("Focus Browser") {
                        viewModel.selectedTab = .browser
                        viewModel.focusBrowser(on: card.id)
                    }
                    Button("Inline Edit") {
                        viewModel.selectedTab = .browser
                        viewModel.handleCardDoubleClick(card.id)
                    }
                }
            } else {
                Text("No card selected")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Automation")
                .font(.headline)
            Toggle("Auto Save", isOn: $viewModel.settings.autoSaveDefault)
            Toggle("Auto Reload", isOn: $viewModel.settings.autoReloadDefault)
            HStack {
                Text("Web Search")
                Spacer()
                Picker("Web Search", selection: $viewModel.settings.preferredWebSearchName) {
                    ForEach(viewModel.settings.webSearchProviders) { provider in
                        Text(provider.name).tag(provider.name)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            HStack {
                Text("Read Speed")
                Spacer()
                Text("\(Int(viewModel.settings.readAloudRate))")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.settings.readAloudRate, in: 100 ... 320, step: 5)
            TextField("GPT Model", text: $viewModel.settings.gptModel)
                .textFieldStyle(.roundedBorder)

            Divider()

            Text("Global Search")
                .font(.headline)
            List(viewModel.globalSearchResults) { card in
                Button(card.title) {
                    viewModel.selectCard(card.id)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

private struct StatusBarView: View {
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
