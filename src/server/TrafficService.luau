--[[
	TrafficService: civilian cars cruising the city's roads. They stop at red lights and behind
	other cars and people, which makes running a red light near a cop (or riding into traffic) a
	real risk.

	Cars start spread over every road in the map by its length (every grid, the turnpike, the
	freeways and causeways, the country roads), and a car left far from every player is moved to a
	road a few blocks from one (out of sight), so there's traffic wherever anyone rides.
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
	local kind = CarModel.CivilianKinds[rng:NextInteger(1, #CarModel.CivilianKinds)]
	local color = CarModel.CivilianColors[rng:NextInteger(1, #CarModel.CivilianColors)]
	local model = CarModel.Build(kind, { Color = color })
	model.Name = "Traffic"
	local edge = pickRoad() :: Layout.Edge
	local driver = CarDriver.new(model, kind, CFrame.new(Layout.Nodes[edge.A].Position), rng)
	model.Parent = vehicles
	CarDriver.Claim(driver)
	driver.TopSpeed = Config.Traffic.Speed + rng:NextNumber(-Config.Traffic.SpeedVariance, Config.Traffic.SpeedVariance)
	place(driver, edge)
	return { Driver = driver, StillFor = 0 }
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
			local edge = pickRoad(people[turn])
			if edge then
				place(driver, edge)
				car.StillFor = 0
			end
		end
	end
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
	for _ = 1, Config.Traffic.CarCount do
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
			CarDriver.Step(driver, dt, people)
			-- a car that hasn't moved for a minute (jammed) goes somewhere else
			if math.abs(driver.Speed) < 0.3 then
				car.StillFor += dt
			else
				car.StillFor = 0
			end
			if car.StillFor > 60 then
				car.StillFor = 0
				local edge = pickRoad(if #people > 0 then people[rng:NextInteger(1, #people)] else nil) or pickRoad()
				if edge then
					place(driver, edge)
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
