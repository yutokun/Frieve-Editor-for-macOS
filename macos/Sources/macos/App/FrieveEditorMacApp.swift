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
                BrowserCanvasView(viewModel: viewModel)
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

private struct BrowserCanvasView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var browserFocused: Bool

    private let gridOverlayOpacity = Color.secondary.opacity(0.08)

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let scene = viewModel.browserCanvasScene(in: canvasSize)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color(nsColor: .textBackgroundColor), Color(nsColor: .underPageBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !viewModel.hasActiveBrowserGesture {
                                    viewModel.beginCanvasGesture(at: value.startLocation, modifiers: currentModifierFlags())
                                }
                                viewModel.updateCanvasGesture(from: value.startLocation, to: value.location, in: canvasSize)
                            }
                            .onEnded { _ in
                                viewModel.endCanvasGesture(in: canvasSize)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture(count: 1)
                            .onEnded { _ in
                                if !currentModifierFlags().contains(.shift) && !currentModifierFlags().contains(.command) {
                                    viewModel.clearSelection()
                                }
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { value in
                                viewModel.addCard(at: value.location, in: canvasSize)
                            }
                    )

                Canvas { context, size in
                    let guidePath = viewModel.browserBackgroundGuidePath(in: size)
                    context.stroke(
                        guidePath,
                        with: .color(gridOverlayOpacity),
                        style: StrokeStyle(lineWidth: 0.7)
                    )

                    for link in scene.links {
                        let lineColor: Color = link.isHighlighted ? .accentColor.opacity(0.85) : .secondary.opacity(0.42)
                        context.stroke(link.path, with: .color(lineColor), style: StrokeStyle(lineWidth: link.isHighlighted ? 3 : 2, lineCap: .round, lineJoin: .round))

                        if let arrowHead = link.arrowHead {
                            var arrowPath = Path()
                            arrowPath.move(to: arrowHead[0])
                            arrowPath.addLines([arrowHead[1], arrowHead[2], arrowHead[0]])
                            context.fill(arrowPath, with: .color(lineColor))
                        }

                        if let labelPoint = link.labelPoint {
                            let labelText = Text(link.link.name).font(.caption2.weight(.semibold))
                            context.draw(labelText, at: labelPoint, anchor: .bottom)
                        }
                    }

                    if let preview = viewModel.linkPreviewSegment(in: size) {
                        var previewPath = Path()
                        previewPath.move(to: preview.0)
                        previewPath.addLine(to: preview.1)
                        context.stroke(previewPath, with: .color(.accentColor.opacity(0.65)), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ForEach(scene.cards) { render in
                    let position = viewModel.canvasPoint(for: render.position, in: canvasSize)
                    CardNodeView(viewModel: viewModel, renderData: render, canvasSize: canvasSize)
                        .position(position)
                }

                if let selectionFrame = viewModel.selectionFrame(in: canvasSize), viewModel.selectedCardIDs.count > 1 {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [7, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.accentColor.opacity(0.06))
                        )
                        .frame(width: selectionFrame.width + 18, height: selectionFrame.height + 18)
                        .position(x: selectionFrame.midX, y: selectionFrame.midY)
                        .allowsHitTesting(false)
                }

                if let marqueeRect = viewModel.marqueeRect() {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.10))
                        .overlay(Rectangle().stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .frame(width: marqueeRect.width, height: marqueeRect.height)
                        .position(x: marqueeRect.midX, y: marqueeRect.midY)
                        .allowsHitTesting(false)
                }

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
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        viewModel.updateMagnification(value, in: canvasSize)
                    }
                    .onEnded { _ in
                        viewModel.endMagnification()
                    }
            )
            .background(
                BrowserInteractionBridge(
                    onScroll: { deltaX, deltaY, location, modifiers in
                        viewModel.handleScrollWheel(deltaX: deltaX, deltaY: deltaY, modifiers: modifiers, at: location, in: canvasSize)
                    },
                    onDelete: {
                        viewModel.deleteSelectedCard()
                    },
                    onMoveSelection: { dx, dy in
                        viewModel.nudgeSelection(dx: dx, dy: dy)
                    },
                    onZoomIn: {
                        viewModel.zoomIn()
                    },
                    onZoomOut: {
                        viewModel.zoomOut()
                    },
                    onFit: {
                        viewModel.requestBrowserFit()
                    }
                )
            )
        }
    }
}

private struct CardNodeView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let renderData: BrowserCardRenderData
    let canvasSize: CGSize

    var body: some View {
        let card = renderData.card
        let metadata = renderData.metadata
        let isSelected = viewModel.selectedCardIDs.contains(card.id)
        let isHovered = viewModel.browserHoverCardID == card.id
        let cardSize = metadata.canvasSize
        let badges = metadata.badges
        let labelLine = metadata.labelLine
        let drawingPreviewEnabled = metadata.hasDrawingPreview
        let detailSummary = metadata.detailSummary
        let summaryText = metadata.summaryText

        VStack(alignment: .leading, spacing: 8) {
            if card.hasMedia {
                BrowserMediaPreviewView(viewModel: viewModel, card: card, badgeText: metadata.mediaBadgeText)
                    .frame(height: 72)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: card.shapeSymbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    if !card.isFolded {
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        Label("Folded", systemImage: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    if card.isFixed {
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
                ScrollView(.horizontal, showsIndicators: false) {
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
                .frame(height: 22)
            }

            HStack(spacing: 10) {
                Label("\(metadata.linkCount)", systemImage: "point.3.connected.trianglepath.dotted")
                Label(card.score.formatted(.number.precision(.fractionLength(1))), systemImage: "chart.bar")
                Label(card.shapeName, systemImage: card.shapeSymbolName)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: cardSize.width, height: cardSize.height, alignment: .topLeading)
        .background(
            BrowserCardShape(shapeIndex: card.shape)
                .fill(viewModel.color(for: card))
        )
        .overlay {
            BrowserCardShape(shapeIndex: card.shape)
                .fill(viewModel.browserCardGlow(for: card, isSelected: isSelected))
        }
        .overlay {
            BrowserCardShape(shapeIndex: card.shape)
                .stroke(
                    viewModel.browserCardStrokeColor(for: card, isSelected: isSelected, isHovered: isHovered),
                    lineWidth: isSelected ? 3 : (isHovered ? 2 : 1)
                )
        }
        .overlay(alignment: .bottomTrailing) {
            if drawingPreviewEnabled {
                BrowserDrawingOverlay(viewModel: viewModel, card: card)
                    .padding(8)
            }
        }
        .shadow(color: viewModel.browserCardShadow(for: card, isSelected: isSelected, isHovered: isHovered), radius: isSelected ? 12 : (isHovered ? 10 : 8), y: 3)
        .contentShape(BrowserCardShape(shapeIndex: card.shape))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    viewModel.updateCardInteraction(cardID: card.id, gesture: value, in: canvasSize, modifiers: currentModifierFlags())
                }
                .onEnded { value in
                    viewModel.endCardInteraction(gesture: value, in: canvasSize)
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 1)
                .onEnded { _ in
                    viewModel.handleCardTap(card.id, modifiers: currentModifierFlags())
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { _ in
                    viewModel.handleCardDoubleClick(card.id)
                }
        )
        .onHover { hovering in
            viewModel.setBrowserHoverCard(hovering ? card.id : nil)
        }
    }
}

private struct BrowserCardShape: Shape {
    let shapeIndex: Int

    func path(in rect: CGRect) -> Path {
        switch ((shapeIndex % 6) + 6) % 6 {
        case 0:
            return RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect)
        case 1:
            return Capsule(style: .continuous).path(in: rect)
        case 2:
            return RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
        case 3:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case 4:
            var path = Path()
            let inset = rect.width * 0.14
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        default:
            var path = Path(roundedRect: rect, cornerRadius: 12)
            let foldWidth = min(rect.width * 0.18, 18)
            path.move(to: CGPoint(x: rect.maxX - foldWidth, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - foldWidth, y: rect.minY + foldWidth))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + foldWidth))
            return path
        }
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
            }
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

final class BrowserInteractionNSView: NSView {
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
