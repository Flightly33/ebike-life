--[[
	Builds one walk-in shop per theme (City/Interior, baked part) and fits each out the way a
	client does (Client/ShopFit), ceilings off, for tools/preview renders.

	lune run tools/lune/preview_shops.luau <parts.json> <views.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")

local Instance, CFrame, Color3 = roblox.Instance, roblox.CFrame, roblox.Color3

local Config = Loader.Require("ReplicatedStorage.Shared.Config")
local PartKit = Loader.Require("ReplicatedStorage.Shared.PartKit")
local Interior = Loader.Require("ReplicatedStorage.Shared.City.Interior")
Loader.Mock("StarterPlayer.StarterPlayerScripts.Client.Graphics", {
	Current = function()
		return Config.Graphics.Ultra
	end,
})
Loader.Mock("StarterPlayer.StarterPlayerScripts.Client.Sound", { Play = function() end })
local ShopFit = Loader.Require("StarterPlayer.StarterPlayerScripts.Client.ShopFit")

local SHOPS = {
	{ "Food", "🍔 Burger Bay", Color3.fromRGB(210, 40, 40), 40, 30, 12.6, true, 14 },
	{ "Gas", "☀ SUNFUEL MART", Color3.fromRGB(255, 120, 20), 46, 28, 11.6, true, 0 },
	{ "Shop", "Cafe Sol", Color3.fromRGB(30, 110, 70), 30, 40, 12, false, -10 },
	{ "Shop", "Fruteria", Color3.fromRGB(230, 150, 30), 30, 40, 12, false, 9 },
	{ "Shop", "Taco Loco", Color3.fromRGB(200, 40, 40), 32, 40, 12, false, -9 },
	{ "Shop", "Surf Shop", Color3.fromRGB(30, 80, 160), 30, 40, 12, false, 10 },
	{ "Shop", "Nail Spa", Color3.fromRGB(200, 90, 150), 30, 40, 12, false, -10 },
}

local root = Instance.new("Model")
local fits = Instance.new("Folder")
fits.Parent = root
local views = {}
local K = Config.WORLD_SCALE
for i, s in SHOPS do
	local x = (i - 1) * 120
	local holder = Instance.new("Model")
	holder.Parent = root
	local model = Interior.Build(holder, CFrame.new(x, 0, 0), s[4], s[5], s[6], {
		Kind = s[1],
		Name = s[2],
		Accent = s[3],
		Front = s[7],
		DoorX = s[8],
		Sides = true,
		Rng = Loader.Globals.Random.new(i * 7),
	})
	PartKit.ScaleAbout(holder, roblox.Vector3.new(x, 0, 0), K)
	local lod = model:FindFirstChild("Placeholder")
	if lod then
		lod:Destroy()
	end
	local ceiling = model:FindFirstChild("Ceiling")
	if ceiling then
		ceiling.Transparency = 1
	end
	ShopFit.Preview(model, fits)
	if ceiling then
		ceiling.Transparency = 1
	end
	local w, d, h = s[4] * K, s[5] * K, s[6] * K
	-- cutaway from above the street side, and from the doorway at eye level
	table.insert(views, { name = string.gsub(s[2], "[^%w]", "") .. "_top", pos = { x + w * 0.15, h * 2.4, -d * 1.05 }, look = { x, 0, d * 0.08 }, fov = 50, width = 1280, height = 800 })
	table.insert(views, { name = string.gsub(s[2], "[^%w]", "") .. "_eye", pos = { x + s[8] * K, 6.2, -d / 2 + 4 }, look = { x, 4, d / 2 }, fov = 70, width = 1280, height = 800 })
end
fs.writeFile(process.args[1], serde.encode("json", Preview.Export(root)))
fs.writeFile(process.args[2], serde.encode("json", views))
print("wrote", #views, "views")
