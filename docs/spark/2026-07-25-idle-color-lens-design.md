# Idle Magnifier Color Picker Design

Date: 2026-07-25 (updated 2026-07-27)
Status: Implemented and verified on branch `feat_idle-magnifier-color-picker`
Project: capcap

## Summary

Add a magnifier color picker (lens) to the screenshot overlay. When the user has triggered an overlay session, the cursor is followed by a configurable panel that shows the current pixel coordinates, RGB/HEX value, and a magnified view of the area around the cursor. The lens is visible in three states: (1) idle (before any selection), (2) during drag-to-select, and (3) while resizing or moving an existing selection rectangle. The user can press `⌘+C` to copy the currently displayed value, or `Shift` (single tap) to toggle between HEX and RGB display. Clicking the cursor still triggers the existing window-selection capture. Pressing `Esc` cancels as before. The lens replaces the legacy "drag to screenshot" cursor chip while the overlay is active.

The feature is opt-in via a `Defaults.idleColorLensEnabled` toggle (default `false` so existing users keep the legacy "drag to screenshot" chip until they explicitly enable the lens) and reuses the existing `backgroundSnapshot` for pixel sampling, so no new screen-capture permission is required.

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
- Not promoting the overlay panel to a key window — events are observed via global monitors instead so the foreground app keeps focus.

## User Flow

1. User triggers screenshot via cmd+cmd (or any configured screenshot hotkey, or countdown shortcut).
2. `OverlayWindowController` presents the overlay. If `presetImage == nil` and `Defaults.idleColorLensEnabled` is true, an `IdleColorLensWindow` is created and replaces the "drag to screenshot" cursor chip.
3. Mouse moves: lens position follows the cursor; the magnified area, coordinates, and HEX/RGB value update live.
4. `Shift` (single tap, no other modifiers): toggles between HEX and RGB display. The new state persists for the current session and resets to HEX on the next overlay activation.
5. `⌘+C`: copies the currently displayed value (HEX → `#RRGGBB`, RGB → `rgb(r, g, b)`) to the clipboard, shows the existing `L10n.colorCopied` toast, and updates `HistoryManager` + `Defaults.lastPickedColorHex` if `Defaults.historyCacheEnabled` is true. The two tip rows (`Press ⌘+C…` and `Press Shift…`) remain visible for the entire overlay session — they do not fade out.
6. Click without drag: still triggers window-selection capture (existing behavior). The lens does not consume the click.
7. Mouse down + drag: lens stays visible while the user draws the selection rectangle, then dismisses when selection completes.
8. `Esc`: cancels the overlay session; lens dismisses with the rest.
9. Closing the overlay: lens is released via the standard `tearDown` path.

## Lens UI

Panel size: **dynamic** — computed from `Defaults.idleLensMagnifiedSize` (default 144) plus info rows (2–4 depending on hint visibility). The default configuration produces a 256 × 240 point panel. The lens is a borderless `NSPanel` (similar to `CursorChipWindow`), drawn at `level = .screenSaver + 1`, ignoring mouse events, with `sharingType = .none` so ScreenCaptureKit excludes it from frozen-desktop snapshots.

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

The 12×12 source region centered on the cursor is extracted via `CGImage.cropping(to:)`. The cropped `CGImage` is drawn directly into the destination rect with `CGContext.draw(cropped, in: rect)`. `CGContext.draw` already maps the image's visual top-left to the destination rect's visual top-left, so **no manual y-flip transform is required** — adding one (`scaleBy(_, -scaleY)`) inverts the image and breaks pixel alignment.

When the cursor approaches a screen edge and the 12×12 source region would extend beyond the snapshot bounds, the crop is clamped to the valid pixel range. The draw rect is adjusted so the out-of-bounds portion appears as the dimmed background fill while the valid pixels stay correctly positioned. A `context.clip(to: rect)` call prevents the crop from bleeding outside the magnified area.

### Crosshair

Two layers ensure the centre is always visible:
- A **10 px wide cross** in `#A5BAF9` at 65% alpha spans the full magnified area. This provides a strong background presence even on pure-white source pixels.
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

- `idleLensFlagsChangedLocalMonitor` and `idleLensFlagsChangedGlobalMonitor` — mirror each other for Shift detection.
- `idleLensKeyDownGlobalMonitor` — global `keyDown` monitor for `⌘+C`. The local `escLocalMonitor` also handles `⌘+C` but typically does not fire because the event is delivered to the foreground app.

Both handlers gate on `guard idleColorLensActive else { return }`, so they never react when the lens is dismissed (e.g., once the user starts a selection or the overlay ends).

Global monitors only observe — they cannot prevent the foreground app from receiving `⌘+C`. Users should expect the foreground app's normal `⌘+C` behavior to still happen in parallel with the color copy.

## Multi-Monitor & Coordinates

- Coordinates displayed: **absolute desktop coordinates** (AppKit `NSEvent.mouseLocation`), integer. May be negative when the active screen sits left of the main display.
- **Points vs Pixels**: `Defaults.idleLensCoordinateMode` (`.points` default / `.pixels`) controls whether the lens shows AppKit logical-point coordinates or CGImage physical-pixel coordinates. On Retina displays, 1 point = 2 pixels, so the numbers differ. The mode is set via a popup in Settings and takes effect immediately when the lens is next refreshed — no runtime toggle.
- `OverlayWindowController` caches `screenFramesByDisplayID: [CGDirectDisplayID: NSRect]` at activation time, mapping the AppKit frame of each screen.
- The lens picks the screen containing `mouseLocation` by linear scan over `screenFramesByDisplayID`; uses the corresponding `CGImage` from `screenSnapshots`.
- **Edge-boundary fix**: `CGRect.contains` uses a half-open `[min, max)` interval — a cursor at the absolute top edge (`y == frame.maxY`) is treated as outside. The screen-detection guard was replaced with an inclusive `min <= x <= max && min <= y <= max` check so the lens resolves a snapshot at all screen edges.
- The `IdleColorLensSampler.pixelCoordinate` helper applies the screen's point-to-pixel scale (handles Retina correctly) and clamps the result to the valid pixel range so cursor-on-edge still resolves to a sample instead of returning `nil`.
- The single-pixel `IdleColorLensSampler.sample` helper uses a 1×1 `CGContext` with explicit `drawRect` math (subtract image dimensions, then add 0.5 for half-pixel centering) so the target pixel lands on the context's pixel center and the Y axis is correct on the first try.

## Settings

New `Defaults.idleColorLensEnabled: Bool` (default `false`).

- When `true`: `OverlayWindowController` creates the lens instead of the `dragToScreenshot` cursor chip in idle.
- When `false` (default): legacy `CursorChipWindow` chip with `L10n.dragToScreenshot` text is shown.

The feature has its own **dedicated card** in Settings → General (see below), with a master toggle, configurable options, and a live preview of the lens.

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
| `settingsIdleLensMagnifiedSizeLabel` | `Magnified area size` | `放大区域尺寸` |
| `settingsIdleLensMagnificationLabel` | `Magnification` | `放大倍率` |
| `settingsIdleLensPanelOffsetLabel` | `Panel offset` | `面板偏移` |
| `settingsIdleLensBackgroundLabel` | `Background colour` | `背景颜色` |
| `settingsIdleLensFollowSystemAppearanceTitle` | `Follow system appearance` | `跟随系统外观` |
| `settingsIdleLensFollowSystemAppearanceHint` | `Match the lens background to the current light or dark mode` | `将放大镜背景与当前浅色或深色模式匹配` |
| `settingsIdleLensDarkBackgroundLabel` | `Dark mode` | `深色模式` |
| `settingsIdleLensLightBackgroundLabel` | `Light mode` | `浅色模式` |
| `settingsIdleLensCoordinateModeLabel` | `Coordinates mode` | `坐标模式` |
| `settingsIdleLensCoordinateModePoints` | `Points` | `逻辑点` |
| `settingsIdleLensCoordinateModePixels` | `Pixels` | `物理像素` |

All translations follow the project rule: **no trailing punctuation** on user-facing strings.

## Settings Card Layout

```
+----------------------------------------------+
| [ON/OFF] Show color lens on idle             |
| Display a magnifier with RGB/HEX readout...  |
+----------------------------------------------+
| Magnified area size: [144 × 144 v]           |
| Coordinates mode: [Points v]                 |
| Panel offset (X, Y): [15]  [14]             |
| Background colour                            |
|   [ON] Follow system appearance              |
|   Dark mode  [■]  alpha: ━━━━━━━              |
|   Light mode [□]  alpha: ━━━━━━━              |
| +------------------+ +----------------------+ |
| | [preview panel] | | Show ⌘+C hint  [ON]  | |
| | - magnifier     | | Show Shift hint [ON]  | |
| | - coordinates   | +----------------------+ |
| | - swatch + HEX  |                         | |
| | - hint rows     |                         | |
| +------------------+                         | |
+----------------------------------------------+
```

### Configurable options

All options live on `Defaults` and take effect the next time the lens is created (or, for the live preview, immediately).

| Key | Type | Default | Purpose |
| --- | --- | --- | --- |
| `idleColorLensEnabled` | `Bool` | `false` | Master toggle. When off, the legacy "drag to screenshot" cursor chip is shown. |
| `idleLensMagnifiedSize` | `Int` | `144` | Side length of the magnified square. Choices: 96, 144, 192. |
| `idleLensPanelOffsetX` | `Double` | `15` | Horizontal offset (in points) between the cursor and the panel's left edge. |
| `idleLensPanelOffsetY` | `Double` | `14` | Vertical offset (in points) between the cursor and the panel's top edge (when below the cursor). |
| `idleLensFollowSystemAppearance` | `Bool` | `true` | When on, the lens picks the dark/light background based on `effectiveAppearance`. When off, it always uses the dark colour. |
| `idleLensDarkBackground{R,G,B,Alpha}` | `Double` × 4 | `0, 0, 0, 0.7` | RGBA used in dark mode (or always when `followSystemAppearance` is off). Alpha is clamped to 0…1. |
| `idleLensLightBackground{R,G,B,Alpha}` | `Double` × 4 | `1, 1, 1, 0.8` | RGBA used in light mode (only honoured when `followSystemAppearance` is on). Alpha is clamped to 0…1. |
| `idleLensShowCopyHint` | `Bool` | `true` | Whether to render the "Press ⌘+C to copy color" row. |
| `idleLensShowShiftHint` | `Bool` | `true` | Whether to render the "Press Shift to switch RGB" row. |
| `idleLensCoordinateMode` | `String` (`.points` / `.pixels`) | `.points` | Whether coordinates are shown as AppKit logical points or CGImage physical pixels. |

The lens panel size is recomputed from these defaults every time the panel is created — pick a different `idleLensMagnifiedSize` and the panel grows to fit.

### Preview

The right side of the card hosts an `IdleLensPreviewView` (defined in `capcap/Settings/IdleLensPreviewView.swift`). It draws a stylised "app icon" inside the magnified square, mock coordinates (`590, 445`) and a swatch + HEX (`#0B63FE`) that match the dominant icon colour, plus the conditional hint rows. The preview re-renders via a `UserDefaults.didChangeNotification` observer so changes to background colour, hint visibility, or follow-system appearance reflect immediately.

## Files Touched

### New

- `capcap/UI/IdleColorLensWindow.swift` — `NSPanel` subclass plus `IdleColorLensView` (drawing, magnification, swatch, layout) and the pure `IdleColorLensSampler` enum for pixel-coordinate mapping, single-pixel sampling, and background-colour selection (`backgroundColor(forAppearance:)`, `darkBackgroundColor()`, `lightBackgroundColor()`).
- `capcap/Settings/IdleLensPreviewView.swift` — `NSView` subclass that mocks the lens for the Settings card; reads from `Defaults` directly and re-renders on `UserDefaults.didChangeNotification`.
- `Tests/capcapTests/IdleColorLensTests.swift` — Unit tests covering `pixelCoordinate` mapping (including offset-screen cases), single-pixel sampling, Y-axis orientation, clamp-to-bounds, all new `Defaults` defaults, and alpha-setter clamping.
- `docs/spark/2026-07-25-idle-color-lens-design.md` — This document.

### Modified

- `capcap/Capture/OverlayWindowController.swift` — Owns the lens lifecycle, mouse-tracking (`.mouseMoved` + `.leftMouseDragged`), and `Shift` / `⌘+C` routing via local + global monitors. `refreshIdleColorLensContent` uses inclusive edge-boundary screen detection. `setupIdleColorLens` guards against duplicates. `selectionDidStart` recreates the lens if it was dismissed by a previous `selectionDidComplete` (for resize/move handle drags).
- `capcap/Utilities/Defaults.swift` — Adds `idleColorLensEnabled`, the configurable lens defaults, and the L10n accessors for the new keys.
- `capcap/Settings/SettingsView.swift` — Builds the dedicated "Idle Color Lens" card in `General` (master toggle + every option above + live preview). The previous single-line toggle inside the General `Toggles` card was removed.
- `capcap/Capture/SelectionView.swift` — Calls `delegate?.selectionDidStart()` for `.resize` and `.move` drag-action paths so the lens stays visible while adjusting an existing selection.
- `Resources/*.lproj/Localizable.strings` × 8 — Adds the lens-related keys (`idleLens*`, `settingsIdleColorLens*`, `settingsIdleLens*`).

## Verification

- `bash scripts/compile-check.sh` — passes (0 errors) on every iteration of the design.
- Manual runtime verification performed on `feat_idle-magnifier-color-picker`:
  - cmd+cmd activates the overlay; lens replaces the "drag to screenshot" chip.
  - Cursor moves update the magnified area, coordinates, and HEX value live.
  - Tip rows stay visible for the entire idle session (conditional on `idleLensShowCopyHint` / `idleLensShowShiftHint`).
  - ⌘+C copies the currently shown format; toast and clipboard confirm.
  - Single-tap Shift toggles HEX ↔ RGB; next cmd+cmd session resets to HEX.
  - Drag starts a selection — lens stays visible and tracks the drag endpoint.
  - Resizing or moving an existing selection via handles — lens stays visible.
  - Settings toggle hides the lens and restores the legacy chip.
  - Multi-monitor: cursor on a secondary screen left of the main display reports negative coordinates and samples the correct screen's snapshot.
  - Edge cases: panel flips left when the cursor is near the right edge; flips up when the cursor is near the bottom edge; defaults to below the cursor when the cursor is near the top.
  - **Top-edge pixel**: cursor at the absolute top of any screen (y == frame.maxY) correctly resolves a snapshot, magnifies, and samples the colour — no blank/missing pixel.
  - **Ghost lens**: first cmd+cmd activation shows exactly one lens (no shadow/frozen duplicate). Confirmed `sharingType = .none` prevents ScreenCaptureKit from capturing the lens in its own background snapshot.
  - **Points/Pixels mode**: Settings popup switches between logical points (e.g. `590, 445`) and physical pixels (e.g. `1180, 890` on a 2× Retina display).
- The unit tests in `IdleColorLensTests.swift` cover the pixel-coordinate math, the y-axis-correct sample path, every new `Defaults` key (magnified size, panel offsets, hint toggles, follow-system appearance, RGBA alpha clamping). Running them requires Xcode (the `XCTest` framework is not bundled with the available `xcode-select` command-line tools).
- Manual runtime verification on `feat_idle-magnifier-color-picker` covers the dedicated Settings card: master toggle, magnified-area size picker (96 / 144 / 192), X / Y offset fields, dark + light NSColorWells with alpha sliders, follow-system-appearance toggle, and the two hint toggles all take effect; the `IdleLensPreviewView` on the right of the card mirrors every change in real time.

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
- v6 — configurable Settings card: dedicated card replacing the single-line toggle, with magnified area size picker (96/144/192), magnification factor, panel offset fields, dark/light background RGBA with follow-system-appearance toggle, hint visibility toggles, live `IdleLensPreviewView`.
- v7 — lens stays visible during drag-to-select (`.leftMouseDragged` added to mouse monitors, `selectionDidStart` no longer dismisses). Enhanced crosshair: 10 px `#A5BAF9` cross behind 1 px white cross. Boundary crop clamping + `context.clip(to: rect)` when source region extends beyond snapshot bounds.
- v8 — **ghost lens fix**: `sharingType = .none` on `IdleColorLensWindow` prevents `SCScreenshotManager.captureImage` from including the lens in the background snapshot (was causing a frozen duplicate on first activation). `hasShadow = false`. `setupIdleColorLens` adds `guard idleColorLens == nil` duplicate prevention.
- v9 — **top-edge pixel fix**: `CGRect.contains` replaced with inclusive boundary check (`min <= x <= max`) in `refreshIdleColorLensContent` because the half-open `[min, max)` interval excluded cursor positions at the absolute edge.
- v10 — **lens during selection adjustment**: `SelectionView.mouseDown` calls `selectionDidStart()` for `.resize` and `.move` paths; `selectionDidStart` recreates the lens if it was dismissed by a previous `selectionDidComplete`. Lens now visible while dragging resize handles or moving an existing selection.
- v11 — **Points/Pixels coordinate mode**: `Defaults.IdleLensCoordinateMode` enum (`.points`/`.pixels`), Settings popup, L10n keys in 8 languages. `drawInfo` switches between `mouseLocation` (points) and `currentPixelPoint` (pixels) based on the setting.