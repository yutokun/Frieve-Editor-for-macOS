# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Rule

**Do not edit the Windows version.** This project is porting Windows → macOS. The `windows/` directory is reference-only.

## Repository Structure

- `windows/` — Original Windows app (C++Builder / VCL). Reference only.
- `macos/` — macOS port (Swift 6, SwiftUI, SwiftPM). Active development target.
- `shared/` — Cross-platform format specs and sample documents.
- `plans/` — Architecture and migration planning documents.

## Build & Test (macOS)

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

**Format spec**: `shared/format-specs/FIP2_FORMAT_SPEC.md` (canonical), mirrored at `macos/Sources/macos/Resources/FIP2_FORMAT_SPEC.md`.

## Format-Change Rules

When changing the FIP2 format or document serialization, update **all** of these together:
1. `shared/format-specs/FIP2_FORMAT_SPEC.md`
2. `macos/Sources/macos/Resources/FIP2_FORMAT_SPEC.md`
3. `macos/Sources/macos/Model/` codec implementations
4. Relevant tests in `macos/Tests/macosTests/`

## Key Design Patterns

- The browser view uses AppKit (NSView) bridged into SwiftUI via NSViewRepresentable, with Metal shaders for rendering.
- `WorkspaceViewModel` is the central @Observable state object, deliberately split across multiple extension files by responsibility.
- Settings use `UserDefaults` via `AppSettings` (not a settings file).
- The app supports auto-save and auto-reload; keep this in mind when testing document operations.
