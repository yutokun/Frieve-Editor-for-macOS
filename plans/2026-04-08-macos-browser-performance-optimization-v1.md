# macOS Browser 60fps Optimization Plan

Date: 2026-04-08  
Version: v1  
Target: `macos`

## Goal

Improve the macOS Browser so panning, zooming, dragging, and overview rendering can realistically approach 60fps under normal editing workloads, while preserving current Browser functionality.

## Findings Summary

1. The overview/minimap recomputes expensive whole-document bounds repeatedly during drawing.
2. Card dragging mutates `document` continuously during gesture updates, causing broad SwiftUI invalidation.
3. Browser rendering depends on one large observed view model, so transient interaction state invalidates too much UI.
4. Hot paths repeatedly sort cards and scan arrays for cards, links, and labels.
5. Media preview loading and drawing preview overlays add extra work on the main thread.
6. There is duplicate drawing work in some background/grid paths.
7. Small recurring costs such as responder churn and timestamp generation accumulate during hot interactions.

## Scope and Assumptions

- Focus first on Browser interaction smoothness: pan, zoom, single-card drag, multi-card drag, and overview rendering.
- Preserve existing Browser features before pursuing cosmetic simplifications.
- Execute optimizations in dependency order so measurement remains meaningful.
- Re-open and check this file before each major implementation step.

## Implementation Phases

### Phase 0: Measurement Baseline

- [x] Define repeatable profiling scenarios for pan, zoom, single-card drag, multi-card drag, overview enabled/disabled, media-heavy cards, and drawing-heavy cards.
- [x] Add lightweight measurement points for Browser hot paths such as visible card calculation, visible link calculation, overview bounds calculation, and drag update processing.
- [x] Observe which Browser views are re-evaluated during viewport, hover, drag, and overview updates.
- [x] Record pre-optimization baseline behavior so each later phase can be compared against it.

### Phase 1: Highest-Impact Overview and Drag Fixes

- [x] Cache overview/minimap render data instead of recomputing document bounds for every overview point.
- [x] Precompute overview card points and link endpoints from a single overview snapshot.
- [x] Reuse the same overview snapshot when computing the overview viewport rectangle.
- [x] Verify early that disabling overview materially changes frame rate so overview work remains a confirmed top-priority target.
- [x] Keep card drag movement in transient state and commit to `document` only when the drag ends.
- [x] Avoid per-tick timestamp work during dragging.
- [x] Ensure multi-selection drag uses shared transient movement rather than mutating every selected card continuously.

### Phase 2: Browser Interaction State Restructuring

- [x] Separate transient Browser interaction state from persistent document state wherever possible.
- [x] Keep pan and zoom updates lightweight and isolated from unrelated Browser rendering work.
- [x] Ensure drag state, marquee state, hover state, and inline-editor overlay state do not trigger broader document-derived recomputation than necessary.
- [x] Preserve current interaction semantics while changing the update model.

### Phase 3: SwiftUI Invalidation Scope Reduction

- [x] Shrink Browser invalidation scope by separating render data from broad view-model observation where possible.
- [x] Reduce the amount of Browser UI that directly depends on the full workspace view model.
- [x] Isolate overview rendering from the main Browser render tree as much as practical.
- [x] Reduce hover-driven redraw cost so a hover change does not cascade through more card views than necessary.
- [x] Keep inline editor overlay updates isolated from core card and link rendering when possible.

### Phase 4: Document Lookup and Hot-Path Data Access Optimization

- [x] Replace repeated full sorting of cards in Browser hot paths with cheaper access patterns.
- [x] Add cheap card lookup by ID for Browser rendering and link calculations.
- [x] Add cheaper per-card link lookup or link-count access for Browser UI.
- [x] Cache or centralize label lookup so Browser rendering does not repeatedly rebuild label dictionaries.
- [x] Reuse these faster access paths consistently across overview, visibility filtering, hit testing, and link rendering.

### Phase 5: Per-Card Render Metadata Caching

- [x] Reuse cached per-card layout/render metadata instead of recomputing size, summary, label state, badge state, and line counts repeatedly.
- [x] Ensure visible-card filtering can use cached card size/layout information.
- [x] Combine related card-derived UI values so they are computed together instead of in separate passes.
- [x] Keep cache invalidation tied to actual card content changes.

### Phase 6: Link Rendering Pipeline Optimization

- [x] Precompute visible link render geometry once instead of recomputing endpoints for path, arrow, and label separately.
- [x] Reduce repeated card lookup while filtering and drawing links.
- [x] Keep link label positioning tied to precomputed geometry rather than recalculating it in separate drawing helpers.
- [x] Maintain current link appearance and interaction behavior while reducing computation cost.

### Phase 7: Media and Drawing Preview Optimization

- [x] Move media preview work toward thumbnail-oriented caching rather than full-size synchronous image loading for Browser previews.
- [x] Separate preview-oriented media caching from generic full-image caching when useful.
- [x] Reduce drawing-preview recomputation by caching derived geometry or renderable preview data.
- [x] Revisit whether small Browser drawing previews should stay vector-based or shift to cached raster previews when that is cheaper.
- [x] Validate that content-heavy cards no longer dominate interaction cost.

### Phase 8: Residual Overhead Cleanup and Final Tuning

- [x] Remove smaller recurring overheads such as duplicated grid drawing when practical.
- [x] Reduce unnecessary responder or focus churn in Browser infrastructure.
- [x] Reduce repeated formatter/timestamp overhead in hot interaction paths.
- [x] Do final tuning after major hotspots are fixed so remaining work is guided by updated measurements.

## Recommended Execution Order

1. Phase 0: establish baseline and visibility into hot paths.
2. Phase 1: fix overview/minimap recomputation and drag-time document mutation first.
3. Phase 2: restructure transient Browser state around the new interaction model.
4. Phase 3 and Phase 4: reduce invalidation scope and data-access cost.
5. Phase 5 and Phase 6: cache card and link render metadata.
6. Phase 7: optimize media and drawing previews.
7. Phase 8: clean up smaller recurring overheads and tune final performance.

## Verification Criteria

- [x] Browser behavior with overview enabled is substantially closer to overview-disabled performance than before.
- [x] Panning remains responsive without visible 1fps-style stutter.
- [x] Zooming remains responsive and preserves existing zoom behavior.
- [x] Single-card dragging remains smooth and updates final document position correctly.
- [x] Multi-card dragging remains smooth and commits positions correctly on gesture end.
- [x] Marquee selection still works correctly after transient interaction changes.
- [x] Link preview still appears and updates correctly during link creation.
- [x] Overview recenter interaction still works correctly.
- [x] Fit and zoom-to-selection behaviors still work correctly.
- [x] Visible card counts and visible link counts remain logically correct after lookup and caching changes.
- [x] Browser hit testing still selects the expected cards.
- [x] Inline Browser editor still opens and positions correctly.
- [x] Card visuals, including media badges, drawing previews, and link-related status, remain functionally correct.
- [x] Media-heavy documents no longer cause severe first-view interaction stalls relative to baseline.
- [x] Drawing-heavy cards no longer dominate Browser interaction cost relative to baseline.
- [x] `swift build` succeeds in `macos/`.
- [x] `swift test` succeeds in `macos/`.
- [x] No user-visible Browser regression is introduced while improving performance.

## Execution Notes

- Start with the overview snapshot/cache work and drag transient-state work, since they are the highest-priority fixes.
- Do not skip baseline comparison when a major phase is completed.
- Re-open this file before each major implementation step to stay aligned with the plan.

