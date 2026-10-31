--[[
	Garage: Flighty Garage's screen (the service desk's TuningPrompt). Your bike goes up on the lift
	in the middle of the real garage, the camera works round it, and every change shows on it as
	you make it: a mechanic steps up and works on the part, paint mists on and the colour fades
	across, parts flash as they go on, and the bike settles on its springs when the suspension
	changes.

	Tabs: Paint (every part of the bike: a colour picker with presets and hex, finishes, livery
	patterns from the texture pack, and your crate paints; Shared/Livery), Parts (Shared/Upgrades,
	bought one stage at a time), Setup (the mechanic's free adjustments, Shared/Setup) and Glow
	(underglow kits from crates). A stats panel compares what you have with what you're making.
	Paint and setup are drafts until you press Apply (SetLivery / SetSetup; custom paint costs
	cash); parts are bought straight away (BuyUpgrade). Drag to turn the bike, scroll to zoom.
]]

local MaterialService = game:GetService("MaterialService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BikeModel = require(Shared.Models.BikeModel)
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Layout = require(Shared.City.Layout)
local Livery = require(Shared.Livery)
local Paints = require(Shared.Paints)
local PartKit = require(Shared.PartKit)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Setup = require(Shared.Setup)
local Upgrades = require(Shared.Upgrades)

local Sound = require(script.Parent.Parent.Sound)
local State = require(script.Parent.Parent.State)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local Garage = {}

local New = Theme.New
local C = Theme.Colors

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local PRESETS = {
	rgb(240, 240, 238), rgb(20, 20, 22), rgb(120, 122, 128), rgb(205, 30, 38),
	rgb(255, 110, 20), rgb(250, 205, 30), rgb(150, 220, 40), rgb(35, 150, 70),
	rgb(0, 150, 150), rgb(110, 185, 240), rgb(30, 80, 200), rgb(25, 30, 70),
	rgb(110, 50, 190), rgb(255, 120, 200), rgb(140, 20, 40), rgb(184, 110, 60),
	rgb(205, 180, 135), rgb(95, 100, 55), rgb(230, 180, 50), rgb(0, 230, 255),
}

-- Is the player close enough to the garage to work in it?
function Garage.Near(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local g = Layout.Garage
	local p = root.Position
	local dx = math.max(g.MinX - p.X, 0, p.X - g.MaxX)
	local dz = math.max(g.MinZ - p.Z, 0, p.Z - g.MaxZ)
	return math.sqrt(dx * dx + dz * dz) < 60 * Config.MAP_SCALE / 1.25
end

--------------------------------------------------------------------------------
-- The scene: the bike on the lift, the mechanic, effects, the camera
--------------------------------------------------------------------------------

type Scene = {
	Folder: Folder,
	Bike: Model?,
	BikeId: string,
	Deck: CFrame, -- the lift deck's top middle, facing the back wall
	Mechanic: { [string]: BasePart },
	MechanicAt: CFrame,
	WorkUntil: number,
	WorkAt: Vector3?,
	Yaw: number,
	Pitch: number,
	Dist: number,
	Focus: Vector3,
	CamCF: CFrame?,
	Rise: number, -- 0..1 the lift coming up
}

local scene: Scene? = nil
local saved = { CameraType = Enum.CameraType.Custom, Subject = nil :: Instance?, Hud = true }

local function deckFrame(): CFrame
	local lift = Layout.Garage.Lift
	-- the deck's top is 3 design units over the floor (City/Landmarks.Garage)
	local top = Vector3.new(lift.X, lift.Y + 3.0 * Config.WORLD_SCALE, lift.Z)
	return CFrame.lookAt(top, top - Vector3.zAxis)
end

local function bikeScale(): number
	local player = Players.LocalPlayer
	local bikes = Workspace:FindFirstChild("Bikes")
	local mine = bikes and bikes:FindFirstChild("Bike_" .. player.UserId)
	local size = mine and mine:GetAttribute("Scale")
	return if type(size) == "number" then size else 1
end

-- The parts of the preview a slot or upgrade touches
local UPGRADE_PARTS: { [string]: { string } } = {
	Battery = { "Battery", "BatteryBox", "BatteryCase", "Frame" },
	Controller = { "Motor", "MidMotor", "MotorCover", "MotorCap", "HubMotor" },
	Tires = { "Tire", "Front", "Rear" },
	Suspension = { "Fork", "ForkLeg", "Stanchion", "Shock", "ShockBody", "ShockTop", "ShockEnd", "Swing", "Swingarm" },
	Brakes = { "Rotor", "Front", "Rear" },
	Limiter = { "Display", "Steer", "Handlebar" },
}

local function partsFor(model: Model, test: (BasePart) -> boolean): { BasePart }
	local out: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and test(d) then
			table.insert(out, d)
		end
	end
	return out
end

local function slotParts(model: Model, slot: string): { BasePart }
	return partsFor(model, function(p)
		return p:GetAttribute("Paint") == slot
	end)
end

local function upgradeParts(model: Model, upgrade: string): { BasePart }
	local names: { string } = UPGRADE_PARTS[upgrade] or {}
	return partsFor(model, function(p)
		for _, n in (names :: { string }) do
			-- part-built names, or a mesh's group ("<bike>__<Group>__<Slot>")
			if p.Name == n or string.find(p.Name, "__" .. n .. "__", 1, true) then
				return true
			end
		end
		return false
	end)
end

local function centreOf(parts: { BasePart }, fallback: Vector3): Vector3
	if #parts == 0 then
		return fallback
	end
	local sum = Vector3.zero
	for _, p in parts do
		sum += p.Position
	end
	return sum / #parts
end

local function buildMechanic(folder: Folder): { [string]: BasePart }
	local parts: { [string]: BasePart } = {}
	local Q = Config.Avatar.Height / 5.15
	local opts = { Collide = false, Query = false, Touch = false }
	local function add(name: string, size: Vector3, color: Color3, material: Enum.Material?)
		parts[name] = PartKit.Box(folder, name, size * Q, CFrame.identity, color, material or Enum.Material.SmoothPlastic, opts)
	end
	local overalls = rgb(255, 122, 24)
	local skin = rgb(198, 140, 100)
	add("LegL", Vector3.new(0.9, 2.1, 0.9), overalls, Enum.Material.Fabric)
	add("LegR", Vector3.new(0.9, 2.1, 0.9), overalls, Enum.Material.Fabric)
	add("BootL", Vector3.new(0.95, 0.4, 1.2), rgb(30, 30, 32))
	add("BootR", Vector3.new(0.95, 0.4, 1.2), rgb(30, 30, 32))
	add("Torso", Vector3.new(2, 1.9, 1), overalls, Enum.Material.Fabric)
	add("Bib", Vector3.new(1.3, 1.2, 0.08), rgb(26, 28, 34), Enum.Material.Fabric)
	add("Head", Vector3.new(1.15, 1.15, 1.15), skin)
	add("Cap", Vector3.new(1.24, 0.32, 1.24), rgb(26, 28, 34), Enum.Material.Fabric)
	add("Brim", Vector3.new(1.0, 0.07, 0.6), rgb(26, 28, 34), Enum.Material.Fabric)
	add("EyeL", Vector3.new(0.14, 0.16, 0.04), rgb(20, 20, 24))
	add("EyeR", Vector3.new(0.14, 0.16, 0.04), rgb(20, 20, 24))
	add("ArmL", Vector3.new(0.85, 1.9, 0.85), overalls, Enum.Material.Fabric)
	add("ArmR", Vector3.new(0.85, 1.9, 0.85), overalls, Enum.Material.Fabric)
	add("GloveL", Vector3.new(0.9, 0.45, 0.9), rgb(30, 30, 32), Enum.Material.Rubber)
	add("GloveR", Vector3.new(0.9, 0.45, 0.9), rgb(30, 30, 32), Enum.Material.Rubber)
	add("Wrench", Vector3.new(0.2, 1.3, 0.12), rgb(196, 200, 206), Enum.Material.Metal)
	-- a spray of sparks or paint mist from the tool
	local tip = parts.Wrench
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.2, 0.5)
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(50, 50)
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Size = NumberSequence.new(0.12, 0.02)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(rgb(255, 220, 120), rgb(255, 120, 30))
	sparks.Parent = tip
	return parts
end

local function poseMechanic(sc: Scene, now: number)
	local p = sc.Mechanic
	local Q = Config.Avatar.Height / 5.15
	local working = now < sc.WorkUntil
	local at = sc.MechanicAt
	local target = sc.WorkAt
	if working and target then
		-- step up to the work and face it
		local stand = target + (at.Position - target) * Vector3.new(1, 0, 1).Unit * 0
		local flat = Vector3.new(target.X, at.Position.Y, target.Z)
		local away = (at.Position - flat)
		local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		local spot = flat + dir * 3.2 * Q
		at = CFrame.lookAt(Vector3.new(spot.X, at.Position.Y, spot.Z), flat)
		local _ = stand
	end
	local function u(x: number, y: number, z: number): CFrame
		return CFrame.new(x * Q, y * Q, z * Q)
	end
	local swing = if working then math.sin(now * 14) * 0.5 else math.sin(now * 1.5) * 0.04
	local hip = at * u(0, 2.1, 0)
	p.LegL.CFrame = hip * u(-0.5, -1.05, 0)
	p.LegR.CFrame = hip * u(0.5, -1.05, 0)
	p.BootL.CFrame = hip * u(-0.5, -1.95, -0.15)
	p.BootR.CFrame = hip * u(0.5, -1.95, -0.15)
	local lean = if working then CFrame.Angles(math.rad(-18), 0, 0) else CFrame.identity
	local torso = at * u(0, 3.05, 0) * lean
	p.Torso.CFrame = torso
	p.Bib.CFrame = torso * u(0, 0.2, -0.53)
	local head = torso * u(0, 1.55, 0)
	p.Head.CFrame = head
	p.Cap.CFrame = head * u(0, 0.58, 0)
	p.Brim.CFrame = head * u(0, 0.47, -0.82)
	p.EyeL.CFrame = head * u(-0.24, 0.1, -0.58)
	p.EyeR.CFrame = head * u(0.24, 0.1, -0.58)
	local shoulder = torso * u(0, 0.85, 0)
	local reach = if working then 1.3 else 0
	local armL = shoulder * u(-1.43, 0, 0) * CFrame.Angles(reach + swing * 0.3, 0, -0.08) * u(0, -0.9, 0)
	local armR = shoulder * u(1.43, 0, 0) * CFrame.Angles(reach - swing, 0, 0.08) * u(0, -0.9, 0)
	p.ArmL.CFrame = armL
	p.ArmR.CFrame = armR
	p.GloveL.CFrame = armL * u(0, -0.95, 0)
	p.GloveR.CFrame = armR * u(0, -0.95, 0)
	p.Wrench.CFrame = armR * u(0, -1.4, -0.3) * CFrame.Angles(math.rad(80), 0, 0)
end

-- The mechanic works on a spot for a while (sparks for parts, a mist of paint for paint)
local function work(sc: Scene, at: Vector3, seconds: number, mist: Color3?)
	sc.WorkAt = at
	sc.WorkUntil = os.clock() + seconds
	local sparks = sc.Mechanic.Wrench:FindFirstChild("Sparks")
	if sparks and sparks:IsA("ParticleEmitter") then
		if mist then
			sparks.Color = ColorSequence.new(mist)
			sparks.LightEmission = 0
			sparks.Acceleration = Vector3.new(0, -2, 0)
			sparks.Size = NumberSequence.new(0.3, 0.9)
			sparks.Transparency = NumberSequence.new(0.3, 1)
		else
			sparks.Color = ColorSequence.new(rgb(255, 220, 120), rgb(255, 120, 30))
			sparks.LightEmission = 1
			sparks.Acceleration = Vector3.new(0, -30, 0)
			sparks.Size = NumberSequence.new(0.12, 0.02)
			sparks.Transparency = NumberSequence.new(0)
		end
		task.spawn(function()
			for _ = 1, math.floor(seconds * 6) do
				if not sparks.Parent then
					return
				end
				sparks:Emit(if mist then 12 else 8)
				task.wait(1 / 6)
			end
		end)
	end
end

-- Flashes parts orange (SelectionBoxes) for a moment
local function flash(parts: { BasePart }, color: Color3?)
	local boxes: { SelectionBox } = {}
	for i, p in parts do
		if i > 40 then
			break
		end
		local box = Instance.new("SelectionBox")
		box.Adornee = p
		box.Color3 = color or rgb(255, 160, 40)
		box.LineThickness = 0.04
		box.SurfaceTransparency = 0.7
		box.SurfaceColor3 = color or rgb(255, 160, 40)
		box.Parent = p
		table.insert(boxes, box)
	end
	task.delay(1.1, function()
		for _, b in boxes do
			b:Destroy()
		end
	end)
end

local function buildBike(sc: Scene, bike: Bikes.Bike, choice: BikeModel.PaintChoice?)
	local old = sc.Bike
	if old then
		old:Destroy()
	end
	local ok, model = pcall(BikeModel.Build, bike, choice, { Static = true, Scale = bikeScale() })
	if not ok then
		warn("[Garage] " .. tostring(model))
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	model:PivotTo(sc.Deck * CFrame.new(0, -3 * (1 - sc.Rise), 0))
	model.Parent = sc.Folder
	sc.Bike = model
	sc.BikeId = bike.Id
	local _, size = model:GetBoundingBox()
	sc.Focus = sc.Deck.Position + Vector3.new(0, size.Y * 0.45, 0)
	sc.Dist = math.max(size.Magnitude * 1.15, 9)
end

-- Repaints the preview, the colours fading from the old to the new
local function repaint(sc: Scene, bike: Bikes.Bike, choice: BikeModel.PaintChoice?, slot: string?)
	local model = sc.Bike
	if not model then
		return
	end
	local before: { [BasePart]: Color3 } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			before[d] = d.Color
		end
	end
	BikeModel.ApplyPaint(model, bike, choice)
	for part, old in before do
		if part.Parent and part.Color ~= old then
			local new = part.Color
			part.Color = old
			TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Sine), { Color = new }):Play()
		end
	end
	if slot then
		local parts = slotParts(model, slot)
		local look = Livery.Look(slot, if choice then (choice :: any)[slot] else nil, { Frame = bike.Colors.Frame, Accent = bike.Colors.Accent, Rims = bike.Colors.Rims })
		work(sc, centreOf(parts, sc.Focus), 0.9, look.Color)
		Sound.Play("SprayPaint", sc.Focus, 1, 0.8)
	end
end

local function sceneStep(dt: number)
	local sc = scene
	if not sc then
		return
	end
	local now = os.clock()
	-- the lift comes up
	if sc.Rise < 1 then
		sc.Rise = math.min(1, sc.Rise + dt / 1.4)
		local model = sc.Bike
		if model then
			local eased = 1 - (1 - sc.Rise) ^ 3
			model:PivotTo(sc.Deck * CFrame.new(0, -3 * (1 - eased), 0))
		end
	end
	poseMechanic(sc, now)
	-- the camera works round the bike
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local orbit = CFrame.new(sc.Focus) * CFrame.Angles(0, sc.Yaw, 0) * CFrame.Angles(-sc.Pitch, 0, 0) * CFrame.new(0, 0, sc.Dist)
		local current = sc.CamCF or camera.CFrame
		local nextCF = current:Lerp(orbit, math.min(1, dt * 6))
		sc.CamCF = nextCF
		camera.CFrame = nextCF
		camera.Focus = CFrame.new(sc.Focus)
	end
end

local function openScene(bikeId: string, choice: BikeModel.PaintChoice?)
	local folder = Instance.new("Folder")
	folder.Name = "GarageScene"
	folder.Parent = Workspace
	local deck = deckFrame()
	local sc: Scene = {
		Folder = folder,
		Bike = nil,
		BikeId = bikeId,
		Deck = deck,
		Mechanic = buildMechanic(folder),
		MechanicAt = deck * CFrame.new(5.5 * Config.WORLD_SCALE, -3.0 * Config.WORLD_SCALE, 2 * Config.WORLD_SCALE) * CFrame.Angles(0, math.rad(-120), 0),
		WorkUntil = 0,
		WorkAt = nil,
		Yaw = math.rad(-125),
		Pitch = math.rad(14),
		Dist = 12,
		Focus = deck.Position,
		CamCF = nil,
		Rise = 0,
	}
	-- warm studio lights over the lift (only this client sees them)
	for _, side in { -1, 1 } do
		local holder = PartKit.Box(folder, "GarageLight", Vector3.new(0.2, 0.2, 0.2), deck * CFrame.new(side * 9, 14, 4), rgb(255, 255, 255), Enum.Material.SmoothPlastic, { Collide = false, Query = false, Touch = false, Transparency = 1 })
		local light = Instance.new("PointLight")
		light.Range = 30
		light.Brightness = 1.6
		light.Color = rgb(255, 244, 228)
		light.Parent = holder
	end
	scene = sc
	local bike = Bikes.Get(bikeId)
	if bike then
		buildBike(sc, bike, choice)
	end
	Sound.Play("Lift", deck.Position, 1, 0.8)
	local camera = Workspace.CurrentCamera
	if camera then
		saved.CameraType = camera.CameraType
		saved.Subject = camera.CameraSubject
		sc.CamCF = camera.CFrame
	end
	RunService:BindToRenderStep("GarageScene", Enum.RenderPriority.Camera.Value + 20, sceneStep)
end

local function closeScene()
	local sc = scene
	if not sc then
		return
	end
	scene = nil
	pcall(function()
		RunService:UnbindFromRenderStep("GarageScene")
	end)
	sc.Folder:Destroy()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = if saved.CameraType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else saved.CameraType
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		camera.CameraSubject = saved.Subject or humanoid
	end
end

--------------------------------------------------------------------------------
-- Stats for the comparison panel
--------------------------------------------------------------------------------

local function zeroTo50(spec: BikeStats.Spec): number
	local g = Config.Physics.Gravity
	local rho = Config.Physics.AirDensity
	local m = spec.MassKg
	local v, t = 0, 0
	local target = 50 / 3.6 * Config.SpeedBoost
	while v < target and t < 30 do
		local drive = math.min(spec.WheelForceN, spec.MotorW / math.max(v, 0.5))
		drive = math.min(drive, spec.GripRoad * m * g * 0.62)
		if v * 3.6 >= spec.CutoffKmh then
			drive = 0
		end
		local drag = 0.5 * rho * spec.CdA * v * v + spec.CrrRoad * m * g
		v += (drive - drag) / m * 0.02
		t += 0.02
		if drive <= drag and v < target then
			return 99
		end
	end
	return t
end

-- km on a charge cruising at 40 km/h (real) on tarmac: what the air and the tyres take, through
-- the drivetrain, drained like the game's battery (Config.Battery; speeds are SpeedBoost times real)
local function rangeKm(spec: BikeStats.Spec): number
	local g = Config.Physics.Gravity
	local rho = Config.Physics.AirDensity
	local v = 40 / 3.6 * Config.SpeedBoost
	local watts = (0.5 * rho * spec.CdA * v * v + spec.CrrRoad * spec.MassKg * g) * v / 0.85
	local whPerKm = watts / (v * 3.6) * Config.Battery.DrainScale / Config.SpeedBoost ^ 3
	return if whPerKm > 0 then spec.BatteryWh / whPerKm else 999
end

type Stat = { Name: string, Value: (BikeStats.Spec) -> number, Format: (number) -> string, Better: number, Max: number }
local STATS: { Stat } = {
	{ Name = "Top speed", Value = function(s)
		return math.min(s.CutoffKmh, BikeStats.TopSpeedKmh(s, 1, 3.4))
	end, Format = function(v)
		return string.format("%d km/h", v)
	end, Better = 1, Max = 200 },
	{ Name = "0-50 km/h", Value = zeroTo50, Format = function(v)
		return if v >= 99 then "—" else string.format("%.1f s", v)
	end, Better = -1, Max = 8 },
	{ Name = "Range", Value = rangeKm, Format = function(v)
		return string.format("%d km", math.floor(v + 0.5))
	end, Better = 1, Max = 200 },
	{ Name = "Peak power", Value = function(s)
		return s.MotorW / 1000
	end, Format = function(v)
		return string.format("%.1f kW", v)
	end, Better = 1, Max = 80 },
	{ Name = "Wheel force", Value = function(s)
		return s.WheelForceN
	end, Format = function(v)
		return string.format("%d N", math.floor(v))
	end, Better = 1, Max = 3500 },
	{ Name = "Grip (road)", Value = function(s)
		return s.GripRoad
	end, Format = function(v)
		return string.format("%.2f", v)
	end, Better = 1, Max = 1.1 },
	{ Name = "Grip (off-road)", Value = function(s)
		return s.GripOff
	end, Format = function(v)
		return string.format("%.2f", v)
	end, Better = 1, Max = 1.1 },
	{ Name = "Brakes", Value = function(s)
		return s.BrakeG
	end, Format = function(v)
		return string.format("%.2f g", v)
	end, Better = 1, Max = 1.3 },
	{ Name = "Spring rate", Value = function(s)
		return s.SpringScale
	end, Format = function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end, Better = 0, Max = 1.4 },
	{ Name = "Wheelie pop", Value = function(s)
		return s.WheeliePop
	end, Format = function(v)
		return string.format("%.2f", v)
	end, Better = 0, Max = 2 },
}

--------------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------------

function Garage.new(gui: Instance, close: () -> ()): Panel.Panel
	local frame = New("Frame", { Name = "Garage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20, Parent = gui })
	-- the drag-to-turn surface behind the panels
	local turner = New("TextButton", { Name = "Turner", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = frame })

	-- top bar
	local top = New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.1, Size = UDim2.new(1, 0, 0, 62), ZIndex = 21, Parent = frame })
	New("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 200, 208)), Parent = top })
	Theme.Label({ Text = "🔧 FLIGHTY GARAGE", Size = UDim2.fromOffset(330, 44), Position = UDim2.fromOffset(16, 9), TextSize = 32, Color = C.Orange, Align = Enum.TextXAlignment.Left, Stroke = 3, ZIndex = 22, Parent = top })
	local picker = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 44), Position = UDim2.new(0.5, 0, 0, 9), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 22, Parent = top })
	local bikeName = Theme.Label({ Text = "", Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(55, 0), TextSize = 26, Stroke = 2, ZIndex = 23, Parent = picker })
	local cash = Theme.Label({ Text = "", Size = UDim2.fromOffset(200, 40), Position = UDim2.new(1, -150, 0, 11), AnchorPoint = Vector2.new(1, 0), TextSize = 30, Color = C.Cash, StrokeColor = C.CashDark, Align = Enum.TextXAlignment.Right, Stroke = 3, ZIndex = 22, Parent = top })
	Theme.Button({ Text = "Exit", Size = UDim2.fromOffset(110, 42), Position = UDim2.new(1, -16, 0, 10), AnchorPoint = Vector2.new(1, 0), Color = C.Red, TextSize = 22, ZIndex = 22, Parent = top, OnClick = close })

	-- left panel with the tabs
	local left = New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, Size = UDim2.new(0, 430, 1, -150), Position = UDim2.fromOffset(14, 74), ZIndex = 21, Parent = frame })
	Theme.Corner(left, 10)
	Theme.Stroke(left, rgb(12, 12, 14), 2)
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 8), ZIndex = 22, Parent = left })
	Theme.List(tabs, Enum.FillDirection.Horizontal, 6)
	local content = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -16, 1, -60), Position = UDim2.fromOffset(8, 54), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ZIndex = 22, Parent = left })
	Theme.List(content, Enum.FillDirection.Vertical, 8)

	-- right panel: the stats
	local right = New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, Size = UDim2.new(0, 320, 0, 480), Position = UDim2.new(1, -14, 0, 74), AnchorPoint = Vector2.new(1, 0), ZIndex = 21, Parent = frame })
	Theme.Corner(right, 10)
	Theme.Stroke(right, rgb(12, 12, 14), 2)
	Theme.Label({ Text = "Performance", Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 8), TextSize = 24, Align = Enum.TextXAlignment.Left, Stroke = 2, ZIndex = 22, Parent = right })
	local statList = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 1, -50), Position = UDim2.fromOffset(12, 44), ZIndex = 22, Parent = right })
	Theme.List(statList, Enum.FillDirection.Vertical, 4)

	-- bottom bar: what the draft costs, apply and undo
	local bottom = New("Frame", { BackgroundColor3 = C.Panel, BackgroundTransparency = 0.06, Size = UDim2.fromOffset(560, 64), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 21, Parent = frame })
	Theme.Corner(bottom, 10)
	Theme.Stroke(bottom, rgb(12, 12, 14), 2)
	local pending = Theme.Label({ Text = "", Size = UDim2.new(1, -300, 1, 0), Position = UDim2.fromOffset(14, 0), TextSize = 20, Align = Enum.TextXAlignment.Left, Stroke = 2, ZIndex = 22, Parent = bottom })
	local hint = Theme.Label({ Text = "Drag to turn the bike · scroll to zoom", Size = UDim2.fromOffset(420, 20), Position = UDim2.new(0.5, 0, 1, -104), AnchorPoint = Vector2.new(0.5, 0), TextSize = 15, Font = Theme.Body, Color = C.SubText, Stroke = 2, ZIndex = 21, Parent = frame })
	local _ = hint

	-- state
	local bikeId = ""
	local tab = "Paint"
	local slot = "Frame"
	local draft: { [string]: string } = {}
	local draftSetup: { [string]: number } = {}
	local hue, sat, val = 0, 0.8, 0.8
	local finishId, patternId = "gloss", "none"

	local function data(): Profile.Data?
		return State.Get()
	end
	local function currentBike(): Bikes.Bike?
		return Bikes.Get(bikeId)
	end
	local function savedChoice(): { [string]: string }
		local d = data()
		local choice = if d then d.Paint[bikeId] else nil
		local out: { [string]: string } = {}
		if choice then
			for k, v in choice :: any do
				out[k] = v
			end
		end
		return out
	end
	local function levels(): Upgrades.Levels
		local d = data()
		return if d then Profile.Levels(d, bikeId) else {}
	end
	local function draftLevels(): Upgrades.Levels
		local out = table.clone(levels())
		for _, s in Setup.List do
			out["S_" .. s.Key] = draftSetup[s.Key]
		end
		return out
	end
	local function setupChanged(): boolean
		local lv = levels()
		for _, s in Setup.List do
			if Setup.Get(lv, s.Key) ~= draftSetup[s.Key] then
				return true
			end
		end
		return false
	end
	local function paintCost(): number
		local bike = currentBike()
		return if bike then Livery.Cost(bike.Price, savedChoice(), draft) else 0
	end
	local function paintChanged(): boolean
		local old = savedChoice()
		for _, key in Paints.Slots do
			if old[key] ~= draft[key] then
				return true
			end
		end
		return false
	end

	local render: () -> ()

	local function updateStats()
		clear(statList)
		local bike = currentBike()
		if not bike then
			return
		end
		local now = BikeStats.Compute(bike, levels())
		local new = BikeStats.Compute(bike, draftLevels())
		for i, stat in STATS do
			local a, b = stat.Value(now), stat.Value(new)
			local row = New("Frame", { BackgroundColor3 = C.Tile, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = i, ZIndex = 22, Parent = statList })
			Theme.Corner(row, 6)
			Theme.Label({ Text = stat.Name, Size = UDim2.new(0.5, 0, 0, 18), Position = UDim2.fromOffset(8, 3), TextSize = 14, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, ZIndex = 23, Parent = row })
			local changed = math.abs(a - b) > 1e-3
			local good = (b - a) * stat.Better > 0
			local color = if not changed or stat.Better == 0 then (if changed then C.Blue else C.Text) elseif good then C.Cash else rgb(255, 90, 80)
			Theme.Label({ Text = if changed then string.format("%s → %s", stat.Format(a), stat.Format(b)) else stat.Format(a), Size = UDim2.new(0.62, 0, 0, 20), Position = UDim2.new(1, -8, 0, 2), AnchorPoint = Vector2.new(1, 0), TextSize = 16, Color = color, Align = Enum.TextXAlignment.Right, Stroke = 1, ZIndex = 23, Parent = row })
			local track = New("Frame", { BackgroundColor3 = rgb(24, 24, 28), Size = UDim2.new(1, -16, 0, 6), Position = UDim2.fromOffset(8, 28), ZIndex = 23, Parent = row })
			Theme.Corner(track, 3)
			local fill = New("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(math.clamp(b / stat.Max, 0.02, 1), 1), ZIndex = 24, Parent = track })
			Theme.Corner(fill, 3)
		end
	end

	local function updateBottom()
		local cost = paintCost()
		local parts: { string } = {}
		if paintChanged() then
			table.insert(parts, if cost > 0 then "Paint job " .. Economy.FormatCash(cost) else "Paint (free)")
		end
		if setupChanged() then
			table.insert(parts, "Setup (free)")
		end
		pending.Text = if #parts > 0 then table.concat(parts, " · ") else "No changes yet"
		local d = data()
		cash.Text = Economy.FormatCash(if d then d.Cash else 0)
	end

	-- the slot's current coat as colour / finish / pattern for the controls
	local function loadSlot()
		local value = draft[slot]
		local coat = Livery.Decode(value)
		local bike = currentBike()
		local look = Livery.Look(slot, value, if bike then { Frame = bike.Colors.Frame, Accent = bike.Colors.Accent, Rims = bike.Colors.Rims } else nil)
		hue, sat, val = look.Color:ToHSV()
		finishId = if coat then coat.Finish.Id elseif slot == "Seat" then "leather" else "gloss"
		patternId = if coat and coat.Pattern then coat.Pattern.Id else "none"
	end

	-- puts the colour / finish / pattern on the slot (a custom coat) and repaints the preview
	local function paintSlot()
		local finish = Livery.Finish(finishId)
		if finish and finish.SeatOnly and slot ~= "Seat" then
			finishId = "gloss"
		end
		draft[slot] = Livery.Encode(Color3.fromHSV(hue, sat, val), finishId, if patternId ~= "none" then patternId else nil)
		local bike = currentBike()
		local sc = scene
		if bike and sc then
			repaint(sc, bike, draft :: any, slot)
		end
		updateBottom()
	end

	local function section(title: string, order: number)
		Theme.Label({ Text = title, Size = UDim2.new(1, 0, 0, 24), TextSize = 19, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = order, ZIndex = 23, Parent = content })
	end

	local function chipGrid(order: number, height: number): Frame
		local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = 23, Parent = content })
		New("UIGridLayout", { CellSize = UDim2.fromOffset(126, 46), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
		return grid
	end

	local function chip(parent: Instance, text: string, sub: string, selected: boolean, order: number, color: Color3?, enabled: boolean?, onClick: () -> ())
		local b = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if selected then C.Orange else (color or C.Card), LayoutOrder = order, ZIndex = 24, Parent = parent })
		Theme.Corner(b, 8)
		Theme.Stroke(b, if selected then rgb(255, 255, 255) else rgb(16, 16, 18), if selected then 2 else 1)
		Theme.Label({ Text = text, Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 3), TextSize = 15, Stroke = 1, ZIndex = 25, Parent = b })
		Theme.Label({ Text = sub, Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 25), TextSize = 12, Font = Theme.Body, Color = if enabled == false then rgb(150, 150, 156) else C.Cash, Stroke = 1, ZIndex = 25, Parent = b })
		b.Activated:Connect(function()
			if enabled == false then
				Toasts.Message("Error", "That pattern arrives with the texture pack import")
				return
			end
			Sound.Play("Click")
			onClick()
		end)
	end

	-- Paint tab ----------------------------------------------------------------
	local function paintTab()
		local bike = currentBike()
		if not bike then
			return
		end
		-- the slots
		local slots = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 1, ZIndex = 23, Parent = content })
		Theme.List(slots, Enum.FillDirection.Horizontal, 5)
		for i, s in Livery.Slots do
			local b = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if s.Key == slot then C.Orange else C.Card, Size = UDim2.fromOffset(78, 56), LayoutOrder = i, ZIndex = 24, Parent = slots })
			Theme.Corner(b, 8)
			Theme.Label({ Text = s.Icon, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 3), TextSize = 22, Stroke = 0, ZIndex = 25, Parent = b })
			Theme.Label({ Text = s.Title, Size = UDim2.new(1, -4, 0, 18), Position = UDim2.fromOffset(2, 32), TextSize = 12, Font = Theme.Body, Stroke = 1, ZIndex = 25, Parent = b })
			local swatch = New("Frame", { BackgroundColor3 = Livery.Look(s.Key, draft[s.Key], { Frame = bike.Colors.Frame, Accent = bike.Colors.Accent, Rims = bike.Colors.Rims }).Color, Size = UDim2.fromOffset(14, 14), Position = UDim2.new(1, -4, 0, 4), AnchorPoint = Vector2.new(1, 0), ZIndex = 26, Parent = b })
			Theme.Round(swatch)
			Theme.Stroke(swatch, rgb(255, 255, 255), 1)
			b.Activated:Connect(function()
				slot = s.Key
				loadSlot()
				local sc = scene
				if sc and sc.Bike then
					flash(slotParts(sc.Bike, slot), rgb(120, 200, 255))
				end
				render()
			end)
		end
		-- what's on it now
		local value = draft[slot]
		local coat = Livery.Decode(value)
		local paint = Paints.Get(value)
		local desc = if coat then string.format("Custom · %s%s", coat.Finish.Name, if coat.Pattern then " · " .. coat.Pattern.Name else "") elseif paint then "Crate paint · " .. paint.Name else "Factory finish"
		Theme.Label({ Text = desc, Size = UDim2.new(1, 0, 0, 20), TextSize = 15, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, LayoutOrder = 2, ZIndex = 23, Parent = content })

		-- colour: saturation / value square, hue bar, hex, presets
		section("Colour", 3)
		local pickerRow = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 170), LayoutOrder = 4, ZIndex = 23, Parent = content })
		local square = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromHSV(hue, 1, 1), Size = UDim2.fromOffset(170, 170), ZIndex = 24, Parent = pickerRow })
		Theme.Corner(square, 6)
		local white = New("Frame", { BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = square })
		Theme.Corner(white, 6)
		New("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = white })
		local black = New("Frame", { BackgroundColor3 = rgb(0, 0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 26, Parent = square })
		Theme.Corner(black, 6)
		New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
		local knob = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(sat, 1 - val), ZIndex = 27, Parent = square })
		Theme.Round(knob)
		Theme.Stroke(knob, rgb(255, 255, 255), 2)
		local hueBar = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.fromOffset(24, 170), Position = UDim2.fromOffset(180, 0), ZIndex = 24, Parent = pickerRow })
		Theme.Corner(hueBar, 6)
		local keys = {}
		for k = 0, 6 do
			table.insert(keys, ColorSequenceKeypoint.new(k / 6, Color3.fromHSV(k / 6 % 1, 1, 1)))
		end
		New("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys), Parent = hueBar })
		local hueKnob = New("Frame", { BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.new(1, 6, 0, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, hue), ZIndex = 25, Parent = hueBar })
		Theme.Stroke(hueKnob, rgb(0, 0, 0), 1)
		local side = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -216, 1, 0), Position = UDim2.fromOffset(214, 0), ZIndex = 24, Parent = pickerRow })
		local big = New("Frame", { BackgroundColor3 = Color3.fromHSV(hue, sat, val), Size = UDim2.new(1, 0, 0, 60), ZIndex = 25, Parent = side })
		Theme.Corner(big, 8)
		Theme.Stroke(big, rgb(255, 255, 255), 2)
		local hexBox = New("TextBox", { Text = "#" .. Color3.fromHSV(hue, sat, val):ToHex():upper(), PlaceholderText = "#RRGGBB", ClearTextOnFocus = false, BackgroundColor3 = C.Chip, TextColor3 = C.Text, TextSize = 18, FontFace = Theme.Body, Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 68), ZIndex = 25, Parent = side })
		Theme.Corner(hexBox, 6)
		local priceNow = Theme.Label({ Text = "", Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 106), TextSize = 14, Font = Theme.Body, Color = C.SubText, Wrapped = true, Stroke = 0, ZIndex = 25, Parent = side })
		priceNow.Text = string.format("A custom coat on this bike: %s + finish + pattern", Economy.FormatCash(Livery.Price(bike.Price, Livery.Encode(rgb(0, 0, 0), "gloss", nil))))
		local function refreshPicker()
			square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			knob.Position = UDim2.fromScale(sat, 1 - val)
			hueKnob.Position = UDim2.fromScale(0.5, hue)
			big.BackgroundColor3 = Color3.fromHSV(hue, sat, val)
			hexBox.Text = "#" .. Color3.fromHSV(hue, sat, val):ToHex():upper()
		end
		local dragging: string? = nil
		local function readAt(x: number, y: number)
			if dragging == "square" then
				sat = math.clamp((x - square.AbsolutePosition.X) / square.AbsoluteSize.X, 0, 1)
				val = 1 - math.clamp((y - square.AbsolutePosition.Y) / square.AbsoluteSize.Y, 0, 1)
			elseif dragging == "hue" then
				hue = math.clamp((y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 0.999)
			end
			refreshPicker()
		end
		local moved: RBXScriptConnection? = nil
		local ended: RBXScriptConnection? = nil
		local function startDrag(which: string, input: InputObject)
			dragging = which
			readAt(input.Position.X, input.Position.Y)
			moved = UserInputService.InputChanged:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
					readAt(i.Position.X, i.Position.Y)
				end
			end)
			ended = UserInputService.InputEnded:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					dragging = nil
					if moved then
						moved:Disconnect()
					end
					if ended then
						ended:Disconnect()
					end
					paintSlot()
					render()
				end
			end)
		end
		square.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				startDrag("square", input)
			end
		end)
		hueBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				startDrag("hue", input)
			end
		end)
		hexBox.FocusLost:Connect(function()
			local text = string.gsub(hexBox.Text, "#", "")
			local ok, color = pcall(Color3.fromHex, text)
			if ok and #text == 6 then
				hue, sat, val = color:ToHSV()
				paintSlot()
				render()
			else
				refreshPicker()
			end
		end)
		local presets = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 5, ZIndex = 23, Parent = content })
		New("UIGridLayout", { CellSize = UDim2.fromOffset(36, 26), CellPadding = UDim2.fromOffset(4, 4), Parent = presets })
		for i, c in PRESETS do
			local b = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = c, LayoutOrder = i, ZIndex = 24, Parent = presets })
			Theme.Corner(b, 5)
			Theme.Stroke(b, rgb(255, 255, 255), 1, 0.6)
			b.Activated:Connect(function()
				hue, sat, val = c:ToHSV()
				paintSlot()
				render()
			end)
		end

		-- finishes
		section("Finish", 6)
		local finishes = chipGrid(7, 100)
		for i, f in Livery.Finishes do
			if f.SeatOnly and slot ~= "Seat" then
				continue
			end
			chip(finishes, f.Name, if f.Price > 0 then "+" .. Economy.FormatCash(f.Price) else "Included", f.Id == finishId and Livery.Decode(draft[slot]) ~= nil, i, nil, true, function()
				finishId = f.Id
				paintSlot()
				render()
			end)
		end

		-- patterns (from the texture pack)
		section("Pattern", 8)
		local patterns = chipGrid(9, 100)
		chip(patterns, "Plain", "Included", patternId == "none", 0, nil, true, function()
			patternId = "none"
			paintSlot()
			render()
		end)
		for i, p in Livery.Patterns do
			local installed = MaterialService:FindFirstChild(p.Variant) ~= nil
			chip(patterns, p.Name, if installed then "+" .. Economy.FormatCash(p.Price) else "Texture pack", p.Id == patternId, i, nil, installed, function()
				patternId = p.Id
				paintSlot()
				render()
			end)
		end

		-- crate paints the player owns
		section("Your crate paints", 10)
		local crate = chipGrid(11, 50)
		local d = data()
		chip(crate, "Factory", "Free", draft[slot] == nil, 0, nil, true, function()
			draft[slot] = nil
			local sc = scene
			if sc then
				repaint(sc, bike, draft :: any, slot)
			end
			loadSlot()
			updateBottom()
			render()
		end)
		for i, p in Paints.List do
			if p.Kind == "Paint" and p.Id ~= "stock" and d and Profile.HasPaint(d, p.Id) then
				chip(crate, p.Name, p.Rarity, draft[slot] == p.Id, i, p.Color:Lerp(C.Card, 0.55), true, function()
					draft[slot] = p.Id
					local sc = scene
					if sc then
						repaint(sc, bike, draft :: any, slot)
					end
					loadSlot()
					updateBottom()
					render()
				end)
			end
		end
	end

	-- Parts tab ------------------------------------------------------------------
	local function partsTab()
		local bike = currentBike()
		local d = data()
		if not bike or not d then
			return
		end
		local lv = levels()
		for i, s in Upgrades.Slots do
			if s.Name == "Limiter" and not BikeStats.HasLimiter(bike) then
				continue
			end
			local card = New("Frame", { BackgroundColor3 = C.Tile, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i, ZIndex = 23, Parent = content })
			Theme.Corner(card, 8)
			New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = card })
			Theme.List(card, Enum.FillDirection.Vertical, 4)
			Theme.Label({ Text = s.Title, Size = UDim2.new(1, 0, 0, 22), TextSize = 19, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = 1, ZIndex = 24, Parent = card })
			Theme.Label({ Text = s.Description, Size = UDim2.new(1, 0, 0, 30), TextSize = 13, Font = Theme.BodyRegular, Color = C.SubText, Wrapped = true, Align = Enum.TextXAlignment.Left, Stroke = 0, LayoutOrder = 2, ZIndex = 24, Parent = card })
			local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = 24, Parent = card })
			New("UIGridLayout", { CellSize = UDim2.fromOffset(186, 46), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
			local current = Upgrades.Level(lv, s.Name)
			local owned = Upgrades.Owned(lv, s.Name)
			for level = 0, #s.Levels - 1 do
				local name = s.Levels[level + 1]
				local sub: string
				local enabled = true
				if level == current then
					sub = "Fitted ✓"
				elseif level <= owned then
					sub = "Owned: fit it"
				elseif level == owned + 1 then
					sub = "Buy " .. Economy.FormatCash(Upgrades.Cost(bike.Id, s.Name, level))
				else
					sub = "Needs the stage before"
					enabled = false
				end
				local b = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = if level == current then C.Orange else C.Card, LayoutOrder = level, ZIndex = 25, Parent = row })
				Theme.Corner(b, 8)
				Theme.Label({ Text = name, Size = UDim2.new(1, -8, 0, 20), Position = UDim2.fromOffset(4, 3), TextSize = 13, Wrapped = true, Stroke = 1, ZIndex = 26, Parent = b })
				Theme.Label({ Text = sub, Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 26), TextSize = 12, Font = Theme.Body, Color = if enabled then C.Cash else rgb(150, 150, 156), Stroke = 1, ZIndex = 26, Parent = b })
				b.Activated:Connect(function()
					if not enabled or level == current then
						return
					end
					local ok, message = Remotes.Function("BuyUpgrade"):InvokeServer(bike.Id, s.Name, level)
					Toasts.Message(if ok then "Cash" else "Error", tostring(message))
					local sc = scene
					if ok and sc and sc.Bike then
						local parts = upgradeParts(sc.Bike, s.Name)
						flash(parts)
						work(sc, centreOf(parts, sc.Focus), 1.3, nil)
						Sound.Play(if s.Name == "Tires" or s.Name == "Brakes" then "AirWrench" else "Ratchet", sc.Focus, 1, 0.8)
					end
				end)
			end
		end
	end

	-- Setup tab ------------------------------------------------------------------
	local function settle(sc: Scene, depth: number)
		local model = sc.Bike
		if not model then
			return
		end
		local base = model:GetPivot()
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 1.2 and model.Parent do
				local t = os.clock() - t0
				local dip = depth * math.exp(-t * 3.5) * math.sin(t * 14)
				model:PivotTo(base * CFrame.new(0, -math.abs(dip), 0))
				task.wait()
			end
			if model.Parent then
				model:PivotTo(base)
			end
		end)
	end

	local function setupTab()
		for i, s in Setup.List do
			local card = New("Frame", { BackgroundColor3 = C.Tile, Size = UDim2.new(1, -6, 0, 96), LayoutOrder = i, ZIndex = 23, Parent = content })
			Theme.Corner(card, 8)
			Theme.Label({ Text = s.Title, Size = UDim2.new(0.6, 0, 0, 22), Position = UDim2.fromOffset(10, 6), TextSize = 18, Align = Enum.TextXAlignment.Left, Stroke = 2, ZIndex = 24, Parent = card })
			local value = draftSetup[s.Key]
			Theme.Label({ Text = s.Label(value), Size = UDim2.new(0.4, -10, 0, 22), Position = UDim2.new(1, -10, 0, 6), AnchorPoint = Vector2.new(1, 0), TextSize = 17, Color = if value ~= s.Default then C.Orange else C.Text, Align = Enum.TextXAlignment.Right, Stroke = 2, ZIndex = 24, Parent = card })
			Theme.Label({ Text = s.Description, Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 28), TextSize = 12, Font = Theme.BodyRegular, Color = C.SubText, Wrapped = true, Align = Enum.TextXAlignment.Left, Stroke = 0, ZIndex = 24, Parent = card })
			local track = New("Frame", { BackgroundColor3 = rgb(24, 24, 28), Size = UDim2.new(1, -120, 0, 8), Position = UDim2.new(0.5, 0, 0, 68), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 24, Parent = card })
			Theme.Corner(track, 4)
			local steps = s.Max - s.Min
			for k = 0, steps do
				local tick = New("Frame", { BackgroundColor3 = if s.Min + k == value then C.Orange else rgb(90, 90, 96), Size = UDim2.fromOffset(if s.Min + k == value then 14 else 6, if s.Min + k == value then 14 else 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(k / steps, 0.5), ZIndex = 25, Parent = track })
				Theme.Round(tick)
			end
			Theme.Label({ Text = s.Left, Size = UDim2.fromOffset(120, 14), Position = UDim2.new(0, 60, 0, 80), TextSize = 11, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, ZIndex = 24, Parent = card })
			Theme.Label({ Text = s.Right, Size = UDim2.fromOffset(120, 14), Position = UDim2.new(1, -60, 0, 80), AnchorPoint = Vector2.new(1, 0), TextSize = 11, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Right, Stroke = 0, ZIndex = 24, Parent = card })
			for _, dir in { -1, 1 } do
				Theme.Button({ Text = if dir < 0 then "−" else "+", Size = UDim2.fromOffset(40, 34), Position = if dir < 0 then UDim2.fromOffset(10, 56) else UDim2.new(1, -10, 0, 56), AnchorPoint = if dir < 0 then Vector2.zero else Vector2.new(1, 0), TextSize = 24, Color = C.Gray, ZIndex = 24, Parent = card, OnClick = function()
					local nextValue = math.clamp(draftSetup[s.Key] + dir, s.Min, s.Max)
					if nextValue == draftSetup[s.Key] then
						return
					end
					draftSetup[s.Key] = nextValue
					local sc = scene
					if sc and sc.Bike then
						local partsMap = { Gearing = "Brakes", PowerMap = "Controller", Regen = "Controller", Spring = "Suspension", Damping = "Suspension", Pressure = "Tires", Steering = "Limiter", Balance = "Suspension" }
						local parts = upgradeParts(sc.Bike, partsMap[s.Key] or "Suspension")
						work(sc, centreOf(parts, sc.Focus), 0.8, nil)
						flash(parts, rgb(120, 200, 255))
						Sound.Play("Ratchet", sc.Focus, 1.2, 0.6)
						if s.Key == "Spring" or s.Key == "Damping" or s.Key == "Balance" then
							settle(sc, 0.6 - draftSetup.Spring * 0.12)
						end
					end
					render()
				end })
			end
		end
	end

	-- Glow tab ---------------------------------------------------------------------
	local function glowTab()
		local bike = currentBike()
		local d = data()
		if not bike or not d then
			return
		end
		Theme.Label({ Text = "Underglow kits come from crates. Fit any you've won.", Size = UDim2.new(1, 0, 0, 34), TextSize = 14, Font = Theme.BodyRegular, Color = C.SubText, Wrapped = true, Align = Enum.TextXAlignment.Left, Stroke = 0, LayoutOrder = 0, ZIndex = 23, Parent = content })
		local grid = chipGrid(1, 100)
		local function pick(value: string?)
			draft.Glow = value :: any
			local sc = scene
			if sc then
				repaint(sc, bike, draft :: any, nil)
				if sc.Bike then
					work(sc, sc.Deck.Position, 0.8, nil)
				end
			end
			updateBottom()
			render()
		end
		chip(grid, "None", "", draft.Glow == nil, 0, nil, true, function()
			pick(nil)
		end)
		for i, p in Paints.List do
			if p.Kind == "Glow" and Profile.HasPaint(d, p.Id) then
				chip(grid, p.Name, p.Rarity, draft.Glow == p.Id, i, p.Color:Lerp(C.Card, 0.5), true, function()
					pick(p.Id)
				end)
			end
		end
	end

	-- tabs and the bike picker -----------------------------------------------------
	local tabButtons: { [string]: TextButton } = {}
	for i, name in { "Paint", "Parts", "Setup", "Glow" } do
		tabButtons[name] = Theme.Button({ Text = name, Size = UDim2.fromOffset(98, 36), TextSize = 18, Color = C.Gray, LayoutOrder = i, ZIndex = 23, Parent = tabs, OnClick = function()
			tab = name
			local sc = scene
			if sc then
				-- frame the bike for the tab
				sc.Pitch = if name == "Parts" then math.rad(8) else math.rad(14)
			end
			render()
		end })
	end

	local function owned(): { Bikes.Bike }
		local d = data()
		local out: { Bikes.Bike } = {}
		if d then
			for _, b in Bikes.List do
				if d.Owned[b.Id] then
					table.insert(out, b)
				end
			end
		end
		return out
	end

	local function loadBike(id: string)
		bikeId = id
		draft = savedChoice()
		draftSetup = {}
		local lv = levels()
		for _, s in Setup.List do
			draftSetup[s.Key] = Setup.Get(lv, s.Key)
		end
		slot = "Frame"
		loadSlot()
		local bike = currentBike()
		local sc = scene
		if bike and sc then
			sc.Rise = 0
			buildBike(sc, bike, draft :: any)
			Sound.Play("Lift", sc.Deck.Position, 1, 0.8)
		end
	end

	for _, dir in { -1, 1 } do
		Theme.Button({ Text = if dir < 0 then "◀" else "▶", Size = UDim2.fromOffset(48, 40), Position = if dir < 0 then UDim2.fromOffset(0, 2) else UDim2.new(1, 0, 0, 2), AnchorPoint = if dir < 0 then Vector2.zero else Vector2.new(1, 0), TextSize = 20, Color = C.Gray, ZIndex = 23, Parent = picker, OnClick = function()
			local list = owned()
			if #list == 0 then
				return
			end
			local index = 1
			for i, b in list do
				if b.Id == bikeId then
					index = i
				end
			end
			index = (index - 1 + dir) % #list + 1
			loadBike(list[index].Id)
			render()
		end })
	end

	-- apply and undo
	Theme.Button({ Text = "Undo", Size = UDim2.fromOffset(100, 44), Position = UDim2.new(1, -150, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.Gray, TextSize = 20, ZIndex = 22, Parent = bottom, OnClick = function()
		loadBike(bikeId)
		render()
	end })
	Theme.Button({ Text = "Apply", Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.Green, TextSize = 22, ZIndex = 22, Parent = bottom, OnClick = function()
		local said: { string } = {}
		local anyOk = false
		if paintChanged() then
			local ok, message = Remotes.Function("SetLivery"):InvokeServer(bikeId, draft)
			table.insert(said, tostring(message))
			if not ok then
				Toasts.Message("Error", tostring(message))
				return
			end
			anyOk = true
		end
		if setupChanged() then
			local ok, message = Remotes.Function("SetSetup"):InvokeServer(bikeId, draftSetup)
			table.insert(said, tostring(message))
			if not ok then
				Toasts.Message("Error", tostring(message))
				return
			end
			anyOk = true
		end
		if anyOk then
			Toasts.Message("Cash", table.concat(said, " · "))
			Sound.Play("Cash")
			local sc = scene
			if sc then
				work(sc, sc.Focus, 1.0, nil)
			end
		end
	end })

	render = function()
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == tab then C.Orange else C.Gray
		end
		local bike = currentBike()
		bikeName.Text = if bike then Bikes.FullName(bike) else "No bike"
		clear(content)
		if tab == "Paint" then
			paintTab()
		elseif tab == "Parts" then
			partsTab()
		elseif tab == "Setup" then
			setupTab()
		else
			glowTab()
		end
		updateStats()
		updateBottom()
	end

	-- drag to turn, scroll to zoom
	local turning: Vector2? = nil
	turner.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			turning = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local sc = scene
		if not sc then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			sc.Dist = math.clamp(sc.Dist * (if input.Position.Z > 0 then 0.88 else 1.14), 5, 30)
		elseif turning and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local now = Vector2.new(input.Position.X, input.Position.Y)
			local delta = now - turning
			turning = now
			sc.Yaw -= delta.X * 0.008
			sc.Pitch = math.clamp(sc.Pitch + delta.Y * 0.005, math.rad(-5), math.rad(60))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			turning = nil
		end
	end)

	-- open and close with the panel
	local hud: ScreenGui? = nil
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		local player = Players.LocalPlayer
		local playerGui = player:FindFirstChild("PlayerGui")
		hud = playerGui and playerGui:FindFirstChild("EbikeHUD") :: ScreenGui?
		if frame.Visible then
			saved.Hud = if hud then hud.Enabled else true
			if hud then
				hud.Enabled = false
			end
		else
			closeScene()
			local h = hud
			if h then
				h.Enabled = saved.Hud
			end
		end
	end)

	local title = Theme.Label({ Text = "", Size = UDim2.fromOffset(0, 0), Parent = frame })
	title.Visible = false
	local self: Panel.Panel = { Name = "Garage", Frame = frame, Body = frame, Title = title, Footer = title, OnClose = nil, Refresh = nil }
	self.Refresh = function()
		local d = data()
		if not d then
			return
		end
		local spawned = Players.LocalPlayer:GetAttribute("BikeId")
		local id = if type(spawned) == "string" and spawned ~= "" and d.Owned[spawned] then spawned else d.Equipped
		openScene(id, d.Paint[id])
		loadBike(id)
		tab = "Paint"
		render()
	end
	State.Changed:Connect(function()
		if frame.Visible then
			-- (a purchase changed the profile: keep the drafts, refresh the panels)
			if tab == "Parts" then
				render()
			else
				updateStats()
				updateBottom()
			end
		end
	end)
	return self
end

return Garage
