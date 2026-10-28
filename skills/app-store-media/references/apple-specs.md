# Apple's screenshot and preview requirements

Source: Apple, [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
and [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications),
App Store Connect Help. **Checked 2026-10-28** by fetching the raw HTML and
grepping it, because summarising tools have dropped the "Requirement" cells
before. Re-check before every release: the required set changed during 2026.

```bash
curl -sL https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications \
  | python3 -c "import sys,re,html; t=html.unescape(re.sub(r'<[^>]+>','\n',sys.stdin.read())); \
    [print(t[m.start()-80:m.start()+300].replace('\n',' ')) for m in re.finditer('Required|Duo',t)]"
```

## Screenshots: general

- 1 to 10 screenshots per display size per locale; `.png`, `.jpg` or `.jpeg`.
- **No alpha channel or transparency.**
- Portrait or landscape at the exact listed pixel sizes. Any other size is refused at upload.
- Screenshots can be changed only on a new app version once a version is approved.

## Required sizes (as of 2026-10-28)

The page has a "Required device sizes" section:

> To submit your app, you must provide screenshots for the following required display sizes:
> iPhone: At least one screenshot for iPhone with Dynamic Island (medium display).
> iPad (if your app supports iPadOS): At least one screenshot for iPad 13-inch display.

That is new relative to September 2026, when the page made the large classes
(6.9" or 6.5") the requirement and let every smaller class scale down. The
per-row notes still describe scaling, so the page now contradicts itself;
supplying the 6.3" set removes the question. The 6.5" row still reads
"Required if app runs on iPhone and screenshots for iPhone with Dynamic Island
(large display) aren't provided".

## iPhone classes (portrait sizes; landscape is the transpose)

| Class | Common name | Devices (examples) | Accepted sizes | If not provided |
|---|---|---|---|---|
| Dynamic Island, large | 6.9" | Air, 17 Pro Max, 16 Pro Max, 16 Plus, 15 Plus | 1260x2736, 1290x2796, **1320x2868** | scaled from Face ID large |
| Face ID, large | 6.5" | 11 Pro Max, XS Max | 1284x2778, **1242x2688** | scaled from Dynamic Island large |
| Dynamic Island, medium | 6.3" | 17 Pro, 17, 16 Pro, 16, 15 Pro, 15 | 1179x2556, **1206x2622** | **Required** (see above) |
| Face ID, medium | 6.1" | 17e, 16e, 14, 13, 12, X | **1170x2532**, 1125x2436, 1080x2340 | scaled from Dynamic Island medium |
| Home Button, large | 5.5" | 8 Plus, 7 Plus | 1242x2208 | scaled from Face ID medium |
| Home Button, medium | 4.7" | SE (2nd, 3rd gen), 8 | 750x1334 | scaled from 5.5" |
| Home Button, 4" and 3.5" | | SE (1st), 5s, 4s | 640x1136 / 640x960 | scaled from the next class |

Bold sizes are what the framer emits by default. The simulator that captures
1320x2868 natively is the iPhone 17 Pro Max.

Check the app's deployment target against the small classes: an app with a
minimum of iOS 17 still runs on iPhone SE (2nd and 3rd generation, 4.7"),
whose 750x1334 screen is a different shape (16:9) from every Face ID phone.
Framing for that canvas has to shrink the phone rather than crop it, or the
bottom controls disappear (see [framing.md](framing.md)).

## iPhone Duo

| Display | Accepted sizes |
|---|---|
| Outer (closed) | 1398x2034 portrait, 2034x1398 landscape |
| Inner (open) | 2007x2853 portrait, 2853x2007 landscape |

> Starting in April 2027, screenshots will be required for any app using the
> iOS 27.1 SDK or later.
>
> When you submit iPhone Duo screenshots in App Store Connect, your App Store
> product page will display a badge to let people know your app is optimized for iPhone Duo.

The page does not say whether both displays are required; supply both.

## iPad classes

| Class | Accepted sizes | Note |
|---|---|---|
| 13" | **2064x2752**, 2048x2732 | "Required if app runs on iPad" |
| 12.9" (2nd gen) | 2048x2732 | scaled from 13" |
| 11" | 1488x2266, 1668x2420, 1668x2388, 1640x2360 | scaled from 13" |
| 10.5", 9.7" | 1668x2224; 1536x2048 | scaled down the chain |

One 13" set covers every iPad. The iPad Pro 13-inch (M4 or M5) simulator captures 2064x2752.

## App Preview video (summary; detail in preview-video.md)

- Optional; 15 to 30 seconds; up to 3 per size per locale; max 500 MB.
  Previews always play before screenshots.
- Upload resolution is not the device resolution: every modern iPhone class
  uploads at **886x1920** portrait; iPad 13" at **1200x1600**.
- H.264 up to High Profile Level 4.0 (or ProRes 422 HQ), 10 to 12 Mbps VBR,
  max 30 fps, `.mov`/`.m4v`/`.mp4`. HEVC is not listed.
- An audio track is mandatory: AAC 256 kbps, 44.1 or 48 kHz, stereo, all tracks enabled.
- No device hardware, frames, hands or fingers (Guideline 2.3.4). Text
  overlays are allowed, must be legible, must not show prices.
- Poster frame defaults to 5 s in; processing can take up to 24 hours.

## Google Play, for the Android side

Phone screenshots: 2 to 8, JPEG or 24-bit PNG with no alpha, each side 320 to
3840 px, long side at most twice the short side; at least four at 1080 px or
better recommended. Tablets want strict 9:16 or 16:9, so iPad captures cannot
be reused. Also a 512x512 icon and a 1024x500 feature graphic. A promo video is
a YouTube URL only. Source: Play Console Help, "Add preview assets" (checked September 2026).
