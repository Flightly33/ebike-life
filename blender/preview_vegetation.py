"""
Renders the vegetation kits (blender/vegetation.py) with their textures in Cycles, each on a
patch of grass under a sun and sky: blender/out/renders/veg_<Kit>.png and vegetation.png.

  /root/tools/blendenv/bin/python blender/preview_vegetation.py
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import preview_materials as PM  # noqa: E402
import vegetation as V  # noqa: E402

TEX = os.path.join(HERE, "out", "textures")
OUT = os.path.join(HERE, "out", "renders")


def kit_material(slot, manifest):
    mat = bpy.data.materials.get(slot)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    if slot in V.PLAIN:
        c = V.PLAIN[slot]
        bsdf.inputs["Base Color"].default_value = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1)
        bsdf.inputs["Roughness"].default_value = 0.6
        return
    entry = next(k for k in manifest["Kits"] if k["Name"] == V.TEXTURED[slot])
    maps = entry["Maps"]
    col = nt.nodes.new("ShaderNodeTexImage")
    col.image = PM.image(maps["Color"], False)
    color_out = col.outputs["Color"]
    if slot in V.TINT:
        t = V.TINT[slot]
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs[0].default_value = 1.0
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (t[0] ** 2.2 * 1.6, t[1] ** 2.2 * 1.6, t[2] ** 2.2 * 1.6, 1)
        nt.links.new(color_out, mix.inputs[6])
        nt.links.new(rgb.outputs[0], mix.inputs[7])
        color_out = mix.outputs[2]
    nt.links.new(color_out, bsdf.inputs["Base Color"])
    if entry["Alpha"]:
        nt.links.new(col.outputs["Alpha"], bsdf.inputs["Alpha"])
    rough = nt.nodes.new("ShaderNodeTexImage")
    rough.image = PM.image(maps["Roughness"], True)
    nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    nrm = nt.nodes.new("ShaderNodeTexImage")
    nrm.image = PM.image(maps["Normal"], True)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])


def main():
    with open(os.path.join(TEX, "manifest.json")) as f:
        manifest = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    shots = []
    for kit in V.KITS:
        scene = PM.reset()
        scene.render.resolution_x = 480
        scene.render.resolution_y = 640
        scene.cycles.samples = 48
        saved = dict(V.KITS)
        V.KITS.clear()
        V.KITS[kit] = saved[kit]
        man = V.build_all(scene)
        V.KITS.clear()
        V.KITS.update(saved)
        for e in man[kit]:
            kit_material(e["Slot"], manifest)
        # grass under it, using the library's grass
        grass_entry = next(m for m in manifest["Materials"] if m["Name"] == "Grass")
        PM.ground(PM.make_material(grass_entry), grass_entry["Tile"], tiles=20)
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for ob in scene.objects:
            if ob.type == "MESH" and ob.name.startswith(kit):
                for c in ob.bound_box:
                    w = ob.matrix_world @ Vector(c)
                    lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                    hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        height = hi.z
        cam = bpy.data.cameras.new("Cam")
        cam.lens = 35
        cobj = bpy.data.objects.new("Cam", cam)
        scene.collection.objects.link(cobj)
        dist = height * 1.45
        mid = (lo + hi) / 2
        cobj.location = (mid.x + dist * 0.25, mid.y - dist, height * 0.42)
        direction = Vector((mid.x, mid.y, height * 0.5)) - cobj.location
        cobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.camera = cobj
        path = os.path.join(OUT, f"veg_{kit}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        shots.append(path)
        print("rendered", kit)
    w, h = 480, 640
    sheet = np.zeros((h, w * len(shots), 4), np.float32)
    for i, path in enumerate(shots):
        img = bpy.data.images.load(path)
        sheet[:, i * w:(i + 1) * w] = np.array(img.pixels[:], np.float32).reshape(h, w, 4)[::-1]
    out = bpy.data.images.new("sheet", w * len(shots), h, alpha=True)
    out.pixels.foreach_set(sheet[::-1].ravel())
    out.filepath_raw = os.path.join(OUT, "vegetation.png")
    out.file_format = "PNG"
    out.save()
    print("wrote", out.filepath_raw)


if __name__ == "__main__":
    main()
