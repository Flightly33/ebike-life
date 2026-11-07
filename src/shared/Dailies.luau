--[[
	Dailies: the login streak and the daily and weekly challenges (DailyService keeps the score).
	Everyone gets the same challenges on the same day (picked from the pools by the day's number), so
	friends can do them together. Days and weeks are UTC; weeks start on Monday.

	Counters ("Stat"): Distance (m), Wheelie (s), Air (jumps landed), Flips, AirTricks, Drift (s),
	Loops, Deliveries, Races (finished), Escapes, Earned ($, every source).
]]

local Dailies = {}

export type Challenge = { Id: string, Text: string, Stat: string, Goal: number, Reward: number }

-- cash for day 1, 2, ... of a streak; the last one repeats
Dailies.Streak = { 250, 400, 600, 800, 1000, 1500, 2500 }
Dailies.PER_DAY = 3
Dailies.PER_WEEK = 4

Dailies.Daily = {
	{ Id = "d_ride5", Text = "Ride 5 km", Stat = "Distance", Goal = 5000, Reward = 300 },
	{ Id = "d_ride10", Text = "Ride 10 km", Stat = "Distance", Goal = 10000, Reward = 500 },
	{ Id = "d_wheelie30", Text = "Wheelie for 30 seconds in all", Stat = "Wheelie", Goal = 30, Reward = 350 },
	{ Id = "d_air10", Text = "Land 10 jumps", Stat = "Air", Goal = 10, Reward = 300 },
	{ Id = "d_flip3", Text = "Land 3 backflips", Stat = "Flips", Goal = 3, Reward = 400 },
	{ Id = "d_tricks10", Text = "Pull 10 air tricks", Stat = "AirTricks", Goal = 10, Reward = 400 },
	{ Id = "d_drift20", Text = "Drift for 20 seconds", Stat = "Drift", Goal = 20, Reward = 300 },
	{ Id = "d_loop2", Text = "Ride the loop twice", Stat = "Loops", Goal = 2, Reward = 350 },
	{ Id = "d_deliver3", Text = "Make 3 deliveries", Stat = "Deliveries", Goal = 3, Reward = 450 },
	{ Id = "d_race1", Text = "Finish a race or time trial", Stat = "Races", Goal = 1, Reward = 300 },
	{ Id = "d_escape1", Text = "Escape the police", Stat = "Escapes", Goal = 1, Reward = 400 },
	{ Id = "d_earn2k", Text = "Earn $2,000", Stat = "Earned", Goal = 2000, Reward = 350 },
} :: { Challenge }

Dailies.Weekly = {
	{ Id = "w_ride50", Text = "Ride 50 km", Stat = "Distance", Goal = 50000, Reward = 2500 },
	{ Id = "w_wheelie300", Text = "Wheelie for 5 minutes in all", Stat = "Wheelie", Goal = 300, Reward = 2500 },
	{ Id = "w_flip25", Text = "Land 25 backflips", Stat = "Flips", Goal = 25, Reward = 3000 },
	{ Id = "w_tricks75", Text = "Pull 75 air tricks", Stat = "AirTricks", Goal = 75, Reward = 3000 },
	{ Id = "w_deliver20", Text = "Make 20 deliveries", Stat = "Deliveries", Goal = 20, Reward = 4000 },
	{ Id = "w_race8", Text = "Finish 8 races or time trials", Stat = "Races", Goal = 8, Reward = 3000 },
	{ Id = "w_escape6", Text = "Escape the police 6 times", Stat = "Escapes", Goal = 6, Reward = 3500 },
	{ Id = "w_earn25k", Text = "Earn $25,000", Stat = "Earned", Goal = 25000, Reward = 3000 },
} :: { Challenge }

function Dailies.Day(t: number): number
	return math.floor(t / 86400)
end

-- (1 Jan 1970 was a Thursday: three days on, a week starts on a Monday)
function Dailies.Week(t: number): number
	return math.floor((math.floor(t / 86400) + 3) / 7)
end

function Dailies.StreakReward(streak: number): number
	return Dailies.Streak[math.clamp(streak, 1, #Dailies.Streak)]
end

-- `count` challenges from `pool`, the same for everyone with the same seed
local function pick(pool: { Challenge }, seed: number, count: number): { Challenge }
	local order = {}
	for i = 1, #pool do
		order[i] = i
	end
	local state = (seed * 7919 + 104729) % 2147483647
	for i = #order, 2, -1 do
		state = (state * 48271) % 2147483647
		local j = state % i + 1
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	for i = 1, math.min(count, #order) do
		table.insert(out, pool[order[i]])
	end
	return out
end

function Dailies.ForDay(day: number): { Challenge }
	return pick(Dailies.Daily, day, Dailies.PER_DAY)
end

function Dailies.ForWeek(week: number): { Challenge }
	return pick(Dailies.Weekly, week + 5000, Dailies.PER_WEEK)
end

function Dailies.IsWeekly(id: string): boolean
	return string.sub(id, 1, 2) == "w_"
end

-- What's waiting to be claimed at time `t` (the HUD's and phone's badges): the streak (1 or 0) plus
-- the challenges done and not claimed. Progress only counts for the day and week it belongs to.
export type Save = {
	LastLogin: number,
	Day: number,
	Week: number,
	Progress: { [string]: number },
	WeekProgress: { [string]: number },
	Claimed: { [string]: boolean },
}
function Dailies.Claimable(daily: Save, t: number): number
	local day, week = Dailies.Day(t), Dailies.Week(t)
	local count = if daily.LastLogin ~= day then 1 else 0
	if daily.Day == day then
		for _, c in Dailies.ForDay(day) do
			if (daily.Progress[c.Stat] or 0) >= c.Goal and not daily.Claimed[c.Id] then
				count += 1
			end
		end
	end
	if daily.Week == week then
		for _, c in Dailies.ForWeek(week) do
			if (daily.WeekProgress[c.Stat] or 0) >= c.Goal and not daily.Claimed[c.Id] then
				count += 1
			end
		end
	end
	return count
end

return Dailies
