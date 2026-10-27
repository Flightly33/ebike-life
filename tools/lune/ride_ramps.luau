_G.DEBUGQP = (require("@lune/process").env.DEBUGQP == "1")
--[[
	Rides BikePhysics over the baked city's real ramps, kickers, quarter pipes and hills (map/City.rbxm,
	through tools/lune/geoworld.luau) and reports what goes wrong: crashes, wall hits, take-offs,
	landings and frame-to-frame pitch jumps.

	lune run tools/lune/ride_ramps.luau [bikeId] [kmh,kmh] [filter] [verbose]
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Loader = require("./loader")
local GeoWorld = require("./geoworld")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Bikes = Loader.Require("ReplicatedStorage.Shared.Bikes")
local BikeStats = Loader.Require("ReplicatedStorage.Shared.BikeStats")
local BikePhysics = Loader.Require("ReplicatedStorage.Shared.BikePhysics")
local Modes = Loader.Require("ReplicatedStorage.Shared.Modes")

local bikeId = process.args[1] or "storm_x"
local speeds = {}
for s in string.gmatch(process.args[2] or "30,50,70", "[^,]+") do
	table.insert(speeds, tonumber(s))
end
local filter = process.args[3]
if filter == "-" then
	filter = nil
end
local verbose = process.args[4] == "verbose"
local downRuns = true
-- trace=t0-t1 prints every frame in that window
local traceFrom, traceTo = math.huge, -math.huge
for _, a in process.args do
	local a0, a1 = string.match(a, "^trace=([%d%.]+)%-([%d%.]+)$")
	if a0 then
		traceFrom, traceTo = tonumber(a0) :: number, tonumber(a1) :: number
	end
end

local city = roblox.deserializeModel(fs.readFile("map/City.rbxm"))[1]
local geo = GeoWorld.new(city)
print(string.format("world: %d solid parts", geo.Count))
local world = geo.Physics

-- what to ride: tilted riding faces in the parks and the hills, approached straight up their slope
local targets = {}
for _, d in city:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide and d.CanQuery then
		local look = d.CFrame.LookVector
		local park = d:FindFirstAncestor("JumpPark") or d:FindFirstAncestor("LoopPark") or d:FindFirstAncestor("Hills") or d:FindFirstAncestor("Plaza")
		local first = d.Name ~= "Transition" or (d.Parent and d.Parent:FindFirstChild("Transition") == d)
		local quarterFoot = d.Name == "Transition" and first
		if park and ((look.Y > 0.08 and look.Y < 0.9) or quarterFoot) and first and d.Size.X > 6 then
			local label = park.Name .. "/" .. (if d.Parent then d.Parent.Name else "?") .. "/" .. d.Name
			if not filter or string.find(label, filter, 1, true) then
				table.insert(targets, { Part = d, Label = label })
			end
		end
	end
end
table.sort(targets, function(a, b)
	return a.Label < b.Label
end)
print(string.format("%d ramp faces", #targets))

local bike = Bikes.Get(bikeId)
assert(bike, bikeId)
local spec = BikeStats.Compute(bike, nil)
local DT = 1 / 60

local totals = { Crash = 0, Wall = 0, Runs = 0, Flicker = 0, Snap = 0 }
for _, target in targets do
	local part = target.Part
	local look = part.CFrame.LookVector
	local low = part.CFrame.Position - look * (part.Size.Z / 2)
	local high = part.CFrame.Position + look * (part.Size.Z / 2) + part.CFrame.UpVector * (part.Size.Y / 2)
	local runs = {}
	for _, kmh in speeds do
		if kmh > 0 then
			table.insert(runs, { Kmh = kmh, Down = false })
		end
	end
	if downRuns then
		table.insert(runs, { Kmh = 15, Down = true })
	end
	for _, run in runs do
		local kmh = run.Kmh
		local flat = Vector3.new(look.X, 0, look.Z).Unit
		local start = Vector3.new(low.X, 0, low.Z) - flat * 45
		local fromY = low.Y + 60
		if run.Down then
			-- from just behind the top, facing down the face
			flat = -flat
			start = Vector3.new(high.X, 0, high.Z) - flat * 3
			fromY = high.Y + 3
		end
		local ground = world.Down(Vector3.new(start.X, fromY, start.Z), if run.Down then 8 else 200)
		if not ground then
			continue
		end
		local startPos = Vector3.new(start.X, ground.Position.Y, start.Z)
		local s = BikePhysics.new(spec, CFrame.lookAt(startPos, startPos + flat))
		s.Speed = kmh / 3.6
		local log = {}
		local counts: { [string]: number } = {}
		local maxPitchJump, maxYJump = 0, 0
		local jumpAt = ""
		local lastPitch, lastY = s.Pitch, s.Position.Y
		local t = 0
		local crashed = false
		while t < 9 do
			local inp = BikePhysics.Idle()
			inp.Throttle = if BikePhysics.Kmh(s) < kmh then 1 else 0
			local events = BikePhysics.Step(s, spec, Modes.Defaults.TURBO, inp, world, DT)
			t += DT
			for _, e in events do
				counts[e.Kind] = (counts[e.Kind] or 0) + 1
				if e.Kind == "Crash" then
					crashed = true
					local what = geo.LastSweepPart
					table.insert(log, string.format("t=%.2f CRASH %s (last sweep hit %s) pitch %.0f vy %.1f", t, tostring(e.Text), if what then what:GetFullName() else "-", math.deg(s.Pitch), s.VerticalSpeed))
				elseif e.Kind == "Impact" then
					local what = geo.LastSweepPart
					table.insert(log, string.format("t=%.2f impact %.1f m/s %s on %s", t, e.Value or 0, tostring(e.Text), if what then what:GetFullName() else "-"))
				elseif e.Kind == "Takeoff" or e.Kind == "Land" or e.Kind == "Fakie" then
					table.insert(log, string.format("t=%.2f %s %s %.2f  y=%.1f pitch %.0f kmh %.0f", t, e.Kind, tostring(e.Text or ""), e.Value or 0, s.Position.Y, math.deg(s.Pitch), BikePhysics.Kmh(s)))
				end
			end
			if t >= traceFrom and t <= traceTo then
				local dir = BikePhysics.Heading(s.Yaw)
				local half = spec.Wheelbase / 2
				local f = world.Down(s.Position + dir * half + Vector3.new(0, 8, 0), 20)
				local r = world.Down(s.Position - dir * half + Vector3.new(0, 8, 0), 20)
				print(string.format("   %.3f %s pos (%.1f %.2f %.1f) pitch %.1f  frontY %s (%s) rearY %s (%s) kmh %.0f", t, if s.Grounded then "G" else "A", s.Position.X, s.Position.Y, s.Position.Z, math.deg(s.Pitch), if f then string.format("%.2f", f.Position.Y) else "-", if f then f.Part.Name else "", if r then string.format("%.2f", r.Position.Y) else "-", if r then r.Part.Name else "", BikePhysics.Kmh(s)))
			end
			if s.Grounded and math.abs(s.Pitch - lastPitch) > maxPitchJump then
				maxPitchJump = math.abs(s.Pitch - lastPitch)
				local kinds = {}
				for _, e in events do
					table.insert(kinds, e.Kind)
				end
				jumpAt = string.format("t=%.2f %.0f->%.0f deg [%s] kmh %.0f", t, math.deg(lastPitch), math.deg(s.Pitch), table.concat(kinds, ","), BikePhysics.Kmh(s))
			end
			if s.Grounded then
				maxYJump = math.max(maxYJump, math.abs(s.Position.Y - lastY))
			end
			lastPitch, lastY = s.Pitch, s.Position.Y
			if crashed and t > 0 then
				break
			end
		end
		totals.Runs += 1
		-- glitches: popping off the ground over and over, or the pitch jumping (not on a bail, and
		-- not the first frames, where the test drops the bike on a slope)
		if (counts.Takeoff or 0) >= 6 then
			totals.Flicker += 1
			print("  GLITCH flicker: " .. target.Label)
		end
		if math.deg(maxPitchJump) > 25 and not crashed and not string.find(jumpAt, "t=0.0", 1, true) then
			totals.Snap += 1
			print("  GLITCH pitch snap: " .. target.Label .. " " .. jumpAt)
		end
		if crashed then
			totals.Crash += 1
		end
		local summary = string.format("%-55s %s%3d km/h  takeoffs %d lands %d impacts %d crash %s  max dPitch %.0f deg/frame", target.Label, if run.Down then "DOWN " else "", kmh, counts.Takeoff or 0, counts.Land or 0, counts.Impact or 0, if crashed then "YES" else "no", math.deg(maxPitchJump))
		print(summary .. "  @ " .. jumpAt)
		if verbose or crashed or (counts.Takeoff or 0) > 2 then
			for _, line in log do
				print("      " .. line)
			end
		end
	end
end
print(string.format("== %d runs, %d crashed (walls), %d flickering, %d pitch snaps; %d rays, %d sweeps", totals.Runs, totals.Crash, totals.Flicker, totals.Snap, geo.Stats.Rays, geo.Stats.Sweeps))
if totals.Flicker + totals.Snap > 0 then
	process.exit(1)
end
