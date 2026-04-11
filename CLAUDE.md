# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Rule

**Do not edit the Windows version.** This project is porting Windows → macOS. The `windows/` directory is reference-only.

## Repository Structure

- `windows/` — Original Windows app (C++Builder / VCL). Reference only.
- `macos/` — macOS port (Swift 6, SwiftUI, SwiftPM). Active development target.
- `shared/` — Cross-platform format specs and sample documents.
- `plans/` — Architecture and migration planning documents.

## File Organization and Refactor Direction

- Make file-organization decisions platform-first: prefer placing code under `windows/` or `macos/` based on the implementation that owns the behavior, and only use `shared/` for truly cross-platform specifications or reference material.
- Use responsibility-based file ownership: each file or unit should have a narrow, durable reason to change, with document, session, settings, browser, timer, codec, and UI concerns owned by distinct files once they are non-trivial.
- Avoid catch-all files that mix UI rendering, file I/O, timers, orchestration, and service logic in one place. When a file starts accumulating multiple responsibilities, split it by behavior boundaries instead of extending the grab-bag.
- For macOS, prefer splitting large types across focused extensions in separate files when that improves ownership and navigation, while keeping app entry, SwiftUI views, state models, and AppKit bridge code in clearly separated pieces.
- For Windows, keep VCL forms thin and focused on wiring and presentation. Move timer handling, document lifecycle, session state, browser integration, settings, and similar logic into dedicated units as they grow, rather than continuing to expand the main form files.
- These organization rules do not relax the format-change requirements: any document format or serialization change still has to be coordinated across the shared spec and both platform implementations.

## Where to Start Reading

### Windows

- Entry point: `windows/src/feditor.cpp`
- Project definition: `windows/src/feditor.cbproj`
- Main form and most UI behavior: `windows/src/forms/fomain.*`
- Auto-save / auto-reload behavior: `windows/src/forms/fomain_timer.cpp`
- Settings and localization wiring: `windows/src/forms/fomain_settings.cpp`, `windows/src/utils/setting.cpp`

### macOS

- Package definition: `macos/Package.swift`
- App entry point: `macos/Sources/macos/App/FrieveEditorMacApp.swift`
- Main state management: `macos/Sources/macos/App/WorkspaceViewModel.swift`
- Settings persistence: `macos/Sources/macos/App/AppSettings.swift`
- File loading/saving codecs: `macos/Sources/macos/Model/DocumentCodecs.swift`

### Shared Format

- Canonical shared FIP2 spec: `shared/format-specs/FIP2_FORMAT_SPEC.md`
- Bundled macOS copy of the same spec: `macos/Sources/macos/Resources/FIP2_FORMAT_SPEC.md`

## Build & Test

### Windows

- Preferred IDE workflow: open `windows/src/feditor.cbproj` in C++Builder and build.
- Command-line packaging workflow: run `windows/build_project.bat`.
- Default command-line target is `Release Win64`.
- The build script requires a RAD Studio environment (`rsvars.bat`) and uses the .NET Framework 64-bit `MSBuild.exe` path baked into the script.
- Packaging is not just `feditor.exe`: the script also copies `help.fip`, `setting2.ini`, `help/`, `lng/`, and `wallpaper/` into `windows/dist/feditor/` and creates a zip file.

### macOS

All commands run from the `macos/` directory:

```bash
cd macos
swift build          # Build the project
swift run            # Run the app
swift test           # Run all tests
```

Requires macOS 13+, Swift tools 6.3, Swift language mode 6.

## Architecture (macOS)

**App layer** (`macos/Sources/macos/App/`):
- `FrieveEditorMacApp.swift` — App entry point
- `WorkspaceViewModel.swift` — Central state management, split across extensions:
  - `+DocumentActions` — File open/save/export
  - `+BrowserInteraction` — Pan, zoom, drag, selection in the browser
  - `+BrowserCanvas` — Coordinate transforms, viewport management
  - `+BrowserRendering` — Card/link rendering pipeline
  - `+Selection` — Card selection logic
  - `+Support` — Utility helpers
- `BrowserSurfaceView.swift` / `BrowserWorkspaceView.swift` — AppKit bridge views for the card browser (NSViewRepresentable)
- `BrowserCardRenderingView.swift` — Card rendering within the browser
- `BrowserMetalShaders.metal` — GPU shaders for browser rendering
- `WorkspaceRootView.swift` — Main SwiftUI workspace layout
- `WorkspacePanels.swift` — Side panel UI
- `AppSettings.swift` — UserDefaults-backed settings persistence

**Model layer** (`macos/Sources/macos/Model/`):
- `FrieveDocument.swift` — Core document model
- `DocumentCodecs.swift` / `DocumentFileCodec.swift` — Codec protocol and registration
- `FIP2Codec.swift` — Current FIP2 format reader/writer
- `LegacyFIPCodec.swift` — Legacy format support

## Format-Change Rules

When changing the FIP2 format or document serialization, update **all** of these together:
1. `shared/format-specs/FIP2_FORMAT_SPEC.md`
2. `macos/Sources/macos/Resources/FIP2_FORMAT_SPEC.md`
3. `macos/Sources/macos/Model/` codec implementations
4. Windows document parsing/saving code under `windows/src/utils/`
5. Relevant tests in `macos/Tests/macosTests/`

Do not update only the spec or only one platform implementation.

## Key Design Patterns

- The browser view uses AppKit (NSView) bridged into SwiftUI via NSViewRepresentable, with Metal shaders for rendering.
- `WorkspaceViewModel` is the central @Observable state object, deliberately split across multiple extension files by responsibility.
- Settings use `UserDefaults` via `AppSettings` (not a settings file).
- The app supports auto-save and auto-reload; keep this in mind when testing document operations.

## Configuration and Localization

### Windows

- Runtime GPT / web-search related settings live in `windows/resource/setting2.ini`.
- UI localization depends heavily on `.lng` files under `windows/resource/lng/`.
- Many visible menu and UI strings are loaded from the language file at runtime, so text changes may require both code and `.lng` updates.

### macOS

- User settings are stored in `UserDefaults` through `AppSettings`.
- Recent files, GPT settings, language, and auto-save / auto-reload defaults are persisted there.

## Environment and Tooling Caveats

- `windows/readme.md` says to open `src/feditor.cbprpj`, but the actual project file is `windows/src/feditor.cbproj`.
- macOS tests include an absolute-path dependency on `/Users/yuto/SoftwareProjects/Frieve-Editor/windows/resource/help.fip`; this is environment-specific and may fail on other machines or CI.
- `.vscode/` C/C++ settings are helpful for navigation, but they depend on Embarcadero include paths and should not be treated as the source of truth for the build.
- `.vscode/settings.json` disables C/C++ error squiggles, so editor diagnostics alone are not reliable proof that the Windows code is clean.

## Practical Working Rules

1. Identify the target platform first. Windows and macOS are separate implementations, not a single shared codebase.
2. Prefer changing existing files over inventing new structure.
3. When touching document format behavior, verify both platform implementations and the shared spec.
4. When touching Windows UI text, check whether the string is hard-coded or loaded from `.lng` resources.
5. When validating packaging or release behavior on Windows, verify resource files as well as the executable.
6. Treat project files and build scripts as more authoritative than README prose when they disagree.
