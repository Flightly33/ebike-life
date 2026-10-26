--[[
	DayNight: the game clock and how the world looks at each hour. Pure (no services), shared by the
	server (the admin time command) and every client (Client/DayNight applies the look locally).

	The clock runs from the server time, so every player sees the same hour without anything
	replicating. A day is `Config.DayNight.DaySeconds` of real time; daylight (06:00-20:00) takes
	`DayShare` of it and the night goes quicker. `ReplicatedStorage`'s "ClockOffset" attribute (a
	fraction of a day) shifts it (the admin time command sets it).

	Looks are keyframes by hour, blended between: stylised and clean (bright saturated days, warm
	golden mornings and evenings, pink-orange sunsets, blue dusks, deep blue nights with glowing lamps
	and windows). `Night` (0 day .. 1 night) is how lit the city's lights are.
]]

local Config = require(script.Parent.Config)

local DayNight = {}

local DAY_START, DAY_END = 6, 20

-- The hour (0..24) at a server time `t` (seconds), shifted by `offset` (fraction of a real day)
function DayNight.Hour(t: number, offset: number?): number
	local cfg = Config.DayNight
	local f = (t / cfg.DaySeconds + (offset or 0) + cfg.StartFraction) % 1
	local share = cfg.DayShare
	if f < share then
		return DAY_START + (DAY_END - DAY_START) * (f / share)
	end
	local night = (f - share) / (1 - share)
	return (DAY_END + (24 - DAY_END + DAY_START) * night) % 24
end

-- The real-day fraction at which the clock reads `hour` (the inverse of Hour, without the offset)
function DayNight.FractionAt(hour: number): number
	local share = Config.DayNight.DayShare
	if hour >= DAY_START and hour < DAY_END then
		return (hour - DAY_START) / (DAY_END - DAY_START) * share
	end
	local since = (hour - DAY_END) % 24
	return share + since / (24 - DAY_END + DAY_START) * (1 - share)
end

export type Look = {
	Brightness: number,
	Exposure: number,
	Ambient: Color3,
	Outdoor: Color3,
	ShiftTop: Color3,
	ShiftBottom: Color3,
	AtmoDensity: number,
	AtmoColor: Color3,
	AtmoDecay: Color3,
	AtmoHaze: number,
	AtmoGlare: number,
	Tint: Color3,
	GradeBrightness: number,
	Contrast: number,
	Saturation: number,
	Bloom: number,
	BloomThreshold: number,
	SunRays: number,
	Night: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local KEYS: { { Hour: number, Look: Look } } = {
	{ Hour = 0, Look = {
		Brightness = 0.8, Exposure = -0.15, Ambient = rgb(52, 58, 92), Outdoor = rgb(64, 74, 118),
		ShiftTop = rgb(150, 170, 255), ShiftBottom = rgb(40, 50, 90),
		AtmoDensity = 0.34, AtmoColor = rgb(52, 64, 110), AtmoDecay = rgb(30, 38, 80), AtmoHaze = 1.6, AtmoGlare = 0,
		Tint = rgb(220, 228, 255), GradeBrightness = 0.0, Contrast = 0.14, Saturation = 0.08,
		Bloom = 1.1, BloomThreshold = 0.85, SunRays = 0, Night = 1,
	} },
	{ Hour = 5.2, Look = {
		Brightness = 1.0, Exposure = -0.1, Ambient = rgb(70, 70, 110), Outdoor = rgb(90, 88, 140),
		ShiftTop = rgb(190, 160, 230), ShiftBottom = rgb(60, 60, 110),
		AtmoDensity = 0.36, AtmoColor = rgb(110, 100, 160), AtmoDecay = rgb(80, 70, 130), AtmoHaze = 1.8, AtmoGlare = 0.1,
		Tint = rgb(232, 225, 255), GradeBrightness = 0.0, Contrast = 0.12, Saturation = 0.08,
		Bloom = 1.0, BloomThreshold = 0.95, SunRays = 0.02, Night = 0.9,
	} },
	{ Hour = 6.6, Look = {
		Brightness = 2.2, Exposure = 0.05, Ambient = rgb(120, 96, 92), Outdoor = rgb(170, 130, 118),
		ShiftTop = rgb(255, 180, 120), ShiftBottom = rgb(120, 100, 130),
		AtmoDensity = 0.36, AtmoColor = rgb(250, 190, 150), AtmoDecay = rgb(230, 130, 100), AtmoHaze = 1.9, AtmoGlare = 0.7,
		Tint = rgb(255, 238, 220), GradeBrightness = 0.02, Contrast = 0.1, Saturation = 0.16,
		Bloom = 0.9, BloomThreshold = 1.15, SunRays = 0.12, Night = 0.3,
	} },
	{ Hour = 9, Look = {
		Brightness = 3, Exposure = 0.1, Ambient = rgb(94, 96, 106), Outdoor = rgb(140, 144, 156),
		ShiftTop = rgb(255, 246, 228), ShiftBottom = rgb(140, 156, 180),
		AtmoDensity = 0.3, AtmoColor = rgb(200, 216, 236), AtmoDecay = rgb(140, 168, 206), AtmoHaze = 1.1, AtmoGlare = 0.2,
		Tint = rgb(255, 252, 247), GradeBrightness = 0.02, Contrast = 0.08, Saturation = 0.14,
		Bloom = 0.6, BloomThreshold = 1.4, SunRays = 0.05, Night = 0,
	} },
	{ Hour = 13, Look = {
		Brightness = 3.2, Exposure = 0.1, Ambient = rgb(92, 92, 102), Outdoor = rgb(140, 143, 153),
		ShiftTop = rgb(255, 248, 232), ShiftBottom = rgb(140, 153, 178),
		AtmoDensity = 0.28, AtmoColor = rgb(199, 214, 235), AtmoDecay = rgb(140, 166, 204), AtmoHaze = 1.0, AtmoGlare = 0.15,
		Tint = rgb(255, 253, 248), GradeBrightness = 0.02, Contrast = 0.08, Saturation = 0.14,
		Bloom = 0.55, BloomThreshold = 1.45, SunRays = 0.04, Night = 0,
	} },
	{ Hour = 17, Look = {
		Brightness = 2.8, Exposure = 0.1, Ambient = rgb(104, 94, 92), Outdoor = rgb(156, 140, 132),
		ShiftTop = rgb(255, 222, 180), ShiftBottom = rgb(140, 140, 165),
		AtmoDensity = 0.3, AtmoColor = rgb(232, 210, 190), AtmoDecay = rgb(210, 160, 130), AtmoHaze = 1.3, AtmoGlare = 0.35,
		Tint = rgb(255, 244, 228), GradeBrightness = 0.02, Contrast = 0.09, Saturation = 0.18,
		Bloom = 0.65, BloomThreshold = 1.3, SunRays = 0.08, Night = 0,
	} },
	{ Hour = 19.1, Look = {
		Brightness = 1.9, Exposure = 0.05, Ambient = rgb(118, 84, 96), Outdoor = rgb(170, 112, 112),
		ShiftTop = rgb(255, 150, 100), ShiftBottom = rgb(120, 90, 140),
		AtmoDensity = 0.36, AtmoColor = rgb(250, 160, 140), AtmoDecay = rgb(220, 90, 90), AtmoHaze = 2.0, AtmoGlare = 0.9,
		Tint = rgb(255, 228, 214), GradeBrightness = 0.02, Contrast = 0.12, Saturation = 0.22,
		Bloom = 0.9, BloomThreshold = 1.1, SunRays = 0.14, Night = 0.4,
	} },
	{ Hour = 20.4, Look = {
		Brightness = 1.1, Exposure = -0.05, Ambient = rgb(70, 66, 110), Outdoor = rgb(90, 84, 140),
		ShiftTop = rgb(170, 150, 240), ShiftBottom = rgb(60, 56, 110),
		AtmoDensity = 0.35, AtmoColor = rgb(90, 86, 150), AtmoDecay = rgb(60, 50, 120), AtmoHaze = 1.7, AtmoGlare = 0.1,
		Tint = rgb(226, 222, 255), GradeBrightness = 0.0, Contrast = 0.13, Saturation = 0.1,
		Bloom = 1.05, BloomThreshold = 0.9, SunRays = 0.02, Night = 0.95,
	} },
}

local function mix(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return a + (b - a) * t
end

-- The look at an hour, blended between the keyframes (smoothly, so changes ease in and out)
function DayNight.LookAt(hour: number): Look
	hour %= 24
	local count = #KEYS
	local from, to = KEYS[count], KEYS[1]
	for i = 1, count do
		local nextKey = KEYS[i % count + 1]
		local nextHour = if i == count then nextKey.Hour + 24 else nextKey.Hour
		if hour >= KEYS[i].Hour and hour < nextHour then
			from, to = KEYS[i], nextKey
			break
		end
	end
	local span = (to.Hour - from.Hour) % 24
	local t = if span > 0 then ((hour - from.Hour) % 24) / span else 0
	t = t * t * (3 - 2 * t)
	local out = {}
	for key, value in from.Look do
		out[key] = mix(value, (to.Look :: any)[key], t)
	end
	return out :: any
end

return DayNight
