--[[
	RaceService: the courses in Shared/Races, two ways.

	  Time trials  on your own: ride to the start line, the clock starts as you cross it, every
	               checkpoint in order on the bike. Medals by time, pay by medal, best times saved.
	  Races        a lobby per course on the phone: once two riders are in, a countdown starts; at Go
	               everyone on their bike near the start line races, positions on the HUD, pay by
	               finishing place. It ends when all are home, or a while after the winner.

	A Race Day event doubles the pay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Events = require(Shared.Events)
local Objectives = require(Shared.Objectives)
local Races = require(Shared.Races)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local DataService = require(script.Parent.DataService)
local BikeService = require(script.Parent.BikeService)
local EconomyService = require(script.Parent.EconomyService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local RaceService = {}

RaceService.Finished = Signal.new() -- (player, courseId, seconds, place?)
RaceService.COUNTDOWN = 20
RaceService.START_RADIUS = 160
RaceService.WAIT = 120 -- seconds one rider waits for another before the lobby closes
RaceService.AFTER_WINNER = 90
RaceService.MAX = 8

type Finish = { Player: Player, Time: number, Place: number }
type Lobby = {
	Course: Races.Course,
	Racers: { Player },
	State: string, -- "Open", "Countdown", "Running"
	OpenedAt: number,
	StartAt: number,
	Starters: number,
	Finished: { Finish },
	WinnerAt: number?,
	Running: { [Player]: boolean },
}

local lobbies: { [string]: Lobby } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function notify(player: Player, kind: string, text: string)
	Remotes.Event("Notify"):FireClient(player, kind, text)
end

local function checkpoints(built: Races.Built): { Objectives.Step }
	local steps = {}
	for i, p in built.Points do
		local text = if i == #built.Points then "Ride to the finish!" else string.format("Checkpoint %d of %d", i, #built.Points)
		table.insert(steps, Objectives.Reach(text, p, Objectives.RACE_RADIUS, true))
	end
	return steps
end

local function saveTime(player: Player, courseId: string, seconds: number): (boolean, number?)
	local data = DataService.Get(player)
	if not data then
		return false, nil
	end
	local best = data.BestTimes[courseId]
	local rounded = math.floor(seconds * 10 + 0.5) / 10
	if not best or rounded < best then
		data.BestTimes[courseId] = rounded
		return true, best
	end
	return false, best
end

local function canRace(player: Player, id: any): (Races.Course?, string?)
	local course = if type(id) == "string" then Races.Get(id) else nil
	local data = DataService.Get(player)
	if not course or not data then
		return nil, "No such course"
	end
	if data.Level < course.Level then
		return nil, string.format("Opens at level %d", course.Level)
	end
	return course, nil
end

function RaceService.StartTrial(player: Player, id: any): (boolean, string)
	local course, problem = canRace(player, id)
	if not course then
		return false, problem or "No such course"
	end
	RaceService.Leave(player)
	local built = Races.Build(course)
	local steps = { Objectives.Reach("Ride to the start line", built.Start, Objectives.RACE_RADIUS, true) }
	for _, step in checkpoints(built) do
		table.insert(steps, step)
	end
	ObjectiveService.Start(player, {
		Id = "trial_" .. course.Id,
		Kind = "Trial",
		Title = course.Name .. " · time trial",
		Steps = steps,
		ClockFrom = 2,
		TimeLimit = built.Bronze * 3,
		Reward = { Cash = built.Pay, Xp = math.floor(built.Pay * 0.6) },
	}, {
		Pay = false,
		OnDone = function(who: Player, run, ok: boolean)
			if not ok then
				return
			end
			local seconds = now() - run.StartedAt
			local medal = Races.Medal(built, seconds)
			local newBest, best = saveTime(who, course.Id, seconds)
			local cash = math.floor(built.Pay * Races.MEDAL_PAY[medal] * Events.Multiplier(now(), "Races"))
			EconomyService.Reward(who, cash, math.floor(cash * 0.6), "Time trial · " .. medal)
			local data = DataService.Get(who)
			if data then
				data.Stats.Races += 1
				DataService.Changed(who)
			end
			RaceService.Finished:Fire(who, course.Id, seconds, nil)
			Remotes.Event("Race"):FireClient(who, "Results", { Name = course.Name, Trial = true, Time = seconds, Medal = medal, Best = best, NewBest = newBest, Cash = cash })
		end,
	})
	return true, course.Name
end

local function lobbyInfo(lobby: Lobby): { [string]: any }
	local names = {}
	for _, racer in lobby.Racers do
		table.insert(names, racer.DisplayName)
	end
	return { Course = lobby.Course.Id, Name = lobby.Course.Name, Racers = names, State = lobby.State, StartAt = lobby.StartAt, Start = Races.Build(lobby.Course).Start }
end

local function broadcast(lobby: Lobby, kind: string, data: any)
	for _, racer in lobby.Racers do
		Remotes.Event("Race"):FireClient(racer, kind, data)
	end
end

local function clear(player: Player)
	player:SetAttribute("RaceLobby", nil)
	player:SetAttribute("RacePos", nil)
end

function RaceService.Leave(player: Player)
	for id, lobby in lobbies do
		local index = table.find(lobby.Racers, player)
		if index then
			table.remove(lobby.Racers, index)
			if lobby.Running[player] then
				ObjectiveService.Cancel(player, "Left the race")
			end
			clear(player)
			if #lobby.Racers == 0 then
				lobbies[id] = nil
			else
				if lobby.State == "Countdown" and #lobby.Racers < 2 then
					lobby.State = "Open"
					lobby.OpenedAt = now()
				end
				broadcast(lobby, "Lobby", lobbyInfo(lobby))
			end
		end
	end
end

function RaceService.Join(player: Player, id: any): (boolean, string)
	local course, problem = canRace(player, id)
	if not course then
		return false, problem or "No such course"
	end
	local existing = lobbies[course.Id]
	if existing and table.find(existing.Racers, player) then
		return true, "You're in the " .. course.Name .. " lobby"
	end
	if existing and existing.State == "Running" then
		return false, "That race has started: join the next one"
	end
	if existing and #existing.Racers >= RaceService.MAX then
		return false, "That race is full"
	end
	RaceService.Leave(player)
	local lobby = existing
	if not lobby then
		lobby = { Course = course, Racers = {}, State = "Open", OpenedAt = now(), StartAt = 0, Starters = 0, Finished = {}, Running = {} }
		lobbies[course.Id] = lobby
	end
	local l = lobby :: Lobby
	table.insert(l.Racers, player)
	player:SetAttribute("RaceLobby", course.Id)
	if #l.Racers >= 2 and l.State == "Open" then
		l.State = "Countdown"
		l.StartAt = now() + RaceService.COUNTDOWN
	end
	broadcast(l, "Lobby", lobbyInfo(l))
	return true, "Joined the " .. course.Name .. " lobby: ride to the start line"
end

local function dissolve(id: string, lobby: Lobby)
	for _, racer in lobby.Racers do
		clear(racer)
	end
	lobbies[id] = nil
end

local function finished(lobby: Lobby, who: Player, run: ObjectiveService.Run, ok: boolean, reason: string)
	lobby.Running[who] = nil
	if not ok then
		if reason ~= "Race over" and reason ~= "Left the race" then
			notify(who, "Error", "🏁 Out of the race: " .. reason)
		end
		return
	end
	local seconds = now() - run.StartedAt
	local place = #lobby.Finished + 1
	table.insert(lobby.Finished, { Player = who, Time = seconds, Place = place })
	if place == 1 then
		lobby.WinnerAt = now()
	end
	local built = Races.Build(lobby.Course)
	local cash = math.floor(built.Pay * (Races.PLACE_PAY[place] or 0.5) * Events.Multiplier(now(), "Races"))
	EconomyService.Reward(who, cash, math.floor(cash * 0.6), string.format("Race · %s", if place == 1 then "1st!" elseif place == 2 then "2nd" elseif place == 3 then "3rd" else place .. "th"))
	saveTime(who, lobby.Course.Id, seconds)
	local data = DataService.Get(who)
	if data then
		data.Stats.Races += 1
		if place == 1 and lobby.Starters >= 2 then
			data.Stats.Wins += 1
		end
		DataService.Changed(who)
	end
	who:SetAttribute("RacePos", string.format("%d/%d", place, lobby.Starters))
	RaceService.Finished:Fire(who, lobby.Course.Id, seconds, place)
	Remotes.Event("Race"):FireClient(who, "Finished", { Place = place, Of = lobby.Starters, Time = seconds, Cash = cash })
end

local function go(id: string, lobby: Lobby)
	local built = Races.Build(lobby.Course)
	local starters = {}
	for _, racer in lobby.Racers do
		local ride = BikeService.Get(racer)
		if ride and ride.Riding and (ride.Root.Position - built.Start).Magnitude < RaceService.START_RADIUS then
			table.insert(starters, racer)
		else
			notify(racer, "Error", "🏁 You weren't on your bike at the start line: you missed the race")
			clear(racer)
		end
	end
	lobby.Racers = starters
	if #starters == 0 then
		lobbies[id] = nil
		return
	end
	lobby.State = "Running"
	lobby.StartAt = now()
	lobby.Starters = #starters
	for _, racer in starters do
		lobby.Running[racer] = true
		ObjectiveService.Start(racer, {
			Id = "race_" .. id,
			Kind = "Race",
			Title = lobby.Course.Name,
			Steps = checkpoints(built),
			TimeLimit = built.Bronze * 2.5,
			Reward = { Cash = 0, Xp = 0 },
		}, {
			Pay = false,
			OnDone = function(who: Player, run, ok: boolean, reason: string)
				finished(lobby, who, run, ok, reason)
			end,
		})
	end
	broadcast(lobby, "Go", lobbyInfo(lobby))
end

local function standings(lobby: Lobby)
	local built = Races.Build(lobby.Course)
	type Entry = { Player: Player, Key: number }
	local live: { Entry } = {}
	for racer in lobby.Running do
		local run = ObjectiveService.Active(racer)
		local ride = BikeService.Get(racer)
		if run and ride then
			local target = built.Points[math.min(run.Step, #built.Points)]
			table.insert(live, { Player = racer, Key = run.Step * 1e7 - (ride.Root.Position - target).Magnitude })
		end
	end
	table.sort(live, function(a, b)
		return a.Key > b.Key
	end)
	for i, entry in live do
		entry.Player:SetAttribute("RacePos", string.format("%d/%d", #lobby.Finished + i, lobby.Starters))
	end
end

local function step()
	local t = now()
	for id, lobby in table.clone(lobbies) do
		if lobby.State == "Open" then
			if t - lobby.OpenedAt > RaceService.WAIT and #lobby.Racers <= 1 then
				for _, racer in lobby.Racers do
					notify(racer, "Info", "🏁 Nobody joined the " .. lobby.Course.Name .. ": try its time trial")
				end
				dissolve(id, lobby)
			end
		elseif lobby.State == "Countdown" then
			if t >= lobby.StartAt then
				go(id, lobby)
			end
		elseif lobby.State == "Running" then
			standings(lobby)
			local over = next(lobby.Running) == nil or (lobby.WinnerAt ~= nil and t - (lobby.WinnerAt :: number) > RaceService.AFTER_WINNER)
			if over then
				for racer in table.clone(lobby.Running) do
					ObjectiveService.Cancel(racer, "Race over")
				end
				local results = {}
				for _, f in lobby.Finished do
					table.insert(results, { Name = f.Player.DisplayName, Time = f.Time, Place = f.Place })
				end
				broadcast(lobby, "Results", { Name = lobby.Course.Name, Results = results })
				dissolve(id, lobby)
			end
		end
	end
end

function RaceService.Init()
	ObjectiveService.Handle("StartTrial", function(player: Player, id: any)
		return RaceService.StartTrial(player, id)
	end)
	ObjectiveService.Handle("JoinRace", function(player: Player, id: any)
		return RaceService.Join(player, id)
	end)
	ObjectiveService.Handle("LeaveRace", function(player: Player)
		RaceService.Leave(player)
		return true, "Left the race"
	end)
	ObjectiveService.Overview("Races", function(player: Player)
		local data = DataService.Get(player)
		local list = {}
		for _, course in Races.Courses do
			local built = Races.Build(course)
			local lobby = lobbies[course.Id]
			table.insert(list, {
				Id = course.Id,
				Name = course.Name,
				Blurb = course.Blurb,
				Level = course.Level,
				Locked = data ~= nil and data.Level < course.Level,
				Km = built.Length / Config.STUDS_PER_METER / 1000, -- (as the bike measures it: its speedometer's metres)
				Gold = built.Gold,
				Silver = built.Silver,
				Bronze = built.Bronze,
				Pay = built.Pay,
				Best = if data then data.BestTimes[course.Id] else nil,
				Lobby = if lobby then #lobby.Racers else 0,
				State = if lobby then lobby.State else "",
				Joined = lobby ~= nil and table.find(lobby.Racers, player) ~= nil,
			})
		end
		return list
	end)
	Players.PlayerRemoving:Connect(RaceService.Leave)
	-- work the courses out ahead of the first phone (road-graph searches), a course a frame
	task.spawn(function()
		for _, course in Races.Courses do
			Races.Build(course)
			task.wait()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			step()
		end
	end)
end

return RaceService
