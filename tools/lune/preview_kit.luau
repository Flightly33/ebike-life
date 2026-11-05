--[[
	A street of the city's buildings with the city kit put on them the way the game does it
	(Models/CityKit, the kit's meshes faked from MeshManifest as tests/meshes.luau does), written
	out for blender/preview_street.py: the parts left (boxes, wedges, cylinders) and every kit mesh
	placed (its source mesh, CFrame, size, colour, material). Design units, like the builders.

	rojo sourcemap default.project.json -o sourcemap.json
	lune run tools/lune/preview_kit.luau <street.json> [bare]

	`bare` skips the kit (the part-built look, for a before/after).
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local World = require("../sim/World")
local Sim = require("../sim/Instance")
local Vector3, CFrame, Color3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local out = process.args[1]
local bare = process.args[2] == "bare"
local root = process.cwd
if string.sub(root, -1) ~= "/" then
	root ..= "/"
end
local world = World.new(root)
local RS = world.Services.ReplicatedStorage
local server = world:Context("server", true, nil)
local Shared = RS:WaitForChild("Shared")
local Models = Shared:WaitForChild("Models")
local Manifest = server.Require(Models:WaitForChild("MeshManifest"))

-- the fake import: every manifest mesh, named and sized as Studio's importer leaves them, each
-- remembering which one it is (the kit's clones keep the attribute)
local folder = Sim.New("Model")
folder.Name = "VehicleMeshes"
for _, entries in Manifest do
	for _, entry in entries do
		local part = Sim.Raw("MeshPart")
		Sim.States[part].Name = entry.Name
		Sim.States[part].Props.MeshSize = entry.Size
		part.CFrame = CFrame.new(entry.Center)
		part:SetAttribute("Source", entry.Name)
		part.Parent = folder
	end
end
folder.Parent = RS

local City = Shared:WaitForChild("City")
local Buildings = server.Require(City:WaitForChild("Buildings"))
local Neighborhoods = server.Require(City:WaitForChild("Neighborhoods"))
local Props = server.Require(City:WaitForChild("Props"))
local PartKit = server.Require(Shared:WaitForChild("PartKit"))
local CityKit = server.Require(Models:WaitForChild("CityKit"))

math.randomseed(4)
local rng: any = {
	NextNumber = function(_, a: number?, b: number?): number
		local lo, hi = a or 0, b or 1
		return lo + math.random() * (hi - lo)
	end,
	NextInteger = function(_, a: number, b: number): number
		return math.random(a, b)
	end,
}

local street = Sim.New("Model")
street.Name = "City"
-- a road along x at z = 0 with pavements, the buildings on its north side facing it (+Z)
local S = Vector3.new(0, 0, 1)
PartKit.Box(street, "Road", Vector3.new(700, 0.4, 44), CFrame.new(200, -0.2, 0), Color3.fromRGB(62, 64, 68), Enum.Material.Asphalt)
PartKit.Box(street, "Pavement", Vector3.new(700, 0.8, 16), CFrame.new(200, 0.0, -30), Color3.fromRGB(196, 192, 184), Enum.Material.Pavement)
PartKit.Box(street, "Pavement", Vector3.new(700, 0.8, 16), CFrame.new(200, 0.0, 30), Color3.fromRGB(196, 192, 184), Enum.Material.Pavement)
PartKit.Box(street, "Lot", Vector3.new(700, 0.4, 200), CFrame.new(200, -0.2, -138), Color3.fromRGB(120, 150, 80), Enum.Material.Grass)
-- a stucco and a brick midrise with their shopfronts, then a house, a villa and a bungalow
Buildings.Midrise(street, 0, -58, 60, 40, 4, S, rng, { Vector3.new(-1, 0, 0) }, true, { "Cafe Sol" })
Buildings.Midrise(street, 64, -58, 56, 40, 5, S, rng, { Vector3.new(1, 0, 0) }, false, { "Panaderia" })
Buildings.House(street, Vector3.new(160, 0, -68), S, 30, rng, 70)
Neighborhoods.Villa(street, Vector3.new(250, 0, -68), S, rng, 74)
Neighborhoods.Bungalow(street, Vector3.new(340, 0, -62), S, rng)
Buildings.Tower(street, -110, -80, 70, 70, 260, rng)
Buildings.DecoHotel(street, Vector3.new(430, 0, -70), S, 64, 44, 4, rng)
for x = -20, 380, 60 do
	Props.StreetLight(street, Vector3.new(x, 0.4, -24), S)
end
Props.Signal(street, 1, "X", Vector3.new(120, 0.4, -24), Vector3.new(-1, 0, 0), 16)

local placed = if bare then 0 else CityKit.Apply(street)
print(string.format("kit placed on %d stand-ins", placed))

local function color(c: any): { number }
	return { c.R, c.G, c.B }
end
local parts, meshes = {}, {}
for _, d in street:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		local entry = {
			cf = { d.CFrame:GetComponents() },
			size = { d.Size.X, d.Size.Y, d.Size.Z },
			-- (the vegetation's meshes wear the pack's textures in the game, not a slot)
			color = if d.Color then color(d.Color) else { 0.4, 0.5, 0.3 },
			material = if d.Material then d.Material.Name else "SmoothPlastic",
			transparency = d.Transparency,
			name = d.Name,
		}
		if d:IsA("MeshPart") then
			entry.source = d:GetAttribute("Source")
			table.insert(meshes, entry)
		else
			local shape = "Block"
			if d.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif d.ClassName == "Part" then
				shape = d.Shape.Name
			end
			entry.shape = shape
			table.insert(parts, entry)
		end
	end
end
fs.writeFile(out, serde.encode("json", { parts = parts, meshes = meshes }))
print(string.format("wrote %s: %d parts, %d kit meshes", out, #parts, #meshes))
