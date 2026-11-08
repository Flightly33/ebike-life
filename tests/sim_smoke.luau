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

local CFrame, Vector3, Vector2, Color3 = roblox.CFrame, roblox.Vector3, roblox.Vector2, roblox.Color3

local root = process.cwd
if string.sub(root, -1) ~= "/" then
	root ..= "/"
end

World.Digest = process.env.SIM_DIGEST ~= nil
local world = World.new(root)
local RS = world.Services.ReplicatedStorage
local SSS = world.Services.ServerScriptService
local WS = world.Services.Workspace

-- SIM_GUI=<file.json>: snapshots of the player's screen for tools/preview/gui.mjs
local GuiExport = require("../tools/lune/gui_export")
local guiShots: { any } = {}
local guiPlayer: any = nil
local function shot(name: string, w: number?, h: number?)
	if not process.env.SIM_GUI or not guiPlayer then
		return
	end
	local screens = {}
	for _, sg in guiPlayer:FindFirstChild("PlayerGui"):GetChildren() do
		if sg.ClassName == "ScreenGui" then
			table.insert(screens, sg)
		end
	end
	table.sort(screens, function(a, b)
		return (a.DisplayOrder or 0) < (b.DisplayOrder or 0)
	end)
	local ok, tree = pcall(GuiExport.Screens, screens)
	if ok then
		table.insert(guiShots, { name = name, w = w or 1280, h = h or 720, bg = "#6b8fb0", tree = tree })
	else
		print("[gui] " .. tostring(tree))
	end
end

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
local TrafficService = server.Require(SSS.Server:WaitForChild("TrafficService"))
check(#TrafficService.Buses() == #TrafficService.LINES, string.format("a bus on each of the %d lines (%d)", #TrafficService.LINES, #TrafficService.Buses()))

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
guiPlayer = player
print("== booting client")
client.Run(world.Services.StarterPlayer.StarterPlayerScripts:WaitForChild("Client"))
world:Run(4)

-- the radio: each part of the city has its station (Client/Music)
do
	local Music = client.Require(world.Services.StarterPlayer.StarterPlayerScripts:WaitForChild("Client"):WaitForChild("Music"))
	local AudioCatalog = client.Require(Shared:WaitForChild("AudioCatalog"))
	local expect = {
		Downtown = "Downtown",
		Wynwood = "Wynwood",
		LittleHavana = "Havana",
		Beach = "Beach",
		CoralGables = "Suburbs",
		RaceHub = "Race",
		JumpPark = "Stunt",
		Everglades = "Open",
		Airport = "Open",
		Port = "Open",
	}
	local wrong = {}
	for place, mood in expect do
		local got = Music.PlaceMood(Layout.Places[place])
		if got ~= mood then
			table.insert(wrong, string.format("%s: %s (wanted %s)", place, got, mood))
		end
	end
	local named = true
	for _, mood in AudioCatalog.Moods do
		named = named and type(mood.Station) == "string" and #mood.Keywords > 0
	end
	check(#wrong == 0 and named, "the radio's station follows the district" .. (if #wrong > 0 then " (" .. table.concat(wrong, ", ") .. ")" else ""))
end

local ServerData = server.Require(SSS.Server:WaitForChild("DataService"))
local BikeService = server.Require(SSS.Server:WaitForChild("BikeService"))
local PoliceService = server.Require(SSS.Server:WaitForChild("PoliceService"))
local ClientRemotes = client.Require(Shared:WaitForChild("Remotes"))
local Client = world.Services.StarterPlayer.StarterPlayerScripts.Client
local BikeController = client.Require(Client:WaitForChild("BikeController"))
local UI = client.Require(Client:WaitForChild("UI"))
-- answer the graphics prompt like a player would
client.Require(Client:WaitForChild("UI"):WaitForChild("GraphicsPrompt")).Choose("Ultra")
do
	local menusGui = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeMenus")
	local prompt = menusGui and menusGui:FindFirstChild("GraphicsPrompt")
	if prompt then
		prompt:Destroy()
	end
end

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

-- SIM_GUI: the screen at a PC's, a tablet's and a phone's size (touch on the last two), each
-- device's shots taken by `take(tag, w, h)`; then back to the 1280 x 720 keyboard screen
local function onDevices(take: (string, number, number) -> ())
	if not process.env.SIM_GUI then
		return
	end
	local uis = Sim.States[world.Services.UserInputService].Props
	local State = client.Require(Client:WaitForChild("State"))
	local touch = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD"):FindFirstChild("TouchControls")
	-- a new screen size: the camera's ViewportSize and every screen gui's AbsoluteSize change
	local function resize(size: any)
		Sim.Viewport = size
		local targets = { WS.CurrentCamera }
		for _, sg in player:FindFirstChild("PlayerGui"):GetChildren() do
			if sg.ClassName == "ScreenGui" then
				table.insert(targets, sg)
			end
		end
		for _, inst in targets do
			local signals = Sim.States[inst].PropSignals
			local changed = signals.ViewportSize or signals.AbsoluteSize
			if changed then
				changed:Fire()
			end
		end
	end
	for _, d in { { "pc", 1920, 1080, false }, { "tablet", 1180, 820, true }, { "phone", 844, 390, true } } do
		resize(Vector2.new(d[2], d[3]))
		uis.TouchEnabled = d[4]
		uis.KeyboardEnabled = not d[4]
		if touch then
			touch.Visible = d[4] and BikeController.Active
		end
		State.SetSettings(State.Settings(), false)
		world:Run(0.2)
		take(d[1], d[2], d[3])
	end
	resize(Vector2.new(1280, 720))
	uis.TouchEnabled = false
	uis.KeyboardEnabled = true
	if touch then
		touch.Visible = false
	end
	State.SetSettings(State.Settings(), false)
	world:Run(0.2)
end
-- a new rider gets the tutorial a few seconds after joining: on the bike and up to speed already
check(player:GetAttribute("TutorialStarted") == true and player:GetAttribute("ObjTitle") == "Welcome to Flighty" and (player:GetAttribute("ObjStep") or 0) >= 3, "a new rider gets the tutorial, and riding off moved it on (step " .. tostring(player:GetAttribute("ObjStep")) .. ")")
do
	-- the tracker writes the player's own key into "hold {Wheelie}", and Nina's call is in Messages
	local card = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD"):FindFirstChild("Objective")
	local text = ""
	for _, d in card and card:GetDescendants() or {} do
		if d.ClassName == "TextLabel" and string.find(d.Text, "wheelie", 1, true) then
			text = d.Text
		end
	end
	check(string.find(text, "Shift", 1, true) ~= nil and string.find(text, "{", 1, true) == nil, "the tracker names the bound key (" .. text .. ")")
	local Inbox = client.Require(Client:WaitForChild("UI"):WaitForChild("Inbox"))
	local first = Inbox.All()[#Inbox.All()]
	check(first ~= nil and first.From == "Nina" and first.Kind == "Call", "Nina's call is kept in the phone's Messages")
end
shot("hud_riding")
onDevices(function(device, w, h)
	shot("device_" .. device .. "_riding", w, h)
end)

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
-- (the spot furthest from every police car, pursuing or patrolling, so no patrol that happens to
-- be about can see the rider arrive: out of sight whatever the cars' random routes)
local escapeSpot, escapeGap = Vector3.new(-1500, 0.2, -1500), -1
for _, spot in { Vector3.new(-1500, 0.2, -1500), Vector3.new(-1500, 0.2, 1500), Vector3.new(-2600, 0.2, 0), Vector3.new(0, 0.2, -2600) } do
	local gap = math.huge
	for _, d in CarDriver.All do
		local kind = d.Model.Name
		if kind == "Police" or kind == "PoliceMoto" then
			gap = math.min(gap, (d.Position - spot).Magnitude)
		end
	end
	if gap > escapeGap then
		escapeSpot, escapeGap = spot, gap
	end
end
BikeController.Physics.Position = escapeSpot
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
check(ok ~= true, "parts are only fitted at Flighty Garage (" .. tostring(message) .. ")")
-- walk into the garage
local returnTo = rig:GetPivot()
rig:PivotTo(CFrame.new(Layout.Places.Garage + Vector3.new(0, 4, 0)))
world:Run(1)
ok, message = invoke(ClientRemotes.Function("BuyUpgrade"), "storm_x", "Battery", 1)
check(ok == true, "bought a battery upgrade at the garage (" .. tostring(message) .. ")")
ok, message = invoke(ClientRemotes.Function("BuyUpgrade"), "storm_x", "Limiter", 1)
check(ok ~= true, "off-road bikes have no limiter to unlock (" .. tostring(message) .. ")")
ok, message = invoke(ClientRemotes.Function("SetPaint"), "storm_x", "Frame", "red")
check(ok == true, "painted the frame (" .. tostring(message) .. ")")
local crateOk, crateName, paintId = invoke(ClientRemotes.Function("OpenCrate"), "pro")
check(crateOk == true and type(paintId) == "string", "opened a crate: " .. tostring(crateName))
ok, message = invoke(ClientRemotes.Function("BuyBoost"), "cash2x_10")
check(ok == true and data.BoostUntil > 0, "bought a 2x boost (" .. tostring(message) .. ")")

-- a custom paint job and the mechanic's setup
do
	local Livery = server.Require(Shared:WaitForChild("Livery"))
	local before = data.Cash
	local job = { Frame = Livery.Encode(Color3.fromRGB(20, 200, 120), "pearl", nil), Seat = Livery.Encode(Color3.fromRGB(120, 30, 30), "suede", nil), Rims = "red" }
	ok, message = invoke(ClientRemotes.Function("SetLivery"), "storm_x", job)
	check(ok == true and data.Cash < before, "a custom paint job costs cash (" .. tostring(message) .. ")")
	check(data.Paint.storm_x.Frame == job.Frame and data.Paint.storm_x.Seat == job.Seat, "the paint job is saved")
	ok, message = invoke(ClientRemotes.Function("SetLivery"), "storm_x", { Frame = "#12345/nope/none" })
	check(ok ~= true, "a bad coat is refused (" .. tostring(message) .. ")")
	ok, message = invoke(ClientRemotes.Function("SetLivery"), "storm_x", { Frame = Livery.Encode(Color3.new(1, 1, 1), "suede", nil) })
	check(ok ~= true, "a seat-only finish stays off the frame (" .. tostring(message) .. ")")
	local spent = before - data.Cash
	before = data.Cash
	ok = invoke(ClientRemotes.Function("SetLivery"), "storm_x", job)
	check(ok == true and data.Cash == before, "re-applying the same job costs nothing (first was " .. spent .. ")")
	ok, message = invoke(ClientRemotes.Function("SetSetup"), "storm_x", { Gearing = 2, Spring = -1, Pressure = 9 })
	check(ok == true and data.Upgrades.storm_x.S_Gearing == 2 and data.Upgrades.storm_x.S_Pressure == 2, "setup saved, out-of-range values clamped (" .. tostring(message) .. ")")
	local BikeStats = server.Require(Shared:WaitForChild("BikeStats"))
	local Bikes = server.Require(Shared:WaitForChild("Bikes"))
	local stock = BikeStats.Compute(Bikes.Get("storm_x"), { Limiter = 1 })
	local geared = BikeStats.Compute(Bikes.Get("storm_x"), { Limiter = 1, S_Gearing = 2 })
	check(geared.WheelForceN < stock.WheelForceN and geared.CutoffKmh >= stock.CutoffKmh, "taller gearing trades wheel force for top speed")
	-- the garage screen opens with the bike on the lift
	UI.Open("Garage")
	world:Run(2)
	local garageScene = WS:FindFirstChild("GarageScene")
	check(garageScene ~= nil and garageScene:FindFirstChildOfClass("Model") ~= nil, "the garage puts your bike on the lift")
	shot("garage")
	UI.Open("Garage")
	world:Run(0.5)
	check(WS:FindFirstChild("GarageScene") == nil, "leaving the garage clears the scene")
end
rig:PivotTo(returnTo)
world:Run(1)

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
	-- a time trial on it: the start line, then every checkpoint on the bike
	ok, message = invoke(ClientRemotes.Function("Activity"), "StartTrial", "downtown_dash")
	check(ok == true and player:GetAttribute("ObjKind") == "Trial", "a time trial starts (" .. tostring(message) .. ")")
	local hops = 0
	while player:GetAttribute("ObjKind") == "Trial" and hops < 40 do
		local target = player:GetAttribute("ObjTarget")
		if typeof(target) ~= "Vector3" then
			break
		end
		BikeService.Teleport(player, CFrame.new(target + Vector3.new(0, 2, 0)))
		world:Run(0.5)
		hops += 1
	end
	local best = ServerData.Get(player).BestTimes.downtown_dash
	check(best ~= nil, string.format("the trial finished with a best time (%s s, %d hops)", tostring(best), hops))
end

--------------------------------------------------------------------------------
print("== every menu opens")
for _, name in { "MyRides", "Dealership", "Tuning", "Crates", "Shop", "Menus" } do
	UI.Open(name)
	world:Run(0.3)
	shot("menu_" .. name)
end
UI.Open("Menus")
world:Run(0.2)
for _, name in { "Map", "Stats", "Phone" } do
	UI.Open(name)
	world:Run(0.6)
	shot("menu_" .. name)
end
UI.Open("Phone")
world:Run(0.2)
check(player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeMenus"):FindFirstChild("Map") ~= nil, "the full map screen is built")

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
		shot("menu_Order")
		UI.Open("Order")
	end
end

--------------------------------------------------------------------------------
print("== missions, deliveries, races, dailies, events, leaderboards")
do
	local Activity = ClientRemotes.Function("Activity")
	local EconomyService = server.Require(SSS.Server:WaitForChild("EconomyService"))
	local DailyService = server.Require(SSS.Server:WaitForChild("DailyService"))
	local LeaderboardService = server.Require(SSS.Server:WaitForChild("LeaderboardService"))
	local Dailies = server.Require(Shared:WaitForChild("Dailies"))
	local saved = ServerData.Get(player)
	local function walkTo(target: any)
		rig:PivotTo(CFrame.new(target + Vector3.new(0, 3, 0)))
		world:Run(0.4)
	end
	local overview
	ok, overview = invoke(Activity, "Overview")
	check(ok == true and type(overview) == "table" and overview.Missions ~= nil and overview.Jobs ~= nil and overview.Races ~= nil and overview.Daily ~= nil and overview.Events ~= nil and overview.Boards ~= nil, "the phone's Play hub gets every section")
	-- the first story mission: to the Plaza, a wheelie, back to Flighty Mechanics
	local cash0 = player:GetAttribute("Cash")
	ok, message = invoke(Activity, "StartMission", "m02_wynwood")
	check(ok ~= true, "missions open in order (" .. tostring(message) .. ")")
	ok, message = invoke(Activity, "StartMission", "m01_first_ride")
	check(ok == true and player:GetAttribute("ObjKind") == "Mission", "the first mission starts (" .. tostring(message) .. ")")
	check(typeof(player:GetAttribute("ObjTarget")) == "Vector3", "the tracker has somewhere to point")
	walkTo(Layout.Places.Plaza)
	check(player:GetAttribute("ObjStep") == 2, "reaching the Plaza moves the mission on")
	EconomyService.Trick:Fire(player, "Wheelie", 1)
	world:Run(0.2)
	check(player:GetAttribute("ObjStep") == 2, "a 1 s wheelie isn't enough")
	EconomyService.Trick:Fire(player, "Wheelie", 2.5)
	world:Run(0.2)
	check(player:GetAttribute("ObjStep") == 3, "a 2.5 s wheelie is")
	walkTo(Layout.Places.Dealership)
	check(saved.Missions.m01_first_ride == true and player:GetAttribute("ObjKind") == nil, "back at Flighty Mechanics: the mission's done and saved")
	check(player:GetAttribute("Cash") - cash0 >= 400, "and paid")
	shot("objective_done")
	-- Nina texts when it's done, and the next regular when there's more work: the phone's Messages
	world:Run(5)
	local Inbox = client.Require(Client:WaitForChild("UI"):WaitForChild("Inbox"))
	local fromNina, fromJet = false, false
	for _, m in Inbox.All() do
		fromNina = fromNina or (m.From == "Nina" and m.Kind == "Text")
		fromJet = fromJet or (m.From == "Jet" and string.find(m.Text, "Wynwood", 1, true) ~= nil)
	end
	check(fromNina and fromJet, "Nina's thanks and Jet's next job arrive as texts")
	local hud = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD")
	local phoneTile = hud:FindFirstChild("Menu"):FindFirstChild("Phone")
	local badge = phoneTile and phoneTile:FindFirstChild("Badge")
	check(Inbox.Unread() >= 2 and badge ~= nil and badge.Visible == true, "unread texts badge the phone (" .. Inbox.Unread() .. ")")
	shot("hud_message")
	UI.Open("Messages")
	world:Run(0.3)
	check(Inbox.Unread() == 0, "opening Messages reads them")
	shot("menu_Messages")
	UI.Open("Messages")
	-- a delivery: to the counter, then the house, inside the time limit
	ok, overview = invoke(Activity, "Overview")
	local jobs = if ok and type(overview) == "table" then overview.Jobs or {} else {}
	check(#jobs > 0, string.format("delivery jobs on offer (%d)", #jobs))
	if #jobs > 0 then
		local before, cash1 = saved.Stats.Deliveries, player:GetAttribute("Cash")
		ok, message = invoke(Activity, "StartJob", 1)
		check(ok == true and player:GetAttribute("ObjKind") == "Job", "took a delivery (" .. tostring(message) .. ")")
		walkTo(player:GetAttribute("ObjTarget"))
		check(player:GetAttribute("ObjStep") == 2 and (player:GetAttribute("ObjEnds") or 0) > 0, "picked up the order: the clock's running")
		shot("objective_job")
		walkTo(player:GetAttribute("ObjTarget"))
		check(saved.Stats.Deliveries == before + 1, "delivered")
		check(player:GetAttribute("Cash") - cash1 > jobs[1].Pay, "paid with a tip for the time to spare")
	end
	-- a race lobby: on your own it waits for someone to join
	ok, message = invoke(Activity, "JoinRace", "downtown_dash")
	check(ok == true and player:GetAttribute("RaceLobby") == "downtown_dash", "joined a race lobby (" .. tostring(message) .. ")")
	ok = invoke(Activity, "LeaveRace")
	check(ok == true and player:GetAttribute("RaceLobby") == nil, "and left it")
	-- the daily streak and a challenge
	ok, message = invoke(Activity, "ClaimStreak")
	check(ok == true and saved.Daily.Streak == 1, "claimed the daily reward (" .. tostring(message) .. ")")
	ok = invoke(Activity, "ClaimStreak")
	check(ok ~= true, "once a day")
	local base = os.time()
	DailyService.Clock = function()
		return base + 86400
	end
	ok, message = invoke(Activity, "ClaimStreak")
	check(ok == true and saved.Daily.Streak == 2, "the next day grows the streak (" .. tostring(message) .. ")")
	local challenge = Dailies.ForDay(Dailies.Day(base + 86400))[1]
	ok = invoke(Activity, "ClaimChallenge", challenge.Id)
	check(ok ~= true, "a challenge can't be claimed before it's done")
	DailyService.Add(player, challenge.Stat, challenge.Goal)
	ok, message = invoke(Activity, "ClaimChallenge", challenge.Id)
	check(ok == true and saved.Daily.Claimed[challenge.Id] == true, "a finished challenge pays (" .. tostring(message) .. ")")
	DailyService.Clock = os.time
	-- the event timetable and the leaderboards (this server's riders without DataStores)
	check(type(RS:GetAttribute("Event")) == "string", "the event timetable runs (now: '" .. tostring(RS:GetAttribute("Event")) .. "')")
	LeaderboardService.Refresh()
	ok, overview = invoke(Activity, "Overview")
	local earned = if ok and type(overview) == "table" and overview.Boards then overview.Boards[1] else nil
	check(earned ~= nil and earned.Top[1] ~= nil and earned.Top[1].Name == player.DisplayName, "the tester tops the earnings board")
	UI.Open("Activities")
	world:Run(0.6)
	shot("menu_Activities")
	UI.Open("Activities")
	-- the regulars stand where you'd find them, each with a Talk prompt; Nina's "!" is lit while
	-- her tutorial is still open
	local regulars = WS:FindFirstChild("Regulars")
	local talking = 0
	for _, model in regulars and regulars:GetChildren() or {} do
		local prompt = model:FindFirstChild("TalkPrompt", true)
		if prompt and prompt:GetAttribute("Giver") == model.Name then
			talking += 1
		end
	end
	check(talking == 4, string.format("Nina, Marco, Jet and Reyes are out with Talk prompts (%d)", talking))
	world:Run(1.2)
	local nina = regulars and regulars:FindFirstChild("Nina")
	local mark = nina and nina:FindFirstChild("NameTag") and nina.NameTag:FindFirstChild("Ready")
	check(mark ~= nil and mark.Visible == true, "Nina has a mission ready (the tutorial), so her ! is lit")
	onDevices(function(device, w, h)
		shot("device_" .. device .. "_hud", w, h)
		for _, name in { "Phone", "Activities", "Map" } do
			UI.Open(name)
			world:Run(0.5)
			shot("device_" .. device .. "_" .. name, w, h)
			UI.Open(name)
		end
	end)
end

--------------------------------------------------------------------------------
print("== settings and controls")
do
	local Input = client.Require(Client:WaitForChild("Input"))
	local State = client.Require(Client:WaitForChild("State"))
	local Hud = client.Require(Client:WaitForChild("UI"):WaitForChild("Hud"))
	local saved = ServerData.Get(player)
	for key in world.Keys do
		world.Keys[key] = false
	end
	-- rebind the gas to I: I drives, W doesn't, the hints say I, and the server keeps it
	local settings = table.clone(State.Settings())
	settings.Keys = { Gas = "I" }
	State.SetSettings(settings, true)
	world:Run(0.5)
	world.Keys.I = true
	local withI = Input.Read().Throttle
	world.Keys.I = false
	world.Keys.W = true
	local withW = Input.Read().Throttle
	world.Keys.W = false
	world.Keys.Up = true
	local withUp = Input.Read().Throttle
	world.Keys.Up = false
	check(withI == 1 and withW == 0 and withUp == 1, string.format("gas rebound to I: I %s, W %s, the arrow still works %s", tostring(withI), tostring(withW), tostring(withUp)))
	check(saved.Settings.Keys.Gas == "I", "the save keeps the new key")
	local hints = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD"):FindFirstChild("Hints")
	local showsI = false
	for _, d in hints and hints:GetDescendants() or {} do
		if d.ClassName == "TextLabel" and d.Text == "I" then
			showsI = true
		end
	end
	check(showsI, "the key hints show the new key")
	-- the HUD's size and layout follow the settings
	local hudScale = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD"):FindFirstChildOfClass("UIScale")
	local before = hudScale and hudScale.Scale or 0
	settings = table.clone(State.Settings())
	settings.HudScale = 1.2
	settings.HudLayout = "Compact"
	State.SetSettings(settings, true)
	world:Run(0.5)
	local menuTile = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeHUD"):FindFirstChild("Menu"):FindFirstChild("Menus")
	check(hudScale ~= nil and math.abs(hudScale.Scale - before * 1.2) < 0.01, string.format("HUD size 120%% scales the HUD (%.2f -> %.2f)", before, hudScale and hudScale.Scale or 0))
	check(Hud.Compact() and menuTile ~= nil and menuTile.Visible == false, "the compact layout leaves the menu tiles to the phone")
	shot("hud_compact")
	UI.Open("Menus")
	world:Run(0.3)
	shot("menu_Menus")
	-- the Settings and Controls tabs (their tab buttons, clicked)
	local menusPanel = player:FindFirstChild("PlayerGui"):FindFirstChild("EbikeMenus"):FindFirstChild("Menus")
	local function clickTab(label: string): boolean
		for _, d in menusPanel and menusPanel:GetDescendants() or {} do
			if d.ClassName == "TextButton" and d.Text == label then
				Sim.Fire(d, "Activated")
				world:Run(0.3)
				return true
			end
		end
		return false
	end
	check(clickTab("⚙️ Settings"), "the menu has a Settings tab")
	shot("menu_Settings")
	check(clickTab("⌨️ Controls"), "and a Controls tab")
	local listsKey = false
	for _, d in menusPanel:GetDescendants() do
		if d.ClassName == "TextButton" and d.Text == "Shift" then
			listsKey = true
		end
	end
	check(listsKey, "the Controls tab shows each control's key")
	shot("menu_Controls")
	UI.Open("Menus")
	-- back to the defaults
	settings = table.clone(State.Settings())
	settings.Keys = {}
	settings.HudScale = 1
	settings.HudLayout = "Auto"
	State.SetSettings(settings, true)
	world:Run(0.5)
	check(next(saved.Settings.Keys) == nil and saved.Settings.HudLayout == "Auto", "settings back to the defaults")
end

--------------------------------------------------------------------------------
print("== billboards")
do
	local screen
	for _, d in WS:WaitForChild("City"):GetDescendants() do
		if d.Name == "AdFace" and d:GetAttribute("AdKind") == "Screen" then
			screen = d
			break
		end
	end
	check(screen ~= nil, "the city has LED ad screens")
	if screen then
		rig:PivotTo(CFrame.new(screen.Position + screen.CFrame.LookVector * 60))
		world:Run(3)
		local gui = screen:FindFirstChild("Ad")
		check(gui ~= nil, "an ad screen near the player shows an ad")
		world:Run(9)
		check(gui ~= nil and #gui:GetChildren() >= 2, "the screen has its ticker and its ad")
	end
end

--------------------------------------------------------------------------------
print("== achievements")
do
	local Claim = ClientRemotes.Function("ClaimAchievement")
	data.Stats.Distance = math.max(data.Stats.Distance, 1200)
	local before = data.Cash
	ok, message = invoke(Claim, "km1")
	check(ok == true and data.Cash == before + 250 and data.Achievements.km1 == true, "claimed First Kilometre (" .. tostring(message) .. ")")
	ok, message = invoke(Claim, "km1")
	check(ok ~= true, "an achievement pays once (" .. tostring(message) .. ")")
	ok, message = invoke(Claim, "km100")
	check(ok ~= true, "an unfinished one can't be claimed (" .. tostring(message) .. ")")
	ok, message = invoke(Claim, "nonsense")
	check(ok ~= true, "unknown achievements are refused")
end

--------------------------------------------------------------------------------
print("== street and building detail")
do
	local detail = WS:FindFirstChild("CityDetail")
	local roads, buildings = 0, 0
	if detail then
		for _, m in detail:GetChildren() do
			if m.Name == "RoadDetail" then
				roads += 1
			elseif m.Name == "BuildingDetail" then
				buildings += 1
			end
		end
	end
	check(roads > 3, "road detail round the player (" .. roads .. " chunks)")
	check(buildings > 0, "building detail round the player (" .. buildings .. " buildings)")
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
do
	-- from two stars a police moto joins the chase: its officer rides it, it closes in, it leans
	world:Run(2)
	local moto: any = nil
	for _, car in WS:WaitForChild("Vehicles"):GetChildren() do
		if car:GetAttribute("Moto") == true then
			moto = car
		end
	end
	check(moto ~= nil and moto:GetAttribute("Pursuit") == true and moto:FindFirstChild("OfficerHelmet") ~= nil, "a police moto with its officer joins a 3-star chase")
	if moto then
		local root = moto.PrimaryPart
		local me = rig.PrimaryPart.Position
		local before = (root.Position - me).Magnitude
		world:Run(4)
		local after = (root.Position - rig.PrimaryPart.Position).Magnitude
		local upright = root.CFrame.UpVector.Y
		check(after < before or after < 120, string.format("the moto closes in (%.0f -> %.0f studs)", before, after))
		check(upright > 0.75, string.format("and stays up, leaning at most ~40 degrees (up %.2f)", upright))
	end
end
ok, message = invoke(AdminRemote, "wanted", 0)
world:Run(0.5)
check(ok == true and player:GetAttribute("Wanted") == 0, "admin clears the chase")
do
	-- rider gear: buy a helmet (it goes straight on), wear the free one, take it off
	local GearRemote = ClientRemotes.Function("Gear")
	ok, message = invoke(GearRemote, "Buy", "h_full")
	world:Run(0.3)
	local folder = rig:FindFirstChild("Gear")
	local helmetPart = folder and folder:FindFirstChild("GearHelmet")
	check(ok == true and data.Gear.Owned.h_full == true and data.Gear.Worn.Helmet == "h_full" and helmetPart ~= nil and helmetPart:GetAttribute("FirstPersonHide") == true, "bought a full-face helmet and it's on (" .. tostring(message) .. ")")
	ok = invoke(GearRemote, "Buy", "h_full")
	check(ok ~= true, "gear is bought once")
	ok, message = invoke(GearRemote, "Wear", "j_leather")
	check(ok ~= true, "gear you don't own can't be worn (" .. tostring(message) .. ")")
	ok = invoke(GearRemote, "Buy", "j_courier")
	ok = invoke(GearRemote, "Buy", "b_mx")
	world:Run(0.3)
	folder = rig:FindFirstChild("Gear")
	check(folder ~= nil and folder:FindFirstChild("GearJacket") ~= nil and folder:FindFirstChild("GearBoot") ~= nil, "the courier jacket and MX boots are on too")
	shot("hud_gear")
	ok = invoke(GearRemote, "TakeOff", "Helmet")
	world:Run(0.3)
	folder = rig:FindFirstChild("Gear")
	check(ok == true and data.Gear.Worn.Helmet == nil and folder ~= nil and folder:FindFirstChild("GearHelmet") == nil, "and the helmet comes off")
	UI.Open("Gear")
	world:Run(0.4)
	shot("menu_Gear")
	UI.Open("Gear")
end
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

do
	-- by now the buses have been round their lines, pulling up at the shelters on the way
	local served, onLine = 0, 0
	for _, bus in TrafficService.Buses() do
		if bus.LastStop > 0 then
			served += 1
		end
		local route = bus.Route
		if route and table.find(route, bus.ToNode) then
			onLine += 1
		end
	end
	check(served > 0, string.format("buses pull up at the shelters on their lines (%d of %d have)", served, #TrafficService.Buses()))
	check(onLine == #TrafficService.Buses(), string.format("and keep to their lines (%d of %d)", onLine, #TrafficService.Buses()))
end

world:Run(2)

if process.env.SIM_GUI then
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	fs.writeFile(process.env.SIM_GUI, serde.encode("json", guiShots))
	print("[gui] wrote " .. #guiShots .. " screens to " .. process.env.SIM_GUI)
end

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
