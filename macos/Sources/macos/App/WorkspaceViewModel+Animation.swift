import SwiftUI
import AppKit

extension WorkspaceViewModel {
    private var browserAnimationFrameInterval: CFTimeInterval { 1.0 / 60.0 }

    var isBrowserAnimationActive: Bool {
        activeBrowserAnimation != nil
    }

    func startBrowserAnimation(_ mode: BrowserAnimationMode) {
        stopBrowserAnimation()

        browserAnimationBackupDocument = document
        browserAnimationBackupSelectedCardID = selectedCardID
        browserAnimationBackupSelectedCardIDs = selectedCardIDs
        browserAnimationBackupCanvasCenter = canvasCenter
        browserAnimationBackupZoom = zoom
        browserAnimationBackupArrangeMode = arrangeMode
        browserAnimationBackupAutoArrangeEnabled = browserAutoArrangeEnabled
        browserAnimationBackupAutoScroll = autoScroll
        browserAnimationBackupAutoZoom = autoZoom

        activeBrowserAnimation = mode
        animationPaused = false
        browserAnimationCountdownMilliseconds = 0
        browserAnimationTracePreviousCardID = nil
        browserAnimationActiveCardIDs = Array(repeating: nil, count: 30)
        browserAnimationVelocityByCardID.removeAll(keepingCapacity: true)

        selectedTab = .browser
        autoScroll = false
        autoZoom = false
        browserAutoArrangeEnabled = false
        arrangeMode = "None"

        switch mode {
        case .randomFlash:
            prepareRandomFlashAnimation()
        case .randomMap:
            prepareRandomMapAnimation()
        case .randomScroll:
            prepareRandomMotionAnimation(.randomScroll)
        case .randomJump:
            prepareRandomMotionAnimation(.randomJump)
        case .randomTrace:
            prepareRandomTraceAnimation()
        }

        ensureBrowserAnimationTimer()
        statusMessage = "Started \(mode.title)"
    }

    func stopBrowserAnimation() {
        browserAnimationTimer?.invalidate()
        browserAnimationTimer = nil

        if let backup = browserAnimationBackupDocument {
            document = backup
            selectedCardID = browserAnimationBackupSelectedCardID
            selectedCardIDs = browserAnimationBackupSelectedCardIDs
            arrangeMode = browserAnimationBackupArrangeMode ?? "None"
            browserAutoArrangeEnabled = browserAnimationBackupAutoArrangeEnabled ?? false
            autoScroll = browserAnimationBackupAutoScroll ?? false
            autoZoom = browserAnimationBackupAutoZoom ?? true
            canvasCenter = browserAnimationBackupCanvasCenter ?? canvasCenter
            zoom = browserAnimationBackupZoom ?? zoom
        }

        browserAnimationBackupDocument = nil
        browserAnimationBackupSelectedCardID = nil
        browserAnimationBackupSelectedCardIDs = []
        browserAnimationBackupCanvasCenter = nil
        browserAnimationBackupZoom = nil
        browserAnimationBackupArrangeMode = nil
        browserAnimationBackupAutoArrangeEnabled = nil
        browserAnimationBackupAutoScroll = nil
        browserAnimationBackupAutoZoom = nil
        browserAnimationCountdownMilliseconds = 0
        browserAnimationTracePreviousCardID = nil
        browserAnimationActiveCardIDs = Array(repeating: nil, count: 30)
        browserAnimationVelocityByCardID.removeAll(keepingCapacity: true)
        activeBrowserAnimation = nil

        markBrowserSurfaceContentDirty()
        markBrowserSurfacePresentationDirty()
        markBrowserSurfaceViewportDirty()
        statusMessage = "Stopped animation"
    }

    func toggleBrowserAnimationPause() {
        guard activeBrowserAnimation != nil else { return }
        animationPaused.toggle()
        statusMessage = animationPaused ? "Paused animation" : "Resumed animation"
    }

    func toggleBrowserAnimationFullScreen() {
        NSApplication.shared.keyWindow?.toggleFullScreen(nil)
    }

    func setBrowserAnimationZoom(_ nextZoom: Double) {
        zoom = min(max(nextZoom, 0.1), 10.0)
        markBrowserSurfaceViewportDirty()
    }

    private func ensureBrowserAnimationTimer() {
        guard browserAnimationTimer == nil else { return }
        let timer = Timer(timeInterval: browserAnimationFrameInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.applyBrowserAnimationStep()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        browserAnimationTimer = timer
    }

    private func applyBrowserAnimationStep() {
        guard let mode = activeBrowserAnimation else { return }
        switch mode {
        case .randomFlash:
            applyRandomFlashAnimationStep()
        case .randomMap:
            applyRandomMapAnimationStep()
        case .randomScroll:
            applyRandomMotionAnimationStep(jumping: false)
        case .randomJump:
            applyRandomMotionAnimationStep(jumping: true)
        case .randomTrace:
            applyRandomTraceAnimationStep()
        }
    }

    private func animationIntervalMilliseconds(base: Double) -> Double {
        base * pow(2.0, -Double(animationSpeed - 30) / 25.0)
    }

    private func animationVisibleSourceCards() -> [FrieveCard] {
        let cards = (browserAnimationBackupDocument ?? document).cards.filter(\.visible)
        return cards.isEmpty ? (browserAnimationBackupDocument ?? document).cards : cards
    }

    private func randomAnimationCardSelection(limit: Int, excluding excluded: Set<Int> = []) -> [FrieveCard] {
        var candidates = animationVisibleSourceCards().filter { !excluded.contains($0.id) }
        guard !candidates.isEmpty else { return [] }

        let limit = min(max(limit, 1), candidates.count)
        var selection: [FrieveCard] = []
        selection.reserveCapacity(limit)
        while selection.count < limit, !candidates.isEmpty {
            let index = Int.random(in: 0 ..< candidates.count)
            selection.append(candidates.remove(at: index))
        }
        return selection
    }

    private func prepareRandomFlashAnimation() {
        requestBrowserFit()
        performRandomFlashCycle()
    }

    private func applyRandomFlashAnimationStep() {
        guard !animationPaused else { return }
        browserAnimationCountdownMilliseconds -= browserAnimationFrameInterval * 1000
        if browserAnimationCountdownMilliseconds <= 0 {
            performRandomFlashCycle()
        }
    }

    private func performRandomFlashCycle() {
        guard let backup = browserAnimationBackupDocument else { return }
        let chosenCards = randomAnimationCardSelection(limit: animationVisibleCardCount)
        let chosenIDs = Set(chosenCards.map(\.id))
        let selectedID = chosenCards.randomElement()?.id

        document = backup
        for card in document.cards {
            document.updateCard(card.id) { draft in
                draft.visible = chosenIDs.contains(card.id)
            }
        }
        selectedCardID = selectedID
        selectedCardIDs = selectedID.map { [$0] } ?? []
        browserAnimationCountdownMilliseconds = animationIntervalMilliseconds(base: 3000)
        requestBrowserFit()
    }

    private func prepareRandomMapAnimation() {
        arrangeMode = "Link(Soft)"
        browserAutoArrangeEnabled = true
        requestBrowserFit()
        resetRandomMapDocument()
    }

    private func applyRandomMapAnimationStep() {
        guard !animationPaused else { return }
        browserAnimationCountdownMilliseconds -= browserAnimationFrameInterval * 1000
        if browserAnimationCountdownMilliseconds > 0 {
            return
        }

        let visibleIDs = Set(document.cards.filter(\.visible).map(\.id))
        let maxVisible = max(1, animationVisibleCardCount)
        if visibleIDs.count >= maxVisible {
            resetRandomMapDocument()
            return
        }

        guard let selectedCardID else {
            resetRandomMapDocument()
            return
        }

        let nextIDs = document.links.reduce(into: [Int]()) { partial, link in
            if link.fromCardID == selectedCardID && !visibleIDs.contains(link.toCardID) {
                partial.append(link.toCardID)
            } else if link.toCardID == selectedCardID && !visibleIDs.contains(link.fromCardID) {
                partial.append(link.fromCardID)
            }
        }

        if nextIDs.isEmpty {
            resetRandomMapDocument()
            return
        }

        let revealCount = min(maxVisible - visibleIDs.count, max(1, min(3, nextIDs.count)))
        let revealed = Array(nextIDs.shuffled().prefix(revealCount))
        let origin = cardByID(selectedCardID)?.position ?? FrievePoint(x: 0.5, y: 0.5)
        for cardID in revealed {
            document.updateCard(cardID) { card in
                card.visible = true
                card.position = origin
            }
        }
        if let nextSelection = revealed.randomElement() {
            self.selectedCardID = nextSelection
            selectedCardIDs = [nextSelection]
        }
        browserAnimationCountdownMilliseconds = animationIntervalMilliseconds(base: 2000)
        markBrowserSurfaceContentDirty()
    }

    private func resetRandomMapDocument() {
        guard let backup = browserAnimationBackupDocument else { return }
        let startCard = randomAnimationCardSelection(limit: 1).first
        document = backup
        for card in document.cards {
            document.updateCard(card.id) { draft in
                draft.visible = card.id == startCard?.id
            }
        }
        selectedCardID = startCard?.id
        selectedCardIDs = startCard.map { [$0.id] } ?? []
        browserAnimationCountdownMilliseconds = animationIntervalMilliseconds(base: 2000)
        requestBrowserFit()
    }

    private func prepareRandomMotionAnimation(_ mode: BrowserAnimationMode) {
        guard let backup = browserAnimationBackupDocument else { return }
        document = backup
        for card in document.cards {
            document.updateCard(card.id) { draft in
                draft.visible = false
            }
        }
        selectedCardID = nil
        selectedCardIDs = []
        requestBrowserFit()
        browserAnimationCountdownMilliseconds = mode == .randomJump ? 3000 : 0
    }

    private func applyRandomMotionAnimationStep(jumping: Bool) {
        guard !animationPaused else { return }

        let activeLimit = min(max(animationVisibleCardCount, 1), browserAnimationActiveCardIDs.count)
        var occupied = Set(browserAnimationActiveCardIDs.compactMap { $0 })
        while occupied.count < activeLimit {
            let freshCard = randomAnimationCardSelection(limit: 1, excluding: occupied).first ?? animationVisibleSourceCards().randomElement()
            guard let freshCard else { break }
            occupied.insert(freshCard.id)
            spawnAnimatedCard(cardID: freshCard.id, jumping: jumping)
        }

        for card in document.cards {
            document.updateCard(card.id) { draft in
                draft.visible = false
            }
        }

        let speedScale = (jumping ? 0.3 : 0.5) / pow(2.0, -Double(animationSpeed - 30) / 25.0)
        for (index, cardID) in browserAnimationActiveCardIDs.enumerated() {
            guard let cardID, var velocity = browserAnimationVelocityByCardID[cardID] else { continue }
            guard let current = cardByID(cardID) else { continue }

            var nextPosition = current.position
            nextPosition.x += velocity.x * speedScale
            nextPosition.y += velocity.y * speedScale
            if jumping {
                velocity.y += speedScale * 0.01
            }

            if nextPosition.x < -1.0 || nextPosition.y < -1.0 || nextPosition.x > 2.0 || nextPosition.y > 2.0 {
                browserAnimationActiveCardIDs[index] = nil
                browserAnimationVelocityByCardID.removeValue(forKey: cardID)
                continue
            }

            browserAnimationVelocityByCardID[cardID] = velocity
            document.updateCard(cardID) { card in
                card.position = nextPosition
                card.visible = true
            }
        }

        markBrowserSurfaceContentDirty()
        markBrowserSurfacePresentationDirty()
    }

    private func spawnAnimatedCard(cardID: Int, jumping: Bool) {
        for index in browserAnimationActiveCardIDs.indices where browserAnimationActiveCardIDs[index] == nil {
            browserAnimationActiveCardIDs[index] = cardID
            if jumping {
                let frames = Double(Int.random(in: 160 ... 240))
                let startX = Double.random(in: -0.5 ... 1.5)
                document.updateCard(cardID) { card in
                    card.position = FrievePoint(x: startX, y: 2.0)
                    card.visible = true
                }
                browserAnimationVelocityByCardID[cardID] = FrievePoint(
                    x: Double.random(in: -3.0 ... 3.0) * 0.1 / frames,
                    y: -Double.random(in: 27.0 ... 42.0) / frames
                )
            } else {
                let direction = Int.random(in: 0 ..< 4)
                let frames = Double(Int.random(in: 160 ... 240))
                let start: FrievePoint
                let velocity: FrievePoint
                switch direction {
                case 0:
                    let startX = Double.random(in: -0.5 ... 1.5)
                    start = FrievePoint(x: startX, y: 2.0)
                    velocity = FrievePoint(x: Double.random(in: -1.0 ... 1.0) / frames, y: -3.0 / frames)
                case 1:
                    let startX = Double.random(in: -0.5 ... 1.5)
                    start = FrievePoint(x: startX, y: -1.0)
                    velocity = FrievePoint(x: Double.random(in: -1.0 ... 1.0) / frames, y: 3.0 / frames)
                case 2:
                    let startY = Double.random(in: -0.5 ... 1.5)
                    start = FrievePoint(x: 2.0, y: startY)
                    velocity = FrievePoint(x: -3.0 / frames, y: Double.random(in: -1.0 ... 1.0) / frames)
                default:
                    let startY = Double.random(in: -0.5 ... 1.5)
                    start = FrievePoint(x: -1.0, y: startY)
                    velocity = FrievePoint(x: 3.0 / frames, y: Double.random(in: -1.0 ... 1.0) / frames)
                }
                document.updateCard(cardID) { card in
                    card.position = start
                    card.visible = true
                }
                browserAnimationVelocityByCardID[cardID] = velocity
            }
            return
        }
    }

    private func prepareRandomTraceAnimation() {
        guard let backup = browserAnimationBackupDocument else { return }
        document = backup
        autoScroll = true
        autoZoom = true
        requestBrowserFit()

        let initialCardID = selectedCardID ?? animationVisibleSourceCards().randomElement()?.id
        selectedCardID = initialCardID
        selectedCardIDs = initialCardID.map { [$0] } ?? []
        browserAnimationTracePreviousCardID = nil
        browserAnimationCountdownMilliseconds = animationIntervalMilliseconds(base: 1000)
    }

    private func applyRandomTraceAnimationStep() {
        guard !animationPaused else { return }
        browserAnimationCountdownMilliseconds -= browserAnimationFrameInterval * 1000
        if browserAnimationCountdownMilliseconds > 0 {
            return
        }

        let visibleIDs = Set(document.cards.filter(\.visible).map(\.id))
        let currentCardID = selectedCardID
        let previousCardID = browserAnimationTracePreviousCardID
        let candidateIDs = document.links.compactMap { link -> Int? in
            if link.fromCardID == currentCardID, visibleIDs.contains(link.toCardID) {
                return link.toCardID == previousCardID ? nil : link.toCardID
            }
            if link.toCardID == currentCardID, visibleIDs.contains(link.fromCardID) {
                return link.fromCardID == previousCardID ? nil : link.fromCardID
            }
            return nil
        }

        let nextCardID = candidateIDs.randomElement() ?? animationVisibleSourceCards().randomElement()?.id
        browserAnimationTracePreviousCardID = currentCardID
        selectedCardID = nextCardID
        selectedCardIDs = nextCardID.map { [$0] } ?? []
        browserAnimationCountdownMilliseconds = animationIntervalMilliseconds(base: 1000)
    }
}
