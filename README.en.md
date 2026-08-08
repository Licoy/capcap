<p align="center">
  <img src="images/app-banner.png" alt="capcap app banner" width="760" />
</p>

<h1 align="center">capcap</h1>

<p align="center">
  The fastest menu bar screenshot tool for macOS: double-tap <code>⌘</code> to capture, annotate, scroll-stitch, beautify, pin, and upload.
</p>

<p align="center">
  <a href="https://github.com/Licoy/capcap/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Licoy/capcap?style=flat-square"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/Licoy/capcap/releases/latest">Download</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="https://github.com/Licoy/capcap/issues">Issues</a>
</p>

<p align="center">
  <sub>Fork maintained from <a href="https://github.com/realskyrin/capcap">realskyrin/capcap</a> (Licoy/capcap)</sub>
</p>

**The fastest way to grab, mark up, and share screenshots on macOS.** Double-tap `⌘` from anywhere — snap to a window, drag a region, scroll-stitch a long page, then annotate and beautify in one tight floating window. Lives in your menu bar. No Dock icon, no telemetry, no subscription, no third-party dependencies. Bring your own object storage if you want a one-click cloud URL.

<p align="center">
  <img src="images/editor.png" alt="capcap annotation editor — arrows, numbered callouts, mosaic, highlighter and text layered on a screenshot in a single floating toolbar" width="760" />
</p>

<p align="center">
  <a href="https://github.com/Licoy/capcap/releases/latest"><b>Download Latest Release</b></a> &nbsp;·&nbsp;
  macOS 14+ &nbsp;·&nbsp; Universal (Apple Silicon + Intel)
</p>

## Differences from upstream

This fork is maintained from [realskyrin/capcap](https://github.com/realskyrin/capcap). Key differences:

| Item | This repo (Licoy/capcap) | Upstream (realskyrin/capcap) |
|------|--------------------------|------------------------------|
| Bundle ID | `com.github.licoy.capcap.desktop` | `cn.skyrin.capcap` |
| Update / release source | [Licoy/capcap Releases](https://github.com/Licoy/capcap/releases) | Upstream GitHub Releases |
| Documentation | Chinese + English README only | Multi-language READMEs |
| Release signing | CI self-signed cert via GitHub Actions secrets | Upstream self-signed flow |
| Version baseline | Independent line starting at `v1.0.0` | Upstream independent line |

Note: a new Bundle ID means a separate app from upstream installs (fresh permissions and preferences). Both can be installed side by side.

## Why capcap

- **One shortcut, zero friction.** Double-tap `⌘` anywhere and capcap is on screen in milliseconds — or record any global hotkey you like.
- **Snap-to-window or pixel-perfect region.** Hover any window for a one-click capture, or drag a region with full Retina output across every connected display.
- **A real annotation editor.** Arrows, numbered callouts, text, mosaic, highlighter, pen — all editable, draggable, rotatable and undoable *after* you place them.
- **Scroll-stitch long content.** Capture a scrolling area, watch the stitched preview live, and keep editing the merged result.
- **Beautify and pin.** Wrap shots in gradient or wallpaper backgrounds with rounded corners and shadow, or pin the final image floating above any window.
- **Edit Finder images too.** Select a single image file in Finder and trigger the same shortcut to load it straight into the editor — the original is never touched.
- **Menu bar history.** Recent screenshots and picked colors are one click away from re-copying — local-only, configurable size.
- **One-click upload to your own image host.** Optional: configure Tencent COS, Qiniu Kodo, or Aliyun OSS once and the editor's upload button copies a public URL straight to your clipboard. Credentials stay on your Mac.
- **Built with pure AppKit.** No SwiftUI, no Electron, no telemetry. Small, fast, and respectful of macOS.

## Features

- **Edit any image directly** — select a single image file in Finder and trigger the screenshot shortcut to open that image in the annotation editor instead of taking a screenshot.
- **Fast region and window capture** — drag any area, or hover and click a detected window to snap to its bounds.
- **Multi-display support** — creates overlays on every connected screen and captures at full Retina resolution.
- **Full annotation editor** — rectangle, ellipse, arrow, pen, highlighter, mosaic, numbered callouts, and text.
- **Editable annotations** — move existing marks, change color and size, rotate supported annotations, bend arrows/callouts, edit text, delete marks, and use undo/redo.
- **Scroll capture** — capture a selected scrolling area, preview the stitched image live, and merge it back into the editor.
- **Beautify mode** — wrap screenshots in rounded corners, soft shadow, gradient presets, wallpaper background, and adjustable padding.
- **Color picker** — use the macOS color sampler, copy the picked hex value, and keep it in history.
- **Pin to screen** — float the current screenshot above other windows as a draggable reference image.
- **Save or copy** — save as PNG, confirm to copy PNG/TIFF data to the clipboard, or cancel without output.
- **Recent history** — menu bar history with thumbnails and picked colors for quick re-copy, with a configurable cache size.
- **Image-host upload** — optional one-click upload to Tencent COS, Qiniu Kodo, or Aliyun OSS; the public URL is copied to the clipboard.
- **Custom trigger** — use the default double-tap `⌘`, or record a custom global shortcut in Settings.
- **Menu bar app** — runs as an agent app without a Dock icon.

## Requirements

- macOS 14.0+
- Accessibility permission, used for the default double-tap `⌘` trigger
- Screen Recording permission, used by ScreenCaptureKit and screenshot capture
- Automation permission for Finder, requested on first use of the "edit selected image" shortcut

On first launch, capcap opens a setup window that shows permission states. The app can launch once both required permissions are granted.

## Install

Download the `.dmg` or `.zip` from [Releases](https://github.com/Licoy/capcap/releases/latest) and drag `capcap.app` into Applications.

### macOS Verification Warning

This fork packages releases with a **self-signed certificate** (not Apple Developer ID). If macOS shows a warning like `Apple cannot verify "capcap" is free of malware`, remove the quarantine flag from the app bundle you trust, then open it again:

```bash
xattr -dr com.apple.quarantine /Applications/capcap.app
```

If you are running a locally built copy, replace the path with your actual app location, for example:

```bash
xattr -dr com.apple.quarantine ./build/capcap.app
```

Only do this for builds downloaded from this repository or ones you built yourself.

## Build from Source

```bash
# Build and bundle build/capcap.app
./scripts/bundle.sh
```

For local development, this script rebuilds the app, kills any running instance, launches the new bundle, and verifies that it started:

```bash
bash scripts/rebuild-and-open.sh
```

To package a draggable DMG:

```bash
scripts/package-dmg.sh
```

The app bundle is output to `build/capcap.app`; DMGs are output to `dist/`.

## Usage

1. Double-tap `⌘ Command`, press your custom shortcut, or choose **Take Screenshot** from the menu bar.
2. Hover a window and click to capture it, or drag to select any region.
3. Use the floating toolbar to annotate, pick a color, start scroll capture, beautify, save, pin, cancel, or confirm.
4. Click the green checkmark or press `Enter` to copy the final image to the clipboard. Press `Esc` or click `x` to cancel.

To edit an existing image instead of taking a screenshot, click a single image file in Finder, then trigger the same shortcut.

## Editor Tools

| Tool | What it does |
|------|--------------|
| Rectangle / Ellipse | Draw outlined shapes with selectable colors and stroke widths |
| Arrow | Draw straight arrows; select an arrow later to move endpoints or bend the shaft |
| Pen | Draw smoothed freehand strokes |
| Highlighter | Draw semi-transparent marker strokes without darkening overlaps |
| Mosaic | Brush pixelated regions over sensitive content, with adjustable block size |
| Numbered | Add incrementing callout badges; drag while placing to add an arrow |
| Text | Add editable single-line text with color and 10-100 pt size controls |
| Eyedropper | Pick any screen color and copy its `#RRGGBB` value |
| Undo / Redo | Revert and restore editor changes |
| Move Selection | Drag the whole selected screenshot region after selection |
| Scroll Capture | Scroll inside the selected area, stitch frames, and continue editing the merged result |
| Beautify | Add gradient or wallpaper backgrounds, rounded corners, shadow, and padding |
| Save | Save the current result as a PNG |
| Pin | Keep the current result floating above other windows |
| Upload | Upload the current result to the configured image host and copy the public URL |
| Confirm | Copy the final result to the clipboard |

## Release notes (maintainers)

Pushing a `v*` tag triggers GitHub Actions to build and publish a release:

1. **Generate a self-signed certificate** (once):

   ```bash
   scripts/generate-signing-cert.sh
   ```

2. **Configure GitHub Actions secrets** (repo Settings → Secrets → Actions):

   | Secret | Value |
   |--------|-------|
   | `MACOS_CERTIFICATE` | Contents of `capcap-signing.p12.base64` |
   | `MACOS_CERTIFICATE_PWD` | `.p12` export password |
   | `MACOS_SIGNING_IDENTITY` | Certificate CN, default `capcap Self-Signed` |
   | `KEYCHAIN_PASSWORD` | Any throwaway string |

   See [scripts/signing/README.md](scripts/signing/README.md). **Do not** commit the `.p12` file.

3. **Bump version and trigger the build**:

   ```bash
   # Writes Info.plist versions, commits, creates annotated tag vX.Y.Z
   ./bump.sh -v 1.0.0

   # Push branch + tag (or pass -p to push in one step)
   git push origin HEAD && git push origin v1.0.0
   # equivalent: ./bump.sh -v 1.0.1 -p
   ```

## Project Structure

- `capcap/App/` — app entry point, delegate, and bundle metadata
- `capcap/Capture/` — overlay, selection, window detection, ScreenCaptureKit capture, scroll stitching, clipboard, and history
- `capcap/Editor/` — annotation models, editor canvas, floating toolbar, beautify rendering, mosaic, scroll preview, and pin windows
- `capcap/Trigger/` — double-tap `⌘` monitor and custom Carbon hotkey registration
- `capcap/UI/` — menu bar controller, toast, cursor chip, and tooltips
- `capcap/Settings/` — startup/settings window and preferences UI
- `capcap/Upload/` — image-host providers and the floating upload chip
- `capcap/Utilities/` — defaults, localization, update checks, and launch-at-login support
- `scripts/` — compile check, bundle, rebuild/open, icon, signing, and DMG helpers

## Development

```bash
# Fast compile validation for Swift-affecting changes
bash scripts/compile-check.sh

# Build, restart, and verify the local app
bash scripts/rebuild-and-open.sh
```

## Acknowledgments

- Upstream project: [realskyrin/capcap](https://github.com/realskyrin/capcap)
- Thanks to the [Linux.do](https://linux.do) community for testing, feedback, and discussion

## Third-Party Licenses

- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) is licensed under the MIT License. See [ThirdParty/PermissionFlow/LICENSE](ThirdParty/PermissionFlow/LICENSE).

## License

[MIT](LICENSE)
