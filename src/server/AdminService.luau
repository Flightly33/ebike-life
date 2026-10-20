--[[
	AdminService: admin commands, checked on the server (the client's panel is only a front end).

	Admin(command, value) -> ok, message
		cash <amount>        add (or with a negative amount, remove) cash
		level <n>            set your level
		allbikes             own every bike
		maxupgrades          max every upgrade on your current bike
		bike <id>            spawn a bike you own (allbikes first for the rest)
		wanted <0-5>         set your wanted stars (0 clears a chase)
		teleport <place>     go to a place, even while wanted
		time <0-24>          set the time of day for everyone
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Admin)
local Bikes = require(Shared.Bikes)
local Economy = require(Shared.Economy)
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)
local Upgrades = require(Shared.Upgrades)

local BikeService = require(script.Parent.BikeService)
local DataService = require(script.Parent.DataService)
local PoliceService = require(script.Parent.PoliceService)

local AdminService = {}

local admins: { [Player]: boolean } = {}

local function check(player: Player): boolean
	if RunService:IsStudio() or table.find(Admin.UserIds, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

function AdminService.IsAdmin(player: Player): boolean
	return admins[player] == true
end

type Handler = (player: Player, value: any) -> (boolean, string)

local commands: { [string]: Handler } = {
	cash = function(player, value)
		local amount = tonumber(value)
		if not amount then
			return false, "Give an amount"
		end
		amount = math.clamp(math.floor(amount), -Admin.MaxCash, Admin.MaxCash)
		if amount >= 0 then
			DataService.AddCash(player, amount)
		else
			local data = DataService.Get(player)
			DataService.Spend(player, math.min(-amount, if data then data.Cash else 0))
		end
		DataService.Changed(player)
		return true, string.format("Cash %s%s", if amount >= 0 then "+" else "-", Economy.FormatCash(math.abs(amount)))
	end,
	level = function(player, value)
		local level = tonumber(value)
		local data = DataService.Get(player)
		if not level or not data then
			return false, "Give a level"
		end
		data.Level = math.clamp(math.floor(level), 1, 10000)
		data.Xp = 0
		DataService.Changed(player)
		return true, "Level " .. data.Level
	end,
	allbikes = function(player)
		local data = DataService.Get(player)
		if not data then
			return false, "No save loaded"
		end
		for _, bike in Bikes.List do
			data.Owned[bike.Id] = true
		end
		DataService.Changed(player)
		return true, "You own every bike"
	end,
	maxupgrades = function(player)
		local data = DataService.Get(player)
		local ride = BikeService.Get(player)
		local bikeId = if ride then ride.Bike.Id else if data then data.Equipped else nil
		if not data or not bikeId then
			return false, "Get on a bike first"
		end
		local levels = data.Upgrades[bikeId] or {}
		for _, slot in Upgrades.Slots do
			local top = Upgrades.MaxLevel(slot.Name)
			levels[slot.Name] = top
			levels[slot.Name .. "Max"] = top
		end
		data.Upgrades[bikeId] = levels
		DataService.Changed(player)
		BikeService.Refresh(player)
		return true, "Maxed " .. bikeId
	end,
	bike = function(player, value)
		if type(value) ~= "string" or not Bikes.Get(value) then
			return false, "Unknown bike"
		end
		local data = DataService.Get(player)
		if data and not data.Owned[value] then
			data.Owned[value] = true
			DataService.Changed(player)
		end
		return BikeService.Spawn(player, value)
	end,
	wanted = function(player, value)
		local stars = tonumber(value)
		if not stars then
			return false, "Give 0 to 5 stars"
		end
		PoliceService.SetWanted(player, math.clamp(math.floor(stars), 0, 5))
		return true, string.format("Wanted: %d stars", math.clamp(math.floor(stars), 0, 5))
	end,
	teleport = function(player, value)
		local place = if type(value) == "string" and table.find(Admin.Places, value) then (Layout.Places :: any)[value] else nil
		if typeof(place) ~= "Vector3" then
			return false, "Unknown place"
		end
		local target = CFrame.new(place + Vector3.new(0, 4, 0))
		if BikeService.IsRiding(player) then
			BikeService.Teleport(player, target)
		elseif player.Character then
			player.Character:PivotTo(target)
		end
		return true, "Teleported to " .. value
	end,
	time = function(_player, value)
		local hours = tonumber(value)
		if not hours then
			return false, "Give an hour, 0 to 24"
		end
		Lighting.ClockTime = hours % 24
		return true, string.format("Time %.1f", Lighting.ClockTime)
	end,
}

function AdminService.Init()
	local function join(player: Player)
		task.spawn(function()
			if check(player) then
				admins[player] = true
				player:SetAttribute("Admin", true)
			end
		end)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admins[player] = nil
	end)

	Remotes.Function("Admin").OnServerInvoke = function(player: Player, command: any, value: any)
		if not admins[player] then
			return false, "Not an admin"
		end
		local handler = if type(command) == "string" then commands[command] else nil
		if not handler then
			return false, "Unknown command"
		end
		local ok, result, message = pcall(handler, player, value)
		if not ok then
			warn("[AdminService]", command, result)
			return false, "Command failed"
		end
		return result, message
	end
end

return AdminService
