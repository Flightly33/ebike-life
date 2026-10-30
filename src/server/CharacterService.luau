--[[
	CharacterService: prepares characters for riding. Current R15 avatars are jointed with
	AnimationConstraints; made kinematic, they follow the bike rigidly when the client moves it (and
	the procedural rider pose drives them like Motor6Ds).

	Every character is also scaled to one height (Config.Avatar.Height) once its appearance has
	loaded. Roblox avatars run from ~4.5 to ~7.5 studs (body type, height scale, bundles) and the
	city is sized for one person: a tall avatar looked bigger than the bus shelters and the cars,
	and its bike (fitted to its legs) was bigger too.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local CharacterService = {}

local SCALES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }

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

-- Head top to feet from the body parts (accessories left out), as the character stands
local function bodyHeight(character: Model): number?
	local top, bottom = -math.huge, math.huge
	for _, d in character:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local cf, s = d.CFrame, d.Size
			local half = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
			top = math.max(top, cf.Position.Y + half)
			bottom = math.min(bottom, cf.Position.Y - half)
		end
	end
	return if top > bottom then top - bottom else nil
end

-- Scales the whole body (head, width and depth too, so it keeps its look) to Config.Avatar.Height:
-- an R15 avatar through its Humanoid's scale values (the Humanoid resizes it and keeps its hip
-- height), anything else with Model:ScaleTo
local function normalize(character: Model)
	local target = Config.Avatar.Height
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local before = bodyHeight(character)
	if not humanoid or not before or target <= 0 then
		return
	end
	for _ = 1, 3 do
		local height = bodyHeight(character)
		if not height or math.abs(height / target - 1) < 0.02 then
			break
		end
		local k = target / height
		local values: { NumberValue } = {}
		for _, name in SCALES do
			local value = humanoid:FindFirstChild(name)
			if value and value:IsA("NumberValue") then
				table.insert(values, value)
			end
		end
		local resized = false
		if humanoid.RigType == Enum.HumanoidRigType.R15 and #values == #SCALES then
			for _, value in values do
				value.Value *= k
			end
			-- the Humanoid resizes the body a moment later
			local since = os.clock()
			repeat
				task.wait()
				resized = math.abs((bodyHeight(character) or height) - height) > 0.01
			until resized or os.clock() - since > 1
			if not resized then
				for _, value in values do
					value.Value /= k
				end
			end
		end
		if not resized then
			local hip = humanoid.HipHeight
			character:ScaleTo(character:GetScale() * k)
			if humanoid.HipHeight == hip then
				humanoid.HipHeight = hip * k
			end
		end
	end
	local after = bodyHeight(character) or before
	character:SetAttribute("BodyHeight", after)
	print(string.format("[CharacterService] %s: avatar %.2f studs tall, scaled to %.2f", character.Name, before, after))
end

function CharacterService.Init()
	local function hook(player: Player)
		player.CharacterAdded:Connect(prepare)
		player.CharacterAppearanceLoaded:Connect(normalize)
		local character = player.Character
		if character then
			prepare(character)
			local ok, loaded = pcall(function()
				return player:HasAppearanceLoaded()
			end)
			if ok and loaded then
				task.spawn(normalize, character)
			end
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return CharacterService
