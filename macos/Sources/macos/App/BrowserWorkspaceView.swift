import SwiftUI
import AppKit

struct BrowserHUDAvoidanceInsets: Equatable {
    let bottom: CGFloat
    let trailing: CGFloat
}

func browserWallpaperViewportRect(in canvasSize: CGSize, topInset: CGFloat) -> CGRect {
    CGRect(x: 0, y: min(max(topInset, 0), canvasSize.height), width: canvasSize.width, height: max(canvasSize.height - topInset, 0))
}

func browserWallpaperRect(for imageSize: CGSize, in viewportRect: CGRect, fixed: Bool) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, viewportRect.width > 0, viewportRect.height > 0 else { return .zero }
    let widthRatio = viewportRect.width / imageSize.width
    let heightRatio = viewportRect.height / imageSize.height
    let scale = fixed ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
    let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: viewportRect.midX - drawSize.width / 2,
        y: viewportRect.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    )
}

func browserScrollableWallpaperRect(for imageSize: CGSize, anchor: CGPoint, zoom: Double) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let clampedZoom = max(zoom, 0.001)
    let drawSize = CGSize(width: imageSize.width * clampedZoom, height: imageSize.height * clampedZoom)
    return CGRect(
        x: anchor.x - drawSize.width / 2,
        y: anchor.y - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    )
}

func browserWallpaperTileSize(for imageSize: CGSize, fixed: Bool, zoom: Double) -> CGSize {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let clampedZoom = max(zoom, 0.001)
    if fixed {
        return imageSize
    }
    return CGSize(width: imageSize.width * clampedZoom, height: imageSize.height * clampedZoom)
}

func browserWallpaperTileOrigin(anchor: CGPoint, tileSize: CGSize, in viewportRect: CGRect) -> CGPoint {
    guard tileSize.width > 0, tileSize.height > 0 else { return viewportRect.origin }

    func wrappedStart(minEdge: CGFloat, anchor: CGFloat, step: CGFloat) -> CGFloat {
        let offset = (anchor - minEdge).truncatingRemainder(dividingBy: step)
        let positiveOffset = offset >= 0 ? offset : offset + step
        return minEdge + positiveOffset - step
    }

    return CGPoint(
        x: wrappedStart(minEdge: viewportRect.minX, anchor: anchor.x, step: tileSize.width),
        y: wrappedStart(minEdge: viewportRect.minY, anchor: anchor.y, step: tileSize.height)
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

func browserHUDAvoidanceInsets(
    placement: BrowserInlineEditorPosition,
    editorFrame: CGRect,
    canvasSize: CGSize,
    isEditorVisible: Bool
) -> BrowserHUDAvoidanceInsets {
    guard isEditorVisible else {
        return BrowserHUDAvoidanceInsets(bottom: 0, trailing: 0)
    }

    switch placement {
    case .browserRight:
        return BrowserHUDAvoidanceInsets(
            bottom: 0,
            trailing: max(canvasSize.width - editorFrame.minX, 0)
        )
    case .browserBottom:
        return BrowserHUDAvoidanceInsets(
            bottom: max(canvasSize.height - editorFrame.minY, 0),
            trailing: 0
        )
    case .underCard:
        return BrowserHUDAvoidanceInsets(bottom: 0, trailing: 0)
    }
}

func browserHidesViewportSummary(
    placement: BrowserInlineEditorPosition,
    isEditorVisible: Bool
) -> Bool {
    isEditorVisible && (placement == .browserRight || placement == .browserBottom)
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

struct BrowserPetalParticle: Hashable {
    let center: CGPoint
    let size: CGSize
    let rotation: Angle
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

func browserPetalParticles(in size: CGSize, time: TimeInterval) -> [BrowserPetalParticle] {
    guard size.width > 0, size.height > 0 else { return [] }

    let globalDrift = sin(time * 0.19) * 18 + sin(time * 0.07) * 26
    return (0..<30).map { index in
        let sizeSeed = browserAnimationNoise(index, salt: 3.13)
        let driftSeed = browserAnimationNoise(index, salt: 3.29)
        let phase = browserAnimationNoise(index, salt: 3.47)
        let xSeed = browserAnimationNoise(index, salt: 3.61)
        let gustSeed = browserAnimationNoise(index, salt: 3.79)
        let width = CGFloat(12 + sizeSeed * 10)
        let height = width * CGFloat(0.62 + driftSeed * 0.18)
        let fallSpeed = 0.028 + sizeSeed * 0.05
        let yProgress = CGFloat((time * fallSpeed + phase).truncatingRemainder(dividingBy: 1))
        let y = -height + yProgress * (size.height + height * 2)
        let sway = sin(time * (0.55 + driftSeed) + phase * .pi * 2) * CGFloat(20 + driftSeed * 28)
        let flutter = sin(time * (1.4 + driftSeed * 1.2) + Double(index) * 0.9) * CGFloat(6 + driftSeed * 10)
        let gust = sin(time * (0.24 + gustSeed * 0.6) + phase * .pi * 4) * CGFloat(14 + gustSeed * 34)
        let x = CGFloat(xSeed) * size.width + CGFloat(globalDrift) + sway + flutter + gust
        let rotation = Angle.radians(phase * .pi * 2 + time * (0.35 + driftSeed * 0.9))
        let opacity = 0.14 + sizeSeed * 0.08
        return BrowserPetalParticle(
            center: CGPoint(x: x, y: y),
            size: CGSize(width: width, height: height),
            rotation: rotation,
            opacity: opacity
        )
    }
}

struct BrowserWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    var browserTopInset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let hudAvoidance = currentBrowserHUDAvoidanceInsets(in: geometry.size)
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
                .padding(.top, 16)
                .padding(.leading, 16)
                .padding(.bottom, 16 + hudAvoidance.bottom)
                .padding(.trailing, 16 + hudAvoidance.trailing)
            }
        }
    }

    private func currentBrowserHUDAvoidanceInsets(in canvasSize: CGSize) -> BrowserHUDAvoidanceInsets {
        let placement = BrowserInlineEditorPosition(rawValue: viewModel.settings.browserEditInBrowserPosition) ?? .underCard
        let editorFrame = viewModel.browserInlineEditorFrame(
            for: viewModel.browserInlineEditorCard,
            in: canvasSize,
            topInset: browserTopInset
        )
        return browserHUDAvoidanceInsets(
            placement: placement,
            editorFrame: editorFrame,
            canvasSize: canvasSize,
            isEditorVisible: viewModel.browserShowsInlineEditorOverlay
        )
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
            let inlineEditorPlacement = BrowserInlineEditorPosition(rawValue: viewModel.settings.browserEditInBrowserPosition) ?? .underCard
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
                        canvasSize: canvasSize,
                        browserTopInset: browserTopInset
                    )
                }

                if !browserHidesViewportSummary(
                    placement: inlineEditorPlacement,
                    isEditorVisible: viewModel.browserShowsInlineEditorOverlay
                ) {
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
                let isCentered = viewModel.settings.browserTextCentering

                Group {
                    if let overlayMaxWidth {
                        VStack(alignment: isCentered ? .center : .leading, spacing: 3) {
                            Text(detailCard.title)
                                .font(titleFont)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(textAlignment)
                                .frame(width: overlayMaxWidth, alignment: isCentered ? .center : .leading)
                            if !detailCard.bodyText.isEmpty {
                                Text(detailCard.bodyText)
                                    .font(bodyFont)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(textAlignment)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: overlayMaxWidth, alignment: isCentered ? .center : .leading)
                            }
                        }
                    } else {
                        VStack(alignment: isCentered ? .center : .leading, spacing: 3) {
                            Text(detailCard.title)
                                .font(titleFont)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(textAlignment)
                            if !detailCard.bodyText.isEmpty {
                                Text(detailCard.bodyText)
                                    .font(bodyFont)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(textAlignment)
                                    .fixedSize(horizontal: true, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isCentered ? 0 : browserTopInset + 16)
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: viewModel.browserCardTextOverlayFrameAlignment())
                .clipped()
                .allowsHitTesting(false)
            }

            if let image = wallpaperImage {
                let viewportRect = browserWallpaperViewportRect(in: canvasSize, topInset: browserTopInset)
                if viewModel.settings.browserWallpaperTiled {
                    GeometryReader { proxy in
                        Canvas { context, size in
                            let tileSize = browserWallpaperTileSize(
                                for: image.size,
                                fixed: viewModel.settings.browserWallpaperFixed,
                                zoom: viewModel.zoom
                            )
                            guard tileSize.width > 0, tileSize.height > 0 else { return }
                            let anchor = if viewModel.settings.browserWallpaperFixed {
                                viewportRect.origin
                            } else {
                                browserScrollableWallpaperRect(
                                    for: image.size,
                                    anchor: viewModel.canvasPoint(for: FrievePoint(x: 0, y: 0), in: size),
                                    zoom: viewModel.zoom
                                ).origin
                            }
                            let startOrigin = browserWallpaperTileOrigin(anchor: anchor, tileSize: tileSize, in: viewportRect)
                            let columns = Int(ceil((viewportRect.maxX - startOrigin.x) / tileSize.width)) + 1
                            let rows = Int(ceil((viewportRect.maxY - startOrigin.y) / tileSize.height)) + 1
                            context.clip(to: Path(viewportRect))
                            for row in 0..<rows {
                                for column in 0..<columns {
                                    let origin = CGPoint(
                                        x: startOrigin.x + CGFloat(column) * tileSize.width,
                                        y: startOrigin.y + CGFloat(row) * tileSize.height
                                    )
                                    context.draw(
                                        Image(nsImage: image),
                                        in: CGRect(origin: origin, size: tileSize)
                                    )
                                }
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    GeometryReader { proxy in
                        Canvas { context, size in
                            let drawRect = if viewModel.settings.browserWallpaperFixed {
                                browserWallpaperRect(for: image.size, in: viewportRect, fixed: true)
                            } else {
                                browserScrollableWallpaperRect(
                                    for: image.size,
                                    anchor: viewModel.canvasPoint(for: FrievePoint(x: 0, y: 0), in: size),
                                    zoom: viewModel.zoom
                                )
                            }
                            guard drawRect.width > 0, drawRect.height > 0 else { return }
                            context.clip(to: Path(viewportRect))
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
        let petalColor = Color(nsColor: NSColor(red: 0.90, green: 0.72, blue: 0.92, alpha: 1))
        for particle in browserPetalParticles(in: size, time: time) {
            context.drawLayer { layer in
                layer.translateBy(x: particle.center.x, y: particle.center.y)
                layer.rotate(by: particle.rotation)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: particle.size.height / 2))
                path.addQuadCurve(
                    to: CGPoint(x: particle.size.width / 2, y: 0),
                    control: CGPoint(x: particle.size.width * 0.45, y: particle.size.height * 0.45)
                )
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: -particle.size.height / 2),
                    control: CGPoint(x: particle.size.width * 0.35, y: -particle.size.height * 0.35)
                )
                path.addQuadCurve(
                    to: CGPoint(x: -particle.size.width / 2, y: 0),
                    control: CGPoint(x: -particle.size.width * 0.35, y: -particle.size.height * 0.35)
                )
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: particle.size.height / 2),
                    control: CGPoint(x: -particle.size.width * 0.45, y: particle.size.height * 0.45)
                )
                layer.fill(path, with: .color(petalColor.opacity(particle.opacity)))
            }
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
    let browserTopInset: CGFloat

    var body: some View {
        let editorFrame = viewModel.browserInlineEditorFrame(for: card, in: canvasSize, topInset: browserTopInset)
        let hasSelection = card != nil

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inline Editor")
                    .font(.headline)
                Spacer()
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
