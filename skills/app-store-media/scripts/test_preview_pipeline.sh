#!/bin/bash
#
# End-to-end test of the App Preview pipeline on synthetic takes, driven by the
# documented example config (references/examples/preview.example.json), so the
# example is proved to work as written.
#
#   bash scripts/test_preview_pipeline.sh [work-dir]
#
# Generates two sparse variable-frame-rate takes at 1320x2868 (frames only in
# the first 1.5 s of every 4 s, the way simctl writes a screen that stops
# changing; three beats start inside a hold), marks files, and a logo; then
# runs preview_overlays.swift -> preview_cut.py -> check_preview.py and extracts
# a frame per beat kind and either side of each hard cut (the example has a
# brand card joined by cuts) to <work-dir>/frames/ for a visual look. Also proves the cutter
# refuses overlays rendered from a stale config and marks out of order.
# Exits non-zero on any failure. Needs ffmpeg, ffprobe, swift and python3.
set -euo pipefail

SKILL="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL/scripts"
WORK="${1:-$(mktemp -d -t preview-e2e)}"
mkdir -p "$WORK/takes"
WORK="$(cd "$WORK" && pwd)"
say() { printf '%s\n' "$*" >&2; }

cp "$SKILL/references/examples/preview.example.json" "$WORK/preview.json"

say "1/5  synthetic takes, marks and logo in $WORK"
# simctl-like: 60 fps source, then only the frames in the first 1.5 s of each 4 s survive.
sparse='select=lt(mod(t\,4)\,1.5)'
ffmpeg -nostdin -v error -y -f lavfi -t 22 -i "testsrc2=size=1320x2868:rate=60" \
    -vf "$sparse" -fps_mode vfr -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$WORK/takes/walkthrough.mov"
ffmpeg -nostdin -v error -y -f lavfi -t 10 -i "testsrc2=size=1320x2868:rate=60" \
    -vf "hue=h=150,$sparse" -fps_mode vfr -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$WORK/takes/share.mov"
printf 'home\t1.800\nhomeEnd\t7.000\ncompose\t8.000\ncomposeEnd\t13.700\ndone\t16.200\ndoneEnd\t21.400\n' \
    > "$WORK/takes/walkthrough.marks.tsv"
printf 'share\t1.600\nshareEnd\t6.800\n' > "$WORK/takes/share.marks.tsv"
ffmpeg -nostdin -v error -y -f lavfi -i "color=c=white:s=256x256,format=rgba" -frames:v 1 \
    -vf "geq=r=242:g=177:b=52:a='if(lt(hypot(X-128\,Y-128)\,120)\,255\,0)'" "$WORK/logo.png"

say "2/5  overlays"
swift "$SCRIPTS/preview_overlays.swift" "$WORK/preview.json" --out "$WORK/cut/overlays"

say "3/5  negative controls: stale overlays and reordered marks are refused"
python3 - "$WORK/preview.json" "$WORK/stale.json" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["beats"][1]["caption"] = "A caption the overlays never saw"
json.dump(c, open(sys.argv[2], "w"))
PY
if python3 "$SCRIPTS/preview_cut.py" "$WORK/stale.json" --out "$WORK/cut" 2> "$WORK/stale.log"; then
    say "FAIL: the cutter accepted overlays rendered from a different config"; exit 1
fi
grep -q "re-run preview_overlays.swift" "$WORK/stale.log" && say "     ok  stale overlays refused: $(tail -1 "$WORK/stale.log")"
printf 'home\t1.8\ncompose\t8.0\nhomeEnd\t7.0\ncomposeEnd\t13.7\ndone\t16.2\ndoneEnd\t21.4\n' > "$WORK/takes/bad.marks.tsv"
if python3 "$SCRIPTS/preview_cut.py" "$WORK/preview.json" --out "$WORK/cut" \
        --marks "walkthrough=$WORK/takes/bad.marks.tsv" 2> "$WORK/marks.log"; then
    say "FAIL: the cutter accepted marks out of order"; exit 1
fi
say "     ok  reordered marks refused: $(tail -1 "$WORK/marks.log")"

say "4/5  cut (takes named on the command line)"
python3 "$SCRIPTS/preview_cut.py" "$WORK/preview.json" --out "$WORK/cut" \
    --raw "walkthrough=$WORK/takes/walkthrough.mov" "share=$WORK/takes/share.mov" \
    --marks "walkthrough=$WORK/takes/walkthrough.marks.tsv" "share=$WORK/takes/share.marks.tsv"

say "5/5  check"
python3 "$SCRIPTS/check_preview.py" "$WORK/cut/candidate.mp4" --manifest "$WORK/cut/cut.json"

# A frame from each kind of beat, and the two frames either side of each hard cut
# into and out of the card, picked by frame number from the manifest.
mkdir -p "$WORK/frames"
python3 - "$WORK/cut/cut.json" > "$WORK/frames/picks.txt" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); fps = m["fps"]
by = {b["name"]: b for b in m["beats"]}
def mid(n): b = by[n]; return round((b["timeline_in"] + b["timeline_out"]) / 2 * fps)
picks = {"opening": mid("opening"), "home": mid("home"), "card": mid("compose-card"),
         "share": mid("share"), "end": mid("end")}
for t in m["transitions"]:
    if t["kind"] == "cut":
        f = round(by[t["before"]]["timeline_in"] * fps)
        picks[f"cut-{t['before']}-before"], picks[f"cut-{t['before']}-after"] = f - 1, f
for k, v in picks.items():
    print(k, v)
PY
while read -r label frame; do
    ffmpeg -nostdin -v error -y -i "$WORK/cut/candidate.mp4" -vf "select=eq(n\,$frame)" -frames:v 1 \
        "$WORK/frames/$label.png"
done < "$WORK/frames/picks.txt"
say "Frames for a visual look: $WORK/frames/ ($(cut -d' ' -f1 "$WORK/frames/picks.txt" | tr '\n' ' '))"
