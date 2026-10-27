--[[
	Materials: the owner's optional PBR texture sets (AssetIds.Materials) as MaterialVariants that
	replace Roblox's base materials across the whole place. Run once on the server at startup
	(MaterialService replicates). Sets without a ColorMap are skipped, so with none filled in the
	game uses Roblox's own photo-scanned 2022 materials.
]]

local MaterialService = game:GetService("MaterialService")

local AssetIds = require(script.Parent.AssetIds)

local Materials = {}

local function asset(id: string): string
	if id == "" then
		return ""
	end
	if string.find(id, "://", 1, true) then
		return id
	end
	return "rbxassetid://" .. id
end

function Materials.Apply(): number
	local made = 0
	for name, textures in AssetIds.Materials do
		if textures.ColorMap ~= "" then
			local ok, base = pcall(function()
				return (Enum.Material :: any)[name]
			end)
			if ok and base then
				local variant = Instance.new("MaterialVariant")
				variant.Name = "Real" .. name
				variant.BaseMaterial = base
				-- the maps are Content properties (ColorMapContent...) on current Roblox, plain
				-- strings (ColorMap...) on older builds: set whichever this one has
				for _, map in { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" } do
					local id = asset((textures :: any)[map])
					if id ~= "" then
						local ok = pcall(function()
							(variant :: any)[map .. "Content"] = (Content :: any).fromUri(id)
						end)
						if not ok then
							pcall(function()
								(variant :: any)[map] = id
							end)
						end
					end
				end
				variant.StudsPerTile = textures.StudsPerTile
				variant.Parent = MaterialService
				pcall(function()
					MaterialService:SetBaseMaterialOverride(base, variant.Name)
				end)
				made += 1
			else
				warn("[Materials] no Roblox material called " .. name)
			end
		end
	end
	return made
end

return Materials
