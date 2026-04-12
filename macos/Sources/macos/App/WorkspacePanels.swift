import SwiftUI
import AppKit

let drawingToolOptions = ["Cursor", "FreeHand", "Line", "Rect", "Circle"]

struct EditorWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Card title", text: viewModel.bindingForSelectedTitle())
                    .textFieldStyle(.roundedBorder)
                Button("Web Search") { viewModel.searchWebForSelection() }
            }
            TextEditor(text: viewModel.bindingForSelectedBody())
                .font(.body.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 8) {
                Text("Linked Cards")
                    .font(.headline)
                if viewModel.editorRelatedCardLines().isEmpty {
                    Text("リンクしているカードはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(viewModel.editorRelatedCardLines()) { line in
                                Text(line.text)
                                    .font(.body.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 92, maxHeight: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                }
            }
            if !viewModel.lastGPTPrompt.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last GPT Prompt")
                        .font(.headline)
                    ScrollView {
                        Text(viewModel.lastGPTPrompt)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .underPageBackgroundColor)))
                }
            }
        }
        .padding(16)
    }
}

struct DrawingWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Tool", selection: $viewModel.selectedDrawingTool) {
                    ForEach(drawingToolOptions, id: \.self) { tool in
                        Text(tool).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                Text("Color")
                    .foregroundStyle(.secondary)
                Button("Auto") {
                    viewModel.setSelectedDrawingStrokeColor(nil)
                }
                .buttonStyle(.bordered)
                ColorPicker("", selection: viewModel.bindingForSelectedDrawingColor(), supportsOpacity: false)
                    .labelsHidden()
            }
            TextEditor(text: viewModel.bindingForSelectedDrawing())
                .font(.body.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
        }
        .padding(16)
    }
}

struct StatisticsWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    private let labelColumnWidth: CGFloat = 220

    var body: some View {
        let buckets = viewModel.statisticsBuckets
        let maxCount = max(buckets.map(\.count).max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Key")
                Menu(viewModel.statisticsKey.title) {
                    Button("Label") { viewModel.statisticsKey = .label }
                    Menu("Number of Link") {
                        Button("Total") { viewModel.statisticsKey = .totalLinks }
                        Button("Source") { viewModel.statisticsKey = .sourceLinks }
                        Button("Destination") { viewModel.statisticsKey = .destinationLinks }
                    }
                    Menu("Created Date") {
                        Button("Year") { viewModel.statisticsKey = .createdYear }
                        Button("Month") { viewModel.statisticsKey = .createdMonth }
                        Button("Day") { viewModel.statisticsKey = .createdDay }
                        Button("Week") { viewModel.statisticsKey = .createdWeekday }
                        Button("Hour") { viewModel.statisticsKey = .createdHour }
                    }
                    Menu("Edited Date") {
                        Button("Year") { viewModel.statisticsKey = .editedYear }
                        Button("Month") { viewModel.statisticsKey = .editedMonth }
                        Button("Day") { viewModel.statisticsKey = .editedDay }
                        Button("Week") { viewModel.statisticsKey = .editedWeekday }
                        Button("Hour") { viewModel.statisticsKey = .editedHour }
                    }
                    Menu("Viewed Date") {
                        Button("Year") { viewModel.statisticsKey = .viewedYear }
                        Button("Month") { viewModel.statisticsKey = .viewedMonth }
                        Button("Day") { viewModel.statisticsKey = .viewedDay }
                        Button("Week") { viewModel.statisticsKey = .viewedWeekday }
                        Button("Hour") { viewModel.statisticsKey = .viewedHour }
                    }
                }
                .fixedSize()
                Toggle("Sort", isOn: $viewModel.statisticsSortByCount)
                    .toggleStyle(.button)

                Spacer()

                if let selectedBucket = viewModel.selectedStatisticsBucket {
                    Text("\(selectedBucket.name): \(selectedBucket.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Text("Item")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: labelColumnWidth, alignment: .leading)
                StatisticsScaleHeaderView(maxCount: maxCount)
            }
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        StatisticsBarRowView(
                            bucket: bucket,
                            isSelected: bucket.id == viewModel.selectedStatisticsBucketID,
                            maxCount: maxCount,
                            rowIndex: index,
                            labelColumnWidth: labelColumnWidth
                        )
                        .onTapGesture {
                            viewModel.selectStatisticsBucket(bucket)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.18))
            )

            if let selectedBucket = viewModel.selectedStatisticsBucket {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selectedBucket.name)
                            .font(.headline)
                        Text("\(selectedBucket.count) cards")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Table(viewModel.statisticsCards(for: selectedBucket)) {
                        TableColumn("Title", value: \.title)
                        TableColumn("Labels") { card in
                            Text(viewModel.cardLabelNames(for: card).joined(separator: ", "))
                                .lineLimit(1)
                        }
                        TableColumn("Links") { card in
                            Text("\(viewModel.linksForCard(card.id).count)")
                                .monospacedDigit()
                        }
                        TableColumn("Updated", value: \.updated)
                        TableColumn("") { card in
                            Button("Focus Browser") {
                                viewModel.focusStatisticsCardInBrowser(card.id)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .frame(minHeight: 220)
                }
            } else {
                ContentUnavailableView(
                    "Select a bar",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Cards for the selected statistic bucket will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(16)
    }
}

private struct StatisticsScaleHeaderView: View {
    let maxCount: Int

    var body: some View {
        GeometryReader { geometry in
            let steps = max(4, min(maxCount, 8))
            ZStack(alignment: .topLeading) {
                ForEach(0 ... steps, id: \.self) { step in
                    let fraction = CGFloat(step) / CGFloat(steps)
                    let scaledValue = Int((Double(maxCount) * Double(step)) / Double(steps))
                    VStack(spacing: 4) {
                        Text("\(scaledValue)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 1)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .position(x: geometry.size.width * fraction, y: geometry.size.height / 2)
                }
            }
        }
        .frame(height: 26)
    }
}

private struct StatisticsBarRowView: View {
    let bucket: DocumentStatisticBucket
    let isSelected: Bool
    let maxCount: Int
    let rowIndex: Int
    let labelColumnWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Text(bucket.name)
                .lineLimit(1)
                .frame(width: labelColumnWidth, alignment: .leading)

            GeometryReader { geometry in
                let barWidth = geometry.size.width * CGFloat(bucket.count) / CGFloat(max(maxCount, 1))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(barColor)
                        .frame(width: barWidth)
                    if bucket.count > 0 {
                        Text("\(bucket.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: barWidth > 56 ? .trailing : .leading)
                            .offset(x: labelOffset(for: geometry.size.width, barWidth: barWidth))
                    }
                }
            }
            .frame(height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        if rowIndex.isMultiple(of: 2) {
            return Color.clear
        }
        return Color.secondary.opacity(0.05)
    }

    private var barColor: Color {
        if let color = bucket.color {
            return Color(frieveRGB: color)
        }
        let hue = rowCountHue
        return Color(hue: hue, saturation: 0.86, brightness: 0.95)
    }

    private var rowCountHue: Double {
        guard maxCount > 0 else { return 0.58 }
        return Double((rowIndex * 37) % 100) / 100.0
    }

    private func labelOffset(for totalWidth: CGFloat, barWidth: CGFloat) -> CGFloat {
        if barWidth > 56 {
            return 0
        }
        let preferred = min(barWidth + 8, max(totalWidth - 42, 0))
        return preferred
    }
}

struct InspectorPaneView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inspector")
                    .font(.headline)
                if let card = viewModel.selectedCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .foregroundStyle(.secondary)
                        TextField("Card title", text: viewModel.bindingForSelectedTitle())
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Labels")
                            .foregroundStyle(.secondary)
                        TextField("Comma-separated labels", text: viewModel.bindingForSelectedLabels())
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Created", value: card.created)
                    LabeledContent("Updated", value: card.updated)

                    Picker("Shape", selection: viewModel.bindingForSelectedShape()) {
                        Text("Rect").tag(0)
                        Text("Capsule").tag(1)
                        Text("Round").tag(2)
                        Text("Diamond").tag(3)
                        Text("Hexagon").tag(4)
                        Text("Note").tag(5)
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 4) {
                        let sizeStep = browserCardSizeStep(forStoredSize: card.size)
                        HStack {
                            Text("Card Size")
                            Spacer()
                            Text("\(sizeStep)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: viewModel.bindingForSelectedSize(), in: -8 ... 8, step: 1)
                    }

                    TextField("Image path", text: viewModel.bindingForSelectedImagePath())
                        .textFieldStyle(.roundedBorder)
                    TextField("Video path", text: viewModel.bindingForSelectedVideoPath())
                        .textFieldStyle(.roundedBorder)

                    Toggle("Top Card", isOn: .constant(card.isTop))
                        .disabled(true)
                    Toggle("Fixed", isOn: viewModel.bindingForSelectedFixed())
                    Toggle("Folded", isOn: viewModel.bindingForSelectedFolded())

                    Button("Focus Browser") {
                        viewModel.selectedTab = .browser
                        viewModel.focusBrowser(on: card.id)
                    }
                } else {
                    Text("No card selected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .scrollContentBackground(.hidden)
    }
}

struct StatusBarView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(viewModel.statusMessage)
            Spacer()
            Text("Cards: \(viewModel.document.cardCount)")
            Text("Links: \(viewModel.document.linkCount)")
            Text("Focus: \(viewModel.selectedCard?.title ?? "None")")
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
