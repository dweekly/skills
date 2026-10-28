#!/usr/bin/env python3
"""Check an App Preview candidate against Apple's limits and the house rules.

    python3 check_preview.py <candidate.mp4> [--manifest cut.json] [--size 886x1920]
    python3 check_preview.py --self-test

Prints one line per check, `ok` or `FAIL`, tagged [Apple], [house] or
[manifest], and exits 1 if any check failed (2 if ffmpeg is missing).

[Apple]   App preview specifications (see ../references/apple-specs.md):
          H.264 at High Profile Level 4.0 or below, an accepted preview size,
          at most 30 fps, 15 to 30 s, an AAC stereo track at 44.1 or 48 kHz,
          every track enabled, at most 500 MB.
[house]   Stricter choices: exactly 30 fps (constant), yuv420p, audio no
          longer than the video, audio that is digital silence (the film never
          carries captured sound), frame 0 and the frame at 5.0 s (App Store
          Connect's default poster) lit: mean luma above 60 of 255.
[manifest] With --manifest (preview_cut.py's cut.json): every piece decodes
          to its beat's frame count within 2 frames and plays at rate 1, every
          caption is readable for at least 2.5 s (a card followed by a beat
          with the same caption counts as one run), one transition per pair of
          beats, each a 0-frame cut or a dissolve, beats minus dissolve
          overlaps equal the total, and the candidate's frame count matches.

--self-test builds known-bad inputs with ffmpeg (wrong size, 25 fps, too
short, level too high, no audio, non-silent audio, audio longer than video, a
disabled track, a black poster frame, a one-frame beat, an unreadable caption)
and proves each fails its check, that a known-good file passes every check,
and that preview_cut.py's normalise-then-cut recovers a beat that starts
inside a static hold of a sparse variable-frame-rate take, where a naive trim
keeps almost nothing.

Standard library plus ffmpeg and ffprobe on the PATH.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

# Mean luma (signalstats YAVG, 0 to 255) a frame must exceed to count as lit.
# Limited-range black is 16; a dark brand colour measures well above 60.
LUMA_FLOOR = 60.0
POSTER_TIMES = (0.0, 5.0)
FRAME_TOLERANCE = 2
APPLE_SIZES = {(886, 1920), (1920, 886), (1200, 1600), (1600, 1200)}
APPLE_PROFILES = {"Constrained Baseline", "Baseline", "Main", "High"}
APPLE_MAX_LEVEL = 40
APPLE_MAX_BYTES = 500 * 1000 * 1000
HOUSE_FPS = Fraction(30)


class Fail(Exception):
    pass


def ffprobe(path: Path, *args: str) -> dict:
    r = subprocess.run(["ffprobe", "-v", "error", "-of", "json", *args, str(path)], capture_output=True, text=True)
    if r.returncode != 0:
        raise Fail(f"ffprobe could not read {path}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def decoded_frames(path: Path) -> int:
    info = ffprobe(path, "-select_streams", "v:0", "-count_frames", "-show_entries", "stream=nb_read_frames")
    streams = info.get("streams") or []
    if not streams:
        raise Fail(f"{path}: no video stream")
    return int(streams[0].get("nb_read_frames") or 0)


def mean_luma(path: Path, t: float, duration: float) -> float:
    """Mean luma of the first frame at or after t, decoded through a lavfi movie
    source so the seek and the statistics happen in one pass. select= drops the
    keyframe the seek lands on, so a bright keyframe never stands in for a
    dark frame after it; a time past the end yields no frame and fails."""
    if t >= duration:
        raise Fail(f"no frame at {t}s (video is {duration:.3f}s)")
    src = str(path).replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'")
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-f", "lavfi", "-i",
         f"movie={src}:seek_point={t},select=gte(t\\,{t}),signalstats",
         "-show_entries", "frame_tags=lavfi.signalstats.YAVG", "-read_intervals", "%+#1", "-of", "json"],
        capture_output=True, text=True).stdout
    frames = json.loads(out or "{}").get("frames", [])
    if not frames or "lavfi.signalstats.YAVG" not in frames[0].get("tags", {}):
        raise Fail(f"no frame decoded at {t}s")
    return float(frames[0]["tags"]["lavfi.signalstats.YAVG"])


def audio_peak(path: Path) -> tuple[str, int]:
    """(Overall peak level in dB as astats prints it, sample count). Digital
    silence prints -inf; any nonzero sample prints a finite level."""
    r = subprocess.run(["ffmpeg", "-nostdin", "-v", "info", "-i", str(path), "-map", "0:a:0",
                        "-af", "astats=measure_perchannel=none", "-f", "null", "-"],
                       capture_output=True, text=True)
    text = r.stderr
    overall = text.split("] Overall", 1)[-1] if "] Overall" in text else ""
    peak = re.search(r"Peak level dB:\s*(\S+)", overall)
    count = re.search(r"Number of samples:\s*(\d+)", overall)
    if r.returncode != 0 or not peak or not count:
        raise Fail("astats returned no overall audio statistics")
    return peak.group(1), int(count.group(1))


def mp4_track_flags(path: Path) -> list[tuple[int, int]]:
    """(tkhd flags, byte offset of the flags) for every trak in an ISO BMFF file."""
    data = path.read_bytes()

    def boxes(start: int, end: int):
        i = start
        while i + 8 <= end:
            size, kind = struct.unpack(">I4s", data[i:i + 8])
            header = 8
            if size == 1:
                size, header = struct.unpack(">Q", data[i + 8:i + 16])[0], 16
            elif size == 0:
                size = end - i
            if size < header or i + size > end:
                return
            yield kind, i + header, i + size
            i += size

    out = []
    for kind, s, e in boxes(0, len(data)):
        if kind != b"moov":
            continue
        for k2, s2, e2 in boxes(s, e):
            if k2 != b"trak":
                continue
            for k3, s3, _ in boxes(s2, e2):
                if k3 == b"tkhd":
                    out.append((int.from_bytes(data[s3 + 1:s3 + 4], "big"), s3 + 1))
    return out


# --- the checks ------------------------------------------------------------

class Report:
    def __init__(self) -> None:
        self.lines: list[tuple[bool, str, str, str]] = []

    def add(self, tag: str, what: str, ok: bool, got: object) -> None:
        self.lines.append((ok, tag, what, str(got)))

    def check(self, tag: str, what: str, fn) -> None:
        """Run fn() -> (ok, got); an exception is a failure, never a skip."""
        try:
            ok, got = fn()
        except Fail as e:
            ok, got = False, str(e)
        except (KeyError, ValueError, TypeError, ZeroDivisionError) as e:
            ok, got = False, f"{type(e).__name__}: {e}"
        self.add(tag, what, ok, got)

    @property
    def failed(self) -> list[str]:
        return [f"[{t}] {w}" for ok, t, w, _ in self.lines if not ok]

    def text(self) -> str:
        return "\n".join(f"{'ok  ' if ok else 'FAIL'} [{t}] {w}: {g}" for ok, t, w, g in self.lines)


def check_candidate(path: Path, manifest_path: Path | None = None, size: tuple[int, int] | None = None) -> Report:
    rep = Report()
    info = ffprobe(path, "-show_streams", "-show_format")
    vs = [s for s in info.get("streams", []) if s.get("codec_type") == "video"]
    aus = [s for s in info.get("streams", []) if s.get("codec_type") == "audio"]
    manifest = json.loads(manifest_path.read_text()) if manifest_path else None
    if size is None and manifest:
        size = (int(manifest["width"]), int(manifest["height"]))
    size = size or (886, 1920)
    if not vs:
        rep.add("Apple", "video stream present", False, "none")
        return rep
    v = vs[0]
    a = aus[0] if aus else None
    vdur = float(v.get("duration") or 0)
    rfr, afr = Fraction(v.get("r_frame_rate", "0/1")), Fraction(v.get("avg_frame_rate", "0/1"))

    rep.add("Apple", "video codec H.264", v.get("codec_name") == "h264", v.get("codec_name"))
    rep.add("Apple", "profile High or below", v.get("profile") in APPLE_PROFILES, v.get("profile"))
    rep.add("Apple", "level 4.0 or below", 0 < int(v.get("level", 99)) <= APPLE_MAX_LEVEL, v.get("level"))
    got_size = (int(v.get("width", 0)), int(v.get("height", 0)))
    rep.add("Apple", "an accepted preview size", got_size in APPLE_SIZES, f"{got_size[0]}x{got_size[1]}")
    rep.add("Apple", "at most 30 fps", 0 < rfr <= 30 and 0 < afr <= 30, f"r={rfr} avg={afr}")
    rep.add("Apple", "15 to 30 s (video stream)", 15 <= vdur <= 30, f"{vdur:.3f}s")
    size_bytes = path.stat().st_size
    rep.add("Apple", "at most 500 MB", size_bytes <= APPLE_MAX_BYTES, f"{size_bytes / 1e6:.1f} MB")
    rep.add("Apple", "audio track present", a is not None, a.get("codec_name") if a else "none")
    if a is not None:
        rep.add("Apple", "audio AAC", a.get("codec_name") == "aac", a.get("codec_name"))
        rep.add("Apple", "audio stereo", int(a.get("channels", 0)) == 2, a.get("channels"))
        rep.add("Apple", "audio 44.1 or 48 kHz", int(a.get("sample_rate", 0)) in (44100, 48000), a.get("sample_rate"))
    flags = mp4_track_flags(path)
    rep.add("Apple", "every track enabled", bool(flags) and all(f & 1 for f, _ in flags),
            ", ".join(f"tkhd flags 0x{f:06x}" for f, _ in flags) or "no tracks found")

    rep.add("house", f"exactly {size[0]}x{size[1]}", got_size == size, f"{got_size[0]}x{got_size[1]}")
    want_fps = Fraction(int(manifest["fps"])) if manifest else HOUSE_FPS
    rep.add("house", f"exactly {want_fps} fps, constant", rfr == want_fps and afr == want_fps, f"r={rfr} avg={afr}")
    rep.add("house", "pixel format yuv420p", v.get("pix_fmt") == "yuv420p", v.get("pix_fmt"))
    if a is not None:
        adur = float(a.get("duration") or 0)
        # One video frame of slack: container durations round to their own timebases.
        slack = 1 / float(want_fps)
        rep.add("house", "audio no longer than video", adur <= vdur + slack, f"audio {adur:.3f}s, video {vdur:.3f}s")

        def silence():
            peak, n = audio_peak(path)
            return peak == "-inf" and n > 0, f"peak {peak} dB over {n} samples"
        rep.check("house", "audio is digital silence", silence)
    for t in POSTER_TIMES:
        def lit(t=t):
            y = mean_luma(path, t, vdur)
            return y > LUMA_FLOOR, f"mean luma {y:.1f} (floor {LUMA_FLOOR})"
        rep.check("house", f"frame at {t:.1f}s lit", lit)

    if manifest:
        check_manifest(rep, path, manifest, manifest_path.parent)
    return rep


def check_readability(rep: Report, beats: list[dict], floor: float) -> None:
    """Apple asks that text stay on screen long enough to read. Recomputed from
    the beats, not trusted from the cutter: a card directly followed by a
    caption beat with the identical caption is one run, and the floor applies
    to the run; any other card or caption beat must meet it alone."""
    covered: set[int] = set()
    for i, b in enumerate(beats):
        own = float(b.get("caption_readable_seconds", 0))
        if b.get("band") == "card":
            nxt = beats[i + 1] if i + 1 < len(beats) else None
            if nxt and nxt.get("band") == "caption" and nxt.get("caption") == b.get("caption"):
                covered.add(i + 1)
                run_s = own + float(nxt.get("caption_readable_seconds", 0))
                rep.add("manifest", f"card {b['name']} + beat {nxt['name']} caption run readable >= {floor}s",
                        run_s >= floor, f"{own}s + {nxt.get('caption_readable_seconds')}s = {run_s:.3f}s")
            else:
                rep.add("manifest", f"card {b['name']} caption readable >= {floor}s", own >= floor,
                        f"{own}s (the next beat does not repeat its caption)")
        elif b.get("band") == "caption" and i not in covered:
            rep.add("manifest", f"beat {b['name']} caption readable >= {floor}s", own >= floor, f"{own}s")


def check_manifest(rep: Report, path: Path, m: dict, work: Path) -> None:
    fps = int(m["fps"])
    beats = m["beats"]
    for b in beats:
        def piece(b=b):
            if float(b["rate"]) != 1.0:
                return False, f"playback rate {b['rate']}; every beat plays at 1"
            p = work / b["piece"]
            if not p.exists():
                return False, f"missing {p}"
            n = decoded_frames(p)
            want = int(b["frames"])
            return abs(n - want) <= FRAME_TOLERANCE, f"{n} frames, wanted {want} (+/-{FRAME_TOLERANCE})"
        rep.check("manifest", f"beat {b['name']} length", piece)
    check_readability(rep, beats, float(m.get("caption_min_readable_seconds", 2.5)))
    trans = m["transitions"]
    rep.add("manifest", "one transition per pair of beats", len(trans) == len(beats) - 1,
            f"{len(trans)} for {len(beats)} beats")

    def joins():
        bad = [t for t in trans if t.get("kind") not in ("cut", "dissolve")
               or (t["kind"] == "cut") != (int(t["frames"]) == 0)]
        if bad:
            return False, f"inconsistent transitions: {bad}"
        total = sum(int(b["frames"]) for b in beats) - sum(int(t["frames"]) for t in trans)
        return total == int(m["total_frames"]), (f"beats {sum(int(b['frames']) for b in beats)} frames minus "
                                                 f"overlaps {sum(int(t['frames']) for t in trans)} = {total}, "
                                                 f"manifest total {m['total_frames']}")
    rep.check("manifest", "beats minus dissolve overlaps equals the total", joins)

    def total():
        n = decoded_frames(path)
        want = int(m["total_frames"])
        return abs(n - want) <= FRAME_TOLERANCE, f"{n} frames, manifest {want} ({want / fps:.3f}s)"
    rep.check("manifest", "candidate length matches the manifest", total)


# --- self-test -------------------------------------------------------------

def self_test() -> list[str]:
    notes: list[str] = []
    sys.dont_write_bytecode = True  # no __pycache__ beside the scripts
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import preview_cut  # noqa: E402  (the cutter's own normalise, for the regression)

    def ff(*args: str) -> None:
        r = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *args], capture_output=True, text=True)
        if r.returncode != 0:
            raise Fail(f"fixture ffmpeg failed: {r.stderr.strip()[-500:]}")

    def silent_samples(seconds: float, rate: int = 48000) -> int:
        return int(seconds * rate) // 1024 * 1024

    def clip(out: Path, seconds: float = 16, size: str = "886x1920", rate: int = 30, level: str = "4.0",
             audio: str | None = "silent", audio_seconds: float | None = None, video: str | None = None) -> Path:
        src = video or f"testsrc2=size={size}:rate={rate}"
        cmd = ["-f", "lavfi", "-t", str(seconds), "-i", src]
        if audio:
            asrc = ("anullsrc=channel_layout=stereo:sample_rate=48000" if audio == "silent"
                    else "sine=f=440:sample_rate=48000")
            cmd += ["-f", "lavfi", "-i", asrc, "-map", "0:v", "-map", "1:a",
                    "-af", f"atrim=end_sample={silent_samples(audio_seconds or seconds)}"
                           + (",volume=-50dB" if audio != "silent" else ""),
                    "-c:a", "aac", "-b:a", "256k", "-ac", "2", "-ar", "48000"]
        cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-profile:v", "high", "-level:v", level,
                "-pix_fmt", "yuv420p", "-r", str(rate), str(out)]
        ff(*cmd)
        return out

    def expect(label: str, rep: Report, failing: str | None) -> None:
        if failing is None:
            if rep.failed:
                raise Fail(f"{label} should pass every check but failed: {rep.failed}\n{rep.text()}")
            notes.append(f"ok  {label} passes all {len(rep.lines)} checks")
            return
        hits = [f for f in rep.failed if failing in f]
        if not hits:
            raise Fail(f"{label} passed check '{failing}' but must fail it\n{rep.text()}")
        detail = next(g for ok, t, w, g in rep.lines if not ok and failing in f"[{t}] {w}")
        notes.append(f"ok  {label} fails {hits[0]}: {detail}")

    with tempfile.TemporaryDirectory() as td:
        d = Path(td)
        good = clip(d / "good.mp4")
        expect("known-good 16 s clip", check_candidate(good), None)

        expect("640x1386", check_candidate(clip(d / "size.mp4", size="640x1386")), "accepted preview size")
        expect("25 fps", check_candidate(clip(d / "fps25.mp4", rate=25)), "exactly 30 fps")
        expect("10 s", check_candidate(clip(d / "short.mp4", seconds=10)), "15 to 30 s")
        expect("Level 5.1", check_candidate(clip(d / "level.mp4", level="5.1")), "level 4.0 or below")
        expect("no audio track", check_candidate(clip(d / "noaudio.mp4", audio=None)), "audio track present")
        expect("a 440 Hz tone at -50 dB", check_candidate(clip(d / "tone.mp4", audio="tone")), "digital silence")
        expect("audio 2 s longer than video",
               check_candidate(clip(d / "longaudio.mp4", audio_seconds=18)), "audio no longer than video")

        disabled = d / "disabled.mp4"
        data = bytearray(good.read_bytes())
        flags = mp4_track_flags(good)
        if len(flags) < 2:
            raise Fail("fixture: expected two tracks in the known-good clip")
        _, at = flags[-1]
        data[at + 2] &= 0xFE  # clear track_enabled on the last track
        disabled.write_bytes(bytes(data))
        expect("audio track disabled", check_candidate(disabled), "every track enabled")

        black0 = d / "black0.mp4"
        ff("-f", "lavfi", "-t", "1", "-i", "color=c=black:size=886x1920:rate=30",
           "-f", "lavfi", "-t", "15", "-i", "testsrc2=size=886x1920:rate=30",
           "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
           "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[v]", "-map", "[v]", "-map", "2:a",
           "-af", f"atrim=end_sample={silent_samples(16)}", "-c:a", "aac", "-ac", "2",
           "-c:v", "libx264", "-preset", "ultrafast", "-profile:v", "high", "-level:v", "4.0",
           "-pix_fmt", "yuv420p", "-r", "30", str(black0))
        expect("black frame 0", check_candidate(black0), "frame at 0.0s lit")

        # Bright, then black from 3 s, with one keyframe for the whole clip: a
        # check that measured the seek keyframe instead of the frame at 5.0 s
        # would pass this.
        black5 = d / "black5.mp4"
        ff("-f", "lavfi", "-t", "3", "-i", "testsrc2=size=886x1920:rate=30",
           "-f", "lavfi", "-t", "13", "-i", "color=c=black:size=886x1920:rate=30",
           "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
           "-filter_complex", "[0:v][1:v]concat=n=2:v=1:a=0[v]", "-map", "[v]", "-map", "2:a",
           "-af", f"atrim=end_sample={silent_samples(16)}", "-c:a", "aac", "-ac", "2",
           "-c:v", "libx264", "-preset", "ultrafast", "-profile:v", "high", "-level:v", "4.0",
           "-pix_fmt", "yuv420p", "-r", "30", "-g", "600", "-keyint_min", "600", "-sc_threshold", "0", str(black5))
        expect("black poster frame at 5.0 s behind a bright keyframe", check_candidate(black5), "frame at 5.0s lit")

        # Manifest: two beats of 8 s, no dissolve, pieces as small stand-ins.
        work = d / "work"
        work.mkdir()
        for name in ("a", "b"):
            ff("-f", "lavfi", "-i", "testsrc2=size=64x128:rate=30", "-frames:v", "240",
               "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(work / f"piece_{name}.mp4"))
        m = {"fps": 30, "width": 886, "height": 1920, "caption_min_readable_seconds": 2.5, "total_frames": 480,
             "beats": [{"name": n, "piece": f"piece_{n}.mp4", "frames": 240, "rate": 1.0, "band": "caption",
                        "caption_readable_seconds": 7.4} for n in ("a", "b")],
             "transitions": [{"after": "a", "before": "b", "kind": "cut", "frames": 0}]}
        mp = work / "cut.json"
        mp.write_text(json.dumps(m))
        expect("known-good clip with an agreeing manifest", check_candidate(good, mp), None)

        ff("-f", "lavfi", "-i", "testsrc2=size=64x128:rate=30", "-frames:v", "1",
           "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(work / "piece_one.mp4"))
        m1 = json.loads(json.dumps(m))
        m1["beats"][1]["piece"] = "piece_one.mp4"
        mp.write_text(json.dumps(m1))
        expect("a beat that encoded to one frame", check_candidate(good, mp), "beat b length")

        m2 = json.loads(json.dumps(m))
        m2["beats"][0]["caption_readable_seconds"] = 2.0
        mp.write_text(json.dumps(m2))
        expect("a caption readable for 2.0 s", check_candidate(good, mp), "caption readable")

        m3 = json.loads(json.dumps(m))
        m3["beats"][0]["rate"] = 2.0
        mp.write_text(json.dumps(m3))
        expect("a beat played at 2x", check_candidate(good, mp), "beat a length")

        m4 = json.loads(json.dumps(m))
        m4["total_frames"] = 540
        mp.write_text(json.dumps(m4))
        expect("a candidate 60 frames shorter than its manifest", check_candidate(good, mp), "matches the manifest")

        m5 = json.loads(json.dumps(m))
        m5["transitions"][0].update(kind="dissolve", frames=12)
        mp.write_text(json.dumps(m5))
        expect("a 12-frame dissolve the total does not account for", check_candidate(good, mp),
               "beats minus dissolve overlaps")

        # Cards: a 1.2 s card cut into a beat that repeats its caption is one
        # readable run; the same card before a different caption is not.
        ff("-f", "lavfi", "-i", "testsrc2=size=64x128:rate=30", "-frames:v", "36",
           "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(work / "piece_card.mp4"))
        ff("-f", "lavfi", "-i", "testsrc2=size=64x128:rate=30", "-frames:v", "204",
           "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(work / "piece_a204.mp4"))
        card = {"name": "intro", "piece": "piece_card.mp4", "frames": 36, "rate": 1.0, "band": "card",
                "caption": "x", "caption_readable_seconds": 1.2}
        beat_a = {"name": "a", "piece": "piece_a204.mp4", "frames": 204, "rate": 1.0, "band": "caption",
                  "caption": "x", "caption_readable_seconds": round(204 / 30 - 0.6, 3)}
        m6 = json.loads(json.dumps(m))
        m6["beats"] = [card, beat_a, m["beats"][1]]
        m6["transitions"] = [{"after": "intro", "before": "a", "kind": "cut", "frames": 0},
                             {"after": "a", "before": "b", "kind": "cut", "frames": 0}]
        mp.write_text(json.dumps(m6))
        expect("a 1.2 s card cut into a beat that repeats its caption", check_candidate(good, mp), None)
        m6["beats"][0]["caption"] = "y"
        mp.write_text(json.dumps(m6))
        expect("a 1.2 s card cut into a beat with a different caption", check_candidate(good, mp),
               "card intro caption readable")

        # Regression: a sparse VFR take (frames only in the first second of every
        # 4 s, as simctl writes a screen that stops changing), and a beat that
        # starts inside a hold and ends before the screen changes again.
        sparse = d / "sparse.mov"
        ff("-f", "lavfi", "-t", "12", "-i", "testsrc2=size=330x718:rate=60",
           "-vf", "select='lt(mod(t\\,4)\\,1)'", "-fps_mode", "vfr",
           "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(sparse))
        start, seconds = 1.5, 2.4
        want = round(seconds * 30)
        # The naive cut trims the raw take to the beat's window, then resets
        # timestamps and resamples: the window holds no frame at all, so the
        # beat comes out empty (or, with a frame just inside it, one frame).
        naive = d / "naive.mp4"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(sparse), "-vf",
                        f"trim=start={start}:end={start + seconds},setpts=PTS-STARTPTS,fps=30",
                        "-c:v", "libx264", "-preset", "ultrafast", str(naive)], capture_output=True)
        try:
            naive_n = decoded_frames(naive) if naive.exists() and naive.stat().st_size else 0
        except Fail:
            naive_n = 0
        norm = d / "norm.mp4"
        preview_cut.normalise(sparse, norm, 30)
        fixed = d / "fixed.mp4"
        sf = round(start * 30)
        ff("-i", str(norm), "-vf", f"trim=start_frame={sf}:end_frame={sf + want},setpts=PTS-STARTPTS",
           "-c:v", "libx264", "-preset", "ultrafast", str(fixed))
        fixed_n = decoded_frames(fixed)
        if naive_n >= want - FRAME_TOLERANCE:
            raise Fail(f"regression fixture no longer reproduces the defect: naive trim kept {naive_n} frames")
        if abs(fixed_n - want) > FRAME_TOLERANCE:
            raise Fail(f"normalise-then-cut kept {fixed_n} frames of {want}")
        notes.append(f"ok  sparse VFR take, beat starting inside a hold: naive trim keeps {naive_n} of {want} "
                     f"frames, preview_cut.normalise then frame trim keeps {fixed_n}")
    return notes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("candidate", nargs="?", type=Path)
    ap.add_argument("--manifest", type=Path, help="cut.json from preview_cut.py")
    ap.add_argument("--size", help="expected WxH (default: the manifest's, else 886x1920)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            print(f"error: {tool} not on PATH", file=sys.stderr)
            return 2
    if args.self_test:
        try:
            notes = self_test()
        except Fail as e:
            print(f"FAIL self-test: {e}", file=sys.stderr)
            return 1
        print("\n".join(notes))
        print(f"self-test passed: {len(notes)} cases")
        return 0
    if not args.candidate:
        ap.error("a candidate file, or --self-test")
    size = tuple(int(x) for x in args.size.lower().split("x")) if args.size else None
    try:
        rep = check_candidate(args.candidate, args.manifest, size)
    except Fail as e:
        print(f"FAIL {e}", file=sys.stderr)
        return 1
    print(rep.text())
    if rep.failed:
        print(f"{len(rep.failed)} check(s) failed", file=sys.stderr)
        return 1
    print(f"all {len(rep.lines)} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
