# Magnifier Lens Panel Design

Date: 2026-07-25 (updated 2026-08-03)
Status: Implemented and verified on branch `feat_idle-magnifier-color-picker`
Project: capcap

## Summary

Add a magnifier color picker (lens) to the screenshot overlay. When the user has triggered an overlay session, the cursor is followed by a configurable panel that shows the current pixel coordinates, RGB/HEX value, and a magnified view of the area around the cursor. The lens is visible in three states: (1) idle (before any selection), (2) during drag-to-select, and (3) while resizing or moving an existing selection rectangle. The user can press `⌘+C` to copy the currently displayed value, or `Shift` (single tap) to toggle between HEX and RGB display. Clicking the cursor still triggers the existing window-selection capture. Pressing `Esc` cancels as before. The lens replaces the legacy "drag to screenshot" cursor chip while the overlay is active.

The magnifier is **always enabled** during screenshot selection — there is no user-facing toggle. When the user triggers a capture, the cursor immediately switches to the standard crosshair, and the magnifier panel follows the cursor showing coordinates and color values. The magnifier automatically follows the system appearance (light/dark mode) and uses sensible built-in defaults for its size, position, and visual styling. No magnifier-related settings appear in the Settings window.

## Goals

- Provide a Cmd+Shift+4-style color picker experience inside capcap's overlay without adding a separate modal.
- Read pixel values from the already-captured `backgroundSnapshot` to avoid extra permissions or screen-capture latency.
- Replace the "drag to screenshot" cursor chip in the idle state so users see useful information instead of a static hint.
- Preserve existing behaviors: click-on-window capture, drag-to-select, Esc-cancel.
- Keep the lens alive during drag-to-select (so the user can see magnification at the drag endpoint for precise selection).
- Show the lens while resizing or moving an existing selection rectangle via its adjustment handles.
- Stay in sync with the existing `ColorPickerRunner` history behavior so picking colors updates `HistoryManager` and `Defaults.lastPickedColorHex` (gated by `Defaults.historyCacheEnabled`).

## Non-Goals

- Not adding a pinned-color or "lock" feature (Cmd+L analogue of macOS Digital Color Meter).
- Not changing the global color picker hotkey or `ColorPickerRunner`.
- Not introducing new permissions or new background-capture paths.
- Not changing `SelectionView` mouse handling beyond calling `selectionDidStart()` for resize/move paths to keep the lens alive.
- Not refactoring `OverlayWindowController.activate()` signature.
- Not promoting the overlay panel to a key window — the app activates via `NSApp.activate(ignoringOtherApps: true)` when capture begins (required for the crosshair cursor to take effect), then the previous app is restored by `SourceAppFocusRestorer` when the capture session ends.

## User Flow

1. User triggers screenshot via cmd+cmd (or any configured screenshot hotkey, or countdown shortcut).
2. `OverlayWindowController` presents the overlay. The cursor switches to the standard crosshair immediately (via `NSCursor.crosshair.push()` + `NSApp.activate`). A `MagnifierLensPanelWindow` is created and replaces the "drag to screenshot" cursor chip.
3. Mouse moves: lens position follows the cursor; the magnified area, coordinates, and HEX/RGB value update live.
4. `Shift` (single tap, no other modifiers): toggles between HEX and RGB display. The new state persists for the current session and resets to HEX on the next overlay activation.
5. `⌘+C`: copies the currently displayed value (HEX → `#RRGGBB`, RGB → `rgb(r, g, b)`) to the clipboard, shows the existing `L10n.colorCopied` toast, and updates `HistoryManager` + `Defaults.lastPickedColorHex` if `Defaults.historyCacheEnabled` is true. The ratio row and the optional tip rows (`Press ⌘+C…` and `Press Shift…`) remain visible for the entire overlay session — they do not fade out.
6. `R`: cycles the fixed aspect-ratio mode through the same path as the legacy cursor chip. The lens ratio row updates immediately so replacing the chip does not hide ratio state.
7. Click without drag: still triggers window-selection capture (existing behavior). The lens does not consume the click.
8. Mouse down + drag: lens stays visible while the user draws the selection rectangle, then dismisses when selection completes.
9. `Esc`: cancels the overlay session; lens dismisses with the rest.
10. Closing the overlay: lens is released via the standard `tearDown` path.

## Lens UI

Panel size: **fixed** — 220 × 258 points (144 pt magnified area + info rows). The lens is a borderless `NSPanel` (similar to `CursorChipWindow`), drawn at `level = .screenSaver + 1`, ignoring mouse events, with `sharingType = .none` so ScreenCaptureKit excludes it from frozen-desktop snapshots. Its background appearance automatically follows the system light/dark mode.

### Smart positioning

The panel **defaults to directly below the cursor** (panel top edge sits at `cursor.y - 14`). Two edge-flip rules handle overflow:

- Right edge would exceed screen → flip to the left side of the cursor.
- Bottom edge would fall below the screen bottom → flip above the cursor.

When the cursor is near the top of the screen, the panel still appears below it (no clipping). Only when the cursor approaches the bottom edge does the panel flip up.

### Layout

```
+----------------------------+
| [magnified 36×36 @ 4×]     |   <- 144 x 144 area, pixelated
+----------------------------+
| Coordinates: x, y          |
| [##] HEX: #RRGGBB          |   <- 16x16 swatch + HEX or RGB label
| Press ⌘+C to copy color    |   <- always visible (no fade-out)
| Press Shift to switch RGB  |   <- always visible (no fade-out)
+----------------------------+
```

The two tip rows are **permanent** — they do not fade out after appearance. Removing the tips-fade-out logic was a follow-up revision after user feedback.

### Magnified area rendering

The 36×36 source region centered on the cursor is extracted via `CGImage.cropping(to:)` and magnified 4× into the 144-point destination rect. The cropped `CGImage` is drawn directly into the destination rect with `CGContext.draw(cropped, in: rect)`. `CGContext.draw` already maps the image's visual top-left to the destination rect's visual top-left, so **no manual y-flip transform is required** — adding one (`scaleBy(_, -scaleY)`) inverts the image and breaks pixel alignment.

When the cursor approaches a screen edge and the 36×36 source region would extend beyond the snapshot bounds, the crop is clamped to the valid pixel range. The draw rect is adjusted so the out-of-bounds portion appears as the dimmed background fill while the valid pixels stay correctly positioned. A `context.clip(to: rect)` call prevents the crop from bleeding outside the magnified area.

### Crosshair

Two layers ensure the centre is always visible:
- A **6 pt wide cross** in `#A8BDFC` at 65% alpha spans the full magnified area. This provides a strong background presence even on pure-white source pixels.
- A **1 px fine white cross** at the exact centre marks the sampled pixel precisely.

The crosshair at `destRect.midX / destRect.midY` is guaranteed to align with the sampled pixel.

Earlier iterations tried two approaches that did **not** work and have been removed:

- `NSImage.draw(in:from:)` with `fromRect` in CGImage y-down coords — rendered the magnified area with an unpredictable vertical offset depending on the view's flipped state.
- `context.clip(to: rect)` + `translateBy / scaleBy` chain — `CGContext.clip` operates in the current (transformed) coord system, so the clip ended up in the wrong place and the snapshot draw was discarded entirely.

## Interaction

| Input | Idle + lens visible | Drawing (state == .drawing) | Selected (state == .selected) |
| --- | --- | --- | --- |
| Mouse move | Updates lens content | Updates lens content | Updates lens content |
| Click (no drag) | Window-selection capture (unchanged) | — | — |
| Drag | Lens stays visible, selection starts | Lens stays visible, selection updates | Move/resize selection (lens visible) |
| `⌘+C` | Copy current format; toast; history | Copy current format; toast; history | Copy current format; toast; history |
| `Shift` | Toggle HEX ↔ RGB for this session | Toggle HEX ↔ RGB for this session | Toggle HEX ↔ RGB for this session |
| `Esc` | Cancel overlay | Cancel overlay | Cancel overlay |

### Event routing — global + local monitors

The overlay panel is `.nonactivatingPanel`, so keyboard events routed to the foreground app never enter capcap's process. A pure local monitor would miss `⌘+C` and Shift entirely. The current implementation therefore installs both monitors:

- `magnifierLensPanelFlagsChangedLocalMonitor` and `magnifierLensPanelFlagsChangedGlobalMonitor` — mirror each other for Shift detection.
- `magnifierLensPanelKeyDownGlobalMonitor` — global `keyDown` monitor for `⌘+C`. The local `escLocalMonitor` also observes `⌘+C` when the event reaches capcap, but returns the event after copying so it does not consume the normal key path.

Both handlers gate on `guard magnifierLensPanelActive else { return }`, so they never react when the lens is dismissed (e.g., once the user starts a selection or the overlay ends).

Global monitors only observe — they cannot prevent the foreground app from receiving `⌘+C`. Users should expect the foreground app's normal `⌘+C` behavior to still happen in parallel with the color copy.

## Multi-Monitor & Coordinates

- Coordinates displayed: **absolute desktop coordinates** (AppKit `NSEvent.mouseLocation`), integer. May be negative when the active screen sits left of the main display.
- **Points vs Pixels**: `Defaults.magnifierLensPanelCoordinateMode` (`.points` default / `.pixels`) controls whether the lens shows AppKit logical-point coordinates or CGImage physical-pixel coordinates. On Retina displays, 1 point = 2 pixels, so the numbers differ. The mode is set via a popup in Settings and takes effect immediately when the lens is next refreshed — no runtime toggle.
- `OverlayWindowController` caches `screenFramesByDisplayID: [CGDirectDisplayID: NSRect]` at activation time, mapping the AppKit frame of each screen.
- The lens picks the screen containing `mouseLocation` by linear scan over `screenFramesByDisplayID`; uses the corresponding `CGImage` from `screenSnapshots`.
- **Edge-boundary fix**: `CGRect.contains` uses a half-open `[min, max)` interval — a cursor at the absolute top edge (`y == frame.maxY`) is treated as outside. The screen-detection guard was replaced with an inclusive `min <= x <= max && min <= y <= max` check so the lens resolves a snapshot at all screen edges.
- The `MagnifierLensPanelSampler.pixelCoordinate` helper applies the screen's point-to-pixel scale (handles Retina correctly) and clamps the result to the valid pixel range so cursor-on-edge still resolves to a sample instead of returning `nil`.
- The single-pixel `MagnifierLensPanelSampler.sample` helper uses a 1×1 `CGContext` with nearest-neighbour interpolation disabled and integer-aligned `drawRect` math so the target pixel exactly covers the output pixel without blending with adjacent rows, columns, or transparent edges.
- When `ScreenCaptureKit` delivers a display snapshot after the lens is already visible, `OverlayWindowController` refreshes the lens immediately so the initial panel does not stay blank until the next mouse event.

## Settings

The magnifier has **no user-facing settings**. Its size, position, visual styling, and behavior are all driven by sensible built-in defaults:

- Magnified area: 144 × 144 points (36 × 36 source pixels at 4× magnification).
- Panel offset: 15 points right, 14 points below the cursor (with smart edge flipping).
- Appearance: automatically follows the system light/dark mode. Dark background defaults to black at 70% alpha; light background defaults to white at 80% alpha.
- Crosshair: 6 pt wide cross in `#A8BDFC` at 65% alpha, with a 1 px white centre cross.
- Hint rows: coordinate label, color swatch + value, `Press ⌘+C to copy color`, `Press Shift to switch RGB`, and aspect-ratio prompt are all always visible.

These defaults are stored on `Defaults` but are not exposed in the Settings window. The entire magnifier section (toggle, size picker, appearance controls, preview, etc.) has been removed from Settings.

## Localization

New L10n keys (added to all 8 `.lproj/Localizable.strings`):

| Key | en | zh-Hans |
| --- | --- | --- |
| `magnifierLensPanelCoordinates` | `Coordinates: %@, %@` | `坐标: %@, %@` |
| `magnifierLensPanelHex` | `HEX: %@` | `HEX: %@` |
| `magnifierLensPanelRgb` | `RGB: %@` | `RGB: %@` |
| `magnifierLensPanelRgbString` | `rgb(%d, %d, %d)` | `rgb(%d, %d, %d)` |
| `magnifierLensPanelCopyHint` | `Press ⌘+C to copy color` | `按 ⌘+C 复制颜色` |
| `magnifierLensPanelShiftHint` | `Press Shift to switch RGB` | `按 Shift 切换 RGB` |
| `magnifierLensPanelAspectFree` | `Free` | `自由` |
| `magnifierLensPanelAspectHint` | `Press R to switch ratio: %@` | `按 R 切换比例: %@` |

All translations follow the project rule: **no trailing punctuation** on user-facing strings.

## Files Touched

### New

- `capcap/UI/MagnifierLensPanelWindow.swift` — `NSPanel` subclass plus `MagnifierLensPanelView` (drawing, magnification, swatch, layout) and the pure `MagnifierLensPanelSampler` enum for pixel-coordinate mapping, single-pixel sampling, and background-colour selection (`backgroundColor(forAppearance:)`, `darkBackgroundColor()`, `lightBackgroundColor()`).
- `Tests/capcapTests/MagnifierLensPanelTests.swift` — Unit tests covering `pixelCoordinate` mapping (including offset-screen cases), single-pixel sampling, Y-axis orientation, clamp-to-bounds, all new `Defaults` defaults, and alpha-setter clamping.
- `docs/spark/2026-07-25-magnifier-lens-panel-design.md` — This document.

### Modified

- `capcap/Capture/OverlayWindowController.swift` — Owns the lens lifecycle, mouse-tracking (`.mouseMoved` + `.leftMouseDragged`), and `Shift` / `⌘+C` routing via local + global monitors. `refreshMagnifierLensPanelContent` uses inclusive edge-boundary screen detection. `setupMagnifierLensPanel` guards against duplicates. `selectionDidStart` recreates the lens if it was dismissed by a previous `selectionDidComplete` (for resize/move handle drags). Calls `NSApp.activate(ignoringOtherApps: true)` in `presentOverlay` capture branch so the crosshair cursor and lens cursor rects take effect.
- `capcap/Utilities/Defaults.swift` — Adds magnifier lens panel defaults (size, offset, appearance, crosshair, hints, coordinate mode).
- `capcap/Capture/SelectionView.swift` — Calls `delegate?.selectionDidStart()` for `.resize` and `.move` drag-action paths so the lens stays visible while adjusting an existing selection. Added `resetCursorRects` override with crosshair cursor rect and `refreshCursorRects()` for WindowServer cursor-rect evaluation.
- `Resources/*.lproj/Localizable.strings` × 8 — Adds the lens-related keys (`magnifierLensPanel*`).

### Removed

- `capcap/Settings/MagnifierPreviewView.swift` — The Settings preview view is no longer used since the magnifier section has been removed from Settings.

## Verification

- `bash scripts/compile-check.sh` — passes (0 errors).
- `swift test --filter OverlayPresentationTests` — all 16 tests pass, including crosshair cursor assertions.
- Manual runtime verification:
  - cmd+cmd activates the overlay; cursor switches to crosshair immediately regardless of which app is frontmost.
  - Magnifier lens replaces the "drag to screenshot" chip and follows the cursor.
  - Cursor moves update the magnified area, coordinates, and HEX value live.
  - Ratio row stays visible and updates when R cycles free / fixed aspect modes.
  - Tip rows stay visible for the entire idle session.
  - ⌘+C copies the currently shown format; toast and clipboard confirm.
  - Single-tap Shift toggles HEX ↔ RGB; next cmd+cmd session resets to HEX.
  - Drag starts a selection — lens stays visible and tracks the drag endpoint.
  - Resizing or moving an existing selection via handles — lens stays visible.
  - Multi-monitor: cursor on a secondary screen left of the main display reports negative coordinates and samples the correct screen's snapshot.
  - Edge cases: panel flips left when cursor near right edge; flips up when cursor near bottom edge.
  - Settings window: no magnifier-related settings visible.
  - Lens background automatically matches system light/dark mode.
  - Focus is restored to the previous frontmost app when the capture session ends.

## Out of Scope

- A pinned-color or sampling-lock feature (Cmd+L analogue of macOS Digital Color Meter).
- Re-skinning or replacing the existing `ColorPickerRunner` modal.
- A new shortcut slot — the lens only surfaces the existing `R` aspect-ratio shortcut and claims `Shift` / `⌘+C` for lens-specific actions.
- Making the overlay panel a key window to fully intercept `⌘+C` from the foreground app. The current design uses global monitors (observe-only), accepting that the foreground app still receives `⌘+C` in parallel.
- User-facing magnifier settings (toggle, size, appearance, hints) — all removed in favour of built-in defaults.

## Iteration Log

- v1 — initial implementation: panel 240×192, magnified 96×96 (8×8 source @ 12×), tips fade after 1.8s, panel positioned at cursor + (15, −40) (which straddled the cursor and clipped near the top edge).
- v2 — panel enlarged to 256×240, magnified area 144×144 (12×12 source @ 12×), tips made permanent, smart positioning (default below cursor with right + bottom edge flips), pixel-coordinate edge clamp.
- v3 — magnification rendering replaced `NSImage.draw(in:from:)` with `CGContext.draw(snapshot, in:)` after a negative-y-scale transform — turned out to flip the image. Replaced again with `CGImage.cropping(to:)` + plain `CGContext.draw` (no transforms), which renders right-side up with the cursor pixel at `destRect.mid`.
- v4 — single-pixel `sample` helper Y-flip fixed (added explicit `0.5 + py − imageHeight` term to `drawRect.y`); added `testSampleRespectsYAxisOrientation` to catch future regressions.
- v5 — `⌘+C` and Shift added `global` monitors in addition to the existing local ones, because the `.nonactivatingPanel` overlay never receives key events targeted at the foreground app.
- v6 — configurable Settings card: dedicated card replacing the single-line toggle, with magnified area size picker (96/144/192), magnification factor, panel offset fields, dark/light background RGBA with follow-system-appearance toggle, hint visibility toggles, live `MagnifierPreviewView`.
- v7 — lens stays visible during drag-to-select (`.leftMouseDragged` added to mouse monitors, `selectionDidStart` no longer dismisses). Enhanced crosshair: 10 px `#A5BAF9` cross behind 1 px white cross. Boundary crop clamping + `context.clip(to: rect)` when source region extends beyond snapshot bounds.
- v8 — **ghost lens fix**: `sharingType = .none` on `MagnifierLensPanelWindow` prevents `SCScreenshotManager.captureImage` from including the lens in the background snapshot (was causing a frozen duplicate on first activation). `hasShadow = false`. `setupMagnifierLensPanel` adds `guard magnifierLensPanel == nil` duplicate prevention.
- v9 — **top-edge pixel fix**: `CGRect.contains` replaced with inclusive boundary check (`min <= x <= max`) in `refreshMagnifierLensPanelContent` because the half-open `[min, max)` interval excluded cursor positions at the absolute edge.
- v10 — **lens during selection adjustment**: `SelectionView.mouseDown` calls `selectionDidStart()` for `.resize` and `.move` paths; `selectionDidStart` recreates the lens if it was dismissed by a previous `selectionDidComplete`. Lens now visible while dragging resize handles or moving an existing selection.
- v11 — **Points/Pixels coordinate mode**: `Defaults.MagnifierLensPanelCoordinateMode` enum (`.points`/`.pixels`), Settings popup, L10n keys in 8 languages. `drawInfo` switches between `mouseLocation` (points) and `currentPixelPoint` (pixels) based on the setting.
- v12 — **default flipped to enabled**: `Defaults.magnifierLensPanelEnabled` flipped from `false` to `true` so new users see the magnifier lens by default instead of the legacy "drag to screenshot" chip. Existing users who prefer the old behavior can disable the toggle in **Settings → General → Show magnifier while selecting**. Documentation updated to reflect the new default (Summary + Settings + Configurable Options table).
- v13 — **MagnifierLensPanel rename**: Swift types, Defaults keys, L10n keys, tests, and docs were renamed from the earlier idle-color-lens terminology to the `MagnifierLensPanel` naming used by the Settings panel.
- v14 — **review hardening**: single-pixel sampling now disables interpolation and uses integer alignment, panel screen lookup uses inclusive edge bounds, snapshot arrival refreshes an already visible panel, local `⌘+C` copy no longer consumes the event, color defaults clamp RGB/alpha components, magnified size normalizes to supported choices, unused Settings state/resources were removed, and docs were brought back in sync.
- v15 — **aspect-ratio prompt parity**: the lens now renders a `Press R to switch ratio: ...` row backed by the same persisted aspect-ratio state as the legacy cursor chip, and pressing `R` redraws the lens immediately so the fixed-ratio shortcut remains discoverable.
- v16 — **always-on + settings removal + crosshair fix**: magnifier is now always enabled during capture (no toggle). The entire magnifier section (toggle, size picker, appearance controls, crosshair styling, hints, live preview) removed from Settings. Lens size/position/appearance use hardcoded sensible defaults. Crosshair cursor now appears immediately on capture start regardless of which app is frontmost (`NSApp.activate(ignoringOtherApps: true)` in `presentOverlay`). `SelectionView` added `resetCursorRects` override with crosshair cursor rect as supporting infrastructure. Focus restored to previous app when capture ends via `SourceAppFocusRestorer`.
- v17 — **legacy toggle cleanup**: removed the retired `Defaults.magnifierLensPanelEnabled` runtime gate so users who disabled the former Settings toggle still receive the always-on magnifier after upgrading. The obsolete persisted key is intentionally ignored.
