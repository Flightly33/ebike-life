--[[
	CityService: makes sure the city is in the world (the baked map/City.rbxm, or a fresh build if
	it's missing), fills Biscayne Bay, the ocean and the lakes with Terrain water and the open land
	with Terrain grass and marsh (Terrain isn't part of the baked model), swaps its showroom bikes
	and parked cars for the Blender meshes when those are imported, and runs its charging stations.
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

local CHUNK = 512
local terrainWork = 0
local function breathe()
	terrainWork += 1
	if terrainWork % 8 == 0 then
		task.wait()
	end
end

-- Fill a rect (x/z) between two heights in CHUNK-sized pieces
local function fillRect(terrain: Terrain, rect: Layout.Rect, bottom: number, top: number, material: Enum.Material)
	for x = rect.MinX, rect.MaxX - 0.01, CHUNK do
		for z = rect.MinZ, rect.MaxZ - 0.01, CHUNK do
			local x1, z1 = math.min(x + CHUNK, rect.MaxX), math.min(z + CHUNK, rect.MaxZ)
			terrain:FillBlock(CFrame.new((x + x1) / 2, (top + bottom) / 2, (z + z1) / 2), Vector3.new(x1 - x, top - bottom, z1 - z), material)
			breathe()
		end
	end
end

-- Biscayne Bay and the ocean: Terrain water from the bay floor up to Layout.WATER_Y over every
-- Layout.Water rect, turquoise and clear like the real bay; the lakes from their beds
local function fillWater(terrain: Terrain)
	terrain.WaterColor = Color3.fromRGB(26, 150, 160)
	terrain.WaterTransparency = 0.8
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	local lakes: { [Layout.Rect]: boolean } = {}
	for _, lake in Layout.Lakes do
		lakes[lake] = true
	end
	for _, rect in Layout.Water do
		fillRect(terrain, rect, if lakes[rect] then Layout.LAKE_BED_Y else Layout.SEABED_Y, Layout.WATER_Y, Enum.Material.Water)
	end
end

-- The colours of the land: lush subtropical grass, the darker leafy verges, Everglades mud
local TERRAIN_COLORS: { [Enum.Material]: Color3 } = {
	[Enum.Material.Grass] = Color3.fromRGB(92, 134, 58),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(96, 128, 60),
	[Enum.Material.Mud] = Color3.fromRGB(92, 80, 60),
	[Enum.Material.Ground] = Color3.fromRGB(124, 108, 82),
}

-- The open land: Terrain grass (with blades) over the hidden OpenGround colliders, flush with
-- their tops (y = 0), two voxels deep. The Everglades are sawgrass (grass blades) with patches of
-- mud and leafy grass. Under anything lying on the open ground (roads, pads, greens, car parks,
-- hills) the terrain is leafy grass instead, which has no blades to poke through the part. The
-- riding physics stays on the parts, so the terrain is only looks.
local function fillLand(terrain: Terrain, city: Instance)
	for material, color in TERRAIN_COLORS do
		terrain:SetMaterialColor(material, color)
	end
	local depth = 8
	for _, g in Layout.OpenGround do
		fillRect(terrain, g, -depth, 0, Enum.Material.Grass)
	end
	-- the marsh's patchwork (seeded, so every server has the same Everglades)
	local rng = Random.new(2026)
	for _, g in Layout.OpenGround do
		if g.Kind ~= "Marsh" then
			continue
		end
		local area = (g.MaxX - g.MinX) * (g.MaxZ - g.MinZ)
		for _ = 1, math.floor(area / 9000) do
			local x, z = rng:NextNumber(g.MinX, g.MaxX), rng:NextNumber(g.MinZ, g.MaxZ)
			local material = if rng:NextNumber() < 0.55 then Enum.Material.Mud else Enum.Material.LeafyGrass
			terrain:FillCylinder(CFrame.new(x, -depth / 2, z), depth, rng:NextNumber(10, 34), material)
			breathe()
		end
	end
	-- bare (bladeless) ground under the parts lying on the open land, then hide the colliders
	local open = city:FindFirstChild("Ground")
	open = open and open:FindFirstChild("Open")
	for _, d in city:GetDescendants() do
		if not d:IsA("BasePart") or d.Parent == open or not d.CanCollide or d.Transparency >= 1 then
			continue
		end
		local cf, size = d.CFrame, d.Size
		local function extent(axis: number): number
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local pick = function(v: Vector3): number
				return math.abs(if axis == 1 then v.X elseif axis == 2 then v.Y else v.Z)
			end
			return (pick(r) * size.X + pick(u) * size.Y + pick(l) * size.Z) / 2
		end
		local half = Vector3.new(extent(1), extent(2), extent(3))
		local p = cf.Position
		if p.Y - half.Y > 1 or p.Y + half.Y < -1 or half.X < 3 or half.Z < 3 then
			continue
		end
		if Layout.IsBuiltUp(p.X, p.Z) or Layout.InWater(p.X, p.Z) then
			continue
		end
		local round = d:IsA("Part") and (d :: Part).Shape ~= Enum.PartType.Block
		if math.abs(cf.UpVector.Y) > 0.9 and not round then
			-- a flat piece (a road, a pad, a fairway): its own footprint, turned with it
			local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
			local yaw = if look.Magnitude > 1e-3 then CFrame.lookAt(Vector3.zero, look) else CFrame.identity
			terrain:FillBlock(CFrame.new(p.X, -depth / 2, p.Z) * yaw, Vector3.new(size.X + 2, depth, size.Z + 2), Enum.Material.LeafyGrass)
		else
			-- anything else (a hill side, a green, a post): its box on the ground
			terrain:FillBlock(CFrame.new(p.X, -depth / 2, p.Z), Vector3.new(half.X * 2 + 2, depth, half.Z * 2 + 2), Enum.Material.LeafyGrass)
		end
		breathe()
	end
	if open then
		for _, tile in open:GetChildren() do
			if tile:IsA("BasePart") then
				tile.Transparency = 1
				tile.CastShadow = false
			end
		end
	end
end

local function fillTerrain(city: Instance)
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if not terrain then
		return
	end
	local function try(what: string, f: () -> ())
		local ok, err = pcall(function()
			f()
		end)
		if not ok then
			warn(string.format("[CityService] couldn't %s: %s", what, tostring(err)))
		end
	end
	try("fill the bay with water", function()
		fillWater(terrain)
	end)
	try("lay the terrain grass", function()
		fillLand(terrain, city)
	end)
	Workspace:SetAttribute("TerrainReady", true)
end

function CityService.Init()
	-- the realism pack's PBR materials, if it's been imported (Shared/Materials)
	local variants = Materials.Apply()
	if variants > 0 then
		print(string.format("[CityService] %d PBR materials from the realism pack", variants))
	end
	local city = Workspace:FindFirstChild("City")
	if not city then
		warn("[CityService] map/City.rbxm missing from the place; building the city at runtime")
		city = Builder.Build()
		city.Parent = Workspace
	end
	local cityModel = city :: Instance
	task.spawn(fillTerrain, cityModel)
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
