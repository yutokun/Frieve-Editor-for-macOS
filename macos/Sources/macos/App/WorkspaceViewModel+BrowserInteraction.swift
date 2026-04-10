import SwiftUI
import AppKit

extension WorkspaceViewModel {
    func beginCanvasGesture(at point: CGPoint, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift) {
            browserGestureMode = .marquee(additive: modifiers.contains(.command))
            marqueeStartPoint = point
            marqueeCurrentPoint = point
        } else {
            browserGestureMode = .panning(originCenter: canvasCenter)
        }
    }

    var hasActiveBrowserGesture: Bool {
        browserGestureMode != nil
    }

    func updateCanvasGesture(from start: CGPoint, to current: CGPoint, in size: CGSize) {
        switch browserGestureMode {
        case let .panning(originCenter):
            let scale = browserScale(in: size)
            canvasCenter = FrievePoint(
                x: originCenter.x - Double(current.x - start.x) / scale,
                y: originCenter.y - Double(current.y - start.y) / scale
            )
            markBrowserSurfaceViewportDirty()
        case .marquee:
            marqueeStartPoint = start
            marqueeCurrentPoint = current
            markBrowserSurfaceViewportDirty()
        case .none, .movingSelection, .creatingLink:
            break
        }
    }

    func endCanvasGesture(in size: CGSize) {
        if case let .marquee(additive)? = browserGestureMode {
            applyMarqueeSelection(in: size, additive: additive)
        }
        browserGestureMode = nil
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
    }

    func beginCardInteraction(cardID: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.option) {
            if !selectedCardIDs.contains(cardID) {
                selectedCardIDs = [cardID]
                selectedCardID = cardID
                markBrowserSurfacePresentationDirty()
            }
            linkPreviewSourceCardID = cardID
            linkPreviewCanvasPoint = nil
            browserGestureMode = .creatingLink(sourceCardID: cardID)
            markBrowserSurfaceViewportDirty()
            return
        }

        if !selectedCardIDs.contains(cardID) {
            if modifiers.contains(.command) || modifiers.contains(.shift) {
                selectCard(cardID, additive: true)
            } else {
                selectCard(cardID)
            }
        }

        let activeIDs = selectedCardIDs.isEmpty ? [cardID] : Array(selectedCardIDs)
        dragOriginByCardID = Dictionary(uniqueKeysWithValues: activeIDs.compactMap { id in
            cardByID(id).map { (id, $0.position) }
        })
        currentDragTranslation = .zero
        browserGestureMode = .movingSelection
    }

    func updateCardInteraction(cardID: Int, gesture: DragGesture.Value, in size: CGSize, modifiers: NSEvent.ModifierFlags) {
        updateCardInteraction(cardID: cardID, from: gesture.startLocation, to: gesture.location, in: size, modifiers: modifiers)
    }

    func updateCardInteraction(cardID: Int, from startPoint: CGPoint, to currentPoint: CGPoint, in size: CGSize, modifiers: NSEvent.ModifierFlags) {
        let start = CACurrentMediaTime()
        if browserGestureMode == nil {
            beginCardInteraction(cardID: cardID, modifiers: modifiers)
        }

        switch browserGestureMode {
        case .movingSelection:
            let scale = browserScale(in: size)
            currentDragTranslation = FrievePoint(
                x: Double(currentPoint.x - startPoint.x) / scale,
                y: Double(currentPoint.y - startPoint.y) / scale
            )
            markBrowserSurfaceContentDirty()
            markBrowserSurfacePresentationDirty()
        case .creatingLink:
            linkPreviewCanvasPoint = currentPoint
            markBrowserSurfaceViewportDirty()
        case .none, .panning, .marquee:
            break
        }
        recordPerformanceMetric(start, keyPath: \BrowserPerformanceSnapshot.drag)
    }

    func handleScrollWheel(deltaX: CGFloat, deltaY: CGFloat, modifiers: NSEvent.ModifierFlags, at location: CGPoint, in size: CGSize) {
        if modifiers.contains(.command) {
            let factor = exp(Double(deltaY) / 240.0)
            zoom(by: factor, anchor: location, in: size)
            return
        }

        let scale = browserScale(in: size)
        let horizontalDelta = modifiers.contains(.shift) && deltaX == 0 ? deltaY : deltaX
        canvasCenter = FrievePoint(
            x: canvasCenter.x - Double(horizontalDelta) / scale,
            y: canvasCenter.y - Double(deltaY) / scale
        )
        markBrowserSurfaceViewportDirty()
    }

    func endCardInteraction(gesture: DragGesture.Value, in size: CGSize) {
        endCardInteraction(at: gesture.location, in: size)
    }

    func endCardInteraction(at location: CGPoint, in size: CGSize) {
        switch browserGestureMode {
        case let .creatingLink(sourceCardID):
            if let target = hitTestCard(at: location, in: size, excludingCardID: sourceCardID) {
                appendLinkIfNeeded(from: sourceCardID, to: target.id, name: "Related")
            }
        case .movingSelection:
            if let translation = currentDragTranslation, translation != .zero {
                let affectedIDs = dragOriginByCardID.keys.sorted()
                let timestamp = sharedISOTimestamp()
                for id in affectedIDs {
                    guard let origin = dragOriginByCardID[id] else { continue }
                    document.updateCard(id) { card in
                        card.position = FrievePoint(
                            x: origin.x + translation.x,
                            y: origin.y + translation.y
                        )
                        card.updated = timestamp
                    }
                }
                noteDocumentMutation(status: selectedCardIDs.count > 1 ? "Moved \(selectedCardIDs.count) selected cards" : "Moved the selected card")
            }
        case .none, .panning, .marquee:
            break
        }

        dragOriginByCardID.removeAll()
        currentDragTranslation = nil
        markBrowserSurfaceContentDirty()
        markBrowserSurfacePresentationDirty()
        clearCanvasTransientState()
    }

    func marqueeRect() -> CGRect? {
        guard let start = marqueeStartPoint, let current = marqueeCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    func cardWorldFrame(for card: FrieveCard, in size: CGSize) -> CGRect {
        let cardSize = cardCanvasSize(for: card)
        let scale = max(browserScale(in: size), 1)
        let worldWidth = Double(cardSize.width) / scale
        let worldHeight = Double(cardSize.height) / scale
        let position = currentPosition(for: card)
        return CGRect(
            x: position.x - worldWidth / 2,
            y: position.y - worldHeight / 2,
            width: worldWidth,
            height: worldHeight
        )
    }

    func adaptiveBrowserGridStep(in size: CGSize) -> Double {
        let desiredWorldSpacing = 96.0 / max(browserScale(in: size), 1)
        let candidates: [Double] = [0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10]
        return candidates.first(where: { $0 >= desiredWorldSpacing }) ?? 10
    }

    func appendLinkIfNeeded(from sourceCardID: Int, to targetCardID: Int, name: String) {
        guard sourceCardID != targetCardID else { return }
        let alreadyExists = document.links.contains {
            $0.fromCardID == sourceCardID && $0.toCardID == targetCardID
        }
        guard !alreadyExists else {
            statusMessage = "Link already exists"
            return
        }
        document.links.append(
            FrieveLink(
                fromCardID: sourceCardID,
                toCardID: targetCardID,
                directionVisible: true,
                shape: 5,
                labelIDs: [],
                name: name
            )
        )
        noteDocumentMutation(status: "Created a link between cards")
    }

    func linkEndpoints(for link: FrieveLink, in size: CGSize) -> (start: CGPoint, end: CGPoint)? {
        guard let from = cardByID(link.fromCardID),
              let to = cardByID(link.toCardID) else { return nil }
        return (canvasPosition(for: from, in: size), canvasPosition(for: to, in: size))
    }

    func selectionWorldBounds() -> CGRect? {
        let cards = selectedCards
        guard let first = cards.first else { return nil }
        let firstPosition = currentPosition(for: first)
        var minX = firstPosition.x
        var maxX = firstPosition.x
        var minY = firstPosition.y
        var maxY = firstPosition.y
        for card in cards.dropFirst() {
            let position = currentPosition(for: card)
            minX = min(minX, position.x)
            maxX = max(maxX, position.x)
            minY = min(minY, position.y)
            maxY = max(maxY, position.y)
        }
        let width = max(maxX - minX, 0.2)
        let height = max(maxY - minY, 0.2)
        return CGRect(x: minX - width * 0.3, y: minY - height * 0.3, width: width * 1.6, height: height * 1.6)
    }

    func applyMarqueeSelection(in size: CGSize, additive: Bool) {
        guard let rect = marqueeRect(), rect.width > 2 || rect.height > 2 else { return }
        let hits = Set(sortedCards().filter { card in
            rect.intersects(cardFrame(for: card, in: size))
        }.map(\.id))

        if additive {
            selectedCardIDs.formUnion(hits)
        } else {
            selectedCardIDs = hits
        }
        selectedCardID = selectedCardIDs.sorted().last
        document.focusedCardID = selectedCardID
        if selectedCardID != nil {
            document.touchFocusedCard()
        }
        statusMessage = hits.isEmpty ? "No cards in selection" : "Selected \(selectedCardIDs.count) card(s)"
    }

    func browserWorldToCanvasTransform(in size: CGSize) -> CGAffineTransform {
        let scale = CGFloat(browserScale(in: size))
        return CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: size.width / 2 - CGFloat(canvasCenter.x) * scale,
            ty: size.height / 2 - CGFloat(canvasCenter.y) * scale
        )
    }

    func buildLinkPath(for link: FrieveLink, start: CGPoint, end: CGPoint, baseScale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        let dx = end.x - start.x
        let scale = max(baseScale, 0.0001)
        let controlOffset = max(abs(dx) * 0.35, 28 / scale)
        switch abs(link.shape % 6) {
        case 1, 3:
            let cp1 = CGPoint(x: start.x + controlOffset, y: start.y)
            let cp2 = CGPoint(x: end.x - controlOffset, y: end.y)
            path.addCurve(to: end, control1: cp1, control2: cp2)
        case 2, 4:
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            path.addLine(to: CGPoint(x: mid.x, y: start.y))
            path.addLine(to: CGPoint(x: mid.x, y: end.y))
            path.addLine(to: end)
        default:
            path.addLine(to: end)
        }
        return path
    }

    func buildLinkArrowHead(for link: FrieveLink, start: CGPoint, end: CGPoint, baseScale: CGFloat = 1) -> CGPath? {
        guard link.directionVisible else { return nil }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.0001)
        let ux = dx / length
        let uy = dy / length
        let scale = max(baseScale, 0.0001)
        let arrowLength: CGFloat = 10 / scale
        let arrowWidth: CGFloat = 5 / scale
        let tip = end
        let base = CGPoint(x: end.x - ux * arrowLength, y: end.y - uy * arrowLength)
        let left = CGPoint(x: base.x - uy * arrowWidth, y: base.y + ux * arrowWidth)
        let right = CGPoint(x: base.x + uy * arrowWidth, y: base.y - ux * arrowWidth)
        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    func buildLinkLabelPoint(for link: FrieveLink, start: CGPoint, end: CGPoint, baseScale: CGFloat = 1) -> CGPoint? {
        let name = link.name.trimmed
        guard !name.isEmpty else { return nil }
        let verticalOffset = 8 / max(baseScale, 0.0001)
        return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - verticalOffset)
    }
}
