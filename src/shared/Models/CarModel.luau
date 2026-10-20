--[[
	CarModel: police cruisers and city traffic, built from parts.

	Model space: origin on the ground at the car's centre, -Z forward. Runtime cars are one assembly
	welded to an invisible Root, with each wheel on a Motor6D ("Spin") the client turns. Police cars
	have a light bar whose lamps are named LightRed / LightBlue (the client flashes them, with the
	PointLights inside that throw the red and blue glow on the road).

	Collision is two invisible boxes (Body and Cabin), so the visible shell can be as detailed as it
	likes. The shell is a rounded-corner lower body, a greenhouse of raked glass (side windows are
	thick slabs whose top edge runs along the pillar, so the triangles fill without wedge parts),
	wheel arches, multi-spoke rims, lights with lenses, mirrors, plates and a basic interior seen
	through the tinted glass. Lights the client switches on at night are named "NightLight".

	The model's "Kind" attribute ("Cop" or "Car") tells the bike's collision sweep what it hit.
]]

local PartKit = require(script.Parent.Parent.PartKit)

local CarModel = {}

CarModel.SCALE = 3.2 -- studs per metre for cars (a touch under true scale, like the bikes)
local S = CarModel.SCALE
local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local BLACK = Color3.fromRGB(22, 22, 24)
local TRIM = Color3.fromRGB(34, 34, 37)
local TIRE = Color3.fromRGB(28, 28, 30)
local WINDOW = Color3.fromRGB(28, 36, 46)
local CHROME = Color3.fromRGB(205, 208, 214)
local INTERIOR = Color3.fromRGB(48, 46, 46)
local HEAD = Color3.fromRGB(255, 250, 232)
local TAIL = Color3.fromRGB(215, 18, 26)
local AMBER = Color3.fromRGB(255, 150, 20)

export type Kind = string -- "Police" | "Sedan" | "Hatch" | "SUV" | "Van" | "Taxi"
export type Options = { Static: boolean?, Color: Color3?, Plate: string? }

type Dims = {
	Length: number,
	Width: number,
	BodyHeight: number, -- lower body, clearance to beltline
	Clearance: number,
	CabinHeight: number, -- beltline to roof
	CabinLength: number, -- greenhouse length at the beltline
	Wheelbase: number,
	Wheel: number,
	Hood: number, -- fraction of the length ahead of the windscreen
	Rake: number, -- windscreen run as a multiple of the cabin height
	RearRake: number, -- rear window run as a multiple of the cabin height
	Trunk: boolean, -- three-box (sedan) rear: the rear quarter is metal, not glass
}

local DIMS: { [string]: Dims } = {
	Police = { Length = 5.1, Width = 1.95, BodyHeight = 0.62, Clearance = 0.2, CabinHeight = 0.5, CabinLength = 2.45, Wheelbase = 2.95, Wheel = 0.7, Hood = 0.28, Rake = 1.35, RearRake = 1.05, Trunk = true },
	Sedan = { Length = 4.8, Width = 1.84, BodyHeight = 0.58, Clearance = 0.17, CabinHeight = 0.5, CabinLength = 2.4, Wheelbase = 2.8, Wheel = 0.66, Hood = 0.28, Rake = 1.4, RearRake = 1.1, Trunk = true },
	Taxi = { Length = 4.8, Width = 1.84, BodyHeight = 0.58, Clearance = 0.17, CabinHeight = 0.5, CabinLength = 2.4, Wheelbase = 2.8, Wheel = 0.66, Hood = 0.28, Rake = 1.4, RearRake = 1.1, Trunk = true },
	Hatch = { Length = 4.1, Width = 1.78, BodyHeight = 0.58, Clearance = 0.16, CabinHeight = 0.56, CabinLength = 2.45, Wheelbase = 2.6, Wheel = 0.62, Hood = 0.24, Rake = 1.3, RearRake = 0.35, Trunk = false },
	SUV = { Length = 4.75, Width = 1.95, BodyHeight = 0.78, Clearance = 0.24, CabinHeight = 0.62, CabinLength = 2.95, Wheelbase = 2.85, Wheel = 0.76, Hood = 0.24, Rake = 1.05, RearRake = 0.25, Trunk = false },
	Van = { Length = 5.3, Width = 2.0, BodyHeight = 0.9, Clearance = 0.22, CabinHeight = 1.0, CabinLength = 4.4, Wheelbase = 3.3, Wheel = 0.7, Hood = 0.12, Rake = 0.55, RearRake = 0.05, Trunk = false },
}

local CIVILIAN_KINDS: { Kind } = { "Sedan", "Sedan", "Hatch", "Hatch", "SUV", "Van", "Taxi" }
CarModel.CivilianKinds = CIVILIAN_KINDS
CarModel.CivilianColors = {
	Color3.fromRGB(200, 30, 35),
	Color3.fromRGB(30, 70, 160),
	Color3.fromRGB(235, 235, 235),
	Color3.fromRGB(30, 30, 32),
	Color3.fromRGB(150, 152, 156),
	Color3.fromRGB(40, 110, 60),
	Color3.fromRGB(110, 70, 40),
	Color3.fromRGB(240, 170, 30),
	Color3.fromRGB(90, 160, 210),
}

local PLATE_LETTERS = "ABCDEFGHJKLMNPRSTUVWXYZ"

local function plateText(seed: number): string
	local rng = Random.new(seed)
	local a = rng:NextInteger(1, #PLATE_LETTERS)
	local b = rng:NextInteger(1, #PLATE_LETTERS)
	local c = rng:NextInteger(1, #PLATE_LETTERS)
	return string.format("%s%s%s %03d", string.sub(PLATE_LETTERS, a, a), string.sub(PLATE_LETTERS, b, b), string.sub(PLATE_LETTERS, c, c), rng:NextInteger(0, 999))
end

-- metres -> studs, keeping the rotation
local function M(cf: CFrame): CFrame
	return CFrame.new(cf.Position * S) * (cf - cf.Position)
end

function CarModel.Build(kind: Kind, options: Options?): Model
	local static = options ~= nil and options.Static == true
	local dims = DIMS[kind] or DIMS.Sedan
	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("Kind", if kind == "Police" then "Cop" else "Car")
	model:SetAttribute("CarKind", kind)
	local paint = if options and options.Color then options.Color elseif kind == "Police" then Color3.fromRGB(18, 18, 20) elseif kind == "Taxi" then Color3.fromRGB(250, 196, 18) else Color3.fromRGB(200, 30, 35)
	local police = kind == "Police"
	local white = Color3.fromRGB(242, 242, 242)

	local L, W = dims.Length, dims.Width
	local root = PartKit.Box(model, "Root", Vector3.new(0.4, 0.2, 0.4), CFrame.identity, BLACK, SMOOTH, { Transparency = 1, Collide = false, Query = false, Touch = false })
	model.PrimaryPart = root

	local body: { BasePart } = {}
	local function finish(p: BasePart, collide: boolean?): BasePart
		p.CanCollide = collide == true
		p.CanTouch = false
		p.CanQuery = collide == true
		p.Massless = true
		table.insert(body, p)
		return p
	end
	-- all sizes and positions below are metres
	local function box(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
		return finish(PartKit.Box(model, name, size * S, M(cf), color, material or SMOOTH)) :: Part
	end
	local function at(name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?): Part
		return box(name, size, CFrame.new(center), color, material)
	end
	local function cyl(name: string, diameter: number, length: number, cf: CFrame, color: Color3, material: Enum.Material?): Part
		return finish(PartKit.Cylinder(model, name, diameter * S, length * S, M(cf), color, material or SMOOTH)) :: Part
	end
	local function slab(name: string, from: Vector3, to: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material?): Part
		return finish(PartKit.Slab(model, name, from * S, to * S, width * S, thickness * S, color, material or SMOOTH)) :: Part
	end
	local function barTo(name: string, from: Vector3, to: Vector3, w: number, h: number, color: Color3, material: Enum.Material?): Part
		return finish(PartKit.Bar(model, name, from * S, to * S, w * S, h * S, color, material or SMOOTH)) :: Part
	end
	local function lamp(name: string, size: Vector3, center: Vector3, color: Color3): Part
		local p = at(name, size, center, color, Enum.Material.Neon)
		p.CastShadow = false
		return p
	end

	local clear = dims.Clearance
	local top = clear + dims.BodyHeight -- beltline
	local bodyY = clear + dims.BodyHeight / 2
	local roofY = top + dims.CabinHeight
	local cowlZ = -L / 2 + L * dims.Hood
	local roofFrontZ = cowlZ + dims.CabinHeight * dims.Rake
	local cabinEndZ = math.min(cowlZ + dims.CabinLength, L / 2 - 0.06)
	local roofBackZ = math.max(cabinEndZ - dims.CabinHeight * dims.RearRake, roofFrontZ + 0.4)
	local glassX = W * 0.445
	local roofW = W * 0.86

	-- Collision hull (invisible)
	local hull = finish(PartKit.Box(model, "Body", Vector3.new(W, dims.BodyHeight, L) * S, CFrame.new(0, bodyY * S, 0), paint, SMOOTH, { Transparency = 1 }), true)
	hull.Massless = false
	finish(PartKit.Box(model, "Cabin", Vector3.new(roofW, dims.CabinHeight, roofBackZ - roofFrontZ + 0.3) * S, CFrame.new(0, (top + dims.CabinHeight / 2) * S, (roofFrontZ + roofBackZ) / 2 * S), paint, SMOOTH, { Transparency = 1 }), true)

	-- Lower body: a rounded-corner slab
	local r = 0.2
	at("Shell", Vector3.new(W, dims.BodyHeight - 0.04, L - 2 * r), Vector3.new(0, bodyY + 0.02, 0), paint)
	for _, zs in { -1, 1 } do
		at("ShellEnd", Vector3.new(W - 2 * r, dims.BodyHeight - 0.04, r), Vector3.new(0, bodyY + 0.02, zs * (L / 2 - r / 2)), paint)
		for _, xs in { -1, 1 } do
			cyl("Corner", 2 * r, dims.BodyHeight - 0.04, CFrame.new(xs * (W / 2 - r), bodyY + 0.02, zs * (L / 2 - r)) * CFrame.Angles(0, 0, math.pi / 2), paint)
		end
	end
	-- Dark lower sills and a rounded shoulder along the beltline
	at("Sill", Vector3.new(W + 0.01, 0.1, dims.Wheelbase - dims.Wheel * 1.1), Vector3.new(0, clear + 0.05, 0), TRIM)
	for _, xs in { -1, 1 } do
		cyl("Shoulder", 0.07, L - 2 * r - 0.1, CFrame.new(xs * (W / 2 - 0.035), top - 0.02, 0) * CFrame.Angles(0, math.pi / 2, 0), paint)
	end
	-- Hood falls a little to the nose; the boot (or tailgate top) likewise
	slab("Hood", Vector3.new(0, top + 0.02, cowlZ), Vector3.new(0, top - 0.035, -L / 2 + 0.08), W - 0.14, 0.12, if police then white else paint)
	cyl("HoodNose", 0.09, W - 2 * r, CFrame.new(0, top - 0.06, -L / 2 + 0.06), if police then white else paint)
	if dims.Trunk then
		slab("Boot", Vector3.new(0, top + 0.035, cabinEndZ), Vector3.new(0, top + 0.01, L / 2 - 0.07), W - 0.14, 0.12, paint)
		cyl("BootLip", 0.08, W - 2 * r, CFrame.new(0, top - 0.02, L / 2 - 0.06), paint)
	end

	-- Greenhouse
	local cowl = Vector3.new(0, top, cowlZ)
	local roofFront = Vector3.new(0, roofY, roofFrontZ)
	local roofBack = Vector3.new(0, roofY, roofBackZ)
	local tail = Vector3.new(0, top, cabinEndZ)
	local function tint(p: BasePart)
		p.Transparency = 0.3
		p.Reflectance = 0.18
		p.CastShadow = false
	end
	tint(slab("Windscreen", cowl, roofFront, roofW + 0.02, 0.03, WINDOW, GLASS))
	tint(slab("RearWindow", roofBack, tail, roofW, 0.03, WINDOW, GLASS))
	local quarterIsMetal = dims.Trunk
	for _, xs in { -1, 1 } do
		local x = Vector3.new(xs * glassX, 0, 0)
		local depth = math.min(0.9, (roofBackZ - roofFrontZ) * 0.6)
		tint(slab("SideGlassFront", cowl + x, roofFront + x, 0.025, depth, WINDOW, GLASS))
		tint(at("SideGlass", Vector3.new(0.025, dims.CabinHeight, roofBackZ - roofFrontZ), Vector3.new(xs * glassX, top + dims.CabinHeight / 2, (roofFrontZ + roofBackZ) / 2), WINDOW, GLASS))
		tint(slab("SideGlassRear", roofBack + x, tail + x, 0.025, depth, WINDOW, GLASS))
		-- pillars and the window line
		barTo("APillar", cowl + x * 1.01, roofFront + x * 1.01, 0.07, 0.06, if police then white else paint)
		-- three-box cars get a broad C-pillar over the quarter glass
		local cPillar = barTo("CPillar", roofBack + x * 1.01, tail + x * 1.01, 0.07, if quarterIsMetal then 0.16 else 0.06, paint)
		cPillar.CFrame *= CFrame.new(0, -(if quarterIsMetal then 0.05 else 0) * S, 0)
		local bZ = roofFrontZ + (roofBackZ - roofFrontZ) * (if kind == "Van" then 0.18 else 0.48)
		at("BPillar", Vector3.new(0.035, dims.CabinHeight, 0.09), Vector3.new(xs * (glassX + 0.005), top + dims.CabinHeight / 2, bZ), BLACK)
		at("WindowLine", Vector3.new(0.03, 0.025, cabinEndZ - cowlZ), Vector3.new(xs * (glassX + 0.006), top + 0.012, (cowlZ + cabinEndZ) / 2), if kind == "Van" then BLACK else CHROME, if kind == "Van" then SMOOTH else METAL)
	end
	local roofColor = if police then white else paint
	at("Roof", Vector3.new(roofW, 0.06, roofBackZ - roofFrontZ), Vector3.new(0, roofY + 0.03, (roofFrontZ + roofBackZ) / 2), roofColor)
	for _, xs in { -1, 1 } do
		cyl("RoofEdge", 0.07, roofBackZ - roofFrontZ, CFrame.new(xs * roofW / 2, roofY + 0.025, (roofFrontZ + roofBackZ) / 2) * CFrame.Angles(0, math.pi / 2, 0), roofColor)
	end
	-- Interior, seen through the tint
	local seatY = clear + 0.25
	for _, row in { 0, 1 } do
		local z = roofFrontZ + 0.35 + row * 0.8
		if z < cabinEndZ - 0.3 then
			for _, xs in { -1, 1 } do
				at("SeatBase", Vector3.new(0.48, 0.14, 0.5), Vector3.new(xs * 0.4, seatY + 0.2, z), INTERIOR)
				slab("SeatBack", Vector3.new(xs * 0.4, seatY + 0.27, z + 0.25), Vector3.new(xs * 0.4, top + 0.12, z + 0.32), 0.46, 0.12, INTERIOR)
				at("Headrest", Vector3.new(0.24, 0.12, 0.08), Vector3.new(xs * 0.4, top + 0.2, z + 0.31), INTERIOR)
			end
		end
	end
	at("Dash", Vector3.new(W - 0.2, 0.16, 0.36), Vector3.new(0, top - 0.02, cowlZ + 0.2), Color3.fromRGB(30, 30, 32))
	cyl("SteeringWheel", 0.36, 0.04, CFrame.new(-0.4, top + 0.08, cowlZ + 0.48) * CFrame.Angles(math.rad(25), 0, 0) * CFrame.Angles(0, math.pi / 2, 0), BLACK)

	-- Front: bumper, grille, lights, plate
	local front = -L / 2
	local back = L / 2
	at("FrontBumper", Vector3.new(W - 0.18, 0.22, 0.1), Vector3.new(0, clear + 0.14, front - 0.02), if police then BLACK else paint)
	at("FrontLip", Vector3.new(W - 0.3, 0.06, 0.14), Vector3.new(0, clear + 0.02, front + 0.02), TRIM)
	local grille = at("Grille", Vector3.new(W * 0.46, 0.17, 0.03), Vector3.new(0, top - 0.17, front - 0.012), BLACK)
	for i = -1, 1 do
		at("GrilleBar", Vector3.new(W * 0.44, 0.012, 0.012), Vector3.new(0, top - 0.17 + i * 0.05, front - 0.03), if kind == "Van" or police then TRIM else CHROME, METAL)
	end
	local _ = grille
	for _, xs in { -1, 1 } do
		local hx = xs * (W / 2 - 0.36)
		at("HeadlightHousing", Vector3.new(0.34, 0.13, 0.05), Vector3.new(hx, top - 0.12, front - 0.005), BLACK)
		local head = lamp("Headlight", Vector3.new(0.3, 0.08, 0.02), Vector3.new(hx, top - 0.125, front - 0.03), HEAD)
		lamp("DRL", Vector3.new(0.3, 0.02, 0.02), Vector3.new(hx, top - 0.065, front - 0.03), Color3.fromRGB(235, 245, 255))
		local beam = Instance.new("SpotLight")
		beam.Name = "NightLight"
		beam.Face = Enum.NormalId.Front
		beam.Angle = 55
		beam.Range = 45
		beam.Brightness = 0
		beam.Shadows = false
		beam.Color = Color3.fromRGB(255, 244, 220)
		beam.Enabled = false
		beam.Parent = head
		at("FogLight", Vector3.new(0.1, 0.06, 0.02), Vector3.new(xs * (W / 2 - 0.32), clear + 0.12, front - 0.075), Color3.fromRGB(230, 230, 220), Enum.Material.Glass)
		lamp("Indicator", Vector3.new(0.02, 0.04, 0.09), Vector3.new(xs * (W / 2 + 0.004), top - 0.1, front + 0.4), AMBER)
	end
	local plateSeed = 0
	for i = 1, #kind do
		plateSeed += string.byte(kind, i) * i
	end
	local plate = if options and options.Plate then options.Plate elseif police then "POLICE" else plateText(plateSeed + math.floor((paint.R * 7 + paint.G * 13 + paint.B * 17) * 1000))
	local frontPlate = at("Plate", Vector3.new(0.5, 0.12, 0.012), Vector3.new(0, clear + 0.16, front - 0.08), white)
	PartKit.Sign(frontPlate, Enum.NormalId.Front, plate, Color3.fromRGB(20, 30, 70), nil, Enum.Font.GothamBold, 60)

	-- Rear: bumper, lights, plate, exhaust
	at("RearBumper", Vector3.new(W - 0.18, 0.22, 0.1), Vector3.new(0, clear + 0.14, back + 0.02), if police then BLACK else paint)
	at("Diffuser", Vector3.new(W - 0.4, 0.06, 0.12), Vector3.new(0, clear + 0.02, back - 0.02), TRIM)
	local tailY = if kind == "Van" or kind == "SUV" or kind == "Hatch" then top + 0.05 else top - 0.1
	for _, xs in { -1, 1 } do
		local tx = xs * (W / 2 - 0.3)
		at("TaillightHousing", Vector3.new(0.38, 0.14, 0.05), Vector3.new(tx, tailY, back + 0.005), BLACK)
		local light = lamp("Taillight", Vector3.new(0.34, 0.1, 0.02), Vector3.new(tx, tailY, back + 0.03), TAIL)
		lamp("TaillightWrap", Vector3.new(0.02, 0.1, 0.16), Vector3.new(xs * (W / 2 + 0.002), tailY, back - r * 0.9), TAIL)
		local glow = Instance.new("PointLight")
		glow.Name = "NightLight"
		glow.Color = TAIL
		glow.Range = 8
		glow.Brightness = 0
		glow.Shadows = false
		glow.Enabled = false
		glow.Parent = light
		at("Reverse", Vector3.new(0.08, 0.06, 0.02), Vector3.new(xs * (W / 2 - 0.55), tailY, back + 0.03), Color3.fromRGB(235, 235, 235), Enum.Material.Glass)
	end
	if dims.Trunk then
		lamp("TailStrip", Vector3.new(W - 1.1, 0.025, 0.02), Vector3.new(0, tailY + 0.03, back + 0.03), TAIL)
	end
	local rearPlate = at("Plate", Vector3.new(0.5, 0.12, 0.012), Vector3.new(0, clear + 0.3, back + 0.008), white)
	PartKit.Sign(rearPlate, Enum.NormalId.Back, plate, Color3.fromRGB(20, 30, 70), nil, Enum.Font.GothamBold, 60)
	cyl("Exhaust", 0.07, 0.16, CFrame.new(W / 2 - 0.4, clear + 0.04, back + 0.02) * CFrame.Angles(0, math.pi / 2, 0), CHROME, METAL)

	-- Sides: mirrors, handles, door seams, fuel cap
	for _, xs in { -1, 1 } do
		local mz = cowlZ + 0.12
		barTo("MirrorArm", Vector3.new(xs * (W / 2 - 0.05), top + 0.04, mz), Vector3.new(xs * (W / 2 + 0.1), top + 0.08, mz + 0.02), 0.04, 0.03, BLACK)
		at("Mirror", Vector3.new(0.16, 0.1, 0.07), Vector3.new(xs * (W / 2 + 0.14), top + 0.1, mz + 0.03), if police then BLACK else paint)
		local doors: { number } = if kind == "Van" then { cowlZ + 0.05, roofFrontZ + (roofBackZ - roofFrontZ) * 0.18 + 0.05, cabinEndZ - 0.05 } else { cowlZ + 0.05, roofFrontZ + (roofBackZ - roofFrontZ) * 0.48, cabinEndZ - 0.12 }
		for _, z in doors do
			at("DoorSeam", Vector3.new(0.012, dims.BodyHeight - 0.18, 0.01), Vector3.new(xs * (W / 2 + 0.002), clear + 0.1 + (dims.BodyHeight - 0.18) / 2, z), TRIM)
		end
		for i = 1, #doors - 1 do
			at("Handle", Vector3.new(0.02, 0.03, 0.14), Vector3.new(xs * (W / 2 + 0.008), top - 0.1, doors[i + 1] - 0.2), if police then BLACK else CHROME, METAL)
		end
	end
	cyl("FuelCap", 0.13, 0.012, CFrame.new(W / 2 + 0.001, top - 0.12, cabinEndZ + 0.08), paint)

	-- Wheels, each on a hub so they can spin, inside dark arches
	local wheels: { BasePart } = {}
	local rimColor = if police then Color3.fromRGB(70, 70, 74) elseif kind == "Van" then Color3.fromRGB(150, 152, 156) else CHROME
	local D = dims.Wheel
	for _, zs in { -1, 1 } do
		local axleZ = zs * dims.Wheelbase / 2
		cyl("Arch", D * 1.16, W + 0.012, CFrame.new(0, D / 2, axleZ), Color3.fromRGB(14, 14, 15))
		for _, xs in { -1, 1 } do
			local axle = Vector3.new(xs * (W / 2 - 0.1), D / 2, axleZ)
			local hubCF = CFrame.new(axle * S)
			local hub = PartKit.Box(model, "WheelHub", Vector3.new(0.1, 0.1, 0.1), hubCF, BLACK, SMOOTH, { Transparency = 1, Collide = false, Query = false, Touch = false })
			hub.Massless = true
			table.insert(wheels, hub)
			local wheelParts: { BasePart } = {}
			local function wpart(p: BasePart)
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.Massless = true
				table.insert(wheelParts, p)
			end
			local face = xs * 0.12 -- outer face offset
			wpart(PartKit.Cylinder(model, "Tire", D * S, 0.2 * S, hubCF, TIRE, SMOOTH))
			wpart(PartKit.Cylinder(model, "Sidewall", (D - 0.05) * S, 0.24 * S, hubCF, TIRE, SMOOTH))
			wpart(PartKit.Cylinder(model, "RimBarrel", D * 0.66 * S, 0.245 * S, hubCF, Color3.fromRGB(40, 40, 42), METAL))
			local faceCF = hubCF * CFrame.new(face * S, 0, 0)
			wpart(PartKit.Cylinder(model, "RimLip", D * 0.67 * S, 0.012 * S, faceCF, rimColor, METAL))
			wpart(PartKit.Cylinder(model, "RimWell", D * 0.6 * S, 0.016 * S, faceCF, Color3.fromRGB(30, 30, 32), METAL))
			local spokes = if kind == "SUV" then 6 elseif kind == "Van" then 8 else 5
			for i = 1, spokes do
				local angle = (i / spokes) * math.pi * 2
				local spokeCF = faceCF * CFrame.Angles(angle, 0, 0) * CFrame.new(0, D * 0.15 * S, 0)
				wpart(PartKit.Box(model, "RimSpoke", Vector3.new(0.022, D * 0.29, 0.07) * S, spokeCF, rimColor, METAL))
			end
			wpart(PartKit.Cylinder(model, "HubCap", 0.12 * S, 0.03 * S, faceCF, rimColor, METAL))
			for _, p in wheelParts do
				if not static then
					local w = Instance.new("WeldConstraint")
					w.Part0 = hub
					w.Part1 = p
					w.Parent = p
				end
			end
		end
	end

	-- Kind extras
	if police then
		-- black-and-white doors with POLICE, a push bar, a light bar and a spotlight
		for _, xs in { -1, 1 } do
			local door = at("DoorPanel", Vector3.new(0.012, dims.BodyHeight - 0.2, roofBackZ - cowlZ + 0.15), Vector3.new(xs * (W / 2 + 0.004), clear + 0.12 + (dims.BodyHeight - 0.2) / 2, (cowlZ + roofBackZ) / 2 + 0.08), white)
			PartKit.Sign(door, if xs > 0 then Enum.NormalId.Right else Enum.NormalId.Left, "POLICE", Color3.fromRGB(18, 22, 40), nil, Enum.Font.GothamBlack, 40)
			at("Stripe", Vector3.new(0.014, 0.05, roofBackZ - cowlZ + 0.15), Vector3.new(xs * (W / 2 + 0.006), top - 0.07, (cowlZ + roofBackZ) / 2 + 0.08), Color3.fromRGB(30, 80, 200))
		end
		local roofSign = at("RoofNumber", Vector3.new(0.6, 0.004, 0.4), Vector3.new(0, roofY + 0.062, roofBackZ - 0.35), white)
		PartKit.Sign(roofSign, Enum.NormalId.Top, "17", Color3.fromRGB(18, 22, 40), nil, Enum.Font.GothamBlack, 40)
		-- push bar
		for _, xs in { -1, 1 } do
			barTo("PushUpright", Vector3.new(xs * 0.35, clear + 0.08, front - 0.12), Vector3.new(xs * 0.35, top - 0.02, front - 0.14), 0.05, 0.05, BLACK)
		end
		at("PushBar", Vector3.new(0.86, 0.05, 0.05), Vector3.new(0, top - 0.06, front - 0.14), BLACK)
		at("PushBarLow", Vector3.new(0.86, 0.05, 0.05), Vector3.new(0, clear + 0.18, front - 0.14), BLACK)
		-- light bar: base, three red lamps on the driver's side, three blue on the other, white takedowns
		local barZ = roofFrontZ + 0.3
		local barY = roofY + 0.1
		at("LightBarBase", Vector3.new(W * 0.84, 0.05, 0.28), Vector3.new(0, barY - 0.03, barZ), BLACK)
		for _, xs in { -1, 1 } do
			at("LightBarFoot", Vector3.new(0.06, 0.06, 0.2), Vector3.new(xs * W * 0.35, roofY + 0.06, barZ), BLACK)
		end
		local segments = 3
		local span = W * 0.36
		for _, xs in { -1, 1 } do
			for i = 1, segments do
				local x = xs * (0.1 + (i - 0.5) * span / segments)
				local p = lamp(if xs < 0 then "LightRed" else "LightBlue", Vector3.new(span / segments - 0.02, 0.09, 0.24), Vector3.new(x, barY + 0.04, barZ), if xs < 0 then Color3.fromRGB(255, 30, 40) else Color3.fromRGB(40, 90, 255))
				p.Transparency = 0.1
				if i == 2 then
					local light = Instance.new("PointLight")
					light.Name = "Glow"
					light.Color = p.Color
					light.Range = 26
					light.Brightness = 0
					light.Shadows = false
					light.Parent = p
				end
			end
		end
		lamp("Takedown", Vector3.new(0.16, 0.08, 0.25), Vector3.new(0, barY + 0.035, barZ), Color3.fromRGB(240, 240, 255)).Transparency = 0.3
		cyl("Spotlight", 0.11, 0.12, CFrame.new(-glassX - 0.08, top + 0.15, cowlZ + 0.25) * CFrame.Angles(0, math.pi / 2, 0), CHROME, METAL)
		barTo("Antenna", Vector3.new(0.3, roofY + 0.06, roofBackZ - 0.1), Vector3.new(0.3, roofY + 0.5, roofBackZ + 0.05), 0.012, 0.012, BLACK)
		-- grille strobes
		for _, xs in { -1, 1 } do
			lamp(if xs < 0 then "LightRed" else "LightBlue", Vector3.new(0.12, 0.04, 0.02), Vector3.new(xs * 0.14, top - 0.17, front - 0.04), if xs < 0 then Color3.fromRGB(255, 30, 40) else Color3.fromRGB(40, 90, 255))
		end
	elseif kind == "Taxi" then
		local sign = at("TaxiSign", Vector3.new(0.6, 0.18, 0.22), Vector3.new(0, roofY + 0.15, (roofFrontZ + roofBackZ) / 2), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
		sign.CastShadow = false
		PartKit.Sign(sign, Enum.NormalId.Front, "TAXI", Color3.fromRGB(20, 20, 20), nil, Enum.Font.GothamBlack, 40)
		PartKit.Sign(sign, Enum.NormalId.Back, "TAXI", Color3.fromRGB(20, 20, 20), nil, Enum.Font.GothamBlack, 40)
		at("TaxiSignBase", Vector3.new(0.5, 0.05, 0.18), Vector3.new(0, roofY + 0.07, (roofFrontZ + roofBackZ) / 2), BLACK)
		-- checker band along both sides
		local squares = 14
		local runStart, runEnd = cowlZ + 0.1, cabinEndZ - 0.05
		local size = (runEnd - runStart) / squares
		for _, xs in { -1, 1 } do
			for i = 0, squares - 1 do
				for row = 0, 1 do
					if (i + row) % 2 == 0 then
						at("Checker", Vector3.new(0.008, 0.05, size), Vector3.new(xs * (W / 2 + 0.004), top - 0.2 + row * 0.05, runStart + (i + 0.5) * size), BLACK)
					end
				end
			end
		end
	elseif kind == "SUV" then
		for _, xs in { -1, 1 } do
			at("RoofRail", Vector3.new(0.04, 0.04, roofBackZ - roofFrontZ - 0.1), Vector3.new(xs * (roofW / 2 - 0.08), roofY + 0.09, (roofFrontZ + roofBackZ) / 2), BLACK)
		end
		cyl("SpareTire", 0.66, 0.2, CFrame.new(0, top + 0.05, back + 0.12) * CFrame.Angles(0, math.pi / 2, 0), TIRE)
		cyl("SpareCover", 0.5, 0.21, CFrame.new(0, top + 0.05, back + 0.12) * CFrame.Angles(0, math.pi / 2, 0), paint)
		at("SkidPlate", Vector3.new(W * 0.6, 0.05, 0.3), Vector3.new(0, clear + 0.02, front + 0.1), Color3.fromRGB(150, 152, 156), METAL)
	elseif kind == "Van" then
		at("SlidingRail", Vector3.new(0.02, 0.03, cabinEndZ - roofFrontZ - 1.1), Vector3.new(W / 2 + 0.008, top - 0.05, (roofFrontZ + cabinEndZ) / 2 + 0.5), TRIM)
		for i = 0, 2 do
			at("RoofBar", Vector3.new(roofW - 0.1, 0.04, 0.05), Vector3.new(0, roofY + 0.1, roofFrontZ + 0.8 + i * 1.0), BLACK)
		end
	end

	if not static then
		for _, p in body do
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
		for _, hub in wheels do
			local motor = Instance.new("Motor6D")
			motor.Name = "Spin"
			motor.Part0 = root
			motor.Part1 = hub
			motor.C0 = root.CFrame:ToObjectSpace(hub.CFrame)
			motor.Parent = hub
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				d.Anchored = false
			end
		end
	end
	return model
end

-- Half-length and half-width in studs (for AI spacing)
function CarModel.Extents(kind: Kind): (number, number)
	local dims = DIMS[kind] or DIMS.Sedan
	return dims.Length * S / 2, dims.Width * S / 2
end

function CarModel.WheelRadius(kind: Kind): number
	local dims = DIMS[kind] or DIMS.Sedan
	return dims.Wheel * S / 2
end

return CarModel
