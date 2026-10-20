--[[
	CharacterService: prepares characters for riding. Current R15 avatars are jointed with
	AnimationConstraints; made kinematic, they follow the bike rigidly when the client moves it (and
	the procedural rider pose drives them like Motor6Ds).
]]

local Players = game:GetService("Players")

local CharacterService = {}

local function prepare(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			d.IsKinematic = true
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("AnimationConstraint") then
			d.IsKinematic = true
		end
	end)
end

function CharacterService.Init()
	local function hook(player: Player)
		player.CharacterAdded:Connect(prepare)
		if player.Character then
			prepare(player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return CharacterService
