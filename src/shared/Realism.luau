--[[
	Realism: one pass over a built model (the city, a car, a part-built bike) that gives each part
	the real-world material its role calls for, from Roblox's photo-scanned 2022 material set:
	rubber tyres, shingle or clay-tile house roofs, leather and fabric seats, glass that reflects,
	glossy paint on vehicle bodies. Colours are left alone (the builders choose them).

	The owner can go further with their own PBR textures: AssetIds.Materials (MaterialVariants,
	made at startup by Shared/Materials) override the base materials everywhere at once.
]]

local Realism = {}

local Material = Enum.Material

-- by part name
local BY_NAME: { [string]: Enum.Material } = {
	Tire = Material.Rubber,
	Tyre = Material.Rubber,
	Sidewall = Material.Rubber,
	TyreStack = Material.Rubber,
	SeatBase = Material.Leather,
	SeatBack = Material.Leather,
	Headrest = Material.Leather,
	Sofa = Material.Fabric,
	SofaBack = Material.Fabric,
	Rug = Material.Carpet,
}

local HOUSE_ROOFS: { [string]: boolean } = { Roof = true, GarageRoof = true, PorchRoof = true }

-- glossy vehicle paint and glass: a little reflection reads as clear coat and window glass
local PAINT_REFLECTANCE = 0.08
local GLASS_REFLECTANCE = 0.2

local function reddish(c: Color3): boolean
	return c.R > c.G + 0.2 and c.R > c.B + 0.2
end

function Realism.Part(part: BasePart, context: string?, paint: Color3?)
	local name = part.Name
	local byName = BY_NAME[name]
	if byName then
		part.Material = byName
		return
	end
	if HOUSE_ROOFS[name] and context == "House" then
		-- clay tiles on red roofs, asphalt shingles on the rest
		part.Material = if reddish(part.Color) then Material.ClayRoofTiles else Material.RoofShingles
		return
	end
	if part.Material == Material.Glass and part.Transparency < 1 then
		part.Reflectance = math.max(part.Reflectance, GLASS_REFLECTANCE)
		return
	end
	local painted = part:GetAttribute("Paint") ~= nil or (paint ~= nil and part.Color == paint)
	if context == "Vehicle" and painted and part.Material == Material.SmoothPlastic and part.Transparency < 1 then
		part.Reflectance = math.max(part.Reflectance, PAINT_REFLECTANCE)
	end
end

-- Every part under `root`. `context` says what it is ("Vehicle", with its body colour `paint`);
-- houses are found by their model.
function Realism.Apply(root: Instance, context: string?, paint: Color3?)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local ctx = context
			if ctx == nil then
				local model = d:FindFirstAncestorWhichIsA("Model")
				ctx = if model and model.Name == "House" then "House" else nil
			end
			Realism.Part(d, ctx, paint)
		end
	end
end

return Realism
