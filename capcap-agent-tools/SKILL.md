---
name: capcap-agent-tools
description: Use this skill whenever an agent needs to autonomously edit a user-provided image, capture screenshots, enumerate windows, annotate images, or produce visual evidence using capcap's headless `capcap agent` commands. Trigger for requests about editing an attached image, agent screenshots, headless screenshot workflows, visual bug reports, marking UI pixels, drawing arrows/boxes/text on screenshots, or creating final result images without human GUI interaction.
---

# capcap Agent Tools

Use capcap as a headless visual-output tool for agents. The user does not need to operate the GUI: commands return PNG files and JSON metadata that another agent can inspect, transform, or pass along.

## Binary

Prefer a `CAPCAP` shell variable so the same workflow works for installed users and development checkouts:

```bash
CAPCAP="/Applications/capcap.app/Contents/MacOS/capcap"
```

If the app is installed somewhere else, locate it first:

```bash
CAPCAP="$(mdfind 'kMDItemCFBundleIdentifier == "com.github.licoy.capcap.desktop"' | head -n 1)/Contents/MacOS/capcap"
```

In a development checkout, use the debug binary after a Swift build:

```bash
CAPCAP=".build/debug/capcap"
```

If it is missing or stale, run:

```bash
bash scripts/compile-check.sh
```

For an installed app, do not assume `capcap` is on PATH. The app bundle contains the executable, but the bare shell command works only if the user has created a wrapper, symlink, or alias such as:

```bash
alias capcap='/Applications/capcap.app/Contents/MacOS/capcap'
```

All commands below use `$CAPCAP`; set it before running the workflow.

## Core Model

- Commands are headless: they should not open the editor, menus, save panels, or toast UI.
- If the user has already attached or pasted an image, treat that image as the
  input to edit. Do not capture the current screen, current window, browser tab,
  or chat UI to recreate the image unless the user explicitly asks for a fresh
  screenshot or the provided image is unavailable.
- Output images are PNG files.
- Command results are JSON on stdout. Use `--meta path.json` to also write metadata to a file.
- Capture and annotation metadata use `coordinateSpace: "pixels"` and `origin: "top-left"` for images.
- Window enumeration uses global CG coordinates with top-left origin.
- Prefer temporary files under `mktemp -d` for intermediate screenshots and specs.

## Recommended Workflows

### 1. Edit A User-Provided Image

Use this when the user has already provided an image and asks to mark,
highlight, blur, mosaic, magnify, draw around, label, or otherwise edit it. The
user's image is the source of truth.

```bash
tmpdir=$(mktemp -d)
input="$tmpdir/input.png"
# Put the user-provided image at $input using the file/path/reference exposed by
# the host environment. Do not screenshot the chat or browser to obtain it.
```

Inspect the provided image, create `marks.json`, then render:

```bash
"$CAPCAP" agent annotate --input "$input" --spec "$tmpdir/marks.json" --out "$tmpdir/result.png" --meta "$tmpdir/result.json" --pretty
```

Return or attach `result.png` as the final edited image. Only ask the user for a
file path or re-upload when the provided image is visible in the conversation
but unavailable to tools as an input file.

### 2. Capture, Inspect, Annotate

Use this when the agent needs to look at the screenshot before deciding marks.
Do not use this workflow when the user already supplied the image to edit.

```bash
tmpdir=$(mktemp -d)
"$CAPCAP" agent capture --target mouse-screen --out "$tmpdir/shot.png" --meta "$tmpdir/shot.json" --pretty
```

Inspect `shot.png`, create `marks.json`, then render:

```bash
"$CAPCAP" agent annotate --input "$tmpdir/shot.png" --spec "$tmpdir/marks.json" --out "$tmpdir/result.png" --meta "$tmpdir/result.json" --pretty
```

Return or attach `result.png` as the final visual evidence.

### 3. One-Step Capture And Render

Use this when the agent already knows the target and marks.
Do not use this workflow when the user already supplied the image to edit.

```bash
"$CAPCAP" agent run \
  --target rect \
  --rect 0,0,800,600 \
  --spec marks.json \
  --out result.png \
  --shot-out shot.png \
  --meta result.json \
  --pretty
```

`--shot-out` is optional. Use it when the raw screenshot may be useful for debugging or later analysis.

### 4. Window-Targeted Capture

First list windows:

```bash
"$CAPCAP" agent windows --limit 20 --pretty
```

Filter if useful:

```bash
"$CAPCAP" agent windows --owner Safari --limit 10 --pretty
"$CAPCAP" agent list-windows --frontmost-only --pretty
```

Capture a returned `windowID`:

```bash
"$CAPCAP" agent capture --target window-id --window-id 12345 --out shot.png --meta shot.json --pretty
```

Then annotate with `agent annotate`, or combine target and spec with `agent run`.

## Capture Commands

### List Windows

```bash
"$CAPCAP" agent windows --pretty
```

Options:

- `--owner TEXT`: case-insensitive owner app filter
- `--title TEXT`: case-insensitive title filter
- `--limit N`: maximum number of windows
- `--frontmost-only`: return only the frontmost app's top normal window
- `--all` or `--include-system`: include menu bar, Control Center, popups, and other system surfaces
- `--meta path.json`: write metadata to a file
- `--pretty`: pretty-print JSON

Default `windows` output lists normal app windows only (`layer == 0`). Add `--all` only when the target is a menu bar item, popup, or other system surface.

Each window includes:

- `windowID`: pass this to `--window-id`
- `ownerName`, `ownerPID`, `title`
- `frame`: global CG rect `[x, y, width, height]`
- `usesCompositedScreenBackdrop`: true for high-layer system surfaces
- `captureTarget` and `captureCommand`: ready-to-use capture hints

### Capture Screenshot

```bash
"$CAPCAP" agent capture --target mouse-screen --out shot.png --pretty
```

Targets:

- `screen`: full screen; optional `--screen-index N` or `--display-id ID`
- `mouse-screen`: full screen containing the cursor
- `rect`: global CG rect, requires `--rect x,y,width,height`
- `window-id`: exact WindowServer window, requires `--window-id ID`
- `window-at-cursor`: topmost window under the current cursor
- `frontmost-window`: top normal window owned by the frontmost app

Examples:

```bash
"$CAPCAP" agent capture --target rect --rect 0,0,300,200 --out shot.png --meta shot.json --pretty
"$CAPCAP" agent capture --target frontmost-window --out shot.png --pretty
"$CAPCAP" agent capture --target window-at-cursor --out shot.png --pretty
```

For window capture, prefer `windows` -> `window-id` when deterministic selection matters.

## Annotation Spec

Annotation specs are JSON:

```json
{
  "version": 1,
  "coordinateSpace": "pixels",
  "origin": "top-left",
  "annotations": [
    {
      "type": "rect",
      "rect": [80, 80, 280, 120],
      "color": "#FF3B30",
      "lineWidth": 5
    },
    {
      "type": "arrow",
      "from": [520, 240],
      "to": [350, 140],
      "color": "#FF3B30",
      "lineWidth": 6
    },
    {
      "type": "text",
      "at": [92, 52],
      "text": "Agent note",
      "fontSize": 28,
      "color": "#FF3B30",
      "stroke": true
    }
  ]
}
```

Supported annotation types:

- `rect`, `rectangle`, `box`: needs `rect`
- `ellipse`, `oval`, `circle`: needs `rect`
- `arrow`: needs `from` and `to`; optional `style`, `controlPoint`
- `line`: needs `from` and `to`
- `text`, `label`: needs `at` and `text`
- `number`, `numbered`, `badge`: needs `center`; optional `number`, `tip`
- `mosaic`, `pixelate`, `blur`: needs `rect`
- `magnifier`, `loupe`: needs `center`; optional `radius`, `zoom`, `source`
- `pen`, `path`: needs `points`
- `marker`, `highlight`, `highlighter`: needs `points`

Common fields:

- `color`: `#RRGGBB`, `#RGB`, or `#RRGGBBAA`
- `lineWidth`: positive number
- `rotationDegrees` or `rotationRadians`: for supported types
- `fill` or `fillMode`: `none`, `opaque`, `translucent`
- `strokeStyle`: `standard` or `hand-drawn`

## Rendering An Existing Image

```bash
"$CAPCAP" agent annotate \
  --input shot.png \
  --spec marks.json \
  --out result.png \
  --meta result.json \
  --pretty
```

Use this after the agent has inspected `shot.png` and chosen exact pixel coordinates.

## One-Step Run

```bash
"$CAPCAP" agent run \
  --target mouse-screen \
  --spec marks.json \
  --out result.png \
  --meta result.json \
  --pretty
```

`agent run` supports the same target options as `agent capture`, plus:

- `--spec path.json`
- `--out result.png`
- `--shot-out raw.png` for optional raw screenshot output

## Practical Agent Guidance

- When the user attaches or pastes an image with edit instructions, edit that
  original image with `agent annotate`; do not capture the visible chat message,
  browser page, or desktop copy of it.
- For visual bug reports, capture first, inspect the PNG, then annotate. This avoids guessing coordinates.
- Use `windows --frontmost-only` when the user is clearly referring to the active app.
- Use `windows --owner NAME` when the target app is known.
- Use `rect` when another tool already provides exact coordinates.
- Use red `#FF3B30` for primary marks unless the user asked for another color.
- Prefer short visible labels; the final image should be useful without a long explanation.
- Keep all paths absolute or inside a temp directory, and report the final PNG path.

## Troubleshooting

- If capture fails, check macOS Screen Recording permission for the binary being run.
- If `capcap: command not found`, set `CAPCAP="/Applications/capcap.app/Contents/MacOS/capcap"` or create a shell alias/wrapper.
- If an installed app does not recognize `agent`, it is an older capcap build. The headless commands require a release that includes the Agent Tools feature.
- If `window-at-cursor` is unstable, use `agent windows` and capture by `window-id`.
- If system menu bar items appear before app windows, rerun `agent windows` without `--all`.
- If a high-layer system surface has `usesCompositedScreenBackdrop: true`, capcap may capture it through a composited rect path instead of direct window capture.
- If coordinates look vertically flipped, remember specs use image pixels with top-left origin, not AppKit bottom-left coordinates.
