--[[
	Activities: the phone's Play hub (also opened on the Ranks tab by the Ranks app). Tabs:
	  Missions  the story, chapter by chapter: who's asking, the reward, Start on the next one open
	  Jobs      three delivery offers near you: from, to, distance, pay, time limit
	  Races     every course: length, medal times, your best; a time trial, or the race lobby
	  Daily     the login streak and today's and this week's challenges, with Claim buttons
	  Events    the event running now and the timetable
	  Ranks     the leaderboards across every server
	Everything comes from the server in one Activity "Overview" call when the panel opens or a tab
	changes; the buttons call the other Activity actions and refresh.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Missions = require(Shared.Missions)
local Objectives = require(Shared.Objectives)
local Remotes = require(Shared.Remotes)

local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local Activities = {}

local New = Theme.New
local C = Theme.Colors

local TABS = { "Missions", "Jobs", "Races", "Daily", "Events", "Ranks" }
local TAB_ICONS = { Missions = "⭐", Jobs = "📦", Races = "🏁", Daily = "🎁", Events = "🎉", Ranks = "📊" }

local current = "Missions"
local panel: Panel.Panel
local list: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local footer: TextLabel
local cancelButton: TextButton
local boardIndex = 1
local busy = false

local function call(action: string, a: any?, b: any?): (boolean, any)
	local ok, result, extra = pcall(function()
		return Remotes.Function("Activity"):InvokeServer(action, a, b)
	end)
	if not ok then
		return false, "No connection"
	end
	return result == true, extra
end

local function clear()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A row: title, a line under it, an optional progress bar, up to two buttons on the right
type Action = { Text: string, Color: Color3?, OnClick: () -> () }
local function row(order: number, title: string, sub: string, actions: { Action }?, progress: number?, height: number?): Frame
	local frame = New("Frame", { BackgroundColor3 = C.Card, Size = UDim2.new(1, -8, 0, height or 66), LayoutOrder = order, Parent = list })
	Theme.Corner(frame, 8)
	local width = if actions and #actions > 0 then 130 * #actions + 10 else 10
	Theme.Label({ Text = title, Size = UDim2.new(1, -width - 16, 0, 24), Position = UDim2.fromOffset(12, 6), TextSize = 20, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = frame })
	Theme.Label({ Text = sub, Size = UDim2.new(1, -width - 16, 0, 30), Position = UDim2.fromOffset(12, 30), TextSize = 14, Font = Theme.Body, Color = C.SubText, Align = Enum.TextXAlignment.Left, Wrapped = true, Stroke = 1, Parent = frame })
	if progress then
		local back = New("Frame", { BackgroundColor3 = Color3.fromRGB(28, 28, 31), Size = UDim2.new(1, -width - 24, 0, 6), Position = UDim2.new(0, 12, 1, -10), Parent = frame })
		Theme.Round(back)
		local fill = New("Frame", { BackgroundColor3 = if progress >= 1 then C.Cash else C.Orange, Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1), Parent = back })
		Theme.Round(fill)
	end
	if actions then
		for i, action in actions do
			Theme.Button({
				Text = action.Text,
				Size = UDim2.fromOffset(122, 40),
				Position = UDim2.new(1, -10 - (i - 1) * 130, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Color = action.Color or C.Green,
				TextSize = 17,
				Parent = frame,
				OnClick = action.OnClick,
			})
		end
	end
	return frame
end

local function heading(order: number, text: string)
	Theme.Label({ Text = text, Size = UDim2.new(1, -8, 0, 28), TextSize = 22, Color = C.Gold, Align = Enum.TextXAlignment.Left, Stroke = 2, LayoutOrder = order, Parent = list })
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local refresh: () -> ()

local function act(action: string, a: any?, closeAfter: boolean?)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, message = call(action, a)
		busy = false
		Toasts.Message(if ok then "Info" else "Error", tostring(message or (if ok then "Done" else "Couldn't do that")))
		if ok and closeAfter then
			local cb = panel.OnClose
			if cb then
				cb()
			end
		else
			refresh()
		end
	end)
end

local builders: { [string]: (any) -> () } = {}

builders.Missions = function(data: any)
	local missions = if type(data.Missions) == "table" then data.Missions else {}
	heading(0, "Chapter 1 · Flighty Courier")
	for i, m in missions do
		local giver = Missions.Givers[m.Giver]
		local icon = if giver then giver.Icon else "⭐"
		local sub = string.format("%s · %s + %d XP%s", m.Giver, Economy.FormatCash(m.Cash), m.Xp, if m.TimeLimit then string.format(" · %s limit", duration(m.TimeLimit)) else "")
		if m.Status == "Ready" then
			row(i, string.format("%s %s", icon, m.Name), sub .. "\n" .. tostring(m.Intro), {
				{ Text = "Start", OnClick = function()
					act("StartMission", m.Id, true)
				end },
			}, nil, 88)
		elseif m.Status == "Done" then
			row(i, string.format("✅ %s", m.Name), sub)
		else
			row(i, string.format("🔒 %s", m.Name), string.format("Opens at level %d, after the one before it", m.Level))
		end
	end
end

builders.Jobs = function(data: any)
	local jobs = if type(data.Jobs) == "table" then data.Jobs else {}
	heading(0, "Flighty Courier · deliveries near you")
	if #jobs == 0 then
		row(1, "No jobs right now", "Ride somewhere busier, or check back in a minute")
	end
	for i, job in jobs do
		row(i, string.format("📦 %s → %s", tostring(job.From), tostring(job.To)), string.format("%.1f km · %s%s · %s to deliver · tip for time to spare", job.Km, Economy.FormatCash(job.Pay), if job.Rush then " x2 Courier Rush!" else "", duration(job.TimeLimit)), {
			{ Text = "Take job", OnClick = function()
				act("StartJob", job.Index, true)
			end },
		})
	end
end

builders.Races = function(data: any)
	local races = if type(data.Races) == "table" then data.Races else {}
	heading(0, "Time trials and races")
	for i, race in races do
		local best = if race.Best then string.format("Best %s", Objectives.FormatTime(race.Best)) else "No time yet"
		local sub = string.format("%.1f km · 🥇 %s  🥈 %s  🥉 %s · %s · up to %s\n%s", race.Km, Objectives.FormatTime(race.Gold), Objectives.FormatTime(race.Silver), Objectives.FormatTime(race.Bronze), best, Economy.FormatCash(race.Pay), tostring(race.Blurb))
		if race.Locked then
			row(i, string.format("🔒 %s", race.Name), string.format("Opens at level %d", race.Level))
		else
			local raceAction: Action = if race.Joined then { Text = "Leave lobby", Color = C.Red, OnClick = function()
				act("LeaveRace")
			end } else { Text = if race.Lobby > 0 then string.format("Race (%d in)", race.Lobby) else "Race", Color = C.Orange, OnClick = function()
				act("JoinRace", race.Id, true)
			end }
			local actions: { Action } = {
				{ Text = "Time trial", Color = Color3.fromRGB(150, 90, 230), OnClick = function()
					act("StartTrial", race.Id, true)
				end },
				raceAction,
			}
			row(i, string.format("🏁 %s", race.Name), sub, actions, nil, 88)
		end
	end
end

builders.Daily = function(data: any)
	local daily = if type(data.Daily) == "table" then data.Daily else {}
	heading(0, string.format("🔥 Streak: %d day%s", daily.Streak or 0, if daily.Streak == 1 then "" else "s"))
	if daily.CanClaim then
		row(1, string.format("🎁 Day %d reward", daily.NextStreak or 1), string.format("%s today · come back every day for more (up to %s)", Economy.FormatCash(daily.NextReward or 0), Economy.FormatCash(2500)), {
			{ Text = "Claim", Color = C.Gold, OnClick = function()
				act("ClaimStreak")
			end },
		})
	else
		row(1, "🎁 Today's reward claimed", string.format("Next one in %s", duration(daily.DayEnds or 0)))
	end
	local order = 2
	type Section = { Name: string, Rows: { any }, Ends: number }
	local sections: { Section } = {
		{ Name = "Today", Rows = daily.Day or {}, Ends = daily.DayEnds or 0 },
		{ Name = "This week", Rows = daily.Week or {}, Ends = daily.WeekEnds or 0 },
	}
	for _, section in sections do
		heading(order, string.format("%s · resets in %s", section.Name, duration(section.Ends)))
		order += 1
		for _, c in section.Rows do
			local done = c.Progress >= c.Goal
			local actions: { Action }? = nil
			if c.Claimed then
				actions = nil
			elseif done then
				actions = { { Text = "Claim", Color = C.Gold, OnClick = function()
					act("ClaimChallenge", c.Id)
				end } }
			end
			local goal = if c.Goal >= 1000 and string.find(c.Text, "km") then string.format("%.1f / %.0f km", c.Progress / 1000, c.Goal / 1000) else string.format("%d / %d", math.floor(c.Progress), c.Goal)
			row(order, string.format("%s %s", if c.Claimed then "✅" else "🎯", c.Text), string.format("%s · %s", goal, Economy.FormatCash(c.Reward)), actions, c.Progress / math.max(c.Goal, 1))
			order += 1
		end
	end
end

builders.Events = function(data: any)
	local events = if type(data.Events) == "table" then data.Events else {}
	local now = events.Current
	if now then
		heading(0, "On now")
		row(1, string.format("%s %s", now.Icon, now.Name), string.format("%s · %s left", now.Text, duration(now.Ends)))
	else
		heading(0, "No event right now")
	end
	heading(2, "Coming up")
	for i, e in events.Upcoming or {} do
		row(2 + i, string.format("%s %s", e.Icon, e.Name), string.format("%s · in %s (10 minutes)", e.Text, duration(e.In)))
	end
end

builders.Ranks = function(data: any)
	local boards = if type(data.Boards) == "table" then data.Boards else {}
	if #boards == 0 then
		heading(0, "Leaderboards are loading")
		return
	end
	boardIndex = math.clamp(boardIndex, 1, #boards)
	-- the board picker
	local picker = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 76), LayoutOrder = 0, Parent = list })
	New("UIGridLayout", { CellSize = UDim2.fromOffset(150, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = picker })
	for i, board in boards do
		Theme.Button({ Text = board.Name, Size = UDim2.fromOffset(150, 32), Color = if i == boardIndex then C.Orange else C.Gray, TextSize = 14, LayoutOrder = i, Parent = picker, OnClick = function()
			boardIndex = i
			refresh()
		end })
	end
	picker.Size = UDim2.new(1, -8, 0, math.ceil(#boards / 4) * 38)
	local board = boards[boardIndex]
	local function format(value: number): string
		if board.Unit == "$" then
			return Economy.FormatCash(value)
		elseif board.Unit == "time" then
			return Objectives.FormatTime(value)
		elseif board.Unit == "s" then
			return string.format("%.1f s", value)
		elseif board.Unit == "km/h" then
			return string.format("%d km/h", math.floor(value))
		end
		return tostring(math.floor(value))
	end
	heading(1, board.Name .. (if board.Mine then " · you: " .. format(board.Mine) else ""))
	if #board.Top == 0 then
		row(2, "Nobody yet", "Be the first on this board")
	end
	for i, entry in board.Top do
		local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else string.format("%d.", i)
		row(1 + i, string.format("%s %s", medal, tostring(entry.Name)), format(entry.Value), nil, nil, 50)
	end
end

refresh = function()
	task.spawn(function()
		local ok, data = call("Overview")
		clear()
		for name, button in tabButtons do
			button.BackgroundColor3 = if name == current then C.Orange else C.Gray
		end
		if not ok or type(data) ~= "table" then
			heading(0, "Can't reach the server: try again in a moment")
			return
		end
		local builder = builders[current]
		if builder then
			builder(data)
		end
		local active = data.Active
		cancelButton.Visible = active ~= nil
		footer.Text = if active then string.format("Doing: %s", tostring(active.Title)) else ""
	end)
end

function Activities.new(gui: Instance): Panel.Panel
	panel = Panel.new(gui, "Activities", "PLAY", Vector2.new(820, 560))
	local tabs = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = panel.Body })
	Theme.List(tabs, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	for i, name in TABS do
		tabButtons[name] = Theme.Button({ Text = TAB_ICONS[name] .. " " .. name, Size = UDim2.fromOffset(124, 36), Color = C.Gray, TextSize = 17, LayoutOrder = i, Parent = tabs, OnClick = function()
			current = name
			refresh()
		end })
	end
	list = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -96),
		Position = UDim2.fromOffset(0, 48),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = panel.Body,
	})
	Theme.List(list, Enum.FillDirection.Vertical, 6)
	footer = Theme.Label({ Text = "", Size = UDim2.new(1, -170, 0, 36), Position = UDim2.new(0, 0, 1, -38), TextSize = 18, Color = C.SubText, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = panel.Body })
	cancelButton = Theme.Button({ Text = "Give up", Size = UDim2.fromOffset(150, 36), Position = UDim2.new(1, 0, 1, -38), AnchorPoint = Vector2.new(1, 0), Color = C.Red, TextSize = 18, Parent = panel.Body, OnClick = function()
		act("Cancel")
	end })
	cancelButton.Visible = false
	panel.Refresh = refresh
	return panel
end

-- Open on one tab next time (the Ranks app)
function Activities.Show(tab: string)
	if table.find(TABS, tab) then
		current = tab
	end
end

return Activities
