"""
Renders a street the way the game dresses it: the parts left after Models/CityKit ran (boxes,
wedges, cylinders) and the city kit's meshes where CityKit put them, both from
tools/lune/preview_kit.luau's JSON, the parts wearing the realism pack's textures (blender/out/
textures, box-projected at their real tile size). For checking the kit and showing it off before
the owner imports it.

  rojo sourcemap default.project.json -o sourcemap.json
  lune run tools/lune/preview_kit.luau street.json            (bare: the part-built look)
  /root/tools/blendenv/bin/python blender/preview_street.py street.json outdir [view,view] [samples]
"""

import json
import math
import os
import sys

import bpy  # (first: it brings bmesh with it)
import bmesh  # noqa: E402
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import citykit  # noqa: E402
import facadekit  # noqa: E402
import meshkit as K  # noqa: E402
import vegetation  # noqa: E402

TEX = os.path.join(HERE, "out", "textures")
STUD = 0.28  # metres per design stud: the street is in design units

# Roblox world (x, y, z) -> Blender (x, -z, y)
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))

# cameras: (name, position, target, lens mm), Roblox design coordinates
VIEWS = {
    "street": ((-40, 7, 46), (60, 16, -40), 26),
    "shops": ((10, 6, 18), (10, 8, -38), 30),
    "houses": ((150, 7, 28), (230, 10, -66), 30),
    "villa": ((250, 8, 10), (250, 12, -50), 32),
    "lights": ((-10, 4, 14), (-20, 22, -26), 24),
    "cornice": ((-44, 44, -22), (-30, 50, -38), 40),
    "tower": ((-60, 6, 30), (-110, 60, -60), 24),
    "deco": ((400, 8, 26), (432, 18, -48), 30),
    "warehouse": ((540, 8, 22), (560, 10, -44), 30),
    "condo": ((640, 5, 26), (680, 46, -70), 22),
    "shelter": ((614, 5, -6), (625, 5, -30), 30),
    "gas": ((770, 9, 22), (795, 14, -66), 24),
    "gas_under": ((790, 4, -40), (800, 18, -70), 22),
}

SLOT_LOOK = {
    "Black": ((0.03, 0.03, 0.035), 0.0, 0.6),
    "Dark": ((0.07, 0.075, 0.08), 0.8, 0.4),
    "Metal": ((0.6, 0.61, 0.63), 1.0, 0.3),
    "Alu": ((0.62, 0.64, 0.66), 1.0, 0.32),
    "Gold": ((0.72, 0.52, 0.18), 1.0, 0.25),
    "Stone": ((0.68, 0.64, 0.56), 0.0, 0.8),
    "White": ((0.9, 0.9, 0.9), 0.0, 0.5),
    "Yellow": ((0.9, 0.62, 0.05), 0.0, 0.4),
    "Glass": ((0.04, 0.05, 0.06), 0.0, 0.05),
}


def rb_cf(comps):
    """A Roblox CFrame's 12 components -> Blender 4x4 world matrix (unscaled)."""
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = comps
    R = Matrix(((r00, r01, r02), (r10, r11, r12), (r20, r21, r22)))
    M = (C @ R @ C.transposed()).to_4x4()
    M.translation = C @ Vector((x, y, z))
    return M


def srgb_to_linear(c):
    return tuple(((v / 12.92) if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c)


def load_textures():
    path = os.path.join(TEX, "manifest.json")
    if not os.path.exists(path):
        return {}
    manifest = json.load(open(path))
    by_base = {}
    for m in manifest.get("Materials", []):
        if m.get("Livery") or m.get("Turned"):
            continue
        by_base.setdefault(m["Base"], m)
    return by_base


TEXTURES = {}
MATS = {}


def material(color, mat_name, transparency=0.0, slot=None):
    key = (tuple(round(c, 3) for c in color), mat_name, round(transparency, 2), slot)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(f"{mat_name}_{len(MATS)}")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    lin = srgb_to_linear(color)
    metal, rough = 0.0, 0.6
    if slot in SLOT_LOOK:
        lin, metal, rough = SLOT_LOOK[slot]
    if mat_name in ("Metal", "DiamondPlate", "CorrodedMetal"):
        metal, rough = 0.85, 0.35
    elif mat_name == "SmoothPlastic":
        rough = 0.45
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if mat_name == "Neon":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 4.0
    if mat_name == "Glass" or slot == "Glass":
        bsdf.inputs["Roughness"].default_value = 0.04
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Coat Weight"].default_value = 1.0
        bsdf.inputs["Base Color"].default_value = (*(c * 0.5 for c in lin), 1)
    if transparency > 0:
        bsdf.inputs["Alpha"].default_value = max(0.05, 1 - transparency)
    tex = TEXTURES.get(mat_name)
    if tex and slot is None:
        # box-projected maps at the tile's real size, multiplied by the part's colour
        coords = nt.nodes.new("ShaderNodeTexCoord")
        mapping = nt.nodes.new("ShaderNodeMapping")
        k = 1.0 / (tex["Tile"] / STUD)
        mapping.inputs["Scale"].default_value = (k, k, k)
        nt.links.new(coords.outputs["Object"], mapping.inputs["Vector"])

        def image(map_name, non_color):
            fname = tex["Maps"].get(map_name)
            if not fname:
                return None
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = bpy.data.images.load(os.path.join(TEX, os.path.basename(fname)), check_existing=True)
            node.projection = "BOX"
            node.projection_blend = 0.15
            if non_color:
                node.image.colorspace_settings.name = "Non-Color"
            nt.links.new(mapping.outputs["Vector"], node.inputs["Vector"])
            return node

        col = image("Color", False)
        if col:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[6].default_value = (*lin, 1)
            nt.links.new(col.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        rough_img = image("Roughness", True)
        if rough_img:
            nt.links.new(rough_img.outputs["Color"], bsdf.inputs["Roughness"])
        norm = image("Normal", True)
        if norm:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = 0.8
            nt.links.new(norm.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    MATS[key] = m
    return m


VEG = {}


def veg_material(slot):
    """A tree's textured slot: the pack's colour map (with its alpha on leaf cards) on its own UVs."""
    if slot in VEG:
        return VEG[slot]
    m = bpy.data.materials.new("veg_" + slot)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    path = os.path.join(TEX, "manifest.json")
    kits = {k["Name"]: k for k in json.load(open(path)).get("Kits", [])} if os.path.exists(path) else {}
    entry = kits.get(vegetation.TEXTURED[slot])
    if entry:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(os.path.join(TEX, entry["Maps"]["Color"]), check_existing=True)
        tint = vegetation.TINT.get(slot)
        if tint:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[6].default_value = (*tint, 1)
            nt.links.new(node.outputs["Color"], mix.inputs[7])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        if entry.get("Alpha"):
            nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
    VEG[slot] = m
    return m


def part_mesh(shape, size):
    """A unit-free mesh for a Roblox part of `size` (Roblox axes), in Blender axes."""
    bm = bmesh.new()
    sx, sy, sz = size
    if shape == "Cylinder":
        # Roblox cylinders run along their X
        bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=min(sy, sz) / 2, radius2=min(sy, sz) / 2, depth=sx)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    elif shape == "Ball":
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=min(size) / 2)
    elif shape == "Wedge":
        # full height on +Z (Roblox), sloping down to the -Z edge: in Blender +Z(rbx) is -y
        hx, hy, hz = sx / 2, sz / 2, sy / 2
        v = [bm.verts.new(p) for p in ((-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz), (-hx, -hy, hz), (hx, -hy, hz))]
        for f in ((0, 1, 2, 3), (0, 4, 5, 1), (1, 5, 2), (0, 3, 4), (3, 2, 5, 4)):
            bm.faces.new([v[i] for i in f])
    else:
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=(sx, sz, sy), verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def main():
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    data = json.load(open(args[0]))
    out_dir = args[1]
    views = args[2].split(",") if len(args) > 2 and args[2] else list(VIEWS)
    samples = int(args[3]) if len(args) > 3 else 48
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    TEXTURES.update(load_textures())

    # the kit's meshes, built as for Vehicles.fbx
    citykit.build_all()
    facadekit.build_all()
    K.build_objects()
    vegetation.build_all()
    sources = {ob.name: ob for ob in bpy.data.objects if ob.type == "MESH"}
    for ob in sources.values():
        ob.hide_render = True
        ob.hide_viewport = True

    # parts: each a mesh object at its CFrame, its vertices in world space so the textures'
    # object coordinates are world coordinates
    coll = bpy.data.collections.new("street")
    scene.collection.children.link(coll)
    for p in data["parts"]:
        if p["name"] in ("PreviewWater",):
            continue
        bm = part_mesh(p.get("shape", "Block"), p["size"])
        bmesh.ops.transform(bm, matrix=rb_cf(p["cf"]), verts=bm.verts)
        me = bpy.data.meshes.new(p["name"])
        bm.to_mesh(me)
        bm.free()
        me.materials.append(material(p["color"], p["material"], p.get("transparency", 0)))
        ob = bpy.data.objects.new(p["name"], me)
        coll.objects.link(ob)
    # kit meshes: a linked copy of the source, at the CFrame, scaled to the size CityKit gave it
    missing = 0
    for m in data["meshes"]:
        src = sources.get(m.get("source") or "")
        if src is None:
            missing += 1
            continue
        d = src.dimensions
        rb = (d.x, d.z, d.y)
        sx, sy, sz = (m["size"][i] / rb[i] if rb[i] > 1e-6 else 1 for i in range(3))
        ob = bpy.data.objects.new(src.name + "_i", src.data.copy())
        slot = src.name.split("__")[-1]
        ob.data.materials.clear()
        textured = slot in vegetation.TEXTURED
        if textured:
            ob.data.materials.append(veg_material(slot))
        else:
            look_slot = None if slot == "Paint" else slot
            ob.data.materials.append(material(m["color"], m["material"], m.get("transparency", 0), look_slot))
        ob.matrix_world = rb_cf(m["cf"]) @ Matrix.Diagonal((sx, sz, sy, 1.0))
        coll.objects.link(ob)
    print(f"{len(data['parts'])} parts, {len(data['meshes'])} kit meshes ({missing} without a source)")

    # sky, sun and camera
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("sky")
    scene.world = world
    world.use_nodes = True
    sky = world.node_tree.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "NISHITA"
        sky.sun_elevation = math.radians(38)
        sky.sun_rotation = math.radians(200)
    except (AttributeError, TypeError):
        pass
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Strength"].default_value = 0.35
    world.node_tree.links.new(sky.outputs["Color"], bg.inputs["Color"])
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0
    sun.data.angle = math.radians(1.0)
    sun.rotation_euler = (math.radians(52), 0, math.radians(200))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name in views:
        pos, target, lens = VIEWS[name]
        p = C @ Vector(pos)
        t = C @ Vector(target)
        cam.location = p
        cam.rotation_euler = (t - p).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = lens
        cam.data.clip_end = 5000
        scene.render.filepath = os.path.join(out_dir, f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print("wrote", scene.render.filepath)


main()
