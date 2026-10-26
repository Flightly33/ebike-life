--[[
	PoliceService: patrol cars, heat, wanted stars, pursuits, busts and escapes.

	Patrol cruisers drive the city like traffic. Any cop with a clear line of sight within
	Config.Police.SightRange watches what riders do; offences (Shared/Heat: wheelies above all, no
	hands, speeding past a bike's legal limit, fast riding on pavements, red lights, jumps, flips,
	hitting a cop car) fill a heat meter, and a full meter is a wanted star. Each star brings more
	cars, faster ones, and a richer cash multiplier while the chase lasts.

	Lose every pursuer's line of sight for long enough and you escape (and get paid).

	Pursuit tactics, like real units working a chase together:
	  Lead        the nearest car: follows a safe gap behind you (police don't ram or PIT
	              motorcycles: it's deadly force); it only closes in to block you once you're
	              nearly stopped
	  Flank       the second car: rides beside you to box you in
	  Intercept   the rest: predict the crossing you'll reach a few seconds ahead, get there
	              first and block it, then close in
	  Roadblock   from RoadblockStars: a car parked across a crossing ahead with a spike strip in
	              front of it (spikes give you a flat: a crawl for a while)
	Getting caught: stop (or get knocked off, or bail) near a cruiser and the officers get out and
	run you down on foot; if one reaches you while you're still slow or on the ground, the cuffs come
	out (a fine, the bike goes back to the garage and you're walked out of the station). Ride off
	fast enough and they give up, walk back and the chase goes on.

	Player attributes for the HUD: Wanted (stars), Heat (0..1 to the next star), Evade (0..1),
	Bust (0..1), Seen (a cop can see you right now).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Heat = require(Shared.Heat)
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)
local CarModel = require(Shared.Models.CarModel)

local DataService = require(script.Parent.DataService)
local BikeService = require(script.Parent.BikeService)
local EconomyService = require(script.Parent.EconomyService)
local CarDriver = require(script.Parent.CarDriver)
local Officer = require(script.Parent.Officer)

local PoliceService = {}

local C = Config.Police

type Unit = {
	Driver: CarDriver.Driver,
	Target: Player?,
	Extra: boolean, -- brought in for a chase; leaves when it's over
	ReleasedAt: number,
	Role: string, -- "Lead" | "Flank" | "Intercept" | "Roadblock" | "Deployed"
	InterceptNode: number?,
	InterceptAt: number,
	RoadblockAt: number,
	Spikes: BasePart?,
	Officers: { Model },
}

type Watch = {
	Heat: Heat.State,
	SeenAt: number,
	Seen: boolean,
	Spotted: boolean,
	Inside: number?, -- intersection node the player is crossing
	MaxStarsThisChase: number,
	RoadblockAt: number,
}

local units: { Unit } = {}
local watches: { [Player]: Watch } = {}
local rng = Random.new(4242)
local vehicles: Folder
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true

local function watch(player: Player): Watch
	local w = watches[player]
	if not w then
		w = { Heat = Heat.new(), SeenAt = -math.huge, Seen = false, Spotted = false, Inside = nil, MaxStarsThisChase = 0, RoadblockAt = -math.huge }
		watches[player] = w
	end
	return w
end

function PoliceService.Stars(player: Player): number
	local w = watches[player]
	return if w then w.Heat.Stars else 0
end

-- Where the player is and how fast they're going (their bike if riding)
local function whereIs(player: Player): (Vector3?, Vector3)
	local ride = BikeService.Get(player)
	if ride and ride.Riding then
		return ride.Root.Position, ride.Root.AssemblyLinearVelocity
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position, root.AssemblyLinearVelocity
	end
	return nil, Vector3.zero
end

local function refreshIgnore()
	local list: { Instance } = { vehicles }
	local bikes = Workspace:FindFirstChild("Bikes")
	if bikes then
		table.insert(list, bikes)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	losParams.FilterDescendantsInstances = list
	CarDriver.SetIgnore(list)
end

local function lineOfSight(from: Vector3, to: Vector3): boolean
	local hit = Workspace:Raycast(from, to - from, losParams)
	return hit == nil
end

local function spawnUnit(start: CFrame, extra: boolean): Unit
	local model = CarModel.Build("Police")
	model.Name = "Police"
	model:SetAttribute("Pursuit", false)
	local driver = CarDriver.new(model, "Police", start, rng)
	model.Parent = vehicles
	CarDriver.Claim(driver)
	driver.TopSpeed = C.PatrolSpeed
	driver.Accel = 4
	driver.ObeyLights = true
	local unit: Unit = { Driver = driver, Target = nil, Extra = extra, ReleasedAt = 0, Role = "Patrol", InterceptNode = nil, InterceptAt = 0, RoadblockAt = 0, Spikes = nil, Officers = {} }
	table.insert(units, unit)
	return unit
end

local function randomEdge(): (number, number)
	local node = Layout.GridNode[rng:NextInteger(1, Layout.GRID_COUNT - 2)][rng:NextInteger(1, Layout.GRID_COUNT - 2)]
	local edges = Layout.Nodes[node].Edges
	local edge = Layout.Edges[edges[rng:NextInteger(1, #edges)]]
	return node, Layout.OtherEnd(edge, node)
end

local function clearTactics(unit: Unit)
	for _, officer in unit.Officers do
		officer:Destroy()
	end
	table.clear(unit.Officers)
	local spikes = unit.Spikes
	if spikes then
		spikes:Destroy()
		unit.Spikes = nil
	end
	unit.Role = "Patrol"
	unit.InterceptNode = nil
end

local function patrol(unit: Unit)
	local driver = unit.Driver
	clearTactics(unit)
	unit.Target = nil
	driver.Model:SetAttribute("Pursuit", false)
	driver.TopSpeed = C.PatrolSpeed
	driver.Accel = 4
	driver.ObeyLights = true
	local from = Layout.NearestNode(driver.Position)
	local edges = Layout.Nodes[from].Edges
	local edge = Layout.Edges[edges[rng:NextInteger(1, #edges)]]
	CarDriver.Cruise(driver, from, Layout.OtherEnd(edge, from))
end

local function chasersOf(player: Player): number
	local count = 0
	for _, unit in units do
		if unit.Target == player then
			count += 1
		end
	end
	return count
end

local function totalChasers(): number
	local count = 0
	for _, unit in units do
		if unit.Target then
			count += 1
		end
	end
	return count
end

local function assign(unit: Unit, player: Player, stars: number)
	if unit.Target ~= player then
		unit.Role = "Intercept"
	end
	unit.Target = player
	local driver = unit.Driver
	driver.Model:SetAttribute("Pursuit", true)
	driver.TopSpeed = C.PursuitSpeed[math.clamp(stars, 1, #C.PursuitSpeed)]
	driver.Accel = C.PursuitAccel[math.clamp(stars, 1, #C.PursuitAccel)]
	driver.ObeyLights = false
end

-- A node out of the player's sight, 350-700 studs away, to bring a new car in from
local function entryNode(position: Vector3): number
	local best: number? = nil
	for _ = 1, 30 do
		local node = Layout.Nodes[rng:NextInteger(1, #Layout.Nodes)]
		local distance = (node.Position - position).Magnitude
		if distance > 350 and distance < 700 then
			if distance > C.LoseRange then
				best = node.Id
			end
			if not lineOfSight(node.Position + Vector3.new(0, 5, 0), position + Vector3.new(0, 3, 0)) then
				return node.Id
			end
		end
	end
	return best or Layout.PoliceSpawn
end

local function dispatch(player: Player, stars: number)
	local position = whereIs(player)
	if not position then
		return
	end
	local wanted = math.min(C.Units[math.clamp(stars, 1, #C.Units)], C.MaxPursuers)
	-- faster cars for everyone already chasing
	for _, unit in units do
		if unit.Target == player then
			assign(unit, player, stars)
		end
	end
	while chasersOf(player) < wanted and totalChasers() < 12 do
		-- nearest free patrol first
		local nearest: Unit? = nil
		local nearestDistance = 1000
		for _, unit in units do
			if not unit.Target and not unit.Extra then
				local d = (unit.Driver.Position - position).Magnitude
				if d < nearestDistance then
					nearest, nearestDistance = unit, d
				end
			end
		end
		if nearest then
			assign(nearest, player, stars)
		else
			local nodeId = entryNode(position)
			local node = Layout.Nodes[nodeId]
			local look = Vector3.new(position.X - node.Position.X, 0, position.Z - node.Position.Z)
			local start = CFrame.lookAt(node.Position, node.Position + (if look.Magnitude > 1 then look.Unit else Vector3.new(0, 0, -1)))
			local unit = spawnUnit(start, true)
			assign(unit, player, stars)
		end
	end
end

-- The grid crossing the rider will reach about `seconds` from now, if they keep going (nil when
-- they're barely moving)
local function predictNode(position: Vector3, velocity: Vector3, seconds: number): number?
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < 6 then
		return nil
	end
	local ahead = position + flat * seconds
	local nodeId = Layout.NearestNode(ahead, function(node)
		return node.Grid and (node.Position - position):Dot(flat) > 0
	end)
	return nodeId
end

local propsFolder: Folder? = nil
local function props(): Folder
	local existing = propsFolder
	if existing and existing.Parent then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "PoliceProps"
	f.Parent = Workspace
	propsFolder = f
	return f
end

-- A spike strip across the road at `position`, perpendicular to `approach`
local function spikeStrip(position: Vector3, approach: Vector3, width: number): BasePart
	local strip = Instance.new("Part")
	strip.Name = "SpikeStrip"
	strip.Anchored = true
	strip.CanCollide = false
	strip.CanTouch = false
	strip.Size = Vector3.new(width, 0.15, 2.2)
	strip.CFrame = CFrame.lookAt(position + Vector3.new(0, 0.08, 0), position + Vector3.new(0, 0.08, 0) + Vector3.new(approach.X, 0, approach.Z).Unit)
	strip.Color = Color3.fromRGB(30, 30, 32)
	strip.Material = Enum.Material.DiamondPlate
	strip:SetAttribute("Surface", "Spikes")
	strip.Parent = props()
	for i = 0, math.floor(width / 1.5) do
		local tooth = Instance.new("Part")
		tooth.Name = "Spike"
		tooth.Anchored = true
		tooth.CanCollide = false
		tooth.CanQuery = false
		tooth.CanTouch = false
		tooth.Size = Vector3.new(0.25, 0.5, 0.25)
		tooth.CFrame = strip.CFrame * CFrame.new(-width / 2 + 0.75 + i * 1.5, 0.3, 0)
		tooth.Color = Color3.fromRGB(200, 200, 205)
		tooth.Material = Enum.Material.Metal
		tooth.Parent = strip
	end
	return strip
end

-- From RoadblockStars: a cruiser across a crossing ahead, spikes on the rider's side of it
local function placeRoadblock(player: Player, position: Vector3, velocity: Vector3)
	for _, unit in units do
		if unit.Target == player and unit.Role == "Roadblock" then
			return
		end
	end
	local nodeId = predictNode(position, velocity, C.RoadblockAhead)
	if not nodeId then
		return
	end
	local node = Layout.Nodes[nodeId]
	local toNode = Vector3.new(node.Position.X - position.X, 0, node.Position.Z - position.Z)
	if toNode.Magnitude < 160 then
		return -- too close to set up
	end
	if lineOfSight(node.Position + Vector3.new(0, 6, 0), position + Vector3.new(0, 3, 0)) then
		return -- they'd see it appear
	end
	local approach = toNode.Unit
	local across = Vector3.new(-approach.Z, 0, approach.X)
	local start = CFrame.lookAt(node.Position, node.Position + across)
	local unit = spawnUnit(start, true)
	assign(unit, player, C.RoadblockStars)
	unit.Role = "Roadblock"
	unit.RoadblockAt = os.clock()
	CarDriver.Teleport(unit.Driver, nodeId, across)
	CarDriver.Hold(unit.Driver)
	local width = if node.I and node.J then math.max(Layout.LineWidth(node.I), Layout.LineWidth(node.J)) else 30
	unit.Spikes = spikeStrip(node.Position - approach * (width / 2 + 14), approach, width * 0.9)
end

-- Officers out of the car, running at the rider
local function deployOfficers(unit: Unit, position: Vector3)
	if #unit.Officers > 0 then
		return
	end
	local driver = unit.Driver
	CarDriver.Hold(driver)
	unit.Role = "Deployed"
	local cf = CFrame.new(driver.Position) * CFrame.fromEulerAnglesYXZ(0, driver.Yaw, 0)
	for i, side in { -1, 1 } do
		local door = (cf * CFrame.new(side * (driver.HalfWidth + 2.5), 0, -1)).Position
		local officer = Officer.new(door, position - door, i + #units)
		table.insert(unit.Officers, officer)
	end
end

local function release(player: Player)
	for _, unit in units do
		if unit.Target == player then
			unit.ReleasedAt = os.clock()
			patrol(unit)
		end
	end
	local _ = player
end

local function setAttributes(player: Player, w: Watch)
	local h = w.Heat
	local function set(name: string, value: any)
		if player:GetAttribute(name) ~= value then
			player:SetAttribute(name, value)
		end
	end
	set("Wanted", h.Stars)
	set("Heat", math.floor(math.clamp(h.Heat / Heat.Needed(h.Stars), 0, 1) * 100) / 100)
	set("Evade", if h.Stars > 0 then math.floor(math.clamp(h.Evade / Heat.EvadeTime(h.Stars), 0, 1) * 100) / 100 else 0)
	set("Bust", math.floor(h.Bust * 100) / 100)
	set("Seen", w.Seen)
end

local function onEvents(player: Player, w: Watch, events: { Heat.Event })
	for _, event in events do
		if event.Kind == "Wanted" then
			w.MaxStarsThisChase = math.max(w.MaxStarsThisChase, event.Stars)
			Remotes.Event("Police"):FireClient(player, "Wanted", { Stars = event.Stars })
			dispatch(player, event.Stars)
			local data = DataService.Get(player)
			if data and event.Stars > data.Stats.MaxStars then
				data.Stats.MaxStars = event.Stars
				DataService.Changed(player)
			end
		elseif event.Kind == "Escaped" then
			local reward = Heat.EscapeReward(event.Stars, event.Time or 0)
			DataService.AddCash(player, reward)
			local data = DataService.Get(player)
			if data then
				data.Stats.Escapes += 1
				DataService.Changed(player)
			end
			Remotes.Event("Police"):FireClient(player, "Escaped", { Stars = event.Stars, Reward = reward, Time = event.Time or 0 })
			release(player)
			w.MaxStarsThisChase = 0
		end
	end
end

local function bust(player: Player, w: Watch, walkOut: boolean)
	local data = DataService.Get(player)
	local fine = if data then Heat.Fine(data.Cash) else 0
	if data then
		DataService.Spend(player, fine)
		data.Stats.Busts += 1
		DataService.Changed(player)
	end
	local stars = w.Heat.Stars
	Heat.Clear(w.Heat)
	w.MaxStarsThisChase = 0
	release(player)
	BikeService.Despawn(player)
	Remotes.Event("Police"):FireClient(player, "Busted", { Fine = fine, Stars = stars })
	if walkOut then
		local character = player.Character
		if character then
			local station = Layout.Places.Police
			character:PivotTo(CFrame.new(station + Vector3.new(0, 4, -40)))
		end
	end
	setAttributes(player, w)
end

-- Admin: set a player's wanted level directly (0 ends any chase)
function PoliceService.SetWanted(player: Player, stars: number)
	local w = watch(player)
	Heat.Clear(w.Heat)
	w.MaxStarsThisChase = 0
	release(player)
	if stars > 0 then
		local heat = 0.01
		for s = 0, stars - 1 do
			heat += Heat.Needed(s)
		end
		w.SeenAt = os.clock()
		onEvents(player, w, Heat.Offence(w.Heat, heat))
	else
		Remotes.Event("Police"):FireClient(player, "Wanted", { Stars = 0 })
	end
	setAttributes(player, w)
end

-- One-off offences (jumps, flips, hitting a cop) count only if a cop saw them
local function oneOff(player: Player, amount: number)
	local w = watch(player)
	if os.clock() - w.SeenAt > 1 then
		return
	end
	onEvents(player, w, Heat.Offence(w.Heat, amount))
end

-- Did the player just roll into an intersection on red?
local function checkRedLight(player: Player, w: Watch, position: Vector3, velocity: Vector3, kmh: number)
	local function nearestIndex(v: number): number
		return math.clamp(math.floor((v - Layout.GRID_MIN) / Layout.GRID_STEP + 0.5), 0, Layout.GRID_COUNT - 1)
	end
	local i, j = nearestIndex(position.X), nearestIndex(position.Z)
	local insideX = math.abs(position.X - Layout.Line(i)) < Layout.LineWidth(i) / 2
	local insideZ = math.abs(position.Z - Layout.Line(j)) < Layout.LineWidth(j) / 2
	local nodeId = if insideX and insideZ then Layout.GridNode[i][j] else nil
	if nodeId and nodeId ~= w.Inside and kmh > 12 then
		local node = Layout.Nodes[nodeId]
		if Layout.HasLights(node) then
			local axis = if math.abs(velocity.X) > math.abs(velocity.Z) then "X" else "Z"
			local light = Layout.LightState(nodeId, axis, Workspace:GetServerTimeNow(), Config.Lights.Cycle, Config.Lights.Yellow, Config.Lights.AllRed)
			if light == "Red" then
				oneOff(player, C.RedLight)
			end
		end
	end
	w.Inside = nodeId
end

local function tick(dt: number)
	for _, player in Players:GetPlayers() do
		local w = watch(player)
		local position, velocity = whereIs(player)
		if not position then
			continue
		end
		local ride = BikeService.Get(player)
		local riding = ride ~= nil and ride.Riding
		local kmh = if ride and riding then BikeService.Kmh(ride) else Vector3.new(velocity.X, 0, velocity.Z).Magnitude * Config.KMH_PER_STUD_PER_SECOND

		-- Who can see them?
		local range = if w.Heat.Stars > 0 then C.LoseRange else C.SightRange
		local seen = false
		local nearestCop = math.huge
		local eye = position + Vector3.new(0, 3, 0)
		for _, unit in units do
			local d = (unit.Driver.Position - position).Magnitude
			if unit.Target == player then
				nearestCop = math.min(nearestCop, d)
			elseif w.Heat.Stars == 0 then
				nearestCop = math.min(nearestCop, d)
			end
			if not seen and d < range and lineOfSight(unit.Driver.Position + Vector3.new(0, 5, 0), eye) then
				seen = true
			end
		end
		w.Seen = seen
		if seen then
			w.SeenAt = os.clock()
		end

		-- What are they doing?
		local offences = Heat.NoOffences()
		if ride and riding then
			local state = ride.State
			local moving = kmh > 6
			offences.Wheelie = (state.Wheelie or state.Stoppie) and moving
			offences.NoHands = state.Hands == 2 and moving
			offences.Drift = state.Drift and moving
			if state.Surface == "Road" then
				offences.SpeedOver = math.max(0, kmh - ride.Bike.LegalKmh)
			end
			offences.Sidewalk = state.Surface == "Sidewalk" and kmh > C.SidewalkKmh
			checkRedLight(player, w, position, velocity, kmh)
		end
		local hadHeat = w.Heat.Heat > 0
		onEvents(player, w, Heat.Update(w.Heat, dt, seen, offences))
		if seen and not hadHeat and w.Heat.Heat > 0 and w.Heat.Stars == 0 and not w.Spotted then
			w.Spotted = true
			Remotes.Event("Police"):FireClient(player, "Spotted", {})
		elseif w.Heat.Heat <= 0 and w.Heat.Stars == 0 then
			w.Spotted = false
		end

		-- Keep the chasers coming if some were lost, but only while someone can see them: dispatch
		-- doesn't know where a rider who's broken line of sight has gone
		if w.Heat.Stars > 0 and os.clock() - w.SeenAt < 3 and chasersOf(player) < math.min(C.Units[w.Heat.Stars], C.MaxPursuers) then
			dispatch(player, w.Heat.Stars)
		end
		if w.Heat.Stars >= C.RoadblockStars and riding and w.Seen and os.clock() - w.RoadblockAt > 20 then
			w.RoadblockAt = os.clock()
			placeRoadblock(player, position, velocity)
		end

		-- Cornered: stopped (or knocked off, or on foot) near a cruiser sends the officers out; an
		-- officer reaching you while you're slow or down fills the bust meter
		local cornered = false
		if w.Heat.Stars > 0 then
			local bailed = BikeService.Bailed(player)
			local helpless = bailed or not riding or kmh < C.BustKmh
			local stopped = bailed or not riding or kmh < C.DeployKmh
			if stopped then
				for _, unit in units do
					if unit.Target == player and #unit.Officers == 0 and (unit.Driver.Position - position).Magnitude < C.DeployRange then
						deployOfficers(unit, position)
						break
					end
				end
			end
			for _, unit in units do
				if unit.Target == player then
					for _, officer in unit.Officers do
						local root = officer.PrimaryPart
						if root and (root.Position - position).Magnitude < C.ArrestRange and helpless then
							cornered = true
						end
					end
				end
			end
		end
		if Heat.UpdateBust(w.Heat, dt, cornered) then
			bust(player, w, true)
		end
		setAttributes(player, w)
	end
end

-- Roles by distance: the nearest car leads, the next flanks, the rest intercept (a roadblock or a
-- car whose officers are out keeps its job)
local function assignRoles(now: number)
	local byPlayer: { [Player]: { Unit } } = {}
	for _, unit in units do
		local target = unit.Target
		if target and unit.Role ~= "Roadblock" and unit.Role ~= "Deployed" then
			local list = byPlayer[target] or {}
			table.insert(list, unit)
			byPlayer[target] = list
		end
	end
	for player, list in byPlayer do
		local position = whereIs(player)
		if position then
			table.sort(list, function(a, b)
				return (a.Driver.Position - position).Magnitude < (b.Driver.Position - position).Magnitude
			end)
			for i, unit in list do
				unit.Role = if i == 1 then "Lead" elseif i == 2 then "Flank" else "Intercept"
			end
		end
	end
	local _ = now
end

local function driveTactics(unit: Unit, player: Player, position: Vector3, velocity: Vector3, now: number)
	local driver = unit.Driver
	local w = watch(player)
	local distance = (position - driver.Position).Magnitude
	local visible = distance < 260 and (distance < 40 or lineOfSight(driver.Position + Vector3.new(0, 5, 0), position + Vector3.new(0, 3, 0)))
	local role = unit.Role

	if role == "Deployed" then
		-- officers out: send them at the rider, or back to the car when the rider's away
		local gone = distance > C.OfficerGiveUp
		local back = 0
		for _, officer in unit.Officers do
			local humanoid = officer:FindFirstChildOfClass("Humanoid")
			local root = officer.PrimaryPart
			if humanoid and root then
				if gone then
					humanoid:MoveTo(driver.Position)
					if (root.Position - driver.Position).Magnitude < 9 then
						back += 1
					end
				else
					humanoid:MoveTo(position)
				end
			else
				back += 1
			end
		end
		if gone and back >= #unit.Officers then
			for _, officer in unit.Officers do
				officer:Destroy()
			end
			table.clear(unit.Officers)
			unit.Role = "Intercept"
		end
		return
	elseif role == "Roadblock" then
		-- hold the crossing until the rider is past it or it times out
		local node = unit.InterceptNode
		if now - unit.RoadblockAt > C.RoadblockTime or (distance > 320 and not visible) then
			local spikes = unit.Spikes
			if spikes then
				spikes:Destroy()
				unit.Spikes = nil
			end
			unit.Role = "Intercept"
		end
		local _ = node
		return
	elseif role == "Intercept" and not (visible and distance < 70) then
		-- get to the crossing they'll reach next, and block it
		if not unit.InterceptNode or now - unit.InterceptAt > 3 then
			unit.InterceptNode = predictNode(position, velocity, C.InterceptAhead)
			unit.InterceptAt = now
		end
		local nodeId = unit.InterceptNode
		if nodeId then
			local spot = Layout.Nodes[nodeId].Position
			if (spot - driver.Position).Magnitude < 22 then
				CarDriver.Hold(driver)
			else
				CarDriver.Chase(driver, spot, Vector3.zero, false)
			end
			return
		end
	end

	local aim = position
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local moving = flat.Magnitude / Config.STUDS_PER_METER * 3.6 > C.BoxInKmh
	if moving and role ~= "Flank" then
		-- tail at a safe gap, never into the bike
		aim = position - flat.Unit * C.FollowGap
	end
	if role == "Flank" and visible and distance < 140 then
		-- ride alongside, on the side the car is already on
		if flat.Magnitude > 4 then
			local dir = flat.Unit
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local side = if (driver.Position - position):Dot(right) >= 0 then 1 else -1
			-- pacing a lane over and a little behind, never alongside close enough to touch
			aim = position + right * (side * C.FlankOffset) - dir * 6
		end
	end
	CarDriver.Chase(driver, aim, velocity, visible)

	-- hopelessly stuck or left far behind: bring it back in closer
	if driver.StuckCount >= 3 or distance > 1400 then
		local nodeId = entryNode(position)
		CarDriver.Teleport(driver, nodeId, position - Layout.Nodes[nodeId].Position)
		CarDriver.Chase(driver, position, velocity, false)
	end
end

local function driveUnits(dt: number)
	-- people cruising cars stop for
	local people: { Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local p = whereIs(player)
		if p then
			table.insert(people, p)
		end
	end
	local now = os.clock()
	assignRoles(now)
	for index = #units, 1, -1 do
		local unit = units[index]
		local driver = unit.Driver
		local target = unit.Target
		if target then
			local position, velocity = whereIs(target)
			if position and target.Parent then
				driveTactics(unit, target, position, velocity, now)
			else
				patrol(unit)
			end
		elseif unit.Extra and now - unit.ReleasedAt > 25 then
			-- reinforcements head home once nobody is around to see them vanish
			local visible = false
			for _, p in people do
				if (p - driver.Position).Magnitude < 350 then
					visible = true
					break
				end
			end
			if not visible then
				clearTactics(unit)
				CarDriver.Destroy(driver)
				table.remove(units, index)
				continue
			end
		end
		CarDriver.Step(driver, dt, if unit.Target then {} else people)
	end
end

function PoliceService.Init()
	local existing = Workspace:FindFirstChild("Vehicles")
	if existing and existing:IsA("Folder") then
		vehicles = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Vehicles"
		created.Parent = Workspace
		vehicles = created
	end
	refreshIgnore()
	EconomyService.StarsOf = PoliceService.Stars

	for _ = 1, C.PatrolCount do
		local from, to = randomEdge()
		local unit = spawnUnit(CFrame.new(Layout.Nodes[from].Position), false)
		CarDriver.PlaceOnEdge(unit.Driver, from, to)
	end

	EconomyService.Trick:Connect(function(player: Player, kind: string, _amount: number, what: string?)
		if kind == "Jump" then
			oneOff(player, C.Jump)
		elseif kind == "Flip" then
			oneOff(player, C.Flip)
		elseif kind == "Impact" and what == "Cop" then
			-- only if a cop car really is right there
			local position = whereIs(player)
			if position then
				for _, unit in units do
					if (unit.Driver.Position - position).Magnitude < 30 then
						local w = watch(player)
						w.SeenAt = os.clock()
						onEvents(player, w, Heat.Offence(w.Heat, C.HitCop))
						break
					end
				end
			end
		end
	end)

	-- Dying while wanted is a bust (no free escapes by resetting)
	local function hookCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				local w = watches[player]
				if w and w.Heat.Stars > 0 then
					bust(player, w, false)
				end
			end)
		end
		refreshIgnore()
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		watches[player] = nil
		task.defer(refreshIgnore)
	end)

	RunService.Heartbeat:Connect(driveUnits)
	task.spawn(function()
		local interval = 0.2
		while true do
			task.wait(interval)
			tick(interval)
		end
	end)
end

return PoliceService
