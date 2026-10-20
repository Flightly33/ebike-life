--[[
	Modes: assist modes, as on a real e-bike display.

	Assist is the support factor on a pedal-assist bike (150% = the motor adds one and a half times
	what your legs put in); MaxPower caps the motor at a share of its peak; Response is how hard the
	motor ramps in (soft / normal / punchy). Throttle bikes and e-motos ignore Assist and use MaxPower
	as the throttle ceiling. Players can tune each mode in the Tuning menu, like a manufacturer app.
]]

local Modes = {}

export type ModeName = "OFF" | "ECO" | "TOUR" | "SPORT" | "TURBO"
export type Mode = { Assist: number, MaxPower: number, Response: number }
export type ModeSet = { [string]: Mode }

local ORDER: { ModeName } = { "OFF", "ECO", "TOUR", "SPORT", "TURBO" }
Modes.Order = ORDER

Modes.Defaults = {
	OFF = { Assist = 0, MaxPower = 0, Response = 0.5 },
	ECO = { Assist = 0.6, MaxPower = 0.4, Response = 0.25 },
	TOUR = { Assist = 1.4, MaxPower = 0.65, Response = 0.5 },
	SPORT = { Assist = 2.2, MaxPower = 0.85, Response = 0.75 },
	TURBO = { Assist = 3.4, MaxPower = 1.0, Response = 1.0 },
} :: ModeSet

Modes.Colors = {
	OFF = Color3.fromRGB(120, 120, 120),
	ECO = Color3.fromRGB(46, 196, 90),
	TOUR = Color3.fromRGB(40, 150, 255),
	SPORT = Color3.fromRGB(255, 140, 20),
	TURBO = Color3.fromRGB(230, 40, 60),
} :: { [string]: Color3 }

-- What players may set in the Tuning menu
Modes.Limits = {
	Assist = { Min = 0.2, Max = 4.0, Step = 0.2 },
	MaxPower = { Min = 0.1, Max = 1.0, Step = 0.05 },
	Response = { Min = 0, Max = 1, Step = 0.25 },
}

Modes.ResponseNames = { [0] = "Gentle", [0.25] = "Soft", [0.5] = "Normal", [0.75] = "Lively", [1] = "Punchy" }

function Modes.IsMode(name: any): boolean
	return type(name) == "string" and Modes.Defaults[name] ~= nil
end

local function snap(value: number, limit: { Min: number, Max: number, Step: number }): number
	local v = math.clamp(value, limit.Min, limit.Max)
	v = limit.Min + math.floor((v - limit.Min) / limit.Step + 0.5) * limit.Step
	return math.clamp(math.floor(v * 1000 + 0.5) / 1000, limit.Min, limit.Max)
end

-- A player's mode table from saved data, with anything missing or out of range fixed up. OFF is
-- never customisable.
function Modes.Sanitize(saved: any): ModeSet
	local out: ModeSet = {}
	for _, name in Modes.Order do
		local default = Modes.Defaults[name]
		local src = if type(saved) == "table" then saved[name] else nil
		if name == "OFF" or type(src) ~= "table" then
			out[name] = table.clone(default)
		else
			out[name] = {
				Assist = snap(tonumber(src.Assist) or default.Assist, Modes.Limits.Assist),
				MaxPower = snap(tonumber(src.MaxPower) or default.MaxPower, Modes.Limits.MaxPower),
				Response = snap(tonumber(src.Response) or default.Response, Modes.Limits.Response),
			}
		end
	end
	return out
end

function Modes.Next(name: string, direction: number): ModeName
	local index = 2
	for i, mode in Modes.Order do
		if mode == name then
			index = i
		end
	end
	index = math.clamp(index + direction, 1, #Modes.Order)
	return Modes.Order[index]
end

function Modes.ResponseName(response: number): string
	local best, bestDiff = "Normal", math.huge
	for value, label in Modes.ResponseNames do
		local diff = math.abs(value - response)
		if diff < bestDiff then
			best, bestDiff = label, diff
		end
	end
	return best
end

return Modes
