import SwiftUI

@main
struct FrieveEditorMacApp: App {
    @StateObject private var viewModel = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup("Frieve Editor") {
            WorkspaceRootView(viewModel: viewModel)
                .frame(minWidth: 1280, minHeight: 800)
        }
        .commands {
            FrieveEditorCommands(viewModel: viewModel)
        }
    }
}
