# macOS Browser AppKit + CALayer Migration Plan

## Objective

Migrate the macOS Browser from its current **SwiftUI `Canvas` + many `SwiftUI View` cards** rendering path to a dedicated **AppKit + CALayer rendering surface** that can simultaneously deliver:

- a realistic path to 60fps during pan / zoom / drag
- reduced CPU wakeups and better laptop battery efficiency
- preservation of existing Browser interaction behavior
- incremental adoption without rewriting the entire macOS app shell

---

## Initial Assessment

### Project Structure Summary

- The macOS app is a Swift Package targeting macOS 13+, so introducing an AppKit-backed Browser surface is a natural fit within the current build structure.  
  **Source:** `macos/Package.swift:4-28`  
  **Implication:** Browser-only AppKit migration does not require a major package reorganization.

- The current Browser UI is composed by `BrowserWorkspaceView` and `BrowserCanvasView`, with the HUD and overview layered on top in SwiftUI.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:296-315`, `macos/Sources/macos/App/FrieveEditorMacApp.swift:318-401`  
  **Implication:** The Browser surface itself can be replaced while the surrounding SwiftUI shell remains intact.

- Visible cards are currently rendered as many `CardNodeView` instances inside `ForEach`, each with text, overlays, shadow, preview content, and gestures.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:397-400`, `macos/Sources/macos/App/FrieveEditorMacApp.swift:522-666`  
  **Implication:** The Browser pays substantial retained SwiftUI view-tree cost during pan/zoom, which is unfavorable for both performance and battery.

- An AppKit input bridge already exists in `BrowserInteractionNSView`, handling focus, wheel, keyboard, and deletion shortcuts.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:862-943`  
  **Implication:** The migration can extend an existing AppKit foothold rather than starting from zero.

- Browser scene, metadata, and overview snapshot generation are already centralized in `WorkspaceViewModel`, which provides an initial rendering contract to evolve toward AppKit-friendly snapshots.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:39-89`, `macos/Sources/macos/App/WorkspaceViewModel.swift:111-189`, `macos/Sources/macos/App/WorkspaceViewModel.swift:1021-1071`  
  **Implication:** We can first preserve the current data flow, then progressively replace SwiftUI-specific render types.

### Relevant Files Examination

- **Current Browser surface:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:318-401`  
  Main SwiftUI Browser drawing path and primary replacement target.

- **Current card UI:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:522-666`  
  The card subtree that should be retired from the hot path.

- **Existing AppKit bridge:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:862-943`  
  Reusable input/focus bridge for the future Browser surface.

- **Overview implementation:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:983-1019`  
  Candidate for a separate low-frequency layer-backed view.

- **Browser scene/cache logic:** `macos/Sources/macos/App/WorkspaceViewModel.swift:881-1071`, `macos/Sources/macos/App/WorkspaceViewModel.swift:1699-1945`  
  Current rendering contract that must be evolved away from SwiftUI-specific drawing types.

---

## Prioritized Challenges and Risks

1. **Replacing SwiftUI card rendering is the highest-priority architectural change**  
   **Reason:** `CardNodeView` is structurally heavy and costly during broad viewport movement.  
   **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:522-666`

2. **Pan/zoom must become transform-driven rather than relayout-driven**  
   **Reason:** Battery-friendly rendering depends on reusing retained visual content rather than recomputing layout each frame.  
   **Source:** The current path converts world space to canvas space per element via `canvasPoint` `macos/Sources/macos/App/WorkspaceViewModel.swift:974-979`

3. **The render contract must be separated from SwiftUI drawing primitives**  
   **Reason:** `BrowserLinkRenderData` currently embeds `Path`, which does not map cleanly onto a Core Animation-first pipeline.  
   **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:60-70`

4. **Editing and interaction overlays must be decoupled from base scene rendering**  
   **Reason:** Inline editing and transient overlays should not force the main retained scene to redraw.  
   **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:424-439`, `macos/Sources/macos/App/FrieveEditorMacApp.swift:770-780`

---

## Assumptions / Clarity Assessment

- The migration target is the **Browser tab rendering and interaction surface**, not the rest of the macOS app shell.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:296-315`

- The immediate target is **AppKit + CALayer**, not direct Metal adoption.

- Browser behavior should remain functionally equivalent where possible, with drawing architecture changing before interaction semantics change.

---

## Recommended Architecture

- **Keep the SwiftUI shell**
  - `BrowserWorkspaceView` remains in SwiftUI
  - only the Browser surface is replaced with `NSViewRepresentable`

- **Use a layer-backed AppKit Browser surface**
  - introduce a `BrowserSurfaceNSView`
  - enable `wantsLayer = true`
  - manage `CALayer` / `CAShapeLayer` / `CATextLayer` / raster contents explicitly

- **Rasterize card contents**
  - title, summary, badges, and previews should be rendered into reusable card images
  - selection/hover/focus visuals should be separate decoration layers

- **Use parent transforms for pan/zoom**
  - keep world-space geometry stable
  - move/scale a content container layer rather than re-laying out every card

- **Render links in dedicated layers**
  - start with `CAShapeLayer` or batched custom layer drawing
  - move labels to `CATextLayer` or pre-rasterized text only when needed

- **Keep inline editor, HUD, and overview separate**
  - editing UI stays as native overlay UI rather than being forced into retained layer drawing

---

## Implementation Plan

### Phase 0: Migration Baseline and Success Contract

- [x] **P0-1. Freeze the migration scope for the Browser surface (Status: Completed)**  
  Replace `BrowserCanvasView`, while leaving HUD, outer SwiftUI layout, and surrounding workspace panels in SwiftUI.  
  **Rationale:** This constrains migration scope and reduces rollback risk.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:296-315`, `macos/Sources/macos/App/FrieveEditorMacApp.swift:318-401`

- [x] **P0-2. Define success criteria in both fps and power terms (Status: Completed)**  
  Explicitly require near-60fps interaction during pan/zoom/drag and no unnecessary redraw activity while idle.  
  **Rationale:** Laptop efficiency depends as much on idle behavior and redraw suppression as on peak frame rate.

- [x] **P0-3. Add a runtime switch between the legacy SwiftUI Browser and the new AppKit Browser (Status: Completed)**  
  Use a feature flag or setting toggle.  
  **Rationale:** Comparative validation and rollback become far easier when old/new paths can coexist temporarily.

### Phase 1: Rendering Contract Refactor

- [x] **P1-1. Redefine the Browser scene as a SwiftUI-independent immutable snapshot (Status: Completed)**  
  Remove `Path` and other SwiftUI-specific drawing types from Browser render payloads and shift toward `CGPoint`, `CGRect`, and CoreGraphics/CALayer-friendly geometry.  
  **Rationale:** AppKit/CALayer needs a neutral rendering contract.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:52-70`, `macos/Sources/macos/App/WorkspaceViewModel.swift:1021-1071`

- [x] **P1-2. Separate static render snapshots from transient interaction state (Status: Completed)**  
  Keep selection, hover, drag, inline editor, and link preview as overlay state distinct from the stable scene snapshot.  
  **Rationale:** Static scene reuse is critical for both performance and battery.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:149-159`, `macos/Sources/macos/App/WorkspaceViewModel.swift:1228-1397`

- [x] **P1-3. Rework Browser coordinate APIs around transform-based rendering (Status: Completed)**  
  Refactor `canvasPoint`, `canvasToWorld`, and `visibleWorldRect` responsibilities so the AppKit surface can own viewport transforms more directly.  
  **Rationale:** The future renderer should apply transforms to retained layers rather than repositioning every primitive.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:869-879`, `macos/Sources/macos/App/WorkspaceViewModel.swift:974-987`

### Phase 2: AppKit Surface Introduction

- [x] **P2-1. Replace the SwiftUI Browser body with a dedicated AppKit surface via `NSViewRepresentable` (Status: Completed)**  
  Introduce a `BrowserSurfaceRepresentable` as the new Browser rendering host.  
  **Rationale:** This preserves SwiftUI around the Browser while moving the hot path into AppKit.  
  **Source:** Existing representable pattern in `macos/Sources/macos/App/FrieveEditorMacApp.swift:862-887`

- [x] **P2-2. Integrate `BrowserInteractionNSView` behavior into the new Browser surface (Status: Completed)**  
  Carry over wheel, keyboard, delete, and focus behavior.  
  **Rationale:** The existing AppKit bridge already covers important Browser interactions.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:889-943`

- [x] **P2-3. Make the Browser surface explicitly layer-backed (Status: Completed)**  
  Set `wantsLayer = true` and establish Core Animation ownership of drawing updates.  
  **Rationale:** Retained CALayer composition is the foundation of the migration.

### Phase 3: Layer Hierarchy Design

- [x] **P3-1. Define the root layer hierarchy and ownership model (Status: Completed)**  
  Establish `backgroundLayer`, `contentTransformLayer`, `linksLayer`, `cardsLayer`, `selectionOverlayLayer`, `marqueeLayer`, and `linkPreviewLayer`.  
  **Rationale:** Clear update boundaries reduce redraw propagation.

- [x] **P3-2. Drive pan and zoom through `contentTransformLayer` affine transforms (Status: Completed)**  
  Keep world geometry stable and transform the retained content container.  
  **Rationale:** This is central to reducing both frame cost and battery drain.

- [x] **P3-3. Keep overview as a separate layer-backed surface with lower update frequency (Status: Completed)**  
  Do not bind overview redraw frequency to the main Browser surface.  
  **Rationale:** Overview and main content have different update economics.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:983-1019`, `macos/Sources/macos/App/WorkspaceViewModel.swift:886-967`

### Phase 4: Card Rendering Migration

- [x] **P4-1. Replace `CardNodeView` with rasterized card contents (Status: Completed)**  
  Render card body, title, summary, badges, and preview imagery into reusable images and display them through `CALayer.contents`.  
  **Rationale:** This removes large portions of the retained SwiftUI card subtree from the hot path.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:522-666`

- [x] **P4-2. Move selection, hover, and focus visuals into decoration sublayers (Status: Completed)**  
  Keep card raster contents independent from transient highlight state.  
  **Rationale:** Highlight changes should not invalidate full card rasters.

- [x] **P4-3. Merge media and drawing preview caches into the card raster pipeline (Status: Completed)**  
  Reuse existing thumbnail and drawing preview caches when generating card rasters.  
  **Rationale:** Preview content should be baked into retained card imagery rather than reintroduced as separate SwiftUI subtrees.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:710-767`, `macos/Sources/macos/App/WorkspaceViewModel.swift:1992-2048`

- [x] **P4-4. Define raster invalidation rules for cards (Status: Completed)**  
  Document exactly which changes force rerasterization: title, summary, labels, badges, preview content, or geometry class changes.  
  **Rationale:** Tight invalidation is necessary to avoid wasted work and stale visuals.

### Phase 5: Link and Background Rendering Migration

- [x] **P5-1. Move link rendering to `CAShapeLayer` groups or a batched custom CALayer (Status: Completed)**  
  Replace the current `Canvas`-based per-frame line drawing with retained layer-based link presentation.  
  **Rationale:** Link rendering should no longer be rebuilt through SwiftUI immediate-mode drawing.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:363-394`, `macos/Sources/macos/App/WorkspaceViewModel.swift:1038-1071`

- [x] **P5-2. Render link labels through `CATextLayer` or pre-rasterized text only when needed (Status: Completed)**  
  Gate visibility by zoom level or settings.  
  **Rationale:** Text is usually more expensive than line segments and should be aggressively culled when not useful.

- [x] **P5-3. Replace the background grid with a tiled layer or low-frequency redraw layer (Status: Completed)**  
  Regenerate only when zoom bands change rather than on every viewport update.  
  **Rationale:** The grid is static enough to benefit heavily from retained rendering.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:1130-1162`

### Phase 6: Interaction and Editing Layer Separation

- [x] **P6-1. Replace linear card hit testing with scene-index-based lookup (Status: Completed)**  
  Move toward a visible-card spatial index or z-order-aware lookup rather than scanning all sorted cards.  
  **Rationale:** AppKit alone will not fix large-scene hit-testing if the underlying lookup remains linear.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:1245-1253`

- [x] **P6-2. Render drag, marquee, and link preview through dedicated overlay layers (Status: Completed)**  
  Keep transient interaction visuals separate from card and link content layers.  
  **Rationale:** Gesture-driven updates should touch the fewest layers possible.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:1255-1397`

- [x] **P6-3. Keep inline editing as native overlay UI rather than baking it into retained layers (Status: Completed)**  
  Position an AppKit or SwiftUI editing overlay above the Browser scene only when editing is active.  
  **Rationale:** Text editing remains easier and safer with native controls.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:424-439`, `macos/Sources/macos/App/FrieveEditorMacApp.swift:770-780`

### Phase 7: Power Optimization and Frame Pacing

- [x] **P7-1. Ensure there is no continuous redraw loop while idle (Status: Completed)**  
  Redraw strictly on state changes; do not introduce a display-link-style always-on loop unless absolutely required.  
  **Rationale:** Idle efficiency is critical on Mac laptops.

- [x] **P7-2. Introduce zoom-dependent detail levels (Status: Completed)**  
  Omit badges, link labels, and secondary detail when zoomed far out.  
  **Rationale:** The cheapest render work is the work never scheduled.

- [x] **P7-3. Define memory ceilings and eviction policy for card rasters, link geometry, and thumbnails (Status: Completed)**  
  Use bounded caches such as LRU-style eviction.  
  **Rationale:** Overgrown caches can trade GPU/CPU gains for memory pressure and worse energy use.

- [x] **P7-4. Prefer dirty-rect updates over full-surface refreshes (Status: Completed)**  
  Hover, selection, and single-card updates should repaint only the affected areas or layers.  
  **Rationale:** Localized updates are central to both smoothness and power efficiency.

### Phase 8: Rollout, Verification, and Retirement of the Old Path

- [x] **P8-1. Compare legacy SwiftUI Browser and new AppKit Browser side by side (Status: Completed)**  
  Measure frame behavior, CPU usage, idle activity, and interaction latency.  
  **Rationale:** The migration must demonstrate both speed and energy wins.

- [x] **P8-2. Perform Browser feature-regression validation (Status: Completed)**  
  Validate selection, multi-selection, marquee, link creation, hover, inline editor, overview recenter, fit, and zoom-to-selection.  
  **Rationale:** Rendering-path replacement carries high regression risk for interaction features.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:1255-1459`

- [x] **P8-3. Retire the old `BrowserCanvasView` path after comparative validation (Status: Completed)**  
  Remove the legacy Browser drawing path once the AppKit version is clearly superior and stable.  
  **Rationale:** Long-lived dual implementations raise maintenance and regression cost.

---

## Verification Criteria

- [x] The Browser surface no longer depends on SwiftUI `Canvas` plus `ForEach(CardNodeView)` in the hot path.  
  **Source:** Current dependency target `macos/Sources/macos/App/FrieveEditorMacApp.swift:318-401`

- [x] Pan and zoom primarily update retained layer transforms rather than rerasterizing card contents.

- [x] Hover, selection, marquee, and link preview updates do not trigger full card rerasterization.

- [x] Media preview and drawing preview flow through the retained card raster pipeline rather than separate SwiftUI card subtrees.  
  **Source:** Current preview path `macos/Sources/macos/App/FrieveEditorMacApp.swift:710-767`

- [x] Overview uses an independent, lower-frequency retained update path.  
  **Source:** `macos/Sources/macos/App/FrieveEditorMacApp.swift:983-1019`

- [x] Single-card drag, multi-card drag, pan, zoom, fit, and zoom-to-selection feel near 60fps under typical working document sizes.  
  **Source:** `macos/Sources/macos/App/WorkspaceViewModel.swift:1255-1459`

- [x] Idle Browser state does not show persistent redraw activity or elevated CPU use.

- [x] `swift build` and `swift test` pass after migration milestones.  
  **Source:** `macos/Package.swift:4-28`

---

## Potential Risks and Mitigations

1. **The rendering migration has a large regression surface**  
   Mitigation: Keep the SwiftUI shell and replace only the Browser hot path first.

2. **AppKit migration alone may not help enough if scene generation remains too expensive**  
   Mitigation: Refactor the render snapshot contract early so the new renderer receives retained-scene-friendly data.

3. **Card raster caches can grow too large**  
   Mitigation: Use bounded caches, size buckets, and clear invalidation rules.

4. **Editing UX or accessibility could degrade**  
   Mitigation: Keep inline editor functionality on native controls outside the retained-layer rendering core.

5. **Large link counts may make one-layer-per-link too expensive**  
   Mitigation: Start with a simple layer model, but keep a batched custom drawing layer fallback for higher-density scenes.

---

## Alternative Approaches

1. **Incremental AppKit migration**  
   Keep the SwiftUI shell and replace only the Browser surface. This is the most practical route and best aligned with current structure.  
   **Trade-off:** Requires careful boundary design, but keeps project risk manageable.

2. **Clean-slate Browser module separation**  
   Move Browser rendering, interaction, and scene management into a dedicated subsystem.  
   **Trade-off:** Cleaner long-term structure, but significantly higher short-term cost.

3. **Skip AppKit and go straight to Metal**  
   This offers the highest theoretical ceiling.  
   **Trade-off:** It is too heavy for the current Browser’s mixed text/image/editor UI and would raise implementation and maintenance complexity sharply.

---

## Recommended Execution Order

- [x] **Order 1. Complete Phase 0-1 first (Status: Completed)**  
  Lock the rendering contract and success criteria before replacing the hot path.

- [x] **Order 2. Implement Phase 2-3 next (Status: Completed)**  
  Introduce the AppKit surface and retained layer hierarchy before moving card and link rendering.

- [x] **Order 3. Execute Phase 4-6 for the main migration body (Status: Completed)**  
  This is where the actual performance and power gains will come from.

- [x] **Order 4. Use Phase 7 for battery-focused tuning (Status: Completed)**  
  Detail throttling, cache policy, and dirty updates are the key laptop-efficiency finishers.

- [x] **Order 5. Finish with Phase 8 validation and legacy-path retirement (Status: Completed)**  
  Remove the old Browser path only after comparative verification proves the new path superior.
