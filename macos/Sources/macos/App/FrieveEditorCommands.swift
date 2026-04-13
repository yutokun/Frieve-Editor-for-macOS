import SwiftUI

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
                Button("Text File(s)…") { viewModel.importTextFiles() }
                Button("Hierarchical Text File…") { viewModel.importHierarchicalTextFiles() }
                Button("Hierarchical Text File 2…") { viewModel.importHierarchicalTextFilesWithBodies() }
                Button("Text Files in a Folder…") { viewModel.importTextFilesInFolder() }
            }
            Menu("Export") {
                Button("Text File (Card Title)…") { viewModel.exportCardTitles() }
                Button("Text File (Body)…") { viewModel.exportCardBodies() }
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
            Button("Print Browser View…") { viewModel.printBrowserView() }
        }

        CommandGroup(after: .undoRedo) {
            Divider()
            Button("Find…") { viewModel.cardFilterFocusTrigger = true }
                .keyboardShortcut("f", modifiers: [.command])
            Divider()
            Menu("GPT") {
                ForEach(Array(GPTPromptAction.menuSections.enumerated()), id: \.offset) { sectionIndex, actions in
                    ForEach(actions) { action in
                        Button(action.menuTitle) { viewModel.copyGPTPrompt(for: action) }
                    }
                    if sectionIndex < GPTPromptAction.menuSections.count - 1 {
                        Divider()
                    }
                }
            }
            .disabled(viewModel.selectedCardID == nil)
            Button("Web Search") { viewModel.searchWebForSelection() }
                .disabled(viewModel.selectedCardID == nil)
            Button("Edit Card Labels…") { viewModel.showCardLabelEditor = true }
            Button("Edit Link Labels…") { viewModel.showLinkLabelEditor = true }
            Divider()
            Menu("Batch Conversion") {
                Menu("All Cards Shape") {
                    ForEach(frieveCardShapeOptions, id: \.index) { option in
                        Button(option.name) { viewModel.batchChangeAllCardsShape(to: option.index) }
                    }
                }
                Menu("All Links Shape") {
                    ForEach(frieveLinkShapeOptions, id: \.index) { option in
                        Button(option.name) { viewModel.batchChangeAllLinksShape(to: option.index) }
                    }
                }
                Button("Reverse All Links Direction") { viewModel.batchReverseAllLinksDirection() }
            }
        }

        CommandMenu("Insert") {
            Button("New Card") { viewModel.addRootCard() }
            Button("New Root Card") { viewModel.addRootCard() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("New Child Card") { viewModel.addChildCard() }
                .keyboardShortcut(.return, modifiers: [.shift])
            Button("New Sibling Card") { viewModel.addSiblingCard() }
                .keyboardShortcut(.return, modifiers: [.command])
            Divider()
            Menu("New Link") {
                ForEach(viewModel.document.cards.filter { $0.id != viewModel.selectedCardID }, id: \.id) { card in
                    Button(card.title.nilIfEmpty ?? "Card \(card.id)") {
                        viewModel.addLinkFromSelection(to: card.id)
                    }
                }
            }
            .disabled(viewModel.selectedCardID == nil || viewModel.document.cards.count <= 1)
            Button("New Ext Link…") { viewModel.insertExtLink() }
            Menu("New Label for Selected Cards") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.assignCardLabelToSelection(labelID: label.id) }
                }
            }
            .disabled(viewModel.selectedCardIDs.isEmpty)
            Button("New Link Label…") { viewModel.showLinkLabelEditor = true }
            Divider()
            Button("Link to Root") { viewModel.addLinkBetweenSelectionAndRoot() }
            Menu("Link to All Cards with Label") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.linkSelectionToAllCardsWithLabel(labelID: label.id) }
                }
            }
            .disabled(viewModel.selectedCardID == nil)
            Menu("New Card Links to All Cards with Label") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.addCardLinkedToAllCardsWithLabel(labelID: label.id) }
                }
            }
            .disabled(viewModel.document.cardLabels.isEmpty)
            Menu("Add Label to All Destination Cards") {
                ForEach(viewModel.document.cardLabels) { label in
                    Button(label.name) { viewModel.addLabelToAllDestinationCards(labelID: label.id) }
                }
            }
            .disabled(viewModel.selectedCardID == nil)
        }

        CommandGroup(after: .toolbar) {
            Menu("Mode") {
                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
            }
            Divider()
            Button("Arrange") { viewModel.arrangeCards() }
            Button("Shuffle") { viewModel.shuffleLayout() }
            Divider()
            Button("Start Read Aloud") { viewModel.readSelectedCardAloud() }
                .disabled(viewModel.selectedCardID == nil)
            Button("Stop Read Aloud") { viewModel.stopReadAloud() }
            Divider()
            Toggle("Show Overview", isOn: $viewModel.showOverview)
            Toggle("Show Link Labels", isOn: $viewModel.linkLabelsVisible)
            Toggle("Show Label Rectangles", isOn: Binding(
                get: { viewModel.labelRectanglesVisible },
                set: { viewModel.setBrowserLabelRectanglesVisible($0) }
            ))
            Divider()
            Toggle("Show Status Bar", isOn: $viewModel.showStatusBar)
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

        CommandGroup(after: .help) {
            Button("Frieve Website") { viewModel.browseFrieveSite() }
            Button("Frieve Editor Website") { viewModel.browseHelp() }
            Button("Check Latest Release") { viewModel.checkLatestRelease() }
        }
    }
}
