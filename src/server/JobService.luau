--[[
	JobService: Flighty Courier delivery jobs. Pick-ups are the city's walk-in shop counters (every
	`OrderCounter`, with its shop's name); drop-offs are the fronts of houses, villas, bungalows and
	mansions (in front of their `Walls`, which face the street). The phone offers three jobs near you
	(new ones every couple of minutes, or once you take one); each pays by the distance between pick-up
	and drop-off and the rider's level, and the clock starts at the pick-up. A tip on top for time to
	spare and a clean ride. A Courier Rush doubles it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Events = require(Shared.Events)
local Layout = require(Shared.City.Layout)
local Objectives = require(Shared.Objectives)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local BikeService = require(script.Parent.BikeService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ObjectiveService = require(script.Parent.ObjectiveService)

local JobService = {}

JobService.Delivered = Signal.new() -- (player, cash)

type Spot = { Name: string, At: Vector3 }
export type Offer = { Pickup: Spot, Dropoff: Spot, Distance: number, Pay: number, TimeLimit: number }

JobService.OFFERS = 3
JobService.REFRESH = 150 -- seconds an offer list lasts
JobService.BASE = 140
JobService.PER_STUD = 0.1
JobService.LEVEL = 0.03 -- pay per level
JobService.CARGO_BONUS = 1.25 -- delivered on a cargo bike (Bikes kit "Cargo": the Hauler C)
JobService.KMH = 30 -- the average speed the time limit allows for
JobService.SPARE = 75 -- seconds on top
local MAP = Config.MAP_SCALE / 1.25

local pickups: { Spot } = {}
local dropoffs: { Spot } = {}
local offers: { [Player]: { List: { Offer }, At: number } } = {}
local rng = Random.new()

local HOMES = { House = true, Villa = true, Bungalow = true, Mansion = true }

-- The pick-ups and drop-offs in the city (before CityKit swaps any stand-ins: counters and walls stay)
function JobService.Scan(city: Instance)
	table.clear(pickups)
	table.clear(dropoffs)
	for _, d in city:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name == "OrderCounter" then
				local shop = d:GetAttribute("ShopName")
				-- stand in front of the counter, on the customers' side
				local front = d.CFrame * CFrame.new(0, 0, -6)
				table.insert(pickups, { Name = if type(shop) == "string" then shop else "the shop", At = front.Position })
			elseif d.Name == "Walls" then
				local model = d:FindFirstAncestorWhichIsA("Model")
				if model and HOMES[model.Name] then
					local look = d.CFrame.LookVector
					local foot = d.Position - Vector3.new(0, d.Size.Y / 2, 0)
					local front = foot + Vector3.new(look.X, 0, look.Z).Unit * (d.Size.Z / 2 + 14 * Config.WORLD_SCALE)
					table.insert(dropoffs, { Name = model.Name, At = front })
				end
			end
		end
	end
end

function JobService.Counts(): (number, number)
	return #pickups, #dropoffs
end

local function districtName(at: Vector3): string
	local best, bestDistance = "Miami", math.huge
	for _, entry in Layout.Teleports do
		local place = (Layout.Places :: any)[entry.Id]
		if place then
			local d = (place - at).Magnitude
			if d < bestDistance then
				best, bestDistance = entry.Name, d
			end
		end
	end
	return best
end

local function makeOffer(player: Player, near: Vector3): Offer?
	if #pickups == 0 or #dropoffs == 0 then
		return nil
	end
	local data = DataService.Get(player)
	local level = if data then data.Level else 1
	-- a counter fairly near the rider, then a home a ride away from it
	local pickup: Spot? = nil
	for _ = 1, 30 do
		local p = pickups[rng:NextInteger(1, #pickups)]
		if (p.At - near).Magnitude < 1600 * MAP then
			pickup = p
			break
		end
	end
	pickup = pickup or pickups[rng:NextInteger(1, #pickups)]
	local chosen = pickup :: Spot
	local dropoff: Spot? = nil
	for _ = 1, 40 do
		local d = dropoffs[rng:NextInteger(1, #dropoffs)]
		local distance = (d.At - chosen.At).Magnitude
		if distance > 500 * MAP and distance < 2600 * MAP then
			dropoff = d
			break
		end
	end
	if not dropoff then
		return nil
	end
	local drop = dropoff :: Spot
	local distance = (drop.At - chosen.At).Magnitude
	local studsPerSecond = JobService.KMH / Config.KMH_PER_STUD_PER_SECOND
	return {
		Pickup = chosen,
		Dropoff = { Name = string.format("a %s in %s", string.lower(drop.Name), districtName(drop.At)), At = drop.At },
		Distance = distance,
		Pay = math.floor((JobService.BASE + JobService.PER_STUD * distance) * (1 + JobService.LEVEL * level)),
		TimeLimit = math.ceil(distance * 1.35 / studsPerSecond + JobService.SPARE),
	}
end

local function where(player: Player): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return Vector3.zero
end

-- This player's offers (new ones when they're stale)
function JobService.Offers(player: Player): { Offer }
	local entry = offers[player]
	if entry and os.clock() - entry.At < JobService.REFRESH and #entry.List > 0 then
		return entry.List
	end
	local list = {}
	local near = where(player)
	for _ = 1, JobService.OFFERS do
		local offer = makeOffer(player, near)
		if offer then
			table.insert(list, offer)
		end
	end
	offers[player] = { List = list, At = os.clock() }
	return list
end

function JobService.Start(player: Player, index: any): (boolean, string)
	local list = JobService.Offers(player)
	local offer = if type(index) == "number" then list[math.floor(index)] else nil
	if not offer then
		return false, "That job's gone: pick another"
	end
	offers[player] = nil -- fresh offers next time
	local objective: Objectives.Objective = {
		Id = "job",
		Kind = "Job",
		Title = "Delivery for " .. offer.Pickup.Name,
		Steps = {
			Objectives.Reach("Pick up the order at " .. offer.Pickup.Name, offer.Pickup.At, 22),
			Objectives.Reach("Deliver it to " .. offer.Dropoff.Name, offer.Dropoff.At, 26),
		},
		TimeLimit = offer.TimeLimit,
		ClockFrom = 2,
		Reward = { Cash = offer.Pay, Xp = math.floor(offer.Pay * 0.6) },
	}
	ObjectiveService.Start(player, objective, {
		Pay = false,
		OnDone = function(who: Player, run, ok: boolean)
			if not ok then
				return
			end
			local t = Workspace:GetServerTimeNow()
			local spare = math.clamp((run.Ends - t) / offer.TimeLimit, 0, 1)
			local rush = Events.Multiplier(t, "Jobs")
			local tip = math.floor(offer.Pay * 0.5 * spare * (if run.Crashes == 0 then 1 else 0.4))
			local ride = BikeService.Get(who)
			local cargo = if ride and ride.Riding and ride.Bike.Geometry.Kit == "Cargo" then JobService.CARGO_BONUS else 1
			local total = math.floor((offer.Pay + tip) * rush * cargo)
			EconomyService.Reward(who, total, objective.Reward.Xp, if tip > 0 then string.format("Delivery + $%d tip", tip) else "Delivery")
			local data = DataService.Get(who)
			if data then
				data.Stats.Deliveries += 1
				DataService.Changed(who)
			end
			JobService.Delivered:Fire(who, total)
			Remotes.Event("Notify"):FireClient(who, "Cash", string.format("📦 Delivered! $%d%s%s%s", offer.Pay, if tip > 0 then string.format(" + $%d tip", tip) else "", if rush > 1 then " · Courier Rush x2" else "", if cargo > 1 then string.format(" · cargo bike +%d%%", math.floor((cargo - 1) * 100 + 0.5)) else ""), total)
		end,
	})
	return true, objective.Title
end

function JobService.Init()
	local city = Workspace:WaitForChild("City", 60)
	if city then
		JobService.Scan(city)
	end
	if #pickups == 0 or #dropoffs == 0 then
		warn(string.format("[JobService] no delivery jobs: %d pick-ups, %d drop-offs in the city", #pickups, #dropoffs))
	end
	ObjectiveService.Handle("StartJob", function(player: Player, index: any)
		return JobService.Start(player, index)
	end)
	ObjectiveService.Overview("Jobs", function(player: Player)
		local list = {}
		for i, offer in JobService.Offers(player) do
			table.insert(list, {
				Index = i,
				From = offer.Pickup.Name,
				To = offer.Dropoff.Name,
				Km = offer.Distance / Config.STUDS_PER_METER / 1000, -- (as the bike measures it)
				Pay = offer.Pay,
				TimeLimit = offer.TimeLimit,
				Rush = Events.Multiplier(Workspace:GetServerTimeNow(), "Jobs") > 1,
			})
		end
		return list
	end)
	Players.PlayerRemoving:Connect(function(player)
		offers[player] = nil
	end)
end

return JobService
