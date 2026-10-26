"""
City kit: detailed meshes for the city's most repeated pieces, built into Vehicles.fbx alongside the
vehicles (one import for the owner) as "Kit_*" entries. The server swaps them in for the part-built
placeholders (src/server/CityKit.luau); without the import the city keeps its parts.

Each kit is built in its own space, in studs (the city's units), placed so that it maps onto its
placeholder: windows onto the "WindowFrame" part (a 5.7 x 7.2 x 0.3 reference box at the origin,
the street side towards Blender +Y), trees and lamps onto their model's bounding box (base at z = 0).

Slots: "Paint" takes the placeholder's own colour (a window frame's, a tree's leaves), the rest are
fixed (MeshKit.Slots): Stone (sills, lintels), Bark, Dark / Black / Metal.
"""

import math
import random

from mathutils import Vector

import meshkit as K

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def window():
    """A classical window surround for a 5.7 x 7.2 frame: casing, recessed sash with glazing bars,
    a moulded stone sill with a drip, a lintel with a keystone."""
    K.vehicle("Kit_Window")
    put = lambda slot, bm: K.put("Main", slot, bm)  # noqa: E731
    W, H = 5.7, 7.2
    # casing: a moulded ring standing proud of the wall (Blender +Y is out of the wall)
    cas = 0.42
    for (cx, cz, sx, sz) in ((0, H / 2 - cas / 2, W, cas), (0, -H / 2 + cas / 2, W, cas), (-W / 2 + cas / 2, 0, cas, H - 2 * cas), (W / 2 - cas / 2, 0, cas, H - 2 * cas)):
        put("Paint", K.rbox(Vector((cx, 0.12, cz)), (sx, 0.34, sz)))
        put("Paint", K.rbox(Vector((cx, 0.3, cz)), (sx * (0.9 if sx > sz else 1) + (0 if sx > sz else -0.12), 0.06, sz * (1 if sx > sz else 0.94) + (-0.12 if sx > sz else 0))))
    # the sash, set back into the reveal, and its glazing bars (two over two)
    iw, ih = W - 2 * cas, H - 2 * cas
    sash = 0.16
    for (cx, cz, sx, sz) in ((0, ih / 2 - sash / 2, iw, sash), (0, -ih / 2 + sash / 2, iw, sash), (-iw / 2 + sash / 2, 0, sash, ih), (iw / 2 - sash / 2, 0, sash, ih), (0, -0.25, iw, sash * 1.1)):
        put("Paint", K.rbox(Vector((cx, 0.02, cz)), (sx, 0.12, sz)))
    put("Paint", K.rbox(Vector((0, 0.0, 0)), (0.08, 0.07, ih)))
    for z in (ih / 4 - 0.1, -ih / 4 - 0.35):
        put("Paint", K.rbox(Vector((0, 0.0, z)), (iw, 0.07, 0.08)))
    # stone sill with a moulded nose and a drip groove, on two corbels
    sill_z = -H / 2 - 0.12
    put("Stone", _sill(W, sill_z))
    for sx in (-1, 1):
        put("Stone", K.rbox(Vector((sx * (W / 2 + 0.1), 0.35, sill_z - 0.45)), (0.4, 0.45, 0.6)))
    # lintel: a flat arch of voussoirs with a keystone
    lz = H / 2 + 0.38
    put("Stone", K.rbox(Vector((0, 0.18, lz)), (W + 0.9, 0.4, 0.62)))
    put("Stone", K.rbox(Vector((0, 0.36, lz + 0.26)), (W + 1.1, 0.12, 0.12)))
    put("Stone", _keystone(lz))


def _sill(W, z):
    outline = [(-0.05, 0.12), (0.6, 0.08), (0.72, 0.0), (0.68, -0.1), (0.52, -0.13), (0.48, -0.19), (-0.05, -0.21)]
    bm = K.side_prism([(p[0], p[1] + z) for p in outline], -W / 2 - 0.45, W / 2 + 0.45)
    return bm


def _keystone(lz):
    """A keystone tapering wider to the top, standing proud of the lintel."""
    bm = K.prism([(-0.36, -0.36), (0.36, -0.36), (0.46, 0.46), (-0.46, 0.46)], 0.58, Vector((0, 0.02, lz)), X, Z, Y)
    return bm


def tree(kind, seed):
    """A street tree: a tapering trunk with a root flare, real branching, clustered foliage."""
    K.vehicle(f"Kit_Tree_{kind}")
    rng = random.Random(seed)
    bark = "Birch" if kind == "Birch" else "Bark"
    trunk_h = {"Broadleaf": 9.0, "Birch": 11.0, "Conifer": 7.0}[kind]
    put = lambda slot, bm: K.put("Main", slot, bm)  # noqa: E731
    # trunk: tapering, slightly leaning, with a flared base and root buttresses
    base_r = {"Broadleaf": 0.75, "Birch": 0.45, "Conifer": 0.5}[kind]
    pts = [Vector((0, 0, 0)), Vector((0.08, 0.05, trunk_h * 0.35)), Vector((-0.05, 0.1, trunk_h * 0.7)), Vector((0.05, 0.02, trunk_h))]
    put(bark, K.lathe(Vector((0, 0, 0)), Z, [(0, base_r * 1.9), (0.25, base_r * 1.35), (0.7, base_r * 1.08), (1.4, base_r)], 9))
    put(bark, K.sweep(pts, base_r * 0.92, 8, samples=3))
    put(bark, K.cyl(pts[-1], pts[-1] + Z * (2.5 if kind != "Conifer" else 7.0), base_r * 0.75, base_r * 0.25, 7))
    for i in range(5 if kind != "Conifer" else 0):
        a = 2 * math.pi * i / 5 + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        put(bark, K.sweep([d * base_r * 0.6 + Z * 0.9, d * base_r * 1.5 + Z * 0.25, d * base_r * 2.3 - Z * 0.05], base_r * 0.28, 5, samples=2))
    if kind == "Birch":
        # the dark bands on white bark
        for i in range(9):
            z = 1.2 + i * 1.05
            put("Dark", K.torus(Vector((0, 0, z)), Z, base_r * 0.92, 0.06, 9, 3, squash=0.4))
    if kind == "Conifer":
        # whorls of drooping boughs, each a flat spray of needle clumps, narrowing to a spire
        tiers = 6
        for t in range(tiers):
            z = trunk_h * 0.55 + t * 1.5
            r = 4.6 * (1 - t / (tiers + 0.6))
            for i in range(7):
                a = 2 * math.pi * i / 7 + t * 0.45
                d = Vector((math.cos(a), math.sin(a), 0))
                tip = d * r + Z * (z - 0.9)
                put(bark, K.cyl(Vector((0, 0, z)), tip, 0.09, 0.04, 4))
                c = Vector((0, 0, z)) * 0.3 + tip * 0.7
                put("Paint", _clump(c, 1.6 * (1.0 - t * 0.06), rng, flat=0.4))
        put("Paint", _clump(Vector((0, 0, trunk_h * 0.55 + tiers * 1.5 + 0.4)), 0.9, rng, flat=1.6))
        return
    # broadleaf and birch: limbs forking into branches, foliage clustered at their ends
    crown_z = trunk_h + (2.5 if kind == "Broadleaf" else 3.5)
    spread = 4.8 if kind == "Broadleaf" else 2.8
    tips = []
    limbs = 5 if kind == "Broadleaf" else 4
    for i in range(limbs):
        a = 2 * math.pi * i / limbs + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), 0))
        start = Vector((0, 0, trunk_h * rng.uniform(0.62, 0.85)))
        mid = start + d * spread * 0.45 + Z * 2.0
        end = start + d * spread * 0.85 + Z * (3.8 if kind == "Broadleaf" else 4.8)
        put(bark, K.sweep([start, mid, end], base_r * 0.38, 6, samples=3))
        tips.append(end)
        for s in (-1, 1):
            side = Vector((-d.y, d.x, 0)) * s
            twig = mid + (end - mid) * 0.4
            twig_end = twig + side * spread * 0.35 + d * 0.6 + Z * 1.5
            put(bark, K.cyl(twig, twig_end, base_r * 0.16, base_r * 0.08, 5))
            tips.append(twig_end)
    # foliage: clumps round each branch end, and a crown filling the middle
    for n, tip in enumerate(tips):
        for _ in range(2 if n % 3 == 0 else 1):
            c = tip + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.4, 0.9))) * (1.0 if kind == "Broadleaf" else 0.7)
            put("Paint", _clump(c, rng.uniform(1.5, 2.2) * (1 if kind == "Broadleaf" else 0.75), rng))
    for _ in range(5 if kind == "Broadleaf" else 3):
        c = Vector((rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5), crown_z + rng.uniform(0, 2.5)))
        put("Paint", _clump(c, rng.uniform(2.0, 2.6) * (1 if kind == "Broadleaf" else 0.7), rng))


def _clump(center, r, rng, flat=0.8):
    """A clump of leaves: a lumpy, slightly flattened ball."""
    bm = K.sphere(Vector((0, 0, 0)), r, 7, 5)
    phase = rng.uniform(0, 6.28)

    def lump(co):
        n = co.normalized() if co.length > 1e-6 else Z
        bump = 0.18 * math.sin(co.x * 3.1 / r + phase) * math.cos(co.y * 2.7 / r - phase) + 0.12 * math.sin(co.z * 4.3 / r + phase * 0.5)
        return n * (bump * r) + Vector((0, 0, co.z * (flat - 1)))

    K.displace(bm, lump)
    K.displace(bm, lambda co: center)
    return bm


def lamp():
    """A Victorian street lamp: moulded base, fluted column with collars, a lantern cage round the
    globe (the globe itself stays a part, for the night glow), a crown and finial."""
    K.vehicle("Kit_Lamp")
    put = lambda slot, bm: K.put("Main", slot, bm)  # noqa: E731
    o = Vector((0, 0, 0))
    put("Black", K.lathe(o, Z, [(0, 0.85), (0.25, 0.85), (0.3, 0.72), (0.55, 0.7), (0.62, 0.6), (1.3, 0.52), (1.38, 0.6), (1.48, 0.6), (1.56, 0.44), (1.62, 0.4), (1.62, 0)], 12))
    # fluted column: a shaft with sixteen raised ribs
    put("Black", K.cyl(o + Z * 1.6, o + Z * 12.4, 0.3, 0.26, 12))
    for i in range(8):
        a = 2 * math.pi * i / 8
        d = Vector((math.cos(a), math.sin(a), 0))
        put("Black", K.cyl(o + Z * 2.0 + d * 0.29, o + Z * 12.0 + d * 0.255, 0.035, 0.03, 4))
    for z in (2.0, 4.5, 9.0, 12.4):
        put("Black", K.torus(o + Z * z, Z, 0.32, 0.09, 12, 5))
    # the lantern: a capital, four thin posts round the globe, a roof, the finial
    put("Black", K.lathe(o + Z * 12.4, Z, [(0, 0.3), (0.3, 0.42), (0.5, 0.82), (0.75, 0.82), (0.8, 0)], 12))
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        put("Black", K.sweep([o + Z * 13.15 + d * 0.75, o + Z * 13.9 + d * 1.15, o + Z * 14.9 + d * 1.0], 0.04, 4, samples=3))
    put("Black", K.lathe(o + Z * 14.95, Z, [(0, 1.05), (0.08, 1.12), (0.12, 0.95), (0.4, 0.45), (0.5, 0.3), (0.55, 0)], 12))
    put("Black", K.sphere(o + Z * 15.62, 0.17, 8, 5))
    put("Black", K.cyl(o + Z * 15.45, o + Z * 15.62, 0.06, 0.06, 8))


def build_all():
    window()
    tree("Broadleaf", 11)
    tree("Birch", 23)
    tree("Conifer", 37)
    lamp()
