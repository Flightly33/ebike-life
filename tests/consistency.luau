--[[
	Data consistency: the catalog, upgrades, paints, modes, shop and city layout agree with each
	other and with the rules the game relies on. Pure checks, no simulator.

	lune run tests/consistency.luau
]]
local process = require("@lune/process")
local Loader = require("../tools/lune/loader")

local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeStats = Loader.Require("ReplicatedStorage.Shared.BikeStats")
local Upgrades = Loader.Require("ReplicatedStorage.Shared.Upgrades")
local Paints = Loader.Require("ReplicatedStorage.Shared.Paints")
local Modes = Loader.Require("ReplicatedStorage.Shared.Modes")
local Economy = Loader.Require("ReplicatedStorage.Shared.Economy")
local Profile = Loader.Require("ReplicatedStorage.Shared.Profile")
local Config = Loader.Require("ReplicatedStorage.Shared.Config")
local AssetIds = Loader.Require("ReplicatedStorage.Shared.AssetIds")
local AudioCatalog = Loader.Require("ReplicatedStorage.Shared.AudioCatalog")
local Layout = Loader.Require("ReplicatedStorage.Shared.City.Layout")

local failures = 0
local function check(ok: boolean, message: string)
	if not ok then
		failures += 1
		print("FAIL " .. message)
	end
end

-- Bikes: unique ids, rising price and level (a linear ladder), sane specs
local seen = {}
local previous = nil
for i, bike in Bikes.List do
	check(not seen[bike.Id], "unique bike id " .. bike.Id)
	seen[bike.Id] = true
	check(Bikes.RarityColors[bike.Rarity] ~= nil, bike.Id .. " has a known rarity")
	check(bike.PeakW >= bike.NominalW, bike.Id .. " peak power >= nominal")
	check(bike.MaxKmh >= bike.LegalKmh, bike.Id .. " unlocked speed >= legal speed")
	check(bike.Pedals or bike.Throttle, bike.Id .. " can be ridden (pedals or throttle)")
	check(bike.Class == "Off-road" or bike.Class == "Class 1" or bike.Class == "Class 2" or bike.Class == "Class 3", bike.Id .. " has a real e-bike class")
	if bike.Class == "Class 1" or bike.Class == "Class 2" then
		check(bike.LegalKmh == 32, bike.Id .. " Class 1/2 assist limit is 32 km/h (20 mph)")
	elseif bike.Class == "Class 3" then
		check(bike.LegalKmh == 45, bike.Id .. " Class 3 assist limit is 45 km/h (28 mph)")
	end
	if bike.Class == "Class 1" or bike.Class == "Class 3" then
		check(not bike.Throttle, bike.Id .. " Class 1/3 bikes are pedal-assist only")
	end
	local spec = BikeStats.Compute(bike, nil)
	local top = BikeStats.TopSpeedKmh(spec, 1, 3.4)
	check(top >= math.min(spec.CutoffKmh, 30) - 1, bike.Id .. " reaches its assist limit in TURBO (" .. top .. ")")
	if previous then
		check(bike.Price > previous.Price, bike.Id .. " costs more than the bike before it")
		check(bike.Level >= previous.Level, bike.Id .. " unlocks no earlier than the bike before it")
	end
	previous = bike
	local _ = i
end
check(Bikes.Get(Config.Economy.StarterBike) ~= nil and Bikes.Get(Config.Economy.StarterBike).Price == 0, "starter bike exists and is free")

-- Upgrades: every stage costs money, more for later stages
for _, bike in Bikes.List do
	for _, slot in Upgrades.Slots do
		local last = 0
		for level = 1, Upgrades.MaxLevel(slot.Name) do
			local cost = Upgrades.Cost(bike.Id, slot.Name, level)
			check(cost > last, string.format("%s %s stage %d costs more than stage %d", bike.Id, slot.Name, level, level - 1))
			last = cost
		end
	end
end
for _, slot in Upgrades.Slots do
	check(#slot.Levels >= 2, slot.Name .. " has at least one upgrade")
end

-- Paints: unique ids, every crate rarity has prizes
local paintIds = {}
for _, paint in Paints.List do
	check(not paintIds[paint.Id], "unique paint id " .. paint.Id)
	paintIds[paint.Id] = true
end
for _, crate in Paints.Crates do
	for rarity, weight in crate.Weights do
		if weight > 0 then
			local any = false
			for _, paint in Paints.List do
				if paint.Rarity == rarity and not paint.Free then
					any = true
				end
			end
			check(any, crate.Id .. " can roll " .. rarity .. " paints")
		end
	end
	for _ = 1, 200 do
		local paint = Paints.Roll(crate, math.random(), math.random())
		check(paint ~= nil and not paint.Free, crate.Id .. " rolls only crate paints")
	end
end

-- Modes: defaults are inside the customisation limits
for _, name in Modes.Order do
	local mode = Modes.Defaults[name]
	check(mode ~= nil, "default for mode " .. name)
	if name ~= "OFF" then
		local clean = Modes.Sanitize({ [name] = mode })[name]
		check(math.abs(clean.Assist - mode.Assist) < 1e-6 and math.abs(clean.MaxPower - mode.MaxPower) < 1e-6, name .. " defaults survive sanitising")
	end
end

-- Profile round trip
local data = Profile.Default()
local clean = Profile.Sanitize(data)
check(clean.Cash == Config.Economy.StartCash and clean.Owned[Config.Economy.StarterBike] == true, "a fresh profile sanitises to itself")
check(Profile.Sanitize({ Owned = { nope = true }, Cash = -5 }).Cash == 0, "bad saves are cleaned up")

-- Economy: XP steps grow linearly, multipliers stack
check(Economy.XpToNext(2) - Economy.XpToNext(1) == Economy.XpToNext(10) - Economy.XpToNext(9), "XP per level grows linearly")
check(math.abs(Economy.Multiplier({ WheelieTime = 2, Hands = 0, Combo = 0, Stars = 0, Boost = 1 }) - 1.1) < 1e-9, "2 s wheelie is 1.10x (as in the reference)")

-- Audio: every sound slot has a search
for name in AssetIds.Sounds do
	check(AudioCatalog.Effects[name] ~= nil, "sound slot " .. name .. " has a library search")
end

-- City: graph is connected, every charger sits inside the map
local reached = { [1] = true }
local queue = { 1 }
while #queue > 0 do
	local id = table.remove(queue)
	for _, edgeId in Layout.Nodes[id].Edges do
		local other = Layout.OtherEnd(Layout.Edges[edgeId], id)
		if not reached[other] then
			reached[other] = true
			table.insert(queue, other)
		end
	end
end
local count = 0
for _ in reached do
	count += 1
end
check(count == #Layout.Nodes, string.format("road graph is connected (%d/%d nodes)", count, #Layout.Nodes))
for _, p in Layout.Chargers do
	check(math.abs(p.X) < Layout.WORLD_HALF and math.abs(p.Z) < Layout.WORLD_HALF, "charger inside the map")
end
for id, place in Layout.Places do
	check(math.abs(place.X) < Layout.WORLD_HALF and math.abs(place.Z) < Layout.WORLD_HALF, "place " .. id .. " inside the map")
end
for _, t in Layout.Teleports do
	check(Layout.Places[t.Id] ~= nil, "teleport " .. t.Id .. " has a place")
end
for _, id in Loader.Require("ReplicatedStorage.Shared.Admin").Places do
	check(Layout.Places[id] ~= nil, "admin teleport " .. id .. " has a place")
end

-- Miami: nothing that's driven or stood on is in the bay unless it's a bridge or a causeway
for id, place in Layout.Places do
	check(not Layout.InWater(place.X, place.Z), "place " .. id .. " is on land")
end
for k, p in Layout.Chargers do
	check(not Layout.InWater(p.X, p.Z), "charger " .. k .. " is on land")
end
for _, block in Layout.Blocks do
	for _, corner in { { block.MinX, block.MinZ }, { block.MaxX, block.MaxZ }, { block.MinX, block.MaxZ }, { block.MaxX, block.MinZ } } do
		check(not Layout.InWater(corner[1], corner[2]), string.format("block %s %d,%d is on land", block.Grid, block.Bx, block.Bz))
	end
end
for _, node in Layout.Nodes do
	if Layout.InWater(node.Position.X, node.Position.Z) then
		check(node.Elevated, "road node " .. node.Id .. " over the water is up on the bridge")
	end
	check(node.Elevated == (node.Position.Y > Layout.ROAD_Y + 1), "node " .. node.Id .. " Elevated matches its height")
end
for _, edge in Layout.Edges do
	local a, b = Layout.Nodes[edge.A], Layout.Nodes[edge.B]
	local mid = (a.Position + b.Position) / 2
	if Layout.InWater(mid.X, mid.Z) and not (a.Elevated or b.Elevated) then
		check(edge.Kind == "Causeway", "edge " .. edge.Id .. " across the water is a causeway")
	end
	-- the street grid never climbs; only freeways, ramps and the bridge do
	if math.abs(a.Position.Y - b.Position.Y) > 0.5 then
		check(edge.Kind == "Freeway" or edge.Kind == "Ramp", "edge " .. edge.Id .. " that climbs is a freeway or a ramp")
		check(math.abs(a.Position.Y - b.Position.Y) / edge.Length < 0.16, "edge " .. edge.Id .. " climbs no steeper than 16%")
	end
end
check(Layout.Nodes[Layout.PoliceSpawn].Grid, "police spawn at a grid crossing")
for _, ramp in Layout.Ramps do
	check(#Layout.Nodes[ramp.Foot].Edges == 3, "ramp foot is a T on its street")
	check(not Layout.Nodes[ramp.Base].Elevated and Layout.Nodes[ramp.Top].Elevated, "ramp climbs from its base to its top")
end

-- The baked map: every place (teleports, the spawn) and charger is on open ground (a ray from
-- high above lands near its height, not on a roof) with room around it
do
	local fs = require("@lune/fs")
	local roblox = require("@lune/roblox")
	local GeoWorld = require("../tools/lune/geoworld")
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local city = roblox.deserializeModel(fs.readFile("map/City.rbxm"))[1]
	local geo = GeoWorld.new(city)
	local function openGround(p: Vector3, what: string, room: boolean)
		local hit = geo.Physics.Down(Vector3.new(p.X, p.Y + 400, p.Z), 500)
		check(hit ~= nil and math.abs(hit.Position.Y - p.Y) < 3, string.format("%s lands on the ground (hit %s at %s)", what, if hit and hit.Part then hit.Part:GetFullName() else "nothing", if hit then string.format("%.1f", hit.Position.Y) else "-"))
		if room then
			for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
				local frame = CFrame.new(p + Vector3.new(0, 3.5, 0))
				local distance, _, kind = geo.Physics.Sweep(frame, Vector3.new(2, 4, 2), d * 8)
				check(distance == nil or kind ~= "Wall", string.format("%s has room around it (%s)", what, if geo.LastSweepPart then geo.LastSweepPart:GetFullName() else "-"))
			end
		end
	end
	for id, place in Layout.Places do
		openGround(place, "place " .. id, true)
	end
	for k, p in Layout.Chargers do
		-- where the bike parks: on the charging pad in front of the kiosk
		openGround(p + (Layout.ChargerFacing[k] or Vector3.new(0, 0, 1)) * 6, "charger " .. k, false)
	end
end

-- The day and night clock: continuous, invertible, and a full look at every hour
do
	local DayNight = Loader.Require("ReplicatedStorage.Shared.DayNight")
	local day = Config.DayNight.DaySeconds
	local last = DayNight.Hour(0)
	local jumps, dayTime = 0, 0
	for i = 1, 2400 do
		local t = i * day / 2400
		local h = DayNight.Hour(t)
		local step = (h - last) % 24
		if step > 0.5 then
			jumps += 1
		end
		if h >= 6 and h < 20 then
			dayTime += 1
		end
		last = h
	end
	check(jumps == 0, "the clock never jumps")
	check(math.abs(dayTime / 2400 - Config.DayNight.DayShare) < 0.01, "daylight takes DayShare of a day")
	local worst = 0
	for hour = 0, 23.5, 0.5 do
		local back = DayNight.Hour((DayNight.FractionAt(hour) - Config.DayNight.StartFraction) * day)
		worst = math.max(worst, math.abs(((back - hour + 12) % 24) - 12))
	end
	check(worst < 0.01, "FractionAt inverts the clock (admin time command)")
	local ok = true
	for hour = 0, 24, 0.25 do
		local look = DayNight.LookAt(hour)
		for _, key in { "Brightness", "Night", "Bloom", "AtmoDensity" } do
			if type((look :: any)[key]) ~= "number" then
				ok = false
			end
		end
	end
	check(ok, "every hour has a full look")
	check(DayNight.LookAt(1).Night > 0.9 and DayNight.LookAt(13).Night < 0.01, "night is lit, noon isn't")
end

-- Weather: the spells come up in about their odds, ease into each other with no jumps, and the
-- admin override holds one kind
do
	local Weather = Loader.Require("ReplicatedStorage.Shared.Weather")
	local cfg = Config.Weather
	local counts: { [string]: number } = { Clear = 0, Cloudy = 0, Overcast = 0 }
	local spells = 4000
	for i = 1, spells do
		local kind = Weather.KindOf(i)
		counts[kind] += 1
	end
	local total = 0
	for _, odds in cfg.Odds do
		total += odds
	end
	for kind, n in counts do
		local want = cfg.Odds[kind] / total
		check(math.abs(n / spells - want) < 0.04, string.format("%s spells come up %.2f of the time (odds %.2f)", kind, n / spells, want))
	end
	-- the biggest change over one second of server time, as a share of how far that value goes
	-- from one kind to another, across a few hours of spells
	local range: { [string]: number } = {}
	for key in Weather.Kinds.Clear do
		local lo, hi = math.huge, -math.huge
		for _, conditions in Weather.Kinds do
			lo, hi = math.min(lo, (conditions :: any)[key]), math.max(hi, (conditions :: any)[key])
		end
		range[key] = math.max(hi - lo, 1e-6)
	end
	local worst = 0
	local before = Weather.At(1e6)
	for t = 1e6 + 1, 1e6 + 6 * 3600 do
		local now = Weather.At(t)
		for key, value in now do
			worst = math.max(worst, math.abs(value - (before :: any)[key]) / range[key])
		end
		before = now
	end
	-- a smoothstep over BlendSeconds peaks at 1.5 / BlendSeconds of the way a second
	check(worst < 2 / cfg.BlendSeconds, string.format("the weather eases from spell to spell (worst step %.3f of the range a second)", worst))
	local held, kind = Weather.At(1e6, "Overcast")
	check(kind == "Overcast" and held.Cover == Weather.Kinds.Overcast.Cover, "the admin override holds its kind")
	local free = Weather.At(1e6, "")
	check(free.Cover > 0, "an empty override lets the spells run")
end

-- Activities: every race course builds along connected roads, every mission's places exist and
-- the missions open in a chain from the first; dailies and events are well formed
do
	local Races = Loader.Require("ReplicatedStorage.Shared.Races")
	local Missions = Loader.Require("ReplicatedStorage.Shared.Missions")
	local Dailies = Loader.Require("ReplicatedStorage.Shared.Dailies")
	local Events = Loader.Require("ReplicatedStorage.Shared.Events")
	for _, course in Races.Courses do
		local built = Races.Build(course)
		local ok = #built.Points >= 2 and built.Length > 400 and built.Gold < built.Silver and built.Silver < built.Bronze and built.Pay > 0
		for _, place in course.Via do
			ok = ok and (Layout.Places :: any)[place] ~= nil
		end
		check(ok, string.format("race %s: %d checkpoints over %.0f studs, gold %ds", course.Id, #built.Points, built.Length, built.Gold))
	end
	local ids, open = {}, {}
	local missionsOk = true
	for _, m in Missions.List do
		ids[m.Id] = true
		if m.Requires and not ids[m.Requires] then
			missionsOk = false
			print("[test]   " .. m.Id .. " needs a mission that comes after it: " .. tostring(m.Requires))
		end
		local objective = Missions.Objective(m)
		for _, step in objective.Steps do
			if step.Kind == "Reach" and typeof(step.At) ~= "Vector3" then
				missionsOk = false
				print("[test]   " .. m.Id .. ": a place that doesn't exist")
			end
		end
		if Missions.Status(m, open, 100) == "Ready" then
			open[m.Id] = true
		end
	end
	check(missionsOk, string.format("%d missions: places exist, each needs an earlier one", #Missions.List))
	-- doing every mission in order (at a high level) leaves none locked
	local done = {}
	for _ = 1, #Missions.List do
		for _, m in Missions.List do
			if Missions.Status(m, done, 100) == "Ready" then
				done[m.Id] = true
			end
		end
	end
	local all = true
	for _, m in Missions.List do
		all = all and done[m.Id] == true
	end
	check(all, "every mission can be reached from the first")
	local seen = {}
	local dailyOk = true
	for _, c in Dailies.Daily do
		dailyOk = dailyOk and not seen[c.Id] and string.sub(c.Id, 1, 2) == "d_" and c.Goal > 0 and c.Reward > 0
		seen[c.Id] = true
	end
	for _, c in Dailies.Weekly do
		dailyOk = dailyOk and not seen[c.Id] and Dailies.IsWeekly(c.Id) and c.Goal > 0 and c.Reward > 0
		seen[c.Id] = true
	end
	local picks = Dailies.ForDay(20000)
	check(dailyOk and #picks == Dailies.PER_DAY and picks[1].Id ~= picks[2].Id and #Dailies.ForWeek(2900) == Dailies.PER_WEEK, "daily and weekly challenges: unique ids, picked without repeats")
	local eventsSeen, running = {}, 0
	for t = 0, Events.SLOT * #Events.List * 2 - 1, 60 do
		local event = Events.At(t)
		if event then
			eventsSeen[event.Id] = true
			running += 1
		end
	end
	local every = true
	for _, e in Events.List do
		every = every and eventsSeen[e.Id] == true
	end
	check(every and math.abs(running / (Events.SLOT * #Events.List * 2 / 60) - Events.ACTIVE / Events.SLOT) < 0.02, "every event comes round, each running half its slot")
end

-- Controls: defaults unique and bindable, binding swaps instead of leaving a control keyless, the
-- fixed extras step aside for a key another control takes, and the save keeps only valid changes
do
	local Controls = Loader.Require("ReplicatedStorage.Shared.Controls")
	local defaults, ok = {}, true
	for _, a in Controls.List do
		ok = ok and Controls.ValidKey(a.Default) and not defaults[a.Default] and Controls.GroupNames[a.Group] ~= nil
		defaults[a.Default] = true
		for _, alt in a.Alt or {} do
			ok = ok and Controls.ValidKey(alt) and not defaults[alt]
		end
	end
	check(ok, string.format("%d controls: default keys unique, bindable, in a known group", #Controls.List))
	check(not Controls.ValidKey("B") and not Controls.ValidKey("Space") and not Controls.ValidKey("Escape") and not Controls.ValidKey("Banana"), "reserved and unknown keys can't be bound")
	-- Hop onto R (Drift's key): Drift gets Q
	local keys = assert(Controls.Bind(nil, "Hop", "R"))
	check(Controls.Key(keys, "Hop") == "R" and Controls.Key(keys, "Drift") == "Q", "binding a taken key swaps the two controls")
	-- back to the defaults: nothing saved
	local back = assert(Controls.Bind(keys, "Hop", "Q"))
	check(next(back) == nil, "keys back at their defaults save nothing")
	-- Hop onto LeftControl (one of Wheelie's extras): Wheelie loses it, keeps the rest
	local ctrl = assert(Controls.Bind(nil, "Hop", "LeftControl"))
	local wheelie = Controls.Keys(ctrl, "Wheelie")
	check(Controls.Key(ctrl, "Hop") == "LeftControl" and not table.find(wheelie, "LeftControl") and table.find(wheelie, "LeftShift") ~= nil, "a fixed extra steps aside for a key another control takes")
	check(Controls.ActionOf(nil, "Up") == "Gas" and Controls.ActionOf(nil, "LeftControl") == "Wheelie", "the arrows and Ctrl work as extras by default")
	local refused, why = Controls.Bind(nil, "Gas", "B")
	check(refused == nil and type(why) == "string", "binding a reserved key is refused with a reason")
	local clean = Profile.Sanitize({ Settings = { Keys = { Gas = "I", Brake = "B", Nope = "K", Hop = 5 }, HudScale = 9, HudLayout = "Huge" } }).Settings
	check(clean.Keys.Gas == "I" and clean.Keys.Brake == nil and clean.Keys.Nope == nil and clean.Keys.Hop == nil and clean.HudScale == 1.3 and clean.HudLayout == "Auto", "saved settings: only valid key changes, HUD size and layout clamped")
end

-- Dailies.Claimable: the streak and finished challenges count, but only for their own day and week
do
	local Dailies = Loader.Require("ReplicatedStorage.Shared.Dailies")
	local t = 20000 * 86400 + 3600
	local day, week = Dailies.Day(t), Dailies.Week(t)
	local first = Dailies.ForDay(day)[1]
	local fresh = { LastLogin = 0, Day = day, Week = week, Progress = { [first.Stat] = first.Goal }, WeekProgress = {}, Claimed = {} }
	local n = Dailies.Claimable(fresh, t)
	check(n >= 2, "a waiting streak and a finished challenge both count (" .. n .. ")")
	fresh.LastLogin = day
	fresh.Claimed[first.Id] = true
	check(Dailies.Claimable(fresh, t) == 0, "claimed things don't count")
	local stale = { LastLogin = day, Day = day - 1, Week = week, Progress = { [first.Stat] = 1e9 }, WeekProgress = {}, Claimed = {} }
	check(Dailies.Claimable(stale, t) == 0, "yesterday's progress doesn't count today")
end

-- Rider gear: unique ids, every slot stocked, sane prices, and the save keeps only what's owned
do
	local Gear = Loader.Require("ReplicatedStorage.Shared.Gear")
	local seenGear, ok = {}, true
	for _, item in Gear.List do
		ok = ok and not seenGear[item.Id] and Gear.IsSlot(item.Slot) and item.Price >= 0 and item.Level >= 1 and item.Style ~= ""
		seenGear[item.Id] = true
	end
	for _, slot in Gear.Slots do
		ok = ok and #Gear.ForSlot(slot) >= 2
	end
	check(ok, string.format("%d gear items: unique ids, every slot stocked", #Gear.List))
	local fresh = Profile.Default()
	check(fresh.Gear.Owned.h_open == true and next(fresh.Gear.Worn) == nil, "everyone owns the free helmet, nobody wears anything to start")
	local clean = Profile.Sanitize({ Gear = { Owned = { h_mx = true, nope = true }, Worn = { Helmet = "h_mx", Jacket = "j_leather", Boots = "h_open" } } }).Gear
	check(clean.Owned.h_mx == true and clean.Owned.nope == nil and clean.Worn.Helmet == "h_mx" and clean.Worn.Jacket == nil and clean.Worn.Boots == nil, "the save wears only owned gear, each in its own slot")
end

if failures > 0 then
	print(string.format("%d consistency check(s) failed", failures))
	process.exit(1)
end
print("consistency checks passed")
