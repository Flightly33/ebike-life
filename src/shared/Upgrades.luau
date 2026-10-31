--[[
	Upgrades: the Tuning menu's performance parts, bought per bike.

	Each slot has levels (0 = stock). What a level does to the bike is applied in BikeStats; prices
	scale with the bike's own price so upgrading a flagship costs flagship money.
]]

local Bikes = require(script.Parent.Bikes)
local Setup = require(script.Parent.Setup)

local Upgrades = {}

export type SlotName = "Battery" | "Controller" | "Tires" | "Suspension" | "Brakes" | "Limiter"
export type Levels = { [string]: number }

export type Slot = {
	Name: SlotName,
	Title: string,
	Description: string,
	Levels: { string }, -- names, index 1 = level 0 (stock)
	CostFactor: number,
}

Upgrades.Slots = {
	{
		Name = "Battery",
		Title = "Battery",
		Description = "More cells in the pack: more range before the motor cuts out.",
		Levels = { "Stock pack", "Extended pack (+25%)", "High-density cells (+50%)", "Dual pack (+100%)" },
		CostFactor = 1.0,
	},
	{
		Name = "Controller",
		Title = "Motor controller",
		Description = "Higher-current controller: more peak power and torque, faster battery drain.",
		Levels = { "Stock controller", "Stage 1 (+12% power)", "Stage 2 (+25% power)", "Stage 3 (+40% power)" },
		CostFactor = 1.3,
	},
	{
		Name = "Tires",
		Title = "Tyres",
		Description = "Slicks roll fast on tarmac; knobblies grip on grass and dirt.",
		Levels = { "Stock tyres", "Street slicks", "Trail knobblies" },
		CostFactor = 0.5,
	},
	{
		Name = "Suspension",
		Title = "Suspension",
		Description = "Tuned damping soaks up sketchier landings and gives more control in the air.",
		Levels = { "Stock", "Tuned damping", "Pro coil setup" },
		CostFactor = 0.9,
	},
	{
		Name = "Brakes",
		Title = "Brakes",
		Description = "Bigger rotors and 4-piston calipers stop you harder.",
		Levels = { "Stock brakes", "4-piston, 203 mm rotors" },
		CostFactor = 0.6,
	},
	{
		Name = "Limiter",
		Title = "Speed limiter",
		Description = "Off-road mode lifts the legal assist limit to what the motor can do. Cops notice speeding.",
		Levels = { "Street legal", "Off-road mode (unlocked)" },
		CostFactor = 1.5,
	},
} :: { Slot }

Upgrades.BySlot = {} :: { [string]: Slot }
for _, slot in Upgrades.Slots do
	Upgrades.BySlot[slot.Name] = slot
end

Upgrades.BatteryScale = { [0] = 1, 1.25, 1.5, 2.0 }
Upgrades.PowerScale = { [0] = 1, 1.12, 1.25, 1.4 }
Upgrades.TorqueScale = { [0] = 1, 1.08, 1.16, 1.25 }
Upgrades.TireKinds = { [0] = "Stock", "Road", "Knobby" }
Upgrades.LandingBonus = { [0] = 0, 0.08, 0.16 }
Upgrades.AirControlScale = { [0] = 1, 1.15, 1.3 }
Upgrades.BrakeScale = { [0] = 1, 1.15 }

function Upgrades.MaxLevel(slotName: string): number
	local slot = Upgrades.BySlot[slotName]
	return if slot then #slot.Levels - 1 else 0
end

function Upgrades.Level(levels: Levels?, slotName: string): number
	local value = if levels then levels[slotName] else nil
	if type(value) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(value), 0, Upgrades.MaxLevel(slotName))
end

-- Highest level bought in a slot (any level up to it can be selected for free). Stored as
-- "<Slot>Max" next to the selected level.
function Upgrades.Owned(levels: Levels?, slotName: string): number
	local bought = if levels then levels[slotName .. "Max"] else nil
	local owned = if type(bought) == "number" then math.floor(bought) else 0
	return math.clamp(math.max(owned, Upgrades.Level(levels, slotName)), 0, Upgrades.MaxLevel(slotName))
end

-- Price of buying `level` in `slotName` for `bikeId` (each level is bought in turn)
function Upgrades.Cost(bikeId: string, slotName: string, level: number): number
	local bike = Bikes.Get(bikeId)
	local slot = Upgrades.BySlot[slotName]
	if not bike or not slot or level <= 0 then
		return 0
	end
	local base = 300 + bike.Price * 0.06
	local raw = base * slot.CostFactor * level ^ 1.3
	return math.max(25, math.floor(raw / 25 + 0.5) * 25)
end

function Upgrades.Sanitize(saved: any): Levels
	local out: Levels = {}
	if type(saved) ~= "table" then
		return out
	end
	for _, slot in Upgrades.Slots do
		local level = Upgrades.Level(saved, slot.Name)
		local owned = Upgrades.Owned(saved, slot.Name)
		if level > 0 then
			out[slot.Name] = level
		end
		if owned > 0 then
			out[slot.Name .. "Max"] = owned
		end
	end
	-- the mechanic's setup rides along in the same table (Shared/Setup)
	Setup.Sanitize(saved, out)
	return out
end

return Upgrades
