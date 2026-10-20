--[[
	Landmarks: Flighty Mechanics (the dealership, where you spawn), the police station, the city
	plaza, Central Park and the Jump Park.

	The dealership holds a prompt named DealershipPrompt (opens the dealership menu) and one named
	TuningPrompt (the service bay). Showroom bikes are static BikeModels on turntables.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local PartKit = require(script.Parent.Parent.PartKit)
local Bikes = require(script.Parent.Parent.Bikes)
local Config = require(script.Parent.Parent.Config)
local BikeModel = require(script.Parent.Parent.Models.BikeModel)
local CarModel = require(script.Parent.Parent.Models.CarModel)

local Landmarks = {}

local Y = Layout.CURB_Y
local SMOOTH = Enum.Material.SmoothPlastic
local GLASS = Enum.Material.Glass
local CONCRETE = Enum.Material.Concrete
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

local FLIGHTY_ORANGE = Color3.fromRGB(255, 122, 24)
local FLIGHTY_DARK = Color3.fromRGB(26, 28, 34)

local function prompt(parent: BasePart, name: string, action: string, object: string): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 16
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

--------------------------------------------------------------------------------
-- Flighty Mechanics
--------------------------------------------------------------------------------
function Landmarks.Dealership(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "FlightyMechanics")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx = (x0 + x1) / 2
	-- Forecourt
	PartKit.Box(model, "Forecourt", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, (z0 + z1) / 2), Color3.fromRGB(206, 204, 200), Enum.Material.Pavement)
	local floorY = Y + 0.3

	-- Showroom: a glass box on the north half, open toward the forecourt (south, +Z)
	local sw, sd, sh = 200, 104, 34
	local sz = z0 + 14 + sd / 2
	local scx = cx - 30
	PartKit.Box(model, "ShowroomFloor", Vector3.new(sw, 0.4, sd), CFrame.new(scx, floorY + 0.2, sz), Color3.fromRGB(236, 236, 238), Enum.Material.Marble)
	local top = floorY + sh
	PartKit.Box(model, "Roof", Vector3.new(sw + 6, 3, sd + 6), CFrame.new(scx, top + 1.5, sz), FLIGHTY_DARK, SMOOTH)
	PartKit.Box(model, "RoofTrim", Vector3.new(sw + 6.4, 1.2, sd + 6.4), CFrame.new(scx, top + 0.2, sz), FLIGHTY_ORANGE, Enum.Material.Neon, DECOR)
	-- back and side walls
	PartKit.Box(model, "BackWall", Vector3.new(sw, sh, 2), CFrame.new(scx, floorY + sh / 2, sz - sd / 2), FLIGHTY_DARK, SMOOTH)
	for _, side in { -1, 1 } do
		local glass = PartKit.Box(model, "SideGlass", Vector3.new(1, sh, sd), CFrame.new(scx + side * sw / 2, floorY + sh / 2, sz), Color3.fromRGB(150, 190, 210), GLASS)
		glass.Transparency = 0.55
	end
	-- front: glass panels with a wide open entrance in the middle
	local entrance = 50
	local panel = (sw - entrance) / 2
	for _, side in { -1, 1 } do
		local g = PartKit.Box(model, "FrontGlass", Vector3.new(panel, sh, 1), CFrame.new(scx + side * (entrance / 2 + panel / 2), floorY + sh / 2, sz + sd / 2), Color3.fromRGB(150, 190, 210), GLASS)
		g.Transparency = 0.55
	end
	PartKit.Box(model, "EntranceLintel", Vector3.new(entrance, 8, 1.2), CFrame.new(scx, top - 4, sz + sd / 2), FLIGHTY_DARK, SMOOTH)
	-- columns
	for i = 0, 4 do
		local x = scx - sw / 2 + i * sw / 4
		PartKit.Box(model, "Column", Vector3.new(2, sh, 2), CFrame.new(x, floorY + sh / 2, sz + sd / 2), FLIGHTY_DARK, SMOOTH)
	end
	-- the big sign on the roof edge
	local signBoard = PartKit.Box(model, "Sign", Vector3.new(150, 16, 2), CFrame.new(scx, top + 11, sz + sd / 2 - 2), FLIGHTY_DARK, SMOOTH)
	PartKit.Sign(signBoard, Enum.NormalId.Back, "FLIGHTY MECHANICS", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	PartKit.Sign(signBoard, Enum.NormalId.Front, "FLIGHTY MECHANICS", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	local tagline = PartKit.Box(model, "Tagline", Vector3.new(90, 5, 1), CFrame.new(scx, top - 4, sz + sd / 2 + 0.8), FLIGHTY_DARK, SMOOTH, DECOR)
	PartKit.Sign(tagline, Enum.NormalId.Back, "Home of " .. Config.BRAND .. " e-bikes", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 10)

	-- Showroom bikes on turntables, two rows
	local count = #Bikes.List
	local perRow = math.ceil(count / 2)
	for i, bike in Bikes.List do
		local row = if i <= perRow then 0 else 1
		local col = if row == 0 then i - 1 else i - 1 - perRow
		local x = scx - sw / 2 + 22 + col * ((sw - 44) / math.max(perRow - 1, 1))
		local z = sz - sd / 2 + 26 + row * 36
		local deckY = floorY + 0.4
		PartKit.Post(model, "Turntable", 14, 1.0, Vector3.new(x, deckY, z), Color3.fromRGB(30, 32, 36), SMOOTH)
		PartKit.Post(model, "TurntableRing", 14.4, 0.3, Vector3.new(x, deckY + 0.85, z), Bikes.RarityColors[bike.Rarity], Enum.Material.Neon, DECOR)
		local display = BikeModel.Build(bike, nil, { Static = true })
		PartKit.Scale(display, 1 / Config.WORLD_SCALE) -- vehicles are true size; the city shrinks later
		PartKit.PlaceStatic(display, CFrame.new(x, deckY + 1.0, z) * CFrame.Angles(0, math.rad(if row == 0 then 35 else -35), 0))
		display.Name = "Display_" .. bike.Id
		display.Parent = model
		local plaque = PartKit.Box(model, "Plaque", Vector3.new(9, 2.4, 0.3), CFrame.new(x, deckY + 1.6, z + 7.4) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(20, 20, 24), SMOOTH, DECOR)
		local price = if bike.Price == 0 then "FREE" else "$" .. tostring(bike.Price)
		PartKit.Sign(plaque, Enum.NormalId.Back, bike.Name .. "  " .. price, Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 20)
	end

	-- Sales counter with the dealership prompt
	local counterPos = Vector3.new(scx + sw / 2 - 30, floorY + 2.2, sz + sd / 2 - 10)
	local counter = PartKit.Box(model, "Counter", Vector3.new(26, 4.4, 6), CFrame.new(counterPos), FLIGHTY_DARK, SMOOTH)
	PartKit.Box(model, "CounterTop", Vector3.new(26.4, 0.4, 6.4), CFrame.new(counterPos + Vector3.new(0, 2.4, 0)), FLIGHTY_ORANGE, SMOOTH)
	local counterSign = PartKit.Box(model, "CounterSign", Vector3.new(16, 4, 0.4), CFrame.new(counterPos + Vector3.new(0, 9, -2)), FLIGHTY_ORANGE, SMOOTH, DECOR)
	PartKit.Sign(counterSign, Enum.NormalId.Back, "BUY BIKES", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 20)
	PartKit.Sign(counterSign, Enum.NormalId.Front, "BUY BIKES", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 20)
	local dealer = prompt(counter, "DealershipPrompt", "Browse bikes", Config.DEALERSHIP)
	dealer.MaxActivationDistance = 20
	-- A second sales prompt at the entrance, so riders don't have to come inside
	local kioskPos = Vector3.new(scx - entrance / 2 - 8, floorY + 3, sz + sd / 2 + 10)
	local kiosk = PartKit.Box(model, "SalesKiosk", Vector3.new(4, 6, 2), CFrame.new(kioskPos), FLIGHTY_DARK, SMOOTH)
	PartKit.Box(model, "KioskScreen", Vector3.new(3.2, 3, 0.2), CFrame.new(kioskPos + Vector3.new(0, 0.8, 1.05)), FLIGHTY_ORANGE, Enum.Material.Neon, DECOR)
	prompt(kiosk, "DealershipPrompt", "Browse bikes", Config.DEALERSHIP).MaxActivationDistance = 20

	-- Service bay (tuning) on the east side
	local bayX = x1 - 34
	local bayZ = z0 + 50
	PartKit.Box(model, "BayBody", Vector3.new(56, 30, 80), CFrame.new(bayX, floorY + 15, bayZ), Color3.fromRGB(60, 64, 70), Enum.Material.Concrete)
	PartKit.Box(model, "BayDoorFrame", Vector3.new(2, 24, 50), CFrame.new(bayX - 28.5, floorY + 12, bayZ), FLIGHTY_ORANGE, SMOOTH, DECOR)
	PartKit.Box(model, "BayDoor", Vector3.new(1, 20, 44), CFrame.new(bayX - 28.8, floorY + 10, bayZ), Color3.fromRGB(28, 30, 34), SMOOTH, DECOR)
	local baySign = PartKit.Box(model, "BaySign", Vector3.new(1, 6, 40), CFrame.new(bayX - 29, floorY + 26, bayZ), FLIGHTY_DARK, SMOOTH, DECOR)
	PartKit.Sign(baySign, Enum.NormalId.Left, "SERVICE & TUNING", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 12)
	local tuneStand = PartKit.Box(model, "TuningStand", Vector3.new(4, 5, 4), CFrame.new(bayX - 36, floorY + 2.5, bayZ + 30), FLIGHTY_ORANGE, SMOOTH)
	prompt(tuneStand, "TuningPrompt", "Tune your bike", "Service bay").MaxActivationDistance = 20
	-- tool rack and a lift for show
	PartKit.Box(model, "Lift", Vector3.new(10, 1, 16), CFrame.new(bayX - 40, floorY + 0.5, bayZ - 10), Color3.fromRGB(200, 40, 40), Enum.Material.DiamondPlate)

	-- Flags and planters along the forecourt
	for i = 0, 5 do
		local x = x0 + 16 + i * (x1 - x0 - 32) / 5
		local base = Vector3.new(x, floorY, z1 - 6)
		PartKit.Post(model, "FlagPole", 0.5, 26, base, Color3.fromRGB(220, 220, 225), Enum.Material.Metal, NO_COLLIDE)
		PartKit.Box(model, "Flag", Vector3.new(0.2, 9, 5), CFrame.new(base + Vector3.new(0, 21, 2.6)), if i % 2 == 0 then FLIGHTY_ORANGE else FLIGHTY_DARK, Enum.Material.Fabric, DECOR)
	end
	for i = 0, 3 do
		local x = x0 + 30 + i * (x1 - x0 - 60) / 3
		Props.Tree(model, Vector3.new(x, floorY, z1 - 26), rng, 0.8)
	end
	-- Parking bays on the west side of the forecourt
	for i = 0, 6 do
		PartKit.Box(model, "Bay", Vector3.new(0.4, 0.05, 18), CFrame.new(x0 + 8 + i * 12, floorY + 0.03, z1 - 60), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	return model
end

--------------------------------------------------------------------------------
-- Police station
--------------------------------------------------------------------------------
function Landmarks.Police(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "PoliceStation")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	PartKit.Box(model, "Lot", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(86, 88, 92), Enum.Material.Asphalt)
	local floorY = Y + 0.3
	local bw, bd, bh = 170, 80, 36
	local bz = z0 + 10 + bd / 2
	local navy = Color3.fromRGB(30, 50, 90)
	PartKit.Box(model, "Building", Vector3.new(bw, bh, bd), CFrame.new(cx, floorY + bh / 2, bz), Color3.fromRGB(220, 222, 226), CONCRETE)
	PartKit.Box(model, "Stripe", Vector3.new(bw + 0.6, 4, bd + 0.6), CFrame.new(cx, floorY + bh - 6, bz), navy, SMOOTH)
	for f = 0, 1 do
		PartKit.Box(model, "Windows", Vector3.new(bw + 0.4, 5, bd + 0.4), CFrame.new(cx, floorY + 8 + f * 13, bz), Color3.fromRGB(60, 80, 100), GLASS, DECOR)
	end
	local sign = PartKit.Box(model, "Sign", Vector3.new(60, 9, 1), CFrame.new(cx, floorY + bh + 5, bz + bd / 2 - 1), navy, SMOOTH)
	PartKit.Sign(sign, Enum.NormalId.Back, "POLICE", Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBlack, 10)
	PartKit.Sign(sign, Enum.NormalId.Front, "POLICE", Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBlack, 10)
	PartKit.Box(model, "Entrance", Vector3.new(20, 14, 6), CFrame.new(cx, floorY + 7, bz + bd / 2 + 3), navy, SMOOTH)
	PartKit.Post(model, "FlagPole", 0.6, 40, Vector3.new(cx + 40, floorY, bz + bd / 2 + 16), Color3.fromRGB(220, 220, 225), Enum.Material.Metal, NO_COLLIDE)
	-- parked cruisers
	for i = 0, 3 do
		local car = CarModel.Build("Police", { Static = true })
		PartKit.Scale(car, 1 / Config.WORLD_SCALE) -- vehicles are true size; the city shrinks later
		PartKit.PlaceStatic(car, CFrame.new(x0 + 30 + i * 26, floorY, z1 - 40) * CFrame.Angles(0, math.pi, 0))
		car.Parent = model
		PartKit.Box(model, "Bay", Vector3.new(0.4, 0.05, 24), CFrame.new(x0 + 17 + i * 26, floorY + 0.03, z1 - 40), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	for i = 0, 2 do
		Props.Tree(model, Vector3.new(x1 - 20 - i * 30, floorY, z1 - 12), rng, 0.8)
	end
	return model
end

--------------------------------------------------------------------------------
-- City plaza: fountain, bike statue, steps up to a terrace with a street kicker
--------------------------------------------------------------------------------
function Landmarks.Plaza(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "Plaza")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	PartKit.Box(model, "Paving", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(212, 200, 182), Enum.Material.Pavement)
	local fy = Y + 0.3
	-- fountain (rim taller than a bike can climb)
	PartKit.Post(model, "FountainRim", 46, 1.8, Vector3.new(cx, fy, cz), Color3.fromRGB(200, 196, 190), Enum.Material.Marble)
	local water = PartKit.Post(model, "Water", 42, 1.85, Vector3.new(cx, fy, cz), Color3.fromRGB(70, 150, 200), SMOOTH)
	water.Transparency = 0.25
	water.Reflectance = 0.3
	PartKit.Post(model, "Column", 4, 10, Vector3.new(cx, fy, cz), Color3.fromRGB(200, 196, 190), Enum.Material.Marble)
	PartKit.Post(model, "Bowl", 14, 1.2, Vector3.new(cx, fy + 10, cz), Color3.fromRGB(200, 196, 190), Enum.Material.Marble)
	PartKit.Ball(model, "Spray", 6, Vector3.new(cx, fy + 13, cz), Color3.fromRGB(200, 230, 255), Enum.Material.Glass, DECOR).Transparency = 0.5
	-- statue: a Flightly bike on a plinth
	local sx, sz = cx + 80, cz - 70
	PartKit.Box(model, "Plinth", Vector3.new(16, 8, 10), CFrame.new(sx, fy + 4, sz), Color3.fromRGB(80, 82, 88), Enum.Material.Granite)
	local statue = BikeModel.Build(Bikes.List[#Bikes.List], { Frame = "gold", Accent = "gold", Rims = "gold" }, { Static = true })
	PartKit.Scale(statue, 1 / Config.WORLD_SCALE) -- vehicles are true size; the city shrinks later
	PartKit.PlaceStatic(statue, CFrame.new(sx, fy + 8.9, sz) * CFrame.Angles(0, math.rad(60), 0) * CFrame.Angles(math.rad(25), 0, 0))
	statue.Name = "Statue"
	statue:SetAttribute("Gold", true)
	statue.Parent = model
	local plaque = PartKit.Box(model, "StatuePlaque", Vector3.new(12, 3, 0.3), CFrame.new(sx, fy + 4, sz + 5.2), Color3.fromRGB(200, 170, 70), Enum.Material.Metal, DECOR)
	PartKit.Sign(plaque, Enum.NormalId.Back, "Flightly — est. 2026", Color3.fromRGB(40, 30, 10), nil, Enum.Font.FredokaOne, 20)
	-- raised terrace with steps and a kicker off the end
	local tx0, tx1 = x0 + 10, x0 + 110
	local tz0, tz1 = z0 + 10, z0 + 90
	local th = 6
	PartKit.Box(model, "Terrace", Vector3.new(tx1 - tx0, th, tz1 - tz0), CFrame.new((tx0 + tx1) / 2, fy + th / 2, (tz0 + tz1) / 2), Color3.fromRGB(190, 182, 170), Enum.Material.Pavement)
	-- steps on the south side (each 1 stud: a bike rolls up them)
	for i = 1, 5 do
		local stepZ = tz1 + (6 - i) * 3 - 1.5
		PartKit.Box(model, "Step", Vector3.new(60, i, 3), CFrame.new((tx0 + tx1) / 2 + 20, fy + i / 2, stepZ), Color3.fromRGB(200, 192, 180), Enum.Material.Pavement)
	end
	-- a ramp up the east side of the terrace
	PartKit.Ramp(model, "TerraceRamp", Vector3.new(tx1 + 30, fy, (tz0 + tz1) / 2), Vector3.new(tx1, fy + th, (tz0 + tz1) / 2), 20, Color3.fromRGB(190, 182, 170), Enum.Material.Pavement)
	-- wooden kicker on the terrace pointing west, off the edge
	Landmarks.Kicker(model, Vector3.new(tx0 + 30, fy + th, (tz0 + tz1) / 2), Vector3.new(-1, 0, 0), 4, 10, 12)
	-- benches and trees
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		local p = Vector3.new(cx + math.cos(angle) * 40, fy, cz + math.sin(angle) * 40)
		Props.Bench(model, CFrame.lookAt(p, Vector3.new(cx, fy, cz)) * CFrame.Angles(0, math.pi, 0))
		Props.Tree(model, Vector3.new(cx + math.cos(angle + 0.5) * 70, fy, cz + math.sin(angle + 0.5) * 70), rng, 0.9)
	end
	return model
end

--------------------------------------------------------------------------------
-- Ramps
--------------------------------------------------------------------------------
-- A wooden kicker: a plywood slab rising along `dir` from `base` to `height`, on posts
function Landmarks.Kicker(parent: Instance, base: Vector3, dir: Vector3, height: number, length: number, width: number)
	local model = PartKit.Model(parent, "Kicker")
	local lip = base + dir * length + Vector3.new(0, height, 0)
	local wood = Color3.fromRGB(176, 136, 90)
	local surface = PartKit.Slab(model, "Ramp", base, lip, width, 0.6, wood, Enum.Material.WoodPlanks)
	surface:SetAttribute("Surface", "Ramp")
	-- back wall and posts
	local backCenter = base + dir * (length + 0.3) + Vector3.new(0, height / 2 - 0.3, 0)
	PartKit.Box(model, "Back", Vector3.new(width, height - 0.4, 0.6), CFrame.lookAt(backCenter, backCenter + dir), Color3.fromRGB(140, 104, 66), Enum.Material.Wood)
	for _, t in { 0.4, 0.75 } do
		for _, side in { -1, 1 } do
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local p = base + dir * (length * t) + right * (side * (width / 2 - 0.6))
			local h = height * t - 0.4
			if h > 0.3 then
				PartKit.Box(model, "Post", Vector3.new(0.6, h, 0.6), CFrame.new(p + Vector3.new(0, h / 2, 0)), Color3.fromRGB(110, 80, 50), Enum.Material.Wood, NO_COLLIDE)
			end
		end
	end
	return model
end

-- A dirt tabletop: up-ramp, flat table, down-ramp, all solid
local function tabletop(parent: Instance, start: Vector3, dir: Vector3, height: number, rampLength: number, tableLength: number, width: number)
	local dirt = Props.Palette.Dirt
	local up0 = start
	local up1 = start + dir * rampLength + Vector3.new(0, height, 0)
	local table1 = up1 + dir * tableLength
	local down1 = table1 + dir * (rampLength * 1.4) - Vector3.new(0, height, 0)
	PartKit.Ramp(parent, "TakeOff", up0, up1, width, dirt, Enum.Material.Ground)
	local mid = (up1 + table1) / 2
	PartKit.Box(parent, "Table", Vector3.new(width, height, tableLength + 1), CFrame.lookAt(mid - Vector3.new(0, height / 2, 0), mid - Vector3.new(0, height / 2, 0) + dir), dirt, Enum.Material.Ground)
	PartKit.Ramp(parent, "Landing", down1, table1, width, dirt, Enum.Material.Ground)
end

--------------------------------------------------------------------------------
-- Jump Park: a mega ramp with a roll-in tower, a dirt jump line and a row of wooden kickers
--------------------------------------------------------------------------------
function Landmarks.JumpPark(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "JumpPark")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local dirt = Props.Palette.Dirt
	local gy = Y + 0.3
	local ground = PartKit.Box(model, "Dirt", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), dirt, Enum.Material.Ground)
	ground:SetAttribute("Surface", "Dirt")
	local north = Vector3.new(0, 0, -1)

	-- Mega ramp (west lane): climb ramp up the far west edge (south to north... then a platform at
	-- the south end), roll-in heading north, a big kicker and a long landing.
	local laneX = x0 + 36
	local climbX = x0 + 10
	local towerH = 36
	local towerZ0, towerZ1 = z1 - 40, z1 - 6
	-- Tower platform spanning both lanes
	PartKit.Box(model, "Tower", Vector3.new(50, towerH, towerZ1 - towerZ0), CFrame.new(x0 + 26, gy + towerH / 2, (towerZ0 + towerZ1) / 2), Color3.fromRGB(150, 116, 80), Enum.Material.WoodPlanks)
	PartKit.Box(model, "TowerRail", Vector3.new(50, 3, 1), CFrame.new(x0 + 26, gy + towerH + 1.5, towerZ1), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	local towerSign = PartKit.Box(model, "TowerSign", Vector3.new(40, 6, 1), CFrame.new(x0 + 26, gy + towerH + 6, towerZ1 - 0.5), Color3.fromRGB(26, 28, 34), SMOOTH, NO_COLLIDE)
	PartKit.Sign(towerSign, Enum.NormalId.Front, "MEGA RAMP", Color3.fromRGB(255, 122, 24), nil, Enum.Font.FredokaOne, 10)
	-- Climb: a long gentle ramp along the west edge from the north end up to the tower
	PartKit.Ramp(model, "Climb", Vector3.new(climbX, gy, z0 + 30), Vector3.new(climbX, gy + towerH, towerZ0), 16, Color3.fromRGB(150, 116, 80), Enum.Material.WoodPlanks)
	-- Roll-in: 30 degrees down heading north from the platform
	local rollStart = Vector3.new(laneX, gy + towerH, towerZ0)
	local rollRun = towerH / math.tan(math.rad(32))
	local rollEnd = rollStart + north * rollRun - Vector3.new(0, towerH, 0)
	PartKit.Ramp(model, "RollIn", rollEnd, rollStart, 18, Color3.fromRGB(176, 136, 90), Enum.Material.WoodPlanks)
	-- run-out, kicker and landing
	local kickStart = rollEnd + north * 30
	local kickH, kickLen = 9, 16
	local kickLip = kickStart + north * kickLen + Vector3.new(0, kickH, 0)
	PartKit.Ramp(model, "MegaKicker", kickStart, kickLip, 18, Color3.fromRGB(176, 136, 90), Enum.Material.WoodPlanks)
	local landTop = kickLip + north * 30
	local landBottom = landTop + north * 60 - Vector3.new(0, kickH, 0)
	PartKit.Ramp(model, "MegaLanding", landBottom, landTop, 26, Color3.fromRGB(176, 136, 90), Enum.Material.WoodPlanks)

	-- Dirt jump line (centre lane): three tabletops, small to big, heading north
	local lineX = cx + 4
	local z = z1 - 30
	for i, h in { 3.5, 5.5, 7.5 } do
		local rampLen = h / math.tan(math.rad(24))
		local tableLen = 14 + i * 4
		local start = Vector3.new(lineX, gy, z)
		tabletop(model, start, north, h, rampLen, tableLen, 20)
		z -= rampLen + tableLen + rampLen * 1.4 + 26
	end

	-- Kicker row (east lane): wooden kickers with run-outs
	local kx = x1 - 34
	local kz = z1 - 40
	for _, spec in { { 2.5, 7 }, { 4, 10 }, { 5.5, 13 } } do
		Landmarks.Kicker(model, Vector3.new(kx, gy, kz), north, spec[1], spec[2], 14)
		kz -= spec[2] + 70
	end

	-- Fence posts around the edge, an entrance arch on the south side
	for i = 0, 16 do
		local x = x0 + 4 + i * (x1 - x0 - 8) / 16
		PartKit.Post(model, "FencePost", 0.5, 4, Vector3.new(x, gy, z0 + 3), Color3.fromRGB(120, 90, 60), Enum.Material.Wood, NO_COLLIDE)
	end
	local archZ = z1 - 2
	for _, side in { -1, 1 } do
		PartKit.Post(model, "ArchPost", 1.6, 22, Vector3.new(cx + side * 30, gy, archZ), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	end
	local arch = PartKit.Box(model, "ArchSign", Vector3.new(64, 7, 1.2), CFrame.new(cx, gy + 24, archZ), Color3.fromRGB(255, 122, 24), SMOOTH, NO_COLLIDE)
	PartKit.Sign(arch, Enum.NormalId.Back, "JUMP PARK", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 12)
	PartKit.Sign(arch, Enum.NormalId.Front, "JUMP PARK", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 12)
	for _ = 1, 6 do
		Props.Tree(model, Vector3.new(x0 + rng:NextNumber(60, 110), gy, z0 + rng:NextNumber(10, 40)), rng, 0.9)
	end
	return model
end

--------------------------------------------------------------------------------
-- Central Park (two blocks): lawns, paths, a pond, lots of trees, benches and a few small hills
--------------------------------------------------------------------------------
function Landmarks.Park(parent: Instance, blocks: { LayoutModule.Block }, rng: Random)
	local model = PartKit.Model(parent, "CentralPark")
	for _, block in blocks do
		local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		local lawn = PartKit.Box(model, "Lawn", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Props.Palette.Lawn, Enum.Material.Grass)
		lawn:SetAttribute("Surface", "Grass")
		local py = Y + 0.3
		-- cross paths
		PartKit.Box(model, "Path", Vector3.new(14, 0.2, z1 - z0), CFrame.new(cx, py + 0.1, cz), Color3.fromRGB(196, 186, 168), Enum.Material.Pavement)
		PartKit.Box(model, "Path", Vector3.new(x1 - x0, 0.2, 14), CFrame.new(cx, py + 0.1, cz), Color3.fromRGB(196, 186, 168), Enum.Material.Pavement)
		-- pond in one quadrant
		local px, pz = cx - (x1 - x0) / 4, cz + (z1 - z0) / 4
		PartKit.Post(model, "PondRim", 80, 1.8, Vector3.new(px, py, pz), Color3.fromRGB(140, 136, 128), Enum.Material.Cobblestone)
		local water = PartKit.Post(model, "Pond", 76, 1.85, Vector3.new(px, py, pz), Color3.fromRGB(60, 120, 150), SMOOTH)
		water.Transparency = 0.2
		water.Reflectance = 0.35
		-- a grass hill with a gentle rideable slope on each side
		local hx, hz = cx + (x1 - x0) / 4, cz - (z1 - z0) / 4
		local hill = PartKit.Box(model, "HillTop", Vector3.new(30, 6, 30), CFrame.new(hx, py + 3, hz), Props.Palette.Lawn, Enum.Material.Grass)
		hill:SetAttribute("Surface", "Grass")
		for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			local edge = Vector3.new(hx, py + 6, hz) + d * 15
			local foot = edge + d * 26 - Vector3.new(0, 6, 0)
			local slope = PartKit.Ramp(model, "HillSide", foot, edge, 30, Props.Palette.Lawn, Enum.Material.Grass)
			slope:SetAttribute("Surface", "Grass")
		end
		-- trees and benches
		for _ = 1, 26 do
			local x = rng:NextNumber(x0 + 8, x1 - 8)
			local zz = rng:NextNumber(z0 + 8, z1 - 8)
			local onPath = math.abs(x - cx) < 14 or math.abs(zz - cz) < 14
			local inPond = (Vector3.new(x, 0, zz) - Vector3.new(px, 0, pz)).Magnitude < 50
			local onHill = math.abs(x - hx) < 48 and math.abs(zz - hz) < 48
			if not onPath and not inPond and not onHill then
				Props.Tree(model, Vector3.new(x, py, zz), rng)
			end
		end
		for i = -2, 2 do
			if i ~= 0 then
				Props.Bench(model, CFrame.new(cx + 12, py, cz + i * 40) * CFrame.Angles(0, math.rad(90), 0))
				Props.Lamp(model, Vector3.new(cx - 10, py, cz + i * 40 + 10))
			end
		end
	end
	return model
end

return Landmarks
