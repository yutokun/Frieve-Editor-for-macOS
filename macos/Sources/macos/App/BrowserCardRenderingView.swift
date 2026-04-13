import SwiftUI
import AppKit

struct BrowserCardShape: Shape {
    let shapeIndex: Int

    func path(in rect: CGRect) -> Path {
        Path(Self.cgPath(in: rect, shapeIndex: shapeIndex))
    }

    static func cgPath(in rect: CGRect, shapeIndex: Int) -> CGPath {
        let normalizedShapeIndex = ((shapeIndex % frieveCardShapeOptions.count) + frieveCardShapeOptions.count) % frieveCardShapeOptions.count
        switch normalizedShapeIndex {
        case 0:
            return CGMutablePath()
        case 1:
            return CGPath(rect: rect, transform: nil)
        case 2:
            return CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        case 3:
            return CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        case 4:
            return CGPath(ellipseIn: rect, transform: nil)
        case 5:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case 6:
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
        case 7:
            let inset = rect.height / 4
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        case 8:
            let inset = rect.height / 4
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.closeSubpath()
            return path
        case 9:
            let size = min(rect.width, rect.height) * 0.28
            let centered = CGRect(x: rect.midX - size, y: rect.midY - size, width: size * 2, height: size * 2)
            return CGPath(rect: centered, transform: nil)
        case 10:
            let size = min(rect.width, rect.height) * 0.28
            let centered = CGRect(x: rect.midX - size, y: rect.midY - size, width: size * 2, height: size * 2)
            return CGPath(ellipseIn: centered, transform: nil)
        case 11:
            let size = min(rect.width, rect.height) * 0.32
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.midY - size))
            path.addLine(to: CGPoint(x: rect.midX + size * 0.866, y: rect.midY + size * 0.5))
            path.addLine(to: CGPoint(x: rect.midX - size * 0.866, y: rect.midY + size * 0.5))
            path.closeSubpath()
            return path
        case 12:
            let size = min(rect.width, rect.height) * 0.32
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.midY + size))
            path.addLine(to: CGPoint(x: rect.midX + size * 0.866, y: rect.midY - size * 0.5))
            path.addLine(to: CGPoint(x: rect.midX - size * 0.866, y: rect.midY - size * 0.5))
            path.closeSubpath()
            return path
        case 13:
            let size = min(rect.width, rect.height) * 0.32
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.midY - size))
            path.addLine(to: CGPoint(x: rect.midX + size, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + size))
            path.addLine(to: CGPoint(x: rect.midX - size, y: rect.midY))
            path.closeSubpath()
            return path
        case 14:
            let size = min(rect.width, rect.height) * 0.32
            let path = CGMutablePath()
            for step in 0..<6 {
                let angle = (.pi / 6) + (.pi / 3 * Double(step))
                let point = CGPoint(
                    x: rect.midX + CGFloat(sin(angle)) * size,
                    y: rect.midY - CGFloat(cos(angle)) * size
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            return path
        default:
            let outerRadius = min(rect.width, rect.height) * 0.34
            let innerRadius = outerRadius * 0.45
            let path = CGMutablePath()
            for step in 0..<10 {
                let radius = step.isMultiple(of: 2) ? outerRadius : innerRadius
                let angle = (-.pi / 2) + (.pi / 5 * Double(step))
                let point = CGPoint(
                    x: rect.midX + CGFloat(cos(angle)) * radius,
                    y: rect.midY + CGFloat(sin(angle)) * radius
                )
                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            return path
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
        let _ = (metadata, detailLevel, fillColor, previewImage, drawingPreviewImage)
        Text(card.title)
            .font(.system(size: browserCardTitlePointSize(for: card), weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(browserCardContentPadding(for: card))
            .frame(width: metadata.canvasSize.width, height: metadata.canvasSize.height, alignment: .topLeading)
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
