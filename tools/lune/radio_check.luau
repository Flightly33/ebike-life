--[[
	Which radio station (Client/Music) plays at each named place on the map, and the stations'
	searches, without booting the game: lune run tools/lune/radio_check.luau
]]
local process = require("@lune/process")
local World = require("../sim/World")

local root = process.cwd
if string.sub(root, -1) ~= "/" then
	root ..= "/"
end
local world = World.new(root)
local server = world:Context("server", true, nil)
local Shared = world.Services.ReplicatedStorage:WaitForChild("Shared")
server.Require(Shared:WaitForChild("Remotes"))
local viewer = world:AddPlayer("Viewer", 1, true)
local client = world:Context("client", false, viewer)
local Music = client.Require(world.Services.StarterPlayer.StarterPlayerScripts:WaitForChild("Client"):WaitForChild("Music"))
local Layout = client.Require(Shared:WaitForChild("City"):WaitForChild("Layout"))
local AudioCatalog = client.Require(Shared:WaitForChild("AudioCatalog"))

local names = {}
for name in Layout.Places do
	table.insert(names, name)
end
table.sort(names)
for _, name in names do
	local mood = Music.PlaceMood(Layout.Places[name])
	print(string.format("%-14s %-9s %s", name, mood, AudioCatalog.Moods[mood].Station))
end
