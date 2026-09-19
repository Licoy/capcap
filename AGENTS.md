# capcap

macOS menu bar screenshot tool. Pure AppKit, Swift Package Manager, no third-party dependencies.

## Build & Verification

After completing a coherent set of related code changes, run the compile check
once. Rerun it only after relevant code changes or a newly discovered issue:

```bash
bash scripts/compile-check.sh
```

For runtime-sensitive UI changes, run the rebuild script too:

```bash
bash scripts/rebuild-and-open.sh
```

This script builds the app bundle, kills any running instance, launches the new build, and confirms it started.

Reuse successful checks and the installed build for the same source and resource
state. When runtime verification is needed, rebuild and install again if source,
resources, or temporary test hooks changed. Run tests relevant to the requested
change and `git diff --check` before
handoff. Documentation-only changes need no compilation or app restart.

Once the relevant checks are complete, hand off the result. Do not repeat checks
or broaden testing without new changes, failures, or a concrete unresolved risk.
Report any UI observations that could not be completed.

## Reliable Interactive UI Testing

capcap is an `LSUIElement` menu-bar app, so the macOS frontmost application is
often ChatGPT, Terminal, Finder, or another unrelated app even while a capcap
panel is visible. Do not infer the UI automation target from the frontmost app.
The stable Computer Use workflow is:

1. Ensure the installed app matches the current source and resources, following
   Build & Verification above. Reuse an already verified current build.
2. Confirm that the intended capcap surface exists before sending input:

   ```bash
   /Applications/capcap.app/Contents/MacOS/capcap agent windows \
     --owner capcap --all --pretty
   ```

   Verify `ownerName`, `ownerPID`, window frame, and layer. A shallow
   Accessibility tree is normal for custom AppKit panels and is not evidence
   that another app should be targeted.
3. Lock every state read and UI action to `/Applications/capcap.app` using the
   current tool's documented app-targeting API. Do not begin with a generic
   frontmost app, reuse another app's element index, or operate
   ChatGPT/Terminal/Finder to bring capcap forward. Use app discovery only if
   targeting the exact path fails.
4. When the next action depends on UI state or element location, use fresh state.
   If the previous action already returned sufficient current state, no extra
   read is needed. Reacquire elements after rebuilds, relaunches, panel
   transitions, or layout changes.
5. Follow the current tool documentation for initialization, key syntax, and
   available pointer actions.

Dragging holds the mouse button and must not be treated as proof that ordinary
`mouseMoved`, `mouseEntered`, or hover behavior works. Verify hover-sensitive behavior with
real pointer movement when possible. If existing entry points cannot reach a
panel or hover state whose observation is necessary for this task's acceptance,
you may add a narrowly scoped `#if DEBUG` launch argument or keyboard hook.
Follow Build & Verification, use the hook only to isolate the relevant behavior,
then remove it before final verification.
Search for the unique hook name afterward so temporary test code cannot ship.

For runtime-sensitive work, final verification must use the clean installed
app after all debug hooks have been removed, following Build & Verification
above. Reuse checks only if they cover this final state. Treat
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

- No SwiftUI — this project uses AppKit exclusively with programmatic UI.
  The only exception is `AppleTranslationSessionProvider`, which hosts a
  hidden SwiftUI `translationTask` bridge because TranslationSession has no
  public AppKit initializer on macOS 15–25. Do not spread SwiftUI further.
- No storyboards or XIBs.
- Minimum deployment target: macOS 14.0.
- All newly added user-facing copy must not end with punctuation. Punctuation
  inside the sentence is fine, but the final character of every visible string,
  tooltip, alert, toast, menu item, placeholder, and localized value must not be
  punctuation.

## Packaging Lessons

- SwiftPM target resources are not automatically present in the hand-assembled
  `.app` bundle. When adding or changing resource declarations, resource bundles,
  or packaging paths, check both `scripts/bundle.sh` and the release workflow.
  Update missing copy logic so the generated `<package>_<target>.bundle` reaches
  `capcap.app/Contents/Resources/`.
- Treat a missing SwiftPM resource bundle as a release-blocking error, not a
  runtime fallback. The failure may only surface when a UI path first touches
  `Bundle.module`, such as the PermissionFlow authorization panel.
- After packaging changes, verify the final `.app` contents directly with
  `find build/capcap.app/Contents/Resources -maxdepth 2 -name '*.bundle'` and,
  for release builds, confirm the universal app still contains both `arm64` and
  `x86_64` slices.

## Hotspot Ownership

Apply Build & Verification above to changes in these files.

- `capcap/Editor/EditWindowController.swift` owns editor session wiring,
  toolbar callbacks, scroll capture, crop mode, and output actions. Keep tool
  state changes paired with toolbar/sub-toolbar updates.
- `capcap/Editor/EditCanvasView.swift` owns annotation state, mouse handling,
  selection chrome, undo/redo, and export compositing. Preserve value-typed
  annotation mutation and snapshot-based undo.
- `capcap/Editor/Annotations.swift` owns annotation model structs and drawing
  behavior. Keep drawing and hit-testing logic together for each annotation
  type.
- `capcap/Settings/SettingsView.swift` owns the settings window and preference
  controls. Keep persisted defaults in `Defaults.swift` aligned with visible
  controls and localized strings.
- `capcap/Translation/OCRTranslatePanel.swift` owns OCR/translation result
  presentation and provider interaction. Keep translation latency work off the
  main actor except for UI updates.
- `capcap/Capture/PinLauncher.swift` owns pinned-image window behavior,
  toolbar visibility, drag/resize behavior, and zoom interaction. Keep hover
  affordances and the above/below-100% drag model stable.
- `capcap/Utilities/Defaults.swift` owns persisted preferences and localized
  string accessors. Keep new settings normalized at the persistence boundary and
  add matching keys to every `Resources/*.lproj/Localizable.strings` file.
- `capcap/Settings/UploadSettingsPane.swift` owns image-host provider settings.
  Keep provider-specific validation, default-provider selection, and stored
  credentials isolated to this settings surface and `Defaults.swift`.
- `capcap/Trigger/HotkeyManager.swift` owns global shortcut registration and
  keyboard trigger dispatch. Keep shortcut recording, defaults, and active
  registration behavior aligned with Settings.

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
- Use the user's specified toolbar position. Otherwise, follow the layout of
  similar tools and explain the choice. Ask only when the position involves an
  important product tradeoff that cannot be inferred from the existing layout
  or task context.
