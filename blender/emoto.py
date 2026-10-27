"""
The light e-moto (Sur-Ron Light Bee class), modelled as close to the real thing as the game allows.
Called by build_vehicles.moto_bike for every non-moped "Moto" bike.

Blender coordinates, metres: X right, Y forward, Z up. Every point comes from the rig the game uses
(vehicles.json from tools/lune/export_vehicles.luau), so the rider's grips, pegs and seat, the wheels,
the steering axis, the swingarm pivot and the shock mounts all line up with the game's joints.

Groups (the joint each piece rides on): Frame (the chassis), Steer (turns with the bars), Fork
(slides with the fork), Front / Rear (spin with the wheels), Swing (swings with the swingarm),
ShockTop / ShockEnd (the shock's body and shaft). Slots are colours / materials (MeshKit.Slots;
Frame / Accent / Rims are the player's paint).

The real bike, piece by piece:
  - a forged aluminium twin-spar frame: two side loops round the battery, a cast head stock, a rear
    subframe under the seat;
  - the battery in the frame, plastic side covers inside the loops with graphics, shrouds flaring
    from the head stock, a top cover, a long flat MX seat, a rear fender kicking up to the tail light;
  - an upside-down fork in forged triple clamps, gold inner tubes, axle lugs, fork guards, a
    4-piston caliper on a wavy rotor;
  - spoked wheels (36 spokes, nipples, rim locks) on knobby or road tyres;
  - a box-section swingarm with a chain slider, a piggyback shock;
  - the mid motor with cooling fins, its controller with a heatsink, the reduction cover, skid plate;
  - MX footpegs, a side stand, the cockpit (moto bar, pad, switchgear, throttle, levers, display).
"""

import math

from mathutils import Vector

import meshkit as K

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


# Each bike is modelled on one real light e-moto family, so the line-up reads as different bikes:
#   Bee   - Sur-Ron Light Bee: raw silver forged spars, slim graphic side covers, MX shrouds
#   Sting - Talaria Sting: black frame, big angular side panels over the battery with vent slats
#   Storm - Sur-Ron Storm / Ultra Bee: full MX plastics, big louvred shrouds, side number boards
#   Box   - Segway X160/X260: black frame round an exposed ribbed battery box, small shrouds
#   Cafe  - street scrambler: teardrop tank, plain dark covers, brown bench seat, cast wheels
FAMILY = {
    "flit_mini": "Bee", "trail_t": "Bee", "ridge_x": "Bee", "cub_sm": "Bee",
    "hornet_6": "Sting", "hornet_6sm": "Sting",
    "storm_x": "Storm", "storm_xr": "Storm", "viper_sm": "Storm",
    "scout_e": "Box", "halo_gt": "Box",
    "flit_s": "Cafe", "nova_n": "Cafe", "deathrider": "Cafe",
}
FRAME_SLOT = {"Bee": "Metal", "Sting": "Black", "Storm": "Dark", "Box": "Black", "Cafe": "Black"}
CAST_WHEELS = ("flit_s", "nova_n", "viper_sm")


def yz(v):
    return (v.y, v.z)


def build(k, P, cockpit, caliper_unused=None):
    RA, FA, HB, HT, AX = P["RA"], P["FA"], P["HB"], P["HT"], P["AX"]
    pv, st, sb = P["Pivot"], P["ShockTop"], P["ShockBottom"]
    Rf, Rr = P["Rf"], P["Rr"]
    tw = k["TireWidth"]
    sh = k["SeatHeight"]
    kit = k.get("Kit", "Dirt")
    Tf = k.get("FrontTravel", 0.2)
    Tr = k.get("RearTravel", 0.2)
    knobby = k["TireKind"] in ("Knobby", "Fat", "Moto")
    road_kit = kit in ("Supermoto", "Street", "Chopper")
    F = lambda slot, bm: K.put("Frame", slot, bm)  # noqa: E731
    S = lambda slot, bm: K.put("Steer", slot, bm)  # noqa: E731
    FK = lambda slot, bm: K.put("Fork", slot, bm)  # noqa: E731
    SW = lambda slot, bm: K.put("Swing", slot, bm)  # noqa: E731
    fwd_perp = Vector((0, AX.z, -AX.y)).normalized()
    rot_steer = K.frame_rot(X, fwd_perp, AX)
    fam = FAMILY.get(k["Id"], "Bee")
    alu = FRAME_SLOT[fam]

    # the front tyre at full travel: the frame and bodywork keep clear of it (and at ride height, on
    # the little pit bikes where there's no room for more)
    cot = -AX.y / AX.z

    def clear_y(z, margin=0.03, travel=1.0):
        axle = FA + Y * (-Tf * travel * cot) + Z * (Tf * travel)
        r = Rf + margin
        dz = z - axle.z
        if abs(dz) >= r:
            return 9.0
        return axle.y - math.sqrt(r * r - dz * dz)

    # motor centre (the chain's front sprocket is beside it), back from the front tyre on short bikes
    m = pv + Vector((0, 0.1, -0.06))
    m.y = min(m.y, clear_y(m.z, 0.02, 0.35) - 0.105)

    # ------------------------------------------------------------------ frame
    xs = 0.105  # the spars' centre lines, either side of the battery
    top_front = Vector((0, HT.y - 0.075, HT.z - 0.035))
    low_front = Vector((0, HB.y - 0.05, HB.z - 0.03))
    rear_top = Vector((0, min(pv.y + 0.03, top_front.y - 0.13), sh - 0.125))
    above_pivot = Vector((0, pv.y - 0.025, pv.z + 0.1))
    below_pivot = Vector((0, pv.y - 0.015, pv.z - 0.075))
    cradle_rear = Vector((0, pv.y + 0.06, m.z - 0.115))
    cradle_front = Vector((0, m.y + 0.135, m.z - 0.1))
    down = []
    for f in (0.3, 0.62, 0.86):
        z = low_front.z + (cradle_front.z + 0.05 - low_front.z) * f
        y = low_front.y + (cradle_front.y - low_front.y) * f
        floor = min(m.y + 0.11, clear_y(z, 0.015, 0.35)) if z < m.z + 0.13 else rear_top.y + 0.1
        down.append(Vector((0, max(min(y, clear_y(z) - 0.03), floor), z)))
    mid_top = top_front + (rear_top - top_front) * 0.5 + Z * 0.012
    loop = [top_front, mid_top, rear_top, above_pivot, below_pivot, cradle_rear, cradle_front] + list(reversed(down)) + [low_front]
    for side in (-1, 1):
        o = X * side * xs
        F(alu, K.sweep([p + o for p in loop], 0, 10, closed=True, profile=(0.02, 0.034), samples=5, n=5))
        # the cast head stock joins each loop to the head tube
        F(alu, K.sweep([HT - AX * 0.01 + o * 0.25, top_front + o + Y * 0.02], 0, 10, profile=(0.016, 0.03), n=4))
        F(alu, K.sweep([HB + AX * 0.02 + o * 0.25, low_front + o + Y * 0.02], 0, 10, profile=(0.016, 0.03), n=4))
        # the rear subframe: two tubes each side up to the tail
        tail_mount = Vector((0, RA.y + 0.1, sh - 0.075)) + X * side * 0.07
        F(alu, K.sweep([rear_top + o * 0.9, rear_top + o * 0.85 + Y * -0.15 + Z * 0.02, tail_mount], 0.012, 10))
        F(alu, K.sweep([above_pivot + o * 0.9 + Z * 0.02, above_pivot + o * 0.85 + Y * -0.18 + Z * 0.13, tail_mount], 0.01, 10))
        # weld beads where the head stock meets the spars
        F("Metal", K.torus(top_front + o + Y * 0.02, (top_front - HT).normalized(), 0.03, 0.004, 20, 6))
    F(alu, K.lathe(HB - AX * 0.035, AX, [(0, 0.03), (0, 0.042), (0.012, 0.044), (HT.z - HB.z + 0.05, 0.044), (HT.z - HB.z + 0.06, 0.042), (HT.z - HB.z + 0.06, 0.03)], 28))
    # cross members: at the shock mount, behind the motor, under the seat
    F(alu, K.cyl(rear_top - X * xs, rear_top + X * xs, 0.016, 0.016, 14))
    F(alu, K.cyl(cradle_rear - X * xs, cradle_rear + X * xs, 0.014, 0.014, 14))
    F(alu, K.cyl(cradle_front - X * xs, cradle_front + X * xs, 0.014, 0.014, 14))
    F("Metal", K.cyl(st - X * 0.03 + Z * 0.0, st + X * 0.03, 0.012, 0.012, 12))  # shock top bolt
    # swingarm pivot: the bolt through the frame, nuts both sides
    F("Metal", K.cyl(pv - X * (xs + 0.03), pv + X * (xs + 0.03), 0.011, 0.011, 14))
    for side in (-1, 1):
        F("Metal", K.disc(pv + X * side * (xs + 0.032), X, 0.016, 0.01, 6))

    # ------------------------------------------------------------------ battery and bodywork
    bat_front = min(down[0].y, down[1].y) - 0.035
    bat_rear = above_pivot.y + 0.035
    bat_top = rear_top.z + 0.02
    bat_bot = m.z + 0.105
    bat_c = Vector((0, (bat_front + bat_rear) / 2, (bat_top + bat_bot) / 2))
    if fam == "Box":
        bw = 2 * xs + 0.06
        F("Dark", K.rbox(bat_c, (bw, bat_front - bat_rear, bat_top - bat_bot), 0.025))
        for i in range(6):
            z = bat_bot + (bat_top - bat_bot) * (0.18 + i * 0.13)
            for side in (-1, 1):
                F("Black", K.rbox(Vector((side * (bw / 2 + 0.002), bat_c.y, z)), (0.006, (bat_front - bat_rear) * 0.82, 0.012), 0.002))
        for side in (-1, 1):
            F("Accent", K.rbox(Vector((side * (bw / 2 + 0.004), bat_c.y, bat_top - 0.02)), (0.004, (bat_front - bat_rear) * 0.9, 0.012), 0.002))
            F("White", K.rbox(Vector((side * (bw / 2 + 0.006), bat_c.y + 0.03, bat_bot + 0.035)), (0.003, 0.09, 0.02), 0.002))
    else:
        F("Dark", K.rbox(bat_c, (0.17, bat_front - bat_rear, bat_top - bat_bot), 0.02))
    F("Metal", K.rbox(Vector((0, bat_rear + 0.06, bat_top + 0.005)), (0.07, 0.03, 0.012), 0.004))  # latch

    # side covers inside the frame loops, bulging a little, with graphics
    cover = [
        (top_front.y - 0.03, top_front.z - 0.02),
        (mid_top.y, mid_top.z - 0.012),
        (rear_top.y + 0.035, rear_top.z - 0.012),
        (rear_top.y + 0.0, rear_top.z - 0.15),
        (cradle_rear.y + 0.04, m.z + 0.11),
        (down[2].y - 0.04, m.z + 0.12),
        (down[1].y - 0.02, down[1].z),
        (down[0].y - 0.015, down[0].z + 0.03),
    ]
    outline = K.spline2d(cover, 5)
    cy = sum(p[0] for p in cover) / len(cover)
    cz = sum(p[1] for p in cover) / len(cover)
    cover_slot = "Black" if fam == "Cafe" else "Frame"
    for side in ((-1, 1) if fam != "Box" else ()):
        x0 = side * (xs + 0.008)
        piece = K.side_prism(outline, min(x0, x0 + side * 0.012), max(x0, x0 + side * 0.012), 0.004)

        def bulge(co, side=side):
            d = math.hypot((co.y - cy) / 0.22, (co.z - cz) / 0.16)
            return X * side * max(0.0, 0.012 * (1 - d * d))

        F(cover_slot, K.displace(piece, bulge))
        gx = side * (xs + 0.032)
        if fam == "Cafe":
            F("Chrome", K.disc(Vector((gx, cy + 0.02, cz + 0.02)), X, 0.03, 0.004, 28))
            F("Accent", K.disc(Vector((gx + side * 0.002, cy + 0.02, cz + 0.02)), X, 0.022, 0.004, 24))
            continue
        if fam == "Sting":
            # the big angular panel over the lower half, with vent slats
            panel = [(down[1].y + 0.01, down[1].z + 0.05), (rear_top.y + 0.03, rear_top.z - 0.08), (cradle_rear.y + 0.03, m.z + 0.12), (down[2].y + 0.0, m.z + 0.13)]
            px = side * (xs + 0.03)
            F("Frame", K.side_prism(panel, min(px, px + side * 0.01), max(px, px + side * 0.01), 0.004))
            for i in range(4):
                f = 0.25 + i * 0.13
                vy = panel[0][0] + (panel[1][0] - panel[0][0]) * f
                vz = panel[0][1] + (panel[1][1] - panel[0][1]) * f - 0.05
                F("Black", K.rbox(Vector((px + side * 0.011, vy, vz)), (0.004, 0.012, 0.07), 0.002))
            F("Accent", K.side_prism([(p[0], p[1]) for p in panel[:2]] + [(panel[1][0], panel[1][1] - 0.012), (panel[0][0], panel[0][1] - 0.012)], min(px, px + side * 0.0125), max(px, px + side * 0.0125)))
            continue
        # two graphic stripes and a logo badge
        stripe = [(cover[0][0] - 0.01, cover[0][1] - 0.03), (cover[2][0] + 0.06, cover[2][1] - 0.06), (cover[2][0] + 0.06, cover[2][1] - 0.085), (cover[0][0] - 0.03, cover[0][1] - 0.06)]
        F("Accent", K.side_prism(stripe, min(gx, gx + side * 0.002), max(gx, gx + side * 0.002)))
        stripe2 = [(cover[6][0] - 0.02, cover[6][1] + 0.02), (cover[4][0] + 0.1, cover[4][1] + 0.05), (cover[4][0] + 0.1, cover[4][1] + 0.035), (cover[6][0] - 0.03, cover[6][1] + 0.005)]
        F("Accent", K.side_prism(stripe2, min(gx, gx + side * 0.002), max(gx, gx + side * 0.002)))
        F("White", K.disc(Vector((gx, cy + 0.03, cz + 0.02)), X, 0.018, 0.003, 20))

    # shrouds flaring from the head stock, angled out like a real MX bike's
    shroud = [(top_front.y + 0.035, top_front.z + 0.005), (HB.y - 0.035, HB.z - 0.06), (down[0].y - 0.0, down[0].z - 0.05), (down[0].y - 0.07, down[0].z - 0.11), (mid_top.y + 0.06, mid_top.z - 0.07), (mid_top.y + 0.05, mid_top.z + 0.0)]
    if fam == "Storm":
        # big louvred MX shrouds reaching further down and back
        sc_y = sum(p[0] for p in shroud) / len(shroud)
        sc_z = sum(p[1] for p in shroud) / len(shroud)
        shroud = [(sc_y + (p[0] - sc_y) * 1.35 - 0.02, sc_z + (p[1] - sc_z) * 1.35 - 0.02) for p in shroud]
    elif fam == "Box":
        sc_y = sum(p[0] for p in shroud) / len(shroud)
        sc_z = sum(p[1] for p in shroud) / len(shroud)
        shroud = [(sc_y + (p[0] - sc_y) * 0.75, sc_z + (p[1] - sc_z) * 0.75) for p in shroud]
    outline_s = K.spline2d(shroud, 3)
    for side in ((-1, 1) if fam != "Cafe" else ()):
        flare = math.radians(10)
        if fam == "Storm":
            for i in range(4):
                ly = shroud[4][0] + (shroud[1][0] - shroud[4][0]) * (0.3 + i * 0.13)
                lz = shroud[4][1] + (shroud[1][1] - shroud[4][1]) * (0.3 + i * 0.13)
                F("Black", K.rbox(Vector((side * (xs + 0.04 + max(0.0, ly - shroud[5][0]) * math.sin(flare)), ly, lz)), (0.004, 0.01, 0.06), 0.002))

        def tilt(co, side=side):
            return X * side * (xs + 0.03 + max(0.0, co.y - shroud[5][0]) * math.sin(flare))

        F("Frame", K.displace(K.side_prism(outline_s, -0.004, 0.004, 0.003), tilt))
        stripe = [(shroud[0][0] - 0.02, shroud[0][1] - 0.03), (shroud[1][0] - 0.02, shroud[1][1] - 0.02), (shroud[1][0] - 0.03, shroud[1][1] - 0.05), (shroud[0][0] - 0.03, shroud[0][1] - 0.06)]
        F("Accent", K.displace(K.side_prism(stripe, -0.0015, 0.0015), lambda co, side=side: X * side * (xs + 0.0345 + max(0.0, co.y - shroud[5][0]) * math.sin(flare))))

    # top cover over the battery, running from the head stock into the seat
    tank_f = HT + Vector((0, -0.045, -0.04))
    tank_r = Vector((0, rear_top.y + 0.1, sh - 0.045))
    if fam == "Cafe":
        # a teardrop tank, fat and round, then tapering into the seat
        F("Frame", K.loft([(tank_f + Z * 0.01, 0.07, 0.04, 2.2), (tank_f + (tank_r - tank_f) * 0.3 + Z * 0.05, 0.14, 0.075, 2.2), (tank_f + (tank_r - tank_f) * 0.65 + Z * 0.035, 0.13, 0.065, 2.2), (tank_r, 0.075, 0.03, 2.2)], 32, True, axis="Y"))
        F("Chrome", K.disc(tank_f + (tank_r - tank_f) * 0.3 + Z * 0.125, Z, 0.03, 0.008, 24))
    elif fam == "Sting":
        F("Frame", K.loft([(tank_f, 0.06, 0.035, 6), (tank_f + (tank_r - tank_f) * 0.25 + Z * 0.025, 0.11, 0.05, 6), (tank_f + (tank_r - tank_f) * 0.7 + Z * 0.015, 0.115, 0.05, 6), (tank_r, 0.085, 0.03, 6)], 28, True, axis="Y"))
    elif fam == "Storm":
        F("Frame", K.loft([(tank_f, 0.07, 0.04, 3.5), (tank_f + (tank_r - tank_f) * 0.25 + Z * 0.03, 0.125, 0.06, 3.5), (tank_f + (tank_r - tank_f) * 0.7 + Z * 0.015, 0.125, 0.055, 3.5), (tank_r, 0.09, 0.03, 3)], 28, True, axis="Y"))
    else:
        F("Frame", K.loft([(tank_f, 0.06, 0.03, 3), (tank_f + (tank_r - tank_f) * 0.25 + Z * 0.02, 0.1, 0.045, 3.5), (tank_f + (tank_r - tank_f) * 0.7 + Z * 0.012, 0.11, 0.045, 3.5), (tank_r, 0.085, 0.028, 3)], 28, True, axis="Y"))
    F("Black", K.disc(tank_f + (tank_r - tank_f) * 0.3 + Z * 0.068, Z, 0.022, 0.01, 20))  # charge port lid
    for side in (-1, 1):
        mid = tank_f + (tank_r - tank_f) * 0.55
        F("Black", K.rbox(mid + X * side * 0.105 - Z * 0.01, (0.006, 0.16, 0.05), 0.004))  # knee grips

    # the seat: long, flat, slim at the front, its top at the rider's seat point
    seat_f = Vector((0, rear_top.y + 0.13, sh - 0.035))
    seat_b = Vector((0, RA.y + 0.03, sh + 0.025))
    secs = []
    for i in range(10):
        f = i / 9
        p = seat_f + (seat_b - seat_f) * f
        hw = 0.06 + 0.055 * min(1.0, f * 3) - 0.015 * max(0.0, f - 0.85) / 0.15
        hh = 0.03 + 0.016 * min(1.0, f * 2.5)
        if fam == "Cafe":
            hw += 0.012
            hh += 0.03 * max(0.0, f - 0.7) / 0.3  # the tail hump
        secs.append((p, hw, hh, 3.2))
    F("Brown" if fam == "Cafe" else "Leather", K.loft(secs, 28, True, axis="Y"))
    base = [(p - Z * (hh * 0.7), hw * 0.98, hh * 0.45, 4) for p, hw, hh, _ in secs]
    F("Black", K.loft(base, 20, True, axis="Y"))
    for i in range(1, 9):
        p, hw, hh, _ = secs[i]
        F("Dark", K.rbox(p + Z * (hh * 0.92), (hw * 1.4, 0.003, 0.003), 0.001))  # ribs
    for side in (-1, 1):
        F("Dark", K.sweep([secs[0][0] + X * side * secs[0][1] * 0.95, secs[4][0] + X * side * secs[4][1] * 0.97, secs[9][0] + X * side * secs[9][1] * 0.95], 0.0018, 4))

    # rear fender: from under the seat over the tyre, kicking up to the tail light
    over_tyre = max(sh + 0.0, RA.z + Rr + 0.8 * Tr + 0.04)
    rf0 = Vector((0, rear_top.y - 0.12, sh - 0.065))
    rf1 = Vector((0, RA.y + 0.02, over_tyre - 0.005))
    rf2 = Vector((0, RA.y - 0.22, over_tyre + 0.06))
    F("Frame", K.loft([(rf0, 0.08, 0.02, 3), (rf0 + (rf1 - rf0) * 0.5 + Z * 0.012, 0.1, 0.024, 3), (rf1, 0.095, 0.022, 3), (rf2, 0.055, 0.014, 3)], 24, True, axis="Y"))
    lamp = rf2 + Y * -0.005 - Z * 0.018
    F("Black", K.rbox(lamp, (0.075, 0.02, 0.03), 0.008))
    F("NeonRed", K.rbox(lamp - Y * 0.0105, (0.06, 0.002, 0.018), 0.004))
    if kit in ("Street", "Chopper"):
        hanger = rf2 + Y * 0.06 - Z * 0.03
        F("Black", K.sweep([hanger, hanger - Z * 0.1 - Y * 0.05, hanger - Z * 0.17 - Y * 0.07], 0, 10, profile=(0.055, 0.006)))
        F("White", K.rbox(hanger - Z * 0.21 - Y * 0.075, (0.17, 0.004, 0.12), 0.004))
        F("NeonWhite", K.rbox(hanger - Z * 0.14 - Y * 0.08, (0.04, 0.01, 0.01), 0.003))
        for side in (-1, 1):
            F("Black", K.cyl(hanger + X * side * 0.05 - Z * 0.03, hanger + X * side * 0.12 - Z * 0.03, 0.006, 0.006, 8))
            F("NeonAmber", K.sphere(hanger + X * side * 0.13 - Z * 0.03, 0.014, 10, 6))
    if kit == "Supermoto" or fam == "Storm":
        for side in (-1, 1):
            board = K.spline2d([(rf0.y - 0.02, sh - 0.07), (rf1.y + 0.12, over_tyre - 0.03), (rf1.y + 0.1, over_tyre - 0.16), (rf0.y - 0.08, sh - 0.2)], 4)
            F("White", K.side_prism(board, side * 0.1 - 0.003, side * 0.1 + 0.003, 0.002))

    # skid plate under the motor, the controller with its heatsink, the reduction cover
    skid = K.spline2d([(cradle_front.y + 0.02, cradle_front.z - 0.01), (cradle_front.y - 0.02, cradle_front.z - 0.05), (cradle_rear.y + 0.0, cradle_rear.z - 0.035), (cradle_rear.y - 0.03, cradle_rear.z + 0.0)], 4, closed=False)
    skid += [(p[0], p[1] + 0.008) for p in reversed(skid)]
    F("Metal", K.side_prism(skid, -0.09, 0.09, 0.003))
    for i in range(5):
        y = cradle_rear.y + (cradle_front.y - cradle_rear.y) * (0.15 + i * 0.17)
        F("Dark", K.rbox(Vector((0, y, cradle_rear.z - 0.032)), (0.15, 0.012, 0.004), 0.001))
    ctrl = Vector((xs - 0.02, bat_rear + 0.05, m.z + 0.07))
    F("Dark", K.rbox(ctrl, (0.05, 0.12, 0.07), 0.008))
    for i in range(6):
        F("Metal", K.rbox(ctrl + X * 0.028 + Z * (-0.03 + i * 0.012), (0.012, 0.11, 0.003), 0.001))

    # the motor: finned case, end covers with bolts and a ring, the cables
    F("Metal", K.lathe(m, X, [(-0.085, 0), (-0.085, 0.07), (-0.075, 0.095), (0.075, 0.095), (0.085, 0.07), (0.085, 0)], 36))
    for i in range(7):
        F("Dark", K.disc(m + X * (-0.06 + i * 0.02), X, 0.104, 0.006, 32))
    for side in (-1, 1):
        F("Dark", K.lathe(m + X * side * 0.086, X * side, [(0, 0.07), (0.008, 0.068), (0.012, 0.05), (0.012, 0)], 32))
        F("Accent", K.torus(m + X * side * 0.098, X, 0.04, 0.004, 32, 6))
        for i in range(6):
            t = 2 * math.pi * i / 6
            F("Metal", K.disc(m + X * side * 0.099 + Y * 0.058 * math.cos(t) + Z * 0.058 * math.sin(t), X, 0.005, 0.004, 6))
    for i, slot in enumerate(("Red", "Black", "Orange")):
        off = X * (0.02 + i * 0.016)
        F(slot, K.sweep([ctrl + off - Y * 0.04 - Z * 0.03, ctrl + off - Y * 0.02 - Z * 0.07, m + Z * 0.09 + Y * 0.02 + off * 0.5], 0.005, 6))
    # reduction cover on the left, from the motor back to the front sprocket's shaft
    sp_front = m - X * 0.09
    F("Black", K.sweep([m - X * 0.1 + Y * 0.03 + Z * 0.02, sp_front - X * 0.012 - Y * 0.01], 0, 12, profile=(0.012, 0.06), n=4))
    F("Black", K.disc(sp_front - X * 0.028, X, 0.05, 0.014, 28))
    F("Accent", K.disc(sp_front - X * 0.036, X, 0.022, 0.003, 20))

    # ------------------------------------------------------------------ swingarm and shock
    arm_x = tw / 2 + 0.035
    for side in (-1, 1):
        o = X * side * arm_x
        a = pv + o * 0.75
        b = RA + o
        mid = (a + b) / 2 + Z * 0.025
        SW(alu, K.loft([(a, 0.016, 0.036, 5), (a + (mid - a) * 0.5 + Z * 0.006, 0.018, 0.04, 5), (mid, 0.017, 0.036, 5), (b + Y * 0.04, 0.015, 0.026, 5), (b - Y * 0.015, 0.015, 0.024, 5)], 14, True, axis="Y"))
        SW("Black", K.rbox(RA + o - Y * 0.005, (0.034, 0.05, 0.042), 0.006))  # axle block
        SW("Metal", K.cyl(RA + o - Y * 0.035, RA + o - Y * 0.07, 0.004, 0.004, 6))  # adjuster bolt
        SW("Metal", K.disc(RA + o + X * side * 0.019, X, 0.012, 0.006, 6))  # axle nut
    SW(alu, K.loft([(pv + Y * -0.2 + Z * 0.0 - X * arm_x, 0.012, 0.02, 4), (pv + Y * -0.2 + X * arm_x, 0.012, 0.02, 4)], 10, True, axis="X"))  # brace
    SW("Dark", K.cyl(pv - X * 0.07, pv + X * 0.07, 0.024, 0.024, 20))  # pivot boss
    SW("Black", K.sweep([pv - X * arm_x + Z * 0.04 + Y * -0.02, (pv + RA) / 2 - X * arm_x + Z * 0.06], 0, 8, profile=(0.012, 0.01), n=4))  # chain slider
    shock_top, shock_bot = st, sb
    length = (shock_bot - shock_top).length
    d = (shock_bot - shock_top).normalized()
    K.put("ShockTop", "Dark", K.cyl(shock_top - d * 0.012, shock_top + d * 0.085, 0.027, 0.027, 22))
    K.put("ShockTop", "Accent", K.cyl(shock_top + d * 0.02 + X * 0.045, shock_top + d * 0.12 + X * 0.045, 0.018, 0.018, 18))  # piggyback reservoir
    K.put("ShockTop", "Dark", K.cyl(shock_top + d * 0.03, shock_top + d * 0.03 + X * 0.045, 0.008, 0.008, 8))
    coil = "Orange" if k["Id"] not in ("storm_x", "hornet_6") else "Accent"
    for i in range(11):
        K.put("ShockTop", coil, K.torus(shock_top + d * (0.095 + i * 0.013), d, 0.029, 0.0042, 20, 6))
    K.put("ShockTop", "Dark", K.cyl(shock_top + d * 0.085, shock_top + d * (length * 0.55), 0.018, 0.018, 16))
    K.put("ShockEnd", "Metal", K.cyl(shock_bot, shock_bot - d * (length * 0.62), 0.0105, 0.0105, 16))
    K.put("ShockEnd", "Dark", K.disc(shock_bot - d * 0.03, d, 0.03, 0.008, 22))  # spring seat
    K.put("ShockEnd", "Dark", K.cyl(shock_bot - X * 0.02, shock_bot + X * 0.02, 0.016, 0.016, 16))
    SW(alu, K.bar(pv - Z * 0.06, shock_bot, 0.04, 0.03, 0.008))

    # chain run, front sprocket teeth, chain guide (the chain rides the swingarm)
    sp_rear = RA - X * (0.05 + 0.035)
    # each run is its own group: the game slides it along its length (ChainTopSlide / ChainBotSlide)
    for run_group, z_front, z_rear in (("ChainTop", 0.035, 0.102), ("ChainBot", -0.035, -0.102)):
        CH = lambda slot, bm, g=run_group: K.put(g, slot, bm)  # noqa: E731
        a = sp_front + Z * z_front
        b = sp_rear + Z * z_rear
        run = b - a
        n = max(4, int(run.length / 0.019))
        dd = run.normalized()
        for i in range(n):
            p0 = a + run * (i / n)
            p1 = a + run * ((i + 1) / n)
            inner = i % 2 == 0
            for side in (-1, 1):
                off = X * side * (0.0045 if inner else 0.0065)
                CH("Dark" if inner else "Metal", K.bar(p0 + off - dd * 0.002, p1 + off + dd * 0.002, 0.0015, 0.0085, 0.0, up=Z))
            CH("Metal", K.cyl(p0 - X * 0.0075, p0 + X * 0.0075, 0.0028, 0.0028, 6))
    for i in range(14):
        t = 2 * math.pi * i / 14
        radial = Vector((0, math.cos(t), math.sin(t)))
        K.put("Sprocket", "Metal", K.rbox(sp_front + radial * 0.038, (0.006, 0.006, 0.009), 0, K.frame_rot(X, X.cross(radial), radial)))
    SW("Black", K.bar(sp_front - Z * 0.05 + Y * -0.02 - X * 0.0, sp_rear - Z * 0.115 + Y * 0.05, 0.012, 0.015, 0.004))

    # footpegs (the game puts the rider's feet 0.08 m ahead of the pivot), side stand
    for side in (-1, 1):
        peg = pv + Vector((side * 0.17, 0.08, -0.05))
        F(alu, K.bar(pv + Vector((side * 0.09, 0.03, -0.03)), peg - X * side * 0.03, 0.03, 0.03, 0.006, up=Z))
        F("Metal", K.rbox(peg, (0.1, 0.05, 0.016), 0.004))
        for e in range(4):
            F("Metal", K.rbox(peg + Y * (-0.022 + e * 0.0147) + Z * 0.01, (0.1, 0.004, 0.006), 0.001))  # teeth
        F("Metal", K.cyl(peg - X * side * 0.05 + Y * 0.0, peg - X * side * 0.05 + Y * 0.0 - Z * 0.015, 0.006, 0.006, 8))
    # side stand: pivots on a lug off the left footpeg mount, outboard of the chain line (x = -0.09),
    # and swings down and forward from there, so it never crosses the chain
    lug = pv + Vector((-0.135, 0.06, -0.06))
    F(alu, K.bar(pv + Vector((-0.08, 0.04, -0.035)), lug + X * 0.01, 0.022, 0.03, 0.005, up=Z))
    F("Metal", K.cyl(lug - X * 0.012, lug + X * 0.012, 0.009, 0.009, 8))
    F("Dark", K.sweep([lug, pv + Vector((-0.19, 0.12, -0.3)), pv + Vector((-0.235, 0.16, -pv.z + 0.015))], 0.009, 8))
    F("Dark", K.rbox(pv + Vector((-0.235, 0.165, -pv.z + 0.008)), (0.03, 0.045, 0.01), 0.003))
    F("Metal", K.cyl(lug + Vector((-0.004, -0.02, -0.04)), lug + Vector((-0.004, 0.05, -0.12)), 0.0025, 0.0025, 6))  # return spring

    # rear brake line: caliper, along the swingarm, up the frame to the left lever
    lever = P["Bars"] - X * (k["BarWidth"] / 2 - 0.16)
    cal = RA + X * 0.085 + Y * 0.06 + Z * 0.06
    SW("Black", K.sweep([cal, (RA + pv) / 2 + X * 0.07 + Z * 0.05], 0.004, 6))
    F("Black", K.sweep([(RA + pv) / 2 + X * 0.07 + Z * 0.05, pv + X * 0.08 + Z * 0.08, HT - AX * 0.05 + X * 0.06, lever + Z * 0.01], 0.004, 6))

    # ------------------------------------------------------------------ front end
    tire_half = tw / 2 + 0.035
    # forged triple clamps: a plate round the steerer and both fork tubes, pinch bolts
    def clamp(at, thick):
        outline = K.spline2d([(-tire_half - 0.034, 0.0), (-tire_half, -0.034), (0, -0.05), (tire_half, -0.034), (tire_half + 0.034, 0.0), (tire_half, 0.036), (0, 0.022), (-tire_half, 0.036)], 6)
        S(alu, K.prism(outline, thick, at - AX * (thick / 2), X, fwd_perp, AX, 0.004))
        for side in (-1, 1):
            for e in (-1, 1):
                S("Metal", K.cyl(at + X * side * (tire_half + 0.02 * e) - fwd_perp * 0.04, at + X * side * (tire_half + 0.02 * e) - fwd_perp * 0.05, 0.005, 0.005, 6))
    clamp(HB, 0.045)
    clamp(HT, 0.035)
    S("Metal", K.cyl(HT + AX * 0.017, HT + AX * 0.03, 0.016, 0.016, 6))  # stem nut
    for side in (-1, 1):
        top = HT + X * side * tire_half + AX * 0.03
        bottom = FA + X * side * tire_half
        mid = bottom + (top - bottom) * 0.42
        # upside-down fork: dark outer tubes, gold inner tubes sliding up into them
        S("Dark", K.cyl(top, mid, 0.028, 0.027, 24))
        S("Gold", K.lathe(top, AX, [(0, 0.02), (0.012, 0.022), (0.02, 0.016), (0.02, 0)], 20))  # fork cap
        S("Metal", K.cyl(top + AX * 0.02, top + AX * 0.028, 0.006, 0.006, 8))  # adjuster
        S("Black", K.cyl(mid + (top - mid) * 0.03, mid - (top - mid) * 0.02, 0.031, 0.031, 24))  # seal holder
        FK("Gold", K.cyl(mid, bottom + AX * 0.05, 0.02, 0.02, 20))
        # axle lug: a cast foot round the axle, with its pinch bolts
        lug = K.spline2d([(-0.03, -0.03), (0.03, -0.035), (0.035, 0.05), (0.0, 0.11), (-0.03, 0.08)], 4)
        FK("Black", K.prism(lug, 0.04, bottom - X * 0.02 + AX * -0.0, AX, fwd_perp, X, 0.004))
        for e in (0, 1):
            FK("Metal", K.cyl(bottom + X * side * 0.022 - fwd_perp * (0.015 + e * 0.022), bottom + X * side * 0.03 - fwd_perp * (0.015 + e * 0.022), 0.004, 0.004, 6))
        # fork guard: curved plastic in front of the inner tube
        guard_top = max(0.14, (mid - bottom).length - Tf / max(0.3, AX.z) - 0.02)
        g0 = bottom + AX * 0.08
        g1 = bottom + AX * guard_top
        FK("Black", K.sweep([g0 + fwd_perp * 0.022, (g0 + g1) / 2 + fwd_perp * 0.03, g1 + fwd_perp * 0.022], 0, 10, profile=(0.022, 0.005), n=3))
    FK("Metal", K.cyl(FA - X * (tire_half + 0.022), FA + X * (tire_half + 0.022), 0.01, 0.01, 12))  # axle
    for side in (-1, 1):
        FK("Metal", K.disc(FA + X * side * (tire_half + 0.024), X, 0.012, 0.006, 6))

    # brake calipers: 4-piston, two halves either side of the rotor, the bridge, logo plate, bleeder
    def caliper4(group, axle, side_x, rotor_r, angle):
        radial = Vector((0, math.sin(angle), -math.cos(angle)))
        tangent = X.cross(radial)
        rot = K.frame_rot(X, tangent, radial)
        c = axle + X * side_x + radial * (rotor_r - 0.012)
        body = K.spline2d([(-0.055, -0.02), (0.055, -0.02), (0.06, 0.018), (0.03, 0.03), (-0.03, 0.03), (-0.06, 0.018)], 4)
        for half in (-1, 1):
            K.put(group, "Black", K.prism(body, 0.016, c + X * half * 0.011 - X * 0.008 * (1 if half > 0 else 1), tangent, radial, X, 0.004))
        K.put(group, "Black", K.rbox(c + radial * 0.034, (0.03, 0.09, 0.012), 0.004, rot))
        K.put(group, "Accent", K.rbox(c + X * (0.02 if side_x > 0 else -0.02) + X * (0.012 if side_x > 0 else -0.012), (0.003, 0.06, 0.02), 0.002, rot))
        K.put(group, "Metal", K.cyl(c + radial * 0.04 + tangent * 0.04, c + radial * 0.05 + tangent * 0.04, 0.003, 0.003, 6))

    caliper4("Fork", FA, -(0.05 + 0.035), 0.11, math.radians(-135))
    caliper4("Swing", RA, 0.05 + 0.035, 0.1, math.radians(150))

    # kit fronts: number plate with an LED bar (dirt / pit / supermoto), twin lamps (enduro), a
    # round headlight with mirrors (street / chopper); fenders high or low
    plate_c = (HB + HT) / 2 + fwd_perp * 0.1 + AX * 0.02
    plate_rot = K.frame_rot(X, fwd_perp, AX)
    if kit in ("Street", "Chopper"):
        lamp_at = plate_c + fwd_perp * 0.02 + AX * 0.03
        bowl = "Chrome" if kit == "Chopper" else "Black"
        S(bowl, K.lathe(lamp_at, fwd_perp, [(-0.085, 0), (-0.085, 0.04), (-0.06, 0.08), (0.0, 0.095), (0.012, 0.09), (0.012, 0)], 36))
        S("Chrome", K.torus(lamp_at + fwd_perp * 0.012, fwd_perp, 0.088, 0.007, 40, 8))
        S("NeonWhite", K.lathe(lamp_at + fwd_perp * 0.013, fwd_perp, [(0, 0.082), (0.01, 0.05), (0.014, 0)], 32))
        for side in (-1, 1):
            S("Black", K.bar(HT + X * side * (tw / 2 + 0.04), lamp_at + X * side * 0.07 - fwd_perp * 0.03, 0.015, 0.03, 0.004))
            base_m = P["Bars"] + X * side * (k["BarWidth"] / 2 - 0.12) + Z * 0.05
            head = base_m + X * side * 0.08 + Z * 0.2 - Y * 0.02
            S("Black", K.cyl(base_m, head - Z * 0.02, 0.006, 0.006, 8))
            S("Black", K.rbox(head, (0.1, 0.012, 0.06), 0.02))
            S("Glass", K.rbox(head - Y * 0.007, (0.09, 0.002, 0.05), 0.018))
            S("Black", K.cyl(lamp_at + X * side * 0.1 - fwd_perp * 0.02, lamp_at + X * side * 0.16 - fwd_perp * 0.02, 0.006, 0.006, 8))
            S("NeonAmber", K.sphere(lamp_at + X * side * 0.17 - fwd_perp * 0.02, 0.014, 10, 6))
    else:
        shield = K.spline2d([(-0.13, 0.11), (0.0, 0.135), (0.13, 0.11), (0.125, -0.06), (0.06, -0.13), (-0.06, -0.13), (-0.125, -0.06)], 6)
        plate_slot = "White" if kit == "Supermoto" else "Accent"
        S(plate_slot, K.prism(shield, 0.012, plate_c - fwd_perp * 0.006, X, AX, fwd_perp, 0.003))
        S("Black", K.rbox(plate_c + fwd_perp * 0.008 - AX * 0.04, (0.17, 0.006, 0.075), 0.015, plate_rot))
        if kit == "Enduro":
            for side in (-1, 1):
                S("NeonWhite", K.lathe(plate_c + fwd_perp * 0.012 - AX * 0.04 + X * side * 0.045, fwd_perp, [(0, 0.03), (0.006, 0.02), (0.008, 0)], 24))
            for side in (-1, 1):
                g0 = P["Bars"] + X * side * (k["BarWidth"] / 2 - 0.14) + Z * 0.05
                g1 = P["Bars"] + X * side * (k["BarWidth"] / 2 + 0.01) + Z * 0.06 + Y * 0.07
                S("Accent", K.sweep([g0 + Y * 0.02, g0 + Y * 0.08 + X * side * 0.05 + Z * 0.02, g1], 0, 12, profile=(0.05, 0.006)))
        else:
            S("NeonWhite", K.rbox(plate_c + fwd_perp * 0.012 - AX * 0.04, (0.15, 0.004, 0.022), 0.008, plate_rot))
            S("NeonWhite", K.rbox(plate_c + fwd_perp * 0.012 - AX * 0.07, (0.08, 0.004, 0.012), 0.005, plate_rot))
        for e in (-1, 1):
            S("Black", K.cyl(plate_c - fwd_perp * 0.01 + X * e * 0.1, HB + X * e * tire_half + fwd_perp * 0.02, 0.005, 0.005, 6))
    if road_kit:
        # a low fender hugging the tyre (it moves with the fork)
        r = Rf + 0.03
        pts = []
        for i in range(9):
            a = math.radians(-35 + i * 14)
            pts.append(FA + Y * (math.sin(a) * r) + Z * (math.cos(a) * r))
        FK("Frame" if kit == "Street" else "Accent", K.sweep(pts, 0, 16, profile=(tw / 2 + 0.025, 0.006), n=4))
        for side in (-1, 1):
            FK("Black", K.bar(FA + X * side * (tw / 2 + 0.03) + Z * 0.06, pts[4] + X * side * (tw / 2 + 0.02), 0.012, 0.02, 0.003))
    else:
        # the high MX fender under the lower clamp (higher, ahead of it, where the fork is short)
        under = HB.z - FA.z - 0.05
        up = max(under, Rf + Tf + 0.03)
        c = FA + AX * (up / AX.z)
        if up > under + 0.001:
            pts = [c + Y * 0.08, c + Y * 0.18 - Z * 0.008, c + Y * 0.28 - Z * 0.02, c + Y * 0.36 - Z * 0.04]
        else:
            pts = [c + Y * -0.16 - Z * 0.03, c + Y * 0.0, c + Y * 0.14 - Z * 0.006, c + Y * 0.26 - Z * 0.02, c + Y * 0.36 - Z * 0.045]
        S("Accent", K.sweep(pts, 0, 16, profile=(tw / 2 + 0.01, 0.006), n=3))
        S("Black", K.bar(HB - AX * 0.03, c + Z * 0.004, 0.05, 0.02, 0.006))
    # display on the top clamp, key switch
    disp = HT + AX * 0.05 + fwd_perp * 0.03
    S("Dark", K.rbox(disp, (0.1, 0.02, 0.065), 0.01, plate_rot))
    S("NeonCyan", K.rbox(disp - fwd_perp * -0.0, (0.08, 0.004, 0.045), 0.006, K.frame_rot(X, -AX * 0.0 + fwd_perp, AX)))
    S("Metal", K.cyl(HT + AX * 0.02 + X * 0.05 + fwd_perp * 0.015, HT + AX * 0.035 + X * 0.05 + fwd_perp * 0.015, 0.008, 0.008, 10))
    grips = cockpit(k, "Moto", True, P)
    # switchgear on the left, throttle housing on the right
    for i, side in enumerate((-1, 1)):
        g = grips[i]
        inner = g - X * side * 0.085
        if side < 0:
            S("Black", K.rbox(inner + Z * 0.005, (0.035, 0.04, 0.035), 0.008))
            for b in range(3):
                S("Accent" if b == 0 else "Dark", K.rbox(inner + Y * 0.021 + Z * (0.012 - b * 0.011), (0.012, 0.004, 0.008), 0.002))
        else:
            S("Black", K.cyl(inner - X * 0.02, inner + X * 0.018, 0.022, 0.022, 16))
            S("Black", K.sweep([inner + Z * 0.02, inner + Z * 0.05 - Y * 0.04, HT + fwd_perp * 0.05 + Z * 0.02], 0.003, 6))

    # ------------------------------------------------------------------ wheels
    cast = k["Id"] in CAST_WHEELS
    wheel("Front", FA, Rf * 2, tw, knobby, -1, 0.22, False, cast)
    wheel("Rear", RA, Rr * 2, tw, knobby, 1, 0.2, True, cast)
    return grips


def wheel(group, axle, D, tw, knobby, rotor_side, rotor_d, sprocket, cast=False):
    """A moto wheel: tyre (knobby or road), rim with a lock, 36 laced spokes with nipples, hub, wavy rotor."""
    put = lambda slot, bm: K.put(group, slot, bm)  # noqa: E731
    th = max(tw, D * 0.135)  # tyre section height
    R_out = D / 2
    rim_r = R_out - th
    # tyre carcass: a rounded section revolved round the axle (bead, sidewall, shoulder, crown)
    w = tw / 2
    prof = [(-w * 0.62, rim_r + 0.004), (-w * 0.95, rim_r + th * 0.3), (-w, rim_r + th * 0.6), (-w * 0.82, R_out - th * 0.12), (-w * 0.45, R_out - 0.004), (0, R_out), (w * 0.45, R_out - 0.004), (w * 0.82, R_out - th * 0.12), (w, rim_r + th * 0.6), (w * 0.95, rim_r + th * 0.3), (w * 0.62, rim_r + 0.004)]
    put("Tire", K.lathe(axle, X, prof + [(w * 0.62, rim_r + 0.002), (-w * 0.62, rim_r + 0.002)], 72))
    # raised sidewall ring (where the lettering would be)
    for side in (-1, 1):
        put("Tire", K.torus(axle + X * side * w * 0.97, X, rim_r + th * 0.45, 0.003, 64, 5, squash=0.5))
    if knobby:
        pitch = 0.05
        count = int(math.pi * D / pitch)
        knob_h = 0.016

        def place_knob(t, ox, length, wide):
            radial = Vector((0, math.cos(t), math.sin(t)))
            tangent = X.cross(radial)
            phi = math.asin(max(-0.95, min(0.95, ox / (w * 1.05))))
            normal = (radial * math.cos(phi) + X * math.sin(phi)).normalized()
            surface = R_out - (1 - math.cos(phi)) * th * 0.55
            centre = axle + radial * surface + X * ox + normal * (knob_h * 0.3)
            side = normal.cross(tangent).normalized()
            put("Tire", K.rbox(centre, (wide, length, knob_h), 0.003, K.frame_rot(side, tangent, normal), 1))

        for i in range(count):
            t = 2 * math.pi * i / count
            if i % 2 == 0:
                place_knob(t, 0.0, pitch * 0.42, tw * 0.3)
            else:
                for e in (-1, 1):
                    place_knob(t, e * w * 0.42, pitch * 0.4, tw * 0.2)
            # shoulder knobs, angled over the edge
            for e in (-1, 1):
                place_knob(t + (0.5 if i % 2 else 0) * 2 * math.pi / count, e * w * 0.82, pitch * 0.36, tw * 0.17)
    else:
        # road tyre: crown grooves as shallow dark sipes
        count = int(math.pi * D / 0.09)
        for i in range(count):
            t = 2 * math.pi * i / count
            radial = Vector((0, math.cos(t), math.sin(t)))
            tangent = X.cross(radial)
            for e in (-1, 1):
                put("Black", K.rbox(axle + radial * (R_out - 0.0015) + X * e * w * 0.35, (0.004, 0.035, 0.003), 0.0, K.frame_rot(X, tangent, radial), 1))

    # rim: deep MX section with the bead seats, a rim lock opposite the valve
    rw = tw * 0.82 / 2
    put("Rims", K.lathe(axle, X, [(-rw, rim_r - 0.026), (-rw, rim_r + 0.004), (-rw * 0.7, rim_r + 0.006), (-rw * 0.6, rim_r - 0.003), (rw * 0.6, rim_r - 0.003), (rw * 0.7, rim_r + 0.006), (rw, rim_r + 0.004), (rw, rim_r - 0.026), (rw * 0.4, rim_r - 0.032), (-rw * 0.4, rim_r - 0.032), (-rw, rim_r - 0.026)], 72))
    up = Vector((0, 0, 1))
    put("Metal", K.cyl(axle + up * (rim_r - 0.03), axle + up * (rim_r - 0.055), 0.0035, 0.0035, 8))
    put("Black", K.cyl(axle + up * (rim_r - 0.055), axle + up * (rim_r - 0.064), 0.0045, 0.0045, 8))
    put("Dark", K.rbox(axle - up * (rim_r - 0.04), (rw * 1.1, 0.03, 0.022), 0.004))

    # hub: flanges, the brake mount on one side, sprocket carrier on the rear
    hub_r = 0.05
    put("Metal", K.lathe(axle, X, [(-0.09, 0), (-0.09, 0.018), (-0.065, 0.026), (-0.058, 0.062), (-0.05, 0.066), (-0.046, 0.04), (0.046, 0.04), (0.05, 0.066), (0.058, 0.062), (0.065, 0.026), (0.09, 0.018), (0.09, 0)], 36))
    # 36 spokes laced three-cross, with nipples at the rim (or a cast wheel's five split spokes)
    per_side = 0 if cast else 18
    if cast:
        put("Rims", K.lathe(axle, X, [(-0.05, hub_r + 0.005), (-0.05, hub_r + 0.02), (0.05, hub_r + 0.02), (0.05, hub_r + 0.005)], 36))
        for i in range(5):
            for e in (-1, 1):
                t = 2 * math.pi * i / 5 + e * 0.13
                t_hub = 2 * math.pi * i / 5 + e * 0.05
                p_hub = axle + Vector((0, (hub_r + 0.012) * math.cos(t_hub), (hub_r + 0.012) * math.sin(t_hub)))
                p_rim = axle + Vector((0, (rim_r - 0.024) * math.cos(t), (rim_r - 0.024) * math.sin(t)))
                put("Rims", K.bar(p_hub, p_rim, 0.022, 0.014, 0.004, up=X))
    for side in ((-1, 1) if not cast else ()):
        for i in range(per_side):
            t = 2 * math.pi * i / per_side + (math.pi / per_side if side > 0 else 0)
            dlace = 1 if i % 2 == 0 else -1
            p_hub = axle + Vector((side * 0.054, hub_r * math.cos(t), hub_r * math.sin(t)))
            p_rim = axle + Vector((side * rw * 0.15, (rim_r - 0.03) * math.cos(t + dlace * 0.42), (rim_r - 0.03) * math.sin(t + dlace * 0.42)))
            put("Metal", K.cyl(p_hub, p_rim, 0.0028, 0.0028, 6, False))
            nd = (p_rim - p_hub).normalized()
            put("Metal", K.cyl(p_rim - nd * 0.004, p_rim + nd * 0.01, 0.0045, 0.0045, 6))

    # wavy rotor on a carrier, drilled, with its bolts
    rx = rotor_side * 0.09
    rc = axle + X * rx
    ro, ri = rotor_d / 2, rotor_d / 2 - 0.03
    put("Metal", K.petal_disc(rc, X, ro, ri, 12, 0.007, 0.004, 120))
    put("Dark", K.lathe(rc, X, [(-0.003, 0.03), (-0.003, ri + 0.004), (0.003, ri + 0.004), (0.003, 0.03), (-0.003, 0.03)], 36))
    for i in range(18):
        t = 2 * math.pi * (i + 0.5) / 18
        radial = Vector((0, math.cos(t), math.sin(t)))
        put("Dark", K.disc(rc + radial * ((ro + ri) / 2 + (0.004 if i % 2 else -0.004)), X, 0.0035, 0.0045, 8))
    for i in range(6):
        t = 2 * math.pi * i / 6
        radial = Vector((0, math.cos(t), math.sin(t)))
        put("Metal", K.disc(rc + radial * (ri - 0.006) + X * rotor_side * 0.003, X, 0.005, 0.004, 6))
    if sprocket:
        c = axle - X * (0.09)
        put("Metal", K.lathe(c, X, [(-0.003, 0.05), (-0.003, 0.1), (0.003, 0.1), (0.003, 0.05), (-0.003, 0.05)], 48))
        for i in range(48):
            t = 2 * math.pi * i / 48
            radial = Vector((0, math.cos(t), math.sin(t)))
            put("Metal", K.rbox(c + radial * 0.104, (0.005, 0.006, 0.01), 0, K.frame_rot(X, X.cross(radial), radial)))
        for i in range(6):
            t = 2 * math.pi * i / 6
            put("Dark", K.disc(c + Vector((0, 0.07 * math.cos(t), 0.07 * math.sin(t))), X, 0.012, 0.008, 12))  # lightening holes
    for side in (-1, 1):
        put("Metal", K.disc(axle + X * side * 0.094, X, 0.014, 0.01, 6))
