--[[
	Achievements: goals measured from the save (Profile: Stats, Level, bikes, paints), each with a
	cash reward the player claims on the Stats screen (UI/StatsScreen). ShopService checks the
	progress itself before paying, and remembers what's claimed in Profile.Achievements.
]]

local Profile = require(script.Parent.Profile)

export type Achievement = {
	Id: string,
	Name: string,
	Icon: string,
	Description: string,
	Goal: number,
	Reward: number,
	Measure: (Profile.Data) -> number,
}

local Achievements = {}

local function stat(name: string): (Profile.Data) -> number
	return function(data: Profile.Data): number
		return (data.Stats :: any)[name] or 0
	end
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

Achievements.List = {
	{ Id = "km1", Name = "First Kilometre", Icon = "🛣", Description = "Ride 1 km", Goal = 1000, Reward = 250, Measure = stat("Distance") },
	{ Id = "km25", Name = "Commuter", Icon = "🏙", Description = "Ride 25 km", Goal = 25000, Reward = 2500, Measure = stat("Distance") },
	{ Id = "km100", Name = "Road Warrior", Icon = "🗺", Description = "Ride 100 km", Goal = 100000, Reward = 10000, Measure = stat("Distance") },
	{ Id = "wheelie5", Name = "Front Wheel? Optional", Icon = "🏍", Description = "Hold a 5 s wheelie", Goal = 5, Reward = 500, Measure = stat("BestWheelie") },
	{ Id = "wheelie20", Name = "Wheelie King", Icon = "👑", Description = "Hold a 20 s wheelie", Goal = 20, Reward = 5000, Measure = stat("BestWheelie") },
	{ Id = "air2", Name = "Frequent Flyer", Icon = "🕊", Description = "Stay in the air for 2 s", Goal = 2, Reward = 750, Measure = stat("LongestAir") },
	{ Id = "air4", Name = "Orbit", Icon = "🚀", Description = "Stay in the air for 4 s", Goal = 4, Reward = 4000, Measure = stat("LongestAir") },
	{ Id = "flip1", Name = "Upside Down", Icon = "🔄", Description = "Land a flip", Goal = 1, Reward = 1000, Measure = stat("Flips") },
	{ Id = "flip25", Name = "Flip Machine", Icon = "🌀", Description = "Land 25 flips", Goal = 25, Reward = 8000, Measure = stat("Flips") },
	{ Id = "stars3", Name = "Most Wanted", Icon = "🚨", Description = "Reach 3 wanted stars", Goal = 3, Reward = 1500, Measure = stat("MaxStars") },
	{ Id = "stars5", Name = "Public Enemy", Icon = "🚁", Description = "Reach 5 wanted stars", Goal = 5, Reward = 6000, Measure = stat("MaxStars") },
	{ Id = "escape1", Name = "Getaway", Icon = "💨", Description = "Escape the police", Goal = 1, Reward = 1000, Measure = stat("Escapes") },
	{ Id = "escape10", Name = "Ghost Rider", Icon = "👻", Description = "Escape the police 10 times", Goal = 10, Reward = 7500, Measure = stat("Escapes") },
	{ Id = "busted1", Name = "Book 'Em", Icon = "🚓", Description = "Get busted (it happens)", Goal = 1, Reward = 200, Measure = stat("Busts") },
	{ Id = "earn10k", Name = "Side Hustle", Icon = "💵", Description = "Earn $10,000 riding", Goal = 10000, Reward = 1000, Measure = stat("Earned") },
	{ Id = "earn250k", Name = "Big Money", Icon = "💰", Description = "Earn $250,000 riding", Goal = 250000, Reward = 25000, Measure = stat("Earned") },
	{ Id = "level10", Name = "Regular", Icon = "⭐", Description = "Reach level 10", Goal = 10, Reward = 3000, Measure = function(data: Profile.Data): number
		return data.Level
	end },
	{ Id = "level30", Name = "Legend", Icon = "🌟", Description = "Reach level 30", Goal = 30, Reward = 20000, Measure = function(data: Profile.Data): number
		return data.Level
	end },
	{ Id = "bikes3", Name = "Collector", Icon = "🏍", Description = "Own 3 bikes", Goal = 3, Reward = 2000, Measure = function(data: Profile.Data): number
		return count(data.Owned)
	end },
	{ Id = "bikes8", Name = "Showroom", Icon = "🏆", Description = "Own 8 bikes", Goal = 8, Reward = 15000, Measure = function(data: Profile.Data): number
		return count(data.Owned)
	end },
	{ Id = "paints5", Name = "Fresh Coat", Icon = "🎨", Description = "Unlock 5 crate paints", Goal = 5, Reward = 2500, Measure = function(data: Profile.Data): number
		return count(data.Paints)
	end },
} :: { Achievement }

function Achievements.Get(id: string): Achievement?
	for _, a in Achievements.List do
		if a.Id == id then
			return a
		end
	end
	return nil
end

-- Progress 0..1 and whether it's done
function Achievements.Progress(a: Achievement, data: Profile.Data): (number, boolean)
	local value = a.Measure(data)
	return math.clamp(value / a.Goal, 0, 1), value >= a.Goal
end

return Achievements
