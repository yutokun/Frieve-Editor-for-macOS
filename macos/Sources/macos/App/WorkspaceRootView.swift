import SwiftUI
import AppKit

@MainActor
func resolvedAppColor(_ color: @autoclosure () -> NSColor) -> Color {
    let appearance = NSApp.effectiveAppearance
    var resolved = color()
    appearance.performAsCurrentDrawingAppearance {
        resolved = color()
    }
    return Color(nsColor: resolved)
}

struct WorkspaceRootView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
        } content: {
            CardListPane(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
        } detail: {
            WorkspaceContentView(viewModel: viewModel)
        }
        .inspector(isPresented: $viewModel.showInspector) {
            InspectorPaneView(viewModel: viewModel)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .modifier(DocumentTitleModifier(fileDisplayName: viewModel.fileDisplayName,
                                        documentURL: viewModel.documentURL))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .sheet(isPresented: $viewModel.showCardLabelEditor) {
            LabelEditorView(viewModel: viewModel, isLinkLabels: false)
        }
        .sheet(isPresented: $viewModel.showLinkLabelEditor) {
            LabelEditorView(viewModel: viewModel, isLinkLabels: true)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
                Button(action: viewModel.openDocument) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            List {
                if viewModel.showFileList {
                    Section("Recent") {
                        ForEach(viewModel.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                viewModel.openDocument(url)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)
        }
        .background(resolvedAppColor(NSColor.controlBackgroundColor))
    }
}

private struct CardListPane: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cards")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.document.cardCount)")
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            if viewModel.showCardList {
                List(selection: Binding<Set<Int>>(get: {
                    viewModel.selectedCardIDs
                }, set: { selection in
                    if selection.isEmpty {
                        viewModel.clearSelection()
                    } else {
                        viewModel.selectedCardIDs = selection
                        viewModel.selectedCardID = selection.first
                        if let id = selection.first {
                            viewModel.selectCard(id)
                        }
                    }
                })) {
                    HStack(spacing: 4) {
                        TextField("Filter cards", text: $viewModel.searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .focused($filterFocused)
                        Menu {
                            ForEach(CardSortOrder.allCases) { order in
                                Button {
                                    viewModel.cardSortOrder = order
                                } label: {
                                    HStack {
                                        Text(order.label)
                                        if viewModel.cardSortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4)

                    ForEach(viewModel.filteredCards) { card in
                        Text(card.title)
                            .fontWeight(viewModel.selectedCardIDs.contains(card.id) ? .semibold : .regular)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .tag(card.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            } else {
                Spacer()
            }
        }
        .background(resolvedAppColor(NSColor.controlBackgroundColor))
        .onChange(of: viewModel.cardFilterFocusTrigger) { _, triggered in
            if triggered {
                viewModel.showCardList = true
                filterFocused = true
                viewModel.cardFilterFocusTrigger = false
            }
        }
    }
}

private struct WorkspaceContentView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    private let maintenanceTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch viewModel.selectedTab {
                case .browser:
                    BrowserWorkspaceView(viewModel: viewModel)
                        .ignoresSafeArea(.all, edges: .top)
                case .editor:
                    EditorWorkspaceView(viewModel: viewModel)
                case .drawing:
                    DrawingWorkspaceView(viewModel: viewModel)
                case .statistics:
                    StatisticsWorkspaceView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBarView(viewModel: viewModel)
        }
        .onReceive(maintenanceTimer) { now in
            viewModel.performAutomaticMaintenance(now: now)
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        viewModel.browserCanvasSize = geometry.size
                    }
                    .onChange(of: geometry.size) { newSize in
                        viewModel.browserCanvasSize = newSize
                    }
            }
        )
    }
}

private struct DocumentTitleModifier: ViewModifier {
    let fileDisplayName: String
    let documentURL: URL?

    func body(content: Content) -> some View {
        content
            .background(WindowDocumentConfigurator(title: fileDisplayName, representedURL: documentURL))
    }
}

/// NSWindow に直接アクセスして title と representedURL を設定する。
/// representedURL が設定されると macOS がタイトルバーにプロキシアイコンと下向き矢印を表示し、
/// クリックするとファイル名・保存場所を変更できる標準ポップオーバーが表示される。
private struct WindowDocumentConfigurator: NSViewRepresentable {
    let title: String
    let representedURL: URL?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.title = title
            window.representedURL = representedURL
            window.styleMask.insert(.fullSizeContentView)
        }
    }
}
