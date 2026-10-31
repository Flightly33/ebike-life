--[[
	Profile: a player's save, its defaults and the clean-up applied to whatever comes out of the
	DataStore (missing fields, removed bikes, out-of-range values). Shared so the client's menus can
	read the same shape the server sends.
]]

local Bikes = require(script.Parent.Bikes)
local Config = require(script.Parent.Config)
local Modes = require(script.Parent.Modes)
local Livery = require(script.Parent.Livery)
local Paints = require(script.Parent.Paints)
local Upgrades = require(script.Parent.Upgrades)

local Profile = {}

Profile.VERSION = 1

export type PaintChoice = { Frame: string?, Accent: string?, Rims: string?, Seat: string?, Susp: string?, Glow: string? }

export type Stats = {
	BestWheelie: number,
	LongestAir: number,
	Distance: number, -- metres
	Escapes: number,
	Busts: number,
	Flips: number,
	MaxStars: number,
	Earned: number,
}

export type Settings = {
	Units: string, -- "kmh" or "mph"
	Music: number, -- 0..1
	Sounds: number, -- 0..1
	Hints: boolean,
	Fov: number, -- body cam field of view, degrees
	Graphics: string, -- "Ultra" or "Performance"; "" until the player picks (asked on join)
}

export type Data = {
	Version: number,
	Cash: number,
	Level: number,
	Xp: number,
	Owned: { [string]: boolean },
	Equipped: string,
	Upgrades: { [string]: Upgrades.Levels },
	Paint: { [string]: PaintChoice },
	Paints: { [string]: boolean }, -- unlocked crate paints
	Modes: Modes.ModeSet,
	Mode: string,
	Stats: Stats,
	Settings: Settings,
	BoostUntil: number, -- os.time() a 2x cash boost runs until
	Achievements: { [string]: boolean }, -- claimed achievement rewards (Shared/Achievements)
}

function Profile.Default(): Data
	return {
		Version = Profile.VERSION,
		Cash = Config.Economy.StartCash,
		Level = 1,
		Xp = 0,
		Owned = { [Config.Economy.StarterBike] = true },
		Equipped = Config.Economy.StarterBike,
		Upgrades = {},
		Paint = {},
		Paints = {},
		Modes = Modes.Sanitize(nil),
		Mode = "TOUR",
		Stats = { BestWheelie = 0, LongestAir = 0, Distance = 0, Escapes = 0, Busts = 0, Flips = 0, MaxStars = 0, Earned = 0 },
		Settings = { Units = "kmh", Music = 0.5, Sounds = 0.8, Hints = true, Fov = 90, Graphics = "" },
		BoostUntil = 0,
		Achievements = {},
	}
end

local function num(value: any, default: number, min: number?, max: number?): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	if min then
		n = math.max(n, min)
	end
	if max then
		n = math.min(n, max)
	end
	return n
end

function Profile.Sanitize(saved: any): Data
	local data = Profile.Default()
	if type(saved) ~= "table" then
		return data
	end
	data.Cash = math.floor(num(saved.Cash, data.Cash, 0, 1e12))
	data.Level = math.floor(num(saved.Level, 1, 1, 10000))
	data.Xp = num(saved.Xp, 0, 0)
	if type(saved.Owned) == "table" then
		for id, owned in saved.Owned do
			if owned == true and Bikes.Get(id) then
				data.Owned[id] = true
			end
		end
	end
	if type(saved.Equipped) == "string" and data.Owned[saved.Equipped] then
		data.Equipped = saved.Equipped
	end
	if type(saved.Upgrades) == "table" then
		for id, levels in saved.Upgrades do
			if Bikes.Get(id) then
				data.Upgrades[id] = Upgrades.Sanitize(levels)
			end
		end
	end
	if type(saved.Paints) == "table" then
		for id, owned in saved.Paints do
			if owned == true and Paints.Get(id) then
				data.Paints[id] = true
			end
		end
	end
	if type(saved.Paint) == "table" then
		for id, choice in saved.Paint do
			if Bikes.Get(id) and type(choice) == "table" then
				local clean: PaintChoice = {}
				for _, slot in Paints.Slots do
					local paintId = choice[slot]
					-- a crate paint the player has, or a custom coat (Shared/Livery)
					if type(paintId) == "string" and Livery.Valid(slot, paintId) and (Livery.Decode(paintId) ~= nil or Profile.HasPaint(data, paintId)) then
						(clean :: any)[slot] = paintId
					end
				end
				data.Paint[id] = clean
			end
		end
	end
	data.Modes = Modes.Sanitize(saved.Modes)
	if Modes.IsMode(saved.Mode) then
		data.Mode = saved.Mode
	end
	if type(saved.Stats) == "table" then
		for key, value in data.Stats do
			(data.Stats :: any)[key] = num(saved.Stats[key], value :: number, 0)
		end
	end
	if type(saved.Settings) == "table" then
		local s = saved.Settings
		data.Settings.Units = if s.Units == "mph" then "mph" else "kmh"
		data.Settings.Music = num(s.Music, 0.5, 0, 1)
		data.Settings.Sounds = num(s.Sounds, 0.8, 0, 1)
		data.Settings.Hints = s.Hints ~= false
		data.Settings.Fov = num(s.Fov, 90, 60, 120)
		data.Settings.Graphics = if s.Graphics == "Ultra" or s.Graphics == "Performance" then s.Graphics else ""
	end
	data.BoostUntil = num(saved.BoostUntil, 0, 0)
	if type(saved.Achievements) == "table" then
		for id, claimed in saved.Achievements do
			if type(id) == "string" and claimed == true then
				data.Achievements[id] = true
			end
		end
	end
	return data
end

function Profile.HasPaint(data: Data, paintId: string): boolean
	local paint = Paints.Get(paintId)
	if not paint then
		return false
	end
	return paint.Free == true or data.Paints[paintId] == true
end

function Profile.Levels(data: Data, bikeId: string): Upgrades.Levels
	return data.Upgrades[bikeId] or {}
end

return Profile
