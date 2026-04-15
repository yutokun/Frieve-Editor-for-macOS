import SwiftUI
import AppKit

extension WorkspaceViewModel {
    private var browserAutoArrangeFrameInterval: CFTimeInterval { 1.0 / 60.0 }
    private var browserAutoArrangeBaselineInterval: CFTimeInterval { 1.0 / 30.0 }
    private var browserAutoArrangeFrameScale: Double { browserAutoArrangeFrameInterval / browserAutoArrangeBaselineInterval }
    private var browserAutoScrollDuration: CFTimeInterval { 0.28 }
    private var browserAutoScrollSelectionLagDuration: CFTimeInterval { settings.browserNoScrollLag ? 1.0 : 0 }
    private var browserFitBoundsPadding: Double { 0.10 }
    private var browserFitVisibleFraction: Double { 0.94 }
    private var isBrowserAutoArrangeTemporarilySuspended: Bool {
        CACurrentMediaTime() < browserAutoArrangeSuspendedUntil
    }

    func ensureBrowserAutoArrangeTimer() {
        guard browserAutoArrangeTimer == nil else { return }
        let timer = Timer(timeInterval: browserAutoArrangeFrameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyBrowserAutoArrangeStepIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        browserAutoArrangeTimer = timer
    }

    func stopBrowserAutoArrangeTimer(resetClock: Bool = true) {
        browserAutoArrangeTimer?.invalidate()
        browserAutoArrangeTimer = nil
    }

    func updateBrowserAutoArrangeTimerState() {
        guard browserAutoArrangeEnabled, selectedTab == .browser, !shouldSuspendBrowserAutoArrangeForCurrentGesture, !isBrowserAutoArrangeTemporarilySuspended else {
            stopBrowserAutoArrangeTimer()
            return
        }
        ensureBrowserAutoArrangeTimer()
    }

    func suspendBrowserAutoArrange(for duration: CFTimeInterval = 0.18, at timestamp: CFTimeInterval = CACurrentMediaTime()) {
        guard duration > 0 else { return }
        browserAutoArrangeSuspendedUntil = max(browserAutoArrangeSuspendedUntil, timestamp + duration)
        browserAutoArrangeResumeWorkItem?.cancel()
        browserAutoArrangeResumeWorkItem = nil
        stopBrowserAutoArrangeTimer()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.browserAutoArrangeResumeWorkItem = nil
            self.updateBrowserAutoArrangeTimerState()
        }
        browserAutoArrangeResumeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func browserAutoArrangeStepScale() -> Double {
        browserAutoArrangeFrameScale
    }

    func ensureBrowserAutoScrollTimer() {
        guard browserAutoScrollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyBrowserViewportAnimationsFrameIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        browserAutoScrollTimer = timer
    }

    func stopBrowserAutoScrollTimer() {
        browserAutoScrollTimer?.invalidate()
        browserAutoScrollTimer = nil
    }

    func startBrowserAutoScroll(toward targetCenter: FrievePoint, delay: CFTimeInterval = 0) {
        let now = CACurrentMediaTime()
        resetBrowserFitAnimation()
        browserAutoScrollStartCenter = nil
        browserAutoScrollTargetCenter = targetCenter
        browserAutoScrollStartedAt = nil
        browserAutoScrollSuspendedUntil = delay > 0 ? now + delay : 0
        ensureBrowserAutoScrollTimer()
        if delay <= 0 {
            applyBrowserViewportAnimationsFrameIfNeeded(at: now)
        }
    }

    func prepareBrowserAutoScrollForSelectionChange() {
        if let selectedCard {
            startBrowserAutoScroll(toward: selectedCard.position, delay: browserAutoScrollSelectionLagDuration)
        } else {
            resetBrowserAutoScrollAnimation()
        }
    }

    func resetBrowserAutoScrollAnimation() {
        browserAutoScrollStartCenter = nil
        browserAutoScrollTargetCenter = nil
        browserAutoScrollStartedAt = nil
        browserAutoScrollSuspendedUntil = 0
        if !browserAutoArrangeEnabled && browserAutoZoomStartZoom == nil && browserFitAnimationStartedAt == nil {
            stopBrowserAutoScrollTimer()
        }
    }

    func suspendBrowserAutoScroll(for duration: CFTimeInterval = 0.5, at timestamp: CFTimeInterval = CACurrentMediaTime()) {
        browserAutoScrollStartCenter = nil
        browserAutoScrollTargetCenter = nil
        browserAutoScrollStartedAt = nil
        browserAutoScrollSuspendedUntil = max(browserAutoScrollSuspendedUntil, timestamp + duration)
        if autoScroll {
            ensureBrowserAutoScrollTimer()
        }
    }

    @discardableResult
    func applyBrowserViewportAnimationsFrameIfNeeded(
        at timestamp: CFTimeInterval = CACurrentMediaTime(),
        refresh: Bool = true
    ) -> Bool {
        let didScroll = applyBrowserAutoScrollStepIfNeeded(at: timestamp, refresh: false)
        let didZoom = applyBrowserAutoZoomStepIfNeeded(at: timestamp, refresh: false)
        let didFit = applyBrowserFitStepIfNeeded(at: timestamp, refresh: false)
        let didChange = didScroll || didZoom || didFit
        if didChange && refresh {
            markBrowserSurfaceViewportDirty()
        }
        return didChange
    }

    @discardableResult
    func applyBrowserAutoScrollStepIfNeeded(
        at timestamp: CFTimeInterval = CACurrentMediaTime(),
        refresh: Bool = true
    ) -> Bool {
        guard selectedTab == .browser else {
            resetBrowserAutoScrollAnimation()
            return false
        }
        guard autoScroll, let selectedCard else {
            resetBrowserAutoScrollAnimation()
            return false
        }
        guard !hasActiveBrowserGesture else {
            browserAutoScrollStartCenter = nil
            browserAutoScrollTargetCenter = nil
            browserAutoScrollStartedAt = nil
            return false
        }
        guard timestamp >= browserAutoScrollSuspendedUntil else { return false }

        let selectedTargetCenter = selectedCard.position
        if browserAutoScrollTargetCenter != selectedTargetCenter || browserAutoScrollStartCenter == nil || browserAutoScrollStartedAt == nil {
            browserAutoScrollStartCenter = canvasCenter
            browserAutoScrollTargetCenter = selectedTargetCenter
            browserAutoScrollStartedAt = timestamp - (1.0 / 60.0)
        }
        guard let startCenter = browserAutoScrollStartCenter,
              let targetCenter = browserAutoScrollTargetCenter,
              let startedAt = browserAutoScrollStartedAt else {
            return false
        }

        let deltaX = targetCenter.x - startCenter.x
        let deltaY = targetCenter.y - startCenter.y
        let distanceSquared = deltaX * deltaX + deltaY * deltaY
        if distanceSquared <= 0.00000025 {
            var didChange = false
            if canvasCenter != targetCenter {
                canvasCenter = targetCenter
                didChange = true
            }
            browserAutoScrollStartCenter = nil
            browserAutoScrollStartedAt = nil
            if !browserAutoArrangeEnabled && browserAutoZoomStartZoom == nil && browserFitAnimationStartedAt == nil {
                stopBrowserAutoScrollTimer()
            }
            if didChange && refresh {
                markBrowserSurfaceViewportDirty()
            }
            return didChange
        }

        let rawProgress = min(max((timestamp - startedAt) / browserAutoScrollDuration, 0), 1)
        let easedProgress = 1 - pow(1 - rawProgress, 3)
        let nextCenter = FrievePoint(
            x: startCenter.x + deltaX * easedProgress,
            y: startCenter.y + deltaY * easedProgress
        )
        var didChange = false
        if canvasCenter != nextCenter {
            canvasCenter = nextCenter
            didChange = true
        }

        if rawProgress >= 1 {
            canvasCenter = targetCenter
            browserAutoScrollStartCenter = nil
            browserAutoScrollStartedAt = nil
            didChange = true
            if !browserAutoArrangeEnabled && browserAutoZoomStartZoom == nil && browserFitAnimationStartedAt == nil {
                stopBrowserAutoScrollTimer()
            }
        }
        if didChange && refresh {
            markBrowserSurfaceViewportDirty()
        }
        return didChange
    }

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
        scheduleBrowserChromeRefresh(immediate: true)
    }

    func resolvedBrowserCanvasSize() -> CGSize {
        browserCanvasSize == .zero ? CGSize(width: 1200, height: 800) : browserCanvasSize
    }

    func markBrowserSurfaceContentDirty() {
        browserSurfaceContentRevision &+= 1
        cachedBrowserSurfaceContentKey = nil
        cachedBrowserSurfaceContent = nil
        browserSurfaceContentRefreshHandler?()
        scheduleBrowserChromeRefresh()
    }

    func markBrowserSurfacePresentationDirty() {
        browserSurfacePresentationRevision &+= 1
        browserSurfacePresentationRefreshHandler?()
        scheduleBrowserChromeRefresh()
    }

    func markBrowserSurfaceViewportDirty() {
        browserSurfaceViewportRevision &+= 1
        browserSurfaceViewportRefreshHandler?()
        scheduleBrowserChromeRefresh()
    }

    func scheduleBrowserChromeRefresh(immediate: Bool = false, minimumInterval: CFTimeInterval? = nil) {
        if hasActiveBrowserGesture && !immediate {
            browserPendingChromeRefreshWorkItem?.cancel()
            browserPendingChromeRefreshWorkItem = nil
            return
        }
        browserPendingChromeRefreshWorkItem?.cancel()
        let now = CACurrentMediaTime()
        let resolvedMinimumInterval = minimumInterval ?? browserChromeRefreshMinimumInterval()
        let publish: () -> Void = { [weak self] in
            guard let self else { return }
            self.browserLastChromeRefreshAt = CACurrentMediaTime()
            self.browserChromeRevision &+= 1
            self.browserPendingChromeRefreshWorkItem = nil
        }
        if immediate || now - browserLastChromeRefreshAt >= resolvedMinimumInterval {
            publish()
            return
        }
        let delay = resolvedMinimumInterval - (now - browserLastChromeRefreshAt)
        let workItem = DispatchWorkItem(block: publish)
        browserPendingChromeRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func markBrowserInteractionActivity(duration: CFTimeInterval = 0.18) {
        if !browserInteractionModeEnabled {
            browserInteractionModeEnabled = true
            browserPendingChromeRefreshWorkItem?.cancel()
            browserPendingChromeRefreshWorkItem = nil
            browserInteractionModeRefreshHandler?(true)
        }
        browserInteractionModeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.browserInteractionModeEnabled = false
            self.browserInteractionModeWorkItem = nil
            self.browserInteractionModeRefreshHandler?(false)
            self.scheduleBrowserChromeRefresh(immediate: true)
        }
        browserInteractionModeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    func updateBrowserTickerTimerState() {
        let shouldRun = selectedTab == .browser && settings.browserTickerVisible
        guard shouldRun else {
            browserTickerTimer?.invalidate()
            browserTickerTimer = nil
            return
        }
        guard browserTickerTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            self?.markBrowserSurfacePresentationDirty()
        }
        RunLoop.main.add(timer, forMode: .common)
        browserTickerTimer = timer
    }

    func setBrowserLinkLabelsVisible(_ isVisible: Bool) {
        guard linkLabelsVisible != isVisible else { return }
        linkLabelsVisible = isVisible
        markBrowserSurfaceContentDirty()
        markBrowserSurfacePresentationDirty()
    }

    func setBrowserLabelRectanglesVisible(_ isVisible: Bool) {
        guard labelRectanglesVisible != isVisible else { return }
        labelRectanglesVisible = isVisible
        markBrowserSurfaceContentDirty()
        markBrowserSurfacePresentationDirty()
    }

    func resetCanvasToFit(in size: CGSize) {
        resetBrowserFitAnimation()
        let bounds = browserDocumentBounds(padding: browserFitBoundsPadding)
        canvasCenter = FrievePoint(x: bounds.midX, y: bounds.midY)
        let fittedScale = min(
            (size.width * browserFitVisibleFraction) / max(bounds.width, 0.0001),
            (size.height * browserFitVisibleFraction) / max(bounds.height, 0.0001)
        )
        let minDimension = max(min(size.width, size.height), 1)
        browserBaseScaleFactor = max(Double(fittedScale) / Double(minDimension), 0.05)
        zoom = 1.0
        suspendBrowserAutoScroll()
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
        registerUndoCheckpoint()
        for id in activeIDs {
            document.moveCard(id, dx: dx, dy: dy)
        }
        noteDocumentMutation(status: activeIDs.count == 1 ? "Moved the selected card" : "Moved \(activeIDs.count) selected cards")
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
            detailLevel: detailLevel,
            canvasSize: size,
            canvasPadding: canvasPadding,
            labelsVisible: settings.browserLinkNameVisible || settings.browserLabelNameVisible || browserLabelOutlineStyle != .none
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
        var visibleCards: [FrieveCard] = []
        visibleCards.reserveCapacity(64)
        var cards: [BrowserCardLayerSnapshot] = []
        cards.reserveCapacity(64)
        var visibleCardWorldFrames: [Int: CGRect] = [:]
        visibleCardWorldFrames.reserveCapacity(64)

        for card in visibleSortedCards() {
            let position = currentPosition(for: card)
            let metadata = metadata(for: card)
            let worldFrame = browserWorldFrame(position: position, canvasSize: metadata.canvasSize, scale: sceneScale)
            guard paddedVisible.intersects(worldFrame) else { continue }
            visibleCards.append(card)
            visibleCardWorldFrames[card.id] = worldFrame
            cards.append(
                BrowserCardLayerSnapshot(
                    card: card,
                    position: position,
                    metadata: metadata,
                    isSelected: selectedCardIDs.contains(card.id),
                    isHovered: browserHoverCardID == card.id,
                    detailLevel: detailLevel
                )
            )
        }
        cards = browserSurfaceCardsOrderedForRendering(cards)
        let visibleCardIDs = Set(cards.map { $0.id })
        let links = visibleLinkLayerSnapshots(in: size, visibleCardIDs: visibleCardIDs)
        let labelGroups = (browserLabelOutlineStyle != .none || settings.browserLabelNameVisible)
            ? visibleBrowserLabelGroupSnapshots(
                visibleCards: visibleCards,
                visibleCardWorldFrames: visibleCardWorldFrames,
                clipRect: paddedVisible
            )
            : []
        let entry = BrowserSurfaceContentCacheEntry(
            coverageRect: paddedVisible,
            cards: cards,
            cardSnapshotSignature: browserCardSnapshotSignature(cards),
            links: links,
            linkSnapshotSignature: browserLinkSnapshotSignature(links),
            labelGroups: labelGroups
        )
        cachedBrowserSurfaceContentKey = key
        cachedBrowserSurfaceContent = entry
        return entry
    }

    func browserHitRegions(for cards: [BrowserCardLayerSnapshot], in size: CGSize) -> [BrowserCardHitRegion] {
        cards.map { snapshot in
            let center = canvasPoint(for: snapshot.position, in: size)
            return BrowserCardHitRegion(
                cardID: snapshot.id,
                frame: CGRect(
                    x: center.x - snapshot.metadata.canvasSize.width / 2,
                    y: center.y - snapshot.metadata.canvasSize.height / 2,
                    width: snapshot.metadata.canvasSize.width,
                    height: snapshot.metadata.canvasSize.height
                )
            )
        }
    }

    func browserSurfaceScene(in size: CGSize, canvasPadding: CGFloat = 260) -> BrowserSurfaceSceneSnapshot {
        let start = CACurrentMediaTime()
        let content = browserSurfaceContent(in: size, canvasPadding: canvasPadding)
        let cards = browserSurfaceCardsOrderedForRendering(content.cards.map { snapshot in
            BrowserCardLayerSnapshot(
                card: snapshot.card,
                position: snapshot.position,
                metadata: snapshot.metadata,
                isSelected: selectedCardIDs.contains(snapshot.id),
                isHovered: browserHoverCardID == snapshot.id,
                detailLevel: snapshot.detailLevel
            )
        })
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
        let hitRegions = browserHitRegions(for: cards, in: size)
        let scene = BrowserSurfaceSceneSnapshot(
            canvasSize: size,
            worldToCanvasTransform: browserWorldToCanvasTransform(in: size),
            backgroundGuidePath: browserBackgroundGuideCGPath(in: size),
            cards: cards,
            cardSnapshotSignature: browserCardSnapshotSignature(cards),
            links: links,
            linkSnapshotSignature: browserLinkSnapshotSignature(links),
            labelGroups: content.labelGroups,
            hitRegions: hitRegions,
            overlay: overlay,
            overlaySignature: browserOverlaySignature(overlay),
            viewportSummary: browserViewportSummary(in: size)
        )
        recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.surfaceScene)
        return scene
    }

    func browserSurfaceCardsOrderedForRendering(_ cards: [BrowserCardLayerSnapshot]) -> [BrowserCardLayerSnapshot] {
        guard cards.count > 1 else { return cards }

        let originalOrder = cards.enumerated().reduce(into: [Int: Int]()) { partial, entry in
            partial[entry.element.id] = partial[entry.element.id] ?? entry.offset
        }
        let depthByCardID = browserRenderDepthByCardID(for: cards.map(\.id))

        return cards.sorted { lhs, rhs in
            if lhs.isSelected != rhs.isSelected {
                return !lhs.isSelected && rhs.isSelected
            }

            let lhsDepth = depthByCardID[lhs.id] ?? 0
            let rhsDepth = depthByCardID[rhs.id] ?? 0
            if lhsDepth != rhsDepth {
                return lhsDepth > rhsDepth
            }

            return (originalOrder[lhs.id] ?? 0) < (originalOrder[rhs.id] ?? 0)
        }
    }

    func browserRenderDepthByCardID(for cardIDs: [Int]) -> [Int: Int] {
        let visibleCardIDs = Set(cardIDs)
        guard !visibleCardIDs.isEmpty else { return [:] }

        var childrenByParent: [Int: [Int]] = [:]
        var childCardIDs: Set<Int> = []
        for link in document.links where visibleCardIDs.contains(link.fromCardID) && visibleCardIDs.contains(link.toCardID) {
            childrenByParent[link.fromCardID, default: []].append(link.toCardID)
            childCardIDs.insert(link.toCardID)
        }

        let rootCardIDs = cardIDs.filter { !childCardIDs.contains($0) }
        guard !rootCardIDs.isEmpty else {
            return cardIDs.reduce(into: [Int: Int]()) { partial, cardID in
                partial[cardID] = partial[cardID] ?? 0
            }
        }

        var depthByCardID: [Int: Int] = [:]
        var queue = rootCardIDs.map { ($0, 0) }
        var queueIndex = 0

        while queueIndex < queue.count {
            let (cardID, depth) = queue[queueIndex]
            queueIndex += 1

            if let existingDepth = depthByCardID[cardID], existingDepth >= depth {
                continue
            }
            depthByCardID[cardID] = depth

            for childID in childrenByParent[cardID] ?? [] {
                queue.append((childID, depth + 1))
            }
        }

        for cardID in cardIDs where depthByCardID[cardID] == nil {
            depthByCardID[cardID] = 0
        }
        return depthByCardID
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
        guard settings.browserLinkVisible, !visibleCardIDs.isEmpty else {
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
        guard settings.browserLinkVisible, !visibleCardIDs.isEmpty else { return [] }
        let scale = max(browserScale(in: size), 1)
        let detailLevel = browserCardDetailLevel()
        let showsLabels = settings.browserLinkNameVisible && detailLevel != .thumbnail
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
                shapeIndex: ((link.shape % frieveLinkShapeOptions.count) + frieveLinkShapeOptions.count) % frieveLinkShapeOptions.count,
                directionVisible: settings.browserLinkDirectionVisible && link.directionVisible,
                labelPoint: buildLinkLabelPoint(for: link, start: start, end: end, baseScale: CGFloat(scale)),
                labelText: showsLabels ? link.name.trimmed.nilIfEmpty : nil,
                isHighlighted: selectedCardIDs.contains(link.fromCardID) || selectedCardIDs.contains(link.toCardID)
            )
        }
    }

    func visibleBrowserLabelGroupSnapshots(
        visibleCards: [FrieveCard],
        visibleCardWorldFrames: [Int: CGRect],
        clipRect: CGRect
    ) -> [BrowserLabelGroupLayerSnapshot] {
        guard !visibleCards.isEmpty else { return [] }
        let outlineStyle = browserLabelOutlineStyle
        let showsName = settings.browserLabelNameVisible

        return document.cardLabels.compactMap { label in
            guard label.enabled, !label.fold else { return nil }

            var worldBounds: CGRect?
            for card in visibleCards where card.labelIDs.contains(label.id) {
                guard let frame = visibleCardWorldFrames[card.id] else { continue }
                worldBounds = worldBounds.map { $0.union(frame) } ?? frame
            }

            guard var worldBounds, clipRect.intersects(worldBounds) else { return nil }
            guard outlineStyle != .none || showsName else { return nil }
            if outlineStyle == .circle {
                let radius = max(worldBounds.width, worldBounds.height) / 2
                worldBounds = CGRect(
                    x: worldBounds.midX - radius,
                    y: worldBounds.midY - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            }
            return BrowserLabelGroupLayerSnapshot(
                id: label.id,
                name: label.name.trimmed.nilIfEmpty ?? "Label \(label.id)",
                color: label.color,
                worldRect: worldBounds,
                labelSize: label.size,
                prefersNameAbove: worldBounds.minY < 0.4,
                outlineStyle: outlineStyle,
                showsName: showsName
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

    private func browserWorldFrame(position: FrievePoint, canvasSize: CGSize, scale: Double) -> CGRect {
        let worldWidth = Double(canvasSize.width) / scale
        let worldHeight = Double(canvasSize.height) / scale
        return CGRect(
            x: position.x - worldWidth / 2,
            y: position.y - worldHeight / 2,
            width: worldWidth,
            height: worldHeight
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
        if let labelColor = metadata(for: card).primaryLabelColor {
            return Color(frieveRGB: labelColor)
        }
        if card.isTop {
            return isHovered ? .accentColor : .accentColor.opacity(0.85)
        }
        if isHovered {
            return Color.secondary.opacity(0.55)
        }
        return Color.secondary.opacity(0.35)
    }

    func browserCardStrokeWidth(isSelected: Bool) -> Float {
        isSelected ? 3 : 1
    }

    func browserCardShadow(for card: FrieveCard, isSelected: Bool, isHovered: Bool) -> Color {
        _ = (card, isSelected, isHovered)
        guard settings.browserCardShadow else { return .clear }
        return Color.black.opacity(isSelected ? 0.22 : 0.14)
    }

    func browserCardGlow(for card: FrieveCard, isSelected: Bool) -> Color {
        _ = (card, isSelected)
        return .clear
    }

    func browserCardBadgeItems(for card: FrieveCard) -> [String] {
        metadata(for: card).badges
    }

    func browserBackgroundGuidePath(in size: CGSize) -> Path {
        Path(browserBackgroundGuideCGPath(in: size))
    }

    func browserBackgroundGuideCGPath(in size: CGSize) -> CGPath {
        let path = CGMutablePath()
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
        suspendBrowserAutoScroll()
        markBrowserSurfaceViewportDirty()
    }

    func zoomToSelection(in size: CGSize) {
        let visibleCards = visibleSortedCards()
        let visibleIDs = Set(visibleCards.map(\.id))
        guard let primaryCard = cardByID(selectedCardID), visibleIDs.contains(primaryCard.id) else {
            startBrowserFitAnimation(in: size)
            return
        }

        let relatedIDs = browserRelatedCardIDs(for: primaryCard.id, visibleIDs: visibleIDs)
        let selectedIDs = selectedCardIDs.union(selectedCardID.map { [$0] } ?? []).intersection(visibleIDs)
        let focusCards = visibleCards.filter { card in
            card.id == primaryCard.id || relatedIDs.contains(card.id) || selectedIDs.contains(card.id)
        }

        let center = autoScroll ? primaryCard.position : canvasCenter

        let currentScale = browserScale(in: size)
        let W = max(Double(size.width), 1.0)
        let H = max(Double(size.height), 1.0)

        // Windows algorithm: RMS spread of related cards normalized by screen dimensions,
        // targeting m_fZoomSD = 0.21 (cards span ~42% of screen as RMS spread)
        var xdSum = 0.0
        var ydSum = 0.0
        var maxd = 0.0
        var count = 0
        for card in focusCards {
            let dx = (card.position.x - center.x) * currentScale / W
            let dy = (card.position.y - center.y) * currentScale / H
            xdSum += dx * dx
            ydSum += dy * dy
            maxd = max(maxd, max(abs(dx), abs(dy)))
            count += 1
        }
        guard count > 0, xdSum > 0, ydSum > 0 else {
            suspendBrowserAutoScroll()
            return
        }
        let n = Double(count)
        var spread = sqrt(xdSum / n)
        let verticalSpread = sqrt(ydSum / n)
        if verticalSpread > spread {
            spread = verticalSpread
        }

        // target zoom multiplier: make RMS spread = 0.21 of screen
        var zoomMultiplier = 0.21 / spread
        // Also clamp so the farthest card doesn't exceed 40% from center
        if maxd > 0 { zoomMultiplier = min(zoomMultiplier, 0.4 / maxd) }

        let targetZoom = min(max(zoom * zoomMultiplier, 0.2), 6.0)
        startBrowserAutoZoom(to: targetZoom)
        suspendBrowserAutoScroll()
    }

    private func startBrowserAutoZoom(to targetZoom: Double) {
        let now = CACurrentMediaTime()
        resetBrowserFitAnimation()
        browserAutoZoomStartZoom = zoom
        browserAutoZoomTargetZoom = targetZoom
        browserAutoZoomStartedAt = now - (1.0 / 60.0)
        ensureBrowserAutoScrollTimer()
        applyBrowserViewportAnimationsFrameIfNeeded(at: now)
    }

    func resetBrowserAutoZoomAnimation() {
        browserAutoZoomStartZoom = nil
        browserAutoZoomTargetZoom = nil
        browserAutoZoomStartedAt = nil
        if !browserAutoArrangeEnabled && browserAutoScrollStartCenter == nil && browserFitAnimationStartedAt == nil {
            stopBrowserAutoScrollTimer()
        }
    }

    @discardableResult
    func applyBrowserAutoZoomStepIfNeeded(
        at timestamp: CFTimeInterval = CACurrentMediaTime(),
        refresh: Bool = true
    ) -> Bool {
        guard let startZoom = browserAutoZoomStartZoom,
              let targetZoom = browserAutoZoomTargetZoom,
              let startedAt = browserAutoZoomStartedAt else { return false }
        guard !hasActiveBrowserGesture else {
            resetBrowserAutoZoomAnimation()
            return false
        }

        let rawProgress = min(max((timestamp - startedAt) / browserAutoScrollDuration, 0), 1)
        let easedProgress = 1 - pow(1 - rawProgress, 3)
        let nextZoom = startZoom + (targetZoom - startZoom) * easedProgress
        var didChange = false
        if abs(zoom - nextZoom) > 0.0001 {
            zoom = nextZoom
            didChange = true
        }

        if rawProgress >= 1 {
            zoom = targetZoom
            resetBrowserAutoZoomAnimation()
            didChange = true
        }
        if didChange && refresh {
            markBrowserSurfaceViewportDirty()
        }
        return didChange
    }

    func startBrowserFitAnimation(in size: CGSize) {
        let bounds = browserDocumentBounds(padding: browserFitBoundsPadding)
        let fittedScale = min(
            (size.width * browserFitVisibleFraction) / max(bounds.width, 0.0001),
            (size.height * browserFitVisibleFraction) / max(bounds.height, 0.0001)
        )
        let minDimension = max(min(size.width, size.height), 1)
        let targetBaseScaleFactor = max(Double(fittedScale) / Double(minDimension), 0.05)
        let targetZoom = min(max(Double(fittedScale) / (Double(minDimension) * browserBaseScaleFactor), 0.2), 6.0)
        let now = CACurrentMediaTime()

        resetBrowserAutoScrollAnimation()
        browserFitAnimationStartCenter = canvasCenter
        browserFitAnimationTargetCenter = FrievePoint(x: bounds.midX, y: bounds.midY)
        browserFitAnimationStartZoom = zoom
        browserFitAnimationTargetZoom = targetZoom
        browserFitAnimationTargetBaseScaleFactor = targetBaseScaleFactor
        browserFitAnimationStartedAt = now - (1.0 / 60.0)
        ensureBrowserAutoScrollTimer()
        applyBrowserViewportAnimationsFrameIfNeeded(at: now)
    }

    func resetBrowserFitAnimation() {
        browserFitAnimationStartCenter = nil
        browserFitAnimationTargetCenter = nil
        browserFitAnimationStartZoom = nil
        browserFitAnimationTargetZoom = nil
        browserFitAnimationTargetBaseScaleFactor = nil
        browserFitAnimationStartedAt = nil
    }

    @discardableResult
    func applyBrowserFitStepIfNeeded(
        at timestamp: CFTimeInterval = CACurrentMediaTime(),
        refresh: Bool = true
    ) -> Bool {
        guard let startCenter = browserFitAnimationStartCenter,
              let targetCenter = browserFitAnimationTargetCenter,
              let startZoom = browserFitAnimationStartZoom,
              let targetZoom = browserFitAnimationTargetZoom,
              let startedAt = browserFitAnimationStartedAt else {
            return false
        }
        guard !hasActiveBrowserGesture else {
            resetBrowserFitAnimation()
            return false
        }

        let rawProgress = min(max((timestamp - startedAt) / browserAutoScrollDuration, 0), 1)
        let easedProgress = 1 - pow(1 - rawProgress, 3)
        let nextCenter = FrievePoint(
            x: startCenter.x + (targetCenter.x - startCenter.x) * easedProgress,
            y: startCenter.y + (targetCenter.y - startCenter.y) * easedProgress
        )
        let nextZoom = startZoom + (targetZoom - startZoom) * easedProgress
        var didChange = false
        if canvasCenter != nextCenter {
            canvasCenter = nextCenter
            didChange = true
        }
        if abs(zoom - nextZoom) > 0.0001 {
            zoom = nextZoom
            didChange = true
        }

        if rawProgress >= 1 {
            canvasCenter = targetCenter
            if let targetBaseScaleFactor = browserFitAnimationTargetBaseScaleFactor {
                browserBaseScaleFactor = targetBaseScaleFactor
                zoom = 1.0
            } else {
                zoom = targetZoom
            }
            resetBrowserFitAnimation()
            didChange = true
            if !browserAutoArrangeEnabled && browserAutoScrollStartCenter == nil && browserAutoZoomStartZoom == nil {
                stopBrowserAutoScrollTimer()
            }
        }
        if didChange && refresh {
            markBrowserSurfaceViewportDirty()
        }
        return didChange
    }

    func zoom(by factor: Double, anchor: CGPoint? = nil, in size: CGSize) {
        let anchorPoint = anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let worldAnchor = canvasToWorld(anchorPoint, in: size)
        resetBrowserAutoZoomAnimation()
        zoom = min(max(zoom * factor, 0.2), 6.0)
        let scale = browserScale(in: size)
        canvasCenter = FrievePoint(
            x: worldAnchor.x - Double(anchorPoint.x - size.width / 2) / scale,
            y: worldAnchor.y - Double(anchorPoint.y - size.height / 2) / scale
        )
        suspendBrowserAutoScroll()
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
        suspendBrowserAutoScroll()
        markBrowserSurfaceViewportDirty()
    }

    func endMagnification() {
        gestureZoomStart = nil
    }
}
