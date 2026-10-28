#!/usr/bin/env python3
"""Place a real app capture onto a phone screen in a generated or photographed scene.

    place_screen.py <scene.png> <capture.png> <out.png> [--key 00ff00] [--tolerance 90] [--corners x,y x,y x,y x,y]

Generate the scene with the phone's screen as a flat chroma-key colour (default
pure green, #00FF00). The script finds the largest region near that colour,
takes its four extreme corners, perspective-warps the capture onto them, and
blends the edge so no green fringe remains. Pass --corners (top-left, top-right,
bottom-right, bottom-left) to skip detection, for a photograph or a scene whose
key colour came out uneven.

Why: an image model's idea of the app's UI is invented; App Store art must show
the real app, so the screen content is always a real capture.

Requires Pillow and numpy. Prints the corners it used, so a run can be repeated
with --corners after a hand check.
"""
import argparse
import sys

import numpy as np
from PIL import Image, ImageFilter


def find_corners(scene, key, tol):
    px = np.asarray(scene.convert("RGB")).astype(int)
    dist = np.sqrt(((px - np.array(key)) ** 2).sum(axis=2))
    mask = dist < tol
    if mask.sum() < 500:
        sys.exit(f"no chroma-key region found (only {int(mask.sum())} px within {tol} of #{bytes(key).hex()})")
    # Keep the largest connected blob, so stray green elsewhere is ignored.
    from collections import deque
    h, w = mask.shape
    seen = np.zeros_like(mask)
    best = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        blob, q = [], deque([(y0, x0)])
        seen[y0, x0] = True
        while q:
            y, x = q.popleft()
            blob.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if len(blob) > len(best):
            best = blob
    ys, xs = np.array([b[0] for b in best]), np.array([b[1] for b in best])
    # Extreme points along the diagonals give the quad's corners.
    tl = (xs[np.argmin(xs + ys)], ys[np.argmin(xs + ys)])
    br = (xs[np.argmax(xs + ys)], ys[np.argmax(xs + ys)])
    tr = (xs[np.argmax(xs - ys)], ys[np.argmax(xs - ys)])
    bl = (xs[np.argmin(xs - ys)], ys[np.argmin(xs - ys)])
    region = np.zeros_like(mask)
    region[ys, xs] = True
    return [tl, tr, br, bl], region


def perspective_coeffs(dst, src):
    """Coefficients for PIL's PERSPECTIVE transform mapping output (dst) points to input (src) points."""
    a = []
    for (x, y), (u, v) in zip(dst, src):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    b = np.array(src).reshape(8)
    return np.linalg.solve(np.array(a, dtype=float), b).tolist()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene"); ap.add_argument("capture"); ap.add_argument("out")
    ap.add_argument("--key", default="00ff00")
    ap.add_argument("--tolerance", type=float, default=90)
    ap.add_argument("--corners", nargs=4)
    ap.add_argument("--inset", type=float, default=1.5, help="px to grow the warped screen past the key edge")
    a = ap.parse_args()
    scene = Image.open(a.scene).convert("RGB")
    capture = Image.open(a.capture).convert("RGB")
    key = tuple(int(a.key[i:i + 2], 16) for i in (0, 2, 4))
    if a.corners:
        corners = [tuple(float(v) for v in c.split(",")) for c in a.corners]
        region = None
    else:
        corners, region = find_corners(scene, key, a.tolerance)
    print("corners (tl tr br bl):", " ".join(f"{int(x)},{int(y)}" for x, y in corners))

    # Grow the quad slightly about its centre so the warped capture covers the key's antialiased rim.
    cx = sum(c[0] for c in corners) / 4; cy = sum(c[1] for c in corners) / 4
    grown = []
    for x, y in corners:
        dx, dy = x - cx, y - cy
        n = max(1e-6, (dx * dx + dy * dy) ** 0.5)
        grown.append((x + dx / n * a.inset, y + dy / n * a.inset))
    cw, ch = capture.size
    coeffs = perspective_coeffs(grown, [(0, 0), (cw, 0), (cw, ch), (0, ch)])
    warped = capture.transform(scene.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    quad = Image.new("L", scene.size, 0)
    from PIL import ImageDraw
    ImageDraw.Draw(quad).polygon(grown, fill=255)
    if region is not None:
        # Union with the detected key pixels, then soften one pixel so the edge sits naturally.
        key_mask = Image.fromarray((region * 255).astype("uint8"))
        quad = Image.fromarray(np.maximum(np.asarray(quad), np.asarray(key_mask.filter(ImageFilter.MaxFilter(3)))))
    quad = quad.filter(ImageFilter.GaussianBlur(0.8))
    out = Image.composite(warped, scene, quad)
    # Any key-coloured pixels left outside the screen are reported, not hidden.
    # Leftover key colour near the screen means a fringe; elsewhere it is the scene's own business.
    xs = [p[0] for p in grown]; ys = [p[1] for p in grown]
    box = (max(0, int(min(xs)) - 12), max(0, int(min(ys)) - 12), int(max(xs)) + 12, int(max(ys)) + 12)
    near = np.asarray(out.crop(box)).astype(int)
    left = (np.sqrt(((near - np.array(key)) ** 2).sum(axis=2)) < a.tolerance / 2).sum()
    if left:
        print(f"warning: {int(left)} key-coloured pixels remain around the screen; check the edges")
    out.save(a.out)
    print("wrote", a.out, out.size)


if __name__ == "__main__":
    main()
