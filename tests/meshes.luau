--[[
	The Blender mesh path, in the simulator: fakes the imported ReplicatedStorage.VehicleMeshes
	(MeshParts named and sized as MeshManifest says), builds every bike and car, and checks the
	meshes replaced the part-built look and ride on the right joints. Then turns one import the
	wrong way round and checks that vehicle falls back to its part-built model.

	rojo sourcemap default.project.json -o sourcemap.json && lune run tests/meshes.luau
]]
local process = require("@lune/process")
local World = require("../tools/sim/World")
local Sim = require("../tools/sim/Instance")
local Vector3 = require("@lune/roblox").Vector3
local CFrame = require("@lune/roblox").CFrame
local Color3 = require("@lune/roblox").Color3
local Enum = require("@lune/roblox").Enum

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
local Bikes = server.Require(Shared:WaitForChild("Bikes"))

local failures = 0
local function check(ok: boolean, message: string)
	print((if ok then "[test] ok   " else "[test] FAIL ") .. message)
	if not ok then
		failures += 1
	end
end

-- The fake import
local folder = Sim.New("Model")
folder.Name = "VehicleMeshes"
local count = 0
for vehicleId, entries in Manifest do
	-- Studio's importer flattens the file: every MeshPart straight inside one model
	local _ = vehicleId
	for _, entry in entries do
		local part = Sim.Raw("MeshPart")
		Sim.States[part].Name = entry.Name
		-- the importer works in its own units: a uniform scale must not matter
		Sim.States[part].Props.MeshSize = entry.Size * 2.5
		-- laid out as the vehicle, somewhere in the world
		part.CFrame = CFrame.new(entry.Center * 2.5 + Vector3.new(40, 3, -12))
		part.Parent = folder
		count += 1
	end
end
folder.Parent = RS
print(string.format("faked %d meshes", count))

local BikeModel = server.Require(Models:WaitForChild("BikeModel"))
local CarModel = server.Require(Models:WaitForChild("CarModel"))

local function meshes(model: any): { any }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") then
			table.insert(out, d)
		end
	end
	return out
end

-- every bike on sale (and the police moto) has its Blender model
do
	local missing = {}
	for _, bike in Bikes.List do
		if Manifest[bike.Id] == nil then
			table.insert(missing, bike.Id)
		end
	end
	if Manifest[Bikes.PoliceMoto.Id] == nil then
		table.insert(missing, Bikes.PoliceMoto.Id)
	end
	check(#missing == 0, "every bike is in the Blender manifest (missing: " .. table.concat(missing, ", ") .. ")")
end

for _, bike in Bikes.List do
	local model = BikeModel.Build(bike, nil)
	local list = meshes(model)
	if Manifest[bike.Id] == nil then
		-- (a bike the Blender build hasn't modelled yet stays part-built)
		check(#list == 0 and model:FindFirstChildOfClass("Seat") ~= nil and model:FindFirstChild("GripL", true) ~= nil, bike.Id .. ": no meshes yet, so it stays part-built")
		continue
	end
	check(#list == #Manifest[bike.Id], string.format("%s: %d meshes placed", bike.Id, #list))
	local welded, wheel, steer, crank, fork, swing = 0, 0, 0, 0, 0, 0
	for _, part in list do
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		if weld and weld.Part1 == part then
			welded += 1
			local p0 = weld.Part0
			if p0.Name == "FrontHub" or p0.Name == "RearHub" then
				wheel += 1
			elseif p0.Name == "Steer" then
				steer += 1
			elseif p0.Name == "Crank" then
				crank += 1
			elseif p0.Name == "Fork" then
				fork += 1
			elseif p0.Name == "Swing" then
				swing += 1
			end
		end
	end
	check(welded == #list, string.format("%s: every mesh welded (%d/%d)", bike.Id, welded, #list))
	check(wheel > 0 and steer > 0 and (crank > 0) == bike.Pedals, string.format("%s: wheels %d, steering %d, cranks %d", bike.Id, wheel, steer, crank))
	check(fork > 0 and swing > 0, string.format("%s: fork lowers %d and swingarm %d meshes ride the suspension", bike.Id, fork, swing))
	local leftovers = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Part") and d.Transparency < 1 and d.Name ~= "Underglow" and d.Name ~= "ExhaustPipe" and d.Name ~= "ExhaustTip" and string.sub(d.Name, 1, 5) ~= "Hell_" then
			leftovers += 1
		end
	end
	check(leftovers == 0, string.format("%s: no part-built pieces left showing (%d)", bike.Id, leftovers))
	local grips = model:FindFirstChild("GripL", true)
	local pedal = model:FindFirstChild("PedalL", true) or model:FindFirstChild("PegL", true)
	check(grips ~= nil and pedal ~= nil, bike.Id .. ": grip and foot attachments kept")
	check(model:FindFirstChildOfClass("Seat") ~= nil, bike.Id .. ": seat kept")
	if not bike.Pedals then
		local sprocket = model:FindFirstChild("SprocketSpin", true)
		local top, bot = model:FindFirstChild("ChainTopSlide", true), model:FindFirstChild("ChainBotSlide", true)
		check(sprocket ~= nil and top ~= nil and bot ~= nil, bike.Id .. ": the front sprocket and both chain runs are on joints")
		local hub = top and (top :: any).Part1
		local dir, period = hub and hub:GetAttribute("Dir"), hub and hub:GetAttribute("Period")
		-- the runs head backward (+Z) and a link is a few centimetres
		check(typeof(dir) == "Vector3" and (dir :: Vector3).Z > 0.9 and type(period) == "number" and period > 0.05 and period < 0.3, string.format("%s: chain runs backward, link %.3f studs", bike.Id, if type(period) == "number" then period else -1))
	end
end

for _, kind in { "Police", "Sedan", "Hatch", "SUV", "Van", "Taxi" } do
	local model = CarModel.Build(kind, nil)
	local list = meshes(model)
	check(#list == #Manifest["Car_" .. kind], string.format("Car_%s: %d meshes placed", kind, #list))
	local onHubs = 0
	for _, part in list do
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		if weld and weld.Part0.Name == "WheelHub" then
			onHubs += 1
		end
	end
	check(onHubs >= 4, string.format("Car_%s: wheel meshes on the spinning hubs (%d)", kind, onHubs))
	check(model:FindFirstChild("Body") ~= nil and model:FindFirstChild("Cabin") ~= nil, "Car_" .. kind .. ": collision hulls kept")
	if kind == "Police" then
		check(model:FindFirstChild("LightRed") ~= nil and model:FindFirstChild("LightBlue") ~= nil, "police light bar kept")
	end
end

-- An import turned half round (Studio's forward axis) is read from the layout and turned back
local MeshKit = server.Require(Models:WaitForChild("MeshKit"))
for _, part in folder:GetChildren() do
	if string.sub(part.Name, 1, 11) == "flit_mini__" then
		local p = part.Position
		part.CFrame = CFrame.new(-p.X, p.Y, -p.Z)
	end
end
MeshKit.Forget("flit_mini")
local turnedBike = BikeModel.Build(Bikes.Get("flit_mini"), nil, { Static = true })
local turnedOk, straightOk = 0, 0
for _, part in meshes(turnedBike) do
	if part.CFrame.LookVector:Dot(Vector3.new(0, 0, 1)) > 0.99 then
		turnedOk += 1
	end
end
for _, part in meshes(BikeModel.Build(Bikes.Get("storm_x"), nil, { Static = true })) do
	if part.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.99 then
		straightOk += 1
	end
end
check(turnedOk > 0 and turnedOk == #meshes(turnedBike), string.format("a half-turned import is turned back (%d/%d)", turnedOk, #meshes(turnedBike)))
check(straightOk > 0, "a straight import is left alone")

-- A wrongly turned import falls back to parts
for _, part in folder:GetChildren() do
	if string.sub(part.Name, 1, 8) ~= "flit_s__" then
		continue
	end
	local size = Sim.States[part].Props.MeshSize
	Sim.States[part].Props.MeshSize = Vector3.new(size.Z, size.Y, size.X)
end
MeshKit.Forget("flit_s")
local fallback = BikeModel.Build(Bikes.Get("flit_s"), nil)
check(#meshes(fallback) == 0, "a turned import falls back to the part-built bike")

-- An import made before a bike was remodelled is placed by its old entries (MeshManifestV1)
do
	local V1 = server.Require(Models:WaitForChild("MeshManifestV1"))
	local id: string? = nil
	for _, bike in Bikes.List do
		if V1[bike.Id] and bike.Id ~= "flit_mini" and bike.Id ~= "flit_s" then
			id = bike.Id
			break
		end
	end
	if id then
		for _, part in folder:GetChildren() do
			if string.sub(part.Name, 1, #id + 2) == id .. "__" then
				part.Parent = nil
			end
		end
		local old: { [string]: any } = {}
		for _, entry in V1[id] do
			old[entry.Name] = entry
			local part = Sim.Raw("MeshPart")
			Sim.States[part].Name = entry.Name
			Sim.States[part].Props.MeshSize = entry.Size * 2.5
			part.CFrame = CFrame.new(entry.Center * 2.5 + Vector3.new(40, 3, -12))
			part.Parent = folder
		end
		MeshKit.Forget(id)
		local list = meshes(BikeModel.Build(Bikes.Get(id), nil, { Static = true }))
		local ratio: number? = nil
		local consistent = #list == #V1[id]
		for _, part in list do
			local entry = old[part.Name]
			if not entry then
				consistent = false
				break
			end
			local axis = if entry.Size.X >= entry.Size.Y and entry.Size.X >= entry.Size.Z then "X" elseif entry.Size.Y >= entry.Size.Z then "Y" else "Z"
			local r = part.Size[axis] / entry.Size[axis]
			ratio = ratio or r
			if math.abs(r - (ratio :: number)) > 1e-3 * (ratio :: number) then
				consistent = false
			end
		end
		check(consistent, string.format("%s: an import from before the remodel is placed by the old manifest (%d meshes)", id, #list))
	else
		check(true, "no remodelled vehicles in MeshManifestV1")
	end
end

-- The city kit on a little street: windows, the three tree species, a lamp
do
	local CityKit = server.Require(Models:WaitForChild("CityKit"))
	local Detail = server.Require(Shared:WaitForChild("City"):WaitForChild("Detail"))
	local Props = server.Require(Shared:WaitForChild("City"):WaitForChild("Props"))
	local street = Sim.New("Model")
	street.Name = "City"
	local face = CFrame.new(0, 0, -20)
	Detail.Windows(street, face, 40, 0, 24, 12, { Width = 5, Height = 6.5, Spacing = 9, Frame = Color3.fromRGB(240, 236, 228) })
	math.randomseed(5)
	local rng: any = {
		NextNumber = function(_, a: number?, b: number?): number
			local lo, hi = a or 0, b or 1
			return lo + math.random() * (hi - lo)
		end,
		NextInteger = function(_, a: number, b: number): number
			return math.random(a, b)
		end,
	}
	local species = {}
	for i = 1, 40 do
		Props.Tree(street, Vector3.new(i * 20, 0, 30), rng)
	end
	-- palms (coconut and royal) and a couple of the countryside's pines
	for i = 1, 12 do
		Props.Palm(street, Vector3.new(i * 25, 0, 90), rng)
	end
	local Countryside = server.Require(Shared:WaitForChild("City"):WaitForChild("Countryside"))
	local _ = Countryside
	Props.Lamp(street, Vector3.new(0, 0, 60))
	Props.Bench(street, CFrame.new(20, 0, 60) * CFrame.Angles(0, math.rad(90), 0))
	Props.Hydrant(street, Vector3.new(30, 0, 60))
	Detail.Bin(street, Vector3.new(40, 0, 60))
	Detail.Bollard(street, Vector3.new(50, 0, 60))
	Detail.ParkingMeter(street, Vector3.new(60, 0, 60))
	for _, d in street:GetDescendants() do
		if d:IsA("Model") and d.Name == "Tree" then
			species[d:GetAttribute("Species")] = true
		end
	end
	local function count(name: string): number
		local n = 0
		for _, d in street:GetDescendants() do
			if d.Name == name then
				n += 1
			end
		end
		return n
	end
	local frames, panes = count("WindowFrame"), count("Window")
	-- each palm's foot, lean and height before the swap
	local palms = {}
	for _, d in street:GetChildren() do
		if d:IsA("Model") and d.Name == "Palm" then
			local lo, hi
			for _, part in d:GetChildren() do
				if part.Name == "Trunk" then
					local half = part.CFrame.RightVector * (part.Size.X / 2)
					for _, p in { part.Position + half, part.Position - half } do
						if not lo or p.Y < lo.Y then
							lo = p
						end
						if not hi or p.Y > hi.Y then
							hi = p
						end
					end
				end
			end
			local top = -math.huge
			for _, part in d:GetDescendants() do
				if part:IsA("BasePart") then
					top = math.max(top, part.Position.Y + part.Size.Y / 2)
				end
			end
			table.insert(palms, { Model = d, Foot = lo, Lean = Vector3.new(hi.X - lo.X, 0, hi.Z - lo.Z), Top = top, Royal = d:GetAttribute("Species") == "Royal" })
		end
	end
	local placed = CityKit.Apply(street)
	check(species.Broadleaf and species.Birch and species.Conifer, "the street has all three tree species")
	check(placed == frames + 40 + 12 + 1 + 5, string.format("the kit replaced every window, tree, palm, lamp and street furniture (%d of %d)", placed, frames + 58))
	-- palms: the textured kit stands on the trunk's foot, about as tall, leaning the same way
	local palmsOk, leanOk = true, true
	for _, palm in palms do
		local bark, top = nil, -math.huge
		for _, part in palm.Model:GetChildren() do
			if part:IsA("MeshPart") then
				top = math.max(top, part.Position.Y + part.Size.Y / 2)
				if part.Name == "Kit_PalmBark" or part.Name == "Kit_RoyalTrunk" then
					bark = part
				end
			end
		end
		if not bark or math.abs(top - palm.Top) > palm.Top * 0.12 then
			palmsOk = false
		elseif not palm.Royal and palm.Lean.Magnitude > 0.5 then
			local off = Vector3.new(bark.Position.X - palm.Foot.X, 0, bark.Position.Z - palm.Foot.Z)
			if off:Dot(palm.Lean) <= 0 then
				leanOk = false
				print(string.format("[test]   palm lean (%.1f, %.1f), its bark's offset (%.2f, %.2f)", palm.Lean.X, palm.Lean.Z, off.X, off.Z))
			end
		end
	end
	check(palmsOk, "palms: the textured kit stands in for each one, about as tall")
	check(leanOk, "coconut palms lean the way their trunks (the colliders) lean")
	check(count("Frond") == 0 and count("Coconuts") == 0, "palm fronds and coconuts replaced")
	check(count("BinLid") == 0 and count("BollardBand") == 0 and count("Meter") == 0 and count("Nozzles") == 0, "street furniture trim replaced")
	-- lamps and trees stand upright (their meshes taller than wide), furniture stands on the ground
	local upright, grounded = true, true
	for _, d in street:GetDescendants() do
		if d:IsA("MeshPart") then
			local owner = d.Parent
			if owner and owner.Name == "Lamp" and d.Name ~= "Kit_Paint" and d.Size.Y < math.max(d.Size.X, d.Size.Z) then
				upright = false
			end
			-- (a tree's roots are buried a little, in proportion to its size)
			local tree = owner and (owner.Name == "Tree" or owner.Name == "Palm" or owner.Name == "Pine")
			if d.Position.Y - d.Size.Y / 2 < -(if tree then math.max(0.3, d.Size.Y * 0.02) else 0.3) then
				grounded = false
				print(string.format("[test]   %s in %s reaches %.2f below the ground (size %s)", d.Name, if owner then owner.Name else "?", -(d.Position.Y - d.Size.Y / 2), tostring(d.Size)))
			end
		end
	end
	check(upright, "lamp kits stand upright")
	check(grounded, "no kit piece sinks below the ground")
	check(count("WindowFrame") == 0 and count("Sill") == 0, "frames and sills are gone")
	check(count("Window") == panes, "the glass stays (it lights up at night)")
	check(count("Leaves") == 0 and count("Trunk") == 40 + 24, "trees and palms: leaves replaced, trunks kept as colliders")
	check(count("Globe") == 1 and count("Pole") == 1 and count("Collar") == 0, "lamp: globe and pole kept, trim replaced")
	-- each window surround sits on its frame: its casing over the frame's box, the glass behind the bars
	local ok = true
	for _, d in street:GetDescendants() do
		if d:IsA("MeshPart") and d.Parent == street and d.Name == "Kit_Paint" and d.Size.Y > 5 then
			local pane
			for _, w in street:GetChildren() do
				if w.Name == "Window" and (w.Position - d.Position).Magnitude < 1.5 then
					pane = w
				end
			end
			if not pane or math.abs(d.Size.X - (pane.Size.X + 0.7)) > 0.1 then
				ok = false
			end
		end
	end
	check(ok, "each window surround is fitted to its window")
	street:Destroy()
end

-- The facade and street kits on their stand-ins (PartKit.Kit): a stucco midrise with its shopfront
-- and roof, a house, a villa, a bungalow, a street light and a traffic signal; a warehouse (roll-up
-- doors), a condo tower (glass balcony rails), a gas station (its canopy) and a bus shelter
do
	local CityKit = server.Require(Models:WaitForChild("CityKit"))
	local KitSpec = server.Require(Models:WaitForChild("KitSpec"))
	local City = Shared:WaitForChild("City")
	local Buildings = server.Require(City:WaitForChild("Buildings"))
	local Neighborhoods = server.Require(City:WaitForChild("Neighborhoods"))
	local Props = server.Require(City:WaitForChild("Props"))
	local Detail = server.Require(City:WaitForChild("Detail"))
	local PartKit = server.Require(Shared:WaitForChild("PartKit"))
	math.randomseed(11)
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
	Buildings.Midrise(street, 0, 0, 60, 40, 4, Vector3.new(0, 0, -1), rng, nil, true, { "Cafe Sol" })
	Buildings.House(street, Vector3.new(150, 0, 0), Vector3.new(0, 0, -1), 30, rng, 70)
	Neighborhoods.Villa(street, Vector3.new(260, 0, 0), Vector3.new(0, 0, -1), rng, 70)
	Neighborhoods.Bungalow(street, Vector3.new(360, 0, 0), Vector3.new(0, 0, -1), rng)
	Buildings.Tower(street, 480, 0, 60, 60, 200, rng)
	Buildings.DecoHotel(street, Vector3.new(600, 0, 0), Vector3.new(0, 0, -1), 60, 40, 3, rng, false)
	Props.StreetLight(street, Vector3.new(0, 0, -60), Vector3.new(0, 0, -1))
	Props.Signal(street, 1, "X", Vector3.new(40, 0, -60), Vector3.new(1, 0, 0), 14)
	Buildings.Warehouse(street, 750, 0, 80, 50, 26, Vector3.new(0, 0, -1), rng)
	Buildings.CondoTower(street, 900, 0, 50, 50, 90, 0, rng)
	Buildings.GasStation(street, 1000, 1110, -40, 40, Vector3.new(0, 0, -1), rng)
	Detail.BusStop(street, CFrame.lookAt(Vector3.new(90, 0, -60), Vector3.new(90, 0, -61)), "1")
	-- a plain awning 30 wide: ten 3-wide modules
	local awnings = Sim.New("Model")
	awnings.Name = "Awnings"
	awnings.Parent = street
	PartKit.Kit(PartKit.Box(awnings, "Awning", Vector3.new(30, 0.3, 6), CFrame.new(0, 10, -80), Color3.fromRGB(200, 40, 40), Enum.Material.Fabric), "AwningStripe")
	local stand: { any } = {}
	local drops, used = 0, {}
	for _, d in street:GetDescendants() do
		if d:IsA("BasePart") then
			local kit = d:GetAttribute("Kit")
			if type(kit) == "string" then
				table.insert(stand, { Part = d, Kit = kit, CFrame = d.CFrame, Size = d.Size, Color = d.Color, Material = d.Material, Collide = d.CanCollide, Parent = d.Parent })
				used["Kit_" .. kit] = true
			elseif d:GetAttribute("KitDrop") then
				drops += 1
			end
		end
	end
	local unused = {}
	for name in KitSpec do
		if not used[name] and name ~= "Kit_Window_Modern" then
			table.insert(unused, name)
		end
	end
	check(#unused == 0, "the test street has a stand-in for every kit" .. (if #unused > 0 then " (missing " .. table.concat(unused, ", ") .. ")" else ""))
	local lamps = 0
	for _, d in street:GetDescendants() do
		if d.Name == "Red" or d.Name == "Yellow" or d.Name == "Green" or d.Name == "Globe" then
			lamps += 1
		end
	end
	local panes = 0
	for _, d in street:GetDescendants() do
		if d.Name == "Window" then
			panes += 1
		end
	end
	CityKit.Apply(street)
	local left, kept = 0, 0
	for _, s in stand do
		if s.Part.Parent then
			if s.Part.Transparency < 1 then
				left += 1
				print(string.format("[test]   %s stand-in (%s) still showing", s.Part.Name, s.Kit))
			elseif s.Collide then
				kept += 1
			end
		end
	end
	check(left == 0, string.format("every stand-in made way for its kit (%d stand-ins, %d kept as colliders)", #stand, kept))
	local dropsLeft = 0
	for _, d in street:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("KitDrop") and d.Transparency < 1 then
			dropsLeft += 1
		end
	end
	check(drops > 0 and dropsLeft == 0, string.format("the trim the kits draw themselves is gone (%d parts)", drops))
	local lampsAfter, panesAfter = 0, 0
	for _, d in street:GetDescendants() do
		if d.Name == "Red" or d.Name == "Yellow" or d.Name == "Green" or d.Name == "Globe" then
			lampsAfter += 1
		elseif d.Name == "Window" then
			panesAfter += 1
		end
	end
	check(lampsAfter == lamps and lamps == 4, "the signal's lamps and the street light's lens stay parts")
	check(panesAfter == panes, "the window glass stays (it lights up at night)")
	-- each stand-in's centre lies inside one of its kit's meshes, the mesh turned the stand-in's way
	local function meshesIn(parent: any): { any }
		local out = {}
		for _, d in parent:GetChildren() do
			if d:IsA("MeshPart") then
				table.insert(out, d)
			end
		end
		return out
	end
	local AXES = { ["+X"] = Vector3.new(1, 0, 0), ["-X"] = Vector3.new(-1, 0, 0), ["+Y"] = Vector3.new(0, 1, 0), ["-Z"] = Vector3.new(0, 0, -1) }
	-- (the fake import may be turned half round, which every kit piece undoes about its own Y)
	local flip = if MeshKit.ImportTurn() == 180 then -1 else 1
	local placedOk, turnedOk, paintOk = true, true, true
	local function over(parent: any, point: any): any
		-- the mesh over a point, nearest it (an arm's mesh also reaches its head's centre)
		local hit, best = nil, math.huge
		for _, m in meshesIn(parent) do
			local p = m.CFrame:PointToObjectSpace(point)
			local half = m.Size / 2 + Vector3.new(0.1, 0.1, 0.1)
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z and p.Magnitude < best then
				hit, best = m, p.Magnitude
			end
		end
		return hit
	end
	for _, s in stand do
		local spec = KitSpec["Kit_" .. s.Kit]
		if spec.Ring then
			-- a ring (a cornice) runs round its box: a module out from the middle of each wall
			local depth = spec.Reference.Z * s.Size.Y / spec.Reference.Y
			local hx, hz = s.Size.X / 2 - depth / 2, s.Size.Z / 2 - depth / 2
			for _, offset in { Vector3.new(0, 0, -hz), Vector3.new(0, 0, hz), Vector3.new(hx, 0, 0), Vector3.new(-hx, 0, 0) } do
				if not over(s.Parent, s.CFrame * offset) then
					placedOk = false
					print(string.format("[test]   no %s module out from the wall at %s", s.Kit, tostring(offset)))
				end
			end
			continue
		end
		local hit = over(s.Parent, s.CFrame.Position)
		if not hit then
			placedOk = false
			print(string.format("[test]   no %s mesh over its stand-in %s", s.Kit, s.Part.Name))
			continue
		end
		local up = AXES[s.Part:GetAttribute("KitUp") or "+Y"]
		local out = AXES[s.Part:GetAttribute("KitOut") or "-Z"]
		local wantUp, wantOut = s.CFrame:VectorToWorldSpace(up), s.CFrame:VectorToWorldSpace(out)
		if hit.CFrame.UpVector:Dot(wantUp) < 0.99 or hit.CFrame.LookVector:Dot(wantOut * flip) < 0.99 then
			turnedOk = false
			print(string.format("[test]   %s kit turned wrong: up %s look %s, wanted %s %s", s.Kit, tostring(hit.CFrame.UpVector), tostring(hit.CFrame.LookVector), tostring(wantUp), tostring(wantOut)))
		end
		for _, m in meshesIn(s.Parent) do
			if m.Name == "Kit_Paint" and (m.CFrame.Position - s.CFrame.Position).Magnitude < 0.01 + m.Size.Magnitude / 2 then
				if m.Color ~= s.Color and m.Material ~= s.Material then
					-- (a neighbouring stand-in's paint can sit here too; only flag one that matches neither)
					local any = false
					for _, other in stand do
						if other.Parent == s.Parent and other.Color == m.Color and other.Material == m.Material then
							any = true
						end
					end
					if not any then
						paintOk = false
					end
				end
			end
		end
	end
	check(placedOk, "each kit sits on its stand-in")
	check(turnedOk, "each kit stands the way its stand-in does (posts on their X axis, side windows facing out)")
	check(paintOk, "a kit's Paint takes its stand-in's colour and material")
	-- the stucco midrise's windows got Miami's aluminium surround (its own slot), not the classical one
	local alu = 0
	for _, d in street:GetDescendants() do
		if d:IsA("MeshPart") and d.Name == "Kit_Alu" then
			alu += 1
		end
	end
	check(alu > 0, "stucco windows wear the modern surround")
	-- the finest kits are tagged so Performance mode can hide them on phones
	local tagged = world.Services.CollectionService:GetTagged(CityKit.FINE_TAG)
	check(#tagged > 0, string.format("fine detail tagged for Performance mode (%d meshes)", #tagged))
	-- a 30-wide plain awning: ten modules
	local awningPieces = #(MeshKit.Pieces("Kit_AwningStripe") or {})
	check(#meshesIn(awnings) == 10 * awningPieces, string.format("a 30-stud awning is ten modules (%d meshes, %d a module)", #meshesIn(awnings), awningPieces))
	street:Destroy()
end

-- The suspension's joints, on the part-built bikes: put each Motor6D's Transform through the chain
-- the way Roblox does (Part1 = Part0 * C0 * Transform * C1:Inverse()) and look where things end up
folder.Parent = nil
for _, bike in Bikes.List do
	MeshKit.Forget(bike.Id)
end
local VIS = server.Require(Shared:WaitForChild("Config")).VISUAL_STUDS_PER_METER
local cases = {}
for _, bike in Bikes.List do
	table.insert(cases, { bike, 1 })
end
-- fitted to bigger and smaller riders
table.insert(cases, { Bikes.Get("hornet_6"), 1.6 })
table.insert(cases, { Bikes.Get("flit_mini"), 0.8 })
for _, case in cases do
	local bike, size = case[1], case[2]
	local model = BikeModel.Build(bike, nil, { Scale = size })
	local sus = BikeModel.SuspensionGeometry(bike, size)
	local built: { [any]: any } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			built[d] = d.CFrame
		end
	end
	local function solve(pose: any): { [any]: any }
		local transforms = { ForkSlide = pose.Fork, SwingJoint = pose.Swing, ShockJoint = pose.ShockTop, ShockRodJoint = pose.ShockEnd }
		local at: { [any]: any } = {}
		local function place(part: any): any
			if at[part] then
				return at[part]
			end
			if part == model.PrimaryPart then
				at[part] = built[part]
				return at[part]
			end
			for _, child in part:GetChildren() do
				if child:IsA("Motor6D") and child.Part1 == part then
					at[part] = place(child.Part0) * child.C0 * (transforms[child.Name] or CFrame.identity) * child.C1:Inverse()
					return at[part]
				elseif child:IsA("WeldConstraint") and child.Part1 == part then
					at[part] = place(child.Part0) * built[child.Part0]:ToObjectSpace(built[part])
					return at[part]
				end
			end
			at[part] = built[part]
			return at[part]
		end
		for part in built do
			place(part)
		end
		return at
	end
	local frontHub, rearHub = model:FindFirstChild("FrontHub", true), model:FindFirstChild("RearHub", true)
	local worst, aligned, clear = 0, true, true
	for _, c in { { 0, 0 }, { 0.3, 0.3 }, { 1, 0.5 }, { 0.5, 1 }, { 1, 1 } } do
		local cf, cr = c[1] * sus.Travel[1], c[2] * sus.Travel[2]
		local at = solve(BikeModel.SuspensionPose(sus, cf, cr))
		worst = math.max(worst, math.abs(at[frontHub].Position.Y - (sus.Radius[1] * size + cf) * VIS), math.abs(at[rearHub].Position.Y - (sus.Radius[2] * size + cr) * VIS))
		-- the shock's body and shaft point along one line
		local body, shaft
		for part in at do
			if part.Name == "ShockBody" then
				body = part
			elseif part.Name == "ShockShaft" then
				shaft = part
			end
		end
		if body and shaft then
			-- (tubes are cylinders along their X)
			local a, b = at[body].RightVector, at[shaft].RightVector
			if math.abs(a:Dot(b)) < 0.9999 then
				aligned = false
			end
		end
		-- the fork lowers stay below the crown
		local crown
		for part in at do
			if part.Name == "Crown" then
				crown = part
			end
		end
		for part in at do
			if part.Name == "ForkLeg" and crown then
				local axis = at[crown].UpVector
				local legTop = at[part].Position + at[part].RightVector * (part.Size.X / 2)
				local legTop2 = at[part].Position - at[part].RightVector * (part.Size.X / 2)
				local high = math.max(legTop:Dot(axis), legTop2:Dot(axis))
				local crownLow = at[crown].Position:Dot(axis) - crown.Size.Y / 2
				if high > crownLow + 0.01 then
					clear = false
				end
			end
		end
	end
	-- deep in the travel neither tyre runs into the bodywork (big landings may go past that for a frame)
	do
		local CLEAR = tonumber(process.env.CLEAR) or 0.7
		local at = solve(BikeModel.SuspensionPose(sus, CLEAR * sus.Travel[1], CLEAR * sus.Travel[2]))
		local width = bike.Geometry.TireWidth * VIS * size / 2
		local hit = {}
		for part, cf in at do
			local body = { BatteryCase = true, SideCover = true, Tank = true, SeatPad = true, Tail = true, Fender = true, Motor = true }
			if not body[part.Name] then
				continue
			end
			for i, hub in { frontHub, rearHub } do
				local centre = at[hub].Position
				local radius = sus.Radius[i] * VIS * size
				local loc = cf:PointToObjectSpace(centre)
				local half = part.Size / 2
				local near = cf:PointToWorldSpace(Vector3.new(math.clamp(loc.X, -half.X, half.X), math.clamp(loc.Y, -half.Y, half.Y), math.clamp(loc.Z, -half.Z, half.Z)))
				local d = near - centre
				-- the tyre is a disc in the bike's side plane: inside its radius and its width
				if math.abs(d.X) < width and math.sqrt(d.Y * d.Y + d.Z * d.Z) < radius - 0.02 then
					table.insert(hit, (if i == 1 then "front tyre in " else "rear tyre in ") .. part.Name)
				end
			end
		end
		check(#hit == 0, string.format("%s: at " .. math.floor(CLEAR * 100) .. "%% travel the tyres clear the bodywork %s", bike.Id, table.concat(hit, ", ")))
	end
	check(worst < 0.002, string.format("%s: compressed, each wheel rises by its compression (off by %.4f studs)", bike.Id, worst))
	check(aligned, bike.Id .. ": the shock's body and shaft stay in line")
	check(clear, bike.Id .. ": the fork lowers clear the crown at full travel")
end

-- The realism pack's materials: the variants saved with the import go live in MaterialService,
-- sized to the city's scale, the turned copies left alone unless asked for
do
	local Config = server.Require(Shared:WaitForChild("Config"))
	local Materials = server.Require(Shared:WaitForChild("Materials"))
	local pack = Sim.New("Model")
	pack.Name = "VehicleMeshes"
	local saved = Sim.New("Folder")
	saved.Name = "Materials"
	saved.Parent = pack
	for _, spec in { { "RealAsphalt", 2.0, false }, { "RealClayRoofTiles", 1.0, false }, { "RealClayRoofTiles90", 1.0, true } } do
		local variant = Sim.New("MaterialVariant")
		variant.Name = spec[1]
		variant:SetAttribute("TileMeters", spec[2])
		variant:SetAttribute("Turned", spec[3])
		variant.Parent = saved
	end
	pack.Parent = RS
	local made = Materials.Apply()
	local live = world.Services.MaterialService:FindFirstChild("RealAsphalt")
	check(made == 3, string.format("the pack's material variants were installed (%d of 3)", made))
	check(live ~= nil and math.abs(live.StudsPerTile - 2.0 * Config.CITY_STUDS_PER_METER) < 1e-6, "an installed variant tiles at its real size in the city's scale")
	pack:Destroy()
end

for _, e in world.Errors do
	print("  ERROR: " .. e)
	failures += 1
end
if failures > 0 then
	print(string.format("%d failure(s)", failures))
	process.exit(1)
end
print("mesh checks passed")
