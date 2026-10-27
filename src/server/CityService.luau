--[[
	CityService: makes sure the city is in the world (the baked map/City.rbxm, or a fresh build if
	it's missing), fills Biscayne Bay and the ocean with Terrain water (Terrain isn't part of the
	baked model), swaps its showroom bikes and parked cars for the Blender meshes when those are
	imported, and runs its charging stations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Builder = require(Shared.City.Builder)
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)
local Bikes = require(Shared.Bikes)
local PartKit = require(Shared.PartKit)
local BikeModel = require(Shared.Models.BikeModel)
local CarModel = require(Shared.Models.CarModel)
local MeshKit = require(Shared.Models.MeshKit)
local CityKit = require(Shared.Models.CityKit)
local Materials = require(Shared.Materials)

local BikeService = require(script.Parent.BikeService)

local CityService = {}

-- The baked city holds part-built showroom bikes and parked cruisers. When the Blender meshes
-- are imported, rebuild those in place so they match the bikes and cars on the road.
local function swapInMeshes(city: Instance)
	for _, model in city:GetDescendants() do
		if not model:IsA("Model") or not model.PrimaryPart then
			continue
		end
		local bikeId = model:GetAttribute("BikeId")
		local carKind = model:GetAttribute("CarKind")
		local fresh: Model? = nil
		if type(bikeId) == "string" and MeshKit.Has(bikeId) then
			local bike = Bikes.Get(bikeId)
			if bike then
				local paint = if model:GetAttribute("Gold") then { Frame = "gold", Accent = "gold", Rims = "gold" } else nil
				fresh = BikeModel.Build(bike, paint, { Static = true })
			end
		elseif type(carKind) == "string" and MeshKit.Has("Car_" .. carKind) then
			fresh = CarModel.Build(carKind, { Static = true })
		end
		if fresh then
			local placed = fresh :: Model
			PartKit.PlaceStatic(placed, model.PrimaryPart.CFrame)
			placed.Name = model.Name
			for name, value in model:GetAttributes() do
				placed:SetAttribute(name, value)
			end
			placed.Parent = model.Parent
			model:Destroy()
		end
	end
end

-- Biscayne Bay and the ocean: Terrain water from the bay floor up to Layout.WATER_Y over every
-- Layout.Water rect, a chunk at a time, turquoise and clear like the real bay
local WATER_CHUNK = 512
local function fillWater()
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local ok, err = pcall(function()
		terrain.WaterColor = Color3.fromRGB(26, 150, 160)
		terrain.WaterTransparency = 0.8
		terrain.WaterReflectance = 0.6
		terrain.WaterWaveSize = 0.12
		terrain.WaterWaveSpeed = 8
		local top, bottom = Layout.WATER_Y, Layout.SEABED_Y
		local filled = 0
		for _, rect in Layout.Water do
			for x = rect.MinX, rect.MaxX - 1, WATER_CHUNK do
				for z = rect.MinZ, rect.MaxZ - 1, WATER_CHUNK do
					local x1, z1 = math.min(x + WATER_CHUNK, rect.MaxX), math.min(z + WATER_CHUNK, rect.MaxZ)
					terrain:FillBlock(CFrame.new((x + x1) / 2, (top + bottom) / 2, (z + z1) / 2), Vector3.new(x1 - x, top - bottom, z1 - z), Enum.Material.Water)
					filled += 1
					if filled % 8 == 0 then
						task.wait()
					end
				end
			end
		end
	end)
	if not ok then
		warn("[CityService] couldn't fill the bay with water: " .. tostring(err))
	end
end

function CityService.Init()
	-- the owner's PBR texture sets, if any (AssetIds.Materials)
	local variants = Materials.Apply()
	if variants > 0 then
		print(string.format("[CityService] %d custom PBR materials applied", variants))
	end
	local city = Workspace:FindFirstChild("City")
	if not city then
		warn("[CityService] map/City.rbxm missing from the place; building the city at runtime")
		city = Builder.Build()
		city.Parent = Workspace
	end
	local cityModel = city :: Instance
	task.spawn(fillWater)
	swapInMeshes(cityModel)
	-- the detailed city kit (windows, trees, lamps) in place of their part-built placeholders, a
	-- few hundred a frame so start-up doesn't stall
	task.spawn(function()
		local n = 0
		local placed = CityKit.Apply(cityModel, function()
			n += 1
			if n % 250 == 0 then
				task.wait()
			end
		end)
		if placed > 0 then
			print(string.format("[CityKit] detailed %d windows, trees and lamps", placed))
		end
	end)
	for _, d in cityModel:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.Name == "ChargerPrompt" then
			local prompt = d
			prompt.Triggered:Connect(function(player: Player)
				local part = prompt.Parent
				local position = if part and part:IsA("BasePart") then part.Position else Vector3.zero
				if BikeService.Charge(player, position) then
					Remotes.Event("Notify"):FireClient(player, "Info", "⚡ Charging...")
				else
					Remotes.Event("Notify"):FireClient(player, "Error", "Bring your bike closer to the charger")
				end
			end)
		end
	end
end

return CityService
