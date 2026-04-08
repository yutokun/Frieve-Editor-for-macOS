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
        model.beginCanvasGesture(at: CGPoint(x: 400, y: 300), modifiers: [])
        model.updateCanvasGesture(from: CGPoint(x: 400, y: 300), to: CGPoint(x: 520, y: 360), in: canvasSize)
        model.endCanvasGesture(in: canvasSize)
    }
    let movedCenter = await MainActor.run { model.canvasCenter }
    #expect(movedCenter != initialCenter)

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
        model.updateSelectedCardSize(210)
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

@Test func legacyHelpFileLoadsAsDocument() async throws {
    let helpURL = URL(fileURLWithPath: "/Users/yuto/SoftwareProjects/Frieve-Editor/windows/resource/help.fip")
    let document = try DocumentFileCodec.load(url: helpURL)

    #expect(document.cardCount > 0)
    #expect(document.focusedCardID != nil)
}
