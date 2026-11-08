--[[
	Profile: a player's save, its defaults and the clean-up applied to whatever comes out of the
	DataStore (missing fields, removed bikes, out-of-range values). Shared so the client's menus can
	read the same shape the server sends.
]]

local Bikes = require(script.Parent.Bikes)
local Config = require(script.Parent.Config)
local Controls = require(script.Parent.Controls)
local Gear = require(script.Parent.Gear)
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
	TopSpeed: number, -- km/h the server saw
	Deliveries: number,
	Races: number, -- races finished
	Wins: number, -- races won (first of two or more)
	Missions: number, -- story missions done
	Challenges: number, -- daily and weekly challenges claimed
}

-- Daily rewards and challenges (Shared/Dailies): the login streak, and progress on today's and this
-- week's challenges (reset when the day or week changes)
export type Daily = {
	LastLogin: number, -- day number (UTC) of the last streak claim
	Streak: number,
	Day: number, -- the day `Progress` belongs to
	Week: number, -- the week `WeekProgress` belongs to
	Progress: { [string]: number },
	WeekProgress: { [string]: number },
	Claimed: { [string]: boolean }, -- challenge ids claimed this day or week
}

export type Settings = {
	Units: string, -- "kmh" or "mph"
	Music: number, -- 0..1
	Sounds: number, -- 0..1
	Hints: boolean,
	Fov: number, -- body cam field of view, degrees
	Graphics: string, -- "Ultra" or "Performance"; "" until the player picks (asked on join)
	HudScale: number, -- 0.7..1.3, times the screen's own fit
	HudLayout: string, -- "Auto" (compact on touch screens), "Full" or "Compact"
	Keys: { [string]: string }, -- rebound keyboard controls: action id -> KeyCode name (Shared/Controls)
	Stats: boolean, -- the performance readout (UI/PerfStats)
}

-- Rider gear (Shared/Gear): what's owned, and what's worn in each slot ("Helmet" -> item id)
export type GearSave = {
	Owned: { [string]: boolean },
	Worn: { [string]: string },
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
	Missions: { [string]: boolean }, -- story missions done (Shared/Missions)
	BestTimes: { [string]: number }, -- best time trial per course, seconds (Shared/Races)
	Daily: Daily,
	Gear: GearSave,
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
		Stats = { BestWheelie = 0, LongestAir = 0, Distance = 0, Escapes = 0, Busts = 0, Flips = 0, MaxStars = 0, Earned = 0, TopSpeed = 0, Deliveries = 0, Races = 0, Wins = 0, Missions = 0, Challenges = 0 },
		Settings = { Units = "kmh", Music = 0.5, Sounds = 0.8, Hints = true, Fov = 90, Graphics = "", HudScale = 1, HudLayout = "Auto", Keys = {}, Stats = false },
		BoostUntil = 0,
		Achievements = {},
		Missions = {},
		BestTimes = {},
		Daily = { LastLogin = 0, Streak = 0, Day = 0, Week = 0, Progress = {}, WeekProgress = {}, Claimed = {} },
		Gear = { Owned = { h_open = true }, Worn = {} }, -- (everyone has the free open-face helmet)
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
		data.Settings.HudScale = num(s.HudScale, 1, 0.7, 1.3)
		data.Settings.HudLayout = if s.HudLayout == "Full" or s.HudLayout == "Compact" then s.HudLayout else "Auto"
		data.Settings.Stats = s.Stats == true
		if type(s.Keys) == "table" then
			for action, key in s.Keys do
				if type(action) == "string" and Controls.Get(action) and type(key) == "string" and Controls.ValidKey(key) then
					data.Settings.Keys[action] = key
				end
			end
		end
	end
	data.BoostUntil = num(saved.BoostUntil, 0, 0)
	if type(saved.Achievements) == "table" then
		for id, claimed in saved.Achievements do
			if type(id) == "string" and claimed == true then
				data.Achievements[id] = true
			end
		end
	end
	if type(saved.Missions) == "table" then
		for id, done in saved.Missions do
			if type(id) == "string" and done == true then
				data.Missions[id] = true
			end
		end
	end
	if type(saved.BestTimes) == "table" then
		for id, seconds in saved.BestTimes do
			local t = tonumber(seconds)
			if type(id) == "string" and t and t > 1 and t < 36000 then
				data.BestTimes[id] = t
			end
		end
	end
	if type(saved.Daily) == "table" then
		local d, out = saved.Daily, data.Daily
		out.LastLogin = math.floor(num(d.LastLogin, 0, 0))
		out.Streak = math.floor(num(d.Streak, 0, 0, 10000))
		out.Day = math.floor(num(d.Day, 0, 0))
		out.Week = math.floor(num(d.Week, 0, 0))
		for _, pair in { { d.Progress, out.Progress }, { d.WeekProgress, out.WeekProgress } } do
			if type(pair[1]) == "table" then
				for id, value in pair[1] do
					if type(id) == "string" then
						pair[2][id] = num(value, 0, 0)
					end
				end
			end
		end
		if type(d.Claimed) == "table" then
			for id, claimed in d.Claimed do
				if type(id) == "string" and claimed == true then
					out.Claimed[id] = true
				end
			end
		end
	end
	if type(saved.Gear) == "table" then
		local g = saved.Gear
		if type(g.Owned) == "table" then
			for id, owned in g.Owned do
				if owned == true and Gear.Get(id) then
					data.Gear.Owned[id] = true
				end
			end
		end
		if type(g.Worn) == "table" then
			for slot, id in g.Worn do
				local item = Gear.Get(id)
				if Gear.IsSlot(slot) and item and item.Slot == slot and data.Gear.Owned[id] then
					data.Gear.Worn[slot] = id
				end
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
