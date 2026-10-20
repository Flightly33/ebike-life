--[[
	CityService: makes sure the city is in the world (the baked map/City.rbxm, or a fresh build if
	it's missing) and runs its charging stations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Builder = require(Shared.City.Builder)
local Remotes = require(Shared.Remotes)

local BikeService = require(script.Parent.BikeService)

local CityService = {}

function CityService.Init()
	local city = Workspace:FindFirstChild("City")
	if not city then
		warn("[CityService] map/City.rbxm missing from the place; building the city at runtime")
		city = Builder.Build()
		city.Parent = Workspace
	end
	local cityModel = city :: Instance
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
