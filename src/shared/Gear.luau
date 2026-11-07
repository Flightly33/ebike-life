--[[
	Gear: rider gear, worn over the avatar while you play (helmets, jackets, gloves, boots). Bought
	in the phone's Gear app, saved in the profile (Profile.Gear: what you own, what you wear), and
	put on by the server (GearService) so everyone sees it. Purely a look: it changes nothing about
	the ride.

	Each piece is built from parts sized to the body part it sits on (Style says which shape); a
	Blender mesh named `Gear_<Style>_<Slot>` (blender/gearkit.py) in ReplicatedStorage.VehicleMeshes replaces the parts once the
	owner has imported it.
]]

local Gear = {}

export type Slot = "Helmet" | "Jacket" | "Gloves" | "Boots"

export type Item = {
	Id: string,
	Slot: Slot,
	Name: string,
	Blurb: string,
	Price: number,
	Level: number,
	Style: string, -- the shape GearService builds (and the Blender mesh it looks for)
	Main: Color3,
	Trim: Color3,
	Glow: boolean?, -- the trim is neon
}

Gear.Slots = { "Helmet", "Jacket", "Gloves", "Boots" } :: { Slot }
Gear.SlotIcons = { Helmet = "🪖", Jacket = "🧥", Gloves = "🧤", Boots = "🥾" } :: { [string]: string }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Gear.List = {
	-- helmets
	{ Id = "h_open", Slot = "Helmet", Name = "Open-Face", Blurb = "A white open-face lid. Free, and better than nothing.", Price = 0, Level = 1, Style = "OpenFace", Main = rgb(240, 240, 242), Trim = rgb(30, 30, 34) },
	{ Id = "h_mx", Slot = "Helmet", Name = "MX Peak", Blurb = "Motocross helmet with a peak and goggles.", Price = 1200, Level = 3, Style = "MX", Main = rgb(255, 120, 20), Trim = rgb(28, 28, 32) },
	{ Id = "h_full", Slot = "Helmet", Name = "Full-Face", Blurb = "A full-face road helmet with a dark visor.", Price = 2500, Level = 6, Style = "FullFace", Main = rgb(30, 110, 230), Trim = rgb(240, 240, 242) },
	{ Id = "h_carbon", Slot = "Helmet", Name = "Race Carbon", Blurb = "Carbon shell, mirrored visor, a spoiler on the back.", Price = 9000, Level = 15, Style = "Race", Main = rgb(24, 24, 26), Trim = rgb(210, 40, 40) },
	{ Id = "h_neon", Slot = "Helmet", Name = "Neon Halo", Blurb = "A race lid with a glowing stripe that lights up the night.", Price = 25000, Level = 25, Style = "Race", Main = rgb(18, 18, 22), Trim = rgb(40, 255, 220), Glow = true },
	-- jackets
	{ Id = "j_ride", Slot = "Jacket", Name = "Riding Jacket", Blurb = "Textile jacket with armour in the shoulders and elbows.", Price = 800, Level = 2, Style = "Jacket", Main = rgb(46, 50, 58), Trim = rgb(255, 120, 20) },
	{ Id = "j_courier", Slot = "Jacket", Name = "Flighty Courier", Blurb = "The courier crew's yellow and black, as worn by Marco's riders.", Price = 1800, Level = 5, Style = "Jacket", Main = rgb(245, 196, 30), Trim = rgb(24, 24, 28) },
	{ Id = "j_leather", Slot = "Jacket", Name = "Leather", Blurb = "Black leather with silver zips.", Price = 4500, Level = 10, Style = "Leather", Main = rgb(22, 20, 20), Trim = rgb(190, 192, 196) },
	{ Id = "j_race", Slot = "Jacket", Name = "Race Suit", Blurb = "One-piece race leathers' top half: a hump, sliders on the elbows.", Price = 12000, Level = 20, Style = "Race", Main = rgb(240, 240, 242), Trim = rgb(220, 30, 40) },
	{ Id = "j_neon", Slot = "Jacket", Name = "Neon Racer", Blurb = "Race suit with glowing seams.", Price = 30000, Level = 30, Style = "Race", Main = rgb(16, 16, 20), Trim = rgb(255, 40, 200), Glow = true },
	-- gloves
	{ Id = "g_mx", Slot = "Gloves", Name = "MX Gloves", Blurb = "Light motocross gloves.", Price = 300, Level = 1, Style = "Gloves", Main = rgb(30, 30, 34), Trim = rgb(255, 120, 20) },
	{ Id = "g_leather", Slot = "Gloves", Name = "Leather Gauntlets", Blurb = "Long cuffs, padded palms.", Price = 1500, Level = 8, Style = "Gauntlets", Main = rgb(26, 22, 20), Trim = rgb(150, 110, 70) },
	{ Id = "g_carbon", Slot = "Gloves", Name = "Carbon Knuckle", Blurb = "Race gloves with carbon knuckle guards.", Price = 6000, Level = 18, Style = "Gauntlets", Main = rgb(240, 240, 242), Trim = rgb(24, 24, 26) },
	-- boots
	{ Id = "b_mx", Slot = "Boots", Name = "MX Boots", Blurb = "Tall motocross boots with buckles.", Price = 600, Level = 2, Style = "MXBoots", Main = rgb(240, 240, 242), Trim = rgb(30, 30, 34) },
	{ Id = "b_street", Slot = "Boots", Name = "Street Boots", Blurb = "Short black riding boots.", Price = 1200, Level = 6, Style = "Boots", Main = rgb(24, 24, 26), Trim = rgb(90, 92, 98) },
	{ Id = "b_race", Slot = "Boots", Name = "Race Boots", Blurb = "Race boots with toe sliders.", Price = 7000, Level = 18, Style = "MXBoots", Main = rgb(220, 30, 40), Trim = rgb(240, 240, 242) },
} :: { Item }

local byId: { [string]: Item } = {}
for _, item in Gear.List do
	byId[item.Id] = item
end

function Gear.Get(id: any): Item?
	return if type(id) == "string" then byId[id] else nil
end

function Gear.ForSlot(slot: string): { Item }
	local out = {}
	for _, item in Gear.List do
		if item.Slot == slot then
			table.insert(out, item)
		end
	end
	return out
end

function Gear.IsSlot(slot: any): boolean
	return type(slot) == "string" and table.find(Gear.Slots, slot :: any) ~= nil
end

return Gear
