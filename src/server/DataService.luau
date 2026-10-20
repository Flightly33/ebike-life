--[[
	DataService: loads and saves each player's Profile (Shared/Profile) in a DataStore.

	The client gets the whole profile through the Profile remote whenever it changes (batched), and
	the numbers the HUD shows every frame (Cash, Level, Xp, XpNext) as Player attributes.

	If the DataStore can't be reached (Studio without "Enable Studio Access to API Services", or an
	outage) the player still plays on a fresh profile, and that profile is never saved over their
	real one.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local DataService = {}

type Entry = {
	Data: Profile.Data,
	Saveable: boolean, -- false when the load failed: never overwrite the real save
	Dirty: boolean,
}

local entries: { [Player]: Entry } = {}
local store: DataStore? = nil
local storeWarned = false
local profileRemote: RemoteEvent

DataService.Loaded = Signal.new() -- (player, data)

local function key(player: Player): string
	return "player_" .. player.UserId
end

local function retry<T>(attempts: number, fn: () -> T): (boolean, T | string)
	local lastError: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < attempts then
			task.wait(1.5 * attempt)
		end
	end
	return false, tostring(lastError)
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.Store)
	end)
	if ok then
		store = result
		return result
	end
	if not storeWarned then
		storeWarned = true
		warn("[DataService] DataStore unavailable, progress won't save this session: " .. tostring(result))
	end
	return nil
end

local function attributes(player: Player, data: Profile.Data)
	player:SetAttribute("Cash", data.Cash)
	player:SetAttribute("Level", data.Level)
	player:SetAttribute("Xp", math.floor(data.Xp))
	player:SetAttribute("XpNext", Economy.XpToNext(data.Level))
	player:SetAttribute("Mode", data.Mode)
	player:SetAttribute("BoostUntil", data.BoostUntil)
end

local function load(player: Player)
	local data: Profile.Data
	local saveable = false
	local ds = getStore()
	if ds then
		local ok, result = retry(3, function()
			return ds:GetAsync(key(player))
		end)
		if ok then
			data = Profile.Sanitize(result)
			saveable = true
		else
			warn(string.format("[DataService] couldn't load %s (%s); playing on a fresh profile that won't save", player.Name, tostring(result)))
			data = Profile.Default()
		end
	else
		data = Profile.Default()
	end
	if player.Parent ~= Players then
		return
	end
	entries[player] = { Data = data, Saveable = saveable, Dirty = true }
	attributes(player, data)
	DataService.Loaded:Fire(player, data)
end

local function save(player: Player, entry: Entry)
	if not entry.Saveable then
		return
	end
	local ds = getStore()
	if not ds then
		return
	end
	local snapshot = entry.Data
	local ok, err = retry(3, function()
		return ds:UpdateAsync(key(player), function()
			return snapshot
		end)
	end)
	if not ok then
		warn(string.format("[DataService] save failed for %s: %s", player.Name, tostring(err)))
	end
end

function DataService.Get(player: Player): Profile.Data?
	local entry = entries[player]
	return if entry then entry.Data else nil
end

function DataService.WaitFor(player: Player): Profile.Data?
	local deadline = os.clock() + 30
	while not entries[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.Get(player)
end

-- Something in the profile changed: refresh attributes now, push the full profile soon
function DataService.Changed(player: Player)
	local entry = entries[player]
	if entry then
		entry.Dirty = true
		attributes(player, entry.Data)
	end
end

function DataService.AddCash(player: Player, amount: number): number
	local data = DataService.Get(player)
	if not data or amount == 0 then
		return 0
	end
	local whole = math.floor(amount)
	data.Cash = math.max(0, data.Cash + whole)
	if whole > 0 then
		data.Stats.Earned += whole
	end
	-- cash reaches the client as an attribute; the full profile goes out with the next real change
	player:SetAttribute("Cash", data.Cash)
	return whole
end

function DataService.Spend(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or amount < 0 or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	DataService.Changed(player)
	return true
end

function DataService.Init()
	profileRemote = Remotes.Event("Profile")
	local getProfile = Remotes.Function("GetProfile")
	getProfile.OnServerInvoke = function(player: Player)
		return DataService.WaitFor(player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entry = entries[player]
		if entry then
			save(player, entry)
			entries[player] = nil
		end
	end)

	-- Push changed profiles a few times a second
	task.spawn(function()
		while true do
			task.wait(0.3)
			for player, entry in entries do
				if entry.Dirty then
					entry.Dirty = false
					profileRemote:FireClient(player, entry.Data)
				end
			end
		end
	end)
	-- Autosave
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player, entry in entries do
				task.spawn(save, player, entry)
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for player, entry in entries do
			pending += 1
			task.spawn(function()
				save(player, entry)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
