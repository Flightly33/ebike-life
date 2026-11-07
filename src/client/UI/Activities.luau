--[[
	Activities: the phone's Play hub (also opened on the Ranks tab by the Ranks app). Tabs:
	  Missions  the story, chapter by chapter: who's asking, the reward, Start on the next one open
	  Jobs      three delivery offers near you: from, to, distance, pay, time limit
	  Races     every course: length, medal times, your best; a time trial, or the race lobby
	  Daily     the login streak and today's and this week's challenges, with Claim buttons
	  Events    the event running now and the timetable
	  Ranks     the leaderboards across every server
	Everything comes from the server in one Activity "Overview" call when the panel opens or a tab
	changes; the buttons call the other Activity actions and refresh. Built from UI/Kit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Missions = require(Shared.Missions)
local Objectives = require(Shared.Objectives)
local Remotes = require(Shared.Remotes)

local Kit = require(script.Parent.Kit)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Toasts = require(script.Parent.Toasts)

local Activities = {}

local New = Theme.New
local C = Theme.Colors
local R = Theme.Roles

local TABS = { "Missions", "Jobs", "Races", "Daily", "Events", "Ranks" }
local TAB_LABELS = { Missions = "⭐ Missions", Jobs = "📦 Jobs", Races = "🏁 Races", Daily = "🎁 Daily", Events = "🎉 Events", Ranks = "📊 Ranks" }

local current = "Missions"
local panel: Panel.Panel
local list: ScrollingFrame
local tabs: Kit.Tabs
local footer: TextLabel
local cancelButton: TextButton
local boardIndex = 1
local busy = false

-- Fired with the overview whenever it's fetched (the HUD's badges listen)
Activities.Fetched = nil :: ((any) -> ())?

local function call(action: string, a: any?, b: any?): (boolean, any)
	local ok, result, extra = pcall(function()
		return Remotes.Function("Activity"):InvokeServer(action, a, b)
	end)
	if not ok then
		return false, "No connection"
	end
	return result == true, extra
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
	Kit.Heading(list, "Chapter 1 · Flighty Courier", 0)
	for i, m in missions do
		local giver = Missions.Givers[m.Giver]
		local sub = string.format("%s · %s + %d XP%s", if giver then giver.Title else m.Giver, Economy.FormatCash(m.Cash), m.Xp, if m.TimeLimit then string.format(" · %s limit", duration(m.TimeLimit)) else "")
		if m.Status == "Ready" then
			Kit.Row(list, { Order = i, Icon = if giver then giver.Icon else "⭐", Title = m.Name, Sub = sub .. "\n\"" .. tostring(m.Intro) .. "\"", Height = 92, Accent = R.Mission, Actions = {
				{ Text = "Start", OnClick = function()
					act("StartMission", m.Id, true)
				end },
			} })
		elseif m.Status == "Done" then
			Kit.Row(list, { Order = i, Icon = "✅", Title = m.Name, Sub = sub, Dim = true })
		else
			Kit.Row(list, { Order = i, Icon = "🔒", Title = m.Name, Sub = string.format("Opens at level %d, after the one before it", m.Level), Dim = true })
		end
	end
end

builders.Jobs = function(data: any)
	local jobs = if type(data.Jobs) == "table" then data.Jobs else {}
	Kit.Heading(list, "Flighty Courier · deliveries near you", 0)
	if #jobs == 0 then
		Kit.Row(list, { Order = 1, Icon = "📭", Title = "No jobs right now", Sub = "Ride somewhere busier, or check back in a minute" })
	end
	for i, job in jobs do
		Kit.Row(list, { Order = i, Icon = "📦", Accent = R.Job, Title = string.format("%s → %s", tostring(job.From), tostring(job.To)), Sub = string.format("%.1f km · %s%s · %s to deliver · a tip for time to spare", job.Km, Economy.FormatCash(job.Pay), if job.Rush then " x2 Courier Rush!" else "", duration(job.TimeLimit)), Actions = {
			{ Text = "Take job", OnClick = function()
				act("StartJob", job.Index, true)
			end },
		} })
	end
end

builders.Races = function(data: any)
	local races = if type(data.Races) == "table" then data.Races else {}
	Kit.Heading(list, "Time trials and races", 0)
	for i, race in races do
		if race.Locked then
			Kit.Row(list, { Order = i, Icon = "🔒", Title = race.Name, Sub = string.format("Opens at level %d", race.Level), Dim = true })
			continue
		end
		local best = if race.Best then string.format("Best %s", Objectives.FormatTime(race.Best)) else "No time yet"
		local sub = string.format("%.1f km · 🥇 %s  🥈 %s  🥉 %s · %s · up to %s\n%s", race.Km, Objectives.FormatTime(race.Gold), Objectives.FormatTime(race.Silver), Objectives.FormatTime(race.Bronze), best, Economy.FormatCash(race.Pay), tostring(race.Blurb))
		local raceAction: Kit.Action = if race.Joined then { Text = "Leave lobby", Color = R.Negative, OnClick = function()
			act("LeaveRace")
		end } else { Text = if race.Lobby > 0 then string.format("Race (%d in)", race.Lobby) else "Race", Color = R.Accent, OnClick = function()
			act("JoinRace", race.Id, true)
		end }
		local actions: { Kit.Action } = {
			{ Text = "Time trial", Color = R.Trial, OnClick = function()
				act("StartTrial", race.Id, true)
			end },
			raceAction,
		}
		Kit.Row(list, { Order = i, Icon = "🏁", Accent = R.Race, Title = race.Name, Sub = sub, Height = 92, Actions = actions })
	end
end

builders.Daily = function(data: any)
	local daily = if type(data.Daily) == "table" then data.Daily else {}
	Kit.Heading(list, string.format("🔥 Streak: %d day%s", daily.Streak or 0, if daily.Streak == 1 then "" else "s"), 0)
	if daily.CanClaim then
		Kit.Row(list, { Order = 1, Icon = "🎁", Accent = R.Warning, Title = string.format("Day %d reward", daily.NextStreak or 1), Sub = string.format("%s today · come back every day for more (up to %s)", Economy.FormatCash(daily.NextReward or 0), Economy.FormatCash(2500)), Actions = {
			{ Text = "Claim", Color = R.Warning, OnClick = function()
				act("ClaimStreak")
			end },
		} })
	else
		Kit.Row(list, { Order = 1, Icon = "✅", Title = "Today's reward claimed", Sub = string.format("The next one in %s", duration(daily.DayEnds or 0)), Dim = true })
	end
	type Section = { Name: string, Rows: { any }, Ends: number }
	local sections: { Section } = {
		{ Name = "Today", Rows = daily.Day or {}, Ends = daily.DayEnds or 0 },
		{ Name = "This week", Rows = daily.Week or {}, Ends = daily.WeekEnds or 0 },
	}
	local order = 2
	for _, section in sections do
		Kit.Heading(list, string.format("%s · resets in %s", section.Name, duration(section.Ends)), order)
		order += 1
		for _, c in section.Rows do
			local done = c.Progress >= c.Goal
			local actions: { Kit.Action }? = nil
			if not c.Claimed and done then
				actions = { { Text = "Claim", Color = R.Warning, OnClick = function()
					act("ClaimChallenge", c.Id)
				end } }
			end
			local goal = if c.Goal >= 1000 and string.find(c.Text, "km") then string.format("%.1f / %.0f km", c.Progress / 1000, c.Goal / 1000) else string.format("%d / %d", math.floor(c.Progress), c.Goal)
			Kit.Row(list, { Order = order, Icon = if c.Claimed then "✅" else "🎯", Title = c.Text, Sub = string.format("%s · %s", goal, Economy.FormatCash(c.Reward)), Actions = actions, Progress = c.Progress / math.max(c.Goal, 1), Dim = c.Claimed })
			order += 1
		end
	end
end

builders.Events = function(data: any)
	local events = if type(data.Events) == "table" then data.Events else {}
	local now = events.Current
	if now then
		Kit.Heading(list, "On now", 0)
		Kit.Row(list, { Order = 1, Icon = now.Icon, Accent = R.Warning, Title = now.Name, Sub = string.format("%s · %s left", now.Text, duration(now.Ends)) })
	else
		Kit.Heading(list, "No event right now", 0)
	end
	Kit.Heading(list, "Coming up", 2)
	for i, e in events.Upcoming or {} do
		Kit.Row(list, { Order = 2 + i, Icon = e.Icon, Title = e.Name, Sub = string.format("%s · in %s (10 minutes)", e.Text, duration(e.In)) })
	end
end

builders.Ranks = function(data: any)
	local boards = if type(data.Boards) == "table" then data.Boards else {}
	if #boards == 0 then
		Kit.Heading(list, "Leaderboards are loading", 0)
		return
	end
	boardIndex = math.clamp(boardIndex, 1, #boards)
	-- the board picker
	local picker = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.ceil(#boards / 5) * 38), LayoutOrder = 0, Parent = list })
	New("UIGridLayout", { CellSize = UDim2.fromOffset(150, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = picker })
	for i, board in boards do
		Theme.Button({ Text = board.Name, Size = UDim2.fromOffset(150, 32), Color = if i == boardIndex then R.Accent else C.Gray, TextSize = 14, LayoutOrder = i, Parent = picker, OnClick = function()
			boardIndex = i
			refresh()
		end })
	end
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
	Kit.Heading(list, board.Name .. (if board.Mine then " · you: " .. format(board.Mine) else ""), 1)
	if #board.Top == 0 then
		Kit.Row(list, { Order = 2, Icon = "🏆", Title = "Nobody yet", Sub = "Be the first on this board" })
	end
	for i, entry in board.Top do
		local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else string.format("%d.", i)
		Kit.Row(list, { Order = 1 + i, Icon = medal, Title = tostring(entry.Name), Sub = format(entry.Value), Height = 54 })
	end
end

refresh = function()
	task.spawn(function()
		local ok, data = call("Overview")
		Kit.Clear(list)
		tabs.Set(current)
		if not ok or type(data) ~= "table" then
			Kit.Heading(list, "Can't reach the server: try again in a moment", 0)
			return
		end
		local builder = builders[current]
		if builder then
			builder(data)
		end
		local active = data.Active
		cancelButton.Visible = active ~= nil
		footer.Text = if active then string.format("Doing: %s", tostring(active.Title)) else ""
		local fetched = Activities.Fetched
		if fetched then
			fetched(data)
		end
	end)
end

function Activities.new(gui: Instance): Panel.Panel
	panel = Panel.new(gui, "Activities", "PLAY", Vector2.new(820, 560))
	tabs = Kit.Tabs(panel.Body, TABS, TAB_LABELS, function(name: string)
		current = name
		refresh()
	end)
	list = Kit.List(panel.Body, UDim2.new(1, 0, 1, -96), UDim2.fromOffset(0, 48), 6)
	footer = Theme.Label({ Text = "", Size = UDim2.new(1, -170, 0, 36), Position = UDim2.new(0, 0, 1, -38), TextSize = 18, Color = R.Muted, Align = Enum.TextXAlignment.Left, Stroke = 2, Parent = panel.Body })
	cancelButton = Theme.Button({ Text = "Give up", Size = UDim2.fromOffset(150, 36), Position = UDim2.new(1, 0, 1, -38), AnchorPoint = Vector2.new(1, 0), Color = R.Negative, TextSize = 18, Parent = panel.Body, OnClick = function()
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
