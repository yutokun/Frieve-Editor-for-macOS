import SwiftUI
import AppKit

extension WorkspaceViewModel {
    func performAutomaticMaintenance(now: Date = Date()) {
        if settings.autoReloadDefault {
            reloadDocumentFromDiskIfNeeded(now: now)
        }
        if settings.autoSaveDefault {
            autoSaveIfNeeded(now: now)
        }
    }

    func markBrowserPerformanceBaseline() {
        let summary = browserPerformance.summary()
        statusMessage = "Baseline \(summary)"
    }

    func requestBrowserFit() {
        browserViewportRevision += 1
    }

    func markBrowserSurfaceContentDirty() {
        browserSurfaceContentRevision &+= 1
        cachedBrowserSurfaceContentKey = nil
        cachedBrowserSurfaceContent = nil
    }

    func markBrowserSurfacePresentationDirty() {
        browserSurfacePresentationRevision &+= 1
    }

    func markBrowserSurfaceViewportDirty() {
        browserSurfaceViewportRevision &+= 1
    }

    func setBrowserLinkLabelsVisible(_ isVisible: Bool) {
        guard linkLabelsVisible != isVisible else { return }
        linkLabelsVisible = isVisible
        markBrowserSurfaceContentDirty()
        markBrowserSurfacePresentationDirty()
    }

    func resetCanvasToFit(in size: CGSize) {
        let bounds = browserDocumentBounds()
        canvasCenter = FrievePoint(x: bounds.midX, y: bounds.midY)
        let fittedScale = min(
            (size.width * 0.84) / max(bounds.width, 0.0001),
            (size.height * 0.84) / max(bounds.height, 0.0001)
        )
        let minDimension = max(min(size.width, size.height), 1)
        browserBaseScaleFactor = max(Double(fittedScale) / Double(minDimension), 0.05)
        zoom = 1.0
        markBrowserSurfaceViewportDirty()
        clearCanvasTransientState()
    }

    func zoomIn() {
        zoom = min(zoom * 1.15, 6.0)
        markBrowserSurfaceViewportDirty()
    }

    func zoomOut() {
        zoom = max(zoom / 1.15, 0.2)
        markBrowserSurfaceViewportDirty()
    }

    func nudgeSelection(dx: Double, dy: Double) {
        let activeIDs = selectedCardIDs.isEmpty ? Set(selectedCardID.map { [$0] } ?? []) : selectedCardIDs
        guard !activeIDs.isEmpty else { return }
        for id in activeIDs {
            document.moveCard(id, dx: dx, dy: dy)
        }
        noteDocumentMutation(status: activeIDs.count == 1 ? "Moved the selected card" : "Moved \(activeIDs.count) selected cards", updateSearch: false)
    }

    func browserScale(in size: CGSize) -> Double {
        max(Double(min(size.width, size.height)) * browserBaseScaleFactor * zoom, 60)
    }

    func visibleWorldRect(in size: CGSize) -> CGRect {
        let scale = browserScale(in: size)
        let width = Double(size.width) / scale
        let height = Double(size.height) / scale
        return CGRect(
            x: canvasCenter.x - width / 2,
            y: canvasCenter.y - height / 2,
            width: width,
            height: height
        )
    }

    func browserDocumentBounds(padding: Double = 0.18) -> CGRect {
        let snapshot = overviewSnapshot(padding: padding)
        return snapshot.bounds
    }

    func overviewSnapshot(padding: Double = 0.06) -> BrowserOverviewSnapshot {
        let start = CACurrentMediaTime()
        ensureDocumentCaches()
        let key = BrowserOverviewCacheKey(
            documentVersion: documentCacheVersion,
            padding: padding,
            zoom: zoom,
            baseScaleFactor: browserBaseScaleFactor,
            dragTranslation: currentDragTranslation,
            draggedCardIDs: dragOriginByCardID.keys.sorted()
        )
        if let cachedOverviewSnapshot, cachedOverviewSnapshotKey == key {
            recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.overview)
            return cachedOverviewSnapshot
        }
        let cards = visibleSortedCards()
        guard !cards.isEmpty else {
            let empty = BrowserOverviewSnapshot(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), cards: [], links: [])
            cachedOverviewSnapshotKey = key
            cachedOverviewSnapshot = empty
            recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.overview)
            return empty
        }
        let normalizedCanvas = CGSize(width: 1000, height: 1000)
        let normalizedScale = max(browserScale(in: normalizedCanvas), 1)
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for card in cards {
            let position = currentPosition(for: card)
            let cardSize = metadata(for: card).canvasSize
            let halfWidth = Double(cardSize.width) / normalizedScale
            let halfHeight = Double(cardSize.height) / normalizedScale
            minX = min(minX, position.x - halfWidth)
            maxX = max(maxX, position.x + halfWidth)
            minY = min(minY, position.y - halfHeight)
            maxY = max(maxY, position.y + halfHeight)
        }
        let width = max(maxX - minX, 0.35)
        let height = max(maxY - minY, 0.35)
        let bounds = CGRect(
            x: minX - width * padding,
            y: minY - height * padding,
            width: width * (1 + padding * 2),
            height: height * (1 + padding * 2)
        )
        let cardPoints = cards.map { BrowserOverviewSnapshot.CardPoint(cardID: $0.id, point: currentPosition(for: $0)) }
        let linkSegments = document.links.compactMap { link -> BrowserOverviewSnapshot.LinkSegment? in
            guard let from = cardByID(link.fromCardID), let to = cardByID(link.toCardID), from.visible, to.visible else {
                return nil
            }
            return BrowserOverviewSnapshot.LinkSegment(id: link.id, from: currentPosition(for: from), to: currentPosition(for: to))
        }
        let snapshot = BrowserOverviewSnapshot(bounds: bounds, cards: cardPoints, links: linkSegments)
        cachedOverviewSnapshotKey = key
        cachedOverviewSnapshot = snapshot
        recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.overview)
        return snapshot
    }

    func overviewPoint(for card: FrieveCard, in overviewSize: CGSize, snapshot: BrowserOverviewSnapshot? = nil) -> CGPoint {
        overviewPoint(for: card.position, in: overviewSize, snapshot: snapshot)
    }

    func overviewPoint(for point: FrievePoint, in overviewSize: CGSize, snapshot: BrowserOverviewSnapshot? = nil) -> CGPoint {
        let snapshot = snapshot ?? overviewSnapshot()
        let bounds = snapshot.bounds
        let x = ((point.x - bounds.minX) / max(bounds.width, 0.0001)) * overviewSize.width
        let y = ((point.y - bounds.minY) / max(bounds.height, 0.0001)) * overviewSize.height
        return CGPoint(x: x, y: y)
    }

    func overviewViewportRect(overviewSize: CGSize, canvasSize: CGSize, snapshot: BrowserOverviewSnapshot? = nil) -> CGRect {
        let snapshot = snapshot ?? overviewSnapshot()
        let bounds = snapshot.bounds
        let visible = visibleWorldRect(in: canvasSize)
        let minX = ((visible.minX - bounds.minX) / max(bounds.width, 0.0001)) * overviewSize.width
        let maxX = ((visible.maxX - bounds.minX) / max(bounds.width, 0.0001)) * overviewSize.width
        let minY = ((visible.minY - bounds.minY) / max(bounds.height, 0.0001)) * overviewSize.height
        let maxY = ((visible.maxY - bounds.minY) / max(bounds.height, 0.0001)) * overviewSize.height
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func canvasPosition(for card: FrieveCard, in size: CGSize) -> CGPoint {
        canvasPoint(for: card.position, in: size)
    }

    func canvasPoint(for worldPoint: FrievePoint, in size: CGSize) -> CGPoint {
        let scale = browserScale(in: size)
        let x = size.width / 2 + CGFloat((worldPoint.x - canvasCenter.x) * scale)
        let y = size.height / 2 + CGFloat((worldPoint.y - canvasCenter.y) * scale)
        return CGPoint(x: x, y: y)
    }

    func canvasToWorld(_ point: CGPoint, in size: CGSize) -> FrievePoint {
        let scale = browserScale(in: size)
        return FrievePoint(
            x: canvasCenter.x + Double(point.x - size.width / 2) / scale,
            y: canvasCenter.y + Double(point.y - size.height / 2) / scale
        )
    }

    func cardCanvasSize(for card: FrieveCard) -> CGSize {
        metadata(for: card).canvasSize
    }

    func visibleBrowserCards(in size: CGSize, canvasPadding: CGFloat = 220) -> [FrieveCard] {
        let start = CACurrentMediaTime()
        let scale = max(browserScale(in: size), 1)
        let visible = visibleWorldRect(in: size).insetBy(
            dx: -Double(canvasPadding) / scale,
            dy: -Double(canvasPadding) / scale
        )
        let cards = visibleSortedCards().filter { card in
            visible.intersects(cardWorldFrame(for: card, in: size))
        }
        recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.visibleCards)
        return cards
    }

    func browserCanvasScene(in size: CGSize, canvasPadding: CGFloat = 220) -> (cards: [BrowserCardRenderData], links: [BrowserLinkRenderData]) {
        let cards = visibleCardRenderData(in: size, canvasPadding: canvasPadding)
        let visibleCardIDs = Set(cards.map { $0.id })
        let links = visibleLinkRenderData(in: size, visibleCardIDs: visibleCardIDs)
        return (cards, links)
    }

    func browserSurfaceContent(in size: CGSize, canvasPadding: CGFloat = 260) -> BrowserSurfaceContentCacheEntry {
        let detailLevel = browserCardDetailLevel()
        let sceneScale = max(browserScale(in: size), 1)
        let key = BrowserSurfaceContentCacheKey(
            contentRevision: browserSurfaceContentRevision,
            sceneScale: sceneScale,
            detailLevel: detailLevel,
            canvasSize: size,
            canvasPadding: canvasPadding,
            labelsVisible: linkLabelsVisible
        )
        if let cachedBrowserSurfaceContent, cachedBrowserSurfaceContentKey == key {
            let coverage = cachedBrowserSurfaceContent.coverageRect
            let visible = visibleWorldRect(in: size)
            let coverageInsetX = min(coverage.width * 0.18, 0.18)
            let coverageInsetY = min(coverage.height * 0.18, 0.18)
            if coverage.insetBy(dx: coverageInsetX, dy: coverageInsetY).contains(visible) {
                return cachedBrowserSurfaceContent
            }
        }

        let paddedVisible = visibleWorldRect(in: size).insetBy(
            dx: -Double(canvasPadding) / sceneScale,
            dy: -Double(canvasPadding) / sceneScale
        )
        let visibleCards = visibleSortedCards().filter { card in
            paddedVisible.intersects(cardWorldFrame(for: card, in: size))
        }
        let cards = visibleCards.map { card in
            BrowserCardLayerSnapshot(
                card: card,
                position: currentPosition(for: card),
                metadata: metadata(for: card),
                isSelected: selectedCardIDs.contains(card.id),
                isHovered: browserHoverCardID == card.id,
                detailLevel: detailLevel
            )
        }
        let hitRegions = visibleCards.map { BrowserCardHitRegion(cardID: $0.id, frame: cardFrame(for: $0, in: size)) }
        let visibleCardIDs = Set(cards.map { $0.id })
        let links = visibleLinkLayerSnapshots(in: size, visibleCardIDs: visibleCardIDs)
        let entry = BrowserSurfaceContentCacheEntry(
            coverageRect: paddedVisible,
            cards: cards,
            cardSnapshotSignature: browserCardSnapshotSignature(cards),
            links: links,
            linkSnapshotSignature: browserLinkSnapshotSignature(links),
            hitRegions: hitRegions
        )
        cachedBrowserSurfaceContentKey = key
        cachedBrowserSurfaceContent = entry
        return entry
    }

    func browserSurfaceScene(in size: CGSize, canvasPadding: CGFloat = 260) -> BrowserSurfaceSceneSnapshot {
        let start = CACurrentMediaTime()
        let content = browserSurfaceContent(in: size, canvasPadding: canvasPadding)
        let cards = content.cards.map { snapshot in
            BrowserCardLayerSnapshot(
                card: snapshot.card,
                position: snapshot.position,
                metadata: snapshot.metadata,
                isSelected: selectedCardIDs.contains(snapshot.id),
                isHovered: browserHoverCardID == snapshot.id,
                detailLevel: snapshot.detailLevel
            )
        }
        let links = content.links.map { snapshot in
            BrowserLinkLayerSnapshot(
                id: snapshot.id,
                fromCardID: snapshot.fromCardID,
                toCardID: snapshot.toCardID,
                startPoint: snapshot.startPoint,
                endPoint: snapshot.endPoint,
                shapeIndex: snapshot.shapeIndex,
                directionVisible: snapshot.directionVisible,
                labelPoint: snapshot.labelPoint,
                labelText: snapshot.labelText,
                isHighlighted: selectedCardIDs.contains(snapshot.fromCardID) || selectedCardIDs.contains(snapshot.toCardID)
            )
        }
        let overlay = BrowserOverlaySnapshot(
            selectionFrame: selectionFrame(in: size),
            marqueeRect: marqueeRect(),
            linkPreviewSegment: linkPreviewSegment(in: size)
        )
        let scene = BrowserSurfaceSceneSnapshot(
            canvasSize: size,
            worldToCanvasTransform: browserWorldToCanvasTransform(in: size),
            backgroundGuidePath: browserBackgroundGuideCGPath(in: size),
            cards: cards,
            cardSnapshotSignature: browserCardSnapshotSignature(cards),
            links: links,
            linkSnapshotSignature: browserLinkSnapshotSignature(links),
            hitRegions: content.hitRegions,
            overlay: overlay,
            overlaySignature: browserOverlaySignature(overlay),
            viewportSummary: browserViewportSummary(in: size)
        )
        recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.surfaceScene)
        return scene
    }

    func visibleCardRenderData(in size: CGSize, canvasPadding: CGFloat = 220) -> [BrowserCardRenderData] {
        visibleBrowserCards(in: size, canvasPadding: canvasPadding).map { card in
            BrowserCardRenderData(card: card, position: currentPosition(for: card), metadata: metadata(for: card))
        }
    }

    func visibleBrowserLinks(in size: CGSize, visibleCardIDs: Set<Int>) -> [FrieveLink] {
        visibleLinkRenderData(in: size, visibleCardIDs: visibleCardIDs).map(\.link)
    }

    func visibleLinkRenderData(in size: CGSize, visibleCardIDs: Set<Int>) -> [BrowserLinkRenderData] {
        let start = CACurrentMediaTime()
        guard !visibleCardIDs.isEmpty else {
            recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.visibleLinks)
            return []
        }
        let visible = visibleWorldRect(in: size).insetBy(dx: -0.12, dy: -0.12)
        let renders = document.links.compactMap { link -> BrowserLinkRenderData? in
            guard let from = cardByID(link.fromCardID), let to = cardByID(link.toCardID) else { return nil }
            let fromPosition = currentPosition(for: from)
            let toPosition = currentPosition(for: to)
            let shouldInclude: Bool
            if visibleCardIDs.contains(link.fromCardID) || visibleCardIDs.contains(link.toCardID) {
                shouldInclude = true
            } else {
                let segmentBounds = CGRect(
                    x: min(fromPosition.x, toPosition.x),
                    y: min(fromPosition.y, toPosition.y),
                    width: abs(toPosition.x - fromPosition.x),
                    height: abs(toPosition.y - fromPosition.y)
                ).insetBy(dx: -0.05, dy: -0.05)
                shouldInclude = visible.intersects(segmentBounds)
            }
            guard shouldInclude else { return nil }
            let startPoint = canvasPoint(for: fromPosition, in: size)
            let endPoint = canvasPoint(for: toPosition, in: size)
            let path = buildLinkPath(for: link, start: startPoint, end: endPoint)
            let arrowHead = buildLinkArrowHead(for: link, start: startPoint, end: endPoint)
            let labelPoint = buildLinkLabelPoint(for: link, start: startPoint, end: endPoint)
            let isHighlighted = selectedCardIDs.contains(link.fromCardID) || selectedCardIDs.contains(link.toCardID)
            return BrowserLinkRenderData(link: link, start: startPoint, end: endPoint, path: path, arrowHead: arrowHead, labelPoint: labelPoint, isHighlighted: isHighlighted)
        }
        recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.visibleLinks)
        return renders
    }

    func visibleLinkLayerSnapshots(in size: CGSize, visibleCardIDs: Set<Int>) -> [BrowserLinkLayerSnapshot] {
        guard !visibleCardIDs.isEmpty else { return [] }
        let scale = max(browserScale(in: size), 1)
        let detailLevel = browserCardDetailLevel()
        let showsLabels = linkLabelsVisible && detailLevel != .thumbnail
        let visible = visibleWorldRect(in: size).insetBy(dx: -0.12, dy: -0.12)
        return document.links.compactMap { link -> BrowserLinkLayerSnapshot? in
            guard let from = cardByID(link.fromCardID), let to = cardByID(link.toCardID) else { return nil }
            let fromPosition = currentPosition(for: from)
            let toPosition = currentPosition(for: to)
            let shouldInclude: Bool
            if visibleCardIDs.contains(link.fromCardID) || visibleCardIDs.contains(link.toCardID) {
                shouldInclude = true
            } else {
                let segmentBounds = CGRect(
                    x: min(fromPosition.x, toPosition.x),
                    y: min(fromPosition.y, toPosition.y),
                    width: abs(toPosition.x - fromPosition.x),
                    height: abs(toPosition.y - fromPosition.y)
                ).insetBy(dx: -0.05, dy: -0.05)
                shouldInclude = visible.intersects(segmentBounds)
            }
            guard shouldInclude else { return nil }
            let start = CGPoint(x: fromPosition.x, y: fromPosition.y)
            let end = CGPoint(x: toPosition.x, y: toPosition.y)
            return BrowserLinkLayerSnapshot(
                id: link.id,
                fromCardID: link.fromCardID,
                toCardID: link.toCardID,
                startPoint: start,
                endPoint: end,
                shapeIndex: abs(link.shape % 6),
                directionVisible: link.directionVisible,
                labelPoint: buildLinkLabelPoint(for: link, start: start, end: end, baseScale: CGFloat(scale)),
                labelText: showsLabels ? link.name.trimmed.nilIfEmpty : nil,
                isHighlighted: selectedCardIDs.contains(link.fromCardID) || selectedCardIDs.contains(link.toCardID)
            )
        }
    }

    func cardFrame(for card: FrieveCard, in size: CGSize) -> CGRect {
        let center = canvasPoint(for: currentPosition(for: card), in: size)
        let cardSize = cardCanvasSize(for: card)
        return CGRect(
            x: center.x - cardSize.width / 2,
            y: center.y - cardSize.height / 2,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    func selectionFrame(in size: CGSize) -> CGRect? {
        let cards = selectedCards
        guard let first = cards.first else { return nil }
        return cards.dropFirst().reduce(cardFrame(for: first, in: size)) { partial, card in
            partial.union(cardFrame(for: card, in: size))
        }
    }

    func browserCardStrokeColor(for card: FrieveCard, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return .accentColor
        }
        if isHovered {
            return .accentColor.opacity(0.55)
        }
        if let labelColor = metadata(for: card).primaryLabelColor {
            return Color(frieveRGB: labelColor).opacity(0.65)
        }
        return Color.secondary.opacity(0.2)
    }

    func browserCardShadow(for card: FrieveCard, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return .black.opacity(0.18)
        }
        if isHovered || card.hasMedia {
            return .black.opacity(0.12)
        }
        return .black.opacity(0.08)
    }

    func browserCardGlow(for card: FrieveCard, isSelected: Bool) -> Color {
        if isSelected {
            return .accentColor.opacity(0.12)
        }
        if cardHasDrawingPreview(card) {
            return .accentColor.opacity(0.06)
        }
        return .clear
    }

    func browserCardBadgeItems(for card: FrieveCard) -> [String] {
        metadata(for: card).badges
    }

    func browserBackgroundGuidePath(in size: CGSize) -> Path {
        Path(browserBackgroundGuideCGPath(in: size))
    }

    func browserBackgroundGuideCGPath(in size: CGSize) -> CGPath {
        let visible = visibleWorldRect(in: size)
        let path = CGMutablePath()
        let center = canvasPoint(for: canvasCenter, in: size)
        path.move(to: CGPoint(x: center.x, y: 0))
        path.addLine(to: CGPoint(x: center.x, y: size.height))
        path.move(to: CGPoint(x: 0, y: center.y))
        path.addLine(to: CGPoint(x: size.width, y: center.y))

        let majorStep = adaptiveBrowserGridStep(in: size)
        let startX = floor(visible.minX / majorStep) * majorStep
        let endX = ceil(visible.maxX / majorStep) * majorStep
        var x = startX
        while x <= endX {
            let top = canvasPoint(for: FrievePoint(x: x, y: visible.minY), in: size)
            let bottom = canvasPoint(for: FrievePoint(x: x, y: visible.maxY), in: size)
            path.move(to: top)
            path.addLine(to: bottom)
            x += majorStep
        }

        let startY = floor(visible.minY / majorStep) * majorStep
        let endY = ceil(visible.maxY / majorStep) * majorStep
        var y = startY
        while y <= endY {
            let left = canvasPoint(for: FrievePoint(x: visible.minX, y: y), in: size)
            let right = canvasPoint(for: FrievePoint(x: visible.maxX, y: y), in: size)
            path.move(to: left)
            path.addLine(to: right)
            y += majorStep
        }
        return path
    }

    func browserCardSnapshotSignature(_ snapshots: [BrowserCardLayerSnapshot]) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshots.count)
        for snapshot in snapshots {
            hasher.combine(snapshot)
        }
        return hasher.finalize()
    }

    func browserLinkSnapshotSignature(_ snapshots: [BrowserLinkLayerSnapshot]) -> Int {
        var hasher = Hasher()
        hasher.combine(snapshots.count)
        for snapshot in snapshots {
            hasher.combine(snapshot.id)
            hasher.combine(snapshot.fromCardID)
            hasher.combine(snapshot.toCardID)
            hasher.combine(snapshot.shapeIndex)
            hasher.combine(snapshot.directionVisible)
            hasher.combine(snapshot.labelText)
            hasher.combine(snapshot.isHighlighted)
            hasher.combine(snapshot.startPoint.x)
            hasher.combine(snapshot.startPoint.y)
            hasher.combine(snapshot.endPoint.x)
            hasher.combine(snapshot.endPoint.y)
            if let labelPoint = snapshot.labelPoint {
                hasher.combine(labelPoint.x)
                hasher.combine(labelPoint.y)
            } else {
                hasher.combine(-1.0)
                hasher.combine(-1.0)
            }
        }
        return hasher.finalize()
    }

    func browserOverlaySignature(_ overlay: BrowserOverlaySnapshot) -> Int {
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

    func browserViewportSummary(in size: CGSize) -> String {
        let visible = visibleWorldRect(in: size)
        let centerX = String(format: "%.2f", canvasCenter.x)
        let centerY = String(format: "%.2f", canvasCenter.y)
        let width = String(format: "%.2f", Double(visible.width))
        let height = String(format: "%.2f", Double(visible.height))
        return "Center \(centerX), \(centerY) · View \(width) × \(height)"
    }

    func linkPath(for link: FrieveLink, in size: CGSize) -> Path? {
        guard let points = linkEndpoints(for: link, in: size) else { return nil }
        return Path(buildLinkPath(for: link, start: points.start, end: points.end))
    }

    func linkArrowHead(for link: FrieveLink, in size: CGSize) -> CGPath? {
        guard let points = linkEndpoints(for: link, in: size) else { return nil }
        return buildLinkArrowHead(for: link, start: points.start, end: points.end)
    }

    func linkLabelPoint(for link: FrieveLink, in size: CGSize) -> CGPoint? {
        guard let points = linkEndpoints(for: link, in: size) else { return nil }
        return buildLinkLabelPoint(for: link, start: points.start, end: points.end)
    }

    func linkPreviewSegment(in size: CGSize) -> (CGPoint, CGPoint)? {
        guard let sourceID = linkPreviewSourceCardID,
              let sourceCard = cardByID(sourceID),
              let previewPoint = linkPreviewCanvasPoint else {
            return nil
        }
        return (canvasPoint(for: currentPosition(for: sourceCard), in: size), previewPoint)
    }

    func updateLinkPreviewLocation(_ location: CGPoint) {
        linkPreviewCanvasPoint = location
    }

    func cancelBrowserGesture() {
        clearCanvasTransientState()
    }

    func hitTestCard(at point: CGPoint, in size: CGSize, excludingCardID: Int? = nil) -> FrieveCard? {
        let candidates = visibleBrowserCards(in: size, canvasPadding: 40)
        for card in candidates.reversed() {
            guard card.id != excludingCardID else { continue }
            if cardFrame(for: card, in: size).contains(point) {
                return card
            }
        }
        return nil
    }

    func overviewCards() -> [FrieveCard] {
        visibleSortedCards()
    }

    func overviewPoint(for card: FrieveCard, in overviewSize: CGSize) -> CGPoint {
        overviewPoint(for: card, in: overviewSize, snapshot: nil)
    }

    func overviewViewportRect(overviewSize: CGSize, canvasSize: CGSize) -> CGRect {
        overviewViewportRect(overviewSize: overviewSize, canvasSize: canvasSize, snapshot: nil)
    }

    func recenterFromOverview(location: CGPoint, overviewSize: CGSize) {
        let snapshot = overviewSnapshot()
        let bounds = snapshot.bounds
        canvasCenter = FrievePoint(
            x: bounds.minX + Double(location.x / max(overviewSize.width, 1)) * bounds.width,
            y: bounds.minY + Double(location.y / max(overviewSize.height, 1)) * bounds.height
        )
        markBrowserSurfaceViewportDirty()
    }

    func zoomToSelection(in size: CGSize) {
        guard let selectionBounds = selectionWorldBounds() else {
            resetCanvasToFit(in: size)
            return
        }
        canvasCenter = FrievePoint(x: selectionBounds.midX, y: selectionBounds.midY)
        let fittedScale = min(
            (size.width * 0.72) / max(selectionBounds.width, 0.0001),
            (size.height * 0.72) / max(selectionBounds.height, 0.0001)
        )
        let minDimension = max(min(size.width, size.height), 1)
        browserBaseScaleFactor = max(Double(fittedScale) / Double(minDimension), 0.05)
        zoom = 1.0
        markBrowserSurfaceViewportDirty()
    }

    func zoom(by factor: Double, anchor: CGPoint? = nil, in size: CGSize) {
        let anchorPoint = anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let worldAnchor = canvasToWorld(anchorPoint, in: size)
        zoom = min(max(zoom * factor, 0.2), 6.0)
        let scale = browserScale(in: size)
        canvasCenter = FrievePoint(
            x: worldAnchor.x - Double(anchorPoint.x - size.width / 2) / scale,
            y: worldAnchor.y - Double(anchorPoint.y - size.height / 2) / scale
        )
        markBrowserSurfaceViewportDirty()
    }

    func beginMagnification() {
        gestureZoomStart = zoom
    }

    func updateMagnification(_ value: CGFloat, in size: CGSize) {
        _ = size
        if gestureZoomStart == nil {
            gestureZoomStart = zoom
        }
        zoom = min(max((gestureZoomStart ?? 1.0) * Double(value), 0.2), 6.0)
        markBrowserSurfaceViewportDirty()
    }

    func endMagnification() {
        gestureZoomStart = nil
    }
}
