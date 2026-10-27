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

for _, bike in Bikes.List do
	local model = BikeModel.Build(bike, nil)
	local list = meshes(model)
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
	local placed = CityKit.Apply(street)
	check(species.Broadleaf and species.Birch and species.Conifer, "the street has all three tree species")
	check(placed == frames + 40 + 1 + 5, string.format("the kit replaced every window, tree, lamp and street furniture (%d of %d)", placed, frames + 46))
	check(count("BinLid") == 0 and count("BollardBand") == 0 and count("Meter") == 0 and count("Nozzles") == 0, "street furniture trim replaced")
	-- lamps and trees stand upright (their meshes taller than wide), furniture stands on the ground
	local upright, grounded = true, true
	for _, d in street:GetDescendants() do
		if d:IsA("MeshPart") then
			local owner = d.Parent
			if owner and (owner.Name == "Lamp" or owner.Name == "Tree") and d.Name ~= "Kit_Paint" and d.Size.Y < math.max(d.Size.X, d.Size.Z) then
				upright = false
			end
			if d.Position.Y - d.Size.Y / 2 < -0.3 then
				grounded = false
			end
		end
	end
	check(upright, "lamp and tree kits stand upright")
	check(grounded, "no kit piece sinks below the ground")
	check(count("WindowFrame") == 0 and count("Sill") == 0, "frames and sills are gone")
	check(count("Window") == panes, "the glass stays (it lights up at night)")
	check(count("Leaves") == 0 and count("Trunk") == 40, "trees: leaves replaced, trunks kept as colliders")
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

for _, e in world.Errors do
	print("  ERROR: " .. e)
	failures += 1
end
if failures > 0 then
	print(string.format("%d failure(s)", failures))
	process.exit(1)
end
print("mesh checks passed")
