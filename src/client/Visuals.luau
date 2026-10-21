--[[
	Visuals: everything that moves for looks only, on every client.

	Bikes: wheels spin with the bike's speed, bars turn with the rider's steering, pedals turn with
	their cadence (from the bike's attributes; the local rider's bike uses its exact physics state),
	and each bike's motor hums with its power.
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
local CarModel = require(Shared.Models.CarModel)

local BikeController = require(script.Parent.BikeController)
local Sound = require(script.Parent.Sound)

local Visuals = {}

local STUDS = Config.STUDS_PER_METER
local TAU = math.pi * 2

type BikeRig = {
	Root: BasePart,
	Rear: Motor6D?,
	Front: Motor6D?,
	Steer: Motor6D?,
	Barspin: number, -- 0..1 of a barspin (other riders' from the Barspin attribute)
	Crank: Motor6D?,
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
	local spec = BikeStats.Compute(bike, nil)
	local moto = not bike.Pedals
	local newRig: BikeRig = {
		Root = root,
		Rear = findMotor(model, "RearSpin"),
		Front = findMotor(model, "FrontSpin"),
		Steer = findMotor(model, "SteerJoint"),
		Barspin = 0,
		Crank = findMotor(model, "CrankSpin"),
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
		end
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

function Visuals.Init()
	RunService.Stepped:Connect(function(_time: number, dt: number)
		updateBikes(dt)
		updateCars(dt)
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
