"""
Vegetation kits for the realism pack: Miami's trees as textured meshes, in real metres (Blender:
X right, Y back, Z up), standing on the origin. CityKit fits each to its part-built placeholder
(by height, uniformly) and turns it to the placeholder's lean.

  Kit_Palm_Coconut  a leaning, ringed trunk, ~16 drooping fronds, dead fronds, coconuts
  Kit_Palm_Royal    a straight pale trunk swelling mid-height, a green crownshaft, arching fronds
  Kit_Tree_Oak      a live oak: a short trunk, wide spreading limbs, glossy leaf clusters
  Kit_Tree_OakTall  a younger, more upright oak (the "Birch" placeholders)
  Kit_Tree_Pine     a slash pine: tall bare trunk, an open crown of needle tufts

The detail pass's plants (ROUND2: written on their own, with their images, to Plants.fbx):

  Kit_Palm_Sabal          a cabbage palm: a booted trunk, a round crown of costapalmate fans
  Kit_Palm_Date           a Canary Island date palm: a thick scarred trunk, a dense ball of stiff
                          fronds, a knob of old leaf bases, hanging dates
  Kit_Tree_Poinciana      a royal poinciana: low spreading limbs under a flat umbrella of feathery
                          leaves and scarlet flowers, seed pods hanging
  Kit_Shrub_Hibiscus      a hibiscus shrub in flower
  Kit_Shrub_Croton        a croton: a rounded clump of coloured leaves
  Kit_Shrub_Bougainvillea a mound of arching canes in magenta bracts
  Kit_Shrub_SeaGrape      a sea grape: crooked low trunks, a lumpy crown of big round leaves
  Kit_Shrub_Palmetto      a saw palmetto clump: creeping trunks, upright silver-green fans
  Kit_Fern                a sword fern: arching fronds from the ground
  Kit_Grass_Fountain      purple fountain grass with its plumes
  Kit_Agave               a century plant: a rosette of thick, pointed leaves (a solid mesh)

Each piece is a mesh named "<Kit>__Main__<Slot>" (MeshKit's naming). Textured slots (PalmBark,
PalmFrond, PalmFrondDead, RoyalTrunk, OakBark, OakLeaves, PineBark, PineNeedles) get their maps in
Studio from the pack (blender/realism_pack.py); Coconut and Crownshaft are plain colours. Leaves
and fronds are cards with a real back face (Roblox draws one side of a triangle only).

Lean: every kit leans toward +X (Roblox +X), so CityKit can turn it to its placeholder's lean.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

Z = Vector((0, 0, 1))
X = Vector((1, 0, 0))

# Slots: textured (from the pack) or a plain colour (MeshKit.Slots)
TEXTURED = {
    "PalmBark": "PalmBark",
    "PalmFrond": "PalmFrond",
    "PalmFrondDead": "PalmFrond",
    "RoyalTrunk": "RoyalTrunk",
    "OakBark": "OakBark",
    "OakLeaves": "OakLeaves",
    "PineBark": "PineBark",
    "PineNeedles": "PineNeedles",
}
# (the detail pass's plants; PoincianaBark, SeaGrapeBark and ShrubStem reuse the first release's bark)
TEXTURED.update({
    "SabalTrunk": "SabalTrunk",
    "SabalFrond": "SabalFrond",
    "SabalFrondDead": "SabalFrond",
    "DateTrunk": "DateTrunk",
    "DateFrond": "DateFrond",
    "PoincianaBark": "RoyalTrunk",
    "PoincianaLeaves": "PoincianaLeaves",
    "ShrubStem": "OakBark",
    "HibiscusLeaves": "HibiscusLeaves",
    "CrotonLeaves": "CrotonLeaves",
    "BougainvilleaLeaves": "BougainvilleaLeaves",
    "SeaGrapeLeaves": "SeaGrapeLeaves",
    "SeaGrapeBark": "RoyalTrunk",
    "FernFrond": "FernFrond",
    "GrassBlades": "GrassBlades",
    "AgaveLeaf": "AgaveLeaf",
    "PalmettoFrond": "SabalFrond",
    "PalmettoTrunk": "SabalTrunk",
})
FOLIAGE = {"PalmFrond", "PalmFrondDead", "OakLeaves", "PineNeedles", "SabalFrond", "SabalFrondDead", "DateFrond", "PoincianaLeaves", "HibiscusLeaves", "CrotonLeaves", "BougainvilleaLeaves", "SeaGrapeLeaves", "FernFrond", "GrassBlades", "PalmettoFrond"}
TINT = {
    "PalmFrondDead": (0.62, 0.47, 0.28),
    "SabalFrondDead": (0.62, 0.47, 0.28),
    "PoincianaBark": (0.62, 0.57, 0.5),
    "SeaGrapeBark": (0.7, 0.62, 0.52),
    "PalmettoFrond": (0.80, 0.92, 0.88),
}
PLAIN = {"Coconut": (0.36, 0.3, 0.14), "Crownshaft": (0.33, 0.47, 0.2), "PalmStalk": (0.36, 0.38, 0.18), "Dates": (0.78, 0.42, 0.1), "Pods": (0.28, 0.18, 0.1)}


class Piece:
    """A growing bmesh with one UV layer."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")

    def face(self, verts, uvs):
        f = self.bm.faces.new(verts)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def vert(self, co):
        return self.bm.verts.new(co)


def frames(points):
    """Parallel-transport frames (tangent, normal, binormal) along a polyline."""
    out = []
    t0 = (points[1] - points[0]).normalized()
    n0 = t0.cross(Z if abs(t0.dot(Z)) < 0.95 else X).normalized()
    for i, p in enumerate(points):
        if i == 0:
            t = t0
        elif i == len(points) - 1:
            t = (points[i] - points[i - 1]).normalized()
        else:
            t = (points[i + 1] - points[i - 1]).normalized()
        if out:
            prev_t, prev_n, _ = out[-1]
            axis = prev_t.cross(t)
            if axis.length > 1e-8:
                ang = math.asin(min(1.0, axis.length))
                rot = Matrix.Rotation(ang, 3, axis.normalized())
                n = (rot @ prev_n).normalized()
            else:
                n = prev_n
        else:
            n = n0
        b = t.cross(n).normalized()
        n = b.cross(t).normalized()
        out.append((t, n, b))
    return out


def tube(piece, points, radii, seg, u_repeat=1.0, v_tile=1.0, cap=False):
    """A tube through `points` with `radii`, UV u round it (u_repeat times), v down its length
    (one repeat per `v_tile` metres)."""
    fr = frames(points)
    rings = []
    s = 0.0
    vs = []
    for i, p in enumerate(points):
        if i > 0:
            s += (points[i] - points[i - 1]).length
        vs.append(s / v_tile)
        t, n, b = fr[i]
        ring = []
        for j in range(seg + 1):
            a = 2 * math.pi * j / seg
            ring.append(piece.vert(p + (n * math.cos(a) + b * math.sin(a)) * radii[i]))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(seg):
            u0, u1 = u_repeat * j / seg, u_repeat * (j + 1) / seg
            piece.face((rings[i][j], rings[i][j + 1], rings[i + 1][j + 1], rings[i + 1][j]), ((u0, vs[i]), (u1, vs[i]), (u1, vs[i + 1]), (u0, vs[i + 1])))
    if cap:
        top = piece.vert(points[-1] + fr[-1][0] * radii[-1] * 0.3)
        for j in range(seg):
            piece.face((rings[-1][j], rings[-1][j + 1], top), ((0, 0), (0.1, 0), (0.05, 0.1)))
    return s


def card_strip(piece, spine, widths, sides, lift, uv_rect=(0, 0, 1, 1), back=0.004):
    """A double-sided strip along `spine`: across it from left to right through the spine (UV u
    0 / 0.5 / 1), each edge lifted along the card normal by `lift` x half width (a V fold),
    v from 0 at the first point to 1 at the last. `sides` gives the across direction per point."""
    u0, v0, u1, v1 = uv_rect
    n = len(spine)
    rows = []
    for i, p in enumerate(spine):
        t = (spine[min(i + 1, n - 1)] - spine[max(i - 1, 0)]).normalized()
        side = sides[i].normalized()
        normal = side.cross(t).normalized()
        if normal.z < 0:
            normal = -normal
        half = widths[i] / 2
        fold = math.atan(lift)
        left = p - side * half * math.cos(fold) + normal * half * math.sin(fold)
        right = p + side * half * math.cos(fold) + normal * half * math.sin(fold)
        rows.append((left, p, right, normal))
    for facing in (1, -1):
        verts = []
        for (left, mid, right, normal) in rows:
            off = normal * (0 if facing == 1 else -back)
            verts.append([piece.vert(left + off), piece.vert(mid + off), piece.vert(right + off)])
        for i in range(n - 1):
            va, vb = v0 + (v1 - v0) * i / (n - 1), v0 + (v1 - v0) * (i + 1) / (n - 1)
            for k in range(2):
                ua, ub = u0 + (u1 - u0) * k / 2, u0 + (u1 - u0) * (k + 1) / 2
                quad = [verts[i][k], verts[i][k + 1], verts[i + 1][k + 1], verts[i + 1][k]]
                uvs = [(ua, va), (ub, va), (ub, vb), (ua, vb)]
                if facing == -1:
                    quad.reverse()
                    uvs.reverse()
                piece.face(quad, uvs)


def card(piece, center, normal, up, width, height, uv_rect=(0, 0, 1, 1), back=0.004):
    """A double-sided quad facing `normal`, `up` along its height."""
    normal = normal.normalized()
    right = up.cross(normal)
    if right.length < 1e-6:
        right = X.cross(normal)
    right.normalize()
    upv = normal.cross(right).normalized()
    u0, v0, u1, v1 = uv_rect
    corners = [center - right * width / 2 - upv * height / 2, center + right * width / 2 - upv * height / 2, center + right * width / 2 + upv * height / 2, center - right * width / 2 + upv * height / 2]
    uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    front = [piece.vert(c) for c in corners]
    piece.face(front, uvs)
    backs = [piece.vert(c - normal * back) for c in corners]
    piece.face(list(reversed(backs)), list(reversed(uvs)))


def ball(piece, center, r, seg=8, rings=5):
    verts = []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        row = []
        for j in range(seg + 1):
            th = 2 * math.pi * j / seg
            row.append(piece.vert(center + Vector((math.sin(phi) * math.cos(th), math.sin(phi) * math.sin(th), math.cos(phi))) * r))
        verts.append(row)
    for i in range(rings):
        for j in range(seg):
            piece.face((verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]), ((0, 0), (0, 1), (1, 1), (1, 0)))


# ---------------------------------------------------------------------------- the kits


def frond(piece, base, azimuth, elevation, length, width, droop, fold, rng, segs=12):
    """A pinnate frond from `base`: out at `azimuth`, rising at `elevation`, sagging by `droop`."""
    d = Vector((math.cos(azimuth), math.sin(azimuth), 0))
    spine, widths, sides = [], [], []
    for i in range(segs + 1):
        t = i / segs
        s = length * t
        p = base + d * s * math.cos(elevation) + Z * (s * math.sin(elevation) - droop * s * s / length)
        spine.append(p)
        widths.append(width * (math.sin(math.pi * (0.12 + 0.88 * t)) ** 0.7) + 0.05)
        twist = rng.uniform(-0.15, 0.15) * t
        side = Vector((-d.y, d.x, 0))
        side = Matrix.Rotation(twist, 3, d) @ side
        sides.append(side)
    card_strip(piece, spine, widths, sides, fold)


def coconut_palm(seed=3):
    rng = random.Random(seed)
    bark, fronds, dead, nuts = Piece(), Piece(), Piece(), Piece()
    H = 8.6
    pts, radii = [], []
    for i in range(31):
        t = i / 30
        pts.append(Vector((1.25 * t ** 1.7 + 0.12 * math.sin(math.pi * t * 1.3), 0.08 * math.sin(math.pi * t), H * t)))
        flare = 0.16 * (1 - min(1.0, t / 0.05)) ** 2
        radii.append(0.18 + 0.07 * (1 - t) ** 2.5 + flare)
    tube(bark, pts, radii, 12, u_repeat=2.0, v_tile=0.6, cap=True)
    top = pts[-1]
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(21):
        az = k * golden + rng.uniform(-0.15, 0.15)
        el = math.radians(rng.uniform(-5, 48) if k < 15 else rng.uniform(-30, 5))
        L = rng.uniform(4.0, 5.0)
        frond(fronds, top + Vector((math.cos(az), math.sin(az), 0)) * 0.12, az, el, L, rng.uniform(1.3, 1.6), droop=rng.uniform(0.35, 0.6), fold=-0.32, rng=rng)
    for k in range(3):
        az = rng.uniform(0, 2 * math.pi)
        frond(dead, top - Z * 0.3 + Vector((math.cos(az), math.sin(az), 0)) * 0.15, az, math.radians(-68), rng.uniform(3.0, 3.6), 0.9, droop=0.05, fold=-0.4, rng=rng)
    for k in range(6):
        az = rng.uniform(0, 2 * math.pi)
        ball(nuts, top - Z * rng.uniform(0.25, 0.5) + Vector((math.cos(az), math.sin(az), 0)) * rng.uniform(0.18, 0.3), rng.uniform(0.11, 0.14))
    return {"PalmBark": bark, "PalmFrond": fronds, "PalmFrondDead": dead, "Coconut": nuts}


def royal_palm(seed=5):
    rng = random.Random(seed)
    bark, shaft, fronds = Piece(), Piece(), Piece()
    H = 12.0
    pts, radii = [], []
    for i in range(25):
        t = i / 24
        pts.append(Vector((0.03 * math.sin(t * 2.0), 0, H * t)))
        swell = 0.07 * math.exp(-((t - 0.45) / 0.22) ** 2)
        flare = 0.18 * (1 - min(1.0, t / 0.04)) ** 2
        radii.append(0.26 + swell - 0.04 * t + flare)
    tube(bark, pts, radii, 14, u_repeat=2.0, v_tile=1.0)
    s0 = pts[-1]
    spts = [s0 + Z * (2.2 * i / 6) for i in range(7)]
    sr = [0.235 - 0.03 * (i / 6) ** 2 for i in range(7)]
    tube(shaft, spts, sr, 14, u_repeat=1.0, v_tile=1.0, cap=True)
    top = spts[-1]
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(19):
        az = k * golden + rng.uniform(-0.1, 0.1)
        el = math.radians(rng.uniform(25, 65) if k < 13 else rng.uniform(-5, 20))
        frond(fronds, top - Z * 0.1, az, el, rng.uniform(4.4, 5.2), rng.uniform(1.3, 1.6), droop=rng.uniform(0.55, 0.85), fold=0.25, rng=rng)
    return {"RoyalTrunk": bark, "Crownshaft": shaft, "PalmFrond": fronds}


def _limb(bark, base, tip, radius, rng, seg=8):
    """A curving limb from `base` to `tip`, tapering."""
    pts, radii = [], []
    sag = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), rng.uniform(-0.2, 0.5)))
    for i in range(7):
        t = i / 6
        pts.append(base.lerp(tip, t) + sag * math.sin(math.pi * t) * (tip - base).length * 0.12)
        radii.append(radius * (1 - 0.7 * t))
    tube(bark, pts, radii, seg, u_repeat=1.0, v_tile=1.0)
    return pts


def oak(seed=11, tall=False):
    """A live oak: a short trunk, limbs spreading into a wide dome of leaf clusters."""
    rng = random.Random(seed)
    bark, leaves = Piece(), Piece()
    trunk_h = 3.2 if tall else 2.4
    pts = [Vector((0.06 * math.sin(i), 0.04 * math.cos(i), trunk_h * i / 5)) for i in range(6)]
    tube(bark, pts, [0.5 - 0.12 * i / 5 + (0.2 if i == 0 else 0) for i in range(6)], 10, u_repeat=1.5, v_tile=1.0)
    top = pts[-1]
    # the crown: a wide dome (an ellipsoid shell, flattened underneath)
    rx = 4.2 if tall else 6.2
    rz = 3.6 if tall else 2.8
    center = top + Z * (rz * (1.05 if tall else 0.9))
    limbs = 4 if tall else 6
    for k in range(limbs):
        az = 2 * math.pi * k / limbs + rng.uniform(-0.3, 0.3)
        reach = Vector((math.cos(az) * rx * 0.72, math.sin(az) * rx * 0.72, rng.uniform(-0.1, 0.35) * rz))
        tip = center + reach
        lp = _limb(bark, top - Z * rng.uniform(0.0, 0.5), tip, 0.28, rng)
        for j in range(2):
            mid = lp[rng.randint(3, 5)]
            az2 = az + rng.uniform(-0.9, 0.9)
            twig = center + Vector((math.cos(az2) * rx * rng.uniform(0.6, 0.85), math.sin(az2) * rx * rng.uniform(0.6, 0.85), rng.uniform(0.0, 0.6) * rz))
            _limb(bark, mid, twig, 0.11, rng, seg=6)
    # leaf clusters over the shell, facing out from the crown's centre
    count = 170 if tall else 230
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        zf = 1 - 2 * (i + 0.5) / count
        if zf < -0.35:
            zf = -0.35 + (zf + 1) * 0.2
        rr = math.sqrt(max(0.0, 1 - zf * zf))
        th = i * golden
        shell = rng.uniform(0.78, 1.04)
        p = center + Vector((math.cos(th) * rr * rx, math.sin(th) * rr * rx, zf * rz)) * shell
        out = (p - center)
        out = Vector((out.x / rx, out.y / rx, out.z / rz)).normalized()
        nrm = (out + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), 0.35))).normalized()
        size = rng.uniform(1.4, 2.0)
        qx, qy = rng.randint(0, 1), rng.randint(0, 1)
        card(leaves, p, nrm, Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.6)), size, size, (qx * 0.5, qy * 0.5, qx * 0.5 + 0.5, qy * 0.5 + 0.5))
    # and some inside, so the crown doesn't look hollow from below
    for i in range(40):
        p = center + Vector((rng.uniform(-0.7, 0.7) * rx, rng.uniform(-0.7, 0.7) * rx, rng.uniform(-0.6, 0.4) * rz))
        qx, qy = rng.randint(0, 1), rng.randint(0, 1)
        card(leaves, p, Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))), Z, 1.8, 1.8, (qx * 0.5, qy * 0.5, qx * 0.5 + 0.5, qy * 0.5 + 0.5))
    return {"OakBark": bark, "OakLeaves": leaves}


def pine(seed=17):
    rng = random.Random(seed)
    bark, needles = Piece(), Piece()
    H = 16.0
    pts = [Vector((0.35 * (i / 20) ** 2, 0, H * i / 20)) for i in range(21)]
    tube(bark, pts, [0.26 * (1 - 0.65 * i / 20) + (0.1 if i == 0 else 0) for i in range(21)], 10, u_repeat=1.5, v_tile=1.0, cap=True)
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(13):
        t = 0.62 + 0.34 * k / 12
        base = pts[int(t * 20)]
        az = k * golden * 1.3
        L = rng.uniform(1.6, 3.0) * (1.1 - 0.6 * (t - 0.62) / 0.34)
        d = Vector((math.cos(az), math.sin(az), rng.uniform(0.05, 0.5)))
        bpts = [base + d.normalized() * L * i / 4 + Z * (0.25 * L * (i / 4) ** 2) for i in range(5)]
        tube(bark, bpts, [0.09 - 0.06 * i / 4 for i in range(5)], 6, v_tile=1.0)
        for j in (2, 3, 4):
            c = bpts[j] + Z * 0.35
            size = rng.uniform(1.1, 1.6)
            for crossing in (0, math.pi / 2):
                nrm = Vector((math.cos(az + crossing), math.sin(az + crossing), 0))
                card(needles, c, nrm, Z, size, size)
    for crossing in (0, math.pi / 2):
        card(needles, pts[-1] + Z * 0.5, Vector((math.cos(crossing), math.sin(crossing), 0)), Z, 1.6, 1.6)
    return {"PineBark": bark, "PineNeedles": needles}


# ---------------------------------------------------------------------------- round 2 (the detail pass)


def quad_uv(k):
    """The UV rect of quadrant `k` of a 2 x 2 atlas painted as veg_textures does it (k = column * 2
    + row, row 0 the top of the image; v runs up the image)."""
    qi, qj = k // 2, k % 2
    v0 = 0.5 * (1 - qj)
    return (qi * 0.5, v0, qi * 0.5 + 0.5, v0 + 0.5)


def fan(piece, base, d, length, droop=0.4, fold=0.5, segs=5, uv_rect=(0, 0, 1, 1)):
    """A palmate fan leaf (the 2:1 SabalFrond image, its stalk's end at the bottom middle): a
    strip along its costa from `base` out along `d`, twice as wide as long, arching down, its
    halves lifted into a V."""
    d = d.normalized()
    side = d.cross(Z)
    if side.length < 1e-4:
        side = X.copy()
    side.normalize()
    spine, widths, sides = [], [], []
    for i in range(segs + 1):
        t = i / segs
        spine.append(base + d * length * t - Z * droop * length * t * t)
        widths.append(2.0 * length)
        sides.append(side)
    card_strip(piece, spine, widths, sides, fold, uv_rect)


def stem(piece, base, tip, radius, rng, seg=5, points=4, bend=0.12):
    """A thin, slightly crooked stem from `base` to `tip`, tapering."""
    sag = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.6)))
    pts, radii = [], []
    for i in range(points):
        t = i / (points - 1)
        pts.append(base.lerp(tip, t) + sag * math.sin(math.pi * t) * (tip - base).length * bend)
        radii.append(radius * (1 - 0.6 * t))
    tube(piece, pts, radii, seg, u_repeat=1.0, v_tile=1.0)
    return pts


def crown_cards(piece, rng, center, rx, rz, count, size, pick, low=-0.45, up_bias=0.35, inner=0.15, shell=(0.8, 1.04)):
    """Leaf-cluster cards over an ellipsoid shell (flattened underneath below `low`), each facing
    out from the centre with a lift, plus `inner` of them inside so it doesn't look hollow.
    `pick(normal)` gives each card's atlas quadrant."""
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        zf = 1 - 2 * (i + 0.5) / count
        if zf < low:
            zf = low + (zf + 1) * 0.2
        rr = math.sqrt(max(0.0, 1 - zf * zf))
        th = i * golden
        k = rng.uniform(*shell)
        p = center + Vector((math.cos(th) * rr * rx, math.sin(th) * rr * rx, zf * rz)) * k
        out = p - center
        out = Vector((out.x / rx, out.y / rx, out.z / rz)).normalized()
        nrm = (out + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), up_bias))).normalized()
        sz = size * rng.uniform(0.8, 1.2)
        card(piece, p, nrm, Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.7)), sz, sz, quad_uv(pick(nrm)))
    for i in range(int(count * inner)):
        p = center + Vector((rng.uniform(-0.65, 0.65) * rx, rng.uniform(-0.65, 0.65) * rx, rng.uniform(-0.5, 0.4) * rz))
        nrm = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 1)))
        sz = size * rng.uniform(0.8, 1.1)
        card(piece, p, nrm, Z, sz, sz, quad_uv(pick(nrm)))


def sabal_palm(seed=29):
    """A cabbage palm (Florida's state tree): a straight trunk with a gentle curve wearing its
    criss-cross boots, a dense round crown of costapalmate fans on long stalks, dead fans hanging."""
    rng = random.Random(seed)
    bark, fans, dead, stalks = Piece(), Piece(), Piece(), Piece()
    H = 9.0
    pts, radii = [], []
    for i in range(21):
        t = i / 20
        pts.append(Vector((0.4 * t ** 2 + 0.04 * math.sin(math.pi * t * 1.5), 0.03 * math.sin(math.pi * t), H * t)))
        flare = 0.12 * (1 - min(1.0, t / 0.05)) ** 2
        radii.append(0.21 + 0.025 * math.sin(math.pi * t) + flare)
    tube(bark, pts, radii, 12, u_repeat=2.0, v_tile=1.0, cap=True)
    top = pts[-1] + Z * 0.15
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(34):
        az = k * golden + rng.uniform(-0.2, 0.2)
        # (a ball of a crown: the young fans stand up, the old ones droop below the top)
        zf = 1 - 1.75 * (k + 0.5) / 34
        el = math.asin(max(-0.95, min(0.95, zf)))
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        L = rng.uniform(1.2, 1.8)
        end = top + d * L - Z * 0.08 * L
        stem(stalks, top, end, 0.045, rng, seg=4, points=3, bend=0.06)
        fan(fans, end, (d + Vector((0, 0, 0.15))).normalized(), rng.uniform(0.9, 1.15), droop=rng.uniform(0.25, 0.5), fold=0.55)
    for k in range(5):
        az = rng.uniform(0, 2 * math.pi)
        d = Vector((math.cos(az) * 0.25, math.sin(az) * 0.25, -1)).normalized()
        base = top - Z * 0.25 + Vector((math.cos(az), math.sin(az), 0)) * 0.2
        stem(stalks, top - Z * 0.1, base, 0.04, rng, seg=4, points=3, bend=0.05)
        fan(dead, base, d, rng.uniform(0.7, 0.85), droop=0.05, fold=0.7)
    return {"SabalTrunk": bark, "SabalFrond": fans, "SabalFrondDead": dead, "PalmStalk": stalks}


def date_palm(seed=31):
    """A Canary Island date palm: a thick, straight trunk of diamond leaf scars swelling into a
    knob of cut leaf bases under a dense ball of stiff arching fronds; dates hanging in bunches."""
    rng = random.Random(seed)
    bark, fronds, dates = Piece(), Piece(), Piece()
    H = 8.2
    pts, radii = [], []
    for i in range(17):
        t = i / 16
        pts.append(Vector((0.02 * math.sin(t * 2.4), 0, H * t)))
        flare = 0.2 * (1 - min(1.0, t / 0.05)) ** 2
        radii.append(0.43 + 0.05 * (1 - t) ** 2 + flare)
    # (the knob of old leaf bases under the crown, the same scarred bark)
    for i in range(1, 6):
        t = i / 5
        pts.append(Vector((0.02 * math.sin(2.4), 0, H + 1.3 * t)))
        radii.append(0.45 + 0.2 * math.sin(math.pi * min(1.0, t * 0.9)) - 0.25 * t ** 3)
    tube(bark, pts, radii, 16, u_repeat=2.0, v_tile=1.0, cap=True)
    top = pts[-1] - Z * 0.25
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(46):
        az = k * golden + rng.uniform(-0.12, 0.12)
        el = math.radians(rng.uniform(45, 75) if k < 16 else (rng.uniform(8, 45) if k < 36 else rng.uniform(-30, 8)))
        frond(fronds, top + Vector((math.cos(az), math.sin(az), 0)) * 0.3, az, el, rng.uniform(4.2, 5.2), rng.uniform(1.35, 1.55), droop=rng.uniform(0.2, 0.4), fold=0.45, rng=rng, segs=6)
    for k in range(2):
        az = rng.uniform(0, 2 * math.pi)
        c = top - Z * 0.9 + Vector((math.cos(az), math.sin(az), 0)) * 0.7
        for j in range(3):
            ball(dates, c + Vector((rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), -0.18 * j)), rng.uniform(0.12, 0.16), seg=6, rings=4)
    return {"DateTrunk": bark, "DateFrond": fronds, "Dates": dates}


def poinciana(seed=37):
    """A royal poinciana (flamboyant): a short trunk splitting low into wide, sweeping limbs under
    a broad, flat-topped umbrella of feathery leaves and scarlet flowers, long seed pods hanging."""
    rng = random.Random(seed)
    bark, leaves, pods = Piece(), Piece(), Piece()
    trunk_h = 2.0
    pts = [Vector((0.05 * math.sin(i), 0.04 * math.cos(i), trunk_h * i / 4)) for i in range(5)]
    tube(bark, pts, [0.42 - 0.08 * i / 4 + (0.22 if i == 0 else 0) for i in range(5)], 10, u_repeat=1.5, v_tile=1.0)
    top = pts[-1]
    rx, rz = 6.8, 1.5
    center = top + Z * 4.0
    for k in range(5):
        az = 2 * math.pi * k / 5 + rng.uniform(-0.3, 0.3)
        tip = center + Vector((math.cos(az) * rx * 0.75, math.sin(az) * rx * 0.75, rng.uniform(-0.6, 0.2)))
        lp = _limb(bark, top - Z * rng.uniform(0.0, 0.4), tip, 0.26, rng)
        for j in range(2):
            mid = lp[rng.randint(3, 5)]
            az2 = az + rng.uniform(-0.8, 0.8)
            twig = center + Vector((math.cos(az2) * rx * rng.uniform(0.55, 0.9), math.sin(az2) * rx * rng.uniform(0.55, 0.9), rng.uniform(0.0, 0.8)))
            _limb(bark, mid, twig, 0.1, rng, seg=6)

    def pick(nrm):
        # (the top of the umbrella in flower, its sides and underside mostly leaves)
        r = rng.random()
        if nrm.z > 0.55:
            return 0 if r < 0.4 else (1 if r < 0.8 else 2)
        return 2 if r < 0.4 else 3

    crown_cards(leaves, rng, center, rx, rz, 230, 1.9, pick, low=-0.25, up_bias=0.9, inner=0.12, shell=(0.85, 1.05))
    for k in range(22):
        a = rng.uniform(0, 2 * math.pi)
        r = rx * math.sqrt(rng.uniform(0.15, 0.85))
        p = center + Vector((math.cos(a) * r, math.sin(a) * r, -rz * 0.7 - rng.uniform(0.2, 0.5)))
        card(pods, p, Vector((math.cos(a), math.sin(a), 0)), Z, 0.07, rng.uniform(0.4, 0.55))
    return {"PoincianaBark": bark, "PoincianaLeaves": leaves, "Pods": pods}


def _shrub(rng, height, width, cards, size, pick, stems=4, stem_r=0.035, low=-0.5, up_bias=0.35, center_frac=0.56):
    """A rounded shrub: woody stems from the ground fanning up into an ellipsoid crown of
    leaf-cluster cards. Returns (stems, leaves)."""
    wood, leaves = Piece(), Piece()
    rx, rz = width / 2, height * 0.46
    center = Vector((0, 0, height * center_frac))
    for k in range(stems):
        a = 2 * math.pi * k / stems + rng.uniform(-0.4, 0.4)
        base = Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0))
        tip = center + Vector((math.cos(a) * rx * 0.5, math.sin(a) * rx * 0.5, rz * rng.uniform(0.0, 0.4)))
        stem(wood, base, tip, stem_r, rng)
    crown_cards(leaves, rng, center, rx, rz, cards, size, pick, low=low, up_bias=up_bias)
    return wood, leaves


def hibiscus(seed=41):
    rng = random.Random(seed)
    wood, leaves = _shrub(rng, 2.0, 1.8, 72, 0.62, lambda n: rng.choice((0, 1, 2, 3, 0, 1, 3)), stems=5)
    return {"ShrubStem": wood, "HibiscusLeaves": leaves}


def croton(seed=43):
    rng = random.Random(seed)
    # (one cultivar a plant would be truer, but a mix reads as a planted bed: two quadrants each)
    pair = rng.choice(((0, 3), (1, 0), (2, 3), (3, 1)))
    wood, leaves = _shrub(rng, 1.3, 1.1, 54, 0.5, lambda n: pair[rng.randint(0, 1)], stems=4, stem_r=0.03, center_frac=0.6)
    return {"ShrubStem": wood, "CrotonLeaves": leaves}


def bougainvillea(seed=47):
    """A mound of long canes arching up and over like a fountain, bracts thickest along them."""
    rng = random.Random(seed)
    wood, leaves = Piece(), Piece()
    H, R = 2.6, 1.3
    for k in range(11):
        a = 2 * math.pi * k / 11 + rng.uniform(-0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0))
        # (tall canes arching over, and low ones spreading near the ground so it mounds right down)
        low = k % 3 == 2
        reach = R * rng.uniform(0.8, 1.15) * (1.1 if low else 1.0)
        rise = H * (rng.uniform(0.3, 0.45) if low else rng.uniform(0.85, 1.0))
        pts = []
        for i in range(6):
            t = i / 5
            pts.append(out * reach * t + Z * (rise * math.sin(math.pi * 0.62 * t) + 0.08))
        tube(wood, pts, [0.035 * (1 - 0.6 * i / 5) for i in range(6)], 4, v_tile=1.0)
        for i in range(2, 6):
            for j in range(3):
                p = pts[i] + Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.1)))
                side = Vector((-out.y, out.x, 0)) * rng.uniform(-0.8, 0.8)
                nrm = (out + side + Z * rng.uniform(-0.1, 0.4)).normalized()
                sz = rng.uniform(0.45, 0.65)
                card(leaves, p, nrm, Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 1.0)), sz, sz, quad_uv(rng.choice((0, 0, 1, 3, 3, 2))))
    crown_cards(leaves, rng, Vector((0, 0, H * 0.5)), R * 0.85, H * 0.45, 46, 0.6, lambda n: rng.choice((0, 1, 3, 2)), low=-0.4, up_bias=0.15)
    return {"ShrubStem": wood, "BougainvilleaLeaves": leaves}


def sea_grape(seed=53):
    """A sea grape: a few crooked low trunks spreading from the base, a lumpy crown of big round
    leaves (three overlapping mounds)."""
    rng = random.Random(seed)
    bark, leaves = Piece(), Piece()
    H = 3.4
    for k in range(4):
        a = 2 * math.pi * k / 4 + rng.uniform(-0.4, 0.4)
        tip = Vector((math.cos(a) * 1.1, math.sin(a) * 1.1, H * rng.uniform(0.45, 0.6)))
        lp = stem(bark, Vector((math.cos(a) * 0.1, math.sin(a) * 0.1, 0)), tip, 0.11, rng, seg=6, points=5, bend=0.18)
        stem(bark, lp[2], lp[2] + Vector((math.cos(a + 0.8) * 0.8, math.sin(a + 0.8) * 0.8, 0.9)), 0.05, rng, seg=5, points=3)
    for c, rx, rz, n in ((Vector((0.0, 0.0, H * 0.62)), 1.6, 1.15, 70), (Vector((0.7, 0.4, H * 0.5)), 1.1, 0.85, 30), (Vector((-0.6, -0.5, H * 0.48)), 1.0, 0.8, 26)):
        crown_cards(leaves, rng, c, rx, rz, n, 1.0, lambda nrm: rng.randint(0, 3), low=-0.35, up_bias=0.3, inner=0.1)
    return {"SeaGrapeBark": bark, "SeaGrapeLeaves": leaves}


def palmetto(seed=59):
    """A saw palmetto clump: short trunks creeping along the ground and turning up, silver-green
    fans held up on long stalks."""
    rng = random.Random(seed)
    trunks, fans, stalks = Piece(), Piece(), Piece()
    for k in range(3):
        a = 2 * math.pi * k / 3 + rng.uniform(-0.4, 0.4)
        out = Vector((math.cos(a), math.sin(a), 0))
        pts = [out * 0.35 * (i / 3) + Z * (0.06 + 0.1 * (i / 3) ** 2) for i in range(4)]
        tube(trunks, pts, [0.07 - 0.015 * i / 3 for i in range(4)], 6, u_repeat=1.0, v_tile=0.5)
        end = pts[-1]
        for j in range(6):
            az = a + rng.uniform(-1.3, 1.3)
            el = math.radians(rng.uniform(28, 72))
            d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
            L = rng.uniform(0.35, 0.8)
            tip = end + d * L
            stem(stalks, end, tip, 0.016, rng, seg=4, points=3, bend=0.05)
            fan(fans, tip, (d + Z * 0.5).normalized(), rng.uniform(0.42, 0.58), droop=0.25, fold=0.5, segs=4)
    return {"PalmettoTrunk": trunks, "PalmettoFrond": fans, "PalmStalk": stalks}


def fern(seed=61):
    """A sword fern: fronds arching out of the ground in a fountain."""
    rng = random.Random(seed)
    fronds = Piece()
    golden = math.pi * (3 - math.sqrt(5))
    for k in range(16):
        az = k * golden + rng.uniform(-0.2, 0.2)
        L = rng.uniform(0.65, 0.95)
        el = math.radians(rng.uniform(45, 78))
        d = Vector((math.cos(az), math.sin(az), 0))
        spine, widths, sides = [], [], []
        for i in range(6):
            t = i / 5
            s_ = L * t
            spine.append(Vector((0, 0, 0.03)) + d * s_ * math.cos(el) + Z * (s_ * math.sin(el) - 0.92 * math.sin(el) * s_ * s_ / L))
            widths.append(0.24 * L)
            sides.append(Vector((-d.y, d.x, 0)))
        card_strip(fronds, spine, widths, sides, 0.15)
    return {"FernFrond": fronds}


def fountain_grass(seed=67):
    """Purple fountain grass: crossed cards of the clump, upright and leaning out."""
    rng = random.Random(seed)
    blades = Piece()
    for k in range(4):
        a = math.pi * k / 4
        nrm = Vector((math.cos(a), math.sin(a), 0))
        card(blades, Vector((0, 0, 0.55)), nrm, Z, 1.1, 1.1)
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.4
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-out.y, out.x, 0))
        up = (Z + out * 0.45).normalized()
        card(blades, out * 0.18 + up * 0.5, side.cross(up).normalized(), up, 1.0, 1.0)
    return {"GrassBlades": blades}


def agave(seed=71):
    """A century plant: a rosette of thick, channelled leaves tapering to a spine, the outer ones
    lying low, the inner ones standing up. A solid mesh (one side of each face shows)."""
    rng = random.Random(seed)
    piece = Piece()
    golden = math.pi * (3 - math.sqrt(5))
    count = 22
    for k in range(count):
        t = k / (count - 1)
        az = k * golden * 1.0 + rng.uniform(-0.1, 0.1)
        el = math.radians(12 + 62 * t ** 0.8 + rng.uniform(-5, 5))
        L = rng.uniform(0.8, 1.0) * (1.0 - 0.35 * t)
        W, T = 0.2 * (1 - 0.3 * t), 0.06
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        side = Vector((-math.sin(az), math.cos(az), 0))
        up = side.cross(d).normalized()
        if up.z < 0:
            up = -up
        stations = 5
        rows = []
        for i in range(stations):
            s_ = i / (stations - 1)
            # (curving up a little, then out)
            p = Vector((0, 0, 0.12)) + d * L * s_ + up * 0.12 * L * math.sin(math.pi * s_ * 0.8)
            half = W / 2 * (1 - s_ ** 1.6) + 0.004
            th = T * (1 - s_) + 0.004
            left, right = p - side * half, p + side * half
            mid = p + up * th * 0.2
            keel = p - up * th
            rows.append((left, mid, right, keel))
        tip = Vector((0, 0, 0.12)) + d * L * 1.08 + up * 0.02
        vs = [[piece.vert(c) for c in row] for row in rows]
        tv = piece.vert(tip)
        for i in range(stations - 1):
            va, vb = i / (stations - 1), (i + 1) / (stations - 1)
            a, b = vs[i], vs[i + 1]
            # top: left -> mid -> right, facing up; bottom: right -> keel -> left, facing down
            piece.face((a[0], a[1], b[1], b[0]), ((0.0, va), (0.5, va), (0.5, vb), (0.0, vb)))
            piece.face((a[1], a[2], b[2], b[1]), ((0.5, va), (1.0, va), (1.0, vb), (0.5, vb)))
            piece.face((a[2], a[3], b[3], b[2]), ((1.0, va), (0.5, va), (0.5, vb), (1.0, vb)))
            piece.face((a[3], a[0], b[0], b[3]), ((0.5, va), (0.0, va), (0.0, vb), (0.5, vb)))
        e = vs[-1]
        for j in range(4):
            piece.face((e[j], e[(j + 1) % 4], tv), ((0.0, 0.96), (1.0, 0.96), (0.5, 1.0)))
    piece.bm.normal_update()
    bmesh.ops.recalc_face_normals(piece.bm, faces=piece.bm.faces)
    return {"AgaveLeaf": piece}


ROUND2 = {"Kit_Palm_Sabal", "Kit_Palm_Date", "Kit_Tree_Poinciana", "Kit_Shrub_Hibiscus", "Kit_Shrub_Croton", "Kit_Shrub_Bougainvillea", "Kit_Shrub_SeaGrape", "Kit_Shrub_Palmetto", "Kit_Fern", "Kit_Grass_Fountain", "Kit_Agave"}


KITS = {
    "Kit_Palm_Coconut": coconut_palm,
    "Kit_Palm_Royal": royal_palm,
    "Kit_Tree_Oak": lambda: oak(11, False),
    "Kit_Tree_OakTall": lambda: oak(23, True),
    "Kit_Tree_Pine": pine,
    "Kit_Palm_Sabal": sabal_palm,
    "Kit_Palm_Date": date_palm,
    "Kit_Tree_Poinciana": poinciana,
    "Kit_Shrub_Hibiscus": hibiscus,
    "Kit_Shrub_Croton": croton,
    "Kit_Shrub_Bougainvillea": bougainvillea,
    "Kit_Shrub_SeaGrape": sea_grape,
    "Kit_Shrub_Palmetto": palmetto,
    "Kit_Fern": fern,
    "Kit_Grass_Fountain": fountain_grass,
    "Kit_Agave": agave,
}


def to_roblox(v):
    return (v.x, v.z, -v.y)


def build_all(scene=None):
    """Make every kit's pieces as objects in the scene (origin at each piece's box centre, parented
    to an empty named after the kit). Returns manifest entries like meshkit.build_objects."""
    scene = scene or bpy.context.scene
    manifest = {}
    for kit, make in KITS.items():
        empty = bpy.data.objects.new(kit, None)
        scene.collection.objects.link(empty)
        for slot, piece in make().items():
            bm = piece.bm
            if not bm.verts:
                continue
            lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
            hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
            center = (lo + hi) / 2
            bmesh.ops.translate(bm, vec=-center, verts=bm.verts)
            tris = sum(len(f.verts) - 2 for f in bm.faces)
            name = f"{kit}__Main__{slot}"
            me = bpy.data.meshes.new(name)
            bm.to_mesh(me)
            bm.free()
            for poly in me.polygons:
                poly.use_smooth = slot not in FOLIAGE
            ob = bpy.data.objects.new(name, me)
            ob.location = center
            scene.collection.objects.link(ob)
            ob.parent = empty
            mat = bpy.data.materials.get(slot) or bpy.data.materials.new(slot)
            me.materials.append(mat)
            size = hi - lo
            manifest.setdefault(kit, []).append({"Name": name, "Group": "Main", "Slot": slot, "Center": to_roblox(center), "Size": (abs(size.x), abs(size.z), abs(size.y)), "Tris": tris})
    return manifest
