import SwiftUI
import AppKit

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
        let id = document.addCard(title: "Child Card", linkedFrom: selectedCardID)
        selectCard(id)
        noteDocumentMutation(status: "Added a child card")
    }

    func addSiblingCard() {
        registerUndoCheckpoint()
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

        let filteredTokens = trimmedLine
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                let lower = token.lowercased()
                return !(lower.hasPrefix("color=") || lower.hasPrefix("stroke=") || lower.hasPrefix("pen="))
            }

        guard let rawValue else {
            return filteredTokens.joined(separator: " ")
        }

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
        let stepScale = browserAutoArrangeStepScale()

        switch arrangeMode {
        case "Link":
            applyBrowserLinkAutoArrangeStep(stepScale: stepScale)
        case "Link(Soft)":
            applyBrowserLinkAutoArrangeStep(ratio: 0.33, stepScale: stepScale)
        case "Matrix":
            applyBrowserMatrixAutoArrangeStep(stepScale: stepScale)
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
        let visibleCards = visibleSortedCards()
        guard visibleCards.count > 1 else { return }
        let freezeSelectedCards = hasActiveBrowserGesture

        var positions: [Int: FrievePoint] = [:]
        positions.reserveCapacity(visibleCards.count)
        for card in visibleCards {
            positions[card.id] = card.position
        }

        let repulsionRatio = 0.5
        let baseLinkRatio = ratio * 0.66 * 0.3
        let linkRatio = 1 - pow(max(1 - baseLinkRatio, 0.0001), stepScale)
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
                let weight = repelWeight / Double(repelCount * repelCount) / 5.0 * repulsionRatio * stepScale
                nextPositions[card.id] = FrievePoint(
                    x: original.x + repelX * weight,
                    y: original.y + repelY * weight
                )
            }
        }

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

    func applyBrowserMatrixAutoArrangeStep(stepScale: Double = 1.0) {
        let visibleCards = browserVisibleCardsInDocumentOrder()
        guard !visibleCards.isEmpty else { return }

        let targets = computeBrowserMatrixTargets(for: visibleCards)
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
        let visibleCards = browserVisibleCardsInDocumentOrder()
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

    func normalizeAndApplyBrowserAutoArrangePositions(_ positions: [Int: FrievePoint], targetIDs: Set<Int>) {
        let normalizedPoints = targetIDs.compactMap { positions[$0] }
        guard let minX = normalizedPoints.map(\.x).min(),
              let maxX = normalizedPoints.map(\.x).max(),
              let minY = normalizedPoints.map(\.y).min(),
              let maxY = normalizedPoints.map(\.y).max(),
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

    func browserVisibleCardsInDocumentOrder() -> [FrieveCard] {
        document.cards.filter(\.visible)
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

    func computeBrowserMatrixTargets(for cards: [FrieveCard]) -> [Int: FrievePoint] {
        guard !cards.isEmpty else { return [:] }

        let visibleIDs = Set(cards.map(\.id))
        let positionsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.position) })
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
            let normalized = FrievePoint(
                x: (position.x - bounds.minX) / (bounds.maxX - bounds.minX),
                y: (position.y - bounds.minY) / (bounds.maxY - bounds.minY)
            )
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
        let originalIDs = cards.map(\.id)
        let originalIndexByID = Dictionary(uniqueKeysWithValues: originalIDs.enumerated().map { ($1, $0) })
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
        guard !cards.isEmpty else { return [:] }

        let hierarchy = browserTreeHierarchy(for: cards)
        let orderedIDs = hierarchy.orderedIDs
        guard !orderedIDs.isEmpty else { return [:] }

        var positions = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.position) })
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
