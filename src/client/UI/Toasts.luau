--[[
	Toasts: the reference game's plain outlined messages ("Level up! You're now level 13 (+$100)")
	low in the middle of the screen, "+$1" pops by the minimap while riding pays, trick payouts
	under the trick display, and big banners for police moments (WANTED, BUSTED, ESCAPED).
]]

local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)

local Theme = require(script.Parent.Theme)

local Toasts = {}

local New = Theme.New
local C = Theme.Colors

local root: ScreenGui
local messages: Frame
local pops: Frame
local trickPops: Frame
local banner: TextLabel
local bannerSub: TextLabel
local bannerToken = 0

local KIND_COLORS: { [string]: Color3 } = {
	Level = Color3.fromRGB(255, 255, 255),
	Info = Color3.fromRGB(255, 255, 255),
	Cash = C.Cash,
	Error = Color3.fromRGB(255, 110, 100),
	Police = Color3.fromRGB(120, 170, 255),
}

-- A centred message that fades after a few seconds (newest at the bottom)
function Toasts.Message(kind: string, text: string)
	local label = Theme.Label({
		Text = text,
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 26,
		Color = KIND_COLORS[kind] or C.Text,
		Stroke = 2,
		Parent = messages,
	})
	label.TextTransparency = 1
	local stroke = label:FindFirstChildOfClass("UIStroke")
	TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	task.delay(if kind == "Level" then 4 else 3, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		task.wait(0.5)
		label:Destroy()
	end)
	-- keep at most four on screen
	local labels = {}
	for _, child in messages:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	if #labels > 4 then
		labels[1]:Destroy()
	end
end

-- "+$1" rising from beside the minimap (riding income)
function Toasts.CashPop(amount: number)
	local label = Theme.Label({
		Text = "+" .. Economy.FormatCash(amount),
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(0, math.random(-6, 6), 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		TextSize = 22,
		Color = C.Cash,
		StrokeColor = C.CashDark,
		Align = Enum.TextXAlignment.Left,
		Parent = pops,
	})
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Position = UDim2.new(0, label.Position.X.Offset, 1, -46), TextTransparency = 1 }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(1.2), { Transparency = 1 }):Play()
	end
	task.delay(1.3, function()
		label:Destroy()
	end)
end

-- "+$18  Air 1.2s · Clean" under the trick display
function Toasts.TrickPop(amount: number, text: string)
	local label = Theme.Label({
		Text = string.format("+%s  %s", Economy.FormatCash(amount), text),
		Size = UDim2.new(1, 0, 0, 28),
		TextSize = 24,
		Color = C.Cash,
		StrokeColor = C.CashDark,
		Parent = trickPops,
	})
	Theme.Pop(label)
	task.delay(2.2, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		end
		task.wait(0.4)
		label:Destroy()
	end)
end

-- A big banner in the middle of the screen (police moments, bails)
function Toasts.Banner(text: string, sub: string?, color: Color3, seconds: number?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	banner.Visible = true
	bannerSub.Text = sub or ""
	bannerSub.TextTransparency = 0
	bannerSub.Visible = sub ~= nil
	for _, label in { banner, bannerSub } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0
		end
	end
	Theme.Pop(banner)
	task.delay(seconds or 2.5, function()
		if token ~= bannerToken then
			return
		end
		for _, label in { banner, bannerSub } do
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			end
		end
	end)
end

-- `minimap`: where cash pops rise from
function Toasts.Init(gui: ScreenGui, minimap: GuiObject)
	root = gui
	messages = New("Frame", {
		Name = "Messages",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.6, 0, 0, 160),
		Position = UDim2.new(0.5, 0, 0.78, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = root,
	})
	Theme.List(messages, Enum.FillDirection.Vertical, 2, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom)
	pops = New("Frame", {
		Name = "CashPops",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(120, 60),
		Position = UDim2.new(1, -40, 1, -4),
		AnchorPoint = Vector2.new(0, 1),
		Parent = minimap,
	})
	trickPops = New("Frame", {
		Name = "TrickPops",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 0, 120),
		Position = UDim2.new(0.5, 0, 0, 150),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = root,
	})
	Theme.List(trickPops, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center)
	banner = Theme.Label({ Name = "Banner", Text = "", Size = UDim2.new(1, 0, 0, 72), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), TextSize = 64, Stroke = 4, Parent = root })
	banner.Visible = false
	bannerSub = Theme.Label({ Name = "BannerSub", Text = "", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0.5, 0, 0.36, 46), AnchorPoint = Vector2.new(0.5, 0.5), TextSize = 28, Stroke = 2, Parent = root })
	bannerSub.Visible = false
end

return Toasts
