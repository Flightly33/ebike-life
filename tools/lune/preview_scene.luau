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

-- on the pavement next to a downtown street, at the spawn, and in the suburbs
local down = Layout.BlockAt(4, 2)
spot("downtown", Vector3.new((down.MinX + down.LotMinX) / 2, Layout.CURB_Y, (down.MinZ + down.MaxZ) / 2 + 20), math.rad(-60))
spot("spawn", Layout.Places.Spawn + Vector3.new(0, 0, 10), math.rad(30))
local sub = Layout.BlockAt(2, 6)
spot("suburb", Vector3.new((sub.LotMinX + sub.LotMaxX) / 2, Layout.CURB_Y, sub.MinZ + 4), math.rad(200))
local mid = Layout.BlockAt(3, 5)
spot("midtown", Vector3.new((mid.LotMinX + mid.LotMaxX) / 2 + 30, Layout.CURB_Y, mid.MaxZ - 4), math.rad(20))
local ind = Layout.BlockAt(6, 1)
spot("industrial", Vector3.new(ind.MinX + 4, Layout.CURB_Y, (ind.LotMinZ + ind.LotMaxZ) / 2), math.rad(-110))
local pol = Layout.FindDistrict("Police")
if pol then
	spot("police", Vector3.new((pol.LotMinX + pol.LotMaxX) / 2 - 30, Layout.CURB_Y, pol.MaxZ - 4), math.rad(20))
end

-- the dealership and the loop park, from above the street
for _, place in { { "dealership", Layout.Places.Dealership }, { "looppark", Layout.BlockAt(1, 4) } } do
	local at: Vector3 = if typeof(place[2]) == "Vector3" then place[2] else Vector3.new((place[2].MinX + place[2].MaxX) / 2, Layout.CURB_Y, (place[2].MinZ + place[2].MaxZ) / 2)
	table.insert(views, { name = place[1], pos = { at.X + 90, at.Y + 55, at.Z + 90 }, look = { at.X, at.Y + 8, at.Z }, fov = 60, width = 1280, height = 720 })
	table.insert(views, { name = place[1] .. "_low", pos = { at.X - 60, at.Y + 14, at.Z + 40 }, look = { at.X, at.Y + 6, at.Z }, fov = 65, width = 1280, height = 720 })
end

fs.writeFile(process.args[1], serde.encode("json", Preview.Export(city)))
fs.writeFile(process.args[2], serde.encode("json", views))
print("wrote", process.args[1], #views, "views")
