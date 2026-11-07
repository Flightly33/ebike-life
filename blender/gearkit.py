"""Rider gear meshes (src/shared/Gear.luau, src/server/GearService.luau).

One rounded shell per style and slot, named `Gear_<Style>_<Slot>` (its mesh object
`Gear_<Style>_<Slot>__Shell__Paint`): GearService clones it, sizes it to the body part it sits on
(MeshPart.Size stretches the mesh's box to fit) and colours it with the item's main colour; the
trim (visors, stripes, buckles) stays part-built. Modelled round the origin, +Y forward (the face of
a helmet, the toe of a boot), +Z up; it lands in CityKit.fbx with the Kit_* meshes.
"""

import math

from mathutils import Vector

import meshkit as K

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


def put(name, bm):
    K.vehicle(name)
    K.put("Shell", "Paint", bm)


def helmet(style):
    """A rounded shell: an egg for the full-face and race lids, a dome for the open-face one; the MX
    lid gets its chin bar and peak, the race lid a little spoiler."""
    name = f"Gear_{style}_Helmet"
    if style == "OpenFace":
        # a dome down to the brow at the front, lower at the back
        put(name, K.lathe(Vector((0, 0, -0.1)), Z, [(0.0, 0.5), (0.18, 0.49), (0.36, 0.44), (0.5, 0.34), (0.58, 0.2), (0.62, 0.0)], 36))
        K.put("Shell", "Paint", K.rbox(Vector((0, -0.1, -0.2)), (0.92, 0.6, 0.3), 0.12))  # the back of the head
        return
    # an egg, a little longer front to back
    put(name, K.lathe(Vector((0, 0, -0.5)), Z, [(0.0, 0.0), (0.04, 0.32), (0.16, 0.45), (0.4, 0.5), (0.62, 0.48), (0.82, 0.38), (0.96, 0.2), (1.0, 0.0)], 40))
    if style == "MX":
        K.put("Shell", "Paint", K.rbox(Vector((0, 0.42, -0.28)), (0.5, 0.22, 0.28), 0.08))  # chin bar
        K.put("Shell", "Paint", K.rbox(Vector((0, 0.36, 0.38)), (0.8, 0.4, 0.05), 0.02, K.frame_rot(X, (Y + Z * 0.25).normalized(), (Z - Y * 0.25).normalized())))  # peak
    elif style == "Race":
        K.put("Shell", "Paint", K.rbox(Vector((0, -0.42, 0.3)), (0.5, 0.16, 0.06), 0.02))  # spoiler


def jacket(style):
    """A torso shell with a raised collar; the race suit's hump on the back."""
    name = f"Gear_{style}_Jacket"
    put(name, K.rbox(Vector((0, 0, 0)), (1.0, 0.9, 1.0), 0.16, seg=4))
    K.put("Shell", "Paint", K.cyl(Vector((0, 0, 0.46)), Vector((0, 0, 0.56)), 0.24, 0.22, 24))  # collar
    if style == "Race":
        K.put("Shell", "Paint", K.sphere(Vector((0, -0.42, 0.18)), 0.22, 20, 12))  # hump
    if style == "Leather":
        for side in (-1, 1):
            K.put("Shell", "Paint", K.rbox(Vector((side * 0.26, 0.44, 0.1)), (0.18, 0.04, 0.5), 0.02))  # lapels


def gloves(style):
    """A rounded hand shell with knuckle padding; the gauntlet's cuff flares at the wrist."""
    name = f"Gear_{style}_Gloves"
    put(name, K.rbox(Vector((0, 0, 0)), (0.9, 0.9, 1.0), 0.2, seg=4))
    K.put("Shell", "Paint", K.rbox(Vector((0, 0.38, -0.15)), (0.85, 0.2, 0.25), 0.08))
    if style == "Gauntlets":
        K.put("Shell", "Paint", K.cyl(Vector((0, 0, 0.42)), Vector((0, 0, 0.6)), 0.46, 0.55, 24))


def boots(style):
    """A boot: a rounded shell with the toe ahead; the MX boot's sole stands proud."""
    name = f"Gear_{style}_Boots"
    put(name, K.rbox(Vector((0, -0.05, 0.05)), (0.9, 0.9, 0.9), 0.18, seg=4))
    K.put("Shell", "Paint", K.sphere(Vector((0, 0.32, -0.15)), 0.32, 20, 12))  # toe
    K.put("Shell", "Paint", K.rbox(Vector((0, 0.05, -0.44)), (0.96, 1.05, 0.12), 0.03))  # sole
    if style == "MXBoots":
        for i in range(3):
            K.put("Shell", "Paint", K.rbox(Vector((0, 0.46, 0.25 - i * 0.18)), (0.7, 0.04, 0.06), 0.01))  # buckle straps


# every style and slot Shared/Gear uses
STYLES = {
    "Helmet": ("OpenFace", "MX", "FullFace", "Race"),
    "Jacket": ("Jacket", "Leather", "Race"),
    "Gloves": ("Gloves", "Gauntlets"),
    "Boots": ("Boots", "MXBoots"),
}


def build_all():
    for style in STYLES["Helmet"]:
        helmet(style)
    for style in STYLES["Jacket"]:
        jacket(style)
    for style in STYLES["Gloves"]:
        gloves(style)
    for style in STYLES["Boots"]:
        boots(style)
    _ = math
