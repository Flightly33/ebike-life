--[[
	Countryside: the open land between Miami's districts (Terrain grass at runtime, over the hidden
	OpenGround tiles Shore lays). Two golf courses (north of the turnpike, and in the Gables between
	Little Havana and Coral Way) with clubhouses, a palm nursery south of the Grove, pine rockland
	and hardwood hammocks of oaks and palms, palms along the turnpike's verges and rolling grass
	hills to ride. Nothing goes on a road, in the water, in a built-up area, on the airport or in
	the Everglades (Everglades.luau builds the marsh).
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Neighborhoods = require(script.Parent.Neighborhoods)
local PartKit = require(script.Parent.Parent.PartKit)

type Rect = LayoutModule.Rect

local Countryside = {}

local SMOOTH = Enum.Material.SmoothPlastic
local GRASS = Enum.Material.Grass
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

local FAIRWAY = Color3.fromRGB(104, 160, 64)
local STRIPE = Color3.fromRGB(118, 174, 72)
local FRINGE = Color3.fromRGB(96, 152, 62)
local GREEN = Color3.fromRGB(116, 184, 78)
local TEE = Color3.fromRGB(110, 170, 70)
local SAND = Color3.fromRGB(228, 212, 172)
local PATH = Color3.fromRGB(198, 194, 186)

-- Every road piece at any height (freeway piers stand on the ground under the deck), flattened
type Segment = { A: Vector3, B: Vector3, Half: number, MinX: number, MaxX: number, MinZ: number, MaxZ: number }
local segments: { Segment } = {}
for _, edge in Layout.Edges do
	local a = Layout.Nodes[edge.A].Position
	local b = Layout.Nodes[edge.B].Position
	local half = edge.Width / 2 + 12 -- the shoulders
	table.insert(segments, {
		A = Vector3.new(a.X, 0, a.Z),
		B = Vector3.new(b.X, 0, b.Z),
		Half = half,
		MinX = math.min(a.X, b.X) - half,
		MaxX = math.max(a.X, b.X) + half,
		MinZ = math.min(a.Z, b.Z) - half,
		MaxZ = math.max(a.Z, b.Z) + half,
	})
end

local MARSH = { Layout.Marsh }
local AIRPORT = { Layout.Airport.Rect }

-- Ground already taken by the countryside's own features (golf holes, the nursery, hills)
local reserved: { Rect } = {}

local function inRects(list: { Rect }, x: number, z: number, margin: number): boolean
	for _, r in list do
		if x > r.MinX - margin and x < r.MaxX + margin and z > r.MinZ - margin and z < r.MaxZ + margin then
			return true
		end
	end
	return false
end

local function nearRoad(x: number, z: number, margin: number): boolean
	local p = Vector3.new(x, 0, z)
	for _, s in segments do
		if x > s.MinX - margin and x < s.MaxX + margin and z > s.MinZ - margin and z < s.MaxZ + margin then
			local ab = s.B - s.A
			local t = math.clamp((p - s.A):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
			if (p - (s.A + ab * t)).Magnitude < s.Half + margin then
				return true
			end
		end
	end
	return false
end

-- True where something would sit on (or within `margin` of) a road, the water, a built-up area,
-- the airport, the Everglades, the map's edge or another countryside feature
function Countryside.Blocked(x: number, z: number, margin: number): boolean
	local edge = Layout.WORLD_HALF - 20
	if math.abs(x) > edge - margin or math.abs(z) > edge - margin then
		return true
	end
	if Layout.IsBuiltUp(x, z, margin) or inRects(MARSH, x, z, margin) or inRects(AIRPORT, x, z, margin + 30) then
		return true
	end
	if inRects(Layout.Water, x, z, margin + 6) or inRects(reserved, x, z, margin) then
		return true
	end
	return nearRoad(x, z, margin)
end

-- Is the whole line from a to b clear by `margin` (sampled every 12 studs)
local function lineClear(a: Vector3, b: Vector3, margin: number): boolean
	local n = math.max(1, math.ceil((b - a).Magnitude / 12))
	for k = 0, n do
		local p = a:Lerp(b, k / n)
		if Countryside.Blocked(p.X, p.Z, margin) then
			return false
		end
	end
	return true
end

-- A slash pine (the pine rockland's tree): a tall bare trunk and a small, open crown
local function pine(parent: Instance, base: Vector3, rng: Random, size: number?)
	local s = size or rng:NextNumber(0.9, 1.3)
	local model = PartKit.Model(parent, "Pine")
	local height = rng:NextNumber(30, 40) * s
	local lean = Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)) * s
	local top = base + Vector3.new(0, height, 0) + lean
	PartKit.Tube(model, "Trunk", base, top, 1.3 * s, Color3.fromRGB(110, 84, 64), Enum.Material.Wood)
	local needles = Color3.fromRGB(58, 96, 52):Lerp(Color3.fromRGB(80, 110, 56), rng:NextNumber(0, 1))
	for k = 1, rng:NextInteger(3, 5) do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1.5, 4.5) * s
		local y = rng:NextNumber(-5, 1) * s
		local d = rng:NextNumber(5, 8) * s
		local tone = if k == 1 then needles:Lerp(Color3.fromRGB(200, 220, 150), 0.12) else needles
		PartKit.Ellipsoid(model, "Leaves", Vector3.new(d, d * 0.55, d), CFrame.new(top + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)), tone, GRASS, NO_COLLIDE)
	end
	-- a couple of dead stubs down the trunk
	for _ = 1, 2 do
		local y = rng:NextNumber(0.45, 0.75)
		local from = base:Lerp(top, y)
		local a = rng:NextNumber(0, math.pi * 2)
		PartKit.Tube(model, "Limb", from, from + Vector3.new(math.cos(a) * 3, 1.2, math.sin(a) * 3) * s, 0.35 * s, Color3.fromRGB(96, 76, 60), Enum.Material.Wood, DECOR)
	end
	return model
end

-- A clump of saw palmetto (low fan palms under the pines)
local function palmetto(parent: Instance, base: Vector3, rng: Random)
	local tone = Color3.fromRGB(96, 128, 76):Lerp(Color3.fromRGB(130, 146, 90), rng:NextNumber(0, 1))
	for k = 1, 4 do
		local a = k * math.pi / 2 + rng:NextNumber(-0.4, 0.4)
		local dir = Vector3.new(math.cos(a), 0.45, math.sin(a)).Unit
		local center = base + dir * 2.4
		PartKit.Ellipsoid(parent, "Palmetto", Vector3.new(3.6, 0.3, 4.4), CFrame.lookAt(center, center + dir), tone, GRASS, DECOR)
	end
end

-- One tree of the woods: oaks, palms and pines (pine rockland mostly pines)
local function woodsTree(parent: Instance, p: Vector3, rng: Random, pines: number)
	local r = rng:NextNumber()
	if r < pines then
		pine(parent, p, rng)
		if rng:NextNumber() < 0.5 then
			palmetto(parent, p + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6)), rng)
		end
	elseif r < pines + (1 - pines) * 0.35 then
		Props.Palm(parent, p, rng, rng:NextNumber(0.85, 1.15))
	else
		Props.Tree(parent, p, rng, rng:NextNumber(1.1, 1.7))
	end
end

--------------------------------------------------------------------------------
-- Golf
--------------------------------------------------------------------------------

-- One hole from the tee to the green: a raised tee box, a striped fairway, the fringe and green
-- with a flag in the cup, bunkers by the green and along the fairway, and a cart path beside it
local function hole(parent: Instance, number: number, tee: Vector3, green: Vector3, width: number, side: number, rng: Random)
	local model = PartKit.Model(parent, "Hole" .. number)
	local dir = (green - tee).Unit
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local length = (green - tee).Magnitude
	local face = CFrame.lookAt(tee, tee + dir)
	local teeBox = PartKit.Box(model, "TeeBox", Vector3.new(16, 0.5, 12), face * CFrame.new(0, 0.25, 0), TEE, GRASS)
	teeBox:SetAttribute("Surface", "Grass")
	for _, sx in { -1, 1 } do
		PartKit.Ball(model, "TeeMarker", 0.8, (face * CFrame.new(sx * 4, 0.9, -3)).Position, Color3.fromRGB(240, 240, 236), SMOOTH, DECOR)
	end
	local sign = PartKit.Box(model, "HoleSign", Vector3.new(3, 2, 0.3), face * CFrame.new(-10, 2.6, 2), Color3.fromRGB(40, 70, 46), SMOOTH, NO_COLLIDE)
	PartKit.Sign(sign, Enum.NormalId.Back, tostring(number), Color3.new(1, 1, 1))
	PartKit.Post(model, "SignPost", 0.3, 1.6, (face * CFrame.new(-10, 0, 2)).Position, Color3.fromRGB(70, 60, 50), Enum.Material.Wood, DECOR)
	-- the fairway, with mowing stripes across it
	local from = tee + dir * 22
	local to = green - dir * 18
	local fairway = PartKit.Slab(model, "Fairway", from + Vector3.new(0, 0.12, 0), to + Vector3.new(0, 0.12, 0), width, 0.3, FAIRWAY, GRASS)
	fairway:SetAttribute("Surface", "Grass")
	local run = (to - from).Magnitude
	local stripes = math.floor(run / 24)
	for k = 0, stripes - 1, 2 do
		local c = from + dir * ((k + 0.5) * run / stripes)
		PartKit.Box(model, "Stripe", Vector3.new(width - 2, 0.06, run / stripes), CFrame.lookAt(c, c + dir) * CFrame.new(0, 0.14, 0), STRIPE, GRASS, DECOR)
	end
	-- fringe, green, cup and flag
	local fringe = PartKit.Post(model, "Fringe", 56, 0.38, green - Vector3.new(0, 0.2, 0), FRINGE, GRASS)
	fringe:SetAttribute("Surface", "Grass")
	local putting = PartKit.Post(model, "PuttingGreen", 44, 0.42, green - Vector3.new(0, 0.2, 0), GREEN, GRASS)
	putting:SetAttribute("Surface", "Grass")
	local cup = green + across * rng:NextNumber(-8, 8) + dir * rng:NextNumber(-6, 6)
	PartKit.Post(model, "Cup", 1.2, 0.05, cup + Vector3.new(0, 0.22, 0), Color3.fromRGB(20, 22, 20), SMOOTH, DECOR)
	PartKit.Post(model, "Pin", 0.22, 9, cup + Vector3.new(0, 0.22, 0), Color3.fromRGB(240, 240, 236), SMOOTH, NO_COLLIDE)
	local flag = PartKit.Box(model, "Flag", Vector3.new(0.08, 1.8, 2.8), CFrame.new(cup + Vector3.new(0, 8.2, 0) + dir * 1.4) * CFrame.lookAt(Vector3.zero, dir).Rotation, if number % 2 == 0 then Color3.fromRGB(220, 40, 40) else Color3.fromRGB(250, 210, 40), Enum.Material.Fabric, DECOR)
	flag:SetAttribute("Flag", true)
	-- bunkers: one or two by the green, one along the fairway on longer holes
	for k = 1, rng:NextInteger(1, 2) do
		local sgn = if k == 1 then side else -side
		local at = green + across * sgn * rng:NextNumber(26, 32) + dir * rng:NextNumber(-12, 4)
		local bunker = PartKit.Post(model, "Bunker", rng:NextNumber(14, 20), 0.3, at - Vector3.new(0, 0.2, 0), SAND, Enum.Material.Sand)
		bunker:SetAttribute("Surface", "Sand")
	end
	if length > 280 then
		local at = tee + dir * length * rng:NextNumber(0.55, 0.7) + across * -side * (width / 2 + 6)
		local bunker = PartKit.Box(model, "Bunker", Vector3.new(14, 0.3, 26), CFrame.lookAt(at, at + dir) * CFrame.new(0, -0.05, 0), SAND, Enum.Material.Sand)
		bunker:SetAttribute("Surface", "Sand")
	end
	-- the cart path down one side
	local off = across * side * (width / 2 + 14)
	local path = PartKit.Slab(model, "CartPath", tee + off + Vector3.new(0, 0.12, 0), green + off + Vector3.new(0, 0.12, 0), 7, 0.3, PATH, Enum.Material.Concrete)
	path:SetAttribute("Surface", "Sidewalk")
end

-- An electric golf cart parked at `cf` (front along -Z)
local function golfCart(parent: Instance, cf: CFrame)
	local model = PartKit.Model(parent, "GolfCart")
	local white = Color3.fromRGB(236, 236, 230)
	PartKit.Box(model, "Body", Vector3.new(4.2, 1.6, 8), cf * CFrame.new(0, 1.5, 0), white, SMOOTH)
	PartKit.Box(model, "Seat", Vector3.new(3.8, 0.8, 2.4), cf * CFrame.new(0, 2.7, 0.6), Color3.fromRGB(40, 40, 44), Enum.Material.Leather, DECOR)
	PartKit.Box(model, "Canopy", Vector3.new(4.4, 0.3, 6), cf * CFrame.new(0, 6.4, 0.4), white, SMOOTH, DECOR)
	for _, sz in { -2.2, 2.6 } do
		PartKit.Box(model, "Strut", Vector3.new(0.25, 3.8, 0.25), cf * CFrame.new(1.9, 4.4, sz), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, DECOR)
		PartKit.Box(model, "Strut", Vector3.new(0.25, 3.8, 0.25), cf * CFrame.new(-1.9, 4.4, sz), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, DECOR)
		for _, sx in { -1, 1 } do
			PartKit.Cylinder(model, "Tyre", 1.6, 0.8, cf * CFrame.new(sx * 2, 0.8, sz), Color3.fromRGB(28, 28, 30), Enum.Material.Rubber, DECOR)
		end
	end
	PartKit.Box(model, "Bag", Vector3.new(1.2, 3, 1.2), cf * CFrame.new(0.9, 3, 3.6), Color3.fromRGB(30, 60, 120), Enum.Material.Fabric, DECOR)
	return model
end

-- The clubhouse: Mediterranean revival (cream stucco, a clay-tile hip roof, arched windows and a
-- loggia on the front), a car park with carts lined up by the first tee. `cf` faces the road.
local function clubhouse(parent: Instance, cf: CFrame, name: string, rng: Random)
	local model = PartKit.Model(parent, "Clubhouse")
	local stucco = Color3.fromRGB(238, 226, 200)
	local w, d, h = 96, 44, 22
	PartKit.Box(model, "Body", Vector3.new(w, h, d), cf * CFrame.new(0, h / 2, 0), stucco, Enum.Material.Plaster)
	Neighborhoods.HipRoof(model, cf, w, d, h, Color3.fromRGB(176, 84, 52))
	local front = cf * CFrame.new(0, 0, -d / 2)
	Neighborhoods.ArchedWindows(model, front, w - 30, 14, 6, Color3.fromRGB(250, 246, 236))
	-- the loggia: columns and a flat roof over the entrance
	for k = -2, 2 do
		PartKit.Post(model, "Column", 1.6, 12, (front * CFrame.new(k * 7, 0, -8)).Position, stucco, Enum.Material.Plaster)
	end
	PartKit.Box(model, "LoggiaRoof", Vector3.new(34, 1.2, 10), front * CFrame.new(0, 12.6, -4.5), Color3.fromRGB(176, 84, 52), Enum.Material.ClayRoofTiles)
	PartKit.Box(model, "Door", Vector3.new(8, 9, 0.4), front * CFrame.new(0, 4.5, -0.2), Color3.fromRGB(90, 60, 40), Enum.Material.Wood, DECOR)
	local sign = PartKit.Box(model, "Sign", Vector3.new(40, 4, 0.4), front * CFrame.new(0, 17, -0.4), stucco, SMOOTH, NO_COLLIDE)
	PartKit.Sign(sign, Enum.NormalId.Front, name, Color3.fromRGB(40, 70, 46), nil, Enum.Font.Garamond)
	-- car park in front, palms either side
	local lot = PartKit.Box(model, "Lot", Vector3.new(w + 20, 0.3, 60), front * CFrame.new(0, 0.15, -44), Color3.fromRGB(88, 90, 94), Enum.Material.Asphalt)
	lot:SetAttribute("Surface", "Asphalt")
	for k = -4, 4 do
		PartKit.Box(model, "Bay", Vector3.new(0.4, 0.05, 16), front * CFrame.new(k * 11, 0.32, -56), Color3.fromRGB(236, 236, 230), SMOOTH, DECOR)
	end
	for _, sx in { -1, 1 } do
		Props.Palm(model, (front * CFrame.new(sx * (w / 2 + 14), 0, -6)).Position, rng)
		Props.Palm(model, (front * CFrame.new(sx * (w / 2 + 6), 0, -30)).Position, rng)
	end
	-- carts by the side door
	local side = cf * CFrame.new(w / 2 + 16, 0, 0)
	for k = 0, 4 do
		golfCart(model, side * CFrame.new(0, 0, -16 + k * 7) * CFrame.Angles(0, math.pi / 2, 0))
	end
	local pad = PartKit.Box(model, "CartPad", Vector3.new(16, 0.3, 44), side * CFrame.new(0, 0.15, 0), PATH, Enum.Material.Concrete)
	pad:SetAttribute("Surface", "Sidewalk")
	return model
end

-- A golf course in `area`: holes in lanes along its long side, alternating direction, trees and
-- palms between the lanes and dotted through the rough, the clubhouse at `club` facing `facing`
local function golfCourse(parent: Instance, name: string, area: Rect, club: CFrame, rng: Random)
	local folder = PartKit.Folder(parent, "Golf")
	folder:SetAttribute("Course", name)
	-- the clubhouse first, so the holes keep off it
	clubhouse(folder, club, name, rng)
	local c = club.Position
	table.insert(reserved, Layout.Rects.New(c.X - 90, c.X + 90, c.Z - 90, c.Z + 90))
	local alongX = area.MaxX - area.MinX > area.MaxZ - area.MinZ
	local long0, long1 = if alongX then area.MinX else area.MinZ, if alongX then area.MaxX else area.MaxZ
	local cross0, cross1 = if alongX then area.MinZ else area.MinX, if alongX then area.MaxZ else area.MaxX
	local function at(along: number, acrossAt: number): Vector3
		return if alongX then Vector3.new(along, 0, acrossAt) else Vector3.new(acrossAt, 0, along)
	end
	local perLane = math.max(1, math.floor((long1 - long0 - 80) / 330))
	local lanes = math.max(1, math.min(math.ceil(18 / perLane), math.floor((cross1 - cross0) / 110)))
	local laneW = (cross1 - cross0) / lanes
	local holes: { Rect } = {}
	local number = 0
	for lane = 0, lanes - 1 do
		local mid = cross0 + laneW * (lane + 0.5)
		local forward = lane % 2 == 0
		local pos = long0 + 40
		while pos < long1 - 180 and number < 18 do
			local finish = math.min(pos + rng:NextNumber(240, 420), long1 - 40)
			if finish - pos < 160 then
				break
			end
			local dog = rng:NextNumber(-1, 1) * math.min(30, laneW / 4)
			local a, b = at(pos, mid - dog * 0.5), at(finish, mid + dog)
			local tee, green = if forward then a else b, if forward then b else a
			local width = rng:NextNumber(50, 66)
			if lineClear(tee, green, width / 2 + 24) then
				number += 1
				local side = if lane % 2 == 0 then 1 else -1
				hole(folder, number, tee, green, width, side, rng)
				table.insert(holes, Layout.Rects.New(math.min(tee.X, green.X) - 40, math.max(tee.X, green.X) + 40, math.min(tee.Z, green.Z) - 40, math.max(tee.Z, green.Z) + 40))
				pos = finish + 40
			else
				pos += 60
			end
		end
	end
	-- trees: rows along the lane edges and clumps in the rough, never on a hole
	local function onHole(x: number, z: number): boolean
		for _, r in holes do
			-- the hole's own bounding box is generous for a diagonal hole; test the line instead
			if x > r.MinX and x < r.MaxX and z > r.MinZ and z < r.MaxZ then
				return true
			end
		end
		return false
	end
	for lane = 1, lanes - 1 do
		local edge = cross0 + laneW * lane
		for along = long0 + 30, long1 - 30, 34 do
			local p = at(along + rng:NextNumber(-8, 8), edge + rng:NextNumber(-10, 10))
			if not onHole(p.X, p.Z) and not Countryside.Blocked(p.X, p.Z, 6) then
				woodsTree(folder, p, rng, 0.25)
			end
		end
	end
	for _ = 1, 120 do
		local p = Vector3.new(rng:NextNumber(area.MinX, area.MaxX), 0, rng:NextNumber(area.MinZ, area.MaxZ))
		if not onHole(p.X, p.Z) and not Countryside.Blocked(p.X, p.Z, 6) then
			woodsTree(folder, p, rng, 0.3)
		end
	end
	table.insert(reserved, area)
end

--------------------------------------------------------------------------------
-- The palm nursery, the woods, the verges, the hills
--------------------------------------------------------------------------------

-- Rows of young palms in a fenced field with a shade house and a sales shed
local function nursery(parent: Instance, area: Rect, rng: Random)
	local folder = PartKit.Folder(parent, "Nursery")
	local cx, cz = (area.MinX + area.MaxX) / 2, (area.MinZ + area.MaxZ) / 2
	local w, d = area.MaxX - area.MinX, area.MaxZ - area.MinZ
	local ground = PartKit.Box(folder, "Field", Vector3.new(w, 0.3, d), CFrame.new(cx, 0.12, cz), Color3.fromRGB(136, 112, 82), Enum.Material.Ground)
	ground:SetAttribute("Surface", "Dirt")
	for x = area.MinX + 30, area.MaxX - 70, 20 do
		for z = area.MinZ + 20, area.MaxZ - 20, 22 do
			local p = Vector3.new(x + rng:NextNumber(-1, 1), 0.27, z + rng:NextNumber(-1, 1))
			PartKit.Post(folder, "Pot", 2.4, 1.6, p, Color3.fromRGB(40, 40, 42), SMOOTH, DECOR)
			Props.Palm(folder, p + Vector3.new(0, 1.4, 0), rng, rng:NextNumber(0.28, 0.42))
		end
	end
	-- the shade house (a black mesh roof on posts) and the shed, at the east end
	local shadeX = area.MaxX - 36
	for _, sz in { -1, 1 } do
		for k = -2, 2 do
			PartKit.Post(folder, "ShadePost", 0.5, 11, Vector3.new(shadeX + sz * 22, 0.27, cz + k * 20), Color3.fromRGB(150, 150, 150), Enum.Material.Metal, NO_COLLIDE)
		end
	end
	local shade = PartKit.Box(folder, "ShadeCloth", Vector3.new(46, 0.2, 84), CFrame.new(shadeX, 11.3, cz), Color3.fromRGB(26, 28, 26), Enum.Material.Fabric, DECOR)
	shade.Transparency = 0.35
	PartKit.Box(folder, "Shed", Vector3.new(26, 12, 18), CFrame.new(shadeX, 6.3, area.MinZ + 16), Color3.fromRGB(220, 214, 196), Enum.Material.WoodPlanks)
	PartKit.Box(folder, "ShedRoof", Vector3.new(30, 0.8, 22), CFrame.new(shadeX, 12.6, area.MinZ + 16), Color3.fromRGB(150, 156, 160), Enum.Material.CorrodedMetal, NO_COLLIDE)
	local sign = PartKit.Box(folder, "Sign", Vector3.new(30, 6, 0.4), CFrame.new(cx, 9, area.MinZ - 4), Color3.fromRGB(244, 240, 226), SMOOTH, NO_COLLIDE)
	PartKit.Sign(sign, Enum.NormalId.Front, "🌴 REDLAND PALM NURSERY", Color3.fromRGB(40, 100, 50))
	for _, sx in { -12, 12 } do
		PartKit.Post(folder, "SignPost", 0.6, 9, Vector3.new(cx + sx, 0, area.MinZ - 4), Color3.fromRGB(110, 84, 60), Enum.Material.Wood, NO_COLLIDE)
	end
	table.insert(reserved, area)
end

-- A rideable grass hill: a flat top and four slopes
local function hill(parent: Instance, spot: Vector3, h: number)
	local top = PartKit.Box(parent, "HillTop", Vector3.new(70, h, 70), CFrame.new(spot + Vector3.new(0, h / 2, 0)), Props.Palette.Grass, GRASS)
	top:SetAttribute("Surface", "Grass")
	for _, dir in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local edge = spot + Vector3.new(0, h, 0) + dir * 35
		local foot = edge + dir * (h * 3.2) - Vector3.new(0, h, 0)
		local slope = PartKit.Ramp(parent, "HillSide", foot, edge, 70, Props.Palette.Grass, GRASS)
		slope:SetAttribute("Surface", "Grass")
	end
	local reach = 35 + h * 3.2
	table.insert(reserved, Layout.Rects.New(spot.X - reach, spot.X + reach, spot.Z - reach, spot.Z + reach))
end

-- Where the hills go (open land in the north, between Little Havana and the airport, by the
-- turnpike's west side, and along the south edge)
Countryside.HILLS = {
	Vector3.new(1050, 0, -3200),
	Vector3.new(-2500, 0, -1600),
	Vector3.new(-1700, 0, -900),
	Vector3.new(-900, 0, 3950),
	Vector3.new(900, 0, 3950),
	Vector3.new(-2600, 0, 4000),
}

function Countryside.Build(city: Instance, rng: Random)
	table.clear(reserved)
	local folder = PartKit.Folder(city, "Countryside")

	-- the hills first (rideable, so they get exactly their spots)
	local hills = PartKit.Folder(folder, "Hills")
	for _, spot in Countryside.HILLS do
		local h = rng:NextNumber(14, 24)
		local reach = 35 + 24 * 3.2
		if Countryside.Blocked(spot.X, spot.Z, reach) then
			warn(string.format("[Countryside] hill at %.0f, %.0f is blocked; skipped", spot.X, spot.Z))
			continue
		end
		hill(hills, spot, h)
	end

	-- golf: the north course (lakes in play) and the Gables course
	golfCourse(folder, "BISCAYNE LINKS", Layout.Rects.New(-1100, 800, -4100, -2560), CFrame.new(0, 0, -2490) * CFrame.Angles(0, math.pi, 0), rng)
	golfCourse(folder, "GRANADA GOLF CLUB", Layout.Rects.New(-2840, -2196, 1140, 2100), CFrame.new(-2290, 0, 1240) * CFrame.Angles(0, -math.pi / 2, 0), rng)
	-- the north course's drive up from the turnpike
	local drive = PartKit.Slab(folder, "ClubDrive", Vector3.new(0, Layout.ROAD_Y, -Layout.RING_HALF - Layout.RING_WIDTH / 2), Vector3.new(0, Layout.ROAD_Y, -2430), 22, 0.4, Color3.fromRGB(88, 90, 94), Enum.Material.Asphalt)
	drive:SetAttribute("Surface", "Asphalt")

	nursery(folder, Layout.Rects.New(-2300, -1820, 3720, 3980), rng)

	-- woods: clumps of oaks, palms and pines over the open land
	local woods = PartKit.Folder(folder, "Woods")
	local placed = 0
	local tries = 0
	local W = Layout.WORLD_HALF
	while placed < 1100 and tries < 9000 do
		tries += 1
		local cx, cz = rng:NextNumber(-W, Layout.SHORE_X), rng:NextNumber(-W, W)
		if not Countryside.Blocked(cx, cz, 30) then
			-- pine rockland in the south-west, hammocks (oaks, palms) elsewhere
			local pines = if cz > 1000 and cx < -1000 then 0.75 elseif cz < -2000 then 0.45 else 0.2
			local n = rng:NextInteger(5, 14)
			for _ = 1, n do
				local p = Vector3.new(cx + rng:NextNumber(-60, 60), 0, cz + rng:NextNumber(-60, 60))
				if not Countryside.Blocked(p.X, p.Z, 6) then
					woodsTree(woods, p, rng, pines)
					placed += 1
				end
			end
		end
	end

	-- palms along the turnpike's verges and the country roads
	local verges = PartKit.Folder(folder, "Verges")
	for _, edge in Layout.Edges do
		if edge.Kind == "Highway" or edge.Kind == "Rural" then
			local a = Layout.Nodes[edge.A].Position
			local dir = edge.Direction
			local side = Vector3.new(-dir.Z, 0, dir.X)
			for along = 30, edge.Length - 30, 70 do
				for _, sgn in { -1, 1 } do
					if rng:NextNumber() < 0.45 then
						local p = Vector3.new(a.X, 0, a.Z) + dir * (along + rng:NextNumber(-10, 10)) + side * sgn * (edge.Width / 2 + 20)
						if not Countryside.Blocked(p.X, p.Z, -8) then
							Props.Palm(verges, p, rng, rng:NextNumber(0.85, 1.1))
						end
					end
				end
			end
		end
	end
end

return Countryside
