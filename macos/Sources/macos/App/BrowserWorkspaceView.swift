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

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let _ = viewModel.browserChromeRevision
            ZStack {
                BrowserSurfaceRepresentable(viewModel: viewModel, canvasSize: canvasSize)

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
