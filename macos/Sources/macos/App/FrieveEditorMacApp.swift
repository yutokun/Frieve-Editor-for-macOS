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

        Settings {
            FrieveEditorSettingsView(settings: viewModel.settings)
        }
    }
}

private struct FrieveEditorSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Automation") {
                Toggle("Auto Save", isOn: $settings.autoSaveDefault)
                Toggle("Auto Reload", isOn: $settings.autoReloadDefault)

                Picker("Web Search", selection: $settings.preferredWebSearchName) {
                    ForEach(settings.webSearchProviders) { provider in
                        Text(provider.name).tag(provider.name)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Read Speed")
                        Spacer()
                        Text("\(Int(settings.readAloudRate))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.readAloudRate, in: 100 ... 320, step: 5)
                }

                TextField("GPT Model", text: $settings.gptModel)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460)
    }
}
