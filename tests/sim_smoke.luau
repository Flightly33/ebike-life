--[[
	End-to-end smoke test in the simulator (tools/sim): boots the real server and client scripts and
	plays the game: spawns a bike, gets on, rides, earns, wheelies past a cop until wanted, gets
	chased, escapes, gets busted, buys a bike, tunes and paints it, opens a crate, buys a boost,
	charges, opens every menu, gets off. Fails on any runtime error and on anything a player would
	notice (the bike not moving, riding not paying, a wheelie past a cop not starting a chase...).

	rojo sourcemap default.project.json -o sourcemap.json && lune run tests/sim_smoke.luau
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local World = require("../tools/sim/World")
local Sim = require("../tools/sim/Instance")

local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local root = process.cwd
if string.sub(root, -1) ~= "/" then
	root ..= "/"
end

World.Digest = process.env.SIM_DIGEST ~= nil
local world = World.new(root)
local RS = world.Services.ReplicatedStorage
local SSS = world.Services.ServerScriptService
local WS = world.Services.Workspace

local function check(ok: boolean, message: string)
	if ok then
		print("[test] ok   " .. message)
	else
		table.insert(world.Errors, "CHECK FAILED: " .. message)
		print("[test] FAIL " .. message)
	end
end

local server = world:Context("server", true, nil)
print("== booting server")
local started = os.clock()
server.Run(SSS:WaitForChild("Server"))
world:Run(3)
print(string.format("   (server boot took %.1f s real time)", os.clock() - started))

local Shared = RS:WaitForChild("Shared")
local Layout = server.Require(Shared:WaitForChild("City"):WaitForChild("Layout"))
local Config = server.Require(Shared:WaitForChild("Config"))
check(WS:FindFirstChild("City") ~= nil, "the city was built")
local vehicles = WS:FindFirstChild("Vehicles")
local cops, traffic = 0, 0
for _, car in vehicles and vehicles:GetChildren() or {} do
	if car:GetAttribute("Kind") == "Cop" then
		cops += 1
	else
		traffic += 1
	end
end
check(cops == Config.Police.PatrolCount, string.format("%d patrol cars out (%d)", Config.Police.PatrolCount, cops))
check(traffic == Config.Traffic.CarCount, string.format("%d traffic cars out (%d)", Config.Traffic.CarCount, traffic))

-- Player, character and client
local player = world:AddPlayer("Tester", 1, true)
local rig = world:BuildRig()
Sim.States[rig].Name = "Tester"
local humanoid = rig:FindFirstChildOfClass("Humanoid")
humanoid.RigType = roblox.Enum.HumanoidRigType.R15
rig:PivotTo(CFrame.new(Layout.Places.Spawn + Vector3.new(0, 3, 0)))
rig.Parent = WS
player.Character = rig
local client = world:Context("client", false, player)
print("== booting client")
client.Run(world.Services.StarterPlayer.StarterPlayerScripts:WaitForChild("Client"))
world:Run(4)

local ServerData = server.Require(SSS.Server:WaitForChild("DataService"))
local BikeService = server.Require(SSS.Server:WaitForChild("BikeService"))
local PoliceService = server.Require(SSS.Server:WaitForChild("PoliceService"))
local ClientRemotes = client.Require(Shared:WaitForChild("Remotes"))
local Client = world.Services.StarterPlayer.StarterPlayerScripts.Client
local BikeController = client.Require(Client:WaitForChild("BikeController"))
local UI = client.Require(Client:WaitForChild("UI"))

check(player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD") ~= nil, "HUD built")
check(player:GetAttribute("Cash") == Config.Economy.StartCash, "profile loaded with the starting cash (" .. tostring(player:GetAttribute("Cash")) .. ")")

-- Police events the client hears
local policeEvents: { string } = {}
ClientRemotes.Event("Police").OnClientEvent:Connect(function(kind)
	table.insert(policeEvents, kind)
	print("[test] police event: " .. tostring(kind))
end)
local payouts = 0
ClientRemotes.Event("Payout").OnClientEvent:Connect(function(amount, label)
	payouts += 1
	if label ~= "" then
		print(string.format("[test] payout +$%d %s", amount, label))
	end
end)

--------------------------------------------------------------------------------
print("== spawn the starter bike and get on")
ClientRemotes.Event("SpawnBike"):FireServer("metro_c1")
world:Run(1)
local bikes = WS:FindFirstChild("Bikes")
local bike = bikes and bikes:FindFirstChild("Bike_1")
check(bike ~= nil, "bike spawned next to the player")
local ride = BikeService.Get(player)
if bike and ride then
	local prompt = bike.PrimaryPart:FindFirstChild("EnterPrompt")
	check(prompt ~= nil, "bike has an Enter prompt")
	Sim.Fire(prompt, "Triggered", player)
	world:Run(0.5)
end
check(BikeController.Active == true, "client controller took over the bike")
check(ride ~= nil and ride.Riding == true, "server sees the player riding")

--------------------------------------------------------------------------------
print("== ride: hold W for 8 s")
local start = bike and bike.PrimaryPart.Position or Vector3.zero
local cashBefore = player:GetAttribute("Cash")
world.Keys.W = true
world:Run(8)
local kmh = BikeController.Kmh()
local moved = bike and (bike.PrimaryPart.Position - start).Magnitude or 0
print(string.format("[test] %.1f km/h after 8 s, moved %.0f studs", kmh, moved))
check(kmh > 25 and kmh < 34, "the commuter reaches its 32 km/h class limit")
check(moved > 120, "the bike moved")
check(ride ~= nil and ride.State.Kmh > 20, "the server gets the rider's state")
check((player:GetAttribute("Cash") :: number) > cashBefore, string.format("riding pays (%s -> %s)", tostring(cashBefore), tostring(player:GetAttribute("Cash"))))
check(payouts > 0, "+$ pops reach the client")

--------------------------------------------------------------------------------
print("== wheelie in front of a cop")
-- Bring a patrol car alongside, facing the same way
local unitCar: any = nil
for _, car in vehicles:GetChildren() do
	if car:GetAttribute("Kind") == "Cop" then
		unitCar = car
		break
	end
end
local CarDriver = server.Require(SSS.Server:WaitForChild("CarDriver"))
local bikeRoot = bike.PrimaryPart
for _, d in CarDriver.All do
	if d.Model == unitCar then
		d.Position = bikeRoot.Position + Vector3.new(25, 0, 0)
		d.Speed = 0
		d.Mode = "Idle"
	end
end
world.Keys.LeftShift = true
world:Run(6)
local physics = BikeController.Physics
print(string.format("[test] wheelie: active=%s time=%.1f angle=%.2f mult=%s wanted=%s heat=%s", tostring(physics and physics.WheelieActive), physics and physics.WheelieTime or 0, physics and physics.Wheelie or 0, tostring(player:GetAttribute("Mult")), tostring(player:GetAttribute("Wanted")), tostring(player:GetAttribute("Heat"))))
check(physics ~= nil and (physics.WheelieTime > 2 or physics.Crash > 0), "a wheelie happened")
check((player:GetAttribute("Wanted") or 0) >= 1, "wheelie next to a cop made the player wanted")
check(table.find(policeEvents, "Wanted") ~= nil, "client told about the wanted level")
local pursuers = 0
for _, car in vehicles:GetChildren() do
	if car:GetAttribute("Pursuit") == true then
		pursuers += 1
	end
end
check(pursuers >= 1, "a cop car is in pursuit (" .. pursuers .. ")")
world.Keys.LeftShift = false
world:Run(2)

--------------------------------------------------------------------------------
print("== escape: get far away and out of sight")
for _, d in CarDriver.All do
	if d.Model:GetAttribute("Pursuit") == true then
		d.Position = Vector3.new(1500, 0.2, 1500) -- far away (and teleported out of sight)
	end
end
BikeController.Physics.Position = Vector3.new(-1500, 0.2, -1500)
world:Run(25)
check(table.find(policeEvents, "Escaped") ~= nil, "escaping the cops pays out")
check((player:GetAttribute("Wanted") or 0) == 0, "wanted level cleared after the escape")

--------------------------------------------------------------------------------
print("== hop and land")
world.Keys.W = true
world.Keys.Q = true
world:Run(0.5)
world.Keys.Q = false
world:Run(2)
print(string.format("[test] payouts so far: %d", payouts))

--------------------------------------------------------------------------------
print("== shopping")
local data = ServerData.Get(player)
ServerData.AddCash(player, 200000)
data.Level = 30
ServerData.Changed(player)
world:Run(1)
local BuyBike = ClientRemotes.Function("BuyBike")
local ok, message
local function invoke(remote, ...)
	local results
	local args = table.pack(...)
	local thread = coroutine.create(function()
		results = table.pack(remote:InvokeServer(table.unpack(args, 1, args.n)))
	end)
	coroutine.resume(thread)
	world:Run(0.5)
	return table.unpack(results or {}, 1, if results then results.n else 0)
end
ok, message = invoke(BuyBike, "storm_x")
check(ok == true, "bought the Storm X (" .. tostring(message) .. ")")
check(data.Owned.storm_x == true, "the Storm X is owned")
ok, message = invoke(ClientRemotes.Function("BuyUpgrade"), "storm_x", "Battery", 1)
check(ok == true, "bought a battery upgrade (" .. tostring(message) .. ")")
ok, message = invoke(ClientRemotes.Function("BuyUpgrade"), "storm_x", "Limiter", 1)
check(ok ~= true, "off-road bikes have no limiter to unlock (" .. tostring(message) .. ")")
ok, message = invoke(ClientRemotes.Function("SetPaint"), "storm_x", "Frame", "red")
check(ok == true, "painted the frame (" .. tostring(message) .. ")")
local crateOk, crateName, paintId = invoke(ClientRemotes.Function("OpenCrate"), "pro")
check(crateOk == true and type(paintId) == "string", "opened a crate: " .. tostring(crateName))
ok, message = invoke(ClientRemotes.Function("BuyBoost"), "cash2x_10")
check(ok == true and data.BoostUntil > 0, "bought a 2x boost (" .. tostring(message) .. ")")

--------------------------------------------------------------------------------
print("== the new bike: spawn, ride, charge")
world.Keys.W = false
ClientRemotes.Event("SpawnBike"):FireServer("storm_x")
world:Run(3)
bike = bikes:FindFirstChild("Bike_1")
check(bike ~= nil and bike:GetAttribute("BikeId") == "storm_x", "spawned the Storm X")
check(BikeController.Active == false, "the old ride ended")
if bike then
	Sim.Fire(bike.PrimaryPart:FindFirstChild("EnterPrompt"), "Triggered", player)
	world:Run(0.5)
	check(BikeController.Active and BikeController.Bike and BikeController.Bike.Id == "storm_x", "riding the Storm X")
	check(bike:GetAttribute("Up_Battery") == 1, "its battery upgrade is on the bike")
	BikeController.SetMode("TURBO")
	world.Keys.W = true
	world:Run(6)
	print(string.format("[test] storm x: %.1f km/h", BikeController.Kmh()))
	check(ServerData.Get(player).Mode == "TURBO", "the assist mode is saved on the server")
	check(BikeController.Kmh() > 60, "the e-moto goes fast")
	world.Keys.W = false
	local batteryBefore = BikeController.BatteryFraction()
	-- a charger right here
	local charger = WS.City.Chargers:GetChildren()[1]
	local kiosk = charger:FindFirstChild("Kiosk")
	kiosk.CFrame = CFrame.new(bike.PrimaryPart.Position + Vector3.new(5, 0, 0))
	Sim.Fire(kiosk:FindFirstChild("ChargerPrompt"), "Triggered", player)
	world:Run(Config.Battery.ChargeSeconds + 1)
	print(string.format("[test] battery %.2f -> %.2f", batteryBefore, BikeController.BatteryFraction()))
	check(BikeController.BatteryFraction() > batteryBefore and BikeController.BatteryFraction() > 0.99, "charging station filled the battery")
end

--------------------------------------------------------------------------------
print("== every menu opens")
for _, name in { "MyRides", "Dealership", "Tuning", "Crates", "Shop", "Menus" } do
	UI.Open(name)
	world:Run(0.3)
end
UI.Open("Menus")
world:Run(0.2)

--------------------------------------------------------------------------------
print("== busted")
local w = PoliceService.Stars(player)
check(w == 0, "not wanted before the bust test")
-- make the player wanted, stop next to a cop
local Heat = server.Require(Shared:WaitForChild("Heat"))
local _ = Heat
world.Keys.W = false
world.Keys.S = true
world:Run(3)
world.Keys.S = false
-- force a star through the heat system: wheelie next to a cop again
for _, d in CarDriver.All do
	if d.Model:GetAttribute("Kind") == "Cop" then
		d.Position = bike.PrimaryPart.Position + Vector3.new(10, 0, 0)
		d.Mode = "Idle"
		d.Speed = 0
		break
	end
end
world.Keys.W = true
world.Keys.LeftShift = true
world:Run(5)
world.Keys.W = false
world.Keys.LeftShift = false
world.Keys.S = true
-- keep a cop on the rider
for _ = 1, 40 do
	for _, d in CarDriver.All do
		if d.Model:GetAttribute("Pursuit") == true then
			d.Position = bike.PrimaryPart.Position + Vector3.new(6, 0, 0)
			d.Speed = 0
		end
	end
	world:Run(0.2)
	if table.find(policeEvents, "Busted") then
		break
	end
end
world.Keys.S = false
check(table.find(policeEvents, "Busted") ~= nil, "stopping next to the cops gets you busted")
check(BikeService.Get(player) == nil, "busted: the bike went back to the garage")

--------------------------------------------------------------------------------
print("== get off")
ClientRemotes.Event("SpawnBike"):FireServer("metro_c1")
world:Run(3)
bike = bikes:FindFirstChild("Bike_1")
if bike then
	Sim.Fire(bike.PrimaryPart:FindFirstChild("EnterPrompt"), "Triggered", player)
	world:Run(0.5)
	local weld = bike:FindFirstChild("Seat"):FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	world:Run(1)
	check(BikeController.Active == false, "getting off ends the ride")
	check(BikeService.Get(player) ~= nil and BikeService.Get(player).Riding == false, "the bike stays parked")
end

world:Run(2)

print("")
print(string.format("== %d warning(s), %d error(s)", #world.Warnings, #world.Errors))
for _, w2 in world.Warnings do
	print("  warn: " .. w2)
end
for _, e in world.Errors do
	print("  ERROR: " .. e)
end
if #world.Errors > 0 then
	process.exit(1)
end
print("smoke test passed")
