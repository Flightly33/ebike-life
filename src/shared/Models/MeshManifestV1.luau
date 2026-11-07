--[[
	MeshManifestV1: the placement of each vehicle's meshes before it was remodelled, for imports of
	Vehicles.fbx made before then (MeshKit uses whichever manifest an import matches). Written by
	tools/lune/manifest_v1.luau. Do not edit by hand.
]]

local MeshManifest = require(script.Parent.MeshManifest)

-- (empty: the owner's import in map/VehicleMeshes.rbxm matches the current manifest)
local M: { [string]: { MeshManifest.Entry } } = {}

return M
