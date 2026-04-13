import SwiftUI
import AppKit

extension WorkspaceViewModel {
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
        guard let imageURL = mediaURL(for: card.imagePath) else { return nil }
        let cacheKey = imageURL.path
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
                guard let thumbnail = Self.loadThumbnail(for: imageURL, maxPixelSize: 256) else {
                    await MainActor.run {
                        guard let self else { return }
                        self.mediaThumbnailTasks.remove(cacheKey)
                        self.missingMediaCacheKeys.insert(cacheKey)
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

    func browserCardRasterCacheKey(for snapshot: BrowserCardLayerSnapshot) -> String {
        [
            String(snapshot.card.id),
            String(snapshot.detailLevel.rawValue),
            snapshot.card.updated,
            snapshot.card.title,
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
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : card.title
        let image = NSImage(size: canvasSize)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        CGRect(origin: .zero, size: canvasSize).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: browserCardTitleNSFont(for: card),
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 0.96),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let padding = browserCardContentPadding(for: card)
        let rect = CGRect(
            x: padding,
            y: padding,
            width: max(canvasSize.width - padding * 2, 1),
            height: max(canvasSize.height - padding * 2, 1)
        )
        attributed.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        )
        return image
    }

    func browserInlineEditorFrame(for card: FrieveCard, in size: CGSize) -> CGRect {
        let cardFrame = self.cardFrame(for: card, in: size)
        let width: CGFloat = 360
        let height: CGFloat = 230
        let desiredX = min(max(cardFrame.midX, width / 2 + 18), size.width - width / 2 - 18)
        let desiredY = min(max(cardFrame.maxY + height / 2 + 12, height / 2 + 18), size.height - height / 2 - 18)
        return CGRect(
            x: desiredX - width / 2,
            y: desiredY - height / 2,
            width: width,
            height: height
        )
    }

    func inlineEditorConnectorPoints(for card: FrieveCard, in size: CGSize) -> (CGPoint, CGPoint)? {
        let cardFrame = cardFrame(for: card, in: size)
        let editorFrame = browserInlineEditorFrame(for: card, in: size)
        let start = CGPoint(x: cardFrame.midX, y: cardFrame.maxY)
        let end = CGPoint(x: editorFrame.midX, y: editorFrame.minY)
        return (start, end)
    }

    func color(for card: FrieveCard) -> Color {
        if let labelColor = metadata(for: card).primaryLabelColor {
            return browserCardFillColor(from: Color(frieveRGB: labelColor))
        }
        // No label: neutral white-based color matching Windows no-label style
        return browserCardFillColor(from: Color(white: 0.55))
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

private func browserCardFillColor(from accent: Color) -> Color {
    let accentRGB = (NSColor(accent).usingColorSpace(.deviceRGB) ?? NSColor(accent))
    let referenceBackground = NSColor(
        calibratedRed: 0.96,
        green: 0.96,
        blue: 0.95,
        alpha: 1
    )
    let outlineLikeColor = accentRGB.blended(withFraction: 0.33, of: referenceBackground) ?? accentRGB
    let fillColor = outlineLikeColor.blended(withFraction: 0.5, of: referenceBackground) ?? outlineLikeColor
    return Color(nsColor: fillColor)
}
