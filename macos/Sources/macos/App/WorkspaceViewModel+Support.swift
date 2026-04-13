import SwiftUI
import AppKit
import ImageIO

private let maxDocumentUndoSnapshots = 64
private let browserCardBaseTitlePointSize: CGFloat = 13
private let browserCardBaseContentPadding: CGFloat = 8
private let browserCardBaseMaximumTextWidth: CGFloat = 200

struct WorkspaceDocumentUndoSnapshot {
    let document: FrieveDocument
    let selectedCardID: Int?
    let selectedCardIDs: Set<Int>
    let browserInlineEditorCardID: Int?
    let hasUnsavedChanges: Bool
}

func browserCardStoredSize(forStep step: Int) -> Int {
    let clampedStep = max(-8, min(step, 8))
    let divisor = 8.0 / log(4.0)
    return Int(100 * exp(Double(clampedStep) / divisor) + 100) - 100
}

func browserCardSizeStep(forStoredSize size: Int) -> Int {
    let clampedSize = max(25, min(size, 400))
    let scaled = log(Double(clampedSize) / 100.0) * (8.0 / log(4.0))
    return max(-8, min(Int(scaled + 100.5) - 100, 8))
}

func browserCardScale(for card: FrieveCard) -> CGFloat {
    CGFloat(max(25, min(card.size, 400))) / 100
}

func browserCardTitlePointSize(for card: FrieveCard) -> CGFloat {
    browserCardBaseTitlePointSize * browserCardScale(for: card)
}

func browserCardContentPadding(for card: FrieveCard) -> CGFloat {
    max(4, ceil(browserCardBaseContentPadding * browserCardScale(for: card)))
}

func browserCardMaximumTextWidth(for card: FrieveCard) -> CGFloat {
    max(60, ceil(browserCardBaseMaximumTextWidth * browserCardScale(for: card)))
}

func browserCardTitleNSFont(for card: FrieveCard) -> NSFont {
    NSFont.systemFont(ofSize: browserCardTitlePointSize(for: card), weight: .medium)
}

func browserCardVisualShapeIndex(for card: FrieveCard) -> Int {
    _ = card
    return 0
}

extension WorkspaceViewModel {
    var browserDisplaySettingsSignature: Int {
        var hasher = Hasher()
        hasher.combine(settings.browserCardShadow)
        hasher.combine(settings.browserCardGradation)
        hasher.combine(settings.browserTickerVisible)
        hasher.combine(settings.browserTickerLines)
        hasher.combine(settings.browserImageVisible)
        hasher.combine(settings.browserVideoVisible)
        hasher.combine(settings.browserDrawingVisible)
        hasher.combine(settings.browserImageLimitation)
        hasher.combine(settings.browserLinkVisible)
        hasher.combine(settings.browserLinkHemming)
        hasher.combine(settings.browserLinkDirectionVisible)
        hasher.combine(settings.browserLinkNameVisible)
        hasher.combine(settings.browserLabelCircleVisible)
        hasher.combine(settings.browserLabelRectangleVisible)
        hasher.combine(settings.browserLabelNameVisible)
        hasher.combine(settings.browserTextVisible)
        hasher.combine(settings.browserTextCentering)
        hasher.combine(settings.browserTextWordWrap)
        hasher.combine(settings.browserEditInBrowser)
        hasher.combine(settings.browserEditInBrowserAlways)
        hasher.combine(settings.browserEditInBrowserPosition)
        hasher.combine(settings.browserScoreVisible)
        hasher.combine(settings.browserScoreType)
        hasher.combine(settings.browserFontFamily)
        hasher.combine(settings.browserFontSize)
        hasher.combine(settings.browserWallpaperPath)
        hasher.combine(settings.browserWallpaperFixed)
        hasher.combine(settings.browserWallpaperTiled)
        hasher.combine(settings.browserBackgroundAnimation)
        hasher.combine(settings.browserBackgroundAnimationType)
        hasher.combine(settings.browserCursorAnimation)
        hasher.combine(settings.browserNoScrollLag)
        hasher.combine(settings.browserAntialiasingEnabled)
        hasher.combine(settings.browserAntialiasingSampleCount)
        return hasher.finalize()
    }

    var browserLabelOutlineStyle: BrowserLabelOutlineStyle {
        if settings.browserLabelCircleVisible {
            return .circle
        }
        if settings.browserLabelRectangleVisible {
            return .rectangle
        }
        return .none
    }

    var browserConfiguredFontFamily: String? {
        let trimmed = settings.browserFontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func browserCardTitlePointSize(for card: FrieveCard) -> CGFloat {
        CGFloat(settings.browserFontSize) * browserCardScale(for: card)
    }

    func browserCardTitleNSFont(for card: FrieveCard) -> NSFont {
        let pointSize = browserCardTitlePointSize(for: card)
        guard let family = browserConfiguredFontFamily,
              let font = NSFont(name: family, size: pointSize)
                ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: pointSize) else {
            return NSFont.systemFont(ofSize: pointSize, weight: .medium)
        }
        return font
    }

    func browserCardBodyNSFont(for card: FrieveCard) -> NSFont {
        let pointSize = max(browserCardTitlePointSize(for: card) * 0.9, 11)
        guard let family = browserConfiguredFontFamily,
              let font = NSFont(name: family, size: pointSize)
                ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: pointSize) else {
            return NSFont.systemFont(ofSize: pointSize)
        }
        return font
    }

    func browserWallpaperURL() -> URL? {
        let trimmed = settings.browserWallpaperPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    var browserBackgroundAnimationType: BrowserBackgroundAnimationType {
        BrowserBackgroundAnimationType(rawValue: settings.browserBackgroundAnimationType) ?? .flowingLines
    }

    var browserAntialiasingSampleCount: Int {
        settings.browserAntialiasingEnabled ? settings.browserAntialiasingSampleCount : 1
    }

    func browserChromeRefreshMinimumInterval() -> CFTimeInterval {
        guard !settings.browserNoScrollLag else { return 0 }
        return browserInteractionModeEnabled ? 1.0 / 6.0 : 1.0 / 12.0
    }

    func browserCursorPulseColor(for colorScheme: ColorScheme) -> Color {
        _ = colorScheme
        return Color.accentColor.opacity(0.6)
    }

    func browserShowsMediaPreview(for card: FrieveCard) -> Bool {
        (settings.browserImageVisible && !(card.imagePath?.trimmed.isEmpty ?? true)) ||
        (settings.browserVideoVisible && !(card.videoPath?.trimmed.isEmpty ?? true))
    }

    func browserShowsDrawingPreview(for card: FrieveCard, hasDrawingPreview: Bool? = nil) -> Bool {
        settings.browserDrawingVisible && (hasDrawingPreview ?? !drawingPreviewItems(for: card).isEmpty)
    }

    func browserMediaPreviewSize(for card: FrieveCard) -> CGSize {
        let limit = CGFloat(settings.browserImageLimitation)
        let width = min(max(limit * 1.6, 72), 320)
        let height = min(max(limit, 48), 220)
        return CGSize(width: width, height: height)
    }

    func browserDrawingPreviewSize(for card: FrieveCard) -> CGSize {
        let limit = CGFloat(settings.browserImageLimitation)
        let width = min(max(limit * 1.2, 72), 220)
        let height = min(max(limit * 0.9, 54), 180)
        return CGSize(width: width, height: height)
    }

    func browserCardTickerText(for card: FrieveCard) -> String? {
        guard settings.browserTickerVisible else { return nil }
        let lines = card.bodyLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.prefix(settings.browserTickerLines).joined(separator: "  •  ")
    }

    func browserCardTickerNSFont(for card: FrieveCard) -> NSFont {
        let bodyFont = browserCardBodyNSFont(for: card)
        let pointSize = max(bodyFont.pointSize * 0.8, 9)
        return NSFont(descriptor: bodyFont.fontDescriptor, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
    }

    func browserCardTickerHeight(for card: FrieveCard) -> CGFloat {
        guard browserCardTickerText(for: card) != nil else { return 0 }
        let font = browserCardTickerNSFont(for: card)
        return ceil(font.ascender - font.descender + font.leading)
    }

    func browserCardScoreNSFont(for card: FrieveCard) -> NSFont {
        let pointSize = max(browserCardTitlePointSize(for: card) * 0.72, 11)
        return NSFont.systemFont(ofSize: pointSize, weight: .bold)
    }

    func browserCardScoreText(for card: FrieveCard) -> String? {
        guard settings.browserScoreVisible else { return nil }

        let outgoing = document.links.filter { $0.fromCardID == card.id }.count
        let incoming = document.links.filter { $0.toCardID == card.id }.count
        let type = BrowserScoreDisplayType(rawValue: settings.browserScoreType) ?? .authenticity

        switch type {
        case .authenticity:
            return String(format: "Score %.2f", card.score)
        case .startingPoint:
            return "Starting \(outgoing)"
        case .destination:
            return "Destination \(incoming)"
        case .linksOut:
            return "Out \(outgoing)"
        case .linksIn:
            return "In \(incoming)"
        case .linksTotal:
            return "Links \(incoming + outgoing)"
        case .linksInOut:
            return "In-Out \(incoming - outgoing)"
        case .textLength:
            return "Text \(card.bodyText.count)"
        }
    }

    func persistDocument(to url: URL, isAutomatic: Bool) {
        do {
            syncDocumentMetadataFromSettings()
            document.sourcePath = url.path
            try DocumentFileCodec.save(document: document, to: url)
            recordRecent(url)
            hasUnsavedChanges = false
            lastAutoSaveAt = Date()
            lastKnownFileModificationDate = fileModificationDate(for: url)
            statusMessage = isAutomatic ? "Auto-saved \(url.lastPathComponent)" : "Saved \(url.lastPathComponent)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func autoSaveIfNeeded(now: Date) {
        guard hasUnsavedChanges, let sourcePath = document.sourcePath else { return }
        let minInterval = TimeInterval(max(settings.autoSaveMinIntervalSec, 1))
        let idleInterval = TimeInterval(max(settings.autoSaveIdleSec, 1))
        guard now.timeIntervalSince(lastMutationAt) >= idleInterval else { return }
        guard now.timeIntervalSince(lastAutoSaveAt) >= minInterval else { return }
        persistDocument(to: URL(fileURLWithPath: sourcePath), isAutomatic: true)
    }

    func reloadDocumentFromDiskIfNeeded(now: Date) {
        guard let sourcePath = document.sourcePath, !hasUnsavedChanges else { return }
        let pollInterval = TimeInterval(max(settings.autoReloadPollSec, 1))
        guard now.timeIntervalSince(lastAutoReloadCheckAt) >= pollInterval else { return }
        lastAutoReloadCheckAt = now
        let url = URL(fileURLWithPath: sourcePath)
        guard let modificationDate = fileModificationDate(for: url) else { return }
        if let lastKnownFileModificationDate, modificationDate <= lastKnownFileModificationDate {
            return
        }
        do {
            let loaded = try DocumentFileCodec.load(url: url)
            document = loaded
            selectedCardID = loaded.focusedCardID ?? loaded.cards.first?.id
            selectedCardIDs = selectedCardID.map { [$0] } ?? []
            lastKnownFileModificationDate = modificationDate
            syncDocumentMetadataFromSettings()
            resetCanvasStateFromDocument()
            statusMessage = "Reloaded \(url.lastPathComponent) from disk"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncDocumentMetadataFromSettings() {
        document.metadata["Title"] = document.title
        document.metadata["DefaultView"] = String(WorkspaceTab.allCases.firstIndex(of: selectedTab) ?? 0)
        document.metadata["AutoSave"] = settings.autoSaveDefault ? "1" : "0"
        document.metadata["AutoReload"] = settings.autoReloadDefault ? "1" : "0"
        document.metadata["Language"] = settings.language
        document.metadata["WebSearch"] = settings.preferredWebSearchName
        document.metadata["GPTModel"] = settings.gptModel
        document.metadata["ReadSpeed"] = String(Int(settings.readAloudRate))
    }

    func noteDocumentMutation(status: String? = nil) {
        hasUnsavedChanges = true
        lastMutationAt = Date()
        syncDocumentMetadataFromSettings()
        markBrowserSurfaceContentDirty()
        if let status {
            statusMessage = status
        }
    }

    func resetCanvasStateFromDocument() {
        clearRenderingCaches()
        canvasCenter = selectedCard?.position ?? FrievePoint(x: 0.5, y: 0.5)
        zoom = 1.0
        browserBaseScaleFactor = 0.8
        requestBrowserFit()
        markBrowserSurfaceContentDirty()
        markBrowserSurfaceViewportDirty()
        clearCanvasTransientState()
    }

    func clearRenderingCaches() {
        drawingPreviewCache.removeAll(keepingCapacity: true)
        drawingPreviewBoundsCache.removeAll(keepingCapacity: true)
        drawingPreviewImageCache.removeAll(keepingCapacity: true)
        drawingPreviewImageCacheOrder.removeAll(keepingCapacity: true)
        browserCardRasterCache.removeAll(keepingCapacity: true)
        browserCardRasterCacheOrder.removeAll(keepingCapacity: true)
        mediaImageCache.removeAll(keepingCapacity: true)
        mediaImageCacheOrder.removeAll(keepingCapacity: true)
        mediaThumbnailTasks.removeAll(keepingCapacity: true)
        missingMediaCacheKeys.removeAll(keepingCapacity: true)
        invalidateDocumentCaches()
    }

    func clearCanvasTransientState() {
        browserGestureMode = nil
        dragOriginByCardID.removeAll()
        currentDragTranslation = nil
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
        linkPreviewSourceCardID = nil
        linkPreviewCanvasPoint = nil
        browserHoverCardID = nil
        cachedOverviewSnapshotKey = nil
        cachedOverviewSnapshot = nil
        markBrowserSurfaceViewportDirty()
    }

    func selectedNarrationText() -> String {
        guard let card = selectedCard else { return "" }
        return [card.title, card.bodyText]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    func selectedWebSearchQuery() -> String {
        if selectedCardIDs.count > 1 {
            return selectedCards
                .map(\.title)
                .map(\.trimmed)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        guard let card = selectedCard else { return "" }
        return card.title.trimmed
    }

    func selectedGPTPrompt() -> String {
        selectedGPTPrompt(for: .summarize)
    }

    func selectedGPTPrompt(for action: GPTPromptAction, customInstruction: String? = nil) -> String {
        let instruction = (customInstruction ?? action.defaultInstruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let card = selectedCard else {
            return [
                settings.gptSystemPrompt,
                "",
                "Requested Action: \(action.operationLabel)",
                "Instruction: \(instruction)"
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        let labels = cardLabelNames(for: card).joined(separator: ", ")
        let relatedTitles = selectedCardLinks.compactMap { link -> String? in
            let otherID = link.fromCardID == card.id ? link.toCardID : link.fromCardID
            return cardByID(otherID)?.title
        }
        .joined(separator: ", ")

        return [
            settings.gptSystemPrompt,
            "",
            "Requested Action: \(action.operationLabel)",
            "Instruction: \(instruction)",
            "",
            "Document Title: \(document.title)",
            "Selected Card ID: \(card.id)",
            "Selected Card Title: \(card.title)",
            "Labels: \(labels.isEmpty ? "None" : labels)",
            "Related Cards: \(relatedTitles.isEmpty ? "None" : relatedTitles)",
            "Body:",
            card.bodyText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    func copyGPTPrompt(for action: GPTPromptAction) {
        let customInstruction: String?
        if action == .create {
            guard let prompt = promptForGPTInstruction(title: action.menuTitle) else {
                statusMessage = "GPT prompt creation was cancelled"
                return
            }
            customInstruction = prompt
        } else {
            customInstruction = nil
        }

        let prompt = selectedGPTPrompt(for: action, customInstruction: customInstruction)
        lastGPTPrompt = prompt
        copyTextToClipboard(prompt)
        statusMessage = "Copied the \(action.menuTitle.replacingOccurrences(of: "…", with: "")) GPT prompt to the clipboard"
    }

    private func promptForGPTInstruction(title: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter the instruction to send with the selected card."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        inputField.placeholderString = "Prompt"
        alert.accessoryView = inputField

        let response = alert.runModal()
        let prompt = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard response == .alertFirstButtonReturn, !prompt.isEmpty else {
            return nil
        }
        return prompt
    }

    func saveTextExport(_ text: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                statusMessage = "Exported \(url.lastPathComponent)"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func saveImageExport(_ image: NSImage, defaultName: String, fileType: NSBitmapImageRep.FileType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try writeImage(image, to: url, fileType: fileType)
                statusMessage = "Exported \(url.lastPathComponent)"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func chooseExportDirectory(prompt: String = "Export") -> URL? {
        let panel = NSOpenPanel()
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func makeSafeFilename(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmed.nilIfEmpty ?? fallback
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitizedScalars = trimmed.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }
        let sanitized = String(sanitizedScalars).trimmed
        return sanitized.nilIfEmpty ?? fallback
    }

    func uniqueFileURL(in directory: URL, baseName: String, pathExtension: String, usedNames: inout Set<String>) -> URL {
        let cleanBaseName = makeSafeFilename(baseName, fallback: "Card")
        var index = 1
        var candidate = "\(cleanBaseName).\(pathExtension)"
        while usedNames.contains(candidate) || FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            index += 1
            candidate = "\(cleanBaseName)-\(index).\(pathExtension)"
        }
        usedNames.insert(candidate)
        return directory.appendingPathComponent(candidate)
    }

    func writeImage(_ image: NSImage, to url: URL, fileType: NSBitmapImageRep.FileType) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: fileType, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }

    func ensureDocumentCaches() {
        guard cachedDocumentCacheVersion != documentCacheVersion else { return }

        cardIndexByID = document.cards.enumerated().reduce(into: [Int: Int]()) { partial, entry in
            partial[entry.element.id] = partial[entry.element.id] ?? entry.offset
        }
        let sortedCards = document.cards.sorted { lhs, rhs in
            if lhs.isTop != rhs.isTop {
                return lhs.isTop && !rhs.isTop
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        sortedCardIDs = sortedCards.map(\.id)
        visibleSortedCardIDs = sortedCards.filter(\.visible).map(\.id)
        labelNameByID = document.cardLabels.reduce(into: [Int: String]()) { partial, label in
            partial[label.id] = partial[label.id] ?? label.name
        }
        labelColorByID = document.cardLabels.reduce(into: [Int: Int]()) { partial, label in
            partial[label.id] = partial[label.id] ?? label.color
        }

        var groupedLinks: [Int: [FrieveLink]] = [:]
        for link in document.links {
            groupedLinks[link.fromCardID, default: []].append(link)
            groupedLinks[link.toCardID, default: []].append(link)
        }
        linksByCardID = groupedLinks
        linkCountByCardID = groupedLinks.mapValues(\.count)

        var metadataCache: [Int: BrowserCardMetadata] = [:]
        metadataCache.reserveCapacity(document.cards.count)
        for card in document.cards {
            let labelNames = card.labelIDs.compactMap { labelNameByID[$0] }
            let labelLine = labelNames.joined(separator: ", ")
            let primaryLabelColor = card.labelIDs.compactMap { labelColorByID[$0] }.first
            let linkCount = linkCountByCardID[card.id] ?? 0
            let hasDrawingPreview = !drawingPreviewItems(for: card).isEmpty
            let summaryText = buildBrowserSummaryText(for: card)
            let detailSummary = buildBrowserDetailSummary(for: card, hasDrawingPreview: hasDrawingPreview)
            let badges = buildBrowserBadgeItems(for: card, labelNames: labelNames, linkCount: linkCount, hasDrawingPreview: hasDrawingPreview)
            let scoreText = browserCardScoreText(for: card)
            let canvasSize = buildCardCanvasSize(for: card, summaryText: summaryText, labelLine: labelLine, badges: badges, detailSummary: detailSummary)
            metadataCache[card.id] = BrowserCardMetadata(
                labelNames: labelNames,
                labelLine: labelLine,
                summaryText: summaryText,
                detailSummary: detailSummary,
                scoreText: scoreText,
                badges: badges,
                canvasSize: canvasSize,
                linkCount: linkCount,
                hasDrawingPreview: hasDrawingPreview,
                primaryLabelColor: primaryLabelColor,
                mediaBadgeText: card.mediaBadgeText
            )
        }
        cardMetadataByID = metadataCache
        cachedDocumentCacheVersion = documentCacheVersion
    }

    func invalidateDocumentCaches() {
        documentCacheVersion &+= 1
        cachedDocumentCacheVersion = -1
        cardIndexByID.removeAll(keepingCapacity: true)
        sortedCardIDs.removeAll(keepingCapacity: true)
        visibleSortedCardIDs.removeAll(keepingCapacity: true)
        labelNameByID.removeAll(keepingCapacity: true)
        labelColorByID.removeAll(keepingCapacity: true)
        linkCountByCardID.removeAll(keepingCapacity: true)
        linksByCardID.removeAll(keepingCapacity: true)
        cardMetadataByID.removeAll(keepingCapacity: true)
        cachedOverviewSnapshotKey = nil
        cachedOverviewSnapshot = nil
        cachedBrowserSurfaceContentKey = nil
        cachedBrowserSurfaceContent = nil
    }

    func sortedCards() -> [FrieveCard] {
        ensureDocumentCaches()
        return sortedCardIDs.compactMap(cardByID)
    }

    func visibleSortedCards() -> [FrieveCard] {
        ensureDocumentCaches()
        return visibleSortedCardIDs.compactMap(cardByID)
    }

    func cardByID(_ id: Int?) -> FrieveCard? {
        guard let id else { return nil }
        ensureDocumentCaches()
        guard let index = cardIndexByID[id], document.cards.indices.contains(index) else { return nil }
        return document.cards[index]
    }

    func linksForCard(_ cardID: Int?) -> [FrieveLink] {
        guard let cardID else { return [] }
        ensureDocumentCaches()
        return linksByCardID[cardID] ?? []
    }

    func metadata(for card: FrieveCard) -> BrowserCardMetadata {
        ensureDocumentCaches()
        if let cached = cardMetadataByID[card.id] {
            return cached
        }
        let labelNames = card.labelIDs.compactMap { labelNameByID[$0] }
        let labelLine = labelNames.joined(separator: ", ")
        let primaryLabelColor = card.labelIDs.compactMap { labelColorByID[$0] }.first
        let linkCount = linkCountByCardID[card.id] ?? 0
        let hasDrawingPreview = !drawingPreviewItems(for: card).isEmpty
        let summaryText = buildBrowserSummaryText(for: card)
        let detailSummary = buildBrowserDetailSummary(for: card, hasDrawingPreview: hasDrawingPreview)
        let badges = buildBrowserBadgeItems(for: card, labelNames: labelNames, linkCount: linkCount, hasDrawingPreview: hasDrawingPreview)
        let scoreText = browserCardScoreText(for: card)
        return BrowserCardMetadata(
            labelNames: labelNames,
            labelLine: labelLine,
            summaryText: summaryText,
            detailSummary: detailSummary,
            scoreText: scoreText,
            badges: badges,
            canvasSize: buildCardCanvasSize(for: card, summaryText: summaryText, labelLine: labelLine, badges: badges, detailSummary: detailSummary),
            linkCount: linkCount,
            hasDrawingPreview: hasDrawingPreview,
            primaryLabelColor: primaryLabelColor,
            mediaBadgeText: card.mediaBadgeText
        )
    }

    func currentPosition(for card: FrieveCard) -> FrievePoint {
        guard let origin = dragOriginByCardID[card.id], let currentDragTranslation else {
            return card.position
        }
        return FrievePoint(x: origin.x + currentDragTranslation.x, y: origin.y + currentDragTranslation.y)
    }

    func recordPerformanceMetric(_ start: CFTimeInterval, keyPath: WritableKeyPath<BrowserPerformanceSnapshot, BrowserPerformanceMetric>) {
        let elapsed = max((CACurrentMediaTime() - start) * 1000, 0)
        browserPerformance[keyPath: keyPath].record(elapsed)
    }

    func recordBrowserFramePresentation(at timestamp: CFTimeInterval = CACurrentMediaTime()) {
        if browserLastPresentedFrameAt > 0 {
            browserPerformance[keyPath: \BrowserPerformanceSnapshot.frameInterval].record(max((timestamp - browserLastPresentedFrameAt) * 1000, 0))
        }
        browserLastPresentedFrameAt = timestamp
    }

    func recordBrowserCardRasterMetric(_ milliseconds: Double) {
        browserPerformance[keyPath: \BrowserPerformanceSnapshot.cardRaster].record(max(milliseconds, 0))
    }

    func enqueueBrowserCardRaster(for snapshot: BrowserCardLayerSnapshot, cacheKey: String) {
        guard browserCardRasterCache[cacheKey] == nil else { return }
        guard pendingBrowserCardRasterKeys.insert(cacheKey).inserted else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingBrowserCardRasterKeys.remove(cacheKey) }
            guard self.browserCardRasterCache[cacheKey] == nil else { return }
            guard self.cachedBrowserCardRaster(for: snapshot, cacheKey: cacheKey) != nil else { return }
            self.markBrowserSurfacePresentationDirty()
        }
    }

    func touchBrowserCardRasterCacheKey(_ key: String) {
        browserCardRasterCacheOrder.removeAll { $0 == key }
        browserCardRasterCacheOrder.append(key)
    }

    func touchDrawingPreviewCacheKey(_ key: String) {
        drawingPreviewImageCacheOrder.removeAll { $0 == key }
        drawingPreviewImageCacheOrder.append(key)
    }

    func touchMediaImageCacheKey(_ key: String) {
        mediaImageCacheOrder.removeAll { $0 == key }
        mediaImageCacheOrder.append(key)
    }

    func cacheMediaImage(_ image: NSImage, forKey key: String) {
        mediaImageCache[key] = image
        touchMediaImageCacheKey(key)
        evictCacheIfNeeded(order: &mediaImageCacheOrder, storage: &mediaImageCache, maxEntries: 96)
    }

    func cacheDrawingPreviewImage(_ image: NSImage, forKey key: String) {
        drawingPreviewImageCache[key] = image
        touchDrawingPreviewCacheKey(key)
        evictCacheIfNeeded(order: &drawingPreviewImageCacheOrder, storage: &drawingPreviewImageCache, maxEntries: 160)
    }

    func evictCacheIfNeeded(order: inout [String], storage: inout [String: NSImage], maxEntries: Int) {
        while order.count > maxEntries {
            let evictedKey = order.removeFirst()
            storage.removeValue(forKey: evictedKey)
        }
    }

    func buildBrowserBadgeItems(for card: FrieveCard, labelNames: [String], linkCount: Int, hasDrawingPreview: Bool) -> [String] {
        var badges: [String] = []
        if card.isTop {
            badges.append("Top")
        }
        if card.isFixed {
            badges.append("Fixed")
        }
        if card.hasMedia {
            badges.append("Media")
        }
        if hasDrawingPreview {
            badges.append("Drawing")
        }
        if card.isFolded {
            badges.append("Folded")
        }
        return Array(badges.prefix(6))
    }

    func buildBrowserSummaryText(for card: FrieveCard) -> String {
        guard settings.browserTextVisible else { return "" }
        let compact = card.bodyText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "" : String(compact.prefix(96))
    }

    func buildBrowserDetailSummary(for card: FrieveCard, hasDrawingPreview: Bool) -> String {
        var segments: [String] = []
        if browserShowsMediaPreview(for: card) {
            segments.append("Media")
        }
        if browserShowsDrawingPreview(for: card, hasDrawingPreview: hasDrawingPreview) {
            segments.append("Drawing")
        }
        if card.isFixed {
            segments.append("Fixed")
        }
        if card.isFolded {
            segments.append("Folded")
        }
        return segments.joined(separator: " · ")
    }

    func buildCardCanvasSize(for card: FrieveCard, summaryText: String, labelLine: String, badges: [String], detailSummary: String) -> CGSize {
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : card.title
        let font = self.browserCardTitleNSFont(for: card)
        let maxTextWidth = browserCardMaximumTextWidth(for: card)
        let padding = browserCardContentPadding(for: card)
        let maxTextHeight = ceil((font.ascender - font.descender + font.leading) * 3)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let textBounds = NSAttributedString(string: title, attributes: attributes).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textWidth = min(ceil(textBounds.width), maxTextWidth)
        let textHeight = min(ceil(textBounds.height), maxTextHeight)
        var width = max(padding * 2, textWidth + padding * 2)
        var height = max(padding * 2, textHeight + padding * 2)

        if browserShowsMediaPreview(for: card) {
            let previewSize = browserMediaPreviewSize(for: card)
            width = max(width, previewSize.width + padding * 2)
            height += previewSize.height + 10
        }

        if browserShowsDrawingPreview(for: card, hasDrawingPreview: !drawingPreviewItems(for: card).isEmpty) {
            let previewSize = browserDrawingPreviewSize(for: card)
            width = max(width, previewSize.width + padding * 2)
            height += previewSize.height + 10
        }

        let tickerHeight = browserCardTickerHeight(for: card)
        if tickerHeight > 0 {
            height += tickerHeight + 6
        }

        if let scoreText = browserCardScoreText(for: card), !scoreText.isEmpty {
            let scoreFont = browserCardScoreNSFont(for: card)
            let scoreBounds = NSAttributedString(
                string: scoreText,
                attributes: [.font: scoreFont]
            ).boundingRect(
                with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            let scoreSize = CGSize(
                width: ceil(scoreBounds.width) + 16,
                height: ceil(scoreBounds.height) + 8
            )
            width = max(width, scoreSize.width + padding * 2)
            height += scoreSize.height + 8
        }

        return CGSize(width: width, height: height)
    }

    func browserCardDetailLevel() -> BrowserCardDetailLevel {
        switch zoom {
        case ..<0.7:
            return .thumbnail
        case ..<1.35:
            return .compact
        default:
            return .full
        }
    }

    func drawingPreviewBounds(for items: [DrawingPreviewItem]) -> CGRect {
        let rects = items.map(drawingPreviewSourceRect(for:))
        let union = rects.dropFirst().reduce(rects.first ?? CGRect(x: 0, y: 0, width: 1, height: 1)) { partial, rect in
            partial.union(rect)
        }
        return CGRect(
            x: union.minX,
            y: union.minY,
            width: max(union.width, 1),
            height: max(union.height, 1)
        )
    }

    func drawingPreviewSourceRect(for item: DrawingPreviewItem) -> CGRect {
        switch item.kind {
        case let .polyline(points, _):
            guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
            return points.dropFirst().reduce(CGRect(x: first.x, y: first.y, width: 0, height: 0)) { partial, point in
                partial.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
            }
        case let .line(start, end):
            return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        case let .rect(rect), let .ellipse(rect):
            return rect
        case let .text(point, _):
            return CGRect(x: point.x, y: point.y, width: 1, height: 1)
        }
    }

    func mapDrawingPoint(_ point: FrievePoint, from source: CGRect, to size: CGSize) -> CGPoint {
        let inset: CGFloat = 4
        let usableWidth = max(size.width - inset * 2, 1)
        let usableHeight = max(size.height - inset * 2, 1)
        let x = ((point.x - source.minX) / max(source.width, 1)) * usableWidth + inset
        let y = ((point.y - source.minY) / max(source.height, 1)) * usableHeight + inset
        return CGPoint(x: x, y: y)
    }

    func mapDrawingRect(_ rect: CGRect, from source: CGRect, to size: CGSize) -> CGRect {
        let p1 = mapDrawingPoint(FrievePoint(x: rect.minX, y: rect.minY), from: source, to: size)
        let p2 = mapDrawingPoint(FrievePoint(x: rect.maxX, y: rect.maxY), from: source, to: size)
        return CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    func renderDrawingPreviewImage(items: [DrawingPreviewItem], sourceBounds: CGRect, targetSize: CGSize, colorProvider: @escaping (Int?, Color) -> Color) -> NSImage? {
        guard targetSize.width > 0, targetSize.height > 0 else { return nil }
        let renderer = ImageRenderer(content:
            Canvas { context, size in
                for item in items {
                    let strokeColor = colorProvider(item.strokeColor, .accentColor.opacity(0.8))
                    let fillColor = colorProvider(item.fillColor, .accentColor.opacity(0.15))
                    switch item.kind {
                    case let .polyline(points, closed):
                        guard let first = points.first else { continue }
                        var path = Path()
                        path.move(to: self.mapDrawingPoint(first, from: sourceBounds, to: size))
                        for point in points.dropFirst() {
                            path.addLine(to: self.mapDrawingPoint(point, from: sourceBounds, to: size))
                        }
                        if closed {
                            path.closeSubpath()
                            context.fill(path, with: .color(fillColor.opacity(0.35)))
                        }
                        context.stroke(path, with: .color(strokeColor), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    case let .line(start, end):
                        var path = Path()
                        path.move(to: self.mapDrawingPoint(start, from: sourceBounds, to: size))
                        path.addLine(to: self.mapDrawingPoint(end, from: sourceBounds, to: size))
                        context.stroke(path, with: .color(strokeColor), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    case let .rect(rect):
                        let mapped = self.mapDrawingRect(rect, from: sourceBounds, to: size)
                        let path = Path(roundedRect: mapped, cornerRadius: 4)
                        context.fill(path, with: .color(fillColor.opacity(0.2)))
                        context.stroke(path, with: .color(strokeColor), lineWidth: 1.2)
                    case let .ellipse(rect):
                        let mapped = self.mapDrawingRect(rect, from: sourceBounds, to: size)
                        let path = Path(ellipseIn: mapped)
                        context.fill(path, with: .color(fillColor.opacity(0.18)))
                        context.stroke(path, with: .color(strokeColor), lineWidth: 1.2)
                    case let .text(point, text):
                        context.draw(Text(text).font(.caption2), at: self.mapDrawingPoint(point, from: sourceBounds, to: size), anchor: .center)
                    }
                }
            }
            .frame(width: targetSize.width, height: targetSize.height)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    nonisolated static func loadThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func sharedISOTimestamp() -> String {
        isoTimestamp()
    }

    func recordRecent(_ url: URL) {
        settings.recordRecent(url: url)
        recentFiles = settings.recentFiles
    }

    func clearRecentFiles() {
        settings.recentFilePaths = []
        recentFiles = []
    }

    func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func fileModificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    func editorRelatedCardLines() -> [EditorRelatedCardLine] {
        guard let selectedCardID else { return [] }

        struct RelationState {
            var hasIncoming = false
            var hasOutgoing = false
            var order = Int.max
        }

        var relationByCardID: [Int: RelationState] = [:]
        for (index, link) in selectedCardLinks.enumerated() {
            let otherCardID: Int
            var state: RelationState
            if link.toCardID == selectedCardID {
                otherCardID = link.fromCardID
                state = relationByCardID[otherCardID] ?? RelationState()
                state.hasIncoming = true
            } else {
                otherCardID = link.toCardID
                state = relationByCardID[otherCardID] ?? RelationState()
                state.hasOutgoing = true
            }
            state.order = min(state.order, index)
            relationByCardID[otherCardID] = state
        }

        return relationByCardID.compactMap { cardID, state in
            guard let card = cardByID(cardID) else { return nil }
            let labels = cardLabelNames(for: card)
            let labelText = labels.isEmpty ? "" : "[\(labels.joined(separator: ", "))] "
            let bodyText = card.bodyText
                .replacingOccurrences(of: "\n", with: " ")
                .trimmed
            let relation: String
            if state.hasIncoming && state.hasOutgoing {
                relation = "相互"
            } else if state.hasIncoming {
                relation = "親"
            } else if state.hasOutgoing {
                relation = "子"
            } else {
                relation = "関連"
            }
            let summary = bodyText.isEmpty ? "本文なし" : bodyText
            return EditorRelatedCardLine(
                cardID: cardID,
                relation: relation,
                text: "\(relation)：\(labelText)\(card.title)：\(summary)"
            )
        }
        .sorted { lhs, rhs in
            let lhsOrder = relationByCardID[lhs.cardID]?.order ?? .max
            let rhsOrder = relationByCardID[rhs.cardID]?.order ?? .max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.cardID < rhs.cardID
        }
    }
}

extension WorkspaceViewModel {
    var canUndoLastDocumentChange: Bool {
        !documentUndoStack.isEmpty
    }

    var canRedoDocumentChange: Bool {
        !documentRedoStack.isEmpty
    }

    func clearDocumentUndoHistory() {
        documentUndoStack.removeAll(keepingCapacity: true)
        documentRedoStack.removeAll(keepingCapacity: true)
        activeUndoEditCardID = nil
    }

    func registerUndoCheckpoint() {
        activeUndoEditCardID = nil
        pushUndoSnapshot()
    }

    func registerUndoCheckpointForEdit(cardID: Int) {
        if activeUndoEditCardID != cardID {
            pushUndoSnapshot()
            activeUndoEditCardID = cardID
        }
    }

    func finishUndoEditCoalescing() {
        activeUndoEditCardID = nil
    }

    func undoLastDocumentChange() {
        finishUndoEditCoalescing()
        guard let snapshot = documentUndoStack.popLast() else {
            statusMessage = "Nothing to undo"
            return
        }
        pushRedoSnapshot()
        restoreUndoSnapshot(snapshot)
        statusMessage = "Undid the last change"
    }

    func redoDocumentChange() {
        finishUndoEditCoalescing()
        guard let snapshot = documentRedoStack.popLast() else {
            statusMessage = "Nothing to redo"
            return
        }
        documentUndoStack.append(
            WorkspaceDocumentUndoSnapshot(
                document: document,
                selectedCardID: selectedCardID,
                selectedCardIDs: selectedCardIDs,
                browserInlineEditorCardID: browserInlineEditorCardID,
                hasUnsavedChanges: hasUnsavedChanges
            )
        )
        restoreUndoSnapshot(snapshot)
        statusMessage = "Redid the last change"
    }

    private func pushRedoSnapshot() {
        documentRedoStack.append(
            WorkspaceDocumentUndoSnapshot(
                document: document,
                selectedCardID: selectedCardID,
                selectedCardIDs: selectedCardIDs,
                browserInlineEditorCardID: browserInlineEditorCardID,
                hasUnsavedChanges: hasUnsavedChanges
            )
        )
        if documentRedoStack.count > maxDocumentUndoSnapshots {
            documentRedoStack.removeFirst(documentRedoStack.count - maxDocumentUndoSnapshots)
        }
    }

    private func pushUndoSnapshot() {
        documentRedoStack.removeAll(keepingCapacity: true)
        documentUndoStack.append(
            WorkspaceDocumentUndoSnapshot(
                document: document,
                selectedCardID: selectedCardID,
                selectedCardIDs: selectedCardIDs,
                browserInlineEditorCardID: browserInlineEditorCardID,
                hasUnsavedChanges: hasUnsavedChanges
            )
        )
        if documentUndoStack.count > maxDocumentUndoSnapshots {
            documentUndoStack.removeFirst(documentUndoStack.count - maxDocumentUndoSnapshots)
        }
    }

    private func restoreUndoSnapshot(_ snapshot: WorkspaceDocumentUndoSnapshot) {
        document = snapshot.document
        selectedCardID = snapshot.selectedCardID
        selectedCardIDs = snapshot.selectedCardIDs
        browserInlineEditorCardID = snapshot.browserInlineEditorCardID
        hasUnsavedChanges = snapshot.hasUnsavedChanges
        syncDocumentMetadataFromSettings()
        clearRenderingCaches()
        clearCanvasTransientState()
        markBrowserSurfaceContentDirty()
    }
}
