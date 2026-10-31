--[[
	Setup: the free adjustments a mechanic makes to a bike at Flighty Garage (on top of the parts in
	Shared/Upgrades): gearing, power map, regen, spring rate, damping, tyre pressure, steering and
	weight bias. Each is a whole-number step between Min and Max (Default when unset), saved in the
	bike's upgrade levels as "S_<Key>" so it travels everywhere the levels do; BikeStats.Compute
	turns them into the spec the physics runs on (Setup.Apply).
]]

local Setup = {}

export type Setting = {
	Key: string,
	Title: string,
	Description: string,
	Min: number,
	Max: number,
	Default: number,
	Left: string, -- what turning it down does
	Right: string, -- what turning it up does
	Label: (number) -> string,
}

local function signed(unit: string): (number) -> string
	return function(v: number): string
		if v == 0 then
			return "Stock"
		end
		return string.format("%+d %s", v, unit)
	end
end

Setup.List = {
	{
		Key = "Gearing",
		Title = "Final drive",
		Description = "Rear sprocket teeth. Fewer teeth: a higher top speed. More teeth: harder acceleration and wheelies.",
		Min = -3,
		Max = 3,
		Default = 0,
		Left = "Acceleration",
		Right = "Top speed",
		Label = function(v: number): string
			return string.format("%dT rear", 48 - v * 2)
		end,
	},
	{
		Key = "PowerMap",
		Title = "Power map",
		Description = "The controller's throttle map. Smooth saves battery; Race hits harder and drains it faster.",
		Min = -2,
		Max = 2,
		Default = 0,
		Left = "Range",
		Right = "Punch",
		Label = function(v: number): string
			return ({ [-2] = "Eco", [-1] = "Smooth", [0] = "Standard", [1] = "Sport", [2] = "Race" })[v] or "Standard"
		end,
	},
	{
		Key = "Regen",
		Title = "Regen braking",
		Description = "How much braking charges the battery (and how much the bike slows when you let off).",
		Min = 0,
		Max = 3,
		Default = 1,
		Left = "Coast",
		Right = "Recharge",
		Label = function(v: number): string
			return ({ [0] = "Off", [1] = "Low", [2] = "Medium", [3] = "High" })[v] or "Low"
		end,
	},
	{
		Key = "Spring",
		Title = "Spring rate",
		Description = "Soft springs soak up bumps and grass; firm ones hold up on big landings and in the loops.",
		Min = -2,
		Max = 2,
		Default = 0,
		Left = "Soft",
		Right = "Firm",
		Label = signed("clicks"),
	},
	{
		Key = "Damping",
		Title = "Damping",
		Description = "Compression and rebound damping. More settles the bike faster after a hit; less lets it bounce.",
		Min = -2,
		Max = 2,
		Default = 0,
		Left = "Lively",
		Right = "Controlled",
		Label = signed("clicks"),
	},
	{
		Key = "Pressure",
		Title = "Tyre pressure",
		Description = "Low pressure grips on grass, dirt and sand; high pressure rolls faster on tarmac.",
		Min = -2,
		Max = 2,
		Default = 0,
		Left = "Off-road grip",
		Right = "Road speed",
		Label = function(v: number): string
			return string.format("%.1f bar", 1.6 + v * 0.2)
		end,
	},
	{
		Key = "Steering",
		Title = "Steering",
		Description = "Steering damper and bar height. Quick turns in faster and spins faster in the air.",
		Min = -2,
		Max = 2,
		Default = 0,
		Left = "Stable",
		Right = "Quick",
		Label = signed("steps"),
	},
	{
		Key = "Balance",
		Title = "Weight bias",
		Description = "Where the weight sits. Rearward pops wheelies easily; forward keeps the front planted.",
		Min = -2,
		Max = 2,
		Default = 0,
		Left = "Planted",
		Right = "Pops up",
		Label = signed("steps"),
	},
} :: { Setting }

Setup.ByKey = {} :: { [string]: Setting }
for _, s in Setup.List do
	Setup.ByKey[s.Key] = s
end

-- The setting's value in a bike's levels (clamped; the default when unset)
function Setup.Get(levels: { [string]: number }?, key: string): number
	local s = Setup.ByKey[key]
	if not s then
		return 0
	end
	local v = if levels then levels["S_" .. key] else nil
	if type(v) ~= "number" or v ~= v then
		return s.Default
	end
	return math.clamp(math.floor(v + 0.5), s.Min, s.Max)
end

-- Copies the valid settings from `saved` into `out` (non-default ones only)
function Setup.Sanitize(saved: any, out: { [string]: number })
	if type(saved) ~= "table" then
		return
	end
	for _, s in Setup.List do
		local v = Setup.Get(saved, s.Key)
		if v ~= s.Default then
			out["S_" .. s.Key] = v
		end
	end
end

-- The spec with the settings applied (BikeStats.Compute calls this last)
function Setup.Apply(spec: any, levels: { [string]: number }?, unlocked: boolean)
	local gear = Setup.Get(levels, "Gearing")
	local map = Setup.Get(levels, "PowerMap")
	local regen = Setup.Get(levels, "Regen")
	local spring = Setup.Get(levels, "Spring")
	local damping = Setup.Get(levels, "Damping")
	local pressure = Setup.Get(levels, "Pressure")
	local steering = Setup.Get(levels, "Steering")
	local balance = Setup.Get(levels, "Balance")
	-- gearing: torque at the wheel against the speed the motor tops out at (the legal limit stays)
	spec.WheelForceN *= 1 - 0.035 * gear
	if unlocked then
		spec.CutoffKmh *= 1 + 0.03 * gear
	end
	spec.WheeliePop *= 1 - 0.05 * gear
	-- power map
	spec.WheelForceN *= 1 + 0.04 * map
	spec.MotorW *= 1 + 0.03 * map
	spec.BatteryWh *= 1 - 0.05 * map
	-- regen: 0 off, 1 the bike's own, 2 and 3 more
	spec.Regen *= ({ [0] = 0, [1] = 1, [2] = 1.5, [3] = 2 })[regen] or 1
	-- suspension (Shared/Suspension scales its springs and dampers by these)
	spec.SpringScale = 1 + 0.12 * spring
	spec.DampScale = 1 + 0.15 * damping
	spec.Landing += 0.015 * spring + 0.01 * damping
	-- tyre pressure: low grips off-road and rolls there better; high rolls faster on tarmac
	spec.CrrRoad *= 1 - 0.05 * pressure
	spec.GripRoad *= 1 - 0.012 * pressure
	spec.GripOff *= 1 - 0.06 * pressure
	spec.CrrOff *= 1 + 0.05 * pressure
	-- steering and weight bias
	spec.SteerScale = 1 + 0.12 * steering
	spec.AirControl *= 1 + 0.05 * steering
	spec.WheeliePop *= 1 + 0.12 * balance
end

return Setup
