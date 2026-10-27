--[[
	World: the real-world side of Shared/BikePhysics. Ground rays and body sweeps against the place,
	ignoring every bike and every character, and what kind of surface a hit was.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BikePhysics = require(Shared.BikePhysics)

local World = {}

local Config = require(Shared.Config)
local loopPlates: { [BasePart]: boolean } = {}
local rideable: (BasePart) -> boolean

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true
-- the ground rays find the water's surface (Terrain water: the bay and the ocean); the body
-- sweeps go through it
local sweepParams = RaycastParams.new()
sweepParams.FilterType = Enum.RaycastFilterType.Exclude
sweepParams.RespectCanCollide = true
sweepParams.IgnoreWater = true

local MATERIALS: { [Enum.Material]: string } = {
	[Enum.Material.Asphalt] = "Road",
	[Enum.Material.Pavement] = "Sidewalk",
	[Enum.Material.Concrete] = "Sidewalk",
	[Enum.Material.Cobblestone] = "Sidewalk",
	[Enum.Material.Brick] = "Sidewalk",
	[Enum.Material.Marble] = "Sidewalk",
	[Enum.Material.Granite] = "Sidewalk",
	[Enum.Material.Slate] = "Sidewalk",
	[Enum.Material.Grass] = "Grass",
	[Enum.Material.LeafyGrass] = "Grass",
	[Enum.Material.Ground] = "Dirt",
	[Enum.Material.Mud] = "Mud",
	[Enum.Material.Sand] = "Sand",
	[Enum.Material.WoodPlanks] = "Ramp",
	[Enum.Material.Wood] = "Ramp",
	[Enum.Material.DiamondPlate] = "Ramp",
	[Enum.Material.Metal] = "Ramp",
}

local function surfaceOf(part: BasePart): string
	local tagged = part:GetAttribute("Surface")
	if type(tagged) == "string" then
		return tagged
	end
	return MATERIALS[part.Material] or "Road"
end
World.SurfaceOf = surfaceOf

-- What a sweep hit: "Cop" / "Car" for vehicles, "Wall" for everything else
local function kindOf(part: BasePart): string
	-- small loose street furniture (bins, bollards, benches, signs, meters) is a "Prop"
	local size = part.Size
	if math.max(size.X, size.Y, size.Z) < 7 and part:GetAttribute("Surface") == nil and not part:FindFirstAncestor("Vehicles") then
		local owner = part:FindFirstAncestorWhichIsA("Model")
		if not (owner and owner:GetAttribute("Kind")) then
			return "Prop"
		end
	end
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		local kind = model:GetAttribute("Kind")
		if type(kind) == "string" then
			return kind
		end
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model")
	end
	return "Wall"
end

-- Ramps, kickers, loop sections, hillsides and natural ground: a tilted part (its most upward face
-- slopes) or grass, dirt, sand or mud. Hitting their side edge isn't hitting a wall.
local NATURAL = { [Enum.Material.Grass] = true, [Enum.Material.LeafyGrass] = true, [Enum.Material.Ground] = true, [Enum.Material.Sand] = true, [Enum.Material.Mud] = true }
rideable = function(part: BasePart): boolean
	if NATURAL[part.Material] or part:GetAttribute("Surface") == "Ramp" then
		return true
	end
	if part:IsA("Part") and part.Shape ~= Enum.PartType.Block then
		return false -- posts, poles, balls
	end
	local cf = part.CFrame
	local top = math.max(math.abs(cf.RightVector.Y), math.abs(cf.UpVector.Y), math.abs(cf.LookVector.Y))
	return top > 0.3 and top < 0.995
end

function World.Refresh()
	local list: { Instance } = {}
	local bikes = Workspace:FindFirstChild("Bikes")
	if bikes then
		table.insert(list, bikes)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	params.FilterDescendantsInstances = list
	sweepParams.FilterDescendantsInstances = list
end

World.Physics = {
	Down = function(origin: Vector3, length: number): BikePhysics.Hit?
		local hit = Workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
		if not hit then
			return nil
		end
		if hit.Material == Enum.Material.Water then
			return { Position = hit.Position, Normal = Vector3.yAxis, Kind = "Water" }
		end
		local part = hit.Instance
		local kind = if part:IsA("BasePart") then surfaceOf(part) else "Road"
		if part:FindFirstAncestorWhichIsA("Model") and kindOf(part :: BasePart) ~= "Wall" then
			kind = "Car" -- riding on a car roof
		end
		return { Position = hit.Position, Normal = hit.Normal, Kind = kind }
	end,
	Sweep = function(frame: CFrame, size: Vector3, delta: Vector3): (number?, Vector3?, string?)
		local hit = Workspace:Blockcast(frame, size, delta, sweepParams)
		if not hit then
			return nil, nil, nil
		end
		local part = hit.Instance
		if part:IsA("BasePart") and rideable(part) then
			-- the edge of something you ride over: never a wall (the ground rays carry the bike)
			return hit.Distance, Vector3.yAxis, "Slope"
		end
		return hit.Distance, hit.Normal, if part:IsA("BasePart") then kindOf(part) else "Wall"
	end,
	-- Loop entries are plates named "LoopEntry" (LookVector along the loop, top face on the riding
	-- surface) with LoopRadius / LoopShift attributes in the city's design units
	Loop = function(position: Vector3, dir: Vector3): BikePhysics.Loop?
		for plate in loopPlates do
			if not plate.Parent then
				loopPlates[plate] = nil
				continue
			end
			local cf = plate.CFrame
			local localPos = cf:PointToObjectSpace(position)
			local half = plate.Size / 2
			if math.abs(localPos.X) < half.X and math.abs(localPos.Z) < half.Z and math.abs(localPos.Y - half.Y) < 2 and dir:Dot(cf.LookVector) > 0.6 then
				local radius = plate:GetAttribute("LoopRadius")
				local shift = plate:GetAttribute("LoopShift")
				if type(radius) == "number" and type(shift) == "number" then
					local entry = cf * CFrame.new(localPos.X, half.Y, localPos.Z)
					return { Entry = entry, Radius = radius * Config.WORLD_SCALE, Shift = shift * Config.WORLD_SCALE }
				end
			end
		end
		return nil
	end,
} :: BikePhysics.World

function World.Params(): RaycastParams
	return params
end

function World.Init()
	World.Refresh()
	-- loop entry plates (they stream in and out with the city)
	local function watchPlate(d: Instance)
		if d:IsA("BasePart") and d.Name == "LoopEntry" then
			loopPlates[d] = true
		end
	end
	for _, d in Workspace:GetDescendants() do
		watchPlate(d)
	end
	Workspace.DescendantAdded:Connect(watchPlate)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(World.Refresh)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function()
		task.defer(World.Refresh)
	end)
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Bikes" then
			World.Refresh()
		end
	end)
end

return World
