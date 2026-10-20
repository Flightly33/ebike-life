--[[
	WantedHud: top-right. Wanted stars (as in the reference), the player's level badge with its XP
	bar, and the police meters: heat building toward the next star while a cop is watching, the
	evade clock while out of sight in a chase, and the bust meter when a cop has you cornered.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local WantedHud = {}

local New = Theme.New
local C = Theme.Colors

local stars: { TextLabel } = {}
local levelText: TextLabel
local xpFill: Frame
local meters: Frame
type Meter = { Frame: Frame, Fill: Frame, Label: TextLabel }
local heat: Meter
local evade: Meter
local bust: Meter

local function meter(parent: Instance, order: number, color: Color3): Meter
	local frame = New("Frame", { BackgroundColor3 = Color3.fromRGB(24, 24, 27), BackgroundTransparency = 0.15, Size = UDim2.fromOffset(190, 22), LayoutOrder = order, Visible = false, Parent = parent })
	Theme.Corner(frame, 6)
	local fill = New("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(0, 1), Parent = frame })
	Theme.Corner(fill, 6)
	local label = Theme.Label({ Text = "", Size = UDim2.fromScale(1, 1), TextSize = 14, Stroke = 2, ZIndex = 2, Parent = frame })
	return { Frame = frame, Fill = fill, Label = label }
end

function WantedHud.Init(gui: ScreenGui)
	local holder = New("Frame", { Name = "WantedHud", BackgroundTransparency = 1, Size = UDim2.fromOffset(260, 120), Position = UDim2.new(1, -12, 0, 6), AnchorPoint = Vector2.new(1, 0), Parent = gui })
	local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = holder })
	Theme.List(row, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
	for i = 1, 5 do
		local star = Theme.Label({ Text = "★", Size = UDim2.fromOffset(30, 34), TextSize = 32, Color = Color3.fromRGB(255, 255, 255), Stroke = 2, LayoutOrder = i, Parent = row })
		star.Visible = false
		table.insert(stars, star)
	end
	-- level badge
	local badge = New("Frame", { BackgroundColor3 = Color3.fromRGB(26, 26, 29), Size = UDim2.fromOffset(38, 38), LayoutOrder = 10, Parent = row })
	Theme.Round(badge)
	Theme.Stroke(badge, Color3.fromRGB(10, 10, 12), 2)
	levelText = Theme.Label({ Text = "1", Size = UDim2.fromScale(1, 1), TextSize = 18, Stroke = 1, Parent = badge })
	local xpBack = New("Frame", { BackgroundColor3 = Color3.fromRGB(26, 26, 29), Size = UDim2.fromOffset(38, 5), Position = UDim2.new(0, 0, 1, 3), Parent = badge })
	Theme.Round(xpBack)
	xpFill = New("Frame", { BackgroundColor3 = C.Gold, Size = UDim2.fromScale(0, 1), Parent = xpBack })
	Theme.Round(xpFill)

	meters = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 50), Parent = holder })
	Theme.List(meters, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right)
	heat = meter(meters, 1, Color3.fromRGB(230, 70, 60))
	evade = meter(meters, 2, Color3.fromRGB(60, 150, 255))
	bust = meter(meters, 3, Color3.fromRGB(255, 40, 40))
end

local function number(player: Player, name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function WantedHud.Update()
	local player = Players.LocalPlayer
	local wanted = number(player, "Wanted")
	local flash = (os.clock() * 3) % 2 < 1
	local evading = number(player, "Evade")
	for i, star in stars do
		star.Visible = i <= wanted
		star.TextTransparency = if evading > 0 and flash then 0.6 else 0
	end
	levelText.Text = tostring(number(player, "Level"))
	local xpNext = number(player, "XpNext")
	xpFill.Size = UDim2.fromScale(if xpNext > 0 then math.clamp(number(player, "Xp") / xpNext, 0, 1) else 0, 1)

	local heatValue = number(player, "Heat")
	local seen = player:GetAttribute("Seen") == true
	heat.Frame.Visible = heatValue > 0.01 and wanted < 5
	heat.Fill.Size = UDim2.fromScale(heatValue, 1)
	heat.Label.Text = if wanted == 0 then (if seen then "👁 Cop watching!" else "Cops suspicious") else "👁 Heat rising"
	evade.Frame.Visible = wanted > 0 and evading > 0.01
	evade.Fill.Size = UDim2.fromScale(evading, 1)
	evade.Label.Text = "Lost them... " .. math.floor(evading * 100) .. "%"
	local bustValue = number(player, "Bust")
	bust.Frame.Visible = bustValue > 0.01
	bust.Fill.Size = UDim2.fromScale(bustValue, 1)
	bust.Label.Text = "PULL OVER!"
end

return WantedHud
