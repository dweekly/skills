# Preview config: the storyboard as JSON

One JSON file describes a whole App Preview: the brand, the takes it is cut
from, and the beats in story order with their captions. Three scripts read it:
`preview_overlays.swift` renders the band images, `preview_cut.py` cuts and
assembles the film, and `check_preview.py` validates the result against the
manifest the cutter writes. Every word on screen lives in this file, so a copy
change never touches code. A complete example is in
[examples/preview.example.json](examples/preview.example.json);
`scripts/test_preview_pipeline.sh` runs that exact file end to end on
synthetic takes.

Paths resolve relative to the config file's directory.

## Top level

| Field | Default | Meaning |
|---|---|---|
| `brand` | required | The framer's brand block (see [framing.md](framing.md)), inline, or a string path to the framer's config, whose `brand` is then used. `gradientTop` is the band colour and the top of the background gradient; `gradientBottom` its bottom; `headline` colours the caption and app name (default white); `subheadline` colours the disclosure and tagline (default `#FFFFFFE0`); `headlineFont` and `subheadlineFont` are PostScript names; `fontFiles` are registered for the run only. `accent` is accepted and unused. |
| `logo` | none | Image for the logo band, drawn at the app name's height beside it. Without it the logo band shows the name only. |
| `appName` | required | Shown in the logo band. |
| `tagline` | none | The logo band's second line; a beat's own `tagline` overrides it. Every logo band needs one or the other. |
| `width`, `height` | 886, 1920 | Output size. 886x1920 is the upload size for every modern iPhone class. |
| `fps` | 30 | Whole number, at most 30 (Apple's maximum). The house rule, and the checker's default, is exactly 30. |
| `bandRatio` | 0.14 | Band height as a fraction of `height`, rounded to an even pixel count (268 of 1920). It fits a caption plus a disclosure line, or the logo row plus a tagline, and leaves 760 px of footage width from a 1320x2868 capture. |
| `textScale` | 1.0 | Multiplies every text size in the band. A larger band (`bandRatio`) with a larger `textScale` gives more prominent copy. |
| `dissolve` | 0.4 | Seconds of cross-fade for a dissolve join (12 frames at 30 fps), and whether joins default to dissolves: when it is `0`, every join defaults to a hard cut. |
| `captionFade` | 0.3 | Seconds a caption takes to fade in at the start of its beat and out at the end. Logo bands do not fade. |
| `captionMinReadable` | 2.5 | Floor, in seconds, for how long each caption is fully on screen (see "Readability" below for cards). |
| `takes` | required | Object of take name to take, below. |
| `beats` | required | List of beats in story order, below. |

## Takes

```json
"takes": {
  "walkthrough": {"raw": "takes/walkthrough.mov", "marks": "takes/walkthrough.marks.tsv",
                  "expectMarks": ["home", "homeEnd", "compose", "composeEnd"]}
}
```

- `raw`, `marks`: optional here; `--raw name=path` and `--marks name=path`
  on the cutter's command line override them, and a config with a single
  take also accepts bare paths.
- `expectMarks`: optional. When present, the marks file must hold exactly
  these names in this order. Use it: a reordered or repeated mark is a broken
  take, and the cutter never sorts or dedupes marks.

A **marks file** is one `name<TAB>seconds` line per mark, in the order the UI
test emitted them, where seconds are measured from the recorder's first frame
(see [preview-video.md](preview-video.md#marks)). Names must be unique and
times strictly increasing. `first` and `last` are reserved.

## Beats

Every beat has a length in `seconds` and is a recording, a still, or a card.
Recordings and stills name their `take`; a card has none.

| Field | Meaning |
|---|---|
| `name` | Unique; names the piece and band files. |
| `take` | A key of `takes`. |
| `seconds` | The beat's own length. Consecutive beats overlap by the dissolve, so the film runs the sum of beats minus one dissolve per join. |
| `start_mark`, `end_mark` | Recording beat: footage starts at `start_mark` and runs `seconds`; `end_mark` must come at least `seconds` later, which proves the take held the screen long enough. Footage beyond `seconds` is not used. |
| `still` | Still beat, instead of the marks: `"first"` or `"last"` frame of the take, or a mark name for the frame at that mark. Held for `seconds`. |
| `band` | `"caption"` or `"logo"`. Default: caption when `caption` is set, else logo. |
| `caption` | One line, at most about five words. Shrinks to fit the width, with a warning below 75%. |
| `disclosure` | Optional second line under a caption, for a feature that needs an account or a purchase. |
| `tagline` | Logo band only: overrides the config's `tagline` (an end card usually says something different from the opening). |
| `card` | `true` makes the beat a brand card: the full frame (no band, no footage) is the brand gradient with `caption` large and centred, wrapping to at most 3 lines, and an optional smaller `subline` (at most 2 lines). The scripts fail if either needs more lines. |
| `subline` | Card only: the smaller line under the card's caption. |
| `transitionIn` | `"cut"` or `"dissolve"`: how this beat is joined to the one before it (ignored on the first beat). Default: dissolve when the config's `dissolve` is above 0, else cut. Cards normally use `"cut"`, set on the card and on the beat after it. |

A **card** is a short brand interstitial between views, typically about a
second, joined by hard cuts. Card text is sized from frame width (caption
0.085, subline 0.040, times `textScale`) and does not fade; it is rendered by
`preview_overlays.swift` as `band_NN_<name>.png` (opaque, full frame) and
listed in `overlays.json`, so the stale-overlay check covers it.

## Readability

Apple asks that text stay on screen long enough to read. A caption beat's
readable time is its length minus, at each end, the larger of the caption fade
and any dissolve there. A card's is its length minus any dissolve overlaps
(cards do not fade). A card followed directly by a caption beat whose
`caption` is identical is one caption run, and the floor applies to the run
(the card's readable time plus the beat's): a 1.2 s card cut into a beat that
repeats its caption passes. A card whose caption the next beat does not repeat
must meet the floor alone, so the same 1.2 s card before a different caption
fails. The cutter refuses a config that misses the floor, and
`check_preview.py` recomputes the runs from the manifest.

`"first"` of a full walkthrough is usually the home screen before the app
launched; prefer a mark (`"still": "home"`) for an opening card. `"last"` is
right when the take was stopped on the screen you want to end on, but note
that a take's normalised length ends at its last *changed* frame: a static
screen held at the very end of a recording may contribute no frames, and the
cutter fails rather than invent them. End the UI test with a short movement
after the final hold, or take the end still from a mark.

## What the scripts write

`preview_overlays.swift <config> --out <dir>`:
`background.png` (opaque gradient with the band filled), one
`band_NN_<beat>.png` per beat (transparent except the band's text), and
`overlays.json` (size, band height and every word drawn). The cutter compares
`overlays.json` with the config and refuses overlays rendered from an older
config.

`preview_cut.py <config> --out <dir> [--raw ...] [--marks ...] [--overlays <dir>]`
(overlays default to `<dir>/overlays`): `normalised_<take>.mp4`, one
`piece_NN_<beat>.mp4` per beat, `candidate.mp4`, and `cut.json`, the
manifest: every take (path, size, mtime, frame count, marks, footage
rectangle), every beat (frames, source frame or still frame, band text,
readable time and any caption run, transition in, timeline in and out), the
transitions (`cut` with 0 frames or `dissolve` with its overlap), the total
frame count (beats minus dissolve overlaps) and the audio description.

`check_preview.py <dir>/candidate.mp4 --manifest <dir>/cut.json`: see
[preview-video.md](preview-video.md#checks).

## Layout constants

Sizes are fractions of frame width, times `textScale`: caption 0.062 (55 px
at 886), disclosure 0.030, app name 0.100, logo height 0.115, tagline 0.038;
side margin 0.06 each side. The footage is scaled uniformly to fit the area
below the band and centred in it; the area around it shows the gradient. The
band text block is centred vertically in the band; the scripts fail if it is
taller than the band.
