import SwiftUI

private let batchShapeOptions = ["Rounded Rectangle", "Ellipse", "Capsule", "Diamond", "Hexagon", "Soft Rectangle"]
private let batchLinkShapeOptions = ["Straight", "Curve", "Right Angle", "Double Curve", "Arc", "Zigzag"]

struct FrieveEditorCommands: Commands {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { viewModel.undoLastDocumentChange() }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!viewModel.canUndoLastDocumentChange)
            Button("Redo") { viewModel.redoDocumentChange() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!viewModel.canRedoDocumentChange)
        }

        CommandGroup(replacing: .newItem) {
            Button("New") { viewModel.newDocument() }
                .keyboardShortcut("n", modifiers: [.command])
            Button("Open…") { viewModel.openDocument() }
                .keyboardShortcut("o", modifiers: [.command])
            Menu("Open Recent") {
                ForEach(viewModel.recentFiles, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        viewModel.openDocument(url)
                    }
                }
                if !viewModel.recentFiles.isEmpty {
                    Divider()
                    Button("Clear Menu") {
                        viewModel.clearRecentFiles()
                    }
                }
            }
            Divider()
            Button("Save") { viewModel.saveDocument() }
                .keyboardShortcut("s", modifiers: [.command])
            Button("Save As…") { viewModel.saveDocumentAs() }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            Divider()
            Menu("Import") {
                Button("Txt File(s)…") { viewModel.importTextFiles() }
                Button("Hierarchical Text File…") { viewModel.importHierarchicalTextFiles() }
                Button("Hierarchical Text File 2…") { viewModel.importHierarchicalTextFilesWithBodies() }
                Button("Txt Files in a Folder…") { viewModel.importTextFilesInFolder() }
            }
            Menu("Export") {
                Button("Text File (Card Title)…") { viewModel.exportCardTitles() }
                Button("Text File (Text)…") { viewModel.exportCardBodies() }
                Button("Text Files…") { viewModel.exportCardBodiesPerFile() }
                Button("Hierarchical Text File…") { viewModel.exportHierarchicalText() }
                Button("HTML Files…") { viewModel.exportHTMLFiles() }
                Divider()
                Button("BMP File…") { viewModel.exportBrowserBMP() }
                Button("JPEG File…") { viewModel.exportBrowserJPEG() }
                Divider()
                Button("Clipboard (Card Title)") { viewModel.copyCardTitlesToClipboard() }
                Button("Clipboard (Body)") { viewModel.copyCardBodiesToClipboard() }
                Button("Clipboard (BMP)") { viewModel.copyBrowserImageToClipboard() }
            }
        }

        CommandGroup(after: .undoRedo) {
            Divider()
            Button("Find…") { viewModel.cardFilterFocusTrigger = true }
                .keyboardShortcut("f", modifiers: [.command])
            Divider()
            Menu("GPT") {
                Button("Copy GPT Prompt") { viewModel.copyGPTPromptToClipboard() }
            }
            .disabled(viewModel.selectedCardID == nil)
            Button("Edit Card Labels…") { viewModel.showCardLabelEditor = true }
            Button("Edit Link Labels…") { viewModel.showLinkLabelEditor = true }
            Divider()
            Menu("Batch Conversion") {
                Menu("All Cards Shape") {
                    ForEach(Array(batchShapeOptions.enumerated()), id: \.offset) { index, name in
                        Button(name) { viewModel.batchChangeAllCardsShape(to: index) }
                    }
                }
                Menu("All Links Shape") {
                    ForEach(Array(batchLinkShapeOptions.enumerated()), id: \.offset) { index, name in
                        Button(name) { viewModel.batchChangeAllLinksShape(to: index) }
                    }
                }
                Button("Reverse All Links Direction") { viewModel.batchReverseAllLinksDirection() }
            }
        }

        CommandMenu("Insert") {
            Button("New Root Card") { viewModel.addRootCard() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("New Child Card") { viewModel.addChildCard() }
                .keyboardShortcut(.return, modifiers: [.shift])
            Button("New Sibling Card") { viewModel.addSiblingCard() }
                .keyboardShortcut(.return, modifiers: [.command])
            Divider()
            Button("New Ext Link…") { viewModel.insertExtLink() }
            Menu("New Label for Selected Cards") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.assignCardLabelToSelection(labelID: label.id) }
                }
            }
            .disabled(viewModel.selectedCardIDs.isEmpty)
            Divider()
            Button("Link to Root") { viewModel.addLinkBetweenSelectionAndRoot() }
            Menu("Link to All Cards with Label") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.linkSelectionToAllCardsWithLabel(labelID: label.id) }
                }
            }
            .disabled(viewModel.selectedCardID == nil)
            Menu("Add Label to All Destination Cards") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.addLabelToAllDestinationCards(labelID: label.id) }
                }
            }
            .disabled(viewModel.selectedCardID == nil)
            Divider()
            Button("Delete Selected Card") { viewModel.deleteSelectedCard() }
                .keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandMenu("Layout") {
            Button("Arrange") { viewModel.arrangeCards() }
            Button("Shuffle") { viewModel.shuffleLayout() }
            Toggle("Show Overview", isOn: $viewModel.showOverview)
            Toggle("Show Link Labels", isOn: $viewModel.linkLabelsVisible)
            Toggle("Show Label Rectangles", isOn: Binding(
                get: { viewModel.labelRectanglesVisible },
                set: { viewModel.setBrowserLabelRectanglesVisible($0) }
            ))
            Toggle("Show File List", isOn: $viewModel.showFileList)
            Toggle("Show Card List", isOn: $viewModel.showCardList)
            Toggle("Show Inspector", isOn: $viewModel.showInspector)
        }

        CommandMenu("Animation") {
            Button("Random Flash") { viewModel.startBrowserAnimation(.randomFlash) }
            Button("Random Map") { viewModel.startBrowserAnimation(.randomMap) }
            Button("Random Scroll") { viewModel.startBrowserAnimation(.randomScroll) }
            Button("Random Jump") { viewModel.startBrowserAnimation(.randomJump) }
            Button("Random Trace") { viewModel.startBrowserAnimation(.randomTrace) }
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
