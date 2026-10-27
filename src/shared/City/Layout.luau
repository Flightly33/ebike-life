--[[
	Layout: the city as data. The Builder turns it into parts, the AI drivers route on its road graph,
	and the minimap draws it. Pure (no instances), deterministic.

	A Miami-style city (north is -Z, east is +X):

	  - The mainland: a 9x9 street grid 360 studs apart (lines at -1440 .. 1440), the avenues at
	    x = 0 and z = 0, and Biscayne Blvd along the bay at x = 1440. Its 8x8 blocks are districts
	    (DISTRICTS below, row = z from north): glass towers along the bay (Edgewater, Downtown,
	    Brickell), Wynwood's mural warehouses, Midtown, fast-food strips and parking, the suburbs,
	    and the places kept from the old map (Flighty Mechanics, Police, the Jump and Loop parks,
	    the Plaza).
	  - Freeways on concrete piers FREEWAY_Y above the streets: I-95 north-south down the middle of
	    block column 4 (with on/off ramps in two blocks), and I-395 east from it, over Biscayne
	    Blvd and across the bay as a bridge, down onto the beach island. At the city's edge I-95
	    comes down to the turnpike, a highway round the north, west and south closed by Biscayne Blvd.
	  - Biscayne Bay east of the mainland (WATER), with the beach island beyond it: West Ave,
	    Collins Ave and Ocean Drive, art-deco hotels and condo towers, the beach and the ocean. Two
	    low causeways at z = -900 and 900 join it to Biscayne Blvd.

	Everything is authored in Roblox's standard units (1 stud = 0.28 m, real-world sizes) and built at
	`K` times that size: the game uses K = Config.WORLD_SCALE (1.25), a little over life size next to
	the avatars and the bikes; the builders use Layout.Design (K = 1) and the Builder scales the
	finished city by WORLD_SCALE. Workspace streaming keeps only what's near each player loaded.
]]

local Config = require(script.Parent.Parent.Config)

export type District =
	"Suburb"
	| "Midtown"
	| "Wynwood"
	| "Edgewater"
	| "Downtown"
	| "Brickell"
	| "FastFood"
	| "Parking"
	| "Freeway"
	| "Corridor"
	| "BayPark"
	| "Marina"
	| "Jump"
	| "Dealership"
	| "Plaza"
	| "Police"
	| "Condo"
	| "ArtDeco"
export type Block = {
	Bx: number,
	Bz: number,
	Grid: string, -- "Main" or "Island"
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
export type RoadKind = "Avenue" | "Street" | "Highway" | "Rural" | "Freeway" | "Ramp" | "Causeway"
export type Node = {
	Id: number,
	Position: Vector3, -- on the road surface
	Edges: { number },
	Grid: boolean, -- a street-grid intersection (square, may have lights)
	I: number?, -- mainland grid indices
	J: number?,
	WX: number?, -- grid crossings: width of the road running along Z (its extent in X)...
	WZ: number?, -- ...and of the road running along X
	Elevated: boolean, -- up on the freeway or a ramp (not at street level)
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
export type Rect = { MinX: number, MaxX: number, MinZ: number, MaxZ: number }
-- An on/off ramp: Foot (a T on a street) -> Base (the bottom of the climb, just inside the block)
-- -> Top (the climb's top, beside the deck) -> Join (the freeway node it merges at)
export type Ramp = { Foot: number, Base: number, Top: number, Join: number, Side: number }
export type Light = "Green" | "Yellow" | "Red"

local function make(K: number)
	local Layout = {}

	Layout.ROAD_Y = 0.2 * K
	Layout.CURB_Y = 0.7 * K
	Layout.GRID_MIN = -1440 * K
	Layout.GRID_STEP = 360 * K
	Layout.GRID_COUNT = 9 -- lines per axis (mainland)
	Layout.AVENUE_INDEX = 4 -- x = 0 and z = 0
	Layout.BAY_INDEX = 8 -- Biscayne Blvd, x = 1440
	Layout.AVENUE_WIDTH = 50 * K -- 4 lanes of 12.5
	Layout.STREET_WIDTH = 26 * K -- 2 lanes of 13
	Layout.AVENUE_SIDEWALK = 14 * K
	Layout.STREET_SIDEWALK = 12 * K
	Layout.RING_HALF = 1920 * K
	Layout.RING_RADIUS = 360 * K
	Layout.RING_WIDTH = 50 * K
	Layout.RURAL_WIDTH = 26 * K
	Layout.WORLD_HALF = 3000 * K

	-- Freeways: the deck's riding surface height, its width (3 lanes each way, shoulders, barriers)
	Layout.FREEWAY_Y = 32 * K
	Layout.FREEWAY_WIDTH = 84 * K
	Layout.RAMP_WIDTH = 28 * K
	Layout.I95_X = 186 * K -- the middle of block column 4
	Layout.I395_Z = -180 * K -- through block row 3, then across the bay
	Layout.RAMP_OFFSET = Layout.FREEWAY_WIDTH / 2 + Layout.RAMP_WIDTH / 2 + 10 * K -- ramp centre lines off I-95's

	-- Water: the bay from the seawall east, the island in it, the ocean beyond the beach
	Layout.WATER_Y = -2.5 * K
	Layout.SEABED_Y = -26 * K
	Layout.SHORE_X = 1500 * K -- the mainland's seawall
	Layout.ISLAND = { MinX = 2120 * K, MaxX = 2760 * K, MinZ = -1500 * K, MaxZ = 1500 * K } :: Rect
	Layout.BEACH_X = 2600 * K -- the sand starts here...
	Layout.SURF_X = 2760 * K -- ...and meets the water here

	local W = Layout.WORLD_HALF
	local isl = Layout.ISLAND
	Layout.Water = {
		{ MinX = Layout.SHORE_X, MaxX = isl.MinX, MinZ = -W, MaxZ = W }, -- Biscayne Bay
		{ MinX = isl.MinX, MaxX = W, MinZ = -W, MaxZ = isl.MinZ }, -- north of the island
		{ MinX = isl.MinX, MaxX = W, MinZ = isl.MaxZ, MaxZ = W }, -- south of the island
		{ MinX = isl.MaxX, MaxX = W, MinZ = isl.MinZ, MaxZ = isl.MaxZ }, -- the ocean
	} :: { Rect }
	Layout.Land = {
		{ MinX = -W, MaxX = Layout.SHORE_X, MinZ = -W, MaxZ = W },
		{ MinX = isl.MinX, MaxX = isl.MaxX, MinZ = isl.MinZ, MaxZ = isl.MaxZ },
	} :: { Rect }

	function Layout.InWater(x: number, z: number): boolean
		for _, r in Layout.Water do
			if x >= r.MinX and x <= r.MaxX and z >= r.MinZ and z <= r.MaxZ then
				return true
			end
		end
		return false
	end

	-- Mainland districts by block, north row first, west to east
	local DISTRICTS: { { District } } = {
		{ "Suburb", "Suburb", "FastFood", "Midtown", "Freeway", "Wynwood", "Wynwood", "Edgewater" },
		{ "Suburb", "Suburb", "Parking", "FastFood", "Freeway", "Wynwood", "Midtown", "Edgewater" },
		{ "Suburb", "Suburb", "Midtown", "Midtown", "Freeway", "Midtown", "Edgewater", "Edgewater" },
		{ "Jump", "Jump", "FastFood", "Dealership", "Freeway", "Corridor", "Corridor", "Corridor" },
		{ "Suburb", "Suburb", "Police", "Plaza", "Freeway", "Downtown", "Downtown", "BayPark" },
		{ "Suburb", "FastFood", "Parking", "Midtown", "Freeway", "Downtown", "Downtown", "Downtown" },
		{ "Suburb", "Suburb", "Midtown", "FastFood", "Freeway", "Brickell", "Brickell", "Brickell" },
		{ "Suburb", "Suburb", "Suburb", "Parking", "Freeway", "Brickell", "Brickell", "Marina" },
	}
	-- the I-95 corridor blocks with a pair of on/off ramps (bz); ramps climb away from the street
	-- their foot is on: in row 1 from the south street (z = Line(2)) north, in row 5 from the north
	-- street (z = Line(5)) south
	Layout.RAMP_ROWS = { 1, 5 }

	function Layout.Line(index: number): number
		return Layout.GRID_MIN + Layout.GRID_STEP * index
	end

	function Layout.IsAvenue(index: number): boolean
		return index == Layout.AVENUE_INDEX
	end

	-- Carriageway width of mainland grid line `index` (x lines: Biscayne Blvd is avenue-wide too)
	function Layout.LineWidthX(index: number): number
		return if index == Layout.AVENUE_INDEX or index == Layout.BAY_INDEX then Layout.AVENUE_WIDTH else Layout.STREET_WIDTH
	end
	function Layout.LineWidthZ(index: number): number
		return if index == Layout.AVENUE_INDEX then Layout.AVENUE_WIDTH else Layout.STREET_WIDTH
	end
	-- (the old square-grid name: the z lines' width, kept for callers that don't care which axis)
	function Layout.LineWidth(index: number): number
		return Layout.LineWidthZ(index)
	end
	local function sidewalkFor(width: number): number
		return if width > Layout.STREET_WIDTH then Layout.AVENUE_SIDEWALK else Layout.STREET_SIDEWALK
	end
	function Layout.LineSidewalk(index: number): number
		return sidewalkFor(Layout.LineWidthZ(index))
	end

	-- The island's grid: West Ave, Collins Ave and Ocean Drive, cross streets half a block off the
	-- mainland's so the causeways and I-395 land on them
	Layout.ISLAND_XS = { 2200 * K, 2380 * K, 2540 * K }
	Layout.ISLAND_X_WIDTHS = { 26 * K, 40 * K, 26 * K }
	Layout.ISLAND_X_NAMES = { "West Ave", "Collins Ave", "Ocean Dr" }
	Layout.ISLAND_ZS = {}
	Layout.ISLAND_Z_WIDTHS = {}
	for j = 0, 7 do
		local z = (-1260 + j * 360) * K
		table.insert(Layout.ISLAND_ZS, z)
		-- 5th St, where I-395 comes down, is a boulevard
		table.insert(Layout.ISLAND_Z_WIDTHS, if math.abs(z - Layout.I395_Z) < 1 then Layout.AVENUE_WIDTH else 26 * K)
	end
	Layout.ISLAND_Z_WIDTH = 26 * K
	Layout.ISLAND_Z_NAMES = { "Lincoln Rd", "17th St", "11th St", "5th St", "1st St", "Pointe Dr", "Marina Way", "Fisher Ln" }

	-- Street names: the mainland's north-south avenues (x lines, west to east) and east-west streets
	-- (z lines, north to south)
	Layout.X_NAMES = { "NW 27th Ave", "NW 22nd Ave", "NW 17th Ave", "NW 12th Ave", "Miami Ave", "NE 2nd Ave", "NE 4th Ave", "NE 6th Ave", "Biscayne Blvd" }
	Layout.Z_NAMES = { "NE 36th St", "NE 29th St", "NE 20th St", "NE 11th St", "Flagler St", "SW 8th St", "SW 15th St", "SW 22nd St", "SW 32nd St" }

	--------------------------------------------------------------------------------
	-- Blocks
	--------------------------------------------------------------------------------
	Layout.Blocks = {} :: { Block }
	local mainBlocks: { [number]: Block } = {}
	local count = Layout.GRID_COUNT
	for bz = 0, count - 2 do
		for bx = 0, count - 2 do
			local x0, x1 = Layout.Line(bx), Layout.Line(bx + 1)
			local z0, z1 = Layout.Line(bz), Layout.Line(bz + 1)
			local minX = x0 + Layout.LineWidthX(bx) / 2
			local maxX = x1 - Layout.LineWidthX(bx + 1) / 2
			local minZ = z0 + Layout.LineWidthZ(bz) / 2
			local maxZ = z1 - Layout.LineWidthZ(bz + 1) / 2
			local block: Block = {
				Bx = bx,
				Bz = bz,
				Grid = "Main",
				District = DISTRICTS[bz + 1][bx + 1],
				MinX = minX,
				MaxX = maxX,
				MinZ = minZ,
				MaxZ = maxZ,
				LotMinX = minX + sidewalkFor(Layout.LineWidthX(bx)),
				LotMaxX = maxX - sidewalkFor(Layout.LineWidthX(bx + 1)),
				LotMinZ = minZ + sidewalkFor(Layout.LineWidthZ(bz)),
				LotMaxZ = maxZ - sidewalkFor(Layout.LineWidthZ(bz + 1)),
			}
			table.insert(Layout.Blocks, block)
			mainBlocks[bz * (count - 1) + bx] = block
		end
	end
	-- the island: condo towers and hotels on Collins (west column), art deco on Ocean Drive
	for bz = 0, #Layout.ISLAND_ZS - 2 do
		for bx = 0, #Layout.ISLAND_XS - 2 do
			local x0, x1 = Layout.ISLAND_XS[bx + 1], Layout.ISLAND_XS[bx + 2]
			local z0, z1 = Layout.ISLAND_ZS[bz + 1], Layout.ISLAND_ZS[bz + 2]
			local minX = x0 + Layout.ISLAND_X_WIDTHS[bx + 1] / 2
			local maxX = x1 - Layout.ISLAND_X_WIDTHS[bx + 2] / 2
			local minZ = z0 + Layout.ISLAND_Z_WIDTHS[bz + 1] / 2
			local maxZ = z1 - Layout.ISLAND_Z_WIDTHS[bz + 2] / 2
			local walk = Layout.STREET_SIDEWALK
			table.insert(Layout.Blocks, {
				Bx = bx,
				Bz = bz,
				Grid = "Island",
				District = if bx == 0 then "Condo" else "ArtDeco",
				MinX = minX,
				MaxX = maxX,
				MinZ = minZ,
				MaxZ = maxZ,
				LotMinX = minX + walk,
				LotMaxX = maxX - walk,
				LotMinZ = minZ + walk,
				LotMaxZ = maxZ - walk,
			})
		end
	end

	-- A mainland block by its indices
	function Layout.BlockAt(bx: number, bz: number): Block
		return mainBlocks[bz * (count - 1) + bx]
	end

	-- The strip of a Freeway block left at street level under I-95 (its piers, a car park, the ramps)
	function Layout.UnderDeck(block: Block): (number, number)
		local half = Layout.FREEWAY_WIDTH / 2 + 6 * K
		if table.find(Layout.RAMP_ROWS, block.Bz) then
			half = Layout.RAMP_OFFSET + Layout.RAMP_WIDTH / 2 + 4 * K
		end
		return Layout.I95_X - half, Layout.I95_X + half
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
	-- Road graph: nodes are intersections, bends and ramp ends; edges are straight road pieces
	--------------------------------------------------------------------------------
	Layout.Nodes = {} :: { Node }
	Layout.Edges = {} :: { Edge }

	local function addNode(position: Vector3, grid: boolean, i: number?, j: number?): number
		local id = #Layout.Nodes + 1
		Layout.Nodes[id] = { Id = id, Position = position, Edges = {}, Grid = grid, I = i, J = j, Elevated = position.Y > Layout.ROAD_Y + 1 }
		return id
	end

	local SPEED: { [RoadKind]: number } = { Avenue = 13, Street = 11, Highway = 22, Rural = 15, Freeway = 26, Ramp = 14, Causeway = 16 }
	local function addEdge(a: number, b: number, kind: RoadKind, width: number, lanes: number)
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
			Speed = SPEED[kind],
		}
		table.insert(Layout.Nodes[a].Edges, id)
		table.insert(Layout.Nodes[b].Edges, id)
	end

	-- Mainland grid crossings
	local ROAD = Layout.ROAD_Y
	local gridNode: { [number]: { [number]: number } } = {}
	Layout.GridNodes = {} :: { number } -- every crossing of both grids
	for i = 0, count - 1 do
		gridNode[i] = {}
		for j = 0, count - 1 do
			local id = addNode(Vector3.new(Layout.Line(i), ROAD, Layout.Line(j)), true, i, j)
			Layout.Nodes[id].WX = Layout.LineWidthX(i)
			Layout.Nodes[id].WZ = Layout.LineWidthZ(j)
			gridNode[i][j] = id
			table.insert(Layout.GridNodes, id)
		end
	end
	Layout.GridNode = gridNode

	-- Extra T-junctions part-way along a grid line (ramp feet, causeway ends): keyed by line, each
	-- a list of { At = coordinate along the line, Node = id }
	local splitsX: { [number]: { { At: number, Node: number } } } = {} -- along x line i (varying z)
	local splitsZ: { [number]: { { At: number, Node: number } } } = {} -- along z line j (varying x)
	local function splitZLine(j: number, x: number): number
		local id = addNode(Vector3.new(x, ROAD, Layout.Line(j)), false)
		splitsZ[j] = splitsZ[j] or {}
		table.insert(splitsZ[j], { At = x, Node = id })
		return id
	end
	local function splitXLine(i: number, z: number): number
		local id = addNode(Vector3.new(Layout.Line(i), ROAD, z), false)
		splitsX[i] = splitsX[i] or {}
		table.insert(splitsX[i], { At = z, Node = id })
		return id
	end

	-- I-95 on/off ramp feet (both sides of the deck, on the street the ramps start from)
	local rampSide = Layout.RAMP_OFFSET
	local rampFeet: { { Row: number, Side: number, Node: number, FootJ: number } } = {}
	for _, row in Layout.RAMP_ROWS do
		local footJ = if row < 3 then row + 1 else row
		for _, side in { -1, 1 } do
			local x = Layout.I95_X + side * rampSide
			table.insert(rampFeet, { Row = row, Side = side, Node = splitZLine(footJ, x), FootJ = footJ })
		end
	end
	-- causeway landings on Biscayne Blvd
	Layout.CAUSEWAY_ZS = { -900 * K, 900 * K }
	local causewayFeet: { number } = {}
	for _, z in Layout.CAUSEWAY_ZS do
		table.insert(causewayFeet, splitXLine(Layout.BAY_INDEX, z))
	end

	-- Grid road pieces, through the splits
	local function lineKindX(i: number): RoadKind
		return if i == Layout.AVENUE_INDEX or i == Layout.BAY_INDEX then "Avenue" else "Street"
	end
	local function lineKindZ(j: number): RoadKind
		return if j == Layout.AVENUE_INDEX then "Avenue" else "Street"
	end
	for j = 0, count - 1 do
		local chain: { { At: number, Node: number } } = {}
		for i = 0, count - 1 do
			table.insert(chain, { At = Layout.Line(i), Node = gridNode[i][j] })
		end
		local extra = splitsZ[j]
		if extra then
			for _, split in extra do
				table.insert(chain, split)
			end
		end
		table.sort(chain, function(a, b)
			return a.At < b.At
		end)
		for k = 1, #chain - 1 do
			local kind: RoadKind = lineKindZ(j)
			addEdge(chain[k].Node, chain[k + 1].Node, kind, Layout.LineWidthZ(j), if kind == "Avenue" then 2 else 1)
		end
	end
	for i = 0, count - 1 do
		local chain: { { At: number, Node: number } } = {}
		for j = 0, count - 1 do
			table.insert(chain, { At = Layout.Line(j), Node = gridNode[i][j] })
		end
		local extra = splitsX[i]
		if extra then
			for _, split in extra do
				table.insert(chain, split)
			end
		end
		table.sort(chain, function(a, b)
			return a.At < b.At
		end)
		for k = 1, #chain - 1 do
			local kind: RoadKind = lineKindX(i)
			addEdge(chain[k].Node, chain[k + 1].Node, kind, Layout.LineWidthX(i), if kind == "Avenue" then 2 else 1)
		end
	end

	-- The turnpike: north, west and south of the city (a U with rounded western corners), its ends
	-- on Biscayne Blvd's extensions at the bay
	local RING_SEGMENTS_PER_CORNER = 6
	local ringNodes: { number } = {}
	local ringMid: { [string]: number } = {}
	local i95North, i95South
	do
		local h, r = Layout.RING_HALF, Layout.RING_RADIUS
		local inner = h - r
		local bayX = Layout.Line(Layout.BAY_INDEX)
		local function add(p: Vector3): number
			local id = addNode(p, false)
			table.insert(ringNodes, id)
			return id
		end
		-- north side, east to west
		add(Vector3.new(bayX, ROAD, -h))
		i95North = add(Vector3.new(Layout.I95_X, ROAD, -h))
		ringMid.N = add(Vector3.new(0, ROAD, -h))
		-- north-west corner: from the north side round to the west side
		for k = 0, RING_SEGMENTS_PER_CORNER do
			local angle = -math.pi / 2 - (math.pi / 2) * k / RING_SEGMENTS_PER_CORNER
			add(Vector3.new(-inner + math.cos(angle) * r, ROAD, -inner + math.sin(angle) * r))
		end
		ringMid.W = add(Vector3.new(-h, ROAD, 0))
		-- south-west corner
		for k = 0, RING_SEGMENTS_PER_CORNER do
			local angle = math.pi - (math.pi / 2) * k / RING_SEGMENTS_PER_CORNER
			add(Vector3.new(-inner + math.cos(angle) * r, ROAD, inner + math.sin(angle) * r))
		end
		ringMid.S = add(Vector3.new(0, ROAD, h))
		i95South = add(Vector3.new(Layout.I95_X, ROAD, h))
		add(Vector3.new(bayX, ROAD, h))
		for k = 1, #ringNodes - 1 do
			addEdge(ringNodes[k], ringNodes[k + 1], "Highway", Layout.RING_WIDTH, 2)
		end
		-- Biscayne Blvd carries on north and south along the bay to the turnpike's ends
		addEdge(ringNodes[1], gridNode[Layout.BAY_INDEX][0], "Avenue", Layout.AVENUE_WIDTH, 2)
		addEdge(gridNode[Layout.BAY_INDEX][count - 1], ringNodes[#ringNodes], "Avenue", Layout.AVENUE_WIDTH, 2)
	end
	Layout.RingNodes = ringNodes

	-- Country roads from the avenue ends out to the turnpike (north, west, south)
	local last = count - 1
	local mid = Layout.AVENUE_INDEX
	addEdge(gridNode[mid][0], ringMid.N, "Rural", Layout.RURAL_WIDTH, 1)
	addEdge(gridNode[mid][last], ringMid.S, "Rural", Layout.RURAL_WIDTH, 1)
	addEdge(gridNode[0][mid], ringMid.W, "Rural", Layout.RURAL_WIDTH, 1)

	-- I-95: up on the deck over every cross street, the I-395 junction, down to the turnpike at each end
	local H = Layout.FREEWAY_Y
	local FW = Layout.FREEWAY_WIDTH
	Layout.I95 = {} :: { number } -- north to south, ground ends included
	local i95At: { [number]: number } = {} -- deck node over mainland z line j
	local junction: number
	do
		local x = Layout.I95_X
		local descent = 400 * K -- 8% grade from the deck to the turnpike
		table.insert(Layout.I95, i95North)
		table.insert(Layout.I95, addNode(Vector3.new(x, ROAD, Layout.Line(0) - descent), false))
		for j = 0, count - 1 do
			local id = addNode(Vector3.new(x, H, Layout.Line(j)), false)
			i95At[j] = id
			table.insert(Layout.I95, id)
			if j == 3 then
				junction = addNode(Vector3.new(x, H, Layout.I395_Z), false)
				table.insert(Layout.I95, junction)
			end
		end
		table.insert(Layout.I95, addNode(Vector3.new(x, ROAD, Layout.Line(last) + descent), false))
		table.insert(Layout.I95, i95South)
		for k = 1, #Layout.I95 - 1 do
			addEdge(Layout.I95[k], Layout.I95[k + 1], "Freeway", FW, 3)
		end
	end
	Layout.I95Junction = junction

	-- I-395: east from the junction over the streets, over Biscayne Blvd and across the bay as a
	-- bridge, down onto the island's West Ave
	Layout.I395 = { junction } :: { number }
	local islandGrid: { [number]: { [number]: number } } = {}
	do
		local z = Layout.I395_Z
		for i = Layout.AVENUE_INDEX + 1, Layout.BAY_INDEX do
			table.insert(Layout.I395, addNode(Vector3.new(Layout.Line(i), H, z), false))
		end
		table.insert(Layout.I395, addNode(Vector3.new(1800 * K, H, z), false))
		table.insert(Layout.I395, addNode(Vector3.new(Layout.ISLAND.MinX + 40 * K, ROAD, z), false))
	end

	-- The island's grid
	for i, x in Layout.ISLAND_XS do
		islandGrid[i] = {}
		for j, z in Layout.ISLAND_ZS do
			local id = addNode(Vector3.new(x, ROAD, z), true)
			Layout.Nodes[id].WX = Layout.ISLAND_X_WIDTHS[i]
			Layout.Nodes[id].WZ = Layout.ISLAND_Z_WIDTHS[j]
			islandGrid[i][j] = id
			table.insert(Layout.GridNodes, id)
		end
	end
	Layout.IslandGrid = islandGrid
	for i = 1, #Layout.ISLAND_XS do
		for j = 1, #Layout.ISLAND_ZS - 1 do
			local wide = Layout.ISLAND_X_WIDTHS[i] > Layout.STREET_WIDTH
			addEdge(islandGrid[i][j], islandGrid[i][j + 1], if wide then "Avenue" else "Street", Layout.ISLAND_X_WIDTHS[i], if wide then 2 else 1)
		end
	end
	for j = 1, #Layout.ISLAND_ZS do
		local wide = Layout.ISLAND_Z_WIDTHS[j] > Layout.STREET_WIDTH
		for i = 1, #Layout.ISLAND_XS - 1 do
			addEdge(islandGrid[i][j], islandGrid[i + 1][j], if wide then "Avenue" else "Street", Layout.ISLAND_Z_WIDTHS[j], if wide then 2 else 1)
		end
	end
	local function islandNodeAtZ(z: number): number
		for j, zz in Layout.ISLAND_ZS do
			if math.abs(zz - z) < 1 then
				return islandGrid[1][j]
			end
		end
		error("no island street at z = " .. z)
	end
	table.insert(Layout.I395, islandNodeAtZ(Layout.I395_Z))
	for k = 1, #Layout.I395 - 1 do
		local last395 = k == #Layout.I395 - 1
		addEdge(Layout.I395[k], Layout.I395[k + 1], if last395 then "Avenue" else "Freeway", if last395 then Layout.AVENUE_WIDTH else FW, if last395 then 2 else 3)
	end

	-- Causeways: low roads across the bay on rock embankments
	Layout.Causeways = {} :: { { A: number, B: number } }
	for k, z in Layout.CAUSEWAY_ZS do
		local island = islandNodeAtZ(z)
		addEdge(causewayFeet[k], island, "Causeway", Layout.STREET_WIDTH + 4 * K, 1)
		table.insert(Layout.Causeways, { A = causewayFeet[k], B = island })
	end

	-- I-95 ramps: from the foot on the street, into the block, up beside the deck, onto it
	Layout.Ramps = {} :: { Ramp }
	for _, foot in rampFeet do
		local towardDeck = if foot.Row < 3 then -1 else 1 -- climbing north in row 1, south in row 5
		local streetZ = Layout.Line(foot.FootJ)
		local joinJ = if foot.Row < 3 then foot.Row else foot.Row + 1
		local joinZ = Layout.Line(joinJ)
		local x = Layout.I95_X + foot.Side * rampSide
		local baseZ = streetZ + towardDeck * (Layout.STREET_WIDTH / 2 + Layout.STREET_SIDEWALK + 6 * K)
		local topZ = joinZ - towardDeck * (Layout.STREET_WIDTH / 2 + Layout.STREET_SIDEWALK + 70 * K)
		local base = addNode(Vector3.new(x, ROAD, baseZ), false)
		local top = addNode(Vector3.new(x, H, topZ), false)
		addEdge(foot.Node, base, "Ramp", Layout.RAMP_WIDTH, 1)
		addEdge(base, top, "Ramp", Layout.RAMP_WIDTH, 1)
		addEdge(top, i95At[joinJ], "Ramp", Layout.RAMP_WIDTH, 1)
		table.insert(Layout.Ramps, { Foot = foot.Node, Base = base, Top = top, Join = i95At[joinJ], Side = foot.Side })
	end

	-- Width of the road crossing a node (for where a road piece starts)
	function Layout.NodeClearance(nodeId: number, alongAxis: string): number
		local node = Layout.Nodes[nodeId]
		if node.Grid and node.WX and node.WZ then
			-- the crossing road's half width
			return if alongAxis == "X" then node.WX / 2 else node.WZ / 2
		end
		return 0
	end

	function Layout.OtherEnd(edge: Edge, nodeId: number): number
		return if edge.A == nodeId then edge.B else edge.A
	end

	-- The node nearest a point. Height counts three times over, so a rider under the freeway maps to
	-- the street, not the deck above them.
	function Layout.NearestNode(position: Vector3, filter: ((Node) -> boolean)?): number
		local best, bestDistance = 1, math.huge
		for _, node in Layout.Nodes do
			if not filter or filter(node) then
				local p = node.Position
				local d = (Vector3.new(position.X, 0, position.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude + math.abs(position.Y - p.Y) * 3
				if d < bestDistance then
					best, bestDistance = node.Id, d
				end
			end
		end
		return best
	end

	-- The grid crossing `position` is inside (nil if none)
	function Layout.IntersectionAt(position: Vector3): number?
		for _, id in Layout.GridNodes do
			local node = Layout.Nodes[id]
			local p = node.Position
			if math.abs(position.X - p.X) < (node.WX or 0) / 2 and math.abs(position.Z - p.Z) < (node.WZ or 0) / 2 and math.abs(position.Y - p.Y) < 8 * K then
				return id
			end
		end
		return nil
	end

	-- Shortest path by road length (Dijkstra)
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
		if edge.Kind == "Freeway" then
			-- the deck's barriers and shoulders take some of its width
			laneWidth = (edge.Width - 12 * K) / (edge.Lanes * 2)
		end
		return laneWidth * (math.clamp(lane, 1, edge.Lanes) - 0.5)
	end

	function Layout.LanePoint(edge: Edge, from: number, t: number, lane: number): Vector3
		local a = Layout.Nodes[from].Position
		local b = Layout.Nodes[Layout.OtherEnd(edge, from)].Position
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		local right = Vector3.new(-flat.Z, 0, flat.X)
		return a:Lerp(b, t) + right * Layout.LaneOffset(edge, lane)
	end

	--------------------------------------------------------------------------------
	-- Traffic lights: on every grid crossing of four roads (and three on an avenue). Phases come from
	-- the server clock so every client and the AI agree.
	--------------------------------------------------------------------------------
	function Layout.HasLights(node: Node): boolean
		if not node.Grid then
			return false
		end
		local avenue = node.I ~= nil and (node.I == Layout.AVENUE_INDEX or node.J == Layout.AVENUE_INDEX or node.I == Layout.BAY_INDEX)
		return #node.Edges >= 4 or (#node.Edges >= 3 and avenue)
	end

	function Layout.LightState(nodeId: number, axis: string, time: number, cycle: number, yellow: number, allRed: number): Light
		local node = Layout.Nodes[nodeId]
		local offset = ((node.I or node.Id) * 5 + (node.J or 0) * 3) % cycle
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
	local bayPark = Layout.FindDistrict("BayPark") :: Block

	local function lotCenter(block: Block): Vector3
		return Vector3.new((block.LotMinX + block.LotMaxX) / 2, Layout.CURB_Y, (block.LotMinZ + block.LotMaxZ) / 2)
	end

	local beachZ = 180 * K
	Layout.Places = {
		-- Spawn: the forecourt in front of the dealership, facing it (north)
		Spawn = Vector3.new((dealership.LotMinX + dealership.LotMaxX) / 2, Layout.CURB_Y, dealership.LotMaxZ - 50 * K),
		Dealership = lotCenter(dealership),
		Police = lotCenter(police),
		JumpPark = lotCenter(jump),
		-- (south of the fountains)
		Plaza = lotCenter(plaza) + Vector3.new(0, 0, 45 * K),
		Park = lotCenter(bayPark) + Vector3.new(0, 0, 60 * K),
		-- on the streets through them (their blocks are built up)
		Downtown = Vector3.new(Layout.Line(5) + 180 * K, Layout.ROAD_Y, Layout.Line(Layout.AVENUE_INDEX) + 12 * K),
		Wynwood = Vector3.new(Layout.Line(6), Layout.ROAD_Y, Layout.Line(0) + 180 * K),
		Beach = Vector3.new(Layout.BEACH_X - 4 * K, Layout.CURB_Y, beachZ), -- the beach walk
		Countryside = Vector3.new(-Layout.RING_HALF + 40 * K, Layout.ROAD_Y, 0),
	}

	-- Teleports offered in the Menus panel
	Layout.Teleports = {
		{ Id = "Dealership", Name = "Flighty Mechanics" },
		{ Id = "JumpPark", Name = "Jump Park" },
		{ Id = "Downtown", Name = "Downtown" },
		{ Id = "Beach", Name = "South Beach" },
		{ Id = "Park", Name = "Bayfront Park" },
		{ Id = "Wynwood", Name = "Wynwood" },
		{ Id = "Plaza", Name = "City Plaza" },
		{ Id = "Countryside", Name = "Outskirts" },
	}

	-- Charging stations: kiosk positions (on pads, by the kerb) and which way each faces (its street)
	local fastFood = Layout.BlockAt(2, 3)
	local wynwood = Layout.BlockAt(5, 0)
	local downtown = Layout.BlockAt(5, 4)
	local brickell = Layout.BlockAt(6, 6)
	Layout.Chargers = {
		Vector3.new(dealership.LotMaxX - 20 * K, Layout.CURB_Y, dealership.LotMaxZ - 20 * K),
		Vector3.new(plaza.LotMinX + 20 * K, Layout.CURB_Y, plaza.LotMaxZ - 20 * K),
		Vector3.new(jump.LotMaxX - 15 * K, Layout.CURB_Y, jump.LotMaxZ - 15 * K),
		Vector3.new(fastFood.LotMinX + 20 * K, Layout.CURB_Y, fastFood.LotMaxZ - 15 * K),
		Vector3.new(downtown.LotMinX + 15 * K, Layout.CURB_Y, downtown.LotMaxZ - 8 * K),
		-- on the pavements of the built-up blocks, facing the street
		Vector3.new((wynwood.MinX + wynwood.MaxX) / 2, Layout.CURB_Y, wynwood.MaxZ - 9 * K),
		Vector3.new((brickell.MinX + brickell.MaxX) / 2, Layout.CURB_Y, brickell.MinZ + 9 * K),
		Vector3.new(police.LotMinX + 20 * K, Layout.CURB_Y, police.LotMinZ + 20 * K),
		Vector3.new(Layout.ISLAND_XS[3] + 30 * K, Layout.CURB_Y, beachZ + 40 * K), -- on the beach walk
		Vector3.new(40 * K, Layout.ROAD_Y, -Layout.RING_HALF + 70 * K), -- country stop on the north road
	}
	Layout.ChargerFacing = {
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(0, 0, -1),
		Vector3.new(-1, 0, 0),
		Vector3.new(-1, 0, 0),
	}

	-- Where pursuing cops enter the map: the crossing by the police station
	Layout.PoliceSpawn = gridNode[3][5]

	return Layout
end

local Layout = make(Config.WORLD_SCALE)
-- The same city in design units (K = 1), for the builders
;(Layout :: any).Design = make(1)

return Layout
