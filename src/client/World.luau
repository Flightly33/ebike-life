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

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true

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
end

World.Physics = {
	Down = function(origin: Vector3, length: number): BikePhysics.Hit?
		local hit = Workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
		if not hit then
			return nil
		end
		local part = hit.Instance
		local kind = if part:IsA("BasePart") then surfaceOf(part) else "Road"
		if part:FindFirstAncestorWhichIsA("Model") and kindOf(part :: BasePart) ~= "Wall" then
			kind = "Car" -- riding on a car roof
		end
		return { Position = hit.Position, Normal = hit.Normal, Kind = kind }
	end,
	Sweep = function(frame: CFrame, size: Vector3, delta: Vector3): (number?, Vector3?, string?)
		local hit = Workspace:Blockcast(frame, size, delta, params)
		if not hit then
			return nil, nil, nil
		end
		local part = hit.Instance
		return hit.Distance, hit.Normal, if part:IsA("BasePart") then kindOf(part) else "Wall"
	end,
} :: BikePhysics.World

function World.Params(): RaycastParams
	return params
end

function World.Init()
	World.Refresh()
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
