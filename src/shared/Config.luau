--[[
	Config: every tuning number in one place.

	Units: physics runs in SI (metres, m/s, kg, W, N); the world is in studs. Riders and their bikes
	share one scale, 1 m ≈ 2.86 studs (1 stud = 0.35 m), which matches a standard avatar's height
	(5.2 studs; every character is scaled to it, Avatar.Height).

	The city is authored in Roblox's standard units (1 stud = 0.28 m, real sizes) and built at
	WORLD_SCALE times that. A Roblox avatar is stocky (a big head, arms and shoulders 4 studs
	across): a city built to its height (0.8) made it look like a giant next to bus shelters,
	doors and cars, and 1.2 still did (the owner's avatar measured ~6.5 studs in a screenshot,
	before characters were scaled to one height). At 1.5 a lane is 19 studs, a storey ~16, a door
	~11, a sedan ~7.8 tall.
	Cars (traffic, police, parked) are part of the world and built at its scale; bikes stay fitted to
	their riders. Where things are on the plan (the streets, blocks, islands and places) is spread
	by CITY_SPREAD: the map grows with the world (MAP_SCALE).
]]

local Config = {}

Config.WORLD_SCALE = 1.5
-- How far apart things are: game studs per unit of the city plan (City/Layout's grid lines, rects
-- and places; the plan was first drawn for a city at 1.25). From 1.2 on the map grows with the
-- world (the owner asked for everything bigger, distances too), so every block, island and park
-- keeps the room it had at 1.2 and the landmarks still fit their lots
Config.MAP_SCALE = 1.25 * Config.WORLD_SCALE / 1.2
-- City/Layout spreads every position on the plan by this and keeps every size real
Config.CITY_SPREAD = Config.MAP_SCALE / Config.WORLD_SCALE
-- the stunt parks and the hills are built this many times their design size whatever the world's
-- scale: the size they're ridden at (the bikes don't grow with the city)
Config.RIDE_SCALE = 1.25
Config.METERS_PER_STUD = 0.35
Config.STUDS_PER_METER = 1 / Config.METERS_PER_STUD
-- the city's own studs per real metre (it's authored at 1 stud = 0.28 m, built at WORLD_SCALE):
-- what the PBR materials' tiles are sized by
Config.CITY_STUDS_PER_METER = Config.WORLD_SCALE / 0.28
-- cars belong to the city: traffic, police and parked cars are built at its scale. Their speeds
-- stay in STUDS_PER_METER (the bikes' metres), so a chase plays the same at any WORLD_SCALE
Config.CAR_STUDS_PER_METER = Config.CITY_STUDS_PER_METER
-- how much bigger a car is drawn than the bikes' scale: the cars' AI spacing grows with it
Config.CAR_SCALE = Config.CAR_STUDS_PER_METER / Config.STUDS_PER_METER
Config.KMH_PER_STUD_PER_SECOND = Config.METERS_PER_STUD * 3.6
-- Bike models are built from real dimensions in metres at this scale
-- Bikes are drawn at this times life size. 1.0 is where a default avatar fits the whole line-up:
-- seated, knees bent on the footpegs and hands on the bars (tools/lune/reach.luau prints each bike's
-- fitting size, 0.87 for the biggest enduro to 1.17 for the youth pit bike). The owner tried 1.2,
-- 2.4 and 1.8 when the rider pose was broken; bigger than ~1.0 and the feet can't reach the pegs.
Config.BIKE_SIZE = 1.0
Config.VISUAL_STUDS_PER_METER = Config.STUDS_PER_METER * Config.BIKE_SIZE

-- Every player's character is scaled to this height (studs, head to feet; CharacterService), the
-- size of a standard avatar the city and the bikes are sized for. Avatars run from ~4.5 to ~7.5
-- studs; a tall one looked bigger than the shelters and cars. 0 leaves avatars as they are.
Config.Avatar = {
	Height = 6.5, -- 1.25x the standard 5.2 (the owner found 5.2 a little small next to the 1.5 city)
}

Config.BRAND = "Flightly"
Config.DEALERSHIP = "Flighty Mechanics"
Config.GAME_NAME = "E-Bike Life"

-- The owner asked for 1.5x the real bikes' speed: every top speed (the controller cut-off) is this
-- much higher, with the power and torque to reach it (aero drag grows with speed cubed)
Config.SpeedBoost = 1.5

-- Crashing out (Client/BikeController): the rider is thrown off with the momentum the bike lost
-- in the hit, and the bike is left to Roblox's physics to tumble and slide to a stop
Config.Crash = {
	EjectLift = 0.35, -- upward m/s per m/s of speed lost in the hit: pitched up over the bars
	EjectLiftMax = 7, -- m/s
	EjectHop = 1.5, -- m/s up on any bail (the rider pushes off)
	SpinPerMps = 0.55, -- rad/s of forward tumble per m/s lost
	SpinMax = 9, -- rad/s
	BikeSpinShare = 0.6, -- of that tumble the bike takes (it pivots on whatever it hit)
	BikeDensity = 0.9, -- the tumbling bike's collision box (water is 1)
	BikeFriction = 0.55,
	BikeElasticity = 0.12,
	RestSpeed = 3, -- m/s: the rider gets up once slower than this (after Physics.CrashTime)
	GetUpMax = 8, -- s: gets up by then whatever
}

Config.Physics = {
	Gravity = 9.81, -- m/s², real
	AirDensity = 1.2, -- kg/m³
	StepHeight = 1.2, -- studs a wheel rolls up without stopping (kerbs are 0.75; a bench seat isn't)
	SnapDistance = 1.0, -- studs the ground may drop away before the bike counts as airborne (a kerb
	-- drop isn't a jump: the wheels follow it down on the suspension)
	MaxSteer = 0.55, -- rad of handlebar at walking pace
	MinSteer = 0.07, -- rad at full speed (bikes turn by leaning at speed)
	StepClimb = 1.4, -- studs of rise per stud travelled the front can follow (steeper than any ramp face, a step is eased over)
	VertEntry = 0.6, -- rad: a too-steep face only launches you if you were already pitched within this of it (riding up a curve)
	VertCarry = 0, -- of the horizontal speed kept leaving a quarter pipe's top (straight up: you come back down it)
	FrontDropRate = 5, -- rad/s the front wheel comes down after landing on the back wheel
	RearDropRate = 7, -- rad/s the rear comes down after a nose-first landing
	MaxRidePitch = 1.0, -- rad: a surface steeper than this (a quarter pipe's top) launches you along it
	SteerRate = 4.5, -- how fast the bars follow the input (1/s)
	MaxLean = 0.85, -- rad
	ReverseSpeed = 1.3, -- m/s when walking the bike backwards
	RearBrakeShare = 0.55, -- of the bike's full braking the rear brake (S) manages alone: the weight
	-- shifts off the rear as it slows; brake + Shift is the front brake, at full power (stoppies)
	BrakeSqueeze = 5, -- per second: how fast the brake comes on (a lever is squeezed, not snapped)
	RiderEfficiency = 0.82, -- motor + controller efficiency for battery drain
	CrashImpact = 9.5, -- m/s of head-on speed into a wall that bails the rider (~34 km/h)
	PropCrashImpact = 6.5, -- m/s head-on into a bench, bin or bollard that throws you (~23 km/h)
	CrashSquareness = 0.55, -- hits more glancing than this (0 = scrape, 1 = head-on) never bail
	CrashTime = 3.0, -- seconds at least on the floor after a bail (ragdoll, then get up)
	AirPitchRate = 5.2, -- rad/s of rotation when pulling back in the air (scaled by AirControl)
	AirSpinRate = 6.5, -- rad/s of spin when steering in the air (scaled by AirControl)
	LandingHeading = 0.75, -- rad between facing and travel a landing tolerates
	MinAirTime = 0.35, -- seconds before a jump counts as air time
}

Config.Wheelie = {
	MinSpeed = 1.6, -- m/s (~6 km/h) to pop one
	DropSpeed = 0.9, -- m/s: below this the front comes down
	Target = 0.5, -- rad the bike settles at while the key is held
	ThrottleTrim = 0.14, -- rad more with the throttle held
	CoastTrim = -0.08, -- rad less without it
	BrakeTrim = -0.5, -- rad: the rear brake brings the front down (real technique)
	Stiffness = 16, -- rad/s² per rad of error, scaled by the bike's WheeliePop
	Damping = 0.55, -- fraction of critical damping
	DropAccel = 7, -- rad/s² the front falls with when released
	LoopOut = 1.02, -- rad: past this the rider loops out
	Balance = 0.6, -- rad: the balance point the bike tips away from...
	Unstable = 1.2, -- ...this hard (x the spring): over 1, the key alone never holds it
	Counted = 0.12, -- rad: above this the wheelie clock runs
	Noise = 1.4, -- rad/s² of wobble at the start
	NoisePerSecond = 0.07, -- more wobble the longer you hold it
	NoisePerKmh = 0.045, -- and the faster you go
	SweetLow = 0.42, -- balance zone shown on the HUD (the balance point is 0.6)
	SweetHigh = 0.7,
}

-- Turning, tuned to the reference scooter game: above walking pace the bars set a turn rate (it
-- carves ~85 degrees a second at 60 km/h, far tighter than real tyre grip), fading a little at very
-- high speed; at walking pace it's the bicycle's steering geometry. The lean shows the turn.
Config.Turning = {
	Rate = 1.5, -- rad/s at full lock
	FadeFrom = 17, -- m/s (~60 km/h): faster than this the rate fades...
	FadeOver = 28, -- ...by half again over this many m/s more
	SteerRate = 10, -- how fast the bars ease toward the input (1/s), at a standstill...
	SteerFadeSpeed = 40, -- ...halving by this many m/s (real bars get heavier at speed)
	RollIn = 8, -- rad/s: how quickly the bike rolls into and out of a turn (a damped spring)
	RollInSlow = 11, -- the same at walking pace (tight and direct)
	Scrub = 0.03, -- speed lost per m/s² of cornering (per second)
	LeanScale = 0.5, -- of the physical lean for that turn
	MaxLean = 0.6, -- rad (~34 degrees)
	LeanRate = 4.5, -- rad/s the body leans in or out
}

Config.Drift = {
	MinSpeed = 4.5, -- m/s (~16 km/h) to throw the tail out
	YawRate = 1.25, -- rad/s of tail swing at full steer...
	YawPerSpeed = 0.035, -- ...plus this per m/s
	Grip = 0.8, -- fraction of lateral grip that bends the line while sliding
	LockedDecel = 0.07, -- g of the locked rear tyre
	SlideDecel = 0.3, -- g more at a 90 degree slip
	HoldSlip = 1.2, -- rad: the tail stops swinging out here (a held slide settles below it, so it never spins out)
	StartSlip = 0.22, -- rad: past this it counts as a drift
	Recover = 5, -- how fast the line snaps back to the heading after a drift (1/s)
}

Config.Stoppie = {
	MinSpeed = 3.5, -- m/s (~13 km/h) to pop one
	Target = 0.32, -- rad the rear settles at
	BrakeTrim = 0.35, -- more front brake lifts it further
	Stiffness = 22,
	Noise = 1.2,
	NoisePerSecond = 0.25,
	DropAccel = 9,
	Over = 0.95, -- rad: past this you go over the bars
	Counted = 0.12,
}

-- Held in the air (keys Z, X, T, G, N; tap Y for a barspin)
Config.AirTricks = {
	OutTime = 0.22, -- seconds to throw the body fully out
	InTime = 0.16, -- to tuck back in
	HoldTime = 0.2, -- held fully out this long before it counts
	LandOut = 0.35, -- still this far out at touchdown: you bail
	BarspinTime = 0.45,
	Names = { "Superman", "CanCan", "NacNac", "KneeKnocker", "NoFooter", "Barspin" },
}

Config.Loop = {
	Gravity = 0.55, -- loops are a little forgiving: gravity counts this much on the way round
	Drive = 2.5, -- m/s² the motor adds with the throttle held
	RollBack = 1.6, -- m/s: slower than this on the lower half and you roll back out
	Stick = 0.6, -- fraction of the real "stay on at the top" speed needed
}

Config.Hop = {
	ChargeTime = 0.45, -- seconds to fully preload
	MinFraction = 0.55, -- of the bike's hop speed on a tap
}

Config.Battery = {
	-- Game time is compressed: a full battery lasts minutes, not hours (real Wh, real watts, x this)
	DrainScale = 3, -- the owner asked for longer rides: ~2.7x the old 8
	LowPower = 0.2, -- below 20% the controller limits power...
	LowPowerCap = 0.7, -- ...to 70%
	CriticalPower = 0.05,
	CriticalPowerCap = 0.4,
	ChargeSeconds = 6, -- a charging station fills an empty pack in this long
}

Config.Economy = {
	StartCash = 150,
	StarterBike = "flit_mini",
	MinPaySpeed = 4, -- km/h before riding pays
	BaseRate = 0.25, -- $/s once moving
	RatePerKmh = 0.03, -- $/s per km/h
	MaxPayKmh = 210, -- speeds above this (exploits, glitches) pay as this (1.5x bikes)
	WheeliePerSecond = 0.05, -- cash multiplier per wheelie second (1.05x after 1 s)
	WheelieMax = 3.0,
	OneHand = 0.25,
	NoHands = 0.5,
	ComboMax = 2.5,
	ComboDecay = 8, -- seconds without a trick before the combo bonus drains
	ChasePerStar = 0.5,
	WheelieLumpMin = 2, -- seconds before a wheelie pays a lump sum when it ends
	WheelieLump = 2.2, -- $ * seconds^1.2
	AirLump = 16, -- $ per second of air
	-- air tricks: $ each, x(1 + Stack per extra trick in the same jump)
	TrickLumps = { Superman = 45, CanCan = 40, NacNac = 40, KneeKnocker = 55, NoFooter = 35, Barspin = 60 } :: { [string]: number },
	TrickStack = 0.5,
	TricksPerJump = 6,
	ComboTrick = 0.05,
	StoppieLumpMin = 1, -- seconds
	StoppieLump = 4, -- $ * seconds^1.2
	LoopLump = 6, -- $ per stud of loop radius
	ComboLoop = 0.15,
	DriftLumpMin = 0.8, -- seconds before a drift pays
	DriftLump = 6, -- $ * seconds^1.15 * (1 + degrees/60)
	ComboDrift = 0.05, -- per drift
	FlipLump = 75,
	SpinLump = 40,
	NoHanderLump = 25,
	CleanLandingBonus = 0.25, -- +25% for a clean landing
	ComboAir = 0.15, -- combo multiplier per landed jump
	ComboFlip = 0.35,
	ComboSpin = 0.25,
	ComboWheelie = 0.1, -- per 5 s of wheelie
	-- Levels: XP needed grows by the same step every level (linear progression)
	XpBase = 120,
	XpStep = 60,
	XpPerKm = 60,
	LevelReward = 100,
	LevelRewardStep = 10,
	PayInterval = 0.25,
}

-- The day and night cycle (Shared/DayNight; applied on each client by Client/DayNight)
Config.DayNight = {
	DaySeconds = 1200, -- one game day in real seconds
	DayShare = 0.7, -- of it in daylight (06:00-20:00); the night goes quicker
	StartFraction = 0.12, -- where the clock starts at server time 0 (mid-morning)
	LampRange = 300, -- studs: street lamps this close cast real light (the rest just glow; how
	-- many, and how many cars' headlights, is the graphics mode's LampLights / HeadlightCars)
	WindowLitShare = 0.45, -- of windows lit at night
}

-- The two graphics modes the player picks on join (Client/Graphics; Menus > Settings changes it).
-- Ultra is the full look; Performance drops what costs most on phones and older computers.
-- The weather (Shared/Weather): spells of sunny, partly cloudy and overcast, the same for everyone
Config.Weather = {
	SpellSeconds = 300, -- how long a spell lasts
	BlendSeconds = 75, -- the last part of it, easing into the next
	Odds = { Clear = 0.5, Cloudy = 0.32, Overcast = 0.18 }, -- Miami: mostly sun
}

-- The realism pack (Shared/Materials): base materials whose quarter-turned copy should be used, if
-- the pattern of the normal one runs the wrong way on the city's parts (roof tile courses along the
-- slope instead of across it, planks across a boardwalk)
Config.Realism = {
	Turned = {} :: { [string]: boolean }, -- e.g. { ClayRoofTiles = true }
}

Config.Graphics = {
	Ultra = {
		Shadows = true,
		Clouds = true,
		SunRays = true,
		DepthOfField = true,
		LampLights = 28,
		HeadlightCars = 8,
		Specular = 1,
		Pedestrians = 36, -- people walking the pavements near the camera, on every block (Client/Ambient)
		ShopRooms = 3, -- walk-in shops fitted out in full detail at once, the nearest first (Client/ShopFit)
		ShopRange = 170, -- studs from the camera a shop is fitted out
	},
	Performance = {
		Shadows = false,
		Clouds = false,
		SunRays = false,
		DepthOfField = false,
		LampLights = 6,
		HeadlightCars = 2,
		Specular = 0.4,
		Pedestrians = 14,
		ShopRooms = 1,
		ShopRange = 110,
	},
}

Config.Police = {
	SightRange = 360, -- studs a cop notices you from
	PatrolCount = 6,
	MaxPursuers = 5,
	PatrolSpeed = 13, -- m/s (~47 km/h)
	-- Heat: offences seen by a cop fill a meter; a full meter is a wanted star
	HeatPerStar = 100,
	HeatStarStep = 50, -- each further star needs this much more
	HeatDecay = 12, -- per second with nothing seen
	Wheelie = 38, -- per second
	NoHands = 16,
	Drift = 32, -- per second sliding past a cop
	Speeding = 12, -- per second while over the legal limit, plus...
	SpeedingPerKmh = 1.2, -- ...this per km/h over
	SpeedingGrace = 4, -- km/h over the limit before it counts
	Sidewalk = 9, -- per second riding a pavement faster than SidewalkKmh
	SidewalkKmh = 15,
	Jump = 22, -- once per jump
	Flip = 45,
	RedLight = 45,
	HitCop = 120,
	StarEvery = 50, -- seconds of being seen in a chase that add a star
	EvadeBase = 7, -- seconds out of sight to escape at one star...
	EvadePerStar = 2.5, -- ...plus this per extra star
	LoseRange = 655, -- studs: further than this always counts as out of sight
	BustRange = 14, -- studs
	BustKmh = 12, -- slower than this near a cop and the cuffs come out
	BustTime = 2.6,
	FootBustRange = 56,
	FinePercent = 0.1,
	FineMin = 25,
	FineMax = 20000,
	EscapeReward = 120, -- per star
	EscapePerSecond = 3, -- per second of chase, per star
	PursuitSpeed = { 24, 26, 28, 30, 33 }, -- m/s top speed per star (86 to 119 km/h)
	PursuitAccel = { 5.5, 6, 6.5, 7, 7.5 }, -- m/s²
	Units = { 1, 2, 3, 4, 5 }, -- cars chasing per star
	-- Tactics
	-- no PIT or ramming: police don't use contact on motorcycles (it's deadly force)
	FollowGap = 45, -- studs the chasing car keeps behind a moving rider (to its centre: a cruiser is ~27 long)
	FlankOffset = 20, -- studs to the side a pacing car rides (a lane over: lanes are 19 studs)
	BoxInKmh = 12, -- below this the cars close in and block the rider in
	InterceptAhead = 6, -- seconds ahead an interceptor aims for
	RoadblockStars = 3,
	RoadblockAhead = 9, -- seconds ahead a roadblock goes
	RoadblockTime = 45,
	FlatTime = 18, -- seconds a spiked tyre stays flat
	FlatKmh = 14,
	-- Officers on foot
	DeployRange = 75, -- studs: a car this close to a stopped (or knocked-off) rider sends officers out
	DeployKmh = 10,
	ArrestRange = 6,
	OfficerGiveUp = 110, -- studs: further than this and they walk back to the car
}

Config.Traffic = {
	CarCount = 28, -- spread over every road, and kept near the players (TrafficService)
	Speed = 11, -- m/s (~40 km/h)
	SpeedVariance = 2.5,
	HitKmh = 26, -- hitting a car faster than this bails you
}

Config.Lights = {
	Cycle = 24, -- seconds for a full traffic-light cycle
	Yellow = 2.5,
	AllRed = 1,
}

Config.Bikes = {
	DespawnDistance = 1100, -- an empty bike this far from its owner goes back to the garage
	IdleDespawn = 300, -- seconds an empty bike may sit before it goes back
	StateRate = 10, -- client state updates per second
}

Config.Data = {
	Store = "EbikeLife_v1",
	AutosaveInterval = 120,
}

Config.Audio = {
	Search = true,
}

return Config
