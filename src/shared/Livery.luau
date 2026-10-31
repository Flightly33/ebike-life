--[[
	Livery: how each part of a bike is painted, beyond the crate paints (Shared/Paints).

	A bike's paint choice (Profile.Paint[bikeId]) holds one value per slot (Livery.Slots: frame,
	plastics, wheels, seat, suspension; plus the underglow in "Glow"). A value is either a crate
	paint id ("chrome", "neon_pink"...) or a custom coat, coded as "#RRGGBB/finish/pattern":
	any colour, a finish (Livery.Finishes: gloss, matte, satin, metallic, pearl, chrome, neon...)
	and a pattern (Livery.Patterns: carbon fibre, camo, snakeskin...; "none" for plain).

	Finishes are Roblox's own materials, so they work everywhere. Patterns are MaterialVariants from
	the realism pack (blender/textures.py paints them; they arrive with the owner's Studio import),
	tinted by the coat's colour; without the pack a pattern shows as its finish alone.

	Custom coats cost cash at Flighty Garage (Livery.Price: a base for the bike's class, plus the
	finish and the pattern); crate paints are free once unlocked.
]]

local Paints = require(script.Parent.Paints)

local Livery = {}

export type Slot = { Key: string, Title: string, Icon: string, Default: Color3, DefaultMaterial: Enum.Material }
export type Finish = { Id: string, Name: string, Material: Enum.Material, Reflectance: number, Price: number, SeatOnly: boolean? }
export type Pattern = { Id: string, Name: string, Variant: string, Base: Enum.Material, Price: number }
export type Coat = { Color: Color3, Finish: Finish, Pattern: Pattern? }
export type Look = { Color: Color3, Material: Enum.Material, Reflectance: number, Variant: string? }

Livery.Slots = {
	{ Key = "Frame", Title = "Frame & tank", Icon = "🏍", Default = Color3.fromRGB(128, 128, 128), DefaultMaterial = Enum.Material.SmoothPlastic },
	{ Key = "Accent", Title = "Plastics", Icon = "🛡", Default = Color3.fromRGB(128, 128, 128), DefaultMaterial = Enum.Material.SmoothPlastic },
	{ Key = "Rims", Title = "Wheels", Icon = "⭕", Default = Color3.fromRGB(40, 40, 44), DefaultMaterial = Enum.Material.Metal },
	{ Key = "Seat", Title = "Seat", Icon = "💺", Default = Color3.fromRGB(34, 30, 28), DefaultMaterial = Enum.Material.Leather },
	{ Key = "Susp", Title = "Suspension", Icon = "🔩", Default = Color3.fromRGB(205, 160, 45), DefaultMaterial = Enum.Material.Metal },
} :: { Slot }

Livery.BySlot = {} :: { [string]: Slot }
for _, slot in Livery.Slots do
	Livery.BySlot[slot.Key] = slot
end

local SM = Enum.Material.SmoothPlastic

Livery.Finishes = {
	{ Id = "gloss", Name = "Gloss", Material = SM, Reflectance = 0.12, Price = 0 },
	{ Id = "matte", Name = "Matte", Material = Enum.Material.Plastic, Reflectance = 0, Price = 0 },
	{ Id = "satin", Name = "Satin", Material = SM, Reflectance = 0.04, Price = 150 },
	{ Id = "metallic", Name = "Metallic flake", Material = Enum.Material.Metal, Reflectance = 0.1, Price = 450 },
	{ Id = "pearl", Name = "Pearl", Material = SM, Reflectance = 0.32, Price = 700 },
	{ Id = "chrome", Name = "Chrome", Material = Enum.Material.Metal, Reflectance = 0.6, Price = 1800 },
	{ Id = "anodised", Name = "Anodised", Material = Enum.Material.Foil, Reflectance = 0.15, Price = 900 },
	{ Id = "rubber", Name = "Soft-touch", Material = Enum.Material.Rubber, Reflectance = 0, Price = 250 },
	{ Id = "rusty", Name = "Rat rod rust", Material = Enum.Material.CorrodedMetal, Reflectance = 0, Price = 400 },
	{ Id = "neon", Name = "Neon glow", Material = Enum.Material.Neon, Reflectance = 0, Price = 3000 },
	{ Id = "leather", Name = "Leather", Material = Enum.Material.Leather, Reflectance = 0, Price = 0, SeatOnly = true },
	{ Id = "suede", Name = "Suede", Material = Enum.Material.Fabric, Reflectance = 0, Price = 200, SeatOnly = true },
} :: { Finish }

-- (the variants' names in MaterialService: "RealPattern<Name>", made by the realism pack)
Livery.Patterns = {
	{ Id = "carbon", Name = "Carbon fibre", Variant = "RealPatternCarbon", Base = Enum.Material.Plastic, Price = 2400 },
	{ Id = "forged", Name = "Forged carbon", Variant = "RealPatternForged", Base = Enum.Material.Plastic, Price = 3000 },
	{ Id = "brushed", Name = "Brushed alloy", Variant = "RealPatternBrushed", Base = Enum.Material.Metal, Price = 1500 },
	{ Id = "camo", Name = "Woodland camo", Variant = "RealPatternCamo", Base = Enum.Material.Plastic, Price = 1600 },
	{ Id = "digicamo", Name = "Digital camo", Variant = "RealPatternDigiCamo", Base = Enum.Material.Plastic, Price = 1600 },
	{ Id = "hex", Name = "Hex weave", Variant = "RealPatternHex", Base = Enum.Material.Plastic, Price = 1800 },
	{ Id = "snake", Name = "Snakeskin", Variant = "RealPatternSnake", Base = Enum.Material.Plastic, Price = 2200 },
	{ Id = "tiger", Name = "Tiger stripe", Variant = "RealPatternTiger", Base = Enum.Material.Plastic, Price = 2000 },
	{ Id = "checker", Name = "Race checker", Variant = "RealPatternChecker", Base = Enum.Material.Plastic, Price = 1400 },
	{ Id = "splatter", Name = "Paint splatter", Variant = "RealPatternSplatter", Base = Enum.Material.Plastic, Price = 1300 },
	{ Id = "flames", Name = "Hot-rod flames", Variant = "RealPatternFlames", Base = Enum.Material.Plastic, Price = 2600 },
	{ Id = "quilted", Name = "Diamond quilt", Variant = "RealPatternQuilted", Base = Enum.Material.Leather, Price = 900 },
} :: { Pattern }

local finishById: { [string]: Finish } = {}
for _, f in Livery.Finishes do
	finishById[f.Id] = f
end
local patternById: { [string]: Pattern } = {}
for _, p in Livery.Patterns do
	patternById[p.Id] = p
end

function Livery.Finish(id: string): Finish?
	return finishById[id]
end

function Livery.Pattern(id: string): Pattern?
	return patternById[id]
end

local function hex(c: Color3): string
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- "#RRGGBB/finish/pattern"
function Livery.Encode(color: Color3, finish: string, pattern: string?): string
	return string.format("#%s/%s/%s", hex(color), finish, pattern or "none")
end

-- A custom coat from its code (nil if it isn't one, or isn't valid)
function Livery.Decode(code: any): Coat?
	if type(code) ~= "string" or #code > 40 then
		return nil
	end
	local rgb, finishId, patternId = string.match(code, "^#(%x%x%x%x%x%x)/(%a+)/(%a+)$")
	if not rgb then
		return nil
	end
	local finish = finishById[finishId :: string]
	if not finish then
		return nil
	end
	local pattern: Pattern? = nil
	if patternId ~= "none" then
		pattern = patternById[patternId :: string]
		if not pattern then
			return nil
		end
	end
	local value = tonumber(rgb, 16) :: number
	local color = Color3.fromRGB(math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
	return { Color = color, Finish = finish, Pattern = pattern }
end

-- Is `value` something that can go in `slot` (a custom coat, or a crate paint of the right kind)?
-- Seat-only finishes stay on the seat.
function Livery.Valid(slot: string, value: any): boolean
	if slot == "Glow" then
		local paint = Paints.Get(value)
		return paint ~= nil and paint.Kind == "Glow"
	end
	if not Livery.BySlot[slot] then
		return false
	end
	local coat = Livery.Decode(value)
	if coat then
		return not coat.Finish.SeatOnly or slot == "Seat"
	end
	local paint = Paints.Get(value)
	return paint ~= nil and paint.Kind == "Paint"
end

-- What a custom coat costs on this bike (crate paints are free once unlocked)
function Livery.Price(bikePrice: number, value: any): number
	local coat = Livery.Decode(value)
	if not coat then
		return 0
	end
	local base = 150 + math.floor(bikePrice * 0.006 / 25 + 0.5) * 25
	return base + coat.Finish.Price + (if coat.Pattern then coat.Pattern.Price else 0)
end

-- The cost of going from one paint choice to another (only the slots that change)
function Livery.Cost(bikePrice: number, old: { [string]: string? }?, new: { [string]: string? }): number
	local total = 0
	for _, slot in Livery.Slots do
		local value = new[slot.Key]
		if value ~= nil and value ~= (if old then old[slot.Key] else nil) then
			total += Livery.Price(bikePrice, value)
		end
	end
	return total
end

-- How a slot looks: its colour, material, shine and pattern variant. `defaults` are the bike's own
-- colours for Frame / Accent / Rims.
function Livery.Look(slotKey: string, value: string?, defaults: { [string]: Color3 }?): Look
	local slot = Livery.BySlot[slotKey]
	local default = (defaults and defaults[slotKey]) or (if slot then slot.Default else Color3.new(0.5, 0.5, 0.5))
	local baseMaterial = if slot then slot.DefaultMaterial else SM
	local coat = Livery.Decode(value)
	if coat then
		local pattern = coat.Pattern
		return {
			Color = coat.Color,
			Material = if pattern then pattern.Base else coat.Finish.Material,
			Reflectance = coat.Finish.Reflectance,
			Variant = if pattern then pattern.Variant else nil,
			-- (a pattern without its variant falls back to the finish: Livery.Fallback)
		}
	end
	local paint = Paints.Get(value)
	if paint and paint.Kind == "Paint" and paint.Id ~= "stock" then
		local material = paint.Material or SM
		return { Color = paint.Color, Material = material, Reflectance = if material == Enum.Material.Foil then 0.3 else 0.05 }
	end
	return { Color = default, Material = baseMaterial, Reflectance = if slotKey == "Rims" or slotKey == "Susp" then 0.1 else 0.04 }
end

-- The finish a patterned coat shows when the pattern's variant isn't in the game
function Livery.Fallback(value: string?): Look?
	local coat = Livery.Decode(value)
	if not coat or not coat.Pattern then
		return nil
	end
	return { Color = coat.Color, Material = coat.Finish.Material, Reflectance = coat.Finish.Reflectance }
end

return Livery
