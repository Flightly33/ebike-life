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
local PartKit = require(script.Parent.Parent.PartKit)
local Config = require(script.Parent.Parent.Config)

local Builder = {}

Builder.SEED = 20261019

local C = Props.Palette
local Y = Layout.CURB_Y
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }

local function ground(city: Instance)
	local folder = PartKit.Folder(city, "Ground")
	local half = Layout.WORLD_HALF
	local tiles = 3
	local size = half * 2 / tiles
	for i = 0, tiles - 1 do
		for j = 0, tiles - 1 do
			local cx = -half + size * (i + 0.5)
			local cz = -half + size * (j + 0.5)
			local tile = PartKit.Box(folder, "Grass", Vector3.new(size, 4, size), CFrame.new(cx, -2, cz), C.Grass, Enum.Material.Grass)
			tile:SetAttribute("Surface", "Grass")
		end
	end
	-- Invisible walls at the map edge
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local center = d * (half + 2) + Vector3.new(0, 100, 0)
		local size3 = if d.X ~= 0 then Vector3.new(4, 200, half * 2 + 8) else Vector3.new(half * 2 + 8, 200, 4)
		local wall = PartKit.Box(folder, "Boundary", size3, CFrame.new(center), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { Transparency = 1, Shadow = false })
		wall:SetAttribute("Surface", "Wall")
	end
end

-- Raised pads between the carriageways (pavement and kerb), with a light kerb line
local function pads(city: Instance)
	local folder = PartKit.Folder(city, "Pads")
	local thickness = Y + 0.4
	local function pad(minX: number, maxX: number, minZ: number, maxZ: number)
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
	for _, block in Layout.Blocks do
		pad(block.MinX, block.MaxX, block.MinZ, block.MaxZ)
	end
	-- pavements on the outer side of the edge roads
	local first, last = Layout.Line(0), Layout.Line(Layout.GRID_COUNT - 1)
	local hw = Layout.STREET_WIDTH / 2
	local sw = Layout.STREET_SIDEWALK
	-- each outer strip runs between the country road gaps
	local outer = last + hw + sw
	local function strip(minX: number, maxX: number, minZ: number, maxZ: number)
		if maxX - minX > 1 and maxZ - minZ > 1 then
			pad(minX, maxX, minZ, maxZ)
		end
	end
	local gap = Layout.AVENUE_WIDTH / 2 -- the avenues continue out as country roads
	strip(first - hw - sw, first - hw, -outer, -gap)
	strip(first - hw - sw, first - hw, gap, outer)
	strip(last + hw, last + hw + sw, -outer, -gap)
	strip(last + hw, last + hw + sw, gap, outer)
	strip(-outer + sw, -gap, first - hw - sw, first - hw)
	strip(gap, outer - sw, first - hw - sw, first - hw)
	strip(-outer + sw, -gap, last + hw, last + hw + sw)
	strip(gap, outer - sw, last + hw, last + hw + sw)
end

local function streetscape(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Streetscape")
	for _, block in Layout.Blocks do
		local trees = block.District == "Downtown" or block.District == "Midtown" or block.District == "Suburb" or block.District == "Industrial"
		local inset = 2.5
		local x0, x1 = block.MinX + inset, block.MaxX - inset
		local z0, z1 = block.MinZ + inset, block.MaxZ - inset
		Props.Streetscape(folder, Vector3.new(x0 + 10, Y, z0), Vector3.new(x1 - 10, Y, z0), rng, trees)
		Props.Streetscape(folder, Vector3.new(x0 + 10, Y, z1), Vector3.new(x1 - 10, Y, z1), rng, trees)
		Props.Streetscape(folder, Vector3.new(x0, Y, z0 + 10), Vector3.new(x0, Y, z1 - 10), rng, trees)
		Props.Streetscape(folder, Vector3.new(x1, Y, z0 + 10), Vector3.new(x1, Y, z1 - 10), rng, trees)
	end
end

-- Street names for the grid lines (x = Line(i) runs north-south, z = Line(j) runs east-west)
local NS_NAMES = { "Maple Ave", "Cedar Ave", "Birch Ave", "Flightly Blvd", "Elm Ave", "Aspen Ave", "Willow Ave" }
local EW_NAMES = { "1st St", "2nd St", "3rd St", "Volt Ave", "5th St", "6th St", "7th St" }

local BUSY: { [string]: boolean } = { Downtown = true, Midtown = true, Plaza = true, Dealership = true, Police = true }

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
			local avenue = Layout.IsAvenue(side.line)
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
	-- street-name signs on the north-east corner of every crossing
	for _, node in Layout.Nodes do
		if node.Grid and node.I and node.J then
			local wx = Layout.LineWidth(node.I)
			local wz = Layout.LineWidth(node.J)
			local base = node.Position + Vector3.new(wx / 2 + 3.5, Y - Layout.ROAD_Y, -(wz / 2 + 3.5))
			Detail.StreetSign(folder, base, NS_NAMES[node.I + 1], Vector3.new(0, 0, 1), EW_NAMES[node.J + 1])
		end
	end
end

local function chargers(city: Instance)
	local folder = PartKit.Folder(city, "Chargers")
	for _, position in Layout.Chargers do
		-- face the nearest street
		local function nearestLine(v: number): number
			local index = math.clamp(math.floor((v - Layout.GRID_MIN) / Layout.GRID_STEP + 0.5), 0, Layout.GRID_COUNT - 1)
			return Layout.Line(index)
		end
		local lx, lz = nearestLine(position.X), nearestLine(position.Z)
		local dx, dz = lx - position.X, lz - position.Z
		if math.abs(position.X) < 100 and math.abs(position.Z) > Layout.Line(Layout.GRID_COUNT - 1) then
			dx, dz = -position.X, 1e9 -- the country stop faces the road at x = 0
		end
		local facing = if math.abs(dx) < math.abs(dz) then Vector3.new(math.sign(dx), 0, 0) else Vector3.new(0, 0, math.sign(dz))
		Props.Charger(folder, position, facing)
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

function Builder.Build(): Model
	local city = Instance.new("Model")
	city.Name = "City"
	local rng = Random.new(Builder.SEED)
	ground(city)
	pads(city)
	Roads.Build(city)

	local blocks = PartKit.Folder(city, "Blocks")
	local parkBlocks = {}
	for _, block in Layout.Blocks do
		local district = block.District
		if district == "Park" then
			table.insert(parkBlocks, block)
		elseif district == "Dealership" then
			Landmarks.Dealership(blocks, block, rng)
		elseif district == "Police" then
			Landmarks.Police(blocks, block, rng)
		elseif district == "Plaza" then
			Landmarks.Plaza(blocks, block, rng)
		elseif district == "Jump" then
			Landmarks.JumpPark(blocks, block, rng)
		else
			Buildings.Fill(blocks, block, rng)
		end
	end
	Landmarks.Park(blocks, parkBlocks, rng)
	streetscape(city, rng)
	furniture(city, rng)
	chargers(city)
	Countryside.Build(city, rng)
	spawnPoint(city)
	-- Built at Roblox's standard scale; shrink to the avatar scale the game runs at
	PartKit.Scale(city, Config.WORLD_SCALE)
	return city
end

return Builder
