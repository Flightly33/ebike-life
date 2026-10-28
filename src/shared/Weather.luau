--[[
	Weather: Miami's weather, worked out from the server time so every player sees the same sky
	without anything replicating. Spells of Config.Weather.SpellSeconds each are sunny ("Clear"),
	partly cloudy ("Cloudy") or overcast ("Overcast"), picked by Config.Weather.Odds; each eases
	into the next over its last Config.Weather.BlendSeconds. ReplicatedStorage's "WeatherOverride"
	attribute (set by the admin weather command) holds one kind instead.

	Weather.At gives the blended conditions, which Client/DayNight lays over the hour's look: cloud
	cover and density, haze, how much of the light is direct sun (and how soft the shadows are),
	colour grading and the wind in the grass and palms.
]]

local Config = require(script.Parent.Config)

local Weather = {}

export type Kind = "Clear" | "Cloudy" | "Overcast"

export type Conditions = {
	Cover: number, -- Clouds.Cover
	Density: number, -- Clouds.Density
	Haze: number, -- 0..1, extra atmosphere
	Sun: number, -- share of the direct sunlight that gets through, 0..1
	Softness: number, -- Lighting.ShadowSoftness
	Saturation: number, -- added to the grade
	Contrast: number, -- added to the grade
	Cool: number, -- 0..1, how far the grade shifts to a cool grey
	Wind: number, -- studs/s, GlobalWind
}

Weather.Kinds = {
	Clear = { Cover = 0.32, Density = 0.55, Haze = 0.0, Sun = 1.0, Softness = 0.15, Saturation = 0.03, Contrast = 0.02, Cool = 0.0, Wind = 5 },
	Cloudy = { Cover = 0.62, Density = 0.72, Haze = 0.3, Sun = 0.8, Softness = 0.35, Saturation = -0.02, Contrast = 0.0, Cool = 0.25, Wind = 9 },
	Overcast = { Cover = 0.94, Density = 0.86, Haze = 1.0, Sun = 0.42, Softness = 0.95, Saturation = -0.14, Contrast = -0.03, Cool = 0.85, Wind = 13 },
} :: { [string]: Conditions }

Weather.Order = { "Clear", "Cloudy", "Overcast" }

local function hash(n: number): number
	-- a steady 0..1 number for a spell index
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

-- The kind of spell number `index`
function Weather.KindOf(index: number): Kind
	local odds = Config.Weather.Odds
	local total = 0
	for _, kind in Weather.Order do
		total += odds[kind]
	end
	local r = hash(index) * total
	for _, kind in Weather.Order do
		r -= odds[kind]
		if r <= 0 then
			return kind :: Kind
		end
	end
	return "Clear"
end

local function blend(a: Conditions, b: Conditions, t: number): Conditions
	local out = {}
	for key, value in a do
		out[key] = value + ((b :: any)[key] - value) * t
	end
	return out :: any
end

-- The conditions at server time `t`; `override` (a kind name) holds that kind
function Weather.At(t: number, override: string?): (Conditions, Kind)
	if override and Weather.Kinds[override] then
		local held: Kind = (override :: any) :: Kind
		return table.clone(Weather.Kinds[override]) :: Conditions, held
	end
	local cfg = Config.Weather
	local index = math.floor(t / cfg.SpellSeconds)
	local into = t - index * cfg.SpellSeconds
	local now: Kind = Weather.KindOf(index)
	local start = cfg.SpellSeconds - cfg.BlendSeconds
	if into < start then
		return table.clone(Weather.Kinds[now]) :: Conditions, now
	end
	local nextKind: Kind = Weather.KindOf(index + 1)
	local f = (into - start) / cfg.BlendSeconds
	f = f * f * (3 - 2 * f)
	local kind: Kind = if f < 0.5 then now else nextKind
	return blend(Weather.Kinds[now], Weather.Kinds[nextKind], f), kind
end

return Weather
