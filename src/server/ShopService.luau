--[[
	ShopService: everything bought or chosen in the menus. The dealership (bikes), Tuning (parts,
	paint, assist modes), Crates (paints and underglow), the Shop (boosts, game passes), settings and
	teleports. Every request is checked against the player's profile here; the client only asks.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.AssetIds)
local Bikes = require(Shared.Bikes)
local BikeStats = require(Shared.BikeStats)
local Economy = require(Shared.Economy)
local Config = require(Shared.Config)
local Layout = require(Shared.City.Layout)
local Modes = require(Shared.Modes)
local Paints = require(Shared.Paints)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Shop)
local Livery = require(Shared.Livery)
local Setup = require(Shared.Setup)
local Achievements = require(Shared.Achievements)
local Upgrades = require(Shared.Upgrades)

local DataService = require(script.Parent.DataService)
local BikeService = require(script.Parent.BikeService)
local EconomyService = require(script.Parent.EconomyService)

local ShopService = {}

local passCache: { [Player]: { [string]: boolean } } = {}
local lastTeleport: { [Player]: number } = {}
local rng = Random.new()

function ShopService.OwnsPass(player: Player, key: string): boolean
	local id = (AssetIds.GamePasses :: any)[key]
	if type(id) ~= "number" or id <= 0 then
		return false
	end
	local cache = passCache[player]
	if not cache then
		cache = {}
		passCache[player] = cache
	end
	if cache[key] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		cache[key] = ok and owns == true
	end
	return cache[key] == true
end

local function notify(player: Player, kind: string, text: string)
	Remotes.Event("Notify"):FireClient(player, kind, text)
end

local function buyBike(player: Player, bikeId: any): (boolean, string)
	if type(bikeId) ~= "string" then
		return false, "Unknown bike"
	end
	local bike = Bikes.Get(bikeId)
	local data = DataService.Get(player)
	if not bike or not data then
		return false, "Unknown bike"
	end
	if data.Owned[bikeId] then
		return false, "You already own the " .. Bikes.FullName(bike)
	end
	if data.Level < bike.Level then
		return false, string.format("Reach level %d to buy the %s", bike.Level, bike.Name)
	end
	if not DataService.Spend(player, bike.Price) then
		return false, string.format("You need %s more", Economy.FormatCash(bike.Price - data.Cash))
	end
	data.Owned[bikeId] = true
	DataService.Changed(player)
	notify(player, "Cash", "You bought the " .. Bikes.FullName(bike) .. "!")
	BikeService.Spawn(player, bikeId)
	return true, "Bought"
end

-- Tuning, parts and paint happen at Flighty Garage: is the player in (or at the door of) it?
local GARAGE_REACH = 60 * Config.MAP_SCALE / 1.25
function ShopService.AtGarage(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local g = Layout.Garage
	local p = root.Position
	local dx = math.max(g.MinX - p.X, 0, p.X - g.MaxX)
	local dz = math.max(g.MinZ - p.Z, 0, p.Z - g.MaxZ)
	return math.sqrt(dx * dx + dz * dz) < GARAGE_REACH
end
local NOT_THERE = "Bring it to Flighty Garage, next to the dealership"

local function buyUpgrade(player: Player, bikeId: any, slotName: any, level: any): (boolean, string)
	if type(bikeId) ~= "string" or type(slotName) ~= "string" or type(level) ~= "number" then
		return false, "Bad request"
	end
	if not ShopService.AtGarage(player) then
		return false, NOT_THERE
	end
	local bike = Bikes.Get(bikeId)
	local slot = Upgrades.BySlot[slotName]
	local data = DataService.Get(player)
	if not bike or not slot or not data or not data.Owned[bikeId] then
		return false, "You don't own that bike"
	end
	if slotName == "Limiter" and not BikeStats.HasLimiter(bike) then
		return false, "Off-road bikes have no limiter"
	end
	level = math.floor(level)
	if level < 0 or level > Upgrades.MaxLevel(slotName) then
		return false, "No such part"
	end
	local levels: Upgrades.Levels = data.Upgrades[bikeId] or {}
	local owned = Upgrades.Owned(levels, slotName)
	if level > owned then
		if level ~= owned + 1 then
			return false, "Buy the earlier stage first"
		end
		local cost = Upgrades.Cost(bikeId, slotName, level)
		if not DataService.Spend(player, cost) then
			return false, string.format("You need %s more", Economy.FormatCash(cost - data.Cash))
		end
		levels[slotName .. "Max"] = level
	end
	if level > 0 then
		levels[slotName] = level
	else
		levels[slotName] = nil
	end
	data.Upgrades[bikeId] = levels
	DataService.Changed(player)
	local ride = BikeService.Get(player)
	if ride and ride.Bike.Id == bikeId then
		BikeService.Refresh(player)
	end
	return true, slot.Levels[level + 1]
end

local function setPaint(player: Player, bikeId: any, slotName: any, paintId: any): (boolean, string)
	if type(bikeId) ~= "string" or type(slotName) ~= "string" or type(paintId) ~= "string" then
		return false, "Bad request"
	end
	local data = DataService.Get(player)
	local bike = Bikes.Get(bikeId)
	if not data or not bike or not data.Owned[bikeId] or not table.find(Paints.Slots, slotName) then
		return false, "Bad request"
	end
	if not ShopService.AtGarage(player) then
		return false, NOT_THERE
	end
	local choice = data.Paint[bikeId] or {}
	if paintId == "stock" or paintId == "none" then
		(choice :: any)[slotName] = nil
	else
		local paint = Paints.Get(paintId)
		if not paint or not (Profile.HasPaint(data, paintId) or ShopService.OwnsPass(player, "VIP")) then
			return false, "Unlock that paint in a crate first"
		end
		if (slotName == "Glow") ~= (paint.Kind == "Glow") then
			return false, "That doesn't go there"
		end
		(choice :: any)[slotName] = paintId
	end
	data.Paint[bikeId] = choice
	DataService.Changed(player)
	local ride = BikeService.Get(player)
	if ride and ride.Bike.Id == bikeId then
		BikeService.Refresh(player)
	end
	return true, "Painted"
end

-- A whole paint job: every slot's crate paint or custom coat (Shared/Livery), paid for at once
local function setLivery(player: Player, bikeId: any, choice: any): (boolean, string, number?)
	if type(bikeId) ~= "string" or type(choice) ~= "table" then
		return false, "Bad request"
	end
	local data = DataService.Get(player)
	local bike = Bikes.Get(bikeId)
	if not data or not bike or not data.Owned[bikeId] then
		return false, "You don't own that bike"
	end
	if not ShopService.AtGarage(player) then
		return false, NOT_THERE
	end
	local vip = ShopService.OwnsPass(player, "VIP")
	local clean: { [string]: string } = {}
	for _, slot in Paints.Slots do
		local value = choice[slot]
		if value == nil or value == "stock" or value == "" then
			continue
		end
		if type(value) ~= "string" or not Livery.Valid(slot, value) then
			return false, "That paint doesn't go there"
		end
		if Livery.Decode(value) == nil and not (Profile.HasPaint(data, value) or vip) then
			return false, "Unlock that paint in a crate first"
		end
		clean[slot] = value
	end
	local old = data.Paint[bikeId] or {}
	local cost = Livery.Cost(bike.Price, old :: any, clean)
	if cost > 0 and not DataService.Spend(player, cost) then
		return false, string.format("You need %s more", Economy.FormatCash(cost - data.Cash))
	end
	data.Paint[bikeId] = clean :: any
	DataService.Changed(player)
	local ride = BikeService.Get(player)
	if ride and ride.Bike.Id == bikeId then
		BikeService.Refresh(player)
	end
	return true, if cost > 0 then string.format("Paint job done: %s", Economy.FormatCash(cost)) else "Paint job done", cost
end

-- The mechanic's setup (Shared/Setup): free, but only at the garage
local function setSetup(player: Player, bikeId: any, values: any): (boolean, string)
	if type(bikeId) ~= "string" or type(values) ~= "table" then
		return false, "Bad request"
	end
	local data = DataService.Get(player)
	local bike = Bikes.Get(bikeId)
	if not data or not bike or not data.Owned[bikeId] then
		return false, "You don't own that bike"
	end
	if not ShopService.AtGarage(player) then
		return false, NOT_THERE
	end
	local levels: Upgrades.Levels = data.Upgrades[bikeId] or {}
	for _, setting in Setup.List do
		local v = values[setting.Key]
		levels["S_" .. setting.Key] = nil
		if type(v) == "number" and v == v then
			local clamped = math.clamp(math.floor(v + 0.5), setting.Min, setting.Max)
			if clamped ~= setting.Default then
				levels["S_" .. setting.Key] = clamped
			end
		end
	end
	data.Upgrades[bikeId] = levels
	DataService.Changed(player)
	local ride = BikeService.Get(player)
	if ride and ride.Bike.Id == bikeId then
		BikeService.Refresh(player)
	end
	return true, "Setup saved"
end

local function openCrate(player: Player, crateId: any): (boolean, string, string?, boolean?)
	if type(crateId) ~= "string" then
		return false, "Unknown crate"
	end
	local crate = Paints.GetCrate(crateId)
	local data = DataService.Get(player)
	if not crate or not data then
		return false, "Unknown crate"
	end
	if not DataService.Spend(player, crate.Price) then
		return false, string.format("You need %s more", Economy.FormatCash(crate.Price - data.Cash))
	end
	local paint = Paints.Roll(crate, rng:NextNumber(), rng:NextNumber())
	local duplicate = data.Paints[paint.Id] == true
	if duplicate then
		local refund = math.floor(crate.Price * 0.25)
		DataService.AddCash(player, refund)
	else
		data.Paints[paint.Id] = true
	end
	DataService.Changed(player)
	return true, paint.Name, paint.Id, duplicate
end

local function buyBoost(player: Player, boostId: any): (boolean, string)
	if type(boostId) ~= "string" then
		return false, "Unknown boost"
	end
	local boost = Shop.GetBoost(boostId)
	local data = DataService.Get(player)
	if not boost or not data then
		return false, "Unknown boost"
	end
	if not DataService.Spend(player, boost.Price) then
		return false, string.format("You need %s more", Economy.FormatCash(boost.Price - data.Cash))
	end
	local now = os.time()
	data.BoostUntil = math.max(data.BoostUntil, now) + boost.Minutes * 60
	DataService.Changed(player)
	return true, string.format("%s active for %d minutes", boost.Name, math.floor((data.BoostUntil - now) / 60 + 0.5))
end

local function claimAchievement(player: Player, id: any): (boolean, string)
	local a = if type(id) == "string" then Achievements.Get(id) else nil
	local data = DataService.Get(player)
	if not a or not data then
		return false, "Unknown achievement"
	end
	if data.Achievements[a.Id] then
		return false, "Already claimed"
	end
	local _, done = Achievements.Progress(a, data)
	if not done then
		return false, "Not there yet"
	end
	data.Achievements[a.Id] = true
	DataService.AddCash(player, a.Reward)
	data.Stats.Earned -= a.Reward -- (a reward isn't earned riding)
	DataService.Changed(player)
	return true, string.format("%s %s: +%s", a.Icon, a.Name, Economy.FormatCash(a.Reward))
end

local function teleport(player: Player, destination: any)
	if type(destination) ~= "string" then
		return
	end
	local place = (Layout.Places :: any)[destination]
	if typeof(place) ~= "Vector3" then
		return
	end
	if (player:GetAttribute("Wanted") or 0) > 0 then
		notify(player, "Error", "You can't teleport while the police are after you!")
		return
	end
	local now = os.clock()
	if lastTeleport[player] and now - lastTeleport[player] < 5 then
		notify(player, "Error", "Wait a moment before teleporting again")
		return
	end
	lastTeleport[player] = now
	local target = CFrame.new(place + Vector3.new(0, 3, 0))
	if BikeService.IsRiding(player) then
		BikeService.Teleport(player, target)
	else
		local character = player.Character
		if character then
			character:PivotTo(target)
		end
	end
end

function ShopService.Init()
	Remotes.Function("BuyBike").OnServerInvoke = buyBike
	Remotes.Function("BuyUpgrade").OnServerInvoke = buyUpgrade
	Remotes.Function("SetPaint").OnServerInvoke = setPaint
	Remotes.Function("OpenCrate").OnServerInvoke = openCrate
	Remotes.Function("BuyBoost").OnServerInvoke = buyBoost
	Remotes.Function("SetLivery").OnServerInvoke = setLivery
	Remotes.Function("SetSetup").OnServerInvoke = setSetup
	Remotes.Function("ClaimAchievement").OnServerInvoke = claimAchievement
	Remotes.Event("Teleport").OnServerEvent:Connect(teleport)
	Remotes.Event("SetMode").OnServerEvent:Connect(function(player: Player, mode: any)
		local data = DataService.Get(player)
		if data and Modes.IsMode(mode) then
			data.Mode = mode
			DataService.Changed(player)
		end
	end)
	Remotes.Event("SaveModes").OnServerEvent:Connect(function(player: Player, modes: any)
		local data = DataService.Get(player)
		if data then
			data.Modes = Modes.Sanitize(modes)
			DataService.Changed(player)
		end
	end)
	Remotes.Event("SaveSettings").OnServerEvent:Connect(function(player: Player, settings: any)
		local data = DataService.Get(player)
		if data then
			data.Settings = Profile.Sanitize({ Settings = settings }).Settings
			DataService.Changed(player)
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if purchased then
			for key, id in AssetIds.GamePasses :: any do
				if id == passId then
					local cache = passCache[player] or {}
					cache[key] = true
					passCache[player] = cache
					notify(player, "Cash", "Thanks! Game pass unlocked.")
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
		lastTeleport[player] = nil
	end)
	-- Boost = timed 2x or the 2x Cash pass
	EconomyService.BoostOf = function(player: Player): number
		local data = DataService.Get(player)
		if ShopService.OwnsPass(player, "DoubleCash") or (data and data.BoostUntil > os.time()) then
			return 2
		end
		return 1
	end
end

return ShopService
