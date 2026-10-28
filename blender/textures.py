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


def material(name, base, tile, pattern, tint, size=1024, directional=False, metal=None, seed=None):
    """Register a generator: it returns colour (H, W, 3), height (m), roughness and optionally
    metalness (H, W) or a constant via `metal`."""

    def wrap(fn):
        MATERIALS.append({"Name": name, "Base": base, "Tile": tile, "Pattern": pattern, "Tint": tint, "Size": size, "Directional": directional, "Metal": metal, "Seed": seed or (zlib.crc32(name.encode()) % 100000), "Fn": fn})
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
        entry = {k: spec[k] for k in ("Name", "Base", "Tile", "Pattern", "Tint", "Size", "Directional")}
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
