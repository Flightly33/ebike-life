--[[
	A street in the baked city with the client's street and building detail (Client/CityDetail)
	built round it, for tools/preview renders:
	lune run tools/lune/preview_detail.luau <parts.json> <views.json> [district]
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")
local Instance, Vector3 = roblox.Instance, roblox.Vector3

local Config = Loader.Require("ReplicatedStorage.Shared.Config")
Loader.Mock("StarterPlayer.StarterPlayerScripts.Client.Graphics", {
	Current = function()
		return Config.Graphics.Ultra
	end,
})
local Layout = Loader.Require("ReplicatedStorage.Shared.City.Layout")
local CityDetail = Loader.Require("StarterPlayer.StarterPlayerScripts.Client.CityDetail")

local district = process.args[3] or "Midtown"
local block
for _, b in Layout.Blocks do
	if b.District == district then
		block = b
		break
	end
end
assert(block, "no " .. district .. " block")
-- the street along the block's south side
local at = Vector3.new((block.MinX + block.MaxX) / 2, Layout.ROAD_Y, block.MaxZ + 12)
local city = roblox.deserializeModel(fs.readFile("map/City.rbxm"))[1]
local detail = Instance.new("Model")
print("built", CityDetail.BuildAround(city, detail, at, 260), "detail units")
-- export the city and the detail near the spot
local near = Instance.new("Model")
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") and (d.CFrame.Position - at).Magnitude < 420 then
		d:Clone().Parent = near
	end
end
detail.Parent = near
fs.writeFile(process.args[1], serde.encode("json", Preview.Export(near)))
fs.writeFile(process.args[2], serde.encode("json", {
	{ name = district .. "_street", pos = { at.X - 60, at.Y + 9, at.Z + 4 }, look = { at.X + 40, at.Y + 4, at.Z - 6 }, fov = 65, width = 1400, height = 800 },
	{ name = district .. "_high", pos = { at.X - 90, at.Y + 70, at.Z + 60 }, look = { at.X, at.Y + 20, at.Z - 30 }, fov = 60, width = 1400, height = 800 },
}))
