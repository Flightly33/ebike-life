--[[
	Races: the courses ridden as solo time trials or multiplayer races (RaceService). A course runs
	through named places (Layout.Places) along the road graph's shortest paths, with a checkpoint about
	every SPACING studs; Build works the same out on the server and the client (the route on the map).

	Medals by average speed over the course's length: gold, silver, bronze. Pay grows with the length.
]]

local Layout = require(script.Parent.City.Layout)
local Config = require(script.Parent.Config)

local Races = {}

export type Course = {
	Id: string,
	Name: string,
	Blurb: string,
	Via: { string }, -- places, in order
	Level: number, -- the level it opens at
}

export type Built = {
	Points: { Vector3 }, -- checkpoints, the last one the finish
	Start: Vector3,
	Length: number, -- studs along the road
	Gold: number, -- seconds
	Silver: number,
	Bronze: number,
	Pay: number, -- $ for a gold time
}

Races.SPACING = 520 -- studs between checkpoints
Races.MEDAL_KMH = { Gold = 52, Silver = 40, Bronze = 30 }
Races.PAY_PER_STUD = 0.09
Races.MEDAL_PAY = { Gold = 1, Silver = 0.7, Bronze = 0.5, None = 0.3 }
-- a multiplayer race pays the trial's gold rate times this, by finishing place
Races.PLACE_PAY = { 1.6, 1.2, 1.0, 0.8, 0.7, 0.6, 0.5, 0.5 }

Races.Courses = {
	{ Id = "downtown_dash", Name = "Downtown Dash", Blurb = "Flighty Mechanics to the Plaza through the towers, then the bay", Via = { "Dealership", "Downtown", "Plaza", "Park" }, Level = 1 },
	{ Id = "wynwood_walls", Name = "Wynwood Walls", Blurb = "The mural district and back past the jump park", Via = { "Downtown", "Wynwood", "JumpPark" }, Level = 2 },
	{ Id = "calle_ocho", Name = "Calle Ocho Sprint", Blurb = "Little Havana's main street, flat out", Via = { "Downtown", "LittleHavana" }, Level = 3 },
	{ Id = "ocean_drive", Name = "Ocean Drive Run", Blurb = "Over the causeway and up the beach", Via = { "Park", "Beach", "NorthBeach" }, Level = 4 },
	{ Id = "gables_gp", Name = "Gables Grand Prix", Blurb = "Coconut Grove, Coral Gables and Little Havana", Via = { "CoconutGrove", "CoralGables", "LittleHavana" }, Level = 6 },
	{ Id = "port_sprint", Name = "Port Sprint", Blurb = "Down from Wynwood, along the bay and over to the container yard", Via = { "Wynwood", "Park", "Port" }, Level = 7 },
	{ Id = "rickenbacker", Name = "Rickenbacker Rush", Blurb = "The Grove to Key Biscayne over the causeway", Via = { "CoconutGrove", "KeyBiscayne" }, Level = 9 },
	{ Id = "tamiami_trail", Name = "Tamiami Trail", Blurb = "Downtown, Calle Ocho and out to the Everglades: the long one", Via = { "Downtown", "LittleHavana", "Everglades" }, Level = 12 },
} :: { Course }

local cache: { [string]: Built } = {}

function Races.Get(id: string): Course?
	for _, course in Races.Courses do
		if course.Id == id then
			return course
		end
	end
	return nil
end

-- The checkpoints, length and medal times of a course (worked out once, then cached)
function Races.Build(course: Course): Built
	local cached = cache[course.Id]
	if cached then
		return cached
	end
	local nodes: { number } = {}
	for i, place in course.Via do
		-- (NearestNode weighs height three times over, so a place under a freeway maps to the street)
		local at = (Layout.Places :: any)[place]
		local node = Layout.NearestNode(at)
		if i == 1 then
			table.insert(nodes, node)
		else
			local path = Layout.Path(nodes[#nodes], node)
			for k = 2, #path do
				table.insert(nodes, path[k])
			end
		end
	end
	local points: { Vector3 } = {}
	local length, since = 0, 0
	local start = Layout.Nodes[nodes[1]].Position
	for k = 2, #nodes do
		local a, b = Layout.Nodes[nodes[k - 1]].Position, Layout.Nodes[nodes[k]].Position
		local d = (b - a).Magnitude
		length += d
		since += d
		if since >= Races.SPACING or k == #nodes then
			table.insert(points, b)
			since = 0
		end
	end
	if #points == 0 then
		table.insert(points, start + Vector3.new(0, 0, 60))
		length = 60
	end
	local function seconds(kmh: number): number
		return math.ceil(length / (kmh / Config.KMH_PER_STUD_PER_SECOND))
	end
	local built: Built = {
		Points = points,
		Start = start,
		Length = length,
		Gold = seconds(Races.MEDAL_KMH.Gold),
		Silver = seconds(Races.MEDAL_KMH.Silver),
		Bronze = seconds(Races.MEDAL_KMH.Bronze),
		Pay = math.floor(length * Races.PAY_PER_STUD),
	}
	cache[course.Id] = built
	return built
end

-- "Gold", "Silver", "Bronze" or "None" for a time
function Races.Medal(built: Built, seconds: number): string
	if seconds <= built.Gold then
		return "Gold"
	elseif seconds <= built.Silver then
		return "Silver"
	elseif seconds <= built.Bronze then
		return "Bronze"
	end
	return "None"
end

return Races
