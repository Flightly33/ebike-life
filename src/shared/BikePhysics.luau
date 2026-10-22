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
	Loop: Loop?, -- riding a loop
	LoopAngle: number, -- rad round it
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
		Loop = nil,
		LoopAngle = 0,
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

-- The frame the bike model is drawn at (model origin = ground midpoint between the wheels)
function BikePhysics.GetCFrame(s: State, spec: Spec): CFrame
	local base = CFrame.new(s.Position) * CFrame.fromEulerAnglesYXZ(0, s.Yaw, 0)
	local pivot = Vector3.new(0, 0, spec.Wheelbase / 2) -- rear tyre contact
	local wheelie = CFrame.new(pivot) * CFrame.Angles(s.Wheelie, 0, 0) * CFrame.new(-pivot)
	local front = Vector3.new(0, 0, -spec.Wheelbase / 2)
	local stoppie = CFrame.new(front) * CFrame.Angles(-s.Stoppie, 0, 0) * CFrame.new(-front)
	return base * CFrame.Angles(s.Pitch, 0, 0) * CFrame.Angles(0, 0, s.Lean) * wheelie * stoppie
end

-- The box swept for collisions: the body above step height, aligned with the heading
function BikePhysics.Body(s: State, spec: Spec): (CFrame, Vector3)
	local length = spec.Wheelbase + spec.WheelRadius + spec.RearWheelRadius
	local k = Config.BIKE_SIZE / 1.2 -- the box was sized for bikes drawn 1.2x life size
	local height = 3.4 * k
	local size = Vector3.new(1.3 * k, height, length)
	local center = s.Position + UP * (P.StepHeight + 0.1 + height / 2)
	return CFrame.new(center) * CFrame.fromEulerAnglesYXZ(0, s.Yaw, 0), size
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
	-- Small street props (bins, bollards, signs) slow you but never bail you; glancing blows never do
	if kind == "Prop" or into < P.CrashSquareness then
		return
	end
	local limit = if kind == "Car" or kind == "Cop" then Config.Traffic.HitKmh / 3.6 else P.CrashImpact
	if hit > limit then
		crash(s, events, if kind == "Wall" then "Wall" else "Hit a car")
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
	local brake = if riding then input.Brake else 0

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
	local brakeDecel = brake * spec.BrakeG * g * math.min(1, grip / 0.85)
	if v > 0.05 then
		local before = v
		v = math.max(0, v + accel * dt - brakeDecel * dt)
		if brake > 0 and spec.Regen > 0 and s.Battery > 0 then
			local braking = math.max(0, before - v) / dt * m * before
			s.Battery = math.min(spec.BatteryWh, s.Battery + braking * spec.Regen * dt / 3600 * Config.Battery.DrainScale)
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
		s.Battery = math.max(0, s.Battery - s.MotorPower / P.RiderEfficiency * dt / 3600 * Config.Battery.DrainScale)
	end

	-- Pedals and wheels
	local cadenceTarget = if pedalling and v > 0.3 then math.clamp(55 + kmh * 1.1, 0, 105) else 0
	s.Cadence = approach(s.Cadence, cadenceTarget, 220 * dt)
	s.CrankAngle = (s.CrankAngle + s.Cadence / 60 * TAU * dt) % TAU

	-- Steering
	local handsFactor = if input.NoHands then 0.45 elseif input.OneHand then 0.8 else 1
	local steerTarget = if riding then input.Steer * handsFactor else 0
	s.Steer = approach(s.Steer, steerTarget, TU.SteerRate * dt)
	local steerMax = P.MaxSteer + (P.MinSteer - P.MaxSteer) * math.clamp(math.abs(v) / 22, 0, 1)
	s.SteerAngle = s.Steer * steerMax
	-- Walking pace: the bicycle's geometry (yaw = v·tanδ / wheelbase). Riding: the bars set a turn
	-- rate (carving, like the reference game), a little less on loose ground and at very high speed.
	local wheelbaseM = spec.Wheelbase / Config.VISUAL_STUDS_PER_METER
	local geometric = v * math.tan(s.Steer * P.MaxSteer) / wheelbaseM
	local gripScale = math.clamp(grip / 0.9, 0.55, 1.05)
	local carve = math.abs(s.Steer) * TU.Rate * gripScale / (1 + math.max(0, math.abs(v) - TU.FadeFrom) / TU.FadeOver)
	local yawRate = math.sign(geometric) * math.min(math.abs(geometric), carve)
	if s.Wheelie > 0.08 or s.Stoppie > 0.05 then
		yawRate *= 0.55
	end
	local lateralMax = grip * g * 0.95
	-- Drift: the rear brake is locked, so the tail is free to swing out. The steering throws the
	-- heading round faster than grip allows, while the direction of travel catches up only as fast
	-- as the tyres can bend it (lateral grip / speed). The gap is the slip angle; sliding scrubs speed.
	-- the tail only swings out at speed; slower than that a locked rear just skids you to a stop
	local drifting = rearLocked and v > DR.MinSpeed
	if drifting then
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
			alpha = stiffness * (target - s.Wheelie) - damping * s.WheelieRate + wobble
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
	local above = P.StepHeight + 0.3
	local half = spec.Wheelbase / 2
	local rearHit = world.Down(target - dir * half + UP * above, above + 6)
	local frontHit = world.Down(target + dir * half + UP * above, above + 6)
	if rearHit and rearHit.Position.Y - s.RearY > P.StepHeight then
		-- Too tall to roll up: a low obstacle the body sweep didn't catch. Stop.
		v = 0
		target = s.Position
		rearHit = world.Down(target - dir * half + UP * above, above + 6)
		frontHit = world.Down(target + dir * half + UP * above, above + 6)
	end
	local rearSupport = rearHit or frontHit
	local horizontalSpeed = v * math.cos(s.Pitch)
	local predicted = s.RearY + s.RearVy * STUDS * dt - 0.5 * g * STUDS * dt * dt
	local tolerance = if s.RearVy > 0.5 then 0.03 else P.SnapDistance

	-- Too steep to keep riding (a quarter pipe's top): you leave it along the surface, like a lip
	local steepPitch: number? = nil
	if rearSupport and v > 0 then
		local n = rearSupport.Normal
		local surfacePitch = math.atan(-n:Dot(dir) / math.max(n.Y, 0.05))
		if surfacePitch > P.MaxRidePitch then
			steepPitch = math.min(surfacePitch, 1.45)
		end
	end

	if not rearSupport or steepPitch or rearSupport.Position.Y < predicted - tolerance then
		-- Off the lip: keep the momentum the rear tyre had up the slope
		local vy = math.max(s.RearVy, -1)
		local along = horizontalSpeed
		if steepPitch then
			vy = v * math.sin(steepPitch)
			along = v * math.cos(steepPitch)
			s.Pitch = steepPitch
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
		-- The front follows its own ground unless it's hanging over a lip (then the bike holds its pitch)
		local pitchTarget = math.atan(slopeTan)
		if frontHit and rearHit then
			local yf = frontHit.Position.Y
			local expected = yr + spec.Wheelbase * math.tan(s.Pitch)
			if yf > expected - 1.0 then
				pitchTarget = math.atan2(yf - yr, spec.Wheelbase)
			else
				pitchTarget = s.Pitch
			end
		end
		-- follow the ground closely: the height tracks the rear tyre exactly, so a lagging pitch
		-- buried the front wheel in the foot of every ramp (worse the bigger the bike is drawn)
		s.Pitch = approach(s.Pitch, pitchTarget, 18 * dt)
		s.Position = Vector3.new(target.X, yr + half * math.sin(s.Pitch), target.Z)
		local kind = rearSupport.Kind
		if frontHit and OFFROAD[frontHit.Kind] then
			kind = frontHit.Kind
		end
		s.Surface = kind
		s.Offroad = OFFROAD[kind] == true
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
		s.Pitch = 0
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
	local tolerance = spec.Landing * (if short then 2.6 elseif airTime < 0.8 then 1.5 else 1) + math.abs(groundPitch) * 0.4
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

	local along = horizontal.Magnitude / STUDS * math.cos(headingError)
	if backwards then
		-- Landed a 180: keep rolling backwards and let the rider stop
		along = -horizontal.Magnitude / STUDS * math.abs(math.cos(headingError)) * 0.5
	end
	local softness = 1 - 0.35 * (math.abs(pitchError) / tolerance) ^ 2
	s.Speed = along * softness
	s.Pitch = groundPitch
	if input.Wheelie and pitchError > 0.12 and pitchError < WH.LoopOut then
		-- Landed rear wheel first with the key held: roll straight into a wheelie
		s.Wheelie = pitchError
		s.WheelieRate = 0
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
		s.AirVelocity = heading(s.Yaw) * 2
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
		if groundY and groundY >= newY - 0.02 then
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

-- Knocked off from outside (a police PIT): a bail with the given reason
function BikePhysics.ForceCrash(s: State, reason: string): { Event }
	local events: { Event } = {}
	crash(s, events, reason)
	return events
end

-- Advances the bike by dt seconds. Returns what happened (tricks, crashes, landings).
function BikePhysics.Step(s: State, spec: Spec, mode: Mode, input: Input, world: World, dt: number): { Event }
	local events: { Event } = {}
	dt = math.clamp(dt, 0, 0.1)
	if dt <= 0 then
		return events
	end
	s.Time += dt

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
	if s.Loop then
		loopStep(s, spec, input, dt, events)
	elseif s.Grounded then
		groundStep(s, spec, mode, input, world, dt, events)
	else
		airStep(s, spec, input, world, dt, events)
	end
	-- a barspin starts on a press made in the air, not a key already held at takeoff (a pad's hop
	-- preload is the same button)
	if s.Grounded or s.Loop then
		s.BarspinHeld = input.Barspin
	end
	return events
end

return BikePhysics
