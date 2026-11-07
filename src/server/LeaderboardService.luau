--[[
	LeaderboardService: the top riders across every server (OrderedDataStores), for the phone's Ranks
	tab: total earned, deliveries, race wins, top speed, longest wheelie, and the best time on every
	course (lowest first). Players' values are written every couple of minutes and when they leave;
	the top tens are read back on the same beat. Without DataStore access (an unpublished place in
	Studio) each board ranks the players on this server.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(Shared.Profile)
local Races = require(Shared.Races)

local DataService = require(script.Parent.DataService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local LeaderboardService = {}

LeaderboardService.INTERVAL = 120
LeaderboardService.TOP = 10

type Board = {
	Id: string,
	Name: string,
	Unit: string, -- "$", "", "km/h", "s", "time"
	Ascending: boolean,
	Value: (Profile.Data) -> number?, -- what a player scores (nil: nothing to show)
	Store: OrderedDataStore?,
	Top: { { Name: string, Value: number } },
}

local boards: { Board } = {
	{ Id = "Earned", Name = "Total earned", Unit = "$", Ascending = false, Value = function(d)
		return d.Stats.Earned
	end, Top = {} },
	{ Id = "Deliveries", Name = "Deliveries", Unit = "", Ascending = false, Value = function(d)
		return d.Stats.Deliveries
	end, Top = {} },
	{ Id = "Wins", Name = "Race wins", Unit = "", Ascending = false, Value = function(d)
		return d.Stats.Wins
	end, Top = {} },
	{ Id = "TopSpeed", Name = "Top speed", Unit = "km/h", Ascending = false, Value = function(d)
		return d.Stats.TopSpeed
	end, Top = {} },
	{ Id = "BestWheelie", Name = "Longest wheelie", Unit = "s", Ascending = false, Value = function(d)
		return d.Stats.BestWheelie
	end, Top = {} },
}
for _, course in Races.Courses do
	local id = course.Id
	table.insert(boards, { Id = "Time_" .. id, Name = course.Name, Unit = "time", Ascending = true, Value = function(d)
		return d.BestTimes[id]
	end, Top = {} })
end

local names: { [number]: string } = {}
local online = true

-- OrderedDataStores hold whole numbers: times and wheelies go in tenths
local function encode(board: Board, value: number): number
	return if board.Unit == "time" or board.Unit == "s" then math.floor(value * 10 + 0.5) else math.floor(value)
end

local function decode(board: Board, value: number): number
	return if board.Unit == "time" or board.Unit == "s" then value / 10 else value
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else "Rider " .. tostring(userId)
	names[userId] = name
	return name
end

local function write(player: Player)
	local data = DataService.Get(player)
	if not data or not online or player.UserId <= 0 then
		return
	end
	for _, board in boards do
		local value = board.Value(data)
		local store = board.Store
		if store and value and value > 0 then
			pcall(function()
				store:SetAsync(tostring(player.UserId), encode(board, value))
			end)
		end
	end
end

-- Each board's top players: from the stores, or this server's players without them
local function read()
	for _, board in boards do
		local store = board.Store
		local top = {}
		local ok = false
		if store and online then
			ok = pcall(function()
				local pages = store:GetSortedAsync(board.Ascending, LeaderboardService.TOP)
				for _, entry in pages:GetCurrentPage() do
					table.insert(top, { Name = nameOf(tonumber(entry.key) or 0), Value = decode(board, entry.value) })
				end
			end)
		end
		if not ok then
			table.clear(top)
			for _, player in Players:GetPlayers() do
				local data = DataService.Get(player)
				local value = data and board.Value(data)
				if value and value > 0 then
					table.insert(top, { Name = player.DisplayName, Value = value })
				end
			end
			table.sort(top, function(a, b)
				return if board.Ascending then a.Value < b.Value else a.Value > b.Value
			end)
			while #top > LeaderboardService.TOP do
				table.remove(top)
			end
		end
		board.Top = top
	end
end

function LeaderboardService.Refresh()
	for _, player in Players:GetPlayers() do
		write(player)
	end
	read()
end

function LeaderboardService.Init()
	for _, board in boards do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("EB_Board_" .. board.Id)
		end)
		if ok and store then
			board.Store = store
		else
			online = false
		end
	end
	ObjectiveService.Overview("Boards", function(player: Player)
		local data = DataService.Get(player)
		local out = {}
		for _, board in boards do
			table.insert(out, { Id = board.Id, Name = board.Name, Unit = board.Unit, Ascending = board.Ascending, Top = board.Top, Mine = if data then board.Value(data) else nil })
		end
		return out
	end)
	Players.PlayerRemoving:Connect(write)
	task.spawn(function()
		task.wait(5)
		while true do
			LeaderboardService.Refresh()
			task.wait(LeaderboardService.INTERVAL)
		end
	end)
end

return LeaderboardService
