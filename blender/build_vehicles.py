"""
Builds every Flightly bike and every car as meshes, split by moving part and paint slot, and
exports blender/out/Vehicles.fbx plus src/shared/Models/MeshManifest.luau.

    /root/tools/blendenv/bin/python blender/build_vehicles.py [--render id,id,...] [--only id,id]

Run `lune run tools/lune/export_vehicles.luau` first: blender/vehicles.json holds the rig points
the game uses (axles, head tube, bottom bracket, bars, saddle), so the meshes line up with the
joints that steer, spin the wheels and turn the cranks.

In Roblox Studio: File > Import 3D, pick Vehicles.fbx, and put the imported model in
ReplicatedStorage, named VehicleMeshes (one child model per vehicle id). The game uses those
MeshParts when they're there and falls back to its part-built models when they're not.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshkit as K  # noqa: E402
import emoto  # noqa: E402
import citykit  # noqa: E402
from meshkit import B, Vector as V  # noqa: E402,F401

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = json.load(open(os.path.join(HERE, "vehicles.json")))

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))  # forward
Z = Vector((0, 0, 1))  # up

TUBE = {"City": 0.055, "Folding": 0.065, "Cruiser": 0.055, "Cargo": 0.06, "Fat": 0.065, "Hardtail": 0.06, "Road": 0.048, "Enduro": 0.07, "Moped": 0.06, "Moto": 0.07}

# Fixed slots (colour + material in the game come from MeshKit.SLOTS on the Luau side)
SLOT_COLORS = {
    "Stone": (0.78, 0.76, 0.7),
    "Bark": (0.3, 0.22, 0.16),
    "Birch": (0.86, 0.85, 0.8),
    "Black": (0.10, 0.10, 0.11),
    "Dark": (0.20, 0.21, 0.23),
    "Metal": (0.75, 0.75, 0.77),
    "Gold": (0.80, 0.62, 0.15),
    "Tire": (0.07, 0.07, 0.08),
    "Leather": (0.13, 0.11, 0.10),
    "Brown": (0.35, 0.22, 0.13),
    "Wood": (0.55, 0.38, 0.22),
    "NeonWhite": (1.0, 0.98, 0.9),
    "NeonRed": (1.0, 0.1, 0.1),
    "NeonAmber": (1.0, 0.55, 0.05),
    "NeonCyan": (0.45, 0.9, 1.0),
    "NeonGreen": (0.3, 1.0, 0.4),
    "Glass": (0.10, 0.13, 0.17),
    "Chrome": (0.85, 0.86, 0.88),
    "Interior": (0.18, 0.17, 0.17),
    "White": (0.95, 0.95, 0.95),
    "Orange": (1.0, 0.45, 0.05),
}


def arg(name):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1].split(",")
    return None


# =============================================================================== wheels


def wheel(group, axle, D, tw, kind, knobby, hub_motor=False, rotor_side=-1, rotor_d=0.18, cassette=False, sprocket=False, spokes=None, spoke_slot="Metal", cast=False, stripe=None):
    put = lambda slot, bm: K.put(group, slot, bm)  # noqa: E731
    moto = kind == "Moto"
    tyre_h = max(tw, D * 0.135) if moto else tw * (0.9 if tw > 0.09 else 0.95)
    R = D / 2 - tyre_h / 2
    put("Tire", K.torus(axle, X, R, tyre_h / 2, 56 if D > 0.6 else 48, 14, squash=tw / tyre_h))
    if knobby:
        count = int(math.pi * D / (0.06 if moto else 0.05))
        knob_h = 0.012 if not moto else 0.016

        def knob(i, t, radial, tangent):
            offsets = [(-0.24,), (0.24,)][i % 2]
            if tw > 0.075:
                offsets = [(-0.3, 0.3), (0.0,)][i % 2]
            pieces = []
            for o in offsets:
                ox = o * tw
                surface = R + math.sqrt(max(0.0, (tyre_h / 2) ** 2 - (ox * tyre_h / tw) ** 2))
                center = axle + X * ox + radial * (surface + knob_h * 0.2)
                rot = K.frame_rot(X, tangent, radial)
                pieces.append(K.rbox(center, (tw * 0.26, math.pi * D / count * 0.48, knob_h), 0.003, rot, 1))
            return pieces

        for i in range(count):
            t = 2 * math.pi * i / count
            radial = Vector((0, math.cos(t), math.sin(t)))
            tangent = X.cross(radial)
            for piece in knob(i, t, radial, tangent):
                put("Tire", piece)
    if stripe:
        # reflective / cream band on the sidewalls
        for side in (-1, 1):
            put(stripe, K.torus(axle + X * side * tw * 0.36, X, R - tyre_h * 0.18, tyre_h * 0.1, 48, 6, squash=0.35))

    rim_d = D - 2 * tyre_h + 0.01
    rim_h = 0.03 if moto else (0.028 if tw > 0.09 else 0.022)
    rim_w = tw * (0.8 if tw > 0.09 else 0.7) if moto or tw > 0.07 else max(tw * 0.62, 0.022)
    r_out, r_in = rim_d / 2, rim_d / 2 - rim_h
    w = rim_w / 2
    put("Rims", K.lathe(axle, X, [(-w, r_in + 0.004), (-w, r_out), (-w * 0.6, r_out + 0.003), (w * 0.6, r_out + 0.003), (w, r_out), (w, r_in + 0.004), (w * 0.4, r_in), (-w * 0.4, r_in), (-w, r_in + 0.004)], 64))

    # hub
    if hub_motor:
        hub_r, flange_x = 0.095, 0.04
        put("Dark", K.lathe(axle, X, [(-0.07, 0), (-0.07, 0.02), (-0.055, 0.03), (-0.05, 0.085), (-0.04, 0.1), (0.04, 0.1), (0.05, 0.085), (0.055, 0.03), (0.07, 0.02), (0.07, 0)], 40))
        put("Accent", K.lathe(axle, X, [(0.051, 0), (0.051, 0.07), (0.056, 0.06), (0.056, 0)], 32))
    elif moto:
        hub_r, flange_x = 0.05, 0.05
        put("Metal", K.lathe(axle, X, [(-0.085, 0), (-0.085, 0.02), (-0.06, 0.03), (-0.05, 0.06), (0.05, 0.06), (0.06, 0.03), (0.085, 0.02), (0.085, 0)], 32))
    else:
        hub_r, flange_x = 0.028, 0.032
        put("Dark", K.lathe(axle, X, [(-0.075, 0), (-0.075, 0.008), (-0.04, 0.012), (-flange_x, 0.03), (-flange_x + 0.004, 0.03), (-0.02, 0.016), (0.02, 0.016), (flange_x - 0.004, 0.03), (flange_x, 0.03), (0.04, 0.012), (0.075, 0.008), (0.075, 0)], 24))

    # spokes
    spoke_r = r_in + 0.002
    if cast:
        for i in range(6):
            t = 2 * math.pi * i / 6
            radial = Vector((0, math.cos(t), math.sin(t)))
            tangent = X.cross(radial)
            put("Rims", K.bar(axle + radial * 0.04, axle + radial * (spoke_r + 0.004), 0.035, 0.03, 0.006, up=X))
            put("Rims", K.bar(axle + radial * 0.04 + tangent * 0.01, axle + (radial * math.cos(0.25) + tangent * math.sin(0.25)) * (spoke_r + 0.004), 0.02, 0.02, 0.004, up=X))
        put("Dark", K.lathe(axle, X, [(-0.06, 0), (-0.06, 0.06), (0.06, 0.06), (0.06, 0)], 24))
    else:
        n = spokes or (24 if moto else (16 if hub_motor else 20))
        per_side = n // 2
        lace = 0.12 if hub_motor else (0.3 if moto else 0.42)
        thick = 0.0042 if not moto else 0.0065
        for side in (-1, 1):
            for i in range(per_side):
                t = 2 * math.pi * i / per_side + (math.pi / per_side if side > 0 else 0)
                d = 1 if i % 2 == 0 else -1
                p_hub = axle + Vector((side * flange_x, hub_r * math.cos(t), hub_r * math.sin(t)))
                p_rim = axle + Vector((side * rim_w * 0.12, spoke_r * math.cos(t + d * lace), spoke_r * math.sin(t + d * lace)))
                put(spoke_slot, K.cyl(p_hub, p_rim, thick, thick, 6, False))

    # brake rotor
    rx = rotor_side * (flange_x + (0.035 if moto else 0.018))
    ro, ri = rotor_d / 2, rotor_d / 2 - (0.03 if moto else 0.02)
    rc = axle + X * rx
    put("Metal", K.lathe(rc, X, [(-0.001, ri), (-0.001, ro), (0.001, ro), (0.001, ri), (-0.001, ri)], 48))
    for i in range(5 if not moto else 6):
        t = 2 * math.pi * i / (5 if not moto else 6)
        radial = Vector((0, math.cos(t), math.sin(t)))
        put("Dark", K.bar(rc + radial * 0.02, rc + radial * (ri + 0.004), 0.006, 0.012, 0.0, up=X))
    put("Dark", K.disc(rc, X, 0.028, 0.008, 20))
    if moto:
        # drilled rotor: a ring of holes through the braking band, and the carrier bolts
        mid = (ro + ri) / 2
        for i in range(18):
            t = 2 * math.pi * (i + 0.5) / 18
            radial = Vector((0, math.cos(t), math.sin(t)))
            put("Dark", K.disc(rc + radial * (mid + (0.004 if i % 2 else -0.004)), X, 0.0035, 0.0034, 8))
        for i in range(6):
            t = 2 * math.pi * i / 6
            radial = Vector((0, math.cos(t), math.sin(t)))
            put("Metal", K.disc(rc + radial * (ri + 0.002) + X * rotor_side * 0.002, X, 0.004, 0.003, 6))
        # valve stem and its cap, a rim lock opposite, axle nuts both sides
        up = Vector((0, 0, 1))
        put("Metal", K.cyl(axle + up * (r_in + 0.004), axle + up * (r_in - 0.026), 0.0035, 0.0035, 8))
        put("Black", K.cyl(axle + up * (r_in - 0.026), axle + up * (r_in - 0.036), 0.0045, 0.0045, 8))
        put("Dark", K.rbox(axle - up * (r_in - 0.012), (rim_w * 0.5, 0.03, 0.022), 0.004))
        for side in (-1, 1):
            put("Metal", K.disc(axle + X * side * 0.092, X, 0.016, 0.012, 6))

    if cassette:
        for i in range(9):
            r = 0.058 - i * 0.0042
            c = axle + X * (flange_x + 0.012 + i * 0.0038)
            put("Metal", K.lathe(c, X, [(-0.0011, 0.016), (-0.0011, r), (0.0011, r), (0.0011, 0.016), (-0.0011, 0.016)], 36))
    if sprocket:
        c = axle + X * -(flange_x + 0.035)
        put("Metal", K.lathe(c, X, [(-0.003, 0.05), (-0.003, 0.1), (0.003, 0.1), (0.003, 0.05), (-0.003, 0.05)], 48))
        for i in range(48):
            t = 2 * math.pi * i / 48
            radial = Vector((0, math.cos(t), math.sin(t)))
            tangent = X.cross(radial)
            put("Metal", K.rbox(c + radial * 0.104, (0.005, 0.006, 0.01), 0, K.frame_rot(X, tangent, radial)))
    return rim_d, tyre_h


def caliper(group, axle, side_x, rotor_d, angle, moto=False):
    """A brake caliper straddling the rotor at `angle` (radians from straight down, forward positive)."""
    radial = Vector((0, math.sin(angle), -math.cos(angle)))
    tangent = X.cross(radial)
    c = axle + X * side_x + radial * (rotor_d / 2 - 0.012)
    s = 1.4 if moto else 1.0
    K.put(group, "Black", K.rbox(c, (0.034 * s, 0.075 * s, 0.04 * s), 0.008, K.frame_rot(X, tangent, radial)))
    K.put(group, "Accent", K.rbox(c + X * (0.018 * s if side_x < 0 else -0.018 * s) * -1, (0.004, 0.05 * s, 0.022 * s), 0.002, K.frame_rot(X, tangent, radial)))


# =============================================================================== bicycle parts


def cockpit(k, style, moto, P):
    """Stem, bars, grips, levers, display. Returns grip centres (left, right)."""
    put = lambda slot, bm: K.put("Steer", slot, bm)  # noqa: E731
    HT, Bars, AX = P["HT"], P["Bars"], P["AX"]
    half = k["BarWidth"] / 2
    fwd_perp = Vector((0, AX.z, -AX.y)).normalized()  # forward, perpendicular to the steering axis
    if moto:
        # risers on the top clamp, a moto bar with a crossbar and pad
        base = HT + AX * 0.035
        for side in (-1, 1):
            put("Black", K.cyl(base + X * side * 0.035, Bars + X * side * 0.035 - Z * 0.01, 0.016, 0.014, 14))
        bar_l = [Bars + X * -half + Z * 0.06 - Y * 0.05, Bars + X * -half * 0.55 + Z * 0.035 - Y * 0.02, Bars + X * -0.1, Bars + X * 0.1, Bars + X * half * 0.55 + Z * 0.035 - Y * 0.02, Bars + X * half + Z * 0.06 - Y * 0.05]
        put("Black", K.sweep(bar_l, 0.0145, 14))
        put("Black", K.cyl(Bars + X * -0.12 + Z * 0.05 - Y * 0.01, Bars + X * 0.12 + Z * 0.05 - Y * 0.01, 0.011))
        put("Accent", K.rbox(Bars + Z * 0.055 - Y * 0.01, (0.18, 0.045, 0.045), 0.018))
        ends = (bar_l[0], bar_l[-1])
        dirs = ((bar_l[0] - bar_l[1]).normalized(), (bar_l[-1] - bar_l[-2]).normalized())
    else:
        # spacers, stem, faceplate
        put("Black", K.cyl(HT, HT + AX * 0.012, 0.022, 0.022, 20))
        put("Dark", K.cyl(HT + AX * 0.012, HT + AX * 0.024, 0.022, 0.022, 20))
        stem_top = HT + AX * 0.024
        if style == "Folding":
            put("Frame", K.cyl(HT, Bars - AX * 0.06, 0.022, 0.02, 20))
            put("Accent", K.rbox(HT + (Bars - HT) * 0.3, (0.06, 0.05, 0.04), 0.01))
            stem_top = Bars - AX * 0.06
        put("Black", K.bar(stem_top, Bars, 0.036, 0.04, 0.01, up=AX))
        put("Black", K.cyl(stem_top + AX * 0.02, stem_top - AX * 0.02, 0.024, 0.024, 20))
        put("Dark", K.disc(stem_top + AX * 0.025, AX, 0.016, 0.004, 16))
        put("Black", K.rbox(Bars + Y * 0.005, (0.05, 0.016, 0.045), 0.008))
        if style == "Road":
            # drop bars
            for side in (-1, 1):
                s = Bars + X * side * half
                pts = [Bars + X * side * 0.05, s + Y * 0.005, s + Y * 0.08 + Z * 0.01, s + Y * 0.11 - Z * 0.04, s + Y * 0.09 - Z * 0.12, s + Y * 0.0 - Z * 0.135, s - Y * 0.04 - Z * 0.13]
                put("Black", K.sweep(pts, 0.0125, 12))
                # hoods
                put("Black", K.sweep([s + Y * 0.075 + Z * 0.012, s + Y * 0.115 + Z * 0.03, s + Y * 0.125 + Z * 0.018], 0.017, 12))
            put("Black", K.cyl(Bars + X * -0.06, Bars + X * 0.06, 0.0159))
            ends = (Bars + X * -half + Y * 0.1 + Z * 0.02, Bars + X * half + Y * 0.1 + Z * 0.02)
            dirs = (Y, Y)
        else:
            if style == "Cruiser":
                prof = [(0.0, 0, 0), (0.12, 0.04, 0.02), (0.6, -0.06, 0.07), (0.85, -0.16, 0.07), (1.0, -0.2, 0.06)]
            elif style in ("City", "Cargo"):
                prof = [(0.0, 0, 0), (0.15, 0, 0), (0.7, -0.03, 0.02), (1.0, -0.08, 0.025)]
            elif style in ("Hardtail", "Enduro", "Fat"):
                prof = [(0.0, 0, 0), (0.17, 0, 0), (0.32, -0.004, 0.018), (1.0, -0.018, 0.026)]
            else:
                prof = [(0.0, 0, 0), (1.0, 0, 0)]
            pts = []
            for side in (-1, 1):
                for frac, dy, dz in (prof if side > 0 else list(reversed(prof))):
                    if side < 0 and frac == 0:
                        continue
                    pts.append(Bars + X * side * half * frac + Y * dy + Z * dz)
            pts = list(reversed([p for p in pts if p.x < 0])) + [p for p in pts if p.x >= 0]
            pts.sort(key=lambda p: p.x)
            put("Black" if style != "Cruiser" else "Chrome", K.sweep(pts, 0.0112, 12))
            put("Black" if style != "Cruiser" else "Chrome", K.cyl(Bars + X * -0.05, Bars + X * 0.05, 0.0159))
            ends = (pts[0], pts[-1])
            dirs = ((pts[0] - pts[1]).normalized(), (pts[-1] - pts[-2]).normalized())
    grips = []
    for i, side in enumerate((-1, 1)):
        end, d = ends[i], dirs[i]
        g0 = end - d * (0.13 if not moto else 0.135)
        grip_slot = "Brown" if style == "Cruiser" else "Black"
        put(grip_slot, K.cyl(g0, end, 0.017 if not moto else 0.018, 0.017 if not moto else 0.018, 16))
        put("Accent" if style in ("Hardtail", "Enduro", "Fat") else "Dark", K.cyl(g0 - d * 0.008, g0 + d * 0.004, 0.0185, 0.0185, 16))
        put("Dark", K.cyl(end, end + d * 0.006, 0.014, 0.012, 12))
        grips.append((g0 + end) / 2)
        if style == "Road":
            continue
        # master cylinder + lever
        mc = g0 - d * 0.03 + Y * 0.012
        put("Black", K.rbox(mc + Z * 0.008, (0.04, 0.03, 0.03), 0.008))
        lever_end = g0 + d * 0.09 + Y * 0.06 - Z * 0.005
        put("Metal" if not moto else "Black", K.sweep([mc + Y * 0.02, mc + Y * 0.045 + d * 0.02, lever_end], 0.0045, 8, profile=(0.006, 0.0035)))
        # brake hose down to the head tube
        hose_top = mc - Y * 0.01 + Z * 0.01
        put("Black", K.sweep([hose_top, hose_top + Y * 0.06 - Z * 0.05 - d * 0.03, HT + fwd_perp * 0.06 + X * side * 0.02, P["HB"] + fwd_perp * 0.05 + X * side * 0.03], 0.0035, 6))
        if side < 0 and not moto:
            put("Dark", K.rbox(g0 - d * 0.045 - Z * 0.012, (0.02, 0.03, 0.022), 0.006))  # mode remote
            put("NeonCyan", K.rbox(g0 - d * 0.045 - Z * 0.012 + Y * 0.008 + Z * 0.008, (0.012, 0.012, 0.006), 0.002))
            if style in ("City", "Cruiser", "Cargo", "Folding"):
                bell = Bars + X * -0.09 + Y * 0.01 + Z * 0.025
                put("Metal", K.lathe(bell, Z, [(-0.004, 0), (-0.004, 0.026), (0.008, 0.024), (0.02, 0.014), (0.026, 0)], 24))
        if side > 0 and (k["Throttle"] and not moto):
            put("Black", K.rbox(g0 - d * 0.04 + Y * 0.025, (0.025, 0.03, 0.022), 0.006))
    # display
    disp = Bars + Y * (0.035 if not moto else 0.02) + Z * (0.03 if not moto else 0.07)
    rot = K.frame_rot(X, (Y * math.cos(0.5) + Z * math.sin(0.5)), (Z * math.cos(0.5) - Y * math.sin(0.5)))
    put("Black", K.rbox(disp, (0.085, 0.06, 0.018), 0.008, rot))
    put("NeonCyan", K.rbox(disp + (Z * math.cos(0.5) - Y * math.sin(0.5)) * 0.008, (0.068, 0.045, 0.004), 0.002, rot))
    return grips


def saddle(k, style, P):
    put = lambda slot, bm: K.put("Frame", slot, bm)  # noqa: E731
    top = P["SeatTop"]
    width = 0.24 if style == "Cruiser" else (0.13 if style == "Road" else 0.16)
    length = 0.27
    rear = top + Z * 0.035 - Y * (length * 0.45 - 0.02)
    # loft from the back to the nose
    secs = []
    for f, wf, hf, dz in ((0.0, 0.7, 0.55, 0.0), (0.06, 0.97, 0.9, 0.012), (0.2, 1.0, 1.0, 0.016), (0.42, 0.75, 0.85, 0.012), (0.62, 0.42, 0.8, 0.006), (0.86, 0.3, 0.75, 0.0), (1.0, 0.22, 0.6, -0.004)):
        secs.append((rear + Y * (length * f) + Z * dz, width / 2 * wf, 0.03 * hf, 2.6))
    put("Leather" if style != "Cruiser" else "Brown", K.loft(secs, 24, True, axis="Y"))
    put("Accent", K.loft([(s[0] - Z * 0.022, s[1] * 1.02, 0.008, 2.6) for s in secs[1:5]], 24, True, axis="Y"))
    for side in (-1, 1):
        put("Metal", K.sweep([rear + Y * 0.02 + X * side * 0.03 - Z * 0.01, rear + Y * 0.07 + X * side * 0.028 - Z * 0.04, rear + Y * 0.19 + X * side * 0.02 - Z * 0.04, rear + Y * 0.24 + X * side * 0.01 - Z * 0.012], 0.0035, 6))
    put("Black", K.rbox(top - Z * 0.008, (0.04, 0.05, 0.025), 0.006))
    if style == "Cruiser":
        for side in (-1, 1):
            base = rear + Y * 0.04 + X * side * 0.06
            for i in range(6):
                put("Chrome", K.torus(base - Z * (0.012 + i * 0.008), Z, 0.014, 0.003, 16, 6))


def battery_pack(group, a, b, w, h, lift, slot="Dark"):
    """External battery along a->b (rounded box) with a lock and charge LEDs."""
    d = (b - a).normalized()
    up = X.cross(d)
    if up.z < 0:
        up = -up
    a2, b2 = a + up * lift, b + up * lift
    secs = []
    n = 10
    for i in range(n + 1):
        f = i / n
        taper = 1.0 - 0.18 * (abs(f - 0.5) * 2) ** 6
        secs.append((a2 + (b2 - a2) * f, w / 2 * taper, h / 2 * taper, 4))
    # loft builds rings in the X-Z plane; rotate it onto the battery's axis
    K.put(group, slot, _orient_loft(secs, d, up, w, h, 4))
    K.put(group, "Accent", _orient_loft([(p + up * (h * 0.02), hw * 1.02, hh * 0.22, 4) for p, hw, hh, _ in secs[1:-1]], d, up, w, h, 4))
    K.put(group, "Metal", K.cyl(b2 - d * 0.02 + X * (w / 2), b2 - d * 0.02 + X * (w / 2 + 0.006), 0.008, 0.008, 12))
    for i in range(4):
        K.put(group, "NeonGreen", K.rbox(a2 + (b2 - a2) * (0.75 + i * 0.04) + up * (h / 2 + 0.001), (0.01, 0.012, 0.004), 0.001))



def _orient_loft(sections, d, up, w, h, n, seg=20):
    import bmesh

    side = d.cross(up).normalized()
    upv = side.cross(d).normalized()
    bm = bmesh.new()
    rings = []
    for center, hw, hh, ex in sections:
        ring = []
        for i in range(seg):
            t = 2 * math.pi * i / seg
            x, y = K.superellipse(hw, hh, ex, t)
            ring.append(bm.verts.new(center + side * x + upv * y))
        rings.append(ring)
    for a_ring, b_ring in zip(rings, rings[1:]):
        for i in range(seg):
            bm.faces.new((a_ring[i], a_ring[(i + 1) % seg], b_ring[(i + 1) % seg], b_ring[i]))
    for ring in (rings[0], rings[-1]):
        f = bm.faces.new(ring)
        bmesh.ops.triangulate(bm, faces=[f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def oval_tube(group, slot, a, b, w, h):
    """A hydroformed tube: elliptical section (w across, h in the bike's plane)."""
    d = (b - a).normalized()
    up = X.cross(d)
    if up.z < 0:
        up = -up
    secs = [(a, w / 2, h / 2, 2.4), (a + (b - a) * 0.5, w / 2 * 0.95, h / 2 * 0.95, 2.4), (b, w / 2, h / 2, 2.4)]
    K.put(group, slot, _orient_loft(secs, d, up, w, h, 2.4, 20))


def fender(group, axle, radius, width, a0, a1, slot="Accent", stays=True):
    """A fender arc over the wheel from angle a0 to a1 (degrees, 0 = straight ahead, 90 = top)."""
    pts = []
    for i in range(13):
        t = math.radians(a0 + (a1 - a0) * i / 12)
        pts.append(axle + Y * (math.cos(t) * radius) + Z * (math.sin(t) * radius))
    K.put(group, slot, K.sweep(pts, 0, 16, profile=(width / 2, 0.006)))
    K.put(group, slot, K.sweep(pts, 0, 10, profile=(0.006, 0.012)))
    if stays:
        for ang in (a0 + (a1 - a0) * 0.18, a0 + (a1 - a0) * 0.82):
            t = math.radians(ang)
            p = axle + Y * (math.cos(t) * radius) + Z * (math.sin(t) * radius)
            for side in (-1, 1):
                K.put(group, "Metal", K.cyl(axle + X * side * (width / 2 + 0.01), p + X * side * (width / 2), 0.0028, 0.0028, 6))


def light(group, at, facing, r, neon, housing="Black", spot=False):
    facing = facing.normalized()
    K.put(group, housing, K.lathe(at, facing, [(-r * 1.2, 0), (-r * 1.2, r * 0.6), (-r * 0.4, r * 1.05), (r * 0.2, r * 1.08), (r * 0.2, 0)], 24))
    K.put(group, neon, K.lathe(at + facing * r * 0.21, facing, [(-0.001, r * 0.95), (0.003, r * 0.6), (0.004, 0)], 24))


# =============================================================================== bicycle


def bicycle(k, P):
    style = k["Style"]
    t = TUBE[style]
    RA, FA, HB, HT, BB, ST, AX = P["RA"], P["FA"], P["HB"], P["HT"], P["BB"], P["ST"], P["AX"]
    tw = k["TireWidth"]
    F = lambda slot, bm: K.put("Frame", slot, bm)  # noqa: E731
    S = lambda slot, bm: K.put("Steer", slot, bm)  # noqa: E731
    integrated = style in ("Hardtail", "Enduro", "Road")
    axle_half = tw / 2 + 0.03
    fwd_perp = Vector((0, AX.z, -AX.y)).normalized()

    # ---- main frame
    F("Frame", K.cyl(HB - AX * 0.012, HT + AX * 0.01, t * 0.72, t * 0.66, 24))
    F("Dark", K.cyl(HT + AX * 0.008, HT + AX * 0.018, t * 0.72, t * 0.72, 24))
    F("Dark", K.cyl(HB - AX * 0.02, HB - AX * 0.01, t * 0.76, t * 0.76, 24))
    if style == "Cruiser":
        low = BB + Z * 0.12 + Y * 0.18
        F("Frame", K.sweep([HB, HB + (low - HB) * 0.55 - Y * 0.03, low, BB + Y * 0.02], t * 0.55, 16))
        loop_top = HB + AX * 0.1
        loop_low = BB + Z * 0.24 + Y * 0.12
        F("Frame", K.sweep([loop_top, loop_top - Y * 0.15 - Z * 0.08, loop_low, ST], t * 0.42, 14))
        battery_pack("Frame", HB + (low - HB) * 0.18, HB + (low - HB) * 0.9, 0.09, 0.08, 0.065)
        top_join = ST
    elif style == "Folding":
        mid = HB + (BB - HB) * 0.5 + Z * 0.12
        F("Frame", K.sweep([HB, mid, BB + Z * 0.05], t * 0.62, 18, profile=(t * 0.55, t * 0.75)))
        F("Accent", K.rbox(mid + Z * 0.005, (t * 1.5, t * 1.4, t * 1.6), 0.012))
        F("Metal", K.sweep([mid + X * t * 0.75 + Z * 0.02, mid + X * t * 0.85 - Y * 0.05, mid + X * t * 0.8 - Y * 0.1 - Z * 0.02], 0.005, 8))
        battery_pack("Frame", mid + (BB - mid) * 0.08 - Z * 0.03, BB + Z * 0.12 + Y * 0.03, 0.08, 0.075, -0.045)
        top_join = ST
    else:
        tt_start = HT - AX * 0.03
        if integrated:
            oval_tube("Frame", "Frame", tt_start, ST, t * 0.8, t * 1.05)
            oval_tube("Frame", "Frame", HB, BB + Y * 0.04, t * 1.3, t * 1.55)
            # integrated pack: cover on the underside of the down tube
            d = (BB - HB).normalized()
            under = X.cross(d)
            if under.z > 0:
                under = -under
            a, b = HB + (BB - HB) * 0.12 + under * t * 0.55, HB + (BB - HB) * 0.82 + under * t * 0.55
            K.put("Frame", "Dark", _orient_loft([(a, t * 0.55, t * 0.28, 4), ((a + b) / 2, t * 0.56, t * 0.3, 4), (b, t * 0.55, t * 0.28, 4)], d, -under, 0, 0, 4))
            K.put("Frame", "Accent", _orient_loft([(a + (b - a) * 0.1 + under * t * 0.02, t * 0.57, t * 0.06, 4), (a + (b - a) * 0.6 + under * t * 0.02, t * 0.57, t * 0.06, 4)], d, -under, 0, 0, 4))
        else:
            F("Frame", K.cyl(tt_start, ST, t * 0.45, t * 0.42, 20))
            F("Frame", K.cyl(HB, BB, t * 0.58, t * 0.55, 20))
            if style != "Cargo":
                battery_pack("Frame", HB + (BB - HB) * 0.14, HB + (BB - HB) * 0.8, 0.085, 0.08, t * 0.5 + 0.04)
        top_join = ST
        F("Frame", K.sphere(ST, t * 0.48, 16, 10))
    F("Frame", K.cyl(BB - Z * 0.02, top_join + (top_join - BB).normalized() * 0.03, t * 0.5, t * 0.45, 20))
    F("Frame", K.cyl(BB - X * 0.045, BB + X * 0.045, t * 0.6, t * 0.6, 24))  # bottom bracket shell
    F("Accent", K.cyl(top_join + (top_join - BB).normalized() * 0.02, top_join + (top_join - BB).normalized() * 0.045, t * 0.5, t * 0.5, 20))  # seat clamp

    # ---- rear end
    if style == "Enduro":
        pivot = BB + Z * 0.09 - Y * 0.05
        rocker = ST + (BB - ST) * 0.45
        for side in (-1, 1):
            o = X * side * axle_half
            F("Frame", K.sweep([pivot + o * 0.6, pivot + o * 0.9 - Y * 0.15 + Z * 0.01, RA + o], 0, 12, profile=(0.016, 0.026)))
            F("Frame", K.sweep([RA + o, RA + o + Y * 0.12 + Z * 0.16, rocker + o * 0.5 + Z * 0.1 - Y * 0.02], 0.013, 12))
            F("Frame", K.rbox(RA + o, (0.012, 0.045, 0.05), 0.008))
        shock_top = HT + (ST - HT) * 0.55 - Z * 0.03
        shock_bot = rocker + Z * 0.08
        d = (shock_bot - shock_top).normalized()
        F("Dark", K.cyl(shock_top, shock_top + d * 0.1, 0.022, 0.022, 20))
        F("Metal", K.cyl(shock_top + d * 0.1, shock_bot, 0.011, 0.011, 16))
        for i in range(9):
            F("Orange", K.torus(shock_top + d * (0.035 + i * 0.012), d, 0.024, 0.0035, 20, 6))
        F("Frame", K.rbox(rocker + Z * 0.09, (0.06, 0.09, 0.03), 0.01))
    else:
        for side in (-1, 1):
            o = X * side * axle_half
            F("Frame", K.sweep([BB + o * 0.45 + Y * 0.02, BB + o * 0.85 - Y * 0.12 - Z * 0.005, RA + o + Y * 0.03], t * 0.24, 12))
            stay_top = ST - Z * 0.02 + X * side * t * 0.35
            F("Frame", K.sweep([stay_top, stay_top + (RA + o - stay_top) * 0.5 + X * side * 0.012, RA + o + Y * 0.02 + Z * 0.02], t * 0.2, 12))
            F("Frame", K.rbox(RA + o, (0.01, 0.045, 0.045), 0.008))
    # thru axle lever on the left
    F("Black", K.cyl(RA - X * (axle_half + 0.005), RA - X * (axle_half + 0.015), 0.012, 0.012, 16))

    # ---- mid motor
    if "Mid" in k["Drive"]:
        m = BB + Z * 0.02 + Y * 0.035
        F("Dark", K.lathe(m, X, [(-0.07, 0), (-0.07, 0.07), (-0.06, 0.088), (0.06, 0.088), (0.07, 0.07), (0.07, 0)], 32))
        F("Accent", K.lathe(m + X * 0.071, X, [(-0.002, 0), (-0.002, 0.065), (0.003, 0.058), (0.003, 0)], 32))
        F("Black", K.bar(m - Z * 0.09 + Y * 0.07, m - Z * 0.07 - Y * 0.08, 0.13, 0.012, 0.004))

    # ---- drivetrain (chain stays on the frame)
    q = 0.055
    ring_r = 0.075 if "Mid" in k["Drive"] else 0.095
    cass = RA + X * 0.05
    F("Dark", K.sweep([BB + X * q + Z * ring_r, cass + Z * 0.055], 0.004, 6))
    der_top = cass + Z * -0.055 + Y * -0.0
    der_low = cass + Z * -0.12 + Y * 0.02
    F("Dark", K.sweep([BB + X * q - Z * ring_r, der_low + Y * 0.01], 0.004, 6))
    F("Dark", K.sweep([der_low + Y * -0.01, der_top + Y * -0.01, cass - Z * 0.05 - Y * 0.012], 0.004, 6))
    if style not in ("Cruiser",):
        F("Black", K.rbox(cass + X * 0.03 - Z * 0.03 - Y * 0.015, (0.02, 0.05, 0.06), 0.01))
        F("Black", K.bar(der_top + X * 0.012, der_low + X * 0.012, 0.006, 0.03, 0.004))
        for p in (der_top, der_low):
            F("Dark", K.disc(p + X * 0.006, X, 0.017, 0.008, 16))
    if style in ("City", "Cruiser", "Cargo", "Folding"):
        F("Black", K.sweep([BB + X * (q + 0.012) + Z * (ring_r + 0.02) + Y * 0.06, BB + X * (q + 0.012) + Z * (ring_r + 0.025) - Y * 0.08, cass + X * 0.012 + Z * 0.075 + Y * 0.07], 0, 8, profile=(0.012, 0.004)))

    # ---- seat post + saddle
    post_slot = "Metal" if style in ("Folding", "Cruiser", "City") else "Black"
    F(post_slot, K.cyl(ST, P["SeatTop"] - Z * 0.01, 0.0135, 0.0135, 16))
    if style in ("Hardtail", "Enduro"):
        F("Metal", K.cyl(ST + (P["SeatTop"] - ST) * 0.45, P["SeatTop"] - Z * 0.02, 0.0155, 0.0155, 16))
        F("Black", K.cyl(ST, ST + (P["SeatTop"] - ST) * 0.45, 0.0158, 0.0158, 16))
    saddle(k, style, P)

    # ---- fork and front end (steering group)
    tire_half = tw / 2 + 0.024
    suspended = style in ("Hardtail", "Enduro", "Fat", "Cruiser", "Cargo")
    crown = HB - AX * 0.02
    rot_steer = K.frame_rot(X, fwd_perp, AX)
    S("Frame" if not suspended else "Black", K.rbox(crown, (tire_half * 2 + 0.05, 0.045, 0.03), 0.012, rot_steer))
    S("Frame", K.cyl(HB - AX * 0.012, HT, t * 0.36, t * 0.36, 16))  # steerer (hidden in the head tube)
    for side in (-1, 1):
        top = crown + X * side * tire_half
        bottom = FA + X * side * tire_half
        if suspended:
            mid = bottom + (top - bottom) * 0.48
            S("Gold" if style == "Enduro" else "Metal", K.cyl(top, mid, 0.0175 if style != "Enduro" else 0.019, None, 20))
            S("Black", K.cyl(mid + (top - mid) * 0.06, mid - (top - mid) * 0.02, 0.023, 0.023, 20))
            S("Accent" if style in ("Hardtail", "Enduro", "Fat") else "Black", K.cyl(mid + (top - mid) * 0.04, bottom + AX * 0.03, 0.022 if style != "Enduro" else 0.024, 0.019, 20))
            S("Black", K.rbox(bottom + AX * 0.012 - fwd_perp * 0.004, (0.022, 0.04, 0.04), 0.008, rot_steer))
        else:
            S("Frame", K.sweep([top, top + (bottom - top) * 0.5, bottom + fwd_perp * 0.03 + AX * 0.03, bottom + AX * 0.01], 0.0105, 12))
    if suspended:
        arch_y = FA + (crown - FA) * 0.48 + AX * 0.02 + fwd_perp * 0.03
        S("Accent" if style in ("Hardtail", "Enduro", "Fat") else "Black", K.sweep([arch_y + X * -tire_half - fwd_perp * 0.02, arch_y + X * -tire_half * 0.6 + AX * 0.04, arch_y + X * tire_half * 0.6 + AX * 0.04, arch_y + X * tire_half - fwd_perp * 0.02], 0.009, 12))
    S("Black", K.cyl(FA - X * (tire_half + 0.012), FA + X * (tire_half + 0.012), 0.008, 0.008, 12))
    caliper("Steer", FA, -(0.032 + 0.018), 0.18 if style != "Enduro" else 0.2, math.radians(-135))

    # headlight
    if style in ("City", "Cruiser", "Cargo", "Folding"):
        lamp = crown + fwd_perp * 0.07 + AX * 0.01
        S("Black", K.bar(crown + fwd_perp * 0.02, lamp - Y * 0.02, 0.012, 0.006, 0.002))
        light("Steer", lamp, Y + Z * -0.05, 0.03, "NeonWhite", "Chrome" if style == "Cruiser" else "Black")
    else:
        lamp = P["Bars"] + Y * 0.04 + X * 0.07 - Z * 0.015
        light("Steer", lamp, Y, 0.018, "NeonWhite")

    grips = cockpit(k, style, False, P)

    # fenders, racks
    if style in ("City", "Cruiser", "Cargo"):
        fender("Steer", FA, P["Rf"] + 0.035, tw + 0.035, -15, 125)
        K.put("Steer", "Black", K.rbox(FA + Y * (P["Rf"] + 0.03) * math.cos(math.radians(-15)) + Z * (P["Rf"] + 0.03) * math.sin(math.radians(-15)) - Z * 0.03, (tw + 0.02, 0.004, 0.06), 0.001))
        fender("Frame", RA, P["Rr"] + 0.035, tw + 0.035, 55, 200)
    if style == "Folding":
        fender("Frame", RA, P["Rr"] + 0.03, tw + 0.03, 60, 190, "Black", False)
        fender("Steer", FA, P["Rf"] + 0.03, tw + 0.03, -10, 120, "Black", False)
    if style in ("City", "Cruiser"):
        deck_c = RA + Z * (P["Rr"] + 0.08) + Y * 0.04
        for dx in (-0.06, 0.0, 0.06):
            F("Black", K.cyl(deck_c + X * dx - Y * 0.2, deck_c + X * dx + Y * 0.18, 0.006, 0.006, 8))
        for dy in (-0.18, -0.02, 0.15):
            F("Black", K.cyl(deck_c + Y * dy - X * 0.07, deck_c + Y * dy + X * 0.07, 0.005, 0.005, 8))
        for side in (-1, 1):
            F("Black", K.sweep([RA + X * side * (axle_half + 0.01), deck_c + X * side * 0.07 - Y * 0.1 - Z * 0.005, deck_c + X * side * 0.07 - Y * 0.2], 0.0055, 8))
            F("Black", K.cyl(deck_c + X * side * 0.07 - Y * 0.15, ST - Z * 0.03 + X * side * 0.03, 0.004, 0.004, 8))
        F("Black", K.rbox(deck_c - Y * 0.205, (0.06, 0.02, 0.03), 0.006))
        F("NeonRed", K.rbox(deck_c - Y * 0.216, (0.05, 0.004, 0.02), 0.002))
    elif style == "Cargo":
        deck_c = RA + Z * (P["Rr"] + 0.09) + Y * 0.12
        for i, dx in enumerate((-0.09, -0.03, 0.03, 0.09)):
            F("Wood", K.rbox(deck_c + X * dx, (0.055, 0.78, 0.018), 0.004))
        for side in (-1, 1):
            o = X * side * 0.13
            F("Frame", K.sweep([deck_c + o + Y * 0.38 - Z * 0.02, deck_c + o - Y * 0.4 - Z * 0.02], 0.011, 10))
            F("Frame", K.cyl(RA + X * side * axle_half, deck_c + o - Y * 0.15 - Z * 0.02, 0.011, 0.011, 12))
            F("Frame", K.cyl(BB + X * side * 0.02 + Z * 0.05, deck_c + o + Y * 0.35 - Z * 0.03, 0.012, 0.012, 12))
            # running board, monkey bar
            F("Black", K.rbox(deck_c + X * side * 0.2 - Z * (P["Rr"] + 0.04) + Y * 0.05, (0.1, 0.5, 0.012), 0.006))
            F("Black", K.cyl(deck_c + o - Y * 0.0 - Z * 0.02, deck_c + X * side * 0.2 - Z * (P["Rr"] + 0.04) - Y * 0.05, 0.008, 0.008, 8))
            F("Accent", K.rbox(deck_c + X * side * 0.165 - Z * 0.17 + Y * 0.02, (0.07, 0.38, 0.26), 0.03))
            F("Black", K.rbox(deck_c + X * side * 0.165 - Z * 0.05 + Y * 0.02, (0.075, 0.385, 0.02), 0.008))
        bar_pts = [deck_c + X * -0.13 + Y * 0.2, deck_c + X * -0.13 + Y * 0.2 + Z * 0.28, deck_c + X * 0.13 + Y * 0.2 + Z * 0.28, deck_c + X * 0.13 + Y * 0.2]
        F("Frame", K.sweep(bar_pts, 0.011, 12))
        F("Leather", K.rbox(deck_c + Z * 0.035 - Y * 0.0, (0.2, 0.3, 0.05), 0.02))
        battery_pack("Frame", ST + (BB - ST) * 0.2 - Y * 0.07, ST + (BB - ST) * 0.8 - Y * 0.07, 0.08, 0.08, 0.0)
        F("Dark", K.rbox(deck_c - Z * 0.065 - Y * 0.05, (0.11, 0.36, 0.08), 0.02))
        F("NeonRed", K.rbox(deck_c - Y * 0.395, (0.07, 0.006, 0.025), 0.002))
    else:
        if style != "Cruiser":
            tl = ST + (P["SeatTop"] - ST) * 0.25 - Y * 0.035
            F("Black", K.rbox(tl, (0.03, 0.022, 0.05), 0.008))
            F("NeonRed", K.rbox(tl - Y * 0.012, (0.022, 0.004, 0.04), 0.002))

    # kickstand
    F("Dark", K.sweep([BB - X * 0.045 - Y * 0.1 - Z * 0.02, BB - X * 0.12 - Y * 0.2 - Z * 0.15, BB - X * 0.17 - Y * 0.27 - Z * (BB.z - 0.015)], 0.008, 8))

    # ---- wheels
    tk = k["TireKind"]
    knobby = tk in ("Knobby", "Fat")
    hub = k["Drive"] == "Rear hub"
    stripe = "White" if style == "Cruiser" else ("Metal" if style in ("City",) else None)
    spoke = "Dark" if style in ("Hardtail", "Enduro", "Fat", "Road") else "Metal"
    rotor = 0.2 if style == "Enduro" else 0.18
    wheel("Front", FA, P["Rf"] * 2, tw, "Bike", knobby, False, -1, rotor, False, False, None, spoke, False, stripe)
    wheel("Rear", RA, P["Rr"] * 2, tw, "Bike", knobby, hub, -1, rotor, True, False, None, spoke, False, stripe)
    caliper("Frame", RA, -(0.032 + 0.018 if not hub else 0.04 + 0.018), rotor, math.radians(150))

    # ---- cranks
    cranks(k, P, q, ring_r)
    return grips


def cranks(k, P, q, ring_r):
    C = lambda slot, bm: K.put("Crank", slot, bm)  # noqa: E731
    BB = P["BB"]
    style = k["Style"]
    arm_x = 0.085
    C("Metal", K.lathe(BB + X * q, X, [(-0.0015, ring_r - 0.016), (-0.0015, ring_r), (0.0015, ring_r), (0.0015, ring_r - 0.016), (-0.0015, ring_r - 0.016)], 56))
    teeth = int(ring_r * 2 * math.pi / 0.0127)
    for i in range(teeth):
        t = 2 * math.pi * i / teeth
        radial = Vector((0, math.cos(t), math.sin(t)))
        C("Metal", K.rbox(BB + X * q + radial * (ring_r + 0.003), (0.003, 0.005, 0.006), 0, K.frame_rot(X, X.cross(radial), radial)))
    for i in range(4):
        t = 2 * math.pi * i / 4 + 0.4
        radial = Vector((0, math.cos(t), math.sin(t)))
        C("Black", K.bar(BB + X * (q + 0.004), BB + X * (q + 0.004) + radial * (ring_r - 0.012), 0.006, 0.014, 0.003, up=X))
    if style in ("City", "Cruiser", "Cargo", "Folding"):
        C("Black", K.lathe(BB + X * (q + 0.008), X, [(-0.001, ring_r - 0.004), (-0.001, ring_r + 0.012), (0.002, ring_r + 0.012), (0.002, ring_r - 0.004), (-0.001, ring_r - 0.004)], 48))
    C("Dark", K.cyl(BB - X * arm_x, BB + X * arm_x, 0.012, 0.012, 16))
    for side in (-1, 1):
        d = Vector((0, 0, -1)) * side
        start = BB + X * side * arm_x
        foot = start + d * 0.17
        C("Black" if style not in ("Cruiser", "City") else "Metal", K.bar(start, foot, 0.016, 0.026, 0.006, up=X))
        C("Dark", K.cyl(foot, foot + X * side * 0.012, 0.012, 0.012, 14))
        pedal = foot + X * side * 0.065
        mtb = style in ("Hardtail", "Enduro", "Fat")
        pw, pl = (0.1, 0.1) if mtb else (0.09, 0.08)
        C("Black", K.rbox(pedal, (pw, pl, 0.016), 0.005))
        C("Dark", K.cyl(foot + X * side * 0.01, pedal + X * side * pw / 2, 0.006, 0.006, 10))
        if not mtb:
            for e in (-1, 1):
                C("NeonAmber", K.rbox(pedal + Y * e * (pl / 2 + 0.001), (pw * 0.6, 0.003, 0.01), 0.001))


# =============================================================================== mopeds and e-motos


def moto_bike(k, P):
    style = k["Style"]
    moped = style == "Moped"
    if not moped:
        # the light e-motos are modelled in detail in emoto.py
        return emoto.build(k, P, cockpit)
    RA, FA, HB, HT, BB, AX = P["RA"], P["FA"], P["HB"], P["HT"], P["BB"], P["AX"]
    tw = k["TireWidth"]
    seat_h = k["SeatHeight"]
    F = lambda slot, bm: K.put("Frame", slot, bm)  # noqa: E731
    S = lambda slot, bm: K.put("Steer", slot, bm)  # noqa: E731
    # the suspension's moving groups (BikeModel's joints): the fork lowers slide up the steering axis,
    # the swingarm swings about its pivot, the shock's body and shaft turn to stay in line
    FK = lambda slot, bm: K.put("Fork" if not moped else "Steer", slot, bm)  # noqa: E731
    SW = lambda slot, bm: K.put("Swing", slot, bm)  # noqa: E731
    fwd_perp = Vector((0, AX.z, -AX.y)).normalized()
    rot_steer = K.frame_rot(X, fwd_perp, AX)

    pivot = P["Pivot"] if not moped else BB + Z * 0.08 + Y * -0.02
    F("Frame", K.cyl(HB - AX * 0.03, HT + AX * 0.02, 0.04, 0.04, 24))

    if moped:
        # beam frame, battery in the loop, bench seat, round lamp
        low = BB + Z * 0.1 + Y * 0.05
        F("Frame", K.sweep([HB, HB + (low - HB) * 0.5 - Y * 0.02, low, pivot + Z * 0.04], 0, 16, profile=(0.035, 0.045)))
        spine_end = Vector((0, RA.y + 0.05, seat_h - 0.12))
        F("Frame", K.sweep([HT - AX * 0.02, HT + (spine_end - HT) * 0.4 + Z * 0.02, spine_end], 0, 16, profile=(0.03, 0.035)))
        for side in (-1, 1):
            F("Frame", K.cyl(pivot + X * side * 0.07, spine_end + X * side * 0.06 + Y * 0.08, 0.015, 0.015, 12))
        box_c = (low + Vector((0, low.y, seat_h - 0.1))) / 2 + Y * -0.08
        box_c.z = (low.z + seat_h - 0.1) / 2
        size = (0.2, 0.38, seat_h - 0.1 - low.z - 0.02)
        F("Dark", K.rbox(box_c, size, 0.03))
        for side in (-1, 1):
            F("Accent", K.rbox(box_c + X * side * 0.101, (0.01, size[1] * 0.85, size[2] * 0.7), 0.02))
            F("Frame", K.rbox(box_c + X * side * 0.106 + Z * size[2] * 0.15, (0.006, size[1] * 0.6, 0.035), 0.012))
        bench_f = Vector((0, BB.y + 0.08, seat_h - 0.03))
        bench_b = Vector((0, RA.y - 0.06, seat_h + 0.01))
        secs = []
        for i in range(9):
            f = i / 8
            p = bench_f + (bench_b - bench_f) * f
            secs.append((p, 0.12 * (0.82 + 0.18 * min(1, f * 3)), 0.045, 4.5))
        F("Leather", K.loft(secs, 24, True, axis="Y"))
        for i in range(1, 6):
            p = bench_f + (bench_b - bench_f) * (i / 6)
            F("Black", K.rbox(p + Z * 0.044, (0.2, 0.004, 0.004), 0.001))
        F("Frame", K.rbox((bench_f + bench_b) / 2 - Z * 0.055, (0.2, (bench_b - bench_f).length, 0.02), 0.008))
        # rear: swingarm, twin coil shocks, fender, light, plate
        for side in (-1, 1):
            o = X * side * (tw / 2 + 0.035)
            F("Frame", K.bar(pivot + o * 0.7, RA + o, 0.03, 0.05, 0.008, up=Z))
            top = bench_b + o * 0.85 - Z * 0.07 + Y * 0.12
            bot = RA + o + Z * 0.03 + Y * 0.03
            d = (top - bot).normalized()
            F("Black", K.cyl(bot, top, 0.012, 0.012, 14))
            for i in range(10):
                F("Orange", K.torus(bot + d * (0.05 + i * 0.016), d, 0.022, 0.0035, 18, 6))
        fender("Frame", RA, P["Rr"] + 0.04, tw + 0.05, 70, 175, "Frame", False)
        tail = bench_b - Z * 0.04 - Y * 0.06
        F("Black", K.rbox(tail - Y * 0.02, (0.12, 0.05, 0.04), 0.01))
        F("NeonRed", K.rbox(tail - Y * 0.046, (0.1, 0.004, 0.025), 0.002))
        F("Black", K.rbox(tail - Y * 0.1 - Z * 0.09, (0.18, 0.006, 0.12), 0.004))
        F("White", K.rbox(tail - Y * 0.104 - Z * 0.09, (0.16, 0.004, 0.1), 0.004))
        # hub motor cover handled by the wheel; footpegs and pedals
        F("Metal", K.rbox(BB + Z * 0.02 + Y * 0.12 + X * 0.15, (0.08, 0.04, 0.02), 0.006))
        F("Metal", K.rbox(BB + Z * 0.02 + Y * 0.12 - X * 0.15, (0.08, 0.04, 0.02), 0.006))
    else:
        # twin aluminium spars, battery case, side covers, seat, tail
        alu = "Dark"
        for side in (-1, 1):
            o = X * side * 0.09
            F(alu, K.sweep([HT + o * 0.4 - AX * 0.02, HT + o + (pivot - HT) * 0.45 + Z * 0.04, pivot + o + Z * 0.12], 0, 14, profile=(0.018, 0.032)))
            F(alu, K.sweep([HB + o * 0.4, HB + o * 0.8 + (pivot - HB) * 0.35 - Z * 0.12, pivot + o - Z * 0.1], 0, 12, profile=(0.014, 0.022)))
            F(alu, K.sweep([pivot + o + Z * 0.12, Vector((0, RA.y + 0.15, seat_h - 0.1)) + o * 0.9], 0, 12, profile=(0.012, 0.018)))
        # the case's front clears the front tyre at full travel (the axle slides back up the steering axis)
        case_front = min(HT.y - 0.05, FA.y - k.get("FrontTravel", 0.2) * (-AX.y) / AX.z - P["Rf"] - 0.03)
        case_rear = pivot.y - 0.18
        case_top = min(HT.z - 0.1, seat_h - 0.08)  # never above the seat
        case_bot = pivot.z + 0.05
        cc = Vector((0, (case_front + case_rear) / 2, (case_top + case_bot) / 2))
        csize = (0.2, case_front - case_rear, case_top - case_bot)
        F("Dark", K.rbox(cc, csize, 0.025))
        for side in (-1, 1):
            F("Frame", K.loft([(cc + X * side * 0.104 + Y * (csize[1] * 0.46), 0.006, csize[2] * 0.3, 4), (cc + X * side * 0.104 + Y * (csize[1] * 0.2) + Z * 0.02, 0.006, csize[2] * 0.44, 4), (cc + X * side * 0.104 - Y * (csize[1] * 0.42) + Z * 0.04, 0.006, csize[2] * 0.36, 4)], 16, True, axis="Y"))
            F("Accent", K.bar(cc + X * side * 0.109 + Y * csize[1] * 0.35 + Z * 0.02, cc + X * side * 0.109 - Y * csize[1] * 0.25 + Z * 0.07, 0.004, 0.022, 0.002, up=Z))
            F("Accent", K.bar(cc + X * side * 0.109 + Y * csize[1] * 0.25 - Z * 0.03, cc + X * side * 0.109 - Y * csize[1] * 0.05 - Z * 0.0, 0.004, 0.012, 0.002, up=Z))
        tank_f = HT + Vector((0, -0.04, -0.04))
        tank_r = Vector((0, case_front - 0.22, seat_h - 0.05))
        F("Frame", K.loft([(tank_f, 0.08, 0.035, 3), (tank_f + (tank_r - tank_f) * 0.3 + Z * 0.02, 0.115, 0.05, 3), (tank_f + (tank_r - tank_f) * 0.75, 0.11, 0.045, 3), (tank_r, 0.09, 0.03, 3)], 24, True, axis="Y"))
        F("Black", K.disc(tank_f + (tank_r - tank_f) * 0.35 + Z * 0.072, Z, 0.022, 0.012, 20))
        seat_f = Vector((0, case_front - 0.2, seat_h - 0.02))
        seat_b = Vector((0, RA.y + 0.02, seat_h + 0.035))
        secs = []
        for i in range(8):
            f = i / 7
            secs.append((seat_f + (seat_b - seat_f) * f, 0.09 + 0.025 * min(1, f * 2.5), 0.04, 4))
        F("Leather", K.loft(secs, 24, True, axis="Y"))
        F("Frame", K.loft([(seat_b - Z * 0.035 + Y * 0.06, 0.09, 0.035, 3), (seat_b - Z * 0.02 - Y * 0.15, 0.07, 0.03, 3), (seat_b + Z * 0.0 - Y * 0.32, 0.04, 0.02, 3)], 20, True, axis="Y"))
        F("NeonRed", K.rbox(seat_b - Z * 0.035 - Y * 0.322, (0.06, 0.006, 0.02), 0.003))
        kit = k.get("Kit", "Dirt")
        if kit in ("Street", "Chopper"):
            # tail tidy: a short hanger under the tail with the plate and its lamp
            F("Black", K.sweep([seat_b - Z * 0.07 - Y * 0.28, seat_b - Z * 0.16 - Y * 0.42, seat_b - Z * 0.22 - Y * 0.46], 0, 10, profile=(0.06, 0.006)))
            F("White", K.rbox(seat_b - Z * 0.26 - Y * 0.47, (0.17, 0.004, 0.12), 0.004))
            F("NeonWhite", K.rbox(seat_b - Z * 0.19 - Y * 0.465, (0.04, 0.01, 0.01), 0.003))
        else:
            F("Black", K.sweep([seat_b - Z * 0.06 - Y * 0.25, seat_b - Z * 0.2 - Y * 0.34, seat_b - Z * 0.28 - Y * 0.36], 0, 10, profile=(0.07, 0.005)))
            F("White", K.rbox(seat_b - Z * 0.25 - Y * 0.36, (0.14, 0.004, 0.09), 0.003))
        if kit == "Supermoto":
            for side in (-1, 1):
                F("White", K.rbox(seat_b - Z * 0.1 - Y * 0.05 + X * side * 0.09, (0.008, 0.2, 0.12), 0.01))
        for side in (-1, 1):
            F("NeonAmber", K.rbox(seat_b - Z * 0.2 - Y * 0.35 + X * side * 0.09, (0.02, 0.02, 0.015), 0.004))
        # motor with fins, controller, skid plate
        m = pivot + Vector((0, 0.1, -0.06))
        F("Metal", K.lathe(m, X, [(-0.085, 0), (-0.085, 0.07), (-0.075, 0.095), (0.075, 0.095), (0.085, 0.07), (0.085, 0)], 36))
        for i in range(7):
            F("Dark", K.disc(m + X * (-0.06 + i * 0.02), X, 0.104, 0.006, 32))
        F("Accent", K.disc(m + X * 0.087, X, 0.06, 0.006, 32))
        F("Metal", K.bar(cc - Z * (csize[2] / 2 + 0.01) + Y * csize[1] * 0.4, m - Z * 0.11 + Y * 0.02, 0.18, 0.01, 0.004))
        F("Dark", K.disc(m - X * 0.09, X, 0.035, 0.012, 24))  # front sprocket
        # swingarm, linkage, coil shock
        for side in (-1, 1):
            o = X * side * (tw / 2 + 0.035)
            SW(alu, K.loft([(pivot + o * 0.7, 0.02, 0.04, 4), ((pivot + RA) / 2 + o, 0.02, 0.05, 4), (RA + o + Y * 0.01, 0.02, 0.035, 4)], 16, True, axis="Y"))
            SW("Black", K.rbox(RA + o - Y * 0.02, (0.03, 0.05, 0.04), 0.008))
        SW("Dark", K.cyl(pivot - X * 0.07, pivot + X * 0.07, 0.022, 0.022, 20))  # pivot bolt boss
        shock_top = P["ShockTop"]
        shock_bot = P["ShockBottom"]
        length = (shock_bot - shock_top).length
        d = (shock_bot - shock_top).normalized()
        # body, reservoir and spring on the frame mount; shaft and eye on the swingarm's
        K.put("ShockTop", "Dark", K.cyl(shock_top, shock_top + d * 0.08, 0.025, 0.025, 20))
        for i in range(10):
            K.put("ShockTop", "Orange" if k["Id"] not in ("storm_x", "hornet_6") else "Accent", K.torus(shock_top + d * (0.09 + i * 0.014), d, 0.028, 0.004, 20, 6))
        K.put("ShockTop", "Dark", K.cyl(shock_top + d * 0.08, shock_top + d * (length * 0.55), 0.017, 0.017, 16))
        K.put("ShockEnd", "Metal", K.cyl(shock_bot, shock_bot - d * (length * 0.62), 0.011, 0.011, 16))
        K.put("ShockEnd", "Dark", K.cyl(shock_bot - X * 0.02, shock_bot + X * 0.02, 0.016, 0.016, 16))
        SW(alu, K.bar(pivot - Z * 0.06, shock_bot, 0.04, 0.03, 0.008))
        # chain on the left to the rear sprocket (it rides the swingarm; the front sprocket sits by the pivot)
        sp_front = m - X * 0.09
        sp_rear = RA - X * (0.05 + 0.035)
        # the chain as links: alternating side plates with a roller pin at each pitch, top and bottom runs
        for z_front, z_rear in ((0.035, 0.102), (-0.035, -0.102)):
            a = sp_front + Z * z_front
            b = sp_rear + Z * z_rear
            run = b - a
            n = max(4, int(run.length / 0.019))
            d = run.normalized()
            for i in range(n):
                p0 = a + run * (i / n)
                p1 = a + run * ((i + 1) / n)
                inner = i % 2 == 0
                for side in (-1, 1):
                    off = X * side * (0.0045 if inner else 0.0065)
                    SW("Dark" if inner else "Metal", K.bar(p0 + off - d * 0.002, p1 + off + d * 0.002, 0.0015, 0.0085, 0.0, up=Z))
                SW("Metal", K.cyl(p0 - X * 0.0075, p0 + X * 0.0075, 0.0028, 0.0028, 6))
        # the front sprocket's teeth
        for i in range(14):
            t = 2 * math.pi * i / 14
            radial = Vector((0, math.cos(t), math.sin(t)))
            tangent = X.cross(radial)
            F("Metal", K.rbox(sp_front + radial * 0.038, (0.006, 0.006, 0.009), 0, K.frame_rot(X, tangent, radial)))
        F("Metal", K.disc(sp_front - X * 0.004, X, 0.012, 0.006, 6))
        SW("Black", K.bar(sp_front - Z * 0.05 + Y * -0.02, sp_rear - Z * 0.115 + Y * 0.05, 0.012, 0.015, 0.004))
        # footpegs
        for side in (-1, 1):
            # the game puts the rider's feet (PegL / PegR) 0.08 m ahead of the pivot (Blender +Y is forward)
            peg = pivot + Vector((side * 0.17, 0.08, -0.05))
            F(alu, K.bar(pivot + Vector((side * 0.09, 0.03, -0.03)), peg - X * side * 0.03, 0.03, 0.03, 0.006, up=Z))
            F("Metal", K.rbox(peg, (0.1, 0.05, 0.022), 0.004))
            for e in (-1, 1):
                F("Dark", K.rbox(peg + Y * e * 0.024 + Z * 0.012, (0.1, 0.004, 0.008), 0.001))
        F("Dark", K.sweep([pivot + Vector((-0.1, -0.05, -0.16)), pivot + Vector((-0.2, 0.05, -0.32)), pivot + Vector((-0.24, 0.1, -pivot.z + 0.015))], 0.009, 8))

    if not moped:
        # battery case: bolts round the side covers, louvred vents, a charge port on the right
        for side in (-1, 1):
            face = cc + X * side * 0.108
            for fy in (-0.42, 0.42):
                for fz in (-0.4, 0.4):
                    F("Metal", K.disc(face + Y * (csize[1] * fy) + Z * (csize[2] * fz), X, 0.006, 0.004, 6))
            for i in range(5):
                F("Black", K.rbox(face + Y * (-csize[1] * 0.3 + i * 0.022) - Z * (csize[2] * 0.28), (0.004, 0.008, csize[2] * 0.22), 0.001))
        port = cc + X * 0.11 + Y * (csize[1] * 0.25) + Z * (csize[2] * 0.15)
        F("Black", K.disc(port, X, 0.018, 0.01, 20))
        F("Metal", K.torus(port + X * 0.005, X, 0.018, 0.0025, 20, 6))
        F("Accent", K.disc(port + X * 0.007, X, 0.006, 0.002, 12))
        # wiring loom from the controller down to the motor
        for i, slot in enumerate(("Red", "Black", "Orange")):
            off = X * (-0.02 + i * 0.02)
            top = cc - Z * (csize[2] / 2) + Y * (csize[1] * 0.2) + off
            F(slot, K.sweep([top, top - Z * 0.04 - Y * 0.02, m + Z * 0.09 + Y * 0.03 + off], 0.0045, 6))
        # rubber knee grips on the tank, ribbed seat cover and its stitching
        for side in (-1, 1):
            mid = tank_f + (tank_r - tank_f) * 0.55
            F("Black", K.rbox(mid + X * side * 0.105 - Z * 0.01, (0.006, 0.16, 0.05), 0.004))
        for i in range(1, 8):
            p = seat_f + (seat_b - seat_f) * (i / 8)
            F("Dark", K.rbox(p + Z * 0.041, (0.16, 0.003, 0.003), 0.001))
        for side in (-1, 1):
            F("Dark", K.sweep([seat_f + X * side * 0.082 + Z * 0.025, seat_b + X * side * 0.1 + Z * 0.03], 0.0018, 4))
        # the rear brake line: caliper, along the swingarm, up the frame to the left lever
        lever = P["Bars"] - X * (k["BarWidth"] / 2 - 0.16)
        cal = RA + X * 0.085 + Y * 0.06 + Z * 0.06
        SW("Black", K.sweep([cal, (RA + pivot) / 2 + X * 0.07 + Z * 0.05], 0.004, 6))
        F("Black", K.sweep([(RA + pivot) / 2 + X * 0.07 + Z * 0.05, pivot + X * 0.08 + Z * 0.08, HT - AX * 0.05 + X * 0.06, lever + Z * 0.01], 0.004, 6))

    # ---- front end
    tire_half = tw / 2 + 0.035
    S("Black", K.rbox(HB, (tire_half * 2 + 0.09, 0.08, 0.035), 0.012, rot_steer))
    S("Black", K.rbox(HT, (tire_half * 2 + 0.08, 0.075, 0.03), 0.012, rot_steer))
    if not moped:
        # pinch bolts on both clamps, the stem nut on top
        for clamp, depth in ((HB, 0.04), (HT, 0.0375)):
            for side in (-1, 1):
                for e in (-1, 1):
                    S("Metal", K.cyl(clamp + X * side * (tire_half + 0.03 * e) - fwd_perp * depth, clamp + X * side * (tire_half + 0.03 * e) - fwd_perp * (depth + 0.008), 0.005, 0.005, 6))
        S("Metal", K.cyl(HT + AX * 0.015, HT + AX * 0.028, 0.014, 0.014, 6))
    for side in (-1, 1):
        top = HT + X * side * tire_half + AX * 0.02
        bottom = FA + X * side * tire_half
        if moped:
            mid = bottom + (top - bottom) * 0.5
            S("Metal", K.cyl(top, mid, 0.017, None, 18))
            S("Frame", K.cyl(mid + (top - mid) * 0.08, bottom + AX * 0.03, 0.025, 0.022, 18))
        else:
            # upside-down fork: the gold inner tubes, axle lugs and guards slide up into the dark outers
            mid = bottom + (top - bottom) * 0.42
            S("Dark", K.cyl(top, mid, 0.028, 0.027, 22))
            S("Black", K.cyl(mid + (top - mid) * 0.02, mid - (top - mid) * 0.03, 0.03, 0.03, 22))
            FK("Gold", K.cyl(mid, bottom + AX * 0.04, 0.02, 0.02, 18))
            FK("Black", K.rbox(bottom + AX * 0.03, (0.04, 0.06, 0.07), 0.01, rot_steer))
            # the guard ends a full stroke below the outer tube's seal, so it never runs into it
            slide = k.get("FrontTravel", 0.2) / max(0.3, AX.z)
            guard_top = max(0.14, (mid - bottom).length - slide - 0.02)
            FK("Black", K.bar(bottom + AX * guard_top + fwd_perp * 0.025, bottom + AX * 0.09 + fwd_perp * 0.025, 0.04, 0.012, 0.004, up=fwd_perp))
    FK("Black", K.cyl(FA - X * (tire_half + 0.02), FA + X * (tire_half + 0.02), 0.01, 0.01, 12))
    caliper("Fork" if not moped else "Steer", FA, -(0.05 + 0.035), 0.22, math.radians(-135), True)
    if moped:
        lamp = HT + fwd_perp * 0.13 - AX * 0.06
        S("Frame", K.lathe(lamp, Y, [(-0.09, 0), (-0.09, 0.05), (-0.05, 0.085), (0.02, 0.095), (0.03, 0.09), (0.03, 0)], 32))
        S("Chrome", K.torus(lamp + Y * 0.03, Y, 0.088, 0.008, 40, 8))
        S("NeonWhite", K.lathe(lamp + Y * 0.031, Y, [(0, 0.082), (0.008, 0.05), (0.01, 0)], 32))
        S("Black", K.bar(HB + fwd_perp * 0.02, lamp - Y * 0.06, 0.03, 0.012, 0.004))
        fender("Steer", FA, P["Rf"] + 0.035, tw + 0.05, 0, 120, "Frame", False)
        # round mirrors
        for side in (-1, 1):
            base = P["Bars"] + X * side * 0.2
            head = base + X * side * 0.08 + Z * 0.22 - Y * 0.02
            S("Chrome", K.cyl(base, head - Z * 0.03, 0.005, 0.005, 8))
            S("Chrome", K.lathe(head, -Y, [(-0.012, 0), (-0.012, 0.045), (0.004, 0.05), (0.004, 0)], 28))
            S("Glass", K.disc(head - Y * 0.005, Y, 0.042, 0.003, 28))
    else:
        kit = k.get("Kit", "Dirt")
        plate_c = (HB + HT) / 2 + fwd_perp * 0.1 + AX * 0.02
        plate_rot = K.frame_rot(X, fwd_perp, AX)
        if kit in ("Street", "Chopper"):
            # round headlight in a bowl on brackets, mirrors on stalks
            lamp = plate_c + fwd_perp * 0.02 + AX * 0.03
            bowl = "Chrome" if kit == "Chopper" else "Black"
            S(bowl, K.lathe(lamp, Y, [(-0.085, 0), (-0.085, 0.04), (-0.06, 0.08), (0.0, 0.095), (0.012, 0.09), (0.012, 0)], 36))
            S("Chrome", K.torus(lamp + Y * 0.012, Y, 0.088, 0.007, 40, 8))
            S("NeonWhite", K.lathe(lamp + Y * 0.013, Y, [(0, 0.082), (0.01, 0.05), (0.014, 0)], 32))
            for side in (-1, 1):
                S("Black", K.bar(HT + X * side * (tw / 2 + 0.04), lamp + X * side * 0.07 - fwd_perp * 0.03, 0.015, 0.03, 0.004))
                base = P["Bars"] + X * side * (k["BarWidth"] / 2 - 0.12) + Z * 0.05
                head = base + X * side * 0.08 + Z * 0.2 - Y * 0.02
                S("Black", K.cyl(base, head - Z * 0.02, 0.006, 0.006, 8))
                S("Black", K.rbox(head, (0.1, 0.012, 0.06), 0.02))
                S("Glass", K.rbox(head - Y * 0.007, (0.09, 0.002, 0.05), 0.018))
        else:
            # number plate with an LED bar (white boards on the supermoto, twin lamps on the enduro)
            plate_slot = "White" if kit == "Supermoto" else "Accent"
            S(plate_slot, K.rbox(plate_c, (0.26, 0.02, 0.26), 0.04, plate_rot))
            S("Black", K.rbox(plate_c + fwd_perp * 0.012 - AX * 0.035, (0.17, 0.006, 0.07), 0.015, plate_rot))
            if kit == "Enduro":
                for side in (-1, 1):
                    S("NeonWhite", K.lathe(plate_c + fwd_perp * 0.018 - AX * 0.035 + X * side * 0.045, fwd_perp, [(0, 0.03), (0.006, 0.02), (0.008, 0)], 24))
            else:
                S("NeonWhite", K.rbox(plate_c + fwd_perp * 0.016 - AX * 0.035, (0.15, 0.004, 0.022), 0.008, plate_rot))
                S("NeonWhite", K.rbox(plate_c + fwd_perp * 0.016 - AX * 0.065, (0.08, 0.004, 0.012), 0.005, plate_rot))
        if kit == "Enduro":
            # hand guards wrapping the grips
            for side in (-1, 1):
                g0 = P["Bars"] + X * side * (k["BarWidth"] / 2 - 0.14) + Z * 0.05
                g1 = P["Bars"] + X * side * (k["BarWidth"] / 2 + 0.01) + Z * 0.06 + Y * 0.07
                S("Accent", K.sweep([g0 + Y * 0.02, g0 + Y * 0.08 + X * side * 0.05 + Z * 0.02, g1], 0, 12, profile=(0.05, 0.006)))
        if kit in ("Supermoto", "Street", "Chopper"):
            # low fender hugging the tyre
            r = P["Rf"] + 0.03
            pts = []
            for i in range(9):
                a = math.radians(-35 + i * 14)
                pts.append(FA + Y * (math.sin(a) * r) + Z * (math.cos(a) * r))
            FK("Frame" if kit == "Street" else "Accent", K.sweep(pts, 0, 16, profile=(tw / 2 + 0.025, 0.006)))
        else:
            # high fender right under the lower crown (clear of the tyre over the fork's travel)
            under = HB.z - FA.z - 0.05
            up = max(under, P["Rf"] + k.get("FrontTravel", 0.2) + 0.03)  # higher where the fork is capped
            c = FA + AX * (up / AX.z)
            if up > under + 0.001:
                pts = [c + Y * 0.08 + Z * 0.0, c + Y * 0.18 + Z * -0.008, c + Y * 0.28 + Z * -0.02, c + Y * 0.36 + Z * -0.04]
            else:
                pts = [c + Y * -0.14 + Z * -0.025, c + Y * 0.04 + Z * 0.0, c + Y * 0.22 + Z * -0.01, c + Y * 0.36 + Z * -0.04]
            S("Accent", K.sweep(pts, 0, 16, profile=(tw / 2 + 0.008, 0.006)))
            S("Black", K.bar(HB - AX * 0.02, c + Z * 0.004, 0.05, 0.02, 0.006))
        S("Dark", K.rbox(P["Bars"] + Y * 0.0 + Z * 0.04, (0.09, 0.05, 0.03), 0.01))
    grips = cockpit(k, style, True, P)

    # ---- wheels
    knobby = k["TireKind"] in ("Knobby", "Fat", "Moto")
    if moped:
        wheel("Front", FA, P["Rf"] * 2, tw, "Moto", knobby, False, -1, 0.2, False, False, None, "Metal", True)
        wheel("Rear", RA, P["Rr"] * 2, tw, "Moto", knobby, True, 1, 0.2, False, False, None, "Metal", True)
        caliper("Frame", RA, 0.04 + 0.05, 0.2, math.radians(160), True)
        cranks(k, P, 0.055, 0.075)
    else:
        wheel("Front", FA, P["Rf"] * 2, tw, "Moto", knobby, False, -1, 0.22, False, False, None, "Metal")
        wheel("Rear", RA, P["Rr"] * 2, tw, "Moto", knobby, False, 1, 0.2, False, True, None, "Metal")
        caliper("Swing", RA, 0.05 + 0.035, 0.2, math.radians(150), True)
    return grips


# =============================================================================== cars


def car(kind, d, paint_slot="Paint"):
    W, L = d["Width"], d["Length"]
    clear, BH, CH = d["Clearance"], d["BodyHeight"], d["CabinHeight"]
    top = clear + BH
    roof = top + CH
    cowl = -L / 2 + L * d["Hood"]
    roof_front = cowl + CH * d["Rake"]
    cabin_end = min(cowl + d["CabinLength"], L / 2 - 0.06)
    roof_back = max(cabin_end - CH * d["RearRake"], roof_front + 0.4)
    D = d["Wheel"]
    wb = d["Wheelbase"]
    police = kind == "Police"
    body = lambda slot, bm: K.put("Body", slot, bm)  # noqa: E731

    # Blender: forward is +Y, so Roblox z (back) -> -y
    def P3(x, y, z):  # roblox-ish (x, height, z back) -> blender
        return Vector((x, -z, y))

    # Lower body: loft along the length, superellipse sections, the nose and tail lower and rounder
    secs = []
    n = 26
    for i in range(n + 1):
        f = i / n
        zb = -L / 2 + L * f
        nose = min(1.0, f / 0.07) if f < 0.07 else (min(1.0, (1 - f) / 0.06) if f > 0.94 else 1.0)
        ease = math.sin(nose * math.pi / 2)
        hw = W / 2 * (0.86 + 0.14 * ease)
        bottom = clear + 0.04 + (1 - ease) * 0.06
        # hood falls toward the nose; boot toward the tail
        hood_drop = 0.0
        if zb < cowl:
            hood_drop = 0.07 * ((cowl - zb) / (cowl + L / 2)) ** 1.5
        elif d["Trunk"] and zb > cabin_end:
            hood_drop = 0.02 * ((zb - cabin_end) / max(0.01, L / 2 - cabin_end))
        upper = top - hood_drop - (1 - ease) * 0.05
        cz = (upper + bottom) / 2
        hh = (upper - bottom) / 2
        secs.append((P3(0, cz, zb), hw, hh, 5.0))
    shell = K.loft(secs, 36, True, axis="Y")
    # wheel arches cut out of the shell
    for zs in (-1, 1):
        cutter = K.cyl(P3(-W, D / 2, zs * wb / 2), P3(W, D / 2, zs * wb / 2), D * 0.58, D * 0.58, 40)
        shell = K.subtract(shell, cutter)
    body(paint_slot, shell)
    for zs in (-1, 1):
        for xs in (-1, 1):
            c = P3(xs * (W / 2 - 0.12), D / 2, zs * wb / 2)
            body("Black", K.lathe(c, X, [(-0.13, D * 0.565), (-0.13, D * 0.6), (0.13, D * 0.6), (0.13, D * 0.565), (-0.13, D * 0.565)], 40))
    # greenhouse: glass loft and roof
    gsecs = []
    m = 12
    for i in range(m + 1):
        f = i / m
        zb = cowl + (cabin_end - cowl) * f
        if zb < roof_front:
            h = (zb - cowl) / max(0.01, roof_front - cowl)
        elif zb > roof_back:
            h = 1 - (zb - roof_back) / max(0.01, cabin_end - roof_back)
        else:
            h = 1.0
        h = max(0.02, h)
        hw = W * 0.445 - 0.06 * h
        gsecs.append((P3(0, top + CH * h / 2, zb), hw, CH * h / 2 + 0.002, 3.5))
    body("Glass", K.loft(gsecs, 28, True, axis="Y"))
    body(paint_slot if not police else "White", K.loft([(P3(0, roof + 0.02, roof_front + 0.02), W * 0.385, 0.025, 4), (P3(0, roof + 0.03, (roof_front + roof_back) / 2), W * 0.39, 0.03, 4), (P3(0, roof + 0.02, roof_back - 0.02), W * 0.385, 0.025, 4)], 28, True, axis="Y"))
    for xs in (-1, 1):
        for a, b in ((P3(xs * (W * 0.44), top, cowl), P3(xs * (W * 0.385), roof + 0.01, roof_front + 0.02)), (P3(xs * (W * 0.385), roof + 0.01, roof_back - 0.02), P3(xs * (W * 0.44), top, cabin_end))):
            body(paint_slot if not police else "Black", K.sweep([a, b], 0.03, 10))
        bz = roof_front + (roof_back - roof_front) * (0.18 if kind == "Van" else 0.48)
        body("Black", K.bar(P3(xs * W * 0.43, top, bz), P3(xs * W * 0.39, roof, bz), 0.05, 0.03, 0.005))
        body("Chrome" if kind != "Van" else "Black", K.sweep([P3(xs * W * 0.448, top + 0.005, cowl + 0.02), P3(xs * W * 0.448, top + 0.005, cabin_end - 0.02)], 0.008, 8))
    # interior
    for row in (0, 1):
        zr = roof_front + 0.35 + row * 0.8
        if zr < cabin_end - 0.3:
            for xs in (-1, 1):
                body("Interior", K.rbox(P3(xs * 0.4, clear + 0.45, zr), (0.46, 0.5, 0.12), 0.04))
                body("Interior", K.rbox(P3(xs * 0.4, top + 0.08, zr + 0.28), (0.44, 0.1, 0.5), 0.05, K.frame_rot(X, Vector((0, math.cos(0.2), math.sin(0.2))), Vector((0, -math.sin(0.2), math.cos(0.2))))))
    body("Interior", K.rbox(P3(0, top - 0.02, cowl + 0.18), (W - 0.2, 0.36, 0.14), 0.05))
    body("Black", K.torus(P3(-0.4, top + 0.08, cowl + 0.45), Vector((0, -math.cos(0.45), math.sin(0.45))), 0.17, 0.016, 28, 8))
    # front
    front, back = -L / 2, L / 2
    body("Black" if police else paint_slot, K.loft([(P3(0, clear + 0.14, front - 0.01), W / 2 - 0.1, 0.11, 6), (P3(0, clear + 0.14, front + 0.08), W / 2 - 0.02, 0.11, 6)], 32, True, axis="Y"))
    body("Black", K.rbox(P3(0, top - 0.17, front - 0.005), (W * 0.48, 0.03, 0.17), 0.03))
    for i in range(-1, 2):
        body("Chrome" if not police and kind != "Van" else "Dark", K.rbox(P3(0, top - 0.17 + i * 0.05, front - 0.02), (W * 0.45, 0.01, 0.012), 0.004))
    for xs in (-1, 1):
        hx = xs * (W / 2 - 0.34)
        body("Black", K.rbox(P3(hx, top - 0.11, front + 0.01), (0.36, 0.06, 0.13), 0.03))
        body("NeonWhite", K.rbox(P3(hx, top - 0.12, front - 0.018), (0.3, 0.012, 0.075), 0.02))
        body("NeonWhite", K.rbox(P3(hx, top - 0.065, front - 0.018), (0.3, 0.01, 0.018), 0.006))
        body("Glass", K.rbox(P3(xs * (W / 2 - 0.3), clear + 0.12, front - 0.015), (0.12, 0.01, 0.06), 0.02))
        body("NeonAmber", K.rbox(P3(xs * (W / 2 + 0.003), top - 0.1, front + 0.4), (0.008, 0.09, 0.035), 0.004))
    body("White", K.rbox(P3(0, clear + 0.16, front - 0.016), (0.5, 0.008, 0.12), 0.01))
    # rear
    body("Black" if police else paint_slot, K.loft([(P3(0, clear + 0.14, back - 0.08), W / 2 - 0.02, 0.11, 6), (P3(0, clear + 0.14, back + 0.01), W / 2 - 0.1, 0.11, 6)], 32, True, axis="Y"))
    tail_y = top + 0.05 if kind in ("Van", "SUV", "Hatch") else top - 0.1
    for xs in (-1, 1):
        tx = xs * (W / 2 - 0.3)
        body("Black", K.rbox(P3(tx, tail_y, back - 0.01), (0.4, 0.06, 0.15), 0.03))
        body("NeonRed", K.rbox(P3(tx, tail_y, back + 0.018), (0.34, 0.012, 0.1), 0.02))
        body("Glass", K.rbox(P3(xs * (W / 2 - 0.56), tail_y, back + 0.016), (0.08, 0.01, 0.06), 0.01))
    if d["Trunk"]:
        body("NeonRed", K.rbox(P3(0, tail_y + 0.03, back + 0.016), (W - 1.1, 0.008, 0.025), 0.006))
    body("White", K.rbox(P3(0, clear + 0.3, back + 0.006), (0.5, 0.008, 0.12), 0.01))
    body("Chrome", K.cyl(P3(W / 2 - 0.4, clear + 0.04, back - 0.05), P3(W / 2 - 0.4, clear + 0.04, back + 0.06), 0.035, 0.03, 16))
    # mirrors, handles
    for xs in (-1, 1):
        mz = cowl + 0.12
        body("Black", K.bar(P3(xs * (W / 2 - 0.06), top + 0.04, mz), P3(xs * (W / 2 + 0.1), top + 0.08, mz + 0.02), 0.04, 0.03, 0.008))
        body("Black" if police else paint_slot, K.rbox(P3(xs * (W / 2 + 0.15), top + 0.1, mz + 0.03), (0.17, 0.08, 0.1), 0.03))
        body("Glass", K.rbox(P3(xs * (W / 2 + 0.15), top + 0.1, mz + 0.081), (0.14, 0.004, 0.075), 0.02))
        doors = [cowl + 0.05, roof_front + (roof_back - roof_front) * (0.18 if kind == "Van" else 0.48), cabin_end - 0.12]
        for zz in doors:
            body("Black", K.rbox(P3(xs * (W / 2 + 0.001), clear + 0.1 + (BH - 0.18) / 2, zz), (0.006, 0.008, BH - 0.2), 0.002))
        for zz in doors[1:]:
            body("Chrome" if not police else "Black", K.rbox(P3(xs * (W / 2 + 0.006), top - 0.1, zz - 0.2), (0.015, 0.13, 0.025), 0.008))
    # kind extras
    if police:
        for xs in (-1, 1):
            body("White", K.rbox(P3(xs * (W / 2 + 0.004), clear + 0.1 + (BH - 0.2) / 2, (cowl + roof_back) / 2 + 0.08), (0.006, roof_back - cowl + 0.15, BH - 0.22), 0.01))
            body("Blue", K.rbox(P3(xs * (W / 2 + 0.006), top - 0.07, (cowl + roof_back) / 2 + 0.08), (0.006, roof_back - cowl + 0.15, 0.05), 0.004))
            body("Black", K.cyl(P3(xs * 0.35, clear + 0.08, front - 0.12), P3(xs * 0.35, top - 0.02, front - 0.14), 0.025, 0.025, 12))
        body("Black", K.cyl(P3(-0.43, top - 0.06, front - 0.14), P3(0.43, top - 0.06, front - 0.14), 0.025, 0.025, 12))
        body("Black", K.cyl(P3(-0.43, clear + 0.18, front - 0.14), P3(0.43, clear + 0.18, front - 0.14), 0.025, 0.025, 12))
        bz = roof_front + 0.3
        body("Black", K.rbox(P3(0, roof + 0.075, bz), (W * 0.84, 0.28, 0.05), 0.02))
        body("Chrome", K.cyl(P3(-W * 0.445 - 0.08, top + 0.15, cowl + 0.2), P3(-W * 0.445 - 0.08, top + 0.15, cowl + 0.32), 0.055, 0.05, 16))
        body("Black", K.cyl(P3(0.3, roof + 0.06, roof_back - 0.1), P3(0.3, roof + 0.5, roof_back + 0.05), 0.006, 0.003, 6))
    elif kind == "Taxi":
        body("Black", K.rbox(P3(0, roof + 0.075, (roof_front + roof_back) / 2), (0.5, 0.18, 0.05), 0.01))
        body("NeonWhite", K.rbox(P3(0, roof + 0.16, (roof_front + roof_back) / 2), (0.6, 0.22, 0.17), 0.04))
        squares = 14
        start, end = cowl + 0.1, cabin_end - 0.05
        size = (end - start) / squares
        for xs in (-1, 1):
            for i in range(squares):
                for row in (0, 1):
                    if (i + row) % 2 == 0:
                        body("Black", K.rbox(P3(xs * (W / 2 + 0.003), top - 0.2 + row * 0.05, start + (i + 0.5) * size), (0.004, size, 0.05), 0.001))
    elif kind == "SUV":
        for xs in (-1, 1):
            body("Black", K.sweep([P3(xs * (W * 0.37), roof + 0.04, roof_front + 0.1), P3(xs * (W * 0.37), roof + 0.1, roof_front + 0.2), P3(xs * (W * 0.37), roof + 0.1, roof_back - 0.2), P3(xs * (W * 0.37), roof + 0.04, roof_back - 0.1)], 0.018, 8))
        body("Tire", K.torus(P3(0, top + 0.05, back + 0.13), Y, 0.26, 0.09, 40, 12, squash=1.0))
        body(paint_slot, K.disc(P3(0, top + 0.05, back + 0.13), Y, 0.24, 0.17, 40))
        body("Metal", K.rbox(P3(0, clear + 0.02, front + 0.1), (W * 0.6, 0.3, 0.05), 0.02))
    elif kind == "Van":
        body("Black", K.rbox(P3(W / 2 + 0.006, top - 0.05, (roof_front + cabin_end) / 2 + 0.5), (0.02, cabin_end - roof_front - 1.1, 0.03), 0.006))
        # panel sides behind the front doors, windows only up top
        panel_start = roof_front + (roof_back - roof_front) * 0.22
        body(paint_slot, K.loft([(P3(0, top + CH * 0.28, panel_start), W * 0.452, CH * 0.28, 6), (P3(0, top + CH * 0.28, cabin_end - 0.02), W * 0.452, CH * 0.28, 6)], 32, True, axis="Y"))
        for i in range(3):
            body("Black", K.rbox(P3(0, roof + 0.1, roof_front + 0.8 + i * 1.0), (W * 0.8, 0.05, 0.04), 0.01))

    # wheels (spinning): tyre, alloy, brake disc
    for zs in (-1, 1):
        for xs in (-1, 1):
            name = ("F" if zs < 0 else "R") + ("L" if xs < 0 else "R")
            g = "Wheel_" + name
            c = P3(xs * (W / 2 - 0.1), D / 2, zs * wb / 2)
            K.put(g, "Tire", K.torus(c, X, D / 2 - 0.085, 0.085, 48, 14, squash=1.25))
            K.put(g, "Tire", K.lathe(c, X, [(-0.1, D * 0.33), (-0.1, D / 2 - 0.08), (0.1, D / 2 - 0.08), (0.1, D * 0.33)], 40))
            face = xs * 0.1
            rim_slot = "Dark" if police else ("Metal" if kind == "Van" else "Chrome")
            K.put(g, rim_slot, K.lathe(c + X * face, X * xs, [(-0.09, D * 0.33), (-0.002, D * 0.335), (0.004, D * 0.32), (0.004, D * 0.3), (-0.08, D * 0.3)], 48))
            spokes = 6 if kind == "SUV" else (8 if kind == "Van" else 5)
            for i in range(spokes):
                t = 2 * math.pi * i / spokes
                radial = Vector((0, math.cos(t), math.sin(t)))
                K.put(g, rim_slot, K.bar(c + X * face + radial * 0.05, c + X * (face - xs * 0.01) + radial * (D * 0.305), 0.06, 0.02, 0.006, up=X))
            K.put(g, rim_slot, K.lathe(c + X * face, X * xs, [(-0.03, 0), (-0.03, 0.065), (0.008, 0.055), (0.012, 0)], 24))
            K.put(g, "Dark", K.disc(c + X * (face - xs * 0.07), X, D * 0.27, 0.025, 36))
            K.put("Body", "Red" if not police else "Dark", K.rbox(c + X * (face - xs * 0.05) + Z * D * 0.2 + Y * zs * -0.05, (0.05, 0.12, 0.1), 0.015))


# =============================================================================== main


def points(k):
    return {
        "RA": B(k["RearAxle"]),
        "FA": B(k["FrontAxle"]),
        "HB": B(k["HB"]),
        "HT": B(k["HT"]),
        "BB": B(k["BB"]),
        "ST": B(k["ST"]),
        "SeatTop": B(k["SeatTop"]),
        "Bars": B(k["Bars"]),
        "Pivot": B(k["Pivot"]),
        "ShockTop": B(k["ShockTop"]),
        "ShockBottom": B(k["ShockBottom"]),
        "AX": Vector((k["Axis"][0], -k["Axis"][2], k["Axis"][1])),
        "Rf": k["Rf"],
        "Rr": k["Rr"],
    }


def setup_materials(colors_by_vehicle):
    mats = {}

    def mat(veh, slot):
        key = (veh, slot)
        if key in mats:
            return mats[key]
        m = bpy.data.materials.new(f"{veh}_{slot}")
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        col = colors_by_vehicle.get(veh, {}).get(slot) or SLOT_COLORS.get(slot) or (0.6, 0.1, 0.1)
        bsdf.inputs["Base Color"].default_value = (*col, 1)
        metal = slot in ("Metal", "Chrome", "Gold", "Dark")
        bsdf.inputs["Metallic"].default_value = 0.9 if metal else 0.0
        bsdf.inputs["Roughness"].default_value = 0.25 if metal else (0.85 if slot in ("Tire", "Leather", "Black") else 0.35)
        if slot.startswith("Neon"):
            bsdf.inputs["Emission Color"].default_value = (*col, 1)
            bsdf.inputs["Emission Strength"].default_value = 3.0
        if slot == "Glass":
            bsdf.inputs["Alpha"].default_value = 0.55
            bsdf.inputs["Roughness"].default_value = 0.05
        mats[key] = m
        return m

    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob.parent:
            slot = ob.name.split("__")[-1].split(".")[0]
            ob.data.materials.append(mat(ob.parent.name, slot))


def render(ids, out_dir, kinds):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 600
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.75, 0.82, 0.9, 1)
    bg.inputs["Strength"].default_value = 0.9
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.5
    sun_data.angle = math.radians(8)
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)
    floor_me = bpy.data.meshes.new("floor")
    import bmesh

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    bm.to_mesh(floor_me)
    floor = bpy.data.objects.new("floor", floor_me)
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1)
    floor_me.materials.append(fm)
    scene.collection.objects.link(floor)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    empties = {ob.name: ob for ob in bpy.data.objects if ob.type == "EMPTY"}
    for vid in ids:
        for name, e in empties.items():
            hidden = name != vid
            for child in e.children:
                child.hide_render = hidden
        is_car = vid in kinds
        if vid.startswith("Kit_"):
            kids = [c for c in empties[vid].children]
            lo = Vector((min(c.location.x - c.dimensions.x / 2 for c in kids), min(c.location.y - c.dimensions.y / 2 for c in kids), min(c.location.z - c.dimensions.z / 2 for c in kids)))
            hi = Vector((max(c.location.x + c.dimensions.x / 2 for c in kids), max(c.location.y + c.dimensions.y / 2 for c in kids), max(c.location.z + c.dimensions.z / 2 for c in kids)))
            size = max((hi - lo).length, 1)
            target = (lo + hi) / 2
            floor.location = Vector((0, 0, lo.z))
            floor.scale = (size, size, 1)
            sun.rotation_euler = (math.radians(50), 0, math.radians(35))
            cam.location = target + Vector((0.9, 1.6, 0.45)) * size * 0.95
            cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
            cam_data.lens = 45
            scene.render.filepath = os.path.join(out_dir, f"{vid}_q.png")
            bpy.ops.render.render(write_still=True)
            floor.location = Vector((0, 0, 0))
            floor.scale = (1, 1, 1)
            continue
        bike_views = (
            ("side", (3.2, 0.6, 1.0), (0, 0, 0.55), 50),
            ("q", (2.2, 2.4, 1.4), (0, 0, 0.55), 50),
            ("chain", (-1.5, -0.35, 0.15), (0, -0.25, 0.42), 50),
            ("front", (1.0, 1.5, 0.45), (0, 0.45, 0.65), 50),
        )
        car_views = (("side", (7.5, 5.0, 3.0), (0, 0, 0.75), 45), ("rear", (-6.0, -6.5, 2.8), (0, 0, 0.75), 45))
        views = arg("--views")
        for view, (dx, dy, dz), (tx, ty, tz), lens in (car_views if is_car else bike_views):
            if views and view not in views:
                continue
            target = Vector((tx, ty, tz))
            cam.location = target + Vector((dx, dy, dz))
            direction = target - cam.location
            cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
            cam_data.lens = lens
            scene.render.filepath = os.path.join(out_dir, f"{vid}_{view}.png")
            bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    only = arg("--only")
    grips = {}
    colors = {}
    for k in DATA["Bikes"]:
        if only and k["Id"] not in only:
            continue
        K.vehicle(k["Id"])
        P = points(k)
        if k["Style"] in ("Moto", "Moped"):
            grips[k["Id"]] = moto_bike(k, P)
        else:
            grips[k["Id"]] = bicycle(k, P)
        colors[k["Id"]] = {"Frame": tuple(k["Colors"]["Frame"]), "Accent": tuple(k["Colors"]["Accent"]), "Rims": tuple(k["Colors"]["Rims"])}
    car_paint = {"Police": (0.02, 0.02, 0.025), "Taxi": (0.97, 0.75, 0.05)}
    car_kinds = []
    for kind, d in DATA["Cars"].items():
        name = "Car_" + kind
        if only and name not in only:
            continue
        K.vehicle(name)
        car(kind, d)
        car_kinds.append(name)
        colors[name] = {"Paint": car_paint.get(kind, (0.62, 0.05, 0.06)), "Blue": (0.1, 0.3, 0.85), "Red": (0.6, 0.08, 0.08)}
    if not only or any(name.startswith("Kit_") for name in only):
        citykit.build_all()
        for name in ("Kit_Window", "Kit_Tree_Broadleaf", "Kit_Tree_Birch", "Kit_Tree_Conifer", "Kit_Lamp"):
            colors[name] = {"Paint": (0.55, 0.62, 0.3) if "Tree" in name else (0.9, 0.88, 0.82)}
    manifest = K.build_objects()
    os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
    total = 0
    for veh, items in manifest.items():
        tris = sum(i["Tris"] for i in items)
        total += tris
        worst = max(items, key=lambda i: i["Tris"])
        print(f"{veh:14s} {len(items):3d} meshes {tris:7d} tris (largest {worst['Name']} {worst['Tris']})")
    print("total tris", total)
    print("pieces", K.STATS["pieces"], "flipped outward", K.STATS["flipped"])
    write_manifest(manifest)
    bpy.ops.export_scene.fbx(filepath=os.path.join(HERE, "out", "Vehicles.fbx"), use_selection=False, object_types={"EMPTY", "MESH"}, apply_unit_scale=True, axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
    print("wrote blender/out/Vehicles.fbx")
    ids = arg("--render")
    if ids:
        setup_materials(colors)
        if ids == ["all"]:
            ids = list(manifest.keys())
        render(ids, os.path.join(HERE, "out", "renders"), car_kinds)


def write_manifest(manifest):
    lines = [
        "--[[",
        "\tMeshManifest: generated by blender/build_vehicles.py. Do not edit by hand.",
        "",
        "\tFor every vehicle (bike id, or Car_<Kind>), the meshes in blender/out/Vehicles.fbx: which joint",
        "\tgroup each rides on, its colour slot, and its bounding box in metres (model space, -Z forward).",
        "]]",
        "",
        "export type Entry = { Name: string, Group: string, Slot: string, Center: Vector3, Size: Vector3 }",
        "",
        "local M: { [string]: { Entry } } = {",
    ]
    for veh in sorted(manifest):
        lines.append(f'\t["{veh}"] = {{')
        for e in manifest[veh]:
            c, s = e["Center"], e["Size"]
            lines.append(f'\t\t{{ Name = "{e["Name"]}", Group = "{e["Group"]}", Slot = "{e["Slot"]}", Center = Vector3.new({c[0]:.4f}, {c[1]:.4f}, {c[2]:.4f}), Size = Vector3.new({s[0]:.4f}, {s[1]:.4f}, {s[2]:.4f}) }},')
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    lines.append("return M")
    with open(os.path.join(ROOT, "src", "shared", "Models", "MeshManifest.luau"), "w") as f:
        f.write("\n".join(lines) + "\n")


main()
