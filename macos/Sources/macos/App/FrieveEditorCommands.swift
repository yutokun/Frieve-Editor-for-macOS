import SwiftUI

struct FrieveEditorCommands: Commands {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { viewModel.newDocument() }
                .keyboardShortcut("n", modifiers: [.command])
            Button("Open…") { viewModel.openDocument() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Save") { viewModel.saveDocument() }
                .keyboardShortcut("s", modifiers: [.command])
            Button("Save As…") { viewModel.saveDocumentAs() }
                .keyboardShortcut("S", modifiers: [.command, .shift])
        }

        CommandMenu("Cards") {
            Button("New Root Card") { viewModel.addRootCard() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("New Child Card") { viewModel.addChildCard() }
                .keyboardShortcut(.return, modifiers: [.command])
            Button("New Sibling Card") { viewModel.addSiblingCard() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Divider()
            Button("Link to Root") { viewModel.addLinkBetweenSelectionAndRoot() }
            Button("Delete Selected Card") { viewModel.deleteSelectedCard() }
                .keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandMenu("Layout") {
            Button("Arrange") { viewModel.arrangeCards() }
            Button("Shuffle") { viewModel.shuffleLayout() }
            Toggle("Show Overview", isOn: $viewModel.showOverview)
            Toggle("Show Link Labels", isOn: $viewModel.linkLabelsVisible)
            Toggle("Show File List", isOn: $viewModel.showFileList)
            Toggle("Show Card List", isOn: $viewModel.showCardList)
            Toggle("Show Inspector", isOn: $viewModel.showInspector)
        }

        CommandMenu("Export") {
            Button("Export Card Titles") { viewModel.exportCardTitles() }
            Button("Export Card Bodies") { viewModel.exportCardBodies() }
            Button("Export Hierarchical Text") { viewModel.exportHierarchicalText() }
            Button("Export HTML") { viewModel.exportHTMLDocument() }
            Divider()
            Button("Copy FIP2 to Clipboard") { viewModel.exportFIP2ToClipboard() }
            Button("Copy GPT Prompt") { viewModel.copyGPTPromptToClipboard() }
        }

        CommandMenu("Services") {
            Button("Web Search Selection") { viewModel.searchWebForSelection() }
            Button("Read Selected Card Aloud") { viewModel.readSelectedCardAloud() }
            Button("Stop Reading") { viewModel.stopReadAloud() }
        }

        CommandGroup(after: .help) {
            Button("Frieve Editor Website") { viewModel.browseHelp() }
            Button("Check Latest Release") { viewModel.checkLatestRelease() }
        }
    }
}
