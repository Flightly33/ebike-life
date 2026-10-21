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

for _, bike in Bikes.List do
	local model = BikeModel.Build(bike, nil)
	local list = meshes(model)
	check(#list == #Manifest[bike.Id], string.format("%s: %d meshes placed", bike.Id, #list))
	local welded, wheel, steer, crank = 0, 0, 0, 0
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
			end
		end
	end
	check(welded == #list, string.format("%s: every mesh welded (%d/%d)", bike.Id, welded, #list))
	check(wheel > 0 and steer > 0 and (crank > 0) == bike.Pedals, string.format("%s: wheels %d, steering %d, cranks %d", bike.Id, wheel, steer, crank))
	local leftovers = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Part") and d.Transparency < 1 and d.Name ~= "Underglow" and d.Name ~= "ExhaustPipe" and d.Name ~= "ExhaustTip" then
			leftovers += 1
		end
	end
	check(leftovers == 0, string.format("%s: no part-built pieces left showing (%d)", bike.Id, leftovers))
	local grips = model:FindFirstChild("GripL", true)
	local pedal = model:FindFirstChild("PedalL", true) or model:FindFirstChild("PegL", true)
	check(grips ~= nil and pedal ~= nil, bike.Id .. ": grip and foot attachments kept")
	check(model:FindFirstChildOfClass("Seat") ~= nil, bike.Id .. ": seat kept")
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

-- A wrongly turned import falls back to parts
for _, part in folder:GetChildren() do
	if string.sub(part.Name, 1, 8) ~= "velo_s__" then
		continue
	end
	local size = Sim.States[part].Props.MeshSize
	Sim.States[part].Props.MeshSize = Vector3.new(size.Z, size.Y, size.X)
end
local MeshKit = server.Require(Models:WaitForChild("MeshKit"))
MeshKit.Forget("velo_s")
local fallback = BikeModel.Build(Bikes.Get("velo_s"), nil)
check(#meshes(fallback) == 0, "a turned import falls back to the part-built bike")

for _, e in world.Errors do
	print("  ERROR: " .. e)
	failures += 1
end
if failures > 0 then
	print(string.format("%d failure(s)", failures))
	process.exit(1)
end
print("mesh checks passed")
