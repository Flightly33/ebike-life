--[[
	Detail: the small things that make the city read as real at street level: window grids with
	frames and sills, shopfronts, fire escapes, rooftop clutter, and street furniture (bus stops,
	bike racks, benches, bins, bollards, street-name signs, tree grates, manholes, drains, parking
	meters, news boxes), garden bits for houses, and a few vehicle-sized props (box trucks, pallets).

	Design units like the other builders (1 stud = 0.28 m); the Builder shrinks the finished city.
	A "face" is a CFrame on a building wall at ground level whose LookVector points out to the street.
	Almost everything here is decoration: no collisions, no queries, and small parts cast no shadow.
]]

local PartKit = require(script.Parent.Parent.PartKit)

local Detail = {}

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass
local CONCRETE = Enum.Material.Concrete
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local SOLID_DECOR = { Collide = false, Query = false, Touch = false }
local SOLID = { Touch = false }

local DARK = Color3.fromRGB(34, 36, 40)
local STEEL = Color3.fromRGB(70, 74, 80)
local LIGHT_STEEL = Color3.fromRGB(160, 164, 170)
local WINDOW = Color3.fromRGB(58, 78, 98)

Detail.Window = WINDOW

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- The CFrame on the outside of a box building's face: center (cx, cz), the face whose outward
-- normal is `out` (an axis vector), half-depth along `out`, at height y
function Detail.Face(cx: number, cz: number, out: Vector3, halfDepth: number, y: number): CFrame
	local p = Vector3.new(cx, y, cz) + out * halfDepth
	return CFrame.lookAt(p, p + out)
end

export type WindowStyle = {
	Width: number,
	Height: number,
	Spacing: number,
	Frame: Color3,
	Glass: Color3?,
	Sill: boolean?,
}

-- A grid of framed windows on a face between heights y0 and y1 (relative to the face), one row per
-- floor, centred, leaving `margin` studs clear at each side
function Detail.Windows(parent: Instance, face: CFrame, width: number, y0: number, y1: number, floorH: number, style: WindowStyle, margin: number?)
	local m = margin or 3
	local usable = width - 2 * m
	local count = math.floor(usable / style.Spacing)
	if count < 1 then
		return
	end
	local glass = style.Glass or WINDOW
	local span = count * style.Spacing
	local y = y0
	while y + floorH <= y1 + 0.01 do
		local wy = y + floorH * 0.55
		for i = 0, count - 1 do
			local x = -span / 2 + style.Spacing * (i + 0.5)
			local at = face * CFrame.new(x, wy, 0)
			PartKit.Box(parent, "WindowFrame", Vector3.new(style.Width + 0.7, style.Height + 0.7, 0.3), at * CFrame.new(0, 0, -0.1), style.Frame, SMOOTH, DECOR)
			local pane = PartKit.Box(parent, "Window", Vector3.new(style.Width, style.Height, 0.3), at * CFrame.new(0, 0, -0.2), glass, GLASS, DECOR)
			pane.Reflectance = 0.15
			if style.Sill ~= false then
				PartKit.Box(parent, "Sill", Vector3.new(style.Width + 1.2, 0.35, 0.9), at * CFrame.new(0, -style.Height / 2 - 0.45, -0.35), Color3.fromRGB(214, 210, 200), CONCRETE, DECOR)
			end
		end
		y += floorH
	end
end

-- A shopfront across a face: bulkhead, glass bays with mullions, a glass door, a fascia sign and an
-- awning; sometimes a blade sign and café tables out front
function Detail.Storefront(parent: Instance, face: CFrame, width: number, height: number, name: string, color: Color3, rng: Random)
	local w = width - 2
	local frame = Color3.fromRGB(40, 42, 46)
	PartKit.Box(parent, "Bulkhead", Vector3.new(w, 2.2, 0.8), face * CFrame.new(0, 1.1, -0.4), color:Lerp(Color3.new(0, 0, 0), 0.35), SMOOTH, SOLID_DECOR)
	local glass = PartKit.Box(parent, "ShopGlass", Vector3.new(w, height - 3, 0.3), face * CFrame.new(0, 2.2 + (height - 3) / 2, -0.25), Color3.fromRGB(80, 110, 124), GLASS, DECOR)
	glass.Reflectance = 0.22
	glass.Transparency = 0.15
	local bays = math.max(2, math.floor(w / 9))
	for i = 0, bays do
		local x = -w / 2 + i * w / bays
		PartKit.Box(parent, "ShopMullion", Vector3.new(0.45, height - 0.8, 0.5), face * CFrame.new(x, height / 2 - 0.4 + 0.4, -0.35), frame, METAL, DECOR)
	end
	PartKit.Box(parent, "ShopTransom", Vector3.new(w, 0.45, 0.5), face * CFrame.new(0, height - 2.3, -0.35), frame, METAL, DECOR)
	-- door (in a bay near one end)
	local dx = (rng:NextNumber() < 0.5 and -1 or 1) * (w / 2 - w / bays / 2)
	PartKit.Box(parent, "Door", Vector3.new(4.2, 7.6, 0.35), face * CFrame.new(dx, 3.8, -0.42), Color3.fromRGB(70, 96, 110), GLASS, DECOR)
	PartKit.Box(parent, "DoorFrame", Vector3.new(4.8, 8.0, 0.3), face * CFrame.new(dx, 4.0, -0.3), frame, METAL, DECOR)
	PartKit.Box(parent, "Handle", Vector3.new(0.2, 1.6, 0.25), face * CFrame.new(dx + 1.4, 3.8, -0.7), LIGHT_STEEL, METAL, DECOR)
	PartKit.Box(parent, "Threshold", Vector3.new(5, 0.25, 1.2), face * CFrame.new(dx, 0.12, -0.6), LIGHT_STEEL, METAL, DECOR)
	-- fascia and sign
	PartKit.Box(parent, "Fascia", Vector3.new(width, 2.6, 0.6), face * CFrame.new(0, height + 1.3, -0.3), frame, SMOOTH, DECOR)
	local sign = PartKit.Box(parent, "ShopSign", Vector3.new(math.min(w - 4, 30), 2.2, 0.3), face * CFrame.new(0, height + 1.3, -0.65), Color3.fromRGB(245, 242, 235), SMOOTH, DECOR)
	PartKit.Sign(sign, Enum.NormalId.Front, name, color, nil, Enum.Font.FredokaOne, 14)
	-- awning, sloping out over the pavement: a striped one over the door's end of a wide front
	-- (stripes ~0.8 m), or a plain one the whole width
	local depth = 6
	local striped = rng:NextNumber() < 0.6
	local aw = if striped then math.min(w, rng:NextNumber(24, 34)) else w
	local ax = if striped then math.clamp(dx, -w / 2 + aw / 2, w / 2 - aw / 2) else 0
	local stripes = if striped then math.max(3, math.floor(aw / 3)) else 1
	for i = 0, stripes - 1 do
		local x = ax - aw / 2 + (i + 0.5) * aw / stripes
		local c = if i % 2 == 0 then color else Color3.fromRGB(245, 242, 235)
		PartKit.Box(parent, "Awning", Vector3.new(aw / stripes + 0.02, 0.3, depth), face * CFrame.new(x, height - 0.6, -depth / 2 - 0.2) * CFrame.Angles(math.rad(-18), 0, 0), c, Enum.Material.Fabric, DECOR)
	end
	PartKit.Box(parent, "AwningValance", Vector3.new(aw, 1.0, 0.2), face * CFrame.new(ax, height - 1.9 - 0.4, -depth - 0.05), color, Enum.Material.Fabric, DECOR)
	-- blade sign
	if rng:NextNumber() < 0.5 then
		local side = -dx / math.max(math.abs(dx), 1e-3)
		local blade = PartKit.Box(parent, "BladeSign", Vector3.new(0.3, 3, 4.5), face * CFrame.new(side * (w / 2 - 1), height + 4.5, -2.6), color, SMOOTH, DECOR)
		PartKit.Sign(blade, Enum.NormalId.Left, name, Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 14)
		PartKit.Sign(blade, Enum.NormalId.Right, name, Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 14)
		PartKit.Box(parent, "BladeArm", Vector3.new(0.2, 0.2, 5), face * CFrame.new(side * (w / 2 - 1), height + 6.2, -2.6), DARK, METAL, DECOR)
	end
	-- café tables
	if rng:NextNumber() < 0.3 then
		for i = -1, 1, 2 do
			local at = face * CFrame.new(i * w * 0.25, 0, -4)
			PartKit.Post(parent, "TableLeg", 0.3, 2.6, at.Position, DARK, METAL, DECOR)
			PartKit.Cylinder(parent, "TableTop", 2.8, 0.2, CFrame.new(at.Position + Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(235, 235, 230), SMOOTH, DECOR)
			for _, s in { -1, 1 } do
				local c = at * CFrame.new(s * 2.2, 0, 0)
				PartKit.Box(parent, "Chair", Vector3.new(1.4, 0.3, 1.4), c * CFrame.new(0, 1.6, 0), color, SMOOTH, DECOR)
				PartKit.Box(parent, "ChairBack", Vector3.new(0.25, 1.6, 1.4), c * CFrame.new(s * 0.6, 2.5, 0), color, SMOOTH, DECOR)
			end
		end
	end
end

-- A black steel fire escape down a face at offset x: a landing and stair per floor above the first
function Detail.FireEscape(parent: Instance, face: CFrame, x: number, floors: number, floorH: number)
	for f = 1, floors - 1 do
		local y = f * floorH + 0.5
		local at = face * CFrame.new(x, y, -2.2)
		PartKit.Box(parent, "Landing", Vector3.new(12, 0.3, 4), at, DARK, METAL, DECOR)
		PartKit.Box(parent, "Rail", Vector3.new(12, 0.25, 0.25), at * CFrame.new(0, 3, -2), DARK, METAL, DECOR)
		for _, s in { -1, 1 } do
			PartKit.Box(parent, "RailEnd", Vector3.new(0.25, 0.25, 4), at * CFrame.new(s * 6, 3, 0), DARK, METAL, DECOR)
			PartKit.Box(parent, "Post", Vector3.new(0.25, 3, 0.25), at * CFrame.new(s * 6, 1.5, -2), DARK, METAL, DECOR)
		end
		if f > 1 then
			local lo = (face * CFrame.new(x - 5, y - floorH + 0.5, -2.2)).Position
			local hi = (face * CFrame.new(x + 4, y, -2.2)).Position
			PartKit.Bar(parent, "Stair", lo, hi, 2.6, 0.3, DARK, METAL, DECOR)
		end
	end
	-- drop ladder to the first floor
	local top = face * CFrame.new(x + 4, floorH + 0.5, -3.8)
	PartKit.Box(parent, "Ladder", Vector3.new(1.6, floorH * 0.55, 0.2), top * CFrame.new(0, -floorH * 0.28, 0), DARK, METAL, DECOR)
end

-- Roof clutter on a flat roof: AC units, vents, a stair hut, a railing, sometimes a dish or solar
function Detail.Roof(parent: Instance, cx: number, cz: number, w: number, d: number, top: number, rng: Random)
	local units = math.clamp(math.floor(w * d / 900), 1, 6)
	for _ = 1, units do
		local p = Vector3.new(cx + rng:NextNumber(-w / 2 + 6, w / 2 - 6), top, cz + rng:NextNumber(-d / 2 + 6, d / 2 - 6))
		PartKit.Box(parent, "ACUnit", Vector3.new(6, 3.4, 4.5), CFrame.new(p + Vector3.new(0, 1.7, 0)), Color3.fromRGB(196, 198, 200), METAL, SOLID_DECOR)
		PartKit.Cylinder(parent, "Fan", 3.2, 0.3, CFrame.new(p + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.pi / 2), DARK, METAL, DECOR)
		PartKit.Box(parent, "Grille", Vector3.new(5.4, 2.4, 0.2), CFrame.new(p + Vector3.new(0, 1.6, -2.3)), STEEL, METAL, DECOR)
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local p = Vector3.new(cx + rng:NextNumber(-w / 2 + 3, w / 2 - 3), top, cz + rng:NextNumber(-d / 2 + 3, d / 2 - 3))
		PartKit.Post(parent, "Vent", 1.2, 3, p, LIGHT_STEEL, METAL, DECOR)
		PartKit.Cylinder(parent, "VentCap", 2, 0.4, CFrame.new(p + Vector3.new(0, 3.2, 0)) * CFrame.Angles(0, 0, math.pi / 2), LIGHT_STEEL, METAL, DECOR)
	end
	if w > 30 and d > 30 then
		local hut = Vector3.new(cx - w / 2 + 8, top, cz + d / 2 - 8)
		PartKit.Box(parent, "StairHut", Vector3.new(10, 9, 8), CFrame.new(hut + Vector3.new(0, 4.5, 0)), Color3.fromRGB(176, 172, 166), CONCRETE, SOLID)
		PartKit.Box(parent, "HutDoor", Vector3.new(3.4, 7, 0.3), CFrame.new(hut + Vector3.new(0, 3.5, -4.1)), STEEL, METAL, DECOR)
	end
	-- railing along the roof edge
	for _, e in { { Vector3.new(-w / 2 + 0.6, 0, 0), Vector3.new(0, 0, d - 1.2) }, { Vector3.new(w / 2 - 0.6, 0, 0), Vector3.new(0, 0, d - 1.2) }, { Vector3.new(0, 0, -d / 2 + 0.6), Vector3.new(w - 1.2, 0, 0) }, { Vector3.new(0, 0, d / 2 - 0.6), Vector3.new(w - 1.2, 0, 0) } } do
		local c = Vector3.new(cx, top + 3.4, cz) + e[1]
		local size = Vector3.new(math.max(e[2].X, 0.25), 0.25, math.max(e[2].Z, 0.25))
		PartKit.Box(parent, "Railing", size, CFrame.new(c), LIGHT_STEEL, METAL, DECOR)
	end
	local r = rng:NextNumber()
	if r < 0.25 then
		local p = Vector3.new(cx + w / 4, top, cz - d / 4)
		PartKit.Post(parent, "DishPole", 0.4, 3, p, LIGHT_STEEL, METAL, DECOR)
		PartKit.Cylinder(parent, "Dish", 4, 0.4, CFrame.new(p + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), math.rad(60)), Color3.fromRGB(235, 235, 235), SMOOTH, DECOR)
	elseif r < 0.5 and w > 30 then
		for i = 0, 3 do
			local p = Vector3.new(cx - w / 4 + i * 6.5, top + 1.2, cz - d / 4)
			PartKit.Box(parent, "Solar", Vector3.new(6, 0.3, 9), CFrame.new(p) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(30, 50, 90), GLASS, DECOR).Reflectance = 0.2
		end
	end
end

-- Street furniture ---------------------------------------------------------------------------

-- `cf`: on the pavement, LookVector toward the road
function Detail.BusStop(parent: Instance, cf: CFrame, routeName: string)
	local model = PartKit.Model(parent, "BusStop")
	local frame = Color3.fromRGB(40, 44, 50)
	PartKit.Box(model, "Roof", Vector3.new(14, 0.5, 6), cf * CFrame.new(0, 9, 1), frame, METAL)
	for _, x in { -6.6, 6.6 } do
		PartKit.Box(model, "Post", Vector3.new(0.4, 9, 0.4), cf * CFrame.new(x, 4.5, 3.6), frame, METAL)
		local side = PartKit.Box(model, "SideGlass", Vector3.new(0.2, 6, 4.6), cf * CFrame.new(x, 4.5, 1.5), Color3.fromRGB(170, 200, 215), GLASS, DECOR)
		side.Transparency = 0.55
	end
	local back = PartKit.Box(model, "BackGlass", Vector3.new(13, 6, 0.2), cf * CFrame.new(0, 4.5, 3.8), Color3.fromRGB(170, 200, 215), GLASS)
	back.Transparency = 0.55
	PartKit.Box(model, "Bench", Vector3.new(10, 0.4, 1.6), cf * CFrame.new(0, 1.8, 2.8), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
	local ad = PartKit.Box(model, "AdPanel", Vector3.new(4.5, 6.5, 0.6), cf * CFrame.new(-4, 4.5, 4.2), Color3.fromRGB(250, 250, 250), Enum.Material.Neon, DECOR)
	PartKit.Sign(ad, Enum.NormalId.Front, "RIDE FLIGHTLY ⚡", Color3.fromRGB(255, 120, 20), Color3.fromRGB(20, 22, 26), Enum.Font.FredokaOne, 14)
	PartKit.Post(model, "SignPole", 0.35, 11, (cf * CFrame.new(7.8, 0, -1)).Position, frame, METAL)
	local sign = PartKit.Box(model, "StopSign", Vector3.new(2.6, 2.6, 0.2), cf * CFrame.new(7.8, 10.2, -1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(30, 110, 200), SMOOTH, DECOR)
	PartKit.Sign(sign, Enum.NormalId.Front, "BUS " .. routeName, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBold, 20)
	PartKit.Sign(sign, Enum.NormalId.Back, "BUS " .. routeName, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBold, 20)
	return model
end

function Detail.BikeRack(parent: Instance, cf: CFrame, hoops: number)
	for i = 1, hoops do
		local at = cf * CFrame.new((i - (hoops + 1) / 2) * 2.4, 0, 0)
		for _, s in { -1, 1 } do
			PartKit.Box(parent, "RackLeg", Vector3.new(0.25, 2.6, 0.25), at * CFrame.new(0, 1.3, s * 1.1), LIGHT_STEEL, METAL, SOLID_DECOR)
		end
		PartKit.Box(parent, "RackTop", Vector3.new(0.25, 0.25, 2.45), at * CFrame.new(0, 2.6, 0), LIGHT_STEEL, METAL, SOLID_DECOR)
	end
end

function Detail.Bollard(parent: Instance, base: Vector3)
	PartKit.Post(parent, "Bollard", 0.8, 2.6, base, DARK, METAL, { Touch = false, Shadow = false })
	PartKit.Post(parent, "BollardBand", 0.85, 0.3, base + Vector3.new(0, 2.0, 0), Color3.fromRGB(240, 200, 40), SMOOTH, DECOR)
end

function Detail.NewsBox(parent: Instance, cf: CFrame, color: Color3)
	PartKit.Box(parent, "NewsBox", Vector3.new(1.8, 3.2, 1.6), cf * CFrame.new(0, 1.6, 0), color, METAL, SOLID_DECOR)
	PartKit.Box(parent, "NewsWindow", Vector3.new(1.4, 0.9, 0.1), cf * CFrame.new(0, 2.3, -0.82), Color3.fromRGB(200, 210, 220), GLASS, DECOR)
end

function Detail.ParkingMeter(parent: Instance, base: Vector3)
	PartKit.Post(parent, "MeterPole", 0.3, 3.4, base, STEEL, METAL, DECOR)
	PartKit.Box(parent, "Meter", Vector3.new(0.9, 1.3, 0.7), CFrame.new(base + Vector3.new(0, 4.0, 0)), LIGHT_STEEL, METAL, DECOR)
end

function Detail.Bin(parent: Instance, base: Vector3)
	PartKit.Post(parent, "Bin", 1.6, 3, base, Color3.fromRGB(40, 90, 60), METAL, { Touch = false, Shadow = false })
	PartKit.Post(parent, "BinLid", 1.75, 0.3, base + Vector3.new(0, 3, 0), DARK, METAL, DECOR)
end

-- Square cast-iron grate around a street tree
function Detail.TreeGrate(parent: Instance, base: Vector3)
	PartKit.Box(parent, "TreeGrate", Vector3.new(4, 0.08, 4), CFrame.new(base + Vector3.new(0, 0.04, 0)), Color3.fromRGB(46, 44, 42), Enum.Material.DiamondPlate, DECOR)
end

-- Two blade signs on a pole: `nameA` reads along `dirA`, `nameB` along the other axis
function Detail.StreetSign(parent: Instance, base: Vector3, nameA: string, dirA: Vector3, nameB: string)
	local model = PartKit.Model(parent, "StreetSign")
	PartKit.Post(model, "Pole", 0.35, 11, base, STEEL, METAL)
	local green = Color3.fromRGB(20, 110, 60)
	local cfA = CFrame.lookAt(base + Vector3.new(0, 10.4, 0), base + Vector3.new(0, 10.4, 0) + Vector3.new(-dirA.Z, 0, dirA.X))
	local a = PartKit.Box(model, "BladeA", Vector3.new(6.5, 1.3, 0.15), cfA, green, SMOOTH, DECOR)
	PartKit.Sign(a, Enum.NormalId.Front, nameA, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBold, 24)
	PartKit.Sign(a, Enum.NormalId.Back, nameA, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBold, 24)
	local cfB = CFrame.lookAt(base + Vector3.new(0, 9.0, 0), base + Vector3.new(0, 9.0, 0) + dirA)
	local b = PartKit.Box(model, "BladeB", Vector3.new(6.5, 1.3, 0.15), cfB, green, SMOOTH, DECOR)
	PartKit.Sign(b, Enum.NormalId.Front, nameB, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBold, 24)
	PartKit.Sign(b, Enum.NormalId.Back, nameB, Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBold, 24)
	return model
end

-- Flat on the road: a manhole cover or a kerbside drain
function Detail.Manhole(parent: Instance, position: Vector3)
	PartKit.Cylinder(parent, "Manhole", 2.6, 0.06, CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 58, 56), Enum.Material.DiamondPlate, DECOR)
end

function Detail.Drain(parent: Instance, cf: CFrame)
	PartKit.Box(parent, "Drain", Vector3.new(3, 0.06, 1.4), cf, Color3.fromRGB(40, 40, 40), Enum.Material.DiamondPlate, DECOR)
end

-- A painted arrow on the road pointing along `dir`; `turn` -1 left, 0 straight, 1 right
function Detail.Arrow(parent: Instance, position: Vector3, dir: Vector3, turn: number, color: Color3)
	local cf = CFrame.lookAt(position, position + dir)
	PartKit.Box(parent, "ArrowShaft", Vector3.new(0.6, 0.05, 5), cf, color, SMOOTH, DECOR)
	if turn == 0 then
		for _, s in { -1, 1 } do
			PartKit.Box(parent, "ArrowHead", Vector3.new(0.6, 0.05, 2.4), cf * CFrame.new(s * 0.7, 0, -2.6) * CFrame.Angles(0, math.rad(s * -35), 0), color, SMOOTH, DECOR)
		end
	else
		local tip = cf * CFrame.new(0, 0, -2.5)
		PartKit.Box(parent, "ArrowBend", Vector3.new(2.6, 0.05, 0.6), tip * CFrame.new(-turn * -1.3, 0, 0), color, SMOOTH, DECOR)
		for _, s in { -1, 1 } do
			PartKit.Box(parent, "ArrowHead", Vector3.new(1.8, 0.05, 0.6), tip * CFrame.new(turn * 2.4, 0, 0) * CFrame.Angles(0, math.rad(s * 40), 0) * CFrame.new(-turn * 0.7, 0, 0), color, SMOOTH, DECOR)
		end
	end
end

-- Garden bits -------------------------------------------------------------------------------

-- White picket fence from a to b (on the ground)
function Detail.Picket(parent: Instance, a: Vector3, b: Vector3, color: Color3?)
	local c = color or Color3.fromRGB(245, 245, 240)
	local length = (b - a).Magnitude
	if length < 1 then
		return
	end
	local dir = (b - a).Unit
	local cf = CFrame.lookAt((a + b) / 2, (a + b) / 2 + dir)
	PartKit.Box(parent, "FenceRail", Vector3.new(0.25, 0.4, length), cf * CFrame.new(0, 2.0, 0), c, Enum.Material.Wood, DECOR)
	PartKit.Box(parent, "FenceRail", Vector3.new(0.25, 0.4, length), cf * CFrame.new(0, 0.9, 0), c, Enum.Material.Wood, DECOR)
	local count = math.floor(length / 1.6)
	for i = 0, count do
		local p = a + dir * (i * length / math.max(count, 1))
		PartKit.Box(parent, "Picket", Vector3.new(0.6, 3.2, 0.2), CFrame.lookAt(p + Vector3.new(0, 1.6, 0), p + Vector3.new(0, 1.6, 0) + dir) * CFrame.Angles(0, math.rad(90), 0), c, Enum.Material.Wood, DECOR)
	end
end

function Detail.Hedge(parent: Instance, a: Vector3, b: Vector3, height: number)
	local length = (b - a).Magnitude
	if length < 1 then
		return
	end
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, height / 2, 0)
	PartKit.Box(parent, "Hedge", Vector3.new(2.6, height, length), cf, Color3.fromRGB(58, 104, 50), Enum.Material.Grass, SOLID_DECOR)
end

function Detail.FlowerBed(parent: Instance, cf: CFrame, length: number, rng: Random)
	PartKit.Box(parent, "Bed", Vector3.new(length, 0.5, 2.4), cf * CFrame.new(0, 0.25, 0), Color3.fromRGB(90, 62, 42), Enum.Material.Ground, DECOR)
	local colors = { Color3.fromRGB(230, 60, 90), Color3.fromRGB(250, 210, 60), Color3.fromRGB(150, 80, 220), Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 130, 40) }
	local n = math.floor(length / 1.4)
	for i = 0, n - 1 do
		local x = -length / 2 + 0.7 + i * 1.4
		PartKit.Ball(parent, "Flower", 1.1, (cf * CFrame.new(x, 0.9, rng:NextNumber(-0.6, 0.6))).Position, pick(rng, colors), Enum.Material.Grass, DECOR)
	end
end

function Detail.Mailbox(parent: Instance, base: Vector3, facing: Vector3, color: Color3)
	PartKit.Post(parent, "MailPost", 0.5, 3.6, base, Color3.fromRGB(120, 90, 60), Enum.Material.Wood, DECOR)
	local cf = CFrame.lookAt(base + Vector3.new(0, 4.2, 0), base + Vector3.new(0, 4.2, 0) + facing)
	PartKit.Box(parent, "Mailbox", Vector3.new(1.3, 1.2, 2.4), cf, color, METAL, DECOR)
	PartKit.Box(parent, "Flag", Vector3.new(0.1, 0.9, 0.3), cf * CFrame.new(0.7, 0.6, 0.6), Color3.fromRGB(220, 30, 30), SMOOTH, DECOR)
end

-- Vehicles and yard clutter -----------------------------------------------------------------

-- A box truck parked at `cf` (LookVector = its front)
function Detail.BoxTruck(parent: Instance, cf: CFrame, color: Color3, label: string)
	local model = PartKit.Model(parent, "BoxTruck")
	PartKit.Box(model, "Cab", Vector3.new(8, 8, 7), cf * CFrame.new(0, 5.2, -11), color, SMOOTH)
	local screen = PartKit.Box(model, "Windscreen", Vector3.new(7, 3, 0.3), cf * CFrame.new(0, 6.8, -14.55), Color3.fromRGB(40, 52, 64), GLASS, DECOR)
	screen.Reflectance = 0.2
	PartKit.Box(model, "Box", Vector3.new(8.6, 11, 20), cf * CFrame.new(0, 7.2, 3), Color3.fromRGB(240, 240, 238), SMOOTH)
	local side = PartKit.Box(model, "BoxLabel", Vector3.new(8.7, 3, 14), cf * CFrame.new(0, 8, 3), color, SMOOTH, DECOR)
	PartKit.Sign(side, Enum.NormalId.Left, label, Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 14)
	PartKit.Sign(side, Enum.NormalId.Right, label, Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 14)
	PartKit.Box(model, "Chassis", Vector3.new(7, 1.2, 32), cf * CFrame.new(0, 1.8, -2), DARK, METAL)
	for _, z in { -10.5, 6, 10 } do
		for _, s in { -1, 1 } do
			PartKit.Cylinder(model, "Wheel", 3.6, 1.4, cf * CFrame.new(s * 3.6, 1.8, z), Color3.fromRGB(26, 26, 28), SMOOTH)
		end
	end
	for _, s in { -1, 1 } do
		PartKit.Box(model, "Headlight", Vector3.new(1.4, 0.9, 0.2), cf * CFrame.new(s * 3, 3.2, -14.55), Color3.fromRGB(255, 250, 230), Enum.Material.Neon, DECOR)
	end
	return model
end

function Detail.Pallets(parent: Instance, base: Vector3, rng: Random)
	local stacks = rng:NextInteger(1, 3)
	for s = 0, stacks - 1 do
		local p = base + Vector3.new(s * 5, 0, 0)
		local layers = rng:NextInteger(1, 4)
		for l = 0, layers - 1 do
			PartKit.Box(parent, "Pallet", Vector3.new(4.3, 0.6, 4.3), CFrame.new(p + Vector3.new(0, 0.3 + l * 0.65, 0)), Color3.fromRGB(176, 134, 86), Enum.Material.WoodPlanks, SOLID_DECOR)
		end
		if rng:NextNumber() < 0.6 then
			PartKit.Box(parent, "Crates", Vector3.new(3.8, 3, 3.8), CFrame.new(p + Vector3.new(0, layers * 0.65 + 1.5, 0)), Color3.fromRGB(196, 160, 110), Enum.Material.Cardboard, SOLID_DECOR)
		end
	end
end

function Detail.Barrels(parent: Instance, base: Vector3, rng: Random)
	local colors = { Color3.fromRGB(30, 80, 170), Color3.fromRGB(190, 40, 30), Color3.fromRGB(40, 130, 60) }
	for i = 0, rng:NextInteger(2, 5) do
		PartKit.Post(parent, "Barrel", 2, 3, base + Vector3.new((i % 3) * 2.2, 0, math.floor(i / 3) * 2.2), pick(rng, colors), METAL, SOLID_DECOR)
	end
end

-- Chain-link fence from a to b with posts (see-through)
function Detail.ChainLink(parent: Instance, a: Vector3, b: Vector3, height: number)
	local length = (b - a).Magnitude
	if length < 1 then
		return
	end
	local dir = (b - a).Unit
	local cf = CFrame.lookAt((a + b) / 2, (a + b) / 2 + dir)
	local mesh = PartKit.Box(parent, "ChainLink", Vector3.new(0.1, height, length), cf * CFrame.new(0, height / 2, 0), Color3.fromRGB(150, 156, 160), Enum.Material.ForceField, { Touch = false, Shadow = false })
	mesh.Transparency = 0.35
	PartKit.Box(parent, "FenceTop", Vector3.new(0.25, 0.25, length), cf * CFrame.new(0, height, 0), LIGHT_STEEL, METAL, DECOR)
	local posts = math.floor(length / 10)
	for i = 0, posts do
		PartKit.Post(parent, "FencePost", 0.35, height, a + dir * (i * length / math.max(posts, 1)), LIGHT_STEEL, METAL, DECOR)
	end
end

-- A lifeguard tower on the beach: a pastel hut on stilts with a ramp up the back, facing the sea
-- (`cf` looks out to sea, at the sand)
function Detail.LifeguardTower(parent: Instance, cf: CFrame, color: Color3)
	local model = PartKit.Model(parent, "LifeguardTower")
	local wood = Color3.fromRGB(236, 232, 222)
	for _, x in { -4.5, 4.5 } do
		for _, z in { -3.5, 3.5 } do
			PartKit.Box(model, "Stilt", Vector3.new(0.8, 8, 0.8), cf * CFrame.new(x, 4, z), wood, Enum.Material.Wood, NO_COLLIDE)
		end
	end
	PartKit.Box(model, "Floor", Vector3.new(14, 0.6, 12), cf * CFrame.new(0, 8.3, -1), wood, Enum.Material.WoodPlanks)
	PartKit.Box(model, "Hut", Vector3.new(11, 8, 8), cf * CFrame.new(0, 12.6, 0.5), color, Enum.Material.SmoothPlastic)
	local roof = PartKit.Box(model, "HutRoof", Vector3.new(13, 1, 10), cf * CFrame.new(0, 17.1, 0.5) * CFrame.Angles(math.rad(-6), 0, 0), color:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.SmoothPlastic)
	local _ = roof
	PartKit.Box(model, "Window", Vector3.new(8, 3.2, 0.3), cf * CFrame.new(0, 13.6, -3.6), Color3.fromRGB(50, 70, 90), Enum.Material.Glass, DECOR)
	PartKit.Box(model, "Rail", Vector3.new(14, 0.3, 0.3), cf * CFrame.new(0, 11, -6.8), wood, Enum.Material.Wood, DECOR)
	-- the ramp up the back
	PartKit.Slab(model, "Ramp", (cf * CFrame.new(0, 0, 22)).Position, (cf * CFrame.new(0, 8.6, 5)).Position, 4, 0.5, wood, Enum.Material.WoodPlanks, NO_COLLIDE)
	local flag = PartKit.Box(model, "Flag", Vector3.new(3, 2, 0.1), cf * CFrame.new(5, 21, 0.5), Color3.fromRGB(230, 40, 40), Enum.Material.Fabric, DECOR)
	local _f = flag
	PartKit.Post(model, "FlagPole", 0.25, 6, (cf * CFrame.new(3.5, 17.5, 0.5)).Position, Color3.fromRGB(230, 230, 230), Enum.Material.Metal, DECOR)
	return model
end

-- A beach umbrella over a towel or a pair of loungers
function Detail.BeachUmbrella(parent: Instance, base: Vector3, color: Color3, rng: Random)
	local model = PartKit.Model(parent, "Umbrella")
	PartKit.Post(model, "Pole", 0.3, 8, base, Color3.fromRGB(240, 240, 240), Enum.Material.Metal, DECOR)
	local canopy = PartKit.Ellipsoid(model, "Canopy", Vector3.new(11, 2.2, 11), CFrame.new(base + Vector3.new(0, 8, 0)), color, Enum.Material.Fabric, DECOR)
	local _ = canopy
	local yaw = rng:NextNumber(0, math.pi * 2)
	local towels = { Color3.fromRGB(250, 250, 250), Color3.fromRGB(80, 170, 220), Color3.fromRGB(250, 140, 170), Color3.fromRGB(250, 210, 80) }
	for _, x in { -2.2, 2.2 } do
		local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0) * CFrame.new(x, 0, 2)
		if rng:NextNumber() < 0.5 then
			PartKit.Box(model, "Lounger", Vector3.new(2.2, 1.2, 6.5), cf * CFrame.new(0, 0.6, 0), Color3.fromRGB(245, 245, 240), Enum.Material.SmoothPlastic, DECOR)
		else
			PartKit.Box(model, "Towel", Vector3.new(2.4, 0.08, 6), cf * CFrame.new(0, 0.05, 0), towels[rng:NextInteger(1, #towels)], Enum.Material.Fabric, DECOR)
		end
	end
	return model
end

return Detail
