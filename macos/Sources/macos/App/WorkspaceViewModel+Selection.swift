import SwiftUI
import AppKit

extension WorkspaceViewModel {
    func bindingForSelectedTitle() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedCard?.title ?? "" },
            set: { [weak self] newValue in self?.updateSelectedCardTitle(newValue) }
        )
    }

    func bindingForSelectedBody() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedCard?.bodyText ?? "" },
            set: { [weak self] newValue in self?.updateSelectedCardBody(newValue) }
        )
    }

    func bindingForLinkName(_ linkID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.document.links.first(where: { $0.id == linkID })?.name ?? ""
            },
            set: { [weak self] newValue in
                self?.updateLinkName(linkID, name: newValue)
            }
        )
    }

    func bindingForSelectedLabels() -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self, let card = self.selectedCard else { return "" }
                return self.cardLabelNames(for: card).joined(separator: ", ")
            },
            set: { [weak self] newValue in self?.updateSelectedCardLabels(newValue) }
        )
    }

    func bindingForCardLabel(_ label: FrieveLabel) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.selectedCard?.labelIDs.contains(label.id) ?? false },
            set: { [weak self] isOn in
                guard let self, let id = self.selectedCardID else { return }
                self.registerUndoCheckpoint()
                self.document.updateCard(id) { card in
                    if isOn {
                        if !card.labelIDs.contains(label.id) { card.labelIDs.append(label.id) }
                    } else {
                        card.labelIDs.removeAll { $0 == label.id }
                    }
                }
                self.noteDocumentMutation(status: "Updated card label")
            }
        )
    }

    func bindingForSelectedDrawing() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedCard?.drawingEncoded ?? "" },
            set: { [weak self] newValue in self?.updateSelectedCardDrawing(newValue) }
        )
    }

    func bindingForSelectedDrawingColor() -> Binding<Color> {
        Binding(
            get: { [weak self] in
                guard let self, let rawValue = self.selectedDrawingStrokeColorRawValue() else {
                    return .accentColor
                }
                return Color(frieveRGB: rawValue)
            },
            set: { [weak self] newValue in
                self?.setSelectedDrawingStrokeColor(newValue.frieveRGBValue)
            }
        )
    }

    func bindingForSelectedShape() -> Binding<Int> {
        Binding(
            get: { [weak self] in self?.selectedCard?.shape ?? 2 },
            set: { [weak self] newValue in self?.updateSelectedCardShape(newValue) }
        )
    }

    func bindingForSelectedSize() -> Binding<Double> {
        Binding(
            get: { [weak self] in
                guard let self, let size = self.selectedCard?.size else { return 0 }
                return Double(browserCardSizeStep(forStoredSize: size))
            },
            set: { [weak self] newValue in self?.updateSelectedCardSizeStep(Int(newValue.rounded())) }
        )
    }

    func bindingForSelectedImagePath() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedCard?.imagePath ?? "" },
            set: { [weak self] newValue in self?.updateSelectedCardImagePath(newValue) }
        )
    }

    func bindingForSelectedVideoPath() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedCard?.videoPath ?? "" },
            set: { [weak self] newValue in self?.updateSelectedCardVideoPath(newValue) }
        )
    }

    func bindingForSelectedFixed() -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.selectedCard?.isFixed ?? false },
            set: { [weak self] newValue in self?.updateSelectedCardFixed(newValue) }
        )
    }

    func bindingForSelectedFolded() -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.selectedCard?.isFolded ?? false },
            set: { [weak self] newValue in self?.updateSelectedCardFolded(newValue) }
        )
    }

    func selectCard(_ id: Int, additive: Bool = false) {
        finishUndoEditCoalescing()
        if additive {
            if selectedCardIDs.contains(id) {
                selectedCardIDs.remove(id)
                selectedCardID = selectedCardIDs.sorted().last
            } else {
                selectedCardIDs.insert(id)
                selectedCardID = id
            }
        } else {
            selectedCardIDs = [id]
            selectedCardID = id
        }
        updateBrowserInlineEditorForCurrentSelection()
        document.focusedCardID = selectedCardID
        document.touchFocusedCard()
        if autoZoom, selectedTab == .browser {
            zoomToSelection(in: resolvedBrowserCanvasSize())
        }
        if autoScroll {
            prepareBrowserAutoScrollForSelectionChange()
        }
        markBrowserSurfacePresentationDirty()
    }

    func clearSelection() {
        guard !selectedCardIDs.isEmpty || selectedCardID != nil || browserInlineEditorCardID != nil || document.focusedCardID != nil else {
            return
        }
        finishUndoEditCoalescing()
        selectedCardIDs.removeAll()
        selectedCardID = nil
        browserInlineEditorCardID = nil
        document.focusedCardID = nil
        resetBrowserAutoScrollAnimation()
        if autoZoom, selectedTab == .browser {
            zoomToSelection(in: resolvedBrowserCanvasSize())
        }
        markBrowserSurfacePresentationDirty()
    }

    func handleCardTap(_ id: Int, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            selectCard(id, additive: true)
        } else {
            selectCard(id)
        }
    }

    func handleCardDoubleClick(_ id: Int) {
        selectCard(id)
        openBrowserInlineEditor(for: id)
    }

    func handleBrowserEditShortcut() {
        guard let selectedCardID else { return }
        openBrowserInlineEditor(for: selectedCardID)
    }

    func handleBrowserCreateChildShortcut() {
        guard selectedCardID != nil else { return }
        addChildCard()
        if let selectedCardID {
            openBrowserInlineEditor(for: selectedCardID)
        }
    }

    func handleBrowserCreateSiblingShortcut() {
        guard selectedCardID != nil else { return }
        addSiblingCard()
        if let selectedCardID {
            openBrowserInlineEditor(for: selectedCardID)
        }
    }

    func handleBrowserDirectionalSelection(dx: Double, dy: Double) {
        guard let selectedCard = cardByID(selectedCardID) else { return }
        let directionLength = hypot(dx, dy)
        guard directionLength > 0.0001 else { return }

        let directionX = dx / directionLength
        let directionY = dy / directionLength
        let candidates = visibleSortedCards().filter { $0.id != selectedCard.id }
        let source = currentPosition(for: selectedCard)

        let bestCard = candidates.min { lhs, rhs in
            directionalSelectionScore(for: lhs, from: source, directionX: directionX, directionY: directionY) <
            directionalSelectionScore(for: rhs, from: source, directionX: directionX, directionY: directionY)
        }

        guard let bestCard else { return }
        let bestScore = directionalSelectionScore(for: bestCard, from: source, directionX: directionX, directionY: directionY)
        guard bestScore.isFinite else { return }
        selectCard(bestCard.id)
    }

    func dismissBrowserInlineEditor() {
        finishUndoEditCoalescing()
        browserInlineEditorCardID = nil
        markBrowserSurfacePresentationDirty()
    }

    func setBrowserHoverCard(_ cardID: Int?) {
        guard browserHoverCardID != cardID else { return }
        browserHoverCardID = cardID
        markBrowserSurfacePresentationDirty()
    }

    func cardDisplaySummary(for card: FrieveCard) -> String {
        let metadata = metadata(for: card)
        var segments: [String] = [metadata.detailSummary]
        if !metadata.labelNames.isEmpty {
            segments.append(metadata.labelNames.joined(separator: ", "))
        }
        return segments.joined(separator: " · ")
    }

    func cardLabelNames(for card: FrieveCard) -> [String] {
        metadata(for: card).labelNames
    }

    func browserCard(_ id: Int?) -> FrieveCard? {
        cardByID(id)
    }

    var browserHoverCard: FrieveCard? {
        cardByID(browserHoverCardID)
    }

    var browserCardTextCard: FrieveCard? {
        browserHoverCard ?? selectedCard
    }

    var browserInlineEditorCard: FrieveCard? {
        cardByID(browserInlineEditorCardID)
    }

    var browserShowsInlineEditorOverlay: Bool {
        guard settings.browserEditInBrowser, selectedTab == .browser else { return false }
        return browserInlineEditorCardID != nil || settings.browserEditInBrowserAlways
    }

    func focusBrowser(on cardID: Int) {
        guard let card = cardByID(cardID) else { return }
        if autoScroll {
            startBrowserAutoScroll(toward: card.position)
        } else {
            canvasCenter = card.position
            markBrowserSurfaceViewportDirty()
        }
        statusMessage = "Centered browser on \(card.title)"
    }

    func openCardInEditor(_ cardID: Int) {
        guard let card = cardByID(cardID) else { return }
        selectCard(cardID)
        selectedTab = .editor
        editorBodyFocusTrigger = true
        statusMessage = "Opened \(card.title) in the editor"
    }

    private func openBrowserInlineEditor(for cardID: Int) {
        guard settings.browserEditInBrowser else {
            browserInlineEditorCardID = nil
            selectedTab = .editor
            statusMessage = "Opened the card in the editor"
            return
        }
        browserInlineEditorCardID = cardID
        markBrowserSurfacePresentationDirty()
        statusMessage = "Opened inline browser editor"
    }

    func updateBrowserInlineEditorForCurrentSelection() {
        guard settings.browserEditInBrowser else {
            browserInlineEditorCardID = nil
            return
        }
        if settings.browserEditInBrowserAlways,
           selectedTab == .browser,
           let selectedCardID {
            browserInlineEditorCardID = selectedCardID
        } else if browserInlineEditorCardID != nil, browserInlineEditorCardID != selectedCardID {
            browserInlineEditorCardID = nil
        }
    }

    private func directionalSelectionScore(
        for candidate: FrieveCard,
        from source: FrievePoint,
        directionX: Double,
        directionY: Double
    ) -> Double {
        let position = currentPosition(for: candidate)
        let deltaX = position.x - source.x
        let deltaY = position.y - source.y
        let forward = deltaX * directionX + deltaY * directionY
        guard forward > 0.0001 else { return .infinity }

        let lateral = abs(deltaX * -directionY + deltaY * directionX)
        return hypot(forward, lateral * 3)
    }
}
