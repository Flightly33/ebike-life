--[[
	EconomyService: pays riders.

	Every Config.Economy.PayInterval it pays each rider the speed-based rate (Shared/Economy) times
	their cash multiplier, using the speed the server sees, and adds XP for the distance. Finished
	tricks (reported through the Trick remote, sanity-checked) pay lump sums, grow the combo and,
	when a cop is watching, the heat. Level-ups pay a reward.

	The multiplier is published as the "Mult" attribute so the HUD shows exactly what's paid.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local DataService = require(script.Parent.DataService)
local BikeService = require(script.Parent.BikeService)

local EconomyService = {}

local E = Config.Economy

type Tracker = {
	Unpaid: number, -- fractional dollars carried between ticks
	Combo: number,
	ComboAt: number,
	LastLand: number,
	LastWheelieEnd: number,
	LastDriftEnd: number?,
	WheelieComboStep: number,
	Popups: number, -- whole dollars paid since the last "+$" popup
}

local trackers: { [Player]: Tracker } = {}

-- (player, kind, amount): tricks the police care about ("Jump", "Flip", "Impact")
EconomyService.Trick = Signal.new()

-- Stars, set by PoliceService, and the cash boost, set by ShopService (avoids require cycles)
EconomyService.StarsOf = function(_player: Player): number
	return 0
end
EconomyService.BoostOf = function(_player: Player): number
	return 1
end

local function tracker(player: Player): Tracker
	local t = trackers[player]
	if not t then
		t = { Unpaid = 0, Combo = 0, ComboAt = 0, LastLand = 0, LastWheelieEnd = 0, WheelieComboStep = 0, Popups = 0 }
		trackers[player] = t
	end
	return t
end

function EconomyService.Multiplier(player: Player): number
	local ride = BikeService.Get(player)
	local t = tracker(player)
	local wheelie, hands = 0, 0
	if ride and ride.Riding then
		wheelie = BikeService.WheelieTime(ride)
		if BikeService.Kmh(ride) > 8 then
			hands = ride.State.Hands
		end
	end
	local boost = EconomyService.BoostOf(player)
	return Economy.Multiplier({
		WheelieTime = wheelie,
		Hands = hands,
		Combo = t.Combo,
		Stars = EconomyService.StarsOf(player),
		Boost = boost,
	})
end

local function notify(player: Player, kind: string, text: string, amount: number?)
	Remotes.Event("Notify"):FireClient(player, kind, text, amount)
end

local function addXp(player: Player, amount: number)
	local data = DataService.Get(player)
	if not data or amount <= 0 then
		return
	end
	local level, xp, reached = Economy.AddXp(data.Level, data.Xp, amount)
	data.Level = level
	data.Xp = xp
	for _, newLevel in reached do
		local reward = Economy.LevelReward(newLevel)
		DataService.AddCash(player, reward)
		notify(player, "Level", string.format("Level up! You're now level %d (+%s)", newLevel, Economy.FormatCash(reward)), reward)
	end
	if #reached > 0 then
		DataService.Changed(player)
	else
		player:SetAttribute("Xp", math.floor(xp))
	end
end

-- A lump sum for a trick: grows with the combo, and with the chase/boost multiplier
local function payTrick(player: Player, base: number, label: string)
	if base <= 0 then
		return
	end
	local t = tracker(player)
	local amount = math.floor(base * (1 + t.Combo) * EconomyService.BoostOf(player))
	DataService.AddCash(player, amount)
	Remotes.Event("Payout"):FireClient(player, amount, label)
	addXp(player, amount * 0.5)
end

local function bumpCombo(player: Player, amount: number)
	local t = tracker(player)
	t.Combo = math.min(E.ComboMax, t.Combo + amount)
	t.ComboAt = os.clock()
end

local function onTrick(player: Player, kind: any, value: any, extra: any, text: any)
	if type(kind) ~= "string" then
		return
	end
	local ride = BikeService.Get(player)
	if not ride or not ride.Riding then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local t = tracker(player)
	local now = os.clock()
	local v = tonumber(value) or 0
	local x = tonumber(extra) or 0

	if kind == "Land" then
		-- one landing per 0.3 s, at most 6 s of air
		if now - t.LastLand < 0.3 or v < Config.Physics.MinAirTime or v > 6 then
			return
		end
		t.LastLand = now
		if text == "Crash" then
			return
		end
		local clean = text == "Clean"
		payTrick(player, Economy.AirLump(v, clean), string.format("Air %.1fs%s", v, if clean then " · Clean" else ""))
		bumpCombo(player, E.ComboAir * math.min(v, 3))
		if v > data.Stats.LongestAir then
			data.Stats.LongestAir = math.floor(v * 10) / 10
			DataService.Changed(player)
		end
		EconomyService.Trick:Fire(player, "Jump", v)
	elseif kind == "Flip" then
		local flips = math.clamp(math.floor(v), 1, 3)
		if now - t.LastLand > 0.6 then
			return -- flips arrive with their landing
		end
		payTrick(player, E.FlipLump * flips, if flips > 1 then string.format("%dx Backflip!", flips) else "Backflip!")
		bumpCombo(player, E.ComboFlip * flips)
		data.Stats.Flips += flips
		DataService.Changed(player)
		EconomyService.Trick:Fire(player, "Flip", flips)
	elseif kind == "Spin" then
		local spins = math.clamp(math.floor(v), 1, 3)
		if now - t.LastLand > 0.6 then
			return
		end
		payTrick(player, E.SpinLump * spins, string.format("%d", spins * 360))
		bumpCombo(player, E.ComboSpin * spins)
	elseif kind == "NoHander" then
		if now - t.LastLand > 0.6 then
			return
		end
		payTrick(player, E.NoHanderLump, "No-hander!")
	elseif kind == "WheelieEnd" then
		-- trust the server's clock over the client's
		local since = ride.WheelieSince
		local seconds = math.min(v, if since then now - since + 1 else v)
		if now - t.LastWheelieEnd < 0.2 then
			return
		end
		t.LastWheelieEnd = now
		local failed = x == 1
		if not failed then
			payTrick(player, Economy.WheelieLump(seconds), string.format("Wheelie %.1fs", seconds))
			bumpCombo(player, E.ComboWheelie * math.floor(seconds / 5))
		end
		if seconds > data.Stats.BestWheelie then
			data.Stats.BestWheelie = math.floor(seconds * 10) / 10
			DataService.Changed(player)
			if seconds >= 3 then
				notify(player, "Info", string.format("New best wheelie: %.1fs", seconds))
			end
		end
	elseif kind == "DriftEnd" then
		-- trust the server's clock over the client's; one drift per 0.3 s
		local since = ride.DriftSince
		local seconds = math.clamp(math.min(v, if since then now - since + 1 else v), 0, 12)
		if now - (t.LastDriftEnd or 0) < 0.3 or text == "Failed" then
			return
		end
		t.LastDriftEnd = now
		local lump = Economy.DriftLump(seconds, x)
		if lump > 0 then
			payTrick(player, lump, string.format("Drift %.1fs · %d°", seconds, math.floor(math.clamp(x, 0, 75))))
			bumpCombo(player, E.ComboDrift)
			EconomyService.Trick:Fire(player, "Drift", seconds)
		end
	elseif kind == "Crash" then
		t.Combo = 0
		player:SetAttribute("Combo", 0)
	elseif kind == "Impact" then
		if type(text) == "string" and (text == "Cop" or text == "Car") then
			EconomyService.Trick:Fire(player, "Impact", v, text)
		end
	end
	player:SetAttribute("Combo", math.floor(t.Combo * 100) / 100)
end

function EconomyService.Init()
	Remotes.Event("Trick").OnServerEvent:Connect(onTrick)
	Players.PlayerRemoving:Connect(function(player)
		trackers[player] = nil
	end)

	task.spawn(function()
		local dt = E.PayInterval
		local popupClock = 0
		while true do
			task.wait(dt)
			popupClock += dt
			local showPopup = popupClock >= 1
			if showPopup then
				popupClock = 0
			end
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local t = tracker(player)
				-- the combo drains when you stop doing tricks
				if t.Combo > 0 and now - t.ComboAt > E.ComboDecay then
					t.Combo = math.max(0, t.Combo - dt * 0.25)
					player:SetAttribute("Combo", math.floor(t.Combo * 100) / 100)
				end
				local mult = EconomyService.Multiplier(player)
				if player:GetAttribute("Mult") ~= math.floor(mult * 100) / 100 then
					player:SetAttribute("Mult", math.floor(mult * 100) / 100)
				end
				local ride = BikeService.Get(player)
				if ride and ride.Riding and DataService.Get(player) then
					local kmh = BikeService.Kmh(ride)
					local earned = Economy.BaseRate(kmh) * mult * dt + t.Unpaid
					local whole = math.floor(earned)
					t.Unpaid = earned - whole
					if whole > 0 then
						DataService.AddCash(player, whole)
						t.Popups += whole
					end
					local meters = kmh / 3.6 * dt
					local data = DataService.Get(player)
					if data then
						data.Stats.Distance += meters
					end
					addXp(player, meters / 1000 * E.XpPerKm)
					if showPopup and t.Popups > 0 then
						Remotes.Event("Payout"):FireClient(player, t.Popups, "")
						t.Popups = 0
					end
				end
			end
		end
	end)
end

return EconomyService
