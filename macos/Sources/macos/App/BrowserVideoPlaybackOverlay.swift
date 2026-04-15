import SwiftUI
import AppKit
import AVFoundation

struct BrowserVideoPlaybackEntry: Identifiable, Equatable {
    let id: Int
    let url: URL
    let rect: CGRect
    let visibleRects: [CGRect]
    let isSelected: Bool
}

struct BrowserVideoPlaybackOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let canvasSize: CGSize

    var body: some View {
        let _ = viewModel.browserSurfaceViewportRevision
        let entries = playbackEntries()
        ZStack(alignment: .topLeading) {
            ForEach(entries) { entry in
                BrowserLoopingVideoView(
                    url: entry.url,
                    isSelected: entry.isSelected,
                    visibleRects: entry.visibleRects
                )
                .frame(width: entry.rect.width, height: entry.rect.height)
                .position(x: entry.rect.midX, y: entry.rect.midY)
                .allowsHitTesting(false)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func playbackEntries() -> [BrowserVideoPlaybackEntry] {
        guard viewModel.settings.browserVideoVisible else { return [] }
        let cards = viewModel.visibleCardsBackToFront()
        var entries: [BrowserVideoPlaybackEntry] = []
        for (index, card) in cards.enumerated() {
            guard let videoRect = viewModel.browserVideoPreviewScreenRect(for: card, in: canvasSize),
                  let url = viewModel.mediaURL(for: card.videoPath) else { continue }
            let occluders = cards.suffix(from: index + 1).map { viewModel.cardFrame(for: $0, in: canvasSize) }
            let visibleCanvasRects = browserTickerVisibleRects(in: videoRect, occludingRects: occluders)
            guard !visibleCanvasRects.isEmpty else { continue }
            let localRects = visibleCanvasRects.map {
                CGRect(
                    x: $0.minX - videoRect.minX,
                    y: $0.minY - videoRect.minY,
                    width: $0.width,
                    height: $0.height
                )
            }
            entries.append(BrowserVideoPlaybackEntry(
                id: card.id,
                url: url,
                rect: videoRect,
                visibleRects: localRects,
                isSelected: viewModel.selectedCardIDs.contains(card.id)
            ))
        }
        return entries
    }
}

struct BrowserLoopingVideoView: NSViewRepresentable {
    let url: URL
    let isSelected: Bool
    let visibleRects: [CGRect]

    func makeNSView(context: Context) -> LoopingVideoNSView {
        LoopingVideoNSView()
    }

    func updateNSView(_ nsView: LoopingVideoNSView, context: Context) {
        nsView.configure(url: url, selected: isSelected, visibleRects: visibleRects)
    }
}

final class LoopingVideoNSView: NSView {
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private let playerLayer = AVPlayerLayer()
    private let maskLayer = CALayer()
    private var currentSelected = false
    private var currentVisibleRects: [CGRect] = []
    private var fadeTimer: Timer?
    private let fadeDuration: TimeInterval = 0.3
    private let cornerRadius: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let viewLayer = layer ?? CALayer()
        viewLayer.masksToBounds = true
        playerLayer.videoGravity = .resizeAspect
        viewLayer.addSublayer(playerLayer)
        playerLayer.mask = maskLayer
        if layer == nil {
            layer = viewLayer
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        maskLayer.frame = bounds
        rebuildMaskImage()
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            teardownPlayer()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rebuildMaskImage()
            CATransaction.commit()
        }
    }

    func configure(url: URL, selected: Bool, visibleRects: [CGRect]) {
        if currentURL != url {
            currentURL = url
            rebuildPlayer(with: url)
        }
        if currentSelected != selected {
            currentSelected = selected
            startVolumeFade(toSelected: selected)
        }
        if currentVisibleRects != visibleRects {
            currentVisibleRects = visibleRects
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rebuildMaskImage()
            CATransaction.commit()
        }
    }

    private func rebuildMaskImage() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = Int((bounds.width * scale).rounded())
        let pixelHeight = Int((bounds.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return }
        guard let ctx = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        let rounded = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(rounded)
        ctx.clip()
        let rectsToFill = currentVisibleRects.isEmpty ? [bounds] : currentVisibleRects
        for rect in rectsToFill {
            ctx.fill(rect)
        }
        guard let cgImage = ctx.makeImage() else { return }
        maskLayer.contents = cgImage
        maskLayer.contentsScale = scale
        maskLayer.frame = bounds
    }

    private func rebuildPlayer(with url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.volume = currentSelected ? 1.0 : 0.0
        player.actionAtItemEnd = .advance
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        playerLayer.player = player
        player.play()
    }

    private func startVolumeFade(toSelected selected: Bool) {
        fadeTimer?.invalidate()
        guard let player = queuePlayer else { return }
        let target: Float = selected ? 1.0 : 0.0
        let start = player.volume
        let startTime = CACurrentMediaTime()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self, let player = self.queuePlayer else {
                timer.invalidate()
                return
            }
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(max(elapsed / self.fadeDuration, 0), 1)
            player.volume = start + (target - start) * Float(progress)
            if progress >= 1 {
                timer.invalidate()
                self.fadeTimer = nil
            }
        }
    }

    private func teardownPlayer() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        queuePlayer?.pause()
        queuePlayer = nil
        looper = nil
        playerLayer.player = nil
        currentURL = nil
    }
}
