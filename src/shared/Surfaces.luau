--[[
	Surfaces: what kind of ground a part is to the bike (Client/World's rays, BikePhysics, the police's
	speeding and pavement offences): its "Surface" attribute if it has one, otherwise its material's.
	Shared so the city builders can keep a part's surface when they change its material for a texture
	(PartKit.Dress).
]]

local Surfaces = {}

Surfaces.MATERIALS = {
	[Enum.Material.Asphalt] = "Road",
	[Enum.Material.Pavement] = "Sidewalk",
	[Enum.Material.Concrete] = "Sidewalk",
	[Enum.Material.Cobblestone] = "Sidewalk",
	[Enum.Material.Brick] = "Sidewalk",
	[Enum.Material.Marble] = "Sidewalk",
	[Enum.Material.Granite] = "Sidewalk",
	[Enum.Material.Slate] = "Sidewalk",
	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Grass",
	[Enum.Material.Ground] = "Dirt",
	[Enum.Material.Mud] = "Mud",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.WoodPlanks] = "Ramp",
	[Enum.Material.Wood] = "Ramp",
	[Enum.Material.DiamondPlate] = "Ramp",
	[Enum.Material.Metal] = "Ramp",
} :: { [Enum.Material]: string }

function Surfaces.OfMaterial(material: Enum.Material): string
	return Surfaces.MATERIALS[material] or "Road"
end

function Surfaces.Of(part: BasePart): string
	local tagged = part:GetAttribute("Surface")
	if type(tagged) == "string" then
		return tagged
	end
	return Surfaces.OfMaterial(part.Material)
end

return Surfaces
