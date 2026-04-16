import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum ExternalFileReferenceKind {
    case image
    case video
    case bodyText
}

enum GPTPromptAction: String, CaseIterable, Identifiable {
    case create
    case continueWriting
    case simplify
    case longer
    case summarize
    case proofread
    case translateToEnglish
    case translateToJapanese
    case title

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .create: "Create…"
        case .continueWriting: "Continue"
        case .simplify: "Simplify"
        case .longer: "Longer"
        case .summarize: "Summarize"
        case .proofread: "Proofread"
        case .translateToEnglish: "Translate to English"
        case .translateToJapanese: "Translate to Japanese"
        case .title: "Title"
        }
    }

    var operationLabel: String {
        switch self {
        case .create: "Insert"
        case .continueWriting: "Insert After"
        case .simplify, .longer, .summarize, .proofread, .translateToEnglish, .translateToJapanese: "Replace"
        case .title: "Title"
        }
    }

    var defaultInstruction: String? {
        switch self {
        case .create:
            nil
        case .continueWriting:
            "Generate text that follow the text below."
        case .simplify:
            "Replace the text below with simpler text."
        case .longer:
            "Inflate the text below and replace it with longer text than the original."
        case .summarize:
            "Summarize and replace the following text."
        case .proofread:
            "You are a professional multilingual proofreader. Replace the text below with the corrected text for grammar, misspellings, etc. If you do not need proofreading, please answer the original text as it is."
        case .translateToEnglish:
            "Translate the following sentences into English."
        case .translateToJapanese:
            "Translate the following sentences into Japanese."
        case .title:
            "Create a title based on the following sentences. Responses should be in the original language."
        }
    }

    static let menuSections: [[GPTPromptAction]] = [
        [.create],
        [.continueWriting, .simplify, .longer, .summarize, .proofread],
        [.translateToEnglish, .translateToJapanese],
        [.title]
    ]
}

func browserPrintSnapshotScale(for canvasSize: CGSize, printableSize: CGSize) -> CGFloat {
    guard canvasSize.width > 0, canvasSize.height > 0, printableSize.width > 0, printableSize.height > 0 else {
        return 2
    }
    let fittedScale = max(printableSize.width / canvasSize.width, printableSize.height / canvasSize.height)
    return min(max(fittedScale * 2, 2), 4)
}

func browserPrintImageRect(for imageSize: CGSize, in printableRect: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, printableRect.width > 0, printableRect.height > 0 else {
        return printableRect
    }
    let scale = min(printableRect.width / imageSize.width, printableRect.height / imageSize.height)
    let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: printableRect.midX - fittedSize.width / 2,
        y: printableRect.midY - fittedSize.height / 2,
        width: fittedSize.width,
        height: fittedSize.height
    )
}

private final class BrowserPrintPageView: NSView {
    let image: NSImage
    let printableRect: CGRect

    init(frame: CGRect, image: NSImage, printableRect: CGRect) {
        self.image = image
        self.printableRect = printableRect
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        image.draw(in: browserPrintImageRect(for: image.size, in: printableRect))
    }
}

extension WorkspaceViewModel {
    func browserGaussianRandom(using randomUnit: () -> Double = { Double.random(in: 0 ... 1) }) -> Double {
        var total = 0.0
        for _ in 0..<12 {
            total += randomUnit()
        }
        return total - 6.0
    }

    func newDocument() {
        clearDocumentUndoHistory()
        document = .placeholder()
        selectedCardID = document.focusedCardID
        selectedCardIDs = selectedCardID.map { [$0] } ?? []
        browserInlineEditorCardID = nil
        hasUnsavedChanges = false
        lastKnownFileModificationDate = nil
        syncDocumentMetadataFromSettings()
        resetCanvasStateFromDocument()
        statusMessage = "Started a new document"
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
            clearDocumentUndoHistory()
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

    func importTextFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            do {
                try importTextFiles(from: panel.urls)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func importHierarchicalTextFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            do {
                try importHierarchicalTextFiles(from: panel.urls, bodyFollowsIndentedHeadings: false)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func importHierarchicalTextFilesWithBodies() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Import"
        if panel.runModal() == .OK {
            do {
                try importHierarchicalTextFiles(from: panel.urls, bodyFollowsIndentedHeadings: true)
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func importTextFilesInFolder() {
        guard let directory = chooseExportDirectory(prompt: "Import") else { return }
        do {
            let importedTopID = try importTextFilesInFolder(from: directory)
            selectedCardID = importedTopID
            selectedCardIDs = [importedTopID]
            browserInlineEditorCardID = nil
            noteDocumentMutation(status: "Imported text files from folder")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importTextFiles(from urls: [URL]) throws {
        let importURLs = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !importURLs.isEmpty else { return }

        var importedCardIDs: [Int] = []
        for url in importURLs {
            let bodyText = try importedTextContents(from: url)
            let cardID = document.addCard(title: url.deletingPathExtension().lastPathComponent)
            document.updateCard(cardID) { card in
                card.bodyText = bodyText
                card.updated = sharedISOTimestamp()
            }
            importedCardIDs.append(cardID)
        }

        selectedCardID = importedCardIDs.last
        selectedCardIDs = selectedCardID.map { [$0] } ?? []
        browserInlineEditorCardID = nil
        noteDocumentMutation(status: "Imported \(importedCardIDs.count) text file\(importedCardIDs.count == 1 ? "" : "s")")
    }

    func importHierarchicalTextFiles(from urls: [URL], bodyFollowsIndentedHeadings: Bool) throws {
        let importURLs = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !importURLs.isEmpty else { return }

        var importedTopIDs: [Int] = []
        for url in importURLs {
            let text = try importedTextContents(from: url)
            let lines = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            let topID = importHierarchicalTextDocument(
                named: url.deletingPathExtension().lastPathComponent,
                lines: lines,
                bodyFollowsIndentedHeadings: bodyFollowsIndentedHeadings
            )
            importedTopIDs.append(topID)
        }

        selectedCardID = importedTopIDs.last
        selectedCardIDs = selectedCardID.map { [$0] } ?? []
        browserInlineEditorCardID = nil
        let suffix = bodyFollowsIndentedHeadings ? " with bodies" : ""
        noteDocumentMutation(status: "Imported \(importedTopIDs.count) hierarchical text file\(importedTopIDs.count == 1 ? "" : "s")\(suffix)")
    }

    @discardableResult
    func importTextFilesInFolder(from directory: URL) throws -> Int {
        try importTextFilesInFolderRecursively(from: directory, parentID: nil)
    }

    func exportCardTitles() {
        saveTextExport(cardTitlesExportText(), defaultName: "CardTitles.txt")
    }

    func exportCardBodies() {
        saveTextExport(cardBodiesExportText(), defaultName: "CardTexts.txt")
    }

    func exportAnnotatedCardBodies() {
        saveTextExport(annotatedCardBodiesExportText(), defaultName: "CardBodies.txt")
    }

    func exportCardBodiesPerFile() {
        guard let directory = chooseExportDirectory(prompt: "Export") else { return }
        var usedNames: Set<String> = []

        do {
            for card in sortedCards() {
                let url = uniqueFileURL(in: directory, baseName: card.title, pathExtension: "txt", usedNames: &usedNames)
                try card.bodyText.write(to: url, atomically: true, encoding: .utf8)
            }
            statusMessage = "Exported \(usedNames.count) text files"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportHierarchicalText() {
        saveTextExport(document.hierarchicalText(), defaultName: "Hierarchy.txt")
    }

    func exportHTMLFiles() {
        guard let directory = chooseExportDirectory(prompt: "Export") else { return }

        do {
            let cards = sortedCards()
            var filenamesByCardID: [Int: String] = [:]
            var usedNames: Set<String> = ["index.html", "style.css"]
            for card in cards {
                let url = uniqueFileURL(in: directory, baseName: card.title, pathExtension: "html", usedNames: &usedNames)
                filenamesByCardID[card.id] = url.lastPathComponent
            }

            let style = """
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; background: #f7f7f9; color: #1f2937; }
            a { color: #2563eb; text-decoration: none; }
            a:hover { text-decoration: underline; }
            .card { background: white; border-radius: 12px; padding: 20px; box-shadow: 0 4px 16px rgba(0,0,0,0.08); }
            .nav, .links { margin: 18px 0; color: #4b5563; }
            .body { white-space: pre-wrap; line-height: 1.5; }
            """
            try style.write(to: directory.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)

            let listItems = cards.compactMap { card -> String? in
                guard let filename = filenamesByCardID[card.id] else { return nil }
                return "<li><a href=\"\(filename.htmlEscaped)\">\(card.title.htmlEscaped)</a></li>"
            }.joined(separator: "\n")
            let indexHTML = """
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <title>\(document.title.htmlEscaped)</title>
              <link rel="stylesheet" href="./style.css">
            </head>
            <body>
              <div class="card">
                <h1>\(document.title.htmlEscaped)</h1>
                <ul>
                \(listItems)
                </ul>
              </div>
            </body>
            </html>
            """
            try indexHTML.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

            for (index, card) in cards.enumerated() {
                guard let filename = filenamesByCardID[card.id] else { continue }
                let previousLink = index > 0 ? filenamesByCardID[cards[index - 1].id] : nil
                let nextLink = index < cards.count - 1 ? filenamesByCardID[cards[index + 1].id] : nil
                let relatedLinks = linksForCard(card.id).compactMap { link -> String? in
                    let otherID = link.fromCardID == card.id ? link.toCardID : link.fromCardID
                    guard let otherCard = cardByID(otherID),
                          let otherFilename = filenamesByCardID[otherID] else { return nil }
                    return "<a href=\"\(otherFilename.htmlEscaped)\">[\(otherCard.title.htmlEscaped)]</a>"
                }.joined(separator: " ")

                let page = """
                <html lang="en">
                <head>
                  <meta charset="utf-8">
                  <title>\(document.title.htmlEscaped) - \(card.title.htmlEscaped)</title>
                  <link rel="stylesheet" href="./style.css">
                </head>
                <body>
                  <div class="card">
                    <div class="nav">
                      <a href="./index.html">[Top]</a>
                      \(previousLink.map { "<a href=\"\($0.htmlEscaped)\">[Prev]</a>" } ?? "[Prev]")
                      \(nextLink.map { "<a href=\"\($0.htmlEscaped)\">[Next]</a>" } ?? "[Next]")
                    </div>
                    <h1>\(card.title.htmlEscaped)</h1>
                    \(relatedLinks.isEmpty ? "" : "<div class=\"links\">\(relatedLinks)</div>")
                    <div class="body">\(card.bodyText.htmlEscaped)</div>
                  </div>
                </body>
                </html>
                """
                try page.write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            }

            statusMessage = "Exported HTML files"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportHTMLDocument() {
        saveTextExport(document.htmlDocument(title: document.title), defaultName: "FrieveDocument.html")
    }

    func exportBrowserBMP() {
        guard let image = browserSnapshotProvider?() else {
            statusMessage = "Browser image is unavailable"
            return
        }
        saveImageExport(image, defaultName: "Browser.bmp", fileType: .bmp)
    }

    func exportBrowserJPEG() {
        guard let image = browserSnapshotProvider?() else {
            statusMessage = "Browser image is unavailable"
            return
        }
        saveImageExport(image, defaultName: "Browser.jpg", fileType: .jpeg)
    }

    func copyCardTitlesToClipboard() {
        copyTextToClipboard(cardTitlesExportText())
        statusMessage = "Copied card titles to the clipboard"
    }

    func copyCardBodiesToClipboard() {
        copyTextToClipboard(cardBodiesExportText())
        statusMessage = "Copied card text to the clipboard"
    }

    func copyBrowserImageToClipboard() {
        guard let image = browserSnapshotProvider?() else {
            statusMessage = "Browser image is unavailable"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        statusMessage = "Copied the browser image to the clipboard"
    }

    func printBrowserView() {
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let printableRect = printInfo.imageablePageBounds.insetBy(dx: 12, dy: 12)
        let snapshotScale = browserPrintSnapshotScale(for: resolvedBrowserCanvasSize(), printableSize: printableRect.size)
        guard let image = browserHighResolutionSnapshotProvider?(snapshotScale) ?? browserSnapshotProvider?() else {
            statusMessage = "Browser image is unavailable"
            return
        }

        let printView = BrowserPrintPageView(
            frame: CGRect(origin: .zero, size: printInfo.paperSize),
            image: image,
            printableRect: printableRect
        )
        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        statusMessage = operation.run() ? "Opened the browser print dialog" : "Browser printing was cancelled"
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

    func cardTitlesExportText() -> String {
        sortedCards().map(\.title).joined(separator: "\n")
    }

    func cardBodiesExportText() -> String {
        sortedCards().map(\.bodyText).joined(separator: "\n")
    }

    func annotatedCardBodiesExportText() -> String {
        sortedCards()
            .map { "# \($0.title)\n\($0.bodyText)" }
            .joined(separator: "\n\n")
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
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = settings.readAloudSpeechRate
        speechSynthesizer.speak(utterance)
        statusMessage = "Reading the selected card aloud"
    }

    func stopReadAloud() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        statusMessage = "Stopped read aloud"
    }

    func addRootCard() {
        registerUndoCheckpoint()
        let id = document.addCard(title: "New Card")
        selectCard(id)
        noteDocumentMutation(status: "Added a new card")
    }

    func addCard(at canvasPoint: CGPoint, in size: CGSize) {
        registerUndoCheckpoint()
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
        registerUndoCheckpoint()
        let parentID = selectedCardID
        let id = document.addCard(title: "Child Card", linkedFrom: parentID)
        if let parent = document.card(withID: parentID) {
            let pos = nearbyPlacementPosition(near: parent)
            document.updateCard(id) { $0.position = pos }
        }
        selectCard(id)
        noteDocumentMutation(status: "Added a child card")
    }

    func addSiblingCard() {
        registerUndoCheckpoint()
        guard let siblingID = selectedCardID else { return }
        let source = document.card(withID: siblingID)
        let id = document.addSiblingCard(for: siblingID)
        let parentID = document.links.first { $0.toCardID == siblingID }?.fromCardID
        let anchor = document.card(withID: parentID) ?? source
        if let anchor {
            var pos = nearbyPlacementPosition(near: anchor)
            if let source {
                pos.y = source.position.y
            }
            document.updateCard(id) { $0.position = pos }
        }
        selectCard(id)
        noteDocumentMutation(status: "Added a sibling card")
    }

    /// Returns a position near `source`, at a display-pixel-aware distance,
    /// avoiding overlap with existing cards. Matches the Windows placement algorithm.
    private func nearbyPlacementPosition(near source: FrieveCard) -> FrievePoint {
        let size = browserCanvasSize
        let scale = browserScale(in: size)
        let minDist = 120.0 / scale   // minimum 120 display pixels in world units

        // Average distance to all cards connected to source
        let neighbors = document.links
            .filter { $0.fromCardID == source.id || $0.toCardID == source.id }
            .compactMap { link -> FrieveCard? in
                let nid = link.fromCardID == source.id ? link.toCardID : link.fromCardID
                return document.card(withID: nid)
            }
        var r: Double
        if neighbors.isEmpty {
            r = minDist
        } else {
            r = neighbors.reduce(0.0) { sum, n in
                let dx = n.position.x - source.position.x
                let dy = n.position.y - source.position.y
                return sum + sqrt(dx * dx + dy * dy)
            } / Double(neighbors.count)
            r = max(r, minDist)
            r = min(r, minDist * 3)
        }

        let rbak = r
        let allCards = document.cards
        for i in 1...100 {
            let t = Double.random(in: 0 ..< (.pi * 2))
            let candidate = FrievePoint(
                x: source.position.x + sin(t) * r,
                y: source.position.y - cos(t) * r
            )
            let overlapping = allCards.contains { card in
                let dx = card.position.x - candidate.x
                let dy = card.position.y - candidate.y
                return dx * dx + dy * dy < (rbak * rbak / 4.0)
            }
            if !overlapping { return candidate }
            if i > 1 { r += rbak * 0.1 / Double(i) }
        }
        // Fallback: just place at rbak distance in a random direction
        let t = Double.random(in: 0 ..< (.pi * 2))
        return FrievePoint(x: source.position.x + sin(t) * rbak,
                           y: source.position.y - cos(t) * rbak)
    }

    func addLinkBetweenSelectionAndRoot() {
        guard let selectedCardID, let root = sortedCards().first?.id, selectedCardID != root else { return }
        registerUndoCheckpoint()
        appendLinkIfNeeded(from: root, to: selectedCardID, name: "Related")
    }

    func addLinkFromSelection(to targetCardID: Int) {
        guard let selectedCardID, selectedCardID != targetCardID else { return }
        registerUndoCheckpoint()
        appendLinkIfNeeded(from: selectedCardID, to: targetCardID, name: "Related")
    }

    func deleteSelectedCard() {
        let ids = selectedCardIDs.isEmpty ? Set(selectedCardID.map { [$0] } ?? []) : selectedCardIDs
        guard !ids.isEmpty else { return }
        registerUndoCheckpoint()
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
        guard let selectedCardID, let selectedCard = cardByID(selectedCardID) else { return }
        guard selectedCard.title != title else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        let isTop = selectedCard.isTop
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
        guard let selectedCardID, cardByID(selectedCardID)?.bodyText != body else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.bodyText = body
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardLabels(_ labelsText: String) {
        guard let selectedCardID, let selectedCard = cardByID(selectedCardID) else { return }

        let names = labelsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        var uniqueNames: [String] = []
        for name in names where !uniqueNames.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            uniqueNames.append(name)
        }

        let currentNames = cardLabelNames(for: selectedCard)
        guard currentNames != uniqueNames else { return }

        registerUndoCheckpointForEdit(cardID: selectedCardID)

        var resolvedLabelIDs: [Int] = []
        var nextLabelID = (document.cardLabels.map(\.id).max() ?? 0) + 1
        for (index, name) in uniqueNames.enumerated() {
            if let existing = document.cardLabels.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                resolvedLabelIDs.append(existing.id)
                continue
            }
            let newLabel = FrieveLabel(
                id: nextLabelID,
                name: name,
                color: defaultCardLabelColor(for: nextLabelID + index),
                enabled: true,
                show: true,
                hide: false,
                fold: false,
                size: 100
            )
            document.cardLabels.append(newLabel)
            resolvedLabelIDs.append(nextLabelID)
            nextLabelID += 1
        }

        document.updateCard(selectedCardID) { card in
            card.labelIDs = resolvedLabelIDs
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardDrawing(_ drawing: String) {
        guard let selectedCardID, cardByID(selectedCardID)?.drawingEncoded != drawing else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.drawingEncoded = drawing
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func selectedDrawingStrokeColorRawValue() -> Int? {
        guard let drawing = selectedCard?.drawingEncoded else { return nil }
        let colors = drawing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { explicitDrawingStrokeColor(in: String($0)) }
        guard let first = colors.first else { return nil }
        return colors.allSatisfy { $0 == first } ? first : nil
    }

    func setSelectedDrawingStrokeColor(_ rawValue: Int?) {
        guard let currentDrawing = selectedCard?.drawingEncoded else { return }
        let updatedDrawing = currentDrawing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { applyDrawingStrokeColor(rawValue, to: String($0)) }
            .joined(separator: "\n")
        updateSelectedCardDrawing(updatedDrawing)
    }

    func updateSelectedCardShape(_ shape: Int) {
        guard let selectedCardID, cardByID(selectedCardID)?.shape != shape else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.shape = shape
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardSize(_ size: Int) {
        let clampedSize = max(25, min(size, 400))
        guard let selectedCardID, cardByID(selectedCardID)?.size != clampedSize else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.size = clampedSize
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardSizeStep(_ step: Int) {
        updateSelectedCardSize(browserCardStoredSize(forStep: step))
    }

    func updateSelectedCardImagePath(_ path: String) {
        let trimmedPath = path.trimmed
        let nextPath = trimmedPath.isEmpty ? nil : trimmedPath
        guard let selectedCardID, cardByID(selectedCardID)?.imagePath != nextPath else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.imagePath = nextPath
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardVideoPath(_ path: String) {
        let trimmedPath = path.trimmed
        let nextPath = trimmedPath.isEmpty ? nil : trimmedPath
        guard let selectedCardID, cardByID(selectedCardID)?.videoPath != nextPath else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.videoPath = nextPath
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardFixed(_ isFixed: Bool) {
        guard let selectedCardID, cardByID(selectedCardID)?.isFixed != isFixed else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.isFixed = isFixed
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func updateSelectedCardFolded(_ isFolded: Bool) {
        guard let selectedCardID, cardByID(selectedCardID)?.isFolded != isFolded else { return }
        registerUndoCheckpointForEdit(cardID: selectedCardID)
        document.updateCard(selectedCardID) { card in
            card.isFolded = isFolded
            card.updated = isoTimestamp()
        }
        noteDocumentMutation()
    }

    func shuffleLayout(using randomUnit: () -> Double = { Double.random(in: 0 ... 1) }) {
        for card in document.cards where !card.isFixed {
            document.updateCard(card.id) { targetCard in
                targetCard.position = FrievePoint(
                    x: browserGaussianRandom(using: randomUnit) * 0.21 + 0.5,
                    y: browserGaussianRandom(using: randomUnit) * 0.21 + 0.5
                )
                targetCard.updated = isoTimestamp()
            }
        }
        if autoZoom {
            requestBrowserFit()
        }
        noteDocumentMutation(status: "Shuffled card positions")
    }

    private func defaultCardLabelColor(for seed: Int) -> Int {
        let palette: [Int] = [0x71CC2E, 0xE39C31, 0xD65745, 0xC45EE0, 0xD6CA3D, 0xCC7A2E, 0x8E67D9, 0x4B7FD6]
        return palette[abs(seed) % palette.count]
    }

    private func explicitDrawingStrokeColor(in line: String) -> Int? {
        for token in line.split(whereSeparator: \.isWhitespace) {
            let lower = token.lowercased()
            guard lower.hasPrefix("color=") || lower.hasPrefix("stroke=") || lower.hasPrefix("pen=") else { continue }
            let rawValue = lower.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
            let cleaned = rawValue.replacingOccurrences(of: "#", with: "")
            if let value = Int(cleaned, radix: 16) {
                return value
            }
            if let value = Int(cleaned) {
                return value
            }
        }
        return nil
    }

    private func applyDrawingStrokeColor(_ rawValue: Int?, to line: String) -> String {
        let trimmedLine = line.trimmed
        guard !trimmedLine.isEmpty else { return line }

        // Parse and re-encode via the shape model to avoid corrupting coordinates.
        // Raw text manipulation would let hex color digits (e.g. "0000" in "color=FF0000")
        // get picked up as extra coordinate numbers by DrawingEditorCodec.numbers.
        if var shape = DrawingEditorShape(chunk: trimmedLine) {
            shape.strokeColor = rawValue
            return shape.encodedChunk
        }

        // Fallback for unrecognised lines: text-level token replacement
        let filteredTokens = trimmedLine
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                let lower = token.lowercased()
                return !(lower.hasPrefix("color=") || lower.hasPrefix("stroke=") || lower.hasPrefix("pen="))
            }
        guard let rawValue else { return filteredTokens.joined(separator: " ") }
        let colorToken = String(format: "color=%06X", rawValue & 0xFFFFFF)
        return (filteredTokens + [colorToken]).joined(separator: " ")
    }

    func arrangeCards() {
        if arrangeMode == "None" {
            // Toggle: switch to Link
            arrangeMode = "Link"
        } else {
            // Toggle: switch to None
            arrangeMode = "None"
        }
    }

    func applyBrowserAutoArrangeStepIfNeeded(force: Bool = false) {
        guard selectedTab == .browser else { return }
        guard browserAutoArrangeEnabled || force else { return }
        guard force || (!shouldSuspendBrowserAutoArrangeForCurrentGesture && CACurrentMediaTime() >= browserAutoArrangeSuspendedUntil) else { return }
        let stepScale = browserAutoArrangeStepScale()

        switch arrangeMode {
        case "Normalize":
            applyBrowserNormalizeArrangeStep()
        case "Repulsion":
            applyBrowserRepulsionAutoArrangeStep(stepScale: stepScale)
        case "Link":
            applyBrowserLinkAutoArrangeStep(stepScale: stepScale)
        case "Link(Soft)":
            applyBrowserLinkAutoArrangeStep(ratio: 0.33, stepScale: stepScale)
        case "Label":
            applyBrowserLabelAutoArrangeStep(stepScale: stepScale)
        case "Label(Soft)":
            applyBrowserLabelAutoArrangeStep(stepScale: stepScale * 0.33)
        case "Index":
            applyBrowserIndexAutoArrangeStep(stepScale: stepScale)
        case "Index(Soft)":
            applyBrowserIndexAutoArrangeStep(stepScale: stepScale * 0.33)
        case "Matrix":
            applyBrowserMatrixAutoArrangeStep(stepScale: stepScale)
        case "Index(Matrix)":
            applyBrowserMatrixAutoArrangeStep(stepScale: stepScale, rectifiesCircularLayout: true)
        case "Similarity":
            applyBrowserSimilarityAutoArrangeStep(stepScale: stepScale)
        case "Similarity(Soft)":
            applyBrowserSimilarityAutoArrangeStep(stepScale: stepScale * 0.33)
        case "Tree":
            applyBrowserTreeAutoArrangeStep(stepScale: stepScale)
        default:
            break
        }
    }

    func applyBrowserLegacyArrangeMode() {
        let cardIDs = sortedCards().map { $0.id }
        let count = max(cardIDs.count, 1)
        for (index, cardID) in cardIDs.enumerated() {
            let angle = Double(index) / Double(count) * .pi * 2
            let radius = 0.28
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
        noteDocumentMutation(status: "Arranged cards using \(arrangeMode)")
    }

    func resetBrowserArrangeTransientState() {
        browserMatrixTargetByCardID.removeAll(keepingCapacity: true)
        browserMatrixSpeedByCardID.removeAll(keepingCapacity: true)
    }

    func applyBrowserLinkAutoArrangeStep(ratio: Double = 1.0, stepScale: Double = 1.0) {
        let visibleCards = browserArrangeUniqueCards(visibleSortedCards())
        guard visibleCards.count > 1 else { return }
        let freezeSelectedCards = hasActiveBrowserGesture

        let positions = browserArrangePositionsByCardID(visibleCards)
        let baseLinkRatio = ratio * 0.66 * 0.3
        let linkRatio = 1 - pow(max(1 - baseLinkRatio, 0.0001), stepScale)
        var nextPositions = browserRepulsedPositions(for: visibleCards, stepScale: stepScale, ratio: 0.5)

        var linkedAverageByCardID: [Int: FrievePoint] = [:]
        for card in visibleCards where !card.isFixed && !(freezeSelectedCards && selectedCardIDs.contains(card.id)) {
            let neighbors = linksForCard(card.id)
                .compactMap { link -> Int? in
                    if link.fromCardID == card.id { return link.toCardID }
                    if link.toCardID == card.id { return link.fromCardID }
                    return nil
                }
                .filter { positions[$0] != nil && $0 != card.id }

            guard !neighbors.isEmpty else { continue }
            let uniqueNeighbors = Array(Set(neighbors))
            let sum = uniqueNeighbors.reduce(into: FrievePoint(x: 0, y: 0)) { partial, id in
                if let point = positions[id] {
                    partial.x += point.x
                    partial.y += point.y
                }
            }
            let count = Double(uniqueNeighbors.count)
            linkedAverageByCardID[card.id] = FrievePoint(x: sum.x / count, y: sum.y / count)
        }

        for card in visibleCards where !card.isFixed && !(freezeSelectedCards && selectedCardIDs.contains(card.id)) {
            guard let current = nextPositions[card.id], let linkedAverage = linkedAverageByCardID[card.id] else { continue }
            nextPositions[card.id] = FrievePoint(
                x: linkedAverage.x * linkRatio + current.x * (1 - linkRatio),
                y: linkedAverage.y * linkRatio + current.y * (1 - linkRatio)
            )
        }

        let targetIDs = Set(visibleCards
            .filter { !$0.isFixed && !(freezeSelectedCards && selectedCardIDs.contains($0.id)) }
            .map(\.id))
        guard !targetIDs.isEmpty else { return }

        normalizeAndApplyBrowserAutoArrangePositions(nextPositions, targetIDs: targetIDs)
    }

    func applyBrowserNormalizeArrangeStep(using randomUnit: () -> Double = { Double.random(in: 0 ... 1) }) {
        let visibleCards = browserArrangeUniqueCards(visibleSortedCards())
        let targetIDs = Set(visibleCards.map(\.id))
        guard !targetIDs.isEmpty else { return }
        let positions = preparedBrowserNormalizePositions(for: visibleCards, randomUnit: randomUnit)
        normalizeAndApplyBrowserAutoArrangePositions(positions, targetIDs: targetIDs, boundsIDs: targetIDs)
    }

    func applyBrowserRepulsionAutoArrangeStep(stepScale: Double = 1.0, ratio: Double = 1.0) {
        let visibleCards = browserArrangeUniqueCards(visibleSortedCards())
        guard visibleCards.count > 1 else { return }
        let targetIDs = Set(visibleCards.filter { !$0.isFixed && !(hasActiveBrowserGesture && selectedCardIDs.contains($0.id)) }.map(\.id))
        guard !targetIDs.isEmpty else { return }
        let nextPositions = browserRepulsedPositions(for: visibleCards, stepScale: stepScale, ratio: ratio)
        normalizeAndApplyBrowserAutoArrangePositions(nextPositions, targetIDs: targetIDs)
    }

    func browserRepulsedPositions(for visibleCards: [FrieveCard], stepScale: Double, ratio: Double) -> [Int: FrievePoint] {
        let visibleCards = browserArrangeUniqueCards(visibleCards)
        let freezeSelectedCards = hasActiveBrowserGesture
        let positions = browserArrangePositionsByCardID(visibleCards)
        var nextPositions = positions

        for card in visibleCards where !card.isFixed && !(freezeSelectedCards && selectedCardIDs.contains(card.id)) {
            guard let original = positions[card.id] else { continue }
            var repelX = 0.0
            var repelY = 0.0
            var repelWeight = 0.0
            var repelCount = 0

            for other in visibleCards where other.id != card.id {
                guard let otherPosition = positions[other.id] else { continue }
                let fx = original.x - otherPosition.x
                let fy = original.y - otherPosition.y
                let distanceSquared = fx * fx + fy * fy
                if distanceSquared > 0.0 {
                    let w = sqrt(100.0 / distanceSquared)
                    repelX += fx * w
                    repelY += fy * w
                    repelWeight += 1.0
                    repelCount += 1
                } else {
                    repelX += Double.random(in: -0.005 ... 0.005)
                    repelY += Double.random(in: -0.005 ... 0.005)
                    repelWeight += 1.0
                    repelCount += 1
                }
            }

            if repelWeight > 0, repelCount > 0 {
                let weight = repelWeight / Double(repelCount * repelCount) / 5.0 * ratio * stepScale
                nextPositions[card.id] = FrievePoint(
                    x: original.x + repelX * weight,
                    y: original.y + repelY * weight
                )
            }
        }

        return nextPositions
    }

    func applyBrowserLabelAutoArrangeStep(stepScale: Double = 1.0) {
        let orderedCards = browserAutoArrangeCardsInDocumentOrder().sorted { lhs, rhs in
            let lhsLabel = cardLabelNames(for: lhs).first ?? ""
            let rhsLabel = cardLabelNames(for: rhs).first ?? ""
            if lhsLabel != rhsLabel { return lhsLabel.localizedStandardCompare(rhsLabel) == .orderedAscending }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        applyBrowserOrderedTargetArrangeStep(cards: orderedCards, stepScale: stepScale)
    }

    func applyBrowserIndexAutoArrangeStep(stepScale: Double = 1.0) {
        applyBrowserOrderedTargetArrangeStep(cards: browserAutoArrangeCardsInDocumentOrder(), stepScale: stepScale)
    }

    func applyBrowserSimilarityAutoArrangeStep(stepScale: Double = 1.0) {
        let visibleCards = browserArrangeUniqueCards(visibleSortedCards())
        guard visibleCards.count > 1 else { return }
        let freezeSelectedCards = hasActiveBrowserGesture
        let positions = browserRepulsedPositions(for: visibleCards, stepScale: stepScale, ratio: 0.5)
        var nextPositions = positions
        let linkNeighborSets = browserArrangeNeighborSetsByCardID(visibleCards)
        let blend = 1 - pow(0.5, stepScale)

        for card in visibleCards where !card.isFixed && !(freezeSelectedCards && selectedCardIDs.contains(card.id)) {
            var totalWeight = 0.0
            var sum = FrievePoint(x: 0, y: 0)
            let cardLabels = Set(card.labelIDs)
            let cardNeighbors = linkNeighborSets[card.id] ?? []

            for other in visibleCards where other.id != card.id {
                let sharedLabels = Double(cardLabels.intersection(other.labelIDs).count)
                let sharedNeighbors = Double(cardNeighbors.intersection(linkNeighborSets[other.id] ?? []).count)
                let weight = sharedLabels * 1.6 + sharedNeighbors * 0.8
                guard weight > 0, let position = positions[other.id] else { continue }
                totalWeight += weight
                sum.x += position.x * weight
                sum.y += position.y * weight
            }

            guard totalWeight > 0, let current = nextPositions[card.id] else { continue }
            let target = FrievePoint(x: sum.x / totalWeight, y: sum.y / totalWeight)
            nextPositions[card.id] = FrievePoint(
                x: current.x * (1 - blend) + target.x * blend,
                y: current.y * (1 - blend) + target.y * blend
            )
        }

        let targetIDs = Set(visibleCards.filter { !$0.isFixed && !(freezeSelectedCards && selectedCardIDs.contains($0.id)) }.map(\.id))
        guard !targetIDs.isEmpty else { return }
        normalizeAndApplyBrowserAutoArrangePositions(nextPositions, targetIDs: targetIDs)
    }

    func applyBrowserOrderedTargetArrangeStep(cards: [FrieveCard], stepScale: Double = 1.0) {
        guard !cards.isEmpty else { return }
        let aspectRatio = browserMatrixAspectRatio(for: cards)
        let dimensions = browserMatrixDimensions(count: cards.count, aspectRatio: aspectRatio)
        let width = max(dimensions.width, 1)
        let height = max(dimensions.height, 1)

        var targets: [Int: FrievePoint] = [:]
        targets.reserveCapacity(cards.count)
        for (index, card) in cards.enumerated() {
            let x = index % width
            let y = index / width
            targets[card.id] = FrievePoint(
                x: width > 1 ? Double(x) / Double(width - 1) : 0.5,
                y: height > 1 ? Double(y) / Double(height - 1) : 0.5
            )
        }
        blendAndApplyBrowserAutoArrangeTargets(targets, cards: cards, stepScale: stepScale)
    }

    func blendAndApplyBrowserAutoArrangeTargets(_ targets: [Int: FrievePoint], cards: [FrieveCard], stepScale: Double = 1.0) {
        let freezeSelectedCards = hasActiveBrowserGesture
        let blend = 1 - pow(0.5, stepScale)
        var changed = false

        for card in cards {
            guard let target = targets[card.id] else { continue }
            if card.isFixed || (freezeSelectedCards && selectedCardIDs.contains(card.id)) {
                continue
            }

            let next = FrievePoint(
                x: card.position.x * (1 - blend) + target.x * blend,
                y: card.position.y * (1 - blend) + target.y * blend
            )
            guard next != card.position else { continue }
            changed = true
            document.updateCard(card.id) { targetCard in
                targetCard.position = next
            }
        }

        guard changed else { return }
        finalizeBrowserAutoArrangeMutation()
    }

    func applyBrowserMatrixAutoArrangeStep(stepScale: Double = 1.0, rectifiesCircularLayout: Bool = false) {
        let visibleCards = browserAutoArrangeCardsInDocumentOrder()
        guard !visibleCards.isEmpty else { return }

        let targets = computeBrowserMatrixTargets(for: visibleCards, rectifiesCircularLayout: rectifiesCircularLayout)
        guard !targets.isEmpty else { return }

        let freezeSelectedCards = hasActiveBrowserGesture
        var changed = false
        for card in visibleCards {
            guard let target = targets[card.id] else { continue }

            let previousTarget = browserMatrixTargetByCardID[card.id]
            browserMatrixTargetByCardID[card.id] = target
            if previousTarget != target {
                browserMatrixSpeedByCardID[card.id] = 0.0
            }

            if card.isFixed || (freezeSelectedCards && selectedCardIDs.contains(card.id)) {
                continue
            }

            let speed = min((browserMatrixSpeedByCardID[card.id] ?? 0.0) + 0.1 * stepScale, 0.5)
            browserMatrixSpeedByCardID[card.id] = speed
            let blend = 1 - pow(max(1 - speed, 0.0001), stepScale)
            let next = FrievePoint(
                x: card.position.x * (1 - blend) + target.x * blend,
                y: card.position.y * (1 - blend) + target.y * blend
            )
            if next != card.position {
                changed = true
                document.updateCard(card.id) { targetCard in
                    targetCard.position = next
                }
            }
        }

        for cardID in Array(browserMatrixTargetByCardID.keys) where targets[cardID] == nil {
            browserMatrixTargetByCardID.removeValue(forKey: cardID)
            browserMatrixSpeedByCardID.removeValue(forKey: cardID)
        }

        guard changed else { return }
        finalizeBrowserAutoArrangeMutation()
    }

    func applyBrowserTreeAutoArrangeStep(stepScale: Double = 1.0, ratio: Double = 1.0) {
        let visibleCards = browserAutoArrangeCardsInDocumentOrder()
        guard !visibleCards.isEmpty else { return }

        let targetPositions = computeBrowserTreeTargets(for: visibleCards, ratio: ratio)
        guard !targetPositions.isEmpty else { return }

        let draggedTargetID = hasActiveBrowserGesture ? selectedCardID : nil
        let blend = 1 - pow(0.5, stepScale)
        var changed = false
        for card in visibleCards {
            guard let target = targetPositions[card.id] else { continue }

            let next: FrievePoint
            if card.isFixed || (draggedTargetID == card.id) {
                next = card.position
            } else {
                next = FrievePoint(
                    x: card.position.x * (1 - blend) + target.x * blend,
                    y: card.position.y * (1 - blend) + target.y * blend
                )
            }

            if next != card.position {
                changed = true
                document.updateCard(card.id) { targetCard in
                    targetCard.position = next
                }
            }
        }

        guard changed else { return }
        finalizeBrowserAutoArrangeMutation()
    }

    func normalizeAndApplyBrowserAutoArrangePositions(
        _ positions: [Int: FrievePoint],
        targetIDs: Set<Int>,
        boundsIDs: Set<Int>? = nil
    ) {
        let boundPoints = (boundsIDs ?? targetIDs).compactMap { positions[$0] }
        guard let minX = boundPoints.map(\.x).min(),
              let maxX = boundPoints.map(\.x).max(),
              let minY = boundPoints.map(\.y).min(),
              let maxY = boundPoints.map(\.y).max(),
              maxX != minX,
              maxY != minY else {
            return
        }

        var changed = false
        for cardID in targetIDs {
            guard let point = positions[cardID] else { continue }
            let normalized = FrievePoint(
                x: (point.x - minX) / (maxX - minX),
                y: (point.y - minY) / (maxY - minY)
            )
            guard let current = document.card(withID: cardID)?.position, current != normalized else {
                continue
            }
            changed = true
            document.updateCard(cardID) { card in
                card.position = normalized
            }
        }

        guard changed else { return }
        finalizeBrowserAutoArrangeMutation()
    }

    func preparedBrowserNormalizePositions(
        for visibleCards: [FrieveCard],
        randomUnit: () -> Double = { Double.random(in: 0 ... 1) }
    ) -> [Int: FrievePoint] {
        let visibleCards = browserArrangeUniqueCards(visibleCards)
        var positions = browserArrangePositionsByCardID(visibleCards)
        guard visibleCards.count > 1 else { return positions }

        let rawBounds = visibleCards.reduce(into: (minX: 0.5, maxX: 0.5, minY: 0.5, maxY: 0.5, initialized: false)) { partial, card in
            if !partial.initialized {
                partial.minX = card.position.x
                partial.maxX = card.position.x
                partial.minY = card.position.y
                partial.maxY = card.position.y
                partial.initialized = true
            } else {
                partial.minX = min(partial.minX, card.position.x)
                partial.maxX = max(partial.maxX, card.position.x)
                partial.minY = min(partial.minY, card.position.y)
                partial.maxY = max(partial.maxY, card.position.y)
            }
        }
        guard rawBounds.maxX == rawBounds.minX || rawBounds.maxY == rawBounds.minY else {
            return positions
        }

        for card in visibleCards where !card.isFixed {
            positions[card.id] = FrievePoint(
                x: min(max((randomUnit() * 0.9999), 0), 0.9999),
                y: min(max((randomUnit() * 0.9999), 0), 0.9999)
            )
        }
        return positions
    }

    func browserVisibleCardsInDocumentOrder() -> [FrieveCard] {
        document.cards.filter(\.visible)
    }

    func browserArrangeUniqueCards(_ cards: [FrieveCard]) -> [FrieveCard] {
        var seenCardIDs = Set<Int>()
        var uniqueCards: [FrieveCard] = []
        uniqueCards.reserveCapacity(cards.count)

        for card in cards {
            guard seenCardIDs.insert(card.id).inserted else { continue }
            uniqueCards.append(card)
        }

        return uniqueCards
    }

    func browserArrangePositionsByCardID(_ cards: [FrieveCard]) -> [Int: FrievePoint] {
        var positionsByID: [Int: FrievePoint] = [:]
        positionsByID.reserveCapacity(cards.count)
        for card in cards where positionsByID[card.id] == nil {
            positionsByID[card.id] = card.position
        }
        return positionsByID
    }

    func browserArrangeNeighborSetsByCardID(_ cards: [FrieveCard]) -> [Int: Set<Int>] {
        var neighborSetsByID: [Int: Set<Int>] = [:]
        neighborSetsByID.reserveCapacity(cards.count)
        for card in cards where neighborSetsByID[card.id] == nil {
            neighborSetsByID[card.id] = Set(
                linksForCard(card.id)
                    .flatMap { [$0.fromCardID, $0.toCardID] }
                    .filter { $0 != card.id }
            )
        }
        return neighborSetsByID
    }

    func browserAutoArrangeCardsInDocumentOrder() -> [FrieveCard] {
        browserArrangeUniqueCards(browserVisibleCardsInDocumentOrder())
    }

    func browserArrangeBounds(for cards: [FrieveCard]) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        guard let first = cards.first else {
            return (0.0, 1.0, 0.0, 1.0)
        }

        var minX = first.position.x
        var maxX = first.position.x
        var minY = first.position.y
        var maxY = first.position.y
        for card in cards.dropFirst() {
            minX = min(minX, card.position.x)
            maxX = max(maxX, card.position.x)
            minY = min(minY, card.position.y)
            maxY = max(maxY, card.position.y)
        }
        if minX == maxX {
            maxX += 1.0
        }
        if minY == maxY {
            maxY += 1.0
        }
        return (minX, maxX, minY, maxY)
    }

    func browserViewedOrderByCardID() -> [Int: Int] {
        let viewedOrder = document.cards.enumerated().sorted { lhs, rhs in
            if lhs.element.viewed != rhs.element.viewed {
                return lhs.element.viewed < rhs.element.viewed
            }
            return lhs.offset < rhs.offset
        }

        var result: [Int: Int] = [:]
        result.reserveCapacity(viewedOrder.count)
        for (order, entry) in viewedOrder.enumerated() {
            result[entry.element.id] = order
        }
        return result
    }

    func browserRelatedCardIDs(for selectedID: Int?, visibleIDs: Set<Int>) -> Set<Int> {
        guard let selectedID, visibleIDs.contains(selectedID) else { return [] }
        return Set(
            linksForCard(selectedID)
                .flatMap { [$0.fromCardID, $0.toCardID] }
                .filter { $0 != selectedID && visibleIDs.contains($0) }
        )
    }

    func computeBrowserMatrixTargets(for cards: [FrieveCard], rectifiesCircularLayout: Bool = false) -> [Int: FrievePoint] {
        let cards = browserArrangeUniqueCards(cards)
        guard !cards.isEmpty else { return [:] }

        let visibleIDs = Set(cards.map(\.id))
        let positionsByID = browserArrangePositionsByCardID(cards)
        let bounds = browserArrangeBounds(for: cards)
        let selectedID = selectedCardID.flatMap { visibleIDs.contains($0) ? $0 : nil }
        let relatedIDs = browserRelatedCardIDs(for: selectedID, visibleIDs: visibleIDs)
        let fixedIDs = Set(cards.filter(\.isFixed).map(\.id))
        let viewedOrderByID = browserViewedOrderByCardID()
        let viewedDescendingIDs = document.cards.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = viewedOrderByID[lhs.element.id] ?? lhs.offset
                let rhsOrder = viewedOrderByID[rhs.element.id] ?? rhs.offset
                if lhsOrder != rhsOrder {
                    return lhsOrder > rhsOrder
                }
                return lhs.offset > rhs.offset
            }
            .map(\.element.id)

        let fixedOrderedIDs = viewedDescendingIDs.filter { id in
            visibleIDs.contains(id) && fixedIDs.contains(id) && id != selectedID
        }
        let selectedOrderedIDs = selectedID.map { [$0] } ?? []
        let relatedOrderedIDs = document.cards.reversed().map(\.id).filter { id in
            visibleIDs.contains(id) && relatedIDs.contains(id) && id != selectedID && !fixedIDs.contains(id)
        }
        let otherOrderedIDs = viewedDescendingIDs.filter { id in
            visibleIDs.contains(id) && !fixedIDs.contains(id) && !relatedIDs.contains(id) && id != selectedID
        }
        let orderedIDs = fixedOrderedIDs + selectedOrderedIDs + relatedOrderedIDs + otherOrderedIDs

        let aspectRatio = browserMatrixAspectRatio(for: cards)
        let dimensions = browserMatrixDimensions(count: cards.count, aspectRatio: aspectRatio)
        let width = max(dimensions.width, 1)
        let height = max(dimensions.height, 1)
        var grid = Array(repeating: -1, count: width * height)
        var targetsByID: [Int: FrievePoint] = [:]
        targetsByID.reserveCapacity(orderedIDs.count)

        for id in orderedIDs {
            guard let position = positionsByID[id] else { continue }
            var normalized = FrievePoint(
                x: (position.x - bounds.minX) / (bounds.maxX - bounds.minX),
                y: (position.y - bounds.minY) / (bounds.maxY - bounds.minY)
            )
            if rectifiesCircularLayout {
                normalized = rectifiedBrowserMatrixPoint(normalized)
            }
            guard let cellIndex = nearestEmptyBrowserMatrixCell(to: normalized, width: width, height: height, grid: grid) else {
                continue
            }
            grid[cellIndex] = id
            let x = cellIndex % width
            let y = cellIndex / width
            targetsByID[id] = FrievePoint(
                x: width > 1 ? Double(x) / Double(width - 1) : 0.5,
                y: height > 1 ? Double(y) / Double(height - 1) : 0.5
            )
        }

        return targetsByID
    }

    func rectifiedBrowserMatrixPoint(_ point: FrievePoint) -> FrievePoint {
        let x = point.x - 0.5
        let y = point.y - 0.5
        let angle = atan2(y, x)
        var radialAngle = (angle + (.pi * 2)).truncatingRemainder(dividingBy: .pi / 2)
        if radialAngle > .pi / 4 {
            radialAngle = (.pi / 2) - radialAngle
        }
        let coefficient = 1.0 / cos(radialAngle)
        return FrievePoint(
            x: x * coefficient + 0.5,
            y: y * coefficient + 0.5
        )
    }

    func browserMatrixAspectRatio(for cards: [FrieveCard]) -> Double {
        let canvasSize = browserCanvasSize == .zero ? CGSize(width: 1200, height: 800) : browserCanvasSize
        let widthSum = cards.reduce(0.0) { partial, card in
            partial + Double(cardCanvasSize(for: card).width)
        }
        let heightSum = cards.reduce(0.0) { partial, card in
            partial + Double(cardCanvasSize(for: card).height)
        }
        guard widthSum > 0, heightSum > 0, canvasSize.width > 0, canvasSize.height > 0 else { return 1.0 }
        return sqrt((heightSum / Double(canvasSize.height)) / (widthSum / Double(canvasSize.width)))
    }

    func browserMatrixDimensions(count: Int, aspectRatio: Double) -> (width: Int, height: Int) {
        var width = 1
        var height = 1
        let ratio = max(aspectRatio, 0.0001)
        while count > width * height {
            if Double(width) <= Double(height) * ratio {
                width += 2
            } else {
                height += 2
            }
        }
        return (width, height)
    }

    func nearestEmptyBrowserMatrixCell(to point: FrievePoint, width: Int, height: Int, grid: [Int]) -> Int? {
        var bestIndex: Int?
        var bestDistance = Double(width + height)
        for y in 0..<height {
            for x in 0..<width {
                let index = x + y * width
                guard grid[index] == -1 else { continue }
                let distance = abs(point.x * Double(width - 1) - Double(x)) + abs(point.y * Double(height - 1) - Double(y))
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
        }
        return bestIndex
    }

    func browserTreeHierarchy(for cards: [FrieveCard]) -> (orderedIDs: [Int], levelsByID: [Int: Int], parentByID: [Int: Int]) {
        let cards = browserArrangeUniqueCards(cards)
        let originalIDs = cards.map(\.id)
        var originalIndexByID: [Int: Int] = [:]
        for (index, id) in originalIDs.enumerated() where originalIndexByID[id] == nil {
            originalIndexByID[id] = index
        }
        let topIDs = Set(cards.filter(\.isTop).map(\.id))

        var parentIndicesByChildIndex: [Int: [Int]] = [:]
        for link in document.links where link.directionVisible {
            guard let fromIndex = originalIndexByID[link.fromCardID], let toIndex = originalIndexByID[link.toCardID] else {
                continue
            }
            parentIndicesByChildIndex[toIndex, default: []].append(fromIndex)
        }
        for index in parentIndicesByChildIndex.keys {
            parentIndicesByChildIndex[index]?.sort()
        }

        var levelsByID = Dictionary(uniqueKeysWithValues: originalIDs.map { ($0, 0) })
        var parentByID: [Int: Int] = [:]
        var changed = true
        var level = 1
        while changed {
            changed = false
            for (index, cardID) in originalIDs.enumerated() {
                if topIDs.contains(cardID) || (levelsByID[cardID] ?? 0) != 0 || parentByID[cardID] != nil {
                    continue
                }
                let parentIndices = parentIndicesByChildIndex[index] ?? []
                guard !parentIndices.isEmpty else { continue }

                var startPosition = 0
                for (offset, parentIndex) in parentIndices.enumerated() {
                    if parentIndex < index {
                        startPosition = offset
                    } else {
                        break
                    }
                }

                var cursor = startPosition
                var remaining = parentIndices.count
                var assignedParentID: Int?
                while remaining > 0 {
                    let parentIndex = parentIndices[cursor]
                    let parentID = originalIDs[parentIndex]
                    let parentLevel = levelsByID[parentID] ?? 0
                    if parentIndex != index && (topIDs.contains(parentID) || (parentLevel > 0 && parentLevel == level - 1)) {
                        assignedParentID = parentID
                        break
                    }
                    cursor = (cursor + parentIndices.count - 1) % parentIndices.count
                    remaining -= 1
                }

                if let assignedParentID {
                    levelsByID[cardID] = level
                    parentByID[cardID] = assignedParentID
                    changed = true
                }
            }
            level += 1
        }
        let maxLevel = level

        var orderedIDs = originalIDs
        for index in 1..<orderedIDs.count {
            let cardID = orderedIDs[index]
            guard topIDs.contains(cardID) else { continue }
            var currentIndex = index
            while currentIndex > 0 && !topIDs.contains(orderedIDs[currentIndex - 1]) {
                orderedIDs.swapAt(currentIndex, currentIndex - 1)
                currentIndex -= 1
            }
        }

        var currentLevel = 0
        var moved = true
        while moved || currentLevel <= maxLevel {
            moved = false
            var index = 0
            while index < orderedIDs.count {
                let cardID = orderedIDs[index]
                let cardLevel = levelsByID[cardID] ?? 0
                let isParentCard = (topIDs.contains(cardID) && currentLevel == 0) || (cardLevel == currentLevel && cardLevel > 0)
                if isParentCard {
                    var insertIndex = index + 1
                    var childIndex = 0
                    while childIndex < orderedIDs.count {
                        let childID = orderedIDs[childIndex]
                        if parentByID[childID] == cardID {
                            if childIndex < insertIndex {
                                // Already before the insertion point.
                            } else if childIndex > insertIndex {
                                let movedChildID = orderedIDs.remove(at: childIndex)
                                orderedIDs.insert(movedChildID, at: insertIndex)
                                insertIndex += 1
                                moved = true
                                childIndex -= 1
                                index += 1
                            } else {
                                insertIndex += 1
                            }
                        }
                        childIndex += 1
                    }
                }
                index += 1
            }
            currentLevel += 1
        }

        return (orderedIDs, levelsByID, parentByID)
    }

    func computeBrowserTreeTargets(for cards: [FrieveCard], ratio: Double = 1.0) -> [Int: FrievePoint] {
        let cards = browserArrangeUniqueCards(cards)
        guard !cards.isEmpty else { return [:] }

        let hierarchy = browserTreeHierarchy(for: cards)
        let orderedIDs = hierarchy.orderedIDs
        guard !orderedIDs.isEmpty else { return [:] }

        var positions = browserArrangePositionsByCardID(cards)
        var nodeGroupByID: [Int: Int] = [:]
        var nodeHeightByID = Dictionary(uniqueKeysWithValues: orderedIDs.map { ($0, 0) })
        let visibleCount = max(orderedIDs.count + 1, 1)
        let xspan = 1.0 / sqrt(Double(visibleCount))
        let yspan = 1.0 / sqrt(Double(visibleCount))
        let adjustedRatio = ratio * 0.25
        var groupCount = 0

        for rootIndex in orderedIDs.indices {
            let rootID = orderedIDs[rootIndex]
            guard (hierarchy.levelsByID[rootID] ?? 0) == 0 else { continue }

            nodeGroupByID[rootID] = groupCount
            var maxLevel = 0
            var endIndex = rootIndex + 1
            while endIndex < orderedIDs.count {
                let nodeID = orderedIDs[endIndex]
                let nodeLevel = hierarchy.levelsByID[nodeID] ?? 0
                if nodeLevel == 0 {
                    break
                }
                maxLevel = max(maxLevel, nodeLevel)
                nodeGroupByID[nodeID] = groupCount
                endIndex += 1
            }

            for level in stride(from: maxLevel, through: 0, by: -1) {
                for nodeIndex in rootIndex..<endIndex {
                    let nodeID = orderedIDs[nodeIndex]
                    guard (hierarchy.levelsByID[nodeID] ?? 0) == level else { continue }

                    var subtreeHeight = 0
                    var childIndex = nodeIndex + 1
                    while childIndex < orderedIDs.count {
                        let childID = orderedIDs[childIndex]
                        let childLevel = hierarchy.levelsByID[childID] ?? 0
                        if childLevel < level + 1 {
                            break
                        }
                        if childLevel == level + 1 {
                            subtreeHeight += nodeHeightByID[childID] ?? 0
                        }
                        childIndex += 1
                    }
                    nodeHeightByID[nodeID] = max(subtreeHeight, 1)
                }
            }

            if maxLevel >= 1 {
                for level in 1...maxLevel {
                    var processedHeight = 0
                    var lastRootID: Int?
                    var lastRootIndex = -1
                    var rightCount = 0
                    var rightHeight = 0
                    var rightHeightSum = 0

                    for nodeIndex in rootIndex..<endIndex {
                        let nodeID = orderedIDs[nodeIndex]
                        let nodeLevel = hierarchy.levelsByID[nodeID] ?? 0
                        if nodeLevel == level - 1 {
                            lastRootID = nodeID
                            lastRootIndex = nodeIndex
                            processedHeight = 0
                            if level == 1 {
                                rightCount = 0
                                rightHeight = 0
                                rightHeightSum = 0
                                var sum = 0
                                for candidateIndex in rootIndex..<endIndex {
                                    let candidateID = orderedIDs[candidateIndex]
                                    guard (hierarchy.levelsByID[candidateID] ?? 0) == level else { continue }
                                    let candidateHeight = nodeHeightByID[candidateID] ?? 0
                                    let parentHeight = nodeHeightByID[nodeID] ?? 0
                                    if abs((sum + candidateHeight) * 2 - parentHeight) <= abs(sum * 2 - parentHeight) {
                                        rightCount += 1
                                        sum += candidateHeight
                                    } else {
                                        break
                                    }
                                }
                                rightHeight = sum
                            }
                            continue
                        }

                        guard nodeLevel == level,
                              let parentID = lastRootID,
                              let parentPosition = positions[parentID] else {
                            continue
                        }

                        let currentHeight = Double(nodeHeightByID[nodeID] ?? 0)
                        if parentID == rootID {
                            let parentHeight = Double(nodeHeightByID[parentID] ?? 0)
                            if rightCount > 0 {
                                positions[nodeID] = FrievePoint(
                                    x: parentPosition.x + xspan,
                                    y: parentPosition.y + (-Double(rightHeight) * 0.5 + Double(rightHeightSum) + currentHeight * 0.5) * yspan
                                )
                                rightCount -= 1
                                rightHeightSum += nodeHeightByID[nodeID] ?? 0
                            } else {
                                positions[nodeID] = FrievePoint(
                                    x: parentPosition.x - xspan,
                                    y: parentPosition.y + (-(parentHeight - Double(rightHeight)) * 0.5 + Double(processedHeight) + currentHeight * 0.5) * yspan
                                )
                                processedHeight += nodeHeightByID[nodeID] ?? 0
                            }
                        } else {
                            let rootPosition = positions[rootID] ?? parentPosition
                            let parentHeight = Double(nodeHeightByID[parentID] ?? 0)
                            positions[nodeID] = FrievePoint(
                                x: parentPosition.x + (parentPosition.x > rootPosition.x ? xspan : -xspan),
                                y: parentPosition.y + (-parentHeight * 0.5 + Double(processedHeight) + currentHeight * 0.5) * yspan
                            )
                            processedHeight += nodeHeightByID[nodeID] ?? 0
                        }

                        if lastRootIndex == nodeIndex {
                            processedHeight = 0
                        }
                    }
                }
            }

            groupCount += 1
        }

        if groupCount > 0 {
            let groupMembers = Dictionary(grouping: orderedIDs, by: { nodeGroupByID[$0] ?? 0 })
            var groupCenters: [Int: FrievePoint] = [:]
            var groupSizes: [Int: CGSize] = [:]

            for groupIndex in 0..<groupCount {
                let memberIDs = groupMembers[groupIndex] ?? []
                guard let firstID = memberIDs.first, let firstPosition = positions[firstID] else { continue }

                var minX = firstPosition.x
                var maxX = firstPosition.x
                var minY = firstPosition.y
                var maxY = firstPosition.y
                for memberID in memberIDs.dropFirst() {
                    guard let point = positions[memberID] else { continue }
                    minX = min(minX, point.x)
                    maxX = max(maxX, point.x)
                    minY = min(minY, point.y)
                    maxY = max(maxY, point.y)
                }

                groupCenters[groupIndex] = FrievePoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
                if abs(minX - maxX) < 0.01 {
                    groupSizes[groupIndex] = CGSize(width: xspan, height: yspan)
                } else {
                    groupSizes[groupIndex] = CGSize(width: maxX - minX, height: maxY - minY)
                }
            }

            for groupIndex in 0..<groupCount {
                guard let center = groupCenters[groupIndex] else { continue }

                var deltaX = 0.0
                var deltaY = 0.0
                var weight = 0.0
                var count = 0
                for otherGroupIndex in 0..<groupCount where otherGroupIndex != groupIndex {
                    guard let otherCenter = groupCenters[otherGroupIndex],
                          let groupSize = groupSizes[groupIndex],
                          let otherGroupSize = groupSizes[otherGroupIndex] else {
                        continue
                    }

                    let fx = center.x - otherCenter.x
                    let fy = center.y - otherCenter.y
                    let distanceSquared = fx * fx + fy * fy
                    guard distanceSquared > 0.0 else { continue }

                    let wx = (groupSize.width + otherGroupSize.width) / distanceSquared
                    let wy = (groupSize.height + otherGroupSize.height) / distanceSquared
                    deltaX += fx * wx
                    deltaY += fy * wy
                    weight += 1.0
                    count += 1
                }

                guard weight > 0.0, count > 0 else { continue }
                let scaledWeight = weight / Double(count * count) / 5.0 * adjustedRatio
                let moveX = deltaX * scaledWeight * 10.0
                let moveY = deltaY * scaledWeight * 10.0
                for memberID in groupMembers[groupIndex] ?? [] {
                    guard var point = positions[memberID] else { continue }
                    point.x += moveX
                    point.y += moveY
                    positions[memberID] = point
                }
            }

            let points = orderedIDs.compactMap { positions[$0] }
            if let minX = points.map(\.x).min(),
               let maxX = points.map(\.x).max(),
               let minY = points.map(\.y).min(),
               let maxY = points.map(\.y).max(),
               abs(minX - maxX) > 0.01,
               abs(minY - maxY) > 0.01 {
                for cardID in orderedIDs {
                    guard let point = positions[cardID] else { continue }
                    positions[cardID] = FrievePoint(
                        x: (point.x - minX) / (maxX - minX),
                        y: (point.y - minY) / (maxY - minY)
                    )
                }
            }
        }

        return positions
    }

    func finalizeBrowserAutoArrangeMutation() {
        hasUnsavedChanges = true
        lastMutationAt = Date()
        syncDocumentMetadataFromSettings()
        markBrowserSurfaceContentDirty()
    }

func browseFrieveSite() {
        if let url = URL(string: "https://www.frieve.com/") {
            NSWorkspace.shared.open(url)
        }
    }

    func browseHelp() {
        if let url = URL(string: "https://www.frieve.com/software/frieve-editor") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkLatestRelease() {
        if let url = URL(string: "https://github.com/yutokun/Frieve-Editor-for-macOS/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Insert Operations

    func insertExtLink() {
        guard selectedCardID != nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Link"
        if panel.runModal() == .OK, let url = panel.url {
            registerUndoCheckpoint()
            applyExternalFileReference(url)
            noteDocumentMutation(status: "Linked external file")
        }
    }

    func applyExternalFileReference(_ url: URL) {
        let path = url.path
        switch externalFileReferenceKind(for: url) {
        case .image:
            updateSelectedCardImagePath(path)
        case .video:
            updateSelectedCardVideoPath(path)
        case .bodyText:
            updateSelectedCardBody { body in
                body.isEmpty ? path : body + "\n" + path
            }
        }
    }

    func externalFileReferenceKind(for url: URL) -> ExternalFileReferenceKind {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return .bodyText
        }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
            return .video
        }
        return .bodyText
    }

    func assignCardLabelToSelection(labelID: Int) {
        let ids = selectedCardIDs.isEmpty ? Set(selectedCardID.map { [$0] } ?? []) : selectedCardIDs
        guard !ids.isEmpty else { return }
        registerUndoCheckpoint()
        for id in ids {
            document.updateCard(id) { card in
                if !card.labelIDs.contains(labelID) {
                    card.labelIDs.append(labelID)
                }
            }
        }
        noteDocumentMutation(status: "Assigned label to selected cards")
    }

    func linkSelectionToAllCardsWithLabel(labelID: Int) {
        guard let selectedID = selectedCardID else { return }
        let targetCards = document.cards.filter { $0.labelIDs.contains(labelID) && $0.id != selectedID }
        guard !targetCards.isEmpty else {
            statusMessage = "No cards with this label"
            return
        }
        registerUndoCheckpoint()
        let existingLinks = Set(document.links.map { "\($0.fromCardID)-\($0.toCardID)" })
        for card in targetCards {
            let key1 = "\(selectedID)-\(card.id)"
            let key2 = "\(card.id)-\(selectedID)"
            if !existingLinks.contains(key1) && !existingLinks.contains(key2) {
                document.links.append(FrieveLink(
                    fromCardID: selectedID, toCardID: card.id,
                    directionVisible: false, shape: 0, labelIDs: [], name: ""
                ))
            }
        }
        noteDocumentMutation(status: "Linked to \(targetCards.count) cards with label")
    }

    func addLabelToAllDestinationCards(labelID: Int) {
        guard let selectedID = selectedCardID else { return }
        let destinationIDs = document.links
            .filter { $0.fromCardID == selectedID || $0.toCardID == selectedID }
            .flatMap { [$0.fromCardID, $0.toCardID] }
            .filter { $0 != selectedID }
        let uniqueIDs = Set(destinationIDs)
        guard !uniqueIDs.isEmpty else {
            statusMessage = "No linked cards"
            return
        }
        registerUndoCheckpoint()
        for id in uniqueIDs {
            document.updateCard(id) { card in
                if !card.labelIDs.contains(labelID) {
                    card.labelIDs.append(labelID)
                }
            }
        }
        noteDocumentMutation(status: "Added label to \(uniqueIDs.count) destination cards")
    }

    func addCardLinkedToAllCardsWithLabel(labelID: Int) {
        guard let label = document.cardLabels.first(where: { $0.id == labelID }) else { return }
        let targetCards = document.cards.filter { $0.labelIDs.contains(labelID) }
        registerUndoCheckpoint()
        let newCardID = document.addCard(title: label.name)
        if !targetCards.isEmpty {
            let averageX = targetCards.map(\.position.x).reduce(0, +) / Double(targetCards.count)
            let averageY = targetCards.map(\.position.y).reduce(0, +) / Double(targetCards.count)
            document.updateCard(newCardID) { card in
                card.position = FrievePoint(x: averageX, y: averageY)
                card.updated = isoTimestamp()
            }
        }
        for target in targetCards where target.id != newCardID {
            appendLinkIfNeeded(from: newCardID, to: target.id, name: "Related")
        }
        selectCard(newCardID)
        noteDocumentMutation(status: "Added a new card linked to cards with label")
    }

    private func updateSelectedCardBody(_ transform: (String) -> String) {
        guard let selectedCardID, let card = cardByID(selectedCardID) else { return }
        document.updateCard(selectedCardID) { c in
            c.bodyText = transform(card.bodyText)
            c.updated = isoTimestamp()
        }
    }

    func updateLinkName(_ linkID: UUID, name: String) {
        guard let index = document.links.firstIndex(where: { $0.id == linkID }) else { return }
        guard document.links[index].name != name else { return }
        registerUndoCheckpoint()
        document.links[index].name = name
        noteDocumentMutation(status: "Updated link name")
    }

    // MARK: - Batch Conversion

    func batchChangeAllCardsShape(to shape: Int) {
        registerUndoCheckpoint()
        for i in document.cards.indices {
            document.cards[i].shape = shape
        }
        noteDocumentMutation(status: "Changed all cards shape")
    }

    func batchChangeAllLinksShape(to shape: Int) {
        registerUndoCheckpoint()
        for i in document.links.indices {
            document.links[i].shape = shape
        }
        noteDocumentMutation(status: "Changed all links shape")
    }

    func batchReverseAllLinksDirection() {
        registerUndoCheckpoint()
        for i in document.links.indices {
            let from = document.links[i].fromCardID
            document.links[i].fromCardID = document.links[i].toCardID
            document.links[i].toCardID = from
        }
        noteDocumentMutation(status: "Reversed all links direction")
    }

    // MARK: - Label Editing

    func addCardLabel(name: String) {
        registerUndoCheckpoint()
        let maxID = document.cardLabels.map(\.id).max() ?? 0
        let color = Int.random(in: 0...0xFFFFFF)
        document.cardLabels.append(FrieveLabel(
            id: maxID + 1, name: name, color: color,
            enabled: true, show: true, hide: false, fold: false, size: 100
        ))
        noteDocumentMutation(status: "Added label \"\(name)\"")
    }

    func renameCardLabel(id: Int, name: String) {
        registerUndoCheckpoint()
        if let index = document.cardLabels.firstIndex(where: { $0.id == id }) {
            document.cardLabels[index].name = name
        }
        noteDocumentMutation(status: "Renamed label")
    }

    func changeCardLabelColor(id: Int, color: Int) {
        registerUndoCheckpoint()
        if let index = document.cardLabels.firstIndex(where: { $0.id == id }) {
            document.cardLabels[index].color = color
        }
        noteDocumentMutation(status: "Changed label color")
    }

    func deleteCardLabel(id: Int) {
        registerUndoCheckpoint()
        document.cardLabels.removeAll { $0.id == id }
        for i in document.cards.indices {
            document.cards[i].labelIDs.removeAll { $0 == id }
        }
        noteDocumentMutation(status: "Deleted label")
    }

    func addLinkLabel(name: String) {
        registerUndoCheckpoint()
        let maxID = document.linkLabels.map(\.id).max() ?? 0
        let color = Int.random(in: 0...0xFFFFFF)
        document.linkLabels.append(FrieveLabel(
            id: maxID + 1, name: name, color: color,
            enabled: true, show: true, hide: false, fold: false, size: 100
        ))
        noteDocumentMutation(status: "Added link label \"\(name)\"")
    }

    func renameLinkLabel(id: Int, name: String) {
        registerUndoCheckpoint()
        if let index = document.linkLabels.firstIndex(where: { $0.id == id }) {
            document.linkLabels[index].name = name
        }
        noteDocumentMutation(status: "Renamed link label")
    }

    func changeLinkLabelColor(id: Int, color: Int) {
        registerUndoCheckpoint()
        if let index = document.linkLabels.firstIndex(where: { $0.id == id }) {
            document.linkLabels[index].color = color
        }
        noteDocumentMutation(status: "Changed link label color")
    }

    func deleteLinkLabel(id: Int) {
        registerUndoCheckpoint()
        document.linkLabels.removeAll { $0.id == id }
        for i in document.links.indices {
            document.links[i].labelIDs.removeAll { $0 == id }
        }
        noteDocumentMutation(status: "Deleted link label")
    }

    private func importedTextContents(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .shiftJIS,
            .japaneseEUC,
            .iso2022JP
        ]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
            }
        }
        throw CocoaError(.fileReadUnknownStringEncoding)
    }

    @discardableResult
    private func importHierarchicalTextDocument(named title: String, lines: [String], bodyFollowsIndentedHeadings: Bool) -> Int {
        let hierarchyMarker: Character? = if bodyFollowsIndentedHeadings {
            lines.first?.first
        } else {
            lines
                .filter { !$0.isEmpty }
                .reduce(into: [Character: Int]()) { counts, line in
                    if let marker = line.first {
                        counts[marker, default: 0] += 1
                    }
                }
                .max(by: { $0.value < $1.value })?
                .key
        }

        let topID = document.addCard(title: title)
        var levelCardIDs: [Int?] = [topID]
        var lineIndex = 0

        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            guard !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lineIndex += 1
                continue
            }

            var titleLine = rawLine
            var level = 1
            while let hierarchyMarker, titleLine.first == hierarchyMarker {
                titleLine.removeFirst()
                level += 1
            }

            let parentID = stride(from: min(level - 1, levelCardIDs.count - 1), through: 0, by: -1)
                .compactMap { levelCardIDs[$0] }
                .first
            let cardID = document.addCard(title: titleLine, linkedFrom: parentID)

            if levelCardIDs.count > level {
                levelCardIDs.removeSubrange(level ..< levelCardIDs.count)
            } else if levelCardIDs.count < level {
                levelCardIDs.append(contentsOf: Array(repeating: nil, count: level - levelCardIDs.count))
            }
            levelCardIDs.append(cardID)

            if bodyFollowsIndentedHeadings, let hierarchyMarker {
                var bodyLines: [String] = []
                while lineIndex + 1 < lines.count {
                    let nextLine = lines[lineIndex + 1]
                    if nextLine.first == hierarchyMarker {
                        break
                    }
                    bodyLines.append(nextLine)
                    lineIndex += 1
                }
                if !bodyLines.isEmpty {
                    document.updateCard(cardID) { card in
                        card.bodyText = bodyLines.joined(separator: "\n")
                        card.updated = sharedISOTimestamp()
                    }
                }
            }

            lineIndex += 1
        }

        return topID
    }

    @discardableResult
    private func importTextFilesInFolderRecursively(from directory: URL, parentID: Int?) throws -> Int {
        let folderName = directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent
        let folderCardID = parentID.map { document.addCard(title: folderName, linkedFrom: $0) } ?? document.addCard(title: folderName)
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                _ = try importTextFilesInFolderRecursively(from: entry, parentID: folderCardID)
            } else if entry.pathExtension.localizedCaseInsensitiveCompare("txt") == .orderedSame {
                let bodyText = try importedTextContents(from: entry)
                let cardID = document.addCard(title: entry.deletingPathExtension().lastPathComponent, linkedFrom: folderCardID)
                document.updateCard(cardID) { card in
                    card.bodyText = bodyText
                    card.updated = sharedISOTimestamp()
                }
            }
        }

        return folderCardID
    }
}
