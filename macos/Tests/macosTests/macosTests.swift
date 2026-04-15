import Foundation
import AppKit
import MetalKit
import SwiftUI
import Testing
@testable import macos

@Test func placeholderDocumentHasFocusableRootCard() async throws {
    let document = FrieveDocument.placeholder()

    #expect(document.cardCount == 1)
    #expect(document.focusedCardID == 0)
    #expect(document.cards.first?.title == "Frieve Editor")
}

@MainActor
@Test func browserDefaultsEnableAutoScroll() async throws {
    let model = WorkspaceViewModel()

    #expect(model.autoScroll)
}

@MainActor
@Test func browserCardTextPrefersHoverAndFallsBackToSelection() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.addChildCard()
    let childID = try #require(model.selectedCardID)
    model.document.updateCard(childID) { card in
        card.title = "Child"
        card.bodyText = "Selected body"
    }

    model.selectCard(0)
    model.document.updateCard(0) { card in
        card.title = "Root"
        card.bodyText = "Root body"
    }

    #expect(model.browserCardTextCard?.id == 0)
    #expect(model.browserCardTextCard?.bodyText == "Root body")

    model.setBrowserHoverCard(childID)

    #expect(model.browserCardTextCard?.id == childID)
    #expect(model.browserCardTextCard?.bodyText == "Selected body")

    model.setBrowserHoverCard(nil)

    #expect(model.browserCardTextCard?.id == 0)
}

@MainActor
@Test func openCardInEditorSelectsCardAndSwitchesToEditorTab() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.addChildCard()
    let childID = try #require(model.selectedCardID)
    model.selectedTab = .browser
    model.selectCard(0)

    model.openCardInEditor(childID)

    #expect(model.selectedCardID == childID)
    #expect(model.selectedCardIDs == [childID])
    #expect(model.selectedTab == .editor)
    #expect(model.editorBodyFocusTrigger)
}

@Test func browserAppearanceHelperMatchesSwiftUIColorScheme() throws {
    #expect(browserAppearance(for: .light).bestMatch(from: [.aqua, .darkAqua]) == .aqua)
    #expect(browserAppearance(for: .dark).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
}

@Test func browserWallpaperRectUsesFillForFixedAndFitOtherwise() throws {
    let viewport = CGRect(x: 0, y: 0, width: 300, height: 300)
    let fitRect = browserWallpaperRect(
        for: CGSize(width: 400, height: 200),
        in: viewport,
        fixed: false
    )
    let fillRect = browserWallpaperRect(
        for: CGSize(width: 400, height: 200),
        in: viewport,
        fixed: true
    )

    #expect(fitRect == CGRect(x: 0, y: 75, width: 300, height: 150))
    #expect(fillRect == CGRect(x: -150, y: 0, width: 600, height: 300))
}

@Test func browserCanvasBackgroundHelperMatchesColorScheme() throws {
    let light = browserCanvasBackgroundColor(for: .light).usingColorSpace(.deviceRGB)
    let dark = browserCanvasBackgroundColor(for: .dark).usingColorSpace(.deviceRGB)

    #expect(light != nil)
    #expect(dark != nil)
    #expect(dark?.redComponent != light?.redComponent || dark?.greenComponent != light?.greenComponent || dark?.blueComponent != light?.blueComponent)
}

@Test func browserFlowingLineParticlesMixHorizontalAndVerticalMotion() throws {
    let particles = browserFlowingLineParticles(in: CGSize(width: 1280, height: 720), time: 2.0)

    #expect(particles.count == 28)
    #expect(particles.contains(where: { $0.isMostlyHorizontal }))
    #expect(particles.contains(where: { !$0.isMostlyHorizontal }))

    let advanced = browserFlowingLineParticles(in: CGSize(width: 1280, height: 720), time: 3.0)
    let movedHorizontally = zip(particles, advanced).contains { initial, next in
        initial.isMostlyHorizontal && abs(next.start.x - initial.start.x) > 20
    }
    let movedVertically = zip(particles, advanced).contains { initial, next in
        !initial.isMostlyHorizontal && abs(next.start.y - initial.start.y) > 20
    }

    #expect(movedHorizontally)
    #expect(movedVertically)
}

@Test func browserBubbleParticlesDriftSidewaysWhileRising() throws {
    let initial = browserBubbleParticles(in: CGSize(width: 1280, height: 720), time: 1.0)
    let later = browserBubbleParticles(in: CGSize(width: 1280, height: 720), time: 2.0)

    #expect(initial.count == 36)
    #expect(Set(initial.map { Int($0.rect.width.rounded()) }).count > 6)
    #expect(zip(initial, later).contains { first, second in second.rect.midY < first.rect.midY - 8 })
    #expect(zip(initial, later).contains { first, second in abs(second.rect.midX - first.rect.midX) > 6 })
}

@Test func browserSnowParticlesFallWithSideDrift() throws {
    let initial = browserSnowParticles(in: CGSize(width: 1280, height: 720), time: 1.0)
    let later = browserSnowParticles(in: CGSize(width: 1280, height: 720), time: 2.0)

    #expect(initial.count == 64)
    #expect(Set(initial.map { Int($0.rect.width.rounded()) }).count >= 4)
    #expect(zip(initial, later).contains { first, second in second.rect.midY > first.rect.midY + 8 })
    #expect(zip(initial, later).contains { first, second in abs(second.rect.midX - first.rect.midX) > 4 })
}

@Test func browserPetalParticlesKeepStableOpacityWhileDrifting() throws {
    let initial = browserPetalParticles(in: CGSize(width: 1280, height: 720), time: 1.0)
    let later = browserPetalParticles(in: CGSize(width: 1280, height: 720), time: 2.0)

    #expect(initial.count == 30)
    #expect(zip(initial, later).allSatisfy { first, second in abs(first.opacity - second.opacity) < 0.0001 })
    #expect(zip(initial, later).contains { first, second in second.center.y > first.center.y + 6 })
    #expect(zip(initial, later).contains { first, second in abs(second.center.x - first.center.x) > 4 })
    #expect(zip(initial, later).contains { first, second in abs(second.center.x - first.center.x) > 20 })
    #expect(zip(initial, later).contains { first, second in abs(second.rotation.radians - first.rotation.radians) > 0.1 })
}

@Test func browserLinkStrokePaletteMatchesColorScheme() throws {
    let light = browserLinkStrokeColor(for: .light, highlighted: false).usingColorSpace(.deviceRGB)
    let dark = browserLinkStrokeColor(for: .dark, highlighted: false).usingColorSpace(.deviceRGB)
    let lightHighlighted = browserLinkStrokeColor(for: .light, highlighted: true).usingColorSpace(.deviceRGB)
    let darkHighlighted = browserLinkStrokeColor(for: .dark, highlighted: true).usingColorSpace(.deviceRGB)

    #expect(light != nil)
    #expect(dark != nil)
    #expect(lightHighlighted != nil)
    #expect(darkHighlighted != nil)
    #expect(light != dark)
    #expect(lightHighlighted != darkHighlighted)
}

@MainActor
@Test func browserCanvasClearColorVariesByAppearance() throws {
    let view = BrowserSurfaceNSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))

    view.updateColorScheme(.light)
    let lightLuminance = browserTestLuminance(from: view.browserCanvasClearColor)

    view.updateColorScheme(.dark)
    let darkLuminance = browserTestLuminance(from: view.browserCanvasClearColor)

    #expect(lightLuminance != nil)
    #expect(darkLuminance != nil)
    #expect(darkLuminance! < lightLuminance!)
}

@MainActor
@Test func browserSurfaceBecomesTransparentForWallpaperAndBackgroundAnimation() throws {
    let suiteName = "FrieveEditorMacTests.browserBackgroundTransparency"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    let view = BrowserSurfaceNSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
    view.viewModel = model

    model.settings.browserWallpaperPath = "/tmp/wallpaper.png"
    view.updateColorScheme(.light)
    let wallpaperAlpha = view.browserCanvasClearColor.alpha

    model.settings.browserWallpaperPath = ""
    model.settings.browserBackgroundAnimation = true
    view.updateColorScheme(.light)
    let animationAlpha = view.browserCanvasClearColor.alpha

    #expect(view.isOpaque == false)
    #expect(wallpaperAlpha < 1)
    #expect(animationAlpha < 1)
}

@MainActor
@Test func browserParentsRenderInFrontUnlessChildIsSelected() throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.document.updateCard(0) { card in
        card.title = "A Parent"
    }
    let childID = model.document.addCard(title: "Z Child", linkedFrom: 0)

    let scene = model.browserSurfaceScene(in: CGSize(width: 1200, height: 800))
    #expect(scene.cards.map(\.id) == [childID, 0])

    model.selectedCardID = childID
    model.selectedCardIDs = [childID]

    let selectedScene = model.browserSurfaceScene(in: CGSize(width: 1200, height: 800))
    #expect(selectedScene.cards.map(\.id) == [0, childID])
}

@MainActor
@Test func browserTickerExpandsCardHeightAndUsesBodyLines() throws {
    let suiteName = "FrieveEditorMacTests.browserTickerLayout"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    model.newDocument()
    model.settings.browserTickerVisible = false
    model.settings.browserTickerLines = 1
    model.document.updateCard(0) { card in
        card.bodyText = "First line\nSecond line\nThird line"
    }

    let baseCard = try #require(model.document.card(withID: 0))
    let baseHeight = model.metadata(for: baseCard).canvasSize.height

    model.settings.browserTickerVisible = true
    model.settings.browserTickerLines = 2
    model.invalidateDocumentCaches()

    let tickerCard = try #require(model.document.card(withID: 0))
    let tickerHeight = model.metadata(for: tickerCard).canvasSize.height

    #expect(model.browserCardTickerText(for: tickerCard) == "First line  •  Second line")
    #expect(tickerHeight > baseHeight)
}

@Test func browserTickerVisibleRectsStayHiddenUnderStackedFrontCards() throws {
    let stripRect = CGRect(x: 0, y: 0, width: 100, height: 10)
    let occludingRects = [
        CGRect(x: 20, y: 0, width: 50, height: 10),
        CGRect(x: 40, y: 0, width: 50, height: 10)
    ]

    let visibleRects = browserTickerVisibleRects(in: stripRect, occludingRects: occludingRects)

    #expect(visibleRects == [
        CGRect(x: 0, y: 0, width: 20, height: 10),
        CGRect(x: 90, y: 0, width: 10, height: 10)
    ])
}

@MainActor
@Test func browserScoreExpandsCardSizeAndStacksWithTicker() throws {
    let suiteName = "FrieveEditorMacTests.browserScoreLayout"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    model.newDocument()
    model.settings.browserScoreVisible = false
    model.settings.browserTickerVisible = false
    model.settings.browserTickerLines = 1
    model.document.updateCard(0) { card in
        card.title = "A"
        card.bodyText = "First line\nSecond line"
        card.score = 2.75
    }

    let card = try #require(model.document.card(withID: 0))

    model.invalidateDocumentCaches()
    let baseMetadata = model.metadata(for: card)

    model.settings.browserScoreVisible = true
    model.invalidateDocumentCaches()
    let scoreMetadata = model.metadata(for: card)

    model.settings.browserTickerVisible = true
    model.invalidateDocumentCaches()
    let stackedMetadata = model.metadata(for: card)
    let scoreBarLayout = try #require(model.browserCardScoreBarLayout(for: card))

    #expect(baseMetadata.scoreText == nil)
    #expect(scoreMetadata.scoreText == "Score 2.75")
    #expect(scoreMetadata.canvasSize.width > baseMetadata.canvasSize.width)
    #expect(scoreMetadata.canvasSize.height > baseMetadata.canvasSize.height)
    #expect(stackedMetadata.canvasSize.height > scoreMetadata.canvasSize.height)
    #expect(scoreBarLayout.baselineFraction == 0)
    #expect(scoreBarLayout.fillStartFraction == 0)
    #expect(scoreBarLayout.fillEndFraction == 1)
}

@MainActor
@Test func browserScoreBarCentersSignedInOutValues() throws {
    let suiteName = "FrieveEditorMacTests.browserScoreSignedBars"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    model.document = FrieveDocument(
        title: "Score Bars",
        metadata: [:],
        cards: [
            FrieveCard(id: 1, title: "A", bodyText: "", drawingEncoded: "", visible: true, shape: 0, size: 100, isTop: false, isFixed: false, isFolded: false, position: FrievePoint(x: 0, y: 0), created: "", updated: "", viewed: "", labelIDs: [], score: 0, imagePath: nil, videoPath: nil),
            FrieveCard(id: 2, title: "B", bodyText: "", drawingEncoded: "", visible: true, shape: 0, size: 100, isTop: false, isFixed: false, isFolded: false, position: FrievePoint(x: 0, y: 0), created: "", updated: "", viewed: "", labelIDs: [], score: 0, imagePath: nil, videoPath: nil),
            FrieveCard(id: 3, title: "C", bodyText: "", drawingEncoded: "", visible: true, shape: 0, size: 100, isTop: false, isFixed: false, isFolded: false, position: FrievePoint(x: 0, y: 0), created: "", updated: "", viewed: "", labelIDs: [], score: 0, imagePath: nil, videoPath: nil)
        ],
        links: [
            FrieveLink(fromCardID: 1, toCardID: 2, directionVisible: true, shape: 0, labelIDs: [], name: ""),
            FrieveLink(fromCardID: 3, toCardID: 2, directionVisible: true, shape: 0, labelIDs: [], name: ""),
            FrieveLink(fromCardID: 3, toCardID: 1, directionVisible: true, shape: 0, labelIDs: [], name: "")
        ],
        cardLabels: [],
        linkLabels: [],
        sourcePath: nil
    )
    model.settings.browserScoreVisible = true
    model.settings.browserScoreType = BrowserScoreDisplayType.linksInOut.rawValue
    model.invalidateDocumentCaches()

    let negativeLayout = try #require(model.browserCardScoreBarLayout(for: model.document.cards[2]))
    let positiveLayout = try #require(model.browserCardScoreBarLayout(for: model.document.cards[1]))

    #expect(negativeLayout.isNegative)
    #expect(negativeLayout.baselineFraction == 0.5)
    #expect(negativeLayout.fillStartFraction == 0)
    #expect(negativeLayout.fillEndFraction == 0.5)
    #expect(positiveLayout.isNegative == false)
    #expect(positiveLayout.baselineFraction == 0.5)
    #expect(positiveLayout.fillStartFraction == 0.5)
    #expect(positiveLayout.fillEndFraction == 1)
}

@Test func fip2RoundTripPreservesCardAndLinkData() async throws {
    var document = FrieveDocument.placeholder()
    let childID = document.addCard(title: "Child", linkedFrom: 0)
    document.updateCard(childID) { card in
        card.bodyText = "Body\nSecond line"
        card.drawingEncoded = "DrawPayload"
        card.labelIDs = [1]
        card.score = 2.75
        card.imagePath = "/tmp/sample-image.png"
        card.videoPath = "/tmp/sample-video.mov"
    }
    document.metadata["Language"] = "Japanese"

    let serialized = FIP2Codec.save(document: document)
    let decoded = try FIP2Codec.load(text: serialized)

    #expect(decoded.cardCount == 2)
    #expect(decoded.linkCount == 1)
    #expect(decoded.card(withID: childID)?.bodyText == "Body\nSecond line")
    #expect(decoded.card(withID: childID)?.drawingEncoded == "DrawPayload")
    #expect(decoded.card(withID: childID)?.score == 2.75)
    #expect(decoded.card(withID: childID)?.imagePath == "/tmp/sample-image.png")
    #expect(decoded.card(withID: childID)?.videoPath == "/tmp/sample-video.mov")
    #expect(decoded.metadata["Language"] == "Japanese")
    #expect(decoded.metadata["Title"] == decoded.title)
}

@MainActor
@Test func importingTextFilesAddsCardsUsingFilenamesAndBodies() throws {
    let model = WorkspaceViewModel()
    model.newDocument()

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let alphaURL = tempDirectory.appendingPathComponent("Alpha.txt")
    let betaURL = tempDirectory.appendingPathComponent("Beta.txt")
    try "First body".write(to: alphaURL, atomically: true, encoding: .utf8)
    try "Second body".write(to: betaURL, atomically: true, encoding: .utf8)

    try model.importTextFiles(from: [betaURL, alphaURL])

    #expect(model.document.cardCount == 3)
    #expect(model.document.cards.suffix(2).map(\.title) == ["Alpha", "Beta"])
    #expect(model.document.cards.suffix(2).map(\.bodyText) == ["First body", "Second body"])
    #expect(model.selectedCardID == model.document.cards.last?.id)
}

@MainActor
@Test func externalFileLinksUseDedicatedMediaFieldsWhenAvailable() throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.selectCard(0)
    let initialBody = model.selectedCard?.bodyText ?? ""

    model.applyExternalFileReference(URL(fileURLWithPath: "/tmp/sample-image.png"))
    #expect(model.selectedCard?.imagePath == "/tmp/sample-image.png")
    #expect(model.selectedCard?.bodyText == initialBody)

    model.applyExternalFileReference(URL(fileURLWithPath: "/tmp/sample-video.mov"))
    #expect(model.selectedCard?.videoPath == "/tmp/sample-video.mov")
    #expect(model.selectedCard?.bodyText == initialBody)

    model.applyExternalFileReference(URL(fileURLWithPath: "/tmp/readme.txt"))
    #expect(model.selectedCard?.bodyText == "\(initialBody)\n/tmp/readme.txt")
}

@MainActor
@Test func browserBadgesPreferMarkersOverFixedAndFoldedText() throws {
    let model = WorkspaceViewModel()
    let card = FrieveCard(
        id: 1,
        title: "Pinned",
        bodyText: "",
        drawingEncoded: "",
        visible: true,
        shape: 2,
        size: 100,
        isTop: true,
        isFixed: true,
        isFolded: true,
        position: FrievePoint(x: 0.5, y: 0.5),
        created: "",
        updated: "",
        viewed: "",
        labelIDs: [],
        score: 0,
        imagePath: nil,
        videoPath: nil
    )

    let badges = model.buildBrowserBadgeItems(for: card, labelNames: [], linkCount: 0, hasDrawingPreview: false)
    #expect(badges == ["Top"])
}

@MainActor
@Test func browserBlendsMultipleEnabledLabelColors() throws {
    let model = WorkspaceViewModel()
    model.document.cardLabels = [
        FrieveLabel(id: 1, name: "Red", color: 0x0000FF, enabled: true, show: true, hide: false, fold: false, size: 100),
        FrieveLabel(id: 2, name: "Green", color: 0x00FF00, enabled: true, show: true, hide: false, fold: false, size: 100),
        FrieveLabel(id: 3, name: "Disabled", color: 0xFF0000, enabled: false, show: true, hide: false, fold: false, size: 100)
    ]
    model.invalidateDocumentCaches()
    model.ensureDocumentCaches()

    #expect(model.blendedBrowserLabelColor(for: [1, 2, 3]) == 0x008080)
}

@Test func browserVisualShapeIndexUsesStoredCardShape() {
    let card = FrieveCard(
        id: 1,
        title: "",
        bodyText: "",
        drawingEncoded: "",
        visible: true,
        shape: 14,
        size: 100,
        isTop: false,
        isFixed: false,
        isFolded: false,
        position: FrievePoint(x: 0.5, y: 0.5),
        created: "",
        updated: "",
        viewed: "",
        labelIDs: [],
        score: 0,
        imagePath: nil,
        videoPath: nil
    )

    #expect(browserCardVisualShapeIndex(for: card) == 14)
}

@MainActor
@Test func importingHierarchicalTextFile2BuildsTreeAndBodies() throws {
    let model = WorkspaceViewModel()
    model.newDocument()

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let treeURL = tempDirectory.appendingPathComponent("Tree.txt")
    try "*Parent\n**Child\nBody line 1\nBody line 2\n*Sibling\n".write(to: treeURL, atomically: true, encoding: .utf8)

    try model.importHierarchicalTextFiles(from: [treeURL], bodyFollowsIndentedHeadings: true)

    let importedCards = Array(model.document.cards.suffix(4))
    let topCard = importedCards[0]
    let parentCard = importedCards[1]
    let childCard = importedCards[2]
    let siblingCard = importedCards[3]

    #expect(topCard.title == "Tree")
    #expect(parentCard.title == "Parent")
    #expect(childCard.title == "Child")
    #expect(childCard.bodyText == "Body line 1\nBody line 2")
    #expect(siblingCard.title == "Sibling")
    #expect(model.document.links.contains { $0.fromCardID == topCard.id && $0.toCardID == parentCard.id })
    #expect(model.document.links.contains { $0.fromCardID == parentCard.id && $0.toCardID == childCard.id })
    #expect(model.document.links.contains { $0.fromCardID == topCard.id && $0.toCardID == siblingCard.id })
}

@MainActor
@Test func importingTextFilesFolderBuildsFolderHierarchy() throws {
    let model = WorkspaceViewModel()
    model.newDocument()

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let childDirectory = tempDirectory.appendingPathComponent("Child", isDirectory: true)
    try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try "Root body".write(to: tempDirectory.appendingPathComponent("RootNote.txt"), atomically: true, encoding: .utf8)
    try "Nested body".write(to: childDirectory.appendingPathComponent("Nested.txt"), atomically: true, encoding: .utf8)

    let topFolderID = try model.importTextFilesInFolder(from: tempDirectory)

    let folderCard = try #require(model.document.card(withID: topFolderID))
    let rootNoteCard = try #require(model.document.cards.first { $0.title == "RootNote" })
    let childFolderCard = try #require(model.document.cards.first { $0.title == "Child" })
    let nestedCard = try #require(model.document.cards.first { $0.title == "Nested" })

    #expect(folderCard.title == tempDirectory.lastPathComponent)
    #expect(rootNoteCard.bodyText == "Root body")
    #expect(nestedCard.bodyText == "Nested body")
    #expect(model.document.links.contains { $0.fromCardID == folderCard.id && $0.toCardID == rootNoteCard.id })
    #expect(model.document.links.contains { $0.fromCardID == folderCard.id && $0.toCardID == childFolderCard.id })
    #expect(model.document.links.contains { $0.fromCardID == childFolderCard.id && $0.toCardID == nestedCard.id })
}

@Test func statisticsBucketsAggregateLabelsLinksAndDatesLikeWindows() async throws {
    var document = FrieveDocument.placeholder()
    let firstChildID = document.addCard(title: "First", linkedFrom: 0)
    let secondChildID = document.addCard(title: "Second", linkedFrom: 0)

    document.cardLabels.append(
        FrieveLabel(
            id: 2,
            name: "Topic",
            color: 0x2244EE,
            enabled: true,
            show: true,
            hide: false,
            fold: false,
            size: 100
        )
    )

    document.updateCard(0) { card in
        card.labelIDs = [1, 2]
        card.created = "2026-04-10T10:00:00Z"
        card.updated = "2026-04-10T12:00:00Z"
        card.viewed = "2026-04-10T14:00:00Z"
    }
    document.updateCard(firstChildID) { card in
        card.labelIDs = [2]
        card.created = "2026-04-11T11:30:00Z"
        card.updated = "2026-04-11T12:30:00Z"
        card.viewed = "2026-04-11T13:30:00Z"
    }
    document.updateCard(secondChildID) { card in
        card.labelIDs = []
        card.created = "2025-12-01T01:15:00Z"
        card.updated = "2025-12-02T02:15:00Z"
        card.viewed = "2025-12-03T03:15:00Z"
    }

    let labelBuckets = document.statisticsBuckets(for: .label, sortByCount: false)
    #expect(labelBuckets.map(\.name) == ["Overview", "Topic"])
    #expect(labelBuckets.map(\.count) == [1, 2])

    let totalLinkBuckets = document.statisticsBuckets(for: .totalLinks, sortByCount: false)
    #expect(totalLinkBuckets.map(\.name) == ["0 Links", "1 Links", "2 Links"])
    #expect(totalLinkBuckets.map(\.count) == [0, 2, 1])

    let createdMonthBuckets = document.statisticsBuckets(for: .createdMonth, sortByCount: false)
    #expect(createdMonthBuckets.map(\.name) == ["4/2026", "12/2025"])
    #expect(createdMonthBuckets.map(\.count) == [2, 1])

    let sortedLabelBuckets = document.statisticsBuckets(for: .label, sortByCount: true)
    #expect(sortedLabelBuckets.map(\.name) == ["Topic", "Overview"])
    #expect(sortedLabelBuckets.first?.cardIDs.sorted() == [0, firstChildID])
}

@Test func statisticsBucketsHandleUnknownAndDelphiStyleDates() async throws {
    var document = FrieveDocument.placeholder()
    let childID = document.addCard(title: "Legacy", linkedFrom: 0)

    document.updateCard(0) { card in
        card.created = "45392.5"
    }
    document.updateCard(childID) { card in
        card.created = ""
    }

    let buckets = document.statisticsBuckets(for: .createdDay, sortByCount: false)
    #expect(buckets.count == 2)
    #expect(buckets.last?.name == "Unknown")
    #expect(buckets.last?.cardIDs == [childID])
    #expect(buckets.first?.count == 1)
}

@Test func statisticsCardsDoNotCrashWhenDocumentContainsDuplicateCardIDs() async throws {
    let duplicate = FrieveCard(
        id: 0,
        title: "Duplicate Root ID",
        bodyText: "",
        drawingEncoded: "",
        visible: true,
        shape: 2,
        size: 100,
        isTop: false,
        isFixed: false,
        isFolded: false,
        position: FrievePoint(x: 0.7, y: 0.7),
        created: "2026-04-11T10:00:00Z",
        updated: "2026-04-11T10:00:00Z",
        viewed: "2026-04-11T10:00:00Z",
        labelIDs: [1],
        score: 0,
        imagePath: nil,
        videoPath: nil
    )
    var document = FrieveDocument.placeholder()
    document.cards.append(duplicate)

    let labelBucket = try #require(document.statisticsBuckets(for: .label, sortByCount: false).first)
    let cards = document.statisticsCards(for: labelBucket)

    #expect(cards.count == 2)
    #expect(Set(cards.map(\.title)) == ["Frieve Editor", "Duplicate Root ID"])
}

@MainActor
@Test func statisticsCardSelectionSynchronizesWithPrimarySelection() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.statisticsKey = .totalLinks
    let rootBucket = try #require(model.statisticsBuckets.first(where: { $0.cardIDs.contains(0) }))

    #expect(model.selectedStatisticsCardID(in: rootBucket) == 0)

    model.addChildCard()
    let childID = try #require(model.selectedCardID)
    let labelBucket = try #require(model.statisticsBuckets.first(where: { $0.cardIDs.contains(childID) }))

    model.selectStatisticsCard(childID)
    #expect(model.selectedCardID == childID)
    #expect(model.selectedCardIDs == [childID])
    #expect(model.selectedStatisticsCardID(in: labelBucket) == childID)

    model.selectStatisticsCard(nil)
    #expect(model.selectedCardID == nil)
    #expect(model.selectedCardIDs.isEmpty)
    #expect(model.selectedStatisticsCardID(in: labelBucket) == nil)
}

@Test func windowsBGRColorValuesRenderWithExpectedChannels() async throws {
    let red = NSColor(Color(frieveRGB: 0x0000FF)).usingColorSpace(.deviceRGB) ?? .black
    #expect(red.redComponent > 0.99)
    #expect(red.greenComponent < 0.01)
    #expect(red.blueComponent < 0.01)

    let blue = NSColor(Color(frieveRGB: 0xFF0000)).usingColorSpace(.deviceRGB) ?? .black
    #expect(blue.redComponent < 0.01)
    #expect(blue.greenComponent < 0.01)
    #expect(blue.blueComponent > 0.99)
}

@Test func hierarchicalAndHTMLExportsContainCardContent() async throws {
    var document = FrieveDocument.placeholder()
    let childID = document.addCard(title: "Topic", linkedFrom: 0)
    document.updateCard(childID) { card in
        card.bodyText = "Outline line"
    }

    let hierarchical = document.hierarchicalText()
    let html = document.htmlDocument(title: "Exported")

    #expect(hierarchical.contains("- Frieve Editor"))
    #expect(hierarchical.contains("Topic"))
    #expect(html.contains("<html"))
    #expect(html.contains("Exported"))
    #expect(html.contains("Topic"))
}

@MainActor
@Test func windowsStyleTextExportsMatchMenuExpectations() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.document.updateCard(0) { card in
        card.bodyText = "Root body"
    }
    model.addChildCard()
    let childID = try #require(model.selectedCardID)
    model.document.updateCard(childID) { card in
        card.title = "Topic"
        card.bodyText = "Line 1\nLine 2"
    }

    #expect(model.cardTitlesExportText() == "Frieve Editor\nTopic")
    #expect(model.cardBodiesExportText() == "Root body\nLine 1\nLine 2")
    #expect(model.annotatedCardBodiesExportText().contains("# Topic"))
}

@MainActor
@Test func printBrowserViewReportsMissingSnapshot() {
    let model = WorkspaceViewModel()

    model.browserSnapshotProvider = { nil }
    model.printBrowserView()

    #expect(model.statusMessage == "Browser image is unavailable")
}

@Test func windowsShapeMenusExposeFullWindowsOptionSets() {
    #expect(frieveCardShapeOptions.count == 16)
    #expect(frieveCardShapeOptions.map(\.name).contains("No Drawing"))
    #expect(frieveCardShapeOptions.map(\.name).contains("Trapezoid Top"))
    #expect(frieveLinkShapeOptions.count == 12)
    #expect(frieveLinkShapeOptions.map(\.name).contains("Wedge"))
    #expect(frieveLinkShapeOptions.map(\.name).contains("Curved Wedge"))
}

@Test func windowsGPTMenuActionsExposeExpectedWindowsItems() {
    let titles = GPTPromptAction.menuSections.flatMap(\.self).map(\.menuTitle)

    #expect(titles == [
        "Create…",
        "Continue",
        "Simplify",
        "Longer",
        "Summarize",
        "Proofread",
        "Translate to English",
        "Translate to Japanese",
        "Title"
    ])
}

@MainActor
@Test func windowsGPTPromptsIncludeRequestedActionAndCardContext() {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.document.updateCard(0) { card in
        card.title = "Topic"
        card.bodyText = "Line 1\nLine 2"
    }

    let prompt = model.selectedGPTPrompt(for: .summarize)

    #expect(prompt.contains("Requested Action: Replace"))
    #expect(prompt.contains("Instruction: Summarize and replace the following text."))
    #expect(prompt.contains("Selected Card Title: Topic"))
    #expect(prompt.contains("Body:\nLine 1\nLine 2"))
}

@MainActor
@Test func insertMenuActionsCanCreateLinksAndLabelDrivenCards() throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    let rootID = try #require(model.selectedCardID)
    model.addRootCard()
    let secondID = try #require(model.selectedCardID)
    model.addCardLabel(name: "Topic")
    let labelID = try #require(model.document.cardLabels.first?.id)
    model.document.updateCard(rootID) { $0.labelIDs = [labelID] }
    model.document.updateCard(secondID) { $0.labelIDs = [labelID] }

    model.selectCard(rootID)
    model.addLinkFromSelection(to: secondID)
    #expect(model.document.links.contains(where: { $0.fromCardID == rootID && $0.toCardID == secondID }))

    model.addCardLinkedToAllCardsWithLabel(labelID: labelID)
    let createdID = try #require(model.selectedCardID)
    #expect(createdID != rootID)
    #expect(createdID != secondID)
    #expect(model.document.links.contains(where: { $0.fromCardID == createdID && $0.toCardID == rootID }))
    #expect(model.document.links.contains(where: { $0.fromCardID == createdID && $0.toCardID == secondID }))
}

@MainActor
@Test func randomFlashAnimationRestoresDocumentAndSelectionWhenStopped() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.addChildCard()
    let childID = try #require(model.selectedCardID)
    let originalDocument = model.document
    model.canvasCenter = FrievePoint(x: 0.25, y: 0.75)
    model.zoom = 1.8
    model.selectedCardID = childID
    model.selectedCardIDs = [childID]

    model.startBrowserAnimation(.randomFlash)

    #expect(model.activeBrowserAnimation == .randomFlash)
    #expect(model.selectedTab == .browser)
    #expect(model.document.cards.contains(where: { $0.visible }))

    model.stopBrowserAnimation()

    #expect(model.activeBrowserAnimation == nil)
    #expect(model.document == originalDocument)
    #expect(model.selectedCardID == childID)
    #expect(model.selectedCardIDs == [childID])
    #expect(model.canvasCenter == FrievePoint(x: 0.25, y: 0.75))
    #expect(model.zoom == 1.8)
}

@MainActor
@Test func randomTraceAnimationSelectsVisibleCardAndCanPause() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.addChildCard()
    let childID = try #require(model.selectedCardID)
    model.document.updateCard(childID) { card in
        card.visible = true
    }

    model.startBrowserAnimation(.randomTrace)

    #expect(model.activeBrowserAnimation == .randomTrace)
    #expect(model.autoScroll)
    #expect(model.autoZoom)
    let selectedID = try #require(model.selectedCardID)
    #expect(model.selectedCardIDs.contains(selectedID))

    model.toggleBrowserAnimationPause()
    #expect(model.animationPaused)
    model.stopBrowserAnimation()
}

@Test func browserLinkArrowPlacementUsesMidLinkGeometry() async throws {
    let straight = browserLinkArrowPlacement(
        shapeIndex: 5,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 120, y: 0)
    )
    #expect(straight != nil)
    if let straight {
        #expect(abs(straight.center.x - 60) < 0.01)
        #expect(abs(straight.center.y) < 0.01)
        #expect(abs(straight.direction.dx - 1) < 0.001)
        #expect(abs(straight.direction.dy) < 0.001)
    }

    let elbow = browserLinkArrowPlacement(
        shapeIndex: 2,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 120, y: 80)
    )
    #expect(elbow != nil)
    if let elbow {
        #expect(abs(elbow.center.x - 60) < 0.01)
        #expect(abs(elbow.center.y - 40) < 0.01)
        #expect(abs(elbow.direction.dx) < 0.001)
        #expect(abs(elbow.direction.dy - 1) < 0.001)
    }

    let curve = browserLinkArrowPlacement(
        shapeIndex: 1,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 140, y: 40)
    )
    #expect(curve != nil)
    if let curve {
        #expect(curve.center.x > 45)
        #expect(curve.center.x < 95)
        #expect(curve.center.y > 0)
        #expect(curve.center.y < 40)
        #expect(hypot(curve.center.x - 140, curve.center.y - 40) > 40)
    }
}

@Test func browserLinkArrowGeometryMatchesWindowsChevronStyle() async throws {
    let geometry = browserLinkArrowGeometry(
        shapeIndex: 5,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 120, y: 0)
    )
    #expect(geometry != nil)
    if let geometry {
        #expect(abs(geometry.tip.x - 60) < 0.01)
        #expect(abs(geometry.tip.y) < 0.01)
        #expect(geometry.leftWing.x < geometry.tip.x)
        #expect(geometry.rightWing.x < geometry.tip.x)
        #expect(geometry.leftWing.y < geometry.tip.y)
        #expect(geometry.rightWing.y > geometry.tip.y)
        #expect(abs(hypot(geometry.leftWing.x - geometry.tip.x, geometry.leftWing.y - geometry.tip.y) - 12) < 0.05)
        #expect(abs(hypot(geometry.rightWing.x - geometry.tip.x, geometry.rightWing.y - geometry.tip.y) - 12) < 0.05)
    }
}

@Test func browserLinkArrowGeometryScalesChevronLengthForWorldSpaceRendering() async throws {
    let geometry = browserLinkArrowGeometry(
        shapeIndex: 5,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 120, y: 0),
        baseScale: 4
    )
    #expect(geometry != nil)
    if let geometry {
        #expect(abs(hypot(geometry.leftWing.x - geometry.tip.x, geometry.leftWing.y - geometry.tip.y) - 3) < 0.05)
        #expect(abs(hypot(geometry.rightWing.x - geometry.tip.x, geometry.rightWing.y - geometry.tip.y) - 3) < 0.05)
    }
}

@Test func browserLinkArrowStrokeSegmentsKeepRendererChevronAnchoredAtMidLink() async throws {
    let straight = browserLinkArrowStrokeSegments(
        shapeIndex: 5,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 120, y: 0)
    )
    #expect(straight != nil)
    if let straight {
        #expect(straight.leftStart.x < straight.leftEnd.x)
        #expect(straight.rightStart.x < straight.rightEnd.x)
        #expect(straight.leftEnd.x < 60)
        #expect(straight.rightEnd.x < 60)
        #expect(abs(straight.leftEnd.y) < 8)
        #expect(abs(straight.rightEnd.y) < 8)
    }

    let elbow = browserLinkArrowStrokeSegments(
        shapeIndex: 2,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 120, y: 80)
    )
    #expect(elbow != nil)
    if let elbow {
        #expect(abs(straight?.leftEnd.x ?? 0 - 60) > 0.5)
        #expect(abs(elbow.leftEnd.x - 60) < 8)
        #expect(abs(elbow.rightEnd.x - 60) < 8)
        #expect(elbow.leftStart.y < elbow.leftEnd.y)
        #expect(elbow.rightStart.y < elbow.rightEnd.y)
    }

    let curve = browserLinkArrowStrokeSegments(
        shapeIndex: 1,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 140, y: 40)
    )
    #expect(curve != nil)
    if let curve {
        #expect(hypot(curve.leftEnd.x - 140, curve.leftEnd.y - 40) > 35)
        #expect(hypot(curve.rightEnd.x - 140, curve.rightEnd.y - 40) > 35)
    }
}

@Test func browserTrimmedSegmentEndPullsChevronJointBackSlightly() async throws {
    let trimmed = browserTrimmedSegmentEnd(
        start: CGPoint(x: 48, y: -7),
        end: CGPoint(x: 60, y: 0),
        trimDistance: 2
    )
    #expect(trimmed.x < 60)
    #expect(trimmed.x > 58)
    #expect(trimmed.y < 0)
    #expect(trimmed.y > -2)
}

@Test func browserCanvasSelectionPanZoomAndOverviewMathStayConsistent() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let canvasSize = CGSize(width: 1200, height: 800)
    await MainActor.run {
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        model.addChildCard()
        let childID = model.selectedCardID!
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.75, y: 0.6)
        }
        model.selectedCardIDs = [rootID, childID]
        model.selectedCardID = childID
        model.requestBrowserFit()
        model.resetCanvasToFit(in: canvasSize)
    }

    let viewportRect = await MainActor.run {
        model.overviewViewportRect(overviewSize: CGSize(width: 220, height: 150), canvasSize: canvasSize)
    }
    #expect(viewportRect.width > 0)
    #expect(viewportRect.height > 0)

    let marqueeSelectionCount = await MainActor.run { () -> Int in
        let start = model.canvasPoint(for: FrievePoint(x: 0.45, y: 0.45), in: canvasSize)
        let end = model.canvasPoint(for: FrievePoint(x: 0.8, y: 0.65), in: canvasSize)
        model.beginCanvasGesture(at: start, modifiers: [.shift])
        model.updateCanvasGesture(from: start, to: end, in: canvasSize)
        model.endCanvasGesture(in: canvasSize)
        return model.selectedCardIDs.count
    }
    #expect(marqueeSelectionCount >= 2)

    let initialCenter = await MainActor.run { model.canvasCenter }
    await MainActor.run {
        model.handleScrollWheel(deltaX: 24, deltaY: 36, modifiers: [], at: CGPoint(x: 500, y: 320), in: canvasSize)
    }
    let scrolledCenter = await MainActor.run { model.canvasCenter }
    #expect(scrolledCenter.x < initialCenter.x)
    #expect(scrolledCenter.y < initialCenter.y)

    await MainActor.run {
        model.beginCanvasGesture(at: CGPoint(x: 400, y: 300), modifiers: [])
        model.updateCanvasGesture(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 520, y: 360), in: canvasSize)
        model.endCanvasGesture(in: canvasSize)
    }
    let movedCenter = await MainActor.run { model.canvasCenter }
    #expect(movedCenter != scrolledCenter)

    let initialZoom = await MainActor.run { model.zoom }
    await MainActor.run {
        model.beginMagnification()
        model.updateMagnification(1.35, in: canvasSize)
        model.endMagnification()
    }
    let zoomed = await MainActor.run { model.zoom }
    #expect(zoomed > initialZoom)

    let previewExists = await MainActor.run { () -> Bool in
        let targetCard = model.selectedCardID!
        model.beginCardInteraction(cardID: targetCard, modifiers: [.option])
        model.updateLinkPreviewLocation(CGPoint(x: 700, y: 400))
        let preview = model.linkPreviewSegment(in: canvasSize) != nil
        model.cancelBrowserGesture()
        return preview
    }
    #expect(previewExists)

    let visibleCounts = await MainActor.run { () -> (Int, Int) in
        let cards = model.visibleBrowserCards(in: canvasSize)
        let links = model.visibleBrowserLinks(in: canvasSize, visibleCardIDs: Set(cards.map(\.id)))
        return (cards.count, links.count)
    }
    #expect(visibleCounts.0 >= 1)
    #expect(visibleCounts.1 >= 0)

    let surfaceSceneCardCount = await MainActor.run { () -> Int in
        model.markBrowserSurfaceContentDirty()
        return model.browserSurfaceScene(in: canvasSize).cards.count
    }
    #expect(surfaceSceneCardCount >= visibleCounts.0)

    let hoverOnlySceneSignatureChanges = await MainActor.run { () -> Bool in
        model.markBrowserSurfaceContentDirty()
        let baseline = model.browserSurfaceScene(in: canvasSize)
        model.setBrowserHoverCard(model.document.cards.first?.id)
        let hovered = model.browserSurfaceScene(in: canvasSize)
        return baseline.cardSnapshotSignature != hovered.cardSnapshotSignature && baseline.linkSnapshotSignature == hovered.linkSnapshotSignature
    }
    #expect(hoverOnlySceneSignatureChanges)

    let nudgedPositionChanged = await MainActor.run { () -> Bool in
        let before = model.document.card(withID: model.selectedCardID!)!.position
        model.nudgeSelection(dx: 0.01, dy: -0.02)
        let after = model.document.card(withID: model.selectedCardID!)!.position
        return before != after
    }
    #expect(nudgedPositionChanged)
}

@Test func browserShapeMediaDrawingAndInlineEditingBehaviorsWork() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1280, height: 840)

    let results = await MainActor.run { () -> (Int, CGRect, Bool, Bool, Bool, Bool, Bool, String) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        model.updateSelectedCardShape(4)
        model.updateSelectedCardSizeStep(5)
        model.updateSelectedCardImagePath("/tmp/example.png")
        model.updateSelectedCardVideoPath("clips/demo.mov")
        model.updateSelectedCardDrawing("line 0.1 0.2 0.9 0.8 color=FF0000\nrect 0.2 0.2 0.7 0.6 fill=00FF00")
        model.handleCardDoubleClick(rootID)
        let doubleClickOpened = model.browserInlineEditorCardID == rootID
        model.dismissBrowserInlineEditor()
        model.handleBrowserEditShortcut()
        let enterShortcutOpened = model.browserInlineEditorCardID == rootID
        let selected = model.document.card(withID: rootID)!
        let previewCount = selected.drawingPreviewItems().count
        let selectionFrame = model.selectionFrame(in: canvasSize) ?? .zero
        let mediaURL = model.mediaURL(for: selected.videoPath)
        let summary = model.browserViewportSummary(in: canvasSize)
        let pathExists = model.linkPath(for: FrieveLink(fromCardID: rootID, toCardID: rootID + 1, directionVisible: true, shape: 3, labelIDs: [], name: ""), in: canvasSize) != nil
        return (
            previewCount,
            selectionFrame,
            selected.hasMedia,
            selected.primaryMediaPath == "/tmp/example.png",
            doubleClickOpened,
            enterShortcutOpened,
            mediaURL?.lastPathComponent == "demo.mov",
            summary + (pathExists ? "|path" : "|nop")
        )
    }

    #expect(results.0 >= 2)
    #expect(results.1.width > 0)
    #expect(results.2)
    #expect(results.3)
    #expect(results.4)
    #expect(results.5)
    #expect(results.6)
    #expect(results.7.contains("Center"))
    #expect(results.7.contains("|nop"))
}

@MainActor
@Test func browserDrawingPreviewRendersAboveTitleAndOmitsDrawingLabel() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardTitle(
        """
        Drawing Title
        Second Line
        Third Line
        """
    )
    model.updateSelectedCardDrawing("rect 0.1 0.1 0.9 0.9 color=00FF00 fill=00FF00")

    let card = try #require(model.selectedCard)
    let metadata = model.metadata(for: card)
    #expect(!metadata.badges.contains("Drawing"))
    #expect(!metadata.detailSummary.contains("Drawing"))

    let canvasSize = metadata.canvasSize
    let renderer = ImageRenderer(
        content: BrowserCardRasterContentView(
            viewModel: model,
            card: card,
            metadata: metadata,
            detailLevel: .full,
            fillColor: .clear,
            previewImage: nil,
            videoPreviewImage: nil,
            drawingPreviewImage: model.cachedDrawingPreviewImage(for: card, targetSize: model.browserDrawingPreviewSize(for: card))
        )
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    )
    renderer.scale = 2

    let image = try #require(renderer.nsImage)
    let tiffData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiffData))
    let topGreenRow = try #require(firstMatchingRowFromTop(in: bitmap) { color in
        color.alphaComponent > 0.05 &&
        color.greenComponent > 0.35 &&
        color.greenComponent > color.redComponent * 1.4 &&
        color.greenComponent > color.blueComponent * 1.4
    })
    let topDarkRow = try #require(firstMatchingRowFromTop(in: bitmap) { color in
        color.alphaComponent > 0.2 &&
        color.redComponent < 0.35 &&
        color.greenComponent < 0.35 &&
        color.blueComponent < 0.35
    })

    #expect(topGreenRow < topDarkRow)
}

@MainActor
@Test func browserPreviewStripIncludesImageVideoAndDrawingWidths() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardImagePath("/tmp/sample.png")
    model.updateSelectedCardVideoPath("/tmp/sample.mov")
    model.updateSelectedCardDrawing("rect 0.1 0.1 0.9 0.9 color=00FF00 fill=00FF00")

    let card = try #require(model.selectedCard)
    let stripSize = model.browserPreviewStripSize(for: card, hasDrawingPreview: true)
    let mediaSize = model.browserMediaPreviewSize(for: card)
    let drawingSize = model.browserDrawingPreviewSize(for: card)

    #expect(stripSize.width == mediaSize.width * 2 + drawingSize.width + 16)
    #expect(stripSize.height == max(mediaSize.height, drawingSize.height))
}

@MainActor
@Test func browserImageAndVideoPlaceholdersRenderAtTopOfCard() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardTitle("Preview Title")
    model.updateSelectedCardImagePath("/tmp/missing-image.png")
    model.updateSelectedCardVideoPath("/tmp/missing-video.mov")

    let card = try #require(model.selectedCard)
    let metadata = model.metadata(for: card)
    let canvasSize = metadata.canvasSize
    let renderer = ImageRenderer(
        content: BrowserCardRasterContentView(
            viewModel: model,
            card: card,
            metadata: metadata,
            detailLevel: .full,
            fillColor: .clear,
            previewImage: nil,
            videoPreviewImage: nil,
            drawingPreviewImage: nil
        )
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    )
    renderer.scale = 2

    let image = try #require(renderer.nsImage)
    let tiffData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiffData))
    let firstOpaqueRow = try #require(firstMatchingRowFromTop(in: bitmap) { color in
        color.alphaComponent > 0.05
    })
    let firstDarkRow = try #require(firstMatchingRowFromTop(in: bitmap) { color in
        color.alphaComponent > 0.2 &&
        color.redComponent < 0.35 &&
        color.greenComponent < 0.35 &&
        color.blueComponent < 0.35
    })

    #expect(firstOpaqueRow < firstDarkRow)
}

@MainActor
@Test func browserDetailSummaryAddsDedicatedRasterSpace() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardTitle("Summary Title")

    let plainCard = try #require(model.selectedCard)
    let plainMetadata = model.metadata(for: plainCard)

    model.updateSelectedCardFixed(true)
    model.updateSelectedCardFolded(true)

    let markedCard = try #require(model.selectedCard)
    let markedMetadata = model.metadata(for: markedCard)

    #expect(markedMetadata.detailSummary == "Fixed · Folded")
    #expect(markedMetadata.canvasSize.height > plainMetadata.canvasSize.height)
}

@MainActor
@Test func browserFoldedCardsRenderDetailSummaryAwayFromTrailingBadge() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardTitle("Folded Summary")
    model.updateSelectedCardFolded(true)

    let card = try #require(model.selectedCard)
    let metadata = model.metadata(for: card)
    let canvasSize = metadata.canvasSize
    let renderer = ImageRenderer(
        content: BrowserCardRasterContentView(
            viewModel: model,
            card: card,
            metadata: metadata,
            detailLevel: .full,
            fillColor: .clear,
            previewImage: nil,
            videoPreviewImage: nil,
            drawingPreviewImage: nil
        )
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    )
    renderer.scale = 2

    let image = try #require(renderer.nsImage)
    let tiffData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiffData))
    let searchWidth = Int(Double(bitmap.pixelsWide) * 0.65)
    let startingRow = Int(Double(bitmap.pixelsHigh) * 0.35)
    var foundCentralSummaryRow: Int?

    for row in startingRow..<bitmap.pixelsHigh {
        for x in 0..<searchWidth {
            guard let color = bitmap.colorAt(x: x, y: row)?.usingColorSpace(.deviceRGB) else { continue }
            if color.alphaComponent > 0.2 &&
                color.redComponent < 0.4 &&
                color.greenComponent < 0.4 &&
                color.blueComponent < 0.4 {
                foundCentralSummaryRow = row
                break
            }
        }
        if foundCentralSummaryRow != nil {
            break
        }
    }

    #expect(foundCentralSummaryRow != nil)
}

@MainActor
@Test func browserSurfaceSceneRecomputesHitRegionsWhenZoomUsesCachedContent() async throws {
    let suiteName = "FrieveEditorMacTests.browserSurfaceHitRegions"
    let model = WorkspaceViewModel(settings: AppSettings(userDefaults: {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }()))
    let canvasSize = CGSize(width: 1280, height: 840)

    model.newDocument()
    let rootID = try #require(model.selectedCardID)
    let childID = model.document.addCard(title: "Child", linkedFrom: rootID)
    model.markBrowserSurfaceContentDirty()
    model.resetCanvasToFit(in: canvasSize)

    let baselineScene = model.browserSurfaceScene(in: canvasSize)
    let baselineKey = try #require(model.cachedBrowserSurfaceContentKey)
    let baselineRootMidX = try #require(baselineScene.hitRegions.first(where: { $0.cardID == rootID })).frame.midX
    let baselineChildMidX = try #require(baselineScene.hitRegions.first(where: { $0.cardID == childID })).frame.midX

    model.zoom = 1.2

    let zoomedScene = model.browserSurfaceScene(in: canvasSize)
    let zoomedKey = try #require(model.cachedBrowserSurfaceContentKey)
    let zoomedRootMidX = try #require(zoomedScene.hitRegions.first(where: { $0.cardID == rootID })).frame.midX
    let zoomedChildMidX = try #require(zoomedScene.hitRegions.first(where: { $0.cardID == childID })).frame.midX

    #expect(baselineKey == zoomedKey)
    #expect(baselineScene.cards.map(\.id) == zoomedScene.cards.map(\.id))
    #expect(abs(zoomedRootMidX - baselineRootMidX) < 0.001)
    #expect(abs(zoomedChildMidX - baselineChildMidX) > 0.001)
}

@MainActor
@Test func browserAutoZoomKeepsSharedTimerAliveWhenAutoScrollIsOff() async throws {
    let model = WorkspaceViewModel()

    model.autoScroll = false
    model.browserAutoZoomStartZoom = 1
    model.browserAutoZoomTargetZoom = 1.4
    model.browserAutoZoomStartedAt = CACurrentMediaTime()
    model.ensureBrowserAutoScrollTimer()

    let timerBeforeReset = model.browserAutoScrollTimer
    model.resetBrowserAutoScrollAnimation()

    #expect(timerBeforeReset != nil)
    #expect(model.browserAutoScrollTimer != nil)

    model.resetBrowserAutoZoomAnimation()
    model.resetBrowserAutoScrollAnimation()
    #expect(model.browserAutoScrollTimer == nil)
}

@MainActor
@Test func browserViewportAnimationsBatchScrollAndZoomIntoSingleRefresh() async throws {
    let model = WorkspaceViewModel()
    var refreshCount = 0

    model.newDocument()
    model.selectedTab = .browser
    model.autoScroll = true
    model.browserSurfaceViewportRefreshHandler = {
        refreshCount += 1
    }
    model.canvasCenter = FrievePoint(x: 0.2, y: 0.2)
    model.zoom = 1
    model.browserAutoScrollStartCenter = FrievePoint(x: 0.2, y: 0.2)
    model.browserAutoScrollTargetCenter = try #require(model.selectedCard).position
    model.browserAutoScrollStartedAt = 0
    model.browserAutoZoomStartZoom = 1
    model.browserAutoZoomTargetZoom = 2
    model.browserAutoZoomStartedAt = 0

    let didChange = model.applyBrowserViewportAnimationsFrameIfNeeded(at: 0.14)

    #expect(didChange)
    #expect(refreshCount == 1)
    #expect(model.canvasCenter != FrievePoint(x: 0.2, y: 0.2))
    #expect(model.zoom > 1)
}

@MainActor
@Test func inspectorBindingsAllowEditingTitleAndLabels() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()

    model.bindingForSelectedTitle().wrappedValue = "Editable Title"
    model.bindingForSelectedLabels().wrappedValue = "Overview, Topic, Fresh Label"

    let selectedCard = try #require(model.selectedCard)
    let labelNames = model.cardLabelNames(for: selectedCard)

    #expect(selectedCard.title == "Editable Title")
    #expect(labelNames == ["Overview", "Topic", "Fresh Label"])
    #expect(model.document.cardLabels.contains(where: { $0.name == "Topic" }))
    #expect(model.document.cardLabels.contains(where: { $0.name == "Fresh Label" }))
    #expect(model.document.title == "Editable Title")
}

@MainActor
@Test func editorRelatedCardLinesListLinkedCardsAsSingleLineSummaries() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    let rootID = try #require(model.selectedCardID)
    let childID = model.document.addCard(title: "Child", linkedFrom: rootID)
    let parentID = model.document.addCard(title: "Parent", linkedFrom: nil)

    model.document.cardLabels.append(
        FrieveLabel(
            id: 2,
            name: "Topic",
            color: 0x2244EE,
            enabled: true,
            show: true,
            hide: false,
            fold: false,
            size: 100
        )
    )
    model.document.updateCard(childID) { card in
        card.labelIDs = [2]
        card.bodyText = "Child body\nnext line"
    }
    model.document.updateCard(parentID) { card in
        card.bodyText = "Parent body"
    }
    model.document.links.append(
        FrieveLink(
            fromCardID: parentID,
            toCardID: rootID,
            directionVisible: true,
            shape: 5,
            labelIDs: [],
            name: "Related"
        )
    )

    let lines = model.editorRelatedCardLines()

    #expect(lines.count == 2)
    #expect(lines.map(\.text).contains("子：[Topic] Child：Child body next line"))
    #expect(lines.map(\.text).contains("親：Parent：Parent body"))
    #expect(lines.map(\.linkName).contains("Related"))
    #expect(lines.map(\.linkName).contains(""))
}

@MainActor
@Test func updatingLinkNameChangesRenderedEditorRelatedLineData() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    let rootID = try #require(model.selectedCardID)
    let childID = model.document.addCard(title: "Child", linkedFrom: rootID)
    let linkID = try #require(model.document.links.first(where: { $0.toCardID == childID })?.id)

    model.updateLinkName(linkID, name: "Route A")

    let lines = model.editorRelatedCardLines()

    #expect(lines.first?.linkID == linkID)
    #expect(lines.first?.linkName == "Route A")
    #expect(model.document.links.first(where: { $0.id == linkID })?.name == "Route A")
}

@Test func drawingToolsNoLongerIncludeTextTool() async throws {
    #expect(drawingToolOptions == ["Cursor", "FreeHand", "Line", "Rect", "Circle"])
    #expect(!drawingToolOptions.contains("Text"))
}

@Test func drawingEditorDocumentPreservesUnsupportedChunksWhileEditingShapes() async throws {
    let document = DrawingEditorDocument(
        encoded: """
        rect 0.1 0.2 0.6 0.7 color=112233 fill=445566
        text 0.4 0.5 "Legacy note"
        """
    )

    #expect(document.shapes.count == 1)
    #expect(document.shapes.first?.tool == "Rect")
    #expect(document.passthroughChunks == ["text 0.4 0.5 \"Legacy note\""])
    #expect(document.encoded.contains("rect 0.1 0.2 0.6 0.7 color=112233 fill=445566"))
    #expect(document.encoded.contains("text 0.4 0.5 \"Legacy note\""))
}

@Test func drawingEditorShapesRoundTripMoveResizeAndDeleteIntoPreviewablePayload() async throws {
    var line = try #require(DrawingEditorShape(tool: "Line", startPoint: CGPoint(x: 0.1, y: 0.2), strokeColor: 0x3366CC))
    line.updateDraft(tool: "Line", with: CGPoint(x: 0.4, y: 0.5))

    let moved = line.moved(by: CGSize(width: 0.2, height: 0.1))
    let resized = moved.resized(using: .lineEnd, to: CGPoint(x: 0.9, y: 0.85))

    var freeHand = try #require(DrawingEditorShape(tool: "FreeHand", startPoint: CGPoint(x: 0.15, y: 0.15), strokeColor: nil))
    freeHand.updateDraft(tool: "FreeHand", with: CGPoint(x: 0.2, y: 0.18))
    freeHand.updateDraft(tool: "FreeHand", with: CGPoint(x: 0.3, y: 0.28))
    let resizedFreeHand = freeHand.resized(using: .bottomTrailing, to: CGPoint(x: 0.6, y: 0.5))

    var document = DrawingEditorDocument(encoded: "")
    document.shapes = [resized, resizedFreeHand]

    let encoded = document.encoded
    #expect(encoded.contains("line 0.3 0.3 0.9 0.85 color=3366CC"))
    #expect(encoded.contains("freehand"))

    document.shapes.removeLast()
    let lineOnlyEncoded = document.encoded
    let previewCard = FrieveCard(
        id: 99,
        title: "Drawing",
        bodyText: "",
        drawingEncoded: lineOnlyEncoded,
        visible: true,
        shape: 2,
        size: 100,
        isTop: false,
        isFixed: false,
        isFolded: false,
        position: FrievePoint(x: 0.5, y: 0.5),
        created: "",
        updated: "",
        viewed: "",
        labelIDs: [],
        score: 0,
        imagePath: nil,
        videoPath: nil
    )

    let previewItems = previewCard.drawingPreviewItems()
    #expect(previewItems.count == 1)
    if case let .line(start, end) = try #require(previewItems.first?.kind) {
        #expect(abs(start.x - 0.3) < 0.0001)
        #expect(abs(start.y - 0.3) < 0.0001)
        #expect(abs(end.x - 0.9) < 0.0001)
        #expect(abs(end.y - 0.85) < 0.0001)
    } else {
        Issue.record("Expected a line preview item")
    }
}

@MainActor
@Test func drawingColorToolSupportsAutomaticAndPickedColors() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardDrawing("line 0 0 1 1\nrect 0 0 1 1 fill=00FF00")

    model.setSelectedDrawingStrokeColor(0x3366CC)
    let explicitDrawing = try #require(model.selectedCard?.drawingEncoded)
    #expect(explicitDrawing.contains("color=3366CC"))
    #expect(explicitDrawing.contains("fill=00FF00"))
    #expect(model.selectedDrawingStrokeColorRawValue() == 0x3366CC)

    model.setSelectedDrawingStrokeColor(nil)
    let automaticDrawing = try #require(model.selectedCard?.drawingEncoded)
    #expect(!automaticDrawing.contains("color="))
    #expect(!automaticDrawing.contains("stroke="))
    #expect(automaticDrawing.contains("fill=00FF00"))
    #expect(model.selectedDrawingStrokeColorRawValue() == nil)
}

@Test func windowsEncodedDrawingPayloadBuildsPreviewItems() async throws {
    func hex(_ value: UInt32) -> String {
        String(format: "%08X", value)
    }

    func floatHex(_ value: Float) -> String {
        hex(value.bitPattern)
    }

    func colorHex(_ value: Int32) -> String {
        hex(UInt32(bitPattern: value))
    }

    func makeItem(type: UInt32, penColor: Int32, brushColor: Int32, count: UInt32, rect: [Float], points: [Float]) -> String {
        hex(type) +
        colorHex(penColor) +
        colorHex(brushColor) +
        hex(count) +
        rect.map(floatHex).joined() +
        points.map(floatHex).joined()
    }

    let lineItem = makeItem(
        type: 2,
        penColor: 0x0000FF,
        brushColor: -1,
        count: 0,
        rect: [0.1, 0.2, 0.8, 0.9],
        points: []
    )
    let rectItem = makeItem(
        type: 3,
        penColor: Int32.max,
        brushColor: 0x00FF00,
        count: 0,
        rect: [0.25, 0.3, 0.6, 0.55],
        points: []
    )
    let encoded = hex(2) + hex(UInt32(lineItem.count)) + lineItem + hex(UInt32(rectItem.count)) + rectItem

    let card = FrieveCard(
        id: 100,
        title: "Windows Drawing",
        bodyText: "",
        drawingEncoded: encoded,
        visible: true,
        shape: 2,
        size: 100,
        isTop: false,
        isFixed: false,
        isFolded: false,
        position: FrievePoint(x: 0.5, y: 0.5),
        created: "",
        updated: "",
        viewed: "",
        labelIDs: [],
        score: 0,
        imagePath: nil,
        videoPath: nil
    )

    let previewItems = card.drawingPreviewItems()
    #expect(previewItems.count == 2)

    if case let .line(start, end) = try #require(previewItems.first?.kind) {
        #expect(abs(start.x - 0.1) < 0.0001)
        #expect(abs(start.y - 0.2) < 0.0001)
        #expect(abs(end.x - 0.8) < 0.0001)
        #expect(abs(end.y - 0.9) < 0.0001)
    } else {
        Issue.record("Expected a Windows line preview item")
    }
    #expect(previewItems.first?.strokeColor == 0x0000FF)

    if case let .rect(bounds) = try #require(previewItems.last?.kind) {
        #expect(abs(bounds.minX - 0.25) < 0.0001)
        #expect(abs(bounds.minY - 0.3) < 0.0001)
        #expect(abs(bounds.maxX - 0.6) < 0.0001)
        #expect(abs(bounds.maxY - 0.55) < 0.0001)
    } else {
        Issue.record("Expected a Windows rect preview item")
    }
    #expect(previewItems.last?.strokeColor == nil)
    #expect(previewItems.last?.fillColor == 0x00FF00)
}

private func firstMatchingRowFromTop(in bitmap: NSBitmapImageRep, predicate: (NSColor) -> Bool) -> Int? {
    for rowFromTop in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: rowFromTop)?.usingColorSpace(.deviceRGB) else { continue }
            if predicate(color) {
                return rowFromTop
            }
        }
    }
    return nil
}

@Test func browserShiftEnterCreatesChildCardAndStartsInlineEditing() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let results = await MainActor.run { () -> (Int, Bool, Bool, Bool) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        let originalCount = model.document.cardCount
        model.handleBrowserCreateChildShortcut()
        let childID = model.selectedCardID ?? -1
        let child = model.document.card(withID: childID)
        let hasParentLink = model.document.links.contains { $0.fromCardID == rootID && $0.toCardID == childID }
        return (
            model.document.cardCount - originalCount,
            childID != rootID,
            hasParentLink,
            model.browserInlineEditorCardID == child?.id
        )
    }

    #expect(results.0 == 1)
    #expect(results.1)
    #expect(results.2)
    #expect(results.3)
}

@Test func browserCommandEnterCreatesSiblingCardAndStartsInlineEditing() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let results = await MainActor.run { () -> (Int, Bool, Bool, Bool, Bool) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        model.document.updateCard(rootID) { card in
            card.labelIDs = [1]
        }
        let originalCount = model.document.cardCount
        model.handleBrowserCreateSiblingShortcut()
        let siblingID = model.selectedCardID ?? -1
        let sibling = model.document.card(withID: siblingID)
        return (
            model.document.cardCount - originalCount,
            siblingID != rootID,
            sibling?.position.y == model.document.card(withID: rootID)?.position.y,
            model.browserInlineEditorCardID == sibling?.id,
            sibling?.labelIDs == [1]
        )
    }

    #expect(results.0 == 1)
    #expect(results.1)
    #expect(results.2)
    #expect(results.3)
    #expect(results.4)
}

@MainActor
@Test func browserUndoRestoresCreateEditMoveAndDeleteOperations() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    let rootID = try #require(model.selectedCardID)
    let initialCardCount = model.document.cardCount

    model.addChildCard()
    let firstChildID = try #require(model.selectedCardID)
    #expect(model.document.cardCount == initialCardCount + 1)

    model.undoLastDocumentChange()
    #expect(model.document.cardCount == initialCardCount)
    #expect(model.cardByID(firstChildID) == nil)
    #expect(model.selectedCardID == rootID)

    model.addChildCard()
    let editedChildID = try #require(model.selectedCardID)
    let originalPosition = try #require(model.cardByID(editedChildID)?.position)
    model.updateSelectedCardTitle("Edited once")
    model.updateSelectedCardTitle("Edited twice")
    #expect(model.cardByID(editedChildID)?.title == "Edited twice")

    model.undoLastDocumentChange()
    #expect(model.cardByID(editedChildID)?.title == "Child Card")

    model.browserGestureMode = .movingSelection
    model.dragOriginByCardID = [editedChildID: originalPosition]
    model.currentDragTranslation = FrievePoint(x: 0.14, y: -0.09)
    model.endCardInteraction(at: .zero, in: CGSize(width: 1200, height: 800))
    #expect(model.cardByID(editedChildID)?.position == FrievePoint(x: originalPosition.x + 0.14, y: originalPosition.y - 0.09))

    model.undoLastDocumentChange()
    #expect(model.cardByID(editedChildID)?.position == originalPosition)

    model.deleteSelectedCard()
    #expect(model.cardByID(editedChildID) == nil)

    model.undoLastDocumentChange()
    #expect(model.cardByID(editedChildID)?.title == "Child Card")
    #expect(model.cardByID(editedChildID)?.position == originalPosition)
    #expect(model.selectedCardID == editedChildID)
    #expect(model.selectedCardIDs == [editedChildID])

    model.undoLastDocumentChange()
    #expect(model.cardByID(editedChildID) == nil)
    #expect(model.selectedCardID == rootID)
}

@MainActor
@Test func browserCommandZInvokesUndoShortcutHandler() async throws {
    let view = BrowserInteractionNSView(frame: .zero)
    var didUndo = false
    view.onUndo = {
        didUndo = true
    }
    let event = try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "z",
            charactersIgnoringModifiers: "z",
            isARepeat: false,
            keyCode: 6
        )
    )

    view.keyDown(with: event)

    #expect(didUndo)
}

@Test func browserArrowKeysSelectNearestCardInDirection() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let results = await MainActor.run { () -> (Bool, Bool, Bool, Bool) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        let rightID = model.document.addCard(title: "Right", linkedFrom: rootID)
        let leftID = model.document.addCard(title: "Left", linkedFrom: rootID)
        let upID = model.document.addCard(title: "Up", linkedFrom: rootID)
        let downID = model.document.addCard(title: "Down", linkedFrom: rootID)

        model.document.updateCard(rootID) { $0.position = FrievePoint(x: 0.5, y: 0.5) }
        model.document.updateCard(rightID) { $0.position = FrievePoint(x: 0.7, y: 0.5) }
        model.document.updateCard(leftID) { $0.position = FrievePoint(x: 0.3, y: 0.5) }
        model.document.updateCard(upID) { $0.position = FrievePoint(x: 0.5, y: 0.3) }
        model.document.updateCard(downID) { $0.position = FrievePoint(x: 0.5, y: 0.7) }

        model.selectCard(rootID)
        model.handleBrowserDirectionalSelection(dx: 1, dy: 0)
        let movedRight = model.selectedCardID == rightID

        model.selectCard(rootID)
        model.handleBrowserDirectionalSelection(dx: -1, dy: 0)
        let movedLeft = model.selectedCardID == leftID

        model.selectCard(rootID)
        model.handleBrowserDirectionalSelection(dx: 0, dy: -1)
        let movedUp = model.selectedCardID == upID

        model.selectCard(rootID)
        model.handleBrowserDirectionalSelection(dx: 0, dy: 1)
        let movedDown = model.selectedCardID == downID

        return (movedRight, movedLeft, movedUp, movedDown)
    }

    #expect(results.0)
    #expect(results.1)
    #expect(results.2)
    #expect(results.3)
}

@Test func browserSelectedCardsUseThickerOutlineStroke() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Float, Float) in
        model.newDocument()
        return (
            model.browserCardStrokeWidth(isSelected: false),
            model.browserCardStrokeWidth(isSelected: true)
        )
    }

    #expect(result.0 == 1)
    #expect(result.1 > result.0)
}

@Test func browserAutoZoomKeepsViewportStillWhenAutoScrollIsOff() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Bool, Bool, Bool, Bool, Bool) in
        model.newDocument()
        model.browserCanvasSize = CGSize(width: 1200, height: 800)
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Zoom Target", linkedFrom: rootID)
        let siblingID = model.document.addCard(title: "Zoom Sibling", linkedFrom: rootID)
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.82, y: 0.27)
        }
        model.document.updateCard(siblingID) { card in
            card.position = FrievePoint(x: 0.18, y: 0.74)
        }

        model.autoZoom = false
        let beforeCenter = model.canvasCenter
        model.selectCard(childID)
        let centerWithoutAutoZoom = model.canvasCenter == beforeCenter

        model.canvasCenter = FrievePoint(x: 0.50, y: 0.50)
        model.selectCard(rootID)
        model.autoZoom = true
        let centerBeforeAutoZoomSelection = model.canvasCenter
        let zoomBeforeAutoZoomSelection = model.zoom
        model.selectCard(childID)
        let centerWithAutoZoom = model.canvasCenter == centerBeforeAutoZoomSelection
        let zoomAdjustedForSelection = abs((model.browserAutoZoomTargetZoom ?? model.zoom) - zoomBeforeAutoZoomSelection) > 0.0001
        let centerBeforeClear = model.canvasCenter
        model.clearSelection()
        let bounds = model.browserDocumentBounds()
        let fitTargetExistsAfterClear = model.browserFitAnimationStartedAt != nil &&
            (model.browserFitAnimationTargetCenter.map {
                hypot($0.x - bounds.midX, $0.y - bounds.midY) < 0.001
            } ?? false)
        let clearDoesNotSnapToDocumentCenter = hypot(model.canvasCenter.x - centerBeforeClear.x, model.canvasCenter.y - centerBeforeClear.y) <
            hypot(centerBeforeClear.x - bounds.midX, centerBeforeClear.y - bounds.midY)

        return (centerWithoutAutoZoom, centerWithAutoZoom, zoomAdjustedForSelection, fitTargetExistsAfterClear, clearDoesNotSnapToDocumentCenter)
    }

    #expect(result.0)
    #expect(result.1)
    #expect(result.2)
    #expect(result.3)
    #expect(result.4)
}

@Test func browserAutoZoomRepeatedEmptyClicksDoNotRestartClearSelectionFit() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Bool, Bool, Bool) in
        model.newDocument()
        model.browserCanvasSize = CGSize(width: 1200, height: 800)
        model.autoZoom = true
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Click Target", linkedFrom: rootID)
        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.25, y: 0.28)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.78, y: 0.74)
        }

        model.selectCard(childID)
        model.clearSelection()
        let firstFitStartedAt = model.browserFitAnimationStartedAt
        let firstTargetZoom = model.browserFitAnimationTargetZoom
        let firstTargetCenter = model.browserFitAnimationTargetCenter

        model.clearSelection()

        return (
            model.browserFitAnimationStartedAt == firstFitStartedAt,
            model.browserFitAnimationTargetZoom == firstTargetZoom,
            model.browserFitAnimationTargetCenter == firstTargetCenter
        )
    }

    #expect(result.0)
    #expect(result.1)
    #expect(result.2)
}

@Test func browserClearSelectionFitUsesTighterViewportFraming() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1200, height: 800)

    let result = await MainActor.run { () -> (Double, Bool) in
        model.newDocument()
        model.browserCanvasSize = canvasSize
        model.autoZoom = true
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Fit Target", linkedFrom: rootID)
        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.22, y: 0.24)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.81, y: 0.77)
        }
        model.invalidateDocumentCaches()

        model.selectCard(childID)
        model.clearSelection()
        let fitStartedAt = model.browserFitAnimationStartedAt ?? CACurrentMediaTime()
        _ = model.applyBrowserFitStepIfNeeded(at: fitStartedAt + 1.0)

        let contentBounds = model.browserDocumentBounds(padding: 0)
        let visibleRect = model.visibleWorldRect(in: canvasSize)
        let fillRatio = max(
            contentBounds.width / max(visibleRect.width, 0.0001),
            contentBounds.height / max(visibleRect.height, 0.0001)
        )
        let epsilon = 0.0001
        let containsBounds =
            visibleRect.minX <= contentBounds.minX + epsilon &&
            visibleRect.maxX >= contentBounds.maxX - epsilon &&
            visibleRect.minY <= contentBounds.minY + epsilon &&
            visibleRect.maxY >= contentBounds.maxY - epsilon

        return (fillRatio, containsBounds)
    }

    #expect(result.0 > 0.72)
    #expect(result.1)
}

@Test func browserAutoZoomSkipsSingleAxisSpreadLikeWindows() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Double, Double, Bool) in
        model.newDocument()
        model.browserCanvasSize = CGSize(width: 1200, height: 800)
        model.autoZoom = true
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Vertical Target", linkedFrom: rootID)
        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.50, y: 0.20)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.50, y: 0.80)
        }

        let zoomBeforeSelection = model.zoom
        let centerBeforeSelection = model.canvasCenter
        model.selectCard(childID)
        let centerStayedStill = model.canvasCenter == centerBeforeSelection
        return (zoomBeforeSelection, model.zoom, centerStayedStill)
    }

    #expect(result.0 == result.1)
    #expect(result.2)
}

@Test func browserAutoZoomIgnoresUnrelatedRecentCardsByDefault() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Double, Bool) in
        model.newDocument()
        model.browserCanvasSize = CGSize(width: 1200, height: 800)
        model.autoZoom = true
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Zoom Target", linkedFrom: rootID)
        let siblingID = model.document.addCard(title: "Far Recent", linkedFrom: rootID)
        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.50, y: 0.50)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.60, y: 0.58)
        }
        model.document.updateCard(siblingID) { card in
            card.position = FrievePoint(x: 0.12, y: 0.86)
        }

        model.selectCard(rootID)
        let centerBeforeSelection = model.canvasCenter
        model.selectCard(childID)
        return (model.browserAutoZoomTargetZoom ?? model.zoom, model.canvasCenter == centerBeforeSelection)
    }

    #expect(result.0 > 2.0)
    #expect(result.1)
}

@Test func browserCardTextRefreshModeIncludesCardTexturesAfterAsyncRaster() async throws {
    #expect(
        browserPresentationRefreshMode(selectionChanged: false, dragChanged: false, hoverChanged: false) == .cardsLinksAndText
    )
    #expect(
        browserPresentationRefreshMode(selectionChanged: false, dragChanged: false, hoverChanged: true) == .cardsOnly
    )
    #expect(
        browserPresentationRefreshMode(selectionChanged: true, dragChanged: false, hoverChanged: false) == .cardsLinksAndText
    )
    #expect(
        browserPresentationRefreshMode(selectionChanged: false, dragChanged: true, hoverChanged: false) == .cardsLinksAndText
    )
}

@Test func browserCardRasterCacheKeyStaysStableAcrossDetailLevels() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Bool, Bool) in
        let baseCard = FrieveCard(
            id: 7,
            title: "Stable Raster",
            bodyText: "",
            drawingEncoded: "",
            visible: true,
            shape: 0,
            size: 100,
            isTop: false,
            isFixed: false,
            isFolded: false,
            position: FrievePoint(x: 0.5, y: 0.5),
            created: "2026-04-13T00:00:00Z",
            updated: "2026-04-13T00:00:00Z",
            viewed: "2026-04-13T00:00:00Z",
            labelIDs: [],
            score: 0,
            imagePath: nil,
            videoPath: nil
        )
        let movedCard = FrieveCard(
            id: 7,
            title: "Stable Raster",
            bodyText: "",
            drawingEncoded: "",
            visible: true,
            shape: 0,
            size: 100,
            isTop: false,
            isFixed: false,
            isFolded: false,
            position: FrievePoint(x: 0.8, y: 0.2),
            created: "2026-04-13T00:00:00Z",
            updated: "2026-04-15T00:00:00Z",
            viewed: "2026-04-13T00:00:00Z",
            labelIDs: [],
            score: 0,
            imagePath: nil,
            videoPath: nil
        )
        let metadata = BrowserCardMetadata(
            labelNames: [],
            labelLine: "",
            summaryText: "",
            detailSummary: "",
            scoreText: nil,
            badges: [],
            canvasSize: CGSize(width: 120, height: 52),
            linkCount: 0,
            hasDrawingPreview: false,
            primaryLabelColor: nil,
            mediaBadgeText: ""
        )
        let compactSnapshot = BrowserCardLayerSnapshot(
            card: baseCard,
            position: baseCard.position,
            metadata: metadata,
            isSelected: false,
            isHovered: false,
            detailLevel: .compact
        )
        let fullSnapshot = BrowserCardLayerSnapshot(
            card: baseCard,
            position: baseCard.position,
            metadata: metadata,
            isSelected: false,
            isHovered: false,
            detailLevel: .full
        )
        let movedSnapshot = BrowserCardLayerSnapshot(
            card: movedCard,
            position: movedCard.position,
            metadata: metadata,
            isSelected: false,
            isHovered: false,
            detailLevel: .full
        )

        return (
            model.browserCardRasterCacheKey(for: compactSnapshot) == model.browserCardRasterCacheKey(for: fullSnapshot),
            model.browserCardRasterCacheKey(for: compactSnapshot) == model.browserCardRasterCacheKey(for: movedSnapshot)
        )
    }

    #expect(result.0)
    #expect(result.1)
}

@Test func browserArrangeModesMatchMacExpectations() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let results = await MainActor.run { () -> (Bool, Bool, Int) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        let childA = model.document.addCard(title: "Alpha", linkedFrom: rootID)
        let childB = model.document.addCard(title: "Beta", linkedFrom: rootID)
        let childC = model.document.addCard(title: "Gamma", linkedFrom: childA)
        model.selectedCardID = rootID
        model.selectedCardIDs = [rootID]
        model.browserCanvasSize = CGSize(width: 1200, height: 800)

        model.arrangeMode = "Matrix"
        model.browserAutoArrangeEnabled = true
        for _ in 0..<6 {
            model.applyBrowserAutoArrangeStepIfNeeded()
        }
        let matrixEnabled = model.browserAutoArrangeEnabled
        let matrixChanged = [rootID, childA, childB, childC].contains { id in
            guard let card = model.document.card(withID: id) else { return false }
            return card.position != .zero
        }

        model.arrangeMode = "Tree"
        model.browserAutoArrangeEnabled = true
        for _ in 0..<4 {
            model.applyBrowserAutoArrangeStepIfNeeded()
        }
        let treeEnabled = model.browserAutoArrangeEnabled

        model.browserAutoArrangeEnabled = false
        return (matrixEnabled && matrixChanged, treeEnabled, model.document.cards.count)
    }

    #expect(results.0)
    #expect(results.1)
    #expect(results.2 >= 4)
}

@Test func browserMatrixAndTreeArrangeIgnoreDuplicateVisibleCardIDs() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let results = await MainActor.run { () -> (Int, Int, Int, FrievePoint, FrievePoint) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Alpha", linkedFrom: rootID)
        _ = model.document.addCard(title: "Beta", linkedFrom: rootID)

        guard var duplicate = model.document.card(withID: childID) else {
            return (0, 0, 0, .zero, .zero)
        }
        duplicate.title = "Alpha Duplicate"
        duplicate.position = FrievePoint(x: 0.95, y: 0.1)
        model.document.cards.append(duplicate)

        model.browserCanvasSize = CGSize(width: 1200, height: 800)
        let autoArrangeCards = model.browserAutoArrangeCardsInDocumentOrder()
        let matrixTargetCount = model.computeBrowserMatrixTargets(for: autoArrangeCards).count
        let treeTargetCount = model.computeBrowserTreeTargets(for: autoArrangeCards).count

        model.arrangeMode = "Matrix"
        model.browserAutoArrangeEnabled = true
        model.applyBrowserAutoArrangeStepIfNeeded(force: true)
        let matrixPosition = model.document.card(withID: childID)?.position ?? .zero

        model.arrangeMode = "Tree"
        model.browserAutoArrangeEnabled = true
        model.applyBrowserAutoArrangeStepIfNeeded(force: true)
        let treePosition = model.document.card(withID: childID)?.position ?? .zero

        return (autoArrangeCards.count, matrixTargetCount, treeTargetCount, matrixPosition, treePosition)
    }

    #expect(results.0 == 3)
    #expect(results.1 == 3)
    #expect(results.2 == 3)
    #expect(results.3 != FrievePoint(x: 0.58, y: 0.58))
    #expect(results.4 != FrievePoint(x: 0.58, y: 0.58))
}

@Test func shuffleLayoutRepositionsWholeBrowserLayoutInOnePass() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let results = await MainActor.run { () -> (FrievePoint, FrievePoint, FrievePoint, Int, Bool) in
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        let secondID = model.document.addCard(title: "Second", linkedFrom: rootID)
        let fixedID = model.document.addCard(title: "Fixed", linkedFrom: rootID)

        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 5.0, y: 5.0)
        }
        model.document.updateCard(secondID) { card in
            card.position = FrievePoint(x: -3.0, y: 8.0)
        }
        model.document.updateCard(fixedID) { card in
            card.position = FrievePoint(x: 9.0, y: 9.0)
            card.isFixed = true
        }

        let randomValues =
            Array(repeating: 1.0, count: 12) +
            Array(repeating: 0.0, count: 12) +
            Array(repeating: 0.5, count: 12) +
            Array(repeating: 1.0, count: 6) +
            Array(repeating: 0.0, count: 6)
        var index = 0
        let viewportBefore = model.browserViewportRevision

        model.shuffleLayout {
            let value = randomValues[index]
            index += 1
            return value
        }

        return (
            model.document.card(withID: rootID)!.position,
            model.document.card(withID: secondID)!.position,
            model.document.card(withID: fixedID)!.position,
            model.browserViewportRevision - viewportBefore,
            model.hasUnsavedChanges
        )
    }

    #expect(abs(results.0.x - 1.76) < 0.0001)
    #expect(abs(results.0.y + 0.76) < 0.0001)
    #expect(abs(results.1.x - 0.5) < 0.0001)
    #expect(abs(results.1.y - 0.5) < 0.0001)
    #expect(results.2 == FrievePoint(x: 9.0, y: 9.0))
    #expect(results.3 == 1)
    #expect(results.4)
}

@Test func inspectorVisibilityPersistsWhenToggled() async throws {
    let settings = await MainActor.run { AppSettings(userDefaults: UserDefaults(suiteName: "FrieveEditorMacTests.inspectorToggle")!) }
    let model = await MainActor.run { WorkspaceViewModel(settings: settings) }

    let states = await MainActor.run { () -> (Bool, Bool) in
        model.showInspector = false
        let hidden = model.settings.showInspector
        model.showInspector = true
        let shown = model.settings.showInspector
        return (hidden, shown)
    }

    #expect(states.0 == false)
    #expect(states.1 == true)
}

@Test func statusBarVisibilityPersistsWhenToggled() async throws {
    let settings = await MainActor.run { AppSettings(userDefaults: UserDefaults(suiteName: "FrieveEditorMacTests.statusBarToggle")!) }
    let model = await MainActor.run { WorkspaceViewModel(settings: settings) }

    let states = await MainActor.run { () -> (Bool, Bool) in
        model.showStatusBar = false
        let hidden = model.settings.showStatusBar
        model.showStatusBar = true
        let shown = model.settings.showStatusBar
        return (hidden, shown)
    }

    #expect(states.0 == false)
    #expect(states.1 == true)
}

@Test func automationSettingsPersistWhenEditedDirectly() async throws {
    let suiteName = "FrieveEditorMacTests.automationSettings"

    let values = await MainActor.run { () -> (Bool, Bool, String, Int, String) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.autoSaveDefault = false
        settings.autoReloadDefault = false
        settings.preferredWebSearchName = "DuckDuckGo"
        settings.readAloudRate = 7
        settings.gptModel = "gpt-4.1-mini"

        let reloaded = AppSettings(userDefaults: defaults)
        return (
            reloaded.autoSaveDefault,
            reloaded.autoReloadDefault,
            reloaded.preferredWebSearchName,
            Int(reloaded.readAloudRate),
            reloaded.gptModel
        )
    }

    #expect(values.0 == false)
    #expect(values.1 == false)
    #expect(values.2 == "DuckDuckGo")
    #expect(values.3 == 7)
    #expect(values.4 == "gpt-4.1-mini")
}

@Test func browserDisplaySettingsPersistWhenEditedDirectly() async throws {
    let suiteName = "FrieveEditorMacTests.browserDisplaySettings"

    let values = await MainActor.run { () -> (Bool, Bool, Int, Bool, Int, Bool) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.browserCardShadow = false
        settings.browserLinkVisible = false
        settings.browserImageLimitation = 160
        settings.browserEditInBrowserAlways = true
        settings.browserEditInBrowserPosition = BrowserInlineEditorPosition.browserRight.rawValue
        settings.browserScoreVisible = true
        settings.browserScoreType = BrowserScoreDisplayType.textLength.rawValue

        let reloaded = AppSettings(userDefaults: defaults)
        return (
            reloaded.browserCardShadow,
            reloaded.browserLinkVisible,
            reloaded.browserImageLimitation,
            reloaded.browserEditInBrowserAlways,
            reloaded.browserEditInBrowserPosition,
            reloaded.browserScoreVisible
        )
    }

    #expect(values.0 == false)
    #expect(values.1 == false)
    #expect(values.2 == 160)
    #expect(values.3 == true)
    #expect(values.4 == BrowserInlineEditorPosition.browserRight.rawValue)
    #expect(values.5 == true)
}

@Test func browserFontAndOtherSettingsPersistWhenEditedDirectly() async throws {
    let suiteName = "FrieveEditorMacTests.browserFontAndOtherSettings"

    let values = await MainActor.run { () -> (String, Int, Bool, Int, Bool, Bool, Int) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.browserFontFamily = "Helvetica"
        settings.browserFontSize = 17
        settings.browserWallpaperTiled = true
        settings.browserBackgroundAnimation = true
        settings.browserBackgroundAnimationType = BrowserBackgroundAnimationType.snow.rawValue
        settings.browserNoScrollLag = false
        settings.browserAntialiasingEnabled = false
        settings.browserAntialiasingSampleCount = 2

        let reloaded = AppSettings(userDefaults: defaults)
        return (
            reloaded.browserFontFamily,
            reloaded.browserFontSize,
            reloaded.browserWallpaperTiled,
            reloaded.browserBackgroundAnimationType,
            reloaded.browserBackgroundAnimation,
            reloaded.browserAntialiasingEnabled,
            reloaded.browserAntialiasingSampleCount
        )
    }

    #expect(values.0 == "Helvetica")
    #expect(values.1 == 17)
    #expect(values.2 == true)
    #expect(values.3 == BrowserBackgroundAnimationType.snow.rawValue)
    #expect(values.4 == true)
    #expect(values.5 == true)
    #expect(values.6 == 4)
}

@Test func browserFontAndRenderingHelpersUseConfiguredSettings() async throws {
    let values = await MainActor.run { () -> (CGFloat, Int, CFTimeInterval) in
        let defaults = UserDefaults(suiteName: "FrieveEditorMacTests.browserHelperSettings")!
        defaults.removePersistentDomain(forName: "FrieveEditorMacTests.browserHelperSettings")
        let settings = AppSettings(userDefaults: defaults)
        settings.browserFontFamily = "Helvetica"
        settings.browserFontSize = 16
        settings.browserNoScrollLag = true
        settings.browserAntialiasingEnabled = false
        settings.browserAntialiasingSampleCount = 2

        let model = WorkspaceViewModel(settings: settings)
        let card = FrieveCard(
            id: 1,
            title: "Font",
            bodyText: "",
            drawingEncoded: "",
            visible: true,
            shape: 2,
            size: 100,
            isTop: false,
            isFixed: false,
            isFolded: false,
            position: FrievePoint(x: 0.5, y: 0.5),
            created: "2026-04-14T00:00:00Z",
            updated: "2026-04-14T00:00:00Z",
            viewed: "2026-04-14T00:00:00Z",
            labelIDs: [],
            score: 0,
            imagePath: nil,
            videoPath: nil
        )
        let titleFont = model.browserCardTitleNSFont(for: card)
        return (
            titleFont.pointSize,
            model.browserAntialiasingSampleCount,
            model.browserChromeRefreshMinimumInterval()
        )
    }

    #expect(values.0 == 16)
    #expect(values.1 == 4)
    #expect(values.2 == 0)
}

@MainActor
@Test func browserOverlayTextHelpersFollowConfiguredSettings() async throws {
    let suiteName = "FrieveEditorMacTests.browserOverlayHelpers"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let settings = AppSettings(userDefaults: defaults)
    settings.browserTextVisible = true
    settings.browserTextCentering = true
    settings.browserTextWordWrap = true
    settings.browserFontFamily = "Helvetica"
    settings.browserFontSize = 18

    let model = WorkspaceViewModel(settings: settings)
    model.newDocument()

    #expect(model.browserShowsCardTextOverlay)
    #expect(model.browserCardTextOverlayFrameAlignment() == .center)
    #expect(model.browserCardTextOverlayTextAlignment() == .center)
    #expect(model.browserCardTextOverlayMaxWidth(in: CGSize(width: 1200, height: 800)) == 600)
    #expect(model.browserOverlayTitleNSFont().fontName.localizedCaseInsensitiveContains("helvetica"))
    #expect(model.browserOverlayTitleNSFont().pointSize == 18)

    settings.browserTextVisible = false
    settings.browserTextWordWrap = false

    #expect(!model.browserShowsCardTextOverlay)
    #expect(model.browserCardTextOverlayMaxWidth(in: CGSize(width: 1200, height: 800)) == nil)
}

@Test func browserSurfaceAppliesConfiguredAntialiasingSampleCount() async throws {
    let sampleCount = await MainActor.run { () -> Int in
        let defaults = UserDefaults(suiteName: "FrieveEditorMacTests.browserSampleCount")!
        defaults.removePersistentDomain(forName: "FrieveEditorMacTests.browserSampleCount")
        let settings = AppSettings(userDefaults: defaults)
        settings.browserAntialiasingEnabled = false
        settings.browserAntialiasingSampleCount = 2

        let model = WorkspaceViewModel(settings: settings)
        let view = BrowserSurfaceNSView(frame: .init(x: 0, y: 0, width: 640, height: 480))
        view.viewModel = model
        view.applyBrowserRenderingSettings()
        return view.browserSampleCount
    }

    #expect(sampleCount == 4)
}

@Test func browserRenderingHonorsConfiguredDisplaySettings() async throws {
    let suiteName = "FrieveEditorMacTests.browserRenderingSettings"

    let values = await MainActor.run { () -> (String, String?, Int, BrowserLabelOutlineStyle, Bool) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.browserTextVisible = false
        settings.browserLinkVisible = false
        settings.browserLabelCircleVisible = true
        settings.browserLabelRectangleVisible = false
        settings.browserLabelNameVisible = false
        settings.browserScoreVisible = true
        settings.browserScoreType = BrowserScoreDisplayType.textLength.rawValue

        let model = WorkspaceViewModel(settings: settings)
        model.document = FrieveDocument(
            title: "Display",
            metadata: [:],
            focusedCardID: 1,
            cards: [
                FrieveCard(
                    id: 1,
                    title: "Alpha",
                    bodyText: "Alpha body for score text",
                    drawingEncoded: "",
                    visible: true,
                    shape: 2,
                    size: 100,
                    isTop: false,
                    isFixed: false,
                    isFolded: false,
                    position: FrievePoint(x: 0.4, y: 0.5),
                    created: "2026-04-13T00:00:00Z",
                    updated: "2026-04-13T00:00:00Z",
                    viewed: "2026-04-13T00:00:00Z",
                    labelIDs: [1],
                    score: 0.75,
                    imagePath: nil,
                    videoPath: nil
                ),
                FrieveCard(
                    id: 2,
                    title: "Beta",
                    bodyText: "Beta body",
                    drawingEncoded: "",
                    visible: true,
                    shape: 2,
                    size: 100,
                    isTop: false,
                    isFixed: false,
                    isFolded: false,
                    position: FrievePoint(x: 0.7, y: 0.5),
                    created: "2026-04-13T00:00:00Z",
                    updated: "2026-04-13T00:00:00Z",
                    viewed: "2026-04-13T00:00:00Z",
                    labelIDs: [],
                    score: 0.25,
                    imagePath: nil,
                    videoPath: nil
                )
            ],
            links: [
                FrieveLink(fromCardID: 1, toCardID: 2, directionVisible: true, shape: 5, labelIDs: [], name: "Related")
            ],
            cardLabels: [
                FrieveLabel(id: 1, name: "Topic", color: 0x3366AA, enabled: true, show: true, hide: false, fold: false, size: 100)
            ],
            linkLabels: [],
            sourcePath: nil
        )
        model.selectedCardID = 1
        model.selectedCardIDs = [1]
        model.invalidateDocumentCaches()

        let metadata = model.metadata(for: model.document.cards[0])
        let scene = model.browserSurfaceScene(in: CGSize(width: 1200, height: 800))
        let labelGroup = scene.labelGroups.first
        return (
            metadata.summaryText,
            metadata.scoreText,
            scene.links.count,
            labelGroup?.outlineStyle ?? .none,
            labelGroup?.showsName ?? true
        )
    }

    #expect(values.0.isEmpty)
    #expect(values.1 == "Text 25")
    #expect(values.2 == 0)
    #expect(values.3 == .circle)
    #expect(values.4 == false)
}

@Test func browserLabelOutlineSupportsEllipse() async throws {
    let suiteName = "FrieveEditorMacTests.browserLabelEllipse"

    let values = await MainActor.run { () -> (BrowserLabelOutlineStyle, CGRect) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.browserLabelCircleVisible = true
        settings.browserLabelRectangleVisible = true

        let model = WorkspaceViewModel(settings: settings)
        model.document = FrieveDocument(
            title: "Ellipse",
            metadata: [:],
            focusedCardID: 1,
            cards: [
                FrieveCard(id: 1, title: "A", bodyText: "", drawingEncoded: "", visible: true, shape: 0, size: 100, isTop: false, isFixed: false, isFolded: false, position: FrievePoint(x: 0.2, y: 0.5), created: "", updated: "", viewed: "", labelIDs: [1], score: 0, imagePath: nil, videoPath: nil),
                FrieveCard(id: 2, title: "B", bodyText: "", drawingEncoded: "", visible: true, shape: 0, size: 100, isTop: false, isFixed: false, isFolded: false, position: FrievePoint(x: 0.8, y: 0.5), created: "", updated: "", viewed: "", labelIDs: [1], score: 0, imagePath: nil, videoPath: nil)
            ],
            links: [],
            cardLabels: [FrieveLabel(id: 1, name: "Topic", color: 0x3366AA, enabled: true, show: true, hide: false, fold: false, size: 100)],
            linkLabels: [],
            sourcePath: nil
        )
        let scene = model.browserSurfaceScene(in: CGSize(width: 1200, height: 800))
        let labelGroup = try! #require(scene.labelGroups.first)
        return (labelGroup.outlineStyle, labelGroup.worldRect)
    }

    #expect(values.0 == .ellipse)
    #expect(values.1.width > values.1.height)
}

@Test func browserPreviewSizeStepsStayDistinct() async throws {
    let sizes = await MainActor.run { () -> ([CGSize], [CGSize]) in
        let model = WorkspaceViewModel()
        model.newDocument()
        let card = model.selectedCard!
        let options = [32, 40, 64, 80, 120, 160, 240, 320]
        let mediaSizes = options.map { option -> CGSize in
            model.settings.browserImageLimitation = option
            return model.browserMediaPreviewSize(for: card)
        }
        let drawingSizes = options.map { option -> CGSize in
            model.settings.browserImageLimitation = option
            return model.browserDrawingPreviewSize(for: card)
        }
        return (mediaSizes, drawingSizes)
    }

    #expect(Set(sizes.0).count == sizes.0.count)
    #expect(Set(sizes.1).count == sizes.1.count)
    #expect(zip(sizes.0, sizes.0.dropFirst()).allSatisfy { $0.width < $1.width && $0.height < $1.height })
    #expect(zip(sizes.1, sizes.1.dropFirst()).allSatisfy { $0.width < $1.width && $0.height < $1.height })
}

@MainActor
@Test func browserMediaThumbnailStateUpdatesRasterCacheKey() async throws {
    let model = WorkspaceViewModel()
    model.newDocument()
    model.updateSelectedCardVideoPath("/tmp/sample.mov")
    let card = try #require(model.selectedCard)
    let snapshot = try #require(model.browserSurfaceScene(in: CGSize(width: 1200, height: 800)).cards.first)
    let initialKey = model.browserCardRasterCacheKey(for: snapshot)

    let dummyImage = NSImage(size: NSSize(width: 8, height: 8))
    if let mediaURL = model.mediaURL(for: card.videoPath) {
        model.cacheMediaImage(dummyImage, forKey: mediaURL.path)
    }

    let updatedKey = model.browserCardRasterCacheKey(for: snapshot)
    #expect(initialKey != updatedKey)
    #expect(model.cachedVideoPreviewImage(for: card) != nil)
}

@Test func browserInlineEditorSettingsControlAlwaysShowAndPlacement() async throws {
    let suiteName = "FrieveEditorMacTests.browserInlineEditorSettings"

    let values = await MainActor.run { () -> (Int?, Bool, CGRect, CGRect) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.browserEditInBrowser = true
        settings.browserEditInBrowserAlways = true
        settings.browserEditInBrowserPosition = BrowserInlineEditorPosition.browserRight.rawValue

        let model = WorkspaceViewModel(settings: settings)
        let rootID = model.document.sortedCards.first?.id ?? 0
        model.selectCard(rootID)
        let card = model.document.card(withID: rootID)!
        let rightFrame = model.browserInlineEditorFrame(for: card, in: CGSize(width: 900, height: 600), topInset: 52)
        model.clearSelection()
        let noSelectionVisible = model.browserShowsInlineEditorOverlay
        settings.browserEditInBrowserPosition = BrowserInlineEditorPosition.browserBottom.rawValue
        let bottomFrame = model.browserInlineEditorFrame(for: nil, in: CGSize(width: 900, height: 600))
        return (model.browserInlineEditorCard?.id, noSelectionVisible, rightFrame, bottomFrame)
    }

    #expect(values.0 == nil)
    #expect(values.1)
    #expect(values.2.maxX == 884)
    #expect(values.2.minX == 564)
    #expect(values.2.minY == 68)
    #expect(values.2.height == 516)
    #expect(values.3.minX == 16)
    #expect(values.3.maxY == 584)
    #expect(values.3.width == 868)
}

@Test func browserHUDAvoidanceInsetsFollowDockedInlineEditor() {
    let rightInsets = browserHUDAvoidanceInsets(
        placement: .browserRight,
        editorFrame: CGRect(x: 564, y: 68, width: 320, height: 516),
        canvasSize: CGSize(width: 900, height: 600),
        isEditorVisible: true
    )
    #expect(rightInsets.trailing == 336)
    #expect(rightInsets.bottom == 0)

    let bottomInsets = browserHUDAvoidanceInsets(
        placement: .browserBottom,
        editorFrame: CGRect(x: 16, y: 364, width: 868, height: 220),
        canvasSize: CGSize(width: 900, height: 600),
        isEditorVisible: true
    )
    #expect(bottomInsets.trailing == 0)
    #expect(bottomInsets.bottom == 236)

    let hiddenInsets = browserHUDAvoidanceInsets(
        placement: .browserRight,
        editorFrame: CGRect(x: 564, y: 68, width: 320, height: 516),
        canvasSize: CGSize(width: 900, height: 600),
        isEditorVisible: false
    )
    #expect(hiddenInsets == BrowserHUDAvoidanceInsets(bottom: 0, trailing: 0))
}

@Test func browserViewportSummaryHidesOnlyForDockedInlineEditor() {
    #expect(browserHidesViewportSummary(placement: .browserRight, isEditorVisible: true))
    #expect(browserHidesViewportSummary(placement: .browserBottom, isEditorVisible: true))
    #expect(!browserHidesViewportSummary(placement: .underCard, isEditorVisible: true))
    #expect(!browserHidesViewportSummary(placement: .browserRight, isEditorVisible: false))
}

@Test func browserUnderCardInlineEditorKeepsComfortableVerticalGap() async throws {
    let values = await MainActor.run { () -> (CGFloat, CGFloat) in
        let model = WorkspaceViewModel()
        model.newDocument()
        model.settings.browserEditInBrowserPosition = BrowserInlineEditorPosition.underCard.rawValue
        let cardID = try! #require(model.selectedCardID)
        model.document.updateCard(cardID) { card in
            card.position = FrievePoint(x: 0.5, y: 0.2)
        }
        model.invalidateDocumentCaches()
        let card = try! #require(model.selectedCard)
        let cardFrame = model.cardFrame(for: card, in: CGSize(width: 900, height: 600))
        let editorFrame = model.browserInlineEditorFrame(for: card, in: CGSize(width: 900, height: 600))
        return (cardFrame.maxY, editorFrame.minY)
    }

    #expect(values.1 - values.0 >= 18)
}

@Test func browserFixedWallpaperUsesViewportBelowToolbar() {
    let viewport = browserWallpaperViewportRect(in: CGSize(width: 900, height: 600), topInset: 52)
    #expect(viewport == CGRect(x: 0, y: 52, width: 900, height: 548))

    let drawRect = browserWallpaperRect(
        for: CGSize(width: 400, height: 200),
        in: viewport,
        fixed: true
    )
    #expect(drawRect.minY <= viewport.minY)
    #expect(drawRect.maxY >= viewport.maxY)
    #expect(drawRect.midX == viewport.midX)
    #expect(drawRect.midY == viewport.midY)
}

@Test func browserCenteredTextUsesViewportBelowToolbar() {
    let overlayViewport = browserTextOverlayViewportRect(in: CGSize(width: 1200, height: 800), topInset: 52)
    #expect(overlayViewport == CGRect(x: 0, y: 52, width: 1200, height: 748))
}

@Test func browserCenteredTextOffsetGrowsWhenContentOverflowsViewport() {
    #expect(browserCenteredTextVerticalOffset(contentHeight: 700, viewportHeight: 500) == 100)
    #expect(browserCenteredTextVerticalOffset(contentHeight: 400, viewportHeight: 500) == 0)
}

@Test func browserScrollableWallpaperTracksBrowserZoomAtOriginalSize() {
    let zoomOneRect = browserScrollableWallpaperRect(
        for: CGSize(width: 320, height: 180),
        anchor: CGPoint(x: 450, y: 300),
        zoom: 1
    )
    #expect(zoomOneRect == CGRect(x: 290, y: 210, width: 320, height: 180))

    let zoomTwoRect = browserScrollableWallpaperRect(
        for: CGSize(width: 320, height: 180),
        anchor: CGPoint(x: 450, y: 300),
        zoom: 2
    )
    #expect(zoomTwoRect == CGRect(x: 130, y: 120, width: 640, height: 360))
}

@Test func browserWallpaperTileSizingAndOriginFollowModeWithoutFitScaling() {
    let fixedTileSize = browserWallpaperTileSize(
        for: CGSize(width: 120, height: 90),
        fixed: true,
        zoom: 3
    )
    #expect(fixedTileSize == CGSize(width: 120, height: 90))

    let scrollingTileSize = browserWallpaperTileSize(
        for: CGSize(width: 120, height: 90),
        fixed: false,
        zoom: 2
    )
    #expect(scrollingTileSize == CGSize(width: 240, height: 180))

    let origin = browserWallpaperTileOrigin(
        anchor: CGPoint(x: 210, y: 135),
        tileSize: CGSize(width: 120, height: 90),
        in: CGRect(x: 0, y: 52, width: 900, height: 548)
    )
    #expect(origin.x <= 0)
    #expect(origin.y <= 52)
    #expect(origin.x + 120 > 0)
    #expect(origin.y + 90 > 52)
}

@Test func legacyReadSpeedSettingMigratesIntoNewIntegerRange() async throws {
    let suiteName = "FrieveEditorMacTests.legacyReadSpeedMigration"

    let migratedValue = await MainActor.run { () -> Int in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(175, forKey: "FrieveEditorMac.readAloudRate")

        let settings = AppSettings(userDefaults: defaults)
        return settings.readAloudRate
    }

    #expect(migratedValue == 0)
}

@Test func browserCardSizeStepMappingMatchesWindowsRange() async throws {
    #expect(browserCardStoredSize(forStep: -8) == 25)
    #expect(browserCardStoredSize(forStep: 0) == 100)
    #expect(browserCardStoredSize(forStep: 8) == 400)
    #expect(browserCardSizeStep(forStoredSize: 25) == -8)
    #expect(browserCardSizeStep(forStoredSize: 100) == 0)
    #expect(browserCardSizeStep(forStoredSize: 400) == 8)
}

@Test func browserTitleOnlyCardsSizeToFitTitle() async throws {
    let model = await MainActor.run {
        let suiteName = "FrieveEditorMacTests.browserTitleOnlySizing"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    }

    let sizes = await MainActor.run { () -> (CGSize, CGSize) in
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        model.document.updateCard(rootID) { card in
            card.title = "Short"
            card.size = browserCardStoredSize(forStep: -4)
        }
        model.invalidateDocumentCaches()
        let shortSize = model.cardCanvasSize(for: model.document.card(withID: rootID)!)

        model.document.updateCard(rootID) { card in
            card.title = "A much longer browser card title that should wrap across multiple lines"
            card.size = browserCardStoredSize(forStep: 4)
        }
        model.invalidateDocumentCaches()
        let longSize = model.cardCanvasSize(for: model.document.card(withID: rootID)!)
        return (shortSize, longSize)
    }

    #expect(sizes.0.width < 120)
    #expect(sizes.0.height <= 60)
    #expect(sizes.1.width >= sizes.0.width)
    #expect(sizes.1.height >= sizes.0.height)
}

@Test func browserAutoScrollMovesCanvasTowardSelectedCard() async throws {
    let model = await MainActor.run {
        let suiteName = "FrieveEditorMacTests.browserAutoScrollMovement"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    }

    let result = await MainActor.run { () -> (FrievePoint, FrievePoint, FrievePoint) in
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        let childID = model.document.addCard(title: "Child", linkedFrom: rootID)

        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.18, y: 0.22)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.84, y: 0.76)
        }
        model.invalidateDocumentCaches()

        model.canvasCenter = FrievePoint(x: 0.18, y: 0.22)
        model.autoScroll = true
        model.selectCard(childID)
        let steppedCenter = model.canvasCenter
        model.applyBrowserAutoScrollStepIfNeeded(at: CACurrentMediaTime() + 1.0)
        let completedCenter = model.canvasCenter
        let target = model.cardByID(childID)!.position
        model.resetBrowserAutoScrollAnimation()
        return (steppedCenter, completedCenter, target)
    }

    #expect(result.0.x > 0.18)
    #expect(result.0.y > 0.22)
    #expect(abs(result.1.x - result.2.x) < 0.0001)
    #expect(abs(result.1.y - result.2.y) < 0.0001)
}

@Test func browserNoScrollLagSettingControlsSelectionFollowDelay() async throws {
    let model = await MainActor.run {
        let suiteName = "FrieveEditorMacTests.browserNoScrollLag"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    }

    let result = await MainActor.run { () -> (FrievePoint, Bool, Bool, Bool, Bool, FrievePoint) in
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        let childID = model.document.addCard(title: "Child", linkedFrom: rootID)
        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.18, y: 0.22)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.84, y: 0.76)
        }
        model.invalidateDocumentCaches()

        model.settings.browserNoScrollLag = true
        model.canvasCenter = FrievePoint(x: 0.18, y: 0.22)
        model.autoScroll = true
        model.selectCard(childID)
        let delayedCenter = model.canvasCenter
        let baselineTime = CACurrentMediaTime()
        let delayedStep = model.applyBrowserAutoScrollStepIfNeeded(at: baselineTime + 0.5)
        let delayedZoomStep = model.applyBrowserAutoZoomStepIfNeeded(at: baselineTime + 0.5)
        let oneSecondStep = model.applyBrowserAutoScrollStepIfNeeded(at: baselineTime + 1.0)
        let oneSecondZoomStep = model.applyBrowserAutoZoomStepIfNeeded(at: baselineTime + 1.0)

        model.settings.browserNoScrollLag = false
        model.canvasCenter = FrievePoint(x: 0.18, y: 0.22)
        model.selectCard(rootID)
        model.selectCard(childID)
        let immediateCenter = model.canvasCenter

        return (delayedCenter, delayedStep, delayedZoomStep, oneSecondStep, oneSecondZoomStep, immediateCenter)
    }

    #expect(result.0 == FrievePoint(x: 0.18, y: 0.22))
    #expect(result.1 == false)
    #expect(result.2 == false)
    #expect(result.3 == true)
    #expect(result.4 == true)
    #expect(result.5.x > 0.18)
    #expect(result.5.y > 0.22)
}

@Test func browserLinkSnapshotUsesWorldCoordinatesForMetalRenderer() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1280, height: 840)

    let results = await MainActor.run { () -> (CGPoint, CGPoint, CGPoint, CGPoint) in
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        model.addChildCard()
        let childID = model.selectedCardID ?? rootID
        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.32, y: 0.36)
        }
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.74, y: 0.68)
        }
        model.document.links = [FrieveLink(fromCardID: rootID, toCardID: childID, directionVisible: true, shape: 2, labelIDs: [], name: "Route")]
        model.resetCanvasToFit(in: canvasSize)
        model.markBrowserSurfaceContentDirty()
        let scene = model.browserSurfaceScene(in: canvasSize)
        let link = try! #require(scene.links.first)
        let worldStart = CGPoint(x: model.currentPosition(for: model.document.card(withID: rootID)!).x, y: model.currentPosition(for: model.document.card(withID: rootID)!).y)
        let worldEnd = CGPoint(x: model.currentPosition(for: model.document.card(withID: childID)!).x, y: model.currentPosition(for: model.document.card(withID: childID)!).y)
        let expectedCanvasStart = worldStart.applying(scene.worldToCanvasTransform)
        let expectedCanvasEnd = worldEnd.applying(scene.worldToCanvasTransform)
        return (link.startPoint, link.endPoint, expectedCanvasStart, expectedCanvasEnd)
    }

    #expect(abs(results.0.x - results.2.x) > 1)
    #expect(abs(results.0.y - results.2.y) > 1)
    #expect(abs(results.1.x - results.3.x) > 1)
    #expect(abs(results.1.y - results.3.y) > 1)
}

@Test func browserLabelRectanglesEncloseAllCardsForSameLabel() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1280, height: 840)

    let results = await MainActor.run { () -> (CGRect, CGRect, String) in
        model.newDocument()
        let rootID = model.document.sortedCards.first?.id ?? 0
        let secondID = model.document.addCard(title: "Second", linkedFrom: rootID)
        let thirdID = model.document.addCard(title: "Third", linkedFrom: rootID)

        model.document.updateCard(rootID) { card in
            card.position = FrievePoint(x: 0.22, y: 0.24)
            card.labelIDs = [1]
        }
        model.document.updateCard(secondID) { card in
            card.position = FrievePoint(x: 0.38, y: 0.34)
            card.labelIDs = [1]
        }
        model.document.updateCard(thirdID) { card in
            card.position = FrievePoint(x: 0.82, y: 0.72)
            card.labelIDs = []
        }

        model.markBrowserSurfaceContentDirty()
        let scene = model.browserSurfaceScene(in: canvasSize)
        let labelGroup = try! #require(scene.labelGroups.first { $0.id == 1 })
        let firstFrame = model.cardWorldFrame(for: model.document.card(withID: rootID)!, in: canvasSize)
        let secondFrame = model.cardWorldFrame(for: model.document.card(withID: secondID)!, in: canvasSize)
        return (labelGroup.worldRect, firstFrame.union(secondFrame), labelGroup.name)
    }

    #expect(abs(results.0.minX - results.1.minX) < 0.0001)
    #expect(abs(results.0.minY - results.1.minY) < 0.0001)
    #expect(abs(results.0.maxX - results.1.maxX) < 0.0001)
    #expect(abs(results.0.maxY - results.1.maxY) < 0.0001)
    #expect(results.2 == "Overview")
}

@Test func legacyHelpFileLoadsAsDocument() async throws {
    let helpURL = URL(fileURLWithPath: "/Users/yuto/SoftwareProjects/Frieve-Editor/windows/resource/help.fip")
    let document = try DocumentFileCodec.load(url: helpURL)

    #expect(document.cardCount > 0)
    #expect(document.focusedCardID != nil)
}

@Test func browserAutoArrangeStepScaleUsesStableFixedScaleAt60Hz() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    await MainActor.run {
        #expect(abs(model.browserAutoArrangeStepScale() - 0.5) < 0.0001)
    }
}

@Test func draggingSelectionOnlyInvalidatesBrowserPresentation() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1200, height: 800)

    await MainActor.run {
        model.newDocument()
        model.addChildCard()
        let draggedID = model.selectedCardID ?? 0
        let beforeContentRevision = model.browserSurfaceContentRevision
        let beforePresentationRevision = model.browserSurfacePresentationRevision
        let startPoint = CGPoint(x: 400, y: 300)
        let currentPoint = CGPoint(x: 460, y: 340)

        model.beginCardInteraction(cardID: draggedID, modifiers: [])
        model.updateCardInteraction(
            cardID: draggedID,
            from: startPoint,
            to: currentPoint,
            in: canvasSize,
            modifiers: []
        )

        #expect(model.browserSurfaceContentRevision == beforeContentRevision)
        #expect(model.browserSurfacePresentationRevision > beforePresentationRevision)
        #expect(model.currentDragTranslation != nil)
        let draggedCard = try! #require(model.document.card(withID: draggedID))
        #expect(model.currentPosition(for: draggedCard) != draggedCard.position)
    }
}

@MainActor
@Test func draggingCardKeepsMovedTitleTextureVisibleAfterPresentationRefresh() throws {
    let model = WorkspaceViewModel()
    let canvasSize = CGSize(width: 1200, height: 800)
    let view = BrowserSurfaceNSView(frame: CGRect(origin: .zero, size: canvasSize))
    view.viewModel = model

    model.newDocument()
    let draggedID = 0
    model.selectCard(draggedID)
    view.refreshFromViewModel()

    let startPoint = CGPoint(x: 420, y: 310)
    let currentPoint = CGPoint(x: 500, y: 360)
    model.beginCardInteraction(cardID: draggedID, modifiers: [])
    model.updateCardInteraction(
        cardID: draggedID,
        from: startPoint,
        to: currentPoint,
        in: canvasSize,
        modifiers: []
    )
    model.endCardInteraction(at: currentPoint, in: canvasSize)
    view.refreshFromViewModel()

    guard let movedCard = model.cardByID(draggedID) else {
        Issue.record("Expected moved card")
        return
    }
    let movedSnapshot = BrowserCardLayerSnapshot(
        card: movedCard,
        position: model.currentPosition(for: movedCard),
        metadata: model.metadata(for: movedCard),
        isSelected: model.selectedCardIDs.contains(draggedID),
        isHovered: false,
        detailLevel: model.browserCardDetailLevel()
    )
    let movedRasterKey = model.browserCardRasterKey(for: movedSnapshot)
    #expect(model.cachedBrowserCardRaster(for: movedSnapshot, cacheKey: movedRasterKey) != nil)

    model.markBrowserSurfacePresentationDirty()
    view.refreshFromViewModel()

    #expect(view.debugVisibleAtlasKeys().contains(movedRasterKey))
}

@Test func browserCanvasPanningSuspendsAutoArrangeUntilGestureEnds() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1200, height: 800)

    await MainActor.run {
        model.newDocument()
        model.addChildCard()
        let firstChildID = model.selectedCardID ?? 1
        model.addChildCard()
        let secondChildID = model.selectedCardID ?? 2

        model.document.updateCard(0) { card in
            card.position = FrievePoint(x: 0.84, y: 0.14)
        }
        model.document.updateCard(firstChildID) { card in
            card.position = FrievePoint(x: 0.12, y: 0.87)
        }
        model.document.updateCard(secondChildID) { card in
            card.position = FrievePoint(x: 0.9, y: 0.82)
        }

        model.selectedTab = .browser
        model.arrangeMode = "Matrix"

        let beforeContentRevision = model.browserSurfaceContentRevision
        let beforePositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        #expect(model.browserAutoArrangeTimer != nil)

        model.beginCanvasGesture(at: CGPoint(x: 320, y: 240), modifiers: [])
        #expect(model.shouldSuspendBrowserAutoArrangeForCurrentGesture)
        #expect(model.browserAutoArrangeTimer == nil)

        model.applyBrowserAutoArrangeStepIfNeeded()
        let suspendedPositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        #expect(model.browserSurfaceContentRevision == beforeContentRevision)
        #expect(suspendedPositions == beforePositions)

        model.endCanvasGesture(in: canvasSize)
        #expect(!model.shouldSuspendBrowserAutoArrangeForCurrentGesture)
        #expect(model.browserAutoArrangeTimer != nil)

        model.applyBrowserAutoArrangeStepIfNeeded()
        let afterPositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        #expect(model.browserSurfaceContentRevision > beforeContentRevision)
        #expect(afterPositions != beforePositions)
    }
}

@Test func browserScrollWheelSuspendsAutoArrangeWhilePanningViewport() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }
    let canvasSize = CGSize(width: 1200, height: 800)

    await MainActor.run {
        model.newDocument()
        model.addChildCard()
        let firstChildID = model.selectedCardID ?? 1
        model.addChildCard()
        let secondChildID = model.selectedCardID ?? 2

        model.document.updateCard(0) { card in
            card.position = FrievePoint(x: 0.84, y: 0.14)
        }
        model.document.updateCard(firstChildID) { card in
            card.position = FrievePoint(x: 0.12, y: 0.87)
        }
        model.document.updateCard(secondChildID) { card in
            card.position = FrievePoint(x: 0.9, y: 0.82)
        }

        model.selectedTab = .browser
        model.arrangeMode = "Matrix"

        let beforeContentRevision = model.browserSurfaceContentRevision
        let beforePositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        #expect(model.browserAutoArrangeTimer != nil)

        model.handleScrollWheel(deltaX: 24, deltaY: 36, modifiers: [], at: CGPoint(x: 500, y: 320), in: canvasSize)
        #expect(model.browserAutoArrangeTimer == nil)
        #expect(CACurrentMediaTime() < model.browserAutoArrangeSuspendedUntil)

        model.applyBrowserAutoArrangeStepIfNeeded()
        let suspendedPositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        #expect(model.browserSurfaceContentRevision == beforeContentRevision)
        #expect(suspendedPositions == beforePositions)
    }

    try await Task.sleep(nanoseconds: 300_000_000)

    await MainActor.run {
        #expect(model.browserAutoArrangeTimer != nil)

        let beforeResumeRevision = model.browserSurfaceContentRevision
        let beforeResumePositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        model.applyBrowserAutoArrangeStepIfNeeded()
        let afterResumePositions = Dictionary(uniqueKeysWithValues: model.document.cards.map { ($0.id, $0.position) })
        #expect(model.browserSurfaceContentRevision > beforeResumeRevision)
        #expect(afterResumePositions != beforeResumePositions)
    }
}

@MainActor
@Test func browserMiddleButtonDragPansCanvasWithoutMovingCards() throws {
    let model = WorkspaceViewModel()
    let canvasSize = CGSize(width: 1200, height: 800)
    let view = BrowserSurfaceNSView(frame: CGRect(origin: .zero, size: canvasSize))
    view.viewModel = model

    model.newDocument()
    model.addChildCard()
    let cardID = model.selectedCardID ?? 1
    model.selectedTab = .browser

    let initialCenter = model.canvasCenter
    let initialCardPosition = model.cardByID(cardID)!.position
    let startPoint = model.canvasPoint(for: initialCardPosition, in: canvasSize)

    view.beginMiddleButtonCanvasPan(at: startPoint)
    view.updateMiddleButtonCanvasPan(to: CGPoint(x: startPoint.x + 120, y: startPoint.y + 70))
    view.endMiddleButtonCanvasPan(at: CGPoint(x: startPoint.x + 120, y: startPoint.y + 70))

    let finalCenter = model.canvasCenter
    let finalCardPosition = model.cardByID(cardID)!.position
    #expect(finalCenter != initialCenter)
    #expect(finalCardPosition == initialCardPosition)
    #expect(model.browserGestureMode == nil)
    #expect(view.bounds.size == canvasSize)
}

@MainActor
@Test func browserLeftDragOnEmptyCanvasMarqueeSelectsCards() throws {
    let model = WorkspaceViewModel()
    let canvasSize = CGSize(width: 1200, height: 800)
    let view = BrowserSurfaceNSView(frame: CGRect(origin: .zero, size: canvasSize))
    view.viewModel = model

    model.newDocument()
    model.addChildCard()
    let firstChildID = model.selectedCardID ?? 1
    model.addChildCard()
    let secondChildID = model.selectedCardID ?? 2
    model.selectedTab = .browser

    model.document.updateCard(0) { card in
        card.position = FrievePoint(x: 0.30, y: 0.34)
    }
    model.document.updateCard(firstChildID) { card in
        card.position = FrievePoint(x: 0.42, y: 0.48)
    }
    model.document.updateCard(secondChildID) { card in
        card.position = FrievePoint(x: 0.78, y: 0.76)
    }
    model.clearSelection()

    let startPoint = model.canvasPoint(for: FrievePoint(x: 0.22, y: 0.24), in: canvasSize)
    let endPoint = model.canvasPoint(for: FrievePoint(x: 0.52, y: 0.58), in: canvasSize)
    let initialCenter = model.canvasCenter

    view.beginPrimaryCanvasSelection(at: startPoint)
    view.updatePrimaryCanvasSelection(to: endPoint)
    view.endPrimaryCanvasSelection(at: endPoint)

    #expect(model.selectedCardIDs.contains(0))
    #expect(model.selectedCardIDs.contains(firstChildID))
    #expect(!model.selectedCardIDs.contains(secondChildID))
    #expect(model.canvasCenter == initialCenter)
    #expect(model.browserGestureMode == nil)
}

@MainActor
@Test func browserCardContextMenuSelectsRightClickedCardAndExposesExpectedActions() throws {
    let model = WorkspaceViewModel()
    let view = BrowserSurfaceNSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
    view.viewModel = model

    model.newDocument()
    model.addChildCard()
    let firstChildID = model.selectedCardID ?? 1
    model.addChildCard()
    let secondChildID = model.selectedCardID ?? 2
    model.selectCard(firstChildID)

    let menu = view.cardContextMenu(forCardID: secondChildID)
    let titles = menu?.items.map(\.title) ?? []

    #expect(model.selectedCardID == secondChildID)
    #expect(model.selectedCardIDs == [secondChildID])
    #expect(titles.contains("Edit Card"))
    #expect(titles.contains("New Child Card"))
    #expect(titles.contains("New Sibling Card"))
    #expect(titles.contains("Fix Card"))
    #expect(titles.contains("Fold Card"))
    #expect(titles.contains("Web Search"))
    #expect(titles.contains("Copy GPT Prompt"))
    #expect(titles.contains("Delete Card"))
    #expect(titles.contains("Undo"))
}

@MainActor
@Test func browserCardContextMenuActionsAffectSelectedCard() throws {
    let model = WorkspaceViewModel()
    let view = BrowserSurfaceNSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
    view.viewModel = model

    model.newDocument()
    model.addChildCard()
    let cardID = model.selectedCardID ?? 1

    guard let menu = view.cardContextMenu(forCardID: cardID),
          let fixItem = menu.items.first(where: { $0.title == "Fix Card" }),
          let deleteItem = menu.items.first(where: { $0.title == "Delete Card" }) else {
        Issue.record("Expected context menu items were missing")
        return
    }

    _ = view.perform(fixItem.action, with: fixItem)
    #expect(model.cardByID(cardID)?.isFixed == true)

    _ = view.perform(deleteItem.action, with: deleteItem)
    #expect(model.cardByID(cardID) == nil)
}

@MainActor
@Test func browserRefreshSynchronizesAppearanceBeforeRedraw() throws {
    let suiteName = "FrieveEditorMacTests.browserAppearanceRefresh"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let model = WorkspaceViewModel(settings: AppSettings(userDefaults: defaults))
    let view = BrowserSurfaceNSView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
    view.viewModel = model
    model.newDocument()

    view.updateColorScheme(.light)
    let lightLuminance = try #require(browserTestLuminance(from: view.layer?.backgroundColor))
    let lightCanvasLuminance = try #require(browserTestLuminance(from: view.browserCanvasClearColor))
    #expect(view.browserAppearanceSignature == 0)

    view.updateColorScheme(.dark)
    let darkLuminance = try #require(browserTestLuminance(from: view.layer?.backgroundColor))
    let darkCanvasLuminance = try #require(browserTestLuminance(from: view.browserCanvasClearColor))
    #expect(view.browserAppearanceSignature == 1)
    #expect(darkLuminance < lightLuminance)
    #expect(darkCanvasLuminance < lightCanvasLuminance)
}

@Test func webSearchQueryUsesCardTitleOnlyForSingleSelection() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let query = await MainActor.run { () -> String in
        model.newDocument()
        model.addChildCard()
        let cardID = model.selectedCardID ?? 1
        model.document.updateCard(cardID) { card in
            card.title = "Short Query Title"
            card.bodyText = "Very long body text that should not be included in the web search query."
        }
        return model.selectedWebSearchQuery()
    }

    #expect(query == "Short Query Title")
}

@Test func drawingCanvasViewportPanAndZoomPreserveAnchor() {
    var viewport = DrawingCanvasViewport()
    let canvasSize = CGSize(width: 400, height: 300)
    let anchor = CGPoint(x: 120, y: 90)
    let normalized = CGPoint(x: 0.3, y: 0.3)

    let initialPoint = viewport.canvasPoint(from: normalized, in: canvasSize)
    #expect(initialPoint == anchor)

    viewport.pan(by: CGSize(width: 24, height: -18), in: canvasSize)
    let pannedPoint = viewport.canvasPoint(from: normalized, in: canvasSize)
    #expect(pannedPoint.x == initialPoint.x + 24)
    #expect(pannedPoint.y == initialPoint.y - 18)

    viewport.zoom(by: 2.0, anchor: pannedPoint, in: canvasSize)
    let zoomedAnchorPoint = viewport.canvasPoint(from: normalized, in: canvasSize)
    #expect(abs(zoomedAnchorPoint.x - pannedPoint.x) < 0.001)
    #expect(abs(zoomedAnchorPoint.y - pannedPoint.y) < 0.001)
}

@Test func browserChromeRefreshIsDeferredDuringActiveGesture() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    await MainActor.run {
        let beforeRevision = model.browserChromeRevision
        model.beginCanvasGesture(at: CGPoint(x: 10, y: 10), modifiers: [])
        model.scheduleBrowserChromeRefresh(minimumInterval: 0)
        #expect(model.browserChromeRevision == beforeRevision)

        model.endCanvasGesture(in: CGSize(width: 1200, height: 800))
        model.scheduleBrowserChromeRefresh(immediate: true)
        #expect(model.browserChromeRevision > beforeRevision)
    }
}

private func browserTestLuminance(from color: CGColor?) -> Double? {
    guard let color,
          let nsColor = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else {
        return nil
    }
    return (Double(nsColor.redComponent) * 0.2126) +
        (Double(nsColor.greenComponent) * 0.7152) +
        (Double(nsColor.blueComponent) * 0.0722)
}

private func browserTestLuminance(from color: MTLClearColor) -> Double? {
    (color.red * 0.2126) + (color.green * 0.7152) + (color.blue * 0.0722)
}
