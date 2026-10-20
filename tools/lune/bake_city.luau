--[[
	Bakes the city into map/City.rbxm (included in the place by default.project.json), and
	optionally writes a JSON part list for tools/preview (renders without Studio).

	lune run tools/lune/bake_city.luau [preview.json]
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Loader = require("./loader")

local Builder = Loader.Require("ReplicatedStorage.Shared.City.Builder")
local city = Builder.Build()

local counts = {}
local total = 0
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") then
		total += 1
		local top = d
		while top.Parent and top.Parent ~= city do
			top = top.Parent
		end
		counts[top.Name] = (counts[top.Name] or 0) + 1
	end
end
local names = {}
for name in counts do
	table.insert(names, name)
end
table.sort(names)
for _, name in names do
	print(string.format("  %-14s %6d parts", name, counts[name]))
end
print(string.format("  %-14s %6d parts", "TOTAL", total))

fs.writeFile("map/City.rbxm", roblox.serializeModel({ city }))
print("wrote map/City.rbxm")

local previewPath = process.args[1]
if previewPath then
	local Preview = require("./preview_export")
	fs.writeFile(previewPath, serde.encode("json", Preview.Export(city)))
	print("wrote", previewPath)
end
