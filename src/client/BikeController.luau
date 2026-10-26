--[[
	BikeController: rides the local player's bike.

	When the player sits on their own bike (the server makes them its network owner), this runs
	Shared/BikePhysics every frame with the player's input against the real world (World), writes the
	result onto the bike's root part (the rider is welded to it, so they come along), drives the
	chase camera, and reports tricks and crashes to the server (Trick remote) and the rider's state
	to everyone (BikeState remote, 10 times a second).

	The battery lives here (time-compressed, see Config.Battery) and is remembered per spawned bike;
	charging stations refill it through the Charge remote.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bikes = require(Shared.Bikes)
local BikePhysics = require(Shared.BikePhysics)
local BikeStats = require(Shared.BikeStats)
local Config = require(Shared.Config)
local Modes = require(Shared.Modes)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Upgrades = require(Shared.Upgrades)

local BikeCamera = require(script.Parent.BikeCamera)
local Ragdoll = require(script.Parent.Ragdoll)
local Input = require(script.Parent.Input)
local Sound = require(script.Parent.Sound)
local State = require(script.Parent.State)
local World = require(script.Parent.World)

local BikeController = {}

BikeController.Started = Signal.new() -- (model)
BikeController.Stopped = Signal.new()
BikeController.Event = Signal.new() -- (BikePhysics.Event)
BikeController.ModeChanged = Signal.new() -- (modeName)

BikeController.Active = false
BikeController.Model = nil :: Model?
BikeController.Bike = nil :: Bikes.Bike?
BikeController.Spec = nil :: BikeStats.Spec?
BikeController.Physics = nil :: BikePhysics.State?
BikeController.Input = BikePhysics.Idle()
BikeController.ModeName = "TOUR"

local player = Players.LocalPlayer
local root: BasePart? = nil
local antiGravity: VectorForce? = nil
local batteries: { [Model]: number } = {}
local sendClock = 0
local lastImpact = 0
local bailing = false
local bailedAt = 0
local chargeLeft = 0
local warnedEmpty = false
local restoreCollide: { [BasePart]: boolean } = {}
local connections: { RBXScriptConnection } = {}

local function modeTable(): Modes.Mode
	local data = State.Get()
	local modes = if data then data.Modes else Modes.Defaults
	return modes[BikeController.ModeName] or Modes.Defaults.TOUR
end

function BikeController.SetMode(name: string)
	if not Modes.IsMode(name) or name == BikeController.ModeName then
		return
	end
	BikeController.ModeName = name
	Remotes.Event("SetMode"):FireServer(name)
	BikeController.ModeChanged:Fire(name)
	Sound.Play("Click", nil, 1.2, 0.6)
end

function BikeController.Kmh(): number
	local s = BikeController.Physics
	return if s then BikePhysics.Kmh(s) else 0
end

function BikeController.Charging(): boolean
	return chargeLeft > 0
end

function BikeController.BatteryFraction(): number
	local s, spec = BikeController.Physics, BikeController.Spec
	if not s or not spec or spec.BatteryWh <= 0 then
		return 1
	end
	return s.Battery / spec.BatteryWh
end

-- Range left at the current consumption, in km (shown under the battery bar)
function BikeController.RangeKm(): number
	local s, spec = BikeController.Physics, BikeController.Spec
	if not s or not spec then
		return 0
	end
	-- Wh per km riding at ~25 km/h in this mode (a typical city pace), drain-scaled like the battery
	local mode = modeTable()
	local motorW = if spec.Throttle then spec.MotorW * mode.MaxPower * 0.25 else math.min(spec.MotorW * mode.MaxPower, spec.RiderW * mode.Assist * 0.55)
	local whPerKm = (motorW / Config.Physics.RiderEfficiency) / 25 * Config.Battery.DrainScale
	if whPerKm <= 0 then
		return 999
	end
	return s.Battery / whPerKm
end

local function computeSpec(model: Model): (Bikes.Bike?, BikeStats.Spec?)
	local id = model:GetAttribute("BikeId")
	local bike = if type(id) == "string" then Bikes.Get(id) else nil
	if not bike then
		return nil, nil
	end
	local levels: Upgrades.Levels = {}
	for _, slot in Upgrades.Slots do
		local level = model:GetAttribute("Up_" .. slot.Name)
		if type(level) == "number" and level > 0 then
			levels[slot.Name] = level
		end
	end
	-- drawn to fit its rider: its wheels and wheelbase grow with it
	local size = model:GetAttribute("Scale")
	return bike, BikeStats.Scaled(BikeStats.Compute(bike, levels), if type(size) == "number" then size else 1)
end

local function sendTrick(kind: string, value: number?, extra: number?, text: string?)
	Remotes.Event("Trick"):FireServer(kind, value, extra, text)
end

local function onEvent(event: BikePhysics.Event)
	local kind = event.Kind
	local position = if root then root.Position else nil
	if kind == "Land" then
		local air = event.Value or 0
		if air >= Config.Physics.MinAirTime then
			sendTrick("Land", air, event.Extra, event.Text)
		end
		BikeCamera.Shake(math.clamp(air * 0.8, 0.2, 1.4))
		Sound.Play("Land", position, 1, math.clamp(air, 0.3, 1))
	elseif kind == "Flip" or kind == "Spin" or kind == "NoHander" then
		sendTrick(kind, event.Value)
	elseif kind == "WheelieEnd" then
		sendTrick("WheelieEnd", event.Value, event.Extra)
	elseif kind == "AirTrick" then
		sendTrick("AirTrick", event.Value, event.Extra, event.Text)
	elseif kind == "Spiked" then
		Sound.Play("Crash", position, 1.6, 0.6)
		BikeCamera.Shake(0.6)
	elseif kind == "Loop" then
		sendTrick("Loop", event.Value)
	elseif kind == "StoppieEnd" then
		sendTrick("StoppieEnd", event.Value, event.Extra)
	elseif kind == "DriftEnd" then
		sendTrick("DriftEnd", event.Value, event.Extra, event.Text)
	elseif kind == "Crash" then
		sendTrick("Crash", 0, 0, event.Text)
		BikeCamera.Shake(2)
		Sound.Play("Crash", position)
		-- off the bike: ragdoll, the server unseats us but keeps the ride
		local character = player.Character
		if character and root and not bailing then
			bailing = true
			bailedAt = os.clock()
			Remotes.Event("Bail"):FireServer()
			local s = BikeController.Physics
			Ragdoll.Start(character, if s then s.Velocity else root.AssemblyLinearVelocity)
		end
	elseif kind == "Recover" then
		if bailing then
			-- back on your feet where you landed; the bike stays where it slid to, and you walk over and
			-- get back on (its Enter prompt)
			bailing = false
			Ragdoll.Stop(player.Character)
			Remotes.Event("GotUp"):FireServer()
			BikeController.Stop()
			return
		end
	elseif kind == "Impact" then
		local now = os.clock()
		if (event.Text == "Cop" or event.Text == "Car") and now - lastImpact > 1 then
			lastImpact = now
			sendTrick("Impact", event.Value, 0, event.Text)
		end
		if (event.Value or 0) > 3 then
			BikeCamera.Shake(math.clamp((event.Value or 0) * 0.15, 0.2, 1.5))
		end
	elseif kind == "Hop" then
		Sound.Play("Land", position, 1.6, 0.3)
	elseif kind == "Fell" then
		Remotes.Event("DespawnBike"):FireServer()
	end
	BikeController.Event:Fire(event)
end

local function sendState(s: BikePhysics.State, spec: BikeStats.Spec)
	Remotes.Unreliable("BikeState"):FireServer({
		W = s.WheelieActive,
		Wt = math.floor(s.WheelieTime * 10) / 10,
		H = s.Hands,
		M = BikeController.ModeName,
		B = math.floor(BikeController.BatteryFraction() * 1000) / 1000,
		S = math.floor(s.Steer * 100) / 100,
		C = math.floor(s.Cadence),
		P = if spec.MotorW > 0 then math.floor(s.MotorPower / spec.MotorW * 100) / 100 else 0,
		A = not s.Grounded,
		Sf = s.Surface,
		Cr = s.Crash > 0,
		K = math.floor(BikePhysics.Kmh(s)),
		D = s.DriftActive,
		Tr = if s.TrickExt > 0.2 then s.TrickName else "",
		Bs = s.BarSpin > 0,
		St = s.StoppieActive,
		Sl = math.floor(s.Slip * 100) / 100,
	})
end

local function step(dt: number)
	local s, spec, model = BikeController.Physics, BikeController.Spec, BikeController.Model
	local part = root
	if not s or not spec or not model or not part or not part.Parent then
		return
	end
	-- Charging station top-up
	if chargeLeft > 0 then
		local rate = spec.BatteryWh / Config.Battery.ChargeSeconds
		s.Battery = math.min(spec.BatteryWh, s.Battery + rate * dt)
		chargeLeft = math.max(0, chargeLeft - dt)
		if s.Battery >= spec.BatteryWh then
			chargeLeft = 0
		end
	end

	Input.SetAirborne(not s.Grounded)
	local input = Input.Read()
	BikeController.Input = input
	local events = BikePhysics.Step(s, spec, modeTable(), input, World.Physics, dt)
	local cf = BikePhysics.GetCFrame(s, spec)
	part.CFrame = cf
	part.AssemblyLinearVelocity = s.Velocity
	part.AssemblyAngularVelocity = Vector3.zero
	local force = antiGravity
	if force then
		force.Force = Vector3.new(0, part.AssemblyMass * Workspace.Gravity, 0)
	end
	batteries[model] = s.Battery
	for _, event in events do
		onEvent(event)
	end
	if s.Battery <= 0 and not warnedEmpty then
		warnedEmpty = true
		BikeController.Event:Fire({ Kind = "BatteryEmpty" })
	elseif s.Battery > 0 then
		warnedEmpty = false
	end

	-- The camera sits behind the heading on the ground and the direction of travel in the air
	local travelYaw: number? = s.Yaw
	if not s.Grounded then
		travelYaw = if s.AirVelocity.Magnitude > 2 then BikePhysics.YawOf(s.AirVelocity.Unit) else nil
	end
	-- while limp the camera watches the body, not the bike
	local body = Ragdoll.Focus()
	if body then
		cf = CFrame.new(body) * (cf - cf.Position)
	end
	if bailing and os.clock() - bailedAt > 9 then
		-- never got back on (bike gone, too far): end the ride
		bailing = false
		Ragdoll.Stop(player.Character)
		BikeController.Stop()
		return
	end
	-- the chassis really moves on its suspension now: just a touch of buzz on top
	BikeCamera.Rough = if s.Offroad then 0.25 elseif s.Surface == "Sidewalk" then 0.08 else 0.03
	BikeCamera.Update(dt, cf, travelYaw, BikePhysics.Kmh(s), not s.Grounded)

	sendClock += dt
	if sendClock >= 1 / Config.Bikes.StateRate then
		sendClock = 0
		sendState(s, spec)
	end
end

local function setCharacterCollision(character: Model?, riding: boolean)
	if riding and character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				restoreCollide[d] = d.CanCollide
				d.CanCollide = false
			end
		end
	else
		for partToRestore, value in restoreCollide do
			if partToRestore.Parent then
				partToRestore.CanCollide = value
			end
		end
		restoreCollide = {}
	end
end

function BikeController.Stop()
	if not BikeController.Active then
		return
	end
	BikeController.Active = false
	game:GetService("RunService"):UnbindFromRenderStep("EB_Ride")
	for _, c in connections do
		c:Disconnect()
	end
	connections = {}
	if antiGravity then
		antiGravity:Destroy()
		antiGravity = nil
	end
	local character = player.Character
	setCharacterCollision(character, false)
	BikeCamera.Stop(character and character:FindFirstChildOfClass("Humanoid"))
	Input.SetRiding(false)
	BikeController.Model = nil
	BikeController.Physics = nil
	root = nil
	BikeController.Stopped:Fire()
end

function BikeController.Start(model: Model)
	BikeController.Stop()
	local bike, spec = computeSpec(model)
	local part = model.PrimaryPart
	if not bike or not spec or not part then
		return
	end
	root = part
	BikeController.Model = model
	BikeController.Bike = bike
	BikeController.Spec = spec
	BikeCamera.SetBikeScale(spec.Scale)
	local mode = player:GetAttribute("Mode")
	BikeController.ModeName = if Modes.IsMode(mode) then mode :: string else "TOUR"
	local battery = batteries[model] or spec.BatteryWh
	local s = BikePhysics.new(spec, part.CFrame, battery, player.UserId % 97)
	-- start level on the ground under the bike
	local look = part.CFrame.LookVector
	s.Yaw = BikePhysics.YawOf(Vector3.new(look.X, 0, look.Z).Unit)
	BikeController.Physics = s
	BikeController.Active = true

	local existing = part:FindFirstChild("EB_Lift")
	local attachment: Attachment
	if existing and existing:IsA("Attachment") then
		attachment = existing
	else
		attachment = Instance.new("Attachment")
		attachment.Name = "EB_Lift"
		attachment.Parent = part
	end
	local force = Instance.new("VectorForce")
	force.Name = "EB_AntiGravity"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Parent = part
	antiGravity = force

	setCharacterCollision(player.Character, true)
	World.Refresh()
	Input.SetRiding(true)
	BikeCamera.Start(part.CFrame)
	-- Tuning while riding (attributes from the server)
	table.insert(connections, model.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 3) == "Up_" then
			local _, newSpec = computeSpec(model)
			if newSpec then
				local fraction = BikeController.BatteryFraction()
				BikeController.Spec = newSpec
				if BikeController.Physics then
					BikeController.Physics.Battery = fraction * newSpec.BatteryWh
				end
			end
		end
	end))
	RunService:BindToRenderStep("EB_Ride", Enum.RenderPriority.Input.Value + 1, step)
	BikeController.Started:Fire(model)
end

local function hookCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seat: BasePart?)
		if active and seat and seat.Name == "Seat" then
			bailing = false
			local model = seat.Parent
			if model and model:IsA("Model") and model:GetAttribute("Owner") == player.UserId then
				BikeController.Start(model)
				return
			end
		end
		if not active and not bailing then
			BikeController.Stop()
		end
	end)
	humanoid.Died:Connect(function()
		bailing = false
		Ragdoll.Stop(character)
		BikeController.Stop()
	end)
end

function BikeController.Init()
	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	Input.Action:Connect(function(action: string, index: number?)
		if not BikeController.Active then
			return
		end
		if action == "ModeUp" then
			local nextMode = Modes.Next(BikeController.ModeName, 1)
			if nextMode == BikeController.ModeName then
				nextMode = "OFF"
			end
			BikeController.SetMode(nextMode)
		elseif action == "ModeDown" then
			BikeController.SetMode(Modes.Next(BikeController.ModeName, -1))
		elseif action == "Mode" and index then
			BikeController.SetMode(Modes.Order[index])
		elseif action == "Camera" then
			BikeCamera.Toggle()
		elseif action == "Bell" then
			Sound.Play("Bell", if root then root.Position else nil)
		end
	end)
	Remotes.Event("Charge").OnClientEvent:Connect(function()
		if BikeController.Active then
			chargeLeft = Config.Battery.ChargeSeconds
			Sound.Play("Charge")
		else
			-- parked: refill the remembered pack
			for model in batteries do
				if model:GetAttribute("Owner") == player.UserId then
					batteries[model] = nil
				end
			end
		end
	end)
	Remotes.Event("Teleport").OnClientEvent:Connect(function(target: any)
		local s, spec = BikeController.Physics, BikeController.Spec
		if typeof(target) ~= "CFrame" or not s or not spec then
			return
		end
		local battery = s.Battery
		local fresh = BikePhysics.new(spec, target, battery, player.UserId % 97)
		BikeController.Physics = fresh
	end)
	-- Forget batteries of bikes that are gone
	task.spawn(function()
		while true do
			task.wait(10)
			for model in batteries do
				if not model.Parent then
					batteries[model] = nil
				end
			end
		end
	end)
end

return BikeController
