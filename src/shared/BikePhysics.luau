--[[
	BikePhysics: the riding model. Pure Luau (no services), so tests run it under Lune against a fake
	world, and the client runs exactly the same code against the real one.

	The bike is kinematic: this module owns its position, heading and speed, and the client writes
	the result onto the bike's root part every frame. Forces are real-world:
		drive   = rider pedalling + motor (assist factor x rider power, capped by the mode's max power;
		          or throttle), limited by motor torque at the wheel and by tyre grip, and cut at the
		          assist limit (the e-bike's legal class, or the controller limit in off-road mode)
		resist  = aero drag ½ρCdAv² + rolling resistance Crr·m·g + grade m·g·sinθ + brakes
	Battery drains with the motor's electrical power (time-compressed, Config.Battery.DrainScale),
	hub motors regenerate a little under braking, and a low pack limits power like a real BMS.

	Steering is bicycle kinematics (yaw rate = v·tanδ / wheelbase) with lateral grip as the limit, and
	the lean is the real lean for that turn (atan(v·ω/g)).

	Wheelie: holding the key makes the rider hold the bike at a balance angle; the throttle lifts it,
	the rear brake brings it down (real technique), and a wobble that grows with time and speed has to
	be corrected or it loops out. Jumps are ballistic; pulling back in the air flips, steering spins,
	and the landing is judged on pitch and heading.

	Conventions: model space is -Z forward, +Y up; Yaw 0 faces -Z; positive Pitch / Wheelie lift the
	front; positive Lean tips the top to the left (-X). Speed is m/s, positions are studs.
]]

local Config = require(script.Parent.Config)
local BikeStats = require(script.Parent.BikeStats)
local Modes = require(script.Parent.Modes)
local Suspension = require(script.Parent.Suspension)

local BikePhysics = {}

local P = Config.Physics
local WH = Config.Wheelie
local DR = Config.Drift
local ST = Config.Stoppie
local AT = Config.AirTricks
local LP = Config.Loop
local TU = Config.Turning
local STUDS = Config.STUDS_PER_METER
local UP = Vector3.yAxis
local TAU = math.pi * 2

export type Spec = BikeStats.Spec
export type Mode = Modes.Mode

export type Input = {
	Throttle: number, -- 0..1
	Brake: number, -- 0..1
	Steer: number, -- -1 (left) .. 1 (right)
	Wheelie: boolean,
	Hop: boolean, -- held
	OneHand: boolean,
	NoHands: boolean,
	Drift: boolean, -- rear brake locked to slide the tail out
	Trick: string?, -- air trick held: "Superman", "CanCan", "NacNac", "KneeKnocker", "NoFooter"
	Barspin: boolean, -- held key; a press starts a barspin
}

export type Hit = {
	Position: Vector3,
	Normal: Vector3,
	Kind: string, -- "Road", "Sidewalk", "Grass", "Dirt", "Ramp", "Car", ...
}

-- A loop-the-loop: Entry is on the riding surface at the bottom, LookVector along the loop;
-- Radius in studs; Shift is how far sideways the track moves over one turn (so you exit beside
-- where you came in)
export type Loop = { Entry: CFrame, Radius: number, Shift: number }

export type World = {
	-- First solid surface below `origin` within `length` studs
	Down: (origin: Vector3, length: number) -> Hit?,
	-- Sweeps a box (centre frame, size) along `delta`; distance travelled before contact, the contact
	-- normal and what was hit ("Wall", "Car", "Cop")
	Sweep: (frame: CFrame, size: Vector3, delta: Vector3) -> (number?, Vector3?, string?),
	-- A loop whose entry the bike is rolling onto (optional)
	Loop: ((position: Vector3, heading: Vector3) -> Loop?)?,
}

export type Event = {
	Kind: string,
	Value: number?,
	Extra: number?,
	Text: string?,
}

export type State = {
	Position: Vector3, -- ground point midway between the tyre contacts
	Yaw: number,
	Speed: number, -- m/s along the heading
	Velocity: Vector3, -- studs/s, for the part's AssemblyLinearVelocity
	Grounded: boolean,
	VerticalSpeed: number, -- m/s while airborne
	AirVelocity: Vector3, -- horizontal studs/s while airborne
	Pitch: number,
	RearY: number, -- height of the rear tyre's contact
	RearVy: number, -- m/s the rear tyre is rising at (from the slope under it)
	Wheelie: number,
	WheelieRate: number,
	WheelieTime: number,
	WheelieActive: boolean,
	Lean: number,
	Steer: number,
	SteerAngle: number,
	AirTime: number,
	AirPitch: number, -- rotation accumulated in the air (flips)
	AirYaw: number, -- (spins)
	AirPitchRate: number,
	AirYawRate: number,
	AirHands: boolean, -- let go in the air
	VertLaunch: number?, -- pitch of the quarter pipe face we left (turned round at the top)
	FakieHold: boolean?, -- coming back down the face: hold the pitch
	Crash: number, -- seconds of bail left
	CrashReason: string,
	CrashSide: number,
	Battery: number, -- Wh
	MotorPower: number, -- W the motor is putting out
	Cadence: number, -- rpm
	CrankAngle: number,
	WheelAngle: number,
	Distance: number, -- metres ridden
	Surface: string,
	Offroad: boolean,
	HopCharge: number,
	HopHeld: boolean,
	Time: number,
	NoiseA: number,
	NoiseB: number,
	Hands: number, -- 0 both, 1 one hand, 2 no hands (what the pose shows)
	TravelYaw: number, -- direction the bike is actually moving (differs from Yaw in a drift)
	Slip: number, -- rad between heading and travel (+ = tail out to the right)
	DriftActive: boolean,
	DriftTime: number,
	DriftAngle: number, -- biggest slip of this drift, rad
	TrickName: string, -- the air trick being thrown ("" none)
	TrickExt: number, -- 0 tucked .. 1 fully out
	TrickHold: number, -- seconds held fully out
	TrickCounted: boolean,
	AirTricks: number, -- tricks landed this jump
	BarSpin: number, -- 0 none, else progress 0..1 of a barspin
	BarspinHeld: boolean,
	Stoppie: number, -- rad the rear is lifted (front-wheel balance)
	StoppieRate: number,
	StoppieActive: boolean,
	StoppieTime: number,
	Flat: number, -- seconds of flat tyre left (police spike strip)
	Wet: boolean, -- in the water (Splash fired; the controller puts the bike back on the shore)
	Loop: Loop?, -- riding a loop
	LoopAngle: number, -- rad round it
	BrakeApplied: number, -- 0..1, the brake as squeezed (follows the input at BrakeSqueeze)
	FrontBraking: boolean, -- the front brake is on (brake + Shift); otherwise braking is the rear's
	TurnRate: number, -- rad/s the bike is actually turning (rolls in and out after the bars, a spring)
	TurnRateVel: number,
	Settle: number, -- seconds after a landing while the front comes down at its own pace
	-- the spring-damper suspension the chassis rides on (Shared/Suspension), built on the first step
	Sus: Suspension.State?,
	SusParams: Suspension.Params?,
	SusSpec: Spec?, -- the spec SusParams were built from (tuning while riding rebuilds them)
}

local OFFROAD = { Grass = true, Dirt = true, Sand = true, Mud = true, Foam = true }
BikePhysics.Offroad = OFFROAD

local function approach(current: number, target: number, step: number): number
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

local function wrap(angle: number): number
	return (angle + math.pi) % TAU - math.pi
end

function BikePhysics.Heading(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end
local heading = BikePhysics.Heading

function BikePhysics.YawOf(look: Vector3): number
	return math.atan2(-look.X, -look.Z)
end

function BikePhysics.new(spec: Spec, ground: CFrame, battery: number?, seed: number?): State
	local s = seed or 1
	return {
		Position = ground.Position,
		Yaw = BikePhysics.YawOf(ground.LookVector),
		Speed = 0,
		Velocity = Vector3.zero,
		Grounded = true,
		VerticalSpeed = 0,
		AirVelocity = Vector3.zero,
		Pitch = 0,
		RearY = ground.Position.Y,
		RearVy = 0,
		Wheelie = 0,
		WheelieRate = 0,
		WheelieTime = 0,
		WheelieActive = false,
		Lean = 0,
		Steer = 0,
		SteerAngle = 0,
		AirTime = 0,
		AirPitch = 0,
		AirYaw = 0,
		AirPitchRate = 0,
		AirYawRate = 0,
		AirHands = false,
		Crash = 0,
		CrashReason = "",
		CrashSide = 1,
		Battery = math.clamp(battery or spec.BatteryWh, 0, spec.BatteryWh),
		MotorPower = 0,
		Cadence = 0,
		CrankAngle = 0,
		WheelAngle = 0,
		Distance = 0,
		Surface = "Road",
		Offroad = false,
		HopCharge = 0,
		HopHeld = false,
		Time = 0,
		NoiseA = (s * 1.618) % TAU,
		NoiseB = (s * 2.718) % TAU,
		Hands = 0,
		TravelYaw = BikePhysics.YawOf(ground.LookVector),
		Slip = 0,
		DriftActive = false,
		DriftTime = 0,
		DriftAngle = 0,
		TrickName = "",
		TrickExt = 0,
		TrickHold = 0,
		TrickCounted = false,
		AirTricks = 0,
		BarSpin = 0,
		BarspinHeld = false,
		Stoppie = 0,
		StoppieRate = 0,
		StoppieActive = false,
		StoppieTime = 0,
		Flat = 0,
		Wet = false,
		Loop = nil,
		LoopAngle = 0,
		BrakeApplied = 0,
		FrontBraking = false,
		TurnRate = 0,
		TurnRateVel = 0,
		Settle = 0,
		Sus = nil,
		SusParams = nil,
		SusSpec = nil,
	}
end

function BikePhysics.Idle(): Input
	return { Throttle = 0, Brake = 0, Steer = 0, Wheelie = false, Hop = false, OneHand = false, NoHands = false, Drift = false, Trick = nil, Barspin = false }
end

-- km/h along the heading
function BikePhysics.Kmh(s: State): number
	if s.Grounded then
		return math.abs(s.Speed) * 3.6
	end
	return s.AirVelocity.Magnitude / STUDS * 3.6
end

-- The frame the bike model is drawn at: the sprung chassis. The model's origin is the ground
-- midpoint between the wheels with the suspension topped out, so on the ground line it sits lower
-- by the sag and moves with the suspension (heave along the line's normal, pitch about it).
function BikePhysics.GetCFrame(s: State, spec: Spec): CFrame
	local base = CFrame.new(s.Position) * CFrame.fromEulerAnglesYXZ(0, s.Yaw, 0)
	-- a wheelie turns the bike about the rear axle (the wheel stays on the ground under it), a stoppie
	-- about the front one, each where the suspension has it in the chassis (risen by its compression)
	local cFront, cRear = BikePhysics.DrawnCompression(s)
	local VIS = Config.VISUAL_STUDS_PER_METER
	local pivot = Vector3.new(0, spec.RearWheelRadius + cRear * VIS, spec.Wheelbase / 2)
	local wheelie = CFrame.new(pivot) * CFrame.Angles(s.Wheelie, 0, 0) * CFrame.new(-pivot)
	local front = Vector3.new(0, spec.WheelRadius + cFront * VIS, -spec.Wheelbase / 2)
	local stoppie = CFrame.new(front) * CFrame.Angles(-s.Stoppie, 0, 0) * CFrame.new(-front)
	local frame = base * CFrame.Angles(s.Pitch, 0, 0)
	local sus, params = s.Sus, s.SusParams
	if sus and params then
		local kind, a, b = Suspension.Pose(sus, params, not s.Grounded and not s.Loop)
		if kind == "World" then
			-- on the ground: the chassis' own height and pitch (the ground line under it can snap
			-- over a kerb; the chassis doesn't)
			frame = CFrame.new(s.Position.X, a * Config.STUDS_PER_METER, s.Position.Z) * CFrame.fromEulerAnglesYXZ(0, s.Yaw, 0) * CFrame.Angles(b, 0, 0)
		else
			frame = frame * CFrame.new(0, a * Config.VISUAL_STUDS_PER_METER, 0) * CFrame.Angles(b, 0, 0)
		end
	end
	return frame * CFrame.Angles(0, 0, s.Lean) * wheelie * stoppie
end

-- The chassis' pitch in the world (rad, + nose up), riding its suspension
function BikePhysics.ChassisPitch(s: State): number
	local sus, params = s.Sus, s.SusParams
	if sus and params then
		local kind, _, b = Suspension.Pose(sus, params, not s.Grounded and not s.Loop)
		return if kind == "World" then b else s.Pitch + b
	end
	return s.Pitch
end

-- Suspension compression at each wheel (m: 0 topped out .. travel bottomed), for the visuals
function BikePhysics.Compression(s: State): (number, number)
	local sus = s.Sus
	if not sus then
		return 0, 0
	end
	return sus.C[1], sus.C[2]
end

-- What to draw at each wheel: the compression plus the tyre's squash (the drawn wheel is rigid, so it
-- rises by the squash too and sits on the road instead of in it)
function BikePhysics.DrawnCompression(s: State): (number, number)
	local sus = s.Sus
	if not sus then
		return 0, 0
	end
	local out = { sus.C[1], sus.C[2] }
	for i = 1, 2 do
		local ground = sus.Ground[i]
		if sus.Grounded[i] and ground then
			out[i] += math.clamp(ground - sus.Y[i], 0, 0.06)
		end
	end
	return out[1], out[2]
end

-- The box swept for collisions: the body above step height, aligned with the heading
function BikePhysics.Body(s: State, spec: Spec): (CFrame, Vector3)
	local length = spec.Wheelbase + spec.WheelRadius + spec.RearWheelRadius
	local k = Config.BIKE_SIZE * spec.Scale / 1.2 -- the box was sized for bikes drawn 1.2x life size
	local height = 3.4 * k
	local size = Vector3.new(1.3 * k, height, length)
	-- tilted with the ground under it, so on a ramp or a hill it glides along the surface instead of
	-- its level front corner digging into the rise
	local pitch = if s.Grounded then math.clamp(s.Pitch, -1.2, 1.2) else 0
	local frame = CFrame.new(s.Position) * CFrame.fromEulerAnglesYXZ(0, s.Yaw, 0) * CFrame.Angles(pitch, 0, 0)
	return frame * CFrame.new(0, P.StepHeight + 0.1 + height / 2, 0), size
end

local function push(events: { Event }, kind: string, value: number?, extra: number?, text: string?)
	table.insert(events, { Kind = kind, Value = value, Extra = extra, Text = text })
end

local function endWheelie(s: State, events: { Event }, failed: boolean)
	if s.WheelieActive then
		push(events, "WheelieEnd", s.WheelieTime, if failed then 1 else 0)
	end
	s.WheelieActive = false
	s.WheelieTime = 0
end

local function crash(s: State, events: { Event }, reason: string)
	if s.Crash > 0 then
		return
	end
	endWheelie(s, events, true)
	s.Crash = P.CrashTime
	s.CrashReason = reason
	s.CrashSide = if s.Lean > 0.02 then 1 elseif s.Lean < -0.02 then -1 elseif s.Steer > 0 then -1 else 1
	s.Wheelie = 0
	s.WheelieRate = 0
	s.HopCharge = 0
	push(events, "Crash", nil, nil, reason)
end

-- Two probes, one under each tyre. Returns the ground height under the midpoint, the slope pitch
-- and the surface, or nil if neither tyre has ground under it.
local function probe(world: World, position: Vector3, yaw: number, spec: Spec, above: number, length: number): (number?, number, string)
	local dir = heading(yaw)
	local half = spec.Wheelbase / 2
	local front = world.Down(position + dir * half + UP * above, length)
	local rear = world.Down(position - dir * half + UP * above, length)
	if front and rear then
		local yf, yr = front.Position.Y, rear.Position.Y
		local kind = if OFFROAD[rear.Kind] or OFFROAD[front.Kind] then (if OFFROAD[rear.Kind] then rear.Kind else front.Kind) else rear.Kind
		return (yf + yr) / 2, math.atan2(yf - yr, spec.Wheelbase), kind
	elseif rear then
		return rear.Position.Y, 0, rear.Kind
	elseif front then
		return front.Position.Y, 0, front.Kind
	end
	return nil, 0, "Air"
end

local function noise(s: State): number
	local t = s.Time
	return math.sin(1.7 * t + s.NoiseA) * 0.6 + math.sin(3.1 * t + s.NoiseB) * 0.4 + math.sin(0.53 * t + s.NoiseA * 0.5) * 0.35
end

-- The height (m, world) a wheel's axle rests at on the ground under it, from rays across the tyre's
-- footprint: the wheel sits on the highest point its circle touches, so it rolls up a kerb edge
-- instead of jumping it. Terrain roughness by surface is added to every sample. nil: nothing under it.
-- `x` is the wheel's station along the ground line from its midpoint (studs, + forward).
local SAMPLES = { -0.8, -0.4, 0, 0.4, 0.8 }
local function wheelSupport(world: World, origin: Vector3, along: Vector3, dir: Vector3, x: number, radius: number, reach: number): number?
	local best: number? = nil
	local station = origin + along * x
	for _, f in SAMPLES do
		local at = station + dir * (f * radius)
		local hit = world.Down(at + UP * (2 * radius + 1.5), 2 * radius + 1.5 + reach)
		if hit then
			local dx = (hit.Position - station):Dot(dir)
			if math.abs(dx) < radius then
				local height = hit.Position.Y + Suspension.Roughness(hit.Position, hit.Kind) * STUDS
				local axle = height + math.sqrt(radius * radius - dx * dx)
				if best == nil or axle > best then
					best = axle
				end
			end
		end
	end
	return if best then best / STUDS else nil
end

-- Horizontal move with collision. Returns the delta actually travelled and, if something was hit,
-- its flattened normal, how square-on the hit was (0 glancing .. 1 head-on) and what it was.
local function sweepMove(s: State, spec: Spec, world: World, delta: Vector3): (Vector3, Vector3?, number, string)
	local magnitude = delta.Magnitude
	if magnitude < 1e-5 then
		return delta, nil, 0, ""
	end
	local frame, size = BikePhysics.Body(s, spec)
	local distance, normal, kind = world.Sweep(frame, size, delta)
	if not distance or not normal then
		return delta, nil, 0, ""
	end
	if kind == "Slope" then
		-- the edge of a ramp, a loop or a hill (World says so): ride on, the ground rays carry the bike
		return delta, nil, 0, "Slope"
	end
	local travel = math.max(0, distance - 0.05)
	local moved = delta.Unit * travel
	if normal.Y > 0.3 then
		-- a face you can ride up (a ramp, a quarter pipe): the wheels' ground probes deal with it
		return moved, nil, 0, "Slope"
	end
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 0.2 then
		return moved, nil, 0, ""
	end
	flat = flat.Unit
	local into = math.max(0, -delta.Unit:Dot(flat))
	return moved, flat, into, kind or "Wall"
end

-- What an impact does: cars bail you at a lower speed than walls (they move); reports it either way
local function impact(s: State, events: { Event }, speed: number, into: number, kind: string)
	local hit = speed * into
	if hit > 1 then
		push(events, "Impact", hit, nil, kind)
	end
	-- glancing blows never bail you; a small street prop (a bench, a bin, a bollard) stops you dead
	-- at a crawl but throws you over the bars at speed
	if into < P.CrashSquareness then
		return
	end
	local limit = if kind == "Car" or kind == "Cop" then Config.Traffic.HitKmh / 3.6 elseif kind == "Prop" then P.PropCrashImpact else P.CrashImpact
	if hit > limit then
		crash(s, events, if kind == "Wall" then "Wall" elseif kind == "Prop" then "Hit something" else "Hit a car")
	end
end

-- Riding a loop: the bike follows the circle. Gravity takes speed on the way up (softened, with a
-- little motor help); too slow near the top and it falls off.
local function loopStep(s: State, spec: Spec, input: Input, dt: number, events: { Event })
	local loop = s.Loop :: Loop
	local radiusStuds = loop.Radius
	local r = radiusStuds / STUDS
	local g = P.Gravity * LP.Gravity
	local theta = s.LoopAngle
	local v = s.Speed + (-g * math.sin(theta) + input.Throttle * LP.Drive) * dt
	local fwd = loop.Entry.LookVector
	local up = loop.Entry.UpVector
	local right = loop.Entry.RightVector
	local tangent = (fwd * math.cos(theta) + up * math.sin(theta)).Unit
	-- out of speed, or too slow to stay on near the top: slide back down and out the way you came
	-- (dropping off upside down was a guaranteed crash inside the loop)
	local away = -math.cos(theta) -- 1 at the top
	if v < LP.RollBack or v * v / r < g * away * LP.Stick then
		s.Loop = nil
		s.LoopAngle = 0
		s.Position = loop.Entry.Position - fwd * 1.5
		s.RearY = s.Position.Y
		s.RearVy = 0
		s.Pitch = 0
		s.Speed = -math.clamp(math.sqrt(2 * g * r * (1 - math.cos(theta))), 1, 8)
		s.Velocity = fwd * (s.Speed * STUDS)
		push(events, "LoopFail")
		return
	end
	theta += v / r * dt
	if theta >= TAU then
		-- out the bottom, beside where we came in
		s.Loop = nil
		s.LoopAngle = 0
		local exit = loop.Entry.Position + fwd * 0.5 + right * loop.Shift
		s.Position = exit
		s.RearY = exit.Y
		s.RearVy = 0
		s.Pitch = 0
		s.Speed = v
		s.Velocity = fwd * (v * STUDS)
		push(events, "Loop", radiusStuds)
		return
	end
	s.LoopAngle = theta
	local center = loop.Entry.Position + up * radiusStuds
	s.Position = center + (-up * math.cos(theta) + fwd * math.sin(theta)) * radiusStuds + right * (loop.Shift * theta / TAU)
	s.Pitch = theta
	s.Speed = v
	s.Lean = 0
	s.Velocity = (tangent + right * (loop.Shift / (TAU * radiusStuds))) * (v * STUDS)
	s.WheelAngle = (s.WheelAngle + v / spec.WheelRadiusM * dt) % TAU
end

local function groundStep(s: State, spec: Spec, mode: Mode, input: Input, world: World, dt: number, events: { Event })
	local g = P.Gravity
	local m = spec.MassKg
	local v = s.Speed
	local kmh = math.abs(v) * 3.6
	local offroad = s.Offroad
	local grip = if offroad then spec.GripOff else spec.GripRoad
	local crr = if offroad then spec.CrrOff else spec.CrrRoad
	local riding = s.Crash <= 0
	local throttle = if riding then input.Throttle else 0
	s.Settle = math.max(0, s.Settle - dt)
	-- S is the rear brake; with Shift it's the front (full power, and what lifts a stoppie)
	s.FrontBraking = riding and input.Brake > 0 and input.Wheelie
	s.BrakeApplied = approach(s.BrakeApplied, if riding then input.Brake else 0, P.BrakeSqueeze * dt)
	local brake = s.BrakeApplied

	-- Battery management: a low pack limits power, an empty one cuts the motor
	local charge = if spec.BatteryWh > 0 then s.Battery / spec.BatteryWh else 0
	local bms = 1
	if s.Battery <= 0 then
		bms = 0
	elseif charge < Config.Battery.CriticalPower then
		bms = Config.Battery.CriticalPowerCap
	elseif charge < Config.Battery.LowPower then
		bms = Config.Battery.LowPowerCap
	end

	-- Rider: legs fade out above ~40 km/h (you can't spin that fast)
	local pedalling = spec.Pedals and throttle > 0 and v > -0.2
	local riderW = if pedalling then spec.RiderW * throttle * math.clamp((58 - kmh) / 18, 0, 1) else 0

	-- Motor
	local cap = spec.MotorW * mode.MaxPower * bms
	local wanted = 0
	if cap > 0 and v > -0.2 then
		if spec.Throttle then
			wanted = cap * throttle
		elseif pedalling then
			wanted = math.min(cap, riderW * mode.Assist)
		end
	end
	-- Assist fades over the last 2 km/h before the cut-off, like a real controller
	wanted *= math.clamp((spec.CutoffKmh - kmh) / 2, 0, 1)
	-- R locks the rear wheel (to drift, or to skid at low speed): a locked wheel takes no drive, so
	-- the controller cuts the motor rather than burn the pack for nothing
	local rearLocked = riding and input.Drift and s.Wheelie < 0.05
	if rearLocked then
		wanted = 0
	end
	local rampUp = spec.MotorW * (0.8 + 4 * mode.Response)
	if wanted > s.MotorPower then
		s.MotorPower = approach(s.MotorPower, wanted, rampUp * dt)
	else
		s.MotorPower = approach(s.MotorPower, wanted, spec.MotorW * 6 * dt)
	end

	local speedForForce = math.max(math.abs(v), 1.2)
	local motorForce = math.min(s.MotorPower / speedForForce, spec.WheelForceN * math.max(0.35, mode.MaxPower) * bms)
	local riderForce = math.min(riderW / speedForForce, spec.RiderForceN * throttle)
	local traction = grip * m * g * 0.62 -- weight on the rear tyre
	local drive = if rearLocked then 0 else math.min(motorForce + riderForce, traction)

	-- Resistances
	local aero = 0.5 * P.AirDensity * spec.CdA * v * math.abs(v)
	local roll = if math.abs(v) > 0.05 then crr * m * g * math.sign(v) else 0
	local grade = m * g * math.sin(s.Pitch)
	local accel = (drive - aero - roll - grade) / m

	-- Brakes (and walking the bike backwards from a stop)
	local brakeDecel = brake * spec.BrakeG * (if s.FrontBraking then 1 else P.RearBrakeShare) * g * math.min(1, grip / 0.85)
	if v > 0.05 then
		local before = v
		v = math.max(0, v + accel * dt - brakeDecel * dt)
		if brake > 0 and spec.Regen > 0 and s.Battery > 0 then
			local braking = math.max(0, before - v) / dt * m * before
			s.Battery = math.min(spec.BatteryWh, s.Battery + braking * spec.Regen * dt / 3600 * Config.Battery.DrainScale / Config.SpeedBoost ^ 3)
		end
	elseif v < -0.05 then
		if throttle > 0 then
			v = math.min(0, v + (brakeDecel + spec.BrakeG * g * throttle) * dt)
		else
			v = approach(v, -P.ReverseSpeed * brake, 2.5 * dt)
		end
	else
		if brake > 0 and throttle <= 0 and riding then
			v = approach(v, -P.ReverseSpeed * brake, 2.5 * dt)
		else
			v += math.max(0, accel) * dt
		end
	end
	if not riding then
		v = approach(v, 0, 7 * dt)
	end

	-- Battery drain
	if s.MotorPower > 0 then
		s.Battery = math.max(0, s.Battery - s.MotorPower / P.RiderEfficiency * dt / 3600 * Config.Battery.DrainScale / Config.SpeedBoost ^ 3)
	end

	-- Pedals and wheels
	local cadenceTarget = if pedalling and v > 0.3 then math.clamp(55 + kmh * 1.1, 0, 105) else 0
	s.Cadence = approach(s.Cadence, cadenceTarget, 220 * dt)
	s.CrankAngle = (s.CrankAngle + s.Cadence / 60 * TAU * dt) % TAU

	-- Steering
	local handsFactor = if input.NoHands then 0.45 elseif input.OneHand then 0.8 else 1
	local steerTarget = if riding then input.Steer * handsFactor else 0
	-- the bars ease toward the input (fast at first, settling in), slower at speed like a real bike
	local steerEase = TU.SteerRate / (1 + math.abs(v) / TU.SteerFadeSpeed)
	s.Steer += (steerTarget - s.Steer) * math.min(1, steerEase * dt)
	if math.abs(steerTarget - s.Steer) < 1e-3 then
		s.Steer = steerTarget
	end
	local steerMax = P.MaxSteer + (P.MinSteer - P.MaxSteer) * math.clamp(math.abs(v) / 22, 0, 1)
	s.SteerAngle = s.Steer * steerMax
	-- Walking pace: the bicycle's geometry (yaw = v·tanδ / wheelbase). Riding: the bars set a turn
	-- rate (carving, like the reference game), a little less on loose ground and at very high speed.
	local wheelbaseM = spec.Wheelbase / Config.VISUAL_STUDS_PER_METER
	local geometric = v * math.tan(s.Steer * P.MaxSteer) / wheelbaseM
	local gripScale = math.clamp(grip / 0.9, 0.55, 1.05)
	local carve = math.abs(s.Steer) * TU.Rate * gripScale / (1 + math.max(0, math.abs(v) - TU.FadeFrom) / TU.FadeOver)
	local wantedRate = math.sign(geometric) * math.min(math.abs(geometric), carve)
	if s.Wheelie > 0.08 or s.Stoppie > 0.05 then
		wantedRate *= 0.55
	end
	-- the bike rolls into a turn and back out of it: the turn rate follows the bars through a
	-- critically damped spring (an S-curve in and out instead of a snap), stiffer at walking pace
	local w = TU.RollIn + (TU.RollInSlow - TU.RollIn) * math.clamp(1 - math.abs(v) / 8, 0, 1)
	s.TurnRateVel += (w * w * (wantedRate - s.TurnRate) - 2 * w * s.TurnRateVel) * dt
	s.TurnRate += s.TurnRateVel * dt
	local yawRate = s.TurnRate
	local lateralMax = grip * g * 0.95
	-- Drift: the rear brake is locked, so the tail is free to swing out. The steering throws the
	-- heading round faster than grip allows, while the direction of travel catches up only as fast
	-- as the tyres can bend it (lateral grip / speed). The gap is the slip angle; sliding scrubs speed.
	-- the tail only swings out at speed; slower than that a locked rear just skids you to a stop
	local drifting = rearLocked and v > DR.MinSpeed
	if drifting then
		-- the slide owns the heading; turning picks up smoothly from straight after it
		s.TurnRate, s.TurnRateVel = 0, 0
		-- the tail swings out at the steering, tapering off toward the hold angle: holding the key
		-- keeps a big, steady slide (bigger the faster you go) instead of spinning you out
		local swing = input.Steer * handsFactor * (DR.YawRate + DR.YawPerSpeed * v)
		if -swing * s.Slip > 0 then
			swing *= math.max(0, 1 - (math.abs(s.Slip) / DR.HoldSlip) ^ 2)
		end
		s.Yaw -= swing * dt
		local catchUp = lateralMax * DR.Grip / math.max(v, 1)
		s.TravelYaw += math.clamp(wrap(s.Yaw - s.TravelYaw), -catchUp * dt, catchUp * dt)
		s.Slip = wrap(s.Yaw - s.TravelYaw)
		v = math.max(0, v - (DR.LockedDecel + DR.SlideDecel * math.abs(math.sin(s.Slip))) * g * dt)
	else
		if rearLocked and v > 0 then
			v = math.max(0, v - DR.LockedDecel * g * dt)
		end
		s.Yaw -= yawRate * dt
		s.TravelYaw += wrap(s.Yaw - s.TravelYaw) * math.min(1, DR.Recover * dt)
		-- carving scrubs a little speed off
		if v > 0 then
			v = math.max(0, v - TU.Scrub * math.abs(v * yawRate) * dt)
		end
		s.Slip = wrap(s.Yaw - s.TravelYaw)
	end
	if s.DriftActive then
		s.DriftTime += dt
		s.DriftAngle = math.max(s.DriftAngle, math.abs(s.Slip))
		if not drifting or s.Crash > 0 then
			s.DriftActive = false
			push(events, "DriftEnd", s.DriftTime, math.deg(s.DriftAngle), if s.Crash > 0 then "Failed" else nil)
		end
	elseif drifting and math.abs(s.Slip) > DR.StartSlip then
		s.DriftActive = true
		s.DriftTime = 0
		s.DriftAngle = math.abs(s.Slip)
		push(events, "DriftStart")
	end

	local leanTarget = -math.atan(v * yawRate / g) * TU.LeanScale
	if drifting then
		-- lean into the slide, opposite the tail
		leanTarget = math.clamp(s.Slip * 0.6, -0.5, 0.5)
	end
	if input.NoHands and riding and math.abs(v) > 0.5 then
		leanTarget += noise(s) * 0.06 * math.clamp(6 / math.abs(v), 0.4, 2)
	end
	if not riding then
		leanTarget = s.CrashSide * 1.35
	end
	leanTarget = math.clamp(leanTarget, -1.4, 1.4)
	if riding then
		leanTarget = math.clamp(leanTarget, -TU.MaxLean, TU.MaxLean)
	end
	s.Lean = approach(s.Lean, leanTarget, (if riding then TU.LeanRate else 4) * dt)

	-- Stoppie: brake hard with the wheelie key held at speed and balance on the front wheel. The
	-- rear rises toward a balance angle; more brake pushes it further; too far and you go over.
	local stoppieWanted = riding and input.Wheelie and brake > 0.5 and s.Wheelie <= 0.02 and (v > ST.MinSpeed or (s.Stoppie > 0.05 and v > 0.5))
	if stoppieWanted then
		local target = ST.Target + ST.BrakeTrim * (brake - 0.5)
		local stiffness = ST.Stiffness
		local alpha = stiffness * (target - s.Stoppie) - 2 * math.sqrt(stiffness) * 0.6 * s.StoppieRate + (ST.Noise + ST.NoisePerSecond * s.StoppieTime) * noise(s)
		s.StoppieRate += alpha * dt
	elseif s.Stoppie > 0 then
		s.StoppieRate -= ST.DropAccel * dt
	else
		s.StoppieRate = 0
	end
	s.Stoppie += s.StoppieRate * dt
	if s.Stoppie <= 0 then
		s.Stoppie = 0
		s.StoppieRate = math.max(0, s.StoppieRate)
	end
	if s.Stoppie > ST.Over then
		crash(s, events, "Over the bars")
		s.Stoppie = 0
		s.StoppieRate = 0
	end
	if s.Stoppie > ST.Counted and not s.StoppieActive and riding then
		s.StoppieActive = true
		s.StoppieTime = 0
		push(events, "StoppieStart")
	end
	if s.StoppieActive then
		s.StoppieTime += dt
		if s.Stoppie <= 0.03 or not riding then
			s.StoppieActive = false
			push(events, "StoppieEnd", s.StoppieTime, if riding then 0 else 1)
		end
	end

	-- Wheelie
	if riding and not stoppieWanted then
		local canLift = v > WH.MinSpeed
		local stillUp = v > WH.DropSpeed
		local alpha: number
		local stiffness = WH.Stiffness * math.max(0.25, spec.WheeliePop)
		local damping = 2 * math.sqrt(stiffness) * WH.Damping
		local liftable = bms > 0 or spec.Pedals -- a pedal bike can still be manualled with a flat battery
		if input.Wheelie and liftable and (canLift or (s.Wheelie > 0.05 and stillUp)) then
			local target = WH.Target + (if throttle > 0 then WH.ThrottleTrim else WH.CoastTrim) + WH.BrakeTrim * brake
			local wobble = (WH.Noise + WH.NoisePerSecond * s.WheelieTime + WH.NoisePerKmh * kmh) * noise(s)
			-- a real wheelie is balanced, not parked: past the balance point gravity tips it further
			-- (up toward looping out, or back down), so holding the key alone doesn't hold it. The
			-- rider keeps it with the throttle (lifts) and the rear brake (drops).
			local tip = WH.Unstable * stiffness * math.max(0, s.Wheelie - WH.Balance)
			alpha = stiffness * (target - s.Wheelie) - damping * s.WheelieRate + wobble + tip
		elseif s.Wheelie > 0 then
			alpha = -WH.DropAccel - damping * 0.5 * s.WheelieRate - (if brake > 0 then 4 else 0)
		else
			alpha = 0
			s.WheelieRate = 0
		end
		s.WheelieRate += alpha * dt
		s.Wheelie += s.WheelieRate * dt
		if s.Wheelie <= 0 then
			s.Wheelie = 0
			s.WheelieRate = math.max(0, s.WheelieRate)
		end
		if s.Wheelie > WH.LoopOut then
			crash(s, events, "Looped out")
		end
	end
	if s.Wheelie > WH.Counted and not s.WheelieActive and s.Crash <= 0 then
		s.WheelieActive = true
		s.WheelieTime = 0
		push(events, "WheelieStart")
	end
	if s.WheelieActive then
		if s.Wheelie <= 0.03 then
			endWheelie(s, events, false)
		else
			s.WheelieTime += dt
		end
	end

	-- Hands (what the pose shows; tricks only count while moving)
	s.Hands = if not riding then 0 elseif input.NoHands then 2 elseif input.OneHand then 1 else 0

	-- Move along the ground (along the travel direction; the wheels probe along the heading)
	local dir = heading(s.Yaw)
	local moveDir = heading(s.TravelYaw)
	local horizontal = v * math.cos(s.Pitch) * STUDS * dt
	local delta = moveDir * horizontal
	local moved, normal, into, hitKind = sweepMove(s, spec, world, delta)
	if hitKind == "Slope" then
		moved = delta
	end
	if normal then
		impact(s, events, math.abs(v), into, hitKind)
		v *= (1 - into) * 0.92
		-- Glance off: turn toward the wall's tangent
		local moveDir = delta.Unit
		local tangent = moveDir - normal * moveDir:Dot(normal)
		if tangent.Magnitude > 0.05 and into < 0.85 then
			local tangentYaw = BikePhysics.YawOf(if v >= 0 then tangent.Unit else -tangent.Unit)
			s.Yaw += wrap(tangentYaw - s.Yaw) * 0.5
			s.TravelYaw += wrap(tangentYaw - s.TravelYaw) * 0.5
		end
	end
	local target = s.Position + moved

	-- Ground under the new position. The rear tyre is the reference: it is the last wheel to leave
	-- a lip, and its vertical speed comes from the surface slope under it (from the hit normal, so a
	-- curb's step doesn't read as a launch).
	-- The rays start high enough above each tyre to find a face as steep as MaxRidePitch under it
	-- (a ray that starts inside a ramp misses it, and the pitch flickered on steep faces)
	local half = spec.Wheelbase / 2
	local above = P.StepHeight + 0.3 + half * math.tan(P.MaxRidePitch)
	local rearHit = world.Down(target - dir * half + UP * above, above + 6)
	local frontHit = world.Down(target + dir * half + UP * above, above + 6)
	if rearHit and rearHit.Position.Y - s.RearY > P.StepHeight + half * 2 * math.max(0, math.sin(s.Pitch)) then
		-- Too tall to roll up: a low obstacle the body sweep didn't catch. Stop.
		v = 0
		target = s.Position
		rearHit = world.Down(target - dir * half + UP * above, above + 6)
		frontHit = world.Down(target + dir * half + UP * above, above + 6)
	end
	-- the front tyre meeting a face too steep to ride (> MaxRidePitch) from (nearly) level ground:
	-- the end or side of something (the back of a thick ramp, a wall). It stops you; only a face you
	-- were already climbing (a quarter pipe's curve) carries on up and launches.
	local function steepness(hit: Hit?): number
		if not hit then
			return 0
		end
		local n = hit.Normal
		return math.atan(-n:Dot(dir) / math.max(n.Y, 0.05))
	end
	if v > 0 and frontHit and steepness(frontHit) > P.MaxRidePitch and s.Pitch < steepness(frontHit) - P.VertEntry and frontHit.Position.Y - s.RearY > P.StepHeight then
		impact(s, events, math.abs(v), 1, "Wall")
		v = 0
		target = s.Position
		rearHit = world.Down(target - dir * half + UP * above, above + 6)
		frontHit = world.Down(target + dir * half + UP * above, above + 6)
	end
	local rearSupport = rearHit or frontHit
	local horizontalSpeed = v * math.cos(s.Pitch)
	-- where the rear tyre would be if the slope it was on carried on: the rise for the ground
	-- actually covered this step (the step follows the bike's pitch, not the rear's slope, so
	-- RearVy·dt overshot on a concave face and read a quarter pipe as a lip: takeoff/land flicker)
	local sinRear = math.clamp(s.RearVy / math.max(math.abs(v), 0.1), -0.99, 0.99)
	local rise = math.abs(horizontal) * sinRear / math.sqrt(1 - sinRear * sinRear)
	local predicted = s.RearY + rise - 0.5 * g * STUDS * dt * dt
	local tolerance = if s.RearVy > 0.5 then 0.03 else P.SnapDistance

	-- Too steep to keep riding (a quarter pipe's top): you leave it along the surface, like a lip
	local steepPitch: number? = nil
	if rearSupport and v > 0 then
		local n = rearSupport.Normal
		local surfacePitch = math.atan(-n:Dot(dir) / math.max(n.Y, 0.05))
		if surfacePitch > P.MaxRidePitch then
			if s.Pitch > surfacePitch - P.VertEntry then
				steepPitch = math.min(surfacePitch, 1.45)
			else
				-- a steep face met from (nearly) level ground isn't a quarter pipe you rode up: it's
				-- the end or side of something (the back of a ramp, a wall). Stop at it.
				impact(s, events, math.abs(v), 1, "Wall")
				v = 0
				target = s.Position
				rearHit = world.Down(target - dir * half + UP * above, above + 6)
				frontHit = world.Down(target + dir * half + UP * above, above + 6)
				rearSupport = rearHit or frontHit
			end
		end
	end

	-- under the rear, a face falling away steeper than anything ridable (the end face just below a
	-- ramp's lip) means the rear is off the lip: leave with the ramp's own lift, not that face's
	-- (a face you're already riding down at about its angle, a quarter pipe's top on the way back,
	-- is just steep ground)
	local cliff = rearSupport ~= nil and steepness(rearSupport) < -P.MaxRidePitch and s.Pitch > steepness(rearSupport) + P.VertEntry
	-- dropping in: the front tyre is planted on a ridable face below and the rear's ground is where
	-- the bike's own line through the front puts it (over a deck's edge or a coping): stay down
	local anchored = false
	if rearSupport and frontHit and rearSupport ~= frontHit and s.Pitch < -0.15 and math.abs(steepness(frontHit)) < P.MaxRidePitch then
		local alongLine = frontHit.Position.Y - spec.Wheelbase * math.tan(s.Pitch)
		anchored = rearSupport.Position.Y < alongLine + 1.0 and rearSupport.Position.Y > alongLine - 2.0
	end
	if not rearSupport or steepPitch or cliff or (rearSupport.Position.Y < predicted - tolerance and not anchored) then
		-- Off the lip: keep the momentum the rear tyre had up the slope
		local vy = math.max(s.RearVy, -1)
		local along = horizontalSpeed
		if steepPitch then
			-- out of a quarter pipe you go up, not over the coping: you come back down the face
			vy = v * math.sin(steepPitch)
			along = v * math.cos(steepPitch) * P.VertCarry
			s.Pitch = steepPitch
			predicted = math.max(predicted, (rearSupport :: Hit).Position.Y)
		elseif cliff then
			predicted = math.max(predicted, (rearSupport :: Hit).Position.Y)
		end
		s.VertLaunch = steepPitch
		s.Grounded = false
		s.VerticalSpeed = vy - g * dt
		s.AirVelocity = moveDir * (along * STUDS)
		s.Position = Vector3.new(target.X, predicted + half * math.sin(s.Pitch), target.Z)
		s.Pitch += s.Wheelie
		s.Wheelie = 0
		s.WheelieRate = 0
		endWheelie(s, events, false)
		s.AirTime = 0
		s.AirPitch = 0
		s.AirYaw = 0
		s.AirPitchRate = 0
		s.AirYawRate = 0
		s.AirHands = false
		s.AirTricks = 0
		s.Stoppie = 0
		s.StoppieRate = 0
		push(events, "Takeoff", math.max(0, vy))
	else
		local yr = rearSupport.Position.Y
		local surfaceNormal = rearSupport.Normal
		local slopeTan = -surfaceNormal:Dot(dir) / math.max(surfaceNormal.Y, 0.25)
		local surfacePitch = math.atan(slopeTan)
		s.RearY = yr
		-- rising along the surface at the bike's speed (not v·tan: that fired steep ramps out twice
		-- as fast as you rode up them)
		s.RearVy = v * math.sin(surfacePitch)
		if frontHit and s.Pitch < surfacePitch - 0.05 then
			-- the front is already down a steeper face (dropping in off a deck, over a crest): the
			-- rear follows the bike's line off the edge, not the flat it is leaving
			s.RearVy = v * math.sin(s.Pitch)
		end
		-- The front follows its own ground unless it's hanging over a lip (then the bike holds its pitch)
		local pitchTarget = math.atan(slopeTan)
		if frontHit and rearHit then
			local yf = frontHit.Position.Y
			local geometric = math.atan2(yf - yr, spec.Wheelbase)
			local expected = yr + spec.Wheelbase * math.tan(s.Pitch)
			-- the front's ground is part of the same slope (its own surface, or the rear's, tilts
			-- about as much as the line between the tyres): follow it, downhill as well as up. Only a
			-- drop that matches neither (the front out over a lip) holds the pitch.
			local fn = frontHit.Normal
			local frontSlope = math.atan(-fn:Dot(dir) / math.max(fn.Y, 0.05))
			-- (a ridable slope: a ramp's end face just under its lip reads as a cliff, not a slope)
			local ridable = math.abs(geometric) < P.MaxRidePitch
			local onSlope = ridable and ((math.abs(frontSlope) < P.MaxRidePitch and math.abs(frontSlope - geometric) < 0.2) or (math.abs(surfacePitch) < P.MaxRidePitch and math.abs(surfacePitch - geometric) < 0.2))
			if steepness(frontHit) < -P.MaxRidePitch and s.Pitch > steepness(frontHit) + P.VertEntry then
				-- the front ray found a ramp's end face below its lip: the front is off the lip
				pitchTarget = s.Pitch
			elseif yf > expected - 1.0 or onSlope then
				pitchTarget = geometric
			else
				pitchTarget = s.Pitch
			end
		elseif not frontHit and math.abs(surfacePitch) > P.MaxRidePitch then
			pitchTarget = s.Pitch
		end
		-- follow the ground closely: the height tracks the rear tyre exactly, so a lagging pitch
		-- buried the front wheel in the foot of every ramp (worse the bigger the bike is drawn).
		-- After a landing on the back wheel the front comes down at its own (gravity) pace.
		-- the pitch can change only as fast as the tyres roll over what's under them: a ramp's face
		-- quickly, the edge of a step (a kerb, a mat) over about a tyre's width of travel
		local rolling = math.abs(horizontal) / dt * P.StepClimb / spec.Wheelbase
		local rate = if s.Settle <= 0 then math.clamp(rolling, 1.5, 24) elseif s.Pitch > pitchTarget then P.FrontDropRate else P.RearDropRate
		s.Pitch = approach(s.Pitch, pitchTarget, rate * dt)
		-- sit on whichever tyre is lower than the ground line would put it: the rear normally, the
		-- front while a nose-first landing brings the rear down (so neither tyre sinks in)
		local y = yr + half * math.sin(s.Pitch)
		if s.Settle > 0 and frontHit and s.Pitch < pitchTarget then
			y = math.max(y, frontHit.Position.Y - half * math.sin(s.Pitch))
		end
		s.Position = Vector3.new(target.X, y, target.Z)
		local kind = rearSupport.Kind
		if frontHit and OFFROAD[frontHit.Kind] then
			kind = frontHit.Kind
		end
		s.Surface = kind
		s.Offroad = OFFROAD[kind] == true
		if kind == "Water" then
			-- rolled off into the bay: it sinks (the controller puts it back on the shore)
			if not s.Wet then
				s.Wet = true
				push(events, "Splash")
			end
			v *= math.max(0, 1 - 6 * dt)
		end
		if kind == "Spikes" and s.Flat <= 0 then
			s.Flat = Config.Police.FlatTime
			push(events, "Spiked")
		end
	end

	-- a flat tyre (spike strip) drags the bike down to a crawl
	if s.Flat > 0 then
		s.Flat = math.max(0, s.Flat - dt)
		local cap = Config.Police.FlatKmh / 3.6
		if v > cap then
			v = math.max(cap, v - 6 * dt)
		end
	end
	s.Speed = v
	s.Distance += math.abs(v) * dt
	s.WheelAngle = (s.WheelAngle + v / spec.WheelRadiusM * dt) % TAU
	if s.Grounded then
		s.Velocity = moveDir * (v * math.cos(s.Pitch) * STUDS) + UP * (v * math.sin(s.Pitch) * STUDS)
	else
		s.Velocity = s.AirVelocity + UP * (s.VerticalSpeed * STUDS)
	end
end

local function land(s: State, spec: Spec, input: Input, world: World, groundY: number, groundPitch: number, kind: string, events: { Event })
	local flips = math.floor((math.abs(s.AirPitch) + 1.1) / TAU)
	local spins = math.floor((math.abs(s.AirYaw) + 1.0) / TAU)
	local pitchError = wrap(s.Pitch - groundPitch)
	local horizontal = Vector3.new(s.AirVelocity.X, 0, s.AirVelocity.Z)
	local headingError = 0
	if horizontal.Magnitude > 2 then
		headingError = math.abs(wrap(BikePhysics.YawOf(horizontal.Unit) - s.Yaw))
	end
	local backwards = headingError > math.pi / 2
	local airTime = s.AirTime
	-- back down a quarter pipe after the automatic turn: always rides away
	local fakie = s.FakieHold == true
	s.VertLaunch = nil
	s.FakieHold = nil
	s.Grounded = true
	s.Position = Vector3.new(s.Position.X, groundY, s.Position.Z)
	s.RearY = groundY - spec.Wheelbase / 2 * math.sin(groundPitch)
	s.RearVy = 0
	s.Surface = kind
	s.Offroad = OFFROAD[kind] == true
	local _ = world

	if kind == "Water" then
		-- a jump into the bay
		s.Pitch = groundPitch
		s.Speed = 0
		s.TrickExt = 0
		s.TrickName = ""
		s.BarSpin = 0
		if not s.Wet then
			s.Wet = true
			push(events, "Splash")
		end
		return
	end
	if s.Crash > 0 then
		s.Pitch = groundPitch
		s.Speed = horizontal.Magnitude / STUDS * 0.4
		return
	end

	-- Short drops (kerbs, bumps) are forgiving: only real jumps are judged strictly. Landing on the
	-- back wheel with the wheelie key held just carries on the wheelie.
	local short = airTime < 0.45
	-- the foam pit catches anything
	if kind == "Foam" then
		s.TrickExt = 0
		s.TrickName = ""
		s.BarSpin = 0
		s.Settle = 0.4
		s.Speed = horizontal.Magnitude / STUDS * 0.25
		push(events, "Land", airTime, flips, "Foam")
		if flips > 0 then
			push(events, "Flip", flips)
		end
		if spins > 0 then
			push(events, "Spin", spins)
		end
		return
	end
	-- still stretched out in a trick, or the bars still spinning: you land on your face
	local tucked = s.TrickExt < AT.LandOut and (s.BarSpin <= 0 or s.BarSpin > 0.8)
	s.TrickExt = 0
	s.TrickName = ""
	s.BarSpin = 0
	if not tucked then
		s.Pitch = groundPitch
		s.Speed = horizontal.Magnitude / STUDS * 0.5
		crash(s, events, "Didn't pull it back")
		push(events, "Land", airTime, flips, "Crash")
		return
	end
	-- (no rescue for a bike that's tumbled: much past the tolerance, it crashes and tumbles on)
	local tolerance = spec.Landing * (if short then 1.6 elseif airTime < 0.8 then 1.15 else 1) + math.abs(groundPitch) * 0.4
	if fakie then
		pitchError = 0
		headingError = 0
		backwards = false
	end
	local headingTolerance = P.LandingHeading * (if short then 1.8 else 1)
	if input.Wheelie and pitchError > 0 and pitchError < WH.LoopOut then
		tolerance = math.max(tolerance, WH.LoopOut)
	end
	if math.abs(pitchError) > tolerance or (headingError > headingTolerance and not backwards) or (backwards and headingError < math.pi - headingTolerance) then
		s.Pitch = groundPitch
		s.Speed = horizontal.Magnitude / STUDS * 0.5
		crash(s, events, if math.abs(pitchError) > tolerance then "Bad landing" else "Sideways landing")
		push(events, "Land", airTime, flips, "Crash")
		return
	end

	-- the speed you carry is the whole velocity along the ground you land on: dropping onto a down
	-- slope (a landing ramp, back down a quarter pipe) keeps the fall's speed, an up slope eats it
	local along = horizontal.Magnitude / STUDS * math.cos(headingError) * math.cos(groundPitch) - s.VerticalSpeed * math.sin(-groundPitch)
	along = math.max(0, along)
	if backwards then
		-- Landed a 180: keep rolling backwards and let the rider stop
		along = -horizontal.Magnitude / STUDS * math.abs(math.cos(headingError)) * 0.5
	end
	local softness = 1 - 0.35 * (math.abs(pitchError) / tolerance) ^ 2
	s.Speed = along * softness
	if input.Wheelie and pitchError > 0.12 and pitchError < WH.LoopOut then
		-- Landed rear wheel first with the key held: roll straight into a wheelie
		s.Pitch = groundPitch
		s.Wheelie = pitchError
		s.WheelieRate = 0
	elseif math.abs(wrap(s.Pitch - groundPitch)) > 0.02 then
		-- one wheel first: the other comes down over the next moment instead of snapping flat
		s.Settle = 0.4
	else
		s.Pitch = groundPitch
	end
	local clean = math.abs(pitchError) < 0.2 and headingError < 0.25
	push(events, "Land", airTime, flips, if clean then "Clean" else "Sketchy")
	if spins > 0 then
		push(events, "Spin", spins)
	end
	if flips > 0 then
		push(events, "Flip", flips)
	end
	if s.AirHands and airTime >= P.MinAirTime then
		push(events, "NoHander", airTime)
	end
end

local function airStep(s: State, spec: Spec, input: Input, world: World, dt: number, events: { Event })
	local g = P.Gravity
	s.AirTime += dt
	s.VerticalSpeed -= g * dt
	-- no drifting in the air: land facing where you're going
	s.TravelYaw = s.Yaw
	s.Slip = 0
	if s.DriftActive then
		s.DriftActive = false
		push(events, "DriftEnd", s.DriftTime, math.deg(s.DriftAngle))
	end
	local riding = s.Crash <= 0

	-- Out of a quarter pipe: at the top, turn round to face back down the face you came up
	local vert = s.VertLaunch
	if vert and s.VerticalSpeed <= 0 then
		s.VertLaunch = nil
		s.Yaw = wrap(s.Yaw + math.pi)
		s.TravelYaw = s.Yaw
		s.Pitch = -vert * 0.85
		s.AirPitchRate = 0
		s.AirYawRate = 0
		s.AirVelocity = heading(s.Yaw) * 5 -- drift back over the face, so both tyres come down on it
		s.FakieHold = true
		push(events, "Fakie")
	end

	-- Pitch: pull back to rotate (backflip), brake to push the nose down, otherwise ease toward a
	-- landing attitude that follows the trajectory (held still on the way up a quarter pipe and
	-- back down it)
	local control = spec.AirControl
	local pitchRateTarget: number
	if s.VertLaunch or s.FakieHold then
		pitchRateTarget = 0
	elseif riding and input.Wheelie then
		pitchRateTarget = P.AirPitchRate * control
	elseif riding and input.Brake > 0 then
		pitchRateTarget = -P.AirPitchRate * 0.6 * control
	else
		local horizontal = s.AirVelocity.Magnitude / STUDS
		local trajectory = math.clamp(math.atan2(s.VerticalSpeed, math.max(horizontal, 1)) * 0.5, -0.35, 0.3)
		local limit = P.AirPitchRate * control
		pitchRateTarget = math.clamp(wrap(trajectory - s.Pitch) * 4, -limit, limit)
	end
	s.AirPitchRate = approach(s.AirPitchRate, pitchRateTarget, 26 * dt)
	s.Pitch += s.AirPitchRate * dt
	s.AirPitch += s.AirPitchRate * dt
	if s.Pitch > math.pi then
		s.Pitch -= TAU
	elseif s.Pitch < -math.pi then
		s.Pitch += TAU
	end

	-- Spin: steer to rotate, otherwise drift back toward the direction of travel
	local yawRateTarget: number
	if riding and math.abs(input.Steer) > 0.1 then
		yawRateTarget = -input.Steer * P.AirSpinRate * control
	else
		local horizontal = Vector3.new(s.AirVelocity.X, 0, s.AirVelocity.Z)
		yawRateTarget = 0
		if horizontal.Magnitude > 2 then
			local travelYaw = BikePhysics.YawOf(horizontal.Unit)
			local err = wrap(travelYaw - s.Yaw)
			if math.abs(err) < math.pi / 2 then
				yawRateTarget = err * 3 -- ease toward the travel direction
			end
		end
	end
	s.AirYawRate = approach(s.AirYawRate, yawRateTarget, 18 * dt)
	s.Yaw += s.AirYawRate * dt
	s.AirYaw += s.AirYawRate * dt

	if riding and (input.NoHands or input.OneHand) then
		s.AirHands = true
	end
	s.Hands = if not riding then 0 elseif input.NoHands then 2 elseif input.OneHand then 1 else 0
	s.Lean = approach(s.Lean, if riding then 0 else s.CrashSide * 1.0, 2 * dt)

	-- Air tricks: hold a trick key to throw the body out (it counts after a moment fully out), let
	-- go to tuck back in. One at a time; switching means tucking first.
	local want = if riding then input.Trick else nil
	-- the ground coming up: tuck in (and don't start a barspin) in time to land on the bike, so a key
	-- held too long never means a bail
	-- Seconds until touchdown, rising or falling, onto the highest ground under either wheel or where
	-- the bike will be by the time a tuck finishes (so a gap jump onto a raised deck counts the deck)
	local landingIn = math.huge
	do
		local dir = heading(s.Yaw)
		local half = spec.Wheelbase / 2
		local ahead = Vector3.new(s.AirVelocity.X, 0, s.AirVelocity.Z) * (AT.InTime * 1.4 + 0.03)
		local highest: number? = nil
		for _, at in { s.Position, s.Position + dir * half, s.Position - dir * half, s.Position + ahead + dir * half } do
			local below = world.Down(at + UP * 0.5, 60)
			if below and (highest == nil or below.Position.Y > highest) then
				highest = below.Position.Y
			end
		end
		if highest then
			local h = math.max(0, s.Position.Y - highest) / STUDS
			local down = -s.VerticalSpeed
			landingIn = (math.sqrt(down * down + 2 * P.Gravity * h) - down) / P.Gravity
		end
	end
	if landingIn < AT.InTime * 1.4 + 0.03 then
		want = nil
	end
	if want and (s.TrickName == "" or s.TrickName == want) then
		if s.TrickName ~= want then
			s.TrickName = want
			s.TrickHold = 0
			s.TrickCounted = false
		end
		s.TrickExt = math.min(1, s.TrickExt + dt / AT.OutTime)
		if s.TrickExt >= 1 then
			s.TrickHold += dt
			if s.TrickHold >= AT.HoldTime and not s.TrickCounted then
				s.TrickCounted = true
				s.AirTricks += 1
				push(events, "AirTrick", s.TrickHold, s.AirTricks, s.TrickName)
			end
		end
	else
		s.TrickExt = math.max(0, s.TrickExt - dt / AT.InTime)
		if s.TrickExt <= 0 then
			s.TrickName = ""
		end
	end
	-- Barspin: a press flicks the bars round once
	if riding and input.Barspin and not s.BarspinHeld and s.BarSpin <= 0 and landingIn > AT.BarspinTime then
		s.BarSpin = 0.001
	end
	s.BarspinHeld = input.Barspin
	if s.BarSpin > 0 then
		s.BarSpin += dt / AT.BarspinTime
		if s.BarSpin >= 1 then
			s.BarSpin = 0
			s.AirTricks += 1
			push(events, "AirTrick", AT.BarspinTime, s.AirTricks, "Barspin")
		end
	end
	s.MotorPower = approach(s.MotorPower, 0, spec.MotorW * 6 * dt)
	s.Cadence = approach(s.Cadence, 0, 200 * dt)

	-- Horizontal move with collisions
	local delta = s.AirVelocity * dt
	local moved, normal, into, hitKind = sweepMove(s, spec, world, delta)
	if hitKind == "Slope" then
		-- up against a ramp face: stop going into it (no bail), gravity brings you down onto it
		s.AirVelocity *= 0.5
	end
	if normal then
		impact(s, events, s.AirVelocity.Magnitude / STUDS, into, hitKind)
		s.AirVelocity = (s.AirVelocity - normal * s.AirVelocity:Dot(normal)) * 0.85
	end

	-- Vertical move and landing
	local fall = s.VerticalSpeed * STUDS * dt
	local newY = s.Position.Y + fall
	local target = Vector3.new(s.Position.X + moved.X, newY, s.Position.Z + moved.Z)
	if s.VerticalSpeed <= 0 then
		local above = 1.2
		local groundY, slope, kind = probe(world, Vector3.new(target.X, s.Position.Y, target.Z), s.Yaw, spec, above, above - fall + 0.15)
		if groundY and groundY > s.Position.Y + 0.35 then
			-- "ground" above where the bike already was: the tyres straddle a step's face (one on
			-- top, one below). Not a landing: keep falling past the face onto the lower side.
			groundY = nil
		end
		local under = if groundY and groundY >= newY - 0.02 then world.Down(Vector3.new(target.X, groundY + 2, target.Z), 4) else nil
		if groundY and groundY >= newY - 0.02 and under and under.Normal.Y < math.cos(P.MaxRidePitch) then
			-- a face too steep to ride (the back of a ramp, a wall's slope): you can't land on it,
			-- you slide off it, pushed out along it, and land on whatever is below
			local out = Vector3.new(under.Normal.X, 0, under.Normal.Z)
			if out.Magnitude > 1e-3 then
				s.AirVelocity = Vector3.new(s.AirVelocity.X, 0, s.AirVelocity.Z) * 0.5 + out.Unit * (P.Gravity * STUDS * 0.25)
			end
			s.VerticalSpeed = math.min(s.VerticalSpeed, 0)
			s.Position = Vector3.new(target.X, groundY + 0.05, target.Z)
			s.Velocity = s.AirVelocity + UP * (s.VerticalSpeed * STUDS)
			return
		end
		if groundY and groundY >= newY - 0.02 then
			-- the slope you land on, from rays that start well above both tyres (the short landing
			-- rays start inside a steep face and miss it, which read a quarter pipe as flat)
			-- (only when the ground itself is tilted that way: across a step, a deck's edge, the
			-- line between the tyres isn't a slope)
			local high = P.StepHeight + 0.3 + spec.Wheelbase / 2 * math.tan(1.2)
			local dir = heading(s.Yaw)
			local half = spec.Wheelbase / 2
			local at = Vector3.new(target.X, groundY, target.Z)
			local fh = world.Down(at + dir * half + UP * high, 2 * high + 4)
			local rh = world.Down(at - dir * half + UP * high, 2 * high + 4)
			if fh and rh then
				local line = math.atan2(fh.Position.Y - rh.Position.Y, spec.Wheelbase)
				local function tilt(hit: Hit): number
					return math.atan(-hit.Normal:Dot(dir) / math.max(hit.Normal.Y, 0.05))
				end
				if math.abs(tilt(fh) - line) < 0.3 or math.abs(tilt(rh) - line) < 0.3 then
					slope = line
					-- and sit between the tyres on it (the short rays may have found only one)
					groundY = math.min((fh.Position.Y + rh.Position.Y) / 2, s.Position.Y + 0.35)
				end
			end
			s.Position = Vector3.new(target.X, groundY, target.Z)
			land(s, spec, input, world, groundY, slope, kind, events)
			s.Velocity = heading(s.Yaw) * (s.Speed * STUDS)
			return
		end
	end
	s.Position = target
	if s.Position.Y < -300 then
		push(events, "Fell")
	end
	s.Velocity = s.AirVelocity + UP * (s.VerticalSpeed * STUDS)
	s.WheelAngle = (s.WheelAngle + s.AirVelocity.Magnitude / STUDS / spec.WheelRadiusM * dt * 0.6) % TAU
end

-- Advances the bike by dt seconds. Returns what happened (tricks, crashes, landings).
function BikePhysics.Step(s: State, spec: Spec, mode: Mode, input: Input, world: World, dt: number): { Event }
	local events: { Event } = {}
	dt = math.clamp(dt, 0, 0.1)
	if dt <= 0 then
		return events
	end
	s.Time += dt
	-- for the suspension: where the bike was before anything this frame (a hop leaves the ground below)
	local wasGround = s.Grounded or s.Loop ~= nil
	local wasLoop = s.Loop ~= nil
	local fallBefore = s.VerticalSpeed

	if s.Crash > 0 then
		s.Crash -= dt
		if s.Crash <= 0 then
			s.Crash = 0
			push(events, "Recover")
		end
	end

	-- Bunny hop: hold to preload, release to pop
	if input.Hop and s.Crash <= 0 then
		s.HopCharge = math.min(1, s.HopCharge + dt / Config.Hop.ChargeTime)
		s.HopHeld = true
	elseif s.HopHeld then
		s.HopHeld = false
		if s.Grounded and s.Crash <= 0 then
			local charge = Config.Hop.MinFraction + (1 - Config.Hop.MinFraction) * s.HopCharge
			local dir = heading(s.Yaw)
			local along = s.Speed * math.cos(s.Pitch)
			s.Grounded = false
			s.VerticalSpeed = spec.HopSpeed * charge + math.max(0, s.Speed * math.sin(s.Pitch))
			s.AirVelocity = dir * (along * STUDS)
			s.Pitch += s.Wheelie
			s.Wheelie = 0
			s.WheelieRate = 0
			endWheelie(s, events, false)
			s.AirTime = 0
			s.AirPitch = 0
			s.AirYaw = 0
			s.AirPitchRate = 0.6 -- a hop lifts the front first
			s.AirYawRate = 0
			s.AirHands = false
			s.AirTricks = 0
			push(events, "Hop", charge)
		end
		s.HopCharge = 0
	end

	-- rolling onto a loop's entry?
	local findLoop = world.Loop
	if s.Grounded and not s.Loop and findLoop and s.Speed > 2 and s.Crash <= 0 and s.Wheelie < 0.1 then
		local loop = findLoop(s.Position, heading(s.Yaw))
		if loop then
			s.Loop = loop
			s.LoopAngle = 0
			s.Yaw = BikePhysics.YawOf(loop.Entry.LookVector)
			s.TravelYaw = s.Yaw
			push(events, "LoopStart")
		end
	end
	local before, pitchBefore, speedBefore = s.Position, s.Pitch, s.Speed
	if s.Loop then
		loopStep(s, spec, input, dt, events)
	elseif s.Grounded then
		groundStep(s, spec, mode, input, world, dt, events)
	else
		airStep(s, spec, input, world, dt, events)
	end

	-- the suspension under the chassis
	if s.SusSpec ~= spec or not s.Sus then
		local params = Suspension.Params(spec)
		s.SusParams = params
		s.SusSpec = spec
		if not s.Sus then
			s.Sus = Suspension.new(params)
		end
	end
	local sus, params = s.Sus :: Suspension.State, s.SusParams :: Suspension.Params
	local dir = heading(s.Yaw)
	local along = dir * math.cos(s.Pitch) + UP * math.sin(s.Pitch)
	local onGround = s.Grounded and not s.Loop
	local support: { number? } = { nil, nil }
	if onGround then
		local half = spec.Wheelbase / 2
		local reach = (spec.FrontTravel + spec.RearTravel) * STUDS + 2
		support[1] = wheelSupport(world, s.Position, along, dir, half, spec.WheelRadius, reach)
		support[2] = wheelSupport(world, s.Position, along, dir, -half, spec.RearWheelRadius, reach)
	end
	local loop = s.Loop
	Suspension.Step(sus, params, {
		Mode = if loop then "Loop" elseif s.Grounded then "Ground" else "Air",
		WasGround = wasGround,
		WasLoop = wasLoop,
		Origin = s.Position / STUDS,
		Move = (s.Position - before) / STUDS,
		Heading = dir,
		Pitch = s.Pitch,
		PitchBefore = pitchBefore,
		Speed = if s.Grounded or loop then s.Speed else 0,
		Support = support,
		LongAccel = if onGround then math.clamp((s.Speed - speedBefore) / dt, -25, 25) else 0,
		Hop = if s.HopHeld then s.HopCharge else 0,
		RearBrake = not s.FrontBraking and s.BrakeApplied > 0,
		FrontOff = s.Wheelie > 0.03,
		RearOff = s.Stoppie > 0.03,
		LandingSpeed = if not wasGround and s.Grounded then fallBefore else nil,
		LoopRadius = if loop then loop.Radius / STUDS else nil,
	}, dt)

	-- a barspin starts on a press made in the air, not a key already held at takeoff (a pad's hop
	-- preload is the same button)
	if s.Grounded or s.Loop then
		s.BarspinHeld = input.Barspin
	end
	return events
end

return BikePhysics
