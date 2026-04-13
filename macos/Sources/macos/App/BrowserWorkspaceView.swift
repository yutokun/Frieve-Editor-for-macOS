import SwiftUI
import AppKit

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                BrowserLayerSurfaceView(viewModel: viewModel)

                VStack(alignment: .trailing, spacing: 10) {
                    if viewModel.showOverview {
                        OverviewMiniMapView(viewModel: viewModel, size: geometry.size)
                            .frame(width: 220, height: 150)
                    }
                    if let mode = viewModel.activeBrowserAnimation {
                        BrowserAnimationHUD(viewModel: viewModel, mode: mode)
                    }
                    BrowserCanvasHUD(viewModel: viewModel, canvasSize: geometry.size)
                }
                .padding(16)
            }
        }
    }
}

private struct BrowserLayerSurfaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var browserFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let _ = viewModel.browserChromeRevision
            ZStack {
                BrowserCanvasBackgroundView(viewModel: viewModel, colorScheme: colorScheme)
                BrowserSurfaceRepresentable(viewModel: viewModel, canvasSize: canvasSize)

                if viewModel.settings.browserCursorAnimation {
                    BrowserCursorPulseOverlay(viewModel: viewModel, canvasSize: canvasSize, colorScheme: colorScheme)
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
                            Text(hoverCard.title)
                                .font(.caption.weight(.semibold))
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

private struct BrowserCanvasBackgroundView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: browserCanvasBackgroundColor(for: colorScheme)))

            if let image = wallpaperImage {
                if viewModel.settings.browserWallpaperTiled {
                    GeometryReader { proxy in
                        Canvas { context, size in
                            let tileSize = image.size
                            guard tileSize.width > 0, tileSize.height > 0 else { return }
                            let columns = Int(ceil(size.width / tileSize.width)) + 1
                            let rows = Int(ceil(size.height / tileSize.height)) + 1
                            for row in 0..<rows {
                                for column in 0..<columns {
                                    let origin = CGPoint(
                                        x: CGFloat(column) * tileSize.width,
                                        y: CGFloat(row) * tileSize.height
                                    )
                                    context.draw(Image(nsImage: image), at: origin, anchor: .topLeading)
                                }
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: viewModel.settings.browserWallpaperFixed ? .fill : .fit)
                        .opacity(0.30)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }

            if viewModel.settings.browserBackgroundAnimation {
                BrowserAnimatedBackgroundOverlay(
                    viewModel: viewModel,
                    colorScheme: colorScheme
                )
            }
        }
        .allowsHitTesting(false)
    }

    private var wallpaperImage: NSImage? {
        guard let url = viewModel.browserWallpaperURL() else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct BrowserAnimatedBackgroundOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let colorScheme: ColorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                switch viewModel.browserBackgroundAnimationType {
                case .flowingLines:
                    drawFlowingLines(context: &context, size: size, time: time)
                case .bubbles:
                    drawBubbles(context: &context, size: size, time: time)
                case .snow:
                    drawSnow(context: &context, size: size, time: time)
                case .petals:
                    drawPetals(context: &context, size: size, time: time)
                }
            }
        }
        .opacity(colorScheme == .dark ? 0.55 : 0.35)
        .allowsHitTesting(false)
    }

    private func drawFlowingLines(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let base = browserLinkStrokeColor(for: colorScheme, highlighted: false).withAlphaComponent(0.22)
        for index in 0..<18 {
            let progress = CGFloat(((time * 36) + Double(index * 41)).truncatingRemainder(dividingBy: 900)) - 120
            var path = Path()
            path.move(to: CGPoint(x: progress, y: CGFloat(index) * 44))
            path.addLine(to: CGPoint(x: progress + 220, y: CGFloat(index) * 44 + 70))
            context.stroke(path, with: .color(Color(nsColor: base)), lineWidth: index.isMultiple(of: 3) ? 2.5 : 1.2)
        }
    }

    private func drawBubbles(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let color = Color(nsColor: browserLinkStrokeColor(for: colorScheme, highlighted: false))
        for index in 0..<28 {
            let normalized = Double(index) / 28
            let x = CGFloat((normalized * 1_137).truncatingRemainder(dividingBy: 1)) * max(size.width, 1)
            let yProgress = CGFloat(((time * 0.08) + normalized).truncatingRemainder(dividingBy: 1))
            let y = size.height - (size.height + 80) * yProgress
            let diameter = CGFloat(10 + (index % 5) * 6)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                with: .color(color.opacity(0.18))
            )
        }
    }

    private func drawSnow(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let color = Color.white.opacity(colorScheme == .dark ? 0.24 : 0.18)
        for index in 0..<40 {
            let normalized = Double(index) / 40
            let xOffset = CGFloat(sin(time * 0.7 + normalized * 12) * 18)
            let x = CGFloat((normalized * 927).truncatingRemainder(dividingBy: 1)) * max(size.width, 1) + xOffset
            let yProgress = CGFloat(((time * 0.06) + normalized * 1.7).truncatingRemainder(dividingBy: 1))
            let y = (size.height + 40) * yProgress - 20
            let diameter = CGFloat(3 + index % 4)
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                with: .color(color)
            )
        }
    }

    private func drawPetals(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let color = Color.pink.opacity(colorScheme == .dark ? 0.20 : 0.16)
        for index in 0..<24 {
            let normalized = Double(index) / 24
            let x = CGFloat((normalized * 743 + time * 18).truncatingRemainder(dividingBy: 1)) * max(size.width, 1)
            let yProgress = CGFloat(((time * 0.04) + normalized * 1.3).truncatingRemainder(dividingBy: 1))
            let y = (size.height + 60) * yProgress - 30
            let width = CGFloat(10 + index % 5)
            let height = width * 0.66
            let rect = CGRect(x: x, y: y, width: width, height: height)
            context.rotate(by: .degrees(Double(index * 17) + time * 15))
            context.fill(Path(ellipseIn: rect), with: .color(color))
            context.rotate(by: .degrees(-(Double(index * 17) + time * 15)))
        }
    }
}

private struct BrowserCursorPulseOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let canvasSize: CGSize
    let colorScheme: ColorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            if let pulseFrame {
                let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        viewModel.browserCursorPulseColor(for: colorScheme),
                        lineWidth: 2 + phase * 3
                    )
                    .frame(width: pulseFrame.width + 18 + phase * 14, height: pulseFrame.height + 18 + phase * 14)
                    .position(x: pulseFrame.midX, y: pulseFrame.midY)
                    .blur(radius: 0.5 + phase * 1.4)
                    .allowsHitTesting(false)
            }
        }
    }

    private var pulseFrame: CGRect? {
        if let hoverCard = viewModel.browserHoverCard {
            return viewModel.cardFrame(for: hoverCard, in: canvasSize)
        }
        guard let selectedCard = viewModel.selectedCard else { return nil }
        return viewModel.cardFrame(for: selectedCard, in: canvasSize)
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
                Label("Metal", systemImage: "cpu")
                Label("\(Int(viewModel.browserPerformance.frameInterval.rollingFPS.rounded())) fps", systemImage: "speedometer")
                Label("\(viewModel.selectedCardIDs.count)", systemImage: "checkmark.circle")
                Label("\(viewModel.zoom.formatted(.number.precision(.fractionLength(2))))×", systemImage: "magnifyingglass")
                Label(viewModel.autoScroll ? "Follow" : "Free", systemImage: viewModel.autoScroll ? "scope" : "hand.draw")
            }
            HStack(spacing: 12) {
                Picker("Arrange", selection: $viewModel.arrangeMode) {
                    Text("None").tag("None")
                    Text("Link").tag("Link")
                    Text("Link(Soft)").tag("Link(Soft)")
                    Text("Matrix").tag("Matrix")
                    Text("Tree").tag("Tree")
                }
                .fixedSize()
                Button("Shuffle") { viewModel.shuffleLayout() }
                Toggle("Auto Scroll", isOn: $viewModel.autoScroll)
                    .toggleStyle(.checkbox)
                Toggle("Auto Zoom", isOn: $viewModel.autoZoom)
                    .toggleStyle(.checkbox)
                Toggle("Link Labels", isOn: Binding(
                    get: { viewModel.linkLabelsVisible },
                    set: { viewModel.setBrowserLinkLabelsVisible($0) }
                ))
                    .toggleStyle(.checkbox)
                Toggle("Label Rects", isOn: Binding(
                    get: { viewModel.labelRectanglesVisible },
                    set: { viewModel.setBrowserLabelRectanglesVisible($0) }
                ))
                    .toggleStyle(.checkbox)
                Toggle("Overview", isOn: $viewModel.showOverview)
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

private struct BrowserAnimationHUD: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let mode: BrowserAnimationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(mode.title, systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                Spacer()
                Button(viewModel.animationPaused ? "Resume" : "Pause") {
                    viewModel.toggleBrowserAnimationPause()
                }
                Button("Stop") {
                    viewModel.stopBrowserAnimation()
                }
            }

            HStack(spacing: 12) {
                Button("Full Screen") {
                    viewModel.toggleBrowserAnimationFullScreen()
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Zoom")
                        Spacer()
                        Text("\(viewModel.zoom.formatted(.number.precision(.fractionLength(2))))×")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.zoom },
                            set: { viewModel.setBrowserAnimationZoom($0) }
                        ),
                        in: 0.2 ... 4.0
                    )
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(viewModel.animationSpeed)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.animationSpeed) },
                            set: { viewModel.animationSpeed = Int($0.rounded()) }
                        ),
                        in: 1 ... 100,
                        step: 1
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Cards")
                        Spacer()
                        Text("\(viewModel.animationVisibleCardCount)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.animationVisibleCardCount) },
                            set: { viewModel.animationVisibleCardCount = Int($0.rounded()) }
                        ),
                        in: 1 ... 30,
                        step: 1
                    )
                }
            }
        }
        .font(.caption)
        .padding(12)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
