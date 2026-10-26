--[[
	FX: riding effects, built from Roblox's own particle textures (rbxasset://, no uploaded assets).

	  Drift smoke   white tyre smoke from the rear wheel while sliding, thicker the deeper the
	                slip, plus dark skid marks laid on the ground behind it (they fade out)
	  Wheelie sparks sparks off the rear fender in a high wheelie, a shower when the front slams
	                down and when you bail
	  Hop puff      a puff of dust (or grit off-road) from both tyres on a bunny hop
	  Landing       a dust ring from both tyres, bigger the longer the air, with a ground shock ring
	                on big landings

	The local rider's effects come from its physics events; other riders' smoke and sparks follow
	their bikes' Drift and Wheelie attributes.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BikeController = require(script.Parent.BikeController)

local FX = {}

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local ROAD_DUST = Color3.fromRGB(196, 192, 184)
local DIRT_DUST = Color3.fromRGB(150, 116, 80)

type Rig = {
	Root: BasePart,
	Rear: Attachment,
	Front: Attachment,
	Smoke: ParticleEmitter,
	Sparks: ParticleEmitter,
	RearDust: ParticleEmitter,
	FrontDust: ParticleEmitter,
	LastMark: number,
	LastMarkPos: Vector3?,
}

local rigs: { [Model]: Rig } = {}
local marks: { BasePart } = {}
local MAX_MARKS = 220

local function emitter(parent: Attachment, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function dust(parent: Attachment, name: string): ParticleEmitter
	return emitter(parent, {
		Name = name,
		Texture = SMOKE,
		Rate = 0,
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(80, 25),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 4,
		Color = ColorSequence.new(ROAD_DUST),
		LightInfluence = 1,
		EmissionDirection = Enum.NormalId.Top,
	})
end

local function rigFor(model: Model): Rig?
	local existing = rigs[model]
	if existing then
		return existing
	end
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local half = root.Size.Z / 2
	local rear = Instance.new("Attachment")
	rear.Name = "FX_Rear"
	rear.Position = Vector3.new(0, 0.15, half)
	rear.Parent = root
	local front = Instance.new("Attachment")
	front.Name = "FX_Front"
	front.Position = Vector3.new(0, 0.15, -half)
	front.Parent = root
	local smoke = emitter(rear, {
		Name = "DriftSmoke",
		Texture = SMOKE,
		Rate = 0,
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(35, 35),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(0.4, 4), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.new(0, 1.6, 0),
		Drag = 1.5,
		RotSpeed = NumberRange.new(-40, 40),
		Rotation = NumberRange.new(0, 360),
		Color = ColorSequence.new(Color3.fromRGB(235, 235, 235)),
		LightInfluence = 0.9,
		EmissionDirection = Enum.NormalId.Back,
	})
	local sparks = emitter(rear, {
		Name = "Sparks",
		Texture = SPARK,
		Rate = 0,
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(30, 55),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) }),
		Transparency = NumberSequence.new(0),
		Acceleration = Vector3.new(0, -50, 0),
		Drag = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 110, 30)),
		LightEmission = 1,
		LightInfluence = 0,
		EmissionDirection = Enum.NormalId.Back,
	})
	local rig: Rig = {
		Root = root,
		Rear = rear,
		Front = front,
		Smoke = smoke,
		Sparks = sparks,
		RearDust = dust(rear, "RearDust"),
		FrontDust = dust(front, "FrontDust"),
		LastMark = 0,
		LastMarkPos = nil,
	}
	rigs[model] = rig
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
	return rig
end

local function setDustColor(rig: Rig, offroad: boolean)
	local c = ColorSequence.new(if offroad then DIRT_DUST else ROAD_DUST)
	rig.RearDust.Color = c
	rig.FrontDust.Color = c
end

-- A dark skid mark on the ground under the rear tyre, joining the last one
local function skid(rig: Rig)
	local p = rig.Rear.WorldPosition
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bikes = Workspace:FindFirstChild("Bikes")
	params.FilterDescendantsInstances = if bikes then { bikes } else {}
	local hit = Workspace:Raycast(p + Vector3.new(0, 1, 0), Vector3.new(0, -3, 0), params)
	if not hit then
		rig.LastMarkPos = nil
		return
	end
	local here = hit.Position + hit.Normal * 0.03
	local last = rig.LastMarkPos
	rig.LastMarkPos = here
	if not last or (here - last).Magnitude > 4 or (here - last).Magnitude < 0.2 then
		return
	end
	local mark = Instance.new("Part")
	mark.Name = "SkidMark"
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Material = Enum.Material.SmoothPlastic
	mark.Color = Color3.fromRGB(24, 24, 24)
	mark.Transparency = 0.35
	mark.Size = Vector3.new(0.35, 0.02, (here - last).Magnitude + 0.1)
	mark.CFrame = CFrame.lookAt((here + last) / 2, here)
	mark.Parent = Workspace
	table.insert(marks, mark)
	TweenService:Create(mark, TweenInfo.new(7, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	task.delay(7.2, function()
		mark:Destroy()
	end)
	if #marks > MAX_MARKS then
		local old = table.remove(marks, 1)
		if old then
			old:Destroy()
		end
	end
end

-- A flat ring that grows and fades on the ground (big landings)
local function shockRing(position: Vector3, size: number)
	local ring = Instance.new("Part")
	ring.Name = "LandingRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 255, 255)
	ring.Transparency = 0.5
	ring.Size = Vector3.new(0.1, 2, 2)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, size, size), Transparency = 1 }):Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

local function onEvent(event: any)
	local model = BikeController.Model
	local rig = if model then rigFor(model) else nil
	local s = BikeController.Physics
	if not rig or not s then
		return
	end
	setDustColor(rig, s.Offroad)
	local kind = event.Kind
	if kind == "Hop" then
		local n = math.floor(6 + (event.Value or 0.5) * 10)
		rig.RearDust:Emit(n)
		rig.FrontDust:Emit(n)
	elseif kind == "Land" then
		local air = event.Value or 0
		local n = math.floor(math.clamp(8 + air * 22, 8, 50))
		rig.RearDust:Emit(n)
		rig.FrontDust:Emit(n)
		if air > 0.9 then
			-- on the ground under the bike (the chassis rides below it by the sag)
			local physics = BikeController.Physics
			shockRing(if physics then physics.Position else rig.Root.Position, math.clamp(10 + air * 10, 12, 40))
		end
		if event.Text == "Crash" then
			rig.Sparks:Emit(40)
		end
	elseif kind == "WheelieEnd" then
		-- the front slamming down
		rig.Sparks:Emit(if event.Extra == 1 then 30 else 12)
	elseif kind == "Crash" then
		rig.Sparks:Emit(45)
		rig.RearDust:Emit(30)
		rig.FrontDust:Emit(30)
	end
end

local function update(_dt: number)
	local folder = Workspace:FindFirstChild("Bikes")
	if not folder then
		return
	end
	local now = os.clock()
	local mine = BikeController.Model
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local rig = rigFor(model)
		if not rig then
			continue
		end
		local slip, wheelie, speed, grounded, offroad = 0, 0, 0, true, false
		local s = BikeController.Physics
		if model == mine and s then
			slip = if s.DriftActive or math.abs(s.Slip) > 0.15 then s.Slip else 0
			wheelie = s.Wheelie
			speed = math.abs(s.Speed)
			grounded = s.Grounded
			offroad = s.Offroad
		else
			local d = model:GetAttribute("Drift")
			slip = if type(d) == "number" then d else 0
			wheelie = if model:GetAttribute("Wheelie") == true then 0.6 else 0
			speed = rig.Root.AssemblyLinearVelocity.Magnitude / Config.STUDS_PER_METER
		end
		-- drift smoke (white on tarmac, dust off-road) and skid marks
		local depth = math.clamp((math.abs(slip) - 0.12) / 0.8, 0, 1)
		if grounded and depth > 0 and speed > 2 then
			rig.Smoke.Rate = 20 + 90 * depth
			rig.Smoke.Color = ColorSequence.new(if offroad then DIRT_DUST else Color3.fromRGB(235, 235, 235))
			if not offroad and now - rig.LastMark > 0.06 then
				rig.LastMark = now
				skid(rig)
			end
		else
			rig.Smoke.Rate = 0
			rig.LastMarkPos = nil
		end
		-- sparks off the rear fender in a high wheelie at speed
		if grounded and wheelie > 0.62 and speed > 3 then
			rig.Sparks.Rate = 25 + 120 * math.clamp((wheelie - 0.62) / 0.35, 0, 1)
		else
			rig.Sparks.Rate = 0
		end
		-- a trail of dust riding fast off-road
		if model == mine and grounded and offroad and speed > 6 then
			rig.RearDust.Rate = math.clamp(speed * 1.5, 0, 30)
		else
			rig.RearDust.Rate = 0
		end
	end
end

function FX.Init()
	BikeController.Event:Connect(onEvent)
	RunService.Heartbeat:Connect(update)
end

return FX
