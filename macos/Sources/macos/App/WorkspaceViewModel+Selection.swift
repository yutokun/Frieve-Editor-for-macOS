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

    func bindingForSelectedDrawing() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedCard?.drawingEncoded ?? "" },
            set: { [weak self] newValue in self?.updateSelectedCardDrawing(newValue) }
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
            get: { [weak self] in Double(self?.selectedCard?.size ?? 100) },
            set: { [weak self] newValue in self?.updateSelectedCardSize(Int(newValue.rounded())) }
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
        if browserInlineEditorCardID != nil, browserInlineEditorCardID != selectedCardID {
            browserInlineEditorCardID = nil
        }
        document.focusedCardID = selectedCardID
        document.touchFocusedCard()
        if autoScroll, let card = cardByID(selectedCardID) {
            canvasCenter = card.position
            markBrowserSurfaceViewportDirty()
        }
        markBrowserSurfacePresentationDirty()
        refreshSearchResults()
    }

    func clearSelection() {
        selectedCardIDs.removeAll()
        selectedCardID = nil
        browserInlineEditorCardID = nil
        document.focusedCardID = nil
        markBrowserSurfacePresentationDirty()
        refreshSearchResults()
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
        browserInlineEditorCardID = id
        markBrowserSurfacePresentationDirty()
        statusMessage = "Opened inline browser editor"
    }

    func dismissBrowserInlineEditor() {
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

    var browserInlineEditorCard: FrieveCard? {
        cardByID(browserInlineEditorCardID)
    }

    func focusBrowser(on cardID: Int) {
        guard let card = cardByID(cardID) else { return }
        canvasCenter = card.position
        markBrowserSurfaceViewportDirty()
        statusMessage = "Centered browser on \(card.title)"
    }
}
