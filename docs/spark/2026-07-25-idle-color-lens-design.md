# Idle Magnifier Color Picker Design

Date: 2026-07-25
Status: Implemented and verified on branch `feat_idle-magnifier-color-picker`
Project: capcap

## Summary

Add a magnifier color picker (lens) to the screenshot overlay's idle state. When the user has triggered an overlay session but has not yet started dragging a selection, the cursor is followed by a small panel that shows the current pixel coordinates, RGB/HEX value, and a magnified view of the area around the cursor. The user can press `⌘+C` to copy the currently displayed value, or `Shift` (single tap) to toggle between HEX and RGB display. Clicking the cursor still triggers the existing window-selection capture. Pressing `Esc` cancels as before. The lens replaces the legacy "drag to screenshot" cursor chip while the overlay is in the idle state.

The feature is opt-in via a new `Defaults.idleColorLensEnabled` toggle (default `false` so existing users keep the legacy "drag to screenshot" chip until they explicitly enable the lens) and reuses the existing `backgroundSnapshot` for pixel sampling, so no new screen-capture permission is required.

## Goals

- Provide a Cmd+Shift+4-style color picker experience inside capcap's overlay without adding a separate modal.
- Read pixel values from the already-captured `backgroundSnapshot` to avoid extra permissions or screen-capture latency.
- Replace the "drag to screenshot" cursor chip in the idle state so users see useful information instead of a static hint.
- Preserve existing behaviors: click-on-window capture, drag-to-select, Esc-cancel.
- Stay in sync with the existing `ColorPickerRunner` history behavior so picking colors updates `HistoryManager` and `Defaults.lastPickedColorHex` (gated by `Defaults.historyCacheEnabled`).

## Non-Goals

- Not adding a pinned-color or "lock" feature (Cmd+L analogue of macOS Digital Color Meter).
- Not changing the global color picker hotkey or `ColorPickerRunner`.
- Not introducing new permissions or new background-capture paths.
- Not changing `SelectionView` mouse handling, only reading its existing `backgroundSnapshot` CGImage.
- Not refactoring `OverlayWindowController.activate()` signature.
- Not promoting the overlay panel to a key window — events are observed via global monitors instead so the foreground app keeps focus.

## User Flow

1. User triggers screenshot via cmd+cmd (or any configured screenshot hotkey, or countdown shortcut).
2. `OverlayWindowController` presents the overlay. If `presetImage == nil` and `Defaults.idleColorLensEnabled` is true, an `IdleColorLensWindow` is created and replaces the "drag to screenshot" cursor chip.
3. Mouse moves: lens position follows the cursor; the magnified area, coordinates, and HEX/RGB value update live.
4. `Shift` (single tap, no other modifiers): toggles between HEX and RGB display. The new state persists for the current session and resets to HEX on the next overlay activation.
5. `⌘+C` (in idle state only): copies the currently displayed value (HEX → `#RRGGBB`, RGB → `rgb(r, g, b)`) to the clipboard, shows the existing `L10n.colorCopied` toast, and updates `HistoryManager` + `Defaults.lastPickedColorHex` if `Defaults.historyCacheEnabled` is true. The two tip rows (`Press ⌘+C…` and `Press Shift…`) remain visible for the entire idle session — they do not fade out.
6. Click without drag: still triggers window-selection capture (existing behavior). The lens does not consume the click.
7. Mouse down + drag: lens hides immediately, normal selection drawing begins.
8. `Esc`: cancels the overlay session; lens dismisses with the rest.
9. Closing the overlay: lens is released via the standard `tearDown` path.

## Lens UI

Panel size: **256 × 240 points**. The lens is a borderless `NSPanel` (similar to `CursorChipWindow`), drawn at `level = .screenSaver + 1`, ignoring mouse events.

### Smart positioning

The panel **defaults to directly below the cursor** (panel top edge sits at `cursor.y - offsetY`, where `offsetY = 14`). Two edge-flip rules handle overflow:

- Right edge would exceed screen → flip to the left side of the cursor.
- Bottom edge would fall below the screen bottom → flip above the cursor.

When the cursor is near the top of the screen, the panel still appears below it (no clipping). Only when the cursor approaches the bottom edge does the panel flip up.

### Layout

```
+----------------------------+
| [magnified 12×12 @ 12×]    |   <- 144 x 144 area, pixelated
+----------------------------+
| Coordinates: x, y          |
| [##] HEX: #RRGGBB          |   <- 16x16 swatch + HEX or RGB label
| Press ⌘+C to copy color    |   <- always visible (no fade-out)
| Press Shift to switch RGB  |   <- always visible (no fade-out)
+----------------------------+
```

The two tip rows are **permanent** — they do not fade out after appearance. Removing the tips-fade-out logic was a follow-up revision after user feedback.

### Magnified area rendering

The 12×12 source region centered on the cursor is extracted via `CGImage.cropping(to:)`. The cropped `CGImage` is drawn directly into the destination rect with `CGContext.draw(cropped, in: rect)`. `CGContext.draw` already maps the image's visual top-left to the destination rect's visual top-left, so **no manual y-flip transform is required** — adding one (`scaleBy(_, -scaleY)`) inverts the image and breaks pixel alignment. The crosshair at `destRect.midX / destRect.midY` is guaranteed to align with the sampled pixel.

Earlier iterations tried two approaches that did **not** work and have been removed:

- `NSImage.draw(in:from:)` with `fromRect` in CGImage y-down coords — rendered the magnified area with an unpredictable vertical offset depending on the view's flipped state.
- `context.clip(to: rect)` + `translateBy / scaleBy` chain — `CGContext.clip` operates in the current (transformed) coord system, so the clip ended up in the wrong place and the snapshot draw was discarded entirely.

## Interaction

| Input | Idle + lens visible | Drawing (state == .drawing) | Selected (state == .selected) |
| --- | --- | --- | --- |
| Mouse move | Updates lens content | (lens hidden) | (lens hidden) |
| Click (no drag) | Window-selection capture (unchanged) | — | — |
| Drag | Lens hides, selection starts | Selection updates | Move/resize selection |
| `⌘+C` | Copy current format; toast; history | (no effect) | (no effect) |
| `Shift` | Toggle HEX ↔ RGB for this session | (no effect) | (no effect) |
| `Esc` | Cancel overlay | Cancel overlay | Cancel overlay |

### Event routing — global + local monitors

The overlay panel is `.nonactivatingPanel`, so keyboard events routed to the foreground app never enter capcap's process. A pure local monitor would miss `⌘+C` and Shift entirely. The current implementation therefore installs both monitors:

- `idleLensFlagsChangedLocalMonitor` and `idleLensFlagsChangedGlobalMonitor` — mirror each other for Shift detection.
- `idleLensKeyDownGlobalMonitor` — global `keyDown` monitor for `⌘+C`. The local `escLocalMonitor` also handles `⌘+C` but typically does not fire because the event is delivered to the foreground app.

Both handlers gate on `guard idleColorLensActive else { return }`, so they never react when the lens is dismissed (e.g., once the user starts a selection or the overlay ends).

Global monitors only observe — they cannot prevent the foreground app from receiving `⌘+C`. Users should expect the foreground app's normal `⌘+C` behavior to still happen in parallel with the color copy.

## Multi-Monitor & Coordinates

- Coordinates displayed: **absolute desktop coordinates** (AppKit `NSEvent.mouseLocation`), integer. May be negative when the active screen sits left of the main display.
- `OverlayWindowController` caches `screenFramesByDisplayID: [CGDirectDisplayID: NSRect]` at activation time, mapping the AppKit frame of each screen.
- The lens picks the screen containing `mouseLocation` by linear scan over `screenFramesByDisplayID`; uses the corresponding `CGImage` from `screenSnapshots`.
- The `IdleColorLensSampler.pixelCoordinate` helper applies the screen's point-to-pixel scale (handles Retina correctly) and clamps the result to the valid pixel range so cursor-on-edge still resolves to a sample instead of returning `nil`.
- The single-pixel `IdleColorLensSampler.sample` helper uses a 1×1 `CGContext` with explicit `drawRect` math (subtract image dimensions, then add 0.5 for half-pixel centering) so the target pixel lands on the context's pixel center and the Y axis is correct on the first try.

## Settings

New `Defaults.idleColorLensEnabled: Bool` (default `false`).

- When `true`: `OverlayWindowController` creates the lens instead of the `dragToScreenshot` cursor chip in idle.
- When `false` (default): legacy `CursorChipWindow` chip with `L10n.dragToScreenshot` text is shown.

SettingsView adds the toggle row inside the existing **General → Toggles** card, placed after the `pinAcrossSpaces` row. The Toggles card is the first thing visible in General, so users can find the lens switch without digging into the Shortcuts tab.

```
Show color lens on idle       [ON/OFF]   ← inside General → Toggles
Display a magnifier with RGB/HEX readout next to the cursor before drawing
```

## Localization

New L10n keys (added to all 8 `.lproj/Localizable.strings`):

| Key | en | zh-Hans |
| --- | --- | --- |
| `idleLensCoordinates` | `Coordinates: %@, %@` | `坐标: %@, %@` |
| `idleLensHex` | `HEX: %@` | `HEX: %@` |
| `idleLensRgb` | `RGB: %@` | `RGB: %@` |
| `idleLensRgbString` | `rgb(%d, %d, %d)` | `rgb(%d, %d, %d)` |
| `idleLensCopyHint` | `Press ⌘+C to copy color` | `按 ⌘+C 复制颜色` |
| `idleLensShiftHint` | `Press Shift to switch RGB` | `按 Shift 切换 RGB` |
| `settingsIdleColorLensTitle` | `Show color lens on idle` | `空闲态显示放大镜取色` |
| `settingsIdleColorLensHint` | `Display a magnifier with RGB/HEX readout next to the cursor before drawing` | `绘制前在光标旁显示带 RGB/HEX 的放大镜` |

All translations follow the project rule: **no trailing punctuation** on user-facing strings.

## Files Touched

### New

- `capcap/UI/IdleColorLensWindow.swift` — `NSPanel` subclass plus `IdleColorLensView` (drawing, magnification, swatch, layout) and the pure `IdleColorLensSampler` enum for pixel-coordinate mapping and single-pixel sampling.
- `Tests/capcapTests/IdleColorLensTests.swift` — Unit tests covering `pixelCoordinate` mapping (including offset-screen cases), single-pixel sampling, Y-axis orientation (each row painted a distinct color so a flipped sample fails), clamp-to-bounds, and `Defaults.idleColorLensEnabled` default.
- `docs/spark/2026-07-25-idle-color-lens-design.md` — This document.

### Modified

- `capcap/Capture/OverlayWindowController.swift` — Owns the lens lifecycle, mouse-tracking, and `Shift` / `⌘+C` routing via local + global monitors.
- `capcap/Utilities/Defaults.swift` — Adds `idleColorLensEnabled` and the 8 new L10n accessors.
- `capcap/Settings/SettingsView.swift` — Adds the toggle row in the capture-behavior section.
- `Resources/*.lproj/Localizable.strings` × 8 — Adds the 8 lens-related keys.

## Verification

- `bash scripts/compile-check.sh` — passes (0 errors) on every iteration of the design.
- Manual runtime verification performed on `feat_idle-magnifier-color-picker`:
  - cmd+cmd activates the overlay; lens replaces the "drag to screenshot" chip.
  - Cursor moves update the magnified area, coordinates, and HEX value live.
  - Tip rows stay visible for the entire idle session.
  - ⌘+C copies the currently shown format; toast and clipboard confirm.
  - Single-tap Shift toggles HEX ↔ RGB; next cmd+cmd session resets to HEX.
  - Drag starts a selection — lens hides immediately.
  - Settings toggle hides the lens and restores the legacy chip.
  - Multi-monitor: cursor on a secondary screen left of the main display reports negative coordinates and samples the correct screen's snapshot.
  - Edge cases: panel flips left when the cursor is near the right edge; flips up when the cursor is near the bottom edge; defaults to below the cursor when the cursor is near the top.
- The unit tests in `IdleColorLensTests.swift` cover the pixel-coordinate math and the y-axis-correct sample path. Running them requires Xcode (the `XCTest` framework is not bundled with the available `xcode-select` command-line tools).

## Out of Scope

- A pinned-color or sampling-lock feature (Cmd+L analogue of macOS Digital Color Meter).
- Re-skinning or replacing the existing `ColorPickerRunner` modal.
- A new shortcut slot — only `Shift` and `⌘+C` are claimed inside the idle lens window.
- Making the overlay panel a key window to fully intercept `⌘+C` from the foreground app. The current design uses global monitors (observe-only), accepting that the foreground app still receives `⌘+C` in parallel.

## Iteration Log

- v1 — initial implementation: panel 240×192, magnified 96×96 (8×8 source @ 12×), tips fade after 1.8s, panel positioned at cursor + (15, −40) (which straddled the cursor and clipped near the top edge).
- v2 — panel enlarged to 256×240, magnified area 144×144 (12×12 source @ 12×), tips made permanent, smart positioning (default below cursor with right + bottom edge flips), pixel-coordinate edge clamp.
- v3 — magnification rendering replaced `NSImage.draw(in:from:)` with `CGContext.draw(snapshot, in:)` after a negative-y-scale transform — turned out to flip the image. Replaced again with `CGImage.cropping(to:)` + plain `CGContext.draw` (no transforms), which renders right-side up with the cursor pixel at `destRect.mid`.
- v4 — single-pixel `sample` helper Y-flip fixed (added explicit `0.5 + py − imageHeight` term to `drawRect.y`); added `testSampleRespectsYAxisOrientation` to catch future regressions.
- v5 — `⌘+C` and Shift added `global` monitors in addition to the existing local ones, because the `.nonactivatingPanel` overlay never receives key events targeted at the foreground app.