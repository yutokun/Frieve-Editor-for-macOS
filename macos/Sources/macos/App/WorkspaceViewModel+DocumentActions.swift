import SwiftUI
import AppKit

extension WorkspaceViewModel {
    func newDocument() {
        document = .placeholder()
        selectedCardID = document.focusedCardID
        selectedCardIDs = selectedCardID.map { [$0] } ?? []
        browserInlineEditorCardID = nil
        hasUnsavedChanges = false
        lastKnownFileModificationDate = nil
        syncDocumentMetadataFromSettings()
        resetCanvasStateFromDocument()
        statusMessage = "Started a new document"
        refreshSearchResults()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openDocument(url)
        }
    }

    func openDocument(_ url: URL) {
        do {
            let loaded = try DocumentFileCodec.load(url: url)
            document = loaded
            selectedCardID = loaded.focusedCardID ?? loaded.cards.first?.id
            selectedCardIDs = selectedCardID.map { [$0] } ?? []
            browserInlineEditorCardID = nil
            hasUnsavedChanges = false
            lastKnownFileModificationDate = fileModificationDate(for: url)
            recordRecent(url)
            syncDocumentMetadataFromSettings()
            resetCanvasStateFromDocument()
            statusMessage = "Opened \(url.lastPathComponent)"
            refreshSearchResults()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func saveDocument() {
        if let sourcePath = document.sourcePath {
            persistDocument(to: URL(fileURLWithPath: sourcePath), isAutomatic: false)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileDisplayName
        panel.prompt = "Save"
        if panel.runModal() == .OK, let url = panel.url {
            persistDocument(to: url, isAutomatic: false)
        }
    }

    func exportCardTitles() {
        let text = sortedCards().map { $0.title }.joined(separator: "\n")
        saveTextExport(text, defaultName: "CardTitles.txt")
    }

    func exportCardBodies() {
        let text = sortedCards()
            .map { "# \($0.title)\n\($0.bodyText)" }
            .joined(separator: "\n\n")
        saveTextExport(text, defaultName: "CardBodies.txt")
    }

    func exportHierarchicalText() {
        saveTextExport(document.hierarchicalText(), defaultName: "Hierarchy.txt")
    }

    func exportHTMLDocument() {
        saveTextExport(document.htmlDocument(title: document.title), defaultName: "FrieveDocument.html")
    }

    func exportFIP2ToClipboard() {
        copyTextToClipboard(FIP2Codec.save(document: document))
        statusMessage = "Copied FIP2 text to the clipboard"
    }

    func copyGPTPromptToClipboard() {
        let prompt = selectedGPTPrompt()
        lastGPTPrompt = prompt
        copyTextToClipboard(prompt)
        statusMessage = "Copied a GPT-ready prompt to the clipboard"
    }

    func searchWebForSelection() {
        let query = selectedWebSearchQuery()
        guard !query.isEmpty else {
            statusMessage = "Nothing available to search"
            return
        }
        guard let url = settings.preferredWebSearchURL(for: query) else {
            statusMessage = "Could not build the web search URL"
            return
        }
        NSWorkspace.shared.open(url)
        statusMessage = "Opened \(settings.preferredWebSearchProvider().name) search"
    }

    func readSelectedCardAloud() {
        let text = selectedNarrationText()
        guard !text.isEmpty else {
            statusMessage = "Nothing available to read aloud"
            return
        }
        speechSynthesizer.stopSpeaking()
        speechSynthesizer.rate = Float(settings.readAloudRate)
        if speechSynthesizer.startSpeaking(text) {
            statusMessage = "Reading the selected card aloud"
        } else {
            statusMessage = "Failed to start read aloud"
        }
    }

    func stopReadAloud() {
        speechSynthesizer.stopSpeaking()
        statusMessage = "Stopped read aloud"
    }

    func addRootCard() {
        let id = document.addCard(title: "New Card")
        selectCard(id)
        noteDocumentMutation(status: "Added a new card")
    }

    func addCard(at canvasPoint: CGPoint, in size: CGSize) {
        let id = document.addCard(title: "New Card")
        let world = canvasToWorld(canvasPoint, in: size)
        document.updateCard(id) { card in
            card.position = world
            card.updated = isoTimestamp()
        }
        selectCard(id)
        noteDocumentMutation(status: "Created a new card in the browser")
    }

    func addChildCard() {
        let id = document.addCard(title: "Child Card", linkedFrom: selectedCardID)
        selectCard(id)
        noteDocumentMutation(status: "Added a child card")
    }

    func addSiblingCard() {
        let id = document.addSiblingCard(for: selectedCardID)
        selectCard(id)
        noteDocumentMutation(status: "Added a sibling card")
    }

    func addLinkBetweenSelectionAndRoot() {
        guard let selectedCardID, let root = sortedCards().first?.id, selectedCardID != root else { return }
        appendLinkIfNeeded(from: root, to: selectedCardID, name: "Related")
    }

    func deleteSelectedCard() {
        let ids = selectedCardIDs.isEmpty ? Set(selectedCardID.map { [$0] } ?? []) : selectedCardIDs
        guard !ids.isEmpty else { return }
        for id in ids {
            document.deleteCard(id)
        }
        selectedCardID = document.focusedCardID ?? sortedCards().first?.id
        selectedCardIDs = selectedCardID.map { [$0] } ?? []
        if let browserInlineEditorCardID, ids.contains(browserInlineEditorCardID) {
            self.browserInlineEditorCardID = nil
        }
        noteDocumentMutation(status: ids.count == 1 ? "Deleted the selected card" : "Deleted \(ids.count) selected cards")
    }

    func updateSelectedCardTitle(_ title: String) {
        guard let selectedCardID else { return }
        let isTop = cardByID(selectedCardID)?.isTop ?? false
        document.updateCard(selectedCardID) { card in
            card.title = title
            card.updated = isoTimestamp()
        }
        if isTop, !title.trimmed.isEmpty {
            document.title = title
        }
        noteDocumentMutation()
    }

    func updateSelectedCardBody(_ body: String) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.bodyText = body
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardDrawing(_ drawing: String) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.drawingEncoded = drawing
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func updateSelectedCardShape(_ shape: Int) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.shape = shape
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func updateSelectedCardSize(_ size: Int) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.size = max(80, min(size, 320))
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func updateSelectedCardImagePath(_ path: String) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.imagePath = path.trimmed.isEmpty ? nil : path.trimmed
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func updateSelectedCardVideoPath(_ path: String) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.videoPath = path.trimmed.isEmpty ? nil : path.trimmed
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func updateSelectedCardFixed(_ isFixed: Bool) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.isFixed = isFixed
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func updateSelectedCardFolded(_ isFolded: Bool) {
        guard let selectedCardID else { return }
        document.updateCard(selectedCardID) { card in
            card.isFolded = isFolded
            card.updated = isoTimestamp()
        }
        noteDocumentMutation(updateSearch: false)
    }

    func shuffleLayout() {
        for card in document.cards {
            document.moveCard(card.id, dx: Double.random(in: -0.2 ... 0.2), dy: Double.random(in: -0.2 ... 0.2))
        }
        noteDocumentMutation(status: "Shuffled card positions", updateSearch: false)
    }

    func arrangeCards() {
        let cardIDs = sortedCards().map { $0.id }
        let count = max(cardIDs.count, 1)
        for (index, cardID) in cardIDs.enumerated() {
            let angle = Double(index) / Double(count) * .pi * 2
            let radius = 0.28 + (arrangeMode == "Matrix" ? 0.12 : 0)
            document.updateCard(cardID) { card in
                card.position = FrievePoint(
                    x: 0.5 + cos(angle) * radius,
                    y: 0.5 + sin(angle) * radius
                )
            }
        }
        if autoZoom {
            requestBrowserFit()
        }
        noteDocumentMutation(status: "Arranged cards using \(arrangeMode)", updateSearch: false)
    }

    func refreshSearchResults() {
        globalSearchResults = document.filteredCards(query: globalSearchQuery)
        if globalSearchQuery.trimmed.isEmpty {
            globalSearchResults = sortedCards()
        }
    }

    func browseHelp() {
        if let url = URL(string: "https://www.frieve.com/software/frieve-editor") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkLatestRelease() {
        if let url = URL(string: "https://github.com/Frieve-A/Frieve-Editor/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}
