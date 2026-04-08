import SwiftUI
import AppKit
import ImageIO

private enum BrowserGestureMode {
    case movingSelection
    case creatingLink(sourceCardID: Int)
    case panning(originCenter: FrievePoint)
    case marquee(additive: Bool)
}

private struct BrowserPerformanceMetric {
    var lastMilliseconds: Double = 0
    var rollingMilliseconds: Double = 0

    mutating func record(_ milliseconds: Double) {
        lastMilliseconds = milliseconds
        rollingMilliseconds = rollingMilliseconds == 0 ? milliseconds : (rollingMilliseconds * 0.82 + milliseconds * 0.18)
    }
}

private struct BrowserPerformanceSnapshot {
    var visibleCards = BrowserPerformanceMetric()
    var visibleLinks = BrowserPerformanceMetric()
    var overview = BrowserPerformanceMetric()
    var drag = BrowserPerformanceMetric()

    func summary() -> String {
        String(
            format: "Browser %.1f/%.1f/%.1f/%.1f ms",
            visibleCards.rollingMilliseconds,
            visibleLinks.rollingMilliseconds,
            overview.rollingMilliseconds,
            drag.rollingMilliseconds
        )
    }
}

struct BrowserCardMetadata: Hashable {
    let labelNames: [String]
    let labelLine: String
    let summaryText: String
    let detailSummary: String
    let badges: [String]
    let canvasSize: CGSize
    let linkCount: Int
    let hasDrawingPreview: Bool
    let primaryLabelColor: Int?
    let mediaBadgeText: String
}

struct BrowserCardRenderData: Identifiable {
    let card: FrieveCard
    let position: FrievePoint
    let metadata: BrowserCardMetadata

    var id: Int { card.id }
}

struct BrowserLinkRenderData: Identifiable {
    let link: FrieveLink
    let start: CGPoint
    let end: CGPoint
    let path: CGPath
    let arrowHead: CGPath?
    let labelPoint: CGPoint?
    let isHighlighted: Bool

    var id: UUID { link.id }
}

enum BrowserCardDetailLevel: Int, Hashable {
    case thumbnail
    case compact
    case full
}

struct BrowserCardLayerSnapshot: Identifiable, Hashable {
    let card: FrieveCard
    let position: FrievePoint
    let metadata: BrowserCardMetadata
    let isSelected: Bool
    let isHovered: Bool
    let detailLevel: BrowserCardDetailLevel

    var id: Int { card.id }
}

struct BrowserLinkLayerSnapshot: Identifiable {
    let id: UUID
    let path: CGPath
    let arrowHead: CGPath?
    let labelPoint: CGPoint?
    let labelText: String?
    let isHighlighted: Bool
}

struct BrowserOverlaySnapshot {
    let selectionFrame: CGRect?
    let marqueeRect: CGRect?
    let linkPreviewSegment: (CGPoint, CGPoint)?
}

struct BrowserCardHitRegion: Hashable {
    let cardID: Int
    let frame: CGRect
}

struct BrowserSurfaceSceneSnapshot {
    let canvasSize: CGSize
    let worldToCanvasTransform: CGAffineTransform
    let backgroundGuidePath: CGPath
    let cards: [BrowserCardLayerSnapshot]
    let links: [BrowserLinkLayerSnapshot]
    let hitRegions: [BrowserCardHitRegion]
    let overlay: BrowserOverlaySnapshot
    let viewportSummary: String
}

struct BrowserOverviewSnapshot: Hashable {
    struct CardPoint: Identifiable, Hashable {
        let cardID: Int
        let point: FrievePoint

        var id: Int { cardID }
    }

    struct LinkSegment: Identifiable, Hashable {
        let id: UUID
        let from: FrievePoint
        let to: FrievePoint
    }

    let bounds: CGRect
    let cards: [CardPoint]
    let links: [LinkSegment]
}

private struct BrowserOverviewCacheKey: Hashable {
    let documentVersion: Int
    let padding: UInt64
    let zoom: UInt64
    let baseScaleFactor: UInt64
    let dragTranslationX: UInt64
    let dragTranslationY: UInt64
    let draggedCardIDs: [Int]

    init(documentVersion: Int, padding: Double, zoom: Double, baseScaleFactor: Double, dragTranslation: FrievePoint?, draggedCardIDs: [Int]) {
        self.documentVersion = documentVersion
        self.padding = padding.bitPattern
        self.zoom = zoom.bitPattern
        self.baseScaleFactor = baseScaleFactor.bitPattern
        self.dragTranslationX = dragTranslation?.x.bitPattern ?? 0
        self.dragTranslationY = dragTranslation?.y.bitPattern ?? 0
        self.draggedCardIDs = draggedCardIDs
    }
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    var settings: AppSettings

    @Published var document: FrieveDocument {
        didSet { invalidateDocumentCaches() }
    }
    @Published var selectedCardID: Int?
    @Published var selectedCardIDs: Set<Int> = []
    @Published var selectedTab: WorkspaceTab = .browser {
        didSet { syncDocumentMetadataFromSettings() }
    }
    @Published var searchQuery: String = ""
    @Published var globalSearchQuery: String = "" {
        didSet { refreshSearchResults() }
    }
    @Published var statusMessage: String = "Ready"
    @Published var zoom: Double = 1.0
    @Published var autoScroll: Bool = false
    @Published var autoZoom: Bool = true
    @Published var linkLabelsVisible: Bool = true
    @Published var showOverview: Bool = true {
        didSet { settings.showOverview = showOverview }
    }
    @Published var showFileList: Bool = true {
        didSet { settings.showFileList = showFileList }
    }
    @Published var showCardList: Bool = true {
        didSet { settings.showCardList = showCardList }
    }
    @Published var showInspector: Bool = true {
        didSet { settings.showInspector = showInspector }
    }
    @Published var arrangeMode: String = "Link"
    @Published var selectedDrawingTool: String = "Cursor"
    @Published var recentFiles: [URL] = []
    @Published var globalSearchResults: [FrieveCard] = []
    @Published var lastGPTPrompt: String = ""
    @Published var browserViewportRevision: Int = 0
    @Published var canvasCenter: FrievePoint = .zero
    @Published var marqueeStartPoint: CGPoint?
    @Published var marqueeCurrentPoint: CGPoint?
    @Published var linkPreviewSourceCardID: Int?
    @Published var linkPreviewCanvasPoint: CGPoint?
    @Published var browserInlineEditorCardID: Int?
    @Published var browserHoverCardID: Int?

    private var dragOriginByCardID: [Int: FrievePoint] = [:]
    private var currentDragTranslation: FrievePoint?
    private let speechSynthesizer = NSSpeechSynthesizer()
    private var hasUnsavedChanges = false
    private var lastMutationAt = Date.distantPast
    private var lastAutoSaveAt = Date.distantPast
    private var lastAutoReloadCheckAt = Date.distantPast
    private var lastKnownFileModificationDate: Date?
    private var browserBaseScaleFactor: Double = 0.8
    private var browserGestureMode: BrowserGestureMode?
    private var gestureZoomStart: Double?
    private var drawingPreviewCache: [Int: (encoded: String, items: [DrawingPreviewItem])] = [:]
    private var drawingPreviewBoundsCache: [Int: (encoded: String, bounds: CGRect)] = [:]
    private var drawingPreviewImageCache: [String: NSImage] = [:]
    private var browserCardRasterCache: [String: NSImage] = [:]
    private var browserCardRasterCacheOrder: [String] = []
    private var drawingPreviewImageCacheOrder: [String] = []
    private var mediaImageCacheOrder: [String] = []
    private var mediaImageCache: [String: NSImage] = [:]
    private var mediaThumbnailTasks: Set<String> = []
    private var missingMediaCacheKeys: Set<String> = []
    private var browserPerformance = BrowserPerformanceSnapshot()

    private var documentCacheVersion: Int = 0
    private var cachedDocumentCacheVersion: Int = -1
    private var cardIndexByID: [Int: Int] = [:]
    private var sortedCardIDs: [Int] = []
    private var visibleSortedCardIDs: [Int] = []
    private var labelNameByID: [Int: String] = [:]
    private var labelColorByID: [Int: Int] = [:]
    private var linkCountByCardID: [Int: Int] = [:]
    private var linksByCardID: [Int: [FrieveLink]] = [:]
    private var cardMetadataByID: [Int: BrowserCardMetadata] = [:]
    private var cachedOverviewSnapshotKey: BrowserOverviewCacheKey?
    private var cachedOverviewSnapshot: BrowserOverviewSnapshot?

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        showOverview = settings.showOverview
        showFileList = settings.showFileList
        showCardList = settings.showCardList
        showInspector = settings.showInspector
        recentFiles = settings.recentFiles

        if let bundledHelp = Bundle.module.url(forResource: "help", withExtension: "fip"),
           let loaded = try? DocumentFileCodec.load(url: bundledHelp) {
            document = loaded
            selectedCardID = loaded.focusedCardID ?? loaded.cards.first?.id
            statusMessage = "Loaded bundled help"
            if recentFiles.isEmpty {
                recentFiles = [bundledHelp]
            }
            lastKnownFileModificationDate = fileModificationDate(for: bundledHelp)
        } else {
            let placeholder = FrieveDocument.placeholder()
            document = placeholder
            selectedCardID = placeholder.focusedCardID
            statusMessage = "Loaded placeholder document"
            lastKnownFileModificationDate = nil
        }

        if let selectedCardID {
            selectedCardIDs = [selectedCardID]
        }
        syncDocumentMetadataFromSettings()
        resetCanvasStateFromDocument()
        refreshSearchResults()
    }

    var filteredCards: [FrieveCard] {
        document.filteredCards(query: searchQuery)
    }

    var selectedCard: FrieveCard? {
        cardByID(selectedCardID)
    }

    var selectedCards: [FrieveCard] {
        sortedCards().filter { selectedCardIDs.contains($0.id) }
    }

    var selectedCardLinks: [FrieveLink] {
        linksForCard(selectedCardID)
    }

    var statisticsRows: [DocumentStatisticRow] {
        document.statisticsRows()
    }

    var browserPerformanceSummary: String {
        browserPerformance.summary()
    }

    var fileDisplayName: String {
        if let path = document.sourcePath {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "Unsaved.fip2"
    }

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
        }
        refreshSearchResults()
    }

    func clearSelection() {
        selectedCardIDs.removeAll()
        selectedCardID = nil
        browserInlineEditorCardID = nil
        document.focusedCardID = nil
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
        statusMessage = "Opened inline browser editor"
    }

    func dismissBrowserInlineEditor() {
        browserInlineEditorCardID = nil
    }

    func setBrowserHoverCard(_ cardID: Int?) {
        guard browserHoverCardID != cardID else { return }
        browserHoverCardID = cardID
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
                    self.objectWillChange.send()
                    self.cacheMediaImage(thumbnail, forKey: cacheKey)
                }
            }
        }
        return nil
    }

    func browserCardRasterCacheKey(for snapshot: BrowserCardLayerSnapshot, previewReady: Bool, drawingPreviewReady: Bool) -> String {
        [
            String(snapshot.card.id),
            String(snapshot.detailLevel.rawValue),
            snapshot.card.updated,
            snapshot.card.title,
            snapshot.metadata.summaryText,
            snapshot.metadata.labelLine,
            snapshot.metadata.detailSummary,
            snapshot.metadata.badges.joined(separator: "|"),
            snapshot.card.imagePath ?? "",
            snapshot.card.videoPath ?? "",
            previewReady ? "preview-ready" : "preview-pending",
            drawingPreviewReady ? "drawing-ready" : "drawing-none",
            "\(Int(snapshot.metadata.canvasSize.width.rounded()))x\(Int(snapshot.metadata.canvasSize.height.rounded()))"
        ].joined(separator: "::")
    }

    func browserCardRasterKey(for snapshot: BrowserCardLayerSnapshot) -> String {
        let previewReady = snapshot.detailLevel == .thumbnail ? false : cachedPreviewImage(for: snapshot.card) != nil
        let drawingPreviewReady = snapshot.detailLevel == .full
            ? cachedDrawingPreviewImage(for: snapshot.card, targetSize: CGSize(width: 96, height: 72)) != nil
            : false
        return browserCardRasterCacheKey(
            for: snapshot,
            previewReady: previewReady,
            drawingPreviewReady: drawingPreviewReady
        )
    }

    func cachedBrowserCardRaster(for snapshot: BrowserCardLayerSnapshot) -> NSImage? {
        cachedBrowserCardRaster(for: snapshot, cacheKey: browserCardRasterKey(for: snapshot))
    }

    func cachedBrowserCardRaster(for snapshot: BrowserCardLayerSnapshot, cacheKey: String) -> NSImage? {
        let previewImage = snapshot.detailLevel == .thumbnail ? nil : cachedPreviewImage(for: snapshot.card)
        let drawingPreviewImage = snapshot.detailLevel == .full
            ? cachedDrawingPreviewImage(for: snapshot.card, targetSize: CGSize(width: 96, height: 72))
            : nil
        if let cached = browserCardRasterCache[cacheKey] {
            touchBrowserCardRasterCacheKey(cacheKey)
            return cached
        }

        let renderer = ImageRenderer(
            content: BrowserCardRasterContentView(
                card: snapshot.card,
                metadata: snapshot.metadata,
                detailLevel: snapshot.detailLevel,
                fillColor: color(for: snapshot.card),
                previewImage: previewImage,
                drawingPreviewImage: drawingPreviewImage
            )
            .frame(width: snapshot.metadata.canvasSize.width, height: snapshot.metadata.canvasSize.height)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        browserCardRasterCache[cacheKey] = image
        touchBrowserCardRasterCacheKey(cacheKey)
        evictCacheIfNeeded(order: &browserCardRasterCacheOrder, storage: &browserCardRasterCache, maxEntries: 240)
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

    func focusBrowser(on cardID: Int) {
        guard let card = cardByID(cardID) else { return }
        canvasCenter = card.position
        statusMessage = "Centered browser on \(card.title)"
    }

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
        clearCanvasTransientState()
    }

    func zoomIn() {
        zoom = min(zoom * 1.15, 6.0)
    }

    func zoomOut() {
        zoom = max(zoom / 1.15, 0.2)
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

    private func cardWorldFrame(for card: FrieveCard, in size: CGSize) -> CGRect {
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

    func browserSurfaceScene(in size: CGSize, canvasPadding: CGFloat = 260) -> BrowserSurfaceSceneSnapshot {
        let detailLevel = browserCardDetailLevel()
        let visibleCards = visibleBrowserCards(in: size, canvasPadding: canvasPadding)
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
        return BrowserSurfaceSceneSnapshot(
            canvasSize: size,
            worldToCanvasTransform: browserWorldToCanvasTransform(in: size),
            backgroundGuidePath: browserBackgroundGuideCGPath(in: size),
            cards: cards,
            links: links,
            hitRegions: hitRegions,
            overlay: BrowserOverlaySnapshot(
                selectionFrame: selectionFrame(in: size),
                marqueeRect: marqueeRect(),
                linkPreviewSegment: linkPreviewSegment(in: size)
            ),
            viewportSummary: browserViewportSummary(in: size)
        )
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
                path: buildLinkPath(for: link, start: start, end: end, baseScale: CGFloat(scale)),
                arrowHead: buildLinkArrowHead(for: link, start: start, end: end, baseScale: CGFloat(scale)),
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

    func browserViewportSummary(in size: CGSize) -> String {
        let visible = visibleWorldRect(in: size)
        let centerX = String(format: "%.2f", canvasCenter.x)
        let centerY = String(format: "%.2f", canvasCenter.y)
        let width = String(format: "%.2f", Double(visible.width))
        let height = String(format: "%.2f", Double(visible.height))
        return "Center \(centerX), \(centerY) · View \(width) × \(height)"
    }

    func color(for card: FrieveCard) -> Color {
        if let labelColor = metadata(for: card).primaryLabelColor {
            return Color(frieveRGB: labelColor)
        }

        if card.isTop {
            return Color.accentColor.opacity(0.20)
        }

        let normalizedScore = max(min(card.score, 5.0), -5.0)
        if normalizedScore >= 0 {
            return Color(red: 0.96 - normalizedScore * 0.03,
                         green: 0.96,
                         blue: 0.96 - normalizedScore * 0.08)
        }

        return Color(red: 0.96,
                     green: 0.95 + normalizedScore * 0.02,
                     blue: 0.96 + normalizedScore * 0.05)
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
        case .marquee:
            marqueeStartPoint = start
            marqueeCurrentPoint = current
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
            }
            linkPreviewSourceCardID = cardID
            linkPreviewCanvasPoint = nil
            browserGestureMode = .creatingLink(sourceCardID: cardID)
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
        case .creatingLink:
            linkPreviewCanvasPoint = currentPoint
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
            x: canvasCenter.x + Double(horizontalDelta) / scale,
            y: canvasCenter.y + Double(deltaY) / scale
        )
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
                noteDocumentMutation(status: selectedCardIDs.count > 1 ? "Moved \(selectedCardIDs.count) selected cards" : "Moved the selected card", updateSearch: false)
            }
        case .none, .panning, .marquee:
            break
        }

        dragOriginByCardID.removeAll()
        currentDragTranslation = nil
        clearCanvasTransientState()
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
    }

    func endMagnification() {
        gestureZoomStart = nil
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
    }

    private func adaptiveBrowserGridStep(in size: CGSize) -> Double {
        let desiredWorldSpacing = 96.0 / max(browserScale(in: size), 1)
        let candidates: [Double] = [0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10]
        return candidates.first(where: { $0 >= desiredWorldSpacing }) ?? 10
    }

    private func appendLinkIfNeeded(from sourceCardID: Int, to targetCardID: Int, name: String) {
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

    private func linkEndpoints(for link: FrieveLink, in size: CGSize) -> (start: CGPoint, end: CGPoint)? {
        guard let from = cardByID(link.fromCardID),
              let to = cardByID(link.toCardID) else { return nil }
        return (canvasPosition(for: from, in: size), canvasPosition(for: to, in: size))
    }

    private func selectionWorldBounds() -> CGRect? {
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

    private func applyMarqueeSelection(in size: CGSize, additive: Bool) {
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
        refreshSearchResults()
    }

    private func persistDocument(to url: URL, isAutomatic: Bool) {
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

    private func autoSaveIfNeeded(now: Date) {
        guard hasUnsavedChanges, let sourcePath = document.sourcePath else { return }
        let minInterval = TimeInterval(max(settings.autoSaveMinIntervalSec, 1))
        let idleInterval = TimeInterval(max(settings.autoSaveIdleSec, 1))
        guard now.timeIntervalSince(lastMutationAt) >= idleInterval else { return }
        guard now.timeIntervalSince(lastAutoSaveAt) >= minInterval else { return }
        persistDocument(to: URL(fileURLWithPath: sourcePath), isAutomatic: true)
    }

    private func reloadDocumentFromDiskIfNeeded(now: Date) {
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
            refreshSearchResults()
            statusMessage = "Reloaded \(url.lastPathComponent) from disk"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func syncDocumentMetadataFromSettings() {
        document.metadata["Title"] = document.title
        document.metadata["DefaultView"] = String(WorkspaceTab.allCases.firstIndex(of: selectedTab) ?? 0)
        document.metadata["AutoSave"] = settings.autoSaveDefault ? "1" : "0"
        document.metadata["AutoReload"] = settings.autoReloadDefault ? "1" : "0"
        document.metadata["Language"] = settings.language
        document.metadata["WebSearch"] = settings.preferredWebSearchName
        document.metadata["GPTModel"] = settings.gptModel
        document.metadata["ReadSpeed"] = String(Int(settings.readAloudRate))
    }

    private func noteDocumentMutation(status: String? = nil, updateSearch: Bool = true) {
        hasUnsavedChanges = true
        lastMutationAt = Date()
        syncDocumentMetadataFromSettings()
        if let status {
            statusMessage = status
        }
        if updateSearch {
            refreshSearchResults()
        }
    }

    private func resetCanvasStateFromDocument() {
        clearRenderingCaches()
        canvasCenter = selectedCard?.position ?? FrievePoint(x: 0.5, y: 0.5)
        zoom = 1.0
        browserBaseScaleFactor = 0.8
        requestBrowserFit()
        clearCanvasTransientState()
    }

    private func clearRenderingCaches() {
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

    private func clearCanvasTransientState() {
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
    }

    private func selectedNarrationText() -> String {
        guard let card = selectedCard else { return "" }
        return [card.title, card.bodyText]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private func selectedWebSearchQuery() -> String {
        if !globalSearchQuery.trimmed.isEmpty {
            return globalSearchQuery.trimmed
        }
        if selectedCardIDs.count > 1 {
            return selectedCards.map(\.title).joined(separator: " ")
        }
        guard let card = selectedCard else { return "" }
        return [card.title, card.summary]
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func selectedGPTPrompt() -> String {
        guard let card = selectedCard else {
            return settings.gptSystemPrompt
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
            "Document Title: \(document.title)",
            "Selected Card ID: \(card.id)",
            "Selected Card Title: \(card.title)",
            "Labels: \(labels.isEmpty ? "None" : labels)",
            "Related Cards: \(relatedTitles.isEmpty ? "None" : relatedTitles)",
            "Body:",
            card.bodyText
        ].joined(separator: "\n")
    }

    private func saveTextExport(_ text: String, defaultName: String) {
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

    private func ensureDocumentCaches() {
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
            let canvasSize = buildCardCanvasSize(for: card, summaryText: summaryText, labelLine: labelLine, badges: badges, detailSummary: detailSummary)
            metadataCache[card.id] = BrowserCardMetadata(
                labelNames: labelNames,
                labelLine: labelLine,
                summaryText: summaryText,
                detailSummary: detailSummary,
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

    private func invalidateDocumentCaches() {
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
    }

    private func sortedCards() -> [FrieveCard] {
        ensureDocumentCaches()
        return sortedCardIDs.compactMap(cardByID)
    }

    private func visibleSortedCards() -> [FrieveCard] {
        ensureDocumentCaches()
        return visibleSortedCardIDs.compactMap(cardByID)
    }

    private func cardByID(_ id: Int?) -> FrieveCard? {
        guard let id else { return nil }
        ensureDocumentCaches()
        guard let index = cardIndexByID[id], document.cards.indices.contains(index) else { return nil }
        return document.cards[index]
    }

    private func linksForCard(_ cardID: Int?) -> [FrieveLink] {
        guard let cardID else { return [] }
        ensureDocumentCaches()
        return linksByCardID[cardID] ?? []
    }

    private func metadata(for card: FrieveCard) -> BrowserCardMetadata {
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
        return BrowserCardMetadata(
            labelNames: labelNames,
            labelLine: labelLine,
            summaryText: summaryText,
            detailSummary: detailSummary,
            badges: badges,
            canvasSize: buildCardCanvasSize(for: card, summaryText: summaryText, labelLine: labelLine, badges: badges, detailSummary: detailSummary),
            linkCount: linkCount,
            hasDrawingPreview: hasDrawingPreview,
            primaryLabelColor: primaryLabelColor,
            mediaBadgeText: card.mediaBadgeText
        )
    }

    private func currentPosition(for card: FrieveCard) -> FrievePoint {
        guard let origin = dragOriginByCardID[card.id], let currentDragTranslation else {
            return card.position
        }
        return FrievePoint(x: origin.x + currentDragTranslation.x, y: origin.y + currentDragTranslation.y)
    }

    private func recordPerformanceMetric(_ start: CFTimeInterval, keyPath: WritableKeyPath<BrowserPerformanceSnapshot, BrowserPerformanceMetric>) {
        let elapsed = max((CACurrentMediaTime() - start) * 1000, 0)
        browserPerformance[keyPath: keyPath].record(elapsed)
    }

    private func touchBrowserCardRasterCacheKey(_ key: String) {
        browserCardRasterCacheOrder.removeAll { $0 == key }
        browserCardRasterCacheOrder.append(key)
    }

    private func touchDrawingPreviewCacheKey(_ key: String) {
        drawingPreviewImageCacheOrder.removeAll { $0 == key }
        drawingPreviewImageCacheOrder.append(key)
    }

    private func touchMediaImageCacheKey(_ key: String) {
        mediaImageCacheOrder.removeAll { $0 == key }
        mediaImageCacheOrder.append(key)
    }

    private func cacheMediaImage(_ image: NSImage, forKey key: String) {
        mediaImageCache[key] = image
        touchMediaImageCacheKey(key)
        evictCacheIfNeeded(order: &mediaImageCacheOrder, storage: &mediaImageCache, maxEntries: 96)
    }

    private func cacheDrawingPreviewImage(_ image: NSImage, forKey key: String) {
        drawingPreviewImageCache[key] = image
        touchDrawingPreviewCacheKey(key)
        evictCacheIfNeeded(order: &drawingPreviewImageCacheOrder, storage: &drawingPreviewImageCache, maxEntries: 160)
    }

    private func evictCacheIfNeeded(order: inout [String], storage: inout [String: NSImage], maxEntries: Int) {
        while order.count > maxEntries {
            let evictedKey = order.removeFirst()
            storage.removeValue(forKey: evictedKey)
        }
    }

    private func buildBrowserBadgeItems(for card: FrieveCard, labelNames: [String], linkCount: Int, hasDrawingPreview: Bool) -> [String] {
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
        if linkCount > 0 {
            badges.append("Links \(linkCount)")
        }
        if !labelNames.isEmpty {
            badges.append(contentsOf: labelNames.prefix(2))
        }
        return Array(badges.prefix(6))
    }

    private func buildBrowserSummaryText(for card: FrieveCard) -> String {
        let compact = card.bodyText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? "No body text" : String(compact.prefix(96))
    }

    private func buildBrowserDetailSummary(for card: FrieveCard, hasDrawingPreview: Bool) -> String {
        var segments = [card.shapeName]
        if card.hasMedia {
            segments.append("Media")
        }
        if hasDrawingPreview {
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

    private func buildCardCanvasSize(for card: FrieveCard, summaryText: String, labelLine: String, badges: [String], detailSummary: String) -> CGSize {
        let baseWidth = CGFloat(max(180, min(card.size + 120, 320)))
        var height = CGFloat(max(120, min(card.size + 24, 260)))
        if card.hasMedia {
            height += 80
        }
        if !card.isFolded {
            height += CGFloat(min(summaryText.count / 24, 3)) * 18
        }
        if !labelLine.isEmpty {
            height += 22
        }
        if !detailSummary.isEmpty {
            height += 16
        }
        if !badges.isEmpty {
            height += 24
        }
        return CGSize(width: baseWidth, height: min(max(height, 130), 360))
    }

    private func browserCardDetailLevel() -> BrowserCardDetailLevel {
        switch zoom {
        case ..<0.7:
            return .thumbnail
        case ..<1.35:
            return .compact
        default:
            return .full
        }
    }

    private func browserWorldToCanvasTransform(in size: CGSize) -> CGAffineTransform {
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

    private func buildLinkPath(for link: FrieveLink, start: CGPoint, end: CGPoint, baseScale: CGFloat = 1) -> CGPath {
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

    private func buildLinkArrowHead(for link: FrieveLink, start: CGPoint, end: CGPoint, baseScale: CGFloat = 1) -> CGPath? {
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

    private func buildLinkLabelPoint(for link: FrieveLink, start: CGPoint, end: CGPoint, baseScale: CGFloat = 1) -> CGPoint? {
        let name = link.name.trimmed
        guard !name.isEmpty else { return nil }
        let verticalOffset = 8 / max(baseScale, 0.0001)
        return CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - verticalOffset)
    }

    private func drawingPreviewBounds(for items: [DrawingPreviewItem]) -> CGRect {
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

    private func drawingPreviewSourceRect(for item: DrawingPreviewItem) -> CGRect {
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

    private func mapDrawingPoint(_ point: FrievePoint, from source: CGRect, to size: CGSize) -> CGPoint {
        let inset: CGFloat = 4
        let usableWidth = max(size.width - inset * 2, 1)
        let usableHeight = max(size.height - inset * 2, 1)
        let x = ((point.x - source.minX) / max(source.width, 1)) * usableWidth + inset
        let y = ((point.y - source.minY) / max(source.height, 1)) * usableHeight + inset
        return CGPoint(x: x, y: y)
    }

    private func mapDrawingRect(_ rect: CGRect, from source: CGRect, to size: CGSize) -> CGRect {
        let p1 = mapDrawingPoint(FrievePoint(x: rect.minX, y: rect.minY), from: source, to: size)
        let p2 = mapDrawingPoint(FrievePoint(x: rect.maxX, y: rect.maxY), from: source, to: size)
        return CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    private func renderDrawingPreviewImage(items: [DrawingPreviewItem], sourceBounds: CGRect, targetSize: CGSize, colorProvider: @escaping (Int?, Color) -> Color) -> NSImage? {
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

    private nonisolated static func loadThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
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

    private func sharedISOTimestamp() -> String {
        isoTimestamp()
    }

    private func recordRecent(_ url: URL) {
        settings.recordRecent(url: url)
        recentFiles = settings.recentFiles
    }

    private func copyTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func fileModificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}

extension Color {
    init(frieveRGB value: Int) {
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
