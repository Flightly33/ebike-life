"""
Shape helpers for build_vehicles.py. Everything works in Blender coordinates, metres:
X right, Y forward, Z up. Roblox model space (x right, y up, -z forward) converts with B().

Pieces are bmeshes in world space, dropped into buckets keyed by (vehicle, group, slot). Each
bucket becomes one mesh object, so one MeshPart in Roblox: the group says which joint it rides
on (Frame, Steer, Front, Rear, Crank, Body, Wheel_*), the slot says its colour and material.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector


def B(v):
    """Roblox model-space metres (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def to_roblox(v):
    return (v.x, v.z, -v.y)


class Buckets:
    def __init__(self):
        self.items = {}

    def add(self, key, bm):
        self.items.setdefault(key, []).append(bm)


BUCKETS = Buckets()
STATS = {"flipped": 0, "pieces": 0}
_current = {"vehicle": None}


def vehicle(name):
    _current["vehicle"] = name


def put(group, slot, bm):
    BUCKETS.add((_current["vehicle"], group, slot), bm)
    return bm


# ---------------------------------------------------------------- primitives


def _align(bm, p0, p1):
    """Rotate a piece built along +Z (centred on the origin) to run from p0 to p1."""
    d = p1 - p0
    length = d.length
    if length < 1e-9:
        return
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts)


def cyl(p0, p1, r0, r1=None, seg=16, caps=True):
    """A (tapered) cylinder from p0 to p1."""
    r1 = r0 if r1 is None else r1
    bm = bmesh.new()
    length = (p1 - p0).length
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r0, radius2=r1, depth=max(length, 1e-4))
    _align(bm, p0, p1)
    return bm


def disc(center, axis, r, thickness, seg=24):
    axis = Vector(axis).normalized()
    return cyl(center - axis * thickness / 2, center + axis * thickness / 2, r, r, seg)


def sphere(center, r, seg=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    return bm


def rbox(center, size, bevel=0.0, rot=None, seg=3):
    """A box (size = full extents) with rounded edges, optionally rotated (3x3 Matrix)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        b = min(bevel, min(size) * 0.49)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    m = Matrix.Translation(center)
    if rot is not None:
        m = m @ rot.to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


def bar(p0, p1, w, h, bevel=0.0, up=Vector((0, 0, 1))):
    """A rectangular-section bar from p0 to p1: w across (perpendicular to `up`), h along `up`."""
    d = p1 - p0
    fwd = d.normalized()
    side = fwd.cross(up)
    if side.length < 1e-6:
        side = fwd.cross(Vector((1, 0, 0)))
    side.normalize()
    upv = side.cross(fwd).normalized()
    rot = Matrix((side, fwd, upv)).transposed()
    return rbox((p0 + p1) / 2, (w, d.length, h), bevel, rot)


def torus(center, axis, R, r, seg_major=48, seg_minor=12, squash=1.0):
    """A torus around `axis`. squash < 1 flattens the section along the axis."""
    axis = Vector(axis).normalized()
    a = Vector((1, 0, 0)) if abs(axis.x) < 0.9 else Vector((0, 1, 0))
    u = axis.cross(a).normalized()
    v = axis.cross(u).normalized()
    bm = bmesh.new()
    rings = []
    for i in range(seg_major):
        t = 2 * math.pi * i / seg_major
        radial = u * math.cos(t) + v * math.sin(t)
        ring = []
        for j in range(seg_minor):
            s = 2 * math.pi * j / seg_minor
            p = center + radial * (R + r * math.cos(s)) + axis * (r * squash * math.sin(s))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for i in range(seg_major):
        a_ring, b_ring = rings[i], rings[(i + 1) % seg_major]
        for j in range(seg_minor):
            bm.faces.new((a_ring[j], b_ring[j], b_ring[(j + 1) % seg_minor], a_ring[(j + 1) % seg_minor]))
    return bm


def lathe(center, axis, profile, seg=32):
    """Revolve [(along_axis, radius), ...] around `axis` through `center`; radius 0 closes a pole."""
    axis = Vector(axis).normalized()
    a = Vector((1, 0, 0)) if abs(axis.x) < 0.9 else Vector((0, 1, 0))
    u = axis.cross(a).normalized()
    v = axis.cross(u).normalized()
    bm = bmesh.new()
    rows = []
    for along, radius in profile:
        row = []
        if radius <= 1e-6:
            row = [bm.verts.new(center + axis * along)] * seg
        else:
            for i in range(seg):
                t = 2 * math.pi * i / seg
                row.append(bm.verts.new(center + axis * along + (u * math.cos(t) + v * math.sin(t)) * radius))
        rows.append(row)
    for k in range(len(rows) - 1):
        r0, r1 = rows[k], rows[k + 1]
        for i in range(seg):
            quad = [r0[i], r1[i], r1[(i + 1) % seg], r0[(i + 1) % seg]]
            unique = []
            for q in quad:
                if q not in unique:
                    unique.append(q)
            if len(unique) >= 3:
                try:
                    bm.faces.new(unique)
                except ValueError:
                    pass
    return bm


def superellipse(a, b, n, t):
    c, s = math.cos(t), math.sin(t)
    x = a * math.copysign(abs(c) ** (2 / n), c)
    y = b * math.copysign(abs(s) ** (2 / n), s)
    return x, y


def loft(sections, seg=20, caps=True, axis="Y"):
    """
    Skin a tube through cross-sections. Each section: (center Vector, half_width, half_height,
    exponent) where the cross-section is a superellipse in the plane across `axis` (Y: X-Z plane,
    i.e. along the bike or car; X: Y-Z plane, across it). Exponent 2 is an ellipse, 4+ a rounded box.
    """
    bm = bmesh.new()
    rings = []
    for center, hw, hh, n in sections:
        ring = []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            x, y = superellipse(hw, hh, n, t)
            if axis == "Y":
                p = center + Vector((x, 0, y))
            elif axis == "X":
                p = center + Vector((0, x, y))
            else:
                p = center + Vector((x, y, 0))
            ring.append(bm.verts.new(p))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a_ring, b_ring = rings[k], rings[k + 1]
        for i in range(seg):
            bm.faces.new((a_ring[i], a_ring[(i + 1) % seg], b_ring[(i + 1) % seg], b_ring[i]))
    if caps:
        for ring in (rings[0], rings[-1]):
            f = bm.faces.new(ring)
            bmesh.ops.triangulate(bm, faces=[f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def sweep(points, r, seg=12, closed=False, profile=None, samples=6, n=2.0):
    """
    A smooth tube through `points` (a Catmull-Rom spline, so bends are rounded). `profile` (w, h)
    makes an elliptical section instead of a round one, with h along the frame's 'up' (+Z bias).
    """
    pts = [Vector(p) for p in points]
    if len(pts) < 2:
        return bmesh.new()
    path = []
    count = len(pts)
    span = count if closed else count - 1
    for k in range(span):
        p0 = pts[(k - 1) % count] if (closed or k > 0) else pts[0] * 2 - pts[1]
        p1 = pts[k]
        p2 = pts[(k + 1) % count]
        p3 = pts[(k + 2) % count] if (closed or k + 2 < count) else p2 * 2 - p1
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            path.append(p)
    if not closed:
        path.append(pts[-1])
    w, h = (r, r) if profile is None else profile
    bm = bmesh.new()
    rings = []
    prev_side = None
    for i, p in enumerate(path):
        if i == 0:
            tangent = path[1] - path[0]
        elif i == len(path) - 1:
            tangent = path[-1] - path[-2]
        else:
            tangent = path[i + 1] - path[i - 1]
        tangent.normalize()
        up = Vector((0, 0, 1))
        side = tangent.cross(up)
        if side.length < 1e-4:
            side = prev_side if prev_side is not None else tangent.cross(Vector((1, 0, 0)))
        side.normalize()
        prev_side = side
        upv = side.cross(tangent).normalized()
        ring = []
        for j in range(seg):
            t = 2 * math.pi * j / seg
            sx, sy = superellipse(w, h, n, t)
            ring.append(bm.verts.new(p + side * sx + upv * sy))
        rings.append(ring)
    n = len(rings)
    for k in range(n if closed else n - 1):
        a_ring, b_ring = rings[k], rings[(k + 1) % n]
        for j in range(seg):
            bm.faces.new((a_ring[j], a_ring[(j + 1) % seg], b_ring[(j + 1) % seg], b_ring[j]))
    if not closed:
        for ring in (rings[0], rings[-1]):
            f = bm.faces.new(ring)
            bmesh.ops.triangulate(bm, faces=[f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def spline2d(points, samples=6, closed=True):
    """A smooth closed (or open) Catmull-Rom curve through 2D points [(u, v), ...]."""
    pts = [Vector((p[0], p[1], 0)) for p in points]
    count = len(pts)
    out = []
    span = count if closed else count - 1
    for k in range(span):
        p0 = pts[(k - 1) % count] if (closed or k > 0) else pts[0] * 2 - pts[1]
        p1 = pts[k]
        p2 = pts[(k + 1) % count]
        p3 = pts[(k + 2) % count] if (closed or k + 2 < count) else p2 * 2 - p1
        for s in range(samples):
            t = s / samples
            t2, t3 = t * t, t * t * t
            p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append((p.x, p.y))
    if not closed:
        out.append((pts[-1].x, pts[-1].y))
    return out


def prism(poly, depth, origin, ax_u, ax_v, ax_w, bevel=0.0, seg=2, bevel_angle=25):
    """
    Extrude a 2D outline [(u, v), ...] (counter-clockwise or not) from `origin` along ax_w by
    `depth`, where u runs along ax_u and v along ax_v. Sharp edges (over bevel_angle degrees) are
    rounded by `bevel`. Concave outlines are fine (ear-clipped caps).
    """
    ax_u, ax_v, ax_w = Vector(ax_u).normalized(), Vector(ax_v).normalized(), Vector(ax_w).normalized()
    origin = Vector(origin)
    # drop repeated points (a closed spline can end where it starts)
    clean = []
    for u, v in poly:
        if not clean or (abs(clean[-1][0] - u) > 1e-6 or abs(clean[-1][1] - v) > 1e-6):
            clean.append((u, v))
    if len(clean) > 2 and abs(clean[0][0] - clean[-1][0]) < 1e-6 and abs(clean[0][1] - clean[-1][1]) < 1e-6:
        clean.pop()
    bm = bmesh.new()
    a = [bm.verts.new(origin + ax_u * u + ax_v * v) for u, v in clean]
    b = [bm.verts.new(origin + ax_u * u + ax_v * v + ax_w * depth) for u, v in clean]
    count = len(clean)
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ngons = [f for f in bm.faces if len(f.verts) > 4]
    if ngons:
        bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="EAR_CLIP")
    if bevel > 0:
        sharp = [e for e in bm.edges if e.is_manifold and e.calc_face_angle(0) > math.radians(bevel_angle)]
        if sharp:
            bmesh.ops.bevel(bm, geom=sharp, offset=bevel, segments=seg, profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def side_prism(poly_yz, x0, x1, bevel=0.0, seg=2):
    """A side-profile outline [(y, z), ...] (Blender: y forward, z up) extruded across x0..x1."""
    return prism(poly_yz, x1 - x0, Vector((x0, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0)), bevel, seg)


def displace(bm, fn):
    """Move every vertex: co -> co + fn(co)."""
    for v in bm.verts:
        v.co = v.co + fn(v.co)
    return bm


def petal_disc(center, axis, r_out, r_in, waves, depth, thickness, seg=120):
    """A brake rotor with a wavy ("petal") outer edge: an annulus r_in..r_out(t), `thickness` thick."""
    axis = Vector(axis).normalized()
    a = Vector((1, 0, 0)) if abs(axis.x) < 0.9 else Vector((0, 1, 0))
    u = axis.cross(a).normalized()
    v = axis.cross(u).normalized()
    bm = bmesh.new()
    rings = {}
    for side in (-1, 1):
        off = axis * (thickness / 2 * side)
        outer, inner = [], []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            radial = u * math.cos(t) + v * math.sin(t)
            r = r_out - depth * (0.5 - 0.5 * math.cos(waves * t))
            outer.append(bm.verts.new(center + off + radial * r))
            inner.append(bm.verts.new(center + off + radial * r_in))
        rings[side] = (outer, inner)
    (o0, i0), (o1, i1) = rings[-1], rings[1]
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((o0[i], o0[j], i0[j], i0[i]))
        bm.faces.new((o1[j], o1[i], i1[i], i1[j]))
        bm.faces.new((o0[j], o0[i], o1[i], o1[j]))
        bm.faces.new((i0[i], i0[j], i1[j], i1[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def ring_of(center, axis, count, make):
    """Call make(angle, radial_unit, tangent_unit) count times around `axis`; returns the pieces."""
    axis = Vector(axis).normalized()
    a = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((0, 1, 0))
    u = axis.cross(a).normalized()
    v = axis.cross(u).normalized()
    pieces = []
    for i in range(count):
        t = 2 * math.pi * i / count
        radial = u * math.cos(t) + v * math.sin(t)
        tangent = axis.cross(radial).normalized()
        piece = make(t, radial, tangent)
        if piece is not None:
            pieces.append(piece)
    return pieces


def frame_rot(x, y, z):
    return Matrix((x, y, z)).transposed()


def subtract(bm, cutter):
    """Boolean-subtract `cutter` from `bm` (both world-space bmeshes). Used for wheel arches."""
    scene = bpy.context.scene
    me_a = bpy.data.meshes.new("a")
    bm.to_mesh(me_a)
    me_b = bpy.data.meshes.new("b")
    cutter.to_mesh(me_b)
    ob_a = bpy.data.objects.new("a", me_a)
    ob_b = bpy.data.objects.new("b", me_b)
    scene.collection.objects.link(ob_a)
    scene.collection.objects.link(ob_b)
    mod = ob_a.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = ob_b
    mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob_a.evaluated_get(dg)
    out = bmesh.new()
    out.from_mesh(ev.to_mesh())
    ev.to_mesh_clear()
    for ob in (ob_a, ob_b):
        bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me_a)
    bpy.data.meshes.remove(me_b)
    return out


# ---------------------------------------------------------------- output


UV_TILE = 0.25  # metres per UV unit: one tile of a livery pattern (Shared/Livery) is 25 cm on the bike


def box_uvs(bm):
    """UVs by box projection in world metres (each face mapped from the plane it faces most), so
    the game's livery patterns (MaterialVariants) tile at real size on every piece."""
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if ax >= ay and ax >= az:
                loop[uv].uv = (co.y / UV_TILE, co.z / UV_TILE)
            elif ay >= az:
                loop[uv].uv = (co.x / UV_TILE, co.z / UV_TILE)
            else:
                loop[uv].uv = (co.x / UV_TILE, co.y / UV_TILE)


def build_objects(smooth_angle=35):
    """Turn the buckets into mesh objects (origin at the bbox centre). Returns the manifest."""
    scene = bpy.context.scene
    manifest = {}
    parents = {}
    for (veh, group, slot), pieces in sorted(BUCKETS.items.items()):
        bm = bmesh.new()
        tmp = bpy.data.meshes.new("tmp")
        for piece in pieces:
            # Roblox draws only front faces: make every closed piece face outward
            bmesh.ops.recalc_face_normals(piece, faces=piece.faces)
            try:
                if piece.calc_volume(signed=True) < 0:
                    bmesh.ops.reverse_faces(piece, faces=piece.faces)
                    STATS["flipped"] += 1
            except ValueError:
                pass
            STATS["pieces"] += 1
            piece.to_mesh(tmp)
            bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        if not bm.verts:
            continue
        box_uvs(bm)
        lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
        hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
        center = (lo + hi) / 2
        bmesh.ops.translate(bm, vec=-center, verts=bm.verts)
        tris = sum(len(f.verts) - 2 for f in bm.faces)
        name = f"{veh}__{group}__{slot}"
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = True
        try:
            me.set_sharp_from_angle(angle=math.radians(smooth_angle))
        except AttributeError:
            pass
        ob = bpy.data.objects.new(name, me)
        ob.location = center
        if veh not in parents:
            empty = bpy.data.objects.new(veh, None)
            scene.collection.objects.link(empty)
            parents[veh] = empty
        scene.collection.objects.link(ob)
        ob.parent = parents[veh]
        size = hi - lo
        manifest.setdefault(veh, []).append(
            {
                "Name": name,
                "Group": group,
                "Slot": slot,
                "Center": to_roblox(center),
                "Size": (abs(size.x), abs(size.z), abs(size.y)),
                "Tris": tris,
            }
        )
    return manifest
