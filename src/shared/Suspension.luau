--[[
	Suspension: the spring-damper model the bike rides on. Pure Luau (no services), run by BikePhysics
	every frame and tested offline.

	Planar, in the bike's vertical plane along its heading. Four degrees of freedom:
		the sprung chassis (bike + rider): its height and pitch,
		each wheel's axle height (unsprung: wheel, brake, fork lowers / swingarm).
	On the ground they live in WORLD height, so nothing jumps when BikePhysics' ground line does (it
	snaps over a kerb's step; the bike doesn't): a kerb is just the ground under one tyre rising as
	the bike rolls on, the foot of a ramp drives the wheels up into the springs, a crest lets them
	go light, a kerb drop lets them fall. Inside a loop they ride the loop's own curved frame instead.

	Forces:
		suspension  a progressive spring with preload, separate compression / rebound damping, a stiff
		            progressive bump stop past full travel and a top-out stop below zero, along the
		            chassis' normal between each axle and its mount (compression C = how far the axle
		            has risen from top-out)
		tyre        a stiff one-sided spring-damper between the axle and the ground under the wheel
		            (the ground's height is sampled across the tyre's footprint by BikePhysics, so a
		            wheel rolls up a kerb edge; terrain roughness comes from Suspension.Roughness)
		load        weight transfer: accelerating squats the rear, braking dives the front
		hop         the rider preloading for a bunny hop pushes the chassis down
		landing     touchdown arrives at the landing speed, less what the rider's legs soak up

	Integrated with semi-implicit Euler in fixed 1/960 s substeps (the stiffest mode, a wheel on a
	bump stop, stays far inside the stable range at any frame rate).

	Units: metres, seconds, kilograms. BikePhysics converts studs at the edges.
]]

local Config = require(script.Parent.Config)

local Suspension = {}

local G = 9.81
local SUBSTEP = 1 / 960
local SAG = 0.3 -- static sag as a fraction of travel, with the rider on
local PRELOAD = 0.08 -- spring preload as a fraction of travel (holds the top-out)
local FRONT_SHARE = 0.45 -- of the sprung weight on the front wheel
local TYRE_SAG = 0.02 -- m of tyre squash under static load
local ENVELOP = 0.6 -- a tyre wraps round a sharp edge over this fraction of its radius (rising ground
-- under a wheel is smoothed over that much travel; falling ground isn't)
local LEGS = 0.6 -- of the landing speed that reaches the suspension (the rider's legs take the rest)

export type Corner = {
	X: number, -- m along the chassis from the centre of mass (+ forward)
	R: number, -- wheel radius, m
	T: number, -- travel, m
	K: number, -- spring rate, N/m
	P: number, -- preload, m
	Prog: number, -- progression: the rate rises by (1 + Prog * (C/T)^2)
	Comp: number, -- compression damping, N·s/m
	Reb: number, -- rebound damping, N·s/m
	Mw: number, -- unsprung mass, kg
	Kt: number, -- tyre rate, N/m
	Ct: number, -- tyre damping, N·s/m
}

export type Params = {
	M: number, -- sprung mass (bike less wheels, plus rider), kg
	I: number, -- pitch inertia about the centre of mass, kg·m²
	H: number, -- centre-of-mass height above the ground, m
	Xcg: number, -- centre of mass ahead of the wheelbase midpoint, m (negative: behind)
	Corners: { Corner }, -- [1] front, [2] rear
}

-- E: the chassis' reference height at the centre of mass's station (the model's y = 0 line, which
-- is the ground at top-out), B: its pitch (+ nose up), Y: the axles' heights. In "World" space these
-- are world heights (m) and world pitch; in "Loop" space they're offsets along the loop's normal and
-- pitch relative to the loop's tangent.
export type State = {
	Space: string,
	E: number,
	EV: number,
	B: number,
	BV: number,
	Y: { number },
	YV: { number },
	C: { number }, -- compressions (0 = topped out .. T = bottomed), for the visuals
	Grounded: { boolean }, -- each tyre touching
	Ground: { number? }, -- the ground under each wheel as the tyre feels it (enveloped)
	Lift: number, -- while airborne: the chassis' leftover offset from the bike's air position, m
	Tilt: number, -- (and pitch)
	Ready: boolean,
}

-- What BikePhysics tells the suspension about a frame
export type Frame = {
	Mode: string, -- "Ground", "Air" or "Loop"
	WasGround: boolean, -- on the ground (or in a loop) last frame
	WasLoop: boolean,
	Origin: Vector3, -- the ground line's midpoint this frame, m (world)
	Move: Vector3, -- how far it moved this frame, m
	Heading: Vector3, -- unit horizontal heading
	Pitch: number, -- the ground line's (or the loop's) pitch this frame
	PitchBefore: number,
	Speed: number, -- m/s along the line
	Support: { number? }, -- the height a wheel's axle rests at on the ground under it, m (world;
	-- nil: nothing under it)
	LongAccel: number, -- m/s², + speeding up
	Hop: number, -- 0..1 preload
	FrontOff: boolean, -- wheelie: the front wheel is up
	RearOff: boolean, -- stoppie: the rear wheel is up
	LandingSpeed: number?, -- touched down this frame at this vertical speed (m/s, negative down)
	LoopRadius: number?, -- m, inside a loop
}

local function cornerFor(x: number, radius: number, travel: number, share: number, mSprung: number, mWheel: number, level: number): Corner
	local load = share * mSprung * G
	local sag = SAG * travel
	local preload = PRELOAD * travel
	local prog = if level >= 2 then 2.2 else 1.4
	local k = load / ((sag + preload) * (1 + prog * SAG * SAG))
	local critical = 2 * math.sqrt(k * share * mSprung)
	local kt = load / TYRE_SAG
	return {
		X = x,
		R = radius,
		T = travel,
		K = k,
		P = preload,
		Prog = prog,
		Comp = (if level >= 1 then 0.4 else 0.33) * critical,
		Reb = (if level >= 1 then 0.62 else 0.55) * critical,
		Mw = mWheel,
		Kt = kt,
		Ct = 2 * 0.2 * math.sqrt(kt * mWheel),
	}
end

-- The spring-damper model for a bike's spec (BikeStats.Spec)
function Suspension.Params(spec: any): Params
	local studs = Config.VISUAL_STUDS_PER_METER
	local wheelbase = spec.Wheelbase / studs
	local mWheel = math.max(4, spec.BikeKg * 0.09)
	local mSprung = spec.MassKg - 2 * mWheel
	local xcg = -wheelbase * (0.5 - FRONT_SHARE) -- a 45/55 split puts the mass behind the middle
	local level = spec.SuspensionLevel or 0
	return {
		M = mSprung,
		I = mSprung * (0.33 * wheelbase) ^ 2,
		H = spec.SeatHeightM * 0.75 + 0.25,
		Xcg = xcg,
		Corners = {
			cornerFor(wheelbase / 2 - xcg, spec.WheelRadius / studs, spec.FrontTravel, FRONT_SHARE, mSprung, mWheel, level),
			cornerFor(-wheelbase / 2 - xcg, spec.RearWheelRadius / studs, spec.RearTravel, 1 - FRONT_SHARE, mSprung, mWheel, level),
		},
	}
end

-- Spring + damper force along the chassis' normal, pushing the axle down and the chassis up
local function strut(k: Corner, c: number, cv: number): number
	local f: number
	if c >= 0 then
		local x = c / k.T
		f = k.K * (c + k.P) * (1 + k.Prog * x * x)
		if c > k.T then
			-- bump stop: stiff and progressive, heavily damped
			local over = c - k.T
			f += 60 * k.K * over + 1500 * k.K * over * over / k.T + 3 * k.Comp * math.max(0, cv)
		end
	else
		f = k.K * k.P + 40 * k.K * c -- top-out stop: pulls the wheel back up
	end
	f += if cv > 0 then k.Comp * cv else k.Reb * cv
	return f
end

-- The axle's top-out position on the chassis, as a height (on the chassis' normal through it)
local function mount(st: State, k: Corner): number
	return st.E + k.X * math.sin(st.B) + k.R * math.cos(st.B)
end

local function compression(st: State, k: Corner, y: number): number
	return (y - mount(st, k)) / math.max(0.3, math.cos(st.B))
end

-- At rest on the ground: each axle on its squashed tyre at height `rest[i]`, each strut at its sag
local function settle(st: State, p: Params, rest: { number }, pitch: number)
	local stations = {}
	for i, k in p.Corners do
		local share = if i == 1 then FRONT_SHARE else 1 - FRONT_SHARE
		st.Y[i] = rest[i] - (share * p.M * G + k.Mw * G) / k.Kt
		st.YV[i] = 0
		st.C[i] = SAG * k.T
		st.Grounded[i] = true
		stations[i] = st.Y[i] - st.C[i] * math.cos(pitch) - k.R * math.cos(pitch) -- = E + X_i sin(B)
	end
	local f, r = p.Corners[1], p.Corners[2]
	st.B = math.asin(math.clamp((stations[1] - stations[2]) / (f.X - r.X), -0.9, 0.9))
	st.E = stations[1] - f.X * math.sin(st.B)
	st.EV, st.BV = 0, 0
	st.Lift, st.Tilt = 0, 0
	st.Ready = true
end

function Suspension.new(p: Params): State
	local st: State = { Space = "World", E = 0, EV = 0, B = 0, BV = 0, Y = { 0, 0 }, YV = { 0, 0 }, C = { 0, 0 }, Grounded = { true, true }, Ground = { nil, nil }, Lift = 0, Tilt = 0, Ready = false }
	return st
end

-- The heights the axles rest at on flat ground under the line, for settling without samples
local function lineRest(p: Params, f: Frame): { number }
	local rest = {}
	for i, k in p.Corners do
		rest[i] = f.Origin.Y + (k.X + p.Xcg) * math.sin(f.Pitch) + k.R
	end
	return rest
end

local function integrate(st: State, p: Params, support: { number? }, gravity: number, f: Frame, dt: number)
	local hold = f.FrontOff or f.RearOff
	local steps = math.max(1, math.ceil(dt / SUBSTEP - 1e-6))
	local h = dt / steps
	local corners = p.Corners
	local holdPitch = if st.Space == "Loop" then 0 else f.Pitch
	for _ = 1, steps do
		local cosB = math.cos(st.B)
		local heave = -p.M * gravity - f.Hop * 0.55 * p.M * G
		local torque = p.M * f.LongAccel * p.H
		for i, k in corners do
			local c = compression(st, k, st.Y[i])
			local cv = (st.YV[i] - (st.EV + k.X * cosB * st.BV)) / math.max(0.3, cosB)
			local s = strut(k, c, cv)
			-- the tyre on the ground under it (a wheel in the air, or held up in a wheelie, has none)
			local tyre = 0
			local ground = support[i]
			local lifted = (i == 1 and f.FrontOff) or (i == 2 and f.RearOff)
			if ground and not lifted then
				local squash = ground - st.Y[i]
				if squash > 0 then
					tyre = math.max(0, k.Kt * squash - k.Ct * st.YV[i])
				end
			end
			st.Grounded[i] = tyre > 0
			st.YV[i] += ((tyre - s * cosB) / k.Mw - gravity) * h
			heave += s * cosB
			torque += s * k.X
		end
		if hold then
			-- a wheelie or stoppie holds the chassis' attitude to the ground (the rider's balance
			-- does that; the wheelie angle itself is drawn on top); the weight all goes through the
			-- one wheel left down
			torque -= p.I * (900 * (st.B - holdPitch) + 60 * st.BV)
		end
		st.EV += heave / p.M * h
		st.BV += torque / p.I * h
		st.E += st.EV * h
		st.B += st.BV * h
		for i in corners do
			st.Y[i] += st.YV[i] * h
		end
	end
	for i, k in corners do
		st.C[i] = compression(st, k, st.Y[i])
	end
end

-- Into / out of a loop: the same bodies re-expressed between world heights and the loop's frame
-- (entry and exit are flat, so it's an offset along the vertical)
local function toLoop(st: State, f: Frame)
	st.Space = "Loop"
	st.E -= f.Origin.Y
	st.B -= f.Pitch
	for i in st.Y do
		st.Y[i] -= f.Origin.Y
	end
end
local function toWorld(st: State, f: Frame)
	st.Space = "World"
	st.E += f.Origin.Y
	st.B += f.Pitch
	for i in st.Y do
		st.Y[i] += f.Origin.Y
	end
end

-- Inside a loop the frame follows the path: re-express the bodies in this frame's tangent and normal
-- (the path's own curvature turns their speed into load on the springs)
local function reframeLoop(st: State, p: Params, f: Frame)
	local turn = (f.Pitch - f.PitchBefore + math.pi) % (2 * math.pi) - math.pi
	local cosT, sinT = math.cos(turn), math.sin(turn)
	-- the bodies ride along the path; only rotation moves them relative to the new frame
	st.E = st.E * cosT - p.Xcg * sinT
	st.EV = st.EV * cosT - f.Speed * sinT
	for i, k in p.Corners do
		st.Y[i] = st.Y[i] * cosT - (k.X + p.Xcg) * sinT
		st.YV[i] = st.YV[i] * cosT - f.Speed * sinT
	end
	st.B -= turn
end

-- Advances the suspension by dt. Call every frame after BikePhysics has moved the bike.
function Suspension.Step(st: State, p: Params, f: Frame, dt: number)
	if dt <= 0 then
		return
	end
	dt = math.min(dt, 0.1)
	if f.Mode == "Air" then
		-- the bike flies where BikePhysics says; the chassis eases onto that, the wheels drop to
		-- top-out (unloaded, the springs push them all the way out)
		if f.WasGround then
			if st.Space == "Loop" then
				toWorld(st, f)
			end
			-- the chassis' height and pitch, relative to where BikePhysics now flies the bike
			local reference = f.Origin.Y + p.Xcg * math.sin(f.Pitch)
			st.Lift = st.E - reference
			st.Tilt = st.B - f.Pitch
		end
		local ease = math.exp(-10 * dt)
		st.Lift *= ease
		st.Tilt *= ease
		for i in p.Corners do
			st.C[i] *= math.exp(-14 * dt)
			st.Grounded[i] = false
		end
		st.Ready = false
		return
	end

	if f.Mode == "Loop" then
		if not st.Ready then
			settle(st, p, lineRest(p, f), f.Pitch)
		end
		if st.Space ~= "Loop" then
			toLoop(st, f)
		else
			reframeLoop(st, p, f)
		end
		-- the loop curves up toward its centre under both wheels; gravity along the loop's normal
		local r = f.LoopRadius or 1e6
		local support = {}
		for i, k in p.Corners do
			local x = k.X + p.Xcg
			support[i] = r - math.sqrt(math.max(0, r * r - x * x)) + k.R
		end
		integrate(st, p, support, G * math.cos(f.Pitch), f, dt)
		return
	end

	-- on the ground
	if st.Space == "Loop" then
		toWorld(st, f)
	end
	local support = f.Support
	if not f.WasGround and st.Space == "World" then
		-- touchdown: wheels at top-out just touching the ground line (plus what's left of the air
		-- offset), the whole bike moving down at the landing speed less what the rider's legs take;
		-- a big drop can bottom the springs out
		local landing = (f.LandingSpeed or 0) * LEGS
		st.E = f.Origin.Y + p.Xcg * math.sin(f.Pitch) + st.Lift
		st.B = f.Pitch + st.Tilt
		st.EV, st.BV = landing, 0
		for i, k in p.Corners do
			st.Y[i] = mount(st, k)
			st.YV[i] = landing
			st.C[i] = 0
		end
		st.Lift, st.Tilt = 0, 0
		st.Ready = true
	elseif not st.Ready then
		settle(st, p, lineRest(p, f), f.Pitch)
	elseif f.Move.Magnitude > 8 then
		-- a teleport: start settled at the new spot
		settle(st, p, lineRest(p, f), f.Pitch)
	end
	-- a wheel with nothing sampled under it rests on the ground line (e.g. the simulator's flat world
	-- returns no sample past a lip): better than letting it fall forever
	local filled: { number? } = {}
	local rest = lineRest(p, f)
	local speed = math.max(math.abs(f.Speed), 1)
	for i, k in p.Corners do
		local raw = support[i] or (if f.Mode == "Ground" then rest[i] - 0.6 else nil)
		-- the tyre envelops a sharp edge: rising ground comes up over ENVELOP * R of travel
		local felt = st.Ground[i]
		if raw and felt and raw > felt and f.Move.Magnitude < 8 then
			raw = felt + (raw - felt) * (1 - math.exp(-dt * speed / (ENVELOP * k.R)))
		end
		st.Ground[i] = raw
		filled[i] = raw
	end
	integrate(st, p, filled, G, f, dt)
	-- a hard limit so nothing can ever run away (a 0.1 s hitch, a mismatched ground line)
	for i, k in p.Corners do
		if st.C[i] ~= st.C[i] or math.abs(st.C[i]) > 2 * k.T + 0.5 or math.abs(st.E - f.Origin.Y) > 4 then
			settle(st, p, rest, f.Pitch)
			break
		end
	end
end

-- Where to draw the chassis, at the wheelbase midpoint (the model's origin):
--   "World"     on the ground: its height (m, world) and pitch (rad, world)
--   "Relative"  in the air or a loop: its offset along the line's normal (m) and pitch relative to it
function Suspension.Pose(st: State, p: Params, airborne: boolean): (string, number, number)
	if airborne then
		return "Relative", st.Lift, st.Tilt
	end
	local origin = st.E - p.Xcg * math.sin(st.B)
	return if st.Space == "Loop" then "Relative" else "World", origin, st.B
end

-- Terrain roughness: a small, deterministic height offset (m) of the ground at a world point (studs)
-- for a surface kind, the same on every client. Grass, dirt and fields are bumpy, paving has joints,
-- roads and ramps are smooth.
local ROUGH: { [string]: { number } } = {
	-- { amplitude m, wavelength m, fine amplitude m, fine wavelength m }
	Grass = { 0.055, 1.5, 0.018, 0.45 }, -- lawns, verges, crop fields
	Dirt = { 0.075, 1.8, 0.025, 0.5 }, -- ploughed fields, yards, dirt tracks
	Mud = { 0.06, 1.6, 0.03, 0.4 },
	Sand = { 0.04, 2.2, 0.012, 0.6 },
	Sidewalk = { 0.004, 1.2, 0.003, 0.3 },
	Road = { 0.002, 3, 0.001, 0.8 },
}
function Suspension.Roughness(position: Vector3, kind: string): number
	local spec = ROUGH[kind]
	if not spec then
		return 0
	end
	local studs = Config.STUDS_PER_METER
	local x, z = position.X / studs, position.Z / studs
	return spec[1] * math.noise(x / spec[2], z / spec[2], 7.31) + spec[3] * math.noise(x / spec[4] + 41.7, z / spec[4], 3.17)
end

return Suspension
