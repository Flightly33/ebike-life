"""
Renders each material of the PBR library (blender/out/textures) on a patch of ground under a sun
and sky with Cycles, tinted by its typical part colour the way Roblox tints a MaterialVariant, and
lays them out on one contact sheet: blender/out/renders/materials.png.

  /root/tools/blendenv/bin/python blender/preview_materials.py [Name,Name...] [--wall]
"""

import json
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "out", "textures")
OUT = os.path.join(HERE, "out", "renders")


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    try:
        scene.cycles.use_denoising = True
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        scene.cycles.use_denoising = False
    scene.render.resolution_x = 480
    scene.render.resolution_y = 320
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX" if "AgX" in [i.name for i in type(scene.view_settings).bl_rna.properties["view_transform"].enum_items] else "Filmic"
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    try:
        sky.sky_type = "NISHITA"
        sky.sun_elevation = math.radians(38)
        sky.sun_rotation = math.radians(140)
        sky.sun_disc = False
    except Exception:
        pass
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.18
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(sky.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], out.inputs[0])
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 2.2
    sun.angle = math.radians(1.0)
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = (math.radians(52), 0, math.radians(140))
    scene.collection.objects.link(sun_obj)
    return scene


def image(name, non_color):
    path = os.path.join(TEX, name)
    img = bpy.data.images.load(path, check_existing=True)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return img


def make_material(entry):
    mat = bpy.data.materials.new(entry["Name"])
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    maps = entry["Maps"]
    col = nt.nodes.new("ShaderNodeTexImage")
    col.image = image(maps["Color"], False)
    tint = nt.nodes.new("ShaderNodeRGB")
    t = entry["Tint"]
    tint.outputs[0].default_value = (srgb_to_linear(t[0]), srgb_to_linear(t[1]), srgb_to_linear(t[2]), 1)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    nt.links.new(col.outputs["Color"], mix.inputs[6])
    nt.links.new(tint.outputs[0], mix.inputs[7])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    rough = nt.nodes.new("ShaderNodeTexImage")
    rough.image = image(maps["Roughness"], True)
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    nrm = nt.nodes.new("ShaderNodeTexImage")
    nrm.image = image(maps["Normal"], True)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if "Metalness" in maps:
        met = nt.nodes.new("ShaderNodeTexImage")
        met.image = image(maps["Metalness"], True)
        nt.links.new(met.outputs["Color"], bsdf.inputs["Metallic"])
    return mat


def ground(mat, tile, tiles=4.0):
    size = tile * tiles
    bpy.ops.mesh.primitive_plane_add(size=size)
    obj = bpy.context.active_object
    uv = obj.data.uv_layers.active.data
    for loop in obj.data.loops:
        v = obj.data.vertices[loop.vertex_index].co
        uv[loop.index].uv = ((v.x / size + 0.5) * tiles, (v.y / size + 0.5) * tiles)
    obj.data.materials.append(mat)
    return obj


def camera(tile):
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 35
    obj = bpy.data.objects.new("Cam", cam)
    bpy.context.scene.collection.objects.link(obj)
    d = tile * 1.1
    obj.location = (0, -d * 0.75, d * 0.95)
    obj.rotation_euler = (math.radians(40), 0, 0)
    bpy.context.scene.camera = obj


def main():
    with open(os.path.join(TEX, "manifest.json")) as f:
        manifest = json.load(f)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = set(args[0].split(",")) if args else None
    os.makedirs(OUT, exist_ok=True)
    shots = []
    for entry in manifest["Materials"]:
        if entry.get("Turned") or (only and entry["Name"] not in only):
            continue
        scene = reset()
        mat = make_material(entry)
        ground(mat, entry["Tile"])
        camera(entry["Tile"])
        path = os.path.join(OUT, f"mat_{entry['Name']}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        shots.append((entry["Name"], path))
        print("rendered", entry["Name"])
    # contact sheet
    cols = 5
    w, h = 480, 320
    rows = math.ceil(len(shots) / cols)
    sheet = np.zeros((rows * h, cols * w, 4), np.float32)
    for i, (name, path) in enumerate(shots):
        img = bpy.data.images.load(path)
        px = np.array(img.pixels[:], np.float32).reshape(h, w, 4)[::-1]
        r, c = divmod(i, cols)
        sheet[r * h:(r + 1) * h, c * w:(c + 1) * w] = px
    out = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    out.pixels.foreach_set(sheet[::-1].ravel())
    out.filepath_raw = os.path.join(OUT, "materials.png")
    out.file_format = "PNG"
    out.save()
    print("wrote", out.filepath_raw, [s[0] for s in shots])


if __name__ == "__main__":
    main()
