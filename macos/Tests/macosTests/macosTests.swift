import Foundation
import AppKit
import SwiftUI
import Testing
@testable import macos

@Test func placeholderDocumentHasFocusableRootCard() async throws {
    let document = FrieveDocument.placeholder()

    #expect(document.cardCount == 1)
    #expect(document.focusedCardID == 0)
    #expect(document.cards.first?.title == "Frieve Editor")
}

@Test func fip2RoundTripPreservesCardAndLinkData() async throws {
    var document = FrieveDocument.placeholder()
    let childID = document.addCard(title: "Child", linkedFrom: 0)
    document.updateCard(childID) { card in
        card.bodyText = "Body\nSecond line"
        card.drawingEncoded = "DrawPayload"
        card.labelIDs = [1]
        card.score = 2.75
    }
    document.metadata["Language"] = "Japanese"

    let serialized = FIP2Codec.save(document: document)
    let decoded = try FIP2Codec.load(text: serialized)

    #expect(decoded.cardCount == 2)
    #expect(decoded.linkCount == 1)
    #expect(decoded.card(withID: childID)?.bodyText == "Body\nSecond line")
    #expect(decoded.card(withID: childID)?.drawingEncoded == "DrawPayload")
    #expect(decoded.card(withID: childID)?.score == 2.75)
    #expect(decoded.metadata["Language"] == "Japanese")
    #expect(decoded.metadata["Title"] == decoded.title)
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

    let results = await MainActor.run { () -> (Int, Bool, Bool, Bool) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        let originalCount = model.document.cardCount
        model.handleBrowserCreateSiblingShortcut()
        let siblingID = model.selectedCardID ?? -1
        let sibling = model.document.card(withID: siblingID)
        return (
            model.document.cardCount - originalCount,
            siblingID != rootID,
            sibling?.position.y == model.document.card(withID: rootID)?.position.y,
            model.browserInlineEditorCardID == sibling?.id
        )
    }

    #expect(results.0 == 1)
    #expect(results.1)
    #expect(results.2)
    #expect(results.3)
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

@Test func browserAutoZoomCentersAndFitsSelectionWhenEnabled() async throws {
    let model = await MainActor.run { WorkspaceViewModel() }

    let result = await MainActor.run { () -> (Bool, Bool) in
        model.newDocument()
        model.browserCanvasSize = CGSize(width: 1200, height: 800)
        let rootID = model.selectedCardID ?? 0
        let childID = model.document.addCard(title: "Zoom Target", linkedFrom: rootID)
        model.document.updateCard(childID) { card in
            card.position = FrievePoint(x: 0.82, y: 0.27)
        }

        model.autoZoom = false
        let beforeCenter = model.canvasCenter
        model.selectCard(childID)
        let centerWithoutAutoZoom = model.canvasCenter == beforeCenter

        model.selectCard(rootID)
        model.autoZoom = true
        model.selectCard(childID)
        let target = model.document.card(withID: childID)?.position ?? .zero
        let centeredOnSelection = hypot(model.canvasCenter.x - target.x, model.canvasCenter.y - target.y) < 0.0001

        return (centerWithoutAutoZoom, centeredOnSelection)
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

@Test func automationSettingsPersistWhenEditedDirectly() async throws {
    let suiteName = "FrieveEditorMacTests.automationSettings"

    let values = await MainActor.run { () -> (Bool, Bool, String, Int, String) in
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(userDefaults: defaults)
        settings.autoSaveDefault = false
        settings.autoReloadDefault = false
        settings.preferredWebSearchName = "DuckDuckGo"
        settings.readAloudRate = 205
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
    #expect(values.3 == 205)
    #expect(values.4 == "gpt-4.1-mini")
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
    let model = await MainActor.run { WorkspaceViewModel() }

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
    let model = await MainActor.run { WorkspaceViewModel() }

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
