"""
Textures for the vegetation kits (blender/vegetation.py): bark for the trunks and alpha-cut cards
for the foliage, in their real colours (a SurfaceAppearance isn't tinted by its part's colour).
Written to blender/out/textures/<Name>_<Map>.(png|jpg), listed under "Kits" in manifest.json.

  /root/tools/blendenv/bin/python blender/veg_textures.py [Name,Name...]   (only those; the rest kept)

Card images are PNG with alpha. In UV space v runs up the image (v = 0 at the bottom row), so a
frond's base is at the bottom of its image and its tip at the top.
"""

import json
import math
import os
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texlib as T  # noqa: E402
from texlib import F, lerp, smoothstep  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "textures")

KITS = []


def kit(name, width, height, alpha=False, tile=(1.0, 1.0), rnd=1):
    """`rnd`: the release the images ship in (1: Textures.fbx; 3: the detail pass's Plants.fbx)."""

    def wrap(fn):
        KITS.append({"Name": name, "W": width, "H": height, "Alpha": alpha, "Tile": tile, "Fn": fn, "Round": rnd})
        return fn

    return wrap


def grid(w, h):
    xs = (np.arange(w, dtype=F) + 0.5) / w
    ys = (np.arange(h, dtype=F) + 0.5) / h
    return np.meshgrid(xs, ys)


def col(*c):
    return np.array(c, F)


# ---------------------------------------------------------------------------- bark


@kit("PalmBark", 512, 512, tile=(1.0, 0.6))
def palm_bark(n, x, y, w, h):
    # coconut palm: leaf-scar rings every ~5 cm (12 to the tile's 0.6 m), fibrous between, the
    # rings uneven round the trunk
    rings = 12
    ring_pos = y * rings + 0.15 * n.fbm(x, y, 3, 3, cy=1)
    r = ring_pos % 1
    groove = smoothstep(0.16, 0.0, np.minimum(r, 1 - r))
    fibre = n.fbm(x, y, 60, 3, cy=6)
    lum = 0.5 + 0.06 * fibre + 0.05 * n.fbm(x, y, 4, 4) - 0.18 * groove
    color = lum[..., None] * col(1.0, 0.92, 0.8)
    color = lerp(color, lum[..., None] * col(0.85, 0.85, 0.8), smoothstep(0.2, 0.6, n.fbm(x + 0.3, y, 3, 3))[..., None] * 0.6)
    height = 0.004 * (1 - groove) + 0.0006 * fibre
    rough = 0.88 + 0.05 * groove
    return {"color": color, "height": height, "rough": rough, "tile": 0.6}


@kit("RoyalTrunk", 512, 512, tile=(1.0, 1.0))
def royal_trunk(n, x, y, w, h):
    # royal palm: smooth, pale grey, faint growth rings every ~10 cm, fine vertical checks
    rings = 10
    r = (y * rings + 0.08 * n.fbm(x, y, 2, 3, cy=1)) % 1
    ring = smoothstep(0.06, 0.0, np.minimum(r, 1 - r))
    lum = 0.72 + 0.04 * n.fbm(x, y, 5, 4) + 0.02 * n.fbm(x, y, 60, 2) - 0.06 * ring
    lichen = smoothstep(0.45, 0.65, n.fbm(x, y, 8, 4))
    color = lum[..., None] * col(1.0, 0.99, 0.95)
    color = lerp(color, lum[..., None] * col(0.92, 0.97, 0.86), lichen[..., None] * 0.5)
    height = -0.0015 * ring + 0.0003 * n.fbm(x, y, 60, 2)
    return {"color": color, "height": height, "rough": 0.7 + 0.08 * lichen, "tile": 1.0}


@kit("OakBark", 512, 512, tile=(1.0, 1.0))
def oak_bark(n, x, y, w, h):
    # live oak: deep, blocky vertical furrows, dark grey-brown, a little lichen
    v = n.fbm(x, y, 8, 5, cy=2)
    furrow = smoothstep(0.1, -0.25, v)
    blocks = smoothstep(0.3, 0.0, np.abs(np.sin(2 * math.pi * (y * 6 + 0.6 * n.fbm(x, y, 4, 3)))))
    lum = 0.36 + 0.05 * n.fbm(x, y, 30, 3) - 0.14 * furrow - 0.04 * blocks
    lichen = smoothstep(0.5, 0.7, n.fbm(x, y, 9, 4))
    color = lum[..., None] * col(1.0, 0.9, 0.78)
    color = lerp(color, col(0.62, 0.66, 0.55) * np.ones_like(color), lichen[..., None] * 0.45)
    height = -0.015 * furrow - 0.004 * blocks + 0.001 * n.fbm(x, y, 40, 3)
    return {"color": color, "height": height, "rough": 0.9, "tile": 1.0}


@kit("PineBark", 512, 512, tile=(1.0, 1.0))
def pine_bark(n, x, y, w, h):
    # slash pine: reddish-brown plates split by dark fissures
    f1, f2, ids = n.worley(x, y, 7, jitter=1.0, cy=4)
    plate = smoothstep(0.0, 0.12, f2 - f1)
    tone = n.per_cell(28, 0.85, 1.1)[ids]
    lum = (0.42 * tone + 0.04 * n.fbm(x, y, 40, 3)) * (0.45 + 0.55 * plate)
    color = lum[..., None] * col(1.0, 0.72, 0.55)
    height = 0.008 * plate + 0.0008 * n.fbm(x, y, 50, 3)
    return {"color": color, "height": height, "rough": 0.88, "tile": 1.0}


# ---------------------------------------------------------------------------- foliage cards


def _blade(acc_a, acc_c, acc_h, cx, cy, ax, ay, length, width, color, w, h, fold=0.6, droop=0.0, tip_dry=0.0):
    """Rasterise a lanceolate leaf from (cx, cy) along (ax, ay) into the accumulators (pixels)."""
    ex, ey = cx + ax * length, cy + ay * length
    x0, x1 = int(max(0, min(cx, ex) - width - 2)), int(min(w - 1, max(cx, ex) + width + 2))
    y0, y1 = int(max(0, min(cy, ey) - width - 2)), int(min(h - 1, max(cy, ey) + width + 2))
    if x1 <= x0 or y1 <= y0:
        return
    ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(F)
    dx, dy = xs - cx, ys - cy
    s = (dx * ax + dy * ay) / length  # along, 0..1
    d = -dx * ay + dy * ax  # across (signed)
    half = width * np.clip(np.sin(math.pi * np.clip(s, 0, 1)), 0, 1) ** 0.7
    inside = (s >= 0) & (s <= 1)
    cover = np.clip(half - np.abs(d) + 0.7, 0, 1) * inside
    if not cover.any():
        return
    c = np.broadcast_to(color, cover.shape + (3,)).copy()
    if tip_dry > 0:
        dry = smoothstep(1 - tip_dry, 1.0, s)[..., None]
        c = lerp(c, col(0.62, 0.5, 0.3) * np.ones_like(c), dry)
    mid = smoothstep(1.2, 0.0, np.abs(d))[..., None]
    c = lerp(c, c * 1.25, mid * 0.5)
    hh = (fold * np.clip(1 - np.abs(d) / np.maximum(half, 1e-3), 0, 1)) * cover
    sl = (slice(y0, y1 + 1), slice(x0, x1 + 1))
    a_old = acc_a[sl]
    take = cover > a_old * 0.999
    acc_c[sl] = np.where((cover > 0)[..., None] & take[..., None], lerp(acc_c[sl], c, cover[..., None]), acc_c[sl])
    acc_h[sl] = np.where(take, np.maximum(acc_h[sl], hh), acc_h[sl])
    acc_a[sl] = np.maximum(a_old, cover)


@kit("PalmFrond", 512, 1024, alpha=True)
def palm_frond(n, x, y, w, h):
    # a pinnate coconut frond seen flat: the rachis up the middle (base at the bottom), ~80
    # leaflets a side angled toward the tip, longest mid-frond, some dry tips
    rng = n.rng
    A = np.zeros((h, w), F)
    C = np.zeros((h, w, 3), F)
    H = np.zeros((h, w), F)
    cx = w / 2
    leaflets = 82
    for side in (-1, 1):
        for k in range(leaflets):
            t = 0.04 + 0.94 * (k + rng.uniform(-0.3, 0.3)) / leaflets
            py = h * (1 - t)
            rach = cx + side * (6 * (1 - t) + 1)
            L = (w * 0.47) * (math.sin(math.pi * min(1.0, t * 0.92 + 0.08)) ** 0.6) * rng.uniform(0.85, 1.05)
            ang = math.radians(rng.uniform(32, 48))
            ax, ay = side * math.sin(ang), -math.cos(ang)
            g = rng.uniform(0.75, 1.1)
            c = col(0.2, 0.36, 0.11) * g if rng.random() > 0.15 else col(0.33, 0.42, 0.15) * g
            _blade(A, C, H, rach, py, ax, ay, L, rng.uniform(4.0, 6.5) * (0.6 + 0.4 * math.sin(math.pi * t)), c, w, h, fold=1.0, tip_dry=0.12 if rng.random() < 0.25 else 0.0)
    # the rachis
    yy = (np.arange(h, dtype=F) + 0.5)[:, None] * np.ones((1, w), F)
    xx = (np.arange(w, dtype=F) + 0.5)[None, :] * np.ones((h, 1), F)
    t = 1 - yy / h
    rw = 9 * (1 - t) + 2.5
    rmask = np.clip(rw - np.abs(xx - cx) + 0.7, 0, 1) * (t > 0.0)
    rc = col(0.55, 0.58, 0.3) * (0.9 + 0.1 * np.cos(math.pi * np.clip((xx - cx) / np.maximum(rw, 1), -1, 1)))[..., None]
    C = lerp(C, rc, rmask[..., None])
    A = np.maximum(A, rmask)
    H = np.maximum(H, rmask * 2.0 * np.sqrt(np.clip(1 - ((xx - cx) / np.maximum(rw, 1)) ** 2, 0, 1)))
    rgba = np.concatenate([C, A[..., None]], -1)
    return {"color": rgba, "height": H * 0.0004, "rough": 0.62 + 0.1 * (1 - A), "tile": 0.6}


@kit("OakLeaves", 1024, 1024, alpha=True)
def oak_leaves(n, x, y, w, h):
    # live oak: four leaf clusters (a 2 x 2 atlas), small glossy elliptical leaves round twigs
    rng = n.rng
    A = np.zeros((h, w), F)
    C = np.zeros((h, w, 3), F)
    H = np.zeros((h, w), F)
    q = w // 2
    for qi in range(2):
        for qj in range(2):
            ox, oy = qi * q, qj * q
            ccx, ccy = ox + q / 2, oy + q / 2
            # twigs from the cluster's base outward
            for _ in range(7):
                a = rng.uniform(0, 2 * math.pi)
                L = rng.uniform(0.25, 0.42) * q
                _blade(A, C, H, ccx, ccy + q * 0.3, math.cos(a) * 0.6, -abs(math.sin(a)), L, 1.6, col(0.22, 0.17, 0.12), w, h, fold=0.2)
            lobes = [rng.uniform(0.75, 1.0) for _ in range(9)]
            for _ in range(1100):
                a = rng.uniform(0, 2 * math.pi)
                # a lobed outline, not a disc
                f = a / (2 * math.pi) * 9
                i0 = int(f) % 9
                lobe = lobes[i0] + (lobes[(i0 + 1) % 9] - lobes[i0]) * (f - int(f))
                r = q * 0.44 * lobe * math.sqrt(rng.random()) ** 0.8
                px, py = ccx + r * math.cos(a), ccy + r * math.sin(a) * 0.85
                la = rng.uniform(0, 2 * math.pi)
                g = rng.uniform(0.7, 1.15)
                tone = rng.random()
                if tone < 0.7:
                    c = col(0.16, 0.3, 0.1) * g
                elif tone < 0.9:
                    c = col(0.3, 0.42, 0.14) * g
                else:
                    c = col(0.45, 0.4, 0.18) * g
                _blade(A, C, H, px, py, math.cos(la), math.sin(la), rng.uniform(13, 22), rng.uniform(4.0, 6.0), c, w, h, fold=1.2)
    rgba = np.concatenate([C, A[..., None]], -1)
    return {"color": rgba, "height": H * 0.0006, "rough": 0.58 + 0.2 * (1 - A), "tile": 0.8}


@kit("PineNeedles", 512, 512, alpha=True)
def pine_needles(n, x, y, w, h):
    # slash pine: tufts of long needles from the branch tips (base at the bottom of the image)
    rng = n.rng
    A = np.zeros((h, w), F)
    C = np.zeros((h, w, 3), F)
    H = np.zeros((h, w), F)
    for tuft in range(5):
        bx = w * (0.2 + 0.6 * rng.random())
        by = h * (0.55 + 0.35 * rng.random())
        for _ in range(140):
            a = math.radians(rng.uniform(-75, 75)) - math.pi / 2
            L = rng.uniform(0.25, 0.48) * h
            g = rng.uniform(0.75, 1.1)
            _blade(A, C, H, bx, by, math.cos(a), math.sin(a), L, 1.4, col(0.2, 0.33, 0.14) * g, w, h, fold=0.4)
    rgba = np.concatenate([C, A[..., None]], -1)
    return {"color": rgba, "height": H * 0.0003, "rough": 0.5 + 0.2 * (1 - A), "tile": 0.5}


# ---------------------------------------------------------------------------- round 3: the detail pass's plants
# Shrubs, ground cover and three more trees (blender/vegetation.py's round 2 kits). Their images
# ship in Plants.fbx, an add-on import next to Textures.fbx (rnd=3). These are painted on a Canvas
# (premultiplied "over" compositing, so leaf edges blend over the leaves beneath).


class Canvas:
    """An RGBA leaf canvas: coverage (alpha), premultiplied colour, height (for the normal map)
    and roughness, each new shape painted over what's there."""

    def __init__(self, w, h, rough=0.6):
        self.w, self.h = w, h
        self.A = np.zeros((h, w), F)
        self.C = np.zeros((h, w, 3), F)
        self.H = np.zeros((h, w), F)
        self.R = np.full((h, w), rough, F)

    def box(self, xs, ys, pad):
        x0 = int(max(0, math.floor(min(xs) - pad)))
        x1 = int(min(self.w - 1, math.ceil(max(xs) + pad)))
        y0 = int(max(0, math.floor(min(ys) - pad)))
        y1 = int(min(self.h - 1, math.ceil(max(ys) + pad)))
        if x1 <= x0 or y1 <= y0:
            return None
        gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1].astype(F)
        return (slice(y0, y1 + 1), slice(x0, x1 + 1)), gx + 0.5, gy + 0.5

    def paint(self, sl, cover, c, hh, rough):
        k = cover[..., None]
        self.C[sl] = lerp(self.C[sl], c, k)
        self.A[sl] = lerp(self.A[sl], 1.0, cover)
        self.H[sl] = lerp(self.H[sl], hh, cover)
        if rough is not None:
            self.R[sl] = lerp(self.R[sl], F(rough), cover)

    def leaf(self, cx, cy, ax, ay, length, width, color, profile="lance", fold=0.8, vein=None, vein_mix=0.5, lateral=0, lateral_angle=50.0, serrate=0.0, teeth=7.0, spot=None, field=None, rough=None, comb=0.0, comb_period=6.0, tip_dry=0.0, edge=None, edge_mix=0.0, shade=0.16, split=0.0):
        """A leaf (or petal, bract, leaflet) from its stalk end (cx, cy) pointing along (ax, ay),
        `length` long and `width` at its widest each side of the midrib. `profile`: "lance"
        (pointed both ends), "ovate" (broadest below the middle), "obovate" (broadest toward the
        tip: petals), "round" (an ellipse), "strap" (parallel sides: stems), "wedge" (widening
        from the base: a palm fan's segment, its tip `split` in two). Options: a midrib and
        `lateral` side veins in `vein`, serrated edges, speckles (`spot` = (colour, threshold)
        over `field`), a comb of leaflets (`comb`), a dry tip, a coloured edge."""
        n = math.hypot(ax, ay)
        ax, ay = ax / n, ay / n
        ex, ey = cx + ax * length, cy + ay * length
        got = self.box((cx, ex), (cy, ey), width + 3)
        if got is None:
            return
        sl, xs, ys = got
        dx, dy = xs - cx, ys - cy
        along = dx * ax + dy * ay
        s = along / length
        d = -dx * ay + dy * ax
        sc = np.clip(s, 0, 1)
        if profile == "ovate":
            half = width * np.clip(np.sin(math.pi * sc ** 0.8), 0, 1) ** 0.6
        elif profile == "obovate":
            half = width * np.clip(np.sin(math.pi * sc ** 1.6), 0, 1) ** 0.45
        elif profile == "round":
            half = width * np.sqrt(np.clip(1 - (2 * sc - 1) ** 2, 0, 1))
        elif profile == "strap":
            half = width * np.clip((1 - sc) / 0.3, 0, 1) ** 0.5
        elif profile == "wedge":
            half = width * np.clip(sc / 0.6, 0.05, 1) ** 0.9 * np.clip((1 - sc) / 0.22, 0, 1) ** 0.6
        else:
            half = width * np.clip(np.sin(math.pi * sc), 0, 1) ** 0.7
        if serrate > 0:
            half = half - serrate * (0.5 + 0.5 * np.cos(2 * math.pi * along / teeth)) * (sc > 0.1)
        inside = (s >= 0) & (s <= 1)
        cover = np.clip(half - np.abs(d) + 0.5, 0, 1) * inside
        rel = np.clip(np.abs(d) / np.maximum(half, 1e-3), 0, 1)
        if split > 0:
            cut = np.clip((sc - (1 - split)) / split, 0, 1)
            cover = cover * np.clip((np.abs(d) - half * 0.4 * cut) + 0.5, 0, 1)
        if comb > 0:
            gap = 0.5 + 0.5 * np.cos(2 * math.pi * along / comb_period)
            leaflets = np.clip((gap - comb) * 5 + 0.5, 0, 1)
            cover = cover * np.where(np.abs(d) < np.maximum(0.9, half * 0.12), 1.0, leaflets)
        if not (cover > 0.002).any():
            return
        c = np.empty(cover.shape + (3,), F)
        c[...] = np.asarray(color, F)
        if spot is not None and field is not None:
            m = smoothstep(spot[1], spot[1] + 0.06, field[sl])[..., None]
            c = lerp(c, np.asarray(spot[0], F), m)
        if edge is not None:
            c = lerp(c, np.asarray(edge, F), smoothstep(0.55, 0.98, rel)[..., None] * edge_mix)
        vm = np.zeros(cover.shape, F)
        if vein is not None:
            vm = smoothstep(1.4, 0.3, np.abs(d)) * (sc < 0.96)
            if lateral > 0:
                k = 1 / math.tan(math.radians(lateral_angle))
                spacing = length / (lateral + 1)
                q = (along - np.abs(d) * k) / spacing
                fr = np.abs(q - np.round(q)) * spacing / math.sqrt(1 + k * k)
                lat = np.clip(1 - fr / 0.9, 0, 1) * (rel < 0.88) * (q > 0.5) * (q < lateral + 0.5)
                vm = np.maximum(vm, lat * 0.75)
            c = lerp(c, np.asarray(vein, F), (vm * vein_mix)[..., None])
        c = c * (1 + shade * 0.5 - shade * rel[..., None] ** 2)
        if tip_dry > 0:
            c = lerp(c, np.asarray((0.58, 0.46, 0.28), F), smoothstep(1 - tip_dry, 1.0, s)[..., None])
        hh = fold * (1 - rel) - 0.35 * vm
        self.paint(sl, cover, c, hh, rough)

    def stroke(self, pts, widths, colors, rough=None, fold=0.4):
        """A tapering stroke through `pts` (pixels) with a half width and colour at each point:
        stems, grass blades, threads."""
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            w0, w1 = widths[i], widths[i + 1]
            got = self.box((x0, x1), (y0, y1), max(w0, w1) + 2)
            if got is None:
                continue
            sl, xs, ys = got
            vx, vy = x1 - x0, y1 - y0
            L2 = max(vx * vx + vy * vy, 1e-6)
            t = np.clip(((xs - x0) * vx + (ys - y0) * vy) / L2, 0, 1)
            dist = np.hypot(xs - (x0 + vx * t), ys - (y0 + vy * t))
            half = w0 + (w1 - w0) * t
            cover = np.clip(half - dist + 0.5, 0, 1)
            if not (cover > 0.002).any():
                continue
            c0, c1 = np.asarray(colors[i], F), np.asarray(colors[i + 1], F)
            c = c0 + (c1 - c0) * t[..., None]
            rel = np.clip(dist / np.maximum(half, 1e-3), 0, 1)
            c = c * (1.06 - 0.12 * rel[..., None] ** 2)
            self.paint(sl, cover, c, fold * (1 - rel), rough)

    def plume(self, pts, width, color, field, rough=0.85):
        """A soft flower head along `pts` (a grass plume): thick in the middle, thinning to wisps
        at its edge and ends, broken up by `field`."""
        segs = len(pts) - 1
        for i in range(segs):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            got = self.box((x0, x1), (y0, y1), width + 3)
            if got is None:
                continue
            sl, xs, ys = got
            vx, vy = x1 - x0, y1 - y0
            L2 = max(vx * vx + vy * vy, 1e-6)
            t = np.clip(((xs - x0) * vx + (ys - y0) * vy) / L2, 0, 1)
            dist = np.hypot(xs - (x0 + vx * t), ys - (y0 + vy * t))
            sg = (i + t) / segs
            half = width * np.clip(np.sin(math.pi * np.clip(sg * 0.9 + 0.1, 0, 1)), 0.15, 1) ** 0.6
            body = 1 - dist / np.maximum(half, 0.5)
            cover = np.clip(body * 1.8 + field[sl] * 1.4 - 0.25, 0, 1) * 0.92
            if not (cover > 0.002).any():
                continue
            c = np.empty(cover.shape + (3,), F)
            c[...] = np.asarray(color, F)
            c = c * (0.85 + 0.3 * np.clip(field[sl] + 0.5, 0, 1))[..., None]
            self.paint(sl, cover, c, 0.3 * np.clip(body, 0, 1), rough)

    def result(self, tile, height_scale=0.0006):
        rgba = np.concatenate([self.C, self.A[..., None]], -1)
        return {"color": rgba, "height": self.H * height_scale, "rough": np.where(self.A > 0.02, self.R, 0.9), "tile": tile}


def _jit(rng, c, amount=0.12):
    g = rng.uniform(1 - amount, 1 + amount)
    return tuple(min(1.0, v * g) for v in c)


def _twigs(cv, rng, ox, oy, q, count, color=(0.30, 0.24, 0.15), width=2.2):
    """A cluster's twigs from its foot (the bottom of its quadrant) up and out."""
    fx, fy = ox + q / 2, oy + q * 0.94
    for _ in range(count):
        a = math.radians(rng.uniform(-150, -30))
        L = rng.uniform(0.3, 0.5) * q
        mx, my = fx + math.cos(a) * L * 0.5 + rng.uniform(-10, 10), fy + math.sin(a) * L * 0.5
        ex, ey = fx + math.cos(a) * L, fy + math.sin(a) * L
        cv.stroke([(fx + rng.uniform(-6, 6), fy), (mx, my), (ex, ey)], [width, width * 0.7, width * 0.35], [color, color, color], rough=0.85, fold=0.3)


@kit("HibiscusLeaves", 1024, 1024, alpha=True, rnd=3)
def hibiscus_leaves(n, x, y, w, h):
    # Chinese hibiscus: four clusters (a 2 x 2 atlas) of glossy, toothed dark leaves with big
    # five-petalled flowers (red, and salmon in one), a dark eye and the long staminal column
    rng = n.rng
    cv = Canvas(w, h, rough=0.55)
    q = w // 2
    tones = [(0.80, 0.05, 0.07), (0.76, 0.04, 0.10), (0.96, 0.44, 0.30), (0.84, 0.07, 0.06)]
    for qi in range(2):
        for qj in range(2):
            ox, oy = qi * q, qj * q
            ccx, ccy = ox + q / 2, oy + q * 0.47
            _twigs(cv, rng, ox, oy, q, 7)
            for _ in range(64):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.38 * math.sqrt(rng.random())
                px, py = ccx + r * math.cos(a), ccy + r * math.sin(a) * 0.92
                la = a + rng.uniform(-0.9, 0.9)
                base = _jit(rng, (0.09, 0.25, 0.06) if rng.random() > 0.15 else (0.18, 0.34, 0.08))
                L = rng.uniform(70, 112)
                cv.leaf(px - math.cos(la) * L * 0.45, py - math.sin(la) * L * 0.45, math.cos(la), math.sin(la), L, L * rng.uniform(0.3, 0.38), base, profile="ovate", fold=1.0, vein=(0.28, 0.44, 0.15), vein_mix=0.4, lateral=5, serrate=1.6, teeth=7.0, rough=0.36)
            for _ in range(rng.integers(2, 5)):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.3 * math.sqrt(rng.random())
                fx, fy = ccx + r * math.cos(a), ccy + r * math.sin(a)
                tone = tones[qi * 2 + qj]
                pl = rng.uniform(58, 76)
                spin = rng.uniform(0, 2 * math.pi)
                for k in range(5):
                    pa = spin + k * 2 * math.pi / 5 + rng.uniform(-0.08, 0.08)
                    cv.leaf(fx, fy, math.cos(pa), math.sin(pa), pl * rng.uniform(0.92, 1.06), pl * 0.52, _jit(rng, tone, 0.06), profile="obovate", fold=0.6, vein=tuple(min(1.0, v * 1.3) for v in tone), vein_mix=0.3, lateral=4, lateral_angle=20, rough=0.62, edge=tuple(v * 0.8 for v in tone), edge_mix=0.35)
                cv.leaf(fx - 9, fy, 1, 0, 18, 9, (0.36, 0.02, 0.05), profile="round", fold=0.2, rough=0.7)
                ca = rng.uniform(0, 2 * math.pi)
                cv.stroke([(fx, fy), (fx + math.cos(ca) * pl * 0.95, fy + math.sin(ca) * pl * 0.95)], [2.4, 1.6], [tuple(v * 0.9 for v in tone), tone], rough=0.6)
                ex, ey = fx + math.cos(ca) * pl * 0.95, fy + math.sin(ca) * pl * 0.95
                for _ in range(7):
                    cv.leaf(ex + rng.uniform(-6, 4), ey + rng.uniform(-5, 5), 1, 0, 4, 2.2, (0.96, 0.80, 0.22), profile="round", fold=0.2, rough=0.7)
    return cv.result(tile=1.2)


@kit("CrotonLeaves", 1024, 1024, alpha=True, rnd=3)
def croton_leaves(n, x, y, w, h):
    # crotons: leathery, glossy leaves splashed with colour, one cultivar a quadrant: Petra (green
    # and orange, yellow veins), Mammy (burgundy and red), Gold Dust (green speckled gold) and a
    # yellow-orange one
    rng = n.rng
    cv = Canvas(w, h, rough=0.5)
    field = n.fbm(x, y, 48, 3)
    q = w // 2
    looks = [
        [((0.10, 0.27, 0.07), (0.96, 0.80, 0.14), None), ((0.66, 0.28, 0.05), (0.96, 0.78, 0.16), None), ((0.14, 0.30, 0.07), (0.94, 0.48, 0.10), None)],
        [((0.36, 0.05, 0.08), (0.92, 0.36, 0.10), None), ((0.55, 0.09, 0.08), (0.96, 0.56, 0.12), None), ((0.22, 0.05, 0.09), (0.84, 0.24, 0.12), None)],
        [((0.11, 0.28, 0.07), (0.80, 0.72, 0.18), ((0.94, 0.80, 0.18), 0.12)), ((0.13, 0.31, 0.08), (0.80, 0.72, 0.20), ((0.96, 0.86, 0.26), 0.2))],
        [((0.82, 0.58, 0.08), (0.20, 0.34, 0.08), None), ((0.86, 0.42, 0.07), (0.96, 0.80, 0.20), None), ((0.18, 0.34, 0.07), (0.96, 0.84, 0.20), None)],
    ]
    for qi in range(2):
        for qj in range(2):
            ox, oy = qi * q, qj * q
            ccx, ccy = ox + q / 2, oy + q * 0.48
            _twigs(cv, rng, ox, oy, q, 5, color=(0.26, 0.22, 0.12), width=2.8)
            palette = looks[qi * 2 + qj]
            for _ in range(46):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.34 * math.sqrt(rng.random())
                px, py = ccx + r * math.cos(a), ccy + r * math.sin(a)
                la = a + rng.uniform(-0.7, 0.7)
                base, vein, spot = palette[rng.integers(0, len(palette))]
                L = rng.uniform(95, 150)
                cv.leaf(px - math.cos(la) * L * 0.4, py - math.sin(la) * L * 0.4, math.cos(la), math.sin(la), L, L * rng.uniform(0.17, 0.27), _jit(rng, base, 0.1), profile="lance" if rng.random() < 0.6 else "ovate", fold=1.1, vein=vein, vein_mix=0.85, lateral=7, lateral_angle=40, spot=spot, field=field, rough=0.32)
    return cv.result(tile=1.0)


@kit("BougainvilleaLeaves", 1024, 1024, alpha=True, rnd=3)
def bougainvillea_leaves(n, x, y, w, h):
    # bougainvillea: thin thorny stems, small heart-ish leaves and masses of papery magenta bracts
    # in threes round tiny cream flowers; the quadrants go from mostly bracts to mostly leaves
    rng = n.rng
    cv = Canvas(w, h, rough=0.7)
    q = w // 2
    bract_counts = [80, 55, 32, 75]
    tones = [(0.80, 0.10, 0.46), (0.82, 0.12, 0.50), (0.78, 0.09, 0.44), (0.70, 0.06, 0.40)]
    for qi in range(2):
        for qj in range(2):
            ox, oy = qi * q, qj * q
            ccx, ccy = ox + q / 2, oy + q * 0.48
            k = qi * 2 + qj
            _twigs(cv, rng, ox, oy, q, 8, color=(0.34, 0.26, 0.16), width=1.8)
            for _ in range(70 - bract_counts[k] // 3):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.40 * math.sqrt(rng.random())
                px, py = ccx + r * math.cos(a), ccy + r * math.sin(a)
                la = rng.uniform(0, 2 * math.pi)
                L = rng.uniform(32, 52)
                cv.leaf(px, py, math.cos(la), math.sin(la), L, L * 0.36, _jit(rng, (0.17, 0.36, 0.09)), profile="ovate", fold=0.8, vein=(0.30, 0.48, 0.16), vein_mix=0.4, rough=0.55)
            for _ in range(bract_counts[k]):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.40 * math.sqrt(rng.random())
                bx, by = ccx + r * math.cos(a), ccy + r * math.sin(a)
                tone = _jit(rng, tones[k], 0.1)
                bl = rng.uniform(26, 40)
                spin = rng.uniform(0, 2 * math.pi)
                for j in range(3):
                    ba = spin + j * 2 * math.pi / 3 + rng.uniform(-0.2, 0.2)
                    cv.leaf(bx, by, math.cos(ba), math.sin(ba), bl, bl * 0.42, tone, profile="ovate", fold=0.5, vein=tuple(min(1.0, v * 1.35) for v in tone), vein_mix=0.45, lateral=3, lateral_angle=35, rough=0.75, edge=tuple(v * 0.75 for v in tone), edge_mix=0.3)
                cv.leaf(bx - 2.5, by, 1, 0, 5, 2.2, (0.96, 0.94, 0.80), profile="round", fold=0.2, rough=0.7)
    return cv.result(tile=1.0)


@kit("SeaGrapeLeaves", 1024, 1024, alpha=True, rnd=3)
def sea_grape_leaves(n, x, y, w, h):
    # sea grape: big round leathery leaves with red veins on red stalks, some older ones gone
    # bronze; one quadrant carries a drooping bunch of grapes
    rng = n.rng
    cv = Canvas(w, h, rough=0.5)
    q = w // 2
    for qi in range(2):
        for qj in range(2):
            ox, oy = qi * q, qj * q
            ccx, ccy = ox + q / 2, oy + q * 0.48
            _twigs(cv, rng, ox, oy, q, 5, color=(0.38, 0.30, 0.22), width=3.0)
            for _ in range(24):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.30 * math.sqrt(rng.random())
                px, py = ccx + r * math.cos(a), ccy + r * math.sin(a)
                la = a + rng.uniform(-0.6, 0.6)
                tone = rng.random()
                base = (0.22, 0.38, 0.13) if tone < 0.8 else ((0.50, 0.28, 0.13) if tone < 0.9 else (0.34, 0.46, 0.17))
                L = rng.uniform(120, 170)
                sx, sy = px - math.cos(la) * L * 0.5, py - math.sin(la) * L * 0.5
                cv.stroke([(sx - math.cos(la) * 16, sy - math.sin(la) * 16), (sx + math.cos(la) * 6, sy + math.sin(la) * 6)], [2.6, 2.2], [(0.62, 0.20, 0.18), (0.62, 0.20, 0.18)], rough=0.6)
                cv.leaf(sx, sy, math.cos(la), math.sin(la), L, L * rng.uniform(0.5, 0.56), _jit(rng, base), profile="round", fold=0.7, vein=(0.72, 0.22, 0.22), vein_mix=0.9, lateral=5, lateral_angle=56, rough=0.42, shade=0.28, edge=tuple(v * 0.85 for v in base), edge_mix=0.3)
            if qi == 1 and qj == 1:
                gx, gy = ccx + q * 0.12, ccy - q * 0.05
                cv.stroke([(gx, gy), (gx + 8, gy + 90), (gx + 12, gy + 170)], [1.8, 1.5, 1.2], [(0.40, 0.42, 0.22)] * 3, rough=0.7)
                for i in range(30):
                    t = i / 29
                    bx = gx + 8 * t + 12 * t * t + rng.uniform(-10, 10)
                    by = gy + 20 + 150 * t + rng.uniform(-4, 4)
                    berry = (0.42, 0.52, 0.22) if rng.random() < 0.7 else (0.36, 0.12, 0.26)
                    cv.leaf(bx - 5, by, 1, 0, 10, 5, _jit(rng, berry), profile="round", fold=0.5, rough=0.4)
    return cv.result(tile=1.6)


@kit("PoincianaLeaves", 1024, 1024, alpha=True, rnd=3)
def poinciana_leaves(n, x, y, w, h):
    # royal poinciana: feathery twice-divided leaves (pinnae of tiny leaflets along each stalk)
    # and clusters of scarlet flowers with one white, red-flecked petal; two quadrants in full
    # bloom, one half, one in leaf
    rng = n.rng
    cv = Canvas(w, h, rough=0.65)
    field = n.fbm(x, y, 90, 2)
    q = w // 2
    blooms = [9, 8, 4, 0]
    for qi in range(2):
        for qj in range(2):
            ox, oy = qi * q, qj * q
            ccx, ccy = ox + q / 2, oy + q * 0.48
            k = qi * 2 + qj
            _twigs(cv, rng, ox, oy, q, 6, color=(0.36, 0.32, 0.26), width=2.2)
            for _ in range(11):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.22 * math.sqrt(rng.random())
                sx, sy = ccx + r * math.cos(a), ccy + r * math.sin(a)
                la = a + rng.uniform(-0.6, 0.6)
                L = rng.uniform(0.28, 0.4) * q
                dx, dy = math.cos(la), math.sin(la)
                cv.stroke([(sx, sy), (sx + dx * L, sy + dy * L)], [1.5, 0.8], [(0.30, 0.42, 0.14)] * 2, rough=0.7)
                pairs = 9
                for p in range(pairs):
                    t = 0.12 + 0.85 * p / pairs
                    px, py = sx + dx * L * t, sy + dy * L * t
                    pl = L * 0.42 * (1 - 0.45 * abs(t - 0.45))
                    g = rng.uniform(0.82, 1.12)
                    for side in (-1, 1):
                        pa = la + side * math.radians(rng.uniform(55, 75))
                        cv.leaf(px, py, math.cos(pa), math.sin(pa), pl, 5.0, (0.20 * g, 0.42 * g, 0.11 * g), profile="lance", fold=0.5, comb=0.3, comb_period=4.5, rough=0.62)
            for _ in range(blooms[k]):
                a = rng.uniform(0, 2 * math.pi)
                r = q * 0.34 * math.sqrt(rng.random())
                fx0, fy0 = ccx + r * math.cos(a), ccy + r * math.sin(a)
                for _ in range(rng.integers(5, 10)):
                    fx, fy = fx0 + rng.uniform(-34, 34), fy0 + rng.uniform(-30, 30)
                    tone = (0.90, 0.16, 0.05) if rng.random() < 0.7 else (0.95, 0.36, 0.06)
                    pl = rng.uniform(22, 30)
                    spin = rng.uniform(0, 2 * math.pi)
                    for j in range(5):
                        pa = spin + j * 2 * math.pi / 5
                        if j == 0:
                            cv.leaf(fx, fy, math.cos(pa), math.sin(pa), pl * 1.15, pl * 0.5, (0.97, 0.90, 0.72), profile="obovate", fold=0.4, spot=((0.85, 0.12, 0.08), 0.15), field=field, rough=0.7)
                        else:
                            cv.leaf(fx, fy, math.cos(pa), math.sin(pa), pl, pl * 0.5, _jit(rng, tone, 0.06), profile="obovate", fold=0.4, vein=tuple(min(1.0, v * 1.2) for v in tone), vein_mix=0.25, rough=0.68, edge=tuple(v * 0.85 for v in tone), edge_mix=0.3)
                    for j in range(4):
                        sa = rng.uniform(0, 2 * math.pi)
                        cv.stroke([(fx, fy), (fx + math.cos(sa) * pl * 1.1, fy + math.sin(sa) * pl * 1.1)], [0.7, 0.5], [(0.85, 0.14, 0.06)] * 2, rough=0.7)
    return cv.result(tile=1.4)


@kit("FernFrond", 256, 1024, alpha=True, rnd=3)
def fern_frond(n, x, y, w, h):
    # a sword (Boston) fern frond: the stalk up the middle (base at the bottom), ~45 oblong pinnae
    # a side, longest a little below the middle, lighter toward the young tip
    rng = n.rng
    cv = Canvas(w, h, rough=0.6)
    cx = w / 2
    cv.stroke([(cx, h - 2), (cx, h * 0.5), (cx, 4)], [2.4, 1.6, 0.6], [(0.36, 0.30, 0.16), (0.30, 0.42, 0.14), (0.40, 0.56, 0.20)], rough=0.6)
    pinnae = 46
    for side in (-1, 1):
        for k in range(pinnae):
            t = 0.05 + 0.93 * (k + rng.uniform(-0.2, 0.2)) / pinnae
            py = h * (1 - t)
            L = (w * 0.46) * (math.sin(math.pi * min(1.0, t * 0.9 + 0.1)) ** 0.55) * rng.uniform(0.9, 1.05)
            ang = math.radians(rng.uniform(62, 76))
            g = rng.uniform(0.85, 1.1)
            young = max(0.0, (t - 0.75) / 0.25)
            c = (0.20 * g + 0.12 * young, 0.44 * g + 0.10 * young, 0.12 * g + 0.04 * young)
            cv.leaf(cx + side * 1.5, py, side * math.sin(ang), -math.cos(ang), L, max(3.0, L * 0.2), c, profile="ovate", fold=0.9, vein=(0.30, 0.52, 0.18), vein_mix=0.3, serrate=0.6, teeth=4.0, rough=0.55)
    return cv.result(tile=0.9)


@kit("GrassBlades", 512, 512, alpha=True, rnd=3)
def grass_blades(n, x, y, w, h):
    # purple fountain grass: a clump of arching burgundy blades from the base (bottom middle)
    # and soft pinkish bottlebrush plumes nodding over it
    rng = n.rng
    cv = Canvas(w, h, rough=0.7)
    field = n.fbm(x, y, 70, 3)
    bx, by = w / 2, h - 4
    for _ in range(170):
        a = math.radians(rng.uniform(-62, 62))
        L = rng.uniform(0.45, 0.9) * h
        bend = rng.uniform(0.25, 0.7) * (1 if a >= 0 else -1)
        pts, widths, colors = [], [], []
        g = rng.uniform(0.8, 1.15)
        base = (0.30 * g, 0.12 * g, 0.12 * g) if rng.random() < 0.8 else (0.40 * g, 0.22 * g, 0.16 * g)
        tip = (min(1.0, base[0] * 1.35), base[1] * 1.2, base[2] * 1.1)
        x0 = bx + rng.uniform(-22, 22)
        for i in range(9):
            t = i / 8
            ang = a + bend * t * t * 1.6
            px = x0 + math.sin(a) * L * t * 0.4 + math.sin(ang) * L * t * 0.6
            py = by - math.cos(a) * L * t * 0.4 - math.cos(ang) * L * t * 0.6 + (L * 0.25 * t * t if abs(ang) > 1.0 else 0)
            pts.append((px, py))
            widths.append(2.6 * (1 - t) + 0.4)
            colors.append(tuple(base[j] + (tip[j] - base[j]) * t for j in range(3)))
        cv.stroke(pts, widths, colors, rough=0.65, fold=0.5)
    for _ in range(26):
        a = math.radians(rng.uniform(-50, 50))
        L = rng.uniform(0.55, 0.88) * h
        bend = rng.uniform(0.4, 0.9) * (1 if a >= 0 else -1)
        x0 = bx + rng.uniform(-14, 14)
        pts = []
        for i in range(9):
            t = i / 8
            ang = a + bend * t * t
            pts.append((x0 + math.sin(ang) * L * t, by - math.cos(ang) * L * t))
        cv.stroke(pts[:6], [1.2] * 6, [(0.42, 0.24, 0.20)] * 6, rough=0.7)
        cv.plume(pts[4:], rng.uniform(9, 13), _jit(rng, (0.72, 0.50, 0.48), 0.08), field)
    return cv.result(tile=1.1)


@kit("SabalFrond", 1024, 512, alpha=True, rnd=3)
def sabal_frond(n, x, y, w, h):
    # a cabbage palm's fan leaf seen flat: deep-green pleated segments fanning from the stalk's
    # end (bottom middle), fused for half their length then free and split at the tip, the midrib
    # (costa) running up into it, pale threads hanging between segments, a few tips gone brown
    rng = n.rng
    cv = Canvas(w, h, rough=0.55)
    hx, hy = w / 2, h - 10
    R = h * 0.95
    segments = 52
    for k in range(segments):
        th = math.radians(-102 + 204 * (k + 0.5) / segments + rng.uniform(-1.2, 1.2))
        ax, ay = math.sin(th), -math.cos(th)
        L = R * rng.uniform(0.82, 1.0) * (0.9 + 0.1 * math.cos(th))
        width = R * 0.6 * math.radians(204 / segments) / 2 * 1.25
        g = rng.uniform(0.82, 1.12)
        c = (0.14 * g, 0.29 * g, 0.10 * g) if rng.random() > 0.1 else (0.22 * g, 0.34 * g, 0.12 * g)
        cv.leaf(hx, hy, ax, ay, L, width, c, profile="wedge", fold=1.4, vein=(0.30, 0.42, 0.16), vein_mix=0.35, rough=0.5, split=0.16, tip_dry=0.18 if rng.random() < 0.2 else 0.0, shade=0.3)
    for k in range(segments - 1):
        th = math.radians(-102 + 204 * (k + 1) / segments)
        r0 = R * rng.uniform(0.55, 0.7)
        sx, sy = hx + math.sin(th) * r0, hy - math.cos(th) * r0
        L = rng.uniform(30, 60)
        if rng.random() < 0.6:
            cv.stroke([(sx, sy), (sx + math.sin(th) * L * 0.7, sy - math.cos(th) * L * 0.7 + L * 0.4)], [0.7, 0.4], [(0.78, 0.74, 0.60)] * 2, rough=0.8, fold=0.1)
    cv.stroke([(hx, hy + 8), (hx, hy - R * 0.25), (hx, hy - R * 0.55)], [5.0, 3.0, 1.0], [(0.52, 0.52, 0.24), (0.42, 0.46, 0.20), (0.30, 0.40, 0.16)], rough=0.5, fold=0.8)
    return cv.result(tile=1.6)


@kit("DateFrond", 512, 1024, alpha=True, rnd=3)
def date_frond(n, x, y, w, h):
    # a Canary date palm frond seen flat: a broad stalk up the middle (base at the bottom), ~110
    # stiff, narrow leaflets a side set steeply in a V, sharp spines in place of leaflets low down
    rng = n.rng
    cv = Canvas(w, h, rough=0.5)
    cx = w / 2
    cv.stroke([(cx, h - 2), (cx, h * 0.5), (cx, 6)], [7.0, 4.0, 1.2], [(0.62, 0.60, 0.34), (0.50, 0.54, 0.28), (0.36, 0.46, 0.20)], rough=0.5, fold=1.2)
    for side in (-1, 1):
        for k in range(22):
            t = 0.02 + 0.13 * k / 22
            py = h * (1 - t)
            ang = math.radians(rng.uniform(18, 30))
            cv.leaf(cx + side * 5, py, side * math.sin(ang), -math.cos(ang), rng.uniform(26, 46), 1.6, (0.74, 0.68, 0.40), profile="lance", fold=0.4, rough=0.5)
        for k in range(130):
            t = 0.15 + 0.83 * (k + rng.uniform(-0.3, 0.3)) / 130
            py = h * (1 - t)
            L = (w * 0.47) * (math.sin(math.pi * min(1.0, (t - 0.15) / 0.85 * 0.85 + 0.15)) ** 0.5) * rng.uniform(0.88, 1.04)
            ang = math.radians(rng.uniform(28, 42) - 8 * t)
            g = rng.uniform(0.85, 1.1)
            c = (0.22 * g, 0.36 * g, 0.16 * g) if rng.random() > 0.2 else (0.30 * g, 0.38 * g, 0.24 * g)
            cv.leaf(cx + side * (4 * (1 - t) + 1), py, side * math.sin(ang), -math.cos(ang), L, rng.uniform(4.6, 6.2), c, profile="lance", fold=1.1, vein=(0.40, 0.50, 0.26), vein_mix=0.4, rough=0.45, tip_dry=0.1 if rng.random() < 0.15 else 0.0)
    return cv.result(tile=5.0, height_scale=0.0012)


@kit("SabalTrunk", 512, 512, tile=(1.0, 1.0), rnd=3)
def sabal_trunk(n, x, y, w, h):
    # cabbage palm "boots": the split bases of old leaf stalks, wide and crossing in a diagonal
    # lattice with narrow dark slits between, some broken off to a deeper hollow, fibre over them
    # (the tile wraps twice round the trunk; 1 m tall)
    N, M = 4, 6
    u, v = x * N, y * M
    wa_ = 0.16 * n.fbm(x, y, 5, 3)
    wb_ = 0.16 * n.fbm(x + 0.37, y + 0.21, 5, 3)
    sa = (u + v + wa_) % 1.0
    sb = (u - v + wb_) % 1.0
    # which boot (lattice cell) a pixel is on, for per-boot tone and broken boots
    ia = np.floor(u + v + wa_).astype(np.int64)
    ib = np.floor(u - v + wb_).astype(np.int64)
    cell = ((ia * 7919 + ib * 104729) % 9973).astype(F) / 9973.0
    wa = smoothstep(0.5, 0.36, np.abs(sa - 0.5) * (1 + 0.3 * n.fbm(x, y, 24, 2)))
    wb = smoothstep(0.5, 0.36, np.abs(sb - 0.5) * (1 + 0.3 * n.fbm(x + 0.5, y, 24, 2)))
    boot = np.minimum(wa, wb)
    broken = (cell < 0.18).astype(F) * smoothstep(0.25, 0.1, np.maximum(np.abs(sa - 0.5), np.abs(sb - 0.5)))
    surface = boot * (1 - broken * 0.85)
    # each boot's upper edge catches the light, its underside falls into shadow
    lit = smoothstep(0.0, 0.5, (sa - 0.5) + (0.5 - sb)) * surface
    fibre = n.fbm(x, y, 64, 3, cy=16)
    tone = 0.85 + 0.3 * cell
    lum = 0.06 + (0.26 * tone + 0.06 * lit) * surface + 0.04 * fibre * surface + 0.03 * n.fbm(x, y, 3, 3)
    color = lum[..., None] * col(1.0, 0.86, 0.68)
    grey = smoothstep(0.2, 0.6, n.fbm(x + 0.7, y, 4, 3))[..., None]
    color = lerp(color, lum[..., None] * col(0.92, 0.9, 0.86), grey * 0.5)
    height = 0.03 * surface + 0.006 * lit + 0.0025 * fibre * surface
    return {"color": color, "height": height, "rough": 0.92 - 0.06 * surface, "tile": 1.0}


@kit("DateTrunk", 512, 512, tile=(1.0, 1.0), rnd=3)
def date_trunk(n, x, y, w, h):
    # Canary date palm: a clean trunk of diamond-shaped leaf scars, wider than tall, each pad its
    # own tan, dark fibrous grooves between, a ridge across each (wraps twice round; 1 m tall)
    N, M = 10, 11
    u, v = x * N, y * M
    wa_ = 0.14 * n.fbm(x, y, 6, 3)
    wb_ = 0.14 * n.fbm(x + 0.4, y, 6, 3)
    sa = (u + v + wa_) % 1.0
    sb = (u - v + wb_) % 1.0
    ia = np.floor(u + v + wa_).astype(np.int64)
    ib = np.floor(u - v + wb_).astype(np.int64)
    cell = ((ia * 7919 + ib * 104729) % 9973).astype(F) / 9973.0
    edge = np.minimum(np.minimum(sa, 1 - sa), np.minimum(sb, 1 - sb))
    pad = smoothstep(0.03, 0.2, edge * (1 + 0.4 * n.fbm(x, y, 30, 2)))
    cell_v = ((sa + sb) / 2) % 1.0
    ridge = smoothstep(0.07, 0.0, np.abs(cell_v - 0.5)) * pad
    fibre = n.fbm(x, y, 60, 3, cy=12)
    lum = 0.16 + (0.26 + 0.12 * cell) * pad + 0.07 * ridge + 0.05 * fibre + 0.05 * n.fbm(x, y, 3, 3)
    color = lum[..., None] * col(1.0, 0.84, 0.64)
    # grime and a little lichen in the grooves
    groove = (1 - pad)[..., None]
    color = lerp(color, color * col(0.8, 0.86, 0.72), groove * smoothstep(0.1, 0.5, n.fbm(x + 0.2, y, 5, 3))[..., None])
    height = 0.012 * pad + 0.003 * ridge + 0.0008 * fibre
    return {"color": color, "height": height, "rough": 0.9 - 0.04 * pad, "tile": 1.0}


@kit("AgaveLeaf", 256, 512, tile=(1.0, 1.0), rnd=3)
def agave_leaf(n, x, y, w, h):
    # a century plant's leaf, flat: across (the edges at left and right) waxy blue-grey with fine
    # lengthwise striations and the cream-yellow margin of the variegated form, faint imprints of
    # the leaf it grew against, the tip (top) darkening to its spine
    edge = np.minimum(x, 1 - x)
    margin = smoothstep(0.08, 0.05, edge)
    stri = n.fbm(x, y, 40, 3, cy=2)
    lum = 1 + 0.06 * stri + 0.05 * n.fbm(x, y, 4, 3)
    color = col(0.40, 0.54, 0.55) * lum[..., None]
    imprint = smoothstep(0.55, 0.75, np.abs(np.sin(2 * math.pi * (y * 3 + 0.2 * n.fbm(x, y, 2, 2)))) * (0.5 + 0.5 * n.fbm(x, y, 3, 2)))
    color = color * (1 - 0.06 * imprint[..., None])
    color = lerp(color, col(0.86, 0.80, 0.46) * np.ones_like(color), margin[..., None])
    color = lerp(color, col(0.30, 0.22, 0.14) * np.ones_like(color), smoothstep(0.08, 0.0, y)[..., None])
    height = 0.0006 * stri - 0.0012 * margin
    return {"color": color, "height": height, "rough": 0.55 - 0.08 * margin, "tile": 1.0}


# ---------------------------------------------------------------------------- output


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "manifest.json")
    manifest = {"Materials": []}
    if os.path.exists(path):
        with open(path) as f:
            manifest = json.load(f)
    only = set(sys.argv[1].split(",")) if len(sys.argv) > 1 and sys.argv[1] else None
    previous = {e["Name"]: e for e in manifest.get("Kits", [])}
    entries = []
    for spec in KITS:
        name = spec["Name"]
        if only is not None and name not in only and name in previous:
            # (not asked for: keep what an earlier run made, with this run's round)
            entry = dict(previous[name])
            entry["Round"] = spec["Round"]
            entries.append(entry)
            continue
        x, y = grid(spec["W"], spec["H"])
        n = T.Noise(zlib.crc32(name.encode()) % 100000)
        raw = spec["Fn"](n, x, y, spec["W"], spec["H"])
        color = np.clip(np.asarray(raw["color"], F), 0, 1)
        tile_m = raw.get("tile", 1.0)
        height = np.asarray(raw["height"], F) * np.ones((spec["H"], spec["W"]), F)
        # (pixels are taken as square, `tile` metres to the image's height)
        normal = T.normal_map(height, tile_m, 1.0)
        rough = np.clip(np.asarray(raw["rough"], F) * np.ones((spec["H"], spec["W"]), F), 0.02, 1)
        maps = {}
        if spec["Alpha"]:
            # bleed the leaf colour into the cut-away pixels so filtering doesn't fringe dark
            a = color[..., 3:4]
            fill = T.blur(color[..., :3] * a, 6) / np.maximum(T.blur(a, 6), 1e-3)
            color = np.concatenate([np.where(a > 0.01, color[..., :3] / np.maximum(a, 1e-3) * np.minimum(a * 4, 1) + fill * (1 - np.minimum(a * 4, 1)), fill), a], -1)
            T.save_image(os.path.join(OUT, f"{name}_Color.png"), np.clip(color, 0, 1))
            maps["Color"] = f"{name}_Color.png"
        else:
            T.save_image(os.path.join(OUT, f"{name}_Color.jpg"), color, quality=92)
            maps["Color"] = f"{name}_Color.jpg"
        T.save_image(os.path.join(OUT, f"{name}_Normal.jpg"), normal, quality=95)
        maps["Normal"] = f"{name}_Normal.jpg"
        T.save_image(os.path.join(OUT, f"{name}_Roughness.jpg"), rough, quality=90)
        maps["Roughness"] = f"{name}_Roughness.jpg"
        entries.append({"Name": name, "Alpha": spec["Alpha"], "W": spec["W"], "H": spec["H"], "Maps": maps, "Round": spec["Round"]})
        print(f"{name:<20} {spec['W']}x{spec['H']}  alpha {spec['Alpha']}  round {spec['Round']}")
    manifest["Kits"] = entries
    with open(path, "w") as f:
        json.dump(manifest, f, indent=1)
    print("wrote", path)


if __name__ == "__main__":
    main()
