--[[
	Paints: colours for a bike's frame, accents and rims, plus underglow light kits.

	The basic colours are free; the rest come out of crates. A player owns a paint for every bike once
	they have it. Crates roll a rarity first (by weight), then a paint of that rarity.
]]

local Paints = {}

export type Kind = "Paint" | "Glow"
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"

export type Paint = {
	Id: string,
	Name: string,
	Kind: Kind,
	Color: Color3,
	Rarity: Rarity,
	Material: Enum.Material?, -- metallic and neon finishes
	Free: boolean?,
}

Paints.RarityColors = {
	Common = Color3.fromRGB(205, 205, 205),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(175, 90, 255),
	Legendary = Color3.fromRGB(255, 190, 45),
} :: { [Rarity]: Color3 }

local list: { Paint } = {
	-- Free basics
	{ Id = "stock", Name = "Factory", Kind = "Paint", Color = Color3.fromRGB(128, 128, 128), Rarity = "Common", Free = true },
	{ Id = "black", Name = "Matte Black", Kind = "Paint", Color = Color3.fromRGB(28, 28, 30), Rarity = "Common", Free = true },
	{ Id = "white", Name = "Gloss White", Kind = "Paint", Color = Color3.fromRGB(238, 238, 236), Rarity = "Common", Free = true },
	{ Id = "red", Name = "Race Red", Kind = "Paint", Color = Color3.fromRGB(205, 30, 38), Rarity = "Common", Free = true },
	{ Id = "blue", Name = "Cobalt", Kind = "Paint", Color = Color3.fromRGB(30, 80, 200), Rarity = "Common", Free = true },
	{ Id = "green", Name = "Forest", Kind = "Paint", Color = Color3.fromRGB(35, 110, 60), Rarity = "Common", Free = true },
	{ Id = "orange", Name = "Safety Orange", Kind = "Paint", Color = Color3.fromRGB(255, 110, 20), Rarity = "Common", Free = true },
	-- Crate commons
	{ Id = "sand", Name = "Desert Sand", Kind = "Paint", Color = Color3.fromRGB(205, 180, 135), Rarity = "Common" },
	{ Id = "olive", Name = "Olive Drab", Kind = "Paint", Color = Color3.fromRGB(95, 100, 55), Rarity = "Common" },
	{ Id = "sky", Name = "Sky Blue", Kind = "Paint", Color = Color3.fromRGB(110, 185, 240), Rarity = "Common" },
	{ Id = "pink", Name = "Bubblegum", Kind = "Paint", Color = Color3.fromRGB(255, 140, 190), Rarity = "Common" },
	{ Id = "yellow", Name = "Taxi Yellow", Kind = "Paint", Color = Color3.fromRGB(250, 205, 30), Rarity = "Common" },
	-- Rare
	{ Id = "teal", Name = "Deep Teal", Kind = "Paint", Color = Color3.fromRGB(0, 130, 130), Rarity = "Rare" },
	{ Id = "purple", Name = "Royal Purple", Kind = "Paint", Color = Color3.fromRGB(100, 40, 170), Rarity = "Rare" },
	{ Id = "copper", Name = "Copper", Kind = "Paint", Color = Color3.fromRGB(184, 110, 60), Rarity = "Rare", Material = Enum.Material.Metal },
	{ Id = "gunmetal", Name = "Gunmetal", Kind = "Paint", Color = Color3.fromRGB(70, 74, 80), Rarity = "Rare", Material = Enum.Material.Metal },
	{ Id = "glow_white", Name = "Underglow: Ice", Kind = "Glow", Color = Color3.fromRGB(200, 230, 255), Rarity = "Rare" },
	{ Id = "glow_blue", Name = "Underglow: Blue", Kind = "Glow", Color = Color3.fromRGB(40, 120, 255), Rarity = "Rare" },
	-- Epic
	{ Id = "chrome", Name = "Chrome", Kind = "Paint", Color = Color3.fromRGB(205, 210, 215), Rarity = "Epic", Material = Enum.Material.Foil },
	{ Id = "midnight", Name = "Midnight Metallic", Kind = "Paint", Color = Color3.fromRGB(25, 30, 70), Rarity = "Epic", Material = Enum.Material.Metal },
	{ Id = "lime", Name = "Acid Lime", Kind = "Paint", Color = Color3.fromRGB(170, 255, 40), Rarity = "Epic" },
	{ Id = "glow_purple", Name = "Underglow: Violet", Kind = "Glow", Color = Color3.fromRGB(170, 60, 255), Rarity = "Epic" },
	{ Id = "glow_green", Name = "Underglow: Toxic", Kind = "Glow", Color = Color3.fromRGB(60, 255, 90), Rarity = "Epic" },
	-- Legendary
	{ Id = "gold", Name = "24k Gold", Kind = "Paint", Color = Color3.fromRGB(230, 180, 50), Rarity = "Legendary", Material = Enum.Material.Foil },
	{ Id = "neon_pink", Name = "Neon Pink", Kind = "Paint", Color = Color3.fromRGB(255, 40, 160), Rarity = "Legendary", Material = Enum.Material.Neon },
	{ Id = "neon_cyan", Name = "Neon Cyan", Kind = "Paint", Color = Color3.fromRGB(0, 230, 255), Rarity = "Legendary", Material = Enum.Material.Neon },
	{ Id = "glow_red", Name = "Underglow: Siren", Kind = "Glow", Color = Color3.fromRGB(255, 40, 60), Rarity = "Legendary" },
}

Paints.List = list
Paints.ById = {} :: { [string]: Paint }
for _, paint in list do
	Paints.ById[paint.Id] = paint
end

-- (Shared/Livery: what each slot is, custom coats)
Paints.Slots = { "Frame", "Accent", "Rims", "Seat", "Susp", "Glow" }

function Paints.Get(id: string?): Paint?
	if id == nil then
		return nil
	end
	return Paints.ById[id]
end

export type Crate = {
	Id: string,
	Name: string,
	Price: number,
	Color: Color3,
	Weights: { [string]: number },
}

Paints.Crates = {
	{
		Id = "street",
		Name = "Street Crate",
		Price = 750,
		Color = Color3.fromRGB(150, 150, 150),
		Weights = { Common = 70, Rare = 24, Epic = 5, Legendary = 1 },
	},
	{
		Id = "pro",
		Name = "Pro Crate",
		Price = 3000,
		Color = Color3.fromRGB(70, 150, 255),
		Weights = { Common = 30, Rare = 45, Epic = 20, Legendary = 5 },
	},
	{
		Id = "legend",
		Name = "Legend Crate",
		Price = 12000,
		Color = Color3.fromRGB(255, 190, 45),
		Weights = { Common = 0, Rare = 35, Epic = 45, Legendary = 20 },
	},
} :: { Crate }

function Paints.GetCrate(id: string): Crate?
	for _, crate in Paints.Crates do
		if crate.Id == id then
			return crate
		end
	end
	return nil
end

-- Crate roll: `r1`, `r2` are uniform numbers in [0, 1) (passed in so tests can fix them)
function Paints.Roll(crate: Crate, r1: number, r2: number): Paint
	local total = 0
	for _, weight in crate.Weights do
		total += weight
	end
	local pick = r1 * total
	local rarity: string = "Common"
	for _, name in { "Common", "Rare", "Epic", "Legendary" } do
		local weight = crate.Weights[name] or 0
		if pick < weight then
			rarity = name
			break
		end
		pick -= weight
		rarity = name
	end
	local pool = {}
	for _, paint in list do
		if paint.Rarity == rarity and not paint.Free then
			table.insert(pool, paint)
		end
	end
	return pool[math.clamp(math.floor(r2 * #pool) + 1, 1, #pool)]
end

return Paints
