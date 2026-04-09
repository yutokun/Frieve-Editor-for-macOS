# AGENTS.md

## Purpose

This repository contains two platform-specific Frieve Editor implementations plus a shared file-format specification. Use this guide as the first stop before making changes.

## Repository layout

- `windows/`: primary Windows application implemented with Embarcadero C++Builder / VCL.
- `macos/`: macOS application implemented as a Swift Package with SwiftUI.
- `shared/`: shared specifications and other cross-platform reference material.

## File organization and refactor direction

- Make file-organization decisions platform-first: prefer placing code under `windows/` or `macos/` based on the implementation that owns the behavior, and only use `shared/` for truly cross-platform specifications or reference material.
- Use responsibility-based file ownership: each file or unit should have a narrow, durable reason to change, with document, session, settings, browser, timer, codec, and UI concerns owned by distinct files once they are non-trivial.
- Avoid catch-all files that mix UI rendering, file I/O, timers, orchestration, and service logic in one place. When a file starts accumulating multiple responsibilities, split it by behavior boundaries instead of extending the grab-bag.
- For macOS, prefer splitting large types across focused extensions in separate files when that improves ownership and navigation, while keeping app entry, SwiftUI views, state models, and AppKit bridge code in clearly separated pieces.
- For Windows, keep VCL forms thin and focused on wiring and presentation. Move timer handling, document lifecycle, session state, browser integration, settings, and similar logic into dedicated units as they grow, rather than continuing to expand the main form files.
- These organization rules do not relax the format-change requirements: any document format or serialization change still has to be coordinated across the shared spec and both platform implementations.

## Where to start reading

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

### Shared format

- Canonical shared FIP2 spec: `shared/format-specs/FIP2_FORMAT_SPEC.md`
- Bundled macOS copy of the same spec: `macos/Sources/macos/Resources/FIP2_FORMAT_SPEC.md`

## Platform-specific build and test workflow

### Windows

- Preferred IDE workflow: open `windows/src/feditor.cbproj` in C++Builder and build.
- Command-line packaging workflow: run `windows/build_project.bat`.
- Default command-line target is `Release Win64`.
- The build script requires a RAD Studio environment (`rsvars.bat`) and uses the .NET Framework 64-bit `MSBuild.exe` path baked into the script.
- Packaging is not just `feditor.exe`: the script also copies `help.fip`, `setting2.ini`, `help/`, `lng/`, and `wallpaper/` into `windows/dist/feditor/` and creates a zip file.

### macOS

- Build and test from the `macos/` directory with SwiftPM.
- Expected commands:
  - `swift build`
  - `swift test`
- The package requires macOS 13+ and Swift tools 6.3 / Swift language mode 6.

## Format-change rules

If you change the FIP2 format or anything that affects document serialization, update all related locations together:

1. `shared/format-specs/FIP2_FORMAT_SPEC.md`
2. `macos/Sources/macos/Resources/FIP2_FORMAT_SPEC.md`
3. `macos/Sources/macos/Model/DocumentCodecs.swift`
4. Windows document parsing/saving code under `windows/src/utils/`
5. Relevant macOS tests under `macos/Tests/`

Do not update only the spec or only one platform implementation.

## Runtime behavior to remember while testing

- Windows has timer-driven auto-reload for externally modified files.
- Windows also has auto-save based on idle time and minimum interval.
- macOS stores equivalent defaults for auto-save and auto-reload in app settings.

When validating editing behavior, keep in mind that documents may reload or save automatically.

## Configuration and localization

### Windows

- Runtime GPT / web-search related settings live in `windows/resource/setting2.ini`.
- UI localization depends heavily on `.lng` files under `windows/resource/lng/`.
- Many visible menu and UI strings are loaded from the language file at runtime, so text changes may require both code and `.lng` updates.

### macOS

- User settings are stored in `UserDefaults` through `AppSettings`.
- Recent files, GPT settings, language, and auto-save / auto-reload defaults are persisted there.

## Environment and tooling caveats

- `windows/readme.md` says to open `src/feditor.cbprpj`, but the actual project file is `windows/src/feditor.cbproj`.
- macOS tests include an absolute-path dependency on `/Users/yuto/SoftwareProjects/Frieve-Editor/windows/resource/help.fip`; this is environment-specific and may fail on other machines or CI.
- `.vscode/` C/C++ settings are helpful for navigation, but they depend on Embarcadero include paths and should not be treated as the source of truth for the build.
- `.vscode/settings.json` disables C/C++ error squiggles, so editor diagnostics alone are not reliable proof that the Windows code is clean.

## Practical working rules for agents

1. Identify the target platform first. Windows and macOS are separate implementations, not a single shared codebase.
2. Prefer changing existing files over inventing new structure.
3. When touching document format behavior, verify both platform implementations and the shared spec.
4. When touching Windows UI text, check whether the string is hard-coded or loaded from `.lng` resources.
5. When validating packaging or release behavior on Windows, verify resource files as well as the executable.
6. Treat project files and build scripts as more authoritative than README prose when they disagree.
