--[[
	OrderService: ordering at shop counters. Every `OrderCounter` part in the city (City/Interior:
	walk-in shops, fast food, gas station stores) gets an Order prompt; the client opens its menu
	(UI/OrderMenu) and calls the Order remote, which checks the player is at that counter, takes
	the cash and gives what the item does (Shared/Menus): a timed cash multiplier (of several
	running, the best one counts; it multiplies a 2x boost) or a battery top-up for the bike
	parked by the store.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Menus = require(Shared.Menus)
local Remotes = require(Shared.Remotes)

local BikeService = require(script.Parent.BikeService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local OrderService = {}

local REACH = 24 -- studs from the counter an order counts
local CHARGE_REACH = 160 -- how far away the bike can be parked for a top-up

type Buff = { Factor: number, Until: number }
local buffs: { [Player]: { Buff } } = {}

local function factorOf(player: Player): number
	local list = buffs[player]
	if not list then
		return 1
	end
	local now = os.clock()
	local best = 1
	for i = #list, 1, -1 do
		if list[i].Until <= now then
			table.remove(list, i)
		else
			best = math.max(best, list[i].Factor)
		end
	end
	return best
end

local function order(player: Player, counter: any, itemId: any): (boolean, string)
	if typeof(counter) ~= "Instance" or not counter:IsA("BasePart") or counter.Name ~= "OrderCounter" or type(itemId) ~= "string" then
		return false, "Nothing to order here"
	end
	local menu = counter:GetAttribute("Menu")
	local item = if type(menu) == "string" then Menus.Get(menu, itemId) else nil
	if not item then
		return false, "Not on the menu"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or (root.Position - counter.Position).Magnitude > REACH then
		return false, "Walk up to the counter to order"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Not loaded yet"
	end
	if item.Charge then
		-- check the bike's in reach before taking the money
		if not BikeService.Charge(player, counter.Position, CHARGE_REACH) then
			return false, "Park your bike by the store first"
		end
		if not DataService.Spend(player, item.Price) then
			return false, string.format("You need %s more", Economy.FormatCash(item.Price - data.Cash))
		end
		return true, item.Icon .. " Battery topped up"
	end
	if not DataService.Spend(player, item.Price) then
		return false, string.format("You need %s more", Economy.FormatCash(item.Price - data.Cash))
	end
	local factor, minutes = item.Cash or 1, item.Minutes or 1
	local list = buffs[player] or {}
	buffs[player] = list
	table.insert(list, { Factor = factor, Until = os.clock() + minutes * 60 })
	local best = factorOf(player)
	player:SetAttribute("OrderBoost", best)
	return true, string.format("%s %s: %gx cash for %d min", item.Icon, item.Name, factor, minutes)
end

local function addPrompt(counter: BasePart)
	if counter:FindFirstChild("OrderPrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OrderPrompt"
	prompt.ActionText = "Order"
	local shopName = counter:GetAttribute("ShopName")
	prompt.ObjectText = if type(shopName) == "string" then shopName else "Counter"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter
end

function OrderService.Init()
	Remotes.Function("Order").OnServerInvoke = order
	local base = EconomyService.BoostOf
	EconomyService.BoostOf = function(player: Player): number
		return base(player) * factorOf(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		buffs[player] = nil
	end)
	-- expired buffs clear the HUD attribute
	task.spawn(function()
		while true do
			task.wait(2)
			for player in buffs do
				local f = factorOf(player)
				if player:GetAttribute("OrderBoost") ~= f then
					player:SetAttribute("OrderBoost", if f > 1 then f else nil)
				end
			end
		end
	end)
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 120)
		if not city then
			return
		end
		local count = 0
		for _, d in city:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "OrderCounter" then
				addPrompt(d)
				count += 1
			end
		end
		print(string.format("[OrderService] %d shop counters open", count))
	end)
end

return OrderService
