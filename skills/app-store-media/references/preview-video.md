# App Preview video

Optional, but if one exists it plays before the screenshots, so a video of an
old UI contradicts a new screenshot set. Remove it on the new version rather
than ship the contradiction; make a new one as a follow-up.

## What a cut must satisfy

Apple's spec (see [apple-specs.md](apple-specs.md)): 15 to 30 s; 886x1920 for
every modern iPhone class, 1200x1600 for iPad 13"; H.264 High Profile at
Level 4.0 or below, max 30 fps, 10 to 12 Mbps VBR; an AAC stereo track (silent
is fine) at 44.1 or 48 kHz; no device frames, hands or fingers; text overlays
allowed if legible and price-free.

A raw `simctl io recordVideo` capture is never uploadable as is: on an iPhone
17 Pro Max simulator it is 1320x2868, High Profile Level 5.0, variable frame
rate and has no audio stream. Always re-encode.

## How to produce one

- **Storyboard first**: five or six beats that tell one real-time story (open
  on the product, the core action, its payoff, an end card), each with a
  caption readable for at least 2.5 s.
- **Record** a UI-test walkthrough with `xcrun simctl io <udid> recordVideo
  --codec h264 --mask ignored --force <file>` (wait for "Recording started" on
  stderr; SIGINT stops and finalises). Have the test write a timestamped mark
  at each beat.
- **Cut** per beat from the marks, normalise to exactly 30 fps, scale and pad
  to 886x1920, add title cards rendered by Core Graphics (some ffmpeg builds
  lack `drawtext`), add a silent stereo AAC track, encode H.264 High 4.0.
- Maestro's `record` command composites its command log beside the app, which
  Guideline 2.3.4 forbids; use in-flow `startRecording`/`stopRecording` or
  XCTest plus `simctl` instead.
- Audio for a recording app: feed synthetic speech through a test fixture;
  never record the room.

## Checks the cut must pass (machine-run)

1. Apple's limits: codec, profile and level, size, fps, duration, audio format.
2. Stricter house rules: exactly 30 fps, yuv420p, 24 to 28 s of video stream,
   audio no longer than video.
3. Each piece has the frame count and span its beat asked for (within two
   frames) and a playback rate of exactly 1.
4. Frame 0 and the frame at 5.0 s (the default poster) are lit: mean luma above
   60 of 255.
5. Beat table and manifest agree; captions on screen long enough; transitions accounted for.
6. Every check fails on a known-bad input (one-frame piece, black frame,
   reordered marks, wrong size, 25 fps, too short).

These came from a sibling app's pipeline (`app_preview.sh`, `preview_cut.py`,
`check_preview.py`, `preview_overlays.swift`), which is the place to start.
