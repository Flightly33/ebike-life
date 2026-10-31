--[[
	The dealership block (showroom and Flighty Garage) on its own for tools/preview renders:
	lune run tools/lune/preview_garage.luau <parts.json> <views.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")
local Instance = roblox.Instance

local LayoutModule = Loader.Require("ReplicatedStorage.Shared.City.Layout")
local Layout = LayoutModule.Design
local Landmarks = Loader.Require("ReplicatedStorage.Shared.City.Landmarks")
local root = Instance.new("Model")
for _, b in Layout.Blocks do
	if b.District == "Dealership" then
		Landmarks.Dealership(root, b, Loader.Globals.Random.new(3))
	end
end
-- the garage without its roof, to look in
for _, d in root:GetDescendants() do
	if d.Name == "GarageRoof" or d.Name == "Skylight" or d.Name == "RoofTrim" or d.Name == "StripLight" or d.Name == "LightHood" then
		d.Transparency = 1
	end
end
local g = Layout.Garage
local lift = g.Lift
fs.writeFile(process.args[1], serde.encode("json", Preview.Export(root)))
fs.writeFile(process.args[2], serde.encode("json", {
	{ name = "garage_top", pos = { lift.X - 20, 90, g.MaxZ + 50 }, look = { lift.X, 0, lift.Z - 5 }, fov = 55, width = 1300, height = 850 },
	{ name = "garage_door", pos = { lift.X - 4, 6, g.MaxZ + 18 }, look = { lift.X, 4, lift.Z }, fov = 65, width = 1300, height = 850 },
	{ name = "garage_lift", pos = { lift.X + 9, 7, lift.Z + 9 }, look = { lift.X, 3.5, lift.Z }, fov = 60, width = 1300, height = 850 },
}))
