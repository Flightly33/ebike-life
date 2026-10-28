--[[
	Airport: the international airport north-west of downtown (Layout.Airport). A long runway with
	its markings, edge and approach lights, a parallel taxiway, the apron with airliners at the
	gates, the glass terminal and its jet bridges, the control tower, hangars, a car park off the
	airport road, and a fence round the airside with a gate (the runway is a great place to open
	a bike up). The airlines are made up.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local Roads = require(script.Parent.Roads)
local Buildings = require(script.Parent.Buildings)
local PartKit = require(script.Parent.Parent.PartKit)

local Airport = {}

local C = Props.Palette
local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local CONCRETE = Enum.Material.Concrete
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local MARK_Y = Layout.ROAD_Y + 0.03
local TAXI_W = 82 -- 23 m, an airliner taxiway

export type Livery = { Name: string, Tail: Color3, Stripe: Color3, Belly: Color3 }
Airport.Liveries = {
	{ Name = "SUNCOAST", Tail = Color3.fromRGB(250, 140, 30), Stripe = Color3.fromRGB(250, 190, 40), Belly = Color3.fromRGB(240, 240, 238) },
	{ Name = "PALM AIR", Tail = Color3.fromRGB(30, 140, 100), Stripe = Color3.fromRGB(40, 170, 120), Belly = Color3.fromRGB(240, 240, 238) },
	{ Name = "BISCAYNE", Tail = Color3.fromRGB(20, 60, 140), Stripe = Color3.fromRGB(40, 110, 200), Belly = Color3.fromRGB(200, 204, 210) },
	{ Name = "FLIGHTLY AIR", Tail = Color3.fromRGB(255, 122, 24), Stripe = Color3.fromRGB(30, 30, 34), Belly = Color3.fromRGB(240, 240, 238) },
	{ Name = "CORAL WINGS", Tail = Color3.fromRGB(230, 80, 110), Stripe = Color3.fromRGB(250, 140, 160), Belly = Color3.fromRGB(240, 240, 238) },
} :: { Livery }

-- An airliner (a twin-engine narrow-body, ~44 m) standing on its wheels at `cf` (the ground under
-- the middle of the fuselage), nose along -Z. `opts.Static` false builds it for flying (the
-- ambient planes): unanchored nothing changes, it's just returned as one model.
function Airport.Airliner(parent: Instance?, cf: CFrame, livery: Livery): Model
	local model = PartKit.Model(parent, "Airliner")
	model:SetAttribute("Livery", livery.Name)
	local white = Color3.fromRGB(244, 244, 242)
	local h = 12 -- fuselage centre above the ground
	local len = 120
	local body = cf * CFrame.new(0, h, 0)
	PartKit.Cylinder(model, "Fuselage", 14, len, body * CFrame.Angles(0, math.pi / 2, 0), white, SMOOTH)
	PartKit.Ellipsoid(model, "Nose", Vector3.new(14, 14, 26), body * CFrame.new(0, -0.4, -len / 2 - 2), white, SMOOTH)
	PartKit.Ellipsoid(model, "TailCone", Vector3.new(12, 11, 34), body * CFrame.new(0, 1.2, len / 2 + 4), white, SMOOTH)
	PartKit.Box(model, "Cockpit", Vector3.new(8, 2.2, 3), body * CFrame.new(0, 3.6, -len / 2 - 6) * CFrame.Angles(math.rad(-28), 0, 0), Color3.fromRGB(30, 36, 44), GLASS, DECOR)
	-- windows and the livery's cheatline down both sides, the belly
	for _, sx in { -1, 1 } do
		PartKit.Box(model, "Windows", Vector3.new(0.2, 1.2, len - 16), body * CFrame.new(sx * 6.95, 1.5, -2), Color3.fromRGB(30, 36, 44), GLASS, DECOR)
		PartKit.Box(model, "Cheatline", Vector3.new(0.2, 1.4, len), body * CFrame.new(sx * 6.9, -1.4, 0), livery.Stripe, SMOOTH, DECOR)
		PartKit.Box(model, "Door", Vector3.new(0.25, 6, 3), body * CFrame.new(sx * 6.95, 0.5, -len / 2 + 10), Color3.fromRGB(200, 200, 198), SMOOTH, DECOR)
	end
	PartKit.Box(model, "Belly", Vector3.new(11, 1, len - 10), body * CFrame.new(0, -6.6, 0), livery.Belly, SMOOTH, DECOR)
	local name = PartKit.Box(model, "AirlineName", Vector3.new(0.2, 3.4, 40), body * CFrame.new(7.1, 4.4, -12), white, SMOOTH, DECOR)
	name.Transparency = 1
	PartKit.Sign(name, Enum.NormalId.Right, livery.Name, livery.Tail, nil, Enum.Font.GothamBlack, 6)
	-- wings: swept back from the wing box, a winglet at each tip, an engine under each
	for _, sx in { -1, 1 } do
		local root = body * CFrame.new(sx * 7, -3.5, 4)
		local sweep = CFrame.Angles(0, sx * math.rad(-28), 0)
		local wing = root * sweep * CFrame.new(sx * 30, 0, 0)
		PartKit.Box(model, "Wing", Vector3.new(60, 1.6, 18), wing * CFrame.Angles(0, 0, sx * math.rad(5)), white, SMOOTH)
		PartKit.Box(model, "Winglet", Vector3.new(1, 9, 6), root * sweep * CFrame.new(sx * 60, 7, 2), livery.Tail, SMOOTH, DECOR)
		local engine = root * sweep * CFrame.new(sx * 20, -5.5, -8)
		PartKit.Cylinder(model, "Engine", 9, 18, engine * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(220, 222, 226), METAL)
		PartKit.Cylinder(model, "Intake", 7.2, 0.4, engine * CFrame.new(0, 0, -9.1) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 30, 34), METAL, DECOR)
		-- the tailplane
		PartKit.Box(model, "Stabilizer", Vector3.new(22, 1, 10), body * CFrame.new(sx * 12, 2, len / 2 + 8) * CFrame.Angles(0, sx * math.rad(-25), 0), white, SMOOTH, NO_COLLIDE)
	end
	-- the fin in the airline's colour
	PartKit.Wedge(model, "Fin", Vector3.new(1.4, 26, 28), body * CFrame.new(0, 19, len / 2 + 2), livery.Tail, SMOOTH)
	-- landing gear
	for _, at in { Vector3.new(0, -h + 2.2, -len / 2 + 8), Vector3.new(-5, -h + 2.2, 6), Vector3.new(5, -h + 2.2, 6) } do
		PartKit.Cylinder(model, "Wheel", 4.4, 2.4, body * CFrame.new(at), Color3.fromRGB(28, 28, 30), Enum.Material.Rubber, DECOR)
		PartKit.Box(model, "Strut", Vector3.new(0.8, h - 6, 0.8), body * CFrame.new(at + Vector3.new(0, (h - 6) / 2 + 1.6, 0)), Color3.fromRGB(180, 182, 186), METAL, DECOR)
	end
	return model
end

-- A strip of paint on the ground (centre `p`, along `dir`)
local function paint(parent: Instance, p: Vector3, dir: Vector3, length: number, width: number, color: Color3)
	PartKit.Box(parent, "Line", Vector3.new(width, 0.05, length), CFrame.lookAt(Vector3.new(p.X, MARK_Y, p.Z), Vector3.new(p.X, MARK_Y, p.Z) + dir), color, SMOOTH, DECOR)
end

-- Asphalt from `a` to `b` (flat, axis-aligned) `width` wide, in pieces within the part size limit
local function pavement(parent: Instance, name: string, a: Vector3, b: Vector3, width: number)
	local length = (b - a).Magnitude
	local n = math.ceil(length / 1800)
	local dir = (b - a).Unit
	for k = 0, n - 1 do
		local center = a + dir * (length * (k + 0.5) / n)
		local size = if math.abs(dir.X) > 0.5 then Vector3.new(length / n, 0, width) else Vector3.new(width, 0, length / n)
		Roads.Slab(parent, name, center, size)
	end
end

function Airport.Build(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Airport")
	local A = Layout.Airport
	local z = A.RunwayZ
	local x0, x1 = A.RunwayX0, A.RunwayX1
	local half = A.RunwayWidth / 2
	local east = Vector3.new(1, 0, 0)

	-- the runway and its paint: edge lines, the centre line, piano keys and numbers at each end,
	-- touchdown bars
	local runway = PartKit.Folder(folder, "Runway")
	pavement(runway, "Runway", Vector3.new(x0, 0, z), Vector3.new(x1, 0, z), A.RunwayWidth)
	paint(runway, Vector3.new((x0 + x1) / 2, 0, z - half + 1.5), east, x1 - x0 - 4, 1, C.White)
	paint(runway, Vector3.new((x0 + x1) / 2, 0, z + half - 1.5), east, x1 - x0 - 4, 1, C.White)
	local dash, gap = 40, 30
	for x = x0 + 120, x1 - 120 - dash, dash + gap do
		paint(runway, Vector3.new(x + dash / 2, 0, z), east, dash, 1.2, C.White)
	end
	for _, endX in { x0, x1 } do
		local inward = if endX == x0 then 1 else -1
		-- the threshold's piano keys across most of the width
		for k = -4, 4 do
			if k ~= 0 then
				paint(runway, Vector3.new(endX + inward * 30, 0, z + k * 17), east, 50, 7, C.White)
			end
		end
		local number = PartKit.Box(runway, "RunwayNumber", Vector3.new(30, 0.05, 24), CFrame.new(endX + inward * 70, MARK_Y, z) * CFrame.Angles(0, if inward > 0 then math.rad(90) else math.rad(-90), 0), C.White, SMOOTH, DECOR)
		number.Transparency = 1
		PartKit.Sign(number, Enum.NormalId.Top, if inward > 0 then "09" else "27", C.White, nil, Enum.Font.GothamBold, 3)
		for k = 0, 2 do
			for _, sz in { -1, 1 } do
				paint(runway, Vector3.new(endX + inward * (220 + k * 80), 0, z + sz * 30), east, 40, 6, C.White)
			end
		end
		-- approach lights out past the end
		for k = 1, 6 do
			local p = Vector3.new(endX - inward * k * 22, 0, z)
			PartKit.Post(runway, "ApproachPost", 0.6, 3, p, Color3.fromRGB(80, 80, 84), METAL, DECOR)
			PartKit.Box(runway, "Globe", Vector3.new(1.2, 0.6, 14), CFrame.new(p + Vector3.new(0, 3.2, 0)), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
		end
	end
	-- edge lights
	for x = x0 + 30, x1 - 30, 110 do
		for _, sz in { -1, 1 } do
			local p = Vector3.new(x, Layout.ROAD_Y, z + sz * (half + 3))
			PartKit.Post(runway, "EdgeLight", 0.5, 1, p, Color3.fromRGB(240, 240, 236), METAL, DECOR)
			PartKit.Ball(runway, "EdgeGlobe", 0.8, p + Vector3.new(0, 1.2, 0), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
		end
	end

	-- the taxiway alongside, its links to the runway and the apron, yellow centre lines
	local taxi = PartKit.Folder(folder, "Taxiways")
	local tz = A.TaxiwayZ
	pavement(taxi, "Taxiway", Vector3.new(x0 + 50, 0, tz), Vector3.new(x1 - 50, 0, tz), TAXI_W)
	paint(taxi, Vector3.new((x0 + x1) / 2, 0, tz), east, x1 - x0 - 120, 0.8, C.Yellow)
	for _, x in { x0 + 70, (x0 + x1) / 2, x1 - 70 } do
		pavement(taxi, "Taxiway", Vector3.new(x, 0, z + half), Vector3.new(x, 0, tz - TAXI_W / 2), TAXI_W)
		paint(taxi, Vector3.new(x, 0, (z + half + tz - TAXI_W / 2) / 2), Vector3.new(0, 0, 1), (tz - TAXI_W / 2) - (z + half), 0.8, C.Yellow)
	end
	local apron = A.Apron
	for _, x in { apron.MinX + 150, (apron.MinX + apron.MaxX) / 2, apron.MaxX - 150 } do
		pavement(taxi, "Taxiway", Vector3.new(x, 0, tz + TAXI_W / 2), Vector3.new(x, 0, apron.MinZ), TAXI_W)
	end

	-- the apron: concrete, stand markings, airliners nosed in to the jet bridges
	local apronFolder = PartKit.Folder(folder, "Apron")
	local aw, ad = apron.MaxX - apron.MinX, apron.MaxZ - apron.MinZ
	local n = math.ceil(aw / 1800)
	for k = 0, n - 1 do
		local p = PartKit.Box(apronFolder, "Apron", Vector3.new(aw / n, 0.6, ad), CFrame.new(apron.MinX + aw * (k + 0.5) / n, Layout.ROAD_Y - 0.3, (apron.MinZ + apron.MaxZ) / 2), Color3.fromRGB(176, 176, 172), CONCRETE)
		p:SetAttribute("Surface", "Road")
	end
	local term = A.Terminal
	local gates = 6
	for g = 1, gates do
		local gx = term.MinX + g * (term.MaxX - term.MinX) / (gates + 1)
		local standZ = apron.MaxZ - 90
		paint(apronFolder, Vector3.new(gx, 0, standZ), Vector3.new(0, 0, 1), 150, 0.8, C.Yellow)
		if rng:NextNumber() < 0.85 then
			Airport.Airliner(apronFolder, CFrame.new(gx, Layout.ROAD_Y, standZ) * CFrame.Angles(0, math.pi, 0), Airport.Liveries[rng:NextInteger(1, #Airport.Liveries)])
		end
		-- the jet bridge from the terminal to the front door
		local fromP = Vector3.new(gx, Layout.ROAD_Y + 16, term.MinZ - 2)
		local toP = Vector3.new(gx - 12, Layout.ROAD_Y + 14, standZ + 54)
		PartKit.Bar(apronFolder, "JetBridge", fromP, toP, 9, 9, Color3.fromRGB(196, 198, 202), METAL, NO_COLLIDE)
		PartKit.Post(apronFolder, "BridgeLeg", 1.6, 10, Vector3.new(toP.X, Layout.ROAD_Y, toP.Z - 6), Color3.fromRGB(80, 82, 86), METAL, DECOR)
		-- a baggage tug and a fuel truck by some of them
		if g % 2 == 0 then
			Detail.BoxTruck(apronFolder, CFrame.new(gx + 40, Layout.ROAD_Y, standZ + 10), Color3.fromRGB(240, 240, 236), "FUEL")
		end
	end
	-- one more taxiing out
	Airport.Airliner(apronFolder, CFrame.new(x0 + 400, Layout.ROAD_Y, tz) * CFrame.Angles(0, math.rad(90), 0), Airport.Liveries[rng:NextInteger(1, #Airport.Liveries)])

	-- the terminal: a long glass hall under a curved (three-slab) roof, its landside front
	local terminal = PartKit.Model(folder, "Terminal")
	local tw, td, th = term.MaxX - term.MinX, term.MaxZ - term.MinZ, 40
	local tcx, tcz = (term.MinX + term.MaxX) / 2, (term.MinZ + term.MaxZ) / 2
	local pieces = math.ceil(tw / 1000)
	for k = 0, pieces - 1 do
		local px = term.MinX + tw * (k + 0.5) / pieces
		PartKit.Box(terminal, "Hall", Vector3.new(tw / pieces, th, td - 20), CFrame.new(px, Layout.CURB_Y + th / 2, tcz), Color3.fromRGB(226, 228, 230), CONCRETE)
		local glass = PartKit.Box(terminal, "ShopGlass", Vector3.new(tw / pieces, th - 8, td - 19), CFrame.new(px, Layout.CURB_Y + (th - 8) / 2 + 2, tcz), Color3.fromRGB(80, 120, 140), GLASS, DECOR)
		glass.Reflectance = 0.35
		for _, s in { -1, 0, 1 } do
			local slope = math.rad(s * 10)
			PartKit.Box(terminal, "Roof", Vector3.new(tw / pieces, 2, td / 3 + 2), CFrame.new(px, Layout.CURB_Y + th + 3 - math.abs(s) * 2, tcz + s * td / 3) * CFrame.Angles(slope, 0, 0), Color3.fromRGB(236, 238, 240), METAL)
		end
	end
	local name = PartKit.Box(terminal, "TerminalName", Vector3.new(160, 10, 0.4), CFrame.new(tcx, Layout.CURB_Y + th - 6, term.MaxZ - 9), Color3.fromRGB(30, 30, 34), SMOOTH, DECOR)
	name.Transparency = 1
	PartKit.Sign(name, Enum.NormalId.Back, "MIAMI INTERNATIONAL  ✈", Color3.fromRGB(250, 250, 248), nil, Enum.Font.GothamBold, 4)
	PartKit.Box(terminal, "Canopy", Vector3.new(tw * 0.8, 1.2, 24), CFrame.new(tcx, Layout.CURB_Y + 14, term.MaxZ + 2), Color3.fromRGB(236, 238, 240), METAL, NO_COLLIDE)
	-- the departures curb and the car park between it and the airport road
	local roadZ = Layout.AIRPORT_ROAD_Z
	local lotZ0, lotZ1 = term.MaxZ + 40, roadZ - Layout.STREET_WIDTH
	Roads.Slab(terminal, "Curb", Vector3.new(tcx, 0, term.MaxZ + 24), Vector3.new(tw, 0, 28))
	Buildings.ParkingLot(folder, term.MinX + 40, term.MaxX - 40, lotZ0, lotZ1, Layout.ROAD_Y - 0.15, rng, 0.5)

	-- the control tower, hangars, a windsock
	local towerBase = Vector3.new(term.MaxX + 120, Layout.ROAD_Y, term.MinZ + 40)
	local tower = PartKit.Model(folder, "ControlTower")
	PartKit.Post(tower, "Shaft", 18, 170, towerBase, Color3.fromRGB(226, 226, 222), CONCRETE)
	PartKit.Post(tower, "Cab", 34, 16, towerBase + Vector3.new(0, 170, 0), Color3.fromRGB(40, 70, 86), GLASS)
	PartKit.Post(tower, "CabRoof", 38, 3, towerBase + Vector3.new(0, 186, 0), Color3.fromRGB(226, 226, 222), CONCRETE)
	PartKit.Post(tower, "Antenna", 1, 30, towerBase + Vector3.new(0, 189, 0), Color3.fromRGB(220, 60, 50), METAL, DECOR)
	pcall(function()
		(tower :: any).LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	end)
	for k = 0, 1 do
		local hx = apron.MinX - 130
		local hz = apron.MinZ + 40 + k * 190
		local hangar = PartKit.Model(folder, "Hangar")
		PartKit.Box(hangar, "HangarBody", Vector3.new(150, 50, 160), CFrame.new(hx, Layout.ROAD_Y + 25, hz), Color3.fromRGB(206, 210, 214), Enum.Material.CorrodedMetal)
		for _, sz in { -1, 1 } do
			PartKit.Slab(hangar, "HangarRoof", Vector3.new(hx, Layout.ROAD_Y + 50, hz + sz * 82), Vector3.new(hx, Layout.ROAD_Y + 66, hz), 152, 1.2, Color3.fromRGB(196, 200, 204), METAL, NO_COLLIDE)
		end
		PartKit.Box(hangar, "HangarDoor", Vector3.new(0.6, 40, 140), CFrame.new(hx + 75.3, Layout.ROAD_Y + 20, hz), Color3.fromRGB(150, 156, 162), METAL, DECOR)
	end
	local sock = Vector3.new((x0 + x1) / 2, Layout.ROAD_Y, z - half - 40)
	PartKit.Post(folder, "SockPole", 0.6, 16, sock, Color3.fromRGB(230, 230, 228), METAL)
	PartKit.Ellipsoid(folder, "Windsock", Vector3.new(3, 3, 12), CFrame.new(sock + Vector3.new(6, 15, 0)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 120, 20), Enum.Material.Fabric, DECOR)

	-- the fence round the airside, open at a gate east of the apron so you can ride in
	local f = PartKit.Folder(folder, "Fence")
	local r = A.Rect
	local gateZ0, gateZ1 = apron.MinZ + 40, apron.MinZ + 140
	Detail.ChainLink(f, Vector3.new(r.MinX, Layout.ROAD_Y, r.MinZ), Vector3.new(r.MaxX, Layout.ROAD_Y, r.MinZ), 9)
	Detail.ChainLink(f, Vector3.new(r.MinX, Layout.ROAD_Y, r.MinZ), Vector3.new(r.MinX, Layout.ROAD_Y, apron.MaxZ), 9)
	Detail.ChainLink(f, Vector3.new(r.MaxX, Layout.ROAD_Y, r.MinZ), Vector3.new(r.MaxX, Layout.ROAD_Y, gateZ0), 9)
	Detail.ChainLink(f, Vector3.new(r.MaxX, Layout.ROAD_Y, gateZ1), Vector3.new(r.MaxX, Layout.ROAD_Y, apron.MaxZ), 9)
	Detail.ChainLink(f, Vector3.new(r.MinX, Layout.ROAD_Y, apron.MaxZ), Vector3.new(term.MinX - 10, Layout.ROAD_Y, apron.MaxZ), 9)
	Detail.ChainLink(f, Vector3.new(term.MaxX + 10, Layout.ROAD_Y, apron.MaxZ), Vector3.new(r.MaxX, Layout.ROAD_Y, apron.MaxZ), 9)
	-- the gate road from the airport road up to the opening
	pavement(taxi, "ServiceRoad", Vector3.new(r.MaxX + 30, 0, roadZ - 20), Vector3.new(r.MaxX + 30, 0, (gateZ0 + gateZ1) / 2), 26)
	pavement(taxi, "ServiceRoad", Vector3.new(r.MaxX + 43, 0, (gateZ0 + gateZ1) / 2), Vector3.new(apron.MaxX, 0, (gateZ0 + gateZ1) / 2), 26)
	local sign = PartKit.Box(f, "GateSign", Vector3.new(16, 5, 0.4), CFrame.new(r.MaxX + 30, Layout.ROAD_Y + 10, gateZ1 + 4), Color3.fromRGB(20, 60, 140), SMOOTH, NO_COLLIDE)
	PartKit.Sign(sign, Enum.NormalId.Back, "AIRSIDE GATE 4", Color3.fromRGB(250, 250, 248), nil, Enum.Font.GothamBold, 8)
	return folder
end

return Airport
