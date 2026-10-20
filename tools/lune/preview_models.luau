--[[
	Lines up every bike and car on a floor and writes the part list for tools/preview/render.mjs.

	lune run tools/lune/preview_models.luau <out.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")

local Instance, CFrame, Vector3, Color3 = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Color3

local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeModel = Loader.Require("ReplicatedStorage.Shared.Models.BikeModel")
local CarModel = Loader.Require("ReplicatedStorage.Shared.Models.CarModel")
local PartKit = Loader.Require("ReplicatedStorage.Shared.PartKit")

local root = Instance.new("Model")
local floor = Instance.new("Part")
floor.Size = Vector3.new(400, 1, 200)
floor.CFrame = CFrame.new(0, -0.5, 0)
floor.Color = Color3.fromRGB(200, 200, 196)
floor.Parent = root
-- a 5-stud-tall dummy "rider" for scale next to each bike
for i, bike in Bikes.List do
	local model = BikeModel.Build(bike, nil, { Static = true })
	local x = (i - 1) * 10
	PartKit.PlaceStatic(model, CFrame.new(x, 0, 0) * CFrame.Angles(0, math.rad(90), 0))
	model.Parent = root
	local dummy = Instance.new("Part")
	dummy.Size = Vector3.new(2, 5, 1)
	dummy.CFrame = CFrame.new(x, 2.5, 6)
	dummy.Color = Color3.fromRGB(80, 120, 200)
	dummy.Parent = root
end
for i, kind in { "Police", "Sedan", "Hatch", "SUV", "Van", "Taxi" } do
	local car = CarModel.Build(kind, { Static = true })
	PartKit.PlaceStatic(car, CFrame.new((i - 1) * 22, 0, 40) * CFrame.Angles(0, math.rad(90), 0))
	car.Parent = root
end
fs.writeFile(process.args[1], serde.encode("json", Preview.Export(root)))
print("wrote", process.args[1])
