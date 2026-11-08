--[[
	Ambient: the life around the rider, all local to this client (nothing replicates, nothing
	collides or blocks a ray):
	  - airliners land on and take off from the airport's runway, on a schedule from the server
	    time so every player sees the same plane at the same moment, engines roaring as they pass;
	  - boats cruise the bay and the ocean on long loops, bobbing, a wake behind them;
	  - gulls wheel over South Beach;
	  - people (the standard avatar's size) walk the pavements of every block near the camera (more
	    in Ultra), round the corners or across to the next block, waiting at the kerb for the
	    lights; some sit on the benches and at the bus shelters;
	  - ambience: city hum in the built-up areas, waves by the beaches and the bay, birds over the
	    open land by day and crickets at night, blended by where the camera is.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.City.Layout)
local Airport = require(Shared.City.Airport)
local PartKit = require(Shared.PartKit)

local DayNight = require(script.Parent.DayNight)
local Graphics = require(script.Parent.Graphics)
local Sound = require(script.Parent.Sound)

local Ambient = {}

local K = Config.WORLD_SCALE
local KS = K * Config.CITY_SPREAD -- plan positions (City/Layout spreads them)
local LOCAL = { Collide = false, Query = false, Touch = false }
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }

local folder: Folder
local focus = Vector3.zero

-- A rigid group of parts moved as one: each part's frame relative to the root
type Rig = { Model: Model, Parts: { BasePart }, Offsets: { CFrame } }

local function rig(model: Model): Rig
	local parts, offsets = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(parts, d)
			table.insert(offsets, d.CFrame) -- built around the origin
		end
	end
	return { Model = model, Parts = parts, Offsets = offsets }
end

local function place(r: Rig, cf: CFrame)
	for i, part in r.Parts do
		part.CFrame = cf * r.Offsets[i]
	end
end

--------------------------------------------------------------------------------
-- Airliners
--------------------------------------------------------------------------------

local PLANE_CYCLE = 150 -- seconds: a landing, then a take-off
local APPROACH_TIME = 25
local APPROACH_RUN = 4000 -- studs out along the glide slope (3 degrees)
local LAND_SPEED = 160 -- studs a second at touchdown
local ROLL_DECEL = 8
local TAXI_SPEED = 20
local HOLD_TIME = 5
local TAKEOFF_ACCEL = 12
local ROTATE_SPEED = 170
local CLIMB = math.rad(8)

type Plane = { Rig: Rig, Livery: number, Jet: Sound }
local plane: Plane? = nil

local function buildPlane(livery: number): Plane
	local model = Airport.Airliner(nil, CFrame.identity, Airport.Liveries[livery])
	PartKit.Scale(model, K)
	local r = rig(model)
	model.Parent = folder
	local fuselage = model:FindFirstChild("Fuselage") :: BasePart
	local jet = Sound.Loop("Jet", fuselage)
	jet.RollOffMinDistance = 150
	jet.RollOffMaxDistance = 2600
	return { Rig = r, Livery = livery, Jet = jet }
end

-- Where the plane is at `t` seconds into its cycle (nil when it's off stage) and how loud
local function planeFrame(t: number): (CFrame?, number)
	local airport = Layout.Airport
	local ground = Layout.ROAD_Y
	local z = airport.RunwayZ
	local half = PLANE_CYCLE / 2
	if t < half then
		-- landing, westbound, onto the east end of the runway
		local touch = airport.RunwayX1 - 200 * K
		local west = Vector3.new(-1, 0, 0)
		if t < APPROACH_TIME then
			local f = 1 - t / APPROACH_TIME
			local p = Vector3.new(touch + APPROACH_RUN * f, ground + APPROACH_RUN * f * math.tan(math.rad(3)), z)
			return CFrame.lookAt(p, p + west) * CFrame.Angles(math.rad(3), 0, 0), 1
		end
		local s = t - APPROACH_TIME
		local rollTime = (LAND_SPEED - TAXI_SPEED) / ROLL_DECEL
		local x
		if s < rollTime then
			x = touch - (LAND_SPEED * s - 0.5 * ROLL_DECEL * s * s)
		else
			local rolled = LAND_SPEED * rollTime - 0.5 * ROLL_DECEL * rollTime * rollTime
			x = touch - rolled - TAXI_SPEED * (s - rollTime)
		end
		local p = Vector3.new(x, ground, z)
		local loud = if s < rollTime then 1 - 0.6 * s / rollTime else 0.4
		return CFrame.lookAt(p, p + west), loud
	end
	-- take-off, eastbound, from the west end
	local s = t - half - HOLD_TIME
	local start = airport.RunwayX0 + 150 * K
	local east = Vector3.new(1, 0, 0)
	if s < 0 then
		local p = Vector3.new(start, ground, z)
		return CFrame.lookAt(p, p + east), 0.5
	end
	local rollTime = ROTATE_SPEED / TAKEOFF_ACCEL
	if s < rollTime then
		local p = Vector3.new(start + 0.5 * TAKEOFF_ACCEL * s * s, ground, z)
		return CFrame.lookAt(p, p + east), 1
	end
	local airborne = s - rollTime
	local x0 = start + 0.5 * TAKEOFF_ACCEL * rollTime * rollTime
	local p = Vector3.new(x0 + ROTATE_SPEED * math.cos(CLIMB) * airborne, ground + ROTATE_SPEED * math.sin(CLIMB) * airborne, z)
	return CFrame.lookAt(p, p + east) * CFrame.Angles(CLIMB, 0, 0), 1
end

local function updatePlane()
	local now = Workspace:GetServerTimeNow()
	local cycle = math.floor(now / PLANE_CYCLE)
	local t = now - cycle * PLANE_CYCLE
	local half = math.floor(t / (PLANE_CYCLE / 2))
	local livery = (cycle * 2 + half) % #Airport.Liveries + 1
	local current = plane
	if current and current.Livery ~= livery then
		current.Rig.Model:Destroy()
		plane = nil
		current = nil
	end
	if not current then
		current = buildPlane(livery)
		plane = current
	end
	local p = current :: Plane
	local cf, loud = planeFrame(t)
	if cf then
		place(p.Rig, cf)
		p.Jet.Volume = Sound.BaseVolume("Jet") * loud
	end
end

--------------------------------------------------------------------------------
-- Boats
--------------------------------------------------------------------------------

-- Loops (ellipses, on the plan: spread like its positions) in open water: the north bay, the bay by the port, the ocean
-- off the beach, the south bay
local BOAT_LOOPS = {
	{ Center = Vector3.new(2110, 0, -1800), Rx = 450, Rz = 700, Speed = 34 },
	{ Center = Vector3.new(2240, 0, -420), Rx = 300, Rz = 330, Speed = 26 },
	{ Center = Vector3.new(3850, 0, -800), Rx = 300, Rz = 2800, Speed = 44 },
	{ Center = Vector3.new(3850, 0, -800), Rx = 260, Rz = 2700, Speed = -38 },
	{ Center = Vector3.new(1900, 0, 1900), Rx = 250, Rz = 700, Speed = 30 },
}
local HULLS = { Color3.fromRGB(244, 244, 240), Color3.fromRGB(30, 40, 60), Color3.fromRGB(200, 40, 40), Color3.fromRGB(240, 240, 236), Color3.fromRGB(20, 90, 140) }

type Boat = { Rig: Rig, Loop: typeof(BOAT_LOOPS[1]), Phase: number }
local boats: { Boat } = {}

-- A cabin cruiser built around the origin (bow along -Z, waterline at y = 0), in game studs
local function buildBoat(color: Color3): Model
	local model = PartKit.Model(nil, "Boat")
	local s = K
	PartKit.Box(model, "Hull", Vector3.new(8, 2.4, 22) * s, CFrame.new(0, 0.6 * s, 1 * s), color, Enum.Material.SmoothPlastic, LOCAL)
	-- (upside down: the deck runs on to the stem, the forefoot rakes up to it)
	PartKit.Wedge(model, "Bow", Vector3.new(8, 2.4, 7) * s, CFrame.new(0, 0.6 * s, -13.5 * s) * CFrame.Angles(0, 0, math.pi), color, Enum.Material.SmoothPlastic, LOCAL)
	PartKit.Box(model, "Deck", Vector3.new(7.4, 0.3, 20) * s, CFrame.new(0, 1.9 * s, 1 * s), Color3.fromRGB(196, 170, 130), Enum.Material.WoodPlanks, DECOR)
	PartKit.Box(model, "Cabin", Vector3.new(6, 3, 8) * s, CFrame.new(0, 3.4 * s, -1 * s), Color3.fromRGB(244, 244, 242), Enum.Material.SmoothPlastic, LOCAL)
	PartKit.Box(model, "Windshield", Vector3.new(5.6, 1.4, 0.3) * s, CFrame.new(0, 4.2 * s, -5.1 * s), Color3.fromRGB(40, 50, 60), Enum.Material.Glass, DECOR)
	local wake = PartKit.Box(model, "Wake", Vector3.new(9, 0.1, 30) * s, CFrame.new(0, 0.05 * s, 27 * s), Color3.fromRGB(240, 248, 250), Enum.Material.SmoothPlastic, DECOR)
	wake.Transparency = 0.45
	local spray = PartKit.Box(model, "BowSpray", Vector3.new(10, 0.1, 6) * s, CFrame.new(0, 0.05 * s, -15 * s), Color3.fromRGB(240, 248, 250), Enum.Material.SmoothPlastic, DECOR)
	spray.Transparency = 0.6
	return model
end

local function updateBoats(now: number)
	for _, boat in boats do
		local loop = boat.Loop
		local rx, rz = loop.Rx * KS, loop.Rz * KS
		local center = loop.Center * KS
		-- angular speed from the loop's mean radius, so the boat holds roughly `Speed` studs/s
		local omega = loop.Speed * K / ((rx + rz) / 2)
		local a = boat.Phase + now * omega
		local p = center + Vector3.new(math.cos(a) * rx, Layout.WATER_Y, math.sin(a) * rz)
		local tangent = Vector3.new(-math.sin(a) * rx, 0, math.cos(a) * rz) * math.sign(omega)
		local bob = math.sin(now * 1.7 + boat.Phase * 3) * 0.25
		local roll = math.sin(now * 1.1 + boat.Phase) * math.rad(2.5)
		local pitch = math.sin(now * 1.4 + boat.Phase * 2) * math.rad(1.5) + math.rad(3)
		place(boat.Rig, CFrame.lookAt(p + Vector3.new(0, bob, 0), p + tangent.Unit + Vector3.new(0, bob, 0)) * CFrame.Angles(pitch, 0, roll))
	end
end

--------------------------------------------------------------------------------
-- Gulls over South Beach
--------------------------------------------------------------------------------

type Gull = { Body: BasePart, WingL: BasePart, WingR: BasePart, Phase: number, Radius: number, Height: number, Center: Vector3 }
local gulls: { Gull } = {}
local GM = Config.CITY_STUDS_PER_METER -- gulls are life-size next to the city (sizes below in metres)

local function buildGull(center: Vector3, rng: Random): Gull
	local white = Color3.fromRGB(244, 244, 240)
	local body = PartKit.Box(folder, "Gull", Vector3.new(0.18, 0.18, 0.63) * GM, CFrame.identity, white, Enum.Material.SmoothPlastic, DECOR)
	local wingL = PartKit.Box(folder, "GullWing", Vector3.new(0.77, 0.03, 0.28) * GM, CFrame.identity, Color3.fromRGB(200, 204, 208), Enum.Material.SmoothPlastic, DECOR)
	local wingR = PartKit.Box(folder, "GullWing", Vector3.new(0.77, 0.03, 0.28) * GM, CFrame.identity, Color3.fromRGB(200, 204, 208), Enum.Material.SmoothPlastic, DECOR)
	return { Body = body, WingL = wingL, WingR = wingR, Phase = rng:NextNumber(0, math.pi * 2), Radius = rng:NextNumber(10, 32) * GM, Height = rng:NextNumber(10, 21) * GM, Center = center }
end

local function updateGulls(now: number)
	for _, gull in gulls do
		local a = gull.Phase + now * 6.3 * GM / gull.Radius
		local p = gull.Center + Vector3.new(math.cos(a) * gull.Radius, gull.Height + math.sin(now * 0.7 + gull.Phase) * 1.4 * GM, math.sin(a) * gull.Radius)
		local dir = Vector3.new(-math.sin(a), 0, math.cos(a))
		local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, math.rad(-18))
		local flap = math.sin(now * 7 + gull.Phase) * math.rad(28)
		gull.Body.CFrame = cf
		gull.WingL.CFrame = cf * CFrame.Angles(0, 0, flap) * CFrame.new(-0.42 * GM, 0, 0)
		gull.WingR.CFrame = cf * CFrame.Angles(0, 0, -flap) * CFrame.new(0.42 * GM, 0, 0)
	end
end

--------------------------------------------------------------------------------
-- People on the pavements
--------------------------------------------------------------------------------

local SHIRTS = { Color3.fromRGB(240, 240, 236), Color3.fromRGB(40, 110, 200), Color3.fromRGB(220, 70, 60), Color3.fromRGB(250, 200, 60), Color3.fromRGB(60, 160, 120), Color3.fromRGB(240, 140, 180), Color3.fromRGB(30, 30, 34), Color3.fromRGB(120, 200, 230) }
local PANTS = { Color3.fromRGB(40, 44, 60), Color3.fromRGB(70, 90, 140), Color3.fromRGB(200, 190, 170), Color3.fromRGB(30, 30, 32), Color3.fromRGB(110, 80, 60) }
local HAIR = { Color3.fromRGB(30, 22, 18), Color3.fromRGB(70, 46, 28), Color3.fromRGB(150, 110, 60), Color3.fromRGB(210, 180, 120), Color3.fromRGB(120, 120, 124), Color3.fromRGB(140, 50, 30) }
local SHOES = { Color3.fromRGB(245, 245, 245), Color3.fromRGB(26, 26, 28), Color3.fromRGB(90, 60, 40), Color3.fromRGB(200, 60, 60) }
local SKIN = { Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 140, 100), Color3.fromRGB(150, 100, 70), Color3.fromRGB(96, 64, 46), Color3.fromRGB(246, 210, 180) }
-- people are the standard avatar's size (Config.Avatar.Height; built at 5.15 studs)
local P = Config.Avatar.Height / 5.15
local WALK_SPEED = 5.5 * P
local RESPAWN_RANGE = 520 * Config.MAP_SCALE / 1.25 -- the map grows with the world

type Walker = {
	Parts: { BasePart }, -- torso, head, left leg, right leg, left arm, right arm
	Details: { { Part: BasePart, On: number, Offset: CFrame } }, -- hair, face, shoes, sleeves... riding on a part
	State: string, -- "Walk" a block's side, "Wait" at the kerb, "Cross" the road, "Sit", or "Gone"
	From: Vector3,
	To: Vector3,
	T: number,
	Length: number,
	Phase: number,
	Posed: boolean, -- (standing and sitting people are posed once)
	Block: Layout.Block?, -- the block whose side they're on, the corner they're heading for and which
	Corner: number, -- way round (+1 clockwise)
	Sense: number,
	Next: Layout.Block?, -- crossing to: that block, at that corner
	Entry: number,
	Light: number?, -- the crossing's lights and the axis of the road being crossed; when to give up
	Axis: string,
	Until: number,
	Seat: BasePart?, -- sitting: where, and on which place along it
	Place: number,
	Tick: number, -- frames counted, for posing far walkers less often
}
local walkers: { Walker } = {}
local walkRng = Random.new()
local POSE_NEAR = 120 * K -- studs from the camera within which people are posed every frame
local POSE_FAR = 260 * K

local function buildWalker(): Walker
	local shirt = SHIRTS[walkRng:NextInteger(1, #SHIRTS)]
	local pants = PANTS[walkRng:NextInteger(1, #PANTS)]
	local skin = SKIN[walkRng:NextInteger(1, #SKIN)]
	local shadow = Graphics.Current().Shadows
	local opts = { Collide = false, Query = false, Touch = false, Shadow = shadow }
	local parts: { BasePart } = {
		PartKit.Box(folder, "Torso", Vector3.new(2, 1.9, 1) * P, CFrame.identity, shirt, Enum.Material.Fabric, opts),
		PartKit.Box(folder, "Head", Vector3.new(1.15, 1.15, 1.15) * P, CFrame.identity, skin, Enum.Material.SmoothPlastic, opts),
		PartKit.Box(folder, "LeftLeg", Vector3.new(0.9, 2.1, 0.9) * P, CFrame.identity, pants, Enum.Material.Fabric, opts),
		PartKit.Box(folder, "RightLeg", Vector3.new(0.9, 2.1, 0.9) * P, CFrame.identity, pants, Enum.Material.Fabric, opts),
		PartKit.Box(folder, "LeftArm", Vector3.new(0.85, 1.9, 0.85) * P, CFrame.identity, skin, Enum.Material.SmoothPlastic, opts),
		PartKit.Box(folder, "RightArm", Vector3.new(0.85, 1.9, 0.85) * P, CFrame.identity, skin, Enum.Material.SmoothPlastic, opts),
	}
	-- details, each riding on one of the parts above (offsets in its frame; -Z is the face)
	local details: { { Part: BasePart, On: number, Offset: CFrame } } = {}
	local function add(on: number, name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?)
		local part = PartKit.Box(folder, name, size * P, CFrame.identity, color, material or Enum.Material.SmoothPlastic, opts)
		table.insert(details, { Part = part :: BasePart, On = on, Offset = CFrame.new(offset * P) })
	end
	local hair = HAIR[walkRng:NextInteger(1, #HAIR)]
	local long = walkRng:NextNumber() < 0.4
	add(2, "Hair", Vector3.new(1.22, 0.32, 1.22), Vector3.new(0, 0.48, 0.03), hair, Enum.Material.Fabric)
	add(2, "HairBack", Vector3.new(1.22, if long then 1.5 else 0.75, 0.25), Vector3.new(0, if long then -0.15 else 0.2, 0.52), hair, Enum.Material.Fabric)
	add(2, "EyeL", Vector3.new(0.14, 0.16, 0.04), Vector3.new(-0.24, 0.08, -0.58), Color3.fromRGB(20, 20, 24))
	add(2, "EyeR", Vector3.new(0.14, 0.16, 0.04), Vector3.new(0.24, 0.08, -0.58), Color3.fromRGB(20, 20, 24))
	add(2, "Brows", Vector3.new(0.7, 0.07, 0.04), Vector3.new(0, 0.3, -0.585), hair)
	add(2, "Nose", Vector3.new(0.14, 0.24, 0.1), Vector3.new(0, -0.08, -0.6), skin:Lerp(Color3.new(0, 0, 0), 0.08))
	add(2, "Mouth", Vector3.new(0.34, 0.05, 0.04), Vector3.new(0, -0.3, -0.58), skin:Lerp(Color3.fromRGB(120, 40, 40), 0.5))
	add(1, "Neck", Vector3.new(0.5, 0.35, 0.5), Vector3.new(0, 1.05, 0), skin)
	add(1, "Belt", Vector3.new(2.04, 0.18, 1.04), Vector3.new(0, -0.86, 0), Color3.fromRGB(40, 32, 26), Enum.Material.Leather)
	add(1, "Collar", Vector3.new(0.9, 0.14, 1.04), Vector3.new(0, 0.9, 0), shirt:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Fabric)
	local shoes = SHOES[walkRng:NextInteger(1, #SHOES)]
	for _, leg in { 3, 4 } do
		add(leg, "Shoe", Vector3.new(0.96, 0.32, 1.25), Vector3.new(0, -0.95, -0.15), shoes)
		add(leg, "Sole", Vector3.new(0.98, 0.08, 1.27), Vector3.new(0, -1.1, -0.15), Color3.fromRGB(235, 232, 225))
	end
	for _, arm in { 5, 6 } do
		add(arm, "Sleeve", Vector3.new(0.92, 0.75, 0.92), Vector3.new(0, 0.6, 0), shirt, Enum.Material.Fabric)
		add(arm, "Hand", Vector3.new(0.7, 0.4, 0.75), Vector3.new(0, -1.1, 0), skin)
	end
	local extra = walkRng:NextInteger(1, 5)
	if extra == 1 then -- cap
		local cap = SHIRTS[walkRng:NextInteger(1, #SHIRTS)]
		add(2, "Cap", Vector3.new(1.24, 0.3, 1.24), Vector3.new(0, 0.62, 0), cap, Enum.Material.Fabric)
		add(2, "Brim", Vector3.new(1.0, 0.07, 0.6), Vector3.new(0, 0.5, -0.85), cap, Enum.Material.Fabric)
	elseif extra == 2 then -- backpack
		add(1, "Backpack", Vector3.new(1.5, 1.5, 0.6), Vector3.new(0, 0.05, 0.78), PANTS[walkRng:NextInteger(1, #PANTS)], Enum.Material.Fabric)
	elseif extra == 3 then -- sunglasses
		add(2, "Shades", Vector3.new(0.95, 0.2, 0.06), Vector3.new(0, 0.08, -0.6), Color3.fromRGB(16, 16, 18), Enum.Material.Glass)
	elseif extra == 4 then -- shopping bag in the right hand
		add(6, "Bag", Vector3.new(0.35, 0.9, 0.8), Vector3.new(0, -1.6, 0), Color3.fromRGB(230, 220, 200), Enum.Material.Fabric)
	end
	return {
		Parts = parts,
		Details = details,
		State = "Gone",
		From = Vector3.zero,
		To = Vector3.zero,
		T = 0,
		Length = 0,
		Phase = walkRng:NextNumber(0, math.pi * 2),
		Posed = false,
		Block = nil,
		Corner = 0,
		Sense = 1,
		Next = nil,
		Entry = 0,
		Light = nil,
		Axis = "X",
		Until = 0,
		Seat = nil,
		Place = 1,
		Tick = walkRng:NextInteger(0, 3),
	}
end

local walkBlocks: { Layout.Block } = {}
local blockAt: { [string]: Layout.Block } = {}
local INSET = 8 * K -- the walking line, in from the block's edge (on the pavement)
local SIT_SHARE = 0.25 -- of the people near the camera, sitting on benches and at bus shelters
local WAIT_MAX = 25 -- seconds anyone waits for the green man before crossing anyway
-- a block's walking corners: 0 north-west, 1 north-east, 2 south-east, 3 south-west (north is -Z)
local MIRROR_X: { [number]: number } = { [0] = 1, [1] = 0, [2] = 3, [3] = 2 }
local MIRROR_Z: { [number]: number } = { [0] = 3, [1] = 2, [2] = 1, [3] = 0 }

local function corner(block: Layout.Block, i: number): Vector3
	local x = if i == 1 or i == 2 then block.MaxX - INSET else block.MinX + INSET
	local z = if i >= 2 then block.MaxZ - INSET else block.MinZ + INSET
	return Vector3.new(x, Layout.CURB_Y, z)
end

local function keyOf(grid: string, bx: number, bz: number): string
	return grid .. ":" .. bx .. ":" .. bz
end

-- The crossing's traffic lights (the grid node at that corner of the block), cached
local lightNodes: { [string]: number } = {}
local function lightAt(block: Layout.Block, i: number): number?
	local key = keyOf(block.Grid, block.Bx, block.Bz) .. ":" .. i
	local cached = lightNodes[key]
	if cached == nil then
		local x = if i == 1 or i == 2 then block.MaxX else block.MinX
		local z = if i >= 2 then block.MaxZ else block.MinZ
		local nodeId = Layout.NearestNode(Vector3.new(x, Layout.ROAD_Y, z))
		cached = if Layout.HasLights(Layout.Nodes[nodeId]) then nodeId else 0
		lightNodes[key] = cached
	end
	return if cached ~= 0 then cached else nil
end

local function setLeg(walker: Walker, from: Vector3, to: Vector3, state: string)
	walker.State = state
	walker.From, walker.To = from, to
	walker.Length = (to - from).Magnitude
	walker.T = 0
	walker.Posed = false
end

-- Walk a side of `block` from corner `i` to the next one round it (`sense` +1 clockwise, -1 not)
local function walkSide(walker: Walker, block: Layout.Block, i: number, sense: number)
	local j = (i + sense) % 4
	walker.Block = block
	walker.Corner = j
	walker.Sense = sense
	setLeg(walker, corner(block, i), corner(block, j), "Walk")
end

-- Seats near the camera: park benches and bus shelters in the city's Furniture (rescanned now and
-- then: they stream in and out), with who's sitting on which place along each
local seats: { BasePart } = {}
local sitting: { [BasePart]: { [number]: boolean } } = {}
local seatClock = 0

local function scanSeats()
	table.clear(seats)
	local city = Workspace:FindFirstChild("City")
	local furniture = city and city:FindFirstChild("Furniture")
	if not furniture then
		return
	end
	for _, model in furniture:GetChildren() do
		local name = model.Name
		local part = if name == "Bench" then model:FindFirstChild("Seat") elseif name == "BusStop" then model:FindFirstChild("Bench") else nil
		if part and part:IsA("BasePart") and (part.Position - focus).Magnitude < RESPAWN_RANGE * 0.6 then
			table.insert(seats, part)
		end
	end
end

local function places(seat: BasePart): number
	return math.max(1, math.floor(seat.Size.X / (4.4 * P / 1.26)))
end

local function leaveSeat(walker: Walker)
	local seat = walker.Seat
	if seat then
		local taken = sitting[seat]
		if taken then
			taken[walker.Place] = nil
			if next(taken) == nil then
				sitting[seat] = nil
			end
		end
	end
	walker.Seat = nil
end

-- Sit `walker` on a free place near the camera; false if there's none
local function sitDown(walker: Walker): boolean
	if #seats == 0 then
		return false
	end
	for _ = 1, 6 do
		local seat = seats[walkRng:NextInteger(1, #seats)]
		if seat.Parent then
			local taken = sitting[seat] or {}
			local place = walkRng:NextInteger(1, places(seat))
			if not taken[place] then
				taken[place] = true
				sitting[seat] = taken
				walker.Seat = seat
				walker.Place = place
				walker.State = "Sit"
				walker.Length = 1
				walker.Posed = false
				return true
			end
		end
	end
	return false
end

-- Somewhere near the camera: a seat now and then, otherwise partway along a block's side
local function respawn(walker: Walker)
	leaveSeat(walker)
	if walkRng:NextNumber() < SIT_SHARE and sitDown(walker) then
		return
	end
	local near: { Layout.Block } = {}
	for _, block in walkBlocks do
		local cx, cz = (block.MinX + block.MaxX) / 2, (block.MinZ + block.MaxZ) / 2
		if math.abs(cx - focus.X) < RESPAWN_RANGE * 0.8 and math.abs(cz - focus.Z) < RESPAWN_RANGE * 0.8 then
			table.insert(near, block)
		end
	end
	if #near == 0 then
		walker.State = "Gone"
		walker.Length = 0
		walker.Posed = false
		walker.Until = os.clock() + 1 -- (look again in a second)
		return
	end
	walkSide(walker, near[walkRng:NextInteger(1, #near)], walkRng:NextInteger(0, 3), if walkRng:NextNumber() < 0.5 then 1 else -1)
	walker.T = walkRng:NextNumber(0, walker.Length)
end

-- At the end of a side: round the corner, or wait at the kerb to cross to the next block on
local function atCorner(walker: Walker)
	local block = walker.Block :: Layout.Block
	local j = walker.Corner
	local dir = walker.To - walker.From
	local alongX = math.abs(dir.X) > math.abs(dir.Z)
	local dx = if alongX then (if dir.X > 0 then 1 else -1) else 0
	local dz = if alongX then 0 else (if dir.Z > 0 then 1 else -1)
	local nextBlock = blockAt[keyOf(block.Grid, block.Bx + dx, block.Bz + dz)]
	if nextBlock and walkRng:NextNumber() < 0.55 then
		local entry = if alongX then MIRROR_X[j] else MIRROR_Z[j]
		walker.Next = nextBlock
		walker.Entry = entry
		walker.Light = lightAt(block, j)
		-- (cars on the road being crossed run across the walk: it waits for their red)
		walker.Axis = if alongX then "Z" else "X"
		walker.Until = os.clock() + (if walker.Light then WAIT_MAX else walkRng:NextNumber(1.5, 4))
		setLeg(walker, corner(block, j), corner(nextBlock, entry), "Wait")
	else
		walkSide(walker, block, j, walker.Sense)
	end
end

local function hide(walker: Walker)
	for _, part in walker.Parts do
		part.CFrame = CFrame.new(0, -500, 0)
	end
	for _, detail in walker.Details do
		detail.Part.CFrame = CFrame.new(0, -500, 0)
	end
end

local function poseWalker(walker: Walker, now: number)
	local state = walker.State
	if state == "Gone" or walker.Length <= 0 then
		if not walker.Posed then
			hide(walker)
			walker.Posed = true
		end
		return
	end
	-- standing and sitting people are posed once
	if (state == "Wait" or state == "Sit") and walker.Posed then
		return
	end
	local parts = walker.Parts
	local root: CFrame
	local legSwing, armSwing = 0, 0
	local legs, arms = 0, 0 -- extra forward angle of the legs and arms (sitting)
	if state == "Sit" then
		local seat = walker.Seat :: BasePart
		local n = places(seat)
		local x = (walker.Place - (n + 1) / 2) * seat.Size.X / n
		-- the hips on the seat (a little back on it), facing out the front of it (its -Z)
		root = seat.CFrame * CFrame.new(x, seat.Size.Y / 2 + 0.45 * P - 2.1 * P, 0.3 * P)
		legs, arms = math.pi / 2, math.rad(35)
	else
		local dir = (walker.To - walker.From).Unit
		local p = if state == "Wait" then walker.From else walker.From + dir * walker.T
		if state == "Cross" and walker.T > INSET and walker.T < walker.Length - INSET then
			-- off the kerb: down on the road between the pavements
			p = Vector3.new(p.X, Layout.ROAD_Y, p.Z)
		end
		root = CFrame.lookAt(p, p + Vector3.new(dir.X, 0, dir.Z))
		if state ~= "Wait" then
			legSwing = math.sin(now * 7 + walker.Phase) * math.rad(26)
			armSwing = legSwing * 0.8
		end
	end
	local hip = root * CFrame.new(0, 2.1 * P, 0)
	parts[1].CFrame = root * CFrame.new(0, 3.05 * P, 0)
	parts[2].CFrame = root * CFrame.new(0, 4.6 * P, 0)
	parts[3].CFrame = hip * CFrame.new(-0.5 * P, 0, 0) * CFrame.Angles(legs + legSwing, 0, 0) * CFrame.new(0, -1.05 * P, 0)
	parts[4].CFrame = hip * CFrame.new(0.5 * P, 0, 0) * CFrame.Angles(legs - legSwing, 0, 0) * CFrame.new(0, -1.05 * P, 0)
	local shoulder = root * CFrame.new(0, 3.9 * P, 0)
	parts[5].CFrame = shoulder * CFrame.new(-1.43 * P, 0, 0) * CFrame.Angles(arms - armSwing, 0, 0) * CFrame.new(0, -0.9 * P, 0)
	parts[6].CFrame = shoulder * CFrame.new(1.43 * P, 0, 0) * CFrame.Angles(arms + armSwing, 0, 0) * CFrame.new(0, -0.9 * P, 0)
	for _, detail in walker.Details do
		detail.Part.CFrame = parts[detail.On].CFrame * detail.Offset
	end
	walker.Posed = true
end

local function updateWalkers(dt: number, now: number)
	local want = math.floor(Graphics.Current().Pedestrians * Graphics.Scale() + 0.5)
	seatClock -= dt
	if seatClock <= 0 then
		seatClock = 4
		scanSeats()
	end
	while #walkers < want do
		local walker = buildWalker()
		respawn(walker)
		table.insert(walkers, walker)
	end
	while #walkers > want do
		local walker = table.remove(walkers) :: Walker
		leaveSeat(walker)
		for _, part in walker.Parts do
			part:Destroy()
		end
		for _, detail in walker.Details do
			detail.Part:Destroy()
		end
	end
	local clock = os.clock()
	for _, walker in walkers do
		local state = walker.State
		local at = if state == "Sit" and walker.Seat then (walker.Seat :: BasePart).Position else walker.From + (walker.To - walker.From) * (if walker.Length > 0 then walker.T / walker.Length else 0)
		local far = (at - focus).Magnitude > RESPAWN_RANGE
		if state == "Gone" then
			if clock >= walker.Until then
				respawn(walker)
			end
		elseif far or (state == "Sit" and not (walker.Seat and (walker.Seat :: BasePart).Parent)) then
			respawn(walker)
		elseif state == "Walk" or state == "Cross" then
			walker.T += WALK_SPEED * dt
			if walker.T >= walker.Length then
				if state == "Walk" then
					atCorner(walker)
				else
					-- over: straight on along the next block's side, to its corner matching the one
					-- the crossing started from (crossing west off a north-west corner, the next block's
					-- north-east corner to its north-west one)
					local entry = walker.Entry
					walkSide(walker, walker.Next :: Layout.Block, entry, if (entry + 1) % 4 == walker.Corner then 1 else -1)
				end
			end
		elseif state == "Wait" then
			local go = clock >= walker.Until
			local light = walker.Light
			if light and not go then
				go = Layout.LightState(light, walker.Axis, now, Config.Lights.Cycle, Config.Lights.Yellow, Config.Lights.AllRed) == "Red"
			end
			if go then
				setLeg(walker, walker.From, walker.To, "Cross")
			end
		end
		-- (people near the camera are posed every frame, further ones every second or fourth: their
		-- walk is still worked out every frame, so they don't fall behind)
		walker.Tick += 1
		local d = (at - focus).Magnitude
		local every = if d < POSE_NEAR then 1 elseif d < POSE_FAR then 2 else 4
		if walker.Tick % every == 0 or walker.State == "Gone" then
			poseWalker(walker, now)
		end
	end
end

--------------------------------------------------------------------------------
-- Ambience
--------------------------------------------------------------------------------

type Bed = { Sound: Sound, Name: string, Level: number }
local beds: { [string]: Bed } = {}

local function rectDistance(r: Layout.Rect, x: number, z: number): number
	local dx = math.max(r.MinX - x, 0, x - r.MaxX)
	local dz = math.max(r.MinZ - z, 0, z - r.MaxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- How much of each ambience the camera's spot calls for (0..1)
local function ambienceMix(hour: number): { [string]: number }
	local x, z = focus.X, focus.Z
	local shore = math.huge
	for _, beach in Layout.Beaches do
		shore = math.min(shore, rectDistance(beach, x, z))
	end
	local bay = math.abs(x - Layout.SHORE_X)
	local surf = math.clamp(1 - shore / 260, 0, 1)
	surf = math.max(surf, 0.5 * math.clamp(1 - bay / 180, 0, 1))
	if Layout.InWater(x, z) then
		surf = math.max(surf, 0.7)
	end
	local built = Layout.IsBuiltUp(x, z, -60)
	local night = hour < 6 or hour > 20
	local high = math.clamp((focus.Y - 40) / 200, 0, 1) -- quieter streets from up on the freeway or in the air
	return {
		AmbientCity = if built then (1 - surf * 0.6) * (if night then 0.6 else 1) * (1 - high * 0.6) else 0,
		AmbientSurf = surf,
		AmbientNature = if not built and not night then 1 - surf * 0.7 else 0,
		AmbientNight = if night then (if built then 0.35 else 1) else 0,
	}
end

local function updateBeds(dt: number, hour: number)
	local mix = ambienceMix(hour)
	local ease = 1 - math.exp(-dt / 1.5)
	for name, target in mix do
		local bed = beds[name]
		if not bed then
			bed = { Sound = Sound.Loop(name), Name = name, Level = 0 }
			beds[name] = bed
		end
		local b = bed :: Bed
		b.Level += (target - b.Level) * ease
		b.Sound.Volume = Sound.BaseVolume(name) * b.Level
	end
end

--------------------------------------------------------------------------------

function Ambient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Ambient"
	folder.Parent = Workspace
	-- every block's pavements (homes and parks too, not just the busy districts)
	for _, block in Layout.Blocks do
		table.insert(walkBlocks, block)
		blockAt[keyOf(block.Grid, block.Bx, block.Bz)] = block
	end
	for i, loop in BOAT_LOOPS do
		local model = buildBoat(HULLS[(i - 1) % #HULLS + 1])
		model.Parent = folder
		table.insert(boats, { Rig = rig(model), Loop = loop, Phase = i * 1.7 })
	end
	local rng = Random.new(7)
	local beach = Layout.Places.Beach
	for _ = 1, 7 do
		table.insert(gulls, buildGull(Vector3.new(Layout.BEACH_X + 40 * K, 0, beach.Z), rng))
	end
	local gullClock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		focus = if camera then camera.Focus.Position else Vector3.zero
		local now = Workspace:GetServerTimeNow()
		updatePlane()
		updateBoats(now)
		updateGulls(now)
		updateWalkers(dt, now)
		updateBeds(dt, DayNight.Hour())
		-- the odd gull call when the camera's on the beach
		gullClock -= dt
		if gullClock <= 0 then
			gullClock = 6 + math.random() * 10
			if (focus - Vector3.new(Layout.BEACH_X, focus.Y, beach.Z)).Magnitude < 400 then
				Sound.Play("Gulls", focus + Vector3.new(math.random(-40, 40), 30, math.random(-40, 40)))
			end
		end
	end)
end

return Ambient
