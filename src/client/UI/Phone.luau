--[[
	Phone: the in-game phone (` backquote, or the 📱 tile on the HUD): a handset with a wallpaper that
	follows the time of day, a status bar (clock, signal, the bike's battery), a big lock-screen
	clock with the weather, a grid of apps that open the menus (Map, My Rides, Dealer, Tuning,
	Crates, Shop, Stats, Settings), a dock, and a red badge on Stats while an achievement waits to
	be claimed. Built like a Panel so UI.Open shows and hides it.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weather = require(Shared.Weather)

local BikeController = require(script.Parent.Parent.BikeController)
local Panel = require(script.Parent.Panel)
local StatsScreen = require(script.Parent.StatsScreen)
local Theme = require(script.Parent.Theme)

local Phone = {}

local New = Theme.New

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type App = { Name: string, Icon: string, Top: Color3, Bottom: Color3, Opens: string }
local APPS: { App } = {
	{ Name = "Map", Icon = "🗺", Top = rgb(90, 200, 120), Bottom = rgb(30, 130, 80), Opens = "Map" },
	{ Name = "My Rides", Icon = "🏍", Top = rgb(255, 160, 60), Bottom = rgb(230, 90, 20), Opens = "MyRides" },
	{ Name = "Dealer", Icon = "🛒", Top = rgb(90, 160, 255), Bottom = rgb(40, 80, 210), Opens = "Dealership" },
	{ Name = "Tuning", Icon = "🔧", Top = rgb(160, 160, 170), Bottom = rgb(80, 80, 92), Opens = "Tuning" },
	{ Name = "Crates", Icon = "🎁", Top = rgb(220, 120, 255), Bottom = rgb(140, 50, 200), Opens = "Crates" },
	{ Name = "Shop", Icon = "💵", Top = rgb(140, 240, 90), Bottom = rgb(50, 160, 40), Opens = "Shop" },
	{ Name = "Stats", Icon = "🏆", Top = rgb(255, 220, 80), Bottom = rgb(230, 150, 20), Opens = "Stats" },
	{ Name = "Settings", Icon = "⚙️", Top = rgb(120, 130, 150), Bottom = rgb(60, 66, 80), Opens = "Menus" },
}
local DOCK = { 1, 2, 6, 7 }

-- the wallpaper's colours through the day
type Key = { Hour: number, Top: Color3, Bottom: Color3 }
local SKY: { Key } = {
	{ Hour = 0, Top = rgb(14, 18, 50), Bottom = rgb(40, 20, 70) },
	{ Hour = 6, Top = rgb(255, 150, 90), Bottom = rgb(120, 70, 160) },
	{ Hour = 9, Top = rgb(80, 180, 255), Bottom = rgb(60, 120, 220) },
	{ Hour = 17, Top = rgb(70, 160, 240), Bottom = rgb(255, 160, 90) },
	{ Hour = 19.5, Top = rgb(255, 110, 90), Bottom = rgb(90, 40, 120) },
	{ Hour = 21, Top = rgb(20, 24, 60), Bottom = rgb(50, 24, 80) },
	{ Hour = 24, Top = rgb(14, 18, 50), Bottom = rgb(40, 20, 70) },
}

local function sky(hour: number): (Color3, Color3)
	for i = 1, #SKY - 1 do
		local a, b = SKY[i], SKY[i + 1]
		if hour >= a.Hour and hour <= b.Hour then
			local f = (hour - a.Hour) / (b.Hour - a.Hour)
			return a.Top:Lerp(b.Top, f), a.Bottom:Lerp(b.Bottom, f)
		end
	end
	return SKY[1].Top, SKY[1].Bottom
end

function Phone.new(gui: Instance, open: (string) -> (), close: () -> ()): Panel.Panel
	local frame = New("Frame", { Name = "Phone", BackgroundColor3 = rgb(16, 16, 18), Size = UDim2.fromOffset(340, 660), Position = UDim2.new(1, -40, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Visible = false, ZIndex = 20, Parent = gui })
	Theme.Corner(frame, 46)
	Theme.Stroke(frame, rgb(70, 70, 76), 3)
	-- side buttons
	New("Frame", { BackgroundColor3 = rgb(50, 50, 56), Size = UDim2.fromOffset(4, 60), Position = UDim2.new(1, 1, 0, 140), ZIndex = 19, Parent = frame })
	New("Frame", { BackgroundColor3 = rgb(50, 50, 56), Size = UDim2.fromOffset(4, 40), Position = UDim2.new(0, -5, 0, 120), ZIndex = 19, Parent = frame })
	local screen = New("Frame", { Name = "Screen", BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.new(1, -20, 1, -20), Position = UDim2.fromOffset(10, 10), ClipsDescendants = true, ZIndex = 21, Parent = frame })
	Theme.Corner(screen, 38)
	local wallpaper = New("UIGradient", { Rotation = 90, Parent = screen })
	-- soft shapes on the wallpaper
	for i, s in { { 0.2, 0.25, 220 }, { 0.85, 0.55, 260 }, { 0.3, 0.85, 200 } } do
		local blob = New("Frame", { BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.88, Size = UDim2.fromOffset(s[3], s[3]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(s[1], s[2]), ZIndex = 21 + i * 0, Parent = screen })
		Theme.Round(blob)
	end
	-- notch and status bar
	local notch = New("Frame", { BackgroundColor3 = rgb(10, 10, 12), Size = UDim2.fromOffset(110, 28), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 30, Parent = screen })
	Theme.Corner(notch, 14)
	local clockSmall = Theme.Label({ Text = "12:00", Size = UDim2.fromOffset(70, 22), Position = UDim2.fromOffset(22, 12), TextSize = 16, Font = Theme.Body, Stroke = 0, ZIndex = 31, Parent = screen })
	local status = Theme.Label({ Text = "📶 5G  🔋 100%", Size = UDim2.fromOffset(120, 22), Position = UDim2.new(1, -18, 0, 12), AnchorPoint = Vector2.new(1, 0), TextSize = 14, Font = Theme.Body, Align = Enum.TextXAlignment.Right, Stroke = 0, ZIndex = 31, Parent = screen })
	-- lock-screen clock and the weather
	local clockBig = Theme.Label({ Text = "12:00", Size = UDim2.new(1, 0, 0, 78), Position = UDim2.fromOffset(0, 54), TextSize = 74, Stroke = 0, ZIndex = 31, Parent = screen })
	local weather = Theme.Label({ Text = "Miami", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 132), TextSize = 19, Font = Theme.Body, Stroke = 0, ZIndex = 31, Parent = screen })
	-- the app grid
	local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -28, 0, 220), Position = UDim2.fromOffset(14, 180), ZIndex = 31, Parent = screen })
	New("UIGridLayout", { CellSize = UDim2.fromOffset(68, 96), CellPadding = UDim2.fromOffset(5, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	local badges: { TextLabel } = {}
	local function appIcon(parent: Instance, app: App, order: number, label: boolean): Frame
		local holder = New("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(68, if label then 96 else 68), LayoutOrder = order, ZIndex = 32, Parent = parent })
		local tile = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.fromOffset(62, 62), Position = UDim2.new(0.5, 0, 0, 2), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 33, Parent = holder })
		Theme.Corner(tile, 16)
		New("UIGradient", { Rotation = 90, Color = ColorSequence.new(app.Top, app.Bottom), Parent = tile })
		local shine = New("Frame", { BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.82, Size = UDim2.new(1, -8, 0.45, 0), Position = UDim2.fromOffset(4, 3), ZIndex = 34, Parent = tile })
		Theme.Corner(shine, 12)
		Theme.Label({ Text = app.Icon, Size = UDim2.fromScale(1, 1), TextSize = 32, Stroke = 0, ZIndex = 35, Parent = tile })
		if label then
			Theme.Label({ Text = app.Name, Size = UDim2.new(1, 4, 0, 18), Position = UDim2.new(0, -2, 0, 68), TextSize = 13, Font = Theme.Body, Stroke = 1, ZIndex = 33, Parent = holder })
		end
		if app.Opens == "Stats" then
			local badge = Theme.Label({ Text = "", Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, 2, 0, -4), AnchorPoint = Vector2.new(1, 0), TextSize = 13, Font = Theme.Body, Stroke = 0, ZIndex = 40, Parent = holder })
			badge.BackgroundColor3 = rgb(240, 50, 50)
			badge.BackgroundTransparency = 0
			Theme.Round(badge)
			table.insert(badges, badge)
		end
		local scale = New("UIScale", { Parent = tile })
		tile.MouseButton1Down:Connect(function()
			scale.Scale = 0.9
		end)
		tile.MouseButton1Up:Connect(function()
			scale.Scale = 1
		end)
		tile.Activated:Connect(function()
			close()
			open(app.Opens)
		end)
		return holder
	end
	for i, app in APPS do
		appIcon(grid, app, i, true)
	end
	-- the dock
	local dock = New("Frame", { BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.7, Size = UDim2.new(1, -24, 0, 84), Position = UDim2.new(0.5, 0, 1, -20), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 31, Parent = screen })
	Theme.Corner(dock, 26)
	Theme.List(dock, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for i, index in DOCK do
		appIcon(dock, APPS[index], i, false)
	end
	-- the home bar
	local home = New("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.fromOffset(120, 5), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 32, Parent = screen })
	Theme.Corner(home, 3)
	home.Activated:Connect(close)

	local function tick()
		local t = Lighting.ClockTime
		local text = string.format("%d:%02d", math.floor(t) % 24, math.floor((t % 1) * 60))
		clockSmall.Text = text
		clockBig.Text = text
		local top, bottom = sky(t)
		wallpaper.Color = ColorSequence.new(top, bottom)
		local override = ReplicatedStorage:GetAttribute("WeatherOverride")
		local ok, _, kind = pcall(Weather.At, Workspace:GetServerTimeNow(), if type(override) == "string" and override ~= "" then override else nil)
		local icon = if not ok then "☀️" elseif kind == "Overcast" then "☁️" elseif kind == "Cloudy" then "⛅" else (if t > 19.5 or t < 6 then "🌙" else "☀️")
		local temp = if t > 11 and t < 17 then 33 elseif t > 7 and t < 20 then 29 else 25
		weather.Text = string.format("%s  Miami · %d°C", icon, temp)
		local pct = if BikeController.Active then math.floor(BikeController.BatteryFraction() * 100 + 0.5) else 100
		status.Text = string.format("📶 5G   🔋 %d%%", pct)
		local unclaimed = StatsScreen.Unclaimed()
		for _, b in badges do
			b.Visible = unclaimed > 0
			b.Text = tostring(unclaimed)
		end
	end
	local since = 1
	RunService.Heartbeat:Connect(function(dt)
		if not frame.Visible then
			return
		end
		since += dt
		if since >= 0.5 then
			since = 0
			tick()
		end
	end)

	local title = Theme.Label({ Text = "", Size = UDim2.fromOffset(0, 0), Parent = frame })
	title.Visible = false
	local self: Panel.Panel = { Name = "Phone", Frame = frame, Body = screen, Title = title, Footer = title, OnClose = nil, Refresh = tick }
	return self
end

return Phone
