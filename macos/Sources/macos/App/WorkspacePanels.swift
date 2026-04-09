import SwiftUI

struct EditorWorkspaceView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Card title", text: viewModel.bindingForSelectedTitle())
                    .textFieldStyle(.roundedBorder)
                Button("Web Search") { viewModel.searchWebForSelection() }
                Button("Read Aloud") { viewModel.readSelectedCardAloud() }
                Button("Stop") { viewModel.stopReadAloud() }
            }
            TextEditor(text: viewModel.bindingForSelectedBody())
                .font(.body.monospaced())
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
            HStack {
                Text("Related links: \(viewModel.selectedCardLinks.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy FIP2") { viewModel.exportFIP2ToClipboard() }
                Button("Copy GPT Prompt") { viewModel.copyGPTPromptToClipboard() }
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
                    Text("Cursor").tag("Cursor")
                    Text("FreeHand").tag("FreeHand")
                    Text("Line").tag("Line")
                    Text("Rect").tag("Rect")
                    Text("Circle").tag("Circle")
                    Text("Text").tag("Text")
                }
                .pickerStyle(.segmented)
                Spacer()
                Text("Encoded drawing payload")
                    .foregroundStyle(.secondary)
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

    var body: some View {
        Table(viewModel.statisticsRows) {
            TableColumn("Title", value: \.title)
            TableColumn("Body") { row in
                Text("\(row.bodyLength)")
            }
            TableColumn("Links") { row in
                Text("\(row.linkCount)")
            }
            TableColumn("Labels") { row in
                Text(row.labelNames.joined(separator: ", "))
            }
            TableColumn("Size") { row in
                Text("\(row.size)")
            }
            TableColumn("Score") { row in
                Text(row.score.formatted(.number.precision(.fractionLength(2))))
            }
        }
        .padding(16)
    }
}

struct InspectorPaneView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)
            if let card = viewModel.selectedCard {
                LabeledContent("Title", value: card.title)
                LabeledContent("Card ID", value: String(card.id))
                LabeledContent("Labels", value: viewModel.cardLabelNames(for: card).joined(separator: ", "))
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
                    HStack {
                        Text("Card Size")
                        Spacer()
                        Text("\(card.size)")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: viewModel.bindingForSelectedSize(), in: 80 ... 320, step: 10)
                }

                TextField("Image path", text: viewModel.bindingForSelectedImagePath())
                    .textFieldStyle(.roundedBorder)
                TextField("Video path", text: viewModel.bindingForSelectedVideoPath())
                    .textFieldStyle(.roundedBorder)

                Toggle("Top Card", isOn: .constant(card.isTop))
                    .disabled(true)
                Toggle("Fixed", isOn: viewModel.bindingForSelectedFixed())
                Toggle("Folded", isOn: viewModel.bindingForSelectedFolded())

                HStack {
                    Button("Focus Browser") {
                        viewModel.selectedTab = .browser
                        viewModel.focusBrowser(on: card.id)
                    }
                    Button("Inline Edit") {
                        viewModel.selectedTab = .browser
                        viewModel.handleCardDoubleClick(card.id)
                    }
                }
            } else {
                Text("No card selected")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Automation")
                .font(.headline)
            Toggle("Auto Save", isOn: $viewModel.settings.autoSaveDefault)
            Toggle("Auto Reload", isOn: $viewModel.settings.autoReloadDefault)
            HStack {
                Text("Web Search")
                Spacer()
                Picker("Web Search", selection: $viewModel.settings.preferredWebSearchName) {
                    ForEach(viewModel.settings.webSearchProviders) { provider in
                        Text(provider.name).tag(provider.name)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }
            HStack {
                Text("Read Speed")
                Spacer()
                Text("\(Int(viewModel.settings.readAloudRate))")
                    .foregroundStyle(.secondary)
            }
            Slider(value: $viewModel.settings.readAloudRate, in: 100 ... 320, step: 5)
            TextField("GPT Model", text: $viewModel.settings.gptModel)
                .textFieldStyle(.roundedBorder)

            Divider()

            Text("Global Search")
                .font(.headline)
            List(viewModel.globalSearchResults) { card in
                Button(card.title) {
                    viewModel.selectCard(card.id)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
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
