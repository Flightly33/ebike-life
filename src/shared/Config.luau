--[[
	Config: every tuning number in one place.

	Units: physics runs in SI (metres, m/s, kg, W, N); the world is in studs. The whole game shares
	one scale, 1 m = 0.8 / 0.28 ≈ 2.86 studs (1 stud = 0.35 m): Roblox avatars are about 5.2 studs
	tall, a 1.8 m person at that scale, so the bikes, cars and city all match the player. The city
	is authored in Roblox's standard units (1 stud = 0.28 m) and shrunk by WORLD_SCALE.
]]

local Config = {}

Config.WORLD_SCALE = 0.8
Config.METERS_PER_STUD = 0.28 / Config.WORLD_SCALE
Config.STUDS_PER_METER = 1 / Config.METERS_PER_STUD
Config.KMH_PER_STUD_PER_SECOND = Config.METERS_PER_STUD * 3.6
-- Bike and car models are built from real dimensions in metres at this scale (the same one)
Config.VISUAL_STUDS_PER_METER = Config.STUDS_PER_METER

Config.BRAND = "Flightly"
Config.DEALERSHIP = "Flighty Mechanics"
Config.GAME_NAME = "E-Bike Life"

Config.Physics = {
	Gravity = 9.81, -- m/s², real
	AirDensity = 1.2, -- kg/m³
	StepHeight = 1.2, -- studs a wheel rolls up without stopping (curbs are 0.4)
	SnapDistance = 0.5, -- studs the ground may drop away before the bike counts as airborne
	MaxSteer = 0.55, -- rad of handlebar at walking pace
	MinSteer = 0.07, -- rad at full speed (bikes turn by leaning at speed)
	SteerRate = 4.5, -- how fast the bars follow the input (1/s)
	MaxLean = 0.85, -- rad
	ReverseSpeed = 1.3, -- m/s when walking the bike backwards
	RiderEfficiency = 0.82, -- motor + controller efficiency for battery drain
	CrashImpact = 8.5, -- m/s of head-on speed into a wall that bails the rider (~30 km/h)
	CrashTime = 2.2, -- seconds on the floor after a bail
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
	Counted = 0.12, -- rad: above this the wheelie clock runs
	Noise = 1.4, -- rad/s² of wobble at the start
	NoisePerSecond = 0.07, -- more wobble the longer you hold it
	NoisePerKmh = 0.045, -- and the faster you go
	SweetLow = 0.3, -- balance zone shown on the HUD
	SweetHigh = 0.78,
}

Config.Drift = {
	MinSpeed = 4.5, -- m/s (~16 km/h) to throw the tail out
	YawRate = 1.25, -- rad/s of tail swing at full steer...
	YawPerSpeed = 0.035, -- ...plus this per m/s
	Grip = 0.8, -- fraction of lateral grip that bends the line while sliding
	LockedDecel = 0.07, -- g of the locked rear tyre
	SlideDecel = 0.3, -- g more at a 90 degree slip
	SpinOut = 1.25, -- rad of slip that spins you out
	StartSlip = 0.22, -- rad: past this it counts as a drift
	EndSlip = 0.1,
	Recover = 5, -- how fast the line snaps back to the heading after a drift (1/s)
}

Config.Hop = {
	ChargeTime = 0.45, -- seconds to fully preload
	MinFraction = 0.55, -- of the bike's hop speed on a tap
}

Config.Battery = {
	-- Game time is compressed: a full battery lasts minutes, not hours (real Wh, real watts, x this)
	DrainScale = 8,
	LowPower = 0.2, -- below 20% the controller limits power...
	LowPowerCap = 0.7, -- ...to 70%
	CriticalPower = 0.05,
	CriticalPowerCap = 0.4,
	ChargeSeconds = 6, -- a charging station fills an empty pack in this long
}

Config.Economy = {
	StartCash = 150,
	StarterBike = "metro_c1",
	MinPaySpeed = 4, -- km/h before riding pays
	BaseRate = 0.25, -- $/s once moving
	RatePerKmh = 0.03, -- $/s per km/h
	MaxPayKmh = 140, -- speeds above this (exploits, glitches) pay as this
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

Config.Police = {
	SightRange = 184, -- studs a cop notices you from
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
	LoseRange = 336, -- studs: further than this always counts as out of sight
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
}

Config.Traffic = {
	CarCount = 14,
	Speed = 11, -- m/s (~40 km/h)
	SpeedVariance = 2.5,
	HitKmh = 22, -- hitting a car faster than this bails you
}

Config.Lights = {
	Cycle = 24, -- seconds for a full traffic-light cycle
	Yellow = 2.5,
	AllRed = 1,
}

Config.Bikes = {
	DespawnDistance = 720, -- an empty bike this far from its owner goes back to the garage
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
