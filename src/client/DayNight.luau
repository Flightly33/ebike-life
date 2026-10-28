--[[
	DayNight (client): runs the shared clock (Shared/DayNight) on this client and dresses the world
	for the hour:
	  - Lighting, the sky, Atmosphere, Bloom, colour grading and sun rays blend between the looks,
	    with the weather (Shared/Weather: sunny, partly cloudy, overcast) laid over them;
	  - at dusk the street lamps glow, and the nearest ones (the graphics mode's LampLights within
	    Config.DayNight.LampRange) cast real light;
	  - a stable share of windows light up warm (each window always the same way);
	  - bike and car headlights cast light (your bike's always, the nearest cars').
	Everything here is local: the clock comes from the server time, so all players agree.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DayNightShared = require(Shared.DayNight)
local Weather = require(Shared.Weather)

local BikeController = require(script.Parent.BikeController)
local Graphics = require(script.Parent.Graphics)

local DayNight = {}

local CFG = Config.DayNight
local LAMP_COLOR = Color3.fromRGB(255, 214, 150)
local WINDOW_TONES = { Color3.fromRGB(255, 214, 140), Color3.fromRGB(255, 236, 190), Color3.fromRGB(190, 220, 255) }

type Saved = { Material: Enum.Material, Color: Color3, Transparency: number }

local lamps: { [BasePart]: Saved } = {}
local windows: { [BasePart]: Saved } = {}
local lampLights: { [BasePart]: PointLight } = {}
local beams: { [BasePart]: SpotLight } = {}
local nightOn = false
local pending: { BasePart } = {}

-- a stable 0..1 number for a part (where it stands), so each window is always lit or dark the same way
local function hash(position: Vector3): number
	local n = math.floor(position.X * 3.1) * 73856093 + math.floor(position.Y * 2.7) * 19349663 + math.floor(position.Z * 3.3) * 83492791
	return (n % 1000) / 1000
end

local function dressLamp(part: BasePart, on: boolean)
	local saved = lamps[part]
	if not saved then
		return
	end
	if on then
		part.Material = Enum.Material.Neon
		part.Color = LAMP_COLOR
	else
		part.Material = Enum.Material.SmoothPlastic
		part.Color = saved.Color
	end
end

local function dressWindow(part: BasePart, on: boolean)
	local saved = windows[part]
	if not saved then
		return
	end
	local h = hash(part.Position)
	if on and h < CFG.WindowLitShare then
		part.Material = Enum.Material.Neon
		part.Color = WINDOW_TONES[1 + math.floor(h * 997) % #WINDOW_TONES]:Lerp(Color3.new(0, 0, 0), 0.25)
		part.Transparency = 0
	else
		part.Material = saved.Material
		part.Color = saved.Color
		part.Transparency = saved.Transparency
	end
end

local function track(d: Instance)
	if not d:IsA("BasePart") then
		return
	end
	local name = d.Name
	if name == "Globe" then
		lamps[d] = { Material = d.Material, Color = d.Color, Transparency = d.Transparency }
		dressLamp(d, nightOn)
	elseif name == "Window" or name == "ShopGlass" then
		windows[d] = { Material = d.Material, Color = d.Color, Transparency = d.Transparency }
		if nightOn then
			dressWindow(d, true)
		end
	end
end

local function untrack(d: Instance)
	if d:IsA("BasePart") then
		lamps[d] = nil
		windows[d] = nil
		local light = lampLights[d]
		if light then
			light:Destroy()
			lampLights[d] = nil
		end
	end
end

local function watchCity(city: Instance)
	for _, d in city:GetDescendants() do
		track(d)
	end
	city.DescendantAdded:Connect(track)
	city.DescendantRemoving:Connect(untrack)
end

local OVERCAST_SKY = Color3.fromRGB(196, 202, 210)
local OVERCAST_DECAY = Color3.fromRGB(150, 156, 166)
local OVERCAST_CLOUD = Color3.fromRGB(150, 154, 162)
local OVERCAST_TINT = Color3.fromRGB(240, 244, 250)

local function scaled(c: Color3, k: number): Color3
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end

-- The hour's look with the weather laid over it: cloud cover, how much sun gets through (and how
-- soft the shadows are), haze, a cooler, flatter grade under cloud, and the wind
local function applyLook(look: DayNightShared.Look, hour: number, w: Weather.Conditions)
	local cool = w.Cool
	Lighting.ClockTime = hour
	Lighting.Brightness = look.Brightness * (0.35 + 0.65 * w.Sun)
	Lighting.ExposureCompensation = look.Exposure + 0.15 * cool
	Lighting.Ambient = look.Ambient
	Lighting.OutdoorAmbient = scaled(look.Outdoor, 1 + 0.3 * cool)
	Lighting.ColorShift_Top = look.ShiftTop:Lerp(OVERCAST_SKY, cool * 0.7)
	Lighting.ColorShift_Bottom = look.ShiftBottom
	pcall(function()
		Lighting.ShadowSoftness = w.Softness
	end)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = look.AtmoDensity + 0.12 * w.Haze
		atmosphere.Color = look.AtmoColor:Lerp(OVERCAST_SKY, cool * 0.8)
		atmosphere.Decay = look.AtmoDecay:Lerp(OVERCAST_DECAY, cool * 0.8)
		atmosphere.Haze = look.AtmoHaze + 1.3 * w.Haze
		atmosphere.Glare = look.AtmoGlare * w.Sun * w.Sun
	end
	local grade = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if grade then
		grade.TintColor = look.Tint:Lerp(OVERCAST_TINT, cool * 0.6)
		grade.Brightness = look.GradeBrightness
		grade.Contrast = look.Contrast + w.Contrast
		grade.Saturation = look.Saturation + w.Saturation
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Intensity = look.Bloom
		bloom.Threshold = look.BloomThreshold
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Color = look.Cloud:Lerp(OVERCAST_CLOUD, cool * 0.7)
		clouds.Cover = math.max(w.Cover, look.CloudCover * 0.6)
		clouds.Density = w.Density
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Intensity = look.SunRays * w.Sun * w.Sun * w.Sun
	end
	pcall(function()
		Workspace.GlobalWind = Vector3.new(w.Wind, 0, w.Wind * 0.45)
	end)
end

-- Switch the city's lights on or off (windows a few hundred a frame, so dusk doesn't hitch)
local function setNight(on: boolean)
	nightOn = on
	for part in lamps do
		dressLamp(part, on)
	end
	table.clear(pending)
	for part in windows do
		table.insert(pending, part)
	end
end

local function flushWindows()
	for _ = 1, 300 do
		local part = table.remove(pending)
		if not part then
			return
		end
		if part.Parent then
			dressWindow(part, nightOn)
		end
	end
end

-- Real light from the nearest lamps only
local function updateLampLights(focus: Vector3)
	local near: { { Part: BasePart, D: number } } = {}
	if nightOn then
		for part in lamps do
			local d = (part.Position - focus).Magnitude
			if d < CFG.LampRange then
				table.insert(near, { Part = part, D = d })
			end
		end
		table.sort(near, function(a, b)
			return a.D < b.D
		end)
	end
	local keep: { [BasePart]: boolean } = {}
	for i = 1, math.min(#near, Graphics.Current().LampLights) do
		local part = near[i].Part
		keep[part] = true
		if not lampLights[part] then
			local light = Instance.new("PointLight")
			light.Name = "NightLight"
			light.Color = LAMP_COLOR
			light.Range = 26
			light.Brightness = 1.6
			light.Shadows = false
			light.Parent = part
			lampLights[part] = light
		end
	end
	for part, light in lampLights do
		if not keep[part] then
			light:Destroy()
			lampLights[part] = nil
		end
	end
end

-- Headlights that light the road: your bike's, other bikes', and the nearest cars'
local function updateBeams(focus: Vector3)
	local keep: { [BasePart]: boolean } = {}
	local function want(part: BasePart, range: number)
		keep[part] = true
		if not beams[part] then
			local beam = Instance.new("SpotLight")
			beam.Name = "NightBeam"
			beam.Face = Enum.NormalId.Front
			beam.Angle = 70
			beam.Range = range
			beam.Brightness = 3
			beam.Color = Color3.fromRGB(255, 244, 222)
			beam.Shadows = false
			beam.Parent = part
			beams[part] = beam
		end
	end
	if nightOn then
		local bikes = Workspace:FindFirstChild("Bikes")
		if bikes then
			for _, model in bikes:GetChildren() do
				local mine = model == BikeController.Model
				local root = model:IsA("Model") and model.PrimaryPart
				if root and (mine or (root.Position - focus).Magnitude < 150) then
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") and d.Name == "Headlight" then
							want(d, if mine then 55 else 30)
							break
						end
					end
				end
			end
		end
		local vehicles = Workspace:FindFirstChild("Vehicles")
		if vehicles then
			local cars: { { Model: Model, D: number } } = {}
			for _, model in vehicles:GetChildren() do
				local root = model:IsA("Model") and model.PrimaryPart
				if root then
					table.insert(cars, { Model = model :: Model, D = (root.Position - focus).Magnitude })
				end
			end
			table.sort(cars, function(a, b)
				return a.D < b.D
			end)
			for i = 1, math.min(#cars, Graphics.Current().HeadlightCars) do
				for _, d in cars[i].Model:GetDescendants() do
					if d:IsA("BasePart") and d.Name == "Headlight" then
						want(d, 40)
					end
				end
			end
		end
	end
	for part, beam in beams do
		if not keep[part] or not part.Parent then
			beam:Destroy()
			beams[part] = nil
		end
	end
end

local function offset(): number
	local value = ReplicatedStorage:GetAttribute("ClockOffset")
	return if type(value) == "number" then value else 0
end

function DayNight.Hour(): number
	return DayNightShared.Hour(Workspace:GetServerTimeNow(), offset())
end

-- The weather now (Shared/Weather), and its kind
function DayNight.Weather(): (Weather.Conditions, Weather.Kind)
	local override = ReplicatedStorage:GetAttribute("WeatherOverride")
	return Weather.At(Workspace:GetServerTimeNow(), if type(override) == "string" and override ~= "" then override else nil)
end

function DayNight.Init()
	-- drifting clouds (the engine's own, no parts), blown by a light wind
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Density = 0.62
		clouds.Cover = 0.45
		clouds.Parent = terrain
	end
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 60)
		if city then
			watchCity(city)
		end
	end)
	local lookClock, lightClock = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		lookClock += dt
		lightClock += dt
		if #pending > 0 then
			flushWindows()
		end
		if lookClock >= 0.1 then
			lookClock = 0
			local hour = DayNight.Hour()
			local look = DayNightShared.LookAt(hour)
			applyLook(look, hour, (DayNight.Weather()))
			local night = look.Night > 0.5
			if night ~= nightOn then
				setNight(night)
			end
		end
		if lightClock >= 0.5 then
			lightClock = 0
			local camera = Workspace.CurrentCamera
			local focus = if camera then camera.Focus.Position else Vector3.zero
			updateLampLights(focus)
			updateBeams(focus)
		end
	end)
end

return DayNight
