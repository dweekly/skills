# App Preview video

Optional, but if one exists it plays before the screenshots, so a video of an
old UI contradicts a new screenshot set. Remove it on the new version rather
than ship the contradiction; make a new one as a follow-up.

## What a cut must satisfy

Apple's spec (see [apple-specs.md](apple-specs.md)): 15 to 30 s; 886x1920 for
every modern iPhone class, 1200x1600 for iPad 13"; H.264 High Profile at
Level 4.0 or below, max 30 fps, 10 to 12 Mbps VBR; an AAC stereo track (silent
is fine) at 44.1 or 48 kHz, all tracks enabled; no device frames, hands or
fingers (Guideline 2.3.4); text overlays allowed if legible and price-free.

A raw `simctl io recordVideo` capture is never uploadable as is: on an iPhone
17 Pro Max simulator it is 1320x2868, High Profile Level 5.0, variable frame
rate and has no audio stream. Always re-encode.

## The pipeline

```bash
swift   scripts/preview_overlays.swift preview.json --out work/overlays
python3 scripts/preview_cut.py preview.json --out work \
          --raw walkthrough=takes/walkthrough.mov share=takes/share.mov \
          --marks walkthrough=takes/walkthrough.marks.tsv share=takes/share.marks.tsv
python3 scripts/check_preview.py work/candidate.mp4 --manifest work/cut.json
```

`preview.json` is the storyboard: brand, takes and beats, with every caption
([preview-config.md](preview-config.md), worked example in
[examples/preview.example.json](examples/preview.example.json)). Only a
candidate that passes every check is copied to wherever the listing's media
lives. `bash scripts/test_preview_pipeline.sh` runs all three on synthetic
takes and is the first thing to run after changing any of them.

Every frame of the film has one shape: a band across the top in the brand's
darker colour holding either the logo, app name and tagline (opening and end)
or one caption line with an optional disclosure line, and the app footage
scaled uniformly to fit below the band, centred, on the brand gradient.
Nothing jumps at a transition and no app text is ever covered. Beats play at
recorded speed and are joined by 0.4 s dissolves; captions fade with their
beat. That shape came out of a sibling app's review of its first cut, which
opened on a text card, replayed navigation at 3x and 4x, and stopped the film
with full-frame cards; all three read as frenetic to a muted viewer.

## Storyboard first

Five or six beats that tell one real-time story: open on the product (logo
band over a real screen), the core action, its payoff, one or two supporting
features, an end card. Each caption one line of at most five words, readable
for at least 2.5 s. A feature that needs an account gets a disclosure line.
The default poster frame is at 5.0 s, so something good must be on screen
there. Put motion in the app area early (by about 2 s): a long opening still
followed by a resting screen makes the first movement land after 5 s.

Recording order need not be story order. A screen that ends the take with
something drawn by another process (a review prompt, a permission sheet) goes
last in the recording, or is suppressed under the UI test's launch argument.

## Recording takes

- Simulator pinned by UDID, status bar overridden (9:41, full bars, charged),
  demo data only, as in [capture.md](capture.md).
- `xcrun simctl io <udid> recordVideo --codec h264 --mask ignored --force take.mov`
  in the background. `--mask ignored` keeps the full rectangular framebuffer;
  the default mask burns in black rounded corners. Wait until "Recording
  started" appears on its stderr, then note the epoch time: that instant is
  frame 0 of the take. SIGINT stops and finalises the file.
- Run the UI test that drives the flow (`xcodebuild test-without-building
  -only-testing:...`) while recording, then stop the recorder.
- One take or several. Several short takes (one per feature) are easier to
  retake; one walkthrough keeps continuity. A beat names its take.

### Marks

The UI test prints a mark at the start and end of every beat:

```swift
func mark(_ name: String) {
    print("PREVIEW_MARK \(name) \(Date().timeIntervalSince1970)")
}
```

and the script that ran it turns them into a marks file, offsets from the
recorder's start epoch, in emitted order:

```bash
grep -o "PREVIEW_MARK [A-Za-z0-9_]* [0-9.]*" test.log \
  | awk -v t0="$RECORD_EPOCH" '{ printf "%s\t%.3f\n", $2, $3 - t0 }' > take.marks.tsv
```

What makes marks trustworthy:

- **Resolve every element a beat touches before its start mark.** An XCUITest
  query on a long list can take seconds; one between a mark and its gesture
  pushes the gesture out of the beat.
- **Hold each beat at least its length**, with slack, before the end mark. The
  cutter fails when an end mark comes sooner than the beat needs.
- **Assert the beat's outcome before its end mark** (the row moved, the sheet
  is in its intended state), so a take that did not do the thing fails as a test.
- **The start of a piece is only as exact as the recorder-start poll.** Polling
  for "Recording started" every 0.2 s means up to six frames of offset. The
  checker proves each piece's length; whether a piece starts on its event is
  on the visual review.

### Audio, for an app that listens

The film itself is always silent: the cutter adds generated digital silence
and the checker fails on any nonzero sample, so no captured sound can reach
the store. But an app whose screens react to sound (a recorder's level meter,
live transcription) needs input while the take is recorded. Feed it synthetic
speech through a virtual audio device such as BlackHole, selected as **the
simulator's** input only (Simulator > I/O > Audio Input), and play a
synthetic or licensed clip into it. Never change the Mac's system input,
never record the room, never use a real person's voice without consent.

## How the cut works

- **Normalise first.** `simctl` writes variable-frame-rate video that carries
  a frame only when the screen changes, so a static hold is one frame
  followed by nothing. Trimming that stream at a mark inside a hold drops the
  frame on screen, and resetting timestamps closes the gap: a sibling app's
  first cut encoded a 2.4 s beat as one frame this way, and the total-length
  check still passed. Simulator recordings can also carry non-monotonic decode
  timestamps. So each take is decoded once with `-fflags +igndts` through
  `fps=30` (which repeats a held frame across its hold) and reset to start at
  zero; every beat is then cut by frame number on that dense timeline. The
  checker's self-test reproduces the defect on a synthetic sparse take and
  proves the cutter's normalisation recovers the beat.
- **Compose** each beat as its own piece: background, footage at the fitted
  rectangle, band (fading for captions), composited in RGB and converted once
  to BT.709 yuv420p.
- **Assemble** with `xfade` after every piece is normalised to the same size,
  format, rate and timebase, encoded once to H.264 High 4.0 at 10 to 12 Mbps.
- **Audio** is added after assembly: generated stereo silence, a whole number
  of AAC frames, never longer than the video.

## Checks

`check_preview.py <candidate> --manifest cut.json` prints one line per check
and exits non-zero if any fails:

1. **[Apple]** H.264, profile High or below, level 4.0 or below, an accepted
   preview size, at most 30 fps, 15 to 30 s of video stream, at most 500 MB,
   AAC stereo at 44.1 or 48 kHz, every track enabled (read from each track's
   `tkhd` flags).
2. **[house]** exactly the configured size, exactly 30 fps constant, yuv420p,
   audio no longer than the video, audio that is digital silence (astats
   overall peak of -inf dB over a nonzero number of samples), frame 0 and the
   frame at 5.0 s lit (mean luma above 60 of 255, measured on the frame at
   that time, never the keyframe a seek lands on).
3. **[manifest]** every piece decodes to its beat's frame count within two
   frames and plays at rate 1; every caption readable for at least 2.5 s;
   one transition per pair of beats; the candidate's frame count matches.

`check_preview.py --self-test` proves each check can fail: wrong size, 25 fps,
10 s, Level 5.1, no audio, a quiet tone, audio longer than video, a disabled
track, black frame 0, a black poster frame behind a bright keyframe, a
one-frame beat, an unreadable caption, a sped-up beat and a short candidate
each fail their check, and a known-good file passes them all.

## What only a person can check

Watch the candidate at full size and once at phone size, muted:

- Each beat starts on its event and shows the outcome it claims.
- No app text is cut off or covered; no system prompt from another process.
- Captions match what is on screen at that moment, and read in time.
- The opening and the frame at 5.0 s are good enough to be the poster.
- Nothing shows a feature the build lacks, a price, or another platform.

## Other tools

Maestro's `record` command composites its command log beside the app, which
Guideline 2.3.4 forbids; use in-flow `startRecording`/`stopRecording` or
XCTest plus `simctl` instead.
