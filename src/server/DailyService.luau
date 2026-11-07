--[[
	DailyService: the login streak and the daily and weekly challenges (Shared/Dailies). Counters
	come from the server's own signals (validated tricks, the distance the pay loop measures, cash
	paid, deliveries, races, police escapes) into the save's Daily progress, which resets when the
	day or week turns over. Rewards are claimed on the phone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dailies = require(Shared.Dailies)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local PoliceService = require(script.Parent.PoliceService)
local JobService = require(script.Parent.JobService)
local RaceService = require(script.Parent.RaceService)

local DailyService = {}

-- the clock (os.time) the service reads; the smoke test moves it on a day
DailyService.Clock = function(): number
	return os.time()
end

local lastDistance: { [Player]: number } = {}

-- Start a new day's and week's counters when they turn over
local function roll(daily: Profile.Daily)
	local t = DailyService.Clock()
	local day, week = Dailies.Day(t), Dailies.Week(t)
	if daily.Day ~= day then
		daily.Day = day
		table.clear(daily.Progress)
		for id in table.clone(daily.Claimed) do
			if not Dailies.IsWeekly(id) then
				daily.Claimed[id] = nil
			end
		end
	end
	if daily.Week ~= week then
		daily.Week = week
		table.clear(daily.WeekProgress)
		for id in table.clone(daily.Claimed) do
			if Dailies.IsWeekly(id) then
				daily.Claimed[id] = nil
			end
		end
	end
end

function DailyService.Add(player: Player, stat: string, amount: number)
	local data = DataService.Get(player)
	if not data or amount <= 0 then
		return
	end
	local daily = data.Daily
	roll(daily)
	daily.Progress[stat] = (daily.Progress[stat] or 0) + amount
	daily.WeekProgress[stat] = (daily.WeekProgress[stat] or 0) + amount
end

local function today(): ({ Dailies.Challenge }, { Dailies.Challenge })
	local t = DailyService.Clock()
	return Dailies.ForDay(Dailies.Day(t)), Dailies.ForWeek(Dailies.Week(t))
end

function DailyService.ClaimStreak(player: Player): (boolean, string)
	local data = DataService.Get(player)
	if not data then
		return false, "Your save is still loading"
	end
	local day = Dailies.Day(DailyService.Clock())
	local daily = data.Daily
	if daily.LastLogin == day then
		return false, "Already claimed today: come back tomorrow"
	end
	daily.Streak = if daily.LastLogin == day - 1 then daily.Streak + 1 else 1
	daily.LastLogin = day
	local reward = Dailies.StreakReward(daily.Streak)
	EconomyService.Reward(player, reward, reward * 0.4, string.format("Day %d streak", daily.Streak))
	return true, string.format("Day %d: +$%d", daily.Streak, reward)
end

function DailyService.ClaimChallenge(player: Player, id: any): (boolean, string)
	local data = DataService.Get(player)
	if not data or type(id) ~= "string" then
		return false, "No such challenge"
	end
	local daily = data.Daily
	roll(daily)
	local days, weeks = today()
	for _, list in { days, weeks } do
		for _, challenge in list do
			if challenge.Id == id then
				local progress = (if Dailies.IsWeekly(id) then daily.WeekProgress else daily.Progress)[challenge.Stat] or 0
				if daily.Claimed[id] then
					return false, "Already claimed"
				elseif progress < challenge.Goal then
					return false, "Not done yet"
				end
				daily.Claimed[id] = true
				data.Stats.Challenges += 1
				EconomyService.Reward(player, challenge.Reward, challenge.Reward * 0.4, "Challenge: " .. challenge.Text)
				return true, challenge.Text
			end
		end
	end
	return false, "That challenge isn't on today"
end

local function overview(player: Player): { [string]: any }
	local data = DataService.Get(player)
	if not data then
		return {}
	end
	local daily = data.Daily
	roll(daily)
	local t = DailyService.Clock()
	local day = Dailies.Day(t)
	local nextStreak = if daily.LastLogin == day - 1 then daily.Streak + 1 elseif daily.LastLogin == day then daily.Streak else 1
	local days, weeks = today()
	local function rows(list: { Dailies.Challenge }, progress: { [string]: number }): { any }
		local out = {}
		for _, c in list do
			table.insert(out, { Id = c.Id, Text = c.Text, Goal = c.Goal, Progress = math.min(progress[c.Stat] or 0, c.Goal), Reward = c.Reward, Claimed = daily.Claimed[c.Id] == true })
		end
		return out
	end
	return {
		Streak = daily.Streak,
		CanClaim = daily.LastLogin ~= day,
		NextStreak = nextStreak,
		NextReward = Dailies.StreakReward(nextStreak),
		Rewards = Dailies.Streak,
		Day = rows(days, daily.Progress),
		Week = rows(weeks, daily.WeekProgress),
		DayEnds = (day + 1) * 86400 - t,
		WeekEnds = ((Dailies.Week(t) + 1) * 7 - 3) * 86400 - t,
	}
end

function DailyService.Init()
	EconomyService.Trick:Connect(function(player: Player, kind: string, value: number)
		if kind == "Wheelie" then
			DailyService.Add(player, "Wheelie", value)
		elseif kind == "Jump" then
			DailyService.Add(player, "Air", 1)
		elseif kind == "Flip" then
			DailyService.Add(player, "Flips", value)
		elseif kind == "AirTrick" then
			DailyService.Add(player, "AirTricks", 1)
		elseif kind == "Drift" then
			DailyService.Add(player, "Drift", value)
		elseif kind == "Loop" then
			DailyService.Add(player, "Loops", 1)
		end
	end)
	EconomyService.Earned:Connect(function(player: Player, amount: number)
		DailyService.Add(player, "Earned", amount)
	end)
	JobService.Delivered:Connect(function(player: Player)
		DailyService.Add(player, "Deliveries", 1)
	end)
	RaceService.Finished:Connect(function(player: Player)
		DailyService.Add(player, "Races", 1)
	end)
	PoliceService.Escaped:Connect(function(player: Player)
		DailyService.Add(player, "Escapes", 1)
	end)
	ObjectiveService.Handle("ClaimStreak", function(player: Player)
		return DailyService.ClaimStreak(player)
	end)
	ObjectiveService.Handle("ClaimChallenge", function(player: Player, id: any)
		return DailyService.ClaimChallenge(player, id)
	end)
	ObjectiveService.Overview("Daily", overview)
	-- the distance the pay loop measures, every few seconds; and a nudge when the streak's waiting
	Players.PlayerAdded:Connect(function(player)
		local data = DataService.WaitFor(player)
		if data and data.Daily.LastLogin ~= Dailies.Day(DailyService.Clock()) then
			task.delay(8, function()
				if player.Parent then
					Remotes.Event("Notify"):FireClient(player, "Info", "🎁 Your daily reward is waiting: phone > Play > Daily")
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastDistance[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				if data then
					local was = lastDistance[player]
					lastDistance[player] = data.Stats.Distance
					if was then
						DailyService.Add(player, "Distance", data.Stats.Distance - was)
					end
				end
			end
		end
	end)
end

return DailyService
