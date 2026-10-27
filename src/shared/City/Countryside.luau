--[[
	Countryside: the land between the city grid and the turnpike (a U round the north, west and
	south, its ends on the bay) and beyond it to the map edge. Crop fields, farmsteads, a power line,
	woods of oaks and palms, a few wind turbines and rolling grass hills to ride. Nothing goes in the
	water or on the island.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local PartKit = require(script.Parent.Parent.PartKit)

local Countryside = {}

local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local CITY_EDGE = Layout.Line(Layout.GRID_COUNT - 1) + 40

-- the turnpike's centre line (Layout.RingNodes, in order)
local ring: { Vector3 } = {}
for _, id in Layout.RingNodes do
	local p = Layout.Nodes[id].Position
	table.insert(ring, Vector3.new(p.X, 0, p.Z))
end

local function segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- Signed distance from a point to the turnpike: negative inside the U (between it and the bay)
function Countryside.RingDistance(x: number, z: number): number
	local p = Vector3.new(x, 0, z)
	local best = math.huge
	for k = 1, #ring - 1 do
		best = math.min(best, segmentDistance(p, ring[k], ring[k + 1]))
	end
	-- inside: the polygon the U makes with the shore (an even-odd ray cast)
	local inside = false
	local n = #ring
	for k = 1, n do
		local a, b = ring[k], ring[(k % n) + 1]
		if (a.Z > z) ~= (b.Z > z) and x < a.X + (z - a.Z) / (b.Z - a.Z) * (b.X - a.X) then
			inside = not inside
		end
	end
	return if inside then -best else best
end

-- True where something would sit on (or too close to) a road, the city or the water
function Countryside.Blocked(x: number, z: number, margin: number): boolean
	if x > Layout.SHORE_X - 40 - margin then
		return true -- the baywalk, the bay and the island
	end
	if math.abs(x) < CITY_EDGE + margin and math.abs(z) < CITY_EDGE + margin then
		return true
	end
	if math.abs(Countryside.RingDistance(x, z)) < Layout.RING_WIDTH / 2 + 12 + margin then
		return true
	end
	-- the country roads out of the grid (north, south and west)
	local rural = Layout.RURAL_WIDTH / 2 + 10 + margin
	if math.abs(x) < rural and math.abs(z) < Layout.RING_HALF + 10 then
		return true
	end
	if math.abs(z) < rural and x < 0 and x > -Layout.RING_HALF - 10 then
		return true
	end
	-- I-95 down to the turnpike, and Biscayne Blvd's ends
	if math.abs(x - Layout.I95_X) < Layout.FREEWAY_WIDTH / 2 + 20 + margin and math.abs(z) < Layout.RING_HALF + 10 then
		return true
	end
	if math.abs(x - Layout.Line(Layout.BAY_INDEX)) < Layout.AVENUE_WIDTH / 2 + 20 + margin and math.abs(z) < Layout.RING_HALF + 10 then
		return true
	end
	return false
end

local FIELD_KINDS = {
	{ Name = "Ploughed", Base = Color3.fromRGB(118, 82, 54), Stripe = Color3.fromRGB(96, 64, 42), Material = Enum.Material.Ground, Surface = "Dirt" },
	{ Name = "Crop", Base = Color3.fromRGB(96, 138, 58), Stripe = Color3.fromRGB(72, 110, 44), Material = Enum.Material.Grass, Surface = "Grass" },
	{ Name = "Wheat", Base = Color3.fromRGB(206, 176, 92), Stripe = Color3.fromRGB(184, 152, 74), Material = Enum.Material.Grass, Surface = "Grass" },
}

local function field(parent: Instance, cx: number, cz: number, w: number, d: number, rng: Random)
	local kind = FIELD_KINDS[rng:NextInteger(1, #FIELD_KINDS)]
	local base = PartKit.Box(parent, kind.Name, Vector3.new(w, 0.3, d), CFrame.new(cx, 0.15, cz), kind.Base, kind.Material)
	base:SetAttribute("Surface", kind.Surface)
	local alongX = rng:NextNumber() < 0.5
	local rows = math.floor((if alongX then d else w) / 8)
	for i = 0, rows - 1 do
		local o = -((if alongX then d else w) / 2) + 4 + i * 8
		local size = if alongX then Vector3.new(w - 2, 0.35, 2.4) else Vector3.new(2.4, 0.35, d - 2)
		local pos = if alongX then Vector3.new(cx, 0.32, cz + o) else Vector3.new(cx + o, 0.32, cz)
		PartKit.Box(parent, "Furrow", size, CFrame.new(pos), kind.Stripe, kind.Material, DECOR)
	end
	if kind.Name == "Wheat" and rng:NextNumber() < 0.7 then
		for _ = 1, 4 do
			local p = Vector3.new(cx + rng:NextNumber(-w / 3, w / 3), 2.2, cz + rng:NextNumber(-d / 3, d / 3))
			PartKit.Cylinder(parent, "HayBale", 4.4, 4, CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color3.fromRGB(214, 184, 100), Enum.Material.Fabric)
		end
	end
end

local function farmstead(parent: Instance, cx: number, cz: number, facing: number, rng: Random)
	local model = PartKit.Model(parent, "Farm")
	local look = CFrame.new(cx, 0, cz) * CFrame.Angles(0, facing, 0)
	local red = Color3.fromRGB(160, 46, 38)
	PartKit.Box(model, "Barn", Vector3.new(40, 22, 60), look * CFrame.new(0, 11, 0), red, Enum.Material.WoodPlanks)
	local s = 44 / math.sqrt(2)
	PartKit.Box(model, "BarnRoof", Vector3.new(s, s, 62), look * CFrame.new(0, 22, 0) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(70, 70, 76), Enum.Material.CorrodedMetal)
	PartKit.Box(model, "BarnDoor", Vector3.new(16, 16, 0.4), look * CFrame.new(0, 8, -30.2), Color3.fromRGB(240, 236, 226), Enum.Material.WoodPlanks, DECOR)
	PartKit.Post(model, "Silo", 14, 44, (look * CFrame.new(30, 0, 14)).Position, Color3.fromRGB(200, 204, 208), Enum.Material.Metal)
	PartKit.Ball(model, "SiloCap", 14, (look * CFrame.new(30, 44, 14)).Position, Color3.fromRGB(150, 156, 160), Enum.Material.Metal)
	PartKit.Box(model, "FarmHouse", Vector3.new(28, 14, 22), look * CFrame.new(-44, 7, 10), Color3.fromRGB(244, 238, 220), Enum.Material.WoodPlanks)
	local hs = 25 / math.sqrt(2)
	PartKit.Box(model, "FarmRoof", Vector3.new(30, hs, hs), look * CFrame.new(-44, 14, 10) * CFrame.Angles(math.rad(45), 0, 0), Color3.fromRGB(96, 70, 56), Enum.Material.Slate)
	PartKit.Box(model, "Yard", Vector3.new(120, 0.2, 90), look * CFrame.new(-6, 0.1, 6), Color3.fromRGB(150, 130, 100), Enum.Material.Ground)
	for i = 0, 10 do
		PartKit.Post(model, "FencePost", 0.5, 4, (look * CFrame.new(-60 + i * 12, 0, 52)).Position, Color3.fromRGB(120, 90, 60), Enum.Material.Wood, NO_COLLIDE)
	end
	PartKit.Box(model, "FenceRail", Vector3.new(120, 0.4, 0.4), look * CFrame.new(0, 3, 52), Color3.fromRGB(120, 90, 60), Enum.Material.Wood, NO_COLLIDE)
	for _ = 1, 3 do
		Props.Tree(model, (look * CFrame.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-60, -40))).Position, rng, 1.2)
	end
end

-- A lattice pylon; returns the three wire attachment points
local function pylon(parent: Instance, base: Vector3): { Vector3 }
	local model = PartKit.Model(parent, "Pylon")
	local steel = Color3.fromRGB(150, 156, 160)
	local h = 70
	local legs = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local foot = base + Vector3.new(sx * 7, 0, sz * 7)
			local top = base + Vector3.new(sx * 1.5, h, sz * 1.5)
			PartKit.Bar(model, "Leg", foot, top, 0.8, 0.8, steel, Enum.Material.Metal)
			table.insert(legs, { foot, top })
		end
	end
	-- cross bracing
	for _, y in { 15, 32, 48 } do
		local t = y / h
		local w = 7 + (1.5 - 7) * t
		PartKit.Bar(model, "Brace", base + Vector3.new(-w, y, -w), base + Vector3.new(w, y, w), 0.4, 0.4, steel, Enum.Material.Metal, DECOR)
		PartKit.Bar(model, "Brace", base + Vector3.new(-w, y, w), base + Vector3.new(w, y, -w), 0.4, 0.4, steel, Enum.Material.Metal, DECOR)
	end
	local points = {}
	for i, y in { 52, 62 } do
		local span = if i == 1 then 18 else 12
		PartKit.Bar(model, "Arm", base + Vector3.new(-span, y, 0), base + Vector3.new(span, y, 0), 0.9, 0.9, steel, Enum.Material.Metal, DECOR)
		if i == 1 then
			table.insert(points, base + Vector3.new(-span + 1, y - 3, 0))
			table.insert(points, base + Vector3.new(span - 1, y - 3, 0))
		else
			table.insert(points, base + Vector3.new(0, y + 6, 0))
		end
	end
	PartKit.Bar(model, "Peak", base + Vector3.new(0, h, 0), base + Vector3.new(0, h + 8, 0), 0.6, 0.6, steel, Enum.Material.Metal, DECOR)
	return points
end

function Countryside.Build(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Countryside")
	local fields = PartKit.Folder(folder, "Fields")
	-- Fields on a loose grid inside the ring
	local step = 150
	local limit = Layout.RING_HALF - 60
	for x = -limit, limit, step do
		for z = -limit, limit, step do
			local w, d = rng:NextNumber(100, 135), rng:NextNumber(90, 130)
			local cx, cz = x + rng:NextNumber(-8, 8), z + rng:NextNumber(-8, 8)
			local margin = math.max(w, d) / 2
			if not Countryside.Blocked(cx, cz, margin) and Countryside.RingDistance(cx, cz) < -margin - 30 then
				if rng:NextNumber() < 0.72 then
					field(fields, cx, cz, w, d, rng)
				elseif rng:NextNumber() < 0.6 then
					for _ = 1, 3 do
						Props.Tree(fields, Vector3.new(cx + rng:NextNumber(-w / 2, w / 2), 0, cz + rng:NextNumber(-d / 2, d / 2)), rng, rng:NextNumber(1.0, 1.5))
					end
				end
			end
		end
	end
	-- Farmsteads
	for _, farm in { { -1700, -1150, 90 }, { -1700, 1150, 90 }, { -800, -1700, 0 }, { 900, 1700, 180 } } do
		if not Countryside.Blocked(farm[1], farm[2], 60) then
			farmstead(folder, farm[1], farm[2], math.rad(farm[3]), rng)
		end
	end

	-- Power line across the north fields
	local lines = PartKit.Folder(folder, "PowerLine")
	local previous: { Vector3 }? = nil
	local z = -1700
	for x = -1850, 1300, 220 do
		if not Countryside.Blocked(x, z, 12) then
			local points = pylon(lines, Vector3.new(x, 0, z))
			if previous then
				for i = 1, math.min(#previous, #points) do
					PartKit.Tube(lines, "Wire", previous[i], points[i], 0.25, Color3.fromRGB(40, 40, 42), Enum.Material.SmoothPlastic, DECOR)
				end
			end
			previous = points
		else
			previous = nil
		end
	end

	-- Woods beyond the ring and along its inside
	local woods = PartKit.Folder(folder, "Woods")
	local placed = 0
	local tries = 0
	while placed < 480 and tries < 6000 do
		tries += 1
		local x = rng:NextNumber(-Layout.WORLD_HALF + 20, Layout.WORLD_HALF - 20)
		local zz = rng:NextNumber(-Layout.WORLD_HALF + 20, Layout.WORLD_HALF - 20)
		local ring = Countryside.RingDistance(x, zz)
		local outside = ring > 60
		local verge = ring < -45 and ring > -120 and rng:NextNumber() < 0.25
		if (outside or verge) and not Countryside.Blocked(x, zz, 6) then
			if rng:NextNumber() < 0.3 then
				Props.Palm(woods, Vector3.new(x, 0, zz), rng, rng:NextNumber(0.9, 1.2))
			else
				Props.Tree(woods, Vector3.new(x, 0, zz), rng, rng:NextNumber(1.1, 1.8))
			end
			placed += 1
		end
	end

	-- Wind turbines on the hills outside the ring and along the east fields
	local wind = PartKit.Folder(folder, "WindFarm")
	local turbines = 0
	local attempts = 0
	while turbines < 5 and attempts < 400 do
		attempts += 1
		local x = rng:NextNumber(-Layout.WORLD_HALF + 80, Layout.WORLD_HALF - 80)
		local zz = rng:NextNumber(-Layout.WORLD_HALF + 80, Layout.WORLD_HALF - 80)
		if Countryside.RingDistance(x, zz) > 140 and not Countryside.Blocked(x, zz, 40) then
			Detail.WindTurbine(wind, Vector3.new(x, 0, zz), rng:NextNumber(150, 190), math.rad(200) + rng:NextNumber(-0.2, 0.2))
			turbines += 1
		end
	end

	-- Post-and-rail fences along the country roads, with hay bales in the verges
	local fences = PartKit.Folder(folder, "Fences")
	for _, edge in Layout.Edges do
		if edge.Kind == "Rural" then
			local a = Layout.Nodes[edge.A].Position
			local b = Layout.Nodes[edge.B].Position
			local dir = edge.Direction
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local start = a + dir * (Layout.AVENUE_WIDTH + 40)
			local finish = b - dir * (Layout.RING_WIDTH + 30)
			local length = (finish - start).Magnitude
			local pieces = math.floor(length / 120)
			for k = 0, pieces - 1 do
				local p0 = start + dir * (k * 120 + 6)
				local p1 = start + dir * (k * 120 + 114)
				for _, sgn in { -1, 1 } do
					local off = side * sgn * (edge.Width / 2 + 9)
					Detail.FarmFence(fences, Vector3.new(p0.X, 0, p0.Z) + off, Vector3.new(p1.X, 0, p1.Z) + off)
				end
				if rng:NextNumber() < 0.35 then
					local sgn = if rng:NextNumber() < 0.5 then -1 else 1
					Detail.HayBale(fences, Vector3.new(p0.X, 0, p0.Z) + dir * 50 + side * sgn * (edge.Width / 2 + 18), rng:NextNumber(0, math.pi))
				end
			end
		end
	end

	-- Rolling grass hills outside the ring (rideable slopes)
	local hills = PartKit.Folder(folder, "Hills")
	for _, spot in { Vector3.new(-2400, 0, 300), Vector3.new(-2350, 0, -1500), Vector3.new(-700, 0, -2450), Vector3.new(700, 0, 2450), Vector3.new(-2400, 0, 2300) } do
		local h = rng:NextNumber(14, 24)
		local top = PartKit.Box(hills, "HillTop", Vector3.new(70, h, 70), CFrame.new(spot + Vector3.new(0, h / 2, 0)), Props.Palette.Grass, Enum.Material.Grass)
		top:SetAttribute("Surface", "Grass")
		for _, dir in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			local edge = spot + Vector3.new(0, h, 0) + dir * 35
			local foot = edge + dir * (h * 3.2) - Vector3.new(0, h, 0)
			local slope = PartKit.Ramp(hills, "HillSide", foot, edge, 70, Props.Palette.Grass, Enum.Material.Grass)
			slope:SetAttribute("Surface", "Grass")
		end
	end
end

return Countryside
