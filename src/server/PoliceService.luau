--[[
	PoliceService: patrol cars, heat, wanted stars, pursuits, busts and escapes.

	Patrol cruisers drive the city like traffic. Any cop with a clear line of sight within
	Config.Police.SightRange watches what riders do; offences (Shared/Heat: wheelies above all, no
	hands, speeding past a bike's legal limit, fast riding on pavements, red lights, jumps, flips,
	hitting a cop car) fill a heat meter, and a full meter is a wanted star. Each star brings more
	cars, faster ones, and a richer cash multiplier while the chase lasts.

	Lose every pursuer's line of sight for long enough and you escape (and get paid); slow down next
	to a cop, or get off the bike, and the cuffs come out (a fine, the bike goes back to the garage
	and you're walked out of the station).

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

local PoliceService = {}

local C = Config.Police

type Unit = {
	Driver: CarDriver.Driver,
	Target: Player?,
	Extra: boolean, -- brought in for a chase; leaves when it's over
	ReleasedAt: number,
}

type Watch = {
	Heat: Heat.State,
	SeenAt: number,
	Seen: boolean,
	Spotted: boolean,
	Inside: number?, -- intersection node the player is crossing
	MaxStarsThisChase: number,
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
		w = { Heat = Heat.new(), SeenAt = -math.huge, Seen = false, Spotted = false, Inside = nil, MaxStarsThisChase = 0 }
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
	local unit: Unit = { Driver = driver, Target = nil, Extra = extra, ReleasedAt = 0 }
	table.insert(units, unit)
	return unit
end

local function randomEdge(): (number, number)
	local node = Layout.GridNode[rng:NextInteger(1, Layout.GRID_COUNT - 2)][rng:NextInteger(1, Layout.GRID_COUNT - 2)]
	local edges = Layout.Nodes[node].Edges
	local edge = Layout.Edges[edges[rng:NextInteger(1, #edges)]]
	return node, Layout.OtherEnd(edge, node)
end

local function patrol(unit: Unit)
	local driver = unit.Driver
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
			best = node.Id
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

local function release(player: Player)
	for _, unit in units do
		if unit.Target == player then
			unit.ReleasedAt = os.clock()
			patrol(unit)
		end
	end
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
			offences.Wheelie = state.Wheelie and moving
			offences.NoHands = state.Hands == 2 and moving
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

		-- Keep the chasers coming if some were lost
		if w.Heat.Stars > 0 and chasersOf(player) < math.min(C.Units[w.Heat.Stars], C.MaxPursuers) then
			dispatch(player, w.Heat.Stars)
		end

		-- Cornered?
		local cornered = false
		if w.Heat.Stars > 0 then
			if riding then
				cornered = nearestCop < C.BustRange and kmh < C.BustKmh
			else
				cornered = nearestCop < C.FootBustRange
			end
		end
		if Heat.UpdateBust(w.Heat, dt, cornered) then
			bust(player, w, true)
		end
		setAttributes(player, w)
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
	for index = #units, 1, -1 do
		local unit = units[index]
		local driver = unit.Driver
		local target = unit.Target
		if target then
			local position, velocity = whereIs(target)
			if position and target.Parent then
				local distance = (position - driver.Position).Magnitude
				local direct = distance < 260 and (distance < 40 or lineOfSight(driver.Position + Vector3.new(0, 5, 0), position + Vector3.new(0, 3, 0)))
				CarDriver.Chase(driver, position, velocity, direct)
				-- hopelessly stuck or left far behind: bring it back in closer
				if driver.StuckCount >= 3 or distance > 1400 then
					local nodeId = entryNode(position)
					CarDriver.Teleport(driver, nodeId, position - Layout.Nodes[nodeId].Position)
					CarDriver.Chase(driver, position, velocity, false)
				end
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
