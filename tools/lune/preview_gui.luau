--[[
	Composes the billboard ads offline and writes them for tools/preview/gui.mjs:
	lune run tools/lune/preview_gui.luau ads <out.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local GuiExport = require("./gui_export")

local Config = Loader.Require("ReplicatedStorage.Shared.Config")
Loader.Mock("StarterPlayer.StarterPlayerScripts.Client.Graphics", {
	Current = function()
		return Config.Graphics.Ultra
	end,
})
Loader.Mock("StarterPlayer.StarterPlayerScripts.Client.Sound", { Play = function() end })

local out = {}
local what = process.args[1]
if what == "ads" then
	local Billboards = Loader.Require("StarterPlayer.StarterPlayerScripts.Client.Billboards")
	local Ads = Loader.Require("ReplicatedStorage.Shared.Ads")
	for i = 1, #Ads.List do
		local size = roblox.Vector2.new(960, 320)
		table.insert(out, { name = "ad_" .. i, w = size.X, h = size.Y, tree = GuiExport.Node(Billboards.Compose(i, size)) })
	end
	for i = 1, 6 do
		local size = roblox.Vector2.new(300, 433)
		table.insert(out, { name = "panel_" .. i, w = size.X, h = size.Y, tree = GuiExport.Node(Billboards.Compose(i * 4, size)) })
	end
end
fs.writeFile(process.args[2], serde.encode("json", out))
print("wrote", #out, "guis")
