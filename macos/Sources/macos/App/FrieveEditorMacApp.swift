import AppKit
import SwiftUI

final class FrieveEditorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct FrieveEditorMacApp: App {
    @NSApplicationDelegateAdaptor(FrieveEditorAppDelegate.self) private var appDelegate
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
