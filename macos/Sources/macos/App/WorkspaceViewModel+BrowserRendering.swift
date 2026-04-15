import SwiftUI
import AppKit

extension WorkspaceViewModel {
    private func cachedPreviewImage(for path: String?) -> NSImage? {
        guard let mediaURL = mediaURL(for: path) else { return nil }
        let cacheKey = mediaURL.path
        if let image = mediaImageCache[cacheKey] {
            touchMediaImageCacheKey(cacheKey)
            return image
        }
        if missingMediaCacheKeys.contains(cacheKey) {
            return nil
        }
        if !mediaThumbnailTasks.contains(cacheKey) {
            mediaThumbnailTasks.insert(cacheKey)
            Task.detached(priority: .utility) { [weak self] in
                guard let thumbnail = Self.loadThumbnail(for: mediaURL, maxPixelSize: 256) else {
                    await MainActor.run {
                        guard let self else { return }
                        self.mediaThumbnailTasks.remove(cacheKey)
                        self.missingMediaCacheKeys.insert(cacheKey)
                        self.markBrowserSurfaceContentDirty()
                        self.markBrowserSurfacePresentationDirty()
                    }
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    self.mediaThumbnailTasks.remove(cacheKey)
                    self.cacheMediaImage(thumbnail, forKey: cacheKey)
                    self.markBrowserSurfaceContentDirty()
                    self.markBrowserSurfacePresentationDirty()
                }
            }
        }
        return nil
    }

    func drawingPreviewItems(for card: FrieveCard) -> [DrawingPreviewItem] {
        if let cached = drawingPreviewCache[card.id], cached.encoded == card.drawingEncoded {
            return cached.items
        }
        let items = card.drawingPreviewItems()
        drawingPreviewCache[card.id] = (encoded: card.drawingEncoded, items: items)
        return items
    }

    func drawingPreviewBounds(for card: FrieveCard) -> CGRect {
        if let cached = drawingPreviewBoundsCache[card.id], cached.encoded == card.drawingEncoded {
            return cached.bounds
        }
        let bounds = drawingPreviewBounds(for: drawingPreviewItems(for: card))
        drawingPreviewBoundsCache[card.id] = (encoded: card.drawingEncoded, bounds: bounds)
        return bounds
    }

    func cachedDrawingPreviewImage(for card: FrieveCard, targetSize: CGSize) -> NSImage? {
        let width = max(Int(targetSize.width.rounded()), 1)
        let height = max(Int(targetSize.height.rounded()), 1)
        let cacheKey = "\(card.id):\(width)x\(height):\(card.drawingEncoded.hashValue)"
        if let cached = drawingPreviewImageCache[cacheKey] {
            touchDrawingPreviewCacheKey(cacheKey)
            return cached
        }
        let items = drawingPreviewItems(for: card)
        guard !items.isEmpty else { return nil }
        guard let image = renderDrawingPreviewImage(
            items: items,
            sourceBounds: drawingPreviewBounds(for: card),
            targetSize: CGSize(width: width, height: height),
            colorProvider: { rawValue, fallback in
                self.drawingColor(rawValue: rawValue, fallback: fallback)
            }
        ) else {
            return nil
        }
        cacheDrawingPreviewImage(image, forKey: cacheKey)
        return image
    }

    func cardHasDrawingPreview(_ card: FrieveCard) -> Bool {
        metadata(for: card).hasDrawingPreview
    }

    func browserDetailSummary(for card: FrieveCard) -> String {
        metadata(for: card).detailSummary
    }

    func browserCardLinkCount(for card: FrieveCard) -> Int {
        metadata(for: card).linkCount
    }

    func browserCardLabelLine(for card: FrieveCard) -> String {
        metadata(for: card).labelLine
    }

    func browserCardSummaryText(for card: FrieveCard) -> String {
        metadata(for: card).summaryText
    }

    func browserCardMediaBadgeText(for card: FrieveCard) -> String {
        metadata(for: card).mediaBadgeText
    }

    func cachedPreviewImage(for card: FrieveCard) -> NSImage? {
        cachedPreviewImage(for: card.imagePath)
    }

    func cachedVideoPreviewImage(for card: FrieveCard) -> NSImage? {
        cachedPreviewImage(for: card.videoPath)
    }

    func browserMediaPreviewCacheToken(for path: String?) -> String {
        guard let mediaURL = mediaURL(for: path) else { return "none" }
        let cacheKey = mediaURL.path
        if mediaImageCache[cacheKey] != nil {
            return "ready"
        }
        if missingMediaCacheKeys.contains(cacheKey) {
            return "missing"
        }
        return "loading"
    }

    func browserCardRasterCacheKey(for snapshot: BrowserCardLayerSnapshot) -> String {
        [
            String(snapshot.card.id),
            snapshot.card.title,
            snapshot.metadata.scoreText ?? "",
            snapshot.metadata.badges.joined(separator: "|"),
            snapshot.card.drawingEncoded,
            snapshot.card.imagePath ?? "",
            snapshot.card.videoPath ?? "",
            browserMediaPreviewCacheToken(for: snapshot.card.imagePath),
            browserMediaPreviewCacheToken(for: snapshot.card.videoPath),
            snapshot.metadata.mediaBadgeText,
            snapshot.metadata.hasDrawingPreview ? "1" : "0",
            browserCardScoreBarCacheKey(for: snapshot.card),
            "\(browserDisplaySettingsSignature)",
            "\(Int(snapshot.metadata.canvasSize.width.rounded()))x\(Int(snapshot.metadata.canvasSize.height.rounded()))"
        ].joined(separator: "::")
    }

    func browserCardRasterKey(for snapshot: BrowserCardLayerSnapshot) -> String {
        browserCardRasterCacheKey(for: snapshot)
    }

    func cachedBrowserCardRaster(for snapshot: BrowserCardLayerSnapshot) -> NSImage? {
        cachedBrowserCardRaster(for: snapshot, cacheKey: browserCardRasterKey(for: snapshot))
    }

    func cachedBrowserCardRaster(for snapshot: BrowserCardLayerSnapshot, cacheKey: String) -> NSImage? {
        if let cached = browserCardRasterCache[cacheKey] {
            touchBrowserCardRasterCacheKey(cacheKey)
            return cached
        }

        let rasterStart = CACurrentMediaTime()
        guard let image = rasterizeBrowserCardTitle(for: snapshot.card, canvasSize: snapshot.metadata.canvasSize) else {
            return nil
        }
        recordBrowserCardRasterMetric((CACurrentMediaTime() - rasterStart) * 1000)
        browserCardRasterCache[cacheKey] = image
        touchBrowserCardRasterCacheKey(cacheKey)
        evictCacheIfNeeded(order: &browserCardRasterCacheOrder, storage: &browserCardRasterCache, maxEntries: 360)
        return image
    }

    func browserCardRasterIfReady(for snapshot: BrowserCardLayerSnapshot, cacheKey: String) -> NSImage? {
        if let cached = browserCardRasterCache[cacheKey] {
            touchBrowserCardRasterCacheKey(cacheKey)
            return cached
        }
        if !browserInteractionModeEnabled {
            return cachedBrowserCardRaster(for: snapshot, cacheKey: cacheKey)
        }
        enqueueBrowserCardRaster(for: snapshot, cacheKey: cacheKey)
        return nil
    }

    private func rasterizeBrowserCardTitle(for card: FrieveCard, canvasSize: CGSize) -> NSImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let metadata = cardMetadataByID[card.id] ?? metadata(for: card)
        let renderer = ImageRenderer(
            content: BrowserCardRasterContentView(
                viewModel: self,
                card: card,
                metadata: metadata,
                detailLevel: browserCardDetailLevel(),
                fillColor: Color.clear,
                previewImage: cachedPreviewImage(for: card),
                videoPreviewImage: cachedVideoPreviewImage(for: card),
                drawingPreviewImage: cachedDrawingPreviewImage(for: card, targetSize: browserDrawingPreviewSize(for: card))
            )
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.isOpaque = false
        return renderer.nsImage
    }

    func browserInlineEditorFrame(for card: FrieveCard?, in size: CGSize, topInset: CGFloat = 0) -> CGRect {
        let position = BrowserInlineEditorPosition(rawValue: settings.browserEditInBrowserPosition) ?? .underCard
        let outerPadding: CGFloat = 16
        let width: CGFloat = position == .browserRight ? min(max(size.width * 0.34, 320), 460) : 360
        let height: CGFloat = position == .browserBottom ? min(max(size.height * 0.28, 220), 320) : 230

        switch position {
        case .underCard:
            if let card {
                let cardFrame = self.cardFrame(for: card, in: size)
                let desiredX = min(max(cardFrame.midX, width / 2 + 18), size.width - width / 2 - 18)
                let desiredY = min(max(cardFrame.maxY + height / 2 + 18, height / 2 + 18), size.height - height / 2 - 18)
                return CGRect(
                    x: desiredX - width / 2,
                    y: desiredY - height / 2,
                    width: width,
                    height: height
                )
            }
            return CGRect(
                x: (size.width - width) / 2,
                y: max(size.height - height - 24, 24),
                width: width,
                height: height
            )
        case .browserRight:
            let topMargin = min(max(topInset + outerPadding, 0), size.height)
            return CGRect(
                x: max(size.width - width - outerPadding, outerPadding),
                y: topMargin,
                width: width,
                height: max(size.height - topMargin - outerPadding, 0)
            )
        case .browserBottom:
            let availableWidth = max(size.width - outerPadding * 2, 0)
            return CGRect(
                x: outerPadding,
                y: max(size.height - height - outerPadding, topInset + outerPadding),
                width: availableWidth,
                height: height
            )
        }
    }

    func inlineEditorConnectorPoints(for card: FrieveCard?, in size: CGSize) -> (CGPoint, CGPoint)? {
        guard (BrowserInlineEditorPosition(rawValue: settings.browserEditInBrowserPosition) ?? .underCard) == .underCard,
              let card else { return nil }
        let cardFrame = cardFrame(for: card, in: size)
        let editorFrame = browserInlineEditorFrame(for: card, in: size)
        let start = CGPoint(x: cardFrame.midX, y: cardFrame.maxY)
        let end = CGPoint(x: editorFrame.midX, y: editorFrame.minY)
        return (start, end)
    }

    func browserFillColor(for card: FrieveCard) -> NSColor {
        if let labelColor = metadata(for: card).primaryLabelColor {
            return browserCardFillColor(from: Color(frieveRGB: labelColor), gradation: settings.browserCardGradation)
        }
        return browserCardFillColor(from: Color(white: 0.55), gradation: settings.browserCardGradation)
    }

    func drawingColor(rawValue: Int?, fallback: Color) -> Color {
        guard let rawValue else { return fallback }
        return Color(frieveRGB: rawValue)
    }

    func mediaURL(for path: String?) -> URL? {
        guard let path, !path.trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        if url.isFileURL, path.hasPrefix("/") {
            return url
        }
        if let sourcePath = document.sourcePath {
            return URL(fileURLWithPath: sourcePath)
                .deletingLastPathComponent()
                .appendingPathComponent(path)
        }
        return url
    }
}

extension Color {
    init(frieveRGB value: Int) {
        let red = Double(value & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double((value >> 16) & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    var frieveRGBValue: Int {
        let color = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return red | (green << 8) | (blue << 16)
    }
}

func blendFrieveColor(_ lhs: Int, with rhs: Int, fraction: CGFloat) -> Int {
    let weight = max(0, min(fraction, 1))
    let inverse = 1 - weight

    let lhsRed = CGFloat(lhs & 0xFF)
    let lhsGreen = CGFloat((lhs >> 8) & 0xFF)
    let lhsBlue = CGFloat((lhs >> 16) & 0xFF)
    let rhsRed = CGFloat(rhs & 0xFF)
    let rhsGreen = CGFloat((rhs >> 8) & 0xFF)
    let rhsBlue = CGFloat((rhs >> 16) & 0xFF)

    let red = Int((lhsRed * inverse + rhsRed * weight).rounded())
    let green = Int((lhsGreen * inverse + rhsGreen * weight).rounded())
    let blue = Int((lhsBlue * inverse + rhsBlue * weight).rounded())
    return red | (green << 8) | (blue << 16)
}

private func browserCardFillColor(from accent: Color, gradation: Bool) -> NSColor {
    let accentRGB = (NSColor(accent).usingColorSpace(.deviceRGB) ?? NSColor(accent))
    let referenceBackground = NSColor(
        calibratedRed: 0.96,
        green: 0.96,
        blue: 0.95,
        alpha: 1
    )
    let outlineBlend: CGFloat = 0.33
    let fillBlend: CGFloat = gradation ? 0.5 : 0.66
    let outlineLikeColor = accentRGB.blended(withFraction: outlineBlend, of: referenceBackground) ?? accentRGB
    let fillColor = outlineLikeColor.blended(withFraction: fillBlend, of: referenceBackground) ?? outlineLikeColor
    return fillColor
}
