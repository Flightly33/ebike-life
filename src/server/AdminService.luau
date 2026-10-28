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

	Typing the admin code in chat also makes you an admin for the rest of that visit. The code lives
	here on the server (clients can't read server scripts) and the message is never delivered to
	the chat, so nobody else sees it. Anyone who learns the code gets admin, so change it if it leaks.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admin = require(Shared.Admin)
local Bikes = require(Shared.Bikes)
local Config = require(Shared.Config)
local DayNight = require(Shared.DayNight)
local Economy = require(Shared.Economy)
local Layout = require(Shared.City.Layout)
local Remotes = require(Shared.Remotes)
local Upgrades = require(Shared.Upgrades)
local Weather = require(Shared.Weather)

local BikeService = require(script.Parent.BikeService)
local DataService = require(script.Parent.DataService)
local PoliceService = require(script.Parent.PoliceService)

local AdminService = {}

local admins: { [Player]: boolean } = {}

local CHAT_CODE = "ender=cool"

local function isCode(text: string): boolean
	local cleaned = string.lower((string.gsub(text, "^%s*(.-)%s*$", "%1")))
	return cleaned == CHAT_CODE
end

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

function AdminService.Revoke(player: Player)
	admins[player] = nil
	player:SetAttribute("Admin", false)
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
	weather = function(_player, value)
		-- hold one kind of weather for everyone, or "Auto" to let the spells run (Shared/Weather)
		if value == "Auto" then
			ReplicatedStorage:SetAttribute("WeatherOverride", "")
			return true, "Weather: changing by itself"
		end
		if type(value) ~= "string" or not Weather.Kinds[value] then
			return false, "Give Auto, Clear, Cloudy or Overcast"
		end
		ReplicatedStorage:SetAttribute("WeatherOverride", value)
		return true, "Weather: " .. value
	end,
	time = function(_player, value)
		local hours = tonumber(value)
		if not hours then
			return false, "Give an hour, 0 to 24"
		end
		-- shift every client's clock (Shared/DayNight) so it reads that hour now
		hours %= 24
		local cfg = Config.DayNight
		local now = Workspace:GetServerTimeNow()
		local base = (now / cfg.DaySeconds + cfg.StartFraction) % 1
		ReplicatedStorage:SetAttribute("ClockOffset", (DayNight.FractionAt(hours) - base) % 1)
		Lighting.ClockTime = hours
		return true, string.format("Time %.1f", hours)
	end,
}

function AdminService.Init()
	local function grant(player: Player)
		if admins[player] then
			return
		end
		admins[player] = true
		player:SetAttribute("Admin", true)
		Remotes.Event("Notify"):FireClient(player, "Info", "Admin unlocked. Press F2 or the ADMIN button.")
	end
	-- The chat code: grant on the server, and keep the message out of everyone's chat
	task.spawn(pcall, function()
		local TextChatService = game:GetService("TextChatService")
		local function hide(channel: Instance)
			if channel:IsA("TextChannel") then
				channel.ShouldDeliverCallback = function(message: TextChatMessage)
					return not isCode(message.Text)
				end
			end
		end
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if channels then
			channels.DescendantAdded:Connect(hide)
			for _, channel in channels:GetDescendants() do
				hide(channel)
			end
		end
	end)
	local function join(player: Player)
		player.Chatted:Connect(function(message: string)
			if isCode(message) then
				grant(player)
			end
		end)
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
