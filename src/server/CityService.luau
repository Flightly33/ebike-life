--[[
	CityService: makes sure the city is in the world (the baked map/City.rbxm, or a fresh build if
	it's missing), swaps its showroom bikes and parked cars for the Blender meshes when those are
	imported, and runs its charging stations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Builder = require(Shared.City.Builder)
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
