--[[
	Objective: the HUD for missions, delivery jobs, time trials and races (top left, where the HUD is
	free): the objective's title, the current step with a progress bar, the clock (counting down a
	time limit, or up in a race), the race position; a beacon in the world over the step's target with
	its distance; the mission giver's call when one starts; race lobbies' countdowns and results.

	Everything it shows comes from the player's Obj* attributes (ObjectiveService) and the Objective
	and Race remotes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Missions = require(Shared.Missions)
local Objectives = require(Shared.Objectives)
local Remotes = require(Shared.Remotes)

local Sound = require(script.Parent.Parent.Sound)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local Objective = {}

local New = Theme.New
local C = Theme.Colors

local KIND_COLORS: { [string]: Color3 } = {
	Mission = Color3.fromRGB(255, 196, 46),
	Job = Color3.fromRGB(90, 200, 255),
	Trial = Color3.fromRGB(180, 120, 255),
	Race = Color3.fromRGB(255, 90, 90),
}
local KIND_ICONS: { [string]: string } = { Mission = "⭐", Job = "📦", Trial = "⏱", Race = "🏁" }

local card: Frame
local accent: Frame
local titleLabel: TextLabel
local stepLabel: TextLabel
local clockLabel: TextLabel
local posLabel: TextLabel
local bar: Frame
local barFill: Frame
local lobbyLabel: TextLabel
local callCard: Frame
local callTitle: TextLabel
local callText: TextLabel
local beacon: Part? = nil
local beaconLabel: TextLabel? = nil
local lobby: { [string]: any }? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function makeBeacon()
	local part = Instance.new("Part")
	part.Name = "ObjectiveBeacon"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Neon
	part.Transparency = 0.55
	part.Size = Vector3.new(160, 5, 5)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(160, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 100000
	gui.Parent = part
	local label = Theme.Label({ Text = "", Size = UDim2.fromScale(1, 1), TextSize = 22, Stroke = 2.5, Parent = gui })
	beaconLabel = label
	part.Parent = Workspace
	beacon = part
end

local function showCall(giver: string?, text: string)
	local info = if giver then Missions.Givers[giver] else nil
	callTitle.Text = if info then string.format("%s  %s", info.Icon, info.Title) else "📱 Incoming"
	callText.Text = text
	callCard.Visible = true
	callCard.Position = UDim2.new(0.5, 0, 1, 40)
	TweenService:Create(callCard, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -96) }):Play()
	Sound.Play("Cash", nil, 1.4, 0.4)
	local shown = callText.Text
	task.delay(9, function()
		if callText.Text == shown then
			TweenService:Create(callCard, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 1, 140) }):Play()
		end
	end)
end

function Objective.Init(gui: ScreenGui)
	card = New("Frame", { Name = "Objective", BackgroundColor3 = Color3.fromRGB(22, 22, 25), BackgroundTransparency = 0.08, Size = UDim2.fromOffset(330, 92), Position = UDim2.fromOffset(12, 10), Visible = false, Parent = gui })
	Theme.Corner(card, 12)
	Theme.Stroke(card, Color3.fromRGB(10, 10, 12), 2)
	accent = New("Frame", { BackgroundColor3 = KIND_COLORS.Mission, Size = UDim2.new(0, 6, 1, -16), Position = UDim2.fromOffset(8, 8), Parent = card })
	Theme.Corner(accent, 3)
	titleLabel = Theme.Label({ Text = "", Size = UDim2.new(1, -110, 0, 24), Position = UDim2.fromOffset(22, 6), TextSize = 21, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = card })
	clockLabel = Theme.Label({ Text = "", Size = UDim2.fromOffset(90, 24), Position = UDim2.new(1, -10, 0, 6), AnchorPoint = Vector2.new(1, 0), TextSize = 21, Color = C.Gold, Align = Enum.TextXAlignment.Right, Stroke = 2, Parent = card })
	stepLabel = Theme.Label({ Text = "", Size = UDim2.new(1, -34, 0, 34), Position = UDim2.fromOffset(22, 32), TextSize = 15, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, Parent = card })
	bar = New("Frame", { BackgroundColor3 = Color3.fromRGB(46, 46, 52), Size = UDim2.new(1, -34, 0, 8), Position = UDim2.new(0, 22, 1, -16), Parent = card })
	Theme.Round(bar)
	barFill = New("Frame", { BackgroundColor3 = KIND_COLORS.Mission, Size = UDim2.fromScale(0, 1), Parent = bar })
	Theme.Round(barFill)
	posLabel = Theme.Label({ Text = "", Size = UDim2.fromOffset(120, 54), Position = UDim2.new(0, 12, 0, 108), TextSize = 50, Color = Color3.fromRGB(255, 255, 255), Align = Enum.TextXAlignment.Left, Stroke = 3, Parent = gui })
	posLabel.Visible = false
	lobbyLabel = Theme.Label({ Text = "", Size = UDim2.fromOffset(420, 26), Position = UDim2.fromOffset(12, 108), TextSize = 18, Color = KIND_COLORS.Race, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = gui })
	lobbyLabel.Visible = false

	-- the mission giver's call, sliding up from the bottom
	callCard = New("Frame", { Name = "Call", BackgroundColor3 = Color3.fromRGB(24, 24, 28), BackgroundTransparency = 0.04, Size = UDim2.fromOffset(520, 92), Position = UDim2.new(0.5, 0, 1, 140), AnchorPoint = Vector2.new(0.5, 1), Visible = false, Parent = gui })
	Theme.Corner(callCard, 16)
	Theme.Stroke(callCard, C.Gold, 2, 0.3)
	callTitle = Theme.Label({ Text = "", Size = UDim2.new(1, -24, 0, 26), Position = UDim2.fromOffset(14, 8), TextSize = 20, Color = C.Gold, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = callCard })
	callText = Theme.Label({ Text = "", Size = UDim2.new(1, -28, 1, -40), Position = UDim2.fromOffset(14, 34), TextSize = 16, Font = Theme.Body, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, Parent = callCard })

	Remotes.Event("Objective").OnClientEvent:Connect(function(kind: any, data: any)
		local info = if type(data) == "table" then data else {}
		if kind == "Started" then
			if type(info.Intro) == "string" then
				showCall(info.Giver, info.Intro)
			end
			Toasts.Banner(string.upper(tostring(info.Title or "")), if info.Kind == "Job" then "Delivery job" elseif info.Kind == "Trial" then "Time trial: ride to the start" elseif info.Kind == "Race" then "Race!" else "Mission", KIND_COLORS[info.Kind] or C.Text, 2.2)
		elseif kind == "Step" then
			Sound.Play("Cash", nil, 1.6, 0.35)
		elseif kind == "Done" then
			local sub = if type(info.Cash) == "number" then "+" .. Economy.FormatCash(info.Cash) else nil
			if info.Kind == "Mission" then
				Toasts.Banner("MISSION COMPLETE", sub or tostring(info.Title or ""), C.Gold, 3.5)
				Sound.Play("LevelUp")
			end
		elseif kind == "Failed" then
			local reason = tostring(info.Reason or "")
			if reason ~= "Replaced" and reason ~= "Race over" and reason ~= "Left" then
				Toasts.Banner("FAILED", tostring(info.Title or "") .. (if reason ~= "" then ": " .. reason else ""), Color3.fromRGB(255, 90, 80), 3)
			end
		end
	end)

	Remotes.Event("Race").OnClientEvent:Connect(function(kind: any, data: any)
		local info = if type(data) == "table" then data else {}
		if kind == "Lobby" then
			lobby = info
		elseif kind == "Go" then
			lobby = nil
			Toasts.Banner("GO!", tostring(info.Name or ""), C.Cash, 1.5)
			Sound.Play("LevelUp")
		elseif kind == "Finished" then
			local place = tonumber(info.Place) or 0
			local suffix = if place == 1 then "st" elseif place == 2 then "nd" elseif place == 3 then "rd" else "th"
			Toasts.Banner(string.format("%d%s PLACE", place, suffix), string.format("%s  ·  +%s", Objectives.FormatTime(tonumber(info.Time) or 0), Economy.FormatCash(tonumber(info.Cash) or 0)), if place == 1 then C.Gold else C.Text, 4)
			Sound.Play(if place == 1 then "Escaped" else "Cash")
		elseif kind == "Results" then
			lobby = nil
			if info.Trial then
				local medal = tostring(info.Medal or "None")
				local icon = if medal == "Gold" then "🥇" elseif medal == "Silver" then "🥈" elseif medal == "Bronze" then "🥉" else "🏁"
				Toasts.Banner(string.format("%s %s", icon, Objectives.FormatTime(tonumber(info.Time) or 0)), (if info.NewBest then "New best! " else "") .. "+" .. Economy.FormatCash(tonumber(info.Cash) or 0), if medal == "Gold" then C.Gold else C.Text, 4)
				Sound.Play(if info.NewBest then "LevelUp" else "Cash")
			elseif type(info.Results) == "table" then
				local lines = {}
				for _, r in info.Results do
					table.insert(lines, string.format("%d. %s %s", r.Place, tostring(r.Name), Objectives.FormatTime(r.Time)))
				end
				Toasts.Message("Info", "🏁 " .. tostring(info.Name or "Race") .. ": " .. table.concat(lines, "   "))
			end
		end
	end)
end

function Objective.Update()
	local player = Players.LocalPlayer
	local kind = player:GetAttribute("ObjKind")
	local active = type(kind) == "string" and kind ~= ""
	card.Visible = active
	local target: Vector3? = nil
	local t = serverNow()
	if active then
		local color = KIND_COLORS[kind :: string] or C.Text
		accent.BackgroundColor3 = color
		barFill.BackgroundColor3 = color
		local stepIndex, steps = player:GetAttribute("ObjStep"), player:GetAttribute("ObjSteps")
		titleLabel.Text = string.format("%s %s", KIND_ICONS[kind :: string] or "", tostring(player:GetAttribute("ObjTitle") or ""))
		stepLabel.Text = string.format("%s  (%s/%s)", tostring(player:GetAttribute("ObjText") or ""), tostring(stepIndex or 1), tostring(steps or 1))
		local progress = tonumber(player:GetAttribute("ObjProgress")) or 0
		local stepFraction = ((tonumber(stepIndex) or 1) - 1 + progress) / math.max(tonumber(steps) or 1, 1)
		barFill.Size = UDim2.fromScale(math.clamp(stepFraction, 0, 1), 1)
		local ends = tonumber(player:GetAttribute("ObjEnds")) or 0
		local started = tonumber(player:GetAttribute("ObjStarted")) or 0
		if kind == "Race" or kind == "Trial" then
			clockLabel.Text = if started > 0 then Objectives.FormatTime(t - started) else ""
		elseif ends > 0 then
			local left = ends - t
			clockLabel.Text = Objectives.FormatTime(left)
			clockLabel.TextColor3 = if left < 20 then Color3.fromRGB(255, 90, 80) else C.Gold
		else
			clockLabel.Text = ""
		end
		local at = player:GetAttribute("ObjTarget")
		if typeof(at) == "Vector3" then
			target = at
		end
	end
	local pos = player:GetAttribute("RacePos")
	posLabel.Visible = type(pos) == "string" and kind == "Race"
	if posLabel.Visible then
		posLabel.Text = tostring(pos)
	end
	-- a race lobby counting down: where the start is, how long to go
	local l = lobby
	lobbyLabel.Visible = l ~= nil and not active and player:GetAttribute("RaceLobby") ~= nil
	if l and lobbyLabel.Visible then
		local racers = if type(l.Racers) == "table" then #l.Racers else 1
		if l.State == "Countdown" then
			local left = math.max(0, math.ceil((tonumber(l.StartAt) or t) - t))
			lobbyLabel.Text = string.format("🏁 %s: %d riders · GO in %ds · get to the start line!", tostring(l.Name), racers, left)
		else
			lobbyLabel.Text = string.format("🏁 %s lobby: %d rider · waiting for someone to join", tostring(l.Name), racers)
		end
		if typeof(l.Start) == "Vector3" then
			target = l.Start
		end
	end
	-- the beacon over the target
	if target then
		if not beacon then
			makeBeacon()
		end
		local b = beacon :: Part
		b.CFrame = CFrame.new(target + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		b.Color = if active then (KIND_COLORS[kind :: string] or C.Gold) else KIND_COLORS.Race
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local label = beaconLabel
		if label and root and root:IsA("BasePart") then
			-- (in the bike's metres, so the distance agrees with its speedometer)
			local metres = (root.Position - target).Magnitude / Config.STUDS_PER_METER
			label.Text = if metres >= 1000 then string.format("▼ %.1f km", metres / 1000) else string.format("▼ %d m", math.floor(metres))
		end
		b.Transparency = 0.55
	elseif beacon then
		beacon.Transparency = 1
		if beaconLabel then
			beaconLabel.Text = ""
		end
	end
end

-- Where the current objective (or the race lobby's start) is, for the minimap
function Objective.Target(): Vector3?
	local player = Players.LocalPlayer
	local at = player:GetAttribute("ObjTarget")
	if typeof(at) == "Vector3" then
		return at
	end
	local l = lobby
	if l and typeof(l.Start) == "Vector3" and player:GetAttribute("RaceLobby") ~= nil then
		return l.Start
	end
	return nil
end

return Objective
