--[[
	Builds the city plus avatar-sized dummies and bikes at a few street spots, for checking scale
	in tools/preview renders. Writes the part list and a views file.

	lune run tools/lune/preview_scene.luau <parts.json> <views.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")

local Instance, CFrame, Vector3, Color3 = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Color3

local Builder = Loader.Require("ReplicatedStorage.Shared.City.Builder")
local Layout = Loader.Require("ReplicatedStorage.Shared.City.Layout")
local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeModel = Loader.Require("ReplicatedStorage.Shared.Models.BikeModel")
local CarModel = Loader.Require("ReplicatedStorage.Shared.Models.CarModel")
local PartKit = Loader.Require("ReplicatedStorage.Shared.PartKit")
local Config = Loader.Require("ReplicatedStorage.Shared.Config")

local city = Builder.Build()

-- A blocky R15-sized figure (5.2 studs, like a default avatar)
local function dummy(base: any)
	local m = Instance.new("Model")
	local function box(size: any, offset: any, color: any)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = CFrame.new(base + offset)
		p.Color = color
		p.Parent = m
	end
	local skin, shirt, pants = Color3.fromRGB(234, 184, 146), Color3.fromRGB(40, 110, 200), Color3.fromRGB(40, 44, 60)
	box(Vector3.new(0.9, 2.1, 0.9), Vector3.new(-0.5, 1.05, 0), pants)
	box(Vector3.new(0.9, 2.1, 0.9), Vector3.new(0.5, 1.05, 0), pants)
	box(Vector3.new(2, 1.9, 1), Vector3.new(0, 3.05, 0), shirt)
	box(Vector3.new(0.9, 1.9, 0.9), Vector3.new(-1.45, 3.05, 0), skin)
	box(Vector3.new(0.9, 1.9, 0.9), Vector3.new(1.45, 3.05, 0), skin)
	box(Vector3.new(1.15, 1.15, 1.15), Vector3.new(0, 4.6, 0), skin)
	m.Parent = city
end

local views = {}
local function spot(name: string, at: any, facing: number)
	dummy(at + Vector3.new(3, 0, 0))
	local bike = BikeModel.Build(Bikes.List[1], nil, { Static = true })
	PartKit.PlaceStatic(bike, CFrame.new(at + Vector3.new(-3, 0, 0)) * CFrame.Angles(0, math.rad(90), 0))
	bike.Parent = city
	local car = CarModel.Build("Sedan", { Static = true })
	PartKit.PlaceStatic(car, CFrame.new(at + Vector3.new(0, Layout.ROAD_Y - at.Y, 18)) * CFrame.Angles(0, math.rad(90), 0))
	car.Parent = city
	local look = at + Vector3.new(0, 4, 0)
	local dir = Vector3.new(math.sin(facing), 0, math.cos(facing))
	table.insert(views, { name = name, pos = { look.X + dir.X * 26, look.Y + 5, look.Z + dir.Z * 26 }, look = { look.X, look.Y + 2, look.Z }, fov = 60, width = 1280, height = 720 })
	table.insert(views, { name = name .. "_wide", pos = { look.X + dir.X * 70, look.Y + 30, look.Z + dir.Z * 70 }, look = { look.X, look.Y + 6, look.Z }, fov = 60, width = 1280, height = 720 })
end

-- the water (Terrain in the game, filled at runtime): a flat blue plane for the renders
for _, rect in Layout.Water do
	local w, d = rect.MaxX - rect.MinX, rect.MaxZ - rect.MinZ
	local nx, nz = math.ceil(w / 2000), math.ceil(d / 2000)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local p = Instance.new("Part")
			p.Name = "PreviewWater"
			p.Size = Vector3.new(w / nx, 0.2, d / nz)
			p.CFrame = CFrame.new(rect.MinX + w / nx * (i + 0.5), Layout.WATER_Y - 0.1, rect.MinZ + d / nz * (j + 0.5))
			p.Color = Color3.fromRGB(40, 140, 170)
			p.Transparency = 0.25
			p.Parent = city
		end
	end
end

local function view(name: string, pos: any, look: any, fov: number?)
	table.insert(views, { name = name, pos = { pos.X, pos.Y, pos.Z }, look = { look.X, look.Y, look.Z }, fov = fov or 60, width = 1280, height = 720 })
end
local K = Config.WORLD_SCALE
local function blockCenter(block: any): any
	return Vector3.new((block.LotMinX + block.LotMaxX) / 2, Layout.CURB_Y, (block.LotMinZ + block.LotMaxZ) / 2)
end

spot("spawn", Layout.Places.Spawn + Vector3.new(0, 0, 10), math.rad(30))
local brickell = Layout.BlockAt(6, 6)
spot("brickell", Vector3.new(brickell.MinX + 4, Layout.CURB_Y, (brickell.LotMinZ + brickell.LotMaxZ) / 2), math.rad(-110))
local ff = Layout.BlockAt(2, 3)
spot("fastfood", Vector3.new((ff.LotMinX + ff.LotMaxX) / 2, Layout.CURB_Y, ff.MinZ + 4), math.rad(160))
local sub = Layout.BlockAt(1, 6)
spot("suburb", Vector3.new((sub.LotMinX + sub.LotMaxX) / 2, Layout.CURB_Y, sub.MinZ + 4), math.rad(200))
local wyn = Layout.BlockAt(5, 0)
spot("wynwood", Vector3.new((wyn.LotMinX + wyn.LotMaxX) / 2 + 30, Layout.CURB_Y, wyn.MaxZ + 6), math.rad(20))
local deco = Layout.FindDistrict("ArtDeco")
if deco then
	spot("oceandrive", Vector3.new(deco.MaxX + 6, Layout.CURB_Y, (deco.LotMinZ + deco.LotMaxZ) / 2), math.rad(60))
end
-- on I-95's deck, looking south to the junction; at a ramp's foot; on the bay bridge
local i95 = Layout.Nodes[Layout.I95[4]].Position
view("i95", i95 + Vector3.new(-18 * K, 10, -60 * K), Layout.Nodes[Layout.I95Junction].Position + Vector3.new(0, 4, 0))
local ramp = Layout.Ramps[1]
local foot = Layout.Nodes[ramp.Foot].Position
view("ramp", foot + Vector3.new(40 * K, 14, 60 * K), Layout.Nodes[ramp.Top].Position)
local bridge = Layout.Nodes[Layout.I395[#Layout.I395 - 2]].Position
view("bridge", bridge + Vector3.new(-200 * K, 30, 160 * K), bridge + Vector3.new(200 * K, 0, 0))
view("causeway", Vector3.new(Layout.SHORE_X + 60 * K, 22, Layout.CAUSEWAY_ZS[2] + 120 * K), Vector3.new(Layout.ISLAND.MinX, 0, Layout.CAUSEWAY_ZS[2]))
-- the skyline from the island, the beach, the garage, aerials
view("skyline", Vector3.new(Layout.ISLAND.MinX + 20 * K, 30, 300 * K), Vector3.new(800 * K, 160, 0), 70)
view("beach", Vector3.new(Layout.BEACH_X - 10 * K, 14, 400 * K), Vector3.new(Layout.SURF_X, 0, 100 * K), 70)
local park = Layout.FindDistrict("Parking")
if park then
	local c = blockCenter(park)
	view("garage", c + Vector3.new(-150 * K, 70, 200 * K), c + Vector3.new(-50 * K, 10, 0))
end
view("aerial_downtown", Vector3.new(-200 * K, 900, 900 * K), Vector3.new(900 * K, 0, -100 * K), 60)
view("aerial_beach", Vector3.new(3000 * K, 600, 1400 * K), Vector3.new(2200 * K, 0, -200 * K), 60)
for _, place in { { "dealership", Layout.Places.Dealership }, { "looppark", blockCenter(Layout.BlockAt(1, 3)) }, { "baypark", Layout.Places.Park }, { "marina", blockCenter(Layout.FindDistrict("Marina")) } } do
	local at: Vector3 = place[2]
	table.insert(views, { name = place[1], pos = { at.X + 90, at.Y + 55, at.Z + 90 }, look = { at.X, at.Y + 8, at.Z }, fov = 60, width = 1280, height = 720 })
end
table.insert(views, { name = "map", pos = { 0, 3000, 0 }, look = { 0, 0, 0 }, fov = 60, width = 1400, height = 1400, ortho = Layout.WORLD_HALF * 2 })

fs.writeFile(process.args[1], serde.encode("json", Preview.Export(city)))
fs.writeFile(process.args[2], serde.encode("json", views))
print("wrote", process.args[1], #views, "views")
