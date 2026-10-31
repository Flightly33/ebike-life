--[[
	The billboard structures (City/Billboards) on their own for a tools/preview render:
	lune run tools/lune/preview_billboards.luau <parts.json> <views.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")
local Instance, CFrame, Vector3, Color3, Enum = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Color3, roblox.Enum

local Billboards = Loader.Require("ReplicatedStorage.Shared.City.Billboards")
local PartKit = Loader.Require("ReplicatedStorage.Shared.PartKit")
local Config = Loader.Require("ReplicatedStorage.Shared.Config")
local rng = Loader.Globals.Random.new(5)
local root = Instance.new("Model")
PartKit.Box(root, "Ground", Vector3.new(600, 1, 300), CFrame.new(100, -0.5, 0), Color3.fromRGB(110, 150, 80), Enum.Material.Grass)
PartKit.Box(root, "Road", Vector3.new(600, 0.2, 40), CFrame.new(100, 0.1, -60), Color3.fromRGB(70, 72, 76), Enum.Material.Asphalt)
Billboards.Monopole(root, Vector3.new(0, 0, -20), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), rng)
local building = Vector3.new(170, 0, 20)
PartKit.Box(root, "Building", Vector3.new(60, 40, 50), CFrame.new(building + Vector3.new(0, 20, 0)), Color3.fromRGB(200, 180, 160), Enum.Material.Brick)
Billboards.Rooftop(root, building + Vector3.new(0, 40, 0), Vector3.new(0, 0, -1), 46, rng)
PartKit.Box(root, "Tower", Vector3.new(60, 90, 50), CFrame.new(300, 45, 20), Color3.fromRGB(150, 150, 150), Enum.Material.Concrete)
Billboards.Screen(root, CFrame.lookAt(Vector3.new(300, 40, -7.2), Vector3.new(300, 40, -100)), 40, 24, rng)
PartKit.Scale(root, Config.WORLD_SCALE)
local K = Config.WORLD_SCALE
fs.writeFile(process.args[1], serde.encode("json", Preview.Export(root)))
fs.writeFile(process.args[2], serde.encode("json", {
	{ name = "billboards", pos = { -60 * K, 30 * K, -200 * K }, look = { 150 * K, 50 * K, 0 }, fov = 60, width = 1400, height = 800 },
	{ name = "monopole", pos = { -120 * K, 6 * K, -60 * K }, look = { 0, 50 * K, -20 * K }, fov = 55, width = 1000, height = 800 },
	{ name = "monopole_below", pos = { -14 * K, 2 * K, -30 * K }, look = { 0, 55 * K, -20 * K }, fov = 70, width = 1000, height = 800 },
}))
