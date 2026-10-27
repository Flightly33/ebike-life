--[[
	BikeModel: builds a Flightly bike out of parts from its real geometry (wheel sizes, wheelbase,
	head and seat angles, saddle and bar heights).

	Model space: origin on the ground midway between the tyre contacts, -Z forward, +Y up.

	Runtime bikes (Build without Static) are one assembly:
		Root (invisible, the pivot)  <- welds: frame, battery, saddle, Seat
		  Steer     Motor6D "SteerJoint" (about the head tube axis)   <- welds: fork tops, bars, light
		    Fork      Motor6D "ForkSlide"  (along the steering axis)    <- welds: fork lowers, low fender
		      FrontHub  Motor6D "FrontSpin"
		  Swing     Motor6D "SwingJoint" (about the swingarm pivot)    <- welds: swingarm, chain, hugger
		    RearHub   Motor6D "RearSpin"   (wheel spin)
		    ShockEnd  Motor6D "ShockRodJoint" (e-motos: the shock's shaft, aimed at its body)
		  ShockTop  Motor6D "ShockJoint"  (e-motos: the shock's body and spring, aimed at the shaft)
		  Crank     Motor6D "CrankSpin"  (pedals; pedal bikes only)
	The model is drawn with the suspension topped out (fully extended). The client turns those
	joints through .Transform every frame: the wheels spin, the bars steer, and the fork and swingarm
	follow the suspension's compression (Shared/Suspension). Attachments GripL / GripR (on the
	bars), PedalL / PedalR (on the pedals) or PegL / PegR (e-motos) are where the rider's hands and
	feet go. Parts carry a "Paint" attribute (Frame / Accent / Rims) so a respray only recolours.

	Static models (showroom, menu previews) are anchored parts with no joints.
]]

local Bikes = require(script.Parent.Parent.Bikes)
local Config = require(script.Parent.Parent.Config)
local Paints = require(script.Parent.Parent.Paints)
local Realism = require(script.Parent.Parent.Realism)
local PartKit = require(script.Parent.Parent.PartKit)
local MeshKit = require(script.Parent.MeshKit)

local BikeModel = {}

local BASE_VIS = Config.VISUAL_STUDS_PER_METER
-- studs per metre for the bike being built (Build scales it to fit its rider; see Options.Scale)
local VIS = BASE_VIS
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local BLACK = Color3.fromRGB(26, 26, 28)
local TIRE = Color3.fromRGB(32, 32, 34)
local SILVER = Color3.fromRGB(190, 192, 196)
local DARK = Color3.fromRGB(52, 54, 58)

export type PaintChoice = { Frame: string?, Accent: string?, Rims: string?, Glow: string? }
export type Options = {
	Static: boolean?,
	Scale: number?, -- drawn this many times BIKE_SIZE (BikeModel.FitScale fits a rider); default 1
}

type Group = { Parts: { BasePart }, Pivot: BasePart? }
type Builder = {
	Model: Model,
	Groups: { [string]: Group },
	Colors: { Frame: Color3, Accent: Color3, Rims: Color3 },
}

local function add(b: Builder, group: string, part: BasePart, paint: string?): BasePart
	local g = b.Groups[group]
	if not g then
		g = { Parts = {} }
		b.Groups[group] = g
	end
	table.insert(g.Parts, part)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
	if paint then
		part:SetAttribute("Paint", paint)
	end
	return part
end

local function colorFor(b: Builder, paint: string?, fallback: Color3): Color3
	if paint == "Frame" then
		return b.Colors.Frame
	elseif paint == "Accent" then
		return b.Colors.Accent
	elseif paint == "Rims" then
		return b.Colors.Rims
	end
	return fallback
end

-- Tube between two points (studs), diameter in metres
local function tube(b: Builder, group: string, name: string, a: Vector3, c: Vector3, diameter: number, paint: string?, color: Color3?, material: Enum.Material?): BasePart
	local part = PartKit.Tube(b.Model, name, a, c, diameter * VIS, colorFor(b, paint, color or BLACK), material or SMOOTH)
	return add(b, group, part, paint)
end

local function box(b: Builder, group: string, name: string, size: Vector3, cf: CFrame, paint: string?, color: Color3?, material: Enum.Material?): BasePart
	local part = PartKit.Box(b.Model, name, size, cf, colorFor(b, paint, color or BLACK), material or SMOOTH)
	return add(b, group, part, paint)
end

local function bar(b: Builder, group: string, name: string, a: Vector3, c: Vector3, w: number, h: number, paint: string?, color: Color3?, material: Enum.Material?): BasePart
	local part = PartKit.Bar(b.Model, name, a, c, w * VIS, h * VIS, colorFor(b, paint, color or BLACK), material or SMOOTH)
	return add(b, group, part, paint)
end

local function cyl(b: Builder, group: string, name: string, diameter: number, length: number, cf: CFrame, paint: string?, color: Color3?, material: Enum.Material?): BasePart
	local part = PartKit.Cylinder(b.Model, name, diameter * VIS, length * VIS, cf, colorFor(b, paint, color or BLACK), material or SMOOTH)
	return add(b, group, part, paint)
end

local function neon(b: Builder, group: string, name: string, size: Vector3, cf: CFrame, color: Color3): BasePart
	local part = PartKit.Box(b.Model, name, size, cf, color, Enum.Material.Neon)
	add(b, group, part, nil)
	part.CastShadow = false
	return part
end

-- A wheel at `axle` (studs): tyre, rim ring, spoke area, spokes, hub and brake rotor
local function wheel(b: Builder, group: string, axle: Vector3, diameter: number, width: number, kind: string, hubMotor: boolean)
	local at = CFrame.new(axle)
	local tireW = width
	cyl(b, group, "Tire", diameter, tireW, at, nil, TIRE)
	local rimD = diameter - math.max(width * 1.1, 0.07) * 2
	if kind == "Moto" then
		rimD = diameter * 0.72
	end
	cyl(b, group, "Rim", rimD, tireW * 1.04 + 0.006, at, "Rims")
	local innerD = rimD - (if kind == "Moto" then 0.05 else 0.035) * 2
	cyl(b, group, "Spokes", innerD, tireW * 1.06 + 0.01, at, nil, DARK)
	local spokeW = if kind == "Moto" then 0.012 else 0.006
	local spokeCount = if kind == "Moto" then 4 else 6
	for i = 1, spokeCount do
		local angle = math.pi * i / spokeCount
		box(b, group, "Spoke", Vector3.new((tireW * 1.12 + 0.016) * VIS, spokeW * VIS, innerD * VIS * 0.98), at * CFrame.Angles(angle, 0, 0), nil, SILVER, METAL)
	end
	if hubMotor then
		cyl(b, group, "HubMotor", 0.2, tireW * 1.15 + 0.04, at, nil, DARK, METAL)
		cyl(b, group, "HubCap", 0.12, tireW * 1.2 + 0.05, at, "Accent")
	else
		cyl(b, group, "Hub", 0.07, tireW * 1.2 + 0.04, at, nil, SILVER, METAL)
	end
	-- disc rotor on the left
	local rotorD = if kind == "Moto" then 0.26 else 0.18
	cyl(b, group, "Rotor", rotorD, 0.006, at * CFrame.new(-(tireW * 0.75 + 0.02) * VIS, 0, 0), nil, SILVER, METAL)
end

export type Geo = {
	RearAxle: Vector3,
	FrontAxle: Vector3,
	Rf: number,
	Rr: number,
	Axis: Vector3, -- steering axis (up and back), unit
	HB: Vector3, -- head tube bottom
	HT: Vector3, -- head tube top
	BB: Vector3,
	SeatTop: Vector3,
	ST: Vector3, -- seat tube top
	Bars: Vector3, -- handlebar centre
	Pivot: Vector3, -- swingarm pivot
	ShockTop: Vector3, -- rear shock mounts: on the frame
	ShockBottom: Vector3, -- and on the swingarm
}

local HEAD_ANGLE: { [string]: number } = {
	City = 70, Folding = 72, Cruiser = 68, Cargo = 69, Fat = 69, Hardtail = 66, Road = 72.5, Enduro = 64, Moped = 65, Moto = 64,
}
local FORK_LENGTH: { [string]: number } = {
	City = 0.44, Folding = 0.36, Cruiser = 0.47, Cargo = 0.42, Fat = 0.5, Hardtail = 0.55, Road = 0.4, Enduro = 0.6, Moped = 0.55, Moto = 0.66,
}
local CHAINSTAY: { [string]: number } = {
	City = 0.46, Folding = 0.4, Cruiser = 0.48, Cargo = 0.9, Fat = 0.47, Hardtail = 0.44, Road = 0.41, Enduro = 0.445, Moped = 0.55, Moto = 0.6,
}
local TUBE: { [string]: number } = {
	City = 0.055, Folding = 0.065, Cruiser = 0.055, Cargo = 0.06, Fat = 0.065, Hardtail = 0.06, Road = 0.048, Enduro = 0.07, Moped = 0.06, Moto = 0.07,
}

local function geometry(bike: Bikes.Bike): Geo
	local geo = bike.Geometry
	local style = geo.Style
	local Rf = geo.WheelDiameter / 2
	local Rr = (geo.RearWheelDiameter or geo.WheelDiameter) / 2
	local wb = geo.Wheelbase
	local rearAxle = Vector3.new(0, Rr, wb / 2)
	local frontAxle = Vector3.new(0, Rf, -wb / 2)
	local ha = math.rad(HEAD_ANGLE[style] or 70)
	local axis = Vector3.new(0, math.sin(ha), math.cos(ha))
	local forkLength = FORK_LENGTH[style] or 0.45
	local headTube = if style == "Cruiser" then 0.2 elseif style == "Enduro" or style == "Moto" then 0.12 else 0.16
	if style == "Moto" then
		-- e-motos: the fork is long enough to put the head tube just above the seat (a small-wheeled
		-- pit bike gets a short fork, its tank and battery under the rider) and for the tyre to clear
		-- the lower crown at full travel, as far as the bars allow (the head tube stays under them, so
		-- the bars, on the steering axis, stay where the rider fits them)
		local sinHead = math.sin(ha)
		local fit = (geo.SeatHeight + 0.1 - Rf) / sinHead - headTube
		local clear = (Rf + (geo.FrontTravel or 0.2) + 0.06) / sinHead
		local room = (geo.BarHeight - 0.03 - Rf) / sinHead - headTube
		forkLength = math.clamp(math.max(fit, math.min(clear, room)), 0.35, 0.85)
	end
	local hb = frontAxle + axis * forkLength
	local ht = hb + axis * headTube
	local bbHeight = if style == "Enduro" then 0.34 elseif style == "Fat" then 0.31 else 0.29
	local bb = Vector3.new(0, bbHeight, rearAxle.Z - (CHAINSTAY[style] or 0.45))
	if style == "Cargo" then
		-- longtails keep the cranks near the front; the long stays carry the deck
		bb = Vector3.new(0, 0.28, -wb / 2 + 0.62)
	end
	local sa = math.rad(73.5)
	local seatDir = Vector3.new(0, math.sin(sa), math.cos(sa))
	local postLength = (geo.SeatHeight - 0.05 - bb.Y) / math.sin(sa)
	local seatTop = bb + seatDir * postLength
	local st = bb + seatDir * (postLength * (if style == "Folding" then 0.35 else 0.62))
	local steerer = math.max(0.03, (geo.BarHeight - ht.Y) / math.sin(ha))
	local bars = ht + axis * steerer + Vector3.new(0, 0, -0.06)
	if style == "Cruiser" then
		bars += Vector3.new(0, 0, 0.12) -- swept back
	end
	-- e-motos: the swingarm pivots behind the motor and a mono shock runs from under the seat to it;
	-- the rest swing the rear wheel about the bottom bracket
	local pivot = if style == "Moto" then Vector3.new(0, 0.42, rearAxle.Z - 0.58) else bb
	local shockTop = Vector3.new(0, geo.SeatHeight - 0.15, pivot.Z + 0.01)
	local shockBottom = pivot:Lerp(rearAxle, 0.35) + Vector3.new(0, 0.05, 0)
	return {
		RearAxle = rearAxle,
		FrontAxle = frontAxle,
		Rf = Rf,
		Rr = Rr,
		Axis = axis,
		HB = hb,
		HT = ht,
		BB = bb,
		SeatTop = seatTop,
		ST = st,
		Bars = bars,
		Pivot = pivot,
		ShockTop = shockTop,
		ShockBottom = shockBottom,
	}
end

-- The bike's key points in metres (model space), for tools that build meshes to match the rig
function BikeModel.Geometry(bike: Bikes.Bike): Geo
	return geometry(bike)
end

local function scale(v: Vector3): Vector3
	return v * VIS
end

-- Steering group: fork, bars, grips, light, display. Returns the Steer pivot.
local function frontEnd(b: Builder, bike: Bikes.Bike, g: Geo, moto: boolean)
	local geo = bike.Geometry
	local style = geo.Style
	local steerCF = CFrame.fromMatrix(scale(g.HB), Vector3.xAxis, g.Axis, Vector3.xAxis:Cross(g.Axis))
	local pivot = PartKit.Box(b.Model, "Steer", Vector3.new(0.1, 0.1, 0.1), steerCF, BLACK, SMOOTH, { Transparency = 1 })
	add(b, "Steer", pivot)
	b.Groups.Steer.Pivot = pivot

	local tireHalf = geo.TireWidth / 2 + 0.025
	local forkW = if moto then 0.055 elseif style == "Hardtail" or style == "Enduro" or style == "Fat" or style == "Moped" then 0.045 else 0.03
	local suspended = moto or style == "Hardtail" or style == "Enduro" or style == "Fat" or style == "Moped" or style == "Cruiser" or style == "Cargo"
	-- the fork lowers slide up the steering axis with the suspension
	local forkPivot = PartKit.Box(b.Model, "Fork", Vector3.new(0.1, 0.1, 0.1), CFrame.fromMatrix(scale(g.FrontAxle), Vector3.xAxis, g.Axis, Vector3.xAxis:Cross(g.Axis)), BLACK, SMOOTH, { Transparency = 1 })
	add(b, "Fork", forkPivot)
	b.Groups.Fork.Pivot = forkPivot
	local crown = g.HB + g.Axis * 0.02
	for _, side in { -1, 1 } do
		local top = crown + Vector3.new(side * tireHalf, 0, 0)
		local bottom = g.FrontAxle + Vector3.new(side * tireHalf, 0, 0)
		if suspended then
			local mid = bottom:Lerp(top, 0.45)
			tube(b, "Steer", "Stanchion", scale(top), scale(mid), forkW, nil, if moto then Color3.fromRGB(200, 160, 40) else SILVER, METAL)
			-- the lower's top stays clear of the crown at full travel
			local travel = geo.FrontTravel or 0.2
			local legTop = math.min(0.53, 1 - (travel / g.Axis.Y + 0.05) / (top - bottom).Magnitude)
			tube(b, "Fork", "ForkLeg", scale(bottom:Lerp(top, legTop)), scale(bottom), forkW * 1.35, "Accent")
		else
			tube(b, "Steer", "ForkBlade", scale(top), scale(bottom), forkW, "Frame")
		end
	end
	box(b, "Steer", "Crown", Vector3.new((tireHalf * 2 + forkW * 1.6) * VIS, forkW * 1.4 * VIS, forkW * 2 * VIS), CFrame.fromMatrix(scale(crown), Vector3.xAxis, g.Axis, Vector3.xAxis:Cross(g.Axis)), "Frame")
	-- steerer / stem
	tube(b, "Steer", "Steerer", scale(g.HB), scale(g.HT), TUBE[style] * 1.25, "Frame")
	tube(b, "Steer", "Stem", scale(g.HT), scale(g.Bars), 0.035, nil, BLACK)
	-- bars
	local halfBar = geo.BarWidth / 2
	local barCenter = g.Bars
	if style == "Road" then
		-- drop bars: tops, then hooks forward and down
		local l, r = barCenter + Vector3.new(-halfBar, 0, 0), barCenter + Vector3.new(halfBar, 0, 0)
		tube(b, "Steer", "BarTop", scale(l), scale(r), 0.03, nil, BLACK)
		for _, side in { -1, 1 } do
			local s = barCenter + Vector3.new(side * halfBar, 0, 0)
			local hoodFront = s + Vector3.new(0, 0.02, -0.12)
			local drop = s + Vector3.new(0, -0.14, -0.08)
			local dropEnd = s + Vector3.new(0, -0.14, 0.03)
			tube(b, "Steer", "Hood", scale(s), scale(hoodFront), 0.03, nil, BLACK)
			tube(b, "Steer", "Drop", scale(hoodFront), scale(drop), 0.03, nil, BLACK)
			tube(b, "Steer", "DropEnd", scale(drop), scale(dropEnd), 0.03, nil, BLACK)
		end
	else
		local rise = if moto then 0.05 else 0
		tube(b, "Steer", "Handlebar", scale(barCenter + Vector3.new(-halfBar, rise, 0)), scale(barCenter + Vector3.new(halfBar, rise, 0)), if moto then 0.034 else 0.028, nil, BLACK, METAL)
		if moto then
			box(b, "Steer", "BarPad", Vector3.new(0.18 * VIS, 0.05 * VIS, 0.05 * VIS), CFrame.new(scale(barCenter + Vector3.new(0, rise + 0.03, 0))), "Accent")
		end
		for _, side in { -1, 1 } do
			local gripCenter = barCenter + Vector3.new(side * (halfBar - 0.06), rise, 0)
			cyl(b, "Steer", "Grip", 0.04, 0.12, CFrame.new(scale(gripCenter)), nil, Color3.fromRGB(20, 20, 20))
			-- brake lever
			bar(b, "Steer", "Lever", scale(gripCenter + Vector3.new(-side * 0.05, 0.01, -0.02)), scale(gripCenter + Vector3.new(side * 0.03, 0, -0.08)), 0.012, 0.01, nil, SILVER, METAL)
		end
	end
	local grip = barCenter + Vector3.new(-(halfBar - 0.07), if moto then 0.05 else 0, 0)
	local gripR = barCenter + Vector3.new(halfBar - 0.07, if moto then 0.05 else 0, 0)
	if style == "Road" then
		grip = barCenter + Vector3.new(-halfBar, 0.02, -0.1)
		gripR = barCenter + Vector3.new(halfBar, 0.02, -0.1)
	end
	PartKit.Attach(pivot, "GripL", scale(grip))
	PartKit.Attach(pivot, "GripR", scale(gripR))

	-- e-bike display on the bars
	local displayCF = CFrame.new(scale(barCenter + Vector3.new(0, 0.04, 0.02))) * CFrame.Angles(math.rad(-35), 0, 0)
	box(b, "Steer", "Display", Vector3.new(0.09 * VIS, 0.012 * VIS, 0.06 * VIS), displayCF, nil, BLACK)
	neon(b, "Steer", "Screen", Vector3.new(0.075 * VIS, 0.004 * VIS, 0.045 * VIS), displayCF * CFrame.new(0, 0.008 * VIS, 0), Color3.fromRGB(120, 230, 255))

	-- headlight
	local lampAt = if moto then g.HT + g.Axis * 0.02 + Vector3.new(0, -0.05, -0.12) else g.HT + Vector3.new(0, -0.02, -0.08)
	if moto then
		local kit = geo.Kit or "Dirt"
		local plateFrame = CFrame.fromMatrix(scale(lampAt + Vector3.new(0, 0.02, -0.02)), Vector3.xAxis, g.Axis, Vector3.xAxis:Cross(g.Axis))
		local lampColor = Color3.fromRGB(255, 250, 230)
		if kit == "Street" or kit == "Chopper" then
			-- round headlight in a chrome bowl, mirrors on stalks
			local lamp = lampAt + Vector3.new(0, 0.03, -0.03)
			cyl(b, "Steer", "LampBowl", 0.17, 0.1, CFrame.new(scale(lamp)) * CFrame.Angles(0, math.pi / 2, 0), nil, if kit == "Chopper" then SILVER else BLACK, METAL)
			neon(b, "Steer", "Headlight", Vector3.new(0.12 * VIS, 0.12 * VIS, 0.01 * VIS), CFrame.new(scale(lamp + Vector3.new(0, 0, -0.052))), lampColor)
			for _, side in { -1, 1 } do
				local base = g.Bars + Vector3.new(side * (geo.BarWidth / 2 - 0.12), 0.05, 0)
				local head = base + Vector3.new(side * 0.08, 0.2, 0.02)
				tube(b, "Steer", "MirrorStalk", scale(base), scale(head), 0.012, nil, BLACK, METAL)
				cyl(b, "Steer", "Mirror", 0.09, 0.02, CFrame.new(scale(head + Vector3.new(0, 0.03, 0))) * CFrame.Angles(0, math.pi / 2, 0), nil, BLACK)
			end
		else
			-- number plate with an LED (bigger, twin lamps on the enduro), white boards on the supermoto
			box(b, "Steer", "NumberPlate", Vector3.new(0.24 * VIS, 0.2 * VIS, 0.03 * VIS), plateFrame, if kit == "Supermoto" then nil else "Accent", if kit == "Supermoto" then Color3.fromRGB(240, 240, 240) else nil)
			if kit == "Enduro" then
				for _, side in { -1, 1 } do
					neon(b, "Steer", "Headlight", Vector3.new(0.06 * VIS, 0.06 * VIS, 0.02 * VIS), CFrame.new(scale(lampAt + Vector3.new(side * 0.04, 0.0, -0.045))), lampColor)
				end
			else
				neon(b, "Steer", "Headlight", Vector3.new(0.12 * VIS, 0.05 * VIS, 0.02 * VIS), CFrame.new(scale(lampAt + Vector3.new(0, 0.0, -0.045))), lampColor)
			end
		end
		if kit == "Enduro" then
			-- hand guards
			for _, side in { -1, 1 } do
				local gripAt = g.Bars + Vector3.new(side * (geo.BarWidth / 2 - 0.06), 0.05, 0)
				bar(b, "Steer", "HandGuard", scale(gripAt + Vector3.new(-side * 0.09, 0.02, -0.03)), scale(gripAt + Vector3.new(side * 0.05, 0.01, -0.08)), 0.1, 0.012, "Accent")
			end
		end
		-- front fender: high on the dirt bikes, hugging the tyre on the road ones
		if kit == "Supermoto" or kit == "Street" or kit == "Chopper" then
			-- a flat chord over the tyre: its ends at +-0.2 m are already below the top, so it clears
			local fTop = g.FrontAxle + Vector3.new(0, g.Rf + 0.045, 0)
			bar(b, "Fork", "Fender", scale(fTop + Vector3.new(0, 0, 0.16)), scale(fTop + Vector3.new(0, 0, -0.2)), geo.TireWidth + 0.04, 0.012, if kit == "Street" then "Frame" else "Accent")
		else
			-- high fender right under the lower crown, clear of the tyre over the fork's travel; where the
			-- fork is short of that (its length is capped by the bars) it sits higher, ahead of the crown
			local under = g.HB.Y - 0.05
			local fenderY = math.max(under, g.FrontAxle.Y + g.Rf + (geo.FrontTravel or 0.2) + 0.03)
			local fTop = Vector3.new(0, fenderY, g.FrontAxle.Z + (fenderY - g.FrontAxle.Y) * g.Axis.Z / g.Axis.Y)
			local back = if fenderY > under + 0.001 then -0.08 else 0.14
			bar(b, "Steer", "Fender", scale(fTop + Vector3.new(0, -0.02, back)), scale(fTop + Vector3.new(0, -0.03, -0.36)), geo.TireWidth + 0.01, 0.015, "Accent")
		end
	else
		cyl(b, "Steer", "LampBody", 0.07, 0.07, CFrame.new(scale(lampAt)) * CFrame.Angles(0, math.pi / 2, 0), nil, BLACK)
		neon(b, "Steer", "Headlight", Vector3.new(0.05 * VIS, 0.05 * VIS, 0.01 * VIS), CFrame.new(scale(lampAt + Vector3.new(0, 0, -0.04))), Color3.fromRGB(255, 250, 230))
	end

	-- front wheel on its own hub
	local hub = PartKit.Box(b.Model, "FrontHub", Vector3.new(0.1, 0.1, 0.1), CFrame.new(scale(g.FrontAxle)), BLACK, SMOOTH, { Transparency = 1 })
	add(b, "Front", hub)
	b.Groups.Front.Pivot = hub
	local kind = if moto then "Moto" else "Bike"
	wheel(b, "Front", scale(g.FrontAxle), g.Rf * 2, geo.TireWidth, kind, false)
end

local function rearWheel(b: Builder, bike: Bikes.Bike, g: Geo, moto: boolean)
	local swing = PartKit.Box(b.Model, "Swing", Vector3.new(0.1, 0.1, 0.1), CFrame.new(scale(g.Pivot)), BLACK, SMOOTH, { Transparency = 1 })
	add(b, "Swing", swing)
	b.Groups.Swing.Pivot = swing
	local hub = PartKit.Box(b.Model, "RearHub", Vector3.new(0.1, 0.1, 0.1), CFrame.new(scale(g.RearAxle)), BLACK, SMOOTH, { Transparency = 1 })
	add(b, "Rear", hub)
	b.Groups.Rear.Pivot = hub
	local hubMotor = bike.Drive == "Rear hub"
	wheel(b, "Rear", scale(g.RearAxle), g.Rr * 2, bike.Geometry.TireWidth, if moto then "Moto" else "Bike", hubMotor)
end

local function cranks(b: Builder, bike: Bikes.Bike, g: Geo)
	local crank = PartKit.Box(b.Model, "Crank", Vector3.new(0.1, 0.1, 0.1), CFrame.new(scale(g.BB)), BLACK, SMOOTH, { Transparency = 1 })
	add(b, "Crank", crank)
	b.Groups.Crank.Pivot = crank
	local armLength = 0.17
	local qWidth = 0.09
	cyl(b, "Crank", "Chainring", 0.19, 0.008, CFrame.new(scale(g.BB + Vector3.new(qWidth - 0.03, 0, 0))), nil, SILVER, METAL)
	for _, side in { -1, 1 } do
		-- right arm points down-forward at rest, left arm opposite
		local dir = Vector3.new(0, -1, 0) * side
		local foot = g.BB + Vector3.new(side * qWidth, 0, 0) + dir * armLength
		bar(b, "Crank", "CrankArm", scale(g.BB + Vector3.new(side * qWidth, 0, 0)), scale(foot), 0.02, 0.03, nil, BLACK)
		local pedal = box(b, "Crank", "Pedal", Vector3.new(0.1 * VIS, 0.02 * VIS, 0.08 * VIS), CFrame.new(scale(foot + Vector3.new(side * 0.06, 0, 0))), nil, Color3.fromRGB(40, 40, 40))
		PartKit.Attach(pedal :: BasePart, if side < 0 then "PedalL" else "PedalR", scale(foot + Vector3.new(side * 0.06, 0.03, 0)))
	end
	-- chain: top and bottom runs to the rear sprocket
	local sprocket = g.RearAxle + Vector3.new(qWidth - 0.03, 0, 0)
	local ring = g.BB + Vector3.new(qWidth - 0.03, 0, 0)
	tube(b, "Frame", "Chain", scale(ring + Vector3.new(0, 0.09, 0)), scale(sprocket + Vector3.new(0, 0.05, 0)), 0.012, nil, DARK, METAL)
	tube(b, "Frame", "Chain", scale(ring + Vector3.new(0, -0.09, 0)), scale(sprocket + Vector3.new(0, -0.05, 0)), 0.012, nil, DARK, METAL)
end

local function saddle(b: Builder, bike: Bikes.Bike, g: Geo)
	local style = bike.Geometry.Style
	tube(b, "Frame", "SeatPost", scale(g.ST), scale(g.SeatTop), 0.03, nil, if style == "Folding" then SILVER else BLACK, METAL)
	local width = if style == "Cruiser" then 0.24 elseif style == "Road" then 0.13 else 0.16
	local length = if style == "Cruiser" then 0.26 else 0.27
	local cf = CFrame.new(scale(g.SeatTop + Vector3.new(0, 0.03, 0.02))) * CFrame.Angles(math.rad(-4), 0, 0)
	box(b, "Frame", "Saddle", Vector3.new(width * VIS, 0.06 * VIS, length * VIS), cf, nil, Color3.fromRGB(30, 28, 26))
	box(b, "Frame", "SaddleNose", Vector3.new(width * 0.5 * VIS, 0.05 * VIS, 0.08 * VIS), cf * CFrame.new(0, 0, -length * 0.55 * VIS), nil, Color3.fromRGB(30, 28, 26))
end

local function battery(b: Builder, a: Vector3, c: Vector3, width: number, height: number, offsetUp: number)
	local dir = (c - a).Unit
	local up = Vector3.xAxis:Cross(dir)
	if up.Y < 0 then
		up = -up
	end
	local from, to = a + up * offsetUp, c + up * offsetUp
	bar(b, "Frame", "Battery", scale(from), scale(to), width, height, nil, Color3.fromRGB(36, 38, 42))
	bar(b, "Frame", "BatteryStripe", scale(from:Lerp(to, 0.15) + Vector3.new(0, 0, 0)), scale(from:Lerp(to, 0.85)), width + 0.004, height * 0.25, "Accent")
end

local function fender(b: Builder, axle: Vector3, radius: number, width: number, front: boolean)
	-- three flat segments over the top of the wheel
	local r = radius + 0.04
	local angles = if front then { 30, 70, 110, 150 } else { 30, 70, 110, 150 }
	for i = 1, #angles - 1 do
		local a0, a1 = math.rad(angles[i]), math.rad(angles[i + 1])
		local p0 = axle + Vector3.new(0, math.sin(a0) * r, -math.cos(a0) * r)
		local p1 = axle + Vector3.new(0, math.sin(a1) * r, -math.cos(a1) * r)
		bar(b, if front then "Steer" else "Frame", "Fender", scale(p0), scale(p1), width + 0.03, 0.012, "Accent")
	end
end

local function bicycle(b: Builder, bike: Bikes.Bike, g: Geo)
	local geo = bike.Geometry
	local style = geo.Style
	local t = TUBE[style] or 0.055
	local stay = t * 0.55
	local frame = "Frame"

	-- Main triangle
	if style == "Cruiser" then
		-- step-through: a low swooping down tube in two pieces plus a second parallel tube
		local low = g.BB + Vector3.new(0, 0.12, -0.18)
		tube(b, frame, "DownTube", scale(g.HB), scale(low), t * 1.1, frame)
		tube(b, frame, "DownTube2", scale(low), scale(g.BB), t * 1.1, frame)
		local loopTop = g.HB + g.Axis * 0.1 + Vector3.new(0, 0, 0)
		local loopLow = g.BB + Vector3.new(0, 0.24, -0.12)
		tube(b, frame, "LoopTube", scale(loopTop), scale(loopLow), t * 0.8, frame)
		tube(b, frame, "LoopTube2", scale(loopLow), scale(g.ST), t * 0.8, frame)
		battery(b, g.HB:Lerp(low, 0.15), g.HB:Lerp(low, 0.9), 0.09, 0.08, 0.06)
	elseif style == "Folding" then
		-- one big main beam with a hinge
		local mid = g.HB:Lerp(g.BB, 0.5) + Vector3.new(0, 0.12, 0)
		tube(b, frame, "MainBeam", scale(g.HB), scale(mid), t * 1.2, frame)
		tube(b, frame, "MainBeam2", scale(mid), scale(g.BB + Vector3.new(0, 0.05, 0)), t * 1.2, frame)
		box(b, frame, "Hinge", Vector3.new(t * 2 * VIS, t * 2 * VIS, t * 2 * VIS), CFrame.new(scale(mid)), "Accent")
		battery(b, mid + Vector3.new(0, -0.02, 0), g.BB + Vector3.new(0, 0.1, 0), 0.08, 0.08, 0.02)
	else
		tube(b, frame, "TopTube", scale(g.HT + g.Axis * -0.03), scale(g.ST), t * 0.9, frame)
		tube(b, frame, "DownTube", scale(g.HB), scale(g.BB), t * 1.15, frame)
		if style ~= "Cargo" then
			local integrated = style == "Hardtail" or style == "Enduro" or style == "Road"
			battery(b, g.HB:Lerp(g.BB, 0.12), g.HB:Lerp(g.BB, 0.78), if integrated then t * 1.3 else 0.085, if integrated then 0.06 else 0.08, if integrated then t * 0.4 else t * 0.5 + 0.04)
		end
	end
	tube(b, frame, "HeadTube", scale(g.HB), scale(g.HT), t * 1.35, frame)
	tube(b, frame, "SeatTube", scale(g.BB), scale(g.ST), t, frame)

	-- Rear triangle (or swingarm on full suspension)
	local axleHalf = bike.Geometry.TireWidth / 2 + 0.03
	if style == "Enduro" then
		local pivot = g.BB + Vector3.new(0, 0.08, 0.05)
		local rocker = g.ST:Lerp(g.BB, 0.45)
		for _, side in { -1, 1 } do
			local o = Vector3.new(side * axleHalf, 0, 0)
			bar(b, frame, "Swingarm", scale(pivot + o * 0.6), scale(g.RearAxle + o), 0.035, 0.05, frame)
			tube(b, frame, "SeatStay", scale(g.RearAxle + o), scale(rocker + o * 0.5 + Vector3.new(0, 0.1, 0.02)), 0.028, frame)
		end
		local shockTop = g.HT:Lerp(g.ST, 0.55) + Vector3.new(0, -0.03, 0)
		tube(b, frame, "Shock", scale(shockTop), scale(rocker + Vector3.new(0, 0.08, 0)), 0.045, nil, Color3.fromRGB(250, 120, 20))
		tube(b, frame, "ShockBody", scale(shockTop), scale(shockTop:Lerp(rocker, 0.5)), 0.06, nil, BLACK, METAL)
	else
		for _, side in { -1, 1 } do
			local o = Vector3.new(side * axleHalf, 0, 0)
			tube(b, frame, "ChainStay", scale(g.BB + o * 0.5), scale(g.RearAxle + o), stay, frame)
			local stayTop = if style == "Cargo" then g.ST + Vector3.new(0, -0.03, 0.02) else g.ST + Vector3.new(0, -0.02, 0.02)
			tube(b, frame, "SeatStay", scale(stayTop + o * 0.4), scale(g.RearAxle + o), stay * 0.9, frame)
		end
	end

	-- Mid-drive motor housing at the cranks
	if bike.Drive == "Mid-drive" then
		cyl(b, frame, "MidMotor", 0.17, 0.13, CFrame.new(scale(g.BB + Vector3.new(0, 0.02, -0.03))), nil, DARK, METAL)
		cyl(b, frame, "MotorCover", 0.12, 0.135, CFrame.new(scale(g.BB + Vector3.new(0, 0.02, -0.03))), "Accent")
	end

	-- Style extras
	if style == "City" or style == "Cruiser" then
		fender(b, g.FrontAxle, g.Rf, bike.Geometry.TireWidth, true)
		fender(b, g.RearAxle, g.Rr, bike.Geometry.TireWidth, false)
	end
	if style == "City" or style == "Cargo" or style == "Cruiser" then
		-- rear rack
		local rackTop = g.RearAxle + Vector3.new(0, g.Rr + 0.08, -0.03)
		local deckLength = if style == "Cargo" then 0.75 else 0.38
		local deckCenter = rackTop + Vector3.new(0, 0, if style == "Cargo" then -0.1 else -0.04)
		box(b, frame, "Rack", Vector3.new(0.18 * VIS, 0.02 * VIS, deckLength * VIS), CFrame.new(scale(deckCenter)), nil, if style == "Cargo" then Color3.fromRGB(150, 105, 60) else BLACK, if style == "Cargo" then Enum.Material.Wood else METAL)
		for _, side in { -1, 1 } do
			local o = Vector3.new(side * (axleHalf + 0.01), 0, 0)
			tube(b, frame, "RackStrut", scale(g.RearAxle + o), scale(deckCenter + o + Vector3.new(0, 0, deckLength * 0.35)), 0.016, nil, BLACK)
			if style == "Cargo" then
				-- running boards and bag
				box(b, frame, "RunningBoard", Vector3.new(0.12 * VIS, 0.015 * VIS, 0.5 * VIS), CFrame.new(scale(g.RearAxle + Vector3.new(side * 0.2, -0.1, -0.15))), nil, BLACK)
				box(b, frame, "Pannier", Vector3.new(0.06 * VIS, 0.24 * VIS, 0.36 * VIS), CFrame.new(scale(deckCenter + Vector3.new(side * 0.13, -0.15, 0.05))), "Accent")
			end
		end
		if style == "Cargo" then
			-- second battery under the deck
			box(b, frame, "Battery2", Vector3.new(0.1 * VIS, 0.08 * VIS, 0.36 * VIS), CFrame.new(scale(deckCenter + Vector3.new(0, -0.06, 0.05))), nil, Color3.fromRGB(36, 38, 42))
		end
		neon(b, frame, "Taillight", Vector3.new(0.06 * VIS, 0.03 * VIS, 0.01 * VIS), CFrame.new(scale(deckCenter + Vector3.new(0, 0, deckLength / 2 + 0.01))), Color3.fromRGB(255, 30, 30))
	else
		neon(b, frame, "Taillight", Vector3.new(0.04 * VIS, 0.05 * VIS, 0.012 * VIS), CFrame.new(scale(g.SeatTop + Vector3.new(0, -0.12, 0.06))), Color3.fromRGB(255, 30, 30))
	end
	if style == "Folding" then
		-- tall stem post already drawn; add a rear battery-mounted rack bar
		tube(b, frame, "SeatClamp", scale(g.ST + Vector3.new(0, -0.02, 0)), scale(g.ST + Vector3.new(0, 0.03, 0)), 0.06, "Accent")
	end
	-- kickstand
	tube(b, frame, "Kickstand", scale(g.BB + Vector3.new(-0.05, -0.02, 0.12)), scale(g.BB + Vector3.new(-0.18, -0.26, 0.3)), 0.016, nil, DARK)

	saddle(b, bike, g)
end

local function moped(b: Builder, bike: Bikes.Bike, g: Geo)
	-- Moto-73 style: a low beam frame, a battery box under a long bench, rear coil shocks, pedals
	local frame = "Frame"
	local low = g.BB + Vector3.new(0, 0.1, -0.05)
	bar(b, frame, "Beam", scale(g.HB), scale(low), 0.07, 0.09, frame)
	bar(b, frame, "Spine", scale(g.HT), scale(g.ST + Vector3.new(0, 0.08, -0.25)), 0.06, 0.07, frame)
	local benchFront = Vector3.new(0, bike.Geometry.SeatHeight - 0.03, g.BB.Z - 0.05)
	local benchBack = Vector3.new(0, bike.Geometry.SeatHeight + 0.01, g.RearAxle.Z + 0.08)
	-- battery box between beam and bench
	local boxCenter = (low + benchFront) / 2 + Vector3.new(0, -0.02, 0.12)
	box(b, frame, "BatteryBox", Vector3.new(0.2 * VIS, (benchFront.Y - low.Y) * 0.8 * VIS, 0.36 * VIS), CFrame.new(scale(boxCenter)), nil, Color3.fromRGB(36, 38, 42))
	box(b, frame, "SidePanel", Vector3.new(0.21 * VIS, 0.08 * VIS, 0.3 * VIS), CFrame.new(scale(boxCenter + Vector3.new(0, 0.02, 0))), "Accent")
	bar(b, frame, "Bench", scale(benchFront), scale(benchBack), 0.24, 0.09, nil, Color3.fromRGB(60, 42, 30))
	bar(b, frame, "BenchBase", scale(benchFront + Vector3.new(0, -0.06, 0)), scale(benchBack + Vector3.new(0, -0.06, 0)), 0.2, 0.04, frame)
	local axleHalf = bike.Geometry.TireWidth / 2 + 0.03
	for _, side in { -1, 1 } do
		local o = Vector3.new(side * axleHalf, 0, 0)
		bar(b, frame, "Swingarm", scale(g.BB + o * 0.6 + Vector3.new(0, 0.05, 0)), scale(g.RearAxle + o), 0.03, 0.05, frame)
		tube(b, frame, "Shock", scale(g.RearAxle + o + Vector3.new(0, 0.03, -0.03)), scale(benchBack + o * 0.8 + Vector3.new(0, -0.08, -0.12)), 0.045, nil, Color3.fromRGB(230, 60, 40))
	end
	-- rear fender + light
	local fTop = g.RearAxle + Vector3.new(0, g.Rr + 0.05, 0)
	bar(b, frame, "RearFender", scale(fTop + Vector3.new(0, 0.02, -0.15)), scale(fTop + Vector3.new(0, -0.05, 0.3)), bike.Geometry.TireWidth + 0.04, 0.015, frame)
	neon(b, frame, "Taillight", Vector3.new(0.1 * VIS, 0.04 * VIS, 0.015 * VIS), CFrame.new(scale(benchBack + Vector3.new(0, -0.05, 0.03))), Color3.fromRGB(255, 30, 30))
	cyl(b, frame, "HubMotorCover", 0.05, 0.02, CFrame.new(scale(g.RearAxle)), nil, BLACK)
end

local function moto(b: Builder, bike: Bikes.Bike, g: Geo)
	-- Light e-moto: big battery case, long flat seat, swingarm with a mono shock, footpegs
	local frame = "Frame"
	local pivot = g.Pivot
	local seatH = bike.Geometry.SeatHeight
	-- frame rails from the head down to the pivot
	for _, side in { -1, 1 } do
		local o = Vector3.new(side * 0.09, 0, 0)
		bar(b, frame, "FrameRail", scale(g.HT + o * 0.5), scale(pivot + o + Vector3.new(0, 0.12, 0)), 0.035, 0.06, nil, Color3.fromRGB(60, 62, 66), METAL)
		bar(b, frame, "FrameRailLow", scale(g.HB + o * 0.5), scale(pivot + o + Vector3.new(0, -0.08, 0)), 0.03, 0.05, nil, Color3.fromRGB(60, 62, 66), METAL)
	end
	-- battery case: a boxy centre section from behind the head tube back over the motor, with a
	-- sloped top panel ("tank") running from the head tube down to the seat
	-- (its front clears the front tyre at full travel: the axle slides back up the steering axis)
	local frontTravel = bike.Geometry.FrontTravel or 0.2
	local caseFrontZ = math.max(g.HT.Z + 0.07, g.FrontAxle.Z + frontTravel * g.Axis.Z / g.Axis.Y + g.Rf + 0.03)
	local caseRearZ = pivot.Z + 0.14
	local caseTopY = math.min(g.HT.Y - 0.12, seatH - 0.08) -- never above the seat
	local caseBottomY = pivot.Y - 0.02
	local caseCenter = Vector3.new(0, (caseTopY + caseBottomY) / 2, (caseFrontZ + caseRearZ) / 2)
	local caseSize = Vector3.new(0.2, caseTopY - caseBottomY, caseRearZ - caseFrontZ)
	local caseCF = CFrame.new(scale(caseCenter))
	box(b, frame, "BatteryCase", caseSize * VIS, caseCF, nil, Color3.fromRGB(40, 42, 46))
	for _, side in { -1, 1 } do
		box(b, frame, "SideCover", Vector3.new(0.02, caseSize.Y * 0.8, caseSize.Z * 0.9) * VIS, caseCF * CFrame.new(side * 0.11 * VIS, 0, 0), frame)
		box(b, frame, "Stripe", Vector3.new(0.022, 0.05, caseSize.Z * 0.75) * VIS, caseCF * CFrame.new(side * 0.112 * VIS, caseSize.Y * 0.2 * VIS, 0), "Accent")
	end
	local tankFront = g.HT + Vector3.new(0, -0.04, 0.04)
	local tankRear = Vector3.new(0, seatH - 0.05, caseRearZ - 0.02)
	bar(b, frame, "Tank", scale(tankFront), scale(tankRear), 0.22, 0.09, frame)
	local caseBack = Vector3.new(0, seatH - 0.12, caseRearZ)
	-- seat
	local seatFront = Vector3.new(0, seatH - 0.02, caseBack.Z - 0.1)
	local seatBack = Vector3.new(0, seatH + 0.04, g.RearAxle.Z - 0.05)
	bar(b, frame, "SeatPad", scale(seatFront), scale(seatBack), 0.22, 0.08, nil, Color3.fromRGB(28, 28, 30))
	-- tail section
	bar(b, frame, "Tail", scale(seatBack + Vector3.new(0, -0.035, -0.05)), scale(seatBack + Vector3.new(0, 0.02, 0.32)), 0.16, 0.05, frame)
	neon(b, frame, "Taillight", Vector3.new(0.08 * VIS, 0.03 * VIS, 0.015 * VIS), CFrame.new(scale(seatBack + Vector3.new(0, -0.03, 0.33))), Color3.fromRGB(255, 30, 30))
	local kit = bike.Geometry.Kit or "Dirt"
	if kit == "Street" or kit == "Chopper" then
		-- tail tidy with the plate
		local plate = seatBack + Vector3.new(0, -0.2, 0.36)
		box(b, frame, "PlateHanger", Vector3.new(0.05 * VIS, 0.16 * VIS, 0.02 * VIS), CFrame.new(scale(plate + Vector3.new(0, 0.1, -0.02))), nil, BLACK)
		box(b, frame, "Plate", Vector3.new(0.16 * VIS, 0.11 * VIS, 0.008 * VIS), CFrame.new(scale(plate)), nil, Color3.fromRGB(240, 240, 240))
	elseif kit == "Supermoto" then
		-- side number boards
		for _, side in { -1, 1 } do
			box(b, frame, "SideBoard", Vector3.new(0.01 * VIS, 0.12 * VIS, 0.2 * VIS), CFrame.new(scale(seatBack + Vector3.new(side * 0.085, -0.1, -0.05))), nil, Color3.fromRGB(240, 240, 240))
		end
	end
	-- motor and controller
	-- (back from the front tyre's full travel on the short pit bikes)
	local motorAt = Vector3.new(0, pivot.Y - 0.02, math.max(pivot.Z - 0.12, caseFrontZ + 0.1))
	cyl(b, frame, "Motor", 0.2, 0.16, CFrame.new(scale(motorAt)), nil, Color3.fromRGB(70, 72, 76), METAL)
	cyl(b, frame, "MotorCap", 0.12, 0.17, CFrame.new(scale(motorAt)), "Accent")
	-- swingarm + mono shock: the swingarm swings about the pivot; the shock's body (on the frame) and
	-- shaft (on the swingarm) each turn to keep pointing at the other, so it telescopes
	local axleHalf = bike.Geometry.TireWidth / 2 + 0.035
	for _, side in { -1, 1 } do
		local o = Vector3.new(side * axleHalf, 0, 0)
		bar(b, "Swing", "Swingarm", scale(pivot + o * 0.7), scale(g.RearAxle + o), 0.035, 0.07, nil, Color3.fromRGB(70, 72, 76), METAL)
	end
	for _, name in { "ShockTop", "ShockEnd" } do
		local at = if name == "ShockTop" then g.ShockTop else g.ShockBottom
		local mount = PartKit.Box(b.Model, name, Vector3.new(0.1, 0.1, 0.1), CFrame.new(scale(at)), BLACK, SMOOTH, { Transparency = 1 })
		add(b, name, mount)
		b.Groups[name].Pivot = mount
	end
	tube(b, "ShockTop", "ShockBody", scale(g.ShockTop), scale(g.ShockTop:Lerp(g.ShockBottom, 0.55)), 0.05, nil, Color3.fromRGB(240, 170, 20))
	tube(b, "ShockEnd", "ShockShaft", scale(g.ShockBottom), scale(g.ShockBottom:Lerp(g.ShockTop, 0.62)), 0.02, nil, SILVER, METAL)
	-- chain/belt drive to the rear sprocket
	tube(b, "Swing", "Belt", scale(pivot + Vector3.new(0.1, 0.0, -0.12)), scale(g.RearAxle + Vector3.new(0.1, 0.05, 0)), 0.015, nil, DARK, METAL)
	-- footpegs
	local pegL, pegR
	for _, side in { -1, 1 } do
		local peg = box(b, frame, "Footpeg", Vector3.new(0.1 * VIS, 0.025 * VIS, 0.05 * VIS), CFrame.new(scale(pivot + Vector3.new(side * 0.17, -0.05, -0.08))), nil, SILVER, METAL)
		if side < 0 then
			pegL = peg
		else
			pegR = peg
		end
	end
	if pegL and pegR then
		-- pegs at a real light e-moto's height (~0.37 m)
		PartKit.Attach(pegL :: BasePart, "PegL", scale(pivot + Vector3.new(-0.17, -0.02, -0.08)))
		PartKit.Attach(pegR :: BasePart, "PegR", scale(pivot + Vector3.new(0.17, -0.02, -0.08)))
	end
	-- (no rear hugger: the tail is the rear fender, and a hugger on the swingarm would rise into it)
	box(b, frame, "SeatAnchor", Vector3.new(0.1, 0.1, 0.1), CFrame.new(scale(seatFront:Lerp(seatBack, 0.35))), nil, BLACK).Transparency = 1
end

local function resolvePaints(bike: Bikes.Bike, choice: PaintChoice?): ({ Frame: Color3, Accent: Color3, Rims: Color3 }, { [string]: Enum.Material? })
	local colors = { Frame = bike.Colors.Frame, Accent = bike.Colors.Accent, Rims = bike.Colors.Rims }
	local materials: { [string]: Enum.Material? } = {}
	if choice then
		for _, slot in { "Frame", "Accent", "Rims" } do
			local id = (choice :: any)[slot]
			local paint = Paints.Get(id)
			if paint and paint.Kind == "Paint" and paint.Id ~= "stock" then
				(colors :: any)[slot] = paint.Color
				materials[slot] = paint.Material
			end
		end
	end
	return colors, materials
end

-- Recolour an existing bike (a respray in the Tuning menu)
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SOCKET_DARK = Color3.fromRGB(14, 10, 8)

local function flames(parent: BasePart, rate: number, speed: number)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 110, 20)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 80)
	fire.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Name = "Hellfire"
	e.Texture = FIRE_TEXTURE
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(speed * 0.7, speed)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 50, 0))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 30)
	light.Range = 10
	light.Brightness = 2
	light.Shadows = false
	light.Parent = parent
end

local function hellfire(b: Builder, bike: Bikes.Bike, g: Geo)
	local chrome = Color3.fromRGB(215, 218, 224)
	local pivotZ = g.RearAxle.Z - 0.58
	for _, side in { -1, 1 } do
		local a = Vector3.new(side * 0.13, 0.32, pivotZ - 0.1)
		local m = Vector3.new(side * 0.16, 0.3, pivotZ + 0.25)
		local c = Vector3.new(side * 0.17, 0.5, g.RearAxle.Z + 0.2)
		tube(b, "Frame", "ExhaustPipe", scale(a), scale(m), 0.05, nil, chrome, METAL)
		tube(b, "Frame", "ExhaustPipe", scale(m), scale(c), 0.055, nil, chrome, METAL)
		-- the tip points back; flames come out of its front face
		local tipCF = CFrame.lookAt(scale(c), scale(c + (c - m).Unit))
		local tip = PartKit.Box(b.Model, "ExhaustTip", Vector3.new(0.07, 0.07, 0.04) * VIS, tipCF, chrome, METAL)
		add(b, "Frame", tip, nil)
		flames(tip, 45, 9)
	end
	-- burning wheels: fire on each hub (it turns with the wheel)
	for _, groupName in { "Front", "Rear" } do
		local group = b.Groups[groupName]
		local hub = group and group.Pivot
		if hub then
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Heat = 4
			fire.Color = Color3.fromRGB(255, 90, 10)
			fire.SecondaryColor = Color3.fromRGB(255, 200, 60)
			fire.Parent = hub
			-- the wheel burns from its rim: flames off an invisible ring the size of the tyre
			local radius = if groupName == "Front" then g.Rf else g.Rr
			local ring = PartKit.Box(b.Model, "Hell_Ring", Vector3.new(bike.Geometry.TireWidth, radius * 2, radius * 2) * VIS, hub.CFrame, BLACK, SMOOTH, { Transparency = 1 })
			ring.Shape = Enum.PartType.Cylinder
			add(b, groupName, ring)
			local rim = Instance.new("ParticleEmitter")
			rim.Name = "Hellfire"
			rim.Texture = FIRE_TEXTURE
			rim.Shape = Enum.ParticleEmitterShape.Cylinder
			rim.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			rim.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			rim.Rate = 90
			rim.Lifetime = NumberRange.new(0.15, 0.35)
			rim.Speed = NumberRange.new(1, 3)
			rim.Acceleration = Vector3.new(0, 8, 0)
			rim.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) })
			rim.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			rim.Color = ColorSequence.new(Color3.fromRGB(255, 210, 80), Color3.fromRGB(255, 50, 0))
			rim.LightEmission = 1
			rim.LightInfluence = 0
			rim.Parent = ring
		end
	end

	-- bones: a spine of vertebrae along the tank and ribs wrapping the battery case
	local bone = Color3.fromRGB(226, 218, 192)
	local function blob(group: string, name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material?): BasePart
		local part = PartKit.Box(b.Model, name, size * VIS, CFrame.new(scale(at)), color, material or SMOOTH)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		return add(b, group, part)
	end
	local seatH = bike.Geometry.SeatHeight
	local spineFrom = g.HT + Vector3.new(0, 0.005, 0.07)
	local spineTo = Vector3.new(0, seatH + 0.0, g.Pivot.Z + 0.06)
	for i = 0, 8 do
		local at = spineFrom:Lerp(spineTo, i / 8) + Vector3.new(0, 0.035, 0)
		blob("Frame", "Hell_Vertebra", Vector3.new(0.075, 0.05, 0.055), at, bone)
		box(b, "Frame", "Hell_Spine", Vector3.new(0.018, 0.04, 0.025) * VIS, CFrame.new(scale(at + Vector3.new(0, 0.035, 0.01))) * CFrame.Angles(math.rad(-25), 0, 0), nil, bone)
	end
	for i = 1, 4 do
		local top = spineFrom:Lerp(spineTo, 0.2 + i * 0.15) + Vector3.new(0, 0.02, 0)
		for _, side in { -1, 1 } do
			local mid = top + Vector3.new(side * 0.13, -0.08, 0.01)
			local low = top + Vector3.new(side * 0.115, -0.2, 0.04)
			tube(b, "Frame", "Hell_Rib", scale(top), scale(mid), 0.02, nil, bone)
			tube(b, "Frame", "Hell_Rib", scale(mid), scale(low), 0.018, nil, bone)
		end
	end

	-- a skull for a headlight, its eyes the lamps
	local axis = g.Axis
	local ahead = Vector3.new(0, axis.Z, -axis.Y) -- forward, square to the steering axis
	local face = g.HB:Lerp(g.HT, 0.6) + ahead * 0.13
	blob("Steer", "Hell_Skull", Vector3.new(0.16, 0.15, 0.16), face, bone)
	blob("Steer", "Hell_Skull", Vector3.new(0.11, 0.08, 0.1), face + Vector3.new(0, -0.07, -0.03), bone)
	for _, side in { -1, 1 } do
		local eye = blob("Steer", "Hell_Eye", Vector3.new(0.045, 0.04, 0.03), face + Vector3.new(side * 0.035, 0.0, -0.07), Color3.fromRGB(255, 130, 20), Enum.Material.Neon)
		if side == 1 then
			local beam = Instance.new("SpotLight")
			beam.Color = Color3.fromRGB(255, 170, 80)
			beam.Range = 40
			beam.Angle = 50
			beam.Brightness = 3
			beam.Face = Enum.NormalId.Front
			beam.Parent = eye
		end
	end
	box(b, "Steer", "Hell_Teeth", Vector3.new(0.06, 0.015, 0.01) * VIS, CFrame.new(scale(face + Vector3.new(0, -0.075, -0.08))), nil, SOCKET_DARK)
end

function BikeModel.ApplyPaint(model: Model, bike: Bikes.Bike, choice: PaintChoice?)
	local colors, materials = resolvePaints(bike, choice)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local slot = d:GetAttribute("Paint")
			if type(slot) == "string" then
				local color = (colors :: any)[slot]
				if color then
					d.Color = color
					d.Material = materials[slot] or SMOOTH
				end
			end
		end
	end
	-- Underglow
	local glow = model:FindFirstChild("Underglow")
	if glow then
		glow:Destroy()
	end
	local glowPaint = if choice then Paints.Get(choice.Glow) else nil
	local root = model.PrimaryPart
	if glowPaint and glowPaint.Kind == "Glow" and root then
		local strip = Instance.new("Part")
		strip.Name = "Underglow"
		local size = model:GetAttribute("Scale")
		local vis = if type(size) == "number" then BASE_VIS * size else VIS
		strip.Size = Vector3.new(0.12, 0.05, bike.Geometry.Wheelbase * vis * 0.55)
		strip.CFrame = root.CFrame * CFrame.new(0, 0.35 * vis, 0)
		strip.Color = glowPaint.Color
		strip.Material = Enum.Material.Neon
		strip.CanCollide = false
		strip.CanQuery = false
		strip.CanTouch = false
		strip.Massless = true
		strip.CastShadow = false
		strip.Anchored = root.Anchored
		local light = Instance.new("PointLight")
		light.Color = glowPaint.Color
		light.Range = 12
		light.Brightness = 2.5
		light.Shadows = false
		light.Parent = strip
		if not root.Anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = strip
			weld.Parent = strip
		end
		strip.Parent = model
	end
end

local function motor(name: string, part0: BasePart, part1: BasePart): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	m.C1 = CFrame.identity
	m.Parent = part1
	return m
end

local build: (Bikes.Bike, PaintChoice?, Options?) -> Model

function BikeModel.Build(bike: Bikes.Bike, choice: PaintChoice?, options: Options?): Model
	local size = if options and options.Scale then math.clamp(options.Scale, 0.5, 3) else 1
	VIS = BASE_VIS * size
	local ok, result = pcall(build, bike, choice, options)
	VIS = BASE_VIS
	if not ok then
		error(result, 0)
	end
	result:SetAttribute("Scale", size)
	return result
end

build = function(bike: Bikes.Bike, choice: PaintChoice?, options: Options?): Model
	local static = options ~= nil and options.Static == true
	local colors, _ = resolvePaints(bike, choice)
	local model = Instance.new("Model")
	model.Name = bike.Id
	local b: Builder = { Model = model, Groups = {}, Colors = colors }
	local g = geometry(bike)
	local style = bike.Geometry.Style
	local isMoto = style == "Moto"

	local wheelbase = bike.Geometry.Wheelbase * VIS
	local root = PartKit.Box(model, "Root", Vector3.new(0.4, 0.2, wheelbase), CFrame.identity, BLACK, SMOOTH, { Transparency = 1, Collide = false, Query = false, Touch = false })
	root.Massless = false
	-- the bike, not the rider, is the root of the bike + rider assembly: its frame is what replicates,
	-- and each client places the rider on the seat itself
	root.RootPriority = 100
	model.PrimaryPart = root

	if isMoto then
		moto(b, bike, g)
	elseif style == "Moped" then
		moped(b, bike, g)
	else
		bicycle(b, bike, g)
	end
	-- the frame tubes of mopeds/motos sit on the HeadTube too
	if isMoto or style == "Moped" then
		tube(b, "Frame", "HeadTube", scale(g.HB), scale(g.HT), 0.08, "Frame")
	end
	frontEnd(b, bike, g, isMoto)
	rearWheel(b, bike, g, isMoto)
	if bike.Pedals then
		cranks(b, bike, g)
	end

	-- Imported Blender meshes replace the part-built look; joints, attachments and lamps stay
	if MeshKit.Has(bike.Id) then
		local _, materials = resolvePaints(bike, choice)
		local lamps = { Headlight = true, Taillight = true }
		for _, group in b.Groups do
			local pivot = group.Pivot
			local holder: BasePart = pivot or root
			local kept: { BasePart } = {}
			for _, part in group.Parts do
				if part == pivot then
					table.insert(kept, part)
					continue
				end
				for _, child in part:GetChildren() do
					if child:IsA("Attachment") then
						local world = part.CFrame * child.CFrame
						child.Parent = holder
						child.CFrame = holder.CFrame:ToObjectSpace(world)
					end
				end
				if lamps[part.Name] then
					part.Transparency = 1
					table.insert(kept, part)
				else
					part:Destroy()
				end
			end
			group.Parts = kept
		end
		for _, item in MeshKit.Place(model, bike.Id, VIS, colors :: any, materials :: any) do
			local group = b.Groups[item.Group]
			if not group then
				group = { Parts = {} }
				b.Groups[item.Group] = group
			end
			table.insert(group.Parts, item.Part)
		end
		-- the front sprocket spins and each chain run slides along itself (Visuals drives them): give
		-- them pivots. The sprocket's teeth are one ring, so its mesh's centre is the sprocket's.
		local sprocket = b.Groups.Sprocket
		if sprocket and #sprocket.Parts > 0 then
			local centre = sprocket.Parts[1].Position
			local sprocketHub = PartKit.Box(b.Model, "SprocketHub", Vector3.new(0.1, 0.1, 0.1), CFrame.new(centre), BLACK, SMOOTH, { Transparency = 1 })
			sprocketHub:SetAttribute("Radius", 0.104 * VIS) -- the rear sprocket's pitch radius: chain speed per wheel radian
			sprocket.Pivot = sprocketHub
			table.insert(sprocket.Parts, sprocketHub)
			-- the runs leave the sprocket 0.035 m above and below its centre and meet the rear sprocket
			-- 0.102 m out; links repeat every two plates (emoto.py lays plates ~0.019 m long)
			local rear = Vector3.new(centre.X, scale(g.RearAxle).Y, scale(g.RearAxle).Z)
			for _, entry in { { Name = "ChainTop", Sign = 1 }, { Name = "ChainBot", Sign = -1 } } do
				local name, sign = entry.Name, entry.Sign
				local run = b.Groups[name]
				if run and #run.Parts > 0 then
					local from = centre + Vector3.yAxis * (sign * 0.035 * VIS)
					local to = rear + Vector3.yAxis * (sign * 0.102 * VIS)
					local lengthM = (to - from).Magnitude / VIS
					local plates = math.max(4, math.floor(lengthM / 0.019))
					local hub = PartKit.Box(b.Model, name .. "Hub", Vector3.new(0.1, 0.1, 0.1), CFrame.new(from), BLACK, SMOOTH, { Transparency = 1 })
					hub:SetAttribute("Dir", (to - from).Unit)
					hub:SetAttribute("Period", 2 * lengthM / plates * VIS)
					run.Pivot = hub
					table.insert(run.Parts, hub)
				end
			end
		end
	end

	-- Hellfire (the Deathrider): chrome pipes breathing fire, and burning wheels
	if bike.Effects == "Hellfire" then
		hellfire(b, bike, g)
	end

	-- Seat: where the rider's hips go, tipped forward for the riding position
	local seatLean = if style == "Road" then -16 elseif style == "Hardtail" or style == "Enduro" then -10 elseif isMoto then -8 elseif style == "Cruiser" then 0 else -5
	-- on an e-moto the hips go a third of the way back along the seat pad (moto() builds the pad from
	-- RearAxle.Z - 0.54 to RearAxle.Z - 0.05), on its top
	local seatPoint = if isMoto then Vector3.new(0, bike.Geometry.SeatHeight + 0.04, g.RearAxle.Z - 0.39) elseif style == "Moped" then Vector3.new(0, bike.Geometry.SeatHeight - 0.01, g.BB.Z + 0.18) else g.SeatTop + Vector3.new(0, 0.05, 0.04)

	if not static then
		local seat = Instance.new("Seat")
		seat.Name = "Seat"
		seat.Size = Vector3.new(1, 0.2, 1)
		seat.CFrame = CFrame.new(scale(seatPoint) + Vector3.new(0, -0.1, 0)) * CFrame.Angles(math.rad(seatLean), 0, 0)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanTouch = false
		seat.CanQuery = false
		seat.Massless = true
		seat.Anchored = true
		seat.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = seat
		weld.Parent = seat

		-- Joints
		for groupName, group in b.Groups do
			local pivot = group.Pivot
			for _, part in group.Parts do
				if part ~= pivot then
					local w = Instance.new("WeldConstraint")
					w.Part0 = if groupName == "Frame" or pivot == nil then root else pivot
					w.Part1 = part
					w.Parent = part
				end
			end
		end
		local function pivotOf(name: string): BasePart?
			local group = b.Groups[name]
			return group and group.Pivot
		end
		local steer, fork, front = pivotOf("Steer"), pivotOf("Fork"), pivotOf("Front")
		local swing, rear, crank = pivotOf("Swing"), pivotOf("Rear"), pivotOf("Crank")
		local shockTop, shockEnd = pivotOf("ShockTop"), pivotOf("ShockEnd")
		if steer then
			motor("SteerJoint", root, steer)
		end
		if fork then
			motor("ForkSlide", steer or root, fork)
		end
		if front then
			motor("FrontSpin", fork or steer or root, front)
		end
		if swing then
			motor("SwingJoint", root, swing)
		end
		if rear then
			motor("RearSpin", swing or root, rear)
		end
		if shockTop then
			motor("ShockJoint", root, shockTop)
		end
		if shockEnd then
			motor("ShockRodJoint", swing or root, shockEnd)
		end
		if crank then
			motor("CrankSpin", root, crank)
		end
		local sprocketHub = pivotOf("Sprocket")
		if sprocketHub then
			motor("SprocketSpin", root, sprocketHub)
		end
		for _, name in { "ChainTop", "ChainBot" } do
			local hub = pivotOf(name)
			if hub then
				motor(name .. "Slide", swing or root, hub)
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				d.Anchored = false
			end
		end
	end

	model:SetAttribute("BikeId", bike.Id)
	if not (options ~= nil and options.Static == true) then
		-- with streaming on, a vehicle always arrives whole
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end
	BikeModel.ApplyPaint(model, bike, choice)
	Realism.Apply(model, "Vehicle")
	return model
end

-- The suspension's joints (model space, m), for drawing it
export type SuspensionGeo = {
	FrontAxle: Vector3,
	RearAxle: Vector3,
	Radius: { number }, -- [1] front, [2] rear
	Travel: { number },
	SinHead: number, -- the fork slides along the steering axis: this much of a slide is vertical
	Pivot: Vector3,
	ShockTop: Vector3,
	ShockBottom: Vector3,
	Scale: number, -- the bike is drawn this many times its size (the points above are at size 1)
}

function BikeModel.SuspensionGeometry(bike: Bikes.Bike, size: number?): SuspensionGeo
	local g = geometry(bike)
	return {
		Scale = size or 1,
		FrontAxle = g.FrontAxle,
		RearAxle = g.RearAxle,
		Radius = { g.Rf, g.Rr },
		Travel = { bike.Geometry.FrontTravel or 0.2, bike.Geometry.RearTravel or 0.2 },
		SinHead = math.max(0.3, g.Axis.Y),
		Pivot = g.Pivot,
		ShockTop = g.ShockTop,
		ShockBottom = g.ShockBottom,
	}
end

-- A model-space direction's angle in the bike's side plane, as CFrame.Angles(a, 0, 0) turns it
-- (turning by a takes the angle from x to x - a)
local function sideAngle(v: Vector3): number
	return math.atan2(v.Y, v.Z)
end

local function turnX(v: Vector3, a: number): Vector3
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end

export type SuspensionPose = { Fork: CFrame, Swing: CFrame, ShockTop: CFrame, ShockEnd: CFrame }

--[[
	The joint Transforms that draw the suspension compressed `front` / `rear` m (how far each axle has
	risen from top-out, along the chassis' normal): the fork lowers slide up the steering axis, the
	swingarm turns about its pivot until the rear axle has risen that much, and the shock's body and
	shaft turn to keep pointing at each other.
]]
function BikeModel.SuspensionPose(sus: SuspensionGeo, front: number, rear: number): SuspensionPose
	-- the compressions are real metres; the bike's points scale with its drawn size
	front = math.clamp(front, 0, sus.Travel[1] * 1.05 + 0.06)
	rear = math.clamp(rear, 0, sus.Travel[2] * 1.05 + 0.06)
	local k = sus.Scale
	local arm = (sus.RearAxle - sus.Pivot) * k
	local y = arm.Y + rear
	local z = math.sqrt(math.max(arm.Y * arm.Y + arm.Z * arm.Z - y * y, 1e-6))
	local swing = sideAngle(arm) - math.atan2(y, z)
	local rest = (sus.ShockBottom - sus.ShockTop) * k
	local now = (sus.Pivot - sus.ShockTop) * k + turnX((sus.ShockBottom - sus.Pivot) * k, swing)
	local body = sideAngle(rest) - sideAngle(now)
	return {
		Fork = CFrame.new(0, front / sus.SinHead * BASE_VIS, 0),
		Swing = CFrame.Angles(swing, 0, 0),
		ShockTop = CFrame.Angles(body, 0, 0),
		ShockEnd = CFrame.Angles(body - swing, 0, 0),
	}
end

-- The size (times BIKE_SIZE) to draw a bike so a rider whose legs measure `hipToAnkle` studs (hip
-- joint to ankle joint, standing) sits on it with the knees bent to ~85% of that, as on a real e-moto.
-- A default R15 avatar measures about 1.76.
function BikeModel.FitScale(bike: Bikes.Bike, hipToAnkle: number): number
	local g = geometry(bike)
	local seatPoint = Vector3.new(0, bike.Geometry.SeatHeight + 0.04, g.RearAxle.Z - 0.39)
	local peg = g.Pivot + Vector3.new(-0.17, -0.02, -0.08)
	local rider = hipToAnkle / 1.76
	local function reach(k: number): number
		local hip = seatPoint * BASE_VIS * k + Vector3.new(0, -0.1 * k + 0.21 * rider, 0)
		local ankle = peg * BASE_VIS * k + Vector3.new(0, 0.24 * rider, 0)
		return (hip - ankle).Magnitude
	end
	local want = 0.85 * hipToAnkle
	local lo, hi = 0.5, 3
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if reach(mid) < want then
			lo = mid
		else
			hi = mid
		end
	end
	return (lo + hi) / 2
end

-- The rider's foot rest points for e-motos (no pedals) and the seat height, for the rider pose
function BikeModel.HasPedals(bike: Bikes.Bike): boolean
	return bike.Pedals
end

return BikeModel
