--[[
	Keeps the old placement of every remodelled vehicle, so an import made before the remodel keeps
	working (MeshKit picks whichever manifest the imported meshes match).

	Run after blender/build_vehicles.py has rewritten MeshManifest.luau, with the manifest the
	owner's import was made from (the committed one) as the argument:

	  git show HEAD:src/shared/Models/MeshManifest.luau > /tmp/old.luau
	  lune run tools/lune/manifest_v1.luau /tmp/old.luau

	Writes src/shared/Models/MeshManifestV1.luau with the old entries of each vehicle whose
	entries changed, merged over the ones already in it (a vehicle already kept stays as it was:
	that's what the owner's import holds).
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

type Entry = { Name: string, Group: string, Slot: string, Center: any, Size: any }

local function load(path: string): { [string]: { Entry } }
	local source = fs.readFile(path)
	source = string.gsub(source, "export type[^\n]*\n", "")
	source = string.gsub(source, "local MeshManifest = require[^\n]*\n", "")
	source = string.gsub(source, "local M: [^=]+=", "local M =")
	return luau.load(source, { environment = { Vector3 = Vector3 } })()
end

local oldPath = process.args[1]
assert(oldPath, "usage: lune run tools/lune/manifest_v1.luau <old MeshManifest.luau>")
local old = load(oldPath)
local new = load("src/shared/Models/MeshManifest.luau")
local v1Path = "src/shared/Models/MeshManifestV1.luau"
local kept: { [string]: { Entry } } = if fs.isFile(v1Path) then load(v1Path) else {}

local function same(a: { Entry }, b: { Entry }): boolean
	if #a ~= #b then
		return false
	end
	local byName: { [string]: Entry } = {}
	for _, e in b do
		byName[e.Name] = e
	end
	for _, e in a do
		local f = byName[e.Name]
		if not f or (e.Size - f.Size).Magnitude > 2e-4 or (e.Center - f.Center).Magnitude > 2e-4 then
			return false
		end
	end
	return true
end

local changed = 0
for vehicle, entries in old do
	if kept[vehicle] == nil and (new[vehicle] == nil or not same(entries, new[vehicle])) then
		kept[vehicle] = entries
		changed += 1
		print("kept the old " .. vehicle)
	end
end

local names = {}
for vehicle in kept do
	table.insert(names, vehicle)
end
table.sort(names)
local lines = {
	"--[[",
	"\tMeshManifestV1: the placement of each vehicle's meshes before it was remodelled, for imports of",
	"\tVehicles.fbx made before then (MeshKit uses whichever manifest an import matches). Written by",
	"\ttools/lune/manifest_v1.luau. Do not edit by hand.",
	"]]",
	"",
	"local MeshManifest = require(script.Parent.MeshManifest)",
	"",
	"local M: { [string]: { MeshManifest.Entry } } = {",
}
local function v(x: any): string
	return string.format("Vector3.new(%.4f, %.4f, %.4f)", x.X, x.Y, x.Z)
end
for _, vehicle in names do
	table.insert(lines, string.format('\t["%s"] = {', vehicle))
	for _, e in kept[vehicle] do
		table.insert(lines, string.format('\t\t{ Name = "%s", Group = "%s", Slot = "%s", Center = %s, Size = %s },', e.Name, e.Group, e.Slot, v(e.Center), v(e.Size)))
	end
	table.insert(lines, "\t},")
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "return M")
fs.writeFile(v1Path, table.concat(lines, "\n") .. "\n")
print(string.format("%d vehicles kept (%d new)", #names, changed))
