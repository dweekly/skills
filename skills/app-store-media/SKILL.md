---
name: app-store-media
description: Produces App Store screenshots and the App Preview video for an iOS app from simulator captures, end to end, so that every size Apple accepts is covered, every caption is deliberate, and the result passes App Store Connect on the first upload. Covers which sizes are actually required, capturing clean demo state, scripted framing with brand captions, caption layout and ordering choices with the evidence behind them, a contact sheet for the owner's approval, machine validation, uploading, and measuring the result afterwards; and a preview video cut from UI-test takes by a JSON storyboard, with checks that prove it meets Apple's spec. Use when preparing or refreshing an App Store listing, adding a new device class such as iPhone Duo, or making a preview video; not for in-app UI design.
license: MIT
---

# App Store media

A listing's screenshots are the first thing most people see of an app, and the
work is mostly mechanical once the decisions are made. This skill is those
decisions, the reasons for them, and the tools, earned on two shipped apps in
2026. Read the reference that matches the step you are on; each one says
where its facts came from and when they were checked.

The plain version: capture the app on the largest iPhone and the 13-inch iPad
simulators with clean, realistic demo data; frame each capture with a short
benefit caption in the brand's colours; render one PNG per screen at every
accepted size (including iPhone Duo when the app supports it); show the owner a
contact sheet and get approval before anything is uploaded; validate sizes and
content by script; upload; and judge the result by downloads, not by the
weekly conversion percentage.

## Before you start: ask these up front

Ask them together, each with a recommended default, before capturing anything:

1. **Which screens, in what order?** Lead with the single strongest benefit,
   because App Store search results show only the first three screenshots.
   Default: the core action first (record, create, play), the payoff second,
   the organising view third.
2. **Caption layout?** Default: captions above every shot. See
   [references/practices.md](references/practices.md) for why, and for the
   alternating option and how to test it.
3. **Which device classes?** Default: every iPhone size Apple lists, the
   13-inch iPad if the app runs on iPad, and both iPhone Duo displays if the app
   supports Duo. See [references/apple-specs.md](references/apple-specs.md).
4. **A preview video?** Previews play before screenshots, so an out-of-date
   video undoes a new screenshot set. Default: remove an old-UI video for the
   release and make a new one as a follow-up.
5. **Release mechanics** (the owner's call): manual or automatic release after
   review, phased rollout or not, and what goes in What's New.

## The steps

1. **Read the live requirements.** Fetch Apple's screenshot specification page
   itself, not a summary of it, and grep the raw HTML for "Required". The
   required sizes changed in 2026 (the 6.3-inch iPhone became required).
   [references/apple-specs.md](references/apple-specs.md) records what the page
   said and when.
2. **Capture.** Simulator, pinned by UDID, status bar overridden to 9:41 and
   full bars, staging or demo data only, realistic names and content, no
   microphone recording of a real room.
   [references/capture.md](references/capture.md).
3. **Clean** what a debug build draws that the shipped app does not (staging
   badges, debug overlays, an iPadOS window-resize mark), with a script that
   says exactly which pixels it changed and why. Never retouch app content.
4. **Frame** with `scripts/frame_screenshots.swift <config.json>`, one config
   per app. [references/framing.md](references/framing.md) has the schema and
   the reasons for a drawn bezel instead of fastlane `frameit` or a device photo.
5. **Show a contact sheet** (every shot in store order, captions listed, raw
   captures one click away, the open decisions at the top) and iterate on copy
   and layout there. Cheap renders, fast loops; no upload until approved.
6. **Validate** with `scripts/check_screenshots.py <framed-dir>`: exact pixel
   sizes per class, no alpha channel, 1 to 10 per set, required classes present.
   Then the visual checklist in
   [references/validation.md](references/validation.md).
6b. **Header and search-results assets** (iOS 27 and later, optional): render
   with `scripts/creative_assets.swift <config.json> [--guides]`, inside the
   safe areas from Apple's templates, and approve them on the contact sheet too.
   For the header, a photographic scene of the app in use usually beats a
   screenshot strip: generate it with a chroma-key phone screen and place the
   real capture with `scripts/place_screen.py` (see references/practices.md).
6c. **Preview video** (optional): write the storyboard as a preview config,
   record UI-test takes with marks, then `scripts/preview_overlays.swift`,
   `scripts/preview_cut.py` and `scripts/check_preview.py`, and watch the
   candidate; it goes on the contact sheet for approval too. [references/preview-video.md](references/preview-video.md).
7. **Upload** to a new app version, through the App Store Connect API where a
   key exists, otherwise the web Media Manager.
   [references/upload.md](references/upload.md).
8. **Measure** after release: first-time downloads per week and product-page
   conversion, not the weekly email's impressions-based conversion, which
   swings with organic search spikes. Test layout or copy changes with Product
   Page Optimization rather than guessing. [references/practices.md](references/practices.md).

## Rules that hold every time

- **Every word on a screenshot lives in the config**, in store order, so copy
  edits never touch code. No em dashes in marketing copy unless the brand uses them.
- **Screenshots must be opaque.** App Store Connect rejects an alpha channel.
  The framer draws into an opaque context; the checker verifies it.
- **Frames are allowed on screenshots and banned in preview video.** Guideline
  2.3.4: previews "may only use video screen captures of the app itself".
- **A preview never carries captured audio.** Its track is generated silence,
  and the checker fails on any nonzero sample.
- **Show the real app.** No features the build does not have, no prices, no
  other platforms' devices, no competitor names. A shot that would oversell
  (for example large text where only part of the UI scales) waits.
- **Approval before upload**, and the upload goes to a new version, so the live
  listing is untouched until that version is released.
- **Record the run** in the app's own repo: which build the captures came from,
  the config, the decisions and who made them, and anything deliberately left out.

## References

- [references/apple-specs.md](references/apple-specs.md): accepted and required sizes for every iPhone, iPhone Duo and iPad class, the scaling chain, and the preview video spec, with sources and check dates.
- [references/practices.md](references/practices.md): ordering, caption length and placement, alternating layouts, panoramas, what evidence exists and what does not, and how to measure.
- [references/capture.md](references/capture.md): simulator capture, demo data, status bar, display selection on iPhone Duo, and pitfalls.
- [references/framing.md](references/framing.md): the framer, its config schema, layout rules per canvas shape, and why a drawn bezel.
- [references/validation.md](references/validation.md): the automated checks and the visual checklist.
- [references/upload.md](references/upload.md): new version, API upload with display-type names, web upload, release settings.
- [references/preview-video.md](references/preview-video.md): App Preview video end to end: storyboard, recording takes and marks, synthetic audio input, how the cut works, the checks and the visual review.
- [references/preview-config.md](references/preview-config.md): the preview config (storyboard as JSON) that the overlay, cut and check scripts share, with a worked example in references/examples/preview.example.json.
- [references/further-reading.md](references/further-reading.md): other public tools and skills worth studying, and what each does differently.
