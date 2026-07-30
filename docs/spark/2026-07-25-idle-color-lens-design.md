# Magnifier Lens Panel Design

Date: 2026-07-25 (updated 2026-07-27)
Status: Implemented and verified on branch `feat_idle-magnifier-color-picker`
Project: capcap

## Summary

Add a magnifier color picker (lens) to the screenshot overlay. When the user has triggered an overlay session, the cursor is followed by a configurable panel that shows the current pixel coordinates, RGB/HEX value, and a magnified view of the area around the cursor. The lens is visible in three states: (1) idle (before any selection), (2) during drag-to-select, and (3) while resizing or moving an existing selection rectangle. The user can press `⌘+C` to copy the currently displayed value, or `Shift` (single tap) to toggle between HEX and RGB display. Clicking the cursor still triggers the existing window-selection capture. Pressing `Esc` cancels as before. The lens replaces the legacy "drag to screenshot" cursor chip while the overlay is active.

The feature is controlled by a `Defaults.magnifierLensPanelEnabled` toggle (default `true` so new users get the magnifier experience immediately). Users who prefer the legacy "drag to screenshot" chip can disable it in **Settings → General → Show magnifier while selecting**. The lens reuses the existing `backgroundSnapshot` for pixel sampling, so no new screen-capture permission is required.

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
2. `OverlayWindowController` presents the overlay. If `presetImage == nil` and `Defaults.magnifierLensPanelEnabled` is true, a `MagnifierLensPanelWindow` is created and replaces the "drag to screenshot" cursor chip.
3. Mouse moves: lens position follows the cursor; the magnified area, coordinates, and HEX/RGB value update live.
4. `Shift` (single tap, no other modifiers): toggles between HEX and RGB display. The new state persists for the current session and resets to HEX on the next overlay activation.
5. `⌘+C`: copies the currently displayed value (HEX → `#RRGGBB`, RGB → `rgb(r, g, b)`) to the clipboard, shows the existing `L10n.colorCopied` toast, and updates `HistoryManager` + `Defaults.lastPickedColorHex` if `Defaults.historyCacheEnabled` is true. The two tip rows (`Press ⌘+C…` and `Press Shift…`) remain visible for the entire overlay session — they do not fade out.
6. Click without drag: still triggers window-selection capture (existing behavior). The lens does not consume the click.
7. Mouse down + drag: lens stays visible while the user draws the selection rectangle, then dismisses when selection completes.
8. `Esc`: cancels the overlay session; lens dismisses with the rest.
9. Closing the overlay: lens is released via the standard `tearDown` path.

## Lens UI

Panel size: **dynamic** — computed from `Defaults.magnifierLensPanelMagnifiedSize` (default 144) plus info rows (2–4 depending on hint visibility). The default configuration produces a 256 × 240 point panel. The lens is a borderless `NSPanel` (similar to `CursorChipWindow`), drawn at `level = .screenSaver + 1`, ignoring mouse events, with `sharingType = .none` so ScreenCaptureKit excludes it from frozen-desktop snapshots.

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

New `Defaults.magnifierLensPanelEnabled: Bool` (default `true`).

- When `true` (default): `OverlayWindowController` creates the lens instead of the `dragToScreenshot` cursor chip in idle.
- When `false`: legacy `CursorChipWindow` chip with `L10n.dragToScreenshot` text is shown.

The feature has its own **dedicated card** in Settings → General (see below), with a master toggle, configurable options, and a live preview of the lens.

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
| `settingsMagnifierLensPanelTitle` | `Show magnifier while selecting` | `空闲态显示放大镜取色` |
| `settingsMagnifierLensPanelHint` | `Magnify the area around the cursor when picking screenshot points or adjusting the selection` | `绘制前在光标旁显示带 RGB/HEX 的放大镜` |
| `settingsMagnifierLensPanelMagnifiedSizeLabel` | `Magnified area size` | `放大区域尺寸` |
| `settingsMagnifierLensPanelMagnificationLabel` | `Magnification` | `放大倍率` |
| `settingsMagnifierLensPanelOffsetLabel` | `Panel offset` | `面板偏移` |
| `settingsMagnifierLensPanelFollowSystemAppearanceTitle` | `Follow system appearance` | `跟随系统外观` |
| `settingsMagnifierLensPanelFollowSystemAppearanceHint` | `Match the lens background to the current light or dark mode` | `将放大镜背景与当前浅色或深色模式匹配` |
| `settingsMagnifierLensPanelDarkBackgroundLabel` | `Dark mode` | `深色模式` |
| `settingsMagnifierLensPanelLightBackgroundLabel` | `Light mode` | `浅色模式` |
| `settingsMagnifierLensPanelCoordinateModeLabel` | `Coordinates mode` | `坐标模式` |
| `settingsMagnifierLensPanelCoordinateModePoints` | `Points` | `逻辑点` |
| `settingsMagnifierLensPanelCoordinateModePixels` | `Pixels` | `物理像素` |

All translations follow the project rule: **no trailing punctuation** on user-facing strings.

## Settings Card Layout

```
+----------------------------------------------+
| [ON/OFF] Show magnifier while selecting      |
| Magnify the area around the cursor...        |
+----------------------------------------------+
| Magnified area size: [144 × 144 v]           |
| Coordinates mode: [Points v]                 |
| Panel offset (X, Y): [15]  [14]             |
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
| `magnifierLensPanelEnabled` | `Bool` | `true` | Master toggle. When off, the legacy "drag to screenshot" cursor chip is shown. |
| `magnifierLensPanelMagnifiedSize` | `Int` | `144` | Side length of the magnified square. Choices: 96, 144, 192. |
| `magnifierLensPanelMagnification` | `Double` | `12.0` | Zoom factor for the magnified square. Settings choices: 4, 6, 8, 10, 12, 16, 20, 24. |
| `magnifierLensPanelOffsetX` | `Double` | `15` | Horizontal offset (in points) between the cursor and the panel's left edge. |
| `magnifierLensPanelOffsetY` | `Double` | `14` | Vertical offset (in points) between the cursor and the panel's top edge (when below the cursor). |
| `magnifierLensPanelFollowSystemAppearance` | `Bool` | `true` | When on, the lens picks the dark/light background based on `effectiveAppearance`. When off, it always uses the dark colour. |
| `magnifierLensPanelDarkBackground{R,G,B,Alpha}` | `Double` × 4 | `0, 0, 0, 0.7` | RGBA used in dark mode (or always when `followSystemAppearance` is off). Components are clamped to 0…1. |
| `magnifierLensPanelLightBackground{R,G,B,Alpha}` | `Double` × 4 | `1, 1, 1, 0.8` | RGBA used in light mode (only honoured when `followSystemAppearance` is on). Components are clamped to 0…1. |
| `magnifierLensPanelShowCopyHint` | `Bool` | `true` | Whether to render the "Press ⌘+C to copy color" row. |
| `magnifierLensPanelShowShiftHint` | `Bool` | `true` | Whether to render the "Press Shift to switch RGB" row. |
| `magnifierLensPanelCoordinateMode` | `String` (`.points` / `.pixels`) | `.points` | Whether coordinates are shown as AppKit logical points or CGImage physical pixels. |
| `magnifierLensPanelCrosshair{R,G,B,Alpha}` | `Double` × 4 | `0.659, 0.741, 0.988, 0.65` | RGBA used for the wide crosshair. Components are clamped to 0…1. |
| `magnifierLensPanelCrosshairWidth` | `Double` | `6` | Wide crosshair line width in points, clamped to 1…30. |

The lens panel size is recomputed from these defaults every time the panel is created — pick a different `magnifierLensPanelMagnifiedSize` and the panel grows to fit.

### Preview

The right side of the card hosts a `MagnifierPreviewView` (defined in `capcap/Settings/MagnifierPreviewView.swift`). It draws a stylised "app icon" inside the magnified square, mock coordinates (`590, 445`) and a swatch + HEX (`#0B63FE`) that match the dominant icon colour, plus the conditional hint rows. The preview re-renders via a `UserDefaults.didChangeNotification` observer so changes to background colour, hint visibility, or follow-system appearance reflect immediately.

## Files Touched

### New

- `capcap/UI/MagnifierLensPanelWindow.swift` — `NSPanel` subclass plus `MagnifierLensPanelView` (drawing, magnification, swatch, layout) and the pure `MagnifierLensPanelSampler` enum for pixel-coordinate mapping, single-pixel sampling, and background-colour selection (`backgroundColor(forAppearance:)`, `darkBackgroundColor()`, `lightBackgroundColor()`).
- `capcap/Settings/MagnifierPreviewView.swift` — `NSView` subclass that mocks the lens for the Settings card; reads from `Defaults` directly and re-renders on `UserDefaults.didChangeNotification`.
- `Tests/capcapTests/MagnifierLensPanelTests.swift` — Unit tests covering `pixelCoordinate` mapping (including offset-screen cases), single-pixel sampling, Y-axis orientation, clamp-to-bounds, all new `Defaults` defaults, and alpha-setter clamping.
- `docs/spark/2026-07-25-idle-color-lens-design.md` — This document.

### Modified

- `capcap/Capture/OverlayWindowController.swift` — Owns the lens lifecycle, mouse-tracking (`.mouseMoved` + `.leftMouseDragged`), and `Shift` / `⌘+C` routing via local + global monitors. `refreshMagnifierLensPanelContent` uses inclusive edge-boundary screen detection. `setupMagnifierLensPanel` guards against duplicates. `selectionDidStart` recreates the lens if it was dismissed by a previous `selectionDidComplete` (for resize/move handle drags).
- `capcap/Utilities/Defaults.swift` — Adds `magnifierLensPanelEnabled`, normalized configurable lens defaults, and the L10n accessors for the new keys.
- `capcap/Settings/SettingsView.swift` — Builds the dedicated magnifier lens panel card in `General` (master toggle + every option above + live preview). The previous single-line toggle inside the General `Toggles` card was removed.
- `capcap/Capture/SelectionView.swift` — Calls `delegate?.selectionDidStart()` for `.resize` and `.move` drag-action paths so the lens stays visible while adjusting an existing selection.
- `Resources/*.lproj/Localizable.strings` × 8 — Adds the lens-related keys (`magnifierLensPanel*`, `settingsMagnifierLensPanel*`).

## Verification

- `bash scripts/compile-check.sh` — passes (0 errors) on every iteration of the design.
- Manual runtime verification performed on `feat_idle-magnifier-color-picker`:
  - cmd+cmd activates the overlay; lens replaces the "drag to screenshot" chip.
  - Cursor moves update the magnified area, coordinates, and HEX value live.
  - Tip rows stay visible for the entire idle session (conditional on `magnifierLensPanelShowCopyHint` / `magnifierLensPanelShowShiftHint`).
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
- The unit tests in `MagnifierLensPanelTests.swift` cover the pixel-coordinate math, the x/y-axis-correct sample path, every new `Defaults` key (magnified size, panel offsets, hint toggles, follow-system appearance, and RGBA component clamping). Running them requires Xcode (the `XCTest` framework is not bundled with the available `xcode-select` command-line tools).
- Manual runtime verification on `feat_idle-magnifier-color-picker` covers the dedicated Settings card: master toggle, magnified-area size picker (96 / 144 / 192), X / Y offset fields, dark + light NSColorWells with alpha sliders, follow-system-appearance toggle, and the two hint toggles all take effect; the `MagnifierPreviewView` on the right of the card mirrors every change in real time.

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
- v6 — configurable Settings card: dedicated card replacing the single-line toggle, with magnified area size picker (96/144/192), magnification factor, panel offset fields, dark/light background RGBA with follow-system-appearance toggle, hint visibility toggles, live `MagnifierPreviewView`.
- v7 — lens stays visible during drag-to-select (`.leftMouseDragged` added to mouse monitors, `selectionDidStart` no longer dismisses). Enhanced crosshair: 10 px `#A5BAF9` cross behind 1 px white cross. Boundary crop clamping + `context.clip(to: rect)` when source region extends beyond snapshot bounds.
- v8 — **ghost lens fix**: `sharingType = .none` on `MagnifierLensPanelWindow` prevents `SCScreenshotManager.captureImage` from including the lens in the background snapshot (was causing a frozen duplicate on first activation). `hasShadow = false`. `setupMagnifierLensPanel` adds `guard magnifierLensPanel == nil` duplicate prevention.
- v9 — **top-edge pixel fix**: `CGRect.contains` replaced with inclusive boundary check (`min <= x <= max`) in `refreshMagnifierLensPanelContent` because the half-open `[min, max)` interval excluded cursor positions at the absolute edge.
- v10 — **lens during selection adjustment**: `SelectionView.mouseDown` calls `selectionDidStart()` for `.resize` and `.move` paths; `selectionDidStart` recreates the lens if it was dismissed by a previous `selectionDidComplete`. Lens now visible while dragging resize handles or moving an existing selection.
- v11 — **Points/Pixels coordinate mode**: `Defaults.MagnifierLensPanelCoordinateMode` enum (`.points`/`.pixels`), Settings popup, L10n keys in 8 languages. `drawInfo` switches between `mouseLocation` (points) and `currentPixelPoint` (pixels) based on the setting.
- v12 — **default flipped to enabled**: `Defaults.magnifierLensPanelEnabled` flipped from `false` to `true` so new users see the magnifier lens by default instead of the legacy "drag to screenshot" chip. Existing users who prefer the old behavior can disable the toggle in **Settings → General → Show magnifier while selecting**. Documentation updated to reflect the new default (Summary + Settings + Configurable Options table).
- v13 — **MagnifierLensPanel rename**: Swift types, Defaults keys, L10n keys, tests, and docs were renamed from the earlier idle-color-lens terminology to the `MagnifierLensPanel` naming used by the Settings panel.
- v14 — **review hardening**: single-pixel sampling now disables interpolation and uses integer alignment, panel screen lookup uses inclusive edge bounds, snapshot arrival refreshes an already visible panel, local `⌘+C` copy no longer consumes the event, color defaults clamp RGB/alpha components, magnified size normalizes to supported choices, unused Settings state/resources were removed, and docs were brought back in sync.
