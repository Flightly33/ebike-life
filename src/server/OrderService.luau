--[[
	OrderService: ordering at shop counters. Every `OrderCounter` part in the city (City/Interior)
	gets an Order prompt; the client opens its theme's menu (UI/OrderMenu) and calls the Order
	remote. The server checks the player is at that counter, takes the cash and applies the item's
	effects (Shared/Menus):
	  Cash / Xp  timed multipliers (of several running, the best of each counts), shown on the HUD
	             through the player's `BuffCash` / `BuffCashUntil` / `BuffXp` / `BuffXpUntil`
	             attributes (server time)
	  Charge     fills the battery of the bike parked by the shop
	  Heat       takes wanted stars off, once every Menus.HeatCooldown seconds
	The bought item (Shared/Models/ItemModel) appears in the player's right hand for everyone to see,
	is eaten in bites (or sipped), then goes. The counter's `LastOrder` attribute tells the shop's
	staff (Client/ShopFit) to hand it over.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local ItemModel = require(Shared.Models.ItemModel)
local Menus = require(Shared.Menus)
local Remotes = require(Shared.Remotes)

local BikeService = require(script.Parent.BikeService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PoliceService = require(script.Parent.PoliceService)

local OrderService = {}

local REACH = 26 -- studs from the counter an order counts
local CHARGE_REACH = 160 -- how far away the bike can be parked for a top-up
local HOLD_SECONDS = 7 -- how long a bought item stays in the hand
local ITEM_SCALE = Config.Avatar.Height / 1.75 -- studs per metre at the avatar's size

type Buff = { Factor: number, Until: number }
type Buffs = { Cash: { Buff }, Xp: { Buff }, HeatAt: number, Held: Model? }
local state: { [Player]: Buffs } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function buffsOf(player: Player): Buffs
	local b = state[player]
	if not b then
		b = { Cash = {}, Xp = {}, HeatAt = -math.huge, Held = nil }
		state[player] = b
	end
	return b
end

-- The best running factor of a kind, and when it ends
local function best(list: { Buff }): (number, number)
	local t = now()
	local factor, untilAt = 1, 0
	for i = #list, 1, -1 do
		local buff = list[i]
		if buff.Until <= t then
			table.remove(list, i)
		elseif buff.Factor > factor or (buff.Factor == factor and buff.Until > untilAt) then
			factor, untilAt = buff.Factor, buff.Until
		end
	end
	return factor, untilAt
end

local function publish(player: Player)
	local b = state[player]
	if not b then
		return
	end
	for _, kind in { "Cash", "Xp" } do
		local factor, untilAt = best((b :: any)[kind])
		local f: number? = if factor > 1 then factor else nil
		local u: number? = if factor > 1 then untilAt else nil
		if player:GetAttribute("Buff" .. kind) ~= f then
			player:SetAttribute("Buff" .. kind, f)
		end
		if player:GetAttribute("Buff" .. kind .. "Until") ~= u then
			player:SetAttribute("Buff" .. kind .. "Until", u)
		end
	end
end

-- The item in the right hand, eaten in bites, then gone
local function hold(player: Player, item: Menus.Item)
	local character = player.Character
	if not character then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local b = buffsOf(player)
	local old = b.Held
	if old then
		old:Destroy()
	end
	local model = ItemModel.Build(item.Id, ITEM_SCALE)
	local handle = model.PrimaryPart :: BasePart
	-- held upright in the palm (upright with the hand: an arm hanging down or bent up to the mouth),
	-- its bottom a little under the hand and just in front of it
	local tall = model:GetExtentsSize().Y
	local offset = CFrame.new(0, -hand.Size.Y * 0.5 - tall * 0.25, -hand.Size.Z * 0.5 - 0.15)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if d ~= handle then
				local w = Instance.new("WeldConstraint")
				w.Part0 = handle
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	model:PivotTo(hand.CFrame * offset)
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = offset
	weld.Parent = handle
	model.Parent = character
	b.Held = model
	-- crumbs (or drips) at each bite
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Size = NumberSequence.new(0.12)
	emitter.Color = ColorSequence.new(if item.Eat then Color3.fromRGB(220, 170, 90) else Color3.fromRGB(200, 230, 255))
	emitter.Parent = handle
	task.spawn(function()
		local bites = if item.Eat then 4 else 3
		task.wait(1.2)
		for i = 1, bites do
			if model.Parent == nil then
				return
			end
			emitter:Emit(if item.Eat then 10 else 4)
			if item.Eat then
				pcall(function()
					model:ScaleTo(math.max(0.25, 1 - i / (bites + 1)))
				end)
			end
			task.wait((HOLD_SECONDS - 1.2) / bites)
		end
		if b.Held == model then
			b.Held = nil
		end
		model:Destroy()
	end)
end

local function order(player: Player, counter: any, itemId: any): (boolean, string)
	if typeof(counter) ~= "Instance" or not counter:IsA("BasePart") or counter.Name ~= "OrderCounter" or type(itemId) ~= "string" then
		return false, "Nothing to order here"
	end
	local theme = counter:GetAttribute("Menu")
	local item = if type(theme) == "string" then Menus.Get(theme, itemId) else nil
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
	if data.Cash < item.Price then
		return false, string.format("You need %s more", Economy.FormatCash(item.Price - data.Cash))
	end
	local b = buffsOf(player)
	-- checks before the money goes
	if item.Charge and not BikeService.Charge(player, counter.Position, CHARGE_REACH) then
		return false, "Park your bike by the shop first"
	end
	if item.Heat then
		if PoliceService.Stars(player) <= 0 then
			return false, "Nobody's looking for you"
		end
		local wait = b.HeatAt + Menus.HeatCooldown - now()
		if wait > 0 then
			return false, string.format("The cops know that trick: try again in %ds", math.ceil(wait))
		end
	end
	if not DataService.Spend(player, item.Price) then
		return false, "Not enough cash"
	end
	local said: { string } = {}
	if item.Heat then
		b.HeatAt = now()
		PoliceService.SetWanted(player, math.max(0, PoliceService.Stars(player) - item.Heat))
		table.insert(said, "the cops lost you")
	end
	if item.Charge then
		table.insert(said, "battery full")
	end
	local minutes = item.Minutes or 1
	if item.Cash then
		table.insert(b.Cash, { Factor = item.Cash, Until = now() + minutes * 60 })
		table.insert(said, string.format("%gx cash", item.Cash))
	end
	if item.Xp then
		table.insert(b.Xp, { Factor = item.Xp, Until = now() + minutes * 60 })
		table.insert(said, string.format("%gx XP", item.Xp))
	end
	publish(player)
	counter:SetAttribute("LastOrder", item.Id .. ":" .. player.UserId .. ":" .. string.format("%.2f", now()))
	hold(player, item)
	local tail = if item.Cash or item.Xp then string.format(" for %d min", minutes) else ""
	return true, string.format("%s %s: %s%s", item.Icon, item.Name, table.concat(said, ", "), tail)
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
	local baseCash = EconomyService.BoostOf
	EconomyService.BoostOf = function(player: Player): number
		local b = state[player]
		return baseCash(player) * (if b then (best(b.Cash)) else 1)
	end
	local baseXp = EconomyService.XpBoostOf
	EconomyService.XpBoostOf = function(player: Player): number
		local b = state[player]
		return baseXp(player) * (if b then (best(b.Xp)) else 1)
	end
	Players.PlayerRemoving:Connect(function(player)
		state[player] = nil
	end)
	-- expired buffs come off the HUD
	task.spawn(function()
		while true do
			task.wait(1)
			for player in state do
				publish(player)
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
