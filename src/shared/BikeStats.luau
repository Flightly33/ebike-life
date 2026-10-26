--[[
	BikeStats: turns a catalog bike plus its tuning upgrades into the numbers BikePhysics runs on, and
	into the stat chips the menus show.
]]

local Bikes = require(script.Parent.Bikes)
local Upgrades = require(script.Parent.Upgrades)
local Config = require(script.Parent.Config)

local BikeStats = {}

BikeStats.RIDER_KG = 75
BikeStats.RIDER_W = 210 -- a fit commuter's sustained pedalling
BikeStats.RIDER_FORCE_N = 130 -- what the legs manage at the pedals from a standstill, at the tyre

export type Spec = {
	Id: string,
	MassKg: number,
	MotorW: number,
	WheelForceN: number,
	RiderW: number,
	RiderForceN: number,
	Pedals: boolean,
	Throttle: boolean,
	LegalKmh: number,
	CutoffKmh: number,
	CdA: number,
	CrrRoad: number,
	CrrOff: number,
	GripRoad: number,
	GripOff: number,
	BrakeG: number,
	BatteryWh: number,
	Regen: number,
	Wheelbase: number, -- studs
	WheelRadius: number, -- studs (front)
	RearWheelRadius: number, -- studs
	WheelRadiusM: number, -- metres, for wheel spin
	HopSpeed: number,
	Landing: number,
	AirControl: number,
	WheeliePop: number,
	Unlocked: boolean,
	-- suspension (Shared/Suspension builds the spring-damper model from these)
	FrontTravel: number, -- m at the wheel
	RearTravel: number,
	BikeKg: number, -- the bike alone (MassKg adds the rider)
	SeatHeightM: number,
	SuspensionLevel: number, -- the Suspension upgrade: 0 stock, 1 tuned damping, 2 pro coil setup
}

type TireTable = { Crr: number, Off: number, Grip: number, GripOff: number }
local TIRES: { [string]: TireTable } = {
	Road = { Crr = 0.85, Off = 7.0, Grip = 0.92, GripOff = 0.42 },
	Hybrid = { Crr = 1.0, Off = 4.0, Grip = 0.86, GripOff = 0.55 },
	Knobby = { Crr = 1.15, Off = 2.2, Grip = 0.84, GripOff = 0.8 },
	Fat = { Crr = 1.1, Off = 1.7, Grip = 0.86, GripOff = 0.82 },
	Moto = { Crr = 1.0, Off = 1.8, Grip = 0.92, GripOff = 0.8 },
}

function BikeStats.TireKind(bike: Bikes.Bike, levels: Upgrades.Levels?): string
	local choice = Upgrades.TireKinds[Upgrades.Level(levels, "Tires")]
	if choice == "Stock" or choice == nil then
		return bike.TireKind
	end
	return choice
end

-- Off-road class bikes have no street limiter to unlock
function BikeStats.HasLimiter(bike: Bikes.Bike): boolean
	return bike.Class ~= "Off-road"
end

function BikeStats.Compute(bike: Bikes.Bike, levels: Upgrades.Levels?): Spec
	local geo = bike.Geometry
	local vis = Config.VISUAL_STUDS_PER_METER
	local battery = Upgrades.BatteryScale[Upgrades.Level(levels, "Battery")] or 1
	local power = Upgrades.PowerScale[Upgrades.Level(levels, "Controller")] or 1
	local torque = Upgrades.TorqueScale[Upgrades.Level(levels, "Controller")] or 1
	local suspension = Upgrades.Level(levels, "Suspension")
	local brakes = Upgrades.BrakeScale[Upgrades.Level(levels, "Brakes")] or 1
	local unlocked = (not BikeStats.HasLimiter(bike)) or Upgrades.Level(levels, "Limiter") > 0
	local tire = TIRES[BikeStats.TireKind(bike, levels)] or TIRES.Hybrid
	local rearDiameter = geo.RearWheelDiameter or geo.WheelDiameter
	local rearRadiusM = rearDiameter / 2
	return {
		Id = bike.Id,
		MassKg = bike.WeightKg + BikeStats.RIDER_KG,
		MotorW = bike.PeakW * power,
		WheelForceN = bike.WheelTorqueNm * torque / rearRadiusM,
		RiderW = if bike.Pedals then BikeStats.RIDER_W else 0,
		RiderForceN = if bike.Pedals then BikeStats.RIDER_FORCE_N else 0,
		Pedals = bike.Pedals,
		Throttle = bike.Throttle,
		LegalKmh = bike.LegalKmh,
		CutoffKmh = if unlocked then bike.MaxKmh else bike.LegalKmh,
		CdA = bike.CdA,
		CrrRoad = bike.Crr * tire.Crr,
		CrrOff = bike.Crr * tire.Off,
		GripRoad = tire.Grip,
		GripOff = tire.GripOff,
		BrakeG = bike.BrakeG * brakes,
		BatteryWh = bike.BatteryWh * battery,
		Regen = bike.Regen,
		Wheelbase = geo.Wheelbase * vis,
		WheelRadius = geo.WheelDiameter / 2 * vis,
		RearWheelRadius = rearDiameter / 2 * vis,
		WheelRadiusM = rearRadiusM,
		HopSpeed = bike.HopSpeed,
		Landing = bike.Landing + (Upgrades.LandingBonus[suspension] or 0),
		AirControl = bike.AirControl * (Upgrades.AirControlScale[suspension] or 1),
		WheeliePop = bike.WheeliePop,
		Unlocked = unlocked,
		FrontTravel = geo.FrontTravel or 0.12,
		RearTravel = geo.RearTravel or 0.1,
		BikeKg = bike.WeightKg,
		SeatHeightM = geo.SeatHeight,
		SuspensionLevel = suspension,
	}
end

-- Top speed on flat tarmac in the given mode (km/h), solved from the power balance. Used by the
-- menus and the police (pursuit speed), and checked against the physics in tests.
function BikeStats.TopSpeedKmh(spec: Spec, maxPower: number, assist: number): number
	local g = Config.Physics.Gravity
	local rho = Config.Physics.AirDensity
	local best = 0
	for kmh = 1, 260 do
		local v = kmh / 3.6
		local rider = spec.RiderW
		local motor = 0
		if kmh < spec.CutoffKmh then
			if spec.Throttle then
				motor = spec.MotorW * maxPower
			else
				motor = math.min(spec.MotorW * maxPower, rider * assist)
			end
		end
		local available = rider + motor
		local needed = (0.5 * rho * spec.CdA * v * v + spec.CrrRoad * spec.MassKg * g) * v
		if available >= needed then
			best = kmh
		end
	end
	return best
end

export type Chip = { Label: string, Value: string }

-- Stat chips for a card: motor, power, top speed, battery
function BikeStats.Chips(bike: Bikes.Bike, levels: Upgrades.Levels?): { Chip }
	local spec = BikeStats.Compute(bike, levels)
	local motor = bike.Drive
	return {
		{ Label = "Motor", Value = motor },
		{ Label = "Power", Value = Bikes.FormatWatts(math.floor(spec.MotorW / 10 + 0.5) * 10) },
		{ Label = "Top Speed", Value = string.format("%d km/h", math.min(spec.CutoffKmh, BikeStats.TopSpeedKmh(spec, 1, 3.4))) },
		{ Label = "Battery", Value = string.format("%dV %s", bike.Volts, Bikes.FormatWh(math.floor(spec.BatteryWh))) },
	}
end

return BikeStats
