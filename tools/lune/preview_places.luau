--[[
	The Phase 4 places on their own for tools/preview renders: the Flighty Courier depot, the Race
	Plaza and Bayfront Park's event stage (design units, like the city before Builder scales it).
	lune run tools/lune/preview_places.luau <parts.json> <views.json>
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")
local Preview = require("./preview_export")
local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local LayoutModule = Loader.Require("ReplicatedStorage.Shared.City.Layout")
local Layout = LayoutModule.Design
local Landmarks = Loader.Require("ReplicatedStorage.Shared.City.Landmarks")
local root = Instance.new("Model")
local views = {}
local function lot(b: any): (number, number, number, number, number, number)
	return b.LotMinX, b.LotMaxX, b.LotMinZ, b.LotMaxZ, (b.LotMinX + b.LotMaxX) / 2, (b.LotMinZ + b.LotMaxZ) / 2
end
for _, b in Layout.Blocks do
	local rng = Loader.Globals.Random.new(5)
	if b.District == "Depot" then
		Landmarks.Depot(root, b, rng)
		local x0, x1, z0, z1, cx, cz = lot(b)
		table.insert(views, { name = "depot_top", pos = { cx, 420, cz + 1 }, look = { cx, 0, cz }, fov = 50, width = 1300, height = 1300 })
		table.insert(views, { name = "depot_yard", pos = { cx + 40, 60, z1 + 30 }, look = { cx, 8, z0 + 60 }, fov = 60, width = 1400, height = 860 })
		table.insert(views, { name = "depot_desk", pos = { cx + (x1 - x0) * 0.2 - 10, 9, z0 + 120 }, look = { cx + (x1 - x0) * 0.2, 4, z0 + 88 }, fov = 60, width = 1300, height = 860 })
		table.insert(views, { name = "depot_shops", pos = { cx, 14, z1 + 40 }, look = { cx, 8, z1 - 20 }, fov = 62, width = 1400, height = 860 })
		table.insert(views, { name = "depot_gearstore", pos = { cx - (x1 - x0) * 0.22 + 12, 9, z1 + 26 }, look = { cx - (x1 - x0) * 0.22, 7, z1 - 20 }, fov = 62, width = 1300, height = 860 })
		table.insert(views, { name = "depot_sorting", pos = { cx - 20, 30, z0 + 260 }, look = { cx - 40, 4, z0 + 180 }, fov = 62, width = 1300, height = 860 })
	elseif b.District == "RaceHub" then
		Landmarks.RaceHub(root, b, rng)
		local x0, x1, z0, z1, cx, cz = lot(b)
		local gz = cz - (z1 - z0) * 0.12
		table.insert(views, { name = "race_top", pos = { cx, 420, cz + 1 }, look = { cx, 0, cz }, fov = 50, width = 1300, height = 1300 })
		table.insert(views, { name = "race_grid", pos = { cx + 10, 22, gz + 110 }, look = { cx, 10, gz }, fov = 60, width = 1400, height = 860 })
		table.insert(views, { name = "race_pits", pos = { cx - 40, 30, cz + 60 }, look = { x1 - 16, 10, cz }, fov = 60, width = 1400, height = 860 })
	elseif b.District == "BayPark" then
		local model = Landmarks.BayPark(root, b, rng)
		for _, d in model:GetDescendants() do
			if d.Name == "AdFace" then
				local cf = d.CFrame
				local p = cf.Position
				local front = p + cf.LookVector * 60 + Vector3.new(0, -4, 0)
				table.insert(views, { name = "stage", pos = { front.X, front.Y, front.Z }, look = { p.X, p.Y - 6, p.Z }, fov = 60, width = 1300, height = 860 })
			end
		end
	end
end
fs.writeFile(process.args[1], serde.encode("json", Preview.Export(root)))
fs.writeFile(process.args[2], serde.encode("json", views))
