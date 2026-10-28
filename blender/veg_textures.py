"""
Textures for the vegetation kits (blender/vegetation.py): bark for the trunks and alpha-cut cards
for the foliage, in their real colours (a SurfaceAppearance isn't tinted by its part's colour).
Written to blender/out/textures/<Name>_<Map>.(png|jpg), listed under "Kits" in manifest.json.

  /root/tools/blendenv/bin/python blender/veg_textures.py

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


def kit(name, width, height, alpha=False, tile=(1.0, 1.0)):
    def wrap(fn):
        KITS.append({"Name": name, "W": width, "H": height, "Alpha": alpha, "Tile": tile, "Fn": fn})
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


# ---------------------------------------------------------------------------- output


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "manifest.json")
    manifest = {"Materials": []}
    if os.path.exists(path):
        with open(path) as f:
            manifest = json.load(f)
    entries = []
    for spec in KITS:
        x, y = grid(spec["W"], spec["H"])
        n = T.Noise(zlib.crc32(spec["Name"].encode()) % 100000)
        raw = spec["Fn"](n, x, y, spec["W"], spec["H"])
        color = np.clip(np.asarray(raw["color"], F), 0, 1)
        tile_m = raw.get("tile", 1.0)
        height = np.asarray(raw["height"], F) * np.ones((spec["H"], spec["W"]), F)
        # (pixels are taken as square, `tile` metres to the image's height)
        normal = T.normal_map(height, tile_m, 1.0)
        rough = np.clip(np.asarray(raw["rough"], F) * np.ones((spec["H"], spec["W"]), F), 0.02, 1)
        maps = {}
        name = spec["Name"]
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
        entries.append({"Name": name, "Alpha": spec["Alpha"], "W": spec["W"], "H": spec["H"], "Maps": maps})
        print(f"{name:<12} {spec['W']}x{spec['H']}  alpha {spec['Alpha']}")
    manifest["Kits"] = entries
    with open(path, "w") as f:
        json.dump(manifest, f, indent=1)
    print("wrote", path)


if __name__ == "__main__":
    main()
