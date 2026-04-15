import SwiftUI
import AppKit

private enum BrowserMediaPreviewKind {
    case image
    case video
}

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
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard
    let metadata: BrowserCardMetadata
    let detailLevel: BrowserCardDetailLevel
    let fillColor: Color
    let previewImage: NSImage?
    let videoPreviewImage: NSImage?
    let drawingPreviewImage: NSImage?

    var body: some View {
        let _ = (metadata, detailLevel, fillColor, previewImage, drawingPreviewImage)
        let isCentered = viewModel.settings.browserTextCentering
        let horizontalAlignment: HorizontalAlignment = isCentered ? .center : .leading
        let titleAlignment: TextAlignment = isCentered ? .center : .leading
        let padding = browserCardContentPadding(for: card)
        let previewSize = viewModel.browserMediaPreviewSize(for: card)
        let drawingSize = viewModel.browserDrawingPreviewSize(for: card)
        let hasImagePreview = viewModel.browserShowsImagePreview(for: card)
        let hasVideoPreview = viewModel.browserShowsVideoPreview(for: card)
        let hasDrawingPreview = viewModel.browserShowsDrawingPreview(for: card, hasDrawingPreview: metadata.hasDrawingPreview)
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : card.title
        let titleFont = Font(viewModel.browserCardTitleNSFont(for: card))
        let scoreBarLayout = viewModel.browserCardScoreBarLayout(for: card)

        ZStack(alignment: .topLeading) {
            VStack(alignment: horizontalAlignment, spacing: 8) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(titleAlignment)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)

                if hasImagePreview || hasVideoPreview || hasDrawingPreview {
                    HStack(alignment: .top, spacing: 8) {
                        if hasImagePreview {
                            BrowserMediaPreviewView(
                                viewModel: viewModel,
                                card: card,
                                kind: .image,
                                badgeText: "Image",
                                previewImage: previewImage
                            )
                            .frame(width: previewSize.width, height: previewSize.height)
                        }
                        if hasVideoPreview {
                            BrowserMediaPreviewView(
                                viewModel: viewModel,
                                card: card,
                                kind: .video,
                                badgeText: "Video",
                                previewImage: videoPreviewImage
                            )
                            .frame(width: previewSize.width, height: previewSize.height)
                        }
                        if hasDrawingPreview {
                            BrowserDrawingOverlay(
                                viewModel: viewModel,
                                card: card,
                                targetSize: drawingSize,
                                drawingPreviewImage: drawingPreviewImage
                            )
                            .frame(width: drawingSize.width, height: drawingSize.height)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                if let scoreBarLayout {
                    BrowserCardScoreBarView(layout: scoreBarLayout)
                        .frame(height: viewModel.browserCardScoreBarTrackHeight(for: card))
                        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
                }

                if !metadata.badges.isEmpty {
                    Text(metadata.badges.joined(separator: "  ·  "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(titleAlignment)
                        .lineLimit(viewModel.settings.browserTextWordWrap ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
                }
                Spacer(minLength: 0)
            }

            if card.isFixed {
                BrowserFixedCornerDotsOverlay()
            }

            if card.isFolded {
                BrowserFoldedMarkerOverlay()
            }
        }
        .padding(padding)
        .frame(width: metadata.canvasSize.width, height: metadata.canvasSize.height, alignment: .topLeading)
    }
}

private struct BrowserFixedCornerDotsOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let inset = max(min(geometry.size.width, geometry.size.height) * 0.045, 5)
            let dot = max(min(geometry.size.width, geometry.size.height) * 0.055, 4)

            ZStack {
                circle(size: dot)
                    .position(x: inset, y: inset)
                circle(size: dot)
                    .position(x: geometry.size.width - inset, y: inset)
                circle(size: dot)
                    .position(x: inset, y: geometry.size.height - inset)
                circle(size: dot)
                    .position(x: geometry.size.width - inset, y: geometry.size.height - inset)
            }
        }
        .allowsHitTesting(false)
    }

    private func circle(size: CGFloat) -> some View {
        Circle()
            .fill(Color.blue.opacity(0.95))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.blue.opacity(0.4), lineWidth: 1))
    }
}

private struct BrowserFoldedMarkerOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let size = max(min(geometry.size.width, geometry.size.height) * 0.12, 12)

            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.primary.opacity(0.7), lineWidth: 1)
                Rectangle()
                    .fill(Color.primary.opacity(0.82))
                    .frame(width: size * 0.48, height: 1.2)
                Rectangle()
                    .fill(Color.primary.opacity(0.82))
                    .frame(width: 1.2, height: size * 0.48)
            }
            .frame(width: size, height: size)
            .position(
                x: geometry.size.width - size * 0.9,
                y: geometry.size.height - size * 1.1
            )
        }
        .allowsHitTesting(false)
    }
}

private struct BrowserCardScoreBarView: View {
    let layout: BrowserCardScoreBarLayout

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let startX = width * layout.fillStartFraction
            let endX = width * layout.fillEndFraction
            let baselineX = width * layout.baselineFraction
            let fillWidth = max(endX - startX, 0)
            let fillColor = layout.isNegative ? Color.red.opacity(0.72) : Color.accentColor.opacity(0.88)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))

                if fillWidth > 0 {
                    Capsule()
                        .fill(fillColor)
                        .frame(width: fillWidth)
                        .offset(x: startX)
                }

                if layout.baselineFraction > 0 && layout.baselineFraction < 1 {
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 2, height: height)
                        .offset(x: baselineX - 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct BrowserTickerMarqueeView: View {
    let text: String
    let font: NSFont
    let tint: Color

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let textWidth = max(ceil(attrStr.size().width), 1)
            let travelDistance = textWidth + size.width
            let speed = max(font.pointSize * 0.85, 10)
            let elapsed = CGFloat(CACurrentMediaTime() * Double(speed))
            let offset = elapsed.truncatingRemainder(dividingBy: max(travelDistance, 1))
            let xPos = size.width - offset
            let lineHeight = font.ascender - font.descender + font.leading

            context.withCGContext { cgContext in
                cgContext.clip(to: CGRect(origin: .zero, size: size))
                cgContext.translateBy(x: 0, y: size.height)
                cgContext.scaleBy(x: 1, y: -1)
                let coloredAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(tint)
                ]
                NSAttributedString(string: text, attributes: coloredAttrs)
                    .draw(at: CGPoint(x: xPos, y: (size.height - lineHeight) / 2))
            }
        }
        .frame(height: ceil(font.ascender - font.descender + font.leading))
    }
}

private struct BrowserMediaPreviewView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard
    let kind: BrowserMediaPreviewKind
    let badgeText: String
    let previewImage: NSImage?

    var body: some View {
        Group {
            if kind == .image, let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if !badgeText.isEmpty {
                            Label(badgeText, systemImage: "photo")
                                .font(.caption2)
                                .padding(6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(6)
                        }
                    }
            } else if kind == .image, let image = viewModel.cachedPreviewImage(for: card) {
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
            } else if kind == .video, let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Label(badgeText, systemImage: "film")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
            } else if kind == .video, let image = viewModel.cachedVideoPreviewImage(for: card) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Label(badgeText, systemImage: "film")
                            .font(.caption2)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(6)
                    }
            } else if kind == .video {
                mediaPlaceholder(
                    systemImage: "play.rectangle.fill",
                    title: badgeText,
                    badgeSystemImage: "film"
                )
            } else if kind == .image {
                mediaPlaceholder(
                    systemImage: "photo",
                    title: badgeText,
                    badgeSystemImage: "photo"
                )
            } else {
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.15)))
    }

    @ViewBuilder
    private func mediaPlaceholder(systemImage: String, title: String, badgeSystemImage: String) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                Text(title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(8)
            .overlay(alignment: .bottomTrailing) {
                if !badgeText.isEmpty {
                    Label(badgeText, systemImage: badgeSystemImage)
                        .font(.caption2)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
            }
        }
    }
}

private struct BrowserDrawingOverlay: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let card: FrieveCard
    let targetSize: CGSize
    let drawingPreviewImage: NSImage?

    var body: some View {
        Group {
            if let drawingPreviewImage {
                Image(nsImage: drawingPreviewImage)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else if let image = viewModel.cachedDrawingPreviewImage(for: card, targetSize: targetSize) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                EmptyView()
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .allowsHitTesting(false)
    }
}
