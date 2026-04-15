import SwiftUI
import AppKit

func browserWallpaperRect(for imageSize: CGSize, in canvasSize: CGSize, fixed: Bool) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
    let widthRatio = canvasSize.width / imageSize.width
    let heightRatio = canvasSize.height / imageSize.height
    let scale = fixed ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
    let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: (canvasSize.width - drawSize.width) / 2,
        y: (canvasSize.height - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
}

func browserTickerVisibleRects(in stripRect: CGRect, occludingRects: [CGRect]) -> [CGRect] {
    guard !stripRect.isNull, !stripRect.isEmpty else { return [] }

    var visibleRects = [stripRect]
    for occludingRect in occludingRects {
        let clippedOcclusion = stripRect.intersection(occludingRect)
        if clippedOcclusion.isNull || clippedOcclusion.isEmpty {
            continue
        }
        visibleRects = visibleRects.flatMap { subtractTickerOcclusion(clippedOcclusion, from: $0) }
        if visibleRects.isEmpty {
            break
        }
    }
    return visibleRects
}

private func subtractTickerOcclusion(_ occlusion: CGRect, from rect: CGRect) -> [CGRect] {
    let intersection = rect.intersection(occlusion)
    if intersection.isNull || intersection.isEmpty {
        return [rect]
    }

    var result: [CGRect] = []

    if intersection.minY > rect.minY {
        result.append(
            CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: intersection.minY - rect.minY
            )
        )
    }

    if intersection.maxY < rect.maxY {
        result.append(
            CGRect(
                x: rect.minX,
                y: intersection.maxY,
                width: rect.width,
                height: rect.maxY - intersection.maxY
            )
        )
    }

    let middleMinY = max(rect.minY, intersection.minY)
    let middleMaxY = min(rect.maxY, intersection.maxY)
    if middleMaxY > middleMinY {
        if intersection.minX > rect.minX {
            result.append(
                CGRect(
                    x: rect.minX,
                    y: middleMinY,
                    width: intersection.minX - rect.minX,
                    height: middleMaxY - middleMinY
                )
            )
        }

        if intersection.maxX < rect.maxX {
            result.append(
                CGRect(
                    x: intersection.maxX,
                    y: middleMinY,
                    width: rect.maxX - intersection.maxX,
                    height: middleMaxY - middleMinY
                )
            )
        }
    }

    return result.filter { !$0.isNull && !$0.isEmpty && $0.width > 0 && $0.height > 0 }
}

struct BrowserFlowingLineParticle: Hashable {
    let start: CGPoint
    let end: CGPoint
    let lineWidth: CGFloat
    let opacity: Double

    var isMostlyHorizontal: Bool {
        abs(end.x - start.x) >= abs(end.y - start.y)
    }
}

struct BrowserBubbleParticle: Hashable {
    let rect: CGRect
    let opacity: Double
    let lineWidth: CGFloat
}

struct BrowserSnowParticle: Hashable {
    let rect: CGRect
    let opacity: Double
}

func browserAnimationNoise(_ index: Int, salt: Double) -> Double {
    let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43_758.5453
    return value - floor(value)
}

func browserFlowingLineParticles(in size: CGSize, time: TimeInterval) -> [BrowserFlowingLineParticle] {
    guard size.width > 0, size.height > 0 else { return [] }

    return (0..<28).map { index in
        let orientationSeed = browserAnimationNoise(index, salt: 0.11)
        let isHorizontal = orientationSeed < 0.5
        let thickness = CGFloat(1.0 + browserAnimationNoise(index, salt: 0.23) * 2.4)
        let opacity = 0.10 + browserAnimationNoise(index, salt: 0.31) * 0.16
        let speed = 0.04 + browserAnimationNoise(index, salt: 0.47) * 0.12
        let phase = browserAnimationNoise(index, salt: 0.59)
        let swayPhase = browserAnimationNoise(index, salt: 0.71) * .pi * 2
        let swaySpeed = 0.7 + browserAnimationNoise(index, salt: 0.83) * 1.4
        let swayAmplitude = CGFloat(10 + browserAnimationNoise(index, salt: 0.97) * 34)

        if isHorizontal {
            let travel = CGFloat((time * speed + phase).truncatingRemainder(dividingBy: 1))
            let yBase = CGFloat(browserAnimationNoise(index, salt: 1.11)) * size.height
            let y = yBase + sin(time * swaySpeed + swayPhase) * swayAmplitude
            let x = -size.width + travel * size.width * 2
            return BrowserFlowingLineParticle(
                start: CGPoint(x: x, y: y),
                end: CGPoint(x: x + size.width, y: y),
                lineWidth: thickness,
                opacity: opacity
            )
        } else {
            let travel = CGFloat((time * speed + phase).truncatingRemainder(dividingBy: 1))
            let xBase = CGFloat(browserAnimationNoise(index, salt: 1.27)) * size.width
            let x = xBase + sin(time * swaySpeed + swayPhase) * swayAmplitude
            let y = -size.height + travel * size.height * 2
            return BrowserFlowingLineParticle(
                start: CGPoint(x: x, y: y),
                end: CGPoint(x: x, y: y + size.height),
                lineWidth: thickness,
                opacity: opacity
            )
        }
    }
}

func browserBubbleParticles(in size: CGSize, time: TimeInterval) -> [BrowserBubbleParticle] {
    guard size.width > 0, size.height > 0 else { return [] }

    return (0..<36).map { index in
        let sizeSeed = browserAnimationNoise(index, salt: 1.41)
        let driftSeed = browserAnimationNoise(index, salt: 1.57)
        let phase = browserAnimationNoise(index, salt: 1.73)
        let xSeed = browserAnimationNoise(index, salt: 1.89)
        let diameter = CGFloat(10 + sizeSeed * 24)
        let riseSpeed = 0.035 + sizeSeed * 0.08
        let yProgress = CGFloat((time * riseSpeed + phase).truncatingRemainder(dividingBy: 1))
        let y = size.height + diameter - yProgress * (size.height + diameter * 2)
        let swayAmplitude = CGFloat(12 + driftSeed * 30)
        let sway = sin(time * (0.8 + driftSeed * 1.4) + phase * .pi * 2) * swayAmplitude
        let wobble = sin(time * (1.7 + driftSeed * 1.1) + Double(index)) * (swayAmplitude * 0.35)
        let x = CGFloat(xSeed) * size.width + sway + wobble
        let opacity = 0.08 + sizeSeed * 0.16
        return BrowserBubbleParticle(
            rect: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter),
            opacity: opacity,
            lineWidth: 1 + CGFloat(driftSeed * 1.8)
        )
    }
}

func browserSnowParticles(in size: CGSize, time: TimeInterval) -> [BrowserSnowParticle] {
    guard size.width > 0, size.height > 0 else { return [] }

    let globalDrift = sin(time * 0.32) * 18
    return (0..<64).map { index in
        let sizeSeed = browserAnimationNoise(index, salt: 2.11)
        let phase = browserAnimationNoise(index, salt: 2.29)
        let xSeed = browserAnimationNoise(index, salt: 2.47)
        let driftSeed = browserAnimationNoise(index, salt: 2.61)
        let diameter = CGFloat(2 + sizeSeed * 5)
        let fallSpeed = 0.045 + sizeSeed * 0.07
        let yProgress = CGFloat((time * fallSpeed + phase).truncatingRemainder(dividingBy: 1))
        let y = -diameter + yProgress * (size.height + diameter * 2)
        let localDrift = sin(time * (0.8 + driftSeed * 1.6) + phase * .pi * 2) * CGFloat(8 + driftSeed * 18)
        let gust = sin(time * 0.55 + Double(index) * 0.33) * CGFloat(6 + driftSeed * 10)
        let x = CGFloat(xSeed) * size.width + CGFloat(globalDrift) + localDrift + gust
        let opacity = 0.12 + sizeSeed * 0.18
        return BrowserSnowParticle(
            rect: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter),
            opacity: opacity
        )
    }
}

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    var browserTopInset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                BrowserLayerSurfaceView(viewModel: viewModel, browserTopInset: browserTopInset)

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
    let browserTopInset: CGFloat
    @FocusState private var browserFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = proxy.size
            let _ = viewModel.browserChromeRevision
            ZStack {
                BrowserCanvasBackgroundView(
                    viewModel: viewModel,
                    colorScheme: colorScheme,
                    browserTopInset: browserTopInset,
                    canvasSize: canvasSize
                )
                BrowserSurfaceRepresentable(viewModel: viewModel, canvasSize: canvasSize)

                if viewModel.settings.browserTickerVisible {
                    BrowserTickerOverlayView(viewModel: viewModel, canvasSize: canvasSize)
                }

                if viewModel.settings.browserCursorAnimation {
                    BrowserCursorPulseOverlay(viewModel: viewModel, canvasSize: canvasSize, colorScheme: colorScheme)
                }

                if viewModel.browserShowsInlineEditorOverlay {
                    let editingCard = viewModel.browserInlineEditorCard
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
                        canvasSize: canvasSize
                    )
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
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

private struct BrowserTickerOverlayView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let canvasSize: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let cards = viewModel.visibleCardsBackToFront()
            Canvas { context, _ in
                for (index, card) in cards.enumerated() {
                    guard let tickerText = viewModel.browserCardTickerText(for: card),
                          !tickerText.isEmpty else { continue }

                    let font = viewModel.browserCardTickerNSFont(for: card)
                    let tickerHeight = viewModel.browserCardTickerHeight(for: card)
                    let cardRect = viewModel.cardFrame(for: card, in: canvasSize)
                    let padding = browserCardContentPadding(for: card)
                    let stripW = max(cardRect.width - 2 * padding, 0)
                    guard stripW > 0 else { continue }

                    let stripRect = CGRect(
                        x: cardRect.minX + padding,
                        y: cardRect.maxY - padding - tickerHeight,
                        width: stripW,
                        height: tickerHeight
                    )

                    let occludingRects = cards.suffix(from: index + 1).map {
                        viewModel.cardFrame(for: $0, in: canvasSize)
                    }
                    let visibleRects = browserTickerVisibleRects(in: stripRect, occludingRects: occludingRects)
                    guard !visibleRects.isEmpty else { continue }

                    let nsAttrs: [NSAttributedString.Key: Any] = [.font: font]
                    let textWidth = ceil(NSAttributedString(string: tickerText, attributes: nsAttrs).size().width)
                    let travelDistance = max(textWidth + stripW, 1)
                    let speed = max(Double(font.pointSize) * 3.0, 40)
                    let phase = (now * speed).truncatingRemainder(dividingBy: travelDistance)
                    let xPos = stripRect.minX + stripW - CGFloat(phase)

                    let resolved = context.resolve(
                        Text(tickerText).font(Font(font)).foregroundStyle(Color.black)
                    )
                    for visibleRect in visibleRects {
                        context.drawLayer { ctx in
                            ctx.clip(to: Path(visibleRect))
                            ctx.draw(resolved, at: CGPoint(x: xPos, y: stripRect.midY), anchor: .leading)
                        }
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .allowsHitTesting(false)
    }
}

private struct BrowserCanvasBackgroundView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let colorScheme: ColorScheme
    let browserTopInset: CGFloat
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: browserCanvasBackgroundColor(for: colorScheme)))

            if let detailCard = viewModel.browserCardTextCard,
               viewModel.browserShowsCardTextOverlay {
                let titleFont = Font(viewModel.browserOverlayTitleNSFont())
                let bodyFont = Font(viewModel.browserOverlayBodyNSFont())
                let textAlignment = viewModel.browserCardTextOverlayTextAlignment()
                let overlayMaxWidth = viewModel.browserCardTextOverlayMaxWidth(in: canvasSize)
                let bodyText = viewModel.settings.browserTextWordWrap
                    ? detailCard.bodyText
                    : detailCard.bodyText.replacingOccurrences(of: "\n", with: " ")
                VStack(alignment: .leading) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(detailCard.title)
                                .font(titleFont)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(textAlignment)
                                .frame(maxWidth: .infinity, alignment: viewModel.settings.browserTextCentering ? .center : .leading)
                            if !detailCard.bodyText.isEmpty {
                                Text(bodyText)
                                    .font(bodyFont)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(textAlignment)
                                    .lineLimit(viewModel.settings.browserTextWordWrap ? nil : 1)
                                    .fixedSize(horizontal: !viewModel.settings.browserTextWordWrap, vertical: viewModel.settings.browserTextWordWrap)
                                    .frame(maxWidth: .infinity, alignment: viewModel.settings.browserTextCentering ? .center : .leading)
                            }
                        }
                        .frame(maxWidth: overlayMaxWidth, alignment: viewModel.settings.browserTextCentering ? .center : .leading)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, viewModel.settings.browserTextCentering ? 0 : browserTopInset + 16)
                .padding(.leading, viewModel.settings.browserTextCentering ? 0 : 16)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: viewModel.browserCardTextOverlayFrameAlignment()
                )
                .allowsHitTesting(false)
            }

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
                    GeometryReader { proxy in
                        Canvas { context, size in
                            let drawRect = browserWallpaperRect(
                                for: image.size,
                                in: size,
                                fixed: viewModel.settings.browserWallpaperFixed
                            )
                            guard drawRect.width > 0, drawRect.height > 0 else { return }
                            context.draw(Image(nsImage: image), in: drawRect)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
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
        let baseColor = browserLinkStrokeColor(for: colorScheme, highlighted: false)
        for particle in browserFlowingLineParticles(in: size, time: time) {
            var path = Path()
            path.move(to: particle.start)
            path.addLine(to: particle.end)
            context.stroke(
                path,
                with: .color(Color(nsColor: baseColor).opacity(particle.opacity)),
                lineWidth: particle.lineWidth
            )
        }
    }

    private func drawBubbles(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let baseColor = Color(nsColor: browserLinkStrokeColor(for: colorScheme, highlighted: false))
        for particle in browserBubbleParticles(in: size, time: time) {
            let path = Path(ellipseIn: particle.rect)
            context.fill(path, with: .color(baseColor.opacity(particle.opacity * 0.35)))
            context.stroke(path, with: .color(baseColor.opacity(particle.opacity)), lineWidth: particle.lineWidth)
        }
    }

    private func drawSnow(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let fillColor = Color.white.opacity(colorScheme == .dark ? 0.24 : 0.18)
        let strokeColor = Color.white.opacity(colorScheme == .dark ? 0.34 : 0.24)
        for particle in browserSnowParticles(in: size, time: time) {
            let path = Path(ellipseIn: particle.rect)
            context.fill(path, with: .color(fillColor.opacity(particle.opacity / 0.24)))
            context.stroke(path, with: .color(strokeColor.opacity(particle.opacity / 0.24)), lineWidth: 0.8)
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
    let card: FrieveCard?
    let canvasSize: CGSize

    var body: some View {
        let editorFrame = viewModel.browserInlineEditorFrame(for: card, in: canvasSize)
        let hasSelection = card != nil

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
                .disabled(!hasSelection)
                if !viewModel.settings.browserEditInBrowserAlways {
                    Button {
                        viewModel.dismissBrowserInlineEditor()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }

            TextField("Card title", text: viewModel.bindingForSelectedTitle())
                .textFieldStyle(.roundedBorder)
                .disabled(!hasSelection)

            ZStack(alignment: .topLeading) {
                TextEditor(text: viewModel.bindingForSelectedBody())
                    .font(.body)
                    .disabled(!hasSelection)
                if !hasSelection {
                    Text("No card selected")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                }
            }
            .frame(minHeight: 120)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))

            HStack {
                Button("Web Search") { viewModel.searchWebForSelection() }
                    .disabled(!hasSelection)
                Button("Read") { viewModel.readSelectedCardAloud() }
                    .disabled(!hasSelection)
                Spacer()
                Text(card?.updated ?? "No selection")
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
            }
            Text(viewModel.browserPerformanceHUDSummary)
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
