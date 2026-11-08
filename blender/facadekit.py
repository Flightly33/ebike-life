"""
Facade kit: detailed meshes for the city's buildings and streets, each fitted by Models/CityKit to a
part-built stand-in the builders mark with PartKit.Kit: shopfront mullions, transoms, fascias,
bulkheads, doors, door frames and awnings; Miami's aluminium windows under concrete eyebrows;
house windows, shutters, doors and garage doors; porch posts and Tuscan columns; arched villa
windows; wrought-iron balcony rails; rooftop AC units; street light poles, bases, arms and heads;
traffic signal heads; and (round 2) roll-up doors, condo balconies' glass rails, bus shelters and
gas station canopies.

Each kit is modelled round its stand-in's centre in design studs (1 stud = 0.28 m): Blender x along
the wall, +y out of it (toward the street, Roblox -Z), z up. kit() records the stand-in's box
(written to src/shared/Models/KitSpec.luau); the game scales the kit by the part's size over it.
Geometry may reach outside that box (a sill under a window, a visor in front of a lamp) and scales
with it. A tiled kit is one module, which the game repeats along x to fill the part.

Slots: "Paint" takes the stand-in's own colour and material; the rest are fixed (MeshKit.Slots).
"""

import math

import bmesh
from mathutils import Matrix, Vector

import meshkit as K

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))

# kit name -> {"Reference": (x, y, z) Roblox axes, "Tile": None | "Y" | "Z"}
SPECS = {}
# the Paint colour each kit gets in the offline renders (the game uses the stand-in's)
PAINT = {}


def kit(name, ref, tile=None, uv=7.0, paint=(0.85, 0.84, 0.8), ring=False, corner=None, spec=True):
    """Start a kit: `ref` is its stand-in's size (x along the wall, y up, z depth). A ring kit
    (a cornice) is one module of a run along a wall, `ref` its length, height and projection, laid
    round the stand-in's box with `corner` (another kit) at the corners."""
    K.vehicle(name)
    K.UV_TILES[name] = uv
    if spec:
        SPECS[name] = {"Reference": tuple(ref), "Tile": tile, "Ring": ring, "Corner": corner}
    PAINT[name] = paint
    return lambda slot, bm: K.put("Main", slot, bm)


def box(cx, cy, cz, sx, sy, sz, bevel=0.0, seg=1):
    # (one chamfer catches the light like a rounded edge at street distances, at half the triangles)
    return K.rbox(Vector((cx, cy, cz)), (sx, sy, sz), bevel, seg=seg)


def ring(put, slot, cx, cz, ow, oh, iw, ih, y0, y1, bevel=0.0, bottom=True):
    """A rectangular frame in the wall's plane (x along, z up), standing from y0 to y1."""
    yc, sy = (y0 + y1) / 2, y1 - y0
    side, top = (ow - iw) / 2, (oh - ih) / 2
    put(slot, box(cx - ow / 2 + side / 2, yc, cz, side, sy, oh, bevel))
    put(slot, box(cx + ow / 2 - side / 2, yc, cz, side, sy, oh, bevel))
    put(slot, box(cx, yc, cz + oh / 2 - top / 2, iw, sy, top, bevel))
    if bottom:
        put(slot, box(cx, yc, cz - oh / 2 + top / 2, iw, sy, top, bevel))


def sector(cx, cz, r_in, r_out, a0, a1, y0, y1, seg=16):
    """An annular sector in the wall's plane (angles from +x toward +z), standing from y0 to y1."""
    outer = [(cx + r_out * math.cos(a0 + (a1 - a0) * i / seg), cz + r_out * math.sin(a0 + (a1 - a0) * i / seg)) for i in range(seg + 1)]
    inner = [(cx + r_in * math.cos(a0 + (a1 - a0) * i / seg), cz + r_in * math.sin(a0 + (a1 - a0) * i / seg)) for i in range(seg, -1, -1)]
    return K.prism(outer + inner, y1 - y0, Vector((0, y0, 0)), X, Z, Y)


def moulding(profile, z, x0, x1):
    """A moulding run along x: `profile` [(y out, z up), ...] lifted to height z."""
    return K.side_prism([(y, v + z) for y, v in profile], x0, x1)


# ---------------------------------------------------------------------------------- shopfronts


def shop_mullion():
    """An aluminium storefront mullion: the tube, its pressure plate and snap cover, glazing
    gaskets where the glass meets it, a sill shoe and a head cap."""
    put = kit("Kit_ShopMullion", (0.45, 8.7, 0.5), uv=2.0, paint=(0.16, 0.16, 0.18))
    H = 8.7
    put("Paint", box(0, -0.06, 0, 0.3, 0.36, H - 0.3, 0.03))
    put("Paint", box(0, 0.17, 0, 0.42, 0.1, H - 0.3, 0.035))
    for sx in (-1, 1):
        put("Black", box(sx * 0.19, 0.09, 0, 0.04, 0.06, H - 0.4))
    put("Paint", box(0, 0.0, -H / 2 + 0.15, 0.45, 0.5, 0.3, 0.03))
    put("Paint", box(0, 0.0, H / 2 - 0.15, 0.45, 0.5, 0.3, 0.03))


def shop_transom():
    """The horizontal bar over the shop windows, the mullions' profile on its side."""
    put = kit("Kit_ShopTransom", (10, 0.45, 0.5), uv=2.0, paint=(0.16, 0.16, 0.18))
    L = 10
    put("Paint", box(0, -0.06, 0, L, 0.36, 0.3, 0.03))
    put("Paint", box(0, 0.17, 0, L, 0.1, 0.42, 0.035))
    for sz in (-1, 1):
        put("Black", box(0, 0.09, sz * 0.19, L, 0.06, 0.04))


def fascia():
    """The sign band over a shopfront: a flat band under a cornice cap with an ogee nose (it
    overhangs the sign board), a bed moulding, a bead along its foot and downlights for the sign."""
    put = kit("Kit_Fascia", (20, 2.6, 0.6), uv=7.0, paint=(0.16, 0.16, 0.18))
    L = 20
    put("Paint", box(0, -0.05, -0.05, L, 0.5, 2.3))
    crown = [(-0.3, 1.12), (0.55, 1.12), (0.62, 1.16), (0.66, 1.24), (0.72, 1.3), (0.8, 1.34), (0.82, 1.42), (0.78, 1.47), (-0.3, 1.47)]
    put("Paint", K.side_prism(crown, -L / 2, L / 2))
    put("Paint", box(0, 0.24, 1.06, L, 0.14, 0.12))
    foot = [(-0.3, -1.32), (0.36, -1.32), (0.42, -1.26), (0.42, -1.18), (0.36, -1.12), (-0.3, -1.12)]
    put("Paint", K.side_prism(foot, -L / 2, L / 2))
    for i in range(5):
        x = -L / 2 + (i + 0.5) * L / 5
        put("Black", K.cyl(Vector((x, 0.62, 1.13)), Vector((x, 0.62, 0.98)), 0.12, 0.09, 10))


def bulkhead():
    """One module of the panelled base under the shop windows: a kick plinth, a raised field in a
    bolection moulding, a stone ledge the glass stands on."""
    put = kit("Kit_Bulkhead", (4.5, 2.2, 0.8), tile="Y", uv=4.0, paint=(0.32, 0.12, 0.1))
    W = 4.5
    put("Paint", box(0, -0.02, -0.02, W, 0.76, 1.9))
    put("Paint", box(0, 0.04, -0.93, W, 0.88, 0.34, 0.03))
    put("Paint", box(0, 0.38, -0.05, W - 0.9, 0.06, 1.0, 0.03))
    for cx, cz, sx, sz in ((0, 0.52, W - 0.6, 0.12), (0, -0.62, W - 0.6, 0.12), (-(W - 0.72) / 2, -0.05, 0.12, 1.26), ((W - 0.72) / 2, -0.05, 0.12, 1.26)):
        put("Paint", box(cx, 0.4, cz, sx, 0.08, sz, 0.03))
    put("Stone", box(0, 0.08, 1.0, W + 0.02, 0.96, 0.2, 0.04))


def shop_door():
    """A narrow-stile aluminium shop door: stiles and rails round the glass, a kick plate, a pull
    handle outside and a push bar inside."""
    put = kit("Kit_ShopDoor", (4.2, 7.6, 0.35), uv=2.0)
    W, H, D = 4.2, 7.6, 0.35
    st = 0.34
    for sx in (-1, 1):
        put("Dark", box(sx * (W / 2 - st / 2), 0, 0, st, D, H, 0.04))
    put("Dark", box(0, 0, H / 2 - 0.25, W - 2 * st, D, 0.5, 0.03))
    put("Dark", box(0, 0, -H / 2 + 0.55, W - 2 * st, D, 1.1, 0.03))
    put("Glass", box(0, 0, 0.3, W - 2 * st + 0.04, 0.06, H - 1.6 + 0.04))
    put("Metal", box(0, D / 2 + 0.01, -H / 2 + 0.55, W - 2 * st - 0.2, 0.02, 0.8))
    hx = W / 2 - st - 0.35
    put("Metal", K.cyl(Vector((hx, 0.38, -0.9)), Vector((hx, 0.38, 1.3)), 0.06, 0.06, 10))
    for z in (-0.7, 1.1):
        put("Metal", K.cyl(Vector((hx, 0.17, z)), Vector((hx, 0.38, z)), 0.04, 0.04, 8))
    put("Metal", K.cyl(Vector((-W / 2 + st + 0.1, -0.36, 0.1)), Vector((W / 2 - st - 0.1, -0.36, 0.1)), 0.06, 0.06, 10))
    for x in (-W / 2 + st + 0.25, W / 2 - st - 0.25):
        put("Metal", box(x, -0.26, 0.1, 0.12, 0.2, 0.2))


def shop_door_frame():
    """The doorway's jambs and head with stop beads (the doorway itself open: the shop behind is a
    room), and a door closer on the head."""
    put = kit("Kit_ShopDoorFrame", (4.8, 8.0, 0.3), uv=2.0, paint=(0.16, 0.16, 0.18))
    ring(put, "Paint", 0, 0, 4.8, 8.0, 4.2, 7.6, -0.15, 0.2, 0.03, bottom=False)
    for sx in (-1, 1):
        put("Paint", box(sx * 2.06, 0.24, -0.2, 0.08, 0.1, 7.2))
    put("Paint", box(0, 0.24, 3.76, 4.2, 0.1, 0.08))
    put("Dark", box(1.0, -0.3, 3.55, 1.1, 0.22, 0.26, 0.04))


def awning_stripe():
    """One module of a fabric awning (in the stand-in's own sloped frame): a gently bowed sheet,
    a bound outer edge and a scalloped valance hanging plumb from it, a rod along the wall."""
    put = kit("Kit_AwningStripe", (3, 0.3, 6), tile="Z", uv=3.0, paint=(0.75, 0.12, 0.12))
    W, D = 3.0, 6.0
    n = 16
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        y = -D / 2 + t * D
        z = 0.28 * math.sin(math.pi * t)
        top.append((y, z + 0.035))
        bot.append((y, z - 0.035))
    put("Paint", K.side_prism(top + list(reversed(bot)), -W / 2, W / 2))
    edge = Vector((0, D / 2, 0))
    put("Paint", K.cyl(edge - X * (W / 2), edge + X * (W / 2), 0.06, 0.06, 8))
    # the valance hangs plumb: the stand-in leans 18 degrees out, so world-down is tilted here
    down = Vector((0, math.sin(math.radians(18)), -math.cos(math.radians(18))))
    normal = X.cross(down).normalized()
    height, scallops = 1.0, 3
    outline = []
    steps = 10
    for s in range(scallops):
        for i in range(steps + 1):
            if s > 0 and i == 0:
                continue
            f = i / steps
            u = -W / 2 + (s + f) * W / scallops
            v = 0.24 - 0.24 * math.sqrt(max(0.0, 1 - (2 * f - 1) ** 2))
            outline.append((u, v))
    outline += [(W / 2, height), (-W / 2, height)]
    origin = edge + down * height - normal * 0.025
    put("Paint", K.prism(outline, 0.05, origin, X, -down, normal))
    put("Dark", K.cyl(Vector((-W / 2, -D / 2, 0)), Vector((W / 2, -D / 2, 0)), 0.07, 0.07, 8))


# ---------------------------------------------------------------------------------- windows


def window_modern():
    """Miami's stucco windows: an aluminium single-hung sash set back in a raised stucco band, a
    concrete eyebrow cantilevered over the window and a sloped sill (Detail.Windows' frame box,
    the glass moved into the reveal by CityKit)."""
    put = kit("Kit_Window_Modern", (5.7, 7.2, 0.3), uv=7.0, paint=(0.93, 0.92, 0.88))
    W, H = 5.7, 7.2
    gw, gh = W - 0.7, H - 0.7
    # (wall at y = -0.1, the glass's face at y = -0.045)
    ring(put, "Paint", 0, 0, gw + 1.3, gh + 1.3, gw + 0.1, gh + 0.1, -0.1, 0.1, 0.04)
    ring(put, "Alu", 0, 0, gw + 0.1, gh + 0.1, gw - 0.3, gh - 0.3, -0.1, 0.0)
    put("Alu", box(0, -0.01, -0.35, gw - 0.3, 0.1, 0.2))
    ring(put, "Alu", 0, -gh / 4 - 0.25, gw - 0.3, gh / 2 - 0.1, gw - 0.62, gh / 2 - 0.42, -0.04, 0.04)
    # (a drip groove along the underside, near the nose)
    brow = [(-0.1, 0.06), (1.7, 0.0), (1.8, -0.06), (1.8, -0.22), (1.72, -0.26), (1.56, -0.26), (1.56, -0.2), (1.48, -0.2), (1.48, -0.26), (-0.1, -0.26)]
    put("Paint", moulding(brow, gh / 2 + 0.98, -(gw / 2 + 1.0), gw / 2 + 1.0))
    sill = [(-0.1, 0.0), (0.46, -0.07), (0.5, -0.13), (0.44, -0.22), (-0.1, -0.22)]
    put("Paint", moulding(sill, -(gh / 2 + 0.62), -(gw / 2 + 0.55), gw / 2 + 0.55))


def window_house():
    """A house's double-hung window: a moulded casing under a cap, two sashes six over six, a sill
    with a nose (the stand-in's glass stays behind the sashes)."""
    put = kit("Kit_Window_House", (5, 5, 0.3), uv=7.0, paint=(0.97, 0.97, 0.96))
    gw = 4.2
    # (wall at y = -0.12, the glass's face at y = 0.205)
    ring(put, "Paint", 0, 0, 5.2, 5.3, gw, gw, -0.12, 0.36, 0.03)
    cap = [(-0.12, 0.0), (0.44, 0.0), (0.5, 0.06), (0.5, 0.14), (0.42, 0.2), (-0.12, 0.2)]
    put("Paint", moulding(cap, 2.65, -3.0, 3.0))
    ring(put, "Paint", 0, 0, gw, gw, gw - 0.36, gw - 0.36, 0.2, 0.3)
    put("Paint", box(0, 0.26, 0, gw - 0.36, 0.12, 0.2))
    inner = gw - 0.36
    for z0 in (gw / 4, -gw / 4):
        put("Paint", box(0, 0.24, z0, inner, 0.06, 0.07))
    for x0 in (-inner / 6, inner / 6):
        put("Paint", box(x0, 0.24, 0, 0.07, 0.06, inner))
    sill = [(-0.12, 0.0), (0.62, -0.05), (0.66, -0.12), (0.6, -0.22), (-0.12, -0.22)]
    put("Paint", moulding(sill, -2.65, -2.95, 2.95))


def window_arched():
    """A villa's arched window (stand-in: the sill under it): moulded jambs, a half-round arch with
    a keystone, glazing bars radiating in the fan, a sill on corbels."""
    put = kit("Kit_Window_Arched", (4.8, 0.5, 0.5), uv=7.0, paint=(0.98, 0.97, 0.94))
    wall, front, top = -0.3, 0.06, 6.2
    # (the glass: 4 wide, z 0.2 to 6.2 and its half-round head to 8.2, its face at y = 0.05)
    for sx in (-1, 1):
        put("Paint", box(sx * 2.3, (wall + 0.2) / 2, 3.2, 0.6, 0.2 - wall, 6.0, 0.04))
    put("Paint", sector(0, top, 2.0, 2.6, 0, math.pi, wall, 0.2, seg=20))
    put("Paint", K.prism([(-0.3, 0.0), (0.3, 0.0), (0.4, 0.75), (-0.4, 0.75)], 0.6, Vector((0, wall, top + 1.95)), X, Z, Y))
    bar_y = front + 0.04
    put("Paint", box(0, bar_y, 4.2, 0.09, 0.08, 8.0))
    put("Paint", box(0, bar_y, top, 4.0, 0.08, 0.09))
    put("Paint", box(0, bar_y, 3.2, 4.0, 0.08, 0.07))
    for a in (math.radians(45), math.radians(135)):
        put("Paint", K.bar(Vector((0, bar_y, top)), Vector((2.0 * math.cos(a), bar_y, top + 2.0 * math.sin(a))), 0.08, 0.07, up=Y))
    put("Paint", sector(0, top, 1.88, 2.02, 0, math.pi, front - 0.02, front + 0.08, seg=20))
    for sx in (-1, 1):
        put("Paint", box(sx * 1.95, bar_y, 3.2, 0.12, 0.1, 6.0))
    sill = [(wall, 0.25), (0.46, 0.2), (0.52, 0.1), (0.46, -0.04), (0.36, -0.25), (wall, -0.25)]
    put("Paint", moulding(sill, 0.0, -2.7, 2.7))
    corbel = [(wall, -0.25), (0.3, -0.25), (0.3, -0.38), (wall + 0.12, -0.8), (wall, -0.8)]
    for sx in (-1, 1):
        put("Paint", K.side_prism(corbel, sx * 2.2 - 0.17, sx * 2.2 + 0.17))


# ---------------------------------------------------------------------------------- cornices

# A bracketed cornice's profile: (projection from the wall, height) from the frieze up to the
# crown, round the Cornice stand-in's centre (its box: 1.4 tall, 0.7 out from the wall)
CORNICE = [
    (0.0, -1.3), (0.12, -1.3), (0.12, -0.78), (0.18, -0.78), (0.24, -0.72), (0.28, -0.66), (0.3, -0.62),
    (0.3, -0.42), (0.34, -0.42), (0.34, -0.2), (0.62, -0.2), (0.62, 0.3), (0.64, 0.3), (0.66, 0.4),
    (0.69, 0.5), (0.7, 0.6), (0.7, 0.7), (0.0, 0.7),
]


def cornice():
    """One 6-stud run of a bracketed cornice: the frieze, a cove, the dentil course, scrolled
    modillions under the corona, an ogee crown (CityKit lays it round the roof, Kit_Cornice_Corner
    at the corners)."""
    put = kit("Kit_Cornice", (6, 1.4, 0.7), uv=7.0, ring=True, corner="Kit_Cornice_Corner")
    L = 6.0
    put("Paint", K.side_prism(CORNICE, -L / 2, L / 2))
    for i in range(12):
        x = -L / 2 + (i + 0.5) * L / 12
        put("Paint", box(x, 0.36, -0.52, 0.26, 0.12, 0.2))
    scroll = [(0.34, -0.2), (0.6, -0.2), (0.6, -0.26), (0.54, -0.3), (0.47, -0.33), (0.42, -0.38), (0.4, -0.42), (0.34, -0.42)]
    for i in range(3):
        x = -L / 2 + (i + 0.5) * L / 3
        put("Paint", K.side_prism(scroll, x - 0.16, x + 0.16))


def cornice_corner():
    """The mitred corner of the cornice: the profile swept round a right angle (each height a square
    out to the profile's projection), outside the corner of the walls."""
    put = kit("Kit_Cornice_Corner", (0.7, 1.4, 0.7), uv=7.0, spec=False)
    bm = bmesh.new()
    rows = []
    for g, z in CORNICE:
        g = max(g, 0.001)
        rows.append((bm.verts.new((g, 0, z)), bm.verts.new((g, g, z)), bm.verts.new((0, g, z)), bm.verts.new((0, 0, z))))
    for (a0, a1, a2, a3), (b0, b1, b2, b3) in zip(rows, rows[1:]):
        for f in ((a0, a1, b1, b0), (a1, a2, b2, b1), (a2, a3, b3, b2), (a3, a0, b0, b3)):
            try:
                bm.faces.new(f)
            except ValueError:
                pass
    for row in (rows[0], rows[-1]):
        try:
            bm.faces.new(row)
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    put("Paint", bm)


def string_course():
    """A moulded band between floors: a fillet, a half-round bead, a sloped weathering on top."""
    put = kit("Kit_StringCourse", (20, 0.6, 0.5), uv=7.0)
    L = 20.0
    band = [(-0.25, -0.3), (0.12, -0.3), (0.18, -0.25), (0.22, -0.16), (0.24, -0.06), (0.22, 0.04), (0.18, 0.1), (0.25, 0.12), (0.25, 0.22), (0.05, 0.3), (-0.25, 0.3)]
    put("Paint", K.side_prism(band, -L / 2, L / 2))


# ---------------------------------------------------------------------------------- towers and hotels


def tower_mullion():
    """A glass tower's curtain-wall mullion: the extrusion over the glass joint, a blade fin standing
    off it (its shadow lines run the tower's height), the pressure caps either side."""
    put = kit("Kit_TowerMullion", (0.5, 100, 0.6), uv=7.0, paint=(0.72, 0.74, 0.76))
    H = 100.0
    put("Paint", box(0, -0.05, 0, 0.42, 0.5, H))
    put("Paint", box(0, 0.42, 0, 0.14, 0.36, H))
    for sx in (-1, 1):
        put("Alu", box(sx * 0.22, 0.2, 0, 0.08, 0.06, H))


def lobby_column():
    """A tower lobby's column: a round stainless shaft on a stone plinth, a stone collar at its head."""
    put = kit("Kit_LobbyColumn", (1.8, 16, 1.8), uv=7.0, paint=(0.72, 0.73, 0.75))
    H = 16.0
    put("Paint", box(0, 0, -H / 2 + 0.5, 1.8, 1.8, 1.0, 0.04))
    put("Paint", box(0, 0, -H / 2 + 1.06, 1.6, 1.6, 0.12, 0.03))
    put("Metal", K.cyl(Vector((0, 0, -H / 2 + 1.1)), Vector((0, 0, H / 2 - 0.9)), 0.66, 0.66, 24))
    put("Black", K.cyl(Vector((0, 0, -H / 2 + 1.1)), Vector((0, 0, -H / 2 + 1.16)), 0.68, 0.68, 24))
    put("Paint", box(0, 0, H / 2 - 0.5, 1.7, 1.7, 1.0, 0.04))
    put("Paint", box(0, 0, H / 2 - 1.04, 1.5, 1.5, 0.1, 0.03))


def deco_eyebrow():
    """An Ocean Drive eyebrow: a thin cantilevered ledge with a rounded nose, a drip groove under it
    and three speed lines along its face (also the hotels' canopies, stretched)."""
    put = kit("Kit_DecoEyebrow", (40, 0.6, 3.2), uv=7.0, paint=(0.97, 0.9, 0.88))
    L = 40.0
    # (the wall at y = -1.5; the nose at y = 1.6)
    prof = [(-1.6, 0.3), (1.3, 0.3)]
    for i in range(1, 8):
        a = math.pi / 2 - i * math.pi / 8
        prof.append((1.3 + 0.3 * math.cos(a), 0.3 * math.sin(a)))
    prof += [(1.3, -0.3), (1.05, -0.3), (1.05, -0.24), (0.95, -0.24), (0.95, -0.3), (-1.6, -0.3)]
    put("Paint", K.side_prism(prof, -L / 2, L / 2))
    for z in (-0.12, 0.0, 0.12):
        put("Paint", box(0, 1.58, z, L, 0.06, 0.035))


# ---------------------------------------------------------------------------------- houses


def shutter():
    """A louvred shutter: stiles, three rails, angled louvres in two panels."""
    put = kit("Kit_Shutter", (1.6, 5, 0.3), uv=4.0, paint=(0.16, 0.27, 0.43))
    W, H, D = 1.6, 5.0, 0.3
    st, rl = 0.2, 0.26
    for sx in (-1, 1):
        put("Paint", box(sx * (W / 2 - st / 2), 0, 0, st, D, H, 0.02))
    for z in (H / 2 - rl / 2, -H / 2 + rl / 2, -0.25):
        put("Paint", box(0, 0, z, W - 2 * st + 0.02, D, rl, 0.02))
    tilt = Matrix.Rotation(math.radians(-40), 3, "X")
    for z0, z1 in ((-0.25 + rl / 2, H / 2 - rl), (-H / 2 + rl, -0.25 - rl / 2)):
        n = max(3, round((z1 - z0) / 0.22))
        for i in range(n):
            z = z0 + (i + 0.5) * (z1 - z0) / n
            put("Paint", K.rbox(Vector((0, 0, z)), (W - 2 * st + 0.02, 0.04, 0.3), 0.0, tilt))


def house_door():
    """A six-panel front door in its casing under a cap moulding, with a brass knob, deadbolt and
    kick plate."""
    put = kit("Kit_HouseDoor", (4, 7.5, 0.4), uv=4.0, paint=(0.35, 0.22, 0.16))
    H = 7.5
    dw, dh = 3.4, 7.0
    base = -H / 2
    leaf_z = base + dh / 2
    put("Paint", box(0, -0.1, leaf_z, dw, 0.18, dh))
    for zc, ph in ((base + 6.0, 0.95), (base + 3.95, 2.45), (base + 1.25, 1.85)):
        for xc in (-0.82, 0.82):
            put("Paint", box(xc, -0.0, zc, 1.2, 0.06, ph, 0.04))
            ring(put, "Paint", xc, zc, 1.36, ph + 0.16, 1.2, ph, -0.02, 0.04)
    for sx in (-1, 1):
        put("White", box(sx * (dw / 2 + 0.25), 0.02, base + (dh + 0.5) / 2, 0.5, 0.44, dh + 0.5, 0.03))
    put("White", box(0, 0.02, base + dh + 0.25, dw + 1.0, 0.44, 0.5, 0.03))
    cap = [(-0.2, 0.0), (0.36, 0.0), (0.42, 0.07), (0.42, 0.18), (0.34, 0.26), (-0.2, 0.26)]
    put("White", moulding(cap, base + dh + 0.5, -(dw / 2 + 0.75), dw / 2 + 0.75))
    put("Gold", K.sphere(Vector((1.25, 0.12, base + 3.3)), 0.14, 10, 6))
    put("Gold", K.disc(Vector((1.25, 0.0, base + 3.3)), Y, 0.16, 0.04, 12))
    put("Gold", K.disc(Vector((1.25, 0.0, base + 3.95)), Y, 0.12, 0.05, 12))
    put("Gold", box(0, 0.0, base + 0.35, dw - 0.3, 0.03, 0.55))


def garage_door():
    """A sectional garage door: four sections with raised panels, windows across the top one, the
    jambs and header trim, a lift handle, a rubber seal along the foot."""
    put = kit("Kit_GarageDoor", (12, 8, 0.3), uv=7.0, paint=(0.94, 0.94, 0.93))
    W, H = 12.0, 8.0
    secs = 4
    sh = H / secs
    for k in range(secs):
        zc = -H / 2 + (k + 0.5) * sh
        put("Paint", box(0, -0.02, zc, W - 0.1, 0.22, sh - 0.08, 0.03))
        if k == secs - 1:
            for i in range(4):
                x = -W / 2 + (i + 0.5) * W / 4
                put("Glass", box(x, 0.08, zc, W / 4 - 0.9, 0.04, sh - 0.8))
                ring(put, "Paint", x, zc, W / 4 - 0.6, sh - 0.5, W / 4 - 0.9, sh - 0.8, 0.06, 0.15)
        else:
            for i in range(8):
                x = -W / 2 + (i + 0.5) * W / 8
                put("Paint", box(x, 0.11, zc, W / 8 - 0.4, 0.08, sh - 0.6, 0.06))
    for sx in (-1, 1):
        put("White", box(sx * (W / 2 + 0.3), 0.02, 0.2, 0.6, 0.4, H + 0.4, 0.03))
    put("White", box(0, 0.02, H / 2 + 0.3, W + 1.2, 0.4, 0.6, 0.03))
    put("Metal", box(0, 0.17, -H / 2 + 0.7, 0.9, 0.12, 0.18, 0.04))
    put("Black", box(0, 0.0, -H / 2 + 0.05, W - 0.1, 0.24, 0.1))


def porch_post():
    """A colonial porch post: a base block, a chamfered shaft, a capital, and curved brackets."""
    put = kit("Kit_PorchPost", (0.6, 9, 0.6), uv=4.0, paint=(0.97, 0.97, 0.96))
    H = 9.0
    z0 = -H / 2
    put("Paint", box(0, 0, z0 + 0.45, 0.78, 0.78, 0.9, 0.03))
    put("Paint", box(0, 0, z0 + 0.95, 0.7, 0.7, 0.1, 0.02))
    s, c = 0.26, 0.07
    octagon = [(-s + c, -s), (s - c, -s), (s, -s + c), (s, s - c), (s - c, s), (-s + c, s), (-s, s - c), (-s, -s + c)]
    put("Paint", K.prism(octagon, H - 2.0, Vector((0, 0, z0 + 1.0)), X, Y, Z))
    put("Paint", box(0, 0, H / 2 - 0.75, 0.68, 0.68, 0.1, 0.02))
    put("Paint", box(0, 0, H / 2 - 0.4, 0.76, 0.76, 0.6, 0.03))
    put("Paint", box(0, 0, H / 2 - 0.05, 0.86, 0.86, 0.1, 0.02))
    bracket = [(0.0, 0.0), (0.1, 0.0), (0.22, 0.38), (0.5, 0.7), (0.95, 0.88), (1.1, 0.9), (1.1, 1.05), (0.0, 1.05)]
    for sx in (-1, 1):
        pts = [(sx * (0.26 + u), v) for u, v in bracket]
        put("Paint", K.prism(pts, 0.14, Vector((0, -0.07, H / 2 - 1.15)), X, Z, Y))


def column():
    """A Tuscan column: a square plinth, a torus base, a shaft with entasis, an astragal, the neck,
    the echinus and a square abacus."""
    put = kit("Kit_Column", (1.4, 9, 1.4), uv=7.0, paint=(0.93, 0.91, 0.86))
    H = 9.0
    z0 = -H / 2
    put("Paint", box(0, 0, z0 + 0.18, 1.5, 1.5, 0.36, 0.02))
    prof = [(0.0, 0.0), (0.0, 0.68), (0.08, 0.715), (0.17, 0.7), (0.22, 0.63), (0.28, 0.585), (0.34, 0.57)]
    shaft = 7.0
    for i in range(1, 9):
        f = i / 8
        taper = max(0.0, (f - 0.33) / 0.67) ** 1.4
        prof.append((0.34 + f * shaft, 0.57 - 0.09 * taper))
    t = 0.34 + shaft
    prof += [(t, 0.52), (t + 0.03, 0.545), (t + 0.11, 0.545), (t + 0.14, 0.52), (t + 0.14, 0.49), (t + 0.5, 0.49), (t + 0.5, 0.5), (t + 0.58, 0.57), (t + 0.66, 0.64), (t + 0.74, 0.69), (t + 0.76, 0.7), (t + 0.76, 0.0)]
    put("Paint", K.lathe(Vector((0, 0, z0 + 0.36)), Z, prof, 16))
    put("Paint", box(0, 0, H / 2 - 0.34, 1.5, 1.5, 0.4, 0.02))
    put("Paint", box(0, 0, H / 2 - 0.07, 1.56, 1.56, 0.14, 0.02))


def iron_rail():
    """One module of a wrought-iron balcony rail: a round handrail, rails, balusters and rings."""
    put = kit("Kit_IronRail", (4, 2.4, 0.2), tile="Y", uv=2.0, paint=(0.1, 0.1, 0.11))
    W, H = 4.0, 2.4
    put("Paint", K.cyl(Vector((-W / 2, 0, H / 2 - 0.09)), Vector((W / 2, 0, H / 2 - 0.09)), 0.09, 0.09, 8))
    put("Paint", box(0, 0, -H / 2 + 0.08, W, 0.1, 0.1))
    put("Paint", box(0, 0, H / 2 - 0.42, W, 0.06, 0.06))
    n = 10
    for i in range(n):
        x = -W / 2 + (i + 0.5) * W / n
        put("Paint", box(x, 0, -0.15, 0.06, 0.06, H - 0.6))
        if i < n - 1:
            put("Paint", K.torus(Vector((x + W / n / 2, 0, H / 2 - 0.62)), Y, 0.15, 0.022, 12, 4))
    put("Paint", box(-W / 2 + 0.05, 0, 0, 0.1, 0.1, H))


# ---------------------------------------------------------------------------------- roofs


def ac_unit():
    """A rooftop condensing unit: base rails, a cabinet with corner posts, louvred coil guards, a
    service panel with its disconnect box and line set, the fan under its wire guard on top."""
    put = kit("Kit_ACUnit", (6, 3.4, 4.5), uv=4.0, paint=(0.77, 0.78, 0.78))
    W, H, D = 6.0, 3.4, 4.5
    for sy in (-1, 1):
        put("Dark", box(0, sy * (D / 2 - 0.45), -H / 2 + 0.12, W, 0.4, 0.24))
    put("Paint", box(0, 0, -H / 2 + 0.32, W - 0.1, D - 0.1, 0.16))
    put("Dark", box(0, 0, 0.0, W - 0.6, D - 0.6, H - 0.8))
    for sx in (-1, 1):
        for sy in (-1, 1):
            put("Paint", box(sx * (W / 2 - 0.2), sy * (D / 2 - 0.2), 0.05, 0.4, 0.4, H - 0.6, 0.03))
    put("Paint", box(0, 0, H / 2 - 0.2, W, D, 0.4, 0.05))
    fins = 7
    for k in range(fins):
        z = -H / 2 + 0.6 + (k + 0.5) * (H - 1.3) / fins
        for sy in (-1, 1):
            put("Paint", box(0, sy * (D / 2 - 0.22), z, W - 0.8, 0.06, 0.1))
        put("Paint", box(W / 2 - 0.22, 0, z, 0.06, D - 0.8, 0.1))
    put("Paint", box(-W / 2 + 0.3, 0, 0.0, 0.1, D - 0.8, H - 0.9))
    put("Dark", box(-W / 2 + 0.1, -1.1, 0.25, 0.3, 0.8, 1.0, 0.04))
    for dy, r in ((0.6, 0.12), (1.1, 0.08)):
        a = Vector((-W / 2 + 0.25, dy, -0.6))
        put("Metal", K.cyl(a, a - X * 0.6, r, r, 8))
        put("Black", K.cyl(a - X * 0.6, a - X * 0.6 - Z * 0.8, r + 0.03, r + 0.03, 8))
    c = Vector((0, 0, H / 2 + 0.01))
    put("Black", K.cyl(c, c + Z * 0.05, 1.65, 1.65, 28))
    for r in (1.75, 1.2, 0.65):
        put("Dark", K.torus(c + Z * 0.12, Z, r, 0.03, 24 if r > 1 else 14, 3))
    for i in range(8):
        a = i * math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        put("Dark", K.bar(c + Z * 0.12 + d * 0.2, c + Z * 0.12 + d * 1.78, 0.05, 0.05))
    put("Dark", K.cyl(c + Z * 0.05, c + Z * 0.2, 0.22, 0.22, 12))


# ---------------------------------------------------------------------------------- streets


def light_pole():
    """A tapered steel light or signal pole on a base plate with anchor bolts, a hand-hole cover and a
    cap (stand-in: PartKit.Post, standing on its X axis)."""
    put = kit("Kit_LightPole", (0.8, 26, 0.8), uv=7.0, paint=(0.47, 0.49, 0.5))
    H = 26.0
    z0 = -H / 2
    put("Paint", K.cyl(Vector((0, 0, z0 + 0.2)), Vector((0, 0, H / 2 - 0.3)), 0.4, 0.26, 16))
    put("Paint", box(0, 0, z0 + 0.1, 1.3, 1.3, 0.2, 0.04))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p = Vector((sx * 0.48, sy * 0.48, z0 + 0.2))
            put("Metal", K.cyl(p, p + Z * 0.24, 0.06, 0.06, 6))
            put("Metal", K.cyl(p, p + Z * 0.1, 0.1, 0.1, 6))
    put("Paint", box(0, 0.37, z0 + 2.2, 0.36, 0.08, 0.8, 0.03))
    put("Paint", K.lathe(Vector((0, 0, H / 2 - 0.3)), Z, [(0, 0.28), (0.15, 0.27), (0.25, 0.18), (0.3, 0.0)], 16))


def light_base():
    """The cast cover round a street light's base."""
    put = kit("Kit_LightBase", (1.4, 1.2, 1.4), uv=4.0, paint=(0.47, 0.49, 0.5))
    put("Paint", K.lathe(Vector((0, 0, -0.6)), Z, [(0.0, 0.0), (0.0, 0.7), (0.12, 0.7), (0.18, 0.64), (0.6, 0.56), (0.9, 0.5), (1.05, 0.46), (1.1, 0.48), (1.2, 0.44), (1.2, 0.0)], 16))


def light_arm():
    """A tapered davit arm (stand-in: PartKit.Bar, its far end toward the head), with a clamp at
    the pole and a tenon for the luminaire."""
    put = kit("Kit_LightArm", (0.4, 0.4, 7.0711), uv=4.0, paint=(0.47, 0.49, 0.5))
    L = 7.0711
    put("Paint", K.cyl(Vector((0, -L / 2, 0)), Vector((0, L / 2, 0)), 0.2, 0.13, 12))
    put("Paint", K.lathe(Vector((0, -L / 2, 0)), Y, [(0.0, 0.0), (0.0, 0.27), (0.35, 0.27), (0.4, 0.22), (0.4, 0.0)], 12))
    put("Paint", K.lathe(Vector((0, L / 2 - 0.12, 0)), Y, [(0.0, 0.0), (0.0, 0.16), (0.12, 0.16), (0.12, 0.0)], 12))


def light_head():
    """An LED cobra-head luminaire: a smooth housing swelling from the arm's tenon, cooling fins and
    a photocell on top, a bezel round the lens (the stand-in's glowing lens stays a part)."""
    put = kit("Kit_LightHead", (1.8, 0.7, 3.6), uv=4.0, paint=(0.62, 0.64, 0.66))
    sections = [
        (Vector((0, -1.8, 0.0)), 0.2, 0.18, 2.4),
        (Vector((0, -1.5, 0.02)), 0.42, 0.26, 3.0),
        (Vector((0, -0.95, 0.04)), 0.8, 0.31, 3.5),
        (Vector((0, -0.25, 0.05)), 0.9, 0.33, 4.0),
        (Vector((0, 0.6, 0.04)), 0.88, 0.32, 4.0),
        (Vector((0, 1.3, 0.0)), 0.74, 0.27, 3.5),
        (Vector((0, 1.68, -0.05)), 0.5, 0.18, 3.0),
        (Vector((0, 1.8, -0.08)), 0.28, 0.1, 2.5),
    ]
    put("Paint", K.loft(sections, 24, True, axis="Y"))
    for i in range(5):
        put("Paint", box(-0.5 + i * 0.25, 0.05, 0.37, 0.05, 2.0, 0.08))
    put("Black", K.cyl(Vector((0, -0.75, 0.33)), Vector((0, -0.75, 0.48)), 0.11, 0.1, 10))
    for sx in (-1, 1):
        put("Black", box(sx * 0.7, 0, -0.3, 0.1, 2.8, 0.05))
    for sy in (-1, 1):
        put("Black", box(0, sy * 1.35, -0.3, 1.5, 0.1, 0.05))


def signal_head():
    """A three-section traffic signal: each section's housing and door ring round its lamp (the
    stand-in's lamps stay parts: Visuals switches them), tunnel visors, a backplate with a yellow
    retroreflective border, the hanger up to the mast arm."""
    put = kit("Kit_SignalHead", (1.6, 4.4, 1.2), uv=4.0, paint=(0.9, 0.75, 0.12))
    for zc in (1.35, 0.0, -1.35):
        put("Paint", box(0, -0.05, zc, 1.42, 1.0, 1.32, 0.12))
        put("Paint", K.lathe(Vector((0, 0, zc)), Y, [(0.45, 0.52), (0.45, 0.74), (0.55, 0.74), (0.55, 0.52), (0.45, 0.52)], 20))
        put("Black", sector(0, zc, 0.78, 0.84, math.radians(-15), math.radians(195), 0.6, 1.5, seg=18))
    put("Black", box(0, -0.6, 0, 2.6, 0.06, 5.4, 0.15))
    for cz, sx, sz in ((2.63, 2.5, 0.14), (-2.63, 2.5, 0.14)):
        put("Yellow", box(0, -0.565, cz, sx, 0.02, sz))
    for sx in (-1, 1):
        put("Yellow", box(sx * 1.23, -0.565, 0, 0.14, 0.02, 5.2))
    put("Dark", K.cyl(Vector((0, -0.05, 2.1)), Vector((0, -0.05, 2.45)), 0.12, 0.12, 10))


# ---------------------------------------------------------------------------------- round 2

# (also written on their own to CityKitRound2.fbx, for an owner whose CityKit import is in already:
# re-importing all of CityKit.fbx would replace the trees SetupRealism textured)
ROUND2 = ("Kit_RollUpDoor", "Kit_GlassRail", "Kit_BusShelter", "Kit_GasCanopy")


def roll_up_door():
    """A roll-up loading door: the slatted steel curtain (a ridge at every slat joint), the guide
    channels either side, the coil hood over the opening, a bottom bar with its rubber seal and a
    lift handle. (Warehouses, the courier depot, the race plaza's pit garages.)"""
    put = kit("Kit_RollUpDoor", (14, 13, 0.6), uv=4.0, paint=(0.78, 0.79, 0.8))
    W, H = 14.0, 13.0
    put("Paint", box(0, 0.0, 0, W - 0.8, 0.06, H))
    slats = 24
    for k in range(1, slats):
        z = -H / 2 + k * H / slats
        put("Paint", box(0, 0.06, z, W - 0.8, 0.1, 0.14))
    for sx in (-1, 1):
        put("Dark", box(sx * (W / 2 - 0.25), 0.12, 0, 0.5, 0.36, H))
    put("Dark", box(0, 0.45, H / 2 + 0.75, W + 0.3, 1.1, 1.5, 0.25))
    put("Alu", box(0, 0.12, -H / 2 + 0.2, W - 0.8, 0.26, 0.34))
    put("Black", box(0, 0.08, -H / 2 + 0.03, W - 0.8, 0.18, 0.06))
    put("Alu", box(0, 0.32, -H / 2 + 1.1, 1.4, 0.12, 0.2))


def glass_rail():
    """A condo floor's balcony rail all the way round (one mesh per floor, stretched to it, to keep
    the towers' instance count down): frameless glass on an aluminium shoe under a handrail, posts
    at the corners. Its stand-in is the floor's rail box (the ring's outside)."""
    put = kit("Kit_GlassRail", (60, 3.6, 60), uv=7.0, paint=(0.75, 0.84, 0.88))
    R, H = 30.0, 3.6
    for a, b, sx, sy in ((0, R - 0.18, 2 * R, 0.1), (0, -(R - 0.18), 2 * R, 0.1), (R - 0.18, 0, 0.1, 2 * R), (-(R - 0.18), 0, 0.1, 2 * R)):
        put("ClearGlass", box(a, b, -0.05, sx - 0.4, sy, H - 0.6))
    for a, b, sx, sy in ((0, R - 0.15, 2 * R, 0.3), (0, -(R - 0.15), 2 * R, 0.3), (R - 0.15, 0, 0.3, 2 * R), (-(R - 0.15), 0, 0.3, 2 * R)):
        put("Alu", box(a, b, H / 2 - 0.11, sx, sy, 0.22))
        put("Alu", box(a, b, -H / 2 + 0.12, sx, sy, 0.24))
    for sx in (-1, 1):
        for sy in (-1, 1):
            put("Alu", box(sx * (R - 0.15), sy * (R - 0.15), 0, 0.3, 0.3, H))


def bus_shelter():
    """A bus shelter, fitted to its roof (the shelter hangs below it to the pavement, 9 studs down):
    the canopy with its fascia and gutter, round steel posts, framed glass at the back and sides, a
    slatted bench on brackets, the route map. Detail.BusStop's posts, glass and bench are its drops;
    the ad panel and the stop's sign stay parts."""
    put = kit("Kit_BusShelter", (14, 0.5, 6), uv=4.0, paint=(0.16, 0.17, 0.2))
    G = -9.0  # the pavement, from the roof's middle
    put("Paint", box(0, 0, 0.05, 14.4, 6.4, 0.3, 0.08))
    put("Dark", box(0, 3.15, -0.05, 14.4, 0.3, 0.8, 0.05))
    put("Alu", box(0, -3.25, -0.12, 14.4, 0.32, 0.32))
    for x, y in ((-6.6, -2.6), (6.6, -2.6), (-6.6, 1.8), (6.6, 1.8)):
        put("Dark", K.cyl(Vector((x, y, G)), Vector((x, y, -0.15)), 0.2, 0.2, 10))
    # the glass: the back wall and the two side screens, each in a frame
    put("ClearGlass", box(0, -2.8, -4.5, 12.8, 0.1, 5.8))
    for z in (-1.5, -7.5):
        put("Dark", box(0, -2.8, z, 13.2, 0.18, 0.2))
    for sx in (-1, 1):
        put("ClearGlass", box(sx * 6.6, -0.5, -4.5, 0.1, 4.4, 5.8))
        for z in (-1.5, -7.5):
            put("Dark", box(sx * 6.6, -0.5, z, 0.18, 4.6, 0.2))
    # the bench: four slats on two brackets
    for k in range(4):
        put("Wood", box(0, -2.35 + k * 0.38, -7.2, 10, 0.3, 0.14, 0.03))
    for sx in (-1, 1):
        put("Dark", box(sx * 4, -1.8, -8.1, 0.25, 1.4, 1.8))
    put("White", box(4.4, -2.72, -4.3, 2.4, 0.06, 3.2))
    put("Blue", box(4.4, -2.68, -2.85, 2.4, 0.04, 0.3))


def gas_canopy():
    """A gas station's canopy over the pumps: the deck with a rounded edge and an aluminium cap,
    the soffit underneath with recessed LED panels over the islands. The brand band round its edge
    stays a part (its colour is the brand's)."""
    put = kit("Kit_GasCanopy", (70, 2.6, 42), uv=7.0, paint=(0.98, 0.98, 0.97))
    W, D, H = 70.0, 42.0, 2.6
    put("Paint", box(0, 0, 0.15, W, D, H - 0.3, 0.25, seg=2))
    put("White", box(0, 0, -H / 2 + 0.1, W - 0.6, D - 0.6, 0.12))
    for a, b, sx, sy in ((0, D / 2, W + 0.2, 0.3), (0, -D / 2, W + 0.2, 0.3), (W / 2, 0, 0.3, D + 0.2), (-W / 2, 0, 0.3, D + 0.2)):
        put("Alu", box(a, b, H / 2 - 0.05, sx, sy, 0.3))
    for i in range(4):
        for j in range(2):
            x = -W * 0.36 + i * W * 0.24
            y = -D * 0.22 + j * D * 0.44
            put("NeonWhite", box(x, y, -H / 2 - 0.02, 7, 4.2, 0.06))
            put("Alu", box(x, y, -H / 2 - 0.01, 7.6, 4.8, 0.04))



# ---------------------------------------------------------------------------------- round 3
# The detail pass's street kits (also written on their own to CityKitDetail.fbx: K.detail)


def ped_signal():
    """A pedestrian signal head: a housing round the two lamps (the stand-in's PedStop / PedWalk
    parts stay: Visuals lights them), an egg-crate hood over each, a clamp back to the pole."""
    put = kit(K.detail("Kit_PedSignal"), (1.3, 2.5, 0.9), uv=4.0, paint=(0.9, 0.75, 0.12))
    put("Paint", box(0, -0.05, 0, 1.3, 0.8, 2.5, 0.08))
    for zc in (0.58, -0.58):
        # (the hood: a top and two cheeks round each lamp, open below)
        put("Black", box(0, 0.62, zc + 0.5, 1.12, 0.36, 0.06))
        for sx in (-1, 1):
            put("Black", box(sx * 0.53, 0.62, zc + 0.1, 0.05, 0.36, 0.86))
        put("Black", box(0, 0.44, zc, 1.06, 0.03, 1.02))
    put("Dark", box(0, -0.55, 0.9, 0.5, 0.3, 0.25))
    put("Dark", box(0, -0.55, -0.9, 0.5, 0.3, 0.25))


def signal_cabinet():
    """A traffic signal controller's cabinet on the corner: a rain cap, two doors with seams and a
    handle, louvred vents down the sides, a base flange on its plinth."""
    put = kit(K.detail("Kit_SignalCabinet"), (3.4, 5.4, 2.4), uv=4.0, paint=(0.59, 0.61, 0.59))
    W, H, D = 3.4, 5.4, 2.4
    put("Paint", box(0, 0, -0.05, W, D, H - 0.1, 0.05))
    put("Paint", box(0, 0, H / 2 - 0.05, W + 0.2, D + 0.2, 0.2, 0.06))
    put("Paint", box(0, 0, H / 2 + 0.1, W - 0.4, D - 0.4, 0.1, 0.04))
    put("Dark", box(0, D / 2 + 0.01, 0, 0.04, 0.02, H - 0.6))
    for sx in (-1, 1):
        put("Dark", box(sx * (W / 2 - 0.12), D / 2 + 0.01, 0, 0.03, 0.02, H - 0.5))
        put("Metal", box(sx * 0.35, D / 2 + 0.05, 0.2, 0.12, 0.08, 0.5, 0.02))
        for k in range(6):
            put("Dark", box(sx * (W / 2 + 0.01), 0, -H / 2 + 0.9 + k * 0.22, 0.03, D * 0.6, 0.06))
    put("Dark", box(0, 0, -H / 2 + 0.06, W + 0.15, D + 0.15, 0.12))


def utility_pole():
    """A wooden utility pole (stand-in: PartKit.Post on its X axis): a tapered, checked pole, the
    crossarm across the line with braces and three pin insulators, step bolts and a tag, the
    ground wire down the side."""
    put = kit(K.detail("Kit_UtilityPole"), (1.1, 34, 1.1), uv=4.0, paint=(0.44, 0.36, 0.28))
    H = 34.0
    z0 = -H / 2
    put("Paint", K.cyl(Vector((0, 0, z0)), Vector((0, 0, H / 2 - 0.2)), 0.6, 0.42, 12))
    put("Paint", K.lathe(Vector((0, 0, H / 2 - 0.2)), Z, [(0, 0.42), (0.12, 0.38), (0.2, 0.0)], 12))
    arm = H / 2 - 1.5
    put("Paint", box(0, 0, arm, 0.45, 9.0, 0.45, 0.04))
    for sy in (-1, 1):
        put("Metal", K.cyl(Vector((0, 0.42 * sy, arm - 2.4)), Vector((0, 2.4 * sy, arm - 0.2)), 0.07, 0.07, 6))
    for y in (-4.0, 0.0, 4.0):
        put("Metal", K.cyl(Vector((0, y, arm + 0.2)), Vector((0, y, arm + 0.5)), 0.06, 0.06, 6))
        for k in range(3):
            put("White", K.cyl(Vector((0, y, arm + 0.5 + k * 0.18)), Vector((0, y, arm + 0.62 + k * 0.18)), 0.2 - k * 0.03, 0.2 - k * 0.03, 10))
    for k in range(9):
        a = math.radians(90 + 180 * (k % 2))
        z = z0 + 8 + k * 2.2
        put("Metal", K.cyl(Vector((0.5 * math.cos(a), 0.5 * math.sin(a), z)), Vector((0.85 * math.cos(a), 0.85 * math.sin(a), z)), 0.05, 0.05, 6))
    put("Metal", box(0, 0.6, z0 + 6, 0.36, 0.03, 0.24))
    put("Dark", box(0.55, 0, 0, 0.05, 0.05, H - 2))


def pole_transformer():
    """A pole-top transformer can (stand-in: a cylinder on its X axis): a domed lid, two bushings
    up top, a hanger bracket to the pole."""
    put = kit(K.detail("Kit_PoleTransformer"), (2.2, 3.4, 2.2), uv=4.0, paint=(0.51, 0.53, 0.52))
    put("Paint", K.cyl(Vector((0, 0, -1.6)), Vector((0, 0, 1.4)), 1.08, 1.08, 18))
    put("Paint", K.lathe(Vector((0, 0, 1.4)), Z, [(0, 1.12), (0.12, 1.06), (0.26, 0.6), (0.3, 0.0)], 18))
    put("Paint", box(0, 0, -1.65, 1.6, 1.6, 0.15, 0.05))
    for x in (-0.45, 0.45):
        for k in range(3):
            put("White", K.cyl(Vector((x, 0, 1.55 + k * 0.16)), Vector((x, 0, 1.66 + k * 0.16)), 0.16 - k * 0.02, 0.16 - k * 0.02, 10))
    put("Dark", box(0, -1.2, 0.3, 0.6, 0.5, 2.6, 0.04))


def stop_sign():
    """A stop sign's octagonal plate with its white border, a grey back and two clamps to the pole
    (the STOP lettering stays on the hidden stand-in: CityKit keeps a stand-in that carries a sign)."""
    put = kit(K.detail("Kit_StopSign"), (2.5, 2.5, 0.1), uv=2.0, paint=(0.77, 0.09, 0.12))
    R = 1.25 / math.cos(math.radians(22.5))

    def octagon(r):
        return [(r * math.cos(math.radians(22.5 + 45 * k)), r * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]

    put("Paint", K.prism(octagon(R * 0.9), 0.05, Vector((0, -0.02, 0)), X, Z, Y))
    outer, inner = octagon(R), octagon(R * 0.9)
    for k in range(8):
        a, b = outer[k], outer[(k + 1) % 8]
        c, d = inner[(k + 1) % 8], inner[k]
        put("White", K.prism([a, b, c, d], 0.05, Vector((0, -0.02, 0)), X, Z, Y))
    put("Metal", K.prism(octagon(R), 0.03, Vector((0, -0.06, 0)), X, Z, Y))
    for z in (0.55, -0.55):
        put("Dark", box(0, -0.12, z, 0.5, 0.12, 0.14))


def build_all():
    shop_mullion()
    shop_transom()
    fascia()
    bulkhead()
    shop_door()
    shop_door_frame()
    awning_stripe()
    window_modern()
    window_house()
    window_arched()
    shutter()
    house_door()
    garage_door()
    porch_post()
    column()
    iron_rail()
    ac_unit()
    cornice()
    cornice_corner()
    string_course()
    tower_mullion()
    lobby_column()
    deco_eyebrow()
    light_pole()
    light_base()
    light_arm()
    light_head()
    signal_head()
    roll_up_door()
    glass_rail()
    bus_shelter()
    gas_canopy()
    ped_signal()
    signal_cabinet()
    utility_pole()
    pole_transformer()
    stop_sign()
    return SPECS


def write_spec(path):
    """KitSpec.luau: each stand-in kit's reference box (and tiling) for Models/CityKit."""
    lines = [
        "--[[",
        "\tKitSpec: generated by blender/build_vehicles.py (blender/facadekit.py). Do not edit by hand.",
        "",
        "\tFor every city kit fitted to a stand-in part (PartKit.Kit), the box it was modelled on: the part's",
        "\tsize in the design city (studs), x along the wall, y up, z into the wall (the front is -z).",
        "\tModels/CityKit scales the kit by the part's size over this box. A tiled kit (Tile = the axis whose",
        "\tscale sets the module's size) is laid along x as many times as fit, each one kept in proportion.",
        "\tA ring kit (a cornice) runs round the part's box, the box its outside: modules along each wall",
        "\t(Reference: a module's length, height and projection) and the Corner kit at each corner.",
        "]]",
        "",
        "export type Spec = { Reference: Vector3, Tile: string?, Ring: boolean?, Corner: string? }",
        "",
        "local S: { [string]: Spec } = {",
    ]
    for name in sorted(SPECS):
        spec = SPECS[name]
        r = spec["Reference"]
        extra = f', Tile = "{spec["Tile"]}"' if spec["Tile"] else ""
        if spec.get("Ring"):
            extra += f', Ring = true, Corner = "{spec["Corner"]}"'
        lines.append(f'\t["{name}"] = {{ Reference = Vector3.new({r[0]:.4f}, {r[1]:.4f}, {r[2]:.4f}){extra} }},')
    lines += ["}", "", "return S", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))
