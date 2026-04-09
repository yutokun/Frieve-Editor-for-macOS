import SwiftUI
import AppKit

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
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: viewModel.newDocument) {
                    Label("New", systemImage: "doc.badge.plus")
                }
                Button(action: viewModel.openDocument) {
                    Label("Open", systemImage: "folder")
                }
                Button(action: viewModel.saveDocument) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 330)

                Picker("Arrange", selection: $viewModel.arrangeMode) {
                    Text("Link").tag("Link")
                    Text("Matrix").tag("Matrix")
                    Text("Radial").tag("Radial")
                    Text("Tree").tag("Tree")
                }
                .frame(width: 160)

                Button("Arrange") { viewModel.arrangeCards() }
                Button("Shuffle") { viewModel.shuffleLayout() }
                Button {
                    viewModel.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                Button {
                    viewModel.requestBrowserFit()
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                }
                Button {
                    viewModel.zoomToSelection(in: CGSize(width: 1200, height: 800))
                } label: {
                    Label("Selection", systemImage: "selection.pin.in.out")
                }
                Button {
                    viewModel.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                Toggle("Auto Zoom", isOn: $viewModel.autoZoom)
                Toggle("Overview", isOn: $viewModel.showOverview)
            }
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

            TextField("Filter cards", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(12)

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

                Section("Actions") {
                    Button("New Root Card") { viewModel.addRootCard() }
                    Button("New Child Card") { viewModel.addChildCard() }
                    Button("New Sibling Card") { viewModel.addSiblingCard() }
                    Button("Link to Root") { viewModel.addLinkBetweenSelectionAndRoot() }
                    Button("Delete Selected") { viewModel.deleteSelectedCard() }
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct CardListPane: View {
    @ObservedObject var viewModel: WorkspaceViewModel

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
                    ForEach(viewModel.filteredCards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .fontWeight(viewModel.selectedCardIDs.contains(card.id) ? .semibold : .regular)
                            Text(card.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .tag(card.id)
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct WorkspaceContentView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    private let maintenanceTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(viewModel.fileDisplayName)
                    .font(.title3.weight(.semibold))
                Spacer()
                TextField("Global Search", text: $viewModel.globalSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Stepper(value: $viewModel.zoom, in: 0.5 ... 2.0, step: 0.1) {
                    Text("Zoom \(viewModel.zoom.formatted(.number.precision(.fractionLength(1))))x")
                }
                .frame(width: 170)
            }
            .padding(12)

            HStack(spacing: 0) {
                Group {
                    switch viewModel.selectedTab {
                    case .browser:
                        BrowserWorkspaceView(viewModel: viewModel)
                    case .editor:
                        EditorWorkspaceView(viewModel: viewModel)
                    case .drawing:
                        DrawingWorkspaceView(viewModel: viewModel)
                    case .statistics:
                        StatisticsWorkspaceView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.showInspector {
                    InspectorPaneView(viewModel: viewModel)
                        .frame(width: 280)
                        .background(Color(nsColor: .controlBackgroundColor))
                }
            }

            StatusBarView(viewModel: viewModel)
        }
        .onReceive(maintenanceTimer) { now in
            viewModel.performAutomaticMaintenance(now: now)
        }
    }
}
