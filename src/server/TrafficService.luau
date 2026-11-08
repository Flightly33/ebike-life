--[[
	TrafficService: civilian cars cruising the city's roads. They stop at red lights and behind
	other cars and people, which makes running a red light near a cop (or riding into traffic) a
	real risk.

	Cars start spread over every road in the map by its length (every grid, the turnpike, the
	freeways and causeways, the country roads), and a car left far from every player is moved to a
	road a few blocks from one (out of sight), so there's traffic wherever anyone rides.

	Buses run lines (LINES): each loops a rectangle of downtown streets in the kerb lane and pulls
	up for a few seconds at every shelter on its right (the BusStop models in the city's Furniture);
	a bus far from everyone only moves to where its own line passes near someone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.City.Layout)
local CarModel = require(Shared.Models.CarModel)

local CarDriver = require(script.Parent.CarDriver)

local TrafficService = {}

type Car = { Driver: CarDriver.Driver, StillFor: number }

-- Bus lines: loops through downtown grid crossings (x and z line numbers), each passing the
-- shelters on one side of an avenue (Builder labels the shelters to match: Miami Ave's west side
-- "1", Flagler St's south side "2", its north side "3")
TrafficService.LINES = {
	{ Name = "1", Corners = { { 4, 0 }, { 4, 7 }, { 3, 7 }, { 3, 0 } } },
	{ Name = "2", Corners = { { 2, 4 }, { 7, 4 }, { 7, 3 }, { 2, 3 } } },
	{ Name = "3", Corners = { { 7, 4 }, { 2, 4 }, { 2, 5 }, { 7, 5 } } },
}

-- the kinds that cruise at random (buses only run their lines)
local KINDS: { CarModel.Kind } = {}
for _, kind in CarModel.TrafficKinds do
	if kind ~= "Bus" then
		table.insert(KINDS, kind)
	end
end

local cars: { Car } = {}
local rng = Random.new(777)
local vehicles: Folder

-- the map grows with the world (Config.MAP_SCALE): these were tuned at 1.25
local MAP = Config.MAP_SCALE / 1.25
local KEEP = 1500 * MAP -- a car further than this from every player is moved near one
local NEAR_MIN, NEAR_MAX = 350 * MAP, 1000 * MAP -- how far from a player it turns up
local CHECK_EVERY = 2 -- seconds between those checks

-- every road a car can cruise (not the short pieces through a crossing)
local roads: { Layout.Edge } = {}

-- A road picked by its length, so every one gets its share (`near`: only roads whose middle is
-- this far from that point)
local function pickRoad(near: Vector3?): Layout.Edge?
	local total = 0
	local pool: { Layout.Edge } = {}
	for _, edge in roads do
		local ok = true
		if near then
			local a, b = Layout.Nodes[edge.A].Position, Layout.Nodes[edge.B].Position
			local mid = (a + b) / 2
			local d = Vector3.new(mid.X - near.X, 0, mid.Z - near.Z).Magnitude
			ok = d > NEAR_MIN and d < NEAR_MAX
		end
		if ok then
			table.insert(pool, edge)
			total += edge.Length
		end
	end
	if total <= 0 then
		return nil
	end
	local r = rng:NextNumber(0, total)
	for _, edge in pool do
		r -= edge.Length
		if r <= 0 then
			return edge
		end
	end
	return pool[#pool]
end

-- Set the car down partway along a road, either way along it
local function place(driver: CarDriver.Driver, edge: Layout.Edge)
	local from, to = edge.A, edge.B
	if rng:NextNumber() < 0.5 then
		from, to = to, from
	end
	driver.Lane = rng:NextInteger(1, 2)
	CarDriver.PlaceOnEdge(driver, from, to, rng:NextNumber(0.1, 0.9))
end

local function spawnCar(): Car
	local kind = KINDS[rng:NextInteger(1, #KINDS)]
	local color = CarModel.CivilianColors[rng:NextInteger(1, #CarModel.CivilianColors)]
	-- (the bus and the courier's van keep their livery)
	local fleet = kind == "Bus" or kind == "BoxVan"
	local model = CarModel.Build(kind, if fleet then nil else { Color = color })
	model.Name = "Traffic"
	local edge = pickRoad() :: Layout.Edge
	local driver = CarDriver.new(model, kind, CFrame.new(Layout.Nodes[edge.A].Position), rng)
	model.Parent = vehicles
	CarDriver.Claim(driver)
	driver.TopSpeed = Config.Traffic.Speed + rng:NextNumber(-Config.Traffic.SpeedVariance, Config.Traffic.SpeedVariance)
	place(driver, edge)
	return { Driver = driver, StillFor = 0 }
end

-- A line's nodes in order round its loop (each next to the one before; the last next to the first)
function TrafficService.Route(corners: { { number } }): { number }
	local nodes = {}
	for _, c in corners do
		table.insert(nodes, Layout.NearestNode(Vector3.new(Layout.Line(c[1]), Layout.ROAD_Y, Layout.Line(c[2]))))
	end
	local route = {}
	for k = 1, #nodes do
		local path = Layout.Path(nodes[k], nodes[k % #nodes + 1])
		for i = 1, #path - 1 do
			table.insert(route, path[i])
		end
	end
	return route
end

-- The shelters buses pull up at (where each one stands)
local function shelters(): { Vector3 }
	local list = {}
	local city = Workspace:FindFirstChild("City")
	local furniture = city and city:FindFirstChild("Furniture")
	if furniture then
		for _, model in furniture:GetChildren() do
			local roof = model.Name == "BusStop" and model:FindFirstChild("Roof")
			if roof and roof:IsA("BasePart") then
				table.insert(list, roof.CFrame.Position)
			end
		end
	end
	return list
end

local function spawnBus(route: { number }, stops: { Vector3 }): Car
	local model = CarModel.Build("Bus")
	model.Name = "Traffic"
	local driver = CarDriver.new(model, "Bus", CFrame.new(Layout.Nodes[route[1]].Position), rng)
	model.Parent = vehicles
	CarDriver.Claim(driver)
	driver.TopSpeed = Config.Traffic.Speed * 0.8 -- a bus takes its time
	driver.Lane = 9 -- (the kerb lane, whatever the road)
	driver.Route = route
	driver.Stops = stops
	CarDriver.PlaceOnRoute(driver, rng:NextInteger(1, #route), rng:NextNumber(0.1, 0.9))
	return { Driver = driver, StillFor = 0 }
end

-- A place on a bus's line between NEAR_MIN and NEAR_MAX from `p` (nil if the line doesn't pass near)
local function routeNear(route: { number }, p: Vector3): number?
	local options = {}
	for i, nodeId in route do
		local at = Layout.Nodes[nodeId].Position
		local d = Vector3.new(at.X - p.X, 0, at.Z - p.Z).Magnitude
		if d > NEAR_MIN and d < NEAR_MAX then
			table.insert(options, i)
		end
	end
	return if #options > 0 then options[rng:NextInteger(1, #options)] else nil
end

-- Cars far from everyone go to a road near someone (a player picked in turn)
local turn = 0
local function gather(people: { Vector3 })
	if #people == 0 then
		return
	end
	for _, car in cars do
		local driver = car.Driver
		local nearest = math.huge
		for _, p in people do
			nearest = math.min(nearest, Vector3.new(p.X - driver.Position.X, 0, p.Z - driver.Position.Z).Magnitude)
		end
		if nearest > KEEP then
			turn = turn % #people + 1
			local route = driver.Route
			if route then
				local index = routeNear(route, people[turn])
				if index then
					CarDriver.PlaceOnRoute(driver, index, rng:NextNumber(0.1, 0.9))
					car.StillFor = 0
				end
			else
				local edge = pickRoad(people[turn])
				if edge then
					place(driver, edge)
					car.StillFor = 0
				end
			end
		end
	end
end

-- The buses' drivers (for checks)
function TrafficService.Buses(): { CarDriver.Driver }
	local list = {}
	for _, car in cars do
		if car.Driver.Route then
			table.insert(list, car.Driver)
		end
	end
	return list
end

function TrafficService.Init()
	local existing = Workspace:FindFirstChild("Vehicles")
	if existing and existing:IsA("Folder") then
		vehicles = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Vehicles"
		created.Parent = Workspace
		vehicles = created
	end
	for _, edge in Layout.Edges do
		if edge.Length > 60 then
			table.insert(roads, edge)
		end
	end
	local stops = shelters()
	for _, line in TrafficService.LINES do
		local route = TrafficService.Route(line.Corners)
		if #route >= 3 then
			table.insert(cars, spawnBus(route, stops))
		end
	end
	for _ = #cars + 1, Config.Traffic.CarCount do
		table.insert(cars, spawnCar())
	end
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		local people: { Vector3 } = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				table.insert(people, root.Position)
			end
		end
		for _, car in cars do
			local driver = car.Driver
			CarDriver.StepFor(driver, dt, people, people)
			-- a car that hasn't moved for a minute (jammed) goes somewhere else
			if math.abs(driver.Speed) < 0.3 then
				car.StillFor += dt
			else
				car.StillFor = 0
			end
			if car.StillFor > 60 then
				car.StillFor = 0
				local route = driver.Route
				if route then
					CarDriver.PlaceOnRoute(driver, rng:NextInteger(1, #route), 0.5)
				else
					local edge = pickRoad(if #people > 0 then people[rng:NextInteger(1, #people)] else nil) or pickRoad()
					if edge then
						place(driver, edge)
					end
				end
			end
		end
		sinceCheck += dt
		if sinceCheck >= CHECK_EVERY then
			sinceCheck = 0
			gather(people)
		end
	end)
end

return TrafficService
