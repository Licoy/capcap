# capcap

macOS menu bar screenshot tool. Pure AppKit, Swift Package Manager, no third-party dependencies.

## Build & Verification

After every code change, run the compile check:

```bash
bash scripts/compile-check.sh
```

For runtime-sensitive UI changes, run the rebuild script too:

```bash
bash scripts/rebuild-and-open.sh
```

This script builds the app bundle, kills any running instance, launches the new build, and confirms it started.

## Reliable Interactive UI Testing

capcap is an `LSUIElement` menu-bar app, so the macOS frontmost application is
often ChatGPT, Terminal, Finder, or another unrelated app even while a capcap
panel is visible. Do not infer the UI automation target from the frontmost app.
The stable Computer Use workflow is:

1. Build, install, and launch the current code with
   `bash scripts/rebuild-and-open.sh`.
2. Confirm that the intended capcap surface exists before sending input:

   ```bash
   /Applications/capcap.app/Contents/MacOS/capcap agent windows \
     --owner capcap --all --pretty
   ```

   Verify `ownerName`, `ownerPID`, window frame, and layer. A shallow
   Accessibility tree is normal for custom AppKit panels and is not evidence
   that another app should be targeted.
3. Initialize Computer Use once, then lock every state read and UI action to the
   exact installed app path:

   ```js
   var capcapTarget = "/Applications/capcap.app"
   await sky.get_app_state({ app: capcapTarget, disableDiff: true })
   ```

   Every later `click`, `drag`, `press_key`, `type_text`, and `get_app_state`
   call must include `app: capcapTarget`. Do not begin with a generic frontmost
   app, reuse another app's element index, or operate ChatGPT/Terminal/Finder to
   bring capcap forward. Use `list_apps` only if the exact path fails.
4. After every action, read capcap state again before choosing the next action.
   Accessibility element indices are snapshots; reacquire them after rebuilds,
   relaunches, panel transitions, or layout changes.
5. `press_key` uses xdotool-style key strings. Use `"super+k"`, `"space"`,
   `"Return"`, etc. Do not pass a separate `modifiers` field because it is
   ignored by this interface.

Computer Use has no move-only mouse action. Its `drag` action holds the mouse
button and must not be treated as proof that ordinary `mouseMoved`,
`mouseEntered`, or hover behavior works. Verify hover-sensitive behavior with
real pointer movement when possible. If automation needs deterministic access
to an otherwise unreachable panel or hover state, add a narrowly scoped
`#if DEBUG` launch argument or keyboard hook, compile and rebuild, use it only
to isolate the relevant behavior, then remove it before final verification.
Search for the unique hook name afterward so temporary test code cannot ship.

For runtime-sensitive work, final verification must use the clean installed
app after all debug hooks have been removed: run the compile check, relevant
tests, `git diff --check`, and `bash scripts/rebuild-and-open.sh`. Treat
incomplete Computer Use observations as a limitation, not as proof that an
`LSUIElement` surface passed or failed.

## Project Structure

- `capcap/App/` — Entry point (`main.swift`, `AppDelegate.swift`, `Info.plist`)
- `capcap/Capture/` — Screen capture logic (ScreenCaptureKit, selection overlay)
- `capcap/Editor/` — Post-capture annotation editor
- `capcap/Trigger/` — Double-tap ⌘ key detection
- `capcap/UI/` — Status bar, toast, cursor chip
- `capcap/Settings/` — Settings dialog (startup + preferences)
- `capcap/Utilities/` — UserDefaults wrapper
- `scripts/` — Build and bundle scripts

## Key Rules

- **Always run `bash scripts/compile-check.sh` after modifying code** to verify the compile.
- No SwiftUI — this project uses AppKit exclusively with programmatic UI.
- No storyboards or XIBs.
- Minimum deployment target: macOS 14.0.
- All newly added user-facing copy must not end with punctuation. Punctuation
  inside the sentence is fine, but the final character of every visible string,
  tooltip, alert, toast, menu item, placeholder, and localized value must not be
  punctuation.

## Packaging Lessons

- SwiftPM target resources are not automatically present in the hand-assembled
  `.app` bundle. If any package target declares `resources:` in `Package.swift`
  or code uses `Bundle.module`, update both `scripts/bundle.sh` and the release
  workflow to copy the generated `<package>_<target>.bundle` into
  `capcap.app/Contents/Resources/`.
- Treat a missing SwiftPM resource bundle as a release-blocking error, not a
  runtime fallback. The failure may only surface when a UI path first touches
  `Bundle.module`, such as the PermissionFlow authorization panel.
- After packaging changes, verify the final `.app` contents directly with
  `find build/capcap.app/Contents/Resources -maxdepth 2 -name '*.bundle'` and,
  for release builds, confirm the universal app still contains both `arm64` and
  `x86_64` slices.

## Hotspot Ownership

- `capcap/Editor/EditWindowController.swift` owns editor session wiring,
  toolbar callbacks, scroll capture, crop mode, and output actions. Keep tool
  state changes paired with toolbar/sub-toolbar updates. Verify with
  `bash scripts/compile-check.sh`; use `bash scripts/rebuild-and-open.sh` for
  UI interaction changes.
- `capcap/Editor/EditCanvasView.swift` owns annotation state, mouse handling,
  selection chrome, undo/redo, and export compositing. Preserve value-typed
  annotation mutation and snapshot-based undo. Verify with
  `bash scripts/compile-check.sh`; use `bash scripts/rebuild-and-open.sh` when
  hit testing or visible editing behavior changes.
- `capcap/Editor/Annotations.swift` owns annotation model structs and drawing
  behavior. Keep drawing and hit-testing logic together for each annotation
  type. Verify with `bash scripts/compile-check.sh`.
- `capcap/Settings/SettingsView.swift` owns the settings window and preference
  controls. Keep persisted defaults in `Defaults.swift` aligned with visible
  controls and localized strings. Verify with `bash scripts/compile-check.sh`;
  use `bash scripts/rebuild-and-open.sh` for settings UI behavior.
- `capcap/Translation/OCRTranslatePanel.swift` owns OCR/translation result
  presentation and provider interaction. Keep translation latency work off the
  main actor except for UI updates. Verify with `bash scripts/compile-check.sh`.
- `capcap/Capture/PinLauncher.swift` owns pinned-image window behavior,
  toolbar visibility, drag/resize behavior, and zoom interaction. Keep hover
  affordances and the above/below-100% drag model stable. Verify with
  `bash scripts/compile-check.sh`; use `bash scripts/rebuild-and-open.sh` for
  pin-window interaction changes.
- `capcap/Utilities/Defaults.swift` owns persisted preferences and localized
  string accessors. Keep new settings normalized at the persistence boundary and
  add matching keys to every `Resources/*.lproj/Localizable.strings` file.
  Verify with `bash scripts/compile-check.sh`.
- `capcap/Settings/UploadSettingsPane.swift` owns image-host provider settings.
  Keep provider-specific validation, default-provider selection, and stored
  credentials isolated to this settings surface and `Defaults.swift`. Verify
  with `bash scripts/compile-check.sh`; use `bash scripts/rebuild-and-open.sh`
  when settings UI behavior changes.
- `capcap/Trigger/HotkeyManager.swift` owns global shortcut registration and
  keyboard trigger dispatch. Keep shortcut recording, defaults, and active
  registration behavior aligned with Settings. Verify with
  `bash scripts/compile-check.sh`; use `bash scripts/rebuild-and-open.sh` for
  end-to-end hotkey behavior.

## Adding an Editor Tool

Whenever a new annotation/editor tool is added, it MUST also be wired into the
toolbar — a tool that isn't in `ToolbarLayout` never appears for the user.
Checklist:

- Add the `ToolbarItemID` case and update `editTool`, `symbolName`, `tooltip`,
  and the `kind` switch in `ToolbarLayout.swift`.
- Add the case to **both** `ToolbarLayout.canonicalOrder` and the `default`
  layout's `primary`/`side`/`hidden` buckets. A tool missing from
  `canonicalOrder` is invisible even though the enum case exists.
- Add the `tipXxx` localization key to `Defaults.swift` and to every
  `Resources/*.lproj/Localizable.strings` file.
- If the user has not told you where the tool should sit in the toolbar by
  default, **ask before placing it** — don't guess the position.
