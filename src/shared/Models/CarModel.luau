--[[
	CarModel: police cruisers and city traffic, built from parts.

	Model space: origin on the ground at the car's centre, -Z forward. Runtime cars are one assembly
	welded to an invisible Root, with each wheel on a Motor6D ("Spin") the client turns. Police cars
	have a light bar whose lamps are named LightRed / LightBlue (the client flashes them, with the
	PointLights inside that throw the red and blue glow on the road).

	The model's "Kind" attribute ("Cop" or "Car") tells the bike's collision sweep what it hit.
]]

local PartKit = require(script.Parent.Parent.PartKit)

local CarModel = {}

CarModel.SCALE = 3.2 -- studs per metre for cars (a touch under true scale, like the bikes)
local S = CarModel.SCALE
local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local BLACK = Color3.fromRGB(22, 22, 24)
local TIRE = Color3.fromRGB(30, 30, 32)
local WINDOW = Color3.fromRGB(40, 52, 64)

export type Kind = string -- "Police" | "Sedan" | "Hatch" | "SUV" | "Van" | "Taxi"
export type Options = { Static: boolean?, Color: Color3? }

type Dims = {
	Length: number,
	Width: number,
	BodyHeight: number, -- lower body
	Clearance: number,
	CabinHeight: number,
	CabinLength: number,
	CabinOffset: number, -- +back
	Wheelbase: number,
	Wheel: number,
	Hood: number, -- fraction of the length ahead of the windscreen
}

local DIMS: { [string]: Dims } = {
	Police = { Length = 5.2, Width = 1.95, BodyHeight = 0.62, Clearance = 0.2, CabinHeight = 0.5, CabinLength = 2.3, CabinOffset = 0.25, Wheelbase = 2.9, Wheel = 0.7, Hood = 0.3 },
	Sedan = { Length = 4.8, Width = 1.85, BodyHeight = 0.6, Clearance = 0.18, CabinHeight = 0.48, CabinLength = 2.2, CabinOffset = 0.2, Wheelbase = 2.75, Wheel = 0.66, Hood = 0.3 },
	Taxi = { Length = 4.8, Width = 1.85, BodyHeight = 0.6, Clearance = 0.18, CabinHeight = 0.48, CabinLength = 2.2, CabinOffset = 0.2, Wheelbase = 2.75, Wheel = 0.66, Hood = 0.3 },
	Hatch = { Length = 4.1, Width = 1.78, BodyHeight = 0.6, Clearance = 0.17, CabinHeight = 0.55, CabinLength = 2.2, CabinOffset = 0.45, Wheelbase = 2.55, Wheel = 0.62, Hood = 0.27 },
	SUV = { Length = 4.8, Width = 1.95, BodyHeight = 0.78, Clearance = 0.25, CabinHeight = 0.62, CabinLength = 2.8, CabinOffset = 0.45, Wheelbase = 2.85, Wheel = 0.76, Hood = 0.24 },
	Van = { Length = 5.3, Width = 2.0, BodyHeight = 0.9, Clearance = 0.22, CabinHeight = 1.05, CabinLength = 3.9, CabinOffset = 0.55, Wheelbase = 3.3, Wheel = 0.7, Hood = 0.14 },
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

function CarModel.Build(kind: Kind, options: Options?): Model
	local static = options ~= nil and options.Static == true
	local dims = DIMS[kind] or DIMS.Sedan
	local model = Instance.new("Model")
	model.Name = kind
	model:SetAttribute("Kind", if kind == "Police" then "Cop" else "Car")
	model:SetAttribute("CarKind", kind)
	local paint = if options and options.Color then options.Color elseif kind == "Police" then BLACK elseif kind == "Taxi" then Color3.fromRGB(250, 200, 20) else Color3.fromRGB(200, 30, 35)

	local L, W = dims.Length, dims.Width
	local root = PartKit.Box(model, "Root", Vector3.new(0.4, 0.2, 0.4), CFrame.identity, BLACK, SMOOTH, { Transparency = 1, Collide = false, Query = false, Touch = false })
	model.PrimaryPart = root

	local body: { BasePart } = {}
	local function part(name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?, collide: boolean?): Part
		local p = PartKit.Box(model, name, size * S, CFrame.new(center * S), color, material or SMOOTH)
		p.CanCollide = collide == true
		p.CanTouch = false
		p.CanQuery = collide == true
		p.Massless = true
		table.insert(body, p)
		return p
	end

	local bodyY = dims.Clearance + dims.BodyHeight / 2
	-- Lower body is the collision hull
	local hull = part("Body", Vector3.new(W, dims.BodyHeight, L), Vector3.new(0, bodyY, 0), paint, SMOOTH, true)
	hull.Massless = false
	local top = dims.Clearance + dims.BodyHeight
	-- Cabin
	local cabinZ = -L / 2 + L * dims.Hood + dims.CabinLength / 2 + 0.0
	cabinZ = cabinZ + (dims.CabinOffset - 0.2) * 0.3
	local cabin = part("Cabin", Vector3.new(W * 0.9, dims.CabinHeight, dims.CabinLength), Vector3.new(0, top + dims.CabinHeight / 2, cabinZ), WINDOW, GLASS, true)
	cabin.Reflectance = 0.15
	local roofColor = if kind == "Police" then Color3.fromRGB(245, 245, 245) else paint
	part("Roof", Vector3.new(W * 0.86, 0.06, dims.CabinLength * 0.82), Vector3.new(0, top + dims.CabinHeight + 0.03, cabinZ + 0.05), roofColor)
	-- Pillars
	for _, side in { -1, 1 } do
		part("PillarB", Vector3.new(0.04, dims.CabinHeight, 0.1), Vector3.new(side * W * 0.451, top + dims.CabinHeight / 2, cabinZ + 0.05), roofColor)
		part("Mirror", Vector3.new(0.12, 0.08, 0.1), Vector3.new(side * (W / 2 + 0.05), top + 0.12, cabinZ - dims.CabinLength / 2 + 0.05), paint)
	end
	-- Bumpers, grille, lights
	part("FrontBumper", Vector3.new(W * 0.98, 0.18, 0.12), Vector3.new(0, dims.Clearance + 0.12, -L / 2 - 0.03), Color3.fromRGB(45, 45, 48))
	part("RearBumper", Vector3.new(W * 0.98, 0.18, 0.12), Vector3.new(0, dims.Clearance + 0.12, L / 2 + 0.03), Color3.fromRGB(45, 45, 48))
	part("Grille", Vector3.new(W * 0.5, 0.16, 0.04), Vector3.new(0, top - 0.17, -L / 2 - 0.01), BLACK)
	for _, side in { -1, 1 } do
		local head = part("Headlight", Vector3.new(0.32, 0.1, 0.03), Vector3.new(side * (W / 2 - 0.25), top - 0.12, -L / 2 - 0.01), Color3.fromRGB(255, 250, 225), Enum.Material.Neon)
		head.CastShadow = false
		local tail = part("Taillight", Vector3.new(0.3, 0.1, 0.03), Vector3.new(side * (W / 2 - 0.24), top - 0.12, L / 2 + 0.01), Color3.fromRGB(220, 20, 25), Enum.Material.Neon)
		tail.CastShadow = false
	end

	if kind == "Police" then
		-- White doors (black-and-white livery), POLICE text, push bar, light bar
		for _, side in { -1, 1 } do
			local door = part("DoorPanel", Vector3.new(0.03, dims.BodyHeight * 0.92, dims.CabinLength * 0.95), Vector3.new(side * (W / 2 + 0.012), bodyY + 0.02, cabinZ), Color3.fromRGB(245, 245, 245))
			PartKit.Sign(door, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, "POLICE", Color3.fromRGB(20, 20, 30), nil, Enum.Font.GothamBlack, 40)
		end
		part("PushBar", Vector3.new(W * 0.7, 0.4, 0.08), Vector3.new(0, dims.Clearance + 0.3, -L / 2 - 0.15), BLACK)
		local barY = top + dims.CabinHeight + 0.1
		part("LightBarBase", Vector3.new(W * 0.8, 0.08, 0.26), Vector3.new(0, barY, cabinZ - 0.1), BLACK)
		for _, side in { -1, 1 } do
			local lamp = part(if side < 0 then "LightRed" else "LightBlue", Vector3.new(W * 0.36, 0.1, 0.22), Vector3.new(side * W * 0.2, barY + 0.08, cabinZ - 0.1), if side < 0 then Color3.fromRGB(255, 30, 40) else Color3.fromRGB(40, 90, 255), Enum.Material.Neon)
			lamp.CastShadow = false
			lamp.Transparency = 0.1
			local light = Instance.new("PointLight")
			light.Name = "Glow"
			light.Color = lamp.Color
			light.Range = 26
			light.Brightness = 0
			light.Shadows = false
			light.Parent = lamp
		end
	elseif kind == "Taxi" then
		local sign = part("TaxiSign", Vector3.new(0.5, 0.16, 0.22), Vector3.new(0, top + dims.CabinHeight + 0.14, cabinZ), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
		PartKit.Sign(sign, Enum.NormalId.Front, "TAXI", Color3.fromRGB(20, 20, 20), nil, Enum.Font.GothamBlack, 40)
	end

	-- Wheels (each on a hub so they can spin)
	local wheels: { BasePart } = {}
	for _, zs in { -1, 1 } do
		for _, xs in { -1, 1 } do
			local axle = Vector3.new(xs * (W / 2 - 0.13), dims.Wheel / 2, zs * dims.Wheelbase / 2)
			local hub = PartKit.Box(model, "WheelHub", Vector3.new(0.1, 0.1, 0.1), CFrame.new(axle * S), BLACK, SMOOTH, { Transparency = 1, Collide = false, Query = false, Touch = false })
			hub.Massless = true
			local tire = PartKit.Cylinder(model, "Tire", dims.Wheel * S, 0.24 * S, CFrame.new(axle * S), TIRE, SMOOTH, { Collide = false, Query = false, Touch = false })
			tire.Massless = true
			local rim = PartKit.Cylinder(model, "Rim", dims.Wheel * 0.62 * S, 0.25 * S, CFrame.new(axle * S), if kind == "Police" then Color3.fromRGB(60, 60, 64) else Color3.fromRGB(190, 192, 196), Enum.Material.Metal, { Collide = false, Query = false, Touch = false })
			rim.Massless = true
			table.insert(wheels, hub)
			if not static then
				for _, p in { tire, rim } do
					local w = Instance.new("WeldConstraint")
					w.Part0 = hub
					w.Part1 = p
					w.Parent = p
				end
			end
			-- dark wheel arch
			part("Arch", Vector3.new(0.27, 0.12, dims.Wheel * 1.05), Vector3.new(xs * (W / 2 - 0.12), dims.Wheel + 0.02, zs * dims.Wheelbase / 2), BLACK)
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
