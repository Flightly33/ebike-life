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

	-- pavements round the outside of the mainland grid (gaps where the country roads leave it),
	-- up the west side of Biscayne Blvd's ends, and along the island's edges
	local first, last = Layout.Line(0), Layout.Line(Layout.GRID_COUNT - 1)
	local swOut = Layout.STREET_SIDEWALK
	local hw0 = Layout.LineWidthX(0) / 2
	local bayWest = last - Layout.LineWidthX(Layout.BAY_INDEX) / 2
	local rural = { { -Layout.RURAL_WIDTH / 2, Layout.RURAL_WIDTH / 2 } }
	local outerN = first - Layout.LineWidthZ(0) / 2
	local outerS = last + Layout.LineWidthZ(Layout.GRID_COUNT - 1) / 2
	padX(first - hw0 - swOut, bayWest, outerN - swOut, outerN, table.clone(rural))
	padX(first - hw0 - swOut, bayWest, outerS, outerS + swOut, table.clone(rural))
	padZ(first - hw0 - swOut, first - hw0, outerN, outerS, table.clone(rural))
	local ringIn = Layout.RING_HALF - Layout.RING_WIDTH / 2
	pad(bayWest - Layout.AVENUE_SIDEWALK, bayWest, -ringIn, outerN - swOut)
	pad(bayWest - Layout.AVENUE_SIDEWALK, bayWest, outerS + swOut, ringIn)

	local isl = Layout.ISLAND
	local xs, zs = Layout.ISLAND_XS, Layout.ISLAND_ZS
	local westAve = xs[1] - Layout.ISLAND_X_WIDTHS[1] / 2
	local oceanDr = xs[#xs] + Layout.ISLAND_X_WIDTHS[#xs] / 2
	local zTop = zs[1] - Layout.ISLAND_Z_WIDTHS[1] / 2
	local zBottom = zs[#zs] + Layout.ISLAND_Z_WIDTHS[#zs] / 2
	local landings: { { number } } = { { Layout.I395_Z - Layout.AVENUE_WIDTH / 2 - 2, Layout.I395_Z + Layout.AVENUE_WIDTH / 2 + 2 } }
	for _, z in Layout.CAUSEWAY_ZS do
		table.insert(landings, { z - Layout.STREET_WIDTH / 2 - 4, z + Layout.STREET_WIDTH / 2 + 4 })
	end
	padZ(isl.MinX + 8, westAve, zTop - swOut, zBottom + swOut, landings)
	-- Ocean Drive's east side: a pavement, then a lawn of palms down to the beach path
	pad(oceanDr, oceanDr + swOut + 2, zTop - swOut, zBottom + swOut)
	local lawnX0, lawnX1 = oceanDr + swOut + 2, Layout.BEACH_X - 8
	local lawn = PartKit.Box(folder, "Lawn", Vector3.new(lawnX1 - lawnX0, Y + 0.4, zBottom - zTop + 2 * swOut), CFrame.new((lawnX0 + lawnX1) / 2, (Y - 0.4) / 2, (zTop + zBottom) / 2), C.Lawn, Enum.Material.Grass)
	lawn:SetAttribute("Surface", "Grass")
	pad(Layout.BEACH_X - 8, Layout.BEACH_X, zTop - swOut, zBottom + swOut)
	pad(westAve, oceanDr, zTop - swOut, zTop)
	pad(westAve, oceanDr, zBottom, zBottom + swOut)
end

-- Palms on most pavements, shade trees in the suburbs, nothing on the industrial and freeway blocks
local function treesFor(district: string): boolean | string
	if district == "Suburb" then
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
		local modern = block.District ~= "Suburb" and block.District ~= "Plaza"
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

local BUSY: { [string]: boolean } = { Downtown = true, Brickell = true, Edgewater = true, Midtown = true, Plaza = true, Dealership = true, Police = true, ArtDeco = true, Condo = true }

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

-- The island's ends: South Pointe and the park north of Lincoln Rd, palms and paths on the grass
local function islandEnds(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "IslandParks")
	local isl = Layout.ISLAND
	local zs = Layout.ISLAND_ZS
	local westAve = Layout.ISLAND_XS[1] - Layout.ISLAND_X_WIDTHS[1] / 2
	local inner = { zs[1] - Layout.ISLAND_Z_WIDTHS[1] / 2 - Layout.STREET_SIDEWALK, zs[#zs] + Layout.ISLAND_Z_WIDTHS[#zs] / 2 + Layout.STREET_SIDEWALK }
	local outer = { isl.MinZ + 30, isl.MaxZ - 30 }
	for k = 1, 2 do
		local z0, z1 = math.min(inner[k], outer[k]), math.max(inner[k], outer[k])
		local cz = (z0 + z1) / 2
		local path = PartKit.Box(folder, "Path", Vector3.new(Layout.BEACH_X - westAve, 0.3, 12), CFrame.new((westAve + Layout.BEACH_X) / 2, 0.15, cz), Color3.fromRGB(214, 200, 178), Enum.Material.Pavement)
		path:SetAttribute("Surface", "Sidewalk")
		for _ = 1, 26 do
			local x = rng:NextNumber(isl.MinX + 20, Layout.BEACH_X - 10)
			local z = rng:NextNumber(z0 + 8, z1 - 8)
			if math.abs(z - cz) > 12 then
				Props.Palm(folder, Vector3.new(x, 0, z), rng)
			end
		end
		for i = 1, 5 do
			local x = westAve + i * (Layout.BEACH_X - westAve) / 6
			Props.Bench(folder, CFrame.new(x, 0.3, cz - 9) * CFrame.Angles(0, math.pi, 0))
			Props.Lamp(folder, Vector3.new(x + 20, 0.3, cz + 9))
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
		else
			Buildings.Fill(blocks, block, rng)
		end
	end
	streetscape(city, rng)
	furniture(city, rng)
	islandEnds(city, rng)
	chargers(city)
	Countryside.Build(city, rng)
	spawnPoint(city)
	-- real-world materials by role (roofs, tyres, glass...)
	Realism.Apply(city)
	-- Built at Roblox's standard scale; shrink to the avatar scale the game runs at
	PartKit.Scale(city, Config.WORLD_SCALE)
	return city
end

return Builder
