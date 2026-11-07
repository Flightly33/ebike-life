--[[
	Missions: the story, "Flighty Courier", chapter 1. Each mission is given by one of the regulars
	(Nina runs the workshop at Flighty Mechanics, Marco the courier desk, Jet the stunt crew, Officer
	Reyes would like a word), opens at a level once the one before it is done, and is a list of
	objective steps (Shared/Objectives). MissionService starts them and saves which are done.

	A step here is { kind, text, value[, amount] }: a place name (Layout.Places, or
	"DealershipCharger") for Reach, an amount for the others, and for Trick the trick kind then the
	amount. A control in the text is written {Gas}, {Wheelie}, {MyRides}: the HUD puts in the key,
	pad button or touch button the player uses (UI/Objective.Keys).
]]

local Layout = require(script.Parent.City.Layout)
local Objectives = require(script.Parent.Objectives)

local Missions = {}

export type Mission = {
	Id: string,
	Chapter: number,
	Name: string,
	Giver: string,
	Level: number,
	Requires: string?,
	Intro: string,
	Outro: string,
	Steps: { { any } },
	TimeLimit: number?,
	ClockFrom: number?,
	Reward: Objectives.Reward,
}

Missions.Givers = {
	Nina = { Icon = "🔧", Title = "Nina · Flighty Mechanics" },
	Marco = { Icon = "📦", Title = "Marco · Flighty Courier" },
	Jet = { Icon = "🤸", Title = "Jet · the stunt crew" },
	Reyes = { Icon = "🚓", Title = "Officer Reyes" },
} :: { [string]: { Icon: string, Title: string } }

Missions.List = {
	{
		Id = "m00_tutorial", Chapter = 1, Name = "Welcome to Flighty", Giver = "Nina", Level = 1,
		Intro = "Hi, I'm Nina! Let's get you riding: take your bike out, open her up, pop a wheelie, then charge up next door.",
		Outro = "You're a natural. Keep your phone handy: Marco and Jet will be in touch.",
		Steps = {
			{ "Ride", "Open My Rides ({MyRides}), take your bike out and get on", 0 },
			{ "Speed", "Open the throttle ({Gas}): reach 20 km/h", 20 },
			{ "Wheelie", "Pull a wheelie: hold {Wheelie} with the gas for 1 second", 1 },
			{ "Reach", "Ride to the ⚡ charger beside Flighty Mechanics", "DealershipCharger" },
			{ "Reach", "Back to Flighty Mechanics to see Nina", "Dealership" },
		},
		Reward = { Cash = 300, Xp = 150 },
	},
	{
		Id = "m01_first_ride", Chapter = 1, Name = "First Ride", Giver = "Nina", Level = 1,
		Intro = "Welcome to Flighty! Take her round the block: ride to the Plaza, pull a wheelie, bring her back.",
		Outro = "Not a scratch on her. You'll do.",
		Steps = { { "Reach", "Ride to the Plaza", "Plaza" }, { "Wheelie", "Hold a wheelie for 2 seconds", 2 }, { "Reach", "Ride back to Flighty Mechanics", "Dealership" } },
		Reward = { Cash = 400, Xp = 250 },
	},
	{
		Id = "m02_wynwood", Chapter = 1, Name = "Wynwood Walls", Giver = "Jet", Level = 1, Requires = "m01_first_ride",
		Intro = "Nina says you can ride. Show me: meet me in Wynwood, throw some tricks, then the jump park.",
		Outro = "Okay, okay. You've got style.",
		Steps = { { "Reach", "Ride to Wynwood", "Wynwood" }, { "Trick", "Earn from tricks", "Score", 150 }, { "Reach", "Meet the crew at the Jump Park", "JumpPark" } },
		Reward = { Cash = 600, Xp = 300 },
	},
	{
		Id = "m03_air_time", Chapter = 1, Name = "Air Time", Giver = "Jet", Level = 2, Requires = "m02_wynwood",
		Intro = "Ramps are for flying. Get some proper air and stack two tricks.",
		Outro = "That's what I'm talking about!",
		Steps = { { "Reach", "Ride to the Jump Park", "JumpPark" }, { "Air", "Hang in the air for 1.2 seconds", 1.2 }, { "Trick", "Pull air tricks", "AirTrick", 2 } },
		Reward = { Cash = 700, Xp = 350 },
	},
	{
		Id = "m04_full_circle", Chapter = 1, Name = "Full Circle", Giver = "Jet", Level = 3, Requires = "m03_air_time",
		Intro = "Next door to the jump park there's a loop. Nobody rides it first time. Prove me wrong.",
		Outro = "Upside down and still smiling. Respect.",
		Steps = { { "Reach", "Ride to the Jump Park", "JumpPark" }, { "Trick", "Ride the loop at the Loop Park next door", "Loop", 1 } },
		Reward = { Cash = 800, Xp = 400 },
	},
	{
		Id = "m05_courier_test", Chapter = 1, Name = "Courier Test", Giver = "Marco", Level = 3, Requires = "m02_wynwood",
		Intro = "Nina says you're quick. Our riders cross the city in five minutes. Downtown, then the beach. Go.",
		Outro = "Under five. You're hired: deliveries are on your phone.",
		Steps = { { "Reach", "Ride Downtown", "Downtown" }, { "Reach", "Get to South Beach", "Beach" } },
		TimeLimit = 300, ClockFrom = 2,
		Reward = { Cash = 900, Xp = 450 },
	},
	{
		Id = "m06_heat_check", Chapter = 1, Name = "Heat Check", Giver = "Reyes", Level = 4, Requires = "m05_courier_test",
		Intro = "I've heard about you couriers. Wheelies past my patrol cars. Go on, try it. See what happens.",
		Outro = "...Lost them. Next time, kid.",
		Steps = { { "Escape", "Get the police after you (2 stars), then lose them", 2 } },
		Reward = { Cash = 1000, Xp = 500 },
	},
	{
		Id = "m07_calle_ocho", Chapter = 1, Name = "Calle Ocho", Giver = "Marco", Level = 5, Requires = "m06_heat_check",
		Intro = "Three drops down south: Little Havana, the Gables, the Grove. Learn the streets.",
		Outro = "Now you know the south side.",
		Steps = { { "Reach", "Drop off in Little Havana", "LittleHavana" }, { "Reach", "Drop off in Coral Gables", "CoralGables" }, { "Reach", "Drop off in Coconut Grove", "CoconutGrove" } },
		Reward = { Cash = 1100, Xp = 550 },
	},
	{
		Id = "m08_drift_king", Chapter = 1, Name = "Drift King", Giver = "Jet", Level = 6, Requires = "m04_full_circle",
		Intro = "Hold R and lock the rear. Six seconds of sideways and a big trick score, then you're crew.",
		Outro = "Welcome to the crew.",
		Steps = { { "Trick", "Drift (hold R)", "Drift", 6 }, { "Trick", "Earn from tricks", "Score", 600 } },
		Reward = { Cash = 1200, Xp = 600 },
	},
	{
		Id = "m09_top_speed", Chapter = 1, Name = "Top Speed", Giver = "Nina", Level = 7, Requires = "m07_calle_ocho",
		Intro = "Time for something faster. Hit 60 km/h and keep it rolling for three kilometres. Upgrades help.",
		Outro = "She's flying. Come back for the next upgrade.",
		Steps = { { "Speed", "Reach 60 km/h", 60 }, { "Distance", "Ride", 3000 } },
		Reward = { Cash = 1300, Xp = 650 },
	},
	{
		Id = "m10_island_hopper", Chapter = 1, Name = "Island Hopper", Giver = "Marco", Level = 8, Requires = "m09_top_speed",
		Intro = "Big day: the port, then the beach, then Key Biscayne. Fifteen minutes.",
		Outro = "Three islands, one rider. Legend.",
		Steps = { { "Reach", "Pick up at the Port of Miami", "Port" }, { "Reach", "Drop off at South Beach", "Beach" }, { "Reach", "Drop off on Key Biscayne", "KeyBiscayne" } },
		TimeLimit = 900,
		Reward = { Cash = 1600, Xp = 800 },
	},
	{
		Id = "m11_glades_run", Chapter = 1, Name = "Glades Run", Giver = "Jet", Level = 10, Requires = "m08_drift_king",
		Intro = "Out west the road runs straight through the swamp. Ride it, wheelie for five, come back.",
		Outro = "Gators didn't get you. Nice.",
		Steps = { { "Reach", "Ride out to the Everglades", "Everglades" }, { "Wheelie", "Hold a wheelie for 5 seconds", 5 }, { "Reach", "Ride back to Little Havana", "LittleHavana" } },
		Reward = { Cash = 1800, Xp = 900 },
	},
	{
		Id = "m12_big_delivery", Chapter = 1, Name = "The Big Delivery", Giver = "Marco", Level = 12, Requires = "m10_island_hopper",
		Intro = "A parcel at the airport for Nina. Reyes knows. Grab it, shake the police, bring it home.",
		Outro = "Delivered! Chapter 1 done: the city's yours.",
		Steps = { { "Reach", "Collect the parcel at the airport", "Airport" }, { "Escape", "Shake off the police (3 stars)", 3 }, { "Reach", "Bring it to Flighty Mechanics", "Dealership" } },
		TimeLimit = 900,
		Reward = { Cash = 3500, Xp = 1500 },
	},
} :: { Mission }

function Missions.Get(id: string): Mission?
	for _, mission in Missions.List do
		if mission.Id == id then
			return mission
		end
	end
	return nil
end

-- "Locked", "Ready" or "Done" for a player with these missions done at this level
function Missions.Status(mission: Mission, done: { [string]: boolean }, level: number): string
	if done[mission.Id] then
		return "Done"
	end
	if level < mission.Level or (mission.Requires ~= nil and not done[mission.Requires]) then
		return "Locked"
	end
	return "Ready"
end

-- The mission as an objective (places resolved)
function Missions.Objective(mission: Mission): Objectives.Objective
	local steps: { Objectives.Step } = {}
	for _, s in mission.Steps do
		local kind, text = s[1] :: string, s[2] :: string
		if kind == "Reach" then
			-- (a place in Layout.Places, or the charger by the dealership)
			local at = if s[3] == "DealershipCharger" then Layout.Chargers[1] else (Layout.Places :: any)[s[3]] :: Vector3
			table.insert(steps, Objectives.Reach(text, at))
		elseif kind == "Trick" then
			table.insert(steps, Objectives.Trick(text, s[3] :: string, s[4] :: number))
		else
			table.insert(steps, Objectives.Do(kind, text, s[3] :: number))
		end
	end
	return {
		Id = mission.Id,
		Kind = "Mission",
		Title = mission.Name,
		Steps = steps,
		TimeLimit = mission.TimeLimit,
		ClockFrom = mission.ClockFrom,
		Reward = mission.Reward,
		Intro = mission.Intro,
		Giver = mission.Giver,
	}
end

return Missions
