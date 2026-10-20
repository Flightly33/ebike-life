--[[
	TrafficService: civilian cars cruising the city and the ring road. They stop at red lights and
	behind other cars and people, which makes running a red light near a cop (or riding into traffic)
	a real risk.
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

local function randomStart(): (number, number)
	-- most traffic in the grid, some on the ring road
	if rng:NextNumber() < 0.75 then
		local i, j = rng:NextInteger(0, Layout.GRID_COUNT - 1), rng:NextInteger(0, Layout.GRID_COUNT - 1)
		local node = Layout.GridNode[i][j]
		local edges = Layout.Nodes[node].Edges
		return node, Layout.OtherEnd(Layout.Edges[edges[rng:NextInteger(1, #edges)]], node)
	end
	local ring = Layout.RingNodes
	local k = rng:NextInteger(1, #ring)
	return ring[k], ring[k % #ring + 1]
end

local function spawnCar(): Car
	local kind = CarModel.CivilianKinds[rng:NextInteger(1, #CarModel.CivilianKinds)]
	local color = CarModel.CivilianColors[rng:NextInteger(1, #CarModel.CivilianColors)]
	local model = CarModel.Build(kind, { Color = color })
	model.Name = "Traffic"
	local from, to = randomStart()
	local driver = CarDriver.new(model, kind, CFrame.new(Layout.Nodes[from].Position), rng)
	model.Parent = vehicles
	CarDriver.Claim(driver)
	driver.TopSpeed = Config.Traffic.Speed + rng:NextNumber(-Config.Traffic.SpeedVariance, Config.Traffic.SpeedVariance)
	driver.Lane = rng:NextInteger(1, 2)
	CarDriver.PlaceOnEdge(driver, from, to)
	return { Driver = driver, StillFor = 0 }
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
	for _ = 1, Config.Traffic.CarCount do
		table.insert(cars, spawnCar())
	end
	RunService.Heartbeat:Connect(function(dt)
		local people: { Vector3 } = {}
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				table.insert(people, root.Position)
			end
		end
		for index, car in cars do
			local driver = car.Driver
			CarDriver.Step(driver, dt, people)
			-- a car that hasn't moved for a minute (jammed) is replaced somewhere else
			if math.abs(driver.Speed) < 0.3 then
				car.StillFor += dt
			else
				car.StillFor = 0
			end
			if car.StillFor > 60 then
				CarDriver.Destroy(driver)
				cars[index] = spawnCar()
			end
		end
	end)
end

return TrafficService
