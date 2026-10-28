--[[
	Riding-model checks: runs BikePhysics against small analytic worlds (flat road, a kicker ramp, a
	wall) and checks the numbers come out like real e-bikes.

	lune run tests/physics.luau [verbose]
]]
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("../tools/lune/loader")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeStats = Loader.Require("ReplicatedStorage.Shared.BikeStats")
local BikePhysics = Loader.Require("ReplicatedStorage.Shared.BikePhysics")
local Suspension = Loader.Require("ReplicatedStorage.Shared.Suspension")
local Modes = Loader.Require("ReplicatedStorage.Shared.Modes")
local Config = Loader.Require("ReplicatedStorage.Shared.Config")

local verbose = process.args[1] == "verbose"
local failures = 0
local function check(ok: boolean, message: string)
	if ok then
		if verbose then
			print("  ok   " .. message)
		end
	else
		failures += 1
		print("  FAIL " .. message)
	end
end

local DT = 1 / 60

-- World: flat road at y = 0, optional kicker ramp (rising toward -Z), optional wall across -Z
type Options = { RampStart: number?, RampLength: number?, RampHeight: number?, WallZ: number?, WallKind: string?, Grass: boolean?, DropZ: number?, DropHeight: number?, QuarterStart: number?, QuarterRadius: number?, QuarterAngle: number?, DeckZ: number?, DeckHeight: number?, StepZ: number?, StepHeight: number? }

local function makeWorld(opt: Options)
	local function height(x: number, z: number): (number, string, any)
		local _ = x
		-- a quarter pipe: a circular transition rising toward -Z, up to QuarterAngle
		if opt.QuarterStart and opt.QuarterRadius and opt.QuarterAngle then
			local r = opt.QuarterRadius
			local d = opt.QuarterStart - z
			if d >= 0 and d <= r * math.sin(opt.QuarterAngle) then
				local h = r - math.sqrt(r * r - d * d)
				return h, "Ramp", Vector3.new(0, r - h, d).Unit
			end
		end
		if opt.RampStart and opt.RampLength and opt.RampHeight then
			local start, length, h = opt.RampStart, opt.RampLength, opt.RampHeight
			if z <= start and z >= start - length then
				return h * (start - z) / length, "Ramp", Vector3.new(0, 1, h / length).Unit
			end
		end
		if opt.StepZ and opt.StepHeight and z <= opt.StepZ then
			-- a kerb: a sharp step up (or down, negative) at StepZ
			return opt.StepHeight, if opt.Grass then "Grass" else "Road", Vector3.new(0, 1, 0)
		end
		if opt.DeckZ and opt.DeckHeight and z <= opt.DeckZ then
			return opt.DeckHeight, "Ramp", Vector3.new(0, 1, 0)
		end
		if opt.DropZ and opt.DropHeight and z < opt.DropZ then
			return -opt.DropHeight, "Road", Vector3.new(0, 1, 0)
		end
		return 0, if opt.Grass then "Grass" else "Road", Vector3.new(0, 1, 0)
	end
	local world = {}
	function world.Down(origin, length)
		local h, kind, normal = height(origin.X, origin.Z)
		if origin.Y < h then
			-- Ray starts inside the ramp: Roblox ignores that part; the road under it is at 0
			h, kind, normal = 0, "Road", Vector3.new(0, 1, 0)
		end
		if origin.Y >= h and origin.Y - length <= h then
			return { Position = Vector3.new(origin.X, h, origin.Z), Normal = normal, Kind = kind }
		end
		return nil
	end
	function world.Sweep(frame, size, delta)
		if not opt.WallZ or delta.Z >= 0 then
			return nil
		end
		local front = frame.Position.Z - size.Z / 2
		local after = front + delta.Z
		if front >= opt.WallZ and after < opt.WallZ then
			local distance = (front - opt.WallZ) / math.abs(delta.Z) * delta.Magnitude
			return distance, Vector3.new(0, 0, 1), opt.WallKind or "Wall"
		end
		return nil
	end
	return world
end

local function input(t: { [string]: any }?)
	local i = BikePhysics.Idle()
	for k, v in t or {} do
		(i :: any)[k] = v
	end
	return i
end

local function spawn(id: string, levels: any?)
	local bike = Bikes.Get(id)
	assert(bike, id)
	local spec = BikeStats.Compute(bike, levels)
	local state = BikePhysics.new(spec, CFrame.new(0, 0, 0))
	return spec, state
end

-- Runs `seconds` of riding; `each(t, state, events)` can change the input. Returns all events.
local function ride(spec, state, mode, world, seconds: number, inp, each: ((number, any, { any }) -> ())?)
	local all = {}
	local t = 0
	while t < seconds do
		local events = BikePhysics.Step(state, spec, mode, inp, world, DT)
		for _, e in events do
			e.Time = t
			table.insert(all, e)
		end
		if each then
			each(t, state, events)
		end
		t += DT
	end
	return all
end

local function kmh(state): number
	return BikePhysics.Kmh(state)
end

local flat = makeWorld({})

-- a run-up callback that holds the bike at `limit` km/h (the e-motos would otherwise be flat out)
local function atMost(limit: number)
	return function(_t: number, s: any)
		if BikePhysics.Kmh(s) > limit then
			s.Speed = limit / 3.6
		end
	end
end

-- run up at `limit` km/h, then let go of the throttle from `coastZ` on: capping the speed while the
-- throttle is open reads as endless acceleration, which squats the suspension
local function runUp(limit: number, coastZ: number, inp: any)
	local cap = atMost(limit)
	return function(t: number, s: any)
		if s.Position.Z > coastZ then
			cap(t, s)
		else
			inp.Throttle = 0
		end
	end
end

print("== top speeds (full throttle, TURBO, flat road)")
for _, bike in Bikes.List do
	local spec, state = spawn(bike.Id)
	local reached25: number? = nil
	ride(spec, state, Modes.Defaults.TURBO, flat, 90, input({ Throttle = 1 }), function(t, s)
		if not reached25 and kmh(s) >= 25 then
			reached25 = t
		end
	end)
	local top = kmh(state)
	local predicted = math.min(spec.CutoffKmh, BikeStats.TopSpeedKmh(spec, 1, 3.4))
	print(string.format("  %-10s top %5.1f km/h (limit %d, predicted %d)  0-25 %s s  battery %3d/%d Wh", bike.Id, top, spec.CutoffKmh, predicted, if reached25 then string.format("%.1f", reached25) else "-", math.floor(state.Battery), math.floor(spec.BatteryWh)))
	check(top <= spec.CutoffKmh + 1.5, bike.Id .. " stays under its assist limit")
	check(math.abs(top - predicted) <= math.max(2.5, predicted * 0.03), bike.Id .. " top speed matches the power balance")
	check(reached25 ~= nil and reached25 < 9, bike.Id .. " reaches 25 km/h in under 9 s")
end

print("== modes change acceleration and drain")
do
	local results = {}
	for _, name in { "ECO", "TOUR", "SPORT", "TURBO" } do
		local spec, state = spawn("trail_t")
		local t25: number? = nil
		ride(spec, state, Modes.Defaults[name], flat, 30, input({ Throttle = 1 }), function(t, s)
			if not t25 and kmh(s) >= 25 then
				t25 = t
			end
		end)
		results[name] = { T = t25 or 99, Used = spec.BatteryWh - state.Battery, Top = kmh(state) }
		print(string.format("  %-6s 0-25 %.1f s, top %.1f km/h, used %.1f Wh in 30 s", name, t25 or 99, kmh(state), spec.BatteryWh - state.Battery))
	end
	check(results.ECO.T > results.TURBO.T, "ECO accelerates slower than TURBO")
	check(results.ECO.Used < results.TURBO.Used, "ECO uses less battery than TURBO")
end

print("== OFF mode: no pedals, so no drive")
do
	local spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.OFF, flat, 10, input({ Throttle = 1 }))
	print(string.format("  throttle in OFF: %.1f km/h", kmh(state)))
	check(kmh(state) < 1, "the throttle does nothing in OFF")
	check(state.Battery == spec.BatteryWh, "OFF uses no battery")
	check(not spec.Pedals, "every Flightly is an e-moto with no pedals")
end

print("== battery: full-throttle runtime and the empty-pack cut-out")
do
	for _, id in { "flit_mini", "storm_x" } do
		local spec, state = spawn(id)
		local t = 0
		local emptyAt: number? = nil
		while t < 3600 do
			BikePhysics.Step(state, spec, Modes.Defaults.TURBO, input({ Throttle = 1 }), flat, 0.05)
			t += 0.05
			if state.Battery <= 0 then
				emptyAt = t
				break
			end
		end
		print(string.format("  %s: empty after %s min at full throttle", id, if emptyAt then string.format("%.1f", emptyAt / 60) else ">60"))
		check(emptyAt ~= nil and emptyAt > 180 and emptyAt < 2700, id .. " battery lasts 3-45 minutes flat out")
		ride(spec, state, Modes.Defaults.TURBO, flat, 60, input({ Brake = 1 }), function(_, s)
			if s.Speed < 0 then
				s.Speed = 0
			end
		end)
		ride(spec, state, Modes.Defaults.TURBO, flat, 30, input({ Throttle = 1 }))
		local speed = kmh(state)
		print(string.format("  %s with an empty pack: %.1f km/h", id, speed))
		if spec.Pedals then
			check(speed > 15 and speed < 32, id .. " can still be pedalled home")
		else
			check(speed < 3, id .. " (no pedals) stops")
		end
	end
end

print("== braking")
do
	local spec, state = spawn("flit_mini")
	ride(spec, state, Modes.Defaults.TURBO, flat, 15, input({ Throttle = 1 }))
	local startZ = state.Position.Z
	local before = kmh(state)
	ride(spec, state, Modes.Defaults.TURBO, flat, 6, input({ Brake = 1 }), function(_, s)
		if s.Speed <= 0.01 then
			s.Speed = 0
		end
	end)
	local distance = math.abs(state.Position.Z - startZ) * Config.METERS_PER_STUD
	print(string.format("  rear brake: %.0f km/h to stop in %.1f m", before, distance))
	local k = (before / 49) ^ 2 -- stopping distance grows with the square of the speed
	check(distance > 12 * k and distance < 28 * k, "the rear brake alone stops at about 0.45 g (12-28 m from 49 km/h)")
	-- the front brake (brake + Shift) stops much harder
	spec, state = spawn("flit_mini")
	ride(spec, state, Modes.Defaults.TURBO, flat, 15, input({ Throttle = 1 }))
	startZ = state.Position.Z
	ride(spec, state, Modes.Defaults.TURBO, flat, 6, input({ Brake = 1, Wheelie = true }), function(_, s)
		if s.Speed <= 0.01 then
			s.Speed = 0
		end
	end)
	local front = math.abs(state.Position.Z - startZ) * Config.METERS_PER_STUD
	print(string.format("  front brake: to stop in %.1f m", front))
	check(front < distance * 0.75, "the front brake stops harder than the rear")
end

print("== steering and lean")
do
	local spec, state = spawn("flit_s")
	ride(spec, state, Modes.Defaults.TURBO, flat, 12, input({ Throttle = 1 }))
	local yaw0 = state.Yaw
	local maxLean = 0
	local before = kmh(state)
	local early = 0
	ride(spec, state, Modes.Defaults.TURBO, flat, 1, input({ Throttle = 1, Steer = 1 }), function(t, s)
		maxLean = math.max(maxLean, math.abs(s.Lean))
		if t < 0.1 then
			early = yaw0 - s.Yaw
		end
	end)
	local yaw1 = state.Yaw
	ride(spec, state, Modes.Defaults.TURBO, flat, 1, input({ Throttle = 1, Steer = 1 }))
	local steady = yaw1 - state.Yaw
	print(string.format("  turned %.0f deg in the first second, then %.0f deg/s, from %.0f to %.0f km/h, max lean %.0f deg, %.1f deg in the first 0.1 s", math.deg(yaw0 - yaw1), math.deg(steady), before, kmh(state), math.deg(maxLean), math.deg(early)))
	check(yaw0 - yaw1 > 0.5, "steering right turns right (yaw decreases)")
	-- the reference game carves ~85 degrees a second at speed and barely slows
	check(steady > math.rad(65) and steady < math.rad(100), "carves 65-100 degrees a second at speed (like the reference)")
	-- it rolls into the turn instead of snapping to it
	check(early < math.rad(3), "turn-in builds up (under 3 degrees in the first 0.1 s)")
	check(kmh(state) > before - 6, "a hard carve only scrubs a little speed")
	check(state.Lean < 0, "leans right into a right turn")
	check(maxLean <= Config.Turning.MaxLean + 1e-3 and maxLean > math.rad(20), "leans 20-34 degrees")
	local look = BikePhysics.Heading(state.Yaw)
	check(look.X > 0, "heading swung toward +X (right of -Z)")
end

print("== drift: lock the rear, swing the tail, pay on the way out")
do
	local spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.TURBO, flat, 8, input({ Throttle = 1 }), atMost(33))
	local before = kmh(state)
	local maxSlip, started, ended = 0, false, nil
	local yaw0, travel0 = state.Yaw, state.TravelYaw
	local events = ride(spec, state, Modes.Defaults.TURBO, flat, 1.2, input({ Drift = true, Steer = 1 }), function(_, s)
		maxSlip = math.max(maxSlip, math.abs(s.Slip))
	end)
	for _, e in events do
		if e.Kind == "DriftStart" then
			started = true
		end
	end
	local during = kmh(state)
	local swung = yaw0 - state.Yaw
	local bent = travel0 - state.TravelYaw
	events = ride(spec, state, Modes.Defaults.TURBO, flat, 1.5, input({ Throttle = 1 }))
	for _, e in events do
		if e.Kind == "DriftEnd" then
			ended = e
		end
	end
	print(string.format("  %.0f -> %.0f km/h, heading swung %.0f deg, line bent %.0f deg, max slip %.0f deg", before, during, math.deg(swung), math.deg(bent), math.deg(maxSlip)))
	check(started, "a drift starts")
	check(maxSlip > 0.3 and maxSlip < Config.Drift.HoldSlip, "the tail swings out without spinning")
	check(swung > bent, "the heading turns faster than the line (that's the slide)")
	check(during < before - 2, "sliding scrubs speed")
	check(ended ~= nil and (ended.Value or 0) > 0.3, "releasing ends the drift with its time")
	check(math.abs(state.Slip) < 0.1, "the line snaps back to the heading")
	-- holding full lock, flat out or at a starter bike's pace: a steady slide that scrubs speed, never
	-- a spin-out
	for _, run in { { Id = "hornet_6", Kmh = 200 }, { Id = "flit_mini", Kmh = 40 }, { Id = "deathrider", Kmh = 200 } } do
		spec, state = spawn(run.Id)
		ride(spec, state, Modes.Defaults.TURBO, flat, 8, input({ Throttle = 1 }), atMost(run.Kmh))
		local entry = kmh(state)
		local crashed, held = false, 0
		ride(spec, state, Modes.Defaults.TURBO, flat, 4, input({ Drift = true, Steer = 1, Throttle = 1 }), function(_, s)
			crashed = crashed or s.Crash > 0
			held = math.max(held, math.abs(s.Slip))
		end)
		print(string.format("  %s held full lock from %.0f km/h: slip up to %.0f deg, down to %.0f km/h", run.Id, entry, math.deg(held), kmh(state)))
		check(not crashed and held < Config.Drift.HoldSlip and held > 0.5, run.Id .. ": holding full lock keeps a big slide without spinning out")
		check(kmh(state) < entry - 10 or kmh(state) < 5, run.Id .. ": a long slide scrubs speed off, even on the gas")
	end
	-- letting go of R ends the drift (and pays it) even while still carving at full lock
	spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.TURBO, flat, 8, input({ Throttle = 1 }), atMost(50))
	ride(spec, state, Modes.Defaults.TURBO, flat, 1, input({ Drift = true, Steer = 1, Throttle = 1 }))
	local ends = 0
	for _, e in ride(spec, state, Modes.Defaults.TURBO, flat, 3, input({ Steer = 1, Throttle = 1 })) do
		if e.Kind == "DriftEnd" then
			ends += 1
		end
	end
	check(ends == 1 and not state.DriftActive, "releasing R ends the drift at once, even still steering")
	-- holding R + full lock + gas until it slows: it skids to a stop, one drift, the motor off
	spec, state = spawn("deathrider")
	ride(spec, state, Modes.Defaults.TURBO, flat, 8, input({ Throttle = 1 }), atMost(60))
	local before = state.Battery
	local starts, finished = 0, 0
	for _, e in ride(spec, state, Modes.Defaults.TURBO, flat, 20, input({ Drift = true, Steer = 1, Throttle = 1 })) do
		if e.Kind == "DriftStart" then
			starts += 1
		elseif e.Kind == "DriftEnd" then
			finished += 1
		end
	end
	print(string.format("  R + lock + gas for 20 s: %d drift(s), %.1f km/h, %.1f Wh used", starts, kmh(state), before - state.Battery))
	check(starts == 1 and finished == 1, "a held lock is one drift, not a loop of them")
	check(kmh(state) < 1, "a locked rear skids the bike to a stop")
	-- (only the motor winding down after the lock: ~12 Wh, against ~490 Wh when it kept pulling)
	check(before - state.Battery < 20, "a locked rear doesn't burn the battery")
	-- too slow to drift
	spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.OFF, flat, 1, input({ Throttle = 0.3 }))
	ride(spec, state, Modes.Defaults.OFF, flat, 1, input({ Drift = true, Steer = 1 }))
	check(math.abs(state.Slip) < 0.05, "no drifting at walking pace")
end

print("== wheelie: hold the key, stay up, loop out if ignored")
do
	for _, id in { "flit_mini", "hornet_6", "storm_x", "scout_e" } do
		local spec, state = spawn(id)
		ride(spec, state, Modes.Defaults.SPORT, flat, 6, input({ Throttle = 1 }))
		local startKmh = kmh(state)
		local events = ride(spec, state, Modes.Defaults.SPORT, flat, 40, input({ Throttle = 0.6, Wheelie = true }))
		local started, loopedAt = false, nil
		for _, e in events do
			if e.Kind == "WheelieStart" then
				started = true
			elseif e.Kind == "Crash" and not loopedAt then
				loopedAt = e.Time
			end
		end
		print(string.format("  %-9s from %2.0f km/h: up=%s, loops out after %s s with no corrections", id, startKmh, tostring(started), if loopedAt then string.format("%.1f", loopedAt) else ">40"))
		check(started, id .. " pops a wheelie")
		-- holding the key and the throttle isn't enough: it tips past the balance point and loops out
		check(loopedAt ~= nil and loopedAt > 1 and loopedAt < 6, id .. " loops out within 1-6 s with the key alone (it has to be balanced)")
	end
	-- With corrections (tap the brake when high, the throttle when low) it can go on and on
	local spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.SPORT, flat, 6, input({ Throttle = 1 }))
	local inp = input({ Throttle = 0.6, Wheelie = true })
	local crashed = false
	local longest = 0
	ride(spec, state, Modes.Defaults.SPORT, flat, 60, inp, function(_, s, events)
		inp.Brake = if s.Wheelie > 0.72 then 1 else 0
		inp.Throttle = if s.Wheelie < 0.55 then 1 else 0
		longest = math.max(longest, s.WheelieTime)
		for _, e in events do
			if e.Kind == "Crash" then
				crashed = true
			end
		end
	end)
	print(string.format("  corrected wheelie: %.1f s, crashed=%s", longest, tostring(crashed)))
	check(not crashed and longest > 55, "a corrected wheelie lasts a minute")
	-- Releasing the key brings the front down
	inp.Wheelie = false
	inp.Brake = 0
	local ended = false
	ride(spec, state, Modes.Defaults.SPORT, flat, 3, inp, function(_, _, events)
		for _, e in events do
			if e.Kind == "WheelieEnd" then
				ended = true
			end
		end
	end)
	check(ended and state.Wheelie == 0, "letting go ends the wheelie")
end

print("== jump off a kicker")
do
	-- 21 degree kicker, 5 studs (1.4 m) tall, starting 150 studs ahead
	local world = makeWorld({ RampStart = -150, RampLength = 13, RampHeight = 5 })
	local spec, state = spawn("hornet_6")
	local land, takeoff = nil, nil
	local inp = input({ Throttle = 1 })
	ride(spec, state, Modes.Defaults.TURBO, world, 12, inp, function(_, s, events)
		for _, e in events do
			if e.Kind == "Takeoff" and not takeoff then
				takeoff = { Kmh = kmh(s), Y = s.Position.Y }
			elseif e.Kind == "Land" and not land then
				land = e
			end
		end
	end)
	if takeoff then
		print(string.format("  takeoff at %.0f km/h from %.1f studs", takeoff.Kmh, takeoff.Y))
	end
	if land then
		print(string.format("  landed after %.2f s air (%s)", land.Value, land.Text))
	end
	check(takeoff ~= nil, "launches off the lip")
	check(land ~= nil and land.Value > 0.6, "gets over 0.6 s of air")
	check(land ~= nil and land.Text ~= "Crash", "lands it with no input")

	-- Backflip: drop in fast (like the jump park's mega ramp roll-in) and pull back off a steep kicker
	local big = makeWorld({ RampStart = -60, RampLength = 12, RampHeight = 7 })
	spec, state = spawn("storm_xr")
	state.Speed = 15
	local flips = 0
	local crashedFlip = false
	local inp2 = input({ Throttle = 1 })
	local airborneFor = 0
	ride(spec, state, Modes.Defaults.TURBO, big, 10, inp2, function(_, s, events)
		if not s.Grounded then
			airborneFor += DT
			-- pull back until nearly round, then let it settle
			inp2.Wheelie = s.AirPitch < math.pi * 2 - 1.4
		else
			inp2.Wheelie = false
		end
		for _, e in events do
			if e.Kind == "Flip" then
				flips += e.Value
			elseif e.Kind == "Crash" then
				crashedFlip = true
			end
		end
	end)
	print(string.format("  big kicker: %.2f s air, flips %d, crashed %s", airborneFor, flips, tostring(crashedFlip)))
	check(flips == 1 and not crashedFlip, "a full suspension bike lands a backflip off the big kicker")
end

print("== air tricks, barspin, stoppie")
do
	local world = makeWorld({ RampStart = -150, RampLength = 13, RampHeight = 5 })
	-- hold Z for the first 0.45 s of air, then tap Y for a barspin
	local spec, state = spawn("hornet_6")
	local tricks, landed = {}, nil
	local airClock = 0
	local inp = input({ Throttle = 1 })
	ride(spec, state, Modes.Defaults.TURBO, world, 12, inp, function(_, s, events)
		if not s.Grounded then
			airClock += 1 / 60
			inp.Trick = if airClock < 0.45 then "Superman" else nil
			inp.Barspin = airClock > 0.46 and airClock < 0.52
		else
			inp.Trick = nil
			inp.Barspin = false
		end
		for _, e in events do
			if e.Kind == "AirTrick" then
				table.insert(tricks, e.Text)
			elseif e.Kind == "Land" and not landed and airClock > 0 then
				landed = e
			end
		end
	end)
	print(string.format("  tricks: %s, landed %s", table.concat(tricks, ", "), if landed then tostring(landed.Text) else "?"))
	check(table.find(tricks, "Superman") ~= nil, "holding Z in the air lands a superman")
	check(table.find(tricks, "Barspin") ~= nil, "tapping Y spins the bars")
	check(landed ~= nil and landed.Text ~= "Crash", "tucked in time: clean landing")
	-- every trick, held all the way to the ground: counted, and tucked in time to land
	for _, name in { "Superman", "CanCan", "NacNac", "KneeKnocker", "NoFooter" } do
		spec, state = spawn("hornet_6")
		local bailed, counted = false, false
		local hold = input({ Throttle = 1 })
		ride(spec, state, Modes.Defaults.TURBO, world, 12, hold, function(_, s, events)
			hold.Trick = if s.Grounded then nil else name
			for _, e in events do
				if e.Kind == "Crash" then
					bailed = true
				elseif e.Kind == "AirTrick" and e.Text == name then
					counted = true
				end
			end
		end)
		check(counted and not bailed, name .. ": held to the ground, it counts and tucks in to land")
	end
	-- a gap jump onto a deck higher than the gap's floor (the mega ramp): a trick held to the ground
	-- still tucks in time, because the tuck looks at where the wheels will land, not straight down
	do
		local gap = makeWorld({ RampStart = -150, RampLength = 16, RampHeight = 9, DeckZ = -190, DeckHeight = 6 })
		spec, state = spawn("hornet_6")
		local bailed, landedOnDeck = false, false
		local held = input({ Throttle = 1 })
		local cap = atMost(44)
		ride(spec, state, Modes.Defaults.TURBO, gap, 8, held, function(t, s, events)
			if s.Grounded then
				cap(t, s)
			end
			held.Trick = if s.Grounded then nil else "Superman"
			for _, e in events do
				if e.Kind == "Crash" then
					bailed = true
					print(string.format("  gap jump: crash (%s) at z=%.1f y=%.1f", tostring(e.Text), s.Position.Z, s.Position.Y))
				elseif e.Kind == "Land" then
					print(string.format("  gap jump: landed (%s, %.2f s air) at z=%.1f y=%.1f, trick ext %.2f", tostring(e.Text), e.Value or 0, s.Position.Z, s.Position.Y, s.TrickExt))
					landedOnDeck = landedOnDeck or s.Position.Y > 5
				end
			end
		end)
		check(landedOnDeck and not bailed, "gap jump onto a raised deck with a trick held: tucks in time, no bail")
	end
	-- the exact bad spot: falling, the middle of the bike over the gap's floor, the front wheel just
	-- above the deck, the trick fully out. The tuck has to see the deck, not the floor.
	do
		local gap = makeWorld({ DeckZ = -190, DeckHeight = 6 })
		spec, state = spawn("hornet_6")
		local half = spec.Wheelbase / 2
		state.Grounded = false
		state.Position = Vector3.new(0, 8.5, -190 + half * 0.6) -- front wheel over the deck, middle over the gap
		state.VerticalSpeed = -3
		state.AirVelocity = Vector3.new(0, 0, -1) -- creeping forward: the middle stays over the gap
		state.AirTime = 1
		state.TrickName = "Superman"
		state.TrickExt = 1
		local bailed = false
		ride(spec, state, Modes.Defaults.TURBO, gap, 1.5, input({ Trick = "Superman" }), function(_, _, events)
			for _, e in events do
				if e.Kind == "Crash" then
					bailed = true
				end
			end
		end)
		check(not bailed, "falling onto a deck that's under the front wheel only: the trick still tucks in time")
	end
	-- a barspin pressed on the way up a tap hop doesn't start if it can't finish before touchdown
	for press = 2, 14, 4 do
		spec, state = spawn("hornet_6")
		ride(spec, state, Modes.Defaults.TURBO, flat, 3, input({ Throttle = 1 }), atMost(30))
		local hopInput = input({ Throttle = 1, Hop = true })
		BikePhysics.Step(state, spec, Modes.Defaults.TURBO, hopInput, flat, DT)
		hopInput.Hop = false
		local frame, crashedSpin = 0, false
		ride(spec, state, Modes.Defaults.TURBO, flat, 1.5, hopInput, function(_, s, events)
			frame += 1
			hopInput.Barspin = frame == press
			for _, e in events do
				if e.Kind == "Crash" then
					crashedSpin = true
				end
			end
		end)
		check(not crashedSpin, string.format("a barspin pressed %d frames into a tap hop never bails", press))
	end
	-- stoppie: brake + wheelie key at speed
	spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.TURBO, flat, 6, input({ Throttle = 1 }), atMost(33))
	local stoppie, maxLift = nil, 0
	ride(spec, state, Modes.Defaults.TURBO, flat, 3, input({ Brake = 0.7, Wheelie = true }), function(_, s, events)
		maxLift = math.max(maxLift, s.Stoppie)
		for _, e in events do
			if e.Kind == "StoppieEnd" then
				stoppie = e
			end
		end
	end)
	print(string.format("  stoppie lifted %.0f deg, held %.1f s", math.deg(maxLift), if stoppie then stoppie.Value or 0 else 0))
	check(maxLift > 0.2, "brake + wheelie key lifts the rear")
	check(stoppie ~= nil, "the stoppie ends with its time")
end

print("== loops and the foam pit")
do
	local function loopWorld(radius: number)
		local world = makeWorld({})
		local entry = CFrame.lookAt(Vector3.new(0, 0, -80), Vector3.new(0, 0, -81))
		local used = false
		world.Loop = function(position, dir)
			if not used and math.abs(position.Z + 80) < 2 and dir:Dot(entry.LookVector) > 0.8 then
				used = true
				return { Entry = entry, Radius = radius, Shift = 10 }
			end
			return nil
		end
		return world
	end
	local spec, state = spawn("storm_x")
	local loops, fails = 0, 0
	local events = ride(spec, state, Modes.Defaults.TURBO, loopWorld(16), 10, input({ Throttle = 1 }))
	for _, e in events do
		if e.Kind == "Loop" then
			loops += 1
		elseif e.Kind == "LoopFail" then
			fails += 1
		end
	end
	print(string.format("  e-moto: %d loop(s), %d fall(s), now at x=%.1f", loops, fails, state.Position.X))
	check(loops == 1 and fails == 0, "a fast e-moto goes all the way round")
	check(math.abs(state.Position.X - 10) < 0.5, "it comes out beside the entry")
	-- too slow: falls off near the top
	spec, state = spawn("flit_mini")
	local slow = loopWorld(30)
	fails = 0
	events = ride(spec, state, Modes.Defaults.ECO, slow, 18, input({ Throttle = 0.4 }))
	local kinds = {}
	for _, e in events do
		if e.Kind == "LoopFail" then
			fails += 1
		end
		if e.Kind ~= "Impact" then
			table.insert(kinds, e.Kind)
		end
	end
	check(fails == 1, "too slow for a big loop: you slide back out")
	check(table.find(kinds, "Crash") == nil, "stalling in a loop never crashes you")
	-- foam pit: a flat-out bad landing is fine
	local foam = makeWorld({ RampStart = -150, RampLength = 13, RampHeight = 5 })
	local down = foam.Down
	foam.Down = function(origin, length)
		local hit = down(origin, length)
		if hit and origin.Z < -170 then
			hit.Kind = "Foam"
		end
		return hit
	end
	spec, state = spawn("hornet_6")
	local crashed, foamLanding = false, false
	local inp = input({ Throttle = 1 })
	ride(spec, state, Modes.Defaults.TURBO, foam, 12, inp, function(_, s, evs)
		inp.Trick = if s.Grounded then nil else "Superman"
		for _, e in evs do
			if e.Kind == "Crash" then
				crashed = true
			elseif e.Kind == "Land" and e.Text == "Foam" then
				foamLanding = true
			end
		end
	end)
	check(foamLanding and not crashed, "the foam pit catches a landing you'd normally bail")
end

print("== quarter pipe: up the face, turn at the top, ride back down")
do
	-- the Loop Park halfpipe: radius 16 design studs (20 in game), 72 degrees
	local world = makeWorld({ QuarterStart = -120, QuarterRadius = 20, QuarterAngle = math.rad(72) })
	local spec, state = spawn("hornet_6")
	local crashed, fakie, landed, peak = false, false, false, 0
	local inp = input({ Throttle = 1 })
	ride(spec, state, Modes.Defaults.TURBO, world, 9, inp, function(_, s, events)
		if s.Position.Z < -110 then
			inp.Throttle = 0
		end
		peak = math.max(peak, s.Position.Y)
		for _, e in events do
			if e.Kind == "Crash" then
				crashed = true
			elseif e.Kind == "Fakie" then
				fakie = true
			elseif e.Kind == "Land" and fakie then
				landed = true
			end
		end
	end)
	print(string.format("  peak %.1f studs, fakie %s, landed %s, crashed %s, now %.0f km/h heading %s", peak, tostring(fakie), tostring(landed), tostring(crashed), kmh(state), if BikePhysics.Heading(state.Yaw).Z > 0 then "back out" else "in"))
	check(peak > 20 * (1 - math.cos(Config.Physics.MaxRidePitch)), "rides up the face past where it gets too steep")
	check(peak < 60, "isn't fired into the sky")
	check(fakie and landed and not crashed, "turns at the top and lands back on the face without a bail")
	check(BikePhysics.Heading(state.Yaw).Z > 0.5, "rides back out facing the way it came")
end

print("== suspension: sag, kerbs, drops, dive, squat, landings, grass, wheelies, loops, hitches")
do
	local function comp(s: any): (number, number)
		return BikePhysics.Compression(s)
	end
	local function stationary(spec: any, state: any)
		ride(spec, state, Modes.Defaults.TURBO, flat, 3, input({}))
	end
	-- 1. at rest it settles at ~30% sag and stays still
	local spec, state = spawn("hornet_6")
	stationary(spec, state)
	local cf, cr = comp(state)
	print(string.format("  at rest: front %.0f mm of %.0f, rear %.0f mm of %.0f", cf * 1000, spec.FrontTravel * 1000, cr * 1000, spec.RearTravel * 1000))
	check(math.abs(cf - 0.3 * spec.FrontTravel) < 0.012 and math.abs(cr - 0.3 * spec.RearTravel) < 0.012, "at rest each end sits at ~30% sag")
	check(math.abs((state.Sus :: any).EV) < 0.01, "and the chassis is still")

	-- 1b. riding along, both drawn wheels sit on the road (not in it, not above it)
	do
		local sp, st = spawn("hornet_6")
		ride(sp, st, Modes.Defaults.TURBO, flat, 6, input({ Throttle = 1 }), atMost(30))
		local VIS = Config.VISUAL_STUDS_PER_METER
		local cf = BikePhysics.GetCFrame(st, sp)
		local df, dr = BikePhysics.DrawnCompression(st)
		local front = cf:PointToWorldSpace(Vector3.new(0, sp.WheelRadius + df * VIS, -sp.Wheelbase / 2))
		local rear = cf:PointToWorldSpace(Vector3.new(0, sp.RearWheelRadius + dr * VIS, sp.Wheelbase / 2))
		local sinkF = st.Position.Y + sp.WheelRadius - front.Y
		local sinkR = st.Position.Y + sp.RearWheelRadius - rear.Y
		print(string.format("  riding: front wheel %.2f, rear wheel %.2f studs into the road", sinkF, sinkR))
		check(math.abs(sinkF) < 0.05 and math.abs(sinkR) < 0.05, "riding along, both wheels sit on the road")
	end

	-- 1c. a bike drawn 1.6x to fit a big rider: its wheels sit on the road too
	do
		local sp, st = spawn("hornet_6")
		sp = BikeStats.Scaled(sp, 1.6)
		ride(sp, st, Modes.Defaults.TURBO, flat, 6, input({ Throttle = 1 }), atMost(30))
		local VIS = Config.VISUAL_STUDS_PER_METER
		local cf = BikePhysics.GetCFrame(st, sp)
		local df, dr = BikePhysics.DrawnCompression(st)
		local front = cf:PointToWorldSpace(Vector3.new(0, sp.WheelRadius + df * VIS, -sp.Wheelbase / 2))
		local rear = cf:PointToWorldSpace(Vector3.new(0, sp.RearWheelRadius + dr * VIS, sp.Wheelbase / 2))
		local worst = math.max(math.abs(st.Position.Y + sp.WheelRadius - front.Y), math.abs(st.Position.Y + sp.RearWheelRadius - rear.Y))
		print(string.format("  1.6x bike: wheels %.2f studs off the road", worst))
		check(worst < 0.05, "a bike scaled to fit a big rider keeps its wheels on the road")
	end

	-- 2. a kerb UP at 20 km/h: the front fork takes the hit first, then the rear, the chassis pitches
	-- up then down, no takeoff or landing, and it ends up on top
	local kerb = makeWorld({ StepZ = -120, StepHeight = 0.625 })
	spec, state = spawn("hornet_6")
	local peakF, peakR, peakFAt, peakRAt, maxTilt, minTilt = 0, 0, 0, 0, 0, 0
	local airEvents = 0
	local upInput = input({ Throttle = 1 })
	local upRun = runUp(20, -100, upInput)
	local events = ride(spec, state, Modes.Defaults.TURBO, kerb, 9, upInput, function(t, s)
		upRun(t, s)
		if s.Position.Z > -110 then
			return -- the launch squat isn't the kerb
		end
		local f, r = comp(s)
		if f > peakF then
			peakF, peakFAt = f, t
		end
		if r > peakR then
			peakR, peakRAt = r, t
		end
		local tilt = BikePhysics.ChassisPitch(s)
		maxTilt = math.max(maxTilt, tilt)
		minTilt = math.min(minTilt, tilt)
	end)
	for _, e in events do
		if e.Kind == "Takeoff" or e.Kind == "Land" then
			airEvents += 1
		end
	end
	print(string.format("  kerb up: front peak %.0f mm at %.2f s, rear peak %.0f mm at %.2f s, pitch %+.1f / %+.1f deg", peakF * 1000, peakFAt, peakR * 1000, peakRAt, math.deg(maxTilt), math.deg(minTilt)))
	check(peakF > 0.3 * spec.FrontTravel + 0.03 and peakR > 0.3 * spec.RearTravel + 0.03, "a kerb compresses both ends well past sag")
	check(peakFAt < peakRAt, "the front takes the kerb before the rear")
	check(maxTilt > math.rad(1.5) and minTilt < -math.rad(1), "the chassis pitches up over the kerb, then down")
	check(airEvents == 0, "riding up a kerb is no jump")
	check(math.abs(state.Position.Y - 0.625) < 0.05, "and it ends up on top")

	-- 3. a kerb DOWN: the wheels drop and the chassis falls onto its springs; no jump, no landing
	local drop = makeWorld({ StepZ = -120, StepHeight = -0.625 })
	spec, state = spawn("hornet_6")
	local lowF, highF = 1, 0
	airEvents = 0
	local downInput = input({ Throttle = 1 })
	local downRun = runUp(20, -100, downInput)
	events = ride(spec, state, Modes.Defaults.TURBO, drop, 9, downInput, function(t, s)
		downRun(t, s)
		if s.Position.Z < -110 then
			local f = comp(s)
			lowF = math.min(lowF, f)
			highF = math.max(highF, f)
		end
	end)
	for _, e in events do
		if e.Kind == "Takeoff" or e.Kind == "Land" then
			airEvents += 1
		end
	end
	print(string.format("  kerb down: front from %.0f to %.0f mm", lowF * 1000, highF * 1000))
	check(airEvents == 0, "a kerb drop is no jump: no takeoff, no landing (no fake shake or dust)")
	check(lowF < 0.3 * spec.FrontTravel - 0.02 and highF > 0.3 * spec.FrontTravel + 0.02, "the fork extends off the edge, then compresses as the bike lands on it")

	-- 4. braking dives the front, accelerating squats the rear
	spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.TURBO, flat, 8, input({ Throttle = 1 }), atMost(45))
	local restF, restR = comp(state)
	local diveF, diveR = 0, 1
	ride(spec, state, Modes.Defaults.TURBO, flat, 0.6, input({ Brake = 1 }), function(_, s)
		local f, r = comp(s)
		diveF = math.max(diveF, f)
		diveR = math.min(diveR, r)
	end)
	print(string.format("  braking: front %.0f -> %.0f mm, rear %.0f -> %.0f mm", restF * 1000, diveF * 1000, restR * 1000, diveR * 1000))
	check(diveF > restF + 0.02 and diveR < restR - 0.01, "hard braking dives the front and lifts the rear")
	spec, state = spawn("hornet_6")
	stationary(spec, state)
	restF, restR = comp(state)
	local squatR, squatF = 0, 1
	ride(spec, state, Modes.Defaults.TURBO, flat, 0.5, input({ Throttle = 1 }), function(_, s)
		local f, r = comp(s)
		squatR = math.max(squatR, r)
		squatF = math.min(squatF, f)
	end)
	print(string.format("  launch: rear %.0f -> %.0f mm, front %.0f -> %.0f mm", restR * 1000, squatR * 1000, restF * 1000, squatF * 1000))
	check(squatR > restR + 0.01 and squatF < restF - 0.005, "full throttle squats the rear and lightens the front")

	-- 5. a big jump's landing sinks deep into the travel but the bump stops hold
	local kicker = makeWorld({ RampStart = -150, RampLength = 13, RampHeight = 5 })
	spec, state = spawn("storm_xr")
	local deepest, landed = 0, false
	ride(spec, state, Modes.Defaults.TURBO, kicker, 10, input({ Throttle = 1 }), function(_, s, evs)
		for _, e in evs do
			if e.Kind == "Land" then
				landed = true
			end
		end
		if landed then
			local f, r = comp(s)
			deepest = math.max(deepest, f / spec.FrontTravel, r / spec.RearTravel)
		end
	end)
	print(string.format("  big landing: deepest %.0f%% of travel", deepest * 100))
	check(landed and deepest > 0.6, "a big landing uses most of the travel")
	check(deepest < 1.15, "and the bump stops hold it")

	-- 6. grass is bumpy, tarmac isn't: the wheels work hard on grass
	local function jiggle(world: any): number
		local sp, st = spawn("hornet_6")
		ride(sp, st, Modes.Defaults.TURBO, world, 4, input({ Throttle = 1 }), atMost(30))
		local samples, sum, sumSq = 0, 0, 0
		ride(sp, st, Modes.Defaults.TURBO, world, 4, input({ Throttle = 1 }), function(t, s)
			atMost(30)(t, s)
			local f = comp(s)
			samples += 1
			sum += f
			sumSq += f * f
		end)
		local mean = sum / samples
		return math.sqrt(math.max(0, sumSq / samples - mean * mean))
	end
	local roadJiggle, grassJiggle = jiggle(flat), jiggle(makeWorld({ Grass = true }))
	print(string.format("  fork movement at 30 km/h: road %.1f mm, grass %.1f mm (std dev)", roadJiggle * 1000, grassJiggle * 1000))
	check(grassJiggle > 4 * roadJiggle and grassJiggle > 0.004, "on grass the suspension works over the bumps; on the road it's calm")

	-- 7. a wheelie: the fork tops out, the rear takes all the weight and sinks past its static sag
	spec, state = spawn("hornet_6")
	stationary(spec, state)
	restF, restR = comp(state)
	ride(spec, state, Modes.Defaults.TURBO, flat, 6, input({ Throttle = 1 }), atMost(30))
	ride(spec, state, Modes.Defaults.TURBO, flat, 1.5, input({ Throttle = 1, Wheelie = true }), atMost(30))
	local wf, wr = comp(state)
	print(string.format("  wheelie (%.0f deg): front %.0f mm, rear %.0f mm", math.deg(state.Wheelie), wf * 1000, wr * 1000))
	check(state.Wheelie > 0.2 and wf < 0.02 and wr > restR + 0.01, "in a wheelie the fork tops out and the rear sinks")
	-- the drawn rear wheel stays on the road: its axle a wheel radius up (less the tyre's squash)
	do
		local VIS = Config.VISUAL_STUDS_PER_METER
		local cf = BikePhysics.GetCFrame(state, spec)
		local _, drawnR = BikePhysics.DrawnCompression(state)
		local axle = cf:PointToWorldSpace(Vector3.new(0, spec.RearWheelRadius + drawnR * VIS, spec.Wheelbase / 2))
		local sink = (state.Position.Y + spec.RearWheelRadius) - axle.Y
		print(string.format("  wheelie rear wheel: %.2f studs into the road", sink))
		check(math.abs(sink) < 0.05, "in a wheelie the rear wheel stays on the road, not in it")
	end

	-- 8. a loop's g-force loads the suspension, within its travel
	do
		local loopWorld = makeWorld({})
		local entry = CFrame.lookAt(Vector3.new(0, 0, -80), Vector3.new(0, 0, -81))
		local used = false
		loopWorld.Loop = function(position, d)
			if not used and math.abs(position.Z + 80) < 2 and d:Dot(entry.LookVector) > 0.8 then
				used = true
				return { Entry = entry, Radius = 16, Shift = 10 }
			end
			return nil
		end
		spec, state = spawn("storm_x")
		local inLoop, maxIn = 0, 0
		ride(spec, state, Modes.Defaults.TURBO, loopWorld, 10, input({ Throttle = 1 }), function(_, s)
			if s.Loop then
				local f, r = comp(s)
				inLoop += 1
				maxIn = math.max(maxIn, f / spec.FrontTravel, r / spec.RearTravel)
			end
		end)
		print(string.format("  loop: deepest %.0f%% of travel", maxIn * 100))
		check(inLoop > 0 and maxIn > 0.4 and maxIn < 1.15, "a loop's g-force compresses the suspension, within its travel")
	end

	-- 9. frame hitches (0.1 s steps) over grass and kerbs never blow it up
	do
		local rough = makeWorld({ Grass = true, StepZ = -60, StepHeight = 0.625 })
		local sp, st = spawn("deathrider")
		local ok = true
		for _ = 1, 60 do
			BikePhysics.Step(st, sp, Modes.Defaults.TURBO, input({ Throttle = 1 }), rough, 0.1)
			local f, r = comp(st)
			if f ~= f or r ~= r or f < -0.06 or r < -0.06 or f > sp.FrontTravel + 0.08 or r > sp.RearTravel + 0.08 then
				ok = false
			end
		end
		check(ok, "0.1 s frame hitches over grass and a kerb: the suspension stays sane")
	end
	-- 10. every bike settles (no bike's numbers make it oscillate or sink)
	for _, bike in Bikes.List do
		local sp, st = spawn(bike.Id)
		stationary(sp, st)
		local f, r = comp(st)
		check(math.abs(f - 0.3 * sp.FrontTravel) < 0.015 and math.abs(r - 0.3 * sp.RearTravel) < 0.015 and math.abs((st.Sus :: any).EV) < 0.01, bike.Id .. " settles at its sag")
	end
end

print("== walls")
do
	local world = makeWorld({ WallZ = -150 })
	local spec, state = spawn("storm_x")
	local events = ride(spec, state, Modes.Defaults.TURBO, world, 8, input({ Throttle = 1 }))
	local crashed = false
	for _, e in events do
		if e.Kind == "Crash" then
			crashed = true
		end
	end
	check(crashed, "full speed into a wall bails")
	check(state.Position.Z > -150, "doesn't go through the wall")

	spec, state = spawn("flit_mini")
	local slowEvents = ride(spec, state, Modes.Defaults.ECO, world, 6, input({ Throttle = 0.3 }))
	ride(spec, state, Modes.Defaults.ECO, world, 30, input({ Throttle = 0.15 }))
	crashed = false
	for _, e in slowEvents do
		if e.Kind == "Crash" then
			crashed = true
		end
	end
	print(string.format("  slow roll ends at z=%.2f, speed %.1f km/h", state.Position.Z, kmh(state)))
	check(state.Position.Z > -150, "a slow bump stops at the wall")
end

print("== little bumps don't bail")
do
	-- clipping the side of a ramp, a loop or a hillside (World reports it as "Slope") never stops or bails you
	local edge = makeWorld({ WallZ = -150, WallKind = "Slope" })
	local spec0, state0 = spawn("storm_x")
	local evs = ride(spec0, state0, Modes.Defaults.TURBO, edge, 8, input({ Throttle = 1 }))
	local bailed = false
	for _, e in evs do
		if e.Kind == "Crash" then
			bailed = true
		end
	end
	check(not bailed and state0.Position.Z < -160, "the edge of a ramp or hill is no wall: no bail, no stop")
	local function crashes(events): boolean
		for _, e in events do
			if e.Kind == "Crash" then
				return true
			end
		end
		return false
	end
	-- rolling off a kerb mid-wheelie
	local kerb = makeWorld({ DropZ = -120, DropHeight = 0.6 })
	local spec, state = spawn("hornet_6")
	-- (balanced like a rider would: throttle when low, off and a dab of brake when high)
	local kinp = input({ Throttle = 1, Wheelie = true })
	local events = ride(spec, state, Modes.Defaults.TOUR, kerb, 9, kinp, function(_, s)
		kinp.Throttle = if s.Wheelie < 0.55 then 1 else 0
		kinp.Brake = if s.Wheelie > 0.72 then 1 else 0
	end)
	check(not crashes(events), "a wheelie off a kerb carries on")
	-- off a kerb mid-drift
	spec, state = spawn("hornet_6")
	local driftKerb = makeWorld({ DropZ = -60, DropHeight = 0.6 })
	ride(spec, state, Modes.Defaults.TURBO, driftKerb, 4, input({ Throttle = 1 }))
	events = ride(spec, state, Modes.Defaults.TURBO, driftKerb, 1.5, input({ Drift = true, Steer = 0.6 }))
	check(not crashes(events), "drifting off a kerb doesn't bail")
	-- a bin or bench: a bump at a crawl stops you, at full speed it throws you over the bars
	local bin = makeWorld({ WallZ = -150, WallKind = "Prop" })
	spec, state = spawn("storm_x")
	events = ride(spec, state, Modes.Defaults.TURBO, bin, 8, input({ Throttle = 1 }))
	check(crashes(events), "hitting a bench or bin at full speed throws you")
	local nearBin = makeWorld({ WallZ = -12, WallKind = "Prop" })
	spec, state = spawn("storm_x")
	events = ride(spec, state, Modes.Defaults.ECO, nearBin, 6, input({ Throttle = 0.25 }))
	check(not crashes(events), "rolling into a bench at a crawl just stops you")
end

print("== bunny hop")
do
	local spec, state = spawn("hornet_6")
	ride(spec, state, Modes.Defaults.TOUR, flat, 4, input({ Throttle = 1 }))
	local inp = input({ Throttle = 1, Hop = true })
	ride(spec, state, Modes.Defaults.TOUR, flat, 0.5, inp)
	inp.Hop = false
	local air = 0
	local landed = false
	ride(spec, state, Modes.Defaults.TOUR, flat, 2, inp, function(_, _, events)
		for _, e in events do
			if e.Kind == "Land" then
				air = e.Value
				landed = e.Text ~= "Crash"
			end
		end
	end)
	print(string.format("  hop air time %.2f s", air))
	check(air > 0.4 and landed, "a charged hop gives ~0.5 s of air and lands")
end

print("== grass slows road tyres more than knobblies")
do
	local grass = makeWorld({ Grass = true })
	local spec, state = spawn("flit_s")
	ride(spec, state, Modes.Defaults.TURBO, grass, 30, input({ Throttle = 1 }))
	local road = kmh(state)
	spec, state = spawn("flit_s", { Tires = 2 })
	ride(spec, state, Modes.Defaults.TURBO, grass, 30, input({ Throttle = 1 }))
	local knobby = kmh(state)
	print(string.format("  speed pedelec on grass: slicks %.1f, knobblies %.1f km/h", road, knobby))
	check(knobby > road, "knobblies are faster on grass")
end

if failures > 0 then
	print(string.format("\n%d check(s) FAILED", failures))
	process.exit(1)
end
print("\nall physics checks passed")
