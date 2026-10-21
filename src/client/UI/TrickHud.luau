--[[
	TrickHud: the reference game's top-centre trick display. The trick's name in big orange outlined
	letters ("Wheelie"), its clock, your best time, and the cash multiplier in a pill that fills as
	it grows. During a wheelie a balance bar shows where the bike sits between dropping the front
	and looping out (the green band is the sweet spot).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local BikeController = require(script.Parent.Parent.BikeController)
local State = require(script.Parent.Parent.State)
local Theme = require(script.Parent.Theme)

local TrickHud = {}

local New = Theme.New
local C = Theme.Colors
local WH = Config.Wheelie

local holder: Frame
local title: TextLabel
local timer: TextLabel
local best: TextLabel
local pill: Frame
local pillFill: Frame
local pillText: TextLabel
local balance: Frame
local balanceMarker: Frame
local combo: TextLabel

function TrickHud.Init(gui: ScreenGui)
	holder = New("Frame", {
		Name = "TrickHud",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(320, 150),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = gui,
	})
	title = Theme.Label({ Text = "Wheelie", Size = UDim2.new(1, 0, 0, 40), TextSize = 40, Color = C.Orange, StrokeColor = Color3.fromRGB(40, 16, 0), Stroke = 3, Parent = holder })
	title.Rotation = -3
	timer = Theme.Label({ Text = "0.0s", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 38), TextSize = 30, Stroke = 3, Parent = holder })
	best = Theme.Label({ Text = "Best time: 0.0s", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 68), TextSize = 15, Stroke = 2, Parent = holder })
	pill = New("Frame", { BackgroundColor3 = Color3.fromRGB(52, 52, 56), BackgroundTransparency = 0.1, Size = UDim2.fromOffset(170, 26), Position = UDim2.new(0.5, 0, 0, 88), AnchorPoint = Vector2.new(0.5, 0), Parent = holder })
	Theme.Round(pill)
	pillFill = New("Frame", { BackgroundColor3 = C.Orange, Size = UDim2.fromScale(0.15, 1), Parent = pill })
	Theme.Round(pillFill)
	pillText = Theme.Label({ Text = "1.00x Cash", Size = UDim2.fromScale(1, 1), TextSize = 19, Stroke = 2, ZIndex = 2, Parent = pill })

	balance = New("Frame", { BackgroundColor3 = Color3.fromRGB(40, 40, 44), Size = UDim2.fromOffset(170, 8), Position = UDim2.new(0.5, 0, 0, 120), AnchorPoint = Vector2.new(0.5, 0), Visible = false, Parent = holder })
	Theme.Round(balance)
	local sweet = New("Frame", {
		BackgroundColor3 = C.Green,
		Size = UDim2.fromScale((WH.SweetHigh - WH.SweetLow) / WH.LoopOut, 1),
		Position = UDim2.fromScale(WH.SweetLow / WH.LoopOut, 0),
		Parent = balance,
	})
	Theme.Round(sweet)
	local danger = New("Frame", { BackgroundColor3 = C.Red, Size = UDim2.fromScale(0.12, 1), Position = UDim2.fromScale(0.88, 0), Parent = balance })
	Theme.Round(danger)
	balanceMarker = New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(4, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), ZIndex = 3, Parent = balance })
	Theme.Stroke(balanceMarker, C.Outline, 1)
	combo = Theme.Label({ Text = "", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 132), TextSize = 15, Color = C.Gold, Stroke = 2, Parent = holder })
end

function TrickHud.Update(_dt: number)
	local s = BikeController.Physics
	if not BikeController.Active or not s then
		holder.Visible = false
		return
	end
	local player = Players.LocalPlayer
	local mult = player:GetAttribute("Mult")
	local multiplier = if type(mult) == "number" then mult else 1
	local comboValue = player:GetAttribute("Combo")
	local comboNumber = if type(comboValue) == "number" then comboValue else 0

	local name: string? = nil
	local clock = 0
	local bestText = ""
	local data = State.Get()
	if s.Crash > 0 then
		holder.Visible = false -- a bail is shown by the ragdoll, not a banner
		return
	elseif s.WheelieActive then
		name = "Wheelie"
		clock = s.WheelieTime
		bestText = string.format("Best time: %.1fs", if data then data.Stats.BestWheelie else 0)
	elseif not s.Grounded and s.AirTime > 0.25 then
		name = if s.AirHands then "No-hander!" else "Air"
		clock = s.AirTime
		bestText = string.format("Longest air: %.1fs", if data then data.Stats.LongestAir else 0)
	elseif s.Hands == 2 then
		name = "No Hands"
	elseif s.Hands == 1 then
		name = "One Hand"
	elseif multiplier > 1.001 then
		local wanted = player:GetAttribute("Wanted")
		name = if type(wanted) == "number" and wanted > 0 then "Chase Bonus" else "Combo"
	end
	if not name then
		holder.Visible = false
		return
	end
	holder.Visible = true
	title.Text = name
	title.TextColor3 = if name == "Chase Bonus" then Color3.fromRGB(110, 160, 255) else C.Orange
	timer.Visible = clock > 0
	timer.Text = string.format("%.1fs", clock)
	best.Visible = bestText ~= ""
	best.Text = bestText
	pillText.Text = string.format("%.2fx Cash", multiplier)
	local fill = math.clamp((multiplier - 1) / 3, 0, 1)
	pillFill.Size = UDim2.new(fill, if fill < 0.15 then 26 else 0, 1, 0)
	balance.Visible = s.WheelieActive
	if s.WheelieActive then
		balanceMarker.Position = UDim2.fromScale(math.clamp(s.Wheelie / WH.LoopOut, 0, 1), 0.5)
	end
	combo.Text = if comboNumber > 0.01 then string.format("Combo +%.2fx", comboNumber) else ""
end

return TrickHud
