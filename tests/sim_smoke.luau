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
local payoutLabels: { string } = {}
ClientRemotes.Event("Payout").OnClientEvent:Connect(function(amount, label)
	payouts += 1
	table.insert(payoutLabels, tostring(label))
	if label ~= "" then
		print(string.format("[test] payout +$%d %s", amount, label))
	end
end)

--------------------------------------------------------------------------------
print("== spawn the starter bike and get on")
ClientRemotes.Event("SpawnBike"):FireServer("flit_mini")
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
check(kmh > 30 and kmh <= 50 * Config.SpeedBoost + 1, "the starter pit bike gets going, under its top speed")
check(moved > 34 * Config.STUDS_PER_METER, string.format("the bike moved (%.0f m)", moved / Config.STUDS_PER_METER))
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
-- balance it like a rider: throttle when the front is low, off and a dab of rear brake when high
for _ = 1, 60 do
	local p = BikeController.Physics
	local w = if p then p.Wheelie else 0
	world.Keys.W = w < 0.55
	world.Keys.S = w > 0.72
	world:Run(0.1)
end
world.Keys.W = true
world.Keys.S = false
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
if table.find(policeEvents, "Escaped") == nil then
	for _, d in CarDriver.All do
		print(string.format("[test]   car %s pursuit=%s at %.0f studs", d.Model.Name, tostring(d.Model:GetAttribute("Pursuit")), (d.Position - BikeController.Physics.Position).Magnitude))
	end
	print(string.format("[test]   wanted %s", tostring(player:GetAttribute("Wanted"))))
end
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
print("== drift, skid marks and first person")
local Input = client.Require(Client:WaitForChild("Input"))
local BikeCamera = client.Require(Client:WaitForChild("BikeCamera"))
world.Keys.W = true
world:Run(4)
world.Keys.W = false
world.Keys.R = true
world.Keys.D = true
local maxSlip = 0
for _ = 1, 12 do
	world:Run(0.1)
	local s = BikeController.Physics
	if s then
		maxSlip = math.max(maxSlip, math.abs(s.Slip))
	end
end
world.Keys.R = false
world.Keys.D = false
world:Run(2)
print(string.format("[test] drift max slip %.0f deg", math.deg(maxSlip)))
check(maxSlip > 0.25, "R + steer throws the tail out")
local driftPaid = false
for _, label in payoutLabels do
	if string.find(label, "Drift", 1, true) then
		driftPaid = true
	end
end
check(driftPaid, "the drift paid out")
local skids = 0
for _, d in WS:GetChildren() do
	if d.Name == "SkidMark" then
		skids += 1
	end
end
check(skids > 0, string.format("skid marks on the road (%d)", skids))
Input.Action:Fire("Camera")
world:Run(0.5)
check(BikeCamera.FirstPerson == true, "F switches to first person")
local head = rig:FindFirstChild("Head")
local camPos = WS.CurrentCamera.CFrame.Position
check(head ~= nil and (camPos - head.Position).Magnitude < 3, string.format("the first-person eye is at the rider's head (%.1f studs)", if head then (camPos - head.Position).Magnitude else -1))
Input.Action:Fire("Camera")
world:Run(0.5)
check(BikeCamera.FirstPerson == false, "F again goes back to the chase camera")

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
-- the e-moto run above may have earned a speeding star; start the bust from a clean slate
PoliceService.SetWanted(player, 0)
world:Run(1)
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
-- (a wheelie has to be balanced: held flat out it loops over in a couple of seconds)
world.Keys.LeftShift = true
for _ = 1, 50 do
	local p = BikeController.Physics
	local angle = if p then p.Wheelie else 0
	world.Keys.W = angle < 0.55
	world.Keys.S = angle > 0.72
	world:Run(0.1)
end
world.Keys.W = false
world.Keys.LeftShift = false
world.Keys.S = true
check((player:GetAttribute("Wanted") or 0) >= 1, "the bust test's wheelie made the player wanted")
-- keep a cop on the rider
local maxOfficers = 0
for _ = 1, 60 do
	for _, d in CarDriver.All do
		if d.Model:GetAttribute("Pursuit") == true then
			d.Position = bike.PrimaryPart.Position + Vector3.new(14, 0, 0)
			d.Speed = 0
		end
	end
	world:Run(0.2)
	local officersFolder = WS:FindFirstChild("Officers")
	maxOfficers = math.max(maxOfficers, if officersFolder then #officersFolder:GetChildren() else 0)
	if table.find(policeEvents, "Busted") then
		break
	end
end
world.Keys.S = false
check(maxOfficers > 0, string.format("officers got out of the car (%d)", maxOfficers))
check(table.find(policeEvents, "Busted") ~= nil, "stopping next to the cops: the officers run you down and cuff you")
check(BikeService.Get(player) == nil, "busted: the bike went back to the garage")

--------------------------------------------------------------------------------
print("== get off")
ClientRemotes.Event("SpawnBike"):FireServer("flit_mini")
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

--------------------------------------------------------------------------------
print("== ordering at a shop counter")
do
	local EconomyService = server.Require(SSS.Server:WaitForChild("EconomyService"))
	local counters: { any } = {}
	for _, d in WS:WaitForChild("City"):GetDescendants() do
		if d.Name == "OrderCounter" then
			table.insert(counters, d)
		end
	end
	check(#counters > 50, "the city has walk-in shop counters (" .. #counters .. ")")
	local food
	for _, c in counters do
		if c:GetAttribute("Menu") == "Food" then
			food = c
			break
		end
	end
	check(food ~= nil and food:FindFirstChild("OrderPrompt") ~= nil, "a fast food counter has its Order prompt")
	if food then
		ok, message = invoke(ClientRemotes.Function("Order"), food, "burger")
		check(ok ~= true, "can't order from across the map (" .. tostring(message) .. ")")
		rig:PivotTo(food.CFrame * CFrame.new(0, 3, -7))
		world:Run(1.5)
		local fits = WS:FindFirstChild("ShopFit")
		local fitted = fits and fits:FindFirstChildOfClass("Model")
		local count = 0
		if fitted then
			for _, d in fitted:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
				end
			end
		end
		check(count > 150, "walking up fits the shop out in detail (" .. count .. " parts)")
		check(fitted ~= nil and fitted:FindFirstChild("Staff") ~= nil, "someone is serving")
		local boostBefore = EconomyService.BoostOf(player)
		ok, message = invoke(ClientRemotes.Function("Order"), food, "burger")
		check(ok == true, "ordered a burger (" .. tostring(message) .. ")")
		check(player:GetAttribute("BuffCash") == 1.2, "the burger's cash boost is on the HUD attributes")
		check(math.abs(EconomyService.BoostOf(player) - boostBefore * 1.2) < 1e-6, "and it multiplies the pay boost")
		check(rig:FindFirstChild("Item_burger") ~= nil, "the burger is in the player's hand")
		check(type(food:GetAttribute("LastOrder")) == "string", "the counter tells its staff to hand it over")
		ok, message = invoke(ClientRemotes.Function("Order"), food, "cap")
		check(ok ~= true, "items from another menu are refused (" .. tostring(message) .. ")")
		world:Run(8)
		check(rig:FindFirstChild("Item_burger") == nil, "the burger gets eaten")
		local gas
		for _, c in counters do
			if c:GetAttribute("Menu") == "Gas" then
				gas = c
				break
			end
		end
		if gas then
			rig:PivotTo(gas.CFrame * CFrame.new(0, 3, -7))
			world:Run(1)
			ok, message = invoke(ClientRemotes.Function("Order"), gas, "cap")
			check(ok ~= true, "a disguise needs someone looking for you (" .. tostring(message) .. ")")
			PoliceService.SetWanted(player, 2)
			world:Run(0.5)
			ok, message = invoke(ClientRemotes.Function("Order"), gas, "cap")
			check(ok == true and PoliceService.Stars(player) == 1, "a trucker cap drops a wanted star (" .. tostring(message) .. ")")
			PoliceService.SetWanted(player, 0)
		end
		UI.Open("Order")
		world:Run(0.3)
		UI.Open("Order")
	end
end

--------------------------------------------------------------------------------
print("== admin")
check(player:GetAttribute("Admin") == true, "play-testing in Studio makes you an admin")
local AdminRemote = ClientRemotes.Function("Admin")
local before = data.Cash
ok, message = invoke(AdminRemote, "cash", 5000)
check(ok == true and data.Cash == before + 5000, "admin cash +5000 (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "level", 42)
check(ok == true and data.Level == 42, "admin level 42 (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "allbikes")
check(ok == true and data.Owned.halo_gt == true, "admin owns every bike (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "wanted", 3)
world:Run(0.5)
check(ok == true and player:GetAttribute("Wanted") == 3, "admin sets 3 stars (" .. tostring(player:GetAttribute("Wanted")) .. ")")
ok, message = invoke(AdminRemote, "wanted", 0)
world:Run(0.5)
check(ok == true and player:GetAttribute("Wanted") == 0, "admin clears the chase")
ok, message = invoke(AdminRemote, "teleport", "JumpPark")
check(ok == true, "admin teleport (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "bike", "halo_gt")
world:Run(1)
check(ok == true and BikeService.Get(player) ~= nil and BikeService.Get(player).Bike.Id == "halo_gt", "admin spawns the Halo GT (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "maxupgrades")
check(ok == true, "admin max upgrades (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "weather", "Overcast")
world:Run(1)
check(ok == true and RS:GetAttribute("WeatherOverride") == "Overcast", "admin holds the weather overcast (" .. tostring(message) .. ")")
ok, message = invoke(AdminRemote, "weather", "Auto")
world:Run(1)
check(ok == true and RS:GetAttribute("WeatherOverride") == "", "admin lets the weather change by itself (" .. tostring(message) .. ")")
ok = invoke(AdminRemote, "weather", "Snow")
check(ok ~= true, "admin weather refuses a kind Miami doesn't get")
-- the chat code (Studio already made us admin, so take it away first)
local AdminService = server.Require(SSS.Server:WaitForChild("AdminService"))
AdminService.Revoke(player)
Sim.Fire(player, "Chatted", "ender=wrong")
world:Run(0.2)
check(player:GetAttribute("Admin") == false, "a wrong chat code does nothing")
ok = invoke(AdminRemote, "cash", 5)
check(ok ~= true, "non-admins can't run commands")
Sim.Fire(player, "Chatted", "  Ender=Cool ")
world:Run(0.2)
check(player:GetAttribute("Admin") == true, "typing ender=cool in chat gives admin")
ok, message = invoke(AdminRemote, "nonsense")
check(ok ~= true, "unknown admin commands are refused")

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
