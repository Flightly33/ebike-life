--[[
	Layout: the city as data. The Builder turns it into parts, the AI drivers route on its road graph,
	and the minimap draws it. Pure (no instances), deterministic.

	A 9x9 street grid 360 studs apart (lines at -1440 .. 1440) with two avenues crossing at the
	origin, a ring highway around it (a rounded square, half-size 1920) joined to the avenues by four
	country roads, and farmland in between. Blocks are assigned districts (DISTRICTS below, row = z
	from north): the original 6x6 core (Downtown, Park, the Jump and Loop parks, Flighty Mechanics,
	the Plaza, Police) with a ring of suburbs, midtown and industry around it. Workspace streaming
	keeps only the blocks near each player loaded.

	Everything is authored in Roblox's standard units (1 stud = 0.28 m, real-world sizes) and built at
	`K` times that size: the game uses K = Config.WORLD_SCALE (1.25), a little over life size
	next to the avatars and the bikes; the builders use Layout.Design (K = 1) and the Builder
	shrinks the finished city by WORLD_SCALE.
]]

local Config = require(script.Parent.Parent.Config)

export type District = "Suburb" | "Park" | "Downtown" | "Midtown" | "Industrial" | "Jump" | "Dealership" | "Plaza" | "Police"
export type Block = {
	Bx: number,
	Bz: number,
	District: District,
	-- Pad: the raised area between carriageways (pavements included)
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	-- Lot: the pad minus its pavements
	LotMinX: number,
	LotMaxX: number,
	LotMinZ: number,
	LotMaxZ: number,
}
export type RoadKind = "Avenue" | "Street" | "Highway" | "Rural"
export type Node = {
	Id: number,
	Position: Vector3, -- on the road surface
	Edges: { number },
	Grid: boolean, -- a street-grid intersection (square, may have lights)
	I: number?,
	J: number?,
}
export type Edge = {
	Id: number,
	A: number,
	B: number,
	Kind: RoadKind,
	Width: number,
	Lanes: number, -- per direction
	Length: number,
	Direction: Vector3, -- unit, A -> B
	Axis: string, -- "X", "Z" or "" (diagonal)
	Speed: number, -- m/s limit for AI cars
}
export type Light = "Green" | "Yellow" | "Red"

local function make(K: number)
	local Layout = {}

	Layout.ROAD_Y = 0.2 * K
	Layout.CURB_Y = 0.7 * K
	Layout.GRID_MIN = -1440 * K
	Layout.GRID_STEP = 360 * K
	Layout.GRID_COUNT = 9 -- lines per axis
	Layout.AVENUE_INDEX = 4 -- x = 0 and z = 0
	Layout.AVENUE_WIDTH = 50 * K -- 4 lanes of 12.5
	Layout.STREET_WIDTH = 26 * K -- 2 lanes of 13
	Layout.AVENUE_SIDEWALK = 14 * K
	Layout.STREET_SIDEWALK = 12 * K
	Layout.RING_HALF = 1920 * K
	Layout.RING_RADIUS = 360 * K
	Layout.RING_WIDTH = 50 * K
	Layout.RURAL_WIDTH = 26 * K
	Layout.WORLD_HALF = 2700 * K


	local DISTRICTS: { { District } } = {
		{ "Suburb", "Suburb", "Suburb", "Midtown", "Midtown", "Industrial", "Industrial", "Industrial" },
		{ "Suburb", "Suburb", "Suburb", "Midtown", "Midtown", "Industrial", "Industrial", "Industrial" },
		{ "Suburb", "Suburb", "Park", "Downtown", "Downtown", "Downtown", "Industrial", "Industrial" },
		{ "Suburb", "Suburb", "Park", "Downtown", "Downtown", "Downtown", "Midtown", "Midtown" },
		{ "Suburb", "Jump", "Jump", "Dealership", "Plaza", "Midtown", "Midtown", "Midtown" },
		{ "Suburb", "Suburb", "Suburb", "Midtown", "Midtown", "Police", "Midtown", "Suburb" },
		{ "Suburb", "Suburb", "Suburb", "Suburb", "Suburb", "Suburb", "Suburb", "Suburb" },
		{ "Suburb", "Suburb", "Suburb", "Suburb", "Suburb", "Suburb", "Suburb", "Suburb" },
	}

	function Layout.Line(index: number): number
		return Layout.GRID_MIN + Layout.GRID_STEP * index
	end

	function Layout.IsAvenue(index: number): boolean
		return index == Layout.AVENUE_INDEX
	end

	-- Carriageway width of grid line `index` (either axis)
	function Layout.LineWidth(index: number): number
		return if Layout.IsAvenue(index) then Layout.AVENUE_WIDTH else Layout.STREET_WIDTH
	end

	function Layout.LineSidewalk(index: number): number
		return if Layout.IsAvenue(index) then Layout.AVENUE_SIDEWALK else Layout.STREET_SIDEWALK
	end

	--------------------------------------------------------------------------------
	-- Blocks
	--------------------------------------------------------------------------------

	Layout.Blocks = {} :: { Block }
	for bz = 0, Layout.GRID_COUNT - 2 do
		for bx = 0, Layout.GRID_COUNT - 2 do
			local x0, x1 = Layout.Line(bx), Layout.Line(bx + 1)
			local z0, z1 = Layout.Line(bz), Layout.Line(bz + 1)
			local minX = x0 + Layout.LineWidth(bx) / 2
			local maxX = x1 - Layout.LineWidth(bx + 1) / 2
			local minZ = z0 + Layout.LineWidth(bz) / 2
			local maxZ = z1 - Layout.LineWidth(bz + 1) / 2
			table.insert(Layout.Blocks, {
				Bx = bx,
				Bz = bz,
				District = DISTRICTS[bz + 1][bx + 1],
				MinX = minX,
				MaxX = maxX,
				MinZ = minZ,
				MaxZ = maxZ,
				LotMinX = minX + Layout.LineSidewalk(bx),
				LotMaxX = maxX - Layout.LineSidewalk(bx + 1),
				LotMinZ = minZ + Layout.LineSidewalk(bz),
				LotMaxZ = maxZ - Layout.LineSidewalk(bz + 1),
			})
		end
	end

	function Layout.BlockAt(bx: number, bz: number): Block
		return Layout.Blocks[bz * (Layout.GRID_COUNT - 1) + bx + 1]
	end

	function Layout.FindDistrict(district: District): Block?
		for _, block in Layout.Blocks do
			if block.District == district then
				return block
			end
		end
		return nil
	end

	--------------------------------------------------------------------------------
	-- Road graph: nodes are intersections and bends, edges are straight road pieces
	--------------------------------------------------------------------------------



	Layout.Nodes = {} :: { Node }
	Layout.Edges = {} :: { Edge }

	local function addNode(position: Vector3, grid: boolean, i: number?, j: number?): number
		local id = #Layout.Nodes + 1
		Layout.Nodes[id] = { Id = id, Position = position, Edges = {}, Grid = grid, I = i, J = j }
		return id
	end

	local function addEdge(a: number, b: number, kind: RoadKind, width: number, lanes: number, speed: number)
		local pa, pb = Layout.Nodes[a].Position, Layout.Nodes[b].Position
		local delta = pb - pa
		local axis = ""
		if math.abs(delta.Z) < 1e-3 then
			axis = "X"
		elseif math.abs(delta.X) < 1e-3 then
			axis = "Z"
		end
		local id = #Layout.Edges + 1
		Layout.Edges[id] = {
			Id = id,
			A = a,
			B = b,
			Kind = kind,
			Width = width,
			Lanes = lanes,
			Length = delta.Magnitude,
			Direction = delta.Unit,
			Axis = axis,
			Speed = speed,
		}
		table.insert(Layout.Nodes[a].Edges, id)
		table.insert(Layout.Nodes[b].Edges, id)
	end

	-- Grid
	local gridNode: { [number]: { [number]: number } } = {}
	for i = 0, Layout.GRID_COUNT - 1 do
		gridNode[i] = {}
		for j = 0, Layout.GRID_COUNT - 1 do
			gridNode[i][j] = addNode(Vector3.new(Layout.Line(i), Layout.ROAD_Y, Layout.Line(j)), true, i, j)
		end
	end
	Layout.GridNode = gridNode

	for j = 0, Layout.GRID_COUNT - 1 do
		for i = 0, Layout.GRID_COUNT - 2 do
			local avenue = Layout.IsAvenue(j)
			addEdge(gridNode[i][j], gridNode[i + 1][j], if avenue then "Avenue" else "Street", Layout.LineWidth(j), if avenue then 2 else 1, if avenue then 13 else 11)
		end
	end
	for i = 0, Layout.GRID_COUNT - 1 do
		for j = 0, Layout.GRID_COUNT - 2 do
			local avenue = Layout.IsAvenue(i)
			addEdge(gridNode[i][j], gridNode[i][j + 1], if avenue then "Avenue" else "Street", Layout.LineWidth(i), if avenue then 2 else 1, if avenue then 13 else 11)
		end
	end

	-- Ring highway: a rounded square. Corner arcs are split into short straights.
	local RING_SEGMENTS_PER_CORNER = 6
	local ringNodes: { number } = {}
	local ringMid: { [string]: number } = {}
	do
		local h, r = Layout.RING_HALF, Layout.RING_RADIUS
		local inner = h - r
		-- corners in order going clockwise seen from above (+X east, -Z north): NE, SE, SW, NW
		local corners = {
			{ cx = inner, cz = -inner, start = -math.pi / 2 }, -- NE: from north side to east side
			{ cx = inner, cz = inner, start = 0 },
			{ cx = -inner, cz = inner, start = math.pi / 2 },
			{ cx = -inner, cz = -inner, start = math.pi },
		}
		local mids = { "E", "S", "W", "N" }
		for c, corner in corners do
			for k = 0, RING_SEGMENTS_PER_CORNER do
				local angle = corner.start + (math.pi / 2) * k / RING_SEGMENTS_PER_CORNER
				local x = corner.cx + math.cos(angle) * r
				local z = corner.cz + math.sin(angle) * r
				table.insert(ringNodes, addNode(Vector3.new(x, Layout.ROAD_Y, z), false))
			end
			-- midpoint of the side that follows this corner
			local midPos = ({
				E = Vector3.new(h, Layout.ROAD_Y, 0),
				S = Vector3.new(0, Layout.ROAD_Y, h),
				W = Vector3.new(-h, Layout.ROAD_Y, 0),
				N = Vector3.new(0, Layout.ROAD_Y, -h),
			})[mids[c]]
			local mid = addNode(midPos, false)
			ringMid[mids[c]] = mid
			table.insert(ringNodes, mid)
		end
		for k = 1, #ringNodes do
			local a = ringNodes[k]
			local b = ringNodes[k % #ringNodes + 1]
			addEdge(a, b, "Highway", Layout.RING_WIDTH, 2, 19)
		end
	end
	Layout.RingNodes = ringNodes

	-- Country roads from the avenue ends out to the ring
	local last = Layout.GRID_COUNT - 1
	local mid = Layout.AVENUE_INDEX
	addEdge(gridNode[mid][0], ringMid.N, "Rural", Layout.RURAL_WIDTH, 1, 15)
	addEdge(gridNode[mid][last], ringMid.S, "Rural", Layout.RURAL_WIDTH, 1, 15)
	addEdge(gridNode[0][mid], ringMid.W, "Rural", Layout.RURAL_WIDTH, 1, 15)
	addEdge(gridNode[last][mid], ringMid.E, "Rural", Layout.RURAL_WIDTH, 1, 15)

	-- Width of the widest road meeting at a node (for where a road piece starts)
	function Layout.NodeClearance(nodeId: number, alongAxis: string): number
		local node = Layout.Nodes[nodeId]
		if node.Grid and node.I and node.J then
			-- the crossing road's half width
			if alongAxis == "X" then
				return Layout.LineWidth(node.I) / 2
			else
				return Layout.LineWidth(node.J) / 2
			end
		end
		return 0
	end

	function Layout.OtherEnd(edge: Edge, nodeId: number): number
		return if edge.A == nodeId then edge.B else edge.A
	end

	function Layout.NearestNode(position: Vector3, filter: ((Node) -> boolean)?): number
		local best, bestDistance = 1, math.huge
		for _, node in Layout.Nodes do
			if not filter or filter(node) then
				local d = (Vector3.new(position.X, 0, position.Z) - Vector3.new(node.Position.X, 0, node.Position.Z)).Magnitude
				if d < bestDistance then
					best, bestDistance = node.Id, d
				end
			end
		end
		return best
	end

	-- Shortest path by road length (Dijkstra over ~80 nodes)
	function Layout.Path(from: number, to: number): { number }
		if from == to then
			return { from }
		end
		local dist: { [number]: number } = { [from] = 0 }
		local prev: { [number]: number } = {}
		local done: { [number]: boolean } = {}
		while true do
			local current, best = nil, math.huge
			for id, d in dist do
				if not done[id] and d < best then
					current, best = id, d
				end
			end
			if current == nil or current == to then
				break
			end
			done[current] = true
			for _, edgeId in Layout.Nodes[current].Edges do
				local edge = Layout.Edges[edgeId]
				local other = Layout.OtherEnd(edge, current)
				local d = best + edge.Length
				if not done[other] and d < (dist[other] or math.huge) then
					dist[other] = d
					prev[other] = current
				end
			end
		end
		if prev[to] == nil then
			return { from }
		end
		local path = { to }
		local node = to
		while node ~= from do
			node = prev[node]
			table.insert(path, 1, node)
		end
		return path
	end

	function Layout.EdgeBetween(a: number, b: number): Edge?
		for _, edgeId in Layout.Nodes[a].Edges do
			local edge = Layout.Edges[edgeId]
			if (edge.A == a and edge.B == b) or (edge.A == b and edge.B == a) then
				return edge
			end
		end
		return nil
	end

	-- A point in a driving lane on the right-hand side of travel from `from`. Lanes are counted from
	-- the centre line outwards: lane 1 is next to the centre line, the last lane is by the kerb.
	function Layout.LaneOffset(edge: Edge, lane: number): number
		local laneWidth = edge.Width / (edge.Lanes * 2)
		return laneWidth * (math.clamp(lane, 1, edge.Lanes) - 0.5)
	end

	function Layout.LanePoint(edge: Edge, from: number, t: number, lane: number): Vector3
		local a = Layout.Nodes[from].Position
		local b = Layout.Nodes[Layout.OtherEnd(edge, from)].Position
		local dir = (b - a).Unit
		local right = Vector3.new(-dir.Z, 0, dir.X)
		return a:Lerp(b, t) + right * Layout.LaneOffset(edge, lane)
	end

	--------------------------------------------------------------------------------
	-- Traffic lights: on every grid crossing of four roads. Phases come from the server clock so every
	-- client and the AI agree.
	--------------------------------------------------------------------------------
	function Layout.HasLights(node: Node): boolean
		if not node.Grid then
			return false
		end
		return #node.Edges >= 4 or (#node.Edges >= 3 and (node.I == Layout.AVENUE_INDEX or node.J == Layout.AVENUE_INDEX))
	end


	function Layout.LightState(nodeId: number, axis: string, time: number, cycle: number, yellow: number, allRed: number): Light
		local node = Layout.Nodes[nodeId]
		local offset = ((node.I or 0) * 5 + (node.J or 0) * 3) % cycle
		local half = cycle / 2
		local t = (time + offset) % cycle
		if axis == "Z" then
			t = (t + half) % cycle
		end
		if t < half - yellow - allRed then
			return "Green"
		elseif t < half - allRed then
			return "Yellow"
		end
		return "Red"
	end

	--------------------------------------------------------------------------------
	-- Places
	--------------------------------------------------------------------------------
	local dealership = Layout.FindDistrict("Dealership") :: Block
	local police = Layout.FindDistrict("Police") :: Block
	local jump = Layout.FindDistrict("Jump") :: Block
	local plaza = Layout.FindDistrict("Plaza") :: Block

	local function lotCenter(block: Block): Vector3
		return Vector3.new((block.LotMinX + block.LotMaxX) / 2, Layout.CURB_Y, (block.LotMinZ + block.LotMaxZ) / 2)
	end

	Layout.Places = {
		-- Spawn: the forecourt in front of the dealership, facing it (north)
		Spawn = Vector3.new((dealership.LotMinX + dealership.LotMaxX) / 2, Layout.CURB_Y, dealership.LotMaxZ - 50 * K),
		Dealership = lotCenter(dealership),
		Police = lotCenter(police),
		JumpPark = lotCenter(jump),
		Plaza = lotCenter(plaza),
		Downtown = lotCenter(Layout.BlockAt(4, 2)),
		Park = lotCenter(Layout.BlockAt(2, 2)),
		Industrial = lotCenter(Layout.BlockAt(6, 1)),
		Countryside = Vector3.new(0, Layout.ROAD_Y, -Layout.RING_HALF + 40 * K),
	}

	-- Teleports offered in the Menus panel
	Layout.Teleports = {
		{ Id = "Dealership", Name = "Flighty Mechanics" },
		{ Id = "JumpPark", Name = "Jump Park" },
		{ Id = "Downtown", Name = "Downtown" },
		{ Id = "Park", Name = "Central Park" },
		{ Id = "Plaza", Name = "City Plaza" },
		{ Id = "Industrial", Name = "Industrial" },
		{ Id = "Countryside", Name = "Countryside" },
	}

	-- Charging stations: kiosk positions (on pads, by the kerb)
	Layout.Chargers = {
		Vector3.new(dealership.LotMaxX - 20 * K, Layout.CURB_Y, dealership.LotMaxZ - 20 * K),
		Vector3.new(plaza.LotMinX + 20 * K, Layout.CURB_Y, plaza.LotMaxZ - 20 * K),
		Vector3.new(jump.LotMaxX - 15 * K, Layout.CURB_Y, jump.LotMaxZ - 15 * K),
		Vector3.new(Layout.BlockAt(2, 2).LotMaxX - 15 * K, Layout.CURB_Y, Layout.BlockAt(2, 2).LotMaxZ - 15 * K),
		Vector3.new(Layout.BlockAt(4, 2).LotMinX + 15 * K, Layout.CURB_Y, Layout.BlockAt(4, 2).LotMaxZ - 8 * K),
		Vector3.new(Layout.BlockAt(6, 1).LotMinX + 20 * K, Layout.CURB_Y, Layout.BlockAt(6, 1).LotMaxZ - 20 * K),
		Vector3.new(Layout.BlockAt(1, 5).LotMaxX - 15 * K, Layout.CURB_Y, Layout.BlockAt(1, 5).LotMinZ + 15 * K),
		Vector3.new(police.LotMinX + 20 * K, Layout.CURB_Y, police.LotMinZ + 20 * K),
		Vector3.new(40 * K, Layout.ROAD_Y, -Layout.RING_HALF + 70 * K), -- country stop on the north road
	}

	-- Where pursuing cops enter the map
	Layout.PoliceSpawn = gridNode[5][5]

	return Layout
end

local Layout = make(Config.WORLD_SCALE)
-- The same city in design units (K = 1), for the builders
;(Layout :: any).Design = make(1)

return Layout
