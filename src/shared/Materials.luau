--[[
	Materials: the PBR material library (blender/textures.py: asphalt, pavement slabs, concrete,
	stucco, brick, roof tiles, grass, sand...) in the game, replacing Roblox's base materials
	everywhere they're used, the terrain's included.

	A MaterialVariant's texture maps can only be set in Studio, not by game scripts, so the
	variants are made by the owner's one-off setup (tools/studio/SetupRealism.luau, after importing
	Vehicles.fbx) and travel in ReplicatedStorage.VehicleMeshes.Materials. At startup the server
	copies them into MaterialService (which replicates), sizes each to the city's scale (its tile's
	real metres times Config.CITY_STUDS_PER_METER) and makes it the override for its base material.
	Without the pack the game keeps Roblox's own 2022 materials.

	Directional materials (roof tiles, shingles, planks) come in two turns; Config.Realism.Turned
	picks the quarter-turned copy for a base material if its pattern runs the wrong way in Studio.
]]

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

local Materials = {}

-- The pack's variants (nil without the import)
function Materials.Pack(): Instance?
	local ok, root = pcall(function()
		return ReplicatedStorage:FindFirstChild("VehicleMeshes")
	end)
	if not ok or typeof(root) ~= "Instance" then
		return nil
	end
	return (root :: Instance):FindFirstChild("Materials")
end

function Materials.Apply(): number
	local folder = Materials.Pack()
	if not folder then
		return 0
	end
	local made = 0
	for _, variant in folder:GetChildren() do
		if not variant:IsA("MaterialVariant") then
			continue
		end
		local copy = MaterialService:FindFirstChild(variant.Name)
		if not (copy and copy:IsA("MaterialVariant")) then
			copy = variant:Clone()
		end
		local live = copy :: MaterialVariant
		local tile = variant:GetAttribute("TileMeters")
		if type(tile) == "number" then
			live.StudsPerTile = tile * Config.CITY_STUDS_PER_METER
		end
		live.Parent = MaterialService
		local base = live.BaseMaterial
		if (variant:GetAttribute("Turned") == true) == (Config.Realism.Turned[base.Name] == true) then
			pcall(function()
				MaterialService:SetBaseMaterialOverride(base, live.Name)
			end)
		end
		made += 1
	end
	return made
end

return Materials
