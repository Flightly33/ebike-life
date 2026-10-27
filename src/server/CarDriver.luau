--[[
	CarDriver: drives a CarModel around the road graph (Shared/City/Layout) on the server.

	Cars are kinematic like the bikes: the driver owns position, heading and speed, follows the
	ground with raycasts and writes the result onto the car each frame (server-owned, unanchored, so
	clients get smooth physics replication, with a force that cancels gravity between frames).

	Cruise: random routes in the right-hand lane, stopping at red lights and behind other cars.
	Chase:  straight at the target when it's close and in sight (off-road if need be), otherwise
	        along the shortest road route to it, ignoring lights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.City.Layout)
local CarModel = require(Shared.Models.CarModel)

local CarDriver = {}
CarDriver.__index = CarDriver

local STUDS = Config.STUDS_PER_METER
local TAU = math.pi * 2

export type Mode = "Cruise" | "Chase" | "Idle"

export type Driver = {
	Model: Model,
	Root: BasePart,
	Kind: CarModel.Kind,
	Position: Vector3,
	Yaw: number,
	Pitch: number,
	Speed: number, -- m/s
	TopSpeed: number,
	Accel: number,
	Mode: Mode,
	ObeyLights: boolean,
	Waypoints: { Vector3 },
	WaypointNodes: { number }, -- the node each waypoint leads into (for traffic lights)
	WaypointSpeeds: { number }, -- the road's speed relative to a street's (1), per waypoint
	WaypointIndex: number,
	-- route state while cruising
	FromNode: number,
	ToNode: number,
	Lane: number,
	-- chase state
	Target: Vector3?,
	TargetVelocity: Vector3,
	Direct: boolean,
	ReplanAt: number,
	-- stuck handling
	StuckTime: number,
	Reverse: number,
	StuckCount: number,
	HalfLength: number,
	HalfWidth: number,
	Force: VectorForce,
	Rng: Random,
	Alive: boolean,
}

CarDriver.All = {} :: { Driver }

local queryParams = RaycastParams.new()
queryParams.FilterType = Enum.RaycastFilterType.Exclude
queryParams.RespectCanCollide = true
local excluded: { Instance } = {}

-- Everything the cars' rays should ignore (vehicles, bikes, characters); refreshed by the services
function CarDriver.SetIgnore(list: { Instance })
	excluded = list
	queryParams.FilterDescendantsInstances = excluded
end

local function wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function forward(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function CarDriver.new(model: Model, kind: CarModel.Kind, start: CFrame, rng: Random): Driver
	local root = model.PrimaryPart :: BasePart
	model:PivotTo(start)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Lift"
	attachment.Parent = root
	local force = Instance.new("VectorForce")
	force.Name = "AntiGravity"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Parent = root
	local halfLength, halfWidth = CarModel.Extents(kind)
	local self: Driver = setmetatable({
		Model = model,
		Root = root,
		Kind = kind,
		Position = start.Position,
		Yaw = yawOf(start.LookVector),
		Pitch = 0,
		Speed = 0,
		TopSpeed = Config.Traffic.Speed,
		Accel = 3.5,
		Mode = "Cruise" :: Mode,
		ObeyLights = true,
		Waypoints = {},
		WaypointNodes = {},
		WaypointSpeeds = {},
		WaypointIndex = 1,
		FromNode = 1,
		ToNode = 1,
		Lane = 1,
		Target = nil,
		TargetVelocity = Vector3.zero,
		Direct = false,
		ReplanAt = 0,
		StuckTime = 0,
		Reverse = 0,
		StuckCount = 0,
		HalfLength = halfLength,
		HalfWidth = halfWidth,
		Force = force,
		Rng = rng,
		Alive = true,
	}, CarDriver) :: any
	table.insert(CarDriver.All, self)
	return self
end

function CarDriver.Destroy(self: Driver)
	self.Alive = false
	local index = table.find(CarDriver.All, self)
	if index then
		table.remove(CarDriver.All, index)
	end
	self.Model:Destroy()
end

-- Server ownership once the car is in the world (unanchored parts otherwise drift to players)
function CarDriver.Claim(self: Driver)
	for _, d in self.Model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	pcall(function()
		self.Root:SetNetworkOwner(nil)
	end)
	self.Force.Force = Vector3.new(0, self.Root.AssemblyMass * Workspace.Gravity, 0)
end

--------------------------------------------------------------------------------
-- Routes
--------------------------------------------------------------------------------
local STREET_SPEED = 11 -- m/s, Layout's street speed: the speed TopSpeed is set for

local function clearance(nodeId: number, edge: Layout.Edge): number
	local node = Layout.Nodes[nodeId]
	if node.Grid then
		return Layout.NodeClearance(nodeId, edge.Axis) + 6
	end
	return 4
end

-- Lane points along an edge travelled from `from`
local function edgePoints(edge: Layout.Edge, from: number, lane: number): (Vector3, Vector3)
	local to = Layout.OtherEnd(edge, from)
	local startT = clearance(from, edge) / edge.Length
	local endT = 1 - clearance(to, edge) / edge.Length
	return Layout.LanePoint(edge, from, startT, lane), Layout.LanePoint(edge, from, endT, lane)
end

-- A smooth turn between two lanes through an intersection
local function turnPoints(exit: Vector3, entry: Vector3, corner: Vector3): { Vector3 }
	local points = {}
	local control = corner:Lerp((exit + entry) / 2, 0.35)
	for i = 1, 3 do
		local t = i / 4
		local a = exit:Lerp(control, t)
		local b = control:Lerp(entry, t)
		table.insert(points, a:Lerp(b, t))
	end
	return points
end

local function flatDir(from: Vector3, to: Vector3): Vector3
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.zero
end

-- The next node on a cruise: any road out but the one we came in on, and no doubling back (a
-- freeway's ramps meet it at a node; a car off the ramp goes on along the deck, not back down)
local function pickNext(self: Driver, at: number, cameFrom: number): number
	local node = Layout.Nodes[at]
	local incoming = flatDir(Layout.Nodes[cameFrom].Position, node.Position)
	local options, ahead = {}, {}
	for _, edgeId in node.Edges do
		local other = Layout.OtherEnd(Layout.Edges[edgeId], at)
		if other ~= cameFrom then
			table.insert(options, other)
			if flatDir(node.Position, Layout.Nodes[other].Position):Dot(incoming) > -0.3 then
				table.insert(ahead, other)
			end
		end
	end
	if #ahead > 0 then
		options = ahead
	end
	if #options == 0 then
		return cameFrom
	end
	return options[self.Rng:NextInteger(1, #options)]
end

-- Appends the waypoints for driving from `a` to `b` (and the turn into `c`, if given)
local function appendLeg(self: Driver, a: number, b: number, c: number?)
	local edge = Layout.EdgeBetween(a, b)
	if not edge then
		return
	end
	local lane = math.min(self.Lane, edge.Lanes)
	local entry, exit = edgePoints(edge, a, lane)
	local scale = edge.Speed / STREET_SPEED
	local function add(p: Vector3)
		table.insert(self.Waypoints, p)
		table.insert(self.WaypointNodes, b)
		table.insert(self.WaypointSpeeds, scale)
	end
	add(entry)
	-- intermediate points on long edges keep the pursuit steering on the lane
	local steps = math.floor(edge.Length / 120)
	for i = 1, steps do
		add(entry:Lerp(exit, i / (steps + 1)))
	end
	add(exit)
	if c then
		local nextEdge = Layout.EdgeBetween(b, c)
		if nextEdge then
			local nextEntry = edgePoints(nextEdge, b, math.min(self.Lane, nextEdge.Lanes))
			for _, p in turnPoints(exit, nextEntry, Layout.Nodes[b].Position) do
				add(p)
			end
		end
	end
end

-- Start cruising on the edge from `from` to `to`
function CarDriver.Cruise(self: Driver, from: number, to: number)
	self.Mode = "Cruise"
	self.Target = nil
	self.FromNode = from
	self.ToNode = to
	self.Waypoints = {}
	self.WaypointNodes = {}
	self.WaypointSpeeds = {}
	self.WaypointIndex = 1
	local after = pickNext(self, to, from)
	appendLeg(self, from, to, after)
	self.FromNode, self.ToNode = to, after
end

-- Queue the next leg when the route runs low
local function extendCruise(self: Driver)
	if #self.Waypoints - self.WaypointIndex > 4 then
		return
	end
	local from, to = self.FromNode, self.ToNode
	local after = pickNext(self, to, from)
	-- drop the waypoints already passed
	local kept, keptNodes, keptSpeeds = {}, {}, {}
	for i = self.WaypointIndex, #self.Waypoints do
		table.insert(kept, self.Waypoints[i])
		table.insert(keptNodes, self.WaypointNodes[i])
		table.insert(keptSpeeds, self.WaypointSpeeds[i] or 1)
	end
	self.Waypoints = kept
	self.WaypointNodes = keptNodes
	self.WaypointSpeeds = keptSpeeds
	self.WaypointIndex = 1
	appendLeg(self, from, to, after)
	self.FromNode, self.ToNode = to, after
end

-- Chase `target`; `direct` when the cop can see it and it's close
function CarDriver.Chase(self: Driver, target: Vector3, velocity: Vector3, direct: boolean)
	self.Mode = "Chase"
	self.Target = target
	self.TargetVelocity = velocity
	local now = os.clock()
	if direct then
		self.Direct = true
		return
	end
	if self.Direct or now >= self.ReplanAt or #self.Waypoints - self.WaypointIndex < 1 then
		self.Direct = false
		self.ReplanAt = now + 2
		local start = Layout.NearestNode(self.Position + forward(self.Yaw) * 40)
		local goal = Layout.NearestNode(target)
		local path = Layout.Path(start, goal)
		self.Waypoints = { Layout.Nodes[start].Position }
		self.WaypointNodes = { start }
		self.WaypointSpeeds = { 1 }
		self.WaypointIndex = 1
		for i = 1, #path - 1 do
			appendLeg(self, path[i], path[i + 1], path[i + 2])
		end
		table.insert(self.Waypoints, Vector3.new(target.X, Layout.ROAD_Y, target.Z))
		table.insert(self.WaypointNodes, goal)
		table.insert(self.WaypointSpeeds, 1)
	end
end

--------------------------------------------------------------------------------
-- Driving
--------------------------------------------------------------------------------
local function lightAhead(self: Driver): (boolean, number)
	-- Is the node we're heading into lit, and red/amber for our direction? Returns distance to stop.
	if not self.ObeyLights or self.Mode ~= "Cruise" then
		return false, math.huge
	end
	local nodeId = self.WaypointNodes[self.WaypointIndex]
	local fromNode = if nodeId then Layout.Nodes[nodeId] else nil
	if not fromNode then
		return false, math.huge
	end
	if not Layout.HasLights(fromNode) then
		return false, math.huge
	end
	local toNode = fromNode.Position
	local offset = toNode - self.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local dir = forward(self.Yaw)
	local ahead = flat:Dot(dir)
	local axis = if math.abs(dir.X) > math.abs(dir.Z) then "X" else "Z"
	local half = if axis == "X" then (fromNode.WX or 26) / 2 else (fromNode.WZ or 26) / 2
	local stopDistance = ahead - half - 6 - self.HalfLength
	if stopDistance < -2 or stopDistance > 60 then
		return false, math.huge
	end
	local state = Layout.LightState(fromNode.Id, axis, Workspace:GetServerTimeNow(), Config.Lights.Cycle, Config.Lights.Yellow, Config.Lights.AllRed)
	if state == "Red" or (state == "Yellow" and stopDistance > 8) then
		return true, stopDistance
	end
	return false, math.huge
end

-- Something in front we should stop behind (other cars, people on bikes or on foot)
local function trafficAhead(self: Driver, others: { Vector3 }): number
	local dir = forward(self.Yaw)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local nearest = math.huge
	for _, other in CarDriver.All do
		if other ~= self and other.Alive then
			local offset = other.Position - self.Position
			local ahead = offset:Dot(dir)
			if ahead > 0 and ahead < 60 and math.abs(offset:Dot(right)) < self.HalfWidth + other.HalfWidth + 1 then
				nearest = math.min(nearest, ahead - self.HalfLength - other.HalfLength)
			end
		end
	end
	for _, p in others do
		local offset = p - self.Position
		local ahead = offset:Dot(dir)
		if ahead > 0 and ahead < 50 and math.abs(offset:Dot(right)) < self.HalfWidth + 2 then
			nearest = math.min(nearest, ahead - self.HalfLength - 2)
		end
	end
	return nearest
end

local function ground(position: Vector3): (number?, Vector3)
	local hit = Workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), queryParams)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return nil, Vector3.yAxis
end

-- `people`: positions of riders and walkers a cruising car should stop for
function CarDriver.Step(self: Driver, dt: number, people: { Vector3 })
	if not self.Alive or not self.Root.Parent then
		return
	end
	local dir = forward(self.Yaw)

	-- Where to steer
	local aim: Vector3? = nil
	if self.Mode == "Chase" and self.Direct and self.Target then
		local target = self.Target
		local distance = (target - self.Position).Magnitude
		local lead = math.min(1.2, distance / 60)
		aim = target + self.TargetVelocity * lead
	elseif #self.Waypoints > 0 then
		-- pure pursuit: the first waypoint further than the look-ahead distance
		local lookahead = 18 + math.abs(self.Speed) * STUDS * 0.35
		while self.WaypointIndex < #self.Waypoints do
			local wp = self.Waypoints[self.WaypointIndex]
			local offset = Vector3.new(wp.X - self.Position.X, 0, wp.Z - self.Position.Z)
			if offset.Magnitude < lookahead or offset:Dot(dir) < 0 and offset.Magnitude < lookahead * 2 then
				self.WaypointIndex += 1
			else
				break
			end
		end
		aim = self.Waypoints[self.WaypointIndex]
		if self.Mode == "Cruise" then
			extendCruise(self)
		end
	end

	-- Target speed (cruising: scaled by the road, faster on the freeway)
	local targetSpeed = if self.Mode == "Idle" then 0 else self.TopSpeed
	if self.Mode == "Cruise" then
		targetSpeed *= self.WaypointSpeeds[self.WaypointIndex] or 1
	end
	local yawError = 0
	if aim then
		local offset = Vector3.new(aim.X - self.Position.X, 0, aim.Z - self.Position.Z)
		if offset.Magnitude > 0.5 then
			yawError = wrap(yawOf(offset) - self.Yaw)
		end
		-- slow for corners
		local bend = math.abs(yawError)
		if bend > 0.35 then
			targetSpeed = math.min(targetSpeed, math.max(4, 14 - bend * 9))
		end
		if self.Mode == "Chase" and self.Direct and self.Target then
			local distance = (self.Target - self.Position).Magnitude
			if distance < 30 then
				-- hold station on the target point: speed up a little while behind it, ease off past it
				-- (the police aim it a safe gap behind a rider, so this never closes into the bike)
				local theirs = self.TargetVelocity.Magnitude / STUDS
				local along = if self.TargetVelocity.Magnitude > 1 then (self.Target - self.Position):Dot(self.TargetVelocity.Unit) else distance
				targetSpeed = math.min(targetSpeed, math.max(0, theirs + math.clamp(along * 0.25, -6, 3)))
			end
		end
	end
	if self.Mode == "Cruise" then
		local red, stopIn = lightAhead(self)
		if red then
			targetSpeed = math.min(targetSpeed, math.max(0, stopIn / STUDS * 1.2))
			if stopIn < 1.5 then
				targetSpeed = 0
			end
		end
		local gap = trafficAhead(self, people)
		if gap < 40 then
			targetSpeed = math.min(targetSpeed, math.max(0, (gap - 6) / STUDS * 1.0))
		end
	end

	-- Reverse out when stuck (chases only; cruising cars just wait)
	if self.Reverse > 0 then
		self.Reverse -= dt
		targetSpeed = -4
		yawError = -yawError
	end

	-- Speed
	local accel = if targetSpeed > self.Speed then self.Accel else 9
	if self.Speed < targetSpeed then
		self.Speed = math.min(targetSpeed, self.Speed + accel * dt)
	else
		self.Speed = math.max(targetSpeed, self.Speed - accel * dt)
	end

	-- Steering: turning circle of ~6 m, quicker at walking pace
	local maxRate = math.max(0.8, math.abs(self.Speed) / 6)
	local yawRate = math.clamp(yawError * 3, -maxRate, maxRate)
	if self.Speed < 0 then
		yawRate = -yawRate * 0.6
	end
	self.Yaw = wrap(self.Yaw + yawRate * dt)
	dir = forward(self.Yaw)

	-- Move, stopping at walls
	local delta = dir * (self.Speed * STUDS * dt)
	if delta.Magnitude > 1e-4 then
		local center = self.Position + Vector3.new(0, 3.5, 0)
		local cast = Workspace:Blockcast(CFrame.lookAt(center, center + dir), Vector3.new(self.HalfWidth * 1.6, 3, self.HalfLength * 1.8), delta, queryParams)
		if cast and not (cast.Instance.Size.X < 4 and cast.Instance.Size.Z < 4) then
			delta = delta.Unit * math.max(0, cast.Distance - 0.2)
			self.Speed *= 0.3
		end
	end
	local nextPosition = self.Position + delta
	local frontY, _ = ground(nextPosition + dir * self.HalfLength * 0.8)
	local backY, _ = ground(nextPosition - dir * self.HalfLength * 0.8)
	local y = if frontY and backY then (frontY + backY) / 2 else (frontY or backY or nextPosition.Y)
	if frontY and backY then
		self.Pitch = math.atan2(frontY - backY, self.HalfLength * 1.6)
	end
	-- don't climb walls
	if y - self.Position.Y > 2 then
		y = self.Position.Y
		nextPosition = self.Position
		self.Speed = 0
	end
	self.Position = Vector3.new(nextPosition.X, y, nextPosition.Z)

	-- Stuck detection
	if math.abs(targetSpeed) > 3 and math.abs(self.Speed) < 0.8 and self.Reverse <= 0 then
		self.StuckTime += dt
		if self.StuckTime > 2.2 and self.Mode == "Chase" then
			self.StuckTime = 0
			self.Reverse = 1.3
			self.StuckCount += 1
		end
	else
		self.StuckTime = math.max(0, self.StuckTime - dt)
	end

	local cf = CFrame.new(self.Position) * CFrame.fromEulerAnglesYXZ(0, self.Yaw, 0) * CFrame.Angles(self.Pitch, 0, 0)
	self.Model:PivotTo(cf)
	self.Root.AssemblyLinearVelocity = dir * (self.Speed * STUDS)
	self.Root.AssemblyAngularVelocity = Vector3.zero
end

-- Stop and stay put (a roadblock, or officers getting out)
function CarDriver.Hold(self: Driver)
	self.Mode = "Idle"
	self.Target = nil
	self.Direct = false
	table.clear(self.Waypoints)
	table.clear(self.WaypointNodes)
	table.clear(self.WaypointSpeeds)
	self.WaypointIndex = 1
end

-- Put the car on a road edge (start of a cruise)
function CarDriver.PlaceOnEdge(self: Driver, from: number, to: number)
	local edge = Layout.EdgeBetween(from, to)
	if not edge then
		return
	end
	local entry = edgePoints(edge, from, 1)
	local dir = (Layout.Nodes[to].Position - Layout.Nodes[from].Position).Unit
	self.Position = entry
	self.Yaw = yawOf(dir)
	self.Speed = 0
	self.Model:PivotTo(CFrame.lookAt(entry, entry + dir))
	CarDriver.Cruise(self, from, to)
end

-- Jump to a road node (used when a chasing car is hopelessly stuck or far away)
function CarDriver.Teleport(self: Driver, nodeId: number, facing: Vector3?)
	local node = Layout.Nodes[nodeId]
	local edgeId = node.Edges[self.Rng:NextInteger(1, #node.Edges)]
	local other = Layout.OtherEnd(Layout.Edges[edgeId], nodeId)
	CarDriver.PlaceOnEdge(self, nodeId, other)
	if facing then
		self.Yaw = yawOf(facing)
	end
	self.StuckCount = 0
	self.Reverse = 0
end

return CarDriver
