--[[
	Real corners of the city for blender/preview_street.py: builds the whole city in the simulator
	(Builder.Build, as the game does without the baked map), puts the city kit on it the way the
	game does (Models/CityKit, the kit's meshes faked from MeshManifest as tests/meshes.luau does),
	and writes out what stands round each spot: the parts (with the named materials Dressing gave
	them) and every kit mesh, scaled back to design units, plus a camera view per spot.

	rojo sourcemap default.project.json -o sourcemap.json
	lune run tools/lune/preview_area.luau <area.json> <views.json> [spot,spot...] [detail]
	(`detail`: the client's street, building and home detail too, Client/CityDetail)
	/root/tools/blendenv/bin/python blender/preview_street.py <area.json> <outdir> <views.json> [samples]
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")
local World = require("../sim/World")
local Sim = require("../sim/Instance")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local out, viewsOut = process.args[1], process.args[2]
local only = process.args[3]
local withDetail = process.args[4] == "detail"
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
local Config = server.Require(Shared:WaitForChild("Config"))

-- the fake import: every manifest mesh, named and sized as Studio's importer leaves them
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
local Layout = server.Require(City:WaitForChild("Layout"))
local Builder = server.Require(City:WaitForChild("Builder"))
local CityKit = server.Require(Models:WaitForChild("CityKit"))
local PartKit = server.Require(Shared:WaitForChild("PartKit"))

local K = Config.WORLD_SCALE
local function line(i: number): number
	return Layout.Line(i)
end
-- the spots, in the game's studs: where to stand, where to look, how far round to take
local SPOTS: { [string]: any } = {
	brickell = { At = Vector3.new(line(6) - 30, 6, (line(6) + line(7)) / 2 + 60), Look = Vector3.new(line(6) - 30, 30, (line(6) + line(7)) / 2 - 200), Radius = 520 },
	suburb = { At = Vector3.new(line(1) + 20, 6, (line(1) + line(2)) / 2 + 80), Look = Vector3.new(line(1) - 20, 10, (line(1) + line(2)) / 2 - 150), Radius = 420 },
	downtown = { At = Vector3.new(line(5) + 60, 7, line(4) + 40), Look = Vector3.new(line(6), 25, line(4) - 120), Radius = 520 },
	freeway = { At = Vector3.new((line(4) + line(5)) / 2 - 20, Layout.FREEWAY_Y + 9, (line(2) + line(3)) / 2), Look = Vector3.new((line(4) + line(5)) / 2 + 20, Layout.FREEWAY_Y + 4, (line(2) + line(3)) / 2 - 400), Radius = 520 },
	beach = { At = Layout.Places.Beach + Vector3.new(-90, 7, 60), Look = Layout.Places.Beach + Vector3.new(-200, 14, -120), Radius = 460 },
	plaza = { At = Layout.Places.Plaza + Vector3.new(30, 7, 70), Look = Layout.Places.Plaza + Vector3.new(-40, 8, -100), Radius = 420 },
	depot = { At = Layout.Places.Depot + Vector3.new(-60, 9, 90), Look = Layout.Places.Depot + Vector3.new(30, 6, -90), Radius = 480 },
	port = { At = Layout.Places.Port + Vector3.new(40, 12, 40), Look = Layout.Places.Port + Vector3.new(200, 10, -150), Radius = 500 },
}

print("== building the city")
local city = Builder.Build()

-- close-ups found in the built city: the first pole with a transformer, a stop sign, a signal
-- cabinet (with its corner's signals) and a pool cage
local function first(folderName: string, test: (any) -> boolean): any?
	local f = city:FindFirstChild(folderName)
	if f then
		for _, d in f:GetDescendants() do
			if test(d) then
				return d
			end
		end
	end
	return nil
end
local pole = first("PowerLines", function(d)
	return d.Name == "Transformer"
end)
if pole then
	local base = pole.Parent:FindFirstChild("Pole").CFrame.Position
	local foot = Vector3.new(base.X, base.Y - pole.Parent:FindFirstChild("Pole").Size.X / 2, base.Z)
	SPOTS.pole = { At = foot + Vector3.new(-26 * K, 5 * K, 16 * K), Look = foot + Vector3.new(0, 20 * K, 0), Radius = 160, Lens = 28 }
end
local stop = first("StreetSigns", function(d)
	return d.Name == "StopPlate"
end)
if stop then
	local at = stop.CFrame.Position
	local facing = stop.CFrame.LookVector
	SPOTS.stop = { At = at + facing * 16 * K + stop.CFrame.RightVector * 7 * K - Vector3.new(0, 2.5 * K, 0), Look = at - Vector3.new(0, 3 * K, 0), Radius = 140, Lens = 30 }
end
local cabinet = first("StreetSigns", function(d)
	return d.Name == "Cabinet"
end)
if cabinet then
	local at = cabinet.CFrame.Position
	SPOTS.corner = { At = at + Vector3.new(14 * K, 3 * K, 22 * K), Look = at + Vector3.new(-10 * K, 8 * K, -12 * K), Radius = 160, Lens = 24 }
end
-- homes: in front of the first house, villa, bungalow and mansion; the beach's dune line
local function home(kind: string, bodyName: string, spot: string)
	local walls: any = nil
	for _, d in city:GetDescendants() do
		if d.Name == bodyName and d.Parent and d.Parent.Name == kind and d:IsA("BasePart") then
			walls = d
			break
		end
	end
	if walls then
		local cf, size = walls.CFrame, walls.Size
		SPOTS[spot] = {
			At = (cf * CFrame.new(size.X * 0.42, -size.Y / 2 + 5.5 * K, -size.Z / 2 - 30 * K)).Position,
			Look = (cf * CFrame.new(-size.X * 0.05, -size.Y / 2 + 4 * K, -size.Z / 2)).Position,
			Radius = 200,
			Lens = 24,
		}
	end
end
home("House", "Walls", "house")
home("Villa", "Walls", "villa")
home("Bungalow", "Walls", "bungalow")
home("Mansion", "Ground", "mansion")
for _, d in city:GetDescendants() do
	if d.Name == "Shrub" and d:GetAttribute("Species") == "SeaGrape" then
		local p = (d:FindFirstChild("Leaves") :: any).CFrame.Position
		SPOTS.dune = { At = p + Vector3.new(26 * K, 4 * K, 22 * K), Look = p + Vector3.new(-4 * K, 2 * K, -8 * K), Radius = 180, Lens = 26 }
		break
	end
end
local cage = first("Blocks", function(d)
	return d.Name == "PoolCage"
end)
if cage then
	local at = (cage:FindFirstChild("CageRidge") :: any).CFrame.Position
	SPOTS.cage = { At = at + Vector3.new(34 * K, 6 * K, 30 * K), Look = at - Vector3.new(0, 8 * K, 0), Radius = 150, Lens = 26 }
end

local wanted: { string } = {}
for name in SPOTS do
	if not only or string.find("," .. only .. ",", "," .. name .. ",", 1, true) then
		table.insert(wanted, name)
	end
end
table.sort(wanted)

-- The things round a spot, moved into a model of their own: whole models (a house, a tree, a lamp)
-- by where their first part stands, loose parts by where they stand
local function positionOf(inst: any): Vector3?
	if inst:IsA("BasePart") then
		return inst.CFrame.Position
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			return d.CFrame.Position
		end
	end
	return nil
end

local function gather(source: any, into: any, centre: Vector3, radius: number)
	for _, child in source:GetChildren() do
		if child:IsA("Folder") then
			local sub = Sim.New("Folder")
			sub.Name = child.Name
			sub.Parent = into
			gather(child, sub, centre, radius)
		else
			local p = positionOf(child)
			if p then
				local flat = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z).Magnitude
				-- (long slabs: anything whose box reaches the circle)
				local reach = if child:IsA("BasePart") then math.max(child.Size.X, child.Size.Z) / 2 else 60
				if flat < radius + reach then
					child.Parent = into
				end
			end
		end
	end
end

-- the client's detail (Client/CityDetail), built offline in a client context
local CityDetail: any = nil
if withDetail then
	-- (the client's modules wait for the remotes the server's Remotes module makes)
	server.Require(Shared:WaitForChild("Remotes"))
	local viewer = world:AddPlayer("Viewer", 1, true)
	local client = world:Context("client", false, viewer)
	CityDetail = client.Require(world.Services.StarterPlayer.StarterPlayerScripts:WaitForChild("Client"):WaitForChild("CityDetail"))
end

local views: { [string]: any } = {}
local parts, meshes = {}, {}
local function color(c: any): { number }
	return { c.R, c.G, c.B }
end
for _, name in wanted do
	local spot = SPOTS[name]
	local area = Sim.New("Model")
	area.Name = "City"
	gather(city, area, spot.At, spot.Radius)
	if CityDetail then
		local detail = Sim.New("Model")
		detail.Name = "Detail"
		detail.Parent = area
		print(string.format("%s: %d detail units", name, CityDetail.BuildAround(area, detail, spot.At, spot.Radius)))
	end
	PartKit.Scale(area, 1 / K)
	local placed = CityKit.Apply(area)
	local np, nm = 0, 0
	for _, d in area:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local entry = {
				cf = { d.CFrame:GetComponents() },
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				color = if d.Color then color(d.Color) else { 0.4, 0.5, 0.3 },
				material = if d.Material then d.Material.Name else "SmoothPlastic",
				transparency = d.Transparency,
				name = d.Name,
				variant = if d.MaterialVariant ~= "" then d.MaterialVariant else nil,
			}
			if d:IsA("MeshPart") then
				entry.source = d:GetAttribute("Source")
				table.insert(meshes, entry)
				nm += 1
			else
				local shape = "Block"
				if d.ClassName == "WedgePart" then
					shape = "Wedge"
				elseif d.ClassName == "Part" then
					shape = d.Shape.Name
				end
				entry.shape = shape
				table.insert(parts, entry)
				np += 1
			end
		end
	end
	local at, look = spot.At / K, spot.Look / K
	views[name] = { { at.X, at.Y, at.Z }, { look.X, look.Y, look.Z }, spot.Lens or 24 }
	print(string.format("%s: %d parts, %d kit meshes (%d stand-ins swapped)", name, np, nm, placed))
	area:Destroy()
end
fs.writeFile(out, serde.encode("json", { parts = parts, meshes = meshes }))
fs.writeFile(viewsOut, serde.encode("json", views))
print("wrote " .. out .. " and " .. viewsOut)
