--[[
	Builder: builds the whole city from Layout. Deterministic (fixed seed), so the baked copy in
	map/City.rbxm and a runtime rebuild are identical. Bake: lune run tools/lune/bake_city.luau
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Roads = require(script.Parent.Roads)
local Buildings = require(script.Parent.Buildings)
local Landmarks = require(script.Parent.Landmarks)
local Countryside = require(script.Parent.Countryside)
local Detail = require(script.Parent.Detail)
local Freeways = require(script.Parent.Freeways)
local Shore = require(script.Parent.Shore)
local Neighborhoods = require(script.Parent.Neighborhoods)
local Airport = require(script.Parent.Airport)
local Port = require(script.Parent.Port)
local Everglades = require(script.Parent.Everglades)
local Realism = require(script.Parent.Parent.Realism)
local PartKit = require(script.Parent.Parent.PartKit)
local Config = require(script.Parent.Parent.Config)

local Builder = {}

Builder.SEED = 20261019

local C = Props.Palette
local Y = Layout.CURB_Y
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }

-- Raised pads between the carriageways (pavement and kerb), with a light kerb line
local function pads(city: Instance)
	local folder = PartKit.Folder(city, "Pads")
	local thickness = Y + 0.4
	local function pad(minX: number, maxX: number, minZ: number, maxZ: number)
		if maxX - minX < 1 or maxZ - minZ < 1 then
			return
		end
		local w, d = maxX - minX, maxZ - minZ
		local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
		local p = PartKit.Box(folder, "Pavement", Vector3.new(w, thickness, d), CFrame.new(cx, Y - thickness / 2, cz), C.Pavement, Enum.Material.Pavement)
		p:SetAttribute("Surface", "Sidewalk")
		-- kerb stones
		PartKit.Box(folder, "Kerb", Vector3.new(w, 0.06, 1.1), CFrame.new(cx, Y + 0.01, minZ + 0.55), C.Kerb, Enum.Material.Concrete, DECOR)
		PartKit.Box(folder, "Kerb", Vector3.new(w, 0.06, 1.1), CFrame.new(cx, Y + 0.01, maxZ - 0.55), C.Kerb, Enum.Material.Concrete, DECOR)
		PartKit.Box(folder, "Kerb", Vector3.new(1.1, 0.06, d), CFrame.new(minX + 0.55, Y + 0.01, cz), C.Kerb, Enum.Material.Concrete, DECOR)
		PartKit.Box(folder, "Kerb", Vector3.new(1.1, 0.06, d), CFrame.new(maxX - 0.55, Y + 0.01, cz), C.Kerb, Enum.Material.Concrete, DECOR)
	end
	-- a pad along X from x0 to x1 with gaps cut out of it ({ from, to } in x)
	local function padX(x0: number, x1: number, z0: number, z1: number, gaps: { { number } })
		table.sort(gaps, function(a, b)
			return a[1] < b[1]
		end)
		local from = x0
		for _, gap in gaps do
			pad(from, math.min(gap[1], x1), z0, z1)
			from = math.max(from, gap[2])
		end
		pad(from, x1, z0, z1)
	end
	local function padZ(x0: number, x1: number, z0: number, z1: number, gaps: { { number } })
		table.sort(gaps, function(a, b)
			return a[1] < b[1]
		end)
		local from = z0
		for _, gap in gaps do
			pad(x0, x1, from, math.min(gap[1], z1))
			from = math.max(from, gap[2])
		end
		pad(x0, x1, from, z1)
	end

	for _, block in Layout.Blocks do
		if block.District ~= "Freeway" then
			pad(block.MinX, block.MaxX, block.MinZ, block.MaxZ)
			continue
		end
		-- under I-95: pavements either side, a car park at street level in the middle (piers, the
		-- ramps), entered through gaps in the pavements across its ends
		local u0, u1 = Layout.UnderDeck(block)
		local swN = Layout.LineSidewalk(block.Bz)
		local swS = Layout.LineSidewalk(block.Bz + 1)
		pad(block.MinX, u0, block.MinZ, block.MaxZ)
		pad(u1, block.MaxX, block.MinZ, block.MaxZ)
		local north: { { number } } = {}
		local south: { { number } } = {}
		local ramps = false
		for _, ramp in Layout.Ramps do
			local foot = Layout.Nodes[ramp.Foot].Position
			local mouth = { foot.X - Layout.RAMP_WIDTH / 2 - 1, foot.X + Layout.RAMP_WIDTH / 2 + 1 }
			if math.abs(foot.Z - Layout.Line(block.Bz)) < 1 then
				table.insert(north, mouth)
				ramps = true
			elseif math.abs(foot.Z - Layout.Line(block.Bz + 1)) < 1 then
				table.insert(south, mouth)
				ramps = true
			end
		end
		-- driveways into the car park
		local drive = { Layout.I95_X - 12, Layout.I95_X + 12 }
		if not ramps or #north == 0 then
			table.insert(north, drive)
		end
		if not ramps or #south == 0 then
			table.insert(south, drive)
		end
		padX(u0, u1, block.MinZ, block.MinZ + swN, north)
		padX(u0, u1, block.MaxZ - swS, block.MaxZ, south)
		Roads.Slab(folder, "CarPark", Vector3.new((u0 + u1) / 2, 0, (block.MinZ + block.MaxZ) / 2), Vector3.new(u1 - u0, 0, block.MaxZ - block.MinZ))
	end

	-- pavements round the outside of each street grid, with gaps where roads leave it
	local swOut = Layout.STREET_SIDEWALK
	local function outer(nodeAt: (number, number) -> number, xs: { number }, zs: { number }, xw: { number }, zw: { number }, east: boolean)
		local nx, nz = #xs, #zs
		local inGrid: { [number]: boolean } = {}
		for i = 1, nx do
			for j = 1, nz do
				inGrid[nodeAt(i, j)] = true
			end
		end
		-- the roads leaving the grid from its edge crossings, by side
		local gaps: { [string]: { { number } } } = { N = {}, S = {}, W = {}, E = {} }
		for i = 1, nx do
			for j = 1, nz do
				local id = nodeAt(i, j)
				local p = Layout.Nodes[id].Position
				for _, edgeId in Layout.Nodes[id].Edges do
					local edge = Layout.Edges[edgeId]
					local other = Layout.OtherEnd(edge, id)
					if not inGrid[other] then
						local d = Layout.Nodes[other].Position - p
						local half = edge.Width / 2 + 1
						if j == 1 and d.Z < -1 and math.abs(d.X) < math.abs(d.Z) then
							table.insert(gaps.N, { p.X - half, p.X + half })
						elseif j == nz and d.Z > 1 and math.abs(d.X) < math.abs(d.Z) then
							table.insert(gaps.S, { p.X - half, p.X + half })
						elseif i == 1 and d.X < -1 and math.abs(d.Z) < math.abs(d.X) then
							table.insert(gaps.W, { p.Z - half, p.Z + half })
						elseif i == nx and d.X > 1 and math.abs(d.Z) < math.abs(d.X) then
							table.insert(gaps.E, { p.Z - half, p.Z + half })
						end
					end
				end
			end
		end
		local west = xs[1] - xw[1] / 2
		local eastX = xs[nx] + xw[nx] / 2
		local north = zs[1] - zw[1] / 2
		local south = zs[nz] + zw[nz] / 2
		-- (a grid whose east side is the bay's avenue stops at its west kerb: the baywalk is east)
		local x1 = if east then eastX + swOut else xs[nx] - xw[nx] / 2
		padX(west - swOut, x1, north - swOut, north, gaps.N)
		padX(west - swOut, x1, south, south + swOut, gaps.S)
		padZ(west - swOut, west, north, south, gaps.W)
		if east then
			padZ(eastX, eastX + swOut, north, south, gaps.E)
		end
	end
	local mainXs, mainZs, mainXw, mainZw = {}, {}, {}, {}
	for k = 0, Layout.GRID_COUNT - 1 do
		table.insert(mainXs, Layout.Line(k))
		table.insert(mainZs, Layout.Line(k))
		table.insert(mainXw, Layout.LineWidthX(k))
		table.insert(mainZw, Layout.LineWidthZ(k))
	end
	outer(function(i: number, j: number): number
		return Layout.GridNode[i - 1][j - 1]
	end, mainXs, mainZs, mainXw, mainZw, false)
	local function widthsOf(xs: { number }, node: (number) -> number, axis: string): { number }
		local out = {}
		for k = 1, #xs do
			local n = Layout.Nodes[node(k)]
			table.insert(out, (if axis == "X" then n.WX else n.WZ) or Layout.STREET_WIDTH)
		end
		return out
	end
	for _, spec in { { Name = "Havana", XS = Layout.HAVANA_XS, ZS = Layout.HAVANA_ZS, East = true }, { Name = "South", XS = Layout.SOUTH_XS, ZS = Layout.SOUTH_ZS, East = false } } do
		local nodes = Layout.Grids[spec.Name]
		local xw = widthsOf(spec.XS, function(k: number): number
			return nodes[k][1]
		end, "X")
		local zw = widthsOf(spec.ZS, function(k: number): number
			return nodes[1][k]
		end, "Z")
		outer(function(i: number, j: number): number
			return nodes[i][j]
		end, spec.XS, spec.ZS, xw, zw, spec.East)
	end

	-- Biscayne Blvd's west pavement where it runs on past the turnpike (north to its end, south
	-- to Bayshore Dr)
	local bayWest = Layout.Line(Layout.BAY_INDEX) - Layout.LineWidthX(Layout.BAY_INDEX) / 2
	local ringIn = Layout.RING_HALF - Layout.RING_WIDTH / 2
	local ringOut = Layout.RING_HALF + Layout.RING_WIDTH / 2
	local outerN = Layout.Line(0) - Layout.LineWidthZ(0) / 2
	local outerS = Layout.Line(Layout.GRID_COUNT - 1) + Layout.LineWidthZ(Layout.GRID_COUNT - 1) / 2
	pad(bayWest - Layout.AVENUE_SIDEWALK, bayWest, -ringIn, outerN - swOut)
	pad(bayWest - Layout.AVENUE_SIDEWALK, bayWest, outerS + swOut, ringIn)
	pad(bayWest - Layout.AVENUE_SIDEWALK, bayWest, -3780 - Layout.AVENUE_WIDTH / 2, -ringOut)
	pad(bayWest - Layout.AVENUE_SIDEWALK, bayWest, ringOut, Layout.SOUTH_ZS[1] - Layout.STREET_WIDTH / 2 - swOut)

	-- the islands' edges: Miami Beach and Key Biscayne
	local function islandEdges(xs: { number }, xw: { number }, zs: { number }, zw: { number }, minX: number, beachX: number, landings: { { number } })
		local westAve = xs[1] - xw[1] / 2
		local oceanDr = xs[#xs] + xw[#xs] / 2
		local zTop = zs[1] - zw[1] / 2
		local zBottom = zs[#zs] + zw[#zs] / 2
		-- the bay side: pavement where it's narrow, a pavement and a lawn down to the rocks where
		-- it's wide; the causeways land through gaps
		if westAve - swOut - minX > 40 then
			padZ(westAve - swOut, westAve, zTop - swOut, zBottom + swOut, table.clone(landings))
			local x0, x1 = minX + 8, westAve - swOut
			local sorted = table.clone(landings)
			table.sort(sorted, function(a, b)
				return a[1] < b[1]
			end)
			local from = zTop - swOut
			local function lawn(z0: number, z1: number)
				if z1 - z0 > 1 then
					local part = PartKit.Box(folder, "Lawn", Vector3.new(x1 - x0, Y + 0.4, z1 - z0), CFrame.new((x0 + x1) / 2, (Y - 0.4) / 2, (z0 + z1) / 2), C.Lawn, Enum.Material.Grass)
					part:SetAttribute("Surface", "Grass")
				end
			end
			for _, gap in sorted do
				lawn(from, math.min(gap[1], zBottom + swOut))
				from = math.max(from, gap[2])
			end
			lawn(from, zBottom + swOut)
		else
			padZ(minX + 8, westAve, zTop - swOut, zBottom + swOut, table.clone(landings))
		end
		-- the ocean side: a pavement, then a lawn of palms down to the beach path
		pad(oceanDr, oceanDr + swOut + 2, zTop - swOut, zBottom + swOut)
		local lawnX0, lawnX1 = oceanDr + swOut + 2, beachX - 8
		local lawn = PartKit.Box(folder, "Lawn", Vector3.new(lawnX1 - lawnX0, Y + 0.4, zBottom - zTop + 2 * swOut), CFrame.new((lawnX0 + lawnX1) / 2, (Y - 0.4) / 2, (zTop + zBottom) / 2), C.Lawn, Enum.Material.Grass)
		lawn:SetAttribute("Surface", "Grass")
		pad(beachX - 8, beachX, zTop - swOut, zBottom + swOut)
		pad(westAve, oceanDr, zTop - swOut, zTop)
		pad(westAve, oceanDr, zBottom, zBottom + swOut)
	end
	local landings: { { number } } = { { Layout.I395_Z - Layout.AVENUE_WIDTH / 2 - 2, Layout.I395_Z + Layout.AVENUE_WIDTH / 2 + 2 } }
	for _, z in Layout.CAUSEWAY_ZS do
		table.insert(landings, { z - Layout.STREET_WIDTH / 2 - 4, z + Layout.STREET_WIDTH / 2 + 4 })
	end
	islandEdges(Layout.ISLAND_XS, Layout.ISLAND_X_WIDTHS, Layout.ISLAND_ZS, Layout.ISLAND_Z_WIDTHS, Layout.ISLAND.MinX, Layout.BEACH_X, landings)
	local keyNodes = Layout.Grids.Key
	local keyXw = widthsOf(Layout.KEY_XS, function(k: number): number
		return keyNodes[k][1]
	end, "X")
	local keyZw = widthsOf(Layout.KEY_ZS, function(k: number): number
		return keyNodes[1][k]
	end, "Z")
	local rick = Layout.STREET_WIDTH + 14
	islandEdges(Layout.KEY_XS, keyXw, Layout.KEY_ZS, keyZw, Layout.KEY.MinX, Layout.KEY_BEACH_X, { { Layout.RICKENBACKER_Z - rick / 2 - 4, Layout.RICKENBACKER_Z + rick / 2 + 4 } })
end

-- Palms on most pavements, shade trees in the suburbs, the Gables and the Grove, nothing on the
-- industrial and freeway blocks
local SHADE: { [string]: boolean } = { Suburb = true, Gables = true, Grove = true }
-- old-fashioned lamps (not modern street lights) in the leafy districts
local CLASSIC: { [string]: boolean } = { Suburb = true, Plaza = true, Gables = true, GablesHotel = true, Grove = true, Mansion = true, KeyHomes = true }
local function treesFor(district: string): boolean | string
	if SHADE[district] then
		return true
	elseif district == "Wynwood" or district == "Jump" or district == "Freeway" then
		return false
	end
	return "Palm"
end

local function streetscape(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Streetscape")
	for _, block in Layout.Blocks do
		local trees = treesFor(block.District)
		local modern = not CLASSIC[block.District]
		local inset = 2.5
		local x0, x1 = block.MinX + inset, block.MaxX - inset
		local z0, z1 = block.MinZ + inset, block.MaxZ - inset
		if block.District == "Freeway" then
			-- the pads either side of the car park under I-95
			local u0, u1 = Layout.UnderDeck(block)
			Props.Streetscape(folder, Vector3.new(x0, Y, z0 + 10), Vector3.new(x0, Y, z1 - 10), rng, false, Vector3.new(-1, 0, 0))
			Props.Streetscape(folder, Vector3.new(x1, Y, z0 + 10), Vector3.new(x1, Y, z1 - 10), rng, false, Vector3.new(1, 0, 0))
			Props.Streetscape(folder, Vector3.new(x0 + 10, Y, z0), Vector3.new(u0 - 6, Y, z0), rng, false, Vector3.new(0, 0, -1))
			Props.Streetscape(folder, Vector3.new(u1 + 6, Y, z0), Vector3.new(x1 - 10, Y, z0), rng, false, Vector3.new(0, 0, -1))
			Props.Streetscape(folder, Vector3.new(x0 + 10, Y, z1), Vector3.new(u0 - 6, Y, z1), rng, false, Vector3.new(0, 0, 1))
			Props.Streetscape(folder, Vector3.new(u1 + 6, Y, z1), Vector3.new(x1 - 10, Y, z1), rng, false, Vector3.new(0, 0, 1))
			continue
		end
		local function side(a: Vector3, b: Vector3, road: Vector3)
			Props.Streetscape(folder, a, b, rng, trees, if modern then road else nil)
		end
		side(Vector3.new(x0 + 10, Y, z0), Vector3.new(x1 - 10, Y, z0), Vector3.new(0, 0, -1))
		side(Vector3.new(x0 + 10, Y, z1), Vector3.new(x1 - 10, Y, z1), Vector3.new(0, 0, 1))
		side(Vector3.new(x0, Y, z0 + 10), Vector3.new(x0, Y, z1 - 10), Vector3.new(-1, 0, 0))
		side(Vector3.new(x1, Y, z0 + 10), Vector3.new(x1, Y, z1 - 10), Vector3.new(1, 0, 0))
	end
	-- the island's Ocean Drive promenade and West Ave bay walk: palms and lights
	local isl = Layout.ISLAND
	local xs = Layout.ISLAND_XS
	local oceanDr = xs[#xs] + Layout.ISLAND_X_WIDTHS[#xs] / 2
	local westAve = xs[1] - Layout.ISLAND_X_WIDTHS[1] / 2
	Props.Streetscape(folder, Vector3.new(oceanDr + 3, Y, isl.MinZ + 240), Vector3.new(oceanDr + 3, Y, isl.MaxZ - 240), rng, "Palm", Vector3.new(-1, 0, 0))
	Props.Streetscape(folder, Vector3.new(westAve - 3, Y, isl.MinZ + 240), Vector3.new(westAve - 3, Y, isl.MaxZ - 240), rng, "Palm", Vector3.new(1, 0, 0))
end

local BUSY: { [string]: boolean } = { Downtown = true, Brickell = true, Edgewater = true, Midtown = true, Plaza = true, Dealership = true, Police = true, ArtDeco = true, Condo = true, Havana = true, HavanaPark = true }

-- Benches, bins, racks, meters, news boxes and bollards along the pavements; bus stops on the
-- avenues; street-name signs at the crossings
local function furniture(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Furniture")
	local newsColors = { Color3.fromRGB(200, 40, 40), Color3.fromRGB(40, 80, 170), Color3.fromRGB(240, 200, 40), Color3.fromRGB(40, 140, 80) }
	for _, block in Layout.Blocks do
		if not BUSY[block.District] then
			continue
		end
		local inset = 4.5 -- just inside the kerb
		local sides = {
			{ a = Vector3.new(block.MinX + 16, Y, block.MinZ + inset), b = Vector3.new(block.MaxX - 16, Y, block.MinZ + inset), road = Vector3.new(0, 0, -1), line = block.Bz },
			{ a = Vector3.new(block.MinX + 16, Y, block.MaxZ - inset), b = Vector3.new(block.MaxX - 16, Y, block.MaxZ - inset), road = Vector3.new(0, 0, 1), line = block.Bz + 1 },
			{ a = Vector3.new(block.MinX + inset, Y, block.MinZ + 16), b = Vector3.new(block.MinX + inset, Y, block.MaxZ - 16), road = Vector3.new(-1, 0, 0), line = block.Bx },
			{ a = Vector3.new(block.MaxX - inset, Y, block.MinZ + 16), b = Vector3.new(block.MaxX - inset, Y, block.MaxZ - 16), road = Vector3.new(1, 0, 0), line = block.Bx + 1 },
		}
		for _, side in sides do
			local length = (side.b - side.a).Magnitude
			local dir = (side.b - side.a).Unit
			local avenue = block.Grid == "Main" and Layout.IsAvenue(side.line)
			-- the lamps and trees sit every 40 studs from Props.Streetscape; furniture goes between
			local slots = math.floor(length / 40)
			for k = 1, slots - 1 do
				local p = side.a + dir * (k * length / slots + 12)
				local face = CFrame.lookAt(p, p + side.road)
				local r = rng:NextNumber()
				if avenue and k == math.floor(slots / 2) then
					Detail.BusStop(folder, CFrame.lookAt(p - side.road * 2.5, p - side.road * 2.5 + side.road), tostring(rng:NextInteger(2, 48)))
				elseif r < 0.3 then
					Props.Bench(folder, face * CFrame.new(0, 0, 3))
					Detail.Bin(folder, (face * CFrame.new(5, 0, 3)).Position)
				elseif r < 0.5 and block.District == "Midtown" then
					Detail.BikeRack(folder, face * CFrame.new(0, 0, 5), 4)
				elseif r < 0.65 and block.District == "Downtown" then
					Detail.NewsBox(folder, face * CFrame.new(-1.5, 0, 4) * CFrame.Angles(0, math.pi, 0), newsColors[rng:NextInteger(1, #newsColors)])
					Detail.NewsBox(folder, face * CFrame.new(1, 0, 4) * CFrame.Angles(0, math.pi, 0), newsColors[rng:NextInteger(1, #newsColors)])
				elseif r < 0.8 then
					Detail.Bin(folder, (face * CFrame.new(0, 0, 1)).Position)
				end
				if block.District == "Midtown" and not avenue then
					Detail.ParkingMeter(folder, p + side.road * 1.2 - dir * 6)
				end
			end
			-- bollards at both ends of busy sides
			for _, endPoint in { side.a, side.b } do
				for k = 0, 2 do
					Detail.Bollard(folder, endPoint - dir * (k * 3.2) * (if endPoint == side.a then -1 else 1) + side.road * 1.6)
				end
			end
		end
	end
end

local function chargers(city: Instance)
	local folder = PartKit.Folder(city, "Chargers")
	for k, position in Layout.Chargers do
		Props.Charger(folder, position, Layout.ChargerFacing[k] or Vector3.new(0, 0, 1))
	end
end

local function spawnPoint(city: Instance)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(14, 0.4, 14)
	spawn.CFrame = CFrame.new(Layout.Places.Spawn + Vector3.new(0, 0.5, 0)) -- faces north (-Z), toward the showroom
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 122, 24)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Transparency = 0.2
	spawn.CanCollide = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = city
end

-- The islands' ends: South Pointe, the park at North Beach's tip and Key Biscayne's ends; palms
-- and a path on the grass
local function islandEnds(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "IslandParks")
	local keyNodes = Layout.Grids.Key
	local keyW = Layout.Nodes[keyNodes[1][1]]
	local keyS = Layout.Nodes[keyNodes[1][#Layout.KEY_ZS]]
	local islands = {
		{ Rect = Layout.ISLAND, West = Layout.ISLAND_XS[1] - Layout.ISLAND_X_WIDTHS[1] / 2, Beach = Layout.BEACH_X, North = Layout.ISLAND_ZS[1] - Layout.ISLAND_Z_WIDTHS[1] / 2, South = Layout.ISLAND_ZS[#Layout.ISLAND_ZS] + Layout.ISLAND_Z_WIDTHS[#Layout.ISLAND_ZS] / 2 },
		{ Rect = Layout.KEY, West = Layout.KEY_XS[1] - (keyW.WX or 26) / 2, Beach = Layout.KEY_BEACH_X, North = Layout.KEY_ZS[1] - (keyW.WZ or 26) / 2, South = Layout.KEY_ZS[#Layout.KEY_ZS] + (keyS.WZ or 26) / 2 },
	}
	for _, island in islands do
		local isl = island.Rect
		local westAve = island.West
		local beachX = island.Beach
		local inner = { island.North - Layout.STREET_SIDEWALK, island.South + Layout.STREET_SIDEWALK }
		local outer = { isl.MinZ + 30, isl.MaxZ - 30 }
		for k = 1, 2 do
			local z0, z1 = math.min(inner[k], outer[k]), math.max(inner[k], outer[k])
			if z1 - z0 < 30 then
				continue
			end
			local cz = (z0 + z1) / 2
			local path = PartKit.Box(folder, "Path", Vector3.new(beachX - westAve, 0.3, 12), CFrame.new((westAve + beachX) / 2, 0.15, cz), Color3.fromRGB(214, 200, 178), Enum.Material.Pavement)
			path:SetAttribute("Surface", "Sidewalk")
			for _ = 1, math.floor((z1 - z0) * (beachX - isl.MinX) / 1500) do
				local x = rng:NextNumber(isl.MinX + 20, beachX - 10)
				local z = rng:NextNumber(z0 + 8, z1 - 8)
				if math.abs(z - cz) > 12 then
					Props.Palm(folder, Vector3.new(x, 0, z), rng)
				end
			end
			for i = 1, 5 do
				local x = westAve + i * (beachX - westAve) / 6
				Props.Bench(folder, CFrame.new(x, 0.3, cz - 9) * CFrame.Angles(0, math.pi, 0))
				Props.Lamp(folder, Vector3.new(x + 20, 0.3, cz + 9))
			end
		end
	end
end

function Builder.Build(): Model
	local city = Instance.new("Model")
	city.Name = "City"
	local rng = Random.new(Builder.SEED)
	Shore.Build(city, rng)
	pads(city)
	Roads.Build(city)
	Freeways.Build(city)

	local blocks = PartKit.Folder(city, "Blocks")
	for _, block in Layout.Blocks do
		local district = block.District
		if district == "Dealership" then
			Landmarks.Dealership(blocks, block, rng)
		elseif district == "Police" then
			Landmarks.Police(blocks, block, rng)
		elseif district == "Plaza" then
			Landmarks.Plaza(blocks, block, rng)
		elseif district == "BayPark" then
			Landmarks.BayPark(blocks, block, rng)
		elseif district == "Marina" then
			Landmarks.Marina(blocks, block, rng)
		elseif district == "Jump" then
			if block.Bx == 1 then
				Landmarks.LoopPark(blocks, block, rng)
			else
				Landmarks.JumpPark(blocks, block, rng)
			end
		elseif not Neighborhoods.Fill(blocks, block, rng) then
			Buildings.Fill(blocks, block, rng)
		end
	end
	streetscape(city, rng)
	furniture(city, rng)
	islandEnds(city, rng)
	chargers(city)
	Airport.Build(city, rng)
	Port.Build(city, rng)
	Everglades.Build(city, rng)
	Countryside.Build(city, rng)
	spawnPoint(city)
	-- real-world materials by role (roofs, tyres, glass...)
	Realism.Apply(city)
	-- Built at Roblox's standard scale; shrink to the avatar scale the game runs at
	PartKit.Scale(city, Config.WORLD_SCALE)
	return city
end

return Builder
