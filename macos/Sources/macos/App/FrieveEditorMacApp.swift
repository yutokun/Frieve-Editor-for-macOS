import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

    private var availableFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    private var labelOutlineStyle: Binding<BrowserLabelOutlineStyle> {
        Binding(
            get: {
                if settings.browserLabelCircleVisible {
                    return .circle
                }
                if settings.browserLabelRectangleVisible {
                    return .rectangle
                }
                return .none
            },
            set: { style in
                settings.browserLabelCircleVisible = style == .circle
                settings.browserLabelRectangleVisible = style == .rectangle
            }
        )
    }

    var body: some View {
        TabView {
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
                            Text("\(settings.readAloudRate)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.readAloudRate) },
                                set: { settings.readAloudRate = Int($0.rounded()) }
                            ),
                            in: -10 ... 10,
                            step: 1
                        )
                    }

                    TextField("GPT Model", text: $settings.gptModel)
                        .textFieldStyle(.roundedBorder)
                    SecureField("GPT API Key", text: $settings.gptAPIKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                Section("Panels") {
                    Toggle("Show Overview", isOn: $settings.showOverview)
                }

                Section("Card") {
                    Toggle("Shadow", isOn: $settings.browserCardShadow)
                    Toggle("Gradient", isOn: $settings.browserCardGradation)
                    Toggle("Ticker", isOn: $settings.browserTickerVisible)
                    Picker("Ticker Lines", selection: $settings.browserTickerLines) {
                        Text("1 Line").tag(1)
                        Text("2 Lines").tag(2)
                    }
                    Toggle("Image", isOn: $settings.browserImageVisible)
                    Toggle("Video", isOn: $settings.browserVideoVisible)
                    Toggle("Drawing", isOn: $settings.browserDrawingVisible)
                    Picker("Preview Size", selection: $settings.browserImageLimitation) {
                        ForEach([32, 40, 64, 80, 120, 160, 240, 320], id: \.self) { value in
                            Text("\(value) px").tag(value)
                        }
                    }
                }

                Section("Link") {
                    Toggle("Show Links", isOn: $settings.browserLinkVisible)
                    Toggle("Hemming", isOn: $settings.browserLinkHemming)
                    Toggle("Show Direction", isOn: $settings.browserLinkDirectionVisible)
                    Toggle("Show Names", isOn: $settings.browserLinkNameVisible)
                }

                Section("Label") {
                    Picker("Outline", selection: labelOutlineStyle) {
                        Text("None").tag(BrowserLabelOutlineStyle.none)
                        Text("Rectangle").tag(BrowserLabelOutlineStyle.rectangle)
                        Text("Circle").tag(BrowserLabelOutlineStyle.circle)
                    }
                    Toggle("Show Label Names", isOn: $settings.browserLabelNameVisible)
                }

                Section("Text") {
                    Toggle("Show Card Text", isOn: $settings.browserTextVisible)
                    Toggle("Centering", isOn: $settings.browserTextCentering)
                    Toggle("Word Wrap", isOn: $settings.browserTextWordWrap)
                }

                Section("Font") {
                    Picker("Family", selection: $settings.browserFontFamily) {
                        Text("System Default").tag("")
                        ForEach(availableFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    LabeledContent("Size") {
                        HStack(spacing: 8) {
                            Stepper("", value: $settings.browserFontSize, in: 8 ... 36)
                                .labelsHidden()
                            Text("\(settings.browserFontSize) pt")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 52, alignment: .leading)
                        }
                    }
                    HStack {
                        Button("Default Size") {
                            settings.browserFontSize = 13
                        }
                    }
                }

                Section("Inline Editor") {
                    Toggle("Edit in Browser", isOn: $settings.browserEditInBrowser)
                    Toggle("Always Show Editor", isOn: $settings.browserEditInBrowserAlways)
                    Picker("Placement", selection: $settings.browserEditInBrowserPosition) {
                        ForEach(BrowserInlineEditorPosition.allCases) { position in
                            Text(position.title).tag(position.rawValue)
                        }
                    }
                }

                Section("Score") {
                    Toggle("Show Score", isOn: $settings.browserScoreVisible)
                    Picker("Score Type", selection: $settings.browserScoreType) {
                        ForEach(BrowserScoreDisplayType.allCases) { scoreType in
                            Text(scoreType.title).tag(scoreType.rawValue)
                        }
                    }
                }

                Section("Others") {
                    HStack {
                        Text("Wallpaper")
                        Spacer()
                        Text(settings.browserWallpaperPath.isEmpty ? "None" : URL(fileURLWithPath: settings.browserWallpaperPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Button("Choose Wallpaper…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.image]
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK {
                                settings.browserWallpaperPath = panel.url?.path ?? ""
                            }
                        }
                        Button("Clear") {
                            settings.browserWallpaperPath = ""
                        }
                        .disabled(settings.browserWallpaperPath.isEmpty)
                    }
                    Toggle("Fix Wallpaper", isOn: $settings.browserWallpaperFixed)
                        .disabled(settings.browserWallpaperPath.isEmpty)
                    Toggle("Tile Wallpaper", isOn: $settings.browserWallpaperTiled)
                        .disabled(settings.browserWallpaperPath.isEmpty)
                    Toggle("Background Animation", isOn: $settings.browserBackgroundAnimation)
                    Picker("Animation Type", selection: $settings.browserBackgroundAnimationType) {
                        ForEach(BrowserBackgroundAnimationType.allCases) { animationType in
                            Text(animationType.title).tag(animationType.rawValue)
                        }
                    }
                    .disabled(!settings.browserBackgroundAnimation)
                    Toggle("Cursor Animation", isOn: $settings.browserCursorAnimation)
                    Toggle("No Scroll Lag", isOn: $settings.browserNoScrollLag)
                }
            }
            .tabItem {
                Label("Browser", systemImage: "rectangle.3.group")
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 560)
    }
}
