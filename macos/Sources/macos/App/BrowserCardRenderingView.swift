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
        let labelLine = detailLevel == .thumbnail ? "" : metadata.labelLine
        let detailSummary = detailLevel == .thumbnail ? "" : metadata.detailSummary
        let badges = detailLevel == .full ? metadata.badges : Array(metadata.badges.prefix(2))
        let summaryLineLimit = detailLevel == .compact ? 2 : 3

        VStack(alignment: .leading, spacing: detailLevel == .thumbnail ? 6 : 8) {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: detailLevel == .thumbnail ? 58 : 72)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if detailLevel != .thumbnail {
                            Label(metadata.mediaBadgeText, systemImage: "photo")
                                .font(.caption2)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: card.shapeSymbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.title)
                            .font(detailLevel == .thumbnail ? .subheadline.weight(.semibold) : .headline)
                            .lineLimit(1)
                    }

                    if detailLevel != .thumbnail {
                        if card.isFolded {
                            Label("Folded", systemImage: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(metadata.summaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(summaryLineLimit)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    if card.isFixed && detailLevel != .thumbnail {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("#\(card.id)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if !labelLine.isEmpty {
                Text(labelLine)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }

            if !detailSummary.isEmpty {
                Text(detailSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.35)))
                    }
                }
            }

            HStack(spacing: 10) {
                Label("\(metadata.linkCount)", systemImage: "point.3.connected.trianglepath.dotted")
                Label(card.score.formatted(.number.precision(.fractionLength(1))), systemImage: "chart.bar")
                if detailLevel != .thumbnail {
                    Label(card.shapeName, systemImage: card.shapeSymbolName)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let drawingPreviewImage, detailLevel == .full {
                HStack {
                    Spacer(minLength: 0)
                    Image(nsImage: drawingPreviewImage)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .frame(width: 96, height: 72)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(detailLevel == .thumbnail ? 10 : 12)
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
