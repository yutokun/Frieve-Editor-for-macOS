import Foundation
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

    let results = await MainActor.run { () -> (Int, CGRect, Bool, Bool, Bool, Bool, String) in
        model.newDocument()
        let rootID = model.selectedCardID ?? 0
        model.updateSelectedCardShape(4)
        model.updateSelectedCardSizeStep(5)
        model.updateSelectedCardImagePath("/tmp/example.png")
        model.updateSelectedCardVideoPath("clips/demo.mov")
        model.updateSelectedCardDrawing("line 0.1 0.2 0.9 0.8 color=FF0000\nrect 0.2 0.2 0.7 0.6 fill=00FF00")
        model.handleCardDoubleClick(rootID)
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
            model.browserInlineEditorCardID == rootID,
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
    #expect(results.6.contains("Center"))
    #expect(results.6.contains("|nop"))
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
        model.arrangeCards()
        for _ in 0..<6 {
            model.applyBrowserAutoArrangeStepIfNeeded()
        }
        let matrixEnabled = model.browserAutoArrangeEnabled
        let matrixChanged = [rootID, childA, childB, childC].contains { id in
            guard let card = model.document.card(withID: id) else { return false }
            return card.position != .zero
        }

        model.arrangeMode = "Tree"
        model.arrangeCards()
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
