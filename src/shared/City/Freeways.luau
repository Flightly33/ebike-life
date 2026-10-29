--[[
	Freeways: I-95 and I-395 up on their piers, the on/off ramps, the I-95/I-395 junction, the
	descents to the turnpike at each end and the bridge across the bay, all from Layout's freeway
	nodes (Layout.I95, Layout.I395, Layout.Ramps).

	The riding surface is a thin asphalt slab whose top runs exactly along the road graph's line
	(the AI cars ray down onto it, bikes ride it); a concrete girder, piers, jersey barriers, lamps
	and green gantry signs dress it. Where a deck is under EMBANK_H above the ground it's a solid
	embankment instead of a viaduct.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder scales the finished city by WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local PartKit = require(script.Parent.Parent.PartKit)

local Freeways = {}

local C = Props.Palette
local ASPHALT = Enum.Material.Asphalt
local CONCRETE = Enum.Material.Concrete
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local MARK = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local CONCRETE_COLOR = Color3.fromRGB(198, 196, 190)
local BARRIER_COLOR = Color3.fromRGB(214, 212, 206)
local SIGN_GREEN = Color3.fromRGB(0, 110, 62)
local POLE_GREY = Color3.fromRGB(150, 154, 158)

local SURFACE = 0.6 -- the asphalt riding slab
local GIRDER = 3.2 -- concrete box girder under it
local EMBANK_H = 10 -- lower than this above the ground, a deck is an embankment
local BARRIER_H = 3.2
local BARRIER_W = 1.4
local PIER_STEP = 110 -- ~31 m spans
local LAMP_STEP = 150

local H = Layout.FREEWAY_Y
local FW = Layout.FREEWAY_WIDTH
local RW = Layout.RAMP_WIDTH
local LANE = (FW - 12) / 6 -- three lanes a side (Layout.LaneOffset)
local UP = Vector3.yAxis

local function node(id: number): Vector3
	return Layout.Nodes[id].Position
end

local function flatRight(a: Vector3, b: Vector3): Vector3
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	return Vector3.new(-flat.Z, 0, flat.X)
end

-- Somewhere a pier mustn't stand: a carriageway or pavement of either grid, the baywalk
local function onStreet(x: number, z: number): boolean
	local first, last = Layout.Line(0), Layout.Line(Layout.GRID_COUNT - 1)
	local margin = 4
	if z > first - 60 and z < last + 60 then
		for i = 0, Layout.GRID_COUNT - 1 do
			local w = Layout.LineWidthX(i)
			if math.abs(x - Layout.Line(i)) < w / 2 + (if w > Layout.STREET_WIDTH then Layout.AVENUE_SIDEWALK else Layout.STREET_SIDEWALK) + margin then
				return true
			end
		end
	end
	if x > first - 60 and x < last + 60 then
		for j = 0, Layout.GRID_COUNT - 1 do
			if math.abs(z - Layout.Line(j)) < Layout.LineWidthZ(j) / 2 + Layout.LineSidewalk(j) + margin then
				return true
			end
		end
	end
	-- Biscayne Blvd's east pavement and the baywalk out to the seawall
	if x > Layout.Line(Layout.BAY_INDEX) and x < Layout.SHORE_X + margin then
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------

-- The riding slab whose top runs from `a` to `b`, with the girder under it
local function deck(parent: Instance, a: Vector3, b: Vector3, width: number)
	PartKit.Slab(parent, "Deck", a, b, width, SURFACE, C.Asphalt, ASPHALT)
	local down = Vector3.new(0, SURFACE, 0)
	PartKit.Slab(parent, "Girder", a - down, b - down, width - 3, GIRDER, CONCRETE_COLOR, CONCRETE, NO_COLLIDE)
	-- a lip along both edges reads as the deck's fascia from the street
	local right = flatRight(a, b)
	for _, side in { -1, 1 } do
		local o = right * side * (width / 2 - 0.4)
		PartKit.Slab(parent, "Fascia", a + o - down, b + o - down, 0.8, GIRDER + 0.8, CONCRETE_COLOR:Lerp(Color3.new(1, 1, 1), 0.1), CONCRETE, NO_COLLIDE)
	end
end

-- A solid embankment: the riding slab on a concrete fill reaching the ground
local function embankment(parent: Instance, a: Vector3, b: Vector3, width: number)
	local low, high = a, b
	if low.Y > high.Y then
		low, high = b, a
	end
	PartKit.Slab(parent, "Deck", low, high, width, SURFACE, C.Asphalt, ASPHALT)
	local down = Vector3.new(0, SURFACE, 0)
	if high.Y - low.Y > 0.5 then
		PartKit.Ramp(parent, "Embankment", low - down, high - down, width - 0.3, CONCRETE_COLOR, CONCRETE)
	end
end

-- A pier under the deck point `at` (on the road surface): columns from the ground (or the bay
-- floor) up to a cap beam across the deck
local function pier(parent: Instance, at: Vector3, across: Vector3, width: number)
	local capH = 3.4
	local top = at.Y - SURFACE - GIRDER
	local bottom = if Layout.InWater(at.X, at.Z) then Layout.SEABED_Y else 0
	if top - capH - bottom < 2 then
		return
	end
	local model = PartKit.Model(parent, "Pier")
	local along = Vector3.new(across.Z, 0, -across.X)
	local capCenter = Vector3.new(at.X, top - capH / 2, at.Z)
	PartKit.Box(model, "PierCap", Vector3.new(width - 8, capH, 6), CFrame.lookAt(capCenter, capCenter + along), CONCRETE_COLOR, CONCRETE)
	local columnH = top - capH - bottom
	if width > 40 then
		for _, side in { -1, 1 } do
			local base = Vector3.new(at.X, bottom, at.Z) + across * side * (width / 2 - 10)
			PartKit.Post(model, "Column", 5.5, columnH, base, CONCRETE_COLOR, CONCRETE)
		end
	else
		PartKit.Post(model, "Column", 5, columnH, Vector3.new(at.X, bottom, at.Z), CONCRETE_COLOR, CONCRETE)
	end
end

-- Piers along a viaduct from `a` to `b`, off the streets
local function piers(parent: Instance, a: Vector3, b: Vector3, width: number)
	local length = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	local across = flatRight(a, b)
	local n = math.max(1, math.floor(length / PIER_STEP))
	for k = 0, n do
		local t = (k + 0.5) / (n + 1)
		local p = a:Lerp(b, t)
		if not onStreet(p.X, p.Z) then
			pier(parent, p, across, width)
		end
	end
end

-- A span of deck from `a` to `b` (road surface points): a viaduct on piers where it's high or over
-- the water, an embankment where it's low over land, split where it crosses EMBANK_H or the shore
local function span(parent: Instance, a: Vector3, b: Vector3, width: number, known: boolean?)
	local wetA, wetB = Layout.InWater(a.X, a.Z), Layout.InWater(b.X, b.Z)
	if known ~= nil then
		wetA, wetB = known, known
	end
	if wetA ~= wetB then
		-- find the shore between them
		local lo, hi = 0, 1
		for _ = 1, 16 do
			local mid = (lo + hi) / 2
			local p = a:Lerp(b, mid)
			if Layout.InWater(p.X, p.Z) == wetA then
				lo = mid
			else
				hi = mid
			end
		end
		local shore = a:Lerp(b, (lo + hi) / 2)
		span(parent, a, shore, width, wetA)
		span(parent, shore, b, width, wetB)
		return
	end
	if wetA then
		deck(parent, a, b, width)
		piers(parent, a, b, width)
		return
	end
	local ha, hb = a.Y, b.Y
	if ha >= EMBANK_H and hb >= EMBANK_H then
		deck(parent, a, b, width)
		piers(parent, a, b, width)
	elseif ha < EMBANK_H and hb < EMBANK_H then
		if math.abs(a.Y - b.Y) < 0.05 then
			PartKit.Slab(parent, "Deck", a, b, width, SURFACE, C.Asphalt, ASPHALT)
		else
			embankment(parent, a, b, width)
		end
	else
		local t = (EMBANK_H - ha) / (hb - ha)
		local m = a:Lerp(b, t)
		if ha < hb then
			embankment(parent, a, m, width)
			deck(parent, m, b, width)
			piers(parent, m, b, width)
		else
			deck(parent, a, m, width)
			piers(parent, a, m, width)
			embankment(parent, m, b, width)
		end
	end
end

-- A jersey barrier from `a` to `b` (on the road surface)
local function barrier(parent: Instance, a: Vector3, b: Vector3)
	if (b - a).Magnitude < 0.5 then
		return
	end
	local up = Vector3.new(0, BARRIER_H / 2, 0)
	PartKit.Bar(parent, "Barrier", a + up, b + up, BARRIER_W, BARRIER_H, BARRIER_COLOR, CONCRETE)
	-- the wider foot of the jersey profile
	local foot = Vector3.new(0, 0.5, 0)
	PartKit.Bar(parent, "BarrierFoot", a + foot, b + foot, BARRIER_W + 0.8, 1, BARRIER_COLOR, CONCRETE, MARK)
end

-- A barrier along a span `offset` to the right of a -> b, leaving out the gaps (ranges of the
-- coordinate the span runs along: `axis` "X" or "Z")
local function barrierRun(parent: Instance, a: Vector3, b: Vector3, offset: number, axis: string, gaps: { { number } }?)
	local right = flatRight(a, b)
	local ca = if axis == "X" then a.X else a.Z
	local cb = if axis == "X" then b.X else b.Z
	local lo, hi = math.min(ca, cb), math.max(ca, cb)
	local pieces = { { lo, hi } }
	local cut: { { number } } = gaps or {}
	for _, gap in cut do
		local out = {}
		for _, piece in pieces do
			if gap[2] <= piece[1] or gap[1] >= piece[2] then
				table.insert(out, piece)
			else
				if gap[1] > piece[1] then
					table.insert(out, { piece[1], gap[1] })
				end
				if gap[2] < piece[2] then
					table.insert(out, { gap[2], piece[2] })
				end
			end
		end
		pieces = out
	end
	for _, piece in pieces do
		local t0 = (piece[1] - ca) / (cb - ca)
		local t1 = (piece[2] - ca) / (cb - ca)
		barrier(parent, a:Lerp(b, t0) + right * offset, a:Lerp(b, t1) + right * offset)
	end
end

-- Paint on a deck (3D: follows slopes)
local function stripe(parent: Instance, a: Vector3, b: Vector3, offset: number, width: number, color: Color3)
	local right = flatRight(a, b)
	local lift = Vector3.new(0, 0.03, 0)
	local p0 = a + right * offset + lift
	local p1 = b + right * offset + lift
	local length = (p1 - p0).Magnitude
	if length < 0.5 then
		return
	end
	PartKit.Box(parent, "Line", Vector3.new(width, 0.05, length), PartKit.LookAt((p0 + p1) / 2, p1), color, SMOOTH, MARK)
end

local function dashed(parent: Instance, a: Vector3, b: Vector3, offset: number, dash: number, gap: number, width: number, color: Color3)
	local length = (b - a).Magnitude
	local count = math.floor((length + gap) / (dash + gap))
	if count <= 0 then
		return
	end
	local start = (length - (count * dash + (count - 1) * gap)) / 2
	for i = 0, count - 1 do
		local s0 = start + i * (dash + gap)
		stripe(parent, a:Lerp(b, s0 / length), a:Lerp(b, (s0 + dash) / length), offset, width, color)
	end
end

-- Lane markings for a freeway span (three lanes each way, shoulders, the median)
local function freewayPaint(parent: Instance, a: Vector3, b: Vector3, median: boolean)
	for _, side in { -1, 1 } do
		for lane = 1, 2 do
			dashed(parent, a, b, side * LANE * lane, 10.9, 32.7, 0.5, C.White) -- 10 ft dashes, 30 ft gaps
		end
		stripe(parent, a, b, side * LANE * 3, 0.6, C.White)
		stripe(parent, a, b, side * (if median then 1.6 else 0.6), 0.5, C.Yellow)
	end
end

-- A median barrier down the middle of a span, with gaps (as barrierRun)
local function median(parent: Instance, a: Vector3, b: Vector3, axis: string, gaps: { { number } }?)
	barrierRun(parent, a, b, 0, axis, gaps)
end

-- A twin-arm lamp standing on the median at `at`, arms out across the carriageways
local function medianLamp(parent: Instance, at: Vector3, across: Vector3)
	local model = PartKit.Model(parent, "FreewayLight")
	local base = at + Vector3.new(0, BARRIER_H, 0)
	local h = 30
	PartKit.Post(model, "Pole", 1.1, h, base, POLE_GREY, METAL)
	for _, side in { -1, 1 } do
		local tip = base + Vector3.new(0, h - 0.5, 0) + across * side * 11
		PartKit.Bar(model, "Arm", base + Vector3.new(0, h - 2.5, 0), tip, 0.5, 0.5, POLE_GREY, METAL, NO_COLLIDE)
		local head = PartKit.Box(model, "Head", Vector3.new(2.2, 0.8, 4.2), CFrame.lookAt(tip, tip + across * side), POLE_GREY, METAL, MARK)
		local _ = head
		PartKit.Box(model, "Globe", Vector3.new(1.6, 0.2, 3.2), CFrame.lookAt(tip - Vector3.new(0, 0.5, 0), tip - Vector3.new(0, 0.5, 0) + across * side), Color3.fromRGB(255, 226, 170), Enum.Material.Neon, MARK)
	end
	return model
end

local function lampsAlong(parent: Instance, a: Vector3, b: Vector3, skip: ((Vector3) -> boolean)?)
	local length = (b - a).Magnitude
	local across = flatRight(a, b)
	local n = math.floor(length / LAMP_STEP)
	for k = 1, n do
		local p = a:Lerp(b, k / (n + 1))
		if not skip or not skip(p) then
			medianLamp(parent, p, across)
		end
	end
end

-- A green gantry across a span at `at` (deck centre), `dir` the span's direction; boards are hung
-- over the lanes of either carriageway ({ Dir = 1 (travelling along dir) or -1, Offset across
-- those lanes, Text })
type Board = { Dir: number, Offset: number, Text: string }
local function gantry(parent: Instance, at: Vector3, dir: Vector3, width: number, boards: { Board })
	local model = PartKit.Model(parent, "Gantry")
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local h = 24
	for _, side in { -1, 1 } do
		local foot = at + right * side * (width / 2 - BARRIER_W / 2) + Vector3.new(0, BARRIER_H, 0)
		PartKit.Post(model, "Post", 1.6, h, foot, POLE_GREY, METAL)
	end
	local beamCenter = at + Vector3.new(0, BARRIER_H + h - 1, 0)
	PartKit.Box(model, "Truss", Vector3.new(width, 1.6, 1.6), CFrame.lookAt(beamCenter, beamCenter + dir), POLE_GREY, METAL, NO_COLLIDE)
	PartKit.Box(model, "Truss", Vector3.new(width, 1, 1), CFrame.lookAt(beamCenter - Vector3.new(0, 3, 0), beamCenter - Vector3.new(0, 3, 0) + dir), POLE_GREY, METAL, MARK)
	for _, board in boards do
		-- traffic going along `dir` keeps to its right
		local towards = dir * board.Dir
		local lanes = Vector3.new(-towards.Z, 0, towards.X)
		local c = at + lanes * board.Offset + Vector3.new(0, BARRIER_H + h - 6.5, 0) - towards * 1.2
		local part = PartKit.Box(model, "SignBoard", Vector3.new(19, 10, 0.4), CFrame.lookAt(c, c - towards), SIGN_GREEN, SMOOTH, NO_COLLIDE)
		PartKit.Sign(part, Enum.NormalId.Front, board.Text, Color3.fromRGB(250, 250, 248), nil, Enum.Font.GothamBold, 10)
		PartKit.Box(model, "SignEdge", Vector3.new(19.6, 10.6, 0.3), CFrame.lookAt(c + towards * 0.1, c), Color3.fromRGB(245, 245, 240), SMOOTH, MARK)
	end
	return model
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
function Freeways.Build(city: Instance)
	local folder = PartKit.Folder(city, "Freeways")
	local decks = PartKit.Folder(folder, "Decks")
	local paint = PartKit.Folder(folder, "Markings")
	local furniture = PartKit.Folder(folder, "Furniture")
	local half = FW / 2
	local edge = half - BARRIER_W / 2
	local junction = node(Layout.I95Junction)
	local ringEdge = Layout.RING_HALF - Layout.RING_WIDTH / 2

	-- where ramps meet I-95: per side, the z ranges where the deck's barrier opens
	local gapsBySide: { [number]: { { number } } } = { [-1] = {}, [1] = {} }
	local medianGaps: { { number } } = { { junction.Z - 80, junction.Z + 80 } }
	for _, ramp in Layout.Ramps do
		local top, join = node(ramp.Top), node(ramp.Join)
		local toward = if top.Z > node(ramp.Base).Z then 1 else -1
		local zEnd = join.Z + toward * 20
		table.insert(gapsBySide[ramp.Side], { math.min(top.Z, zEnd), math.max(top.Z, zEnd) })
		table.insert(medianGaps, { join.Z - 70, join.Z + 70 })
	end
	-- the junction opens the east side for I-395
	table.insert(gapsBySide[1], { junction.Z - half, junction.Z + half })

	-- I-95, north to south. A span's "side" in barrierRun is to the right of travel a -> b; going
	-- south (+Z) the right is west (-X), so the east barrier is at -edge.
	local chain = Layout.I95
	for k = 1, #chain - 1 do
		local a, b = node(chain[k]), node(chain[k + 1])
		-- the ground link to the turnpike starts at its kerb
		if math.abs(a.Z) >= Layout.RING_HALF - 1 then
			a = Vector3.new(a.X, a.Y, math.sign(a.Z) * ringEdge)
		end
		if math.abs(b.Z) >= Layout.RING_HALF - 1 then
			b = Vector3.new(b.X, b.Y, math.sign(b.Z) * ringEdge)
		end
		-- the junction square is its own plate
		if chain[k + 1] == Layout.I95Junction then
			b = Vector3.new(b.X, b.Y, junction.Z - half)
		elseif chain[k] == Layout.I95Junction then
			a = Vector3.new(a.X, a.Y, junction.Z + half)
		end
		span(decks, a, b, FW)
		local elevated = a.Y > Layout.ROAD_Y + 1 or b.Y > Layout.ROAD_Y + 1
		freewayPaint(paint, a, b, elevated)
		barrierRun(decks, a, b, edge, "Z", gapsBySide[-1]) -- west
		barrierRun(decks, a, b, -edge, "Z", gapsBySide[1]) -- east
		if elevated then
			median(decks, a, b, "Z", medianGaps)
			lampsAlong(furniture, a, b, function(p)
				for _, gap in medianGaps do
					if p.Z > gap[1] - 10 and p.Z < gap[2] + 10 then
						return true
					end
				end
				return false
			end)
		end
	end
	-- the junction plate (and its west barrier: the east side opens onto I-395)
	do
		local a = Vector3.new(junction.X, H, junction.Z - half)
		local b = Vector3.new(junction.X, H, junction.Z + half)
		deck(decks, a, b, FW)
		piers(decks, a, b, FW)
		barrier(decks, Vector3.new(junction.X - edge, H, junction.Z - half), Vector3.new(junction.X - edge, H, junction.Z + half))
		-- edge lines round the corner
		stripe(paint, a, b, LANE * 3, 0.6, C.White)
	end

	-- I-395, west to east: from the junction's edge over the streets and Biscayne Blvd, across
	-- the bay and down onto the island
	local east = Layout.I395
	for k = 1, #east - 2 do -- the last piece (onto 5th St) is a street
		local a, b = node(east[k]), node(east[k + 1])
		if k == 1 then
			a = Vector3.new(junction.X + half, a.Y, a.Z)
		end
		span(decks, a, b, FW)
		freewayPaint(paint, a, b, true)
		barrierRun(decks, a, b, edge, "X")
		barrierRun(decks, a, b, -edge, "X")
		local medianFrom = junction.X + half + 60
		median(decks, a, b, "X", { { -math.huge, medianFrom } })
		lampsAlong(furniture, a, b, function(p)
			return p.X < medianFrom + 20
		end)
	end

	-- Ramps: a road from the street into the block, an embankment rising into a viaduct, and a
	-- wider plate beside the deck where it merges
	for _, ramp in Layout.Ramps do
		local foot, base, top, join = node(ramp.Foot), node(ramp.Base), node(ramp.Top), node(ramp.Join)
		local toward = if top.Z > base.Z then 1 else -1
		local streetHalf = Layout.LineWidthZ(math.floor((foot.Z - Layout.GRID_MIN) / Layout.GRID_STEP + 0.5)) / 2
		local mouth = Vector3.new(foot.X, foot.Y, foot.Z + toward * streetHalf)
		PartKit.Slab(decks, "RampRoad", mouth, base, RW, SURFACE, C.Asphalt, ASPHALT)
		span(decks, base, top, RW)
		dashed(paint, mouth, top, 0, 10.9, 32.7, 0.5, C.Yellow)
		stripe(paint, mouth, top, RW / 2 - 1.4, 0.45, C.White)
		stripe(paint, mouth, top, -(RW / 2 - 1.4), 0.45, C.White)
		local side = ramp.Side
		local inner = foot.X - side * (RW / 2 - BARRIER_W / 2)
		local outer = foot.X + side * (RW / 2 - BARRIER_W / 2)
		barrier(decks, Vector3.new(inner, base.Y, base.Z), Vector3.new(inner, top.Y, top.Z))
		barrier(decks, Vector3.new(outer, base.Y, base.Z), Vector3.new(outer, top.Y, top.Z))
		-- the merge plate: from the deck's edge out to the ramp's outer edge, the ramp's top to
		-- just past the join
		local zEnd = join.Z + toward * 20
		local x0 = join.X + side * half
		local x1 = foot.X + side * RW / 2
		local plateA = Vector3.new((x0 + x1) / 2, H, top.Z)
		local plateB = Vector3.new((x0 + x1) / 2, H, zEnd)
		deck(decks, plateA, plateB, math.abs(x1 - x0))
		piers(decks, plateA, plateB, math.abs(x1 - x0))
		local zTaper = join.Z - toward * 30
		barrier(decks, Vector3.new(outer, H, top.Z), Vector3.new(outer, H, zTaper))
		barrier(decks, Vector3.new(outer, H, zTaper), Vector3.new(x0 - side * BARRIER_W / 2, H, zEnd))
		stripe(paint, Vector3.new(outer - side * 1.6, H, top.Z), Vector3.new(outer - side * 1.6, H, zTaper), 0, 0.5, C.White)
	end

	-- Signs (Layout's street names for the exits)
	local exitRow1 = Layout.Z_NAMES[Layout.RAMP_ROWS[1] + 2]
	local exitRow5 = Layout.Z_NAMES[Layout.RAMP_ROWS[2] + 1]
	local south = Vector3.new(0, 0, 1)
	gantry(furniture, Vector3.new(Layout.I95_X, H, junction.Z - 130), south, FW, {
		{ Dir = 1, Offset = 10, Text = "← I-395 EAST\nMiami Beach" },
		{ Dir = 1, Offset = 29, Text = "I-95 SOUTH ↓\nBrickell" },
	})
	gantry(furniture, Vector3.new(Layout.I95_X, H, junction.Z + 130), south, FW, {
		{ Dir = -1, Offset = 10, Text = "I-95 NORTH ↑\nWynwood" },
		{ Dir = -1, Offset = 29, Text = "I-395 EAST →\nMiami Beach" },
	})
	gantry(furniture, Vector3.new(Layout.I95_X, H, Layout.Line(Layout.RAMP_ROWS[1]) - 100), south, FW, {
		{ Dir = 1, Offset = 10, Text = "EXIT ↙\n" .. exitRow1 },
		{ Dir = 1, Offset = 29, Text = "EXIT ↘\n" .. exitRow1 },
	})
	gantry(furniture, Vector3.new(Layout.I95_X, H, Layout.Line(Layout.RAMP_ROWS[2] + 1) + 100), south, FW, {
		{ Dir = -1, Offset = 10, Text = "EXIT ↖\n" .. exitRow5 },
		{ Dir = -1, Offset = 29, Text = "EXIT ↗\n" .. exitRow5 },
	})
	local eastDir = Vector3.new(1, 0, 0)
	gantry(furniture, Vector3.new(Layout.Line(6) + 150, H, Layout.I395_Z), eastDir, FW, {
		{ Dir = 1, Offset = 19, Text = "I-395 EAST →\nMiami Beach" },
		{ Dir = -1, Offset = 10, Text = "I-95 NORTH ↑" },
		{ Dir = -1, Offset = 29, Text = "I-95 SOUTH ↓" },
	})
	gantry(furniture, Vector3.new(Layout.SHORE_X + 150, H, Layout.I395_Z), eastDir, FW, {
		{ Dir = 1, Offset = 19, Text = "SOUTH BEACH\n5th St  Ocean Dr" },
		{ Dir = -1, Offset = 19, Text = "DOWNTOWN MIAMI\nI-95 ←" },
	})
	return folder
end

Freeways.OnStreet = onStreet

return Freeways
