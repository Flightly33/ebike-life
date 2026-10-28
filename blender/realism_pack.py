"""
The realism pack: puts every texture of the PBR library (blender/textures.py) and the vegetation
(blender/veg_textures.py) into Vehicles.fbx so one Studio import uploads them all, and writes the
command-bar snippet that wires them up (tools/studio/SetupRealism.luau).

How the textures travel: each image rides on its own little quad ("Swatch__<Image>") as that
quad's colour texture, the one kind of texture every importer path uploads. The snippet reads the
uploaded image ids back off the swatches, builds a MaterialVariant per material (colour, normal,
roughness, metalness) and a SurfaceAppearance on every vegetation mesh, then removes the swatches.
Kit meshes carry no textures of their own in the file, so nothing uploads twice.

Called from build_vehicles.py (add_swatches before the export, write_snippet after).
"""

import json
import os
import re

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEX = os.path.join(HERE, "out", "textures")
SNIPPET = os.path.join(ROOT, "tools", "studio", "SetupRealism.luau")


def load_manifest():
    path = os.path.join(TEX, "manifest.json")
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f)


def images(manifest):
    """Every image file the pack needs, once."""
    seen = []
    for entry in manifest.get("Materials", []) + manifest.get("Kits", []):
        for fname in entry["Maps"].values():
            if fname not in seen:
                seen.append(fname)
    return seen


def stem(fname):
    return os.path.splitext(fname)[0]


def add_swatches(scene=None):
    """One small textured quad per image, under an empty "Realism_Swatches"."""
    manifest = load_manifest()
    if not manifest:
        print("no blender/out/textures/manifest.json: run textures.py and veg_textures.py first")
        return 0
    scene = scene or bpy.context.scene
    parent = bpy.data.objects.new("Realism_Swatches", None)
    scene.collection.objects.link(parent)
    files = images(manifest)
    for i, fname in enumerate(files):
        name = "Swatch__" + stem(fname)
        me = bpy.data.meshes.new(name)
        x, y = (i % 10) * 1.5, (i // 10) * 1.5
        me.from_pydata([(x, y, 0), (x + 1, y, 0), (x + 1, y + 1, 0), (x, y + 1, 0)], [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new(name="UVMap")
        for loop, co in zip(uv.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop.uv = co
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(TEX, fname), check_existing=True)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        scene.collection.objects.link(ob)
        ob.parent = parent
    print(f"realism pack: {len(files)} texture swatches")
    return len(files)


def kit_materials():
    """Give each vegetation slot a plain material (no textures in the file)."""
    import vegetation as V

    for slot in list(V.TEXTURED) + list(V.PLAIN):
        mat = bpy.data.materials.get(slot)
        if mat:
            mat.use_nodes = False
            c = V.PLAIN.get(slot, (0.5, 0.5, 0.5))
            mat.diffuse_color = (c[0], c[1], c[2], 1)


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_snippet(world_scale):
    import vegetation as V

    manifest = load_manifest()
    if not manifest:
        return
    studs_per_metre = world_scale / 0.28
    mats = []
    for m in manifest["Materials"]:
        maps = ", ".join(f"{k} = {lua_string(stem(v))}" for k, v in m["Maps"].items())
        mats.append(f'\t{{ Name = "Real{m["Name"]}", Base = "{m["Base"]}", Pattern = "{m["Pattern"]}", TileMeters = {m["Tile"]}, Turned = {"true" if m.get("Turned") else "false"}, Maps = {{ {maps} }} }},')
    kits = []
    by_name = {k["Name"]: k for k in manifest.get("Kits", [])}
    for slot, tex in V.TEXTURED.items():
        entry = by_name.get(tex)
        if not entry:
            continue
        maps = ", ".join(f"{k} = {lua_string(stem(v))}" for k, v in entry["Maps"].items())
        tint = V.TINT.get(slot)
        tint_lua = f"Color3.new({tint[0]}, {tint[1]}, {tint[2]})" if tint else "nil"
        kits.append(f'\t{slot} = {{ Alpha = {"true" if entry["Alpha"] else "false"}, Tint = {tint_lua}, Maps = {{ {maps} }} }},')
    body = TEMPLATE.replace("%MATERIALS%", "\n".join(mats)).replace("%KITS%", "\n".join(kits)).replace("%STUDS_PER_METRE%", f"{studs_per_metre:.4f}")
    os.makedirs(os.path.dirname(SNIPPET), exist_ok=True)
    with open(SNIPPET, "w") as f:
        f.write(body)
    print("wrote", os.path.relpath(SNIPPET, ROOT))


TEMPLATE = r"""--[[
	SetupRealism: paste this whole file into Studio's command bar (View > Command Bar) and press
	Enter, once, after importing blender/out/Vehicles.fbx into ReplicatedStorage and naming the
	imported model "VehicleMeshes". Generated by blender/realism_pack.py; don't edit by hand.

	It finds the texture images the import uploaded (each rode in on a "Swatch__" quad), builds a
	MaterialVariant for every material of the PBR library (colour, normal, roughness, metalness)
	and a SurfaceAppearance on every tree and palm mesh, removes the swatches, and turns the new
	materials on in this place so you can look around straight away.

	Then right-click ReplicatedStorage > VehicleMeshes > Save to File..., and send the .rbxm file
	back: every build of the game will include it from then on.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")

local STUDS_PER_METRE = %STUDS_PER_METRE% -- the city's scale (the game sets this again at runtime)

local MATERIALS = {
%MATERIALS%
}

local KITS = {
%KITS%
}

local root = ReplicatedStorage:FindFirstChild("VehicleMeshes")
if not root then
	error("Import blender/out/Vehicles.fbx into ReplicatedStorage first and name the model VehicleMeshes")
end

-- the image ids the import uploaded, by image name
local uploaded: { [string]: string } = {}
local swatches = {}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and string.find(d.Name, "^Swatch__") then
		local name = string.match(d.Name, "^Swatch__([%w_]+)") :: string
		name = string.gsub(name, "_%d%d%d$", "")
		local id = ""
		local appearance = d:FindFirstChildOfClass("SurfaceAppearance")
		if appearance then
			pcall(function()
				id = (appearance :: any).ColorMap
			end)
			if id == "" then
				pcall(function()
					id = (appearance :: any).ColorMapContent.Uri or ""
				end)
			end
		end
		if id == "" and d:IsA("MeshPart") then
			pcall(function()
				id = d.TextureID
			end)
			if id == "" then
				pcall(function()
					id = (d :: any).TextureContent.Uri or ""
				end)
			end
		end
		if id ~= "" then
			uploaded[name] = id
		end
		table.insert(swatches, d)
	end
end

local missing = {}
local function map(name: string?): string?
	if not name then
		return nil
	end
	local id = uploaded[name]
	if not id then
		missing[name] = true
	end
	return id
end

local function setMap(target: Instance, prop: string, id: string?)
	if not id then
		return
	end
	local ok = pcall(function()
		(target :: any)[prop .. "Content"] = Content.fromUri(id)
	end)
	if not ok then
		pcall(function()
			(target :: any)[prop] = id
		end)
	end
end

-- MaterialVariants: one copy in MaterialService (live in this place) and one saved with the pack
local saved = root:FindFirstChild("Materials") or Instance.new("Folder")
saved.Name = "Materials"
saved.Parent = root
local made = 0
for _, spec in MATERIALS do
	local base = (Enum.Material :: any)[spec.Base]
	local color = map(spec.Maps.Color)
	if not base or not color then
		continue
	end
	for _, parent in { MaterialService, saved } do
		local old = parent:FindFirstChild(spec.Name)
		if old then
			old:Destroy()
		end
		local variant = Instance.new("MaterialVariant")
		variant.Name = spec.Name
		variant.BaseMaterial = base
		variant.MaterialPattern = if spec.Pattern == "Organic" then Enum.MaterialPattern.Organic else Enum.MaterialPattern.Regular
		variant.StudsPerTile = spec.TileMeters * STUDS_PER_METRE
		variant:SetAttribute("TileMeters", spec.TileMeters)
		variant:SetAttribute("Turned", spec.Turned)
		setMap(variant, "ColorMap", color)
		setMap(variant, "NormalMap", map(spec.Maps.Normal))
		setMap(variant, "RoughnessMap", map(spec.Maps.Roughness))
		setMap(variant, "MetalnessMap", map(spec.Maps.Metalness))
		variant.Parent = parent
	end
	if not spec.Turned then
		MaterialService:SetBaseMaterialOverride(base, spec.Name)
	end
	made += 1
end

-- the trees and palms: a SurfaceAppearance on each textured mesh ("Kit_...__Main__<Slot>")
local dressed = 0
for _, d in root:GetDescendants() do
	if d:IsA("MeshPart") then
		local slot = string.match(d.Name, "^Kit_[%w_]-__Main__([%w]+)")
		local spec = slot and KITS[slot]
		if spec then
			for _, child in d:GetChildren() do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			local appearance = Instance.new("SurfaceAppearance")
			setMap(appearance, "ColorMap", map(spec.Maps.Color))
			setMap(appearance, "NormalMap", map(spec.Maps.Normal))
			setMap(appearance, "RoughnessMap", map(spec.Maps.Roughness))
			pcall(function()
				appearance.AlphaMode = if spec.Alpha then Enum.AlphaMode.Transparency else Enum.AlphaMode.Overlay
			end)
			if spec.Tint then
				pcall(function()
					(appearance :: any).Color = spec.Tint
				end)
			end
			appearance.Parent = d
			d.CastShadow = true
			dressed += 1
		end
	end
end

for _, swatch in swatches do
	swatch:Destroy()
end
for _, d in root:GetDescendants() do
	if d:IsA("Model") and d.Name == "Realism_Swatches" and #d:GetChildren() == 0 then
		d:Destroy()
	end
end

local gone = {}
for name in missing do
	table.insert(gone, name)
end
table.sort(gone)
print(string.format("[SetupRealism] %d materials and %d tree meshes set up from %d uploaded images", made, dressed, (function()
	local n = 0
	for _ in uploaded do
		n += 1
	end
	return n
end)()))
if #gone > 0 then
	warn("[SetupRealism] these images didn't upload (re-import and run again): " .. table.concat(gone, ", "))
end
print("[SetupRealism] Now right-click ReplicatedStorage > VehicleMeshes > Save to File..., and send the .rbxm back.")
"""
