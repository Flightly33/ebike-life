"""
Vegetation kits for the realism pack: Miami's trees as textured meshes, in real metres (Blender:
X right, Y back, Z up), standing on the origin. CityKit fits each to its part-built placeholder
(by height, uniformly) and turns it to the placeholder's lean.

  Kit_Palm_Coconut  a leaning, ringed trunk, ~16 drooping fronds, dead fronds, coconuts
  Kit_Palm_Royal    a straight pale trunk swelling mid-height, a green crownshaft, arching fronds
  Kit_Tree_Oak      a live oak: a short trunk, wide spreading limbs, glossy leaf clusters
  Kit_Tree_OakTall  a younger, more upright oak (the "Birch" placeholders)
  Kit_Tree_Pine     a slash pine: tall bare trunk, an open crown of needle tufts

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
FOLIAGE = {"PalmFrond", "PalmFrondDead", "OakLeaves", "PineNeedles"}
TINT = {"PalmFrondDead": (0.62, 0.47, 0.28)}
PLAIN = {"Coconut": (0.36, 0.3, 0.14), "Crownshaft": (0.33, 0.47, 0.2)}


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


KITS = {
    "Kit_Palm_Coconut": coconut_palm,
    "Kit_Palm_Royal": royal_palm,
    "Kit_Tree_Oak": lambda: oak(11, False),
    "Kit_Tree_OakTall": lambda: oak(23, True),
    "Kit_Tree_Pine": pine,
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
