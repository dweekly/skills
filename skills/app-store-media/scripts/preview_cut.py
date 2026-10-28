#!/usr/bin/env python3
"""Cut an App Preview video from simulator takes, driven by a preview config.

    python3 preview_cut.py <preview.json> --raw <take(s)> --marks <marks> --out <dir>
                           [--overlays <dir>]

Inputs: the config (schema in ../references/preview-config.md), one raw
`simctl io recordVideo` movie and one marks file per take, and the overlays
that preview_overlays.swift rendered from the same config (default
<out>/overlays). `--raw` and `--marks` take `name=path` pairs, one per take;
a config with a single take also accepts a bare path. Paths given in the
config's `takes` block are used when the command line does not name a take.

Output in <out>: `candidate.mp4` (886x1920 by default, H.264 High at Level
4.0, yuv420p, exactly 30 fps, one silent stereo AAC track) and `cut.json`, the
manifest of every take, beat, piece and transition. Validate the candidate
with check_preview.py before using it; nothing here moves it into place.

Standard library plus ffmpeg and ffprobe on the PATH.

Why every take is normalised before anything is cut: `simctl` writes a
variable-frame-rate movie that only carries a frame when the screen changes,
so a static hold is one frame followed by nothing. Trimming that stream at a
mark inside a hold drops the frame that was on screen, and resetting the
timestamps then closes the gap: a sibling app's first cut turned a 2.4 s beat
into one frame that way. Simulator recordings can also carry non-monotonic
decode timestamps, which `-fflags +igndts` corrects. So each take is decoded
once with that flag through `fps=30` (which repeats a held frame across its
hold), reset to start at zero, and every beat is then cut by frame number on
that dense timeline. Marks are offsets in seconds from the recorder's first
frame, which is frame 0 of the normalised take, so a mark at t seconds is
frame round(t * fps).

Every frame has one shape: a band across the top (the logo, app name and
tagline, or a one-line caption) and the take's footage scaled uniformly to fit
below it, aspect preserved, centred. Nothing jumps at a transition and no app
text is covered. A card beat is the exception: a full-frame brand card with a
large caption and no footage. Each beat is joined to the one before it by a
dissolve or a hard cut (`transitionIn`); captions fade in and out with their
beat; logo bands and cards do not fade.

The film carries no captured audio, ever: the track is generated digital
silence (anullsrc), added once after assembly.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

DEFAULTS = {
    "width": 886, "height": 1920, "fps": 30, "bandRatio": 0.14,
    "dissolve": 0.4, "captionFade": 0.3, "captionMinReadable": 2.5,
}
# Every beat plays at recorded speed; the manifest carries the rate so the
# checker can refuse any other value.
PLAYBACK_RATE = 1.0
AUDIO_RATE = 48000
AAC_FRAME = 1024
STILL_KEYWORDS = ("first", "last")
COLOR_TAGS = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv"]


class CutError(Exception):
    pass


def say(*parts: object) -> None:
    print(*parts, file=sys.stderr)


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise CutError(f"ffmpeg failed ({r.returncode}): {' '.join(cmd[:12])} ...\n{r.stderr.strip()[-2000:]}")


def ffprobe_json(path: Path, *args: str) -> dict:
    r = subprocess.run(["ffprobe", "-v", "error", "-of", "json", *args, str(path)], capture_output=True, text=True)
    if r.returncode != 0:
        raise CutError(f"ffprobe could not read {path}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def video_stream(path: Path) -> dict:
    streams = ffprobe_json(path, "-select_streams", "v:0", "-show_streams").get("streams") or []
    if not streams:
        raise CutError(f"no video stream in {path}")
    return streams[0]


def frame_count(path: Path) -> int:
    """Decoded-packet count of the first video stream (exact for our own CFR files)."""
    info = ffprobe_json(path, "-select_streams", "v:0", "-count_packets", "-show_entries", "stream=nb_read_packets")
    return int(info["streams"][0]["nb_read_packets"])


def first_pts(path: Path) -> float:
    frames = ffprobe_json(path, "-select_streams", "v:0", "-show_entries", "frame=pts_time",
                          "-read_intervals", "%+#1").get("frames") or []
    if not frames:
        raise CutError(f"could not decode a frame from {path}")
    return float(frames[0]["pts_time"])


def even(n: float) -> int:
    """Round half up (as Swift's .rounded() does), then down to even: yuv420p needs even sizes."""
    v = int(math.floor(n + 0.5))
    return v if v % 2 == 0 else v - 1


def band_height(height: int, ratio: float) -> int:
    return even(height * ratio)


def fit_below_band(src_w: int, src_h: int, width: int, height: int, band: int) -> dict:
    """The footage rectangle: scaled uniformly to fit the area below the band, centred in it."""
    avail_h = height - band
    fw, fh = even(avail_h * src_w / src_h), avail_h - (avail_h % 2)
    if fw > width:
        fw, fh = width - (width % 2), even(width * src_h / src_w)
    return {"x": (width - fw) // 2, "y": band + (avail_h - fh) // 2, "width": fw, "height": fh}


def normalise(raw: Path, out: Path, fps: int) -> None:
    """Dense constant-rate timeline from zero: +igndts, fps (repeats held frames), PTS reset."""
    run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-fflags", "+igndts", "-i", str(raw),
         "-vf", f"fps={fps},setpts=PTS-STARTPTS", "-an",
         "-c:v", "libx264", "-crf", "12", "-preset", "fast", "-pix_fmt", "yuv420p", str(out)])


def read_marks(path: Path) -> list[tuple[str, float]]:
    """`name<TAB>seconds` per line, in emitted order. Never sorted or deduped:
    a repeated or reordered mark is a broken take, not something to tidy."""
    marks = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2:
            raise CutError(f"{path}:{n}: expected `name<TAB>seconds`, got {line!r}")
        try:
            marks.append((parts[0], float(parts[1])))
        except ValueError:
            raise CutError(f"{path}:{n}: {parts[1]!r} is not a number")
    return marks


def validate_marks(take: str, marks: list[tuple[str, float]], expect: list[str] | None) -> dict[str, float]:
    names = [n for n, _ in marks]
    if expect is not None and names != expect:
        raise CutError(f"take {take}: marks are {names}; the config expects {expect}")
    if len(set(names)) != len(names):
        raise CutError(f"take {take}: a mark name repeats in {names}")
    for reserved in STILL_KEYWORDS:
        if reserved in names:
            raise CutError(f"take {take}: a mark may not be named {reserved!r} (reserved for still beats)")
    last = -math.inf
    for name, t in marks:
        if not math.isfinite(t) or t < 0:
            raise CutError(f"take {take}: mark {name} has time {t}")
        if t <= last:
            raise CutError(f"take {take}: mark {name} at {t:.3f}s is not after the previous mark at {last:.3f}s")
        last = t
    return dict(marks)


def load_config(path: Path) -> dict:
    cfg = json.loads(path.read_text())
    for k, v in DEFAULTS.items():
        cfg.setdefault(k, v)
    if not isinstance(cfg.get("takes"), dict) or not cfg["takes"]:
        raise CutError("config needs a non-empty \"takes\" object")
    if not isinstance(cfg.get("beats"), list) or not cfg["beats"]:
        raise CutError("config needs a non-empty \"beats\" list")
    if int(cfg["fps"]) != cfg["fps"] or not 1 <= cfg["fps"] <= 30:
        raise CutError("fps must be a whole number from 1 to 30 (Apple's maximum; the house value is 30)")
    cfg["fps"] = int(cfg["fps"])
    return cfg


def band_kind(beat: dict) -> str:
    """Same default as preview_overlays.swift; overlays.json is compared against it."""
    if beat.get("card") is True:
        return "card"
    return beat.get("band") or ("caption" if beat.get("caption") else "logo")


def take_paths(values: list[str] | None, cfg: dict, key: str, base: Path, flag: str) -> dict[str, Path]:
    takes = cfg["takes"]
    out: dict[str, Path] = {}
    for name, spec in takes.items():
        if isinstance(spec, dict) and spec.get(key):
            out[name] = (base / spec[key]).resolve()
    for v in values or []:
        if "=" in v and v.split("=", 1)[0] in takes:
            name, p = v.split("=", 1)
        elif len(takes) == 1:
            name, p = next(iter(takes)), v
        else:
            raise CutError(f"{flag} {v!r}: name the take as name=path (takes: {', '.join(takes)})")
        out[name] = Path(p).expanduser().resolve()
    return out


def check_overlays(overlays: dict, cfg: dict, band: int) -> None:
    """Refuse overlays rendered from a different config or geometry."""
    for k, want in (("width", cfg["width"]), ("height", cfg["height"]), ("band_height", band)):
        if overlays.get(k) != want:
            raise CutError(f"overlays have {k}={overlays.get(k)}, the config gives {want}; re-run preview_overlays.swift")
    got = overlays.get("beats", [])
    if [b["name"] for b in got] != [b["name"] for b in cfg["beats"]]:
        raise CutError("overlays were rendered for different beats; re-run preview_overlays.swift")
    for o, b in zip(got, cfg["beats"]):
        kind = band_kind(b)
        want = {"band": kind}
        if kind == "caption":
            want.update(caption=b.get("caption"), disclosure=b.get("disclosure"))
        elif kind == "card":
            want.update(caption=b.get("caption"), subline=b.get("subline"))
        else:
            want.update(tagline=b.get("tagline") or cfg.get("tagline"), appName=cfg.get("appName"))
        for k, v in want.items():
            if o.get(k) != v:
                raise CutError(f"beat {b['name']}: overlay {k} is {o.get(k)!r}, the config says {v!r}; "
                               "re-run preview_overlays.swift")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("config", type=Path, help="preview.json")
    ap.add_argument("--raw", nargs="+", action="extend", help="simctl recording per take: name=path (or a bare path for one take)")
    ap.add_argument("--marks", nargs="+", action="extend", help="marks file per take: name=path (or a bare path for one take)")
    ap.add_argument("--out", required=True, type=Path, help="work directory: pieces, cut.json, candidate.mp4")
    ap.add_argument("--overlays", type=Path, help="preview_overlays.swift output (default <out>/overlays)")
    args = ap.parse_args(argv)
    try:
        return cut(args)
    except CutError as e:
        say(f"error: {e}")
        return 1


def cut(args: argparse.Namespace) -> int:
    config_path = args.config.resolve()
    base = config_path.parent
    cfg = load_config(config_path)
    fps, width, height = cfg["fps"], int(cfg["width"]), int(cfg["height"])
    band = band_height(height, float(cfg["bandRatio"]))
    dissolve_frames = round(float(cfg["dissolve"]) * fps)
    fade = float(cfg["captionFade"])
    min_readable = float(cfg["captionMinReadable"])
    work = args.out.resolve()
    work.mkdir(parents=True, exist_ok=True)
    overlays_dir = (args.overlays or work / "overlays").resolve()
    overlays_json = overlays_dir / "overlays.json"
    if not overlays_json.exists():
        raise CutError(f"no {overlays_json}; run preview_overlays.swift {args.config} --out {overlays_dir}")
    overlays = json.loads(overlays_json.read_text())
    check_overlays(overlays, cfg, band)

    raws = take_paths(args.raw, cfg, "raw", base, "--raw")
    mark_files = take_paths(args.marks, cfg, "marks", base, "--marks")
    used = {b.get("take") for b in cfg["beats"] if b.get("card") is not True}
    for name in used:
        if name not in cfg["takes"]:
            raise CutError(f"a beat names take {name!r}, which is not in \"takes\"")
        if name not in raws or not raws[name].exists():
            raise CutError(f"take {name}: no raw recording (give --raw {name}=<file>)")

    for stale in list(work.glob("piece_*.mp4")) + list(work.glob("still_*.png")):
        stale.unlink()

    # --- 1. Marks and a normalised timeline per take.
    takes: dict[str, dict] = {}
    for name in [t for t in cfg["takes"] if t in used]:
        spec = cfg["takes"][name] if isinstance(cfg["takes"][name], dict) else {}
        marks: dict[str, float] = {}
        if name in mark_files:
            if not mark_files[name].exists():
                raise CutError(f"take {name}: no marks file at {mark_files[name]}")
            marks = validate_marks(name, read_marks(mark_files[name]), spec.get("expectMarks"))
        elif spec.get("expectMarks"):
            raise CutError(f"take {name}: the config expects marks but none were given (--marks {name}=<file>)")
        raw = raws[name]
        rs = video_stream(raw)
        normalised = work / f"normalised_{name}.mp4"
        say(f"normalising take {name}: {raw.name} ({rs['width']}x{rs['height']}) to {fps} fps")
        normalise(raw, normalised, fps)
        frames = frame_count(normalised)
        if frames < 1:
            raise CutError(f"take {name}: the normalised take has no frames")
        geom = fit_below_band(int(rs["width"]), int(rs["height"]), width, height, band)
        st = raw.stat()
        takes[name] = {"raw": str(raw), "raw_bytes": st.st_size, "raw_mtime": int(st.st_mtime),
                       "width": int(rs["width"]), "height": int(rs["height"]),
                       "first_pts": first_pts(raw), "normalised": str(normalised),
                       "normalised_frames": frames, "marks_file": str(mark_files.get(name, "")) or None,
                       "marks": [{"name": k, "seconds": v} for k, v in marks.items()],
                       "footage": geom, "_marks": marks}
        say(f"  {frames} frames ({frames / fps:.3f}s); footage {geom['width']}x{geom['height']} at "
            f"{geom['x']},{geom['y']}")

    # --- 2. Joins, then every beat resolved to frames.
    # joins[i] is the overlap in frames of the join into beat i (none into beat 0):
    # a dissolve overlaps the two beats by `dissolve`, a cut by nothing.
    n_beats = len(cfg["beats"])
    joins, join_kinds = [0] * n_beats, [""] * n_beats
    for i, spec in enumerate(cfg["beats"][1:], 1):
        kind = spec.get("transitionIn") or ("dissolve" if dissolve_frames else "cut")
        if kind not in ("cut", "dissolve"):
            raise CutError(f"beat {spec.get('name')}: transitionIn must be \"cut\" or \"dissolve\", not {kind!r}")
        if kind == "dissolve" and not dissolve_frames:
            raise CutError(f"beat {spec.get('name')}: transitionIn is dissolve but the config's dissolve is 0")
        join_kinds[i], joins[i] = kind, (dissolve_frames if kind == "dissolve" else 0)

    beats = []
    for i, spec in enumerate(cfg["beats"]):
        name = spec.get("name")
        is_card = spec.get("card") is True
        take = None if is_card else spec.get("take")
        if not name or not (is_card or take):
            raise CutError(f"beat {i}: needs \"name\" and \"take\" (or \"card\": true)")
        seconds = float(spec.get("seconds", 0))
        frames = round(seconds * fps)
        if frames < 1:
            raise CutError(f"beat {name}: \"seconds\" must be positive")
        lead_ov, tail_ov = joins[i], (joins[i + 1] if i < n_beats - 1 else 0)
        if frames <= lead_ov + tail_ov:
            raise CutError(f"beat {name}: {seconds}s is too short for its dissolves")
        kind = band_kind(spec)
        o = overlays["beats"][i]
        b = {"order": i, "name": name, "take": take, "band": kind, "seconds": seconds, "frames": frames,
             "rate": PLAYBACK_RATE, "piece": f"piece_{i + 1:02d}_{name}.mp4", "band_file": o["file"],
             "transition_in": join_kinds[i] or None}
        has_still = "still" in spec
        has_marks = "start_mark" in spec or "end_mark" in spec
        if is_card:
            if has_still or has_marks or not spec.get("caption"):
                raise CutError(f"beat {name}: a card has a caption and no take, still or marks")
            b.update(kind="card")
        elif has_still == has_marks:
            raise CutError(f"beat {name}: give either \"still\" or \"start_mark\" and \"end_mark\"")
        elif has_marks:
            t = takes[take]
            sm, em = spec.get("start_mark"), spec.get("end_mark")
            for m in (sm, em):
                if m not in t["_marks"]:
                    raise CutError(f"beat {name}: take {take} has no mark {m!r}")
            start, end = t["_marks"][sm], t["_marks"][em]
            available = end - start
            # Half a frame of slack for float marks; anything shorter is a take that did not hold long enough.
            if available < seconds - 0.5 / fps:
                raise CutError(f"beat {name} needs {seconds}s after mark {sm}, but {em} comes {available:.3f}s later; "
                               "hold the screen longer in the UI test")
            start_frame = round(start * fps)
            if start_frame + frames > t["normalised_frames"]:
                raise CutError(f"beat {name} runs past the end of take {take} "
                               f"(frame {start_frame + frames} of {t['normalised_frames']})")
            b.update(kind="recording", start_mark=sm, end_mark=em, source_start_seconds=round(start, 3),
                     source_available_seconds=round(available, 3), start_frame=start_frame)
        else:
            t = takes[take]
            still = spec["still"]
            if still == "first":
                at = 0
            elif still == "last":
                at = t["normalised_frames"] - 1
            elif still in t["_marks"]:
                at = round(t["_marks"][still] * fps)
            else:
                raise CutError(f"beat {name}: still must be \"first\", \"last\" or a mark of take {take}, not {still!r}")
            if at >= t["normalised_frames"]:
                raise CutError(f"beat {name}: still frame {at} is past the end of take {take}")
            b.update(kind="still", still=still, still_frame=at)
        if kind == "caption":
            # A card that hard-cuts into a beat with the identical caption hands the
            # words straight to the band: no fade-in, so they never vanish between.
            prev = cfg["beats"][i - 1] if i > 0 else {}
            fade_in = 0.0 if (join_kinds[i] == "cut" and prev.get("card") is True
                              and prev.get("caption") == spec.get("caption")) else fade
            # A beat can override either fade, for a film that loops: the first beat
            # shows its caption from frame 0 and the last keeps it to the final frame,
            # so the caption does not blink at the wrap (and frame 0, the default
            # poster, carries it).
            fade_in = float(spec.get("captionFadeIn", fade_in))
            fade_out = float(spec.get("captionFadeOut", fade))
            # Readable time excludes the caption's own fades and any dissolve it sits under.
            lead = max(fade_in, lead_ov / fps)
            tail = max(fade_out, tail_ov / fps)
            b.update(caption=spec.get("caption"), disclosure=spec.get("disclosure"),
                     caption_fade_in_seconds=fade_in, caption_fade_out_seconds=fade_out,
                     caption_readable_seconds=round(frames / fps - lead - tail, 3))
        elif kind == "card":
            # A card's text does not fade; only a dissolve into or out of it takes time away.
            b.update(caption=spec.get("caption"), subline=spec.get("subline"),
                     caption_fade_in_seconds=0.0, caption_fade_out_seconds=0.0,
                     caption_readable_seconds=round((frames - lead_ov - tail_ov) / fps, 3))
        else:
            b.update(tagline=spec.get("tagline") or cfg.get("tagline"),
                     caption_fade_in_seconds=0.0, caption_fade_out_seconds=0.0)
        beats.append(b)

    # Readability. A card followed directly by a caption beat with the identical
    # caption is one caption run: the floor applies to the run, not the card alone.
    covered: set[int] = set()
    for i, b in enumerate(beats):
        if b["band"] == "card":
            nxt = beats[i + 1] if i + 1 < len(beats) else None
            if nxt and nxt["band"] == "caption" and nxt.get("caption") == b["caption"]:
                run_s = round(b["caption_readable_seconds"] + nxt["caption_readable_seconds"], 3)
                for x in (b, nxt):
                    x.update(caption_run=[b["name"], nxt["name"]], caption_run_seconds=run_s)
                covered.add(i + 1)
                if run_s < min_readable:
                    raise CutError(f"card {b['name']} + beat {nxt['name']}: caption readable for {run_s}s, "
                                   f"under the {min_readable}s floor")
            elif b["caption_readable_seconds"] < min_readable:
                raise CutError(f"card {b['name']}: caption readable for {b['caption_readable_seconds']}s, under the "
                               f"{min_readable}s floor; lengthen it or repeat its caption on the next beat")
        elif b["band"] == "caption" and i not in covered and b["caption_readable_seconds"] < min_readable:
            raise CutError(f"beat {b['name']}: caption readable for {b['caption_readable_seconds']}s, under the "
                           f"{min_readable}s floor; lengthen the beat")

    # Final timeline: a dissolve overlaps the previous beat's tail; a cut does not.
    pos = 0
    for i, b in enumerate(beats):
        b["timeline_in"] = round(pos / fps, 3)
        b["timeline_out"] = round((pos + b["frames"]) / fps, 3)
        pos += b["frames"] - (joins[i + 1] if i < len(beats) - 1 else 0)
    total_frames = pos
    transitions = [{"after": beats[i - 1]["name"], "before": beats[i]["name"], "kind": join_kinds[i],
                    "frames": joins[i], "seconds": round(joins[i] / fps, 3)} for i in range(1, len(beats))]

    # --- 3. Pieces: footage over the background, band on top, composited in RGB.
    background = overlays_dir / overlays["background"]
    common = ["-c:v", "libx264", "-crf", "12", "-preset", "fast", "-pix_fmt", "yuv420p", "-r", str(fps),
              *COLOR_TAGS, "-an"]
    loop = ["-loop", "1", "-framerate", str(fps)]
    for b in beats:
        n = b["frames"]
        if b["kind"] == "card":
            # The card image is the whole frame.
            run(["ffmpeg", "-nostdin", "-v", "error", "-y", *loop, "-i", str(overlays_dir / b["band_file"]),
                 "-filter_complex", "[0:v]format=gbrp,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[out]",
                 "-map", "[out]", "-frames:v", str(n), *common, str(work / b["piece"])])
            got = frame_count(work / b["piece"])
            if got != n:
                raise CutError(f"beat {b['name']}: piece has {got} frames, wanted {n}")
            say(f"  {b['piece']}: {n} frames, card")
            continue
        t = takes[b["take"]]
        g = t["footage"]
        scale = f"scale={g['width']}:{g['height']}:flags=lanczos,setsar=1,format=gbrp"
        if b["kind"] == "recording":
            footage_in = ["-i", t["normalised"]]
            footage = f"[1:v]trim=start_frame={b['start_frame']}:end_frame={b['start_frame'] + n},setpts=PTS-STARTPTS,{scale}[f]"
        else:
            still = work / f"still_{b['order'] + 1:02d}_{b['name']}.png"
            run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", t["normalised"],
                 "-vf", f"select=eq(n\\,{b['still_frame']})", "-frames:v", "1", "-fps_mode", "passthrough", str(still)])
            if not still.exists():
                raise CutError(f"beat {b['name']}: could not extract frame {b['still_frame']} of take {b['take']}")
            footage_in = [*loop, "-i", str(still)]
            footage = f"[1:v]{scale}[f]"
        if b["band"] == "caption":
            d, fi, fo = n / fps, b["caption_fade_in_seconds"], b["caption_fade_out_seconds"]
            fades = ([f"fade=t=in:st=0:d={fi}:alpha=1"] if fi > 0 else []) + \
                    ([f"fade=t=out:st={d - fo:.4f}:d={fo}:alpha=1"] if fo > 0 else [])
            band_f = "[2:v]" + ",".join(["format=rgba", *fades]) + "[c]"
        else:
            band_f = "[2:v]format=rgba[c]"
        graph = (f"{footage};[0:v]format=gbrp[bg];[bg][f]overlay={g['x']}:{g['y']}:format=gbrp:shortest=1[b];"
                 f"{band_f};[b][c]overlay=0:0:format=gbrp:shortest=1,"
                 f"scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[out]")
        run(["ffmpeg", "-nostdin", "-v", "error", "-y", *loop, "-i", str(background), *footage_in,
             *loop, "-i", str(overlays_dir / b["band_file"]),
             "-filter_complex", graph, "-map", "[out]", "-frames:v", str(n), *common, str(work / b["piece"])])
        got = frame_count(work / b["piece"])
        if got != n:
            raise CutError(f"beat {b['name']}: piece has {got} frames, wanted {n}")
        say(f"  {b['piece']}: {n} frames, {b['kind']}" + (f" from frame {b['start_frame']}" if b["kind"] == "recording" else ""))

    # --- 4. Assemble with dissolves and cuts to Apple's settings, video only.
    inputs: list[str] = []
    filters: list[str] = []
    for i, b in enumerate(beats):
        inputs += ["-i", str(work / b["piece"])]
        # xfade refuses inputs that differ in size, format, rate or timebase.
        filters.append(f"[{i}:v]scale={width}:{height},setsar=1,format=yuv420p,fps={fps},settb=AVTB,setpts=PTS-STARTPTS[v{i}]")
    if len(beats) == 1:
        filters.append("[v0]null[vout]")
    else:
        prev, length = "v0", beats[0]["frames"]
        for i in range(1, len(beats)):
            label = f"x{i}" if i < len(beats) - 1 else "vout"
            if joins[i]:
                filters.append(f"[{prev}][v{i}]xfade=transition=fade:duration={joins[i] / fps:.6f}:"
                               f"offset={(length - joins[i]) / fps:.6f}[{label}]")
            else:
                filters.append(f"[{prev}][v{i}]concat=n=2:v=1:a=0,settb=AVTB[{label}]")
            prev, length = label, length - joins[i] + beats[i]["frames"]
    assembled = work / "assembled_video.mp4"
    run(["ffmpeg", "-nostdin", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(filters),
         "-map", "[vout]", "-frames:v", str(total_frames),
         "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p", "-r", str(fps),
         "-b:v", "10M", "-maxrate", "12M", "-bufsize", "12M", *COLOR_TAGS, "-an", str(assembled)])

    # --- 5. One silent stereo AAC track, a whole number of AAC frames, never longer than the video.
    samples = (total_frames * AUDIO_RATE // fps) // AAC_FRAME * AAC_FRAME
    candidate = work / "candidate.mp4"
    run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(assembled),
         "-f", "lavfi", "-i", f"anullsrc=channel_layout=stereo:sample_rate={AUDIO_RATE}",
         "-map", "0:v", "-map", "1:a", "-af", f"atrim=end_sample={samples}",
         "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-ar", str(AUDIO_RATE), "-ac", "2",
         "-movflags", "+faststart", str(candidate)])

    # --- 6. The manifest.
    for t in takes.values():
        del t["_marks"]
    manifest = {
        "config": str(config_path), "fps": fps, "width": width, "height": height,
        "band_height": band, "band_ratio": float(cfg["bandRatio"]),
        "dissolve_frames": dissolve_frames, "dissolve_seconds": round(dissolve_frames / fps, 3),
        "caption_fade_seconds": fade, "caption_min_readable_seconds": min_readable,
        "playback_rate": PLAYBACK_RATE, "overlays": str(overlays_dir), "background": overlays["background"],
        "takes": takes, "beats": beats, "transitions": transitions,
        "total_frames": total_frames, "total_expected_seconds": round(total_frames / fps, 3),
        "audio": {"kind": "generated silence (anullsrc)", "sample_rate": AUDIO_RATE, "channels": 2,
                  "samples": samples},
        "candidate": str(candidate),
    }
    (work / "cut.json").write_text(json.dumps(manifest, indent=2) + "\n")
    say(f"wrote {work / 'cut.json'} and {candidate}: {len(beats)} beats, {total_frames} frames "
        f"({total_frames / fps:.3f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
