--[[
	Visuals: everything that moves for looks only, on every client.

	Bikes: wheels spin with the bike's speed, bars turn with the rider's steering, pedals turn with
	their cadence (from the bike's attributes; the local rider's bike uses its exact physics state),
	and each bike's motor hums with its power. The fork lowers slide and the swingarm swings with the
	suspension: the local bike draws its own suspension state, other bikes measure how far each wheel
	sits from the ground under it (their chassis already comes sagged and pitched with their frame).
	Cars: wheels spin; police cars in a pursuit flash their light bars, light the road red and blue
	and run their siren.
	Traffic lights follow the server clock (Shared/City/Layout.LightState).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Config = require(Shared.Config)
local Layout = require(Shared.City.Layout)
local BikeModel = require(Shared.Models.BikeModel)
local BikePhysics = require(Shared.BikePhysics)
local CarModel = require(Shared.Models.CarModel)

local BikeController = require(script.Parent.BikeController)
local Sound = require(script.Parent.Sound)
local World = require(script.Parent.World)

local Visuals = {}

local STUDS = Config.STUDS_PER_METER
local VIS = Config.VISUAL_STUDS_PER_METER
local TAU = math.pi * 2
local MEASURE_RANGE = 300 -- studs from the camera: other bikes' suspension is measured within this

type BikeRig = {
	Root: BasePart,
	Rear: Motor6D?,
	Front: Motor6D?,
	Steer: Motor6D?,
	Barspin: number, -- 0..1 of a barspin (other riders' from the Barspin attribute)
	Crank: Motor6D?,
	Sprocket: Motor6D?, -- the e-moto meshes' front sprocket
	ChainTop: Motor6D?, -- and the chain's two runs, slid along themselves
	ChainBot: Motor6D?,
	Fork: Motor6D?,
	Swing: Motor6D?,
	ShockTop: Motor6D?,
	ShockEnd: Motor6D?,
	Sus: BikeModel.SuspensionGeo,
	Comp: { number }, -- compression drawn at each wheel, m
	WheelAngle: number,
	CrankAngle: number,
	RadiusM: number,
	Motor: Sound?,
	Moto: boolean,
}

type CarRig = {
	Root: BasePart,
	Wheels: { Motor6D },
	Angle: number,
	RadiusStuds: number,
	Red: { BasePart },
	Blue: { BasePart },
	Siren: Sound?,
}

local bikeRigs: { [Model]: BikeRig } = {}
local carRigs: { [Model]: CarRig } = {}
local wind: Sound? = nil

local function findMotor(model: Model, name: string): Motor6D?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("Motor6D") then found else nil
end

local function bikeRig(model: Model): BikeRig?
	local rig = bikeRigs[model]
	if rig then
		return rig
	end
	local root = model.PrimaryPart
	local id = model:GetAttribute("BikeId")
	local bike = if type(id) == "string" then Bikes.Get(id) else nil
	if not root or not bike then
		return nil
	end
	local size = model:GetAttribute("Scale")
	local spec = BikeStats.Scaled(BikeStats.Compute(bike, nil), if type(size) == "number" then size else 1)
	local moto = not bike.Pedals
	local newRig: BikeRig = {
		Root = root,
		Rear = findMotor(model, "RearSpin"),
		Front = findMotor(model, "FrontSpin"),
		Steer = findMotor(model, "SteerJoint"),
		Barspin = 0,
		Crank = findMotor(model, "CrankSpin"),
		Sprocket = findMotor(model, "SprocketSpin"),
		ChainTop = findMotor(model, "ChainTopSlide"),
		ChainBot = findMotor(model, "ChainBotSlide"),
		Fork = findMotor(model, "ForkSlide"),
		Swing = findMotor(model, "SwingJoint"),
		ShockTop = findMotor(model, "ShockJoint"),
		ShockEnd = findMotor(model, "ShockRodJoint"),
		Sus = BikeModel.SuspensionGeometry(bike, (function()
			local size = model:GetAttribute("Scale")
			return if type(size) == "number" then size else 1
		end)()),
		Comp = { 0, 0 },
		WheelAngle = 0,
		CrankAngle = 0,
		RadiusM = spec.WheelRadiusM,
		Motor = Sound.Loop(if moto then "MotoMotor" else "Motor", root),
		Moto = moto,
	}
	bikeRigs[model] = newRig
	model.Destroying:Connect(function()
		local motor = newRig.Motor
		if motor then
			motor:Destroy()
		end
		bikeRigs[model] = nil
	end)
	return newRig
end

local function carRig(model: Model): CarRig?
	local rig = carRigs[model]
	if rig then
		return rig
	end
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local wheels: { Motor6D } = {}
	local red, blue = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "Spin" then
			table.insert(wheels, d)
		elseif d:IsA("BasePart") then
			if d.Name == "LightRed" then
				table.insert(red, d)
			elseif d.Name == "LightBlue" then
				table.insert(blue, d)
			end
		end
	end
	local kind = model:GetAttribute("CarKind")
	local newRig: CarRig = {
		Root = root,
		Wheels = wheels,
		Angle = 0,
		RadiusStuds = CarModel.WheelRadius(if type(kind) == "string" then kind else "Sedan"),
		Red = red,
		Blue = blue,
		Siren = nil,
	}
	carRigs[model] = newRig
	model.Destroying:Connect(function()
		local siren = newRig.Siren
		if siren then
			siren:Destroy()
		end
		carRigs[model] = nil
	end)
	return newRig
end

local function setLamp(part: BasePart, on: boolean, brightness: number)
	part.Transparency = if on then 0 else 0.65
	local glow = part:FindFirstChild("Glow")
	if glow and glow:IsA("PointLight") then
		glow.Brightness = if on then brightness else 0
	end
end

local function forwardSpeed(root: BasePart): number
	local v = root.AssemblyLinearVelocity
	return v:Dot(root.CFrame.LookVector)
end

-- Another rider's bike: how far each wheel's axle has risen from top-out. The ground under each axle
-- (a straight-down ray) is where the tyre's bottom sits, less its squash; the axle rises along the
-- chassis' normal, which a lean or wheelie tips, so the climb is divided by its vertical part. Eased
-- so a lost ray doesn't snap.
local function measureSuspension(rig: BikeRig, dt: number, instant: boolean?)
	local root = rig.Root
	if root.Anchored and not instant then
		rig.Comp[1], rig.Comp[2] = 0, 0 -- parked: topped out, origin on the ground
		return
	end
	local frame = root.CFrame
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - frame.Position).Magnitude > MEASURE_RANGE then
		return
	end
	local upY = math.max(frame.UpVector.Y, 0.3)
	local sus = rig.Sus
	local ease = if instant then 1 else 1 - math.exp(-25 * dt)
	for i = 1, 2 do
		local travel, radius = sus.Travel[i], sus.Radius[i] * sus.Scale
		local axle = frame:PointToWorldSpace((if i == 1 then sus.FrontAxle else sus.RearAxle) * VIS * sus.Scale)
		local above = (travel + radius) * VIS
		local hit = Workspace:Raycast(axle + Vector3.new(0, above, 0), Vector3.new(0, -(above + (radius + 0.15) * VIS), 0), World.Params())
		local target = 0
		if hit then
			local rise = (hit.Position.Y + radius * VIS * upY - axle.Y) / upY / VIS
			target = math.clamp(rise, 0, travel + 0.06)
		end
		rig.Comp[i] += (target - rig.Comp[i]) * ease
	end
end

-- Draw the suspension (BikeModel.SuspensionPose: the fork lowers up the steering axis, the swingarm
-- about its pivot, the shock's body and shaft turned to keep pointing at each other)
-- The chain moves with the rear wheel: the rear sprocket turns with it, so the chain runs at its
-- pitch radius times the wheel's angle. Each run slides along itself by that much, wrapped to one
-- link (two plates), so the links look like they travel; the front sprocket (48 teeth to 14) spins.
local SPROCKET_RATIO = 48 / 14
local function driveChain(rig: BikeRig)
	local sprocket = rig.Sprocket
	if not sprocket then
		return
	end
	sprocket.Transform = CFrame.Angles(-rig.WheelAngle * SPROCKET_RATIO, 0, 0)
	local hub = sprocket.Part1
	local radius = hub and hub:GetAttribute("Radius")
	if type(radius) ~= "number" then
		return
	end
	local travel = rig.WheelAngle * radius
	for _, run in { { Motor = rig.ChainTop, Sign = -1 }, { Motor = rig.ChainBot, Sign = 1 } } do
		local motor = run.Motor
		local part = motor and motor.Part1
		if motor and part then
			local dir, period = part:GetAttribute("Dir"), part:GetAttribute("Period")
			if typeof(dir) == "Vector3" and type(period) == "number" and period > 0 then
				-- the top run is pulled forward onto the sprocket, the bottom run goes back
				motor.Transform = CFrame.new(dir * (run.Sign * (travel % period)))
			end
		end
	end
end

local function poseSuspension(rig: BikeRig)
	local pose = BikeModel.SuspensionPose(rig.Sus, rig.Comp[1], rig.Comp[2])
	if rig.Fork then
		rig.Fork.Transform = pose.Fork
	end
	if rig.Swing then
		rig.Swing.Transform = pose.Swing
	end
	if rig.ShockTop then
		rig.ShockTop.Transform = pose.ShockTop
	end
	if rig.ShockEnd then
		rig.ShockEnd.Transform = pose.ShockEnd
	end
end

local function updateBikes(dt: number)
	local folder = Workspace:FindFirstChild("Bikes")
	if not folder then
		return
	end
	local mine = BikeController.Model
	local physics = BikeController.Physics
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local rig = bikeRig(model)
		if not rig then
			continue
		end
		local speed: number -- m/s
		local steer: number
		local power: number
		if model == mine and physics then
			speed = physics.Speed
			rig.WheelAngle = physics.WheelAngle
			rig.CrankAngle = physics.CrankAngle
			steer = physics.SteerAngle
			rig.Barspin = physics.BarSpin
			local spec = BikeController.Spec
			power = if spec and spec.MotorW > 0 then physics.MotorPower / spec.MotorW else 0
			rig.Comp[1], rig.Comp[2] = BikePhysics.DrawnCompression(physics)
			-- then put each wheel on the ground actually under it this frame (the physics' own ground
			-- can differ a little from what's drawn; the wheels must never sink into the road)
			measureSuspension(rig, dt, true)
		else
			speed = forwardSpeed(rig.Root) / STUDS
			rig.WheelAngle = (rig.WheelAngle + speed / rig.RadiusM * dt) % TAU
			local cadence = model:GetAttribute("Cadence")
			rig.CrankAngle = (rig.CrankAngle + (if type(cadence) == "number" then cadence else 0) / 60 * TAU * dt) % TAU
			local s = model:GetAttribute("Steer")
			steer = (if type(s) == "number" then s else 0) * 0.35
			if model:GetAttribute("Barspin") == true or rig.Barspin > 0 then
				rig.Barspin += dt / 0.45
				if rig.Barspin >= 1 then
					rig.Barspin = 0
				end
			end
			local p = model:GetAttribute("Power")
			power = if type(p) == "number" then p else 0
			measureSuspension(rig, dt)
		end
		poseSuspension(rig)
		local spin = CFrame.Angles(-rig.WheelAngle, 0, 0)
		if rig.Rear then
			rig.Rear.Transform = spin
		end
		if rig.Front then
			rig.Front.Transform = spin
		end
		if rig.Steer then
			rig.Steer.Transform = CFrame.Angles(0, -steer - rig.Barspin * math.pi * 2, 0)
		end
		if rig.Crank then
			rig.Crank.Transform = CFrame.Angles(-rig.CrankAngle, 0, 0)
		end
		driveChain(rig)
		local motor = rig.Motor
		if motor then
			local kmh = math.abs(speed) * 3.6
			local base = Sound.BaseVolume(if rig.Moto then "MotoMotor" else "Motor")
			motor.Volume = base * math.clamp(power * 1.4 + (if kmh > 3 then 0.15 else 0), 0, 1.2)
			motor.PlaybackSpeed = 0.7 + math.clamp(kmh / (if rig.Moto then 90 else 40), 0, 1.4) * 0.8
		end
	end
	-- Wind for the local rider
	local w = wind
	if w then
		local kmh = BikeController.Kmh()
		w.Volume = Sound.BaseVolume("Wind") * math.clamp((kmh - 15) / 45, 0, 1.3)
		w.PlaybackSpeed = 0.8 + math.clamp(kmh / 100, 0, 0.6)
	end
end

local function updateCars(dt: number)
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local flash = (os.clock() * 7) % 2 < 1
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local rig = carRig(model)
		if not rig then
			continue
		end
		local speed = forwardSpeed(rig.Root)
		rig.Angle = (rig.Angle + speed / math.max(rig.RadiusStuds, 0.5) * dt) % TAU
		local spin = CFrame.Angles(-rig.Angle, 0, 0)
		for _, wheel in rig.Wheels do
			wheel.Transform = spin
		end
		if #rig.Red > 0 then
			local pursuit = model:GetAttribute("Pursuit") == true
			for _, lamp in rig.Red do
				setLamp(lamp, pursuit and flash, 7)
			end
			for _, lamp in rig.Blue do
				setLamp(lamp, pursuit and not flash, 7)
			end
			if pursuit and not rig.Siren then
				local siren = Sound.Loop("Siren", rig.Root)
				siren.RollOffMaxDistance = 600
				rig.Siren = siren
			elseif not pursuit and rig.Siren then
				local siren = rig.Siren :: Sound
				siren:Destroy()
				rig.Siren = nil
			end
			local siren = rig.Siren
			if siren then
				siren.Volume = Sound.BaseVolume("Siren")
			end
		end
	end
end

-- Traffic lights
type SignalHead = { Node: number, Axis: string, Red: BasePart, Yellow: BasePart, Green: BasePart }
local signals: { SignalHead } = {}
local RED = Color3.fromRGB(255, 40, 40)
local YELLOW = Color3.fromRGB(255, 200, 30)
local GREEN = Color3.fromRGB(40, 255, 110)
local OFF = Color3.fromRGB(40, 40, 40)

local function collectSignals()
	signals = {}
	local city = Workspace:FindFirstChild("City")
	local folder = city and city:FindFirstChild("Signals")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		local node, axis = model:GetAttribute("Node"), model:GetAttribute("Axis")
		local red, yellow, green = model:FindFirstChild("Red"), model:FindFirstChild("Yellow"), model:FindFirstChild("Green")
		if type(node) == "number" and type(axis) == "string" and red and yellow and green and red:IsA("BasePart") and yellow:IsA("BasePart") and green:IsA("BasePart") then
			table.insert(signals, { Node = node, Axis = axis, Red = red, Yellow = yellow, Green = green })
		end
	end
end

local function lamp(part: BasePart, on: boolean, color: Color3)
	local wantMaterial = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local wantColor = if on then color else OFF
	if part.Material ~= wantMaterial then
		part.Material = wantMaterial
	end
	if part.Color ~= wantColor then
		part.Color = wantColor
	end
end

local function updateSignals()
	local now = Workspace:GetServerTimeNow()
	local L = Config.Lights
	for _, head in signals do
		local state = Layout.LightState(head.Node, head.Axis, now, L.Cycle, L.Yellow, L.AllRed)
		lamp(head.Red, state == "Red", RED)
		lamp(head.Yellow, state == "Yellow", YELLOW)
		lamp(head.Green, state == "Green", GREEN)
	end
end

-- Police officers on foot: swing arms and legs with their running speed
local officerPhase: { [Model]: number } = {}
local function updateOfficers(dt: number)
	local folder = Workspace:FindFirstChild("Officers")
	if not folder then
		return
	end
	for _, officer in folder:GetChildren() do
		if not officer:IsA("Model") then
			continue
		end
		local root = officer.PrimaryPart
		local torso = officer:FindFirstChild("Torso")
		if not root or not torso then
			continue
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local phase = (officerPhase[officer] or 0) + dt * speed * 0.55
		officerPhase[officer] = phase
		local amp = math.clamp(speed / 16, 0, 1) * 0.9
		local swing = math.sin(phase) * amp
		local limbs: { [string]: number } = { ["Left Shoulder"] = 1, ["Right Shoulder"] = -1, ["Left Hip"] = -1, ["Right Hip"] = 1 }
		for name, sign in limbs do
			local joint = torso:FindFirstChild(name)
			if joint and joint:IsA("Motor6D") then
				joint.Transform = CFrame.Angles(0, 0, swing * sign)
			end
		end
	end
	for officer in officerPhase do
		if not officer.Parent then
			officerPhase[officer] = nil
		end
	end
end

function Visuals.Init()
	-- bikes right after the local ride step (EB_Ride), so the fork and swingarm are drawn against the
	-- chassis frame of the same render
	RunService:BindToRenderStep("EB_BikeVisuals", Enum.RenderPriority.Input.Value + 2, updateBikes)
	RunService.Stepped:Connect(function(_time: number, dt: number)
		updateCars(dt)
		updateOfficers(dt)
	end)
	BikeController.Started:Connect(function()
		if not wind then
			wind = Sound.Loop("Wind", nil)
		end
	end)
	BikeController.Stopped:Connect(function()
		local w = wind
		if w then
			w:Destroy()
			wind = nil
		end
	end)
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 30)
		if city then
			task.wait(1)
			collectSignals()
		end
		while true do
			updateSignals()
			task.wait(0.25)
		end
	end)
end

return Visuals
