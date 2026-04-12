import SwiftUI
import AppKit
import AVFoundation

enum CardSortOrder: String, CaseIterable, Identifiable {
    case title
    case titleInverse
    case dateCreated
    case dateCreatedInverse
    case dateEdited
    case dateEditedInverse
    case dateViewed
    case dateViewedInverse
    case score
    case scoreInverse
    case shuffle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .titleInverse: "Title (Inverse)"
        case .dateCreated: "Date Created"
        case .dateCreatedInverse: "Date Created (Inverse)"
        case .dateEdited: "Date Edited"
        case .dateEditedInverse: "Date Edited (Inverse)"
        case .dateViewed: "Date Viewed"
        case .dateViewedInverse: "Date Viewed (Inverse)"
        case .score: "Score"
        case .scoreInverse: "Score (Inverse)"
        case .shuffle: "Shuffle"
        }
    }
}

enum BrowserGestureMode {
    case movingSelection
    case creatingLink(sourceCardID: Int)
    case panning(originCenter: FrievePoint)
    case marquee(additive: Bool)
}

struct BrowserPerformanceMetric {
    var lastMilliseconds: Double = 0
    var rollingMilliseconds: Double = 0

    var lastFPS: Double {
        guard lastMilliseconds > 0.0001 else { return 0 }
        return 1000.0 / lastMilliseconds
    }

    var rollingFPS: Double {
        guard rollingMilliseconds > 0.0001 else { return 0 }
        return 1000.0 / rollingMilliseconds
    }

    mutating func record(_ milliseconds: Double) {
        lastMilliseconds = milliseconds
        rollingMilliseconds = rollingMilliseconds == 0 ? milliseconds : (rollingMilliseconds * 0.82 + milliseconds * 0.18)
    }
}

struct BrowserPerformanceSnapshot {
    var frameInterval = BrowserPerformanceMetric()
    var visibleCards = BrowserPerformanceMetric()
    var visibleLinks = BrowserPerformanceMetric()
    var overview = BrowserPerformanceMetric()
    var drag = BrowserPerformanceMetric()
    var surfaceScene = BrowserPerformanceMetric()
    var surfaceApply = BrowserPerformanceMetric()
    var cardRaster = BrowserPerformanceMetric()

    func summary() -> String {
        String(
            format: "Browser %.0f fps cards %.1f links %.1f scene %.1f apply %.1f raster %.1f drag %.1f ms",
            frameInterval.rollingFPS,
            visibleCards.rollingMilliseconds,
            visibleLinks.rollingMilliseconds,
            surfaceScene.rollingMilliseconds,
            surfaceApply.rollingMilliseconds,
            cardRaster.rollingMilliseconds,
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
    let fromCardID: Int
    let toCardID: Int
    let startPoint: CGPoint
    let endPoint: CGPoint
    let shapeIndex: Int
    let directionVisible: Bool
    let labelPoint: CGPoint?
    let labelText: String?
    let isHighlighted: Bool
}

struct BrowserLabelGroupLayerSnapshot: Identifiable, Hashable {
    let id: Int
    let name: String
    let color: Int
    let worldRect: CGRect
    let labelSize: Int
    let prefersNameAbove: Bool
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
    let cardSnapshotSignature: Int
    let links: [BrowserLinkLayerSnapshot]
    let linkSnapshotSignature: Int
    let labelGroups: [BrowserLabelGroupLayerSnapshot]
    let hitRegions: [BrowserCardHitRegion]
    let overlay: BrowserOverlaySnapshot
    let overlaySignature: Int
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

struct BrowserOverviewCacheKey: Hashable {
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

struct BrowserSurfaceContentCacheKey: Hashable {
    let contentRevision: Int
    let sceneScale: UInt64
    let detailLevel: BrowserCardDetailLevel
    let canvasWidth: UInt64
    let canvasHeight: UInt64
    let canvasPadding: UInt64
    let labelsVisible: Bool

    init(contentRevision: Int, sceneScale: Double, detailLevel: BrowserCardDetailLevel, canvasSize: CGSize, canvasPadding: CGFloat, labelsVisible: Bool) {
        self.contentRevision = contentRevision
        self.sceneScale = sceneScale.bitPattern
        self.detailLevel = detailLevel
        self.canvasWidth = Double(canvasSize.width).bitPattern
        self.canvasHeight = Double(canvasSize.height).bitPattern
        self.canvasPadding = Double(canvasPadding).bitPattern
        self.labelsVisible = labelsVisible
    }
}

struct BrowserSurfaceContentCacheEntry {
    let coverageRect: CGRect
    let cards: [BrowserCardLayerSnapshot]
    let cardSnapshotSignature: Int
    let links: [BrowserLinkLayerSnapshot]
    let linkSnapshotSignature: Int
    let labelGroups: [BrowserLabelGroupLayerSnapshot]
    let hitRegions: [BrowserCardHitRegion]
}

struct EditorRelatedCardLine: Identifiable, Hashable {
    let cardID: Int
    let relation: String
    let text: String

    var id: Int { cardID }
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
        didSet {
            syncDocumentMetadataFromSettings()
            updateBrowserAutoArrangeTimerState()
        }
    }
    @Published var searchQuery: String = ""
    @Published var cardSortOrder: CardSortOrder = .title
@Published var statusMessage: String = "Ready"
    var zoom: Double = 1.0
    @Published var autoScroll: Bool = false {
        didSet {
            if autoScroll {
                prepareBrowserAutoScrollForSelectionChange()
            } else {
                resetBrowserAutoScrollAnimation()
            }
        }
    }
    @Published var autoZoom: Bool = true {
        didSet {
            guard autoZoom, selectedTab == .browser else { return }
            zoomToSelection(in: resolvedBrowserCanvasSize())
        }
    }
    @Published var linkLabelsVisible: Bool = true
    @Published var labelRectanglesVisible: Bool = true
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
    @Published var arrangeMode: String = "None" {
        didSet {
            guard arrangeMode != oldValue else { return }
            resetBrowserArrangeTransientState()
            if arrangeMode == "None" {
                browserAutoArrangeEnabled = false
            } else {
                browserAutoArrangeEnabled = true
                browserActiveArrangeMode = arrangeMode
            }
            updateBrowserAutoArrangeTimerState()
        }
    }
    @Published var browserAutoArrangeEnabled: Bool = false {
        didSet {
            if !browserAutoArrangeEnabled {
                browserActiveArrangeMode = nil
                resetBrowserArrangeTransientState()
            }
            updateBrowserAutoArrangeTimerState()
        }
    }
    @Published var statisticsKey: StatisticsGroupingKey = .label {
        didSet {
            guard statisticsKey != oldValue else { return }
            selectedStatisticsBucketID = nil
        }
    }
    @Published var statisticsSortByCount: Bool = false
    @Published var selectedStatisticsBucketID: String?
    @Published var selectedDrawingTool: String = "Cursor"
    @Published var recentFiles: [URL] = []
@Published var lastGPTPrompt: String = ""
    @Published var browserViewportRevision: Int = 0
    @Published var browserChromeRevision: Int = 0
    var browserSurfaceContentRevision: Int = 0
    var browserSurfaceViewportRevision: Int = 0
    var browserSurfacePresentationRevision: Int = 0
    var canvasCenter: FrievePoint = .zero
    var marqueeStartPoint: CGPoint?
    var marqueeCurrentPoint: CGPoint?
    var linkPreviewSourceCardID: Int?
    var linkPreviewCanvasPoint: CGPoint?
    var browserInlineEditorCardID: Int?
    var browserHoverCardID: Int?

    var dragOriginByCardID: [Int: FrievePoint] = [:]
    var currentDragTranslation: FrievePoint?
    let speechSynthesizer = AVSpeechSynthesizer()
    var hasUnsavedChanges = false
    var lastMutationAt = Date.distantPast
    var lastAutoSaveAt = Date.distantPast
    var lastAutoReloadCheckAt = Date.distantPast
    var lastKnownFileModificationDate: Date?
    var browserBaseScaleFactor: Double = 0.8
    var browserGestureMode: BrowserGestureMode?
    var gestureZoomStart: Double?
    var drawingPreviewCache: [Int: (encoded: String, items: [DrawingPreviewItem])] = [:]
    var drawingPreviewBoundsCache: [Int: (encoded: String, bounds: CGRect)] = [:]
    var drawingPreviewImageCache: [String: NSImage] = [:]
    var browserCardRasterCache: [String: NSImage] = [:]
    var browserCardRasterCacheOrder: [String] = []
    var drawingPreviewImageCacheOrder: [String] = []
    var mediaImageCacheOrder: [String] = []
    var mediaImageCache: [String: NSImage] = [:]
    var mediaThumbnailTasks: Set<String> = []
    var missingMediaCacheKeys: Set<String> = []
    var pendingBrowserCardRasterKeys: Set<String> = []
    var browserPerformance = BrowserPerformanceSnapshot()
    var browserLastPresentedFrameAt: CFTimeInterval = 0
    var browserCanvasSize: CGSize = .zero
    var browserMatrixTargetByCardID: [Int: FrievePoint] = [:]
    var browserMatrixSpeedByCardID: [Int: Double] = [:]
    var browserActiveArrangeMode: String?
    var browserAutoArrangeTimer: Timer?
    var browserAutoArrangeSuspendedUntil: CFTimeInterval = 0
    var browserAutoArrangeResumeWorkItem: DispatchWorkItem?
    var browserAutoScrollStartCenter: FrievePoint?
    var browserAutoScrollTargetCenter: FrievePoint?
    var browserAutoScrollStartedAt: CFTimeInterval?
    var browserAutoScrollSuspendedUntil: CFTimeInterval = 0
    var browserAutoScrollTimer: Timer?
    var browserInteractionModeEnabled: Bool = false
    var browserInteractionModeWorkItem: DispatchWorkItem?
    var browserInteractionModeRefreshHandler: ((Bool) -> Void)?
    var browserSurfaceContentRefreshHandler: (() -> Void)?
    var browserSurfacePresentationRefreshHandler: (() -> Void)?
    var browserSurfaceViewportRefreshHandler: (() -> Void)?
    var browserLastChromeRefreshAt: CFTimeInterval = 0
    var browserPendingChromeRefreshWorkItem: DispatchWorkItem?
    var documentUndoStack: [WorkspaceDocumentUndoSnapshot] = []
    var activeUndoEditCardID: Int?

    var documentCacheVersion: Int = 0
    var cachedDocumentCacheVersion: Int = -1
    var cardIndexByID: [Int: Int] = [:]
    var sortedCardIDs: [Int] = []
    var visibleSortedCardIDs: [Int] = []
    var labelNameByID: [Int: String] = [:]
    var labelColorByID: [Int: Int] = [:]
    var linkCountByCardID: [Int: Int] = [:]
    var linksByCardID: [Int: [FrieveLink]] = [:]
    var cardMetadataByID: [Int: BrowserCardMetadata] = [:]
    var cachedOverviewSnapshotKey: BrowserOverviewCacheKey?
    var cachedOverviewSnapshot: BrowserOverviewSnapshot?
    var cachedBrowserSurfaceContentKey: BrowserSurfaceContentCacheKey?
    var cachedBrowserSurfaceContent: BrowserSurfaceContentCacheEntry?

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
    }

    var filteredCards: [FrieveCard] {
        let base = document.filteredCards(query: searchQuery)
        return sortCards(base, by: cardSortOrder)
    }

    private func sortCards(_ cards: [FrieveCard], by order: CardSortOrder) -> [FrieveCard] {
        switch order {
        case .title:
            return cards
        case .titleInverse:
            return cards.reversed()
        case .dateCreated:
            return cards.sorted { $0.created.localizedStandardCompare($1.created) == .orderedAscending }
        case .dateCreatedInverse:
            return cards.sorted { $0.created.localizedStandardCompare($1.created) == .orderedDescending }
        case .dateEdited:
            return cards.sorted { $0.updated.localizedStandardCompare($1.updated) == .orderedAscending }
        case .dateEditedInverse:
            return cards.sorted { $0.updated.localizedStandardCompare($1.updated) == .orderedDescending }
        case .dateViewed:
            return cards.sorted { $0.viewed.localizedStandardCompare($1.viewed) == .orderedAscending }
        case .dateViewedInverse:
            return cards.sorted { $0.viewed.localizedStandardCompare($1.viewed) == .orderedDescending }
        case .score:
            return cards.sorted { $0.score < $1.score }
        case .scoreInverse:
            return cards.sorted { $0.score > $1.score }
        case .shuffle:
            return cards.shuffled()
        }
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

    var statisticsBuckets: [DocumentStatisticBucket] {
        document.statisticsBuckets(for: statisticsKey, sortByCount: statisticsSortByCount)
    }

    var selectedStatisticsBucket: DocumentStatisticBucket? {
        statisticsBuckets.first { $0.id == selectedStatisticsBucketID }
    }

    func statisticsCards(for bucket: DocumentStatisticBucket) -> [FrieveCard] {
        document.statisticsCards(for: bucket)
    }

    func selectStatisticsBucket(_ bucket: DocumentStatisticBucket) {
        selectedStatisticsBucketID = bucket.id
    }

    func selectedStatisticsCardID(in bucket: DocumentStatisticBucket) -> Int? {
        guard let selectedCardID, bucket.cardIDs.contains(selectedCardID) else { return nil }
        return selectedCardID
    }

    func selectStatisticsCard(_ cardID: Int?) {
        guard let cardID else {
            clearSelection()
            return
        }
        selectCard(cardID)
    }

    func focusStatisticsCardInBrowser(_ cardID: Int) {
        selectedCardID = cardID
        selectedCardIDs = [cardID]
        selectedTab = .browser
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

    var documentURL: URL? {
        guard let path = document.sourcePath else { return nil }
        return URL(fileURLWithPath: path)
    }
}
