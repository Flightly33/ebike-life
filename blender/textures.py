"""
The PBR material library: tileable colour, normal (OpenGL), roughness and metalness maps for the
Roblox base materials the city uses, generated procedurally at real-world scale. They become
MaterialVariants that override those materials everywhere (src/shared/Materials.luau), after the
owner imports blender/out/Realism.fbx in Studio (see blender/realism_pack.py).

  /root/tools/blendenv/bin/python blender/textures.py [Name,Name...]

Writes blender/out/textures/<Name>_<Map>.jpg and manifest.json. Colour maps are near-neutral
"detail" maps: Roblox multiplies a MaterialVariant's colour map by each part's Color, so the
builders' colours still decide hue and brightness (calibrated against `tint`, the material's
typical part colour, which the previews use). Each material's tile covers `tile` metres.
Directional materials (roof tiles, shingles, planks) also get a turned copy ("<Name>90").
"""

import json
import math
import os
import sys
import time
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import texlib as T  # noqa: E402
from texlib import F, lerp, smoothstep  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "textures")

MATERIALS = []


def material(name, base, tile, pattern, tint, size=1024, directional=False, metal=None, seed=None, livery=False, named=False, rnd=1):
    """Register a generator: it returns colour (H, W, 3), height (m), roughness and optionally
    metalness (H, W) or a constant via `metal`. Livery patterns (Shared/Livery: carbon, camo...)
    are painted on bikes by name and never override their base material. Named facade materials
    (`named`: a second stucco, old brick...) are city-scale variants the builders give some walls
    by name (BasePart.MaterialVariant), so a street isn't all one texture; they never override
    their base material either."""

    def wrap(fn):
        MATERIALS.append({"Name": name, "Base": base, "Tile": tile, "Pattern": pattern, "Tint": tint, "Size": size, "Directional": directional, "Metal": metal, "Seed": seed or (zlib.crc32(name.encode()) % 100000), "Livery": livery, "Named": named, "Round": rnd, "Fn": fn})
        return fn

    return wrap


def rgb(r, g, b):
    return np.array([r, g, b], F)


def gray(v):
    return np.repeat(np.asarray(v, F)[..., None], 3, axis=-1)


def tinted(lum, tint):
    """A luminance map times a (relative) colour."""
    return np.asarray(lum, F)[..., None] * np.asarray(tint, F)


# ---------------------------------------------------------------------------- roads & paving


@material("Asphalt", "Asphalt", 2.0, "Organic", (72, 74, 78))
def asphalt(n, x, y, S, tile):
    # dense-graded asphalt, a few years old: angular stones worn almost flush with a darker
    # matrix of sand and binder, voids, hairline cracks, a tar-sealed seam, oil and tyre polish
    mott = n.fbm(x, y, 3, 5)
    wear = smoothstep(-0.2, 0.5, n.fbm(x, y, 2, 4))
    matrix = n.fbm(x, y, 300, 2)
    lum = 0.31 + 0.035 * mott + 0.035 * matrix + 0.04 * wear
    height = 0.00018 * matrix
    rough = 0.9 - 0.03 * mott
    # stones: irregular (warped cells), flat-topped, mostly flush
    for cells, r, prot, lo, hi, dens in ((60, 0.40, 0.0007, 0.42, 0.66, 0.42), (130, 0.38, 0.0005, 0.4, 0.7, 0.45), (280, 0.36, 0.0003, 0.38, 0.62, 0.5)):
        wx = x + (0.32 / cells) * n.perlin(x, y, cells * 2)
        wy = y + (0.32 / cells) * n.perlin(x + 0.5, y + 0.5, cells * 2)
        f1, _, ids = n.worley(wx, wy, cells, jitter=0.95)
        keep = n.per_cell(cells * cells)[ids] < dens * (0.8 + 0.4 * wear)
        m = smoothstep(r, r * 0.82, f1) * keep
        tone = n.per_cell(cells * cells, lo, hi)[ids] + 0.03 * n.perlin(x, y, cells * 4)
        lum = lerp(lum, tone, m)
        height = height + m * prot
        rough = lerp(rough, 0.74, m)
    # voids between the stones
    f1, _, ids = n.worley(x, y, 240, jitter=0.9)
    pit = smoothstep(0.14, 0.07, f1) * (n.per_cell(240 * 240)[ids] < 0.3)
    height = height - pit * 0.0009
    lum = lum * (1 - 0.4 * pit)
    # hairline cracks: a warped cell net, only in places
    wx = x + 0.035 * n.fbm(x, y, 6, 3)
    wy = y + 0.035 * n.fbm(x + 0.37, y + 0.71, 6, 3)
    f1, f2, _ = n.worley(wx, wy, 5, jitter=1.0)
    edge = (f2 - f1) * (tile / 5)  # metres from the crack line
    width = 0.0016 + 0.0014 * (0.5 + 0.5 * n.fbm(x, y, 20, 2))
    crack = smoothstep(width, width * 0.3, edge) * smoothstep(0.05, 0.3, n.fbm(x, y, 3, 3))
    height = height - crack * 0.0012
    lum = lum * (1 - 0.75 * crack)
    rough = lerp(rough, 0.97, crack)
    # tar snakes: glossy sealant poured along old cracks
    f1, f2, _ = n.worley(x + 0.02 * n.fbm(x, y, 8, 3), y, 3, jitter=1.0)
    edge = (f2 - f1) * (tile / 3)
    tar = smoothstep(0.013, 0.007, edge) * smoothstep(0.2, 0.45, n.fbm(x + 0.5, y + 0.2, 2, 3))
    lum = lerp(lum, 0.15, tar)
    rough = lerp(rough, 0.48, tar)
    height = height + tar * 0.0006
    # oil drips and tyre polish
    stain = smoothstep(0.35, 0.7, n.fbm(x, y, 7, 4)) * 0.6
    lum = lum * (1 - 0.2 * stain)
    rough = rough - 0.12 * stain
    return {"color": gray(lum), "height": height, "rough": rough}


@material("Pavement", "Pavement", 3.0, "Regular", (178, 175, 170))
def pavement(n, x, y, S, tile):
    slabs = 2  # 1.5 m slabs
    sx, sy = np.floor(x * slabs), np.floor(y * slabs)
    sid = (sy * slabs + sx).astype(np.int64)
    side = tile / slabs
    lx, ly = (x * slabs % 1) * side, (y * slabs % 1) * side
    d = np.minimum(np.minimum(lx, side - lx), np.minimum(ly, side - ly))
    joint = smoothstep(0.004, 0.0012, d)
    near = smoothstep(0.035, 0.004, d)
    lum = 0.8 + n.per_cell(slabs * slabs, -0.05, 0.05)[sid]
    lum = lum + 0.045 * n.fbm(x, y, 5, 5) + 0.02 * n.fbm(x, y, 40, 3)
    broom = n.perlin(x, y, 3, 420) * 0.6 + n.perlin(x, y, 5, 900) * 0.4
    lum = lum + 0.012 * broom
    height = 0.00025 * broom + 0.0002 * n.fbm(x, y, 200, 2)
    # aggregate speckle and pores
    f1, _, ids = n.worley(x, y, 520, jitter=0.9)
    speck = smoothstep(0.3, 0.15, f1)
    lum = lum + speck * n.per_cell(520 * 520, -0.08, 0.06)[ids]
    f1, _, ids = n.worley(x, y, 300, jitter=0.9)
    pore = smoothstep(0.13, 0.06, f1) * (n.per_cell(300 * 300)[ids] < 0.3)
    lum = lum * (1 - 0.4 * pore)
    height = height - 0.0008 * pore
    # dirt along the joints, stains, chewing gum
    lum = lum * (1 - 0.12 * near) * (1 - 0.06 * smoothstep(0.3, 0.75, n.fbm(x, y, 4, 4)))
    gx = x + 0.004 * n.perlin(x, y, 120)
    f1, _, ids = n.worley(gx, y, 11, jitter=0.9)
    gr = n.per_cell(121, 0.022, 0.04)[ids]
    gum = smoothstep(gr, gr * 0.7, f1) * (n.per_cell(121)[ids] < 0.12)
    lum = lerp(lum, 0.5, gum)
    lum = lum * (1 - 0.55 * joint)
    height = height - joint * 0.008 + gum * 0.0005
    rough = 0.86 + 0.03 * n.fbm(x, y, 9, 3)
    rough = lerp(rough, 0.95, joint)
    rough = lerp(rough, 0.72, gum)
    return {"color": gray(lum), "height": height, "rough": rough}


@material("Concrete", "Concrete", 4.0, "Organic", (214, 210, 200))
def concrete(n, x, y, S, tile):
    lum = 0.82 + 0.07 * n.fbm(x, y, 4, 6) + 0.03 * n.fbm(x, y, 40, 3) + 0.02 * n.fbm(x, y, 256, 2)
    height = 0.0003 * n.fbm(x, y, 256, 2) + 0.0006 * n.fbm(x, y, 24, 3)
    # bugholes (air pockets in the cast face)
    f1, _, ids = n.worley(x, y, 170, jitter=0.95)
    hole = smoothstep(0.19, 0.09, f1) * (n.per_cell(170 * 170)[ids] < 0.28)
    height = height - hole * 0.0022
    lum = lum * (1 - 0.5 * hole)
    # efflorescence and grime
    lum = lum + 0.05 * smoothstep(0.35, 0.7, n.fbm(x, y, 3, 4)) - 0.05 * smoothstep(0.4, 0.8, n.fbm(x + 0.3, y, 5, 4))
    rough = 0.82 + 0.05 * n.fbm(x, y, 7, 3) + 0.08 * hole
    return {"color": gray(lum), "height": height, "rough": rough}


@material("Cobblestone", "Cobblestone", 1.0, "Regular", (196, 180, 160))
def cobblestone(n, x, y, S, tile):
    # granite setts, 10 cm, laid in courses offset by half a sett
    rows = 10
    row = np.floor(y * rows)
    off = (row % 2) * 0.5 + n.per_cell(rows, -0.15, 0.15)[(row % rows).astype(np.int64)]
    cx = x * rows + off
    col = np.floor(cx)
    sid = ((row % rows) * rows + (col % rows)).astype(np.int64)
    lx, ly = (cx % 1 - 0.5) * 0.1, (y * rows % 1 - 0.5) * 0.1
    half = 0.044 + n.per_cell(rows * rows, -0.004, 0.003)[sid]
    corner = 0.012
    qx, qy = np.maximum(np.abs(lx) - (half - corner), 0), np.maximum(np.abs(ly) - (half - corner), 0)
    dist = np.hypot(qx, qy) - corner  # <0 inside the stone
    stone = smoothstep(0.001, -0.002, dist)
    dome = np.clip(-dist / half, 0, 1) ** 0.5
    height = stone * (0.004 + 0.006 * dome) + 0.0006 * n.fbm(x, y, 60, 3) * stone
    lum = lerp(0.95, 0.72 + n.per_cell(rows * rows, -0.12, 0.12)[sid] + 0.05 * n.fbm(x, y, 40, 3), stone)
    hue = np.stack([1 + n.per_cell(rows * rows, -0.04, 0.05)[sid], np.ones_like(x), 1 + n.per_cell(rows * rows, -0.05, 0.04)[sid]], -1)
    color = tinted(lum, (1, 1, 1)) * lerp(np.ones_like(hue), hue, stone[..., None])
    rough = lerp(0.95, 0.72 - 0.1 * dome, stone)
    return {"color": color, "height": height, "rough": rough}


# ---------------------------------------------------------------------------- walls & roofs


@material("Plaster", "Plaster", 1.0, "Organic", (250, 250, 246))
def plaster(n, x, y, S, tile):
    f1, _, _ = n.worley(x, y, 230, jitter=1.0)
    grains = (1 - np.clip(f1, 0, 1)) ** 2
    height = 0.0006 * grains + 0.0003 * n.fbm(x, y, 128, 3) + 0.0009 * n.fbm(x, y, 5, 4)
    lum = 0.92 + 0.012 * n.fbm(x, y, 8, 4) + 0.02 * (grains - 0.4)
    lum = lum - 0.045 * smoothstep(0.45, 0.85, n.fbm(x, y, 3, 4))
    rough = 0.9 + 0.03 * n.fbm(x, y, 20, 2)
    return {"color": gray(lum), "height": height, "rough": rough}


@material("Brick", "Brick", 1.125, "Regular", (150, 80, 60))
def brick(n, x, y, S, tile):
    courses, per = 15, 5
    row = np.floor(y * courses)
    bx = x * per + (row % 2) * 0.5
    bi = np.floor(bx) % per
    bid = ((row % courses) * per + bi).astype(np.int64)
    lx = (bx % 1) * 0.225
    ly = (y * courses % 1) * 0.075
    d = np.minimum(np.minimum(lx - 0.005, 0.22 - lx), np.minimum(ly - 0.005, 0.07 - ly))
    body = smoothstep(-0.0005, 0.003, d)
    lum = lerp(1.0, 0.72 + n.per_cell(courses * per, -0.13, 0.13)[bid] + 0.04 * n.fbm(x, y, 30, 3), body)
    hue = np.stack([1 + n.per_cell(courses * per, -0.03, 0.08)[bid], 1 + n.per_cell(courses * per, -0.08, 0.02)[bid], 1 + n.per_cell(courses * per, -0.1, 0.0)[bid]], -1)
    color = tinted(lum, (1, 1, 1)) * lerp(np.ones_like(hue), hue, body[..., None])
    height = body * (0.005 + 0.0006 * n.fbm(x, y, 90, 3)) + (1 - body) * 0.0004 * n.fbm(x, y, 200, 2)
    rough = lerp(0.93, 0.84, body)
    return {"color": color, "height": height, "rough": rough}


@material("ClayRoofTiles", "ClayRoofTiles", 1.0, "Regular", (176, 84, 52), directional=True)
def clay_roof_tiles(n, x, y, S, tile):
    # Mission barrel tiles: caps and pans in a 25 cm wave, 4 across a metre; 3 courses of 33 cm
    # down the slope (down the image), each course's rounded lower ends lapping the one below
    cols, courses = 4, 3
    course = np.floor(y * courses)
    jitter = n.per_cell(courses, -0.05, 0.05)[(course % courses).astype(np.int64)]
    phase = x * cols + jitter
    wave = 0.5 - 0.5 * np.cos(2 * math.pi * phase)  # 1 on the caps, 0 in the pans
    # the lap line dips where each cap tile's rounded end hangs over the course below
    lap = y * courses + 0.12 * wave
    course = np.floor(lap)
    ly = lap % 1
    tid = ((course % courses) * cols + np.floor(phase) % cols).astype(np.int64)
    height = 0.06 * wave + 0.018 * ly + 0.0006 * n.fbm(x, y, 40, 3)
    lum = 0.84 + n.per_cell(courses * cols, -0.13, 0.1)[tid] + 0.03 * n.fbm(x, y, 20, 3)
    # baked occlusion: pans darker than caps, a shadow under each lapping end
    lum = lum * (0.72 + 0.28 * wave) * (1 - 0.45 * smoothstep(0.1, 0.0, ly))
    weather = smoothstep(0.2, 0.7, n.fbm(x + 0.2, y, 3, 4))
    hue = np.stack([1 + n.per_cell(courses * cols, 0.0, 0.07)[tid], 1 - n.per_cell(courses * cols, 0.0, 0.06)[tid], np.ones_like(x)], -1)
    color = tinted(lum, (1, 1, 1)) * hue
    color = lerp(color, color * np.array([0.9, 0.95, 0.92], F), weather[..., None] * 0.6)
    rough = 0.7 + 0.06 * n.fbm(x, y, 12, 3) + 0.06 * weather
    return {"color": color, "height": height, "rough": rough}


@material("RoofShingles", "RoofShingles", 1.2, "Regular", (110, 112, 118), size=512, directional=True)
def roof_shingles(n, x, y, S, tile):
    # laminated asphalt shingles: 9 courses (13 cm exposure), tabs of uneven width, granules
    courses, tabs = 9, 5
    course = np.floor(y * courses)
    ly = y * courses % 1
    c = (course % courses).astype(np.int64)
    tx = x * tabs + n.per_cell(courses)[c] * tabs
    local = tx % 1
    tid = ((c * 7 + np.floor(tx) % tabs) % 97).astype(np.int64)
    edge = np.minimum(local, 1 - local) * (tile / tabs)
    gap = smoothstep(0.005, 0.002, edge) * (ly > 0.35)
    lum = 0.78 + n.per_cell(97, -0.1, 0.1)[tid] + 0.07 * n.fbm(x, y, 260, 2)
    lum = lum * (1 - 0.4 * smoothstep(0.82, 1.0, ly)) * (1 - 0.6 * gap)
    height = 0.004 * ly + 0.0005 * n.fbm(x, y, 200, 2) - 0.002 * gap
    rough = 0.86 + 0.04 * n.fbm(x, y, 30, 2)
    return {"color": gray(lum), "height": height, "rough": rough}


@material("Limestone", "Limestone", 1.5, "Organic", (206, 200, 186), size=512)
def limestone(n, x, y, S, tile):
    lum = 0.88 + 0.04 * n.fbm(x, y, 5, 5) + 0.02 * n.fbm(x, y, 60, 3)
    f1, _, ids = n.worley(x, y, 90, jitter=1.0)
    pit = smoothstep(0.14, 0.05, f1) * (n.per_cell(8100)[ids] < 0.2)
    height = 0.0005 * n.fbm(x, y, 60, 3) - 0.0015 * pit
    lum = lum * (1 - 0.25 * pit)
    color = tinted(lum, (1.02, 1.0, 0.95))
    return {"color": color, "height": height, "rough": 0.8 + 0.04 * n.fbm(x, y, 10, 2)}


# ---------------------------------------------------------------------------- metal, wood, fabric


@material("Metal", "Metal", 1.0, "Regular", (120, 124, 128), size=512, metal=1.0)
def metal(n, x, y, S, tile):
    streak = 0.6 * n.perlin(x, y, 4, 500) + 0.4 * n.perlin(x, y, 9, 1100)
    smudge = smoothstep(0.2, 0.6, n.fbm(x, y, 5, 4))
    rng = n.rng
    xs, ys, w, _ = T.strokes(rng, S, 90, (20, 90), samples=24, taper=False)
    scratch, _ = T.splat(S, xs, ys, w)
    scratch = np.clip(T.blur(scratch, 0.5) * 1.2, 0, 1)
    lum = 0.84 + 0.04 * streak + 0.05 * scratch
    rough = 0.36 + 0.06 * streak + 0.14 * smudge - 0.1 * scratch
    height = 0.00004 * streak - 0.00008 * scratch
    return {"color": gray(lum), "height": height, "rough": rough}


@material("DiamondPlate", "DiamondPlate", 0.5, "Regular", (60, 58, 56), size=512, metal=1.0)
def diamond_plate(n, x, y, S, tile):
    cells = 12
    gx, gy = x * cells, y * cells
    ix, iy = np.floor(gx), np.floor(gy)
    lx, ly = (gx % 1 - 0.5), (gy % 1 - 0.5)
    sign = np.where((ix + iy) % 2 == 0, 1.0, -1.0).astype(F)
    a = math.radians(45)
    u = (lx * math.cos(a) + ly * math.sin(a) * sign)
    v = (-lx * math.sin(a) * sign + ly * math.cos(a))
    e = (u / 0.38) ** 2 + (v / 0.09) ** 2
    lug = np.clip(1 - e, 0, 1)
    height = 0.0018 * np.sqrt(lug) + 0.00004 * n.perlin(x, y, 3, 300)
    top = smoothstep(0.4, 0.8, lug)
    lum = 0.8 + 0.06 * top + 0.03 * n.fbm(x, y, 6, 3)
    rough = 0.48 - 0.15 * top + 0.08 * smoothstep(0.3, 0.7, n.fbm(x, y, 4, 3))
    return {"color": gray(lum), "height": height, "rough": rough}


@material("CorrodedMetal", "CorrodedMetal", 2.0, "Organic", (90, 96, 104), size=512)
def corroded_metal(n, x, y, S, tile):
    # weathered painted steel: rust blooms and pinpoint rust through the paint, drips running
    # down, a little bare steel where paint has flaked at the rust's edge
    wx = x + 0.03 * n.fbm(x, y, 8, 3)
    bloom = smoothstep(0.15, 0.45, n.fbm(wx, y, 6, 6))
    f1, _, ids = n.worley(x, y, 60, jitter=1.0)
    pin_r = n.per_cell(3600, 0.12, 0.38)[ids]
    pin = smoothstep(pin_r, pin_r * 0.4, f1) * (n.per_cell(3600)[ids] < 0.07) * smoothstep(-0.2, 0.3, n.fbm(x, y, 5, 3))
    drip = smoothstep(0.35, 0.75, n.fbm(x, y, 18, 3, cy=2)) * smoothstep(0.0, 0.3, n.fbm(x, y, 4, 3))
    rust = np.clip(np.maximum(bloom, np.maximum(pin * 0.9, drip * 0.55)), 0, 1)
    flake = smoothstep(0.08, 0.25, bloom) * smoothstep(0.42, 0.25, bloom) * smoothstep(0.2, 0.5, n.fbm(x, y, 40, 2))
    paint_l = 0.86 + 0.03 * n.fbm(x, y, 9, 3)
    rust_c = np.array([1.0, 0.62, 0.42], F) * (0.52 + 0.2 * n.fbm(x, y, 70, 3))[..., None]
    color = lerp(gray(paint_l), rust_c, rust[..., None])
    color = lerp(color, gray(np.full_like(x, 0.7)), flake[..., None] * 0.7)
    metal_map = flake * 0.9
    rough = lerp(0.48, 0.93, rust) - 0.25 * flake
    height = 0.0008 * n.fbm(x, y, 80, 4) * rust + 0.0002 * (1 - rust) + 0.0003 * flake
    return {"color": color, "height": height, "rough": rough, "metal": metal_map}


@material("Wood", "Wood", 1.0, "Regular", (140, 120, 94), size=512)
def wood(n, x, y, S, tile):
    base = n.fbm(x, y, 3, 4, cy=1)
    rings = np.sin(2 * math.pi * (x * 22 + 2.2 * base + 0.3 * n.fbm(x, y, 8, 3, cy=2)))
    lum = 0.8 + 0.07 * rings + 0.04 * n.fbm(x, y, 40, 2, cy=4)
    f1, _, ids = n.worley(x, y, 3, jitter=0.8)
    knot = smoothstep(0.12, 0.03, f1) * (n.per_cell(9)[ids] < 0.35)
    lum = lum * (1 - 0.45 * knot)
    height = 0.0003 * rings + 0.0005 * knot
    return {"color": tinted(lum, (1.03, 1.0, 0.95)), "height": height, "rough": 0.7 + 0.05 * rings}


@material("WoodPlanks", "WoodPlanks", 2.0, "Regular", (170, 140, 100), directional=True)
def wood_planks(n, x, y, S, tile):
    rows = 14  # 14.3 cm boards along x
    row = np.floor(y * rows)
    r = (row % rows).astype(np.int64)
    ly = y * rows % 1
    j1 = n.per_cell(rows)[r]
    j2 = (j1 + n.per_cell(rows, 0.35, 0.65)[r]) % 1
    seg = np.where((x - j1) % 1 < (j2 - j1) % 1, 0, 1)
    bid = (r * 2 + seg).astype(np.int64)
    board_w = tile / rows
    dgap = np.minimum(ly, 1 - ly) * board_w
    dj = np.minimum(np.abs((x - j1 + 0.5) % 1 - 0.5), np.abs((x - j2 + 0.5) % 1 - 0.5)) * tile
    gap = np.maximum(smoothstep(0.0035, 0.0012, dgap), smoothstep(0.0025, 0.0008, dj))
    grain = np.sin(2 * math.pi * (y * rows * 3 + 4 * n.fbm(x, y, 2, 3, cy=rows) + n.per_cell(rows * 2)[bid] * 7))
    tone = n.per_cell(rows * 2, 0.62, 1.0)[bid]
    weathered = n.per_cell(rows * 2)[bid] < 0.45
    tint = np.where(weathered[..., None], np.array([0.96, 0.96, 0.94], F), np.array([1.05, 0.96, 0.86], F))
    lum = tone * (0.92 + 0.05 * grain + 0.04 * n.fbm(x, y, 40, 2, cy=4))
    # nail heads at the joints and every 60 cm
    along = x * tile % 0.6
    d60 = np.minimum(along, 0.6 - along)
    nx = np.minimum(np.abs(dj - 0.025), d60)
    nail = smoothstep(0.0045, 0.0025, np.hypot(nx, (np.abs(ly - 0.5) - 0.3) * board_w)) * (1 - gap)
    lum = lum * (1 - 0.45 * nail) * (1 - 0.8 * gap)
    color = tinted(lum, (1, 1, 1)) * tint
    height = (1 - gap) * (0.001 * np.sin(math.pi * ly) + 0.0002 * grain) - gap * 0.008
    rough = 0.8 + 0.05 * grain - 0.35 * nail + 0.12 * gap
    return {"color": color, "height": height, "rough": rough}


@material("Fabric", "Fabric", 0.25, "Regular", (245, 242, 235), size=512)
def fabric(n, x, y, S, tile):
    k = 70  # threads per tile each way (3.6 mm)
    warp = np.sin(2 * math.pi * x * k)
    weft = np.sin(2 * math.pi * y * k)
    over = np.where(((np.floor(x * k) + np.floor(y * k)) % 2) == 0, 1.0, -1.0).astype(F)
    weave = 0.5 + 0.5 * over * warp * weft
    slub = n.perlin(x, y, 3, 160) * 0.5 + n.perlin(x, y, 160, 3) * 0.5
    lum = 0.88 + 0.03 * slub + 0.03 * (weave - 0.5)
    height = 0.00018 * weave + 0.00005 * slub
    return {"color": gray(lum), "height": height, "rough": 0.9 + 0.03 * (0.5 - weave)}


@material("Rubber", "Rubber", 0.5, "Organic", (24, 24, 26), size=512)
def rubber(n, x, y, S, tile):
    f = n.fbm(x, y, 60, 3)
    return {"color": gray(0.86 + 0.04 * f), "height": 0.00012 * f, "rough": 0.9 + 0.04 * n.fbm(x, y, 8, 2)}


@material("Leather", "Leather", 0.3, "Organic", (48, 46, 46), size=512)
def leather(n, x, y, S, tile):
    f1, f2, _ = n.worley(x, y, 70, jitter=1.0)
    pebble = np.clip(f2 - f1, 0, 1) ** 0.5
    crease = smoothstep(0.08, 0.0, f2 - f1)
    wear = smoothstep(0.2, 0.6, n.fbm(x, y, 3, 3))
    lum = 0.85 + 0.04 * pebble + 0.06 * wear
    height = 0.0003 * pebble - 0.0002 * crease
    rough = 0.6 - 0.15 * wear + 0.08 * crease
    return {"color": gray(lum), "height": height, "rough": rough}


# ---------------------------------------------------------------------------- ground & nature


def _blades(n, S, tile, count, palette, weights, length_m=(0.03, 0.08)):
    """Grass blades seen from above: coloured strokes, with coverage for soil gaps."""
    rng = n.rng
    ppm = S / tile
    xs, ys, w, idx = T.strokes(rng, S, count, (length_m[0] * ppm, length_m[1] * ppm), samples=10)
    choice = rng.choice(len(palette), size=count, p=np.array(weights) / sum(weights))
    lum = rng.uniform(0.7, 1.05, count)
    cols = (np.array(palette, F)[choice] * lum[:, None])[idx]
    cover, csum = T.splat(S, xs, ys, w, cols)
    cover = T.blur(cover, 0.6)
    csum = T.blur(csum, 0.6)
    color = csum / np.maximum(cover, 1e-4)[..., None]
    return color, cover


@material("Grass", "Grass", 1.5, "Organic", (104, 155, 68))
def grass(n, x, y, S, tile):
    palette = [(0.92, 1.0, 0.86), (1.08, 1.04, 0.72), (0.78, 0.88, 0.8), (1.32, 1.1, 0.74), (0.86, 0.95, 0.9)]
    color, cover = _blades(n, S, tile, 150000, palette, [0.4, 0.2, 0.2, 0.08, 0.12])
    density = np.clip(cover / np.percentile(cover, 60), 0, 1)
    soil = np.array([1.15, 0.9, 0.72], F) * 0.5
    patch = 0.1 * n.fbm(x, y, 4, 4)
    dry = smoothstep(0.25, 0.6, n.fbm(x + 0.6, y + 0.1, 3, 4))
    color = lerp(soil * np.ones_like(color), color, density[..., None]) * (1 + patch)[..., None]
    color = lerp(color, color * np.array([1.18, 1.05, 0.82], F), dry[..., None] * 0.6)
    height = 0.004 * T.blur(density, 1.0)
    rough = 0.84 + 0.1 * (1 - density)
    return {"color": color, "height": height, "rough": rough}


@material("LeafyGrass", "LeafyGrass", 2.0, "Organic", (96, 128, 60))
def leafy_grass(n, x, y, S, tile):
    palette = [(0.9, 1.0, 0.85), (1.1, 1.02, 0.72), (0.75, 0.86, 0.78), (1.4, 1.05, 0.7)]
    color, cover = _blades(n, S, tile, 110000, palette, [0.4, 0.2, 0.25, 0.15], (0.025, 0.06))
    density = np.clip(cover / np.percentile(cover, 55), 0, 1)
    # leaf litter: small elongated leaves, brown and yellow
    rng = n.rng
    ppm = S / tile
    xs, ys, w, idx = T.strokes(rng, S, 2500, (0.03 * ppm, 0.06 * ppm), samples=8, taper=False)
    lit, lsum = T.splat(S, xs, ys, w, (np.array([[1.45, 1.0, 0.62], [1.3, 1.15, 0.6], [1.1, 0.8, 0.55]], F)[rng.integers(0, 3, 2500)] * rng.uniform(0.6, 1.0, 2500)[:, None])[idx])
    lit = T.blur(lit, 1.6)
    lsum = T.blur(lsum, 1.6)
    leafc = lsum / np.maximum(lit, 1e-4)[..., None]
    leaf = np.clip(lit * 3, 0, 1)
    soil = np.array([1.1, 0.88, 0.7], F) * 0.48
    color = lerp(soil * np.ones_like(color), color, density[..., None])
    color = lerp(color, leafc, leaf[..., None])
    height = 0.003 * T.blur(density, 1.0) + 0.0015 * leaf
    rough = 0.85 + 0.08 * (1 - density) - 0.05 * leaf
    return {"color": color, "height": height, "rough": rough}


@material("Sand", "Sand", 2.0, "Organic", (228, 212, 172))
def sand(n, x, y, S, tile):
    grain = n.fbm(x, y, 480, 2)
    phase = y * 22 + 3.0 * n.fbm(x, y, 3, 4) + 0.8 * n.fbm(x, y, 12, 3)
    ripple = (0.5 + 0.5 * np.sin(2 * math.pi * phase)) ** 1.6
    calm = smoothstep(-0.1, 0.35, n.fbm(x + 0.3, y, 2, 3))  # ripples only where the wind left them
    trampled = smoothstep(0.1, 0.5, n.fbm(x, y, 5, 3))
    f1, _, _ = n.worley(x, y, 26, jitter=1.0)
    dents = (1 - np.clip(f1, 0, 1)) ** 2 * trampled
    lum = 0.84 + 0.04 * grain + 0.02 * (ripple - 0.5) * calm + 0.03 * n.fbm(x, y, 4, 4) - 0.03 * dents
    f1, _, ids = n.worley(x, y, 45, jitter=1.0)
    shell = smoothstep(0.08, 0.03, f1) * (n.per_cell(2025)[ids] < 0.22)
    f1b, _, idsb = n.worley(x, y, 210, jitter=1.0)
    debris = smoothstep(0.08, 0.03, f1b) * (n.per_cell(210 * 210)[idsb] < 0.08)
    color = tinted(lum, (1, 1, 1))
    shell_c = np.stack([np.full_like(x, 1.12), np.full_like(x, 1.0), np.full_like(x, 0.98)], -1) * (1.0 + n.per_cell(2025, -0.1, 0.05)[ids])[..., None]
    color = lerp(color, np.minimum(shell_c, 1.0), shell[..., None])
    color = color * (1 - 0.45 * debris)[..., None]
    height = 0.0014 * ripple * calm * (1 - trampled) - 0.006 * dents + 0.00025 * grain + 0.0006 * shell
    rough = 0.9 + 0.03 * grain - 0.15 * shell
    return {"color": color, "height": height, "rough": rough}


@material("Ground", "Ground", 2.0, "Organic", (128, 92, 60))
def ground(n, x, y, S, tile):
    lum = 0.72 + 0.08 * n.fbm(x, y, 6, 6)
    f1, _, _ = n.worley(x, y, 60, jitter=1.0)
    clump = (1 - np.clip(f1, 0, 1)) ** 2
    height = 0.004 * clump + 0.0015 * n.fbm(x, y, 30, 4)
    f1, _, ids = n.worley(x, y, 85, jitter=0.95)
    keep = n.per_cell(85 * 85)[ids] < 0.25
    peb = smoothstep(0.32, 0.22, f1) * keep
    pc = n.per_cell(85 * 85, 0.85, 1.25)[ids]
    color = tinted(lum, (1, 1, 1))
    color = lerp(color, np.stack([pc * 0.95, pc * 0.95, pc * 1.0], -1) * 0.82, peb[..., None])
    height = height + peb * 0.005 * np.sqrt(np.clip(1 - (f1 / 0.32) ** 2, 0, 1))
    # dry cracks, twigs
    f1, f2, _ = n.worley(x + 0.02 * n.fbm(x, y, 9, 2), y, 9, jitter=1.0)
    crack = smoothstep(0.012, 0.0, f2 - f1) * smoothstep(0.0, 0.3, n.fbm(x, y, 3, 2))
    rng = n.rng
    xs, ys, w, _ = T.strokes(rng, S, 260, (25, 70), samples=16, taper=False)
    twig, _ = T.splat(S, xs, ys, w)
    twig = np.clip(T.blur(twig, 0.7) * 2.5, 0, 1)
    color = color * (1 - 0.5 * crack)[..., None] * (1 - 0.35 * twig)[..., None]
    height = height - 0.003 * crack + 0.0008 * twig
    rough = 0.92 - 0.04 * peb
    return {"color": color, "height": height, "rough": rough}


@material("Mud", "Mud", 2.0, "Organic", (104, 96, 66))
def mud(n, x, y, S, tile):
    low = n.fbm(x, y, 3, 5)
    height = 0.02 * low + 0.003 * n.fbm(x, y, 22, 3) + 0.0008 * n.fbm(x, y, 120, 2)
    wet = smoothstep(-0.18, -0.35, low)
    water_level = np.minimum(height, np.percentile(height, 18))
    height = lerp(height, water_level, wet)
    lum = 0.68 + 0.06 * n.fbm(x, y, 10, 4)
    rng = n.rng
    xs, ys, w, _ = T.strokes(rng, S, 1800, (20, 60), samples=12)
    bits, _ = T.splat(S, xs, ys, w)
    bits = np.clip(T.blur(bits, 0.6) * 2, 0, 1) * (1 - wet)
    lum = lum * (1 - 0.35 * wet) * (1 - 0.3 * bits)
    color = tinted(lum, (1, 1, 1))
    rough = lerp(0.82, 0.12, wet) - 0.1 * smoothstep(0.0, -0.1, low)
    return {"color": color, "height": height, "rough": rough}


@material("Rock", "Rock", 3.0, "Organic", (128, 124, 116))
def rock(n, x, y, S, tile):
    # weathered limestone boulders: lumpy, pitted, a few fissures, lichen
    bumps = n.fbm(x, y, 5, 6)
    ridges = n.ridged(x, y, 4, 5)
    pits = n.fbm(x, y, 40, 3)
    wx = x + 0.06 * n.fbm(x, y, 4, 3)
    f1, f2, _ = n.worley(wx, y, 4, jitter=1.0)
    fissure = smoothstep(0.02, 0.0, f2 - f1) * smoothstep(0.1, 0.4, n.fbm(x, y, 3, 2))
    height = 0.02 * bumps + 0.01 * ridges + 0.002 * pits - 0.006 * fissure
    lum = 0.78 + 0.07 * bumps + 0.04 * pits - 0.06 * smoothstep(0.2, -0.3, pits)
    lichen = smoothstep(0.45, 0.65, n.fbm(x, y, 10, 4))
    color = tinted(lum * (1 - 0.45 * fissure), (1, 1, 1))
    color = lerp(color, np.array([0.95, 0.98, 0.84], F) * lum[..., None], lichen[..., None] * 0.55)
    rough = 0.86 + 0.05 * n.fbm(x, y, 20, 2)
    return {"color": color, "height": height, "rough": rough}


@material("Slate", "Slate", 2.0, "Organic", (77, 78, 83), size=512)
def slate(n, x, y, S, tile):
    # cleft slate: plates at slightly different levels and tones, faint lamination
    wx = x + 0.04 * n.fbm(x, y, 6, 3)
    f1, f2, ids = n.worley(wx, y, 7, jitter=1.0)
    level = n.per_cell(49, 0.0, 1.0)[ids]
    seam = smoothstep(0.04, 0.0, f2 - f1)
    lam = n.fbm(x, y, 3, 4, cy=24)
    height = 0.003 * level + 0.0008 * lam + 0.001 * n.fbm(x, y, 30, 3) - 0.002 * seam
    lum = 0.78 + 0.08 * (level - 0.5) + 0.03 * lam + 0.02 * n.fbm(x, y, 40, 3) - 0.15 * seam
    return {"color": gray(lum), "height": height, "rough": 0.68 + 0.08 * level}


@material("Marble", "Marble", 2.0, "Organic", (250, 248, 240))
def marble(n, x, y, S, tile):
    turb = n.fbm(x, y, 3, 7)
    vein = np.abs(np.sin(2 * math.pi * (x * 2 + y * 1 + 2.8 * turb)))
    veins = 1 - smoothstep(0.0, 0.12, vein)
    fine = 1 - smoothstep(0.0, 0.05, np.abs(np.sin(2 * math.pi * (x * 5 - y * 3 + 4 * n.fbm(x, y, 6, 6)))))
    lum = 0.95 - 0.28 * veins - 0.12 * fine + 0.02 * n.fbm(x, y, 5, 4)
    color = tinted(lum, (1.0, 0.995, 0.98))
    height = -0.0001 * veins
    rough = 0.16 + 0.05 * n.fbm(x, y, 30, 3) + 0.04 * veins
    return {"color": color, "height": height, "rough": rough}


# ---------------------------------------------------------------------------- facade variants (named)


@material("Stucco", "Plaster", 2.0, "Organic", (246, 238, 222), named=True)
def stucco(n, x, y, S, tile):
    """Miami's sand-float stucco: coarse aggregate, trowel swirls, hairline cracks, weathered
    patches and lighter patch repairs (coarser and older than the smooth Plaster)."""
    f1, _, _ = n.worley(x, y, 360, jitter=1.0)
    grit = (1 - np.clip(f1, 0, 1)) ** 3
    swirl = n.fbm(x, y, 14, 4)
    # (sand-float: a coarse, sandy face; trowel arcs read as soft bands of light and shade)
    height = 0.0018 * grit + 0.002 * smoothstep(0.3, 0.8, swirl) + 0.0009 * n.fbm(x, y, 90, 3)
    lum = 0.86 + 0.08 * (grit - 0.3) + 0.04 * n.fbm(x, y, 6, 4) + 0.05 * (swirl - 0.5)
    c1, c2, _ = n.worley(x, y, 5, jitter=1.0)
    crack = smoothstep(0.014, 0.0, c2 - c1) * smoothstep(0.5, 0.75, n.fbm(x, y, 3, 3))
    height = height - crack * 0.001
    lum = lum - 0.18 * crack
    # weathered patches (dirt held in the texture) and paler patch repairs
    lum = lum - 0.12 * smoothstep(0.45, 0.85, n.fbm(x + 0.37, y, 2, 5)) + 0.06 * smoothstep(0.6, 0.85, n.fbm(x, y + 0.5, 3, 4))
    rough = 0.92 + 0.05 * grit - 0.06 * crack
    return {"color": gray(lum), "height": height, "rough": rough}


@material("BrickOld", "Brick", 1.125, "Regular", (140, 76, 58), named=True)
def brick_old(n, x, y, S, tile):
    """Old brick: irregular, sooted and weathered faces, eroded mortar, chipped arrises and the odd
    replaced brick."""
    courses, per = 15, 5
    row = np.floor(y * courses)
    jog = n.per_cell(courses, -0.06, 0.06)[(row % courses).astype(np.int64)]
    bx = x * per + (row % 2) * 0.5 + jog
    bi = np.floor(bx) % per
    bid = ((row % courses) * per + bi).astype(np.int64)
    lx = (bx % 1) * 0.225
    ly = (y * courses % 1) * 0.075
    wobble = 0.0015 * n.fbm(x, y, 60, 2)
    d = np.minimum(np.minimum(lx - 0.006, 0.219 - lx), np.minimum(ly - 0.006, 0.069 - ly)) + wobble
    body = smoothstep(-0.001, 0.004, d)
    shade = n.per_cell(courses * per, -0.26, 0.14)[bid]
    swap = n.per_cell(courses * per)[bid] < 0.07
    # (the mortar is recessed and grimy; faces vary a lot, a few are newer replacements)
    lum = lerp(0.6, 0.62 + shade + 0.08 * n.fbm(x, y, 30, 3) + 0.14 * swap, body)
    soot = smoothstep(0.4, 0.8, n.fbm(x, y, 2, 5))
    lum = lum * (1 - 0.38 * soot)
    # efflorescence: white salt blooming out of the joints in places
    bloom = smoothstep(0.6, 0.85, n.fbm(x + 0.6, y, 4, 4)) * (1 - body)
    lum = lum + 0.25 * bloom
    hue = np.stack([1 + n.per_cell(courses * per, -0.04, 0.1)[bid], 1 + n.per_cell(courses * per, -0.1, 0.02)[bid], 1 + n.per_cell(courses * per, -0.12, 0.0)[bid]], -1)
    color = tinted(lum, (1, 1, 1)) * lerp(np.ones_like(hue), hue, body[..., None])
    pits = smoothstep(0.62, 0.8, n.fbm(x, y, 120, 2)) * body
    height = body * (0.005 + 0.0009 * n.fbm(x, y, 90, 3)) - pits * 0.001 + (1 - body) * (0.0006 * n.fbm(x, y, 200, 2) - 0.001)
    rough = lerp(0.95, 0.86, body) + 0.03 * soot
    return {"color": color, "height": height, "rough": rough}


@material("ConcreteBoard", "Concrete", 2.4, "Regular", (200, 198, 192), named=True)
def concrete_board(n, x, y, S, tile):
    """Board-formed concrete: the grain and joints of the 15 cm planks it was cast against, form-tie
    holes in a grid, rust and water staining."""
    boards = 16
    row = np.floor(y * boards)
    rid = (row % boards).astype(np.int64)
    ly = y * boards % 1
    joint = smoothstep(0.06, 0.0, np.minimum(ly, 1 - ly))
    grain = n.perlin(x * 0.2, y, 2, 160) * 0.6 + n.fbm(x, y, 40, 3) * 0.4
    tone = n.per_cell(boards, -0.05, 0.05)[rid]
    lum = 0.8 + tone + 0.04 * grain - 0.08 * joint + 0.02 * n.fbm(x, y, 5, 4)
    tx, ty = (x * 4) % 1 - 0.5, (y * 4) % 1 - 0.5
    tie = smoothstep(0.035, 0.02, np.hypot(tx, ty * 0.95))
    lum = lum * (1 - 0.45 * tie)
    stain = smoothstep(0.5, 0.8, n.fbm(x + 0.21, y, 3, 5))
    lum = lum - 0.07 * stain
    height = 0.0005 * grain - 0.0012 * joint - 0.003 * tie + 0.0002 * n.fbm(x, y, 200, 2)
    rough = 0.84 + 0.05 * grain + 0.05 * joint
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.03, 0.98, 0.92], F), (0.6 * stain)[..., None])
    return {"color": color, "height": height, "rough": rough}


@material("Corrugated", "Metal", 1.0, "Regular", (170, 176, 180), size=512, metal=1.0, named=True)
def corrugated(n, x, y, S, tile):
    """Corrugated steel sheeting: 7.6 cm waves, galvanising spangle, rust weeping from the laps and
    fixings, dull where it's weathered."""
    waves = 13
    phase = 2 * math.pi * x * waves
    height = 0.009 * (0.5 + 0.5 * np.sin(phase))
    _, _, ids = n.worley(x, y, 70, jitter=1.0)
    spangle = n.per_cell(70 * 70, -0.04, 0.04)[ids]
    # fixings through every other crest, in rows a half tile apart (distances in tile units)
    dx = ((x * waves / 2) % 1 - 0.75) * 2 / waves
    dy = ((y * 2) % 1 - 0.5) / 2
    screws = smoothstep(0.006, 0.003, np.hypot(dx, dy))
    rust = smoothstep(0.55, 0.85, n.fbm(x, y * 0.6, 3, 5)) * (0.6 + 0.4 * np.cos(phase))
    lum = 0.78 + spangle + 0.05 * np.cos(phase) - 0.25 * screws
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.1, 0.78, 0.55], F), (0.5 * rust)[..., None])
    rough = 0.45 + 0.25 * rust + 0.05 * n.fbm(x, y, 20, 3)
    metal = 1.0 - 0.7 * rust
    return {"color": color, "height": height, "rough": rough, "metal": metal}


# ---------------------------------------------------------------------------- the detail pass
# Named variants the builders put on parts by role and district (rnd=2: they ship in Textures2.fbx,
# an add-on import next to the first pack). Near-neutral like the rest, so the parts' colours still
# decide the hue, except where the material's own colour variation matters (pavers, stone, rust).


def _rects(n, x, y, cells, chance, size=(0.25, 0.75), soft=0.01):
    """Soft-edged rectangles, at most one per cell of a `cells` x `cells` grid: 1 inside, 0 outside,
    with each rectangle's id (for a tone each)."""
    cx, cy = x * cells, y * cells
    i, j = np.floor(cx).astype(np.int64), np.floor(cy).astype(np.int64)
    k = (j % cells) * cells + (i % cells)
    count = cells * cells
    on = n.per_cell(count) < chance
    w = n.per_cell(count, size[0], size[1])
    h = n.per_cell(count, size[0], size[1])
    ox = n.per_cell(count, 0, 1) * (1 - w)
    oy = n.per_cell(count, 0, 1) * (1 - h)
    lx, ly = cx - i, cy - j
    dx = np.minimum(lx - ox[k], ox[k] + w[k] - lx)
    dy = np.minimum(ly - oy[k], oy[k] + h[k] - ly)
    inside = smoothstep(0, soft * cells, np.minimum(dx, dy)) * on[k]
    return inside.astype(F), k


@material("AsphaltWorn", "Asphalt", 4.0, "Organic", (100, 101, 104), named=True, rnd=2)
def asphalt_worn(n, x, y, S, tile):
    """Old, sun-bleached asphalt (side streets, car parks): the binder worn off the aggregate, a
    network of cracks sealed with black tar snakes, saw-cut patch repairs of newer, darker
    asphalt, oil drips."""
    f1, _, ids = n.worley(x, y, 240, jitter=1.0)
    stone = smoothstep(0.45, 0.2, f1)
    tone = n.per_cell(240 * 240, -0.16, 0.16)[ids]
    lum = 0.62 + stone * (0.18 + tone) + 0.05 * n.fbm(x, y, 150, 3) + 0.09 * n.fbm(x, y, 4, 4)
    height = 0.0016 * stone + 0.0004 * n.fbm(x, y, 300, 2)
    wx = x + 0.012 * n.fbm(x, y, 9, 3)
    wy = y + 0.012 * n.fbm(x + 0.4, y, 9, 3)
    c1, c2, _ = n.worley(wx, wy, 6, jitter=1.0)
    edge = c2 - c1
    reach = smoothstep(-0.25, 0.15, n.fbm(x + 0.3, y, 2, 4))
    crack = smoothstep(0.01, 0.0, edge) * reach
    sealed = smoothstep(-0.1, 0.25, n.fbm(x, y + 0.6, 3, 3))
    tar = smoothstep(0.05, 0.028, edge + 0.01 * n.fbm(x, y, 60, 2)) * reach * sealed
    # (the tar band is flat and nearly black; open cracks are dark slots)
    lum = lerp(lum, 0.2 + 0.03 * n.fbm(x, y, 200, 2), tar) - 0.25 * crack * (1 - sealed)
    height = height * (1 - tar) - 0.0025 * crack * (1 - sealed)
    jag = 0.008 * n.fbm(x, y, 40, 2)
    patch, pid = _rects(n, x + jag, y - jag, 3, 0.25, size=(0.2, 0.55), soft=0.004)
    ptone = n.per_cell(9, -0.08, 0.06)[pid]
    lum = lerp(lum, 0.4 + ptone + 0.05 * n.fbm(x, y, 120, 3) + 0.06 * stone, patch * (1 - tar))
    height = height + 0.0025 * patch
    oil = smoothstep(0.5, 0.75, n.fbm(x + 0.71, y + 0.2, 7, 4)) * smoothstep(0.0, 0.3, n.fbm(x, y, 2, 2))
    lum = lum * (1 - 0.4 * oil)
    rough = 0.92 - 0.15 * tar - 0.4 * oil - 0.06 * patch
    # (a little lighter than the fresh asphalt's map on average, 0.5 against 0.4: older, not another
    # material, since both multiply the same road colour)
    return {"color": gray(lum * 0.78), "height": height, "rough": rough}


@material("ConcreteDeck", "Concrete", 6.0, "Regular", (186, 184, 178), named=True, rnd=2)
def concrete_deck(n, x, y, S, tile):
    """A concrete road deck (freeways, bridges, ramps): broom-tined panels with sealed joints, spalled
    edges, cracks, rust bleeding from the rebar, oil drips and tyre-darkened lanes."""
    tine = n.perlin(x, y * 0.02, 300, 3) * 0.6 + n.fbm(x, y, 400, 2) * 0.4
    lum = 0.7 + 0.08 * tine + 0.16 * n.fbm(x, y, 3, 5) + 0.05 * n.fbm(x, y, 40, 3)
    height = 0.001 * tine + 0.0003 * n.fbm(x, y, 200, 2)
    jx = np.minimum((x * 2) % 1, 1 - (x * 2) % 1) * tile / 2
    jy = np.minimum((y * 2) % 1, 1 - (y * 2) % 1) * tile / 2
    jd = np.minimum(jx, jy)
    joint = smoothstep(0.016, 0.006, jd)
    spall = smoothstep(0.08, 0.0, jd) * smoothstep(0.3, 0.65, n.fbm(x, y, 18, 3))
    lum = lerp(lum, 0.18, joint) - 0.2 * spall
    height = height - 0.005 * joint - 0.008 * spall
    wx = x + 0.01 * n.fbm(x, y, 12, 3)
    c1, c2, _ = n.worley(wx, y, 5, jitter=1.0)
    crack = smoothstep(0.008, 0.0, c2 - c1) * smoothstep(0.0, 0.4, n.fbm(x + 0.5, y, 2, 3))
    lum = lum - 0.35 * crack
    height = height - 0.002 * crack
    lane = (np.sin(2 * math.pi * x * 2) * 0.5 + 0.5) ** 2
    drip = smoothstep(0.45, 0.7, n.fbm(x + 0.2, y, 14, 3)) * (1 - lane)
    lum = lum * (1 - 0.22 * lane - 0.45 * drip)
    rust = smoothstep(0.55, 0.85, n.fbm(x + 0.13, y * 3, 8, 4)) * (1 - joint)
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.16, 0.82, 0.6], F), (0.7 * rust)[..., None])
    rough = 0.88 - 0.18 * lane + 0.06 * spall - 0.12 * joint - 0.4 * drip
    return {"color": color, "height": height, "rough": rough}


@material("RoadPaint", "SmoothPlastic", 1.5, "Organic", (240, 240, 236), named=True, rnd=2)
def road_paint(n, x, y, S, tile):
    """Worn road paint (lane lines, crossings, stop bars): the asphalt's grain through the film,
    chipped off in flakes where the tyres run, cracks following the road beneath, grime, glass
    beads."""
    f1, _, _ = n.worley(x, y, 140, jitter=1.0)
    grain = smoothstep(0.5, 0.15, f1)
    flakes1, _, fid = n.worley(x + 0.01 * n.fbm(x, y, 50, 2), y, 60, jitter=1.0)
    flaky = n.per_cell(3600)[fid] < (0.04 + 0.24 * smoothstep(0.0, 0.7, n.fbm(x, y, 4, 4)))
    # (ragged flakes, not dots: the edge wanders with fine noise and the grain)
    loss = smoothstep(0.5, 0.36, flakes1 + 0.22 * n.fbm(x, y, 160, 2) - 0.1 * grain) * flaky
    c1, c2, _ = n.worley(x + 0.007 * n.fbm(x, y, 30, 2), y, 5, jitter=1.0)
    crack = smoothstep(0.012, 0.0, c2 - c1) * smoothstep(0.0, 0.4, n.fbm(x + 0.2, y, 3, 3))
    grime = smoothstep(-0.2, 0.6, n.fbm(x + 0.5, y + 0.3, 3, 4))
    lum = 0.95 - 0.08 * grain - 0.1 * grime - 0.5 * loss - 0.45 * crack + 0.02 * n.fbm(x, y, 40, 3)
    bead = smoothstep(0.07, 0.02, f1) * (1 - loss)
    height = 0.0007 * (1 - loss) + 0.0009 * grain - 0.001 * crack
    rough = 0.58 + 0.32 * loss - 0.3 * bead + 0.05 * grime
    return {"color": gray(lum), "height": height, "rough": rough}


@material("BrickPavers", "Brick", 1.6, "Regular", (168, 92, 64), named=True, rnd=2)
def brick_pavers(n, x, y, S, tile):
    """Clay pavers in basketweave (plazas, Brickell and Downtown pavements, Ocean Drive): 20 x 10 cm
    pavers in pairs, sand joints, a tone and hue each, chamfered edges, worn paths and moss."""
    sq = 8
    sx, sy = x * sq, y * sq
    i, j = np.floor(sx), np.floor(sy)
    lx, ly = sx - i, sy - j
    across = ((i + j) % 2) == 0
    k = np.where(across, np.floor(ly * 2), np.floor(lx * 2))
    fx = np.where(across, lx, (lx * 2) % 1)
    fy = np.where(across, (ly * 2) % 1, ly)
    wx = np.where(across, 0.2, 0.1)
    wy = np.where(across, 0.1, 0.2)
    d = np.minimum(np.minimum(fx, 1 - fx) * wx, np.minimum(fy, 1 - fy) * wy) + 0.0006 * n.fbm(x, y, 120, 2)
    body = smoothstep(0.001, 0.005, d)
    pid = (((j % sq) * sq + (i % sq)) * 2 + k).astype(np.int64)
    count = sq * sq * 2
    shade = n.per_cell(count, -0.16, 0.12)[pid]
    hue = np.stack([1 + n.per_cell(count, -0.02, 0.1)[pid], 1 + n.per_cell(count, -0.12, 0.04)[pid], 1 + n.per_cell(count, -0.18, 0.02)[pid]], -1)
    wear = smoothstep(0.35, 0.75, n.fbm(x, y, 2, 4))
    lum = lerp(0.42, 0.74 + shade + 0.06 * n.fbm(x, y, 50, 3) + 0.1 * wear, body)
    moss = (1 - body) * smoothstep(0.55, 0.8, n.fbm(x + 0.4, y, 3, 4))
    color = tinted(lum, (1, 1, 1)) * lerp(np.ones_like(hue), hue, body[..., None])
    color = lerp(color, np.array([0.32, 0.4, 0.2], F) * 1.0, (0.7 * moss)[..., None])
    cracked = (n.per_cell(count)[pid] < 0.04) * body * smoothstep(0.01, 0.0, np.abs(fx - fy * 0.7 - 0.2) * 0.1)
    height = body * 0.004 * smoothstep(0.0, 0.006, d) - 0.0015 * cracked + 0.0003 * n.fbm(x, y, 200, 2)
    rough = lerp(0.95, 0.8 - 0.1 * wear, body)
    return {"color": color, "height": height, "rough": rough}


@material("CoralStone", "Limestone", 2.0, "Regular", (222, 210, 182), named=True, rnd=2)
def coral_stone(n, x, y, S, tile):
    """Cut coral keystone (Coral Gables, Coconut Grove): 60 x 30 cm blocks in running bond, riddled
    with fossil pits at every size, shell fragments, cream to buff block by block, grey lichen."""
    courses, per = 6, 3
    row = np.floor(y * courses)
    bx = x * per + (row % 2) * 0.5
    bi = np.floor(bx) % per
    bid = ((row % courses) * per + bi).astype(np.int64)
    lx = (bx % 1) * 0.6667
    ly = (y * courses % 1) * 0.3333
    d = np.minimum(np.minimum(lx, 0.6667 - lx), np.minimum(ly, 0.3333 - ly)) + 0.0015 * n.fbm(x, y, 70, 2)
    body = smoothstep(0.002, 0.008, d)
    pits = np.zeros_like(x)
    for cells, radius, keep, depth in ((22, 0.3, 0.25, 1.0), (70, 0.28, 0.55, 0.8), (210, 0.26, 0.65, 0.6), (520, 0.3, 0.5, 0.4)):
        f1, _, ids = n.worley(x, y, cells, jitter=1.0)
        r = radius * n.per_cell(cells * cells, 0.5, 1.2)[ids]
        alive = n.per_cell(cells * cells)[ids] < keep
        pits = np.maximum(pits, smoothstep(r, r * 0.55, f1) * alive * depth)
    g1, _, _ = n.worley(x + 0.37, y, 160, jitter=1.0)
    shell = smoothstep(0.05, 0.0, g1) * (n.fbm(x, y, 90, 2) > 0.25)
    shade = n.per_cell(courses * per, -0.1, 0.08)[bid]
    lum = 0.84 + shade + 0.06 * n.fbm(x, y, 25, 4) - 0.42 * pits + 0.1 * shell
    lichen = smoothstep(0.35, 0.8, n.fbm(x + 0.2, y + 0.7, 3, 5))
    lum = lerp(0.52, lum, body) * (1 - 0.3 * lichen)
    hue = np.stack([1 + n.per_cell(courses * per, 0.0, 0.07)[bid], np.ones_like(shade), 1 - n.per_cell(courses * per, 0.02, 0.12)[bid]], -1)
    color = tinted(lum, (1, 1, 1)) * lerp(np.ones_like(hue), hue, body[..., None])
    color = color * lerp(np.ones(3, F), np.array([0.95, 0.92, 0.85], F), pits[..., None])
    height = body * (0.004 - 0.007 * pits + 0.0008 * n.fbm(x, y, 70, 3)) - (1 - body) * 0.002
    rough = 0.95 - 0.04 * shell
    return {"color": color, "height": height, "rough": rough}


@material("CoralRubble", "Limestone", 2.5, "Organic", (214, 204, 180), named=True, rnd=2)
def coral_rubble(n, x, y, S, tile):
    """A coral rock wall (garden walls, park walls, old Miami houses): chunky irregular oolite stones,
    domed and riddled with pits, bedded in deep, shadowed grey mortar."""
    wx = x + 0.025 * n.fbm(x, y, 6, 3)
    wy = y + 0.025 * n.fbm(x + 0.5, y, 6, 3)
    f1, f2, ids = n.worley(wx, wy, 8, jitter=1.0)
    g1, g2, gid = n.worley(wx + 0.21, wy, 15, jitter=1.0)
    # (a share of the big stones are split into smaller ones: sizes vary like a real wall)
    split = n.per_cell(64)[ids] < 0.45
    gap = np.where(split, g2 - g1, f2 - f1) * np.where(split, 15 / 8, 1.0)
    sid = np.where(split, gid + 1000, ids)
    centre = np.where(split, g1 * 8 / 15, f1)
    body = smoothstep(0.06, 0.16, gap + 0.03 * n.fbm(x, y, 40, 2))
    pits = np.zeros_like(x)
    for cells, radius, keep in ((40, 0.32, 0.5), (130, 0.3, 0.6), (380, 0.32, 0.5)):
        p1, _, pid = n.worley(x, y, cells, jitter=1.0)
        alive = n.per_cell(cells * cells)[pid] < keep
        pits = np.maximum(pits, smoothstep(radius, radius * 0.5, p1) * alive)
    shade = (n.per_cell(1300, -0.15, 0.1))[(sid % 1300).astype(np.int64)]
    lum = 0.8 + shade + 0.06 * n.fbm(x, y, 35, 4) - 0.36 * pits
    mortar = 0.56 + 0.06 * n.fbm(x, y, 90, 3)
    lum = lerp(mortar, lum, body)
    dark = smoothstep(0.3, 0.85, n.fbm(x + 0.9, y, 2, 5))
    lum = lum * (1 - 0.28 * dark)
    hue_r = 1 + n.per_cell(1300, 0.0, 0.08)[(sid % 1300).astype(np.int64)]
    hue_b = 1 - n.per_cell(1300, 0.02, 0.14)[(sid % 1300).astype(np.int64)]
    hue = np.stack([hue_r, np.ones(ids.shape, F), hue_b], -1)
    color = tinted(lum, (1, 1, 1)) * lerp(np.ones_like(hue), hue, body[..., None])
    dome = np.clip(0.55 - centre, 0, 0.55) / 0.55
    height = body * (0.018 * dome + 0.006 - 0.006 * pits) - (1 - body) * 0.01
    rough = lerp(0.92, 0.95, body)
    return {"color": color, "height": height, "rough": rough}


@material("StuccoStreaked", "Plaster", 3.0, "Organic", (240, 232, 214), named=True, rnd=2)
def stucco_streaked(n, x, y, S, tile):
    """Weathered stucco: rain streaks running down from every ledge and sill, mildew darkening in the
    damp (Miami's humidity), hairline cracks, paint worn thin over the trowel texture."""
    f1, _, _ = n.worley(x, y, 300, jitter=1.0)
    grit = (1 - np.clip(f1, 0, 1)) ** 3
    lum = 0.88 + 0.06 * (grit - 0.3) + 0.04 * n.fbm(x, y, 6, 4)
    # streaks: thin vertical runs of grime (noise stretched hard along y), fading as they fall
    runs = n.fbm(x * 1.0, y * 0.04, 90, 4, cy=4)
    fall = (y * 3) % 1
    streak = smoothstep(0.15, 0.55, runs) * (1 - 0.6 * fall) * smoothstep(-0.3, 0.3, n.fbm(x, y, 3, 3))
    mildew = smoothstep(0.2, 0.75, n.fbm(x + 0.4, y, 3, 5)) * (0.4 + 0.6 * smoothstep(0.4, 1.0, y))
    lum = lum - 0.32 * streak - 0.24 * mildew
    c1, c2, _ = n.worley(x, y, 4, jitter=1.0)
    crack = smoothstep(0.012, 0.0, c2 - c1) * smoothstep(0.2, 0.6, n.fbm(x, y + 0.3, 3, 3))
    lum = lum - 0.2 * crack
    color = gray(lum) * lerp(np.ones(3, F), np.array([0.94, 0.97, 0.9], F), mildew[..., None])
    height = 0.0016 * grit + 0.0008 * n.fbm(x, y, 40, 3) - 0.001 * crack
    rough = 0.92 + 0.04 * grit
    return {"color": color, "height": height, "rough": rough}


@material("PaintedBlock", "Concrete", 1.6, "Regular", (222, 220, 212), named=True, rnd=2)
def painted_block(n, x, y, S, tile):
    """Painted concrete block (warehouses, garages, back walls, yard walls): 40 x 20 cm blocks in
    running bond with tooled concave joints, the paint's orange peel over the block's open pores,
    chips showing grey block, rust runs from fixings."""
    courses, per = 8, 4
    row = np.floor(y * courses)
    bx = x * per + (row % 2) * 0.5
    bid = ((row % courses) * per + np.floor(bx) % per).astype(np.int64)
    lx = (bx % 1) * 0.4
    ly = (y * courses % 1) * 0.2
    d = np.minimum(np.minimum(lx, 0.4 - lx), np.minimum(ly, 0.2 - ly))
    joint = smoothstep(0.006, 0.0, d)
    f1, _, _ = n.worley(x, y, 220, jitter=1.0)
    pore = smoothstep(0.18, 0.06, f1) * (n.fbm(x, y, 60, 2) > -0.1)
    peel = n.fbm(x, y, 120, 2)
    tone = n.per_cell(courses * per, -0.025, 0.025)[bid]
    chip = smoothstep(0.62, 0.8, n.fbm(x + 0.3, y, 12, 4)) * smoothstep(0.03, 0.0, d)
    lum = 0.88 + tone + 0.02 * peel - 0.1 * pore - 0.12 * joint + 0.03 * n.fbm(x, y, 3, 4)
    lum = lerp(lum, 0.55 + 0.05 * n.fbm(x, y, 90, 2), chip)
    rust = smoothstep(0.7, 0.9, n.fbm(x * 3, y * 0.4, 6, 4, cy=2))
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.1, 0.84, 0.66], F), (0.5 * rust)[..., None])
    height = 0.0006 * peel - 0.004 * joint * smoothstep(0.0, 0.006, 0.006 - d) - 0.0012 * pore - 0.0008 * chip
    rough = 0.82 + 0.08 * pore + 0.1 * chip
    return {"color": color, "height": height, "rough": rough}


@material("WoodSiding", "Wood", 2.4, "Regular", (232, 230, 222), directional=True, named=True, rnd=2)
def wood_siding(n, x, y, S, tile):
    """Painted lap siding (Coconut Grove cottages, Key Biscayne houses): 15 cm boards, each lapping
    the one below with a shadow line, the wood grain raised under the paint, butt joints, peeling
    paint and nail heads. Boards run along x (the turned copy runs them along y)."""
    boards = 16
    row = np.floor(y * boards)
    rid = (row % boards).astype(np.int64)
    ly = y * boards % 1
    lap = smoothstep(0.0, 0.12, ly) * (1 - smoothstep(0.92, 1.0, ly) * 0.0)
    shadow = smoothstep(0.1, 0.0, ly)
    joints_at = n.per_cell(boards, 0, 1)[rid]
    jx = np.abs(((x + joints_at) % 0.5) - 0.25)
    butt = smoothstep(0.003, 0.0, np.abs(jx - 0.25)) * 0
    grain = n.perlin(x, y, 2, 160) * 0.5 + n.fbm(x * 0.15, y, 4, 3, cy=80) * 0.5
    peel = smoothstep(0.6, 0.82, n.fbm(x, y, 8, 5)) * smoothstep(0.2, 0.6, ly)
    lum = 0.9 + 0.025 * grain + n.per_cell(boards, -0.02, 0.02)[rid] - 0.32 * shadow + 0.02 * n.fbm(x, y, 3, 4)
    lum = lerp(lum, 0.55 + 0.08 * grain, peel)
    nail_x = ((x * 6) % 1) - 0.5
    nail = smoothstep(0.012, 0.006, np.hypot(nail_x / 6 * tile, (ly - 0.85) / boards * tile))
    lum = lum - 0.3 * nail
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.06, 0.95, 0.8], F), peel[..., None])
    height = 0.006 * ly - 0.006 * shadow + 0.0003 * grain - 0.0005 * peel + butt
    rough = 0.7 + 0.15 * peel + 0.04 * grain
    return {"color": color, "height": height, "rough": rough}


@material("GraniteCladding", "Granite", 2.4, "Regular", (120, 118, 116), named=True, rnd=2)
def granite_cladding(n, x, y, S, tile):
    """Polished granite panels (office lobbies, tower bases, monuments): 120 x 60 cm slabs with
    hairline joints, a salt-and-pepper speckle of feldspar, quartz and mica, and a high polish."""
    rows, cols = 4, 2
    rid = (np.floor(y * rows) % rows * cols + np.floor(x * cols) % cols).astype(np.int64)
    lx = (x * cols % 1) * 1.2
    ly = (y * rows % 1) * 0.6
    d = np.minimum(np.minimum(lx, 1.2 - lx), np.minimum(ly, 0.6 - ly))
    joint = smoothstep(0.0025, 0.0, d)
    f1, _, ids = n.worley(x, y, 330, jitter=1.0)
    grain = n.per_cell(330 * 330, 0, 1)[ids]
    crystal = smoothstep(0.55, 0.25, f1)
    dark = (grain < 0.32) * crystal
    light = (grain > 0.82) * crystal
    flow = n.fbm(x * 2, y, 3, 4)
    lum = 0.62 + 0.06 * flow + n.per_cell(rows * cols, -0.04, 0.04)[rid] - 0.42 * dark + 0.3 * light
    lum = lerp(lum, 0.3, joint)
    pink = (grain > 0.55) * (grain < 0.7) * crystal
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.12, 0.95, 0.9], F), (0.6 * pink)[..., None])
    height = -0.002 * joint + 0.00005 * crystal
    rough = 0.12 + 0.05 * dark + 0.4 * joint
    return {"color": color, "height": height, "rough": rough}


@material("PoolTile", "CeramicTiles", 1.2, "Regular", (90, 170, 220), named=True, rnd=2)
def pool_tile(n, x, y, S, tile):
    """Glazed pool and fountain tile: 5 cm mosaic squares in pale grout, each a slightly different
    glaze, with a wet gloss (pools, the plaza's fountain, splash pads)."""
    cells = 24
    i, j = np.floor(x * cells), np.floor(y * cells)
    tid = ((j % cells) * cells + (i % cells)).astype(np.int64)
    lx, ly = x * cells % 1, y * cells % 1
    d = np.minimum(np.minimum(lx, 1 - lx), np.minimum(ly, 1 - ly)) * 0.05
    grout = smoothstep(0.0025, 0.0012, d)
    tone = n.per_cell(cells * cells, -0.08, 0.08)[tid]
    lum = 0.85 + tone + 0.03 * n.fbm(x, y, 30, 3)
    lum = lerp(lum, 1.0, grout)
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.0, 1.0, 1.0], F), grout[..., None])
    height = (1 - grout) * 0.0015 * smoothstep(0.0, 0.004, d)
    rough = lerp(0.08, 0.7, grout)
    return {"color": color, "height": height, "rough": rough}


@material("Terrazzo", "Marble", 1.2, "Organic", (236, 232, 222), named=True, rnd=2)
def terrazzo(n, x, y, S, tile):
    """Miami terrazzo (lobbies, the plaza, deco hotel floors): marble and glass chips of every size
    in a pale cement matrix, brass divider strips in a 60 cm grid, ground and polished."""
    lum = 0.9 + 0.03 * n.fbm(x, y, 8, 4)
    color = gray(lum)
    rough = np.full_like(x, 0.18)
    chips_col = [np.array(c, F) for c in ((0.95, 0.93, 0.88), (0.55, 0.53, 0.5), (0.85, 0.7, 0.55), (0.6, 0.7, 0.72), (0.98, 0.98, 0.98), (0.35, 0.33, 0.32))]
    for cells, size in ((40, 0.32), (110, 0.3), (260, 0.28)):
        f1, _, ids = n.worley(x + cells * 0.001, y, cells, jitter=1.0)
        pick = (n.per_cell(cells * cells, 0, len(chips_col))[ids]).astype(np.int64)
        chip = smoothstep(size, size * 0.8, f1 + 0.08 * n.fbm(x, y, cells * 2, 2))
        palette = np.stack(chips_col)[np.clip(pick, 0, len(chips_col) - 1)]
        color = lerp(color, palette, chip[..., None])
    div = np.minimum(np.abs((x * 2) % 1 - 0.5), np.abs((y * 2) % 1 - 0.5))
    brass = smoothstep(0.004, 0.002, 0.5 - div)
    color = lerp(color, np.array([0.78, 0.62, 0.32], F), brass[..., None])
    height = 0.00005 * n.fbm(x, y, 100, 2)
    rough = rough + 0.15 * brass
    metal = brass
    return {"color": color, "height": height, "rough": rough, "metal": metal}


@material("RoofMembrane", "SmoothPlastic", 6.0, "Regular", (236, 236, 232), named=True, rnd=2)
def roof_membrane(n, x, y, S, tile):
    """A white single-ply flat roof (mid-rises, strip malls, warehouses, garages): 3 m sheets with
    heat-welded laps, wrinkles, dirt washing toward the drains, scuffed walkway pads, patches."""
    sheets = 2
    ly = (y * sheets) % 1
    lap = smoothstep(0.012, 0.0, np.abs(ly - 0.0)) + smoothstep(0.012, 0.0, np.abs(ly - 1.0))
    wrinkle = n.perlin(x, y, 9, 3) * smoothstep(0.2, 0.7, n.fbm(x, y, 2, 3))
    dirt = smoothstep(-0.2, 0.6, n.fbm(x, y, 3, 5)) * 0.5 + smoothstep(0.4, 0.9, n.fbm(x + 0.5, y, 6, 4)) * 0.5
    pond = smoothstep(0.55, 0.8, n.fbm(x + 0.2, y + 0.4, 2, 4))
    pad, _ = _rects(n, x, y, 2, 0.5, size=(0.1, 0.35), soft=0.004)
    patch, _ = _rects(n, x + 0.37, y + 0.11, 3, 0.25, size=(0.08, 0.2), soft=0.003)
    lum = 0.9 - 0.16 * dirt - 0.18 * pond - 0.06 * lap + 0.02 * n.fbm(x, y, 80, 2)
    lum = lerp(lum, 0.62 + 0.05 * n.fbm(x, y, 150, 2), pad)
    lum = lerp(lum, 0.95, patch)
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.0, 0.97, 0.9], F), (0.6 * pond)[..., None])
    height = 0.0015 * wrinkle + 0.002 * lap + 0.003 * pad + 0.001 * patch
    rough = 0.6 + 0.15 * dirt + 0.25 * pad
    return {"color": color, "height": height, "rough": rough}


@material("Gravel", "Pebble", 1.5, "Organic", (170, 166, 158), named=True, rnd=2)
def gravel(n, x, y, S, tile):
    """Loose gravel (roof ballast, rail beds, paths, car park edges): rounded stones from 1 to 4 cm,
    piled on one another, greys and buffs, dust in the gaps."""
    lum = np.full_like(x, 0.35)
    height = np.zeros_like(x)
    color = gray(lum)
    for cells, h, keep in ((26, 0.02, 0.9), (55, 0.012, 0.85), (120, 0.006, 0.8)):
        f1, f2, ids = n.worley(x + cells * 0.0013, y, cells, jitter=1.0)
        stone = smoothstep(0.62, 0.3, f1) * (n.per_cell(cells * cells)[ids] < keep)
        dome = np.sqrt(np.clip(1 - (f1 / 0.62) ** 2, 0, 1))
        tone = n.per_cell(cells * cells, 0.5, 0.95)[ids]
        warm = n.per_cell(cells * cells, 0, 1)[ids]
        tint = np.stack([tone * (1 + 0.08 * warm), tone, tone * (1 - 0.08 * warm)], -1)
        top = h * dome * stone
        over = top > height
        height = np.where(over, top, height)
        shade = 0.75 + 0.25 * dome
        color = np.where(over[..., None], tint * shade[..., None], color)
    rough = np.full_like(x, 0.85)
    return {"color": color, "height": height, "rough": rough}


@material("MetalRoof", "Metal", 2.0, "Regular", (176, 180, 184), directional=True, metal=0.9, named=True, rnd=2)
def metal_roof(n, x, y, S, tile):
    """A standing-seam metal roof (Key Biscayne and Grove houses, sheds, the airport's hangars): seams
    every 45 cm running down the slope, gentle oil-canning in the pans, galvalume sheen, rust at the
    eaves and round the screws. Seams run along y (the turned copy along x)."""
    panels = 4.0 / 0.45 * (tile / 4.0)
    px = (x * panels) % 1
    seam = smoothstep(0.035, 0.0, np.minimum(px, 1 - px))
    can = n.perlin(x, y, int(round(panels)), 3) * (1 - seam)
    spangle = n.fbm(x, y, 140, 2)
    rust = smoothstep(0.62, 0.88, n.fbm(x, y * 0.5, 5, 5))
    lum = 0.8 + 0.06 * can + 0.03 * spangle + 0.12 * seam
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.15, 0.8, 0.55], F), (0.6 * rust)[..., None])
    height = 0.03 * seam * smoothstep(0.0, 0.035, 0.035 - np.minimum(px, 1 - px)) + 0.001 * can
    rough = 0.35 + 0.08 * spangle + 0.35 * rust
    metal = 0.9 - 0.6 * rust
    return {"color": color, "height": height, "rough": rough, "metal": metal}


@material("Mulch", "Ground", 1.5, "Organic", (120, 76, 50), named=True, rnd=2)
def mulch(n, x, y, S, tile):
    """Shredded hardwood mulch (planting beds, tree pits, park borders): long splintered chips in
    reds and browns, piled every which way with dark gaps, the odd fallen leaf."""
    rng = n.rng
    size = S
    color = np.zeros((size, size, 3), F) + np.array([0.2, 0.15, 0.11], F)
    height = np.zeros((size, size), F)
    for layer in range(4):
        count = 2600
        xs, ys, w, idx = T.strokes(rng, size, count, (size * 0.015, size * 0.045), samples=24, taper=False)
        tone = rng.uniform(0.5, 1.0, count)
        red = rng.uniform(0.0, 1.0, count)
        ch = np.stack([tone * (0.8 + 0.15 * red), tone * (0.56 + 0.05 * red), tone * 0.38], -1)[idx]
        wgt, col = T.splat(size, xs, ys, w, ch)
        cov = T.blur(np.clip(wgt, 0, 1), 0.9)
        chip_col = T.blur(col, 0.9) / np.maximum(cov[..., None], 1e-4)
        on = smoothstep(0.12, 0.3, cov)
        color = lerp(color, np.clip(chip_col, 0, 1), on[..., None])
        height = np.maximum(height, (0.004 + 0.001 * layer) * on)
    leaf = smoothstep(0.72, 0.86, n.fbm(x, y, 16, 3))
    color = lerp(color, np.array([0.72, 0.6, 0.3], F), (0.6 * leaf)[..., None])
    rough = np.full((size, size), 0.92, F)
    return {"color": color, "height": height, "rough": rough}


@material("WetSand", "Sand", 4.0, "Organic", (200, 184, 150), named=True, rnd=2)
def wet_sand(n, x, y, S, tile):
    """Wet sand at the water's edge: darker and smoother than the dry beach, faint swash lines and
    ripples left by the last waves, shell bits, bubble holes, a wet sheen."""
    f1, _, _ = n.worley(x, y, 400, jitter=1.0)
    grain = smoothstep(0.5, 0.2, f1)
    warp = 0.3 * n.fbm(x, y, 3, 4)
    wave = np.sin(2 * math.pi * (y * 4 + warp))
    swash = smoothstep(0.96, 1.0, wave) * smoothstep(-0.2, 0.4, n.fbm(x + 0.4, y, 4, 3))
    ripple = np.sin(2 * math.pi * (y * 28 + 2 * warp + 0.4 * n.fbm(x, y, 12, 2)))
    lum = 0.64 + 0.04 * grain + 0.06 * n.fbm(x, y, 5, 4) + 0.07 * swash + 0.015 * ripple
    g1, _, gid = n.worley(x + 0.2, y, 70, jitter=1.0)
    shell = smoothstep(0.08, 0.03, g1) * (n.per_cell(4900)[gid] < 0.18)
    hole = smoothstep(0.025, 0.0, g1) * (n.per_cell(4900)[gid] > 0.92)
    lum = lum + 0.22 * shell - 0.2 * hole
    height = 0.0004 * grain + 0.0008 * swash + 0.0006 * ripple + 0.0008 * shell - 0.001 * hole + 0.003 * n.fbm(x, y, 4, 3)
    rough = 0.3 + 0.15 * swash + 0.12 * grain
    return {"color": gray(lum), "height": height, "rough": rough}


@material("RustySteel", "CorrodedMetal", 1.5, "Organic", (150, 96, 70), named=True, rnd=2)
def rusty_steel(n, x, y, S, tile):
    """Heavy rust over old paint (the port's cranes and bollards, old warehouse doors, ship hulls):
    flaking scale, pitting, islands of the original paint left grey-green, streaks running down."""
    scale = n.fbm(x, y, 20, 5)
    f1, _, ids = n.worley(x, y, 90, jitter=1.0)
    pit = smoothstep(0.2, 0.05, f1) * (n.per_cell(8100)[ids] < 0.4)
    paint = smoothstep(0.35, 0.55, n.fbm(x + 0.3, y, 4, 5))
    streak = smoothstep(0.2, 0.6, n.fbm(x, y * 0.05, 60, 3, cy=3))
    lum = 0.55 + 0.15 * scale - 0.25 * pit + 0.25 * paint - 0.1 * streak
    rust_col = np.stack([0.95 + 0.1 * scale, 0.62 + 0.08 * scale, 0.42 + 0.05 * scale], -1)
    paint_col = np.array([0.82, 0.86, 0.84], F)
    color = tinted(lum, (1, 1, 1)) * lerp(rust_col, paint_col, paint[..., None])
    height = 0.0012 * scale - 0.0015 * pit + 0.0008 * paint
    rough = 0.9 - 0.4 * paint
    metal = 0.15 + 0.6 * paint
    return {"color": color, "height": height, "rough": rough, "metal": metal}


@material("ContainerPaint", "Metal", 2.4, "Regular", (170, 60, 50), directional=True, metal=0.3, named=True, rnd=2)
def container_paint(n, x, y, S, tile):
    """A shipping container's side: trapezoidal corrugations every 28 cm, scuffed and faded paint,
    rust blooming along the crests and in dents, salt staining. Corrugations run along y."""
    waves = tile / 0.28
    p = (x * waves) % 1
    tri = np.clip(np.minimum(p, 1 - p) * 4 - 0.5, -0.5, 0.5) + 0.5
    slope = np.where(p < 0.5, 1.0, -1.0) * (np.abs(np.minimum(p, 1 - p) - 0.25) < 0.125)
    height = 0.03 * tri
    rust = smoothstep(0.5, 0.8, n.fbm(x, y, 6, 5) + 0.25 * tri) + 0.7 * smoothstep(0.7, 0.92, n.fbm(x, y * 0.3, 10, 3))
    rust = np.clip(rust, 0, 1)
    fade = smoothstep(-0.3, 0.6, n.fbm(x + 0.5, y, 2, 4))
    dent = smoothstep(0.65, 0.9, n.fbm(x, y, 3, 3))
    lum = 0.78 + 0.1 * tri - 0.1 * slope + 0.1 * fade - 0.1 * dent + 0.02 * n.fbm(x, y, 80, 2)
    color = gray(lum) * lerp(np.ones(3, F), np.array([0.95, 0.6, 0.4], F), (0.9 * rust)[..., None])
    rough = 0.55 + 0.3 * rust + 0.1 * fade
    metal = 0.3 - 0.25 * rust
    height = height - 0.012 * dent
    return {"color": color, "height": height, "rough": rough, "metal": metal}


@material("MarineConcrete", "Concrete", 2.5, "Organic", (176, 178, 170), named=True, rnd=2)
def marine_concrete(n, x, y, S, tile):
    """Concrete that lives in salt water (seawalls, piers, causeway footings): green-black algae and
    barnacle clusters, white salt crust, rust streaks from the rebar, eroded aggregate."""
    f1, _, _ = n.worley(x, y, 180, jitter=1.0)
    agg = smoothstep(0.45, 0.2, f1)
    algae = smoothstep(-0.1, 0.5, n.fbm(x, y, 3, 5))
    b1, _, bid = n.worley(x + 0.3, y, 60, jitter=0.9)
    cluster = smoothstep(0.1, 0.5, n.fbm(x, y + 0.2, 5, 4))
    barnacle = smoothstep(0.32, 0.1, b1) * cluster
    crater = smoothstep(0.1, 0.04, b1) * cluster
    salt = smoothstep(0.5, 0.8, n.fbm(x + 0.6, y, 4, 4)) * (1 - algae)
    rust = smoothstep(0.65, 0.9, n.fbm(x * 2, y * 0.3, 8, 4, cy=2))
    lum = 0.72 + 0.08 * agg - 0.35 * algae + 0.2 * barnacle - 0.3 * crater + 0.18 * salt
    color = gray(lum)
    color = lerp(color, color * np.array([0.7, 0.85, 0.6], F), algae[..., None])
    color = lerp(color, np.array([0.95, 0.94, 0.9], F) * lum[..., None], (0.6 * barnacle)[..., None])
    color = color * lerp(np.ones(3, F), np.array([1.12, 0.84, 0.64], F), (0.6 * rust)[..., None])
    height = 0.0012 * agg + 0.005 * barnacle - 0.003 * crater
    rough = 0.85 - 0.25 * algae
    return {"color": color, "height": height, "rough": rough}


@material("Hedge", "Grass", 1.0, "Organic", (70, 110, 50), named=True, rnd=2)
def hedge(n, x, y, S, tile):
    """A clipped hedge's face (the suburbs, the Gables, park borders): small glossy leaves packed
    every which way, gaps going dark into the bush, lighter new growth on the clipped surface."""
    color = np.zeros(x.shape + (3,), F) + np.array([0.12, 0.18, 0.08], F)
    height = np.zeros_like(x)
    rough = np.full_like(x, 0.7)
    for cells, h in ((70, 0.02), (130, 0.016), (230, 0.012)):
        f1, f2, ids = n.worley(x + cells * 0.002, y, cells, jitter=1.0)
        ang = n.per_cell(cells * cells, 0, math.pi)[ids]
        # an elliptical leaf: distance to the feature point squashed along a per-leaf angle
        ex = np.cos(ang)
        leaf = smoothstep(0.55, 0.3, f1 * (1 + 0.6 * np.abs(ex)))
        tone = n.per_cell(cells * cells, 0.55, 1.0)[ids]
        new_growth = n.per_cell(cells * cells)[ids] > 0.85
        c = np.stack([0.3 * tone + 0.25 * new_growth, 0.55 * tone + 0.2 * new_growth, 0.22 * tone], -1)
        top = h * leaf * (0.6 + 0.4 * tone)
        over = top > height
        height = np.where(over, top, height)
        color = np.where(over[..., None], c, color)
        rough = np.where(over, 0.45, rough)
    return {"color": color, "height": height, "rough": rough}


@material("PlanksWeathered", "WoodPlanks", 2.4, "Regular", (170, 166, 156), directional=True, named=True, rnd=2)
def planks_weathered(n, x, y, S, tile):
    """Weathered deck boards (marina docks, the Everglades boardwalk, beach walkovers): 14 cm boards
    gone silver-grey in the sun, open grain, gaps between them, rows of nails, the odd darker
    replacement board. Boards run along x."""
    boards = int(round(tile / 0.14))
    row = np.floor(y * boards)
    rid = (row % boards).astype(np.int64)
    ly = y * boards % 1
    gap = smoothstep(0.06, 0.02, np.minimum(ly, 1 - ly))
    offset = n.per_cell(boards, 0, 1)[rid]
    bx = (x + offset) % 1
    butt = smoothstep(0.004, 0.0, np.abs(bx - 0.5) - 0.0)
    grain = n.perlin(x, y, 3, boards * 12) * 0.5 + n.fbm(x * 0.2, y, 6, 3, cy=boards * 6) * 0.5
    check = smoothstep(0.75, 0.9, n.fbm(x * 0.3, y, 10, 3, cy=boards * 8))
    newer = n.per_cell(boards)[rid] < 0.1
    tone = n.per_cell(boards, -0.06, 0.06)[rid]
    lum = 0.78 + tone + 0.07 * grain - 0.2 * check - 0.12 * newer
    lum = lerp(lum, 0.15, gap)
    lum = lerp(lum, 0.3, butt)
    nx = (bx * 4) % 1
    nail = smoothstep(0.03, 0.015, np.hypot((nx - 0.5) * 0.6, (ly - 0.5) * 0.14)) * 0
    color = gray(lum) * lerp(np.ones(3, F), np.array([1.08, 0.96, 0.82], F), (newer * 0.8)[..., None])
    height = (1 - gap) * (0.002 + 0.0006 * grain) - 0.003 * gap - 0.0008 * check
    rough = 0.9 - 0.1 * newer + 0.05 * check
    return {"color": color, "height": height, "rough": rough}


@material("TactilePaving", "SmoothPlastic", 0.6, "Regular", (232, 196, 40), named=True, rnd=2)
def tactile_paving(n, x, y, S, tile):
    """Truncated-dome warning pads at the kerb ramps (the yellow ones every crossing has): domes on a
    6 cm grid in a moulded panel, scuffed and dirty where feet and wheels go."""
    cells = 10
    fx = (x * cells) % 1 - 0.5
    fy = (y * cells) % 1 - 0.5
    r = np.hypot(fx, fy)
    dome = smoothstep(0.32, 0.22, r)
    cap = np.sqrt(np.clip(1 - (r / 0.32) ** 2, 0, 1))
    dirt = smoothstep(-0.2, 0.6, n.fbm(x, y, 3, 4))
    lum = 0.86 - 0.18 * dirt * (1 - dome) - 0.08 * dirt + 0.04 * cap * dome
    panel = np.minimum(np.minimum(x, 1 - x), np.minimum(y, 1 - y))
    seam = smoothstep(0.006, 0.0, panel)
    lum = lum - 0.25 * seam
    height = 0.005 * dome * np.minimum(cap * 1.4, 1.0) - 0.001 * seam
    rough = 0.55 + 0.25 * dirt - 0.15 * dome
    return {"color": gray(lum), "height": height, "rough": rough}


# ---------------------------------------------------------------------------- livery patterns
# Bike paint patterns (Shared/Livery), named "Pattern<Name>" so their variants are
# "RealPattern<Name>". Most are luminance only, so the coat's colour sets the hue; woodland camo,
# splatter and flames carry their own colours (they show true on a white coat).


def _window(size, cx, cy, r):
    """The pixels within `r` of (cx, cy), wrapping: (row/col index, dx, dy from the centre)."""
    r = int(math.ceil(r)) + 1
    xs = np.arange(int(cx) - r, int(cx) + r + 1)
    ys = np.arange(int(cy) - r, int(cy) + r + 1)
    dx = (xs + 0.5 - cx)[None, :].astype(F)
    dy = (ys + 0.5 - cy)[:, None].astype(F)
    return np.ix_(ys % size, xs % size), dx, dy


@material("PatternCarbon", "Plastic", 0.2, "Regular", (60, 60, 64), livery=True)
def pattern_carbon(n, x, y, S, tile):
    k = 40  # 2x2 twill, 5 mm tows
    i, j = np.floor(x * k), np.floor(y * k)
    warp = ((i + j) % 4) < 2
    fx, fy = x * k % 1, y * k % 1
    across = np.where(warp, fx, fy)
    bulge = np.sin(math.pi * across)
    fibre = np.where(warp, n.perlin(x, y, 640, 16), n.perlin(x, y, 16, 640))
    lum = np.where(warp, 0.46, 0.25) + 0.2 * bulge ** 2 + 0.04 * fibre - 0.14 * (1 - bulge) ** 6
    return {"color": gray(lum), "height": 0.00018 * bulge, "rough": 0.16 + 0.06 * (1 - bulge)}


@material("PatternForged", "Plastic", 0.25, "Organic", (60, 60, 64), livery=True)
def pattern_forged(n, x, y, S, tile):
    rng = np.random.default_rng(31)
    lum = 0.2 + 0.03 * n.fbm(x, y, 20, 3)
    height = np.zeros_like(x)
    px = S / tile
    for _ in range(2600):
        cx, cy = rng.uniform(0, S, 2)
        length = rng.uniform(0.012, 0.032) * px
        width = rng.uniform(0.003, 0.009) * px
        a = rng.uniform(0, math.pi)
        idx, dx, dy = _window(S, cx, cy, length / 2)
        u = dx * math.cos(a) + dy * math.sin(a)
        v = -dx * math.sin(a) + dy * math.cos(a)
        ragged = 1 - 0.25 * np.abs(np.sin(u * 0.9 + a * 7))
        inside = (np.abs(u) < length / 2 * ragged) & (np.abs(v) < width / 2)
        # the flakes catch the light by the way their fibres run
        sheen = 0.14 + 0.46 * abs(math.cos(2 * (a - 0.6))) ** 2 + rng.uniform(-0.04, 0.04)
        lum[idx] = np.where(inside, sheen + 0.03 * np.sin(v * 2.5), lum[idx])
        height[idx] = np.where(inside, height[idx] + 0.00003, height[idx])
    return {"color": gray(lum), "height": height, "rough": 0.18 + 0.04 * n.fbm(x, y, 12, 2)}


@material("PatternBrushed", "Metal", 0.3, "Regular", (200, 202, 206), metal=1.0, livery=True)
def pattern_brushed(n, x, y, S, tile):
    streak = 0.5 * n.perlin(x, y, 2, 520) + 0.3 * n.perlin(x, y, 4, 1000) + 0.2 * n.perlin(x, y, 1, 260)
    lum = 0.84 + 0.07 * streak + 0.02 * n.fbm(x, y, 6, 3)
    return {"color": gray(lum), "height": 0.00002 * streak, "rough": 0.3 + 0.08 * streak}


@material("PatternCamo", "Plastic", 0.6, "Organic", (200, 200, 200), livery=True)
def pattern_camo(n, x, y, S, tile):
    # woodland: khaki ground, green, brown and black blobs
    khaki, green, brown, black = rgb(0.86, 0.8, 0.62), rgb(0.36, 0.45, 0.26), rgb(0.46, 0.34, 0.22), rgb(0.1, 0.1, 0.09)
    a = n.fbm(x, y, 5, 4)
    b = n.fbm(x, y, 6, 4)
    c = n.fbm(x, y, 7, 4)
    color = np.broadcast_to(khaki, x.shape + (3,)).copy()
    for field, level, tone in ((a, 0.02, green), (b, 0.12, brown), (c, 0.24, black)):
        m = smoothstep(level, level + 0.015, field)[..., None]
        color = color * (1 - m) + tone * m
    return {"color": color, "height": 0.00002 * a, "rough": 0.55 + 0.05 * n.fbm(x, y, 20, 2)}


@material("PatternDigiCamo", "Plastic", 0.5, "Regular", (200, 200, 200), livery=True)
def pattern_digicamo(n, x, y, S, tile):
    k = 48  # 10 mm pixels
    qx, qy = (np.floor(x * k) + 0.5) / k, (np.floor(y * k) + 0.5) / k
    lum = np.full(x.shape, 0.96, F)
    for cells, level, tone in ((5, 0.0, 0.7), (6, 0.12, 0.46), (8, 0.26, 0.24)):
        field = n.fbm(qx, qy, cells, 4)
        lum = np.where(field > level, tone, lum)
    return {"color": gray(lum), "height": np.zeros_like(x), "rough": 0.6}


@material("PatternHex", "Plastic", 0.2, "Regular", (70, 70, 74), livery=True)
def pattern_hex(n, x, y, S, tile):
    cols = 24  # 8 mm cells
    rows = 14  # (rows * sqrt 3 ~ cols, so the honeycomb tiles with a 1% stretch)
    px, py = x * cols, y * rows * math.sqrt(3)
    best = np.full(x.shape, np.inf, F)
    rel_x = np.zeros_like(x)
    rel_y = np.zeros_like(x)
    for ox, oy in ((0.0, 0.0), (0.5, math.sqrt(3) / 2)):
        cx = np.round(px - ox) + ox
        cy = np.round((py - oy) / math.sqrt(3)) * math.sqrt(3) + oy
        d = np.hypot(px - cx, py - cy)
        closer = d < best
        best = np.where(closer, d, best)
        rel_x = np.where(closer, px - cx, rel_x)
        rel_y = np.where(closer, py - cy, rel_y)
    hexd = np.maximum(np.abs(rel_x), np.maximum(np.abs(0.5 * rel_x + 0.866 * rel_y), np.abs(-0.5 * rel_x + 0.866 * rel_y)))
    wall = smoothstep(0.43, 0.49, hexd)
    dome = 1 - (hexd / 0.5) ** 2
    lum = 0.3 + 0.2 * dome - 0.2 * wall + 0.12 * smoothstep(0.1, 0.4, rel_y * -0.8 + rel_x * 0.3)
    return {"color": gray(lum), "height": 0.0002 * dome - 0.0002 * wall, "rough": 0.22 + 0.2 * wall}


@material("PatternSnake", "Plastic", 0.3, "Organic", (200, 196, 180), livery=True)
def pattern_snake(n, x, y, S, tile):
    f1, f2, ids = n.worley(x, y, 36, jitter=0.3)
    edge = smoothstep(0.0, 0.14, f2 - f1)
    dome = np.clip(1 - f1 * 1.4, 0, 1)
    b1, _, _ = n.worley(x + 0.02 * n.fbm(x, y, 8, 3), y, 7, jitter=0.85)
    blotch = smoothstep(0.36, 0.3, b1)
    ring = smoothstep(0.46, 0.4, b1) - blotch
    lum = 0.9 + n.per_cell(36 * 36, -0.06, 0.04)[ids] - 0.62 * ring - 0.3 * blotch
    lum = lum * (0.5 + 0.5 * edge)
    return {"color": gray(lum), "height": 0.00035 * dome * edge, "rough": 0.42 - 0.12 * dome}


@material("PatternTiger", "Plastic", 0.6, "Organic", (230, 140, 40), livery=True)
def pattern_tiger(n, x, y, S, tile):
    warp = 0.13 * n.fbm(x, y, 2, 4) + 0.03 * n.fbm(x, y, 6, 3)
    s = (x * 6 + y * 1 + warp * 6) % 1
    # stripes swell and taper to points, and break up into forks
    width = np.clip(0.16 + 0.32 * n.fbm(x, y, 3, 3, cy=7), 0, 0.5)
    stripe = smoothstep(width / 2 + 0.01, width / 2 - 0.01, np.abs(s - 0.5))
    stripe = stripe * smoothstep(-0.2, -0.17, n.fbm(x, y, 3, 3, cy=9))
    lum = 0.95 - 0.88 * stripe
    return {"color": gray(lum), "height": np.zeros_like(x), "rough": 0.4}


@material("PatternChecker", "Plastic", 0.32, "Regular", (240, 240, 240), livery=True)
def pattern_checker(n, x, y, S, tile):
    k = 8  # 40 mm squares
    fx, fy = x * k % 1, y * k % 1
    edge = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
    sq = ((np.floor(x * k) + np.floor(y * k)) % 2).astype(F)
    lum = np.where(sq > 0.5, 0.95, 0.06) + 0.03 * smoothstep(0.004, 0.0, edge)
    return {"color": gray(lum), "height": np.zeros_like(x), "rough": 0.3}


@material("PatternSplatter", "Plastic", 0.5, "Organic", (240, 240, 240), livery=True)
def pattern_splatter(n, x, y, S, tile):
    rng = np.random.default_rng(57)
    palette = [rgb(0.1, 0.1, 0.1), rgb(0.0, 0.72, 0.95), rgb(0.95, 0.12, 0.55), rgb(1.0, 0.84, 0.0), rgb(0.3, 0.88, 0.25)]
    color = np.full(x.shape + (3,), 0.95, F)
    height = np.zeros_like(x)
    px = S / tile
    for _ in range(70):
        tone = palette[rng.integers(len(palette))]
        cx, cy = rng.uniform(0, S, 2)
        R = rng.uniform(0.006, 0.022) * px
        drops = [(cx, cy, R, rng.uniform(0, 6.28), rng.integers(5, 9))]
        for _ in range(rng.integers(6, 16)):
            a, d = rng.uniform(0, 2 * math.pi), rng.uniform(1.2, 2.8) * R
            drops.append((cx + math.cos(a) * d, cy + math.sin(a) * d, R * rng.uniform(0.08, 0.28), 0.0, 0))
        for dx0, dy0, r, phase, lobes in drops:
            idx, dx, dy = _window(S, dx0, dy0, r * 1.4)
            ang = np.arctan2(dy, dx)
            edge = r * (1 + (0.28 * np.sin(lobes * ang + phase) + 0.1 * np.sin(2.3 * lobes * ang) if lobes else 0))
            inside = smoothstep(edge + 1.0, edge - 1.0, np.hypot(dx, dy))[..., None]
            color[idx] = color[idx] * (1 - inside) + tone * inside
            height[idx] = height[idx] + 0.00004 * inside[..., 0]
    return {"color": color, "height": height, "rough": 0.35}


@material("PatternFlames", "Plastic", 0.6, "Regular", (240, 240, 240), livery=True)
def pattern_flames(n, x, y, S, tile):
    # hot-rod flames licking along +x on a dark ground (a white coat shows them true)
    rng = np.random.default_rng(13)
    d = np.full(x.shape, -1.0, F)
    rows, per_row = 3, 7
    for r in range(rows):
        yc = (r + 0.5) / rows
        for t in range(per_row):
            x0 = t / per_row + rng.uniform(-0.03, 0.03) + r * 0.11
            length = rng.uniform(0.22, 0.42)
            u = ((x - x0) % 1) / length
            amp = rng.uniform(0.04, 0.08) * rng.choice([-1, 1])
            # each tongue curls one way then flicks back at its tip
            centre = yc + rng.uniform(-0.05, 0.05) + amp * (np.sin(math.pi * u) * 0.7 + np.sin(2.6 * math.pi * u) * 0.3 * u)
            hw = 0.05 * np.clip(1 - u, 0, 1) ** 1.1 * np.clip(u * 5, 0, 1) ** 0.5
            dist = np.abs(((y - centre + 0.5) % 1) - 0.5)
            d = np.maximum(d, np.where(u < 1, hw - dist, -1.0))
    dark, outline, red, orange, yellow = rgb(0.1, 0.1, 0.1), rgb(0.3, 0.02, 0.02), rgb(0.92, 0.12, 0.05), rgb(1.0, 0.46, 0.05), rgb(1.0, 0.86, 0.22)
    color = np.broadcast_to(dark, x.shape + (3,)).copy()
    for edge, tone in ((0.0, outline), (0.004, red), (0.012, orange), (0.024, yellow)):
        m = smoothstep(edge, edge + 0.002, d)[..., None]
        color = color * (1 - m) + tone * m
    inside = smoothstep(0.0, 0.002, d)
    return {"color": color, "height": 0.00003 * inside, "rough": 0.3 - 0.1 * inside}


@material("PatternQuilted", "Leather", 0.2, "Regular", (40, 36, 34), livery=True)
def pattern_quilted(n, x, y, S, tile):
    k = 5  # 40 mm diamonds
    u, v = (x + y) * k, (x - y) * k
    fu, fv = u % 1, v % 1
    e = np.minimum(np.minimum(fu, 1 - fu), np.minimum(fv, 1 - fv))
    pillow = smoothstep(0.0, 0.3, e)
    seam = smoothstep(0.035, 0.0, e)
    stitch = smoothstep(0.014, 0.0, np.abs(e - 0.06)) * (np.sin(2 * math.pi * (u + v) * 9) > 0.1)
    f1, f2, _ = n.worley(x, y, 60, jitter=1.0)
    pebble = np.clip(f2 - f1, 0, 1) ** 0.5
    lum = 0.74 + 0.16 * pillow - 0.42 * seam + 0.2 * stitch + 0.04 * pebble
    height = 0.004 * pillow - 0.001 * seam + 0.0003 * pebble + 0.0003 * stitch
    return {"color": gray(lum), "height": height, "rough": 0.58 - 0.1 * pillow + 0.1 * seam}


# ---------------------------------------------------------------------------- output


def turned(maps):
    """The same maps a quarter turn round (for materials whose direction may need flipping)."""
    out = {}
    for key, img in maps.items():
        if key == "normal":
            r = np.rot90(img, 1).copy()
            nx, ny = r[..., 0] * 2 - 1, r[..., 1] * 2 - 1
            r[..., 0] = (-ny) * 0.5 + 0.5
            r[..., 1] = nx * 0.5 + 0.5
            out[key] = r
        else:
            out[key] = np.rot90(img, 1).copy() if isinstance(img, np.ndarray) else img
    return out


def finish(spec, raw):
    size = spec["Size"]
    color = np.clip(np.asarray(raw["color"], F), 0, None)
    # keep the brightest channel under 1 (8-bit), but don't brighten a dark map
    top = float(np.percentile(color.max(axis=-1), 99.7))
    if top > 1.0:
        color = color / top
    rough = np.clip(np.asarray(raw["rough"], F) * np.ones((size, size), F), 0.02, 1.0)
    normal = T.normal_map(np.asarray(raw["height"], F) * np.ones((size, size), F), spec["Tile"], 1.0)
    maps = {"color": np.clip(color, 0, 1), "normal": normal, "rough": rough}
    if "metal" in raw:
        maps["metal"] = np.clip(np.asarray(raw["metal"], F) * np.ones((size, size), F), 0, 1)
    return maps


def write(name, maps, entry):
    files = {}
    for key, label, q in (("color", "Color", 92), ("normal", "Normal", 95), ("rough", "Roughness", 90), ("metal", "Metalness", 90)):
        if key in maps:
            fname = f"{name}_{label}.jpg"
            T.save_image(os.path.join(OUT, fname), maps[key], quality=q)
            files[label] = fname
    if "metal" not in maps and entry["Metal"] is not None:
        files["Metalness"] = "Shared_MetalFull.png" if entry["Metal"] >= 0.5 else None
    return {k: v for k, v in files.items() if v}


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1].split(",")) if len(sys.argv) > 1 else None
    path = os.path.join(OUT, "manifest.json")
    manifest = {"Materials": []}
    if only and os.path.exists(path):
        with open(path) as f:
            manifest = json.load(f)
    # a tiny all-white map for materials that are metal all over
    T.save_image(os.path.join(OUT, "Shared_MetalFull.png"), np.ones((8, 8), F))
    done = {m["Name"]: m for m in manifest["Materials"]}
    for spec in MATERIALS:
        if only and spec["Name"] not in only:
            continue
        t0 = time.time()
        size = spec["Size"]
        x, y = T.grid(size)
        n = T.Noise(spec["Seed"])
        maps = finish(spec, spec["Fn"](n, x, y, size, spec["Tile"]))
        entry = {k: spec[k] for k in ("Name", "Base", "Tile", "Pattern", "Tint", "Size", "Directional", "Livery", "Named", "Round")}
        entry["Maps"] = write(spec["Name"], maps, spec)
        done[spec["Name"]] = entry
        if spec["Directional"]:
            rot = dict(entry)
            rot["Name"] = spec["Name"] + "90"
            rot["Turned"] = True
            rot["Maps"] = write(rot["Name"], turned(maps), spec)
            done[rot["Name"]] = rot
        stats = maps["color"].mean(axis=(0, 1))
        print(f"{spec['Name']:<14} {size}px  colour mean {stats[0]:.2f},{stats[1]:.2f},{stats[2]:.2f}  rough {maps['rough'].mean():.2f}  {time.time() - t0:.1f}s")
    order = [m["Name"] for m in MATERIALS]
    ordered = []
    for name in order:
        if name in done:
            ordered.append(done[name])
        if name + "90" in done:
            ordered.append(done[name + "90"])
    manifest["Materials"] = ordered
    with open(path, "w") as f:
        json.dump(manifest, f, indent=1)
    print("wrote", path)


if __name__ == "__main__":
    main()
