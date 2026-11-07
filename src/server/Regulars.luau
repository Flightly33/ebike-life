--[[
	Regulars: the four who give the story missions, standing where you'd find them: Nina outside
	Flighty Mechanics, Marco at his courier stand on the Plaza, Jet by the Jump Park and Officer Reyes
	at the police station. Part-built R6 figures (Officer's rig, dressed for each), anchored, with a
	name over their heads and a Talk prompt (TalkPrompt, its Giver attribute) that the client turns
	into their line and the phone's Missions list; the client also lights a "!" over a regular with
	a mission ready for you (UI/init).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Layout = require(Shared.City.Layout)
local Missions = require(Shared.Missions)

local Officer = require(script.Parent.Officer)

local Regulars = {}

type Outfit = { Torso: Color3, Arms: Color3, Legs: Color3, Cap: Color3?, Helmet: Color3?, Bag: Color3? }

-- where each stands: a place, a step off it (studs), and which way they face
type Spot = { Giver: string, Place: string, Offset: Vector3, Outfit: Outfit }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Regulars.Spots = {
	{ Giver = "Nina", Place = "Spawn", Offset = Vector3.new(16, 0, 4), Outfit = { Torso = rgb(60, 62, 70), Arms = rgb(60, 62, 70), Legs = rgb(240, 120, 30), Cap = rgb(240, 120, 30) } },
	{ Giver = "Marco", Place = "Plaza", Offset = Vector3.new(14, 0, 0), Outfit = { Torso = rgb(245, 196, 30), Arms = rgb(24, 24, 28), Legs = rgb(40, 60, 110), Cap = rgb(245, 196, 30), Bag = rgb(24, 24, 28) } },
	{ Giver = "Jet", Place = "JumpPark", Offset = Vector3.new(-14, 0, -6), Outfit = { Torso = rgb(20, 20, 24), Arms = rgb(20, 20, 24), Legs = rgb(200, 30, 40), Helmet = rgb(255, 120, 20) } },
	{ Giver = "Reyes", Place = "Police", Offset = Vector3.new(12, 0, 10), Outfit = { Torso = rgb(28, 40, 80), Arms = rgb(28, 40, 80), Legs = rgb(20, 22, 30) } },
} :: { Spot }

-- the police kit Officer dresses a rig in (the others don't wear it)
local POLICE_KIT = { "Badge", "CapBadge", "NameTag", "Radio", "Antenna", "Holster", "Cuffs", "Buckle", "Tie", "Patch", "Stripe", "Brim", "Cap" }

local function ground(at: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, name in { "Vehicles", "Bikes", "Officers", "Regulars" } do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(at + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else at
end

local function dress(model: Model, giver: string, outfit: Outfit)
	if giver ~= "Reyes" then
		for _, name in POLICE_KIT do
			for _, d in model:GetChildren() do
				if d.Name == name then
					d:Destroy()
				end
			end
		end
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") then
				if d.Name == "Torso" then
					d.Color = outfit.Torso
				elseif d.Name == "Left Arm" or d.Name == "Right Arm" then
					d.Color = outfit.Arms
				elseif d.Name == "Left Leg" or d.Name == "Right Leg" then
					d.Color = outfit.Legs
				end
			end
		end
	end
	local head = model:FindFirstChild("Head") :: BasePart?
	local torso = model:FindFirstChild("Torso") :: BasePart?
	local function piece(name: string, size: Vector3, color: Color3, to: BasePart, offset: CFrame, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Massless = true
		p.CFrame = to.CFrame * offset
		local w = Instance.new("WeldConstraint")
		w.Part0 = to
		w.Part1 = p
		w.Parent = p
		p.Parent = model
	end
	if head and outfit.Cap then
		piece("RegularCap", Vector3.new(1.3, 0.35, 1.3), outfit.Cap, head, CFrame.new(0, 0.65, 0))
		piece("RegularBrim", Vector3.new(1.2, 0.1, 0.55), outfit.Cap, head, CFrame.new(0, 0.5, -0.75))
	end
	if head and outfit.Helmet then
		piece("RegularHelmet", Vector3.new(1.75, 1.75, 1.75), outfit.Helmet, head, CFrame.new(0, 0.1, 0.05), Enum.PartType.Ball)
		piece("RegularGoggles", Vector3.new(1.3, 0.3, 0.12), Color3.fromRGB(18, 18, 22), head, CFrame.new(0, 0.2, -0.82))
	end
	if torso and outfit.Bag then
		piece("RegularBag", Vector3.new(1.4, 1.1, 0.5), outfit.Bag, torso, CFrame.new(0.2, -0.3, 0.75))
		piece("RegularStrap", Vector3.new(0.2, 2.4, 1.1), outfit.Bag, torso, CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(35)))
	end
end

local function nameTag(model: Model, head: BasePart, giver: string)
	local info = Missions.Givers[giver]
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(220, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 26)
	label.Position = UDim2.fromOffset(0, 30)
	label.Text = if info then info.Icon .. " " .. info.Title else giver
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = gui
	-- the "!" the client lights when this regular has a mission ready for you
	local mark = Instance.new("TextLabel")
	mark.Name = "Ready"
	mark.BackgroundTransparency = 1
	mark.Size = UDim2.new(1, 0, 0, 30)
	mark.Text = "❗"
	mark.TextScaled = true
	mark.Visible = false
	mark.Parent = gui
	gui.Parent = model
end

function Regulars.Init()
	task.spawn(function()
		Workspace:WaitForChild("City", 600)
		local folder = Instance.new("Folder")
		folder.Name = "Regulars"
		for i, spot in Regulars.Spots do
			local place = (Layout.Places :: any)[spot.Place] :: Vector3?
			if not place then
				continue
			end
			local foot = ground(place + spot.Offset)
			-- facing the place they're beside
			local model = Officer.new(foot, place - foot, i * 7)
			model.Name = spot.Giver
			model:SetAttribute("Kind", "Regular")
			model:SetAttribute("Giver", spot.Giver)
			dress(model, spot.Giver, spot.Outfit)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = d.Name == "HumanoidRootPart"
				end
			end
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 0
			end
			local head = model:FindFirstChild("Head") :: BasePart?
			local torso = model:FindFirstChild("Torso") :: BasePart?
			if head then
				nameTag(model, head, spot.Giver)
			end
			if torso then
				local info = Missions.Givers[spot.Giver]
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "TalkPrompt"
				prompt.ActionText = "Talk"
				prompt.ObjectText = if info then info.Title else spot.Giver
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 14
				prompt.RequiresLineOfSight = false
				prompt:SetAttribute("Giver", spot.Giver)
				prompt.Parent = torso
			end
			model.Parent = folder
		end
		folder.Parent = Workspace
	end)
end

return Regulars
