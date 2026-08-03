# Crosshair Cursor Not Visible When Another App Is Frontmost

## Symptom

When capcap enters capture mode (cmd+cmd) while another application is
frontmost, the cursor does not change to the crosshair. It stays as the
default arrow. The crosshair only appears when capcap itself was the
most recently activated app.

## Root Cause

Every AppKit cursor API — `NSCursor.push()`, `NSCursor.set()`, and
`NSView.resetCursorRects` / `addCursorRect(_:cursor:)` — is **app-scoped**.
WindowServer ignores cursor changes from any application that is not
frontmost.

capcap is an `LSUIElement` menu-bar app. It uses non-activating overlay
panels (`NSPanel` with `.nonactivatingPanel` style mask) to avoid
disturbing the source app's visual state during capture. Because capcap
never becomes frontmost during capture, none of its cursor API calls
reach WindowServer, and the crosshair never appears.

### Why Previous Attempts Failed

| Approach | Why It Failed |
|---|---|
| `NSCursor.crosshair.push()` + `.set()` alone | App-scoped; WindowServer ignores calls from background apps. |
| `CGWarpMouseCursorPosition` with 1px offset | WindowServer may optimize identical-position warps to no-ops. Even when events fire, `NSCursor.set()` in the handler is still app-scoped. |
| `resetCursorRects` + `addCursorRect` on `SelectionView` | Cursor rects on non-activating panels are not evaluated when the owning app is not frontmost. |

## Fix

In `OverlayWindowController.presentOverlay()`, activate capcap when
entering regular capture mode (no preset image, no suspended draft):

```swift
if presetImage == nil, suspendedDraft == nil {
    NSCursor.crosshair.push()
    cursorWasPushed = true
    claimSelectionKeyboardFocus()
    refreshSelectionCursor()
    NSCursor.crosshair.set()
    NSApp.activate(ignoringOtherApps: true)  // ← key addition
} else { ... }
```

### Why Activation Is Safe

1. The frozen desktop screenshot is captured **before** the overlay
   appears, so the source app's visual state is preserved in the
   background image displayed to the user.

2. `AppDelegate.startCapture()` creates a `SourceAppFocusRestorer`
   before calling `overlayController.activate()`. It records the
   frontmost app at that moment. When the capture session ends,
   `onRequestFocusReturn` triggers `focusRestorer.restore()`, returning
   focus to the original app.

3. This pattern is already used throughout the codebase for the
   settings window, editor, translation panel, and history panel.

### Supporting Infrastructure (Retained)

- `NSCursor.crosshair.push()` / `.pop()` — cursor stack management for
  the capture session lifetime.
- `SelectionView.resetCursorRects` — registers a crosshair cursor rect
  for the entire view bounds (active when the app is frontmost).
- `refreshSelectionCursor()` → `window.invalidateCursorRects(for:)` —
  triggers WindowServer cursor rect re-evaluation.

## Files Changed

- `capcap/Capture/OverlayWindowController.swift` — added `NSApp.activate`
  in `presentOverlay()` capture branch.
- `capcap/Capture/SelectionView.swift` — added `resetCursorRects`
  override and `refreshCursorRects()` public method; changed
  `mouseDragged` to set `.crosshair` instead of `.arrow`.
- `Tests/capcapTests/OverlayPresentationTests.swift` — restored
  crosshair assertions and `testCaptureReassertsCrosshair` test.

## Follow-Up: Crosshair Reverts to Arrow During Mouse Movement

### Symptom

After the `NSApp.activate` fix, the crosshair appears correctly on
capture start. However, after moving the mouse around for a while
(typically a few seconds to tens of seconds), the cursor silently
reverts to the default arrow — without any click or keyboard event.

### Root Cause

macOS may return activation to the previously frontmost app over time
(e.g. system-level focus reclamation, transient UI elements). When
capcap loses frontmost status:

- `NSCursor.crosshair.set()` called in `presentOverlay()` is no longer
  honored by WindowServer.
- The crosshair cursor rect registered in `resetCursorRects` is also
  ignored (cursor rects are app-scoped).
- `SelectionView.mouseMoved` keeps firing — the `NSTrackingArea` uses
  `.activeAlways` — but it performed no cursor work. The cursor thus
  stayed as the default arrow.

### Fix

In `SelectionView.mouseMoved`, re-assert activation and explicitly set
the crosshair on every mouse-move event during idle state:

```swift
override func mouseMoved(with event: NSEvent) {
    guard selectionInteractionEnabled else { return }
    if state == .idle && !selectionLocked {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSCursor.crosshair.set()
        updateWindowHover(with: event)
    }
}
```

- `NSApp.isActive` is a cheap property check; `NSApp.activate` is only
  called when activation has actually been lost.
- `NSCursor.crosshair.set()` on every move provides a belt-and-suspenders
  guarantee: even if cursor rect invalidation is missed for any reason,
  the explicit set keeps the crosshair.
- `SourceAppFocusRestorer` still correctly restores the original app
  when the capture session ends.

## Verification

```bash
bash scripts/compile-check.sh
swift test --filter OverlayPresentationTests
bash scripts/rebuild-and-open.sh
```

16/16 OverlayPresentationTests pass. Manual testing confirms crosshair
appears regardless of which app is frontmost when cmd+cmd is pressed,
and persists through extended mouse movement.
