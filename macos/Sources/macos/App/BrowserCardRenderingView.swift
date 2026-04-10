import SwiftUI
import AppKit

struct BrowserCardShape: Shape {
    let shapeIndex: Int

    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect, shapeIndex: shapeIndex))
    }

    static func cgPath(in rect: CGRect, shapeIndex: Int) -> CGPath {
        switch ((shapeIndex % 6) + 6) % 6 {
        case 0:
            return CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        case 1:
            return CGPath(ellipseIn: rect, transform: nil)
        case 2:
            return CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        case 3:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case 4:
            let inset = rect.width * 0.14
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        default:
            return CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        }
    }
}

struct BrowserCardRasterContentView: View {
    let card: FrieveCard
    let metadata: BrowserCardMetadata
    let detailLevel: BrowserCardDetailLevel
    let fillColor: Color
    let previewImage: NSImage?
    let drawingPreviewImage: NSImage?

    var body: some View {
        Text(card.title)
            .font(.system(size: browserCardTitlePointSize(for: card), weight: .semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(browserCardContentPadding(for: card))
            .frame(width: metadata.canvasSize.width, height: metadata.canvasSize.height, alignment: .topLeading)
            .background(BrowserCardShape(shapeIndex: card.shape).fill(fillColor))
            .clipShape(BrowserCardShape(shapeIndex: card.shape))
    }
}

private struct BrowserMediaPreviewView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard
    let badgeText: String

    var body: some View {
        Group {
            if let image = viewModel.cachedPreviewImage(for: card) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Label(badgeText, systemImage: "photo")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
            } else if let url = viewModel.mediaURL(for: card.videoPath) {
                ZStack {
                    LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 6) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 26))
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.15)))
    }
}

private struct BrowserDrawingOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard

    var body: some View {
        Group {
            if let image = viewModel.cachedDrawingPreviewImage(for: card, targetSize: CGSize(width: 96, height: 72)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                EmptyView()
            }
        }
        .frame(width: 96, height: 72)
        .allowsHitTesting(false)
    }
}
