# Framing: the script, its config, and why it works this way

```bash
swift scripts/frame_screenshots.swift <config.json>                         # captions above every shot
swift scripts/frame_screenshots.swift <config.json> --captions alternate    # above, below, above...
swift scripts/frame_screenshots.swift <config.json> --out <dir> --only iphone_6.9,ipad_13
```

Pure Core Graphics and Core Text on macOS; no ImageMagick, no Python imaging,
no network. Each run writes `<outDir>/<device key>/NN-<screen>.png`, opaque, at
exactly the canvas size, and prints a warning if a caption is taller than its zone.

## Config schema

Paths resolve relative to the config file; `--out` resolves relative to the working directory.

```json
{
  "rawDir": "../screenshots/raw-clean",       // contains one folder per "raw" key
  "outDir": "../screenshots/framed",
  "brand": {
    "gradientTop": "#6755BA",     // darker colour; text always sits on it
    "gradientBottom": "#7674E2",
    "accent": "#FEBE06",          // rule between headline and subheadline
    "headline": "#FFFFFF",
    "subheadline": "#FFFFFFE0",   // #RRGGBBAA allowed
    "headlineFont": "PostScript-Name-Heavy",
    "subheadlineFont": "PostScript-Name-Semibold",
    "fontFiles": ["fonts/Heavy.ttf", "fonts/Semibold.ttf"]   // registered for this process only
  },
  "layout": { "captionZone": 0.205 },          // optional overrides, see below
  "devices": [
    {"key": "iphone_6.9", "raw": "iphone_6.9", "copy": "iphone", "width": 1320, "height": 2868,
     "screenCornerRadius": 0.092, "fontScale": 1.0, "note": "shown on the contact sheet"}
  ],
  "copy": {
    "iphone": [{"file": "recording.png", "headline": "Record every\ndoctor visit",
                "subheadline": "Big, clear buttons. Pause whenever you need to."}]
  }
}
```

- One `devices` entry per output canvas. Several canvases can share one `raw`
  folder (every iPhone class from the 6.9" captures) and one `copy` list.
- `copy` lists are in store order; the output is numbered in that order.
  Explicit `\n` in an iPhone headline controls the break; wide canvases (iPad,
  Duo inner) use single-line headlines.
- A device whose `raw` folder does not exist is skipped with a message, so a
  config can name a class whose captures are still in progress.

### Per-canvas starting values

| Canvas | screenCornerRadius | fontScale |
|---|---|---|
| iPhone, any size | 0.092 | 1.0 |
| iPad 13" | 0.030 | 0.62 |
| iPhone Duo outer | 0.06 (check against the capture) | 0.85 |
| iPhone Duo inner | 0.04 (check against the capture) | 0.62 |

Text is sized from canvas width times `fontScale`, so wide canvases need a
smaller scale or the headline becomes enormous.

### Layout fractions (`layout` overrides)

`captionZone` 0.205 of height; `sideMargin` 0.085 of width each side;
`bezelThickness` 0.018 of bezel width; `headlineFont` 0.072 and
`subheadlineFont` 0.034 of the text unit; `maxOverflow` 0.05; `edgeMargin` 0.03.

## Placement rules

- **Captions above (default):** the phone is top-aligned under the caption and
  may hang off the bottom edge by up to `maxOverflow` of its height (on the
  ~2.17:1 phones the overhang is a few dozen pixels of home indicator). If it
  would hang off further, it shrinks to fit with `edgeMargin` to spare. That
  kicks in on 16:9 canvases (5.5", 4.7"), where cropping would hide the app's
  bottom controls.
- **Alternating:** even-numbered shots put the caption below; every phone
  always fits whole, sitting against its caption zone; the gradient flips so the
  darker colour is under the text.

The default layout is pinned: changing these rules must reproduce an approved
set byte for byte, or the change is a visual change that needs approval.
Check with `cmp` on a few files before and after.

## Why a drawn bezel

- **fastlane `frameit`** had no 13-inch iPad frame (its device list topped out
  at 2048x2732 in 2026) and adds an ImageMagick dependency.
- **Its frames are third-party renderings of Apple devices.** Apple's
  marketing guidelines say not to create illustrations depicting Apple
  products; Apple's third-party guidelines allow a device image only when it is
  an actual photograph of the genuine product.
- **Apple's Product Bezels** (Apple Design Resources) are licence-clean but
  strict: unmodified, no added shadows or reflections, no cropping or tilting,
  latest device only, copy beside the device rather than over it, full status bar.
- **The drawn bezel** is a dark rounded rectangle with a hairline highlight:
  no Dynamic Island, cameras or buttons, so it depicts no Apple product. It
  takes a drop shadow, which Apple's bezels would not allow.

## Fonts

Use the brand's licensed marketing face (register the files per process).
The system font is the fallback; SF Pro's licence is written around UI and
mockups of Apple platform software, which has not been checked against
marketing imagery.
