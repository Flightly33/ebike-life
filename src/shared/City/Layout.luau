--[[
	Layout: the city as data. The Builder turns it into parts, the AI drivers route on its road graph,
	and the minimap draws it. Pure (no instances), deterministic.

	Greater Miami (north is -Z, east is +X), WORLD_HALF each way from the middle:

	  - Downtown: a 9x9 street grid 360 studs apart (lines at -1440 .. 1440), the avenues Miami Ave
	    (x = 0) and Flagler St (z = 0), and Biscayne Blvd along the bay at x = 1440. Its 8x8 blocks
	    are districts (DISTRICTS below, row = z from north): glass towers along the bay (Edgewater,
	    Downtown, Brickell), Wynwood, Midtown, fast food and parking, the suburbs, and the places
	    kept from the first map (Flighty Mechanics, Police, the Jump and Loop parks, the Plaza).
	  - Freeways on piers FREEWAY_Y up: I-95 down block column 4 (ramps in two blocks), I-395 east
	    from it over Biscayne Blvd and across the bay as a bridge onto Miami Beach. The turnpike is a
	    U round the north, west and south of downtown, its ends on Biscayne Blvd.
	  - Round it: Little Havana west (Calle Ocho runs on out through the Everglades as the Tamiami
	    Trail), Coral Gables and Coconut Grove south (one grid, `SOUTH_*`), the airport north-west,
	    and Biscayne Blvd running on north and south along the bay.
	  - Biscayne Bay east of SHORE_X: the port island, the barrier island (South Beach's art deco and
	    condos, North Beach's mansions and condo towers, the beach and the ocean beyond), and Key
	    Biscayne off the south-east. Causeways, I-395 and the Rickenbacker Causeway cross the bay.

	Everything is authored in Roblox's standard units (1 stud = 0.28 m, real-world sizes) and built at
	`K` times that size: the game uses K = Config.WORLD_SCALE (1.2, a world big enough for the
	stocky avatars; see Config); the builders use Layout.Design (K = 1) and the Builder scales the
	finished city by WORLD_SCALE. Positions on the plan (the lines below, the rects, the places) are
	spread by Config.CITY_SPREAD (`KS`), sizes (carriageways, pavements, heights, setbacks) aren't
	(`K`): the map keeps the size it had at 1.25 times life size whatever K is.
	Builders spread their own plan positions with Layout.SPREAD. Workspace streaming keeps only what's
	near each player loaded.
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
	| "Mansion"
	| "Havana"
	| "HavanaPark"
	| "Gables"
	| "GablesHotel"
	| "Grove"
	| "GroveBay"
	| "KeyHomes"
	| "KeyPark"
export type Block = {
	Bx: number,
	Bz: number,
	Grid: string, -- "Main", "Island", "Havana", "South" or "Key"
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
	Grid: boolean, -- a street-grid crossing (square, may have lights)
	I: number?, -- downtown grid indices
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
-- A piece of open land: what the ground is (Terrain fills it at runtime)
export type Ground = { MinX: number, MaxX: number, MinZ: number, MaxZ: number, Kind: string } -- Kind: "Grass" or "Marsh"

-- Rect helpers (pure)
local function rect(minX: number, maxX: number, minZ: number, maxZ: number): Rect
	return { MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ }
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.MinX < b.MaxX and a.MaxX > b.MinX and a.MinZ < b.MaxZ and a.MaxZ > b.MinZ
end

-- `a` minus `b`: up to four rects
local function subtract(a: Rect, b: Rect): { Rect }
	if not overlaps(a, b) then
		return { a }
	end
	local out = {}
	if b.MinX > a.MinX then
		table.insert(out, rect(a.MinX, b.MinX, a.MinZ, a.MaxZ))
	end
	if b.MaxX < a.MaxX then
		table.insert(out, rect(b.MaxX, a.MaxX, a.MinZ, a.MaxZ))
	end
	local x0, x1 = math.max(a.MinX, b.MinX), math.min(a.MaxX, b.MaxX)
	if b.MinZ > a.MinZ then
		table.insert(out, rect(x0, x1, a.MinZ, b.MinZ))
	end
	if b.MaxZ < a.MaxZ then
		table.insert(out, rect(x0, x1, b.MaxZ, a.MaxZ))
	end
	return out
end

local function subtractAll(list: { Rect }, cuts: { Rect }): { Rect }
	local current = list
	for _, cut in cuts do
		local nextList = {}
		for _, r in current do
			for _, piece in subtract(r, cut) do
				if piece.MaxX - piece.MinX > 0.5 and piece.MaxZ - piece.MinZ > 0.5 then
					table.insert(nextList, piece)
				end
			end
		end
		current = nextList
	end
	return current
end

local function intersect(a: Rect, b: Rect): Rect?
	if not overlaps(a, b) then
		return nil
	end
	return rect(math.max(a.MinX, b.MinX), math.min(a.MaxX, b.MaxX), math.max(a.MinZ, b.MinZ), math.min(a.MaxZ, b.MaxZ))
end

local function inside(r: Rect, x: number, z: number): boolean
	return x >= r.MinX and x <= r.MaxX and z >= r.MinZ and z <= r.MaxZ
end

local function make(K: number)
	local Layout = {}
	-- plan positions are spread, sizes aren't (see the header)
	local KS = K * Config.CITY_SPREAD
	Layout.SPREAD = Config.CITY_SPREAD

	Layout.ROAD_Y = 0.2 * K
	Layout.CURB_Y = 0.7 * K
	Layout.GRID_MIN = -1440 * KS
	Layout.GRID_STEP = 360 * KS
	Layout.GRID_COUNT = 9 -- lines per axis (downtown)
	Layout.AVENUE_INDEX = 4 -- x = 0 and z = 0
	Layout.BAY_INDEX = 8 -- Biscayne Blvd, x = 1440
	Layout.AVENUE_WIDTH = 50 * K -- 4 lanes of 12.5
	Layout.STREET_WIDTH = 26 * K -- 2 lanes of 13
	Layout.AVENUE_SIDEWALK = 14 * K
	Layout.STREET_SIDEWALK = 12 * K
	Layout.RING_HALF = 1920 * KS
	Layout.RING_RADIUS = 360 * KS
	Layout.RING_WIDTH = 50 * K
	Layout.RURAL_WIDTH = 26 * K
	Layout.WORLD_HALF = 4250 * KS

	-- Freeways: the deck's riding surface height, its width (3 lanes each way, shoulders, barriers)
	Layout.FREEWAY_Y = 32 * K
	Layout.FREEWAY_WIDTH = 84 * K
	Layout.RAMP_WIDTH = 28 * K
	Layout.I95_X = (Layout.GRID_STEP + Layout.AVENUE_WIDTH / 2 - Layout.STREET_WIDTH / 2) / 2 -- the middle of block column 4
	Layout.I395_Z = -180 * KS -- through block row 3, then across the bay
	Layout.RAMP_OFFSET = Layout.FREEWAY_WIDTH / 2 + Layout.RAMP_WIDTH / 2 + 10 * K -- ramp centre lines off I-95's

	-- Water: the bay from the seawall east, the islands in it, the ocean beyond the beaches
	Layout.WATER_Y = -2.5 * K
	Layout.SEABED_Y = -26 * K
	Layout.LAKE_BED_Y = -9 * K
	Layout.SHORE_X = 1500 * KS -- the mainland's seawall
	-- the barrier island (South Beach, North Beach), its beach from BEACH_X to the surf at SURF_X
	Layout.ISLAND = rect(2720 * KS, 3360 * KS, -3900 * KS, 1500 * KS)
	Layout.BEACH_X = 3200 * KS
	Layout.SURF_X = 3360 * KS
	-- the port island (container yard, cruise terminal) and Key Biscayne
	Layout.PORT = rect(1760 * KS, 2400 * KS, 200 * KS, 700 * KS)
	Layout.PORT_ROAD_Z = 450 * KS
	Layout.KEY = rect(2300 * KS, 3500 * KS, 2400 * KS, 3700 * KS)
	Layout.KEY_BEACH_X = 3320 * KS
	Layout.KEY_SURF_X = 3500 * KS
	Layout.Islands = { Layout.ISLAND, Layout.PORT, Layout.KEY } :: { Rect }

	local W = Layout.WORLD_HALF

	-- Lakes and canals inland: golf ponds, the Everglades' canal and sloughs
	Layout.TAMIAMI_Z = 360 * KS -- Calle Ocho, out through the Everglades as the Tamiami Trail
	Layout.Lakes = {
		rect(-4250 * KS, -3280 * KS, 296 * KS, 322 * KS), -- the Tamiami canal, along the trail's north side
		rect(-4080 * KS, -3700 * KS, -1560 * KS, -1300 * KS),
		rect(-4020 * KS, -3620 * KS, 1840 * KS, 2100 * KS),
		rect(-4120 * KS, -3860 * KS, -3000 * KS, -2760 * KS),
		rect(-3900 * KS, -3600 * KS, 3200 * KS, 3500 * KS),
		rect(-640 * KS, -360 * KS, -3260 * KS, -3020 * KS), -- north golf course
		rect(420 * KS, 760 * KS, -3780 * KS, -3560 * KS),
		rect(-2760 * KS, -2520 * KS, 1420 * KS, 1600 * KS), -- the Gables golf course
		rect(-1240 * KS, -1060 * KS, -1840 * KS, -1680 * KS), -- inside the turnpike
	} :: { Rect }

	-- The water: every part of the bay and the ocean that isn't an island, as rects (stripes down
	-- the island edges), and the lakes
	do
		local xs = { Layout.SHORE_X, W }
		for _, island in Layout.Islands do
			table.insert(xs, island.MinX)
			table.insert(xs, island.MaxX)
		end
		table.sort(xs)
		local water: { Rect } = {}
		for k = 1, #xs - 1 do
			local x0, x1 = xs[k], xs[k + 1]
			if x1 - x0 > 0.5 then
				local pieces = { rect(x0, x1, -W, W) }
				pieces = subtractAll(pieces, Layout.Islands)
				for _, piece in pieces do
					table.insert(water, piece)
				end
			end
		end
		Layout.Sea = water
		local all = table.clone(water)
		for _, lake in Layout.Lakes do
			table.insert(all, lake)
		end
		Layout.Water = all :: { Rect }
	end
	Layout.Land = {
		rect(-W, Layout.SHORE_X, -W, W),
		Layout.ISLAND,
		Layout.PORT,
		Layout.KEY,
	} :: { Rect }

	function Layout.InWater(x: number, z: number): boolean
		for _, r in Layout.Water do
			if inside(r, x, z) then
				return true
			end
		end
		return false
	end

	-- The beaches (sloping sand into the surf): the barrier island's and Key Biscayne's east shores
	Layout.Beaches = {
		rect(Layout.BEACH_X, Layout.SURF_X, Layout.ISLAND.MinZ, Layout.ISLAND.MaxZ),
		rect(Layout.KEY_BEACH_X, Layout.KEY_SURF_X, Layout.KEY.MinZ, Layout.KEY.MaxZ),
	} :: { Rect }

	-- Downtown districts by block, north row first, west to east
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

	-- Carriageway width of downtown grid line `index` (x lines: Biscayne Blvd is avenue-wide too)
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
	Layout.SidewalkFor = sidewalkFor
	function Layout.LineSidewalk(index: number): number
		return sidewalkFor(Layout.LineWidthZ(index))
	end

	-- Street names: downtown's north-south avenues (x lines, west to east) and east-west streets
	-- (z lines, north to south)
	Layout.X_NAMES = { "NW 27th Ave", "NW 22nd Ave", "NW 17th Ave", "NW 12th Ave", "Miami Ave", "NE 2nd Ave", "NE 4th Ave", "NE 6th Ave", "Biscayne Blvd" }
	Layout.Z_NAMES = { "NE 36th St", "NE 29th St", "NE 20th St", "NE 11th St", "Flagler St", "SW 8th St", "SW 15th St", "SW 22nd St", "SW 32nd St" }

	-- The other street grids: lines, carriageway widths, names, and the district of each block
	-- (nil: no block, open ground)
	type GridSpec = { Name: string, XS: { number }, ZS: { number }, XW: { number }, ZW: { number }, XNames: { string }, ZNames: { string }, District: (bx: number, bz: number) -> District? }
	local function lines(from: number, step: number, n: number): { number }
		local out = {}
		for k = 0, n - 1 do
			table.insert(out, (from + k * step) * KS)
		end
		return out
	end
	local function widths(n: number, wide: { [number]: number }?): { number }
		local out = {}
		for k = 1, n do
			table.insert(out, (if wide and wide[k] then wide[k] else 26) * K)
		end
		return out
	end

	-- Miami Beach: West Ave, Collins Ave and Ocean Dr from North Beach down to South Pointe; 5th St,
	-- where I-395 comes down, is a boulevard
	local islandZS = lines(-3780, 360, 15)
	Layout.ISLAND_XS = { 2800 * KS, 2980 * KS, 3140 * KS }
	Layout.ISLAND_X_WIDTHS = { 26 * K, 40 * K, 26 * K }
	Layout.ISLAND_X_NAMES = { "West Ave", "Collins Ave", "Ocean Dr" }
	Layout.ISLAND_ZS = islandZS
	Layout.ISLAND_Z_WIDTHS = widths(15, { [11] = 50 })
	Layout.ISLAND_Z_WIDTH = 26 * K
	Layout.ISLAND_Z_NAMES = { "87th St", "79th St", "71st St", "63rd St", "Arthur Godfrey Rd", "47th St", "41st St", "Lincoln Rd", "17th St", "11th St", "5th St", "1st St", "Pointe Dr", "Marina Way", "Fisher Ln" }
	Layout.NORTH_BEACH_ROWS = 7 -- the island's northern block rows (mansions and condo towers)
	-- Little Havana: Calle Ocho (z = 360) through the middle, Flagler St north of it
	Layout.HAVANA_XS = lines(-3240, 360, 4)
	Layout.HAVANA_ZS = lines(-720, 360, 6)
	-- Coral Gables (west) and Coconut Grove (east), one grid south of the turnpike, Bayshore Dr
	-- (Biscayne Blvd's south end) along the bay
	Layout.SOUTH_XS = lines(-2880, 360, 13)
	Layout.SOUTH_ZS = lines(2160, 360, 5)
	Layout.GROVE_X = -720 * KS -- the Grove starts east of this line
	-- Key Biscayne: Crandon Blvd down the middle
	Layout.KEY_XS = { 2500 * KS, 2900 * KS, 3220 * KS }
	Layout.KEY_ZS = lines(2520, 360, 4)

	local GRIDS: { GridSpec } = {
		{
			Name = "Island",
			XS = Layout.ISLAND_XS,
			ZS = islandZS,
			XW = Layout.ISLAND_X_WIDTHS,
			ZW = Layout.ISLAND_Z_WIDTHS,
			XNames = Layout.ISLAND_X_NAMES,
			ZNames = Layout.ISLAND_Z_NAMES,
			District = function(bx: number, bz: number): District?
				if bz < Layout.NORTH_BEACH_ROWS then
					return if bx == 0 then "Mansion" else "Condo"
				end
				return if bx == 0 then "Condo" else "ArtDeco"
			end,
		},
		{
			Name = "Havana",
			XS = Layout.HAVANA_XS,
			ZS = Layout.HAVANA_ZS,
			XW = widths(4),
			ZW = widths(6, { [3] = 40, [4] = 40 }),
			XNames = { "SW 27th Ave", "SW 22nd Ave", "SW 17th Ave", "SW 12th Ave" },
			ZNames = { "NW 7th St", "NW 3rd St", "W Flagler St", "Calle Ocho", "SW 12th St", "SW 16th St" },
			District = function(bx: number, bz: number): District?
				if bx == 1 and bz == 3 then
					return "HavanaPark" -- Domino Park, by Calle Ocho
				end
				return "Havana"
			end,
		},
		{
			Name = "South",
			XS = Layout.SOUTH_XS,
			ZS = Layout.SOUTH_ZS,
			XW = widths(13, { [13] = 50, [9] = 40 }),
			ZW = widths(5, { [3] = 40 }),
			XNames = { "Red Rd", "Granada Blvd", "Le Jeune Rd", "Ponce de Leon", "Douglas Rd", "SW 32nd Ave", "SW 27th Ave", "Aviation Ave", "Main Hwy", "Grand Ave", "Tigertail Ave", "S Bayshore Ln", "Bayshore Dr" },
			ZNames = { "Coral Way", "Bird Rd", "Miracle Mile", "Sunset Dr", "Kendall Dr" },
			District = function(bx: number, bz: number): District?
				local x = Layout.SOUTH_XS[bx + 1]
				if x < Layout.GROVE_X - 1 then
					if bx == 1 and bz == 1 then
						return "GablesHotel"
					end
					return "Gables"
				end
				if bx == #Layout.SOUTH_XS - 2 then
					return "GroveBay"
				end
				return "Grove"
			end,
		},
		{
			Name = "Key",
			XS = Layout.KEY_XS,
			ZS = Layout.KEY_ZS,
			XW = widths(3, { [2] = 40 }),
			ZW = widths(4),
			XNames = { "Harbor Dr", "Crandon Blvd", "Ocean Ln" },
			ZNames = { "Harbor Rd", "Rickenbacker Way", "Galen Dr", "Cape Dr" },
			District = function(bx: number, _bz: number): District?
				return if bx == 0 then "KeyHomes" else "KeyPark"
			end,
		},
	}

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
	for _, spec in GRIDS do
		for bz = 0, #spec.ZS - 2 do
			for bx = 0, #spec.XS - 2 do
				local district = spec.District(bx, bz)
				if district then
					local minX = spec.XS[bx + 1] + spec.XW[bx + 1] / 2
					local maxX = spec.XS[bx + 2] - spec.XW[bx + 2] / 2
					local minZ = spec.ZS[bz + 1] + spec.ZW[bz + 1] / 2
					local maxZ = spec.ZS[bz + 2] - spec.ZW[bz + 2] / 2
					local block: Block = {
						Bx = bx,
						Bz = bz,
						Grid = spec.Name,
						District = district :: District,
						MinX = minX,
						MaxX = maxX,
						MinZ = minZ,
						MaxZ = maxZ,
						LotMinX = minX + sidewalkFor(spec.XW[bx + 1]),
						LotMaxX = maxX - sidewalkFor(spec.XW[bx + 2]),
						LotMinZ = minZ + sidewalkFor(spec.ZW[bz + 1]),
						LotMaxZ = maxZ - sidewalkFor(spec.ZW[bz + 2]),
					}
					table.insert(Layout.Blocks, block)
				end
			end
		end
	end

	-- A downtown block by its indices
	function Layout.BlockAt(bx: number, bz: number): Block
		return mainBlocks[bz * (count - 1) + bx]
	end

	-- A block of any grid by its indices
	function Layout.GridBlock(grid: string, bx: number, bz: number): Block?
		for _, block in Layout.Blocks do
			if block.Grid == grid and block.Bx == bx and block.Bz == bz then
				return block
			end
		end
		return nil
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
	local names: { [number]: { string } } = {} -- crossing node -> { road along Z, road along X }

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
	-- a street or avenue (by width)
	local function road(a: number, b: number, width: number)
		local wide = width > Layout.STREET_WIDTH
		addEdge(a, b, if wide then "Avenue" else "Street", width, if wide then 2 else 1)
	end

	-- Downtown's grid crossings
	local ROAD = Layout.ROAD_Y
	local gridNode: { [number]: { [number]: number } } = {}
	Layout.GridNodes = {} :: { number } -- every crossing of every grid
	for i = 0, count - 1 do
		gridNode[i] = {}
		for j = 0, count - 1 do
			local id = addNode(Vector3.new(Layout.Line(i), ROAD, Layout.Line(j)), true, i, j)
			Layout.Nodes[id].WX = Layout.LineWidthX(i)
			Layout.Nodes[id].WZ = Layout.LineWidthZ(j)
			gridNode[i][j] = id
			names[id] = { Layout.X_NAMES[i + 1], Layout.Z_NAMES[j + 1] }
			table.insert(Layout.GridNodes, id)
		end
	end
	Layout.GridNode = gridNode

	-- Extra T-junctions part-way along a downtown grid line (ramp feet, causeway and bridge ends):
	-- keyed by line, each a list of { At = coordinate along the line, Node = id }
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
	-- causeway landings and the port bridge on Biscayne Blvd
	local causewayFeet: { number } = {}
	for _, z in { -900 * KS, 900 * KS } do
		table.insert(causewayFeet, splitXLine(Layout.BAY_INDEX, z))
	end
	local portFoot = splitXLine(Layout.BAY_INDEX, Layout.PORT_ROAD_Z)

	-- Downtown's road pieces, through the splits
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

	-- The other grids
	Layout.Grids = {} :: { [string]: { [number]: { [number]: number } } } -- name -> [i][j] node (1-based)
	for _, spec in GRIDS do
		local nodes: { [number]: { [number]: number } } = {}
		for i, x in spec.XS do
			nodes[i] = {}
			for j, z in spec.ZS do
				local id = addNode(Vector3.new(x, ROAD, z), true)
				Layout.Nodes[id].WX = spec.XW[i]
				Layout.Nodes[id].WZ = spec.ZW[j]
				nodes[i][j] = id
				names[id] = { spec.XNames[i], spec.ZNames[j] }
				table.insert(Layout.GridNodes, id)
			end
		end
		for i = 1, #spec.XS do
			for j = 1, #spec.ZS - 1 do
				road(nodes[i][j], nodes[i][j + 1], spec.XW[i])
			end
		end
		for j = 1, #spec.ZS do
			for i = 1, #spec.XS - 1 do
				road(nodes[i][j], nodes[i + 1][j], spec.ZW[j])
			end
		end
		Layout.Grids[spec.Name] = nodes
	end
	local islandGrid = Layout.Grids.Island
	Layout.IslandGrid = islandGrid
	local havana = Layout.Grids.Havana
	local south = Layout.Grids.South
	local key = Layout.Grids.Key
	local function gridAt(nodes: { [number]: { [number]: number } }, xs: { number }, zs: { number }, x: number, z: number): number
		for i, xx in xs do
			for j, zz in zs do
				if math.abs(xx - x) < 1 and math.abs(zz - z) < 1 then
					return nodes[i][j]
				end
			end
		end
		error(string.format("no crossing at %.0f, %.0f", x, z))
	end
	local function islandNodeAtZ(z: number): number
		return gridAt(islandGrid, Layout.ISLAND_XS, islandZS, Layout.ISLAND_XS[1], z)
	end

	-- The turnpike: north, west and south of downtown (a U with rounded western corners), its ends
	-- on Biscayne Blvd. Split where the roads out to the new districts cross it.
	local RING_SEGMENTS_PER_CORNER = 6
	local ringNodes: { number } = {}
	local ringAt: { [string]: number } = {}
	local i95North, i95South
	do
		local h, r = Layout.RING_HALF, Layout.RING_RADIUS
		local inner = h - r
		local bayX = Layout.Line(Layout.BAY_INDEX)
		local function add(p: Vector3, tag: string?): number
			local id = addNode(p, false)
			table.insert(ringNodes, id)
			if tag then
				ringAt[tag] = id
			end
			return id
		end
		-- north side, east to west
		add(Vector3.new(bayX, ROAD, -h), "NE")
		i95North = add(Vector3.new(Layout.I95_X, ROAD, -h))
		add(Vector3.new(0, ROAD, -h), "N")
		add(Vector3.new(-1200 * KS, ROAD, -h), "Airport")
		-- north-west corner: from the north side round to the west side
		for k = 0, RING_SEGMENTS_PER_CORNER do
			local angle = -math.pi / 2 - (math.pi / 2) * k / RING_SEGMENTS_PER_CORNER
			add(Vector3.new(-inner + math.cos(angle) * r, ROAD, -inner + math.sin(angle) * r))
		end
		add(Vector3.new(-h, ROAD, 0), "W")
		add(Vector3.new(-h, ROAD, Layout.TAMIAMI_Z), "Ocho")
		-- south-west corner
		for k = 0, RING_SEGMENTS_PER_CORNER do
			local angle = math.pi - (math.pi / 2) * k / RING_SEGMENTS_PER_CORNER
			add(Vector3.new(-inner + math.cos(angle) * r, ROAD, inner + math.sin(angle) * r))
		end
		add(Vector3.new(-1440 * KS, ROAD, h), "S1")
		add(Vector3.new(-720 * KS, ROAD, h), "S2")
		add(Vector3.new(0, ROAD, h), "S")
		i95South = add(Vector3.new(Layout.I95_X, ROAD, h))
		add(Vector3.new(720 * KS, ROAD, h), "S3")
		add(Vector3.new(bayX, ROAD, h), "SE")
		for k = 1, #ringNodes - 1 do
			addEdge(ringNodes[k], ringNodes[k + 1], "Highway", Layout.RING_WIDTH, 2)
		end
		-- Biscayne Blvd carries on to the turnpike's ends
		addEdge(ringAt.NE, gridNode[Layout.BAY_INDEX][0], "Avenue", Layout.AVENUE_WIDTH, 2)
		addEdge(gridNode[Layout.BAY_INDEX][count - 1], ringAt.SE, "Avenue", Layout.AVENUE_WIDTH, 2)
	end
	Layout.RingNodes = ringNodes

	-- Country roads from the avenue ends out to the turnpike (north, west, south)
	local last = count - 1
	local mid = Layout.AVENUE_INDEX
	addEdge(gridNode[mid][0], ringAt.N, "Rural", Layout.RURAL_WIDTH, 1)
	addEdge(gridNode[mid][last], ringAt.S, "Rural", Layout.RURAL_WIDTH, 1)
	addEdge(gridNode[0][mid], ringAt.W, "Rural", Layout.RURAL_WIDTH, 1)

	-- Out to the new districts
	-- west: Flagler St and Calle Ocho into Little Havana; Calle Ocho on as the Tamiami Trail
	local hx, hz = Layout.HAVANA_XS, Layout.HAVANA_ZS
	addEdge(ringAt.W, gridAt(havana, hx, hz, hx[#hx], 0), "Avenue", 40 * K, 2)
	addEdge(gridNode[0][5], ringAt.Ocho, "Avenue", 40 * K, 2)
	addEdge(ringAt.Ocho, gridAt(havana, hx, hz, hx[#hx], Layout.TAMIAMI_Z), "Avenue", 40 * K, 2)
	Layout.TamiamiTrail = {} :: { number }
	do
		local previous = gridAt(havana, hx, hz, hx[1], Layout.TAMIAMI_Z)
		for _, x in { -3700 * KS, -4160 * KS } do
			local id = addNode(Vector3.new(x, ROAD, Layout.TAMIAMI_Z), false)
			addEdge(previous, id, "Rural", Layout.RURAL_WIDTH, 1)
			table.insert(Layout.TamiamiTrail, id)
			previous = id
		end
	end
	-- Little Havana down to Coral Gables (two streets past the turnpike's corner)
	local sx, sz = Layout.SOUTH_XS, Layout.SOUTH_ZS
	for _, x in { hx[2], hx[#hx] } do
		road(gridAt(havana, hx, hz, x, hz[#hz]), gridAt(south, sx, sz, x, sz[1]), Layout.STREET_WIDTH)
	end
	-- south: downtown's avenues on through the turnpike into the Gables and the Grove
	local links: { { I: number, Tag: string } } = { { I = 0, Tag = "S1" }, { I = 2, Tag = "S2" }, { I = 6, Tag = "S3" } }
	for _, link in links do
		local i, tag = link.I, link.Tag
		local x = Layout.Line(i)
		road(gridNode[i][last], ringAt[tag], Layout.STREET_WIDTH)
		road(ringAt[tag], gridAt(south, sx, sz, x, sz[1]), Layout.STREET_WIDTH)
	end
	road(ringAt.S, gridAt(south, sx, sz, 0, sz[1]), 40 * K)
	addEdge(ringAt.SE, gridAt(south, sx, sz, sx[#sx], sz[1]), "Avenue", Layout.AVENUE_WIDTH, 2)
	-- north: Biscayne Blvd on along the bay; the 79th St causeway to North Beach; the airport road
	Layout.CAUSEWAY_ZS = { -2700 * KS, -900 * KS, 900 * KS }
	local north79 = addNode(Vector3.new(Layout.Line(Layout.BAY_INDEX), ROAD, -2700 * KS), false)
	Layout.BAY_NORTH_Z = -3780 * KS -- where Biscayne Blvd ends, north of the turnpike
	local northEnd = addNode(Vector3.new(Layout.Line(Layout.BAY_INDEX), ROAD, Layout.BAY_NORTH_Z), false)
	addEdge(ringAt.NE, north79, "Avenue", Layout.AVENUE_WIDTH, 2)
	addEdge(north79, northEnd, "Avenue", Layout.AVENUE_WIDTH, 2)
	table.insert(causewayFeet, 1, north79)
	Layout.AIRPORT_ROAD_Z = -2400 * KS
	Layout.AirportRoad = {} :: { number }
	do
		local previous = ringAt.Airport
		local turn = addNode(Vector3.new(-1200 * KS, ROAD, Layout.AIRPORT_ROAD_Z), false)
		addEdge(previous, turn, "Avenue", 40 * K, 2)
		previous = turn
		table.insert(Layout.AirportRoad, turn)
		for _, x in { -1800 * KS, -2400 * KS, -3100 * KS } do
			local id = addNode(Vector3.new(x, ROAD, Layout.AIRPORT_ROAD_Z), false)
			addEdge(previous, id, "Avenue", 40 * K, 2)
			table.insert(Layout.AirportRoad, id)
			previous = id
		end
	end

	-- I-95: up on the deck over every cross street, the I-395 junction, down to the turnpike at each end
	local H = Layout.FREEWAY_Y
	local FW = Layout.FREEWAY_WIDTH
	Layout.I95 = {} :: { number } -- north to south, ground ends included
	local i95At: { [number]: number } = {} -- deck node over downtown z line j
	local junction: number
	do
		local x = Layout.I95_X
		local descent = 400 * KS -- a 5% grade from the deck to the turnpike
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
	-- bridge, down onto the island's 5th St
	Layout.I395 = { junction } :: { number }
	do
		local z = Layout.I395_Z
		for i = Layout.AVENUE_INDEX + 1, Layout.BAY_INDEX do
			table.insert(Layout.I395, addNode(Vector3.new(Layout.Line(i), H, z), false))
		end
		table.insert(Layout.I395, addNode(Vector3.new(2400 * KS, H, z), false))
		table.insert(Layout.I395, addNode(Vector3.new(Layout.ISLAND.MinX + 40 * K, ROAD, z), false))
	end
	table.insert(Layout.I395, islandNodeAtZ(Layout.I395_Z))
	for k = 1, #Layout.I395 - 1 do
		local last395 = k == #Layout.I395 - 1
		addEdge(Layout.I395[k], Layout.I395[k + 1], if last395 then "Avenue" else "Freeway", if last395 then Layout.AVENUE_WIDTH else FW, if last395 then 2 else 3)
	end

	-- Causeways: low roads across the bay on rock embankments (79th St, Venetian, MacArthur), the
	-- port's bridge, the Rickenbacker Causeway to Key Biscayne
	Layout.Causeways = {} :: { { A: number, B: number, Z: number } }
	for k, z in Layout.CAUSEWAY_ZS do
		local island = islandNodeAtZ(z)
		addEdge(causewayFeet[k], island, "Causeway", Layout.STREET_WIDTH + 4 * K, 1)
		table.insert(Layout.Causeways, { A = causewayFeet[k], B = island, Z = z })
	end
	do
		local quay = addNode(Vector3.new(Layout.PORT.MinX + 40 * K, ROAD, Layout.PORT_ROAD_Z), false)
		local far = addNode(Vector3.new(Layout.PORT.MaxX - 40 * K, ROAD, Layout.PORT_ROAD_Z), false)
		addEdge(portFoot, quay, "Causeway", Layout.STREET_WIDTH + 4 * K, 1)
		addEdge(quay, far, "Street", Layout.STREET_WIDTH, 1)
		table.insert(Layout.Causeways, { A = portFoot, B = quay, Z = Layout.PORT_ROAD_Z })
		Layout.PortRoad = { quay, far }
		Layout.RICKENBACKER_Z = 2880 * KS
		local from = gridAt(south, sx, sz, sx[#sx], Layout.RICKENBACKER_Z)
		local to = gridAt(key, Layout.KEY_XS, Layout.KEY_ZS, Layout.KEY_XS[1], Layout.RICKENBACKER_Z)
		addEdge(from, to, "Causeway", Layout.STREET_WIDTH + 14 * K, 1)
		table.insert(Layout.Causeways, { A = from, B = to, Z = Layout.RICKENBACKER_Z })
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

	-- Street names at a grid crossing: the road along Z, then the road along X
	function Layout.CrossingNames(nodeId: number): (string, string)
		local pair = names[nodeId]
		if pair then
			return pair[1], pair[2]
		end
		return "Avenue", "Street"
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
		local avenue = (node.WX or 0) > Layout.STREET_WIDTH or (node.WZ or 0) > Layout.STREET_WIDTH
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
	-- The airport and the ground: where it's built up (the grids, the islands, the airport's
	-- terminal side) and the open land between (Terrain grass at runtime, marsh in the Everglades)
	--------------------------------------------------------------------------------
	Layout.Airport = {
		Rect = rect(-3800 * KS, -1300 * KS, -4000 * KS, -2470 * KS),
		RunwayX0 = -3650 * KS,
		RunwayX1 = -1450 * KS,
		RunwayZ = -3560 * KS,
		RunwayWidth = 160 * K, -- 45 m, an airliner runway
		TaxiwayZ = -3400 * KS,
		Apron = rect(-3300 * KS, -1700 * KS, -3300 * KS, -2840 * KS),
		Terminal = rect(-3200 * KS, -2000 * KS, -2840 * KS, -2600 * KS),
	}
	Layout.EVERGLADES_X = -3330 * KS -- the marsh starts west of here
	local sideW = Layout.STREET_SIDEWALK + 13 * K
	local function gridRect(xs: { number }, zs: { number }, pad: number): Rect
		return rect(xs[1] - pad, xs[#xs] + pad, zs[1] - pad, zs[#zs] + pad)
	end
	Layout.BuiltUp = {
		rect(Layout.Line(0) - sideW - 1, Layout.SHORE_X, Layout.Line(0) - sideW - 1, Layout.Line(last) + sideW + 1),
		Layout.ISLAND,
		Layout.PORT,
		Layout.KEY,
		gridRect(Layout.HAVANA_XS, Layout.HAVANA_ZS, 40 * K),
		gridRect(Layout.SOUTH_XS, Layout.SOUTH_ZS, 40 * K),
		rect(-3300 * KS, -1300 * KS, -2840 * KS, -2300 * KS), -- the terminal, its car park and road
	} :: { Rect }
	do
		local mainland = { rect(-W, Layout.SHORE_X, -W, W) }
		local open = subtractAll(mainland, Layout.Lakes)
		open = subtractAll(open, Layout.BuiltUp)
		-- (the Everglades run south of the airport; its fields are grass)
		local marsh = rect(-W, Layout.EVERGLADES_X, -2300 * KS, W)
		Layout.Marsh = marsh
		local ground: { Ground } = {}
		for _, r in open do
			for _, piece in subtractAll({ r }, { marsh }) do
				table.insert(ground, { MinX = piece.MinX, MaxX = piece.MaxX, MinZ = piece.MinZ, MaxZ = piece.MaxZ, Kind = "Grass" })
			end
			local wet = intersect(r, marsh)
			if wet then
				table.insert(ground, { MinX = wet.MinX, MaxX = wet.MaxX, MinZ = wet.MinZ, MaxZ = wet.MaxZ, Kind = "Marsh" })
			end
		end
		-- open land: Terrain at runtime over a flat (hidden) collider
		Layout.OpenGround = ground
		-- built-up land: ordinary ground parts (the islands' strips, the grids' verges)
		local built: { Rect } = {}
		for _, r in Layout.BuiltUp do
			for _, landRect in Layout.Land do
				local piece = intersect(r, landRect)
				if piece then
					for _, dry in subtractAll({ piece }, Layout.Lakes) do
						table.insert(built, dry)
					end
				end
			end
		end
		Layout.BuiltGround = built
	end

	function Layout.InMarsh(x: number, z: number): boolean
		return inside(Layout.Marsh, x, z) and not Layout.InWater(x, z)
	end

	-- Is (x, z) inside one of the built-up areas (with a margin)
	function Layout.IsBuiltUp(x: number, z: number, margin: number?): boolean
		local m = margin or 0
		for _, r in Layout.BuiltUp do
			if x >= r.MinX - m and x <= r.MaxX + m and z >= r.MinZ - m and z <= r.MaxZ + m then
				return true
			end
		end
		return false
	end

	Layout.Rects = { Subtract = subtractAll, Intersect = intersect, Overlaps = overlaps, New = rect }

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
	-- Flighty Mechanics takes the south middle of its block, this deep and at most this wide (its
	-- grounds and car park the rest)
	Layout.DEALERSHIP_DEPTH = 330 * K
	Layout.DEALERSHIP_WIDTH = 380 * K
	local dealershipEast = (dealership.LotMinX + dealership.LotMaxX) / 2 + math.min(dealership.LotMaxX - dealership.LotMinX, Layout.DEALERSHIP_WIDTH) / 2

	local beachZ = 180 * KS
	-- Flighty Garage: the mechanic's shop beside the showroom (east end of the dealership's lot), its
	-- door on the forecourt (+Z); Lift is the middle of the lift's deck the player's bike stands on
	Layout.Garage = {
		MinX = dealership.LotMaxX - 80 * K,
		MaxX = dealership.LotMaxX - 2 * K,
		MinZ = dealership.LotMinZ + 12 * K,
		MaxZ = dealership.LotMinZ + 118 * K,
		Height = 30 * K,
		Lift = Vector3.new(dealership.LotMaxX - 41 * K, Layout.CURB_Y + 0.3 * K, dealership.LotMinZ + 58 * K),
	}
	Layout.Places = {
		-- Spawn: the forecourt in front of the dealership, facing it (north)
		Spawn = Vector3.new((dealership.LotMinX + dealership.LotMaxX) / 2, Layout.CURB_Y, dealership.LotMaxZ - 50 * K),
		Dealership = Vector3.new((dealership.LotMinX + dealership.LotMaxX) / 2, Layout.CURB_Y, dealership.LotMaxZ - Layout.DEALERSHIP_DEPTH / 2),
		-- (on the forecourt, just outside the garage's door)
		Garage = Vector3.new(dealership.LotMaxX - 41 * K, Layout.CURB_Y, dealership.LotMinZ + 128 * K),
		Police = lotCenter(police),
		-- (inside its south edge: the park keeps its ridden size, so what's in its middle depends on
		-- how big the city's lots are)
		JumpPark = Vector3.new((jump.LotMinX + jump.LotMaxX) / 2, Layout.CURB_Y, jump.LotMaxZ - 10 * K),
		-- (south of the fountains)
		Plaza = lotCenter(plaza) + Vector3.new(0, 0, 45 * K),
		Park = lotCenter(bayPark) + Vector3.new(0, 0, 60 * K),
		-- on the streets through them (their blocks are built up)
		Downtown = Vector3.new(Layout.Line(5) + 180 * KS, Layout.ROAD_Y, Layout.Line(Layout.AVENUE_INDEX) + 12 * K),
		Wynwood = Vector3.new(Layout.Line(6), Layout.ROAD_Y, Layout.Line(0) + 180 * KS),
		Beach = Vector3.new(Layout.BEACH_X - 4 * K, Layout.CURB_Y, beachZ), -- the beach walk
		NorthBeach = Vector3.new(Layout.BEACH_X - 4 * K, Layout.CURB_Y, -2520 * KS),
		LittleHavana = Vector3.new((hx[2] + hx[3]) / 2, Layout.ROAD_Y, Layout.TAMIAMI_Z + 8 * K),
		CoralGables = Vector3.new(-1980 * KS, Layout.ROAD_Y, sz[2]), -- (mid-road: Bird Rd is narrow)
		CoconutGrove = Vector3.new(540 * KS, Layout.ROAD_Y, Layout.RICKENBACKER_Z + 8 * K),
		KeyBiscayne = Vector3.new(Layout.KEY_BEACH_X - 4 * K, Layout.CURB_Y, 3060 * KS),
		Port = Vector3.new(2000 * KS, Layout.ROAD_Y, Layout.PORT_ROAD_Z + 6 * K),
		Airport = Vector3.new(Layout.Airport.RunwayX0 + 60 * K, Layout.ROAD_Y, Layout.Airport.RunwayZ),
		Everglades = Vector3.new(-3900 * KS, Layout.ROAD_Y, Layout.TAMIAMI_Z + 6 * K),
		Countryside = Vector3.new(-Layout.RING_HALF + 40 * K, Layout.ROAD_Y, 0),
	}

	-- Teleports offered in the Menus panel
	Layout.Teleports = {
		{ Id = "Dealership", Name = "Flighty Mechanics" },
		{ Id = "Garage", Name = "Flighty Garage (tuning)" },
		{ Id = "JumpPark", Name = "Jump Park" },
		{ Id = "Downtown", Name = "Downtown" },
		{ Id = "Wynwood", Name = "Wynwood" },
		{ Id = "Park", Name = "Bayfront Park" },
		{ Id = "Beach", Name = "South Beach" },
		{ Id = "NorthBeach", Name = "North Beach" },
		{ Id = "LittleHavana", Name = "Little Havana" },
		{ Id = "CoralGables", Name = "Coral Gables" },
		{ Id = "CoconutGrove", Name = "Coconut Grove" },
		{ Id = "KeyBiscayne", Name = "Key Biscayne" },
		{ Id = "Port", Name = "Port of Miami" },
		{ Id = "Airport", Name = "Airport runway" },
		{ Id = "Everglades", Name = "Everglades" },
		{ Id = "Plaza", Name = "City Plaza" },
	}

	-- Charging stations: kiosk positions (on pads, by the kerb) and which way each faces (its street)
	local fastFood = Layout.BlockAt(2, 3)
	local wynwood = Layout.BlockAt(5, 0)
	local downtown = Layout.BlockAt(5, 4)
	local brickell = Layout.BlockAt(6, 6)
	local havanaBlock = Layout.GridBlock("Havana", 1, 2) :: Block
	local gablesBlock = Layout.GridBlock("South", 3, 1) :: Block
	local groveBlock = Layout.GridBlock("South", 9, 1) :: Block
	local northBeach = Layout.GridBlock("Island", 1, 4) :: Block
	Layout.Chargers = {
		Vector3.new(dealershipEast - 20 * K, Layout.CURB_Y, dealership.LotMaxZ - 20 * K),
		Vector3.new(plaza.LotMinX + 20 * K, Layout.CURB_Y, plaza.LotMaxZ - 20 * K),
		Vector3.new(jump.LotMaxX - 15 * K, Layout.CURB_Y, jump.LotMaxZ - 15 * K),
		Vector3.new(fastFood.LotMinX + 20 * K, Layout.CURB_Y, fastFood.LotMaxZ - 15 * K),
		Vector3.new(downtown.LotMinX + 15 * K, Layout.CURB_Y, downtown.LotMaxZ - 8 * K),
		-- on the pavements of the built-up blocks, facing the street
		Vector3.new((wynwood.MinX + wynwood.MaxX) / 2, Layout.CURB_Y, wynwood.MaxZ - 9 * K),
		Vector3.new((brickell.MinX + brickell.MaxX) / 2, Layout.CURB_Y, brickell.MinZ + 9 * K),
		Vector3.new(police.LotMinX + 20 * K, Layout.CURB_Y, police.LotMinZ + 20 * K),
		Vector3.new(Layout.BEACH_X - 30 * K, Layout.CURB_Y, beachZ + 40 * K), -- on the beach walk
		Vector3.new(40 * K, Layout.ROAD_Y, -Layout.RING_HALF + 70 * K), -- country stop on the north road
		Vector3.new((havanaBlock.MinX + havanaBlock.MaxX) / 2, Layout.CURB_Y, havanaBlock.MaxZ - 9 * K),
		Vector3.new((gablesBlock.MinX + gablesBlock.MaxX) / 2, Layout.CURB_Y, gablesBlock.MinZ + 9 * K),
		Vector3.new((groveBlock.MinX + groveBlock.MaxX) / 2, Layout.CURB_Y, groveBlock.MinZ + 9 * K),
		Vector3.new(Layout.BEACH_X - 30 * K, Layout.CURB_Y, (northBeach.MinZ + northBeach.MaxZ) / 2),
		Vector3.new(Layout.KEY_BEACH_X - 30 * K, Layout.CURB_Y, 3000 * KS),
		Vector3.new(-1500 * KS, Layout.ROAD_Y, Layout.AIRPORT_ROAD_Z - 40 * K), -- airport car park
		Vector3.new(-3900 * KS, Layout.ROAD_Y, Layout.TAMIAMI_Z + 40 * K), -- Everglades airboat dock
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
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(0, 0, -1),
		Vector3.new(-1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
	}

	-- Where pursuing cops enter the map: the crossing by the police station
	Layout.PoliceSpawn = gridNode[3][5]

	return Layout
end

local Layout = make(Config.WORLD_SCALE)
-- The same city in design units (K = 1), for the builders
;(Layout :: any).Design = make(1)

return Layout
