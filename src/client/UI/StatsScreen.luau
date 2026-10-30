--[[
	StatsScreen: your rider profile and the achievements. Left, a profile card (level with an XP
	bar, cash, bikes, paints) over a grid of stats from the save (distance, best wheelie, longest
	air, flips, top wanted level, escapes, busts, earned). Right, every achievement (Shared/
	Achievements) with its progress bar, and a Claim button once it's done: the server checks the
	goal and pays the reward (ClaimAchievement).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Achievements)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)

local Sound = require(script.Parent.Parent.Sound)
local State = require(script.Parent.Parent.State)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local StatsScreen = {}

local New = Theme.New
local C = Theme.Colors

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function count(t: { [string]: boolean }): number
	local n = 0
	for _, v in t do
		if v then
			n += 1
		end
	end
	return n
end

function StatsScreen.new(gui: Instance): Panel.Panel
	local panel = Panel.new(gui, "Stats", "Rider Profile", Vector2.new(1080, 640), nil)
	local left = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, 400, 1, 0), Parent = panel.Body })
	local right = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, -412, 1, 0), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Parent = panel.Body })
	Theme.Corner(right, 8)

	-- the profile card
	local card = New("Frame", { BackgroundColor3 = rgb(255, 255, 255), Size = UDim2.new(1, 0, 0, 200), Parent = left })
	Theme.Corner(card, 10)
	New("UIGradient", { Rotation = 35, Color = ColorSequence.new(rgb(255, 140, 50), rgb(170, 60, 200)), Parent = card })
	local badge = New("Frame", { BackgroundColor3 = rgb(20, 20, 24), BackgroundTransparency = 0.25, Size = UDim2.fromOffset(110, 110), Position = UDim2.fromOffset(18, 20), Parent = card })
	Theme.Round(badge)
	Theme.Stroke(badge, rgb(255, 255, 255), 3)
	Theme.Label({ Text = "LEVEL", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 18), TextSize = 15, Font = Theme.Body, Stroke = 0, Parent = badge })
	local level = Theme.Label({ Text = "1", Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 36), TextSize = 52, Stroke = 3, Parent = badge })
	local name = Theme.Label({ Text = "", Size = UDim2.new(1, -150, 0, 34), Position = UDim2.fromOffset(142, 26), TextSize = 30, Align = Enum.TextXAlignment.Left, Stroke = 3, Parent = card })
	local cash = Theme.Label({ Text = "", Size = UDim2.new(1, -150, 0, 30), Position = UDim2.fromOffset(142, 62), TextSize = 28, Color = C.Cash, StrokeColor = C.CashDark, Align = Enum.TextXAlignment.Left, Stroke = 3, Parent = card })
	local owned = Theme.Label({ Text = "", Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(142, 96), TextSize = 18, Font = Theme.Body, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = card })
	local bar = New("Frame", { BackgroundColor3 = rgb(20, 20, 24), BackgroundTransparency = 0.3, Size = UDim2.new(1, -36, 0, 22), Position = UDim2.fromOffset(18, 150), Parent = card })
	Theme.Corner(bar, 11)
	local fill = New("Frame", { BackgroundColor3 = rgb(255, 220, 70), Size = UDim2.fromScale(0, 1), Parent = bar })
	Theme.Corner(fill, 11)
	New("UIGradient", { Color = ColorSequence.new(rgb(255, 240, 120), rgb(255, 170, 30)), Parent = fill })
	local xp = Theme.Label({ Text = "", Size = UDim2.fromScale(1, 1), TextSize = 15, Font = Theme.Body, Stroke = 2, ZIndex = 3, Parent = bar })

	-- the stats grid
	local grid = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -212), Position = UDim2.fromOffset(0, 212), Parent = left })
	New("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 84), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	type Tile = { Value: TextLabel }
	local tiles: { [string]: Tile } = {}
	local STATS = {
		{ "Distance", "🛣", "Distance" },
		{ "BestWheelie", "🏍", "Best wheelie" },
		{ "LongestAir", "🕊", "Longest air" },
		{ "Flips", "🔄", "Flips landed" },
		{ "MaxStars", "🚨", "Most wanted" },
		{ "Escapes", "💨", "Escapes" },
		{ "Busts", "🚓", "Busted" },
		{ "Earned", "💵", "Earned riding" },
	}
	for i, s in STATS do
		local tile = New("Frame", { BackgroundColor3 = C.Tile, LayoutOrder = i, Parent = grid })
		Theme.Corner(tile, 8)
		Theme.Stroke(tile, C.TileStroke, 1.5)
		Theme.Label({ Text = s[2], Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(8, 20), TextSize = 32, Stroke = 0, Parent = tile })
		Theme.Label({ Text = s[3], Size = UDim2.new(1, -60, 0, 20), Position = UDim2.fromOffset(56, 12), TextSize = 15, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = tile })
		local value = Theme.Label({ Text = "0", Size = UDim2.new(1, -60, 0, 36), Position = UDim2.fromOffset(56, 34), TextSize = 30, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = tile })
		tiles[s[1]] = { Value = value }
	end

	-- achievements
	local header = Theme.Label({ Text = "Achievements", Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(12, 8), TextSize = 28, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = right })
	local list = New("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -16, 1, -56), Position = UDim2.fromOffset(8, 48), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, Parent = right })
	Theme.List(list, Enum.FillDirection.Vertical, 6)

	local function refresh()
		local data = State.Get()
		if not data then
			return
		end
		local player = game:GetService("Players").LocalPlayer
		level.Text = tostring(data.Level)
		name.Text = player.DisplayName
		cash.Text = Economy.FormatCash(data.Cash)
		owned.Text = string.format("🏍 %d bikes   🎨 %d paints", count(data.Owned), count(data.Paints))
		local need = Economy.XpToNext(data.Level)
		fill.Size = UDim2.fromScale(math.clamp(data.Xp / math.max(need, 1), 0, 1), 1)
		xp.Text = string.format("%d / %d XP", math.floor(data.Xp), need)
		local st = data.Stats
		tiles.Distance.Value.Text = string.format("%.1f km", st.Distance / 1000)
		tiles.BestWheelie.Value.Text = string.format("%.1f s", st.BestWheelie)
		tiles.LongestAir.Value.Text = string.format("%.1f s", st.LongestAir)
		tiles.Flips.Value.Text = tostring(st.Flips)
		tiles.MaxStars.Value.Text = string.rep("★", st.MaxStars) .. (if st.MaxStars == 0 then "—" else "")
		tiles.Escapes.Value.Text = tostring(st.Escapes)
		tiles.Busts.Value.Text = tostring(st.Busts)
		tiles.Earned.Value.Text = Economy.FormatCash(st.Earned)
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local claimed = 0
		for i, a in Achievements.List do
			local progress, done = Achievements.Progress(a, data)
			local got = data.Achievements[a.Id] == true
			if got then
				claimed += 1
			end
			-- ready to claim first, then in progress, then claimed
			local order = if done and not got then i elseif not got then 100 + i else 200 + i
			local row = New("Frame", { BackgroundColor3 = if done and not got then rgb(52, 60, 40) else C.Tile, Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order, Parent = list })
			Theme.Corner(row, 8)
			Theme.Stroke(row, if done and not got then C.Gold else C.TileStroke, if done and not got then 2 else 1)
			local icon = New("Frame", { BackgroundColor3 = if got or done then rgb(255, 196, 46) else rgb(70, 70, 78), Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(9, 9), Parent = row })
			Theme.Round(icon)
			Theme.Label({ Text = a.Icon, Size = UDim2.fromScale(1, 1), TextSize = 28, Stroke = 0, Parent = icon })
			Theme.Label({ Text = a.Name, Size = UDim2.new(1, -230, 0, 24), Position = UDim2.fromOffset(72, 6), TextSize = 21, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = row })
			Theme.Label({ Text = a.Description, Size = UDim2.new(1, -230, 0, 16), Position = UDim2.fromOffset(72, 30), TextSize = 14, Font = Theme.BodyRegular, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 0, Parent = row })
			local track = New("Frame", { BackgroundColor3 = rgb(24, 24, 28), Size = UDim2.new(1, -230, 0, 10), Position = UDim2.fromOffset(72, 52), Parent = row })
			Theme.Corner(track, 5)
			local bit = New("Frame", { BackgroundColor3 = if done then C.Gold else C.Blue, Size = UDim2.fromScale(progress, 1), Parent = track })
			Theme.Corner(bit, 5)
			if got then
				Theme.Label({ Text = "Claimed ✓", Size = UDim2.fromOffset(140, 40), Position = UDim2.new(1, -150, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextSize = 19, Color = C.SubText, Stroke = 1, Parent = row })
			elseif done then
				Theme.Button({ Text = "Claim " .. Economy.FormatCash(a.Reward), Size = UDim2.fromOffset(140, 42), Position = UDim2.new(1, -150, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Color = C.Gold, TextSize = 19, Parent = row, OnClick = function()
					local ok, message = Remotes.Function("ClaimAchievement"):InvokeServer(a.Id)
					Toasts.Message(if ok then "Cash" else "Error", tostring(message))
					if ok then
						Sound.Play("LevelUp")
					end
				end })
			else
				Theme.Label({ Text = Economy.FormatCash(a.Reward), Size = UDim2.fromOffset(140, 40), Position = UDim2.new(1, -150, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextSize = 20, Color = C.Cash, StrokeColor = C.CashDark, Stroke = 2, Parent = row })
			end
		end
		header.Text = string.format("Achievements  %d / %d", claimed, #Achievements.List)
	end
	panel.Refresh = refresh
	State.Changed:Connect(function()
		if panel.Frame.Visible then
			refresh()
		end
	end)
	return panel
end

-- How many achievements are done but not claimed (for the HUD and phone badges)
function StatsScreen.Unclaimed(): number
	local data = State.Get()
	if not data then
		return 0
	end
	local n = 0
	for _, a in Achievements.List do
		local _, done = Achievements.Progress(a, data)
		if done and not data.Achievements[a.Id] then
			n += 1
		end
	end
	return n
end

return StatsScreen
