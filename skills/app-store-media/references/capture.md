# Capturing clean raw screenshots

The raw capture is the only part that shows the real app, so it carries the
honesty of the whole set. For driving the simulator itself (picking a device by
runtime, UDIDs, XCTest versus AXe versus Maestro, iPhone Duo displays) use the
`ios-simulator-qa` skill; this file covers what is specific to store media.

## Devices

| Set | Simulator | Native capture |
|---|---|---|
| iPhone (all classes) | iPhone 17 Pro Max | 1320x2868 |
| iPad 13" | iPad Pro 13-inch (M4 or M5) | 2064x2752 |
| iPhone Duo outer / inner | iPhone Duo | see `simctl io enumerate` |

Capture once on the largest iPhone; the framer seats that capture into every
smaller iPhone canvas. Capturing on each smaller phone is not needed: inside a
bezel at thumbnail size the difference does not show, and it multiplies the
state you have to reproduce. The exception is a layout that genuinely differs
by size class (iPad, the Duo's inner display), which gets its own capture.

Pin every simulator by UDID. Other sessions may be driving other simulators;
never `shutdown` or `erase` one you did not create.

## Status bar

```bash
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3
```

`--time` takes `HH:MM`; ISO date strings are rejected despite the help text
(seen on iOS 26.5 and 27.x runtimes). The override applies to screenshots and
to `recordVideo`. Apple's bezel guidelines also ask for full signal, Wi-Fi and battery.

## Demo data

- Use a dedicated staging or demo account whose content you control. Shared
  test accounts leak other testers' rooms, names and junk into lists.
- Realistic, specific, plausible content: real-sounding names, a believable
  appointment, a transcript that reads like a person talking. Never "Lorem
  ipsum", "Test", "John Doe", "TODO", or obviously fake numbers.
- No real people's data, ever, including the developer's own family or patients.
- Synthetic media: generate speech with `say` (two voices for a dialogue) and
  feed it through a test fixture rather than the simulator microphone, which
  records whatever is in the room. Delete any accidental room recording from
  the staging backend, not just from the device.
- Dates: pick a day and time the captures can share, and let relative labels
  ("Today", "Upcoming") agree with it.

## Getting to each screen

Drive the app with launch arguments and test fixtures the app already has
(skip tutorials, preset consent, a fixture upload) rather than tapping through
long flows by coordinates. Wait for the screen to settle: no spinners, no
skeletons, no half-loaded names, no transient toasts. Take the screenshot with
`xcrun simctl io "$UDID" screenshot --type=png <file>` (add `--display=<id>`
on a multi-display device).

## iPhone Duo

`xcrun simctl io "$UDID" enumerate` lists the screens and their selectors for
`screenshot --display=...`; discover the IDs each time. Powering a display on
or off with `screenConfig` is not a fold pose. The pose is set by hand in
Xcode's Device Hub (`Xcode.app/Contents/Applications/DeviceHub.app`), not in
Simulator.app, with no supported command-line API (Xcode 27.1). ios-simulator-qa's
`scripts/duo-pose <UDID> open` sets it from a script and confirms it; if that
fails, ask the person to choose it once in Device Hub, confirm it in a
screenshot, then capture unattended. A
simulator reboot puts it back to closed; see ios-simulator-qa's
`references/duo.md`.

Seen on the iOS 27.1 runtime (October 2026): the Duo device type needs the
27.1 runtime or later (`xcodebuild -downloadPlatform iOS`); `screenConfig
power` on a Duo display crashed SpringBoard rather than changing the pose; and
AXe 1.8.0 taps reported success but never reached the outer display, while
AXe `type` and `describe-ui` worked and the Xcode MCP device-interaction tool's
taps and swipes did. Check the outer display's side column (camera and status
bar) in every capture: an app whose headers stop at the safe area leaves a
white strip there, which is an app defect to fix before shipping Duo screenshots.

## What a debug build adds, and how to remove it

Fix in a cleaning script, never by hand, and log every touch-up:

- staging or debug badges and banners;
- the iPadOS window-resize mark in the bottom-right corner;
- a status bar that a debug-only path draws in the wrong colour (better: fix
  the app and recapture).

Never retouch app content (text, data, layout). If a screen looks wrong, that
is an app bug: file it, fix it, recapture.

## What not to capture yet

Leave out a screen that would oversell the shipped build: a large-text
screenshot where only part of the UI scales, a feature behind a flag, a state
that needs data the demo account cannot have cleanly. Write the omission and
its reason into the run record so the next session knows it was deliberate.
