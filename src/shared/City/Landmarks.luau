--[[
	Landmarks: Flighty Mechanics (the dealership, where you spawn), the police station, the city
	plaza, the Jump and Loop parks, Bayfront Park and the marina.

	The dealership holds a prompt named DealershipPrompt (opens the dealership menu) and one named
	TuningPrompt (the service bay). Showroom bikes are static BikeModels on turntables.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder scales the finished city by WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local PartKit = require(script.Parent.Parent.PartKit)
local Detail = require(script.Parent.Detail)
local Shore = require(script.Parent.Shore)
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
-- bikes are drawn at their riders' scale, this times the city's: what holds a bike on show
-- (turntables, stages, the show ramp) is sized by it
local BIKE = Config.STUDS_PER_METER / Config.CITY_STUDS_PER_METER

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
	local NEON = Enum.Material.Neon
	local WHITE = Color3.fromRGB(255, 255, 255)
	-- Forecourt: pale paving with a dark band and a painted test-ride lane
	PartKit.Box(model, "Forecourt", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, (z0 + z1) / 2), Color3.fromRGB(206, 204, 200), Enum.Material.Pavement)
	local floorY = Y + 0.3

	-- Showroom: a glass box on the north half, open toward the forecourt (south, +Z)
	local sw, sd, sh = 200, 104, 34
	local sz = z0 + 14 + sd / 2
	local scx = cx - 30
	local front = sz + sd / 2
	PartKit.Box(model, "ShowroomFloor", Vector3.new(sw, 0.4, sd), CFrame.new(scx, floorY + 0.2, sz), Color3.fromRGB(34, 36, 42), Enum.Material.Marble).Reflectance = 0.12
	-- tile seams
	for i = 1, 9 do
		PartKit.Box(model, "Seam", Vector3.new(0.2, 0.05, sd), CFrame.new(scx - sw / 2 + i * sw / 10, floorY + 0.42, sz), Color3.fromRGB(70, 72, 80), SMOOTH, DECOR)
	end
	for i = 1, 4 do
		PartKit.Box(model, "Seam", Vector3.new(sw, 0.05, 0.2), CFrame.new(scx, floorY + 0.42, sz - sd / 2 + i * sd / 5), Color3.fromRGB(70, 72, 80), SMOOTH, DECOR)
	end
	local top = floorY + sh
	PartKit.Box(model, "Roof", Vector3.new(sw + 6, 3, sd + 6), CFrame.new(scx, top + 1.5, sz), FLIGHTY_DARK, SMOOTH)
	PartKit.Box(model, "RoofTrim", Vector3.new(sw + 6.4, 1.2, sd + 6.4), CFrame.new(scx, top + 0.2, sz), FLIGHTY_ORANGE, NEON, DECOR)
	-- LED strips across the ceiling
	for i = 1, 6 do
		local strip = PartKit.Box(model, "CeilingLED", Vector3.new(sw - 10, 0.3, 1.2), CFrame.new(scx, top - 0.4, sz - sd / 2 + i * sd / 7), Color3.fromRGB(240, 245, 255), NEON, DECOR)
		local _ = strip
	end
	-- back wall with the big neon logo and two video walls
	PartKit.Box(model, "BackWall", Vector3.new(sw, sh, 2), CFrame.new(scx, floorY + sh / 2, sz - sd / 2), FLIGHTY_DARK, SMOOTH)
	local logo = PartKit.Box(model, "WallLogo", Vector3.new(90, 12, 0.6), CFrame.new(scx, floorY + sh - 9, sz - sd / 2 + 1.4), FLIGHTY_DARK, SMOOTH, DECOR)
	PartKit.Sign(logo, Enum.NormalId.Back, "FLIGHTLY", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	for _, edge in { -1, 1 } do
		PartKit.Box(model, "LogoGlow", Vector3.new(92, 0.6, 0.4), CFrame.new(scx, floorY + sh - 9 + edge * 6.6, sz - sd / 2 + 1.5), FLIGHTY_ORANGE, NEON, DECOR)
	end
	local screens: { { X: number, Text: string } } = { { X = scx - 72, Text = "RIDE THE CITY" }, { X = scx + 72, Text = "NEW: DEATHRIDER" } }
	for _, screen in screens do
		local frame = PartKit.Box(model, "VideoWall", Vector3.new(34, 18, 0.8), CFrame.new(screen.X, floorY + 14, sz - sd / 2 + 1.4), Color3.fromRGB(10, 10, 12), SMOOTH, DECOR)
		local _ = frame
		local panel = PartKit.Box(model, "VideoScreen", Vector3.new(32, 16, 0.3), CFrame.new(screen.X, floorY + 14, sz - sd / 2 + 1.9), Color3.fromRGB(30, 60, 120), NEON, DECOR)
		PartKit.Sign(panel, Enum.NormalId.Back, screen.Text, WHITE, Color3.fromRGB(20, 40, 90), Enum.Font.FredokaOne, 10)
	end
	for _, side in { -1, 1 } do
		local glass = PartKit.Box(model, "SideGlass", Vector3.new(1, sh, sd), CFrame.new(scx + side * sw / 2, floorY + sh / 2, sz), Color3.fromRGB(150, 190, 210), GLASS)
		glass.Transparency = 0.55
	end
	-- front: glass panels with a wide open entrance in the middle
	local entrance = 50
	local panelW = (sw - entrance) / 2
	for _, side in { -1, 1 } do
		local g = PartKit.Box(model, "FrontGlass", Vector3.new(panelW, sh, 1), CFrame.new(scx + side * (entrance / 2 + panelW / 2), floorY + sh / 2, front), Color3.fromRGB(150, 190, 210), GLASS)
		g.Transparency = 0.55
		g.Reflectance = 0.1
	end
	PartKit.Box(model, "EntranceLintel", Vector3.new(entrance, 8, 1.2), CFrame.new(scx, top - 4, front), FLIGHTY_DARK, SMOOTH)
	for i = 0, 4 do
		local x = scx - sw / 2 + i * sw / 4
		PartKit.Box(model, "Column", Vector3.new(2, sh, 2), CFrame.new(x, floorY + sh / 2, front), FLIGHTY_DARK, SMOOTH)
		PartKit.Box(model, "ColumnGlow", Vector3.new(0.4, sh - 2, 2.1), CFrame.new(x, floorY + sh / 2, front), FLIGHTY_ORANGE, NEON, DECOR)
	end
	-- the big sign on the roof edge, lit from below
	local signBoard = PartKit.Box(model, "Sign", Vector3.new(150, 16, 2), CFrame.new(scx, top + 11, front - 2), FLIGHTY_DARK, SMOOTH)
	PartKit.Sign(signBoard, Enum.NormalId.Back, "FLIGHTY MECHANICS", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	PartKit.Sign(signBoard, Enum.NormalId.Front, "FLIGHTY MECHANICS", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	PartKit.Box(model, "SignGlow", Vector3.new(152, 0.8, 2.4), CFrame.new(scx, top + 2.8, front - 2), FLIGHTY_ORANGE, NEON, DECOR)
	local tagline = PartKit.Box(model, "Tagline", Vector3.new(90, 5, 1), CFrame.new(scx, top - 4, front + 0.8), FLIGHTY_DARK, SMOOTH, DECOR)
	PartKit.Sign(tagline, Enum.NormalId.Back, "Home of " .. Config.BRAND .. " e-bikes", WHITE, nil, Enum.Font.FredokaOne, 10)

	-- Hero stage at the back: the top bike on a two-tier lit plinth under spotlights
	local hero = Bikes.List[#Bikes.List]
	local stage = Vector3.new(scx, floorY + 0.4, sz - sd / 2 + 24)
	PartKit.Post(model, "StageBase", 26 * BIKE, 1.4, stage, Color3.fromRGB(20, 20, 24), SMOOTH)
	PartKit.Post(model, "StageRing", 26 * BIKE + 0.6, 0.4, stage + Vector3.new(0, 1.2, 0), Bikes.RarityColors[hero.Rarity], NEON, DECOR)
	PartKit.Post(model, "StageTop", 18 * BIKE, 1.2, stage + Vector3.new(0, 1.4, 0), Color3.fromRGB(30, 30, 34), Enum.Material.Marble)
	PartKit.Post(model, "StageRing2", 18 * BIKE + 0.6, 0.3, stage + Vector3.new(0, 2.5, 0), Bikes.RarityColors[hero.Rarity], NEON, DECOR)
	local heroModel = BikeModel.Build(hero, nil, { Static = true })
	PartKit.Scale(heroModel, 1 / Config.WORLD_SCALE)
	PartKit.PlaceStatic(heroModel, CFrame.new(stage + Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(60), 0))
	heroModel.Name = "Display_" .. hero.Id
	heroModel.Parent = model
	for _, side in { -1, 1 } do
		local lamp = PartKit.Box(model, "Spot", Vector3.new(2.4, 2.4, 3), CFrame.lookAt(stage + Vector3.new(side * 14, sh - 3, 14), stage + Vector3.new(0, 3, 0)), Color3.fromRGB(30, 30, 34), Enum.Material.Metal, DECOR)
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Angle = 35
		beam.Range = 50
		beam.Brightness = 4
		beam.Color = Color3.fromRGB(255, 200, 150)
		beam.Parent = lamp
	end
	local heroSign = PartKit.Box(model, "HeroPlaque", Vector3.new(16, 3, 0.4), CFrame.new(stage + Vector3.new(0, 2.2, 13 * BIKE + 0.4)) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(14, 14, 16), SMOOTH, DECOR)
	PartKit.Sign(heroSign, Enum.NormalId.Back, string.upper(hero.Name) .. "  $" .. tostring(hero.Price), Bikes.RarityColors[hero.Rarity], nil, Enum.Font.FredokaOne, 20)

	-- The rest of the line-up on turntables, two rows either side of the stage
	local others = {}
	for i, bike in Bikes.List do
		if i < #Bikes.List then
			table.insert(others, bike)
		end
	end
	local perRow = math.ceil(#others / 2)
	for i, bike in others do
		local row = if i <= perRow then 0 else 1
		local col = if row == 0 then i - 1 else i - 1 - perRow
		local x = scx - sw / 2 + 18 + col * ((sw - 36) / math.max(perRow - 1, 1))
		local z = sz + 4 + row * 30
		local deckY = floorY + 0.4
		PartKit.Post(model, "Turntable", 13 * BIKE, 1.0, Vector3.new(x, deckY, z), Color3.fromRGB(30, 32, 36), SMOOTH)
		PartKit.Post(model, "TurntableRing", 13 * BIKE + 0.4, 0.3, Vector3.new(x, deckY + 0.85, z), Bikes.RarityColors[bike.Rarity], NEON, DECOR)
		local display = BikeModel.Build(bike, nil, { Static = true })
		PartKit.Scale(display, 1 / Config.WORLD_SCALE) -- bikes are at their riders' scale; the city is scaled later
		PartKit.PlaceStatic(display, CFrame.new(x, deckY + 1.0, z) * CFrame.Angles(0, math.rad(if row == 0 then 35 else -35), 0))
		display.Name = "Display_" .. bike.Id
		display.Parent = model
		local plaque = PartKit.Box(model, "Plaque", Vector3.new(9, 2.4, 0.3), CFrame.new(x, deckY + 1.6, z + 6.5 * BIKE + 0.5) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(20, 20, 24), SMOOTH, DECOR)
		local price = if bike.Price == 0 then "FREE" else "$" .. tostring(bike.Price)
		PartKit.Sign(plaque, Enum.NormalId.Back, bike.Name .. "  " .. price, WHITE, nil, Enum.Font.FredokaOne, 20)
	end

	-- Lounge (west end): rug, sofas, coffee table, plants
	local lounge = Vector3.new(scx - sw / 2 + 20, floorY + 0.4, sz - sd / 2 + 16)
	PartKit.Box(model, "Rug", Vector3.new(26, 0.1, 18), CFrame.new(lounge + Vector3.new(0, 0.05, 0)), Color3.fromRGB(120, 60, 30), Enum.Material.Fabric, DECOR)
	for _, side in { -1, 1 } do
		local sofa = lounge + Vector3.new(0, 0, side * 7)
		PartKit.Box(model, "Sofa", Vector3.new(16, 2.2, 4), CFrame.new(sofa + Vector3.new(0, 1.1, 0)), Color3.fromRGB(40, 42, 48), Enum.Material.Fabric)
		PartKit.Box(model, "SofaBack", Vector3.new(16, 3, 1.2), CFrame.new(sofa + Vector3.new(0, 2.6, side * 1.6)), Color3.fromRGB(40, 42, 48), Enum.Material.Fabric)
		for _, e in { -1, 1 } do
			PartKit.Box(model, "SofaArm", Vector3.new(1.2, 3.2, 4), CFrame.new(sofa + Vector3.new(e * 8.4, 1.6, 0)), Color3.fromRGB(34, 36, 40), Enum.Material.Fabric, DECOR)
		end
	end
	PartKit.Box(model, "CoffeeTable", Vector3.new(8, 0.4, 4), CFrame.new(lounge + Vector3.new(0, 1.6, 0)), Color3.fromRGB(240, 240, 240), Enum.Material.Glass, DECOR).Transparency = 0.3
	for _, x in { -12, 12 } do
		PartKit.Post(model, "Planter", 3, 3, lounge + Vector3.new(x, 0, -9), Color3.fromRGB(230, 230, 230), SMOOTH, DECOR)
		PartKit.Ball(model, "Plant", 5, lounge + Vector3.new(x, 5, -9), Color3.fromRGB(60, 130, 60), Enum.Material.Grass, DECOR)
	end

	-- Parts on show (east end): batteries and motors on pedestals under glass
	for i = 0, 2 do
		local p = Vector3.new(scx + sw / 2 - 16, floorY + 0.4, sz - sd / 2 + 14 + i * 12)
		PartKit.Box(model, "Pedestal", Vector3.new(5, 4, 5), CFrame.new(p + Vector3.new(0, 2, 0)), WHITE, SMOOTH)
		local case = PartKit.Box(model, "GlassCase", Vector3.new(4.6, 4, 4.6), CFrame.new(p + Vector3.new(0, 6, 0)), Color3.fromRGB(200, 230, 240), GLASS, DECOR)
		case.Transparency = 0.7
		if i == 1 then
			PartKit.Cylinder(model, "Motor", 2.6, 1.6, CFrame.new(p + Vector3.new(0, 5.4, 0)), Color3.fromRGB(70, 72, 78), Enum.Material.Metal, DECOR)
			PartKit.Cylinder(model, "MotorCap", 1.6, 1.7, CFrame.new(p + Vector3.new(0, 5.4, 0)), FLIGHTY_ORANGE, SMOOTH, DECOR)
		else
			PartKit.Box(model, "BatteryPack", Vector3.new(1.4, 1.2, 3.4), CFrame.new(p + Vector3.new(0, 4.8, 0)), Color3.fromRGB(36, 38, 42), SMOOTH, DECOR)
			PartKit.Box(model, "BatteryStripe", Vector3.new(1.45, 0.3, 2.8), CFrame.new(p + Vector3.new(0, 5.1, 0)), FLIGHTY_ORANGE, SMOOTH, DECOR)
		end
	end
	-- Helmet wall
	local shelf = Vector3.new(scx + sw / 2 - 2, floorY + 10, sz + 18)
	for row = 0, 1 do
		PartKit.Box(model, "Shelf", Vector3.new(1.4, 0.4, 30), CFrame.new(shelf + Vector3.new(-0.8, row * 6, 0)), Color3.fromRGB(240, 240, 240), SMOOTH, DECOR)
		for k = 0, 4 do
			local colors = { FLIGHTY_ORANGE, Color3.fromRGB(240, 240, 240), Color3.fromRGB(20, 20, 24), Color3.fromRGB(40, 120, 230), Color3.fromRGB(220, 30, 50) }
			PartKit.Ball(model, "Helmet", 2.6, shelf + Vector3.new(-1.4, row * 6 + 1.4, -12 + k * 6), colors[(k + row) % #colors + 1], SMOOTH, DECOR)
		end
	end

	-- Sales counter with the dealership prompt
	local counterPos = Vector3.new(scx + sw / 2 - 30, floorY + 2.2, front - 10)
	local counter = PartKit.Box(model, "Counter", Vector3.new(26, 4.4, 6), CFrame.new(counterPos), FLIGHTY_DARK, SMOOTH)
	PartKit.Box(model, "CounterTop", Vector3.new(26.4, 0.4, 6.4), CFrame.new(counterPos + Vector3.new(0, 2.4, 0)), FLIGHTY_ORANGE, SMOOTH)
	PartKit.Box(model, "CounterGlow", Vector3.new(26.2, 0.3, 0.2), CFrame.new(counterPos + Vector3.new(0, -1.9, 3.05)), FLIGHTY_ORANGE, NEON, DECOR)
	for _, x in { -7, 7 } do
		PartKit.Box(model, "Monitor", Vector3.new(4, 2.6, 0.3), CFrame.new(counterPos + Vector3.new(x, 4.2, -1)) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(20, 20, 24), SMOOTH, DECOR)
		PartKit.Box(model, "MonitorScreen", Vector3.new(3.6, 2.2, 0.1), CFrame.new(counterPos + Vector3.new(x, 4.2, -0.82)) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(120, 200, 255), NEON, DECOR)
	end
	local counterSign = PartKit.Box(model, "CounterSign", Vector3.new(16, 4, 0.4), CFrame.new(counterPos + Vector3.new(0, 9, -2)), FLIGHTY_ORANGE, SMOOTH, DECOR)
	PartKit.Sign(counterSign, Enum.NormalId.Back, "BUY BIKES", WHITE, nil, Enum.Font.FredokaOne, 20)
	PartKit.Sign(counterSign, Enum.NormalId.Front, "BUY BIKES", WHITE, nil, Enum.Font.FredokaOne, 20)
	local dealer = prompt(counter, "DealershipPrompt", "Browse bikes", Config.DEALERSHIP)
	dealer.MaxActivationDistance = 20
	-- A second sales prompt at the entrance, so riders don't have to come inside
	local kioskPos = Vector3.new(scx - entrance / 2 - 8, floorY + 3, front + 10)
	local kiosk = PartKit.Box(model, "SalesKiosk", Vector3.new(4, 6, 2), CFrame.new(kioskPos), FLIGHTY_DARK, SMOOTH)
	PartKit.Box(model, "KioskScreen", Vector3.new(3.2, 3, 0.2), CFrame.new(kioskPos + Vector3.new(0, 0.8, 1.05)), FLIGHTY_ORANGE, NEON, DECOR)
	prompt(kiosk, "DealershipPrompt", "Browse bikes", Config.DEALERSHIP).MaxActivationDistance = 20

	-- Entrance canopy: cantilevered, glowing underneath
	local canopy = Vector3.new(scx, floorY + 22, front + 12)
	PartKit.Box(model, "Canopy", Vector3.new(entrance + 16, 1.6, 24), CFrame.new(canopy), FLIGHTY_DARK, SMOOTH)
	for k = -2, 2 do
		PartKit.Box(model, "CanopyLED", Vector3.new(entrance + 12, 0.2, 0.8), CFrame.new(canopy + Vector3.new(0, -0.9, k * 4.5)), Color3.fromRGB(255, 240, 220), NEON, DECOR)
	end

	-- Outside: a pylon sign by the street, a bike popping a wheelie off a ramp, test-ride lane
	local pylon = Vector3.new(x0 + 8, floorY, z1 - 10)
	PartKit.Box(model, "Pylon", Vector3.new(10, 44, 3), CFrame.new(pylon + Vector3.new(0, 22, 0)), FLIGHTY_DARK, SMOOTH)
	for _, e in { -1, 1 } do
		PartKit.Box(model, "PylonEdge", Vector3.new(0.4, 44, 3.2), CFrame.new(pylon + Vector3.new(e * 5, 22, 0)), FLIGHTY_ORANGE, NEON, DECOR)
	end
	local pylonSign = PartKit.Box(model, "PylonSign", Vector3.new(9, 22, 3.2), CFrame.new(pylon + Vector3.new(0, 30, 0)), FLIGHTY_DARK, SMOOTH, DECOR)
	PartKit.Sign(pylonSign, Enum.NormalId.Front, "FLIGHTY\nMECHANICS", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	PartKit.Sign(pylonSign, Enum.NormalId.Back, "FLIGHTY\nMECHANICS", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 8)
	local rampBase = Vector3.new(scx + entrance / 2 + 24, floorY, front + 26)
	PartKit.Ramp(model, "ShowRamp", rampBase + Vector3.new(0, 0, 10) * BIKE, rampBase + Vector3.new(0, 4, -4) * BIKE, 10 * BIKE, FLIGHTY_DARK, SMOOTH)
	local poser = Bikes.Get("hornet_6")
	if poser then
		local wheelie = BikeModel.Build(poser, nil, { Static = true })
		PartKit.Scale(wheelie, 1 / Config.WORLD_SCALE)
		PartKit.PlaceStatic(wheelie, CFrame.new(rampBase + Vector3.new(0, 4.2, -6) * BIKE) * CFrame.Angles(math.rad(28), 0, 0))
		wheelie.Name = "Display_hornet_6"
		wheelie.Parent = model
	end
	-- test-ride lane: dashed loop with cones on the west forecourt
	for k = 0, 9 do
		local x = x0 + 20 + k * 10
		PartKit.Box(model, "LaneDash", Vector3.new(5, 0.05, 0.6), CFrame.new(x, floorY + 0.03, z1 - 90), WHITE, SMOOTH, DECOR)
		if k % 3 == 0 then
			PartKit.Post(model, "Cone", 1.4, 2.2, Vector3.new(x, floorY, z1 - 96), Color3.fromRGB(255, 120, 20), SMOOTH, { Touch = false })
		end
	end
	local lane = PartKit.Box(model, "TestRideSign", Vector3.new(14, 3, 0.4), CFrame.new(x0 + 30, floorY + 4, z1 - 100), Color3.fromRGB(20, 20, 24), SMOOTH, DECOR)
	PartKit.Sign(lane, Enum.NormalId.Back, "TEST RIDE LANE", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 20)

	-- Service bay (tuning) on the east side: roller door half up, lifts with bikes, a workshop
	local bayX = x1 - 34
	local bayZ = z0 + 50
	PartKit.Box(model, "BayBody", Vector3.new(56, 30, 80), CFrame.new(bayX + 4, floorY + 15, bayZ), Color3.fromRGB(60, 64, 70), Enum.Material.Concrete)
	PartKit.Box(model, "BayFloor", Vector3.new(30, 0.3, 70), CFrame.new(bayX - 40, floorY + 0.15, bayZ), Color3.fromRGB(110, 112, 116), Enum.Material.DiamondPlate)
	PartKit.Box(model, "BayDoorFrame", Vector3.new(2, 24, 50), CFrame.new(bayX - 24.5, floorY + 12, bayZ), FLIGHTY_ORANGE, SMOOTH, DECOR)
	PartKit.Box(model, "BayDoor", Vector3.new(1, 9, 44), CFrame.new(bayX - 24.8, floorY + 19, bayZ), Color3.fromRGB(28, 30, 34), SMOOTH, DECOR)
	local baySign = PartKit.Box(model, "BaySign", Vector3.new(1, 6, 40), CFrame.new(bayX - 25, floorY + 26, bayZ), FLIGHTY_DARK, SMOOTH, DECOR)
	PartKit.Sign(baySign, Enum.NormalId.Left, "SERVICE & TUNING", FLIGHTY_ORANGE, nil, Enum.Font.FredokaOne, 12)
	PartKit.Box(model, "BaySignGlow", Vector3.new(1.2, 0.5, 42), CFrame.new(bayX - 25.1, floorY + 22.6, bayZ), FLIGHTY_ORANGE, NEON, DECOR)
	local tuneStand = PartKit.Box(model, "TuningStand", Vector3.new(4, 5, 4), CFrame.new(bayX - 36, floorY + 2.5, bayZ + 30), FLIGHTY_ORANGE, SMOOTH)
	prompt(tuneStand, "TuningPrompt", "Tune your bike", "Service bay").MaxActivationDistance = 20
	-- two lifts with bikes up on them
	for k, id in { "trail_t", "storm_x" } do
		local liftPos = Vector3.new(bayX - 44, floorY, bayZ - 22 + (k - 1) * 22)
		PartKit.Box(model, "Lift", Vector3.new(10, 1, 16), CFrame.new(liftPos + Vector3.new(0, 3.5, 0)), Color3.fromRGB(200, 40, 40), Enum.Material.DiamondPlate)
		PartKit.Box(model, "LiftColumn", Vector3.new(2, 3.5, 2), CFrame.new(liftPos + Vector3.new(0, 1.75, 0)), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
		local onLift = Bikes.Get(id)
		if onLift then
			local liftBike = BikeModel.Build(onLift, nil, { Static = true })
			PartKit.Scale(liftBike, 1 / Config.WORLD_SCALE)
			PartKit.PlaceStatic(liftBike, CFrame.new(liftPos + Vector3.new(0, 4, 0)))
			liftBike.Name = "Display_" .. id
			liftBike.Parent = model
		end
	end
	-- workbench, tool wall, tyre stack
	local bench = Vector3.new(bayX - 30, floorY, bayZ + 12)
	PartKit.Box(model, "Workbench", Vector3.new(4, 3.6, 14), CFrame.new(bench + Vector3.new(0, 1.8, 0)), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	PartKit.Box(model, "ToolWall", Vector3.new(0.4, 8, 14), CFrame.new(bench + Vector3.new(1.9, 8, 0)), Color3.fromRGB(200, 200, 196), Enum.Material.Concrete, DECOR)
	for k = 0, 9 do
		PartKit.Box(model, "Tool", Vector3.new(0.3, rng:NextNumber(1.5, 3), 0.4), CFrame.new(bench + Vector3.new(1.6, 7 + rng:NextNumber(-1.5, 1.5), -6 + k * 1.3)), Color3.fromRGB(220, 40, 40), Enum.Material.Metal, DECOR)
	end
	for k = 0, 4 do
		PartKit.Cylinder(model, "Tyre", 3.6, 1.2, CFrame.new(bench + Vector3.new(-4, 0.6 + k * 1.25, -12)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(26, 26, 28), SMOOTH, DECOR)
	end

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
	-- Parking bays with chargers on the west side of the forecourt
	for i = 0, 6 do
		PartKit.Box(model, "Bay", Vector3.new(0.4, 0.05, 18), CFrame.new(x0 + 8 + i * 12, floorY + 0.03, z1 - 60), WHITE, SMOOTH, DECOR)
		if i < 6 then
			local post = Vector3.new(x0 + 14 + i * 12, floorY, z1 - 70)
			PartKit.Box(model, "ChargePost", Vector3.new(1.2, 4, 1.2), CFrame.new(post + Vector3.new(0, 2, 0)), WHITE, SMOOTH, { Touch = false })
			PartKit.Box(model, "ChargeLED", Vector3.new(1.25, 0.4, 1.25), CFrame.new(post + Vector3.new(0, 3.4, 0)), Color3.fromRGB(40, 210, 110), NEON, DECOR)
		end
	end

	-- Detail: glazing bars on the showroom glass, an OPEN sign, banners hung from the ceiling
	for _, side in { -1, 1 } do
		for k = 1, 3 do
			local x = scx + side * (entrance / 2 + k * panelW / 4)
			PartKit.Box(model, "GlazingBar", Vector3.new(0.5, sh, 1.3), CFrame.new(x, floorY + sh / 2, front), FLIGHTY_DARK, SMOOTH, DECOR)
		end
		PartKit.Box(model, "GlazingRail", Vector3.new(panelW, 0.5, 1.3), CFrame.new(scx + side * (entrance / 2 + panelW / 2), floorY + 3, front), FLIGHTY_DARK, SMOOTH, DECOR)
		for k = 1, 3 do
			PartKit.Box(model, "GlazingBar", Vector3.new(1.3, sh, 0.5), CFrame.new(scx + side * sw / 2, floorY + sh / 2, sz - sd / 2 + k * sd / 4), FLIGHTY_DARK, SMOOTH, DECOR)
		end
	end
	local open = PartKit.Box(model, "OpenSign", Vector3.new(8, 3, 0.3), CFrame.new(scx + entrance / 2 + 10, floorY + 9, front - 1), Color3.fromRGB(10, 10, 12), SMOOTH, DECOR)
	PartKit.Sign(open, Enum.NormalId.Front, "OPEN", Color3.fromRGB(255, 70, 60), nil, Enum.Font.GothamBlack, 20)
	PartKit.Sign(open, Enum.NormalId.Back, "OPEN", Color3.fromRGB(255, 70, 60), nil, Enum.Font.GothamBlack, 20)
	for k, text in { "0-60 IN SILENCE", "NO PEDALS. ALL TORQUE.", "RIDE ELECTRIC" } do
		local banner = PartKit.Box(model, "Banner", Vector3.new(16, 7, 0.2), CFrame.new(scx - 60 + (k - 1) * 60, top - 6.5, sz + 10), if k % 2 == 1 then FLIGHTY_ORANGE else FLIGHTY_DARK, Enum.Material.Fabric, DECOR)
		PartKit.Sign(banner, Enum.NormalId.Front, text, WHITE, nil, Enum.Font.FredokaOne, 14)
		PartKit.Sign(banner, Enum.NormalId.Back, text, WHITE, nil, Enum.Font.FredokaOne, 14)
		for _, e in { -7, 7 } do
			PartKit.Box(model, "BannerWire", Vector3.new(0.1, 3, 0.1), CFrame.new(scx - 60 + (k - 1) * 60 + e, top - 1.5, sz + 10), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, DECOR)
		end
	end
	-- riding gear on mannequins by the helmet wall, a waiting row of chairs by the counter
	for k = 0, 2 do
		local base = Vector3.new(scx + sw / 2 - 12, floorY + 0.4, sz + 4 + k * 7)
		local suit = ({ FLIGHTY_ORANGE, Color3.fromRGB(30, 30, 34), Color3.fromRGB(40, 110, 220) })[k + 1]
		PartKit.Post(model, "MannequinBase", 2.4, 0.4, base, Color3.fromRGB(230, 230, 230), SMOOTH, DECOR)
		PartKit.Box(model, "MannequinLegs", Vector3.new(1.6, 3.6, 0.9), CFrame.new(base + Vector3.new(0, 2.2, 0)), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric, DECOR)
		PartKit.Box(model, "Jersey", Vector3.new(2.2, 2.6, 1.1), CFrame.new(base + Vector3.new(0, 5.3, 0)), suit, Enum.Material.Fabric, DECOR)
		PartKit.Ball(model, "Helmet", 1.8, base + Vector3.new(0, 7.4, 0), suit, SMOOTH, DECOR)
	end
	for k = 0, 3 do
		local seat = Vector3.new(counterPos.X - 18 - k * 3.2, floorY + 0.4, front - 6)
		PartKit.Box(model, "Chair", Vector3.new(2.6, 1.8, 2.6), CFrame.new(seat + Vector3.new(0, 0.9, 0)), Color3.fromRGB(240, 240, 240), SMOOTH, DECOR)
		PartKit.Box(model, "ChairBack", Vector3.new(2.6, 2.4, 0.4), CFrame.new(seat + Vector3.new(0, 2.6, -1.1)), FLIGHTY_ORANGE, SMOOTH, DECOR)
	end
	-- the roof: solar panels in rows, aircon units
	for row = 0, 3 do
		for k = 0, 6 do
			local p = Vector3.new(scx - sw / 2 + 24 + k * 24, top + 3.6, sz - sd / 2 + 16 + row * 18)
			PartKit.Box(model, "SolarPanel", Vector3.new(20, 0.4, 12), CFrame.new(p + Vector3.new(0, 1.4, 0)) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(28, 40, 70), Enum.Material.Glass, DECOR)
			PartKit.Box(model, "SolarLeg", Vector3.new(0.4, 1.6, 0.4), CFrame.new(p + Vector3.new(0, 0.6, -4)), Color3.fromRGB(150, 150, 154), Enum.Material.Metal, DECOR)
		end
	end
	for k = 0, 1 do
		local unit = Vector3.new(scx + sw / 2 - 20, top + 3, sz + 30 + k * 14)
		PartKit.Box(model, "AirCon", Vector3.new(10, 5, 8), CFrame.new(unit + Vector3.new(0, 2.5, 0)), Color3.fromRGB(196, 198, 200), Enum.Material.Metal, DECOR)
	end
	-- workshop: parts racks with boxes, oil drums, a compressor, a wheel balancer
	for r = 0, 2 do
		local rack = Vector3.new(bayX - 50 + r * 7, floorY, bayZ + 30)
		for _, e in { -2.6, 2.6 } do
			PartKit.Box(model, "RackPost", Vector3.new(0.3, 12, 0.3), CFrame.new(rack + Vector3.new(e, 6, 0)), FLIGHTY_ORANGE, Enum.Material.Metal, DECOR)
		end
		for level = 0, 3 do
			PartKit.Box(model, "RackShelf", Vector3.new(5.6, 0.2, 2.4), CFrame.new(rack + Vector3.new(0, 1 + level * 3.4, 0)), Color3.fromRGB(70, 72, 78), Enum.Material.Metal, DECOR)
			for b = 0, 2 do
				if rng:NextNumber() < 0.8 then
					PartKit.Box(model, "PartsBox", Vector3.new(1.4, rng:NextNumber(1, 2.2), 1.8), CFrame.new(rack + Vector3.new(-1.8 + b * 1.8, 1.1 + level * 3.4 + 0.8, 0)), Color3.fromRGB(190, 150, 100), Enum.Material.Cardboard, DECOR)
				end
			end
		end
	end
	for k = 0, 2 do
		PartKit.Post(model, "OilDrum", 2.6, 3.8, Vector3.new(bayX - 54 + k * 2.9, floorY, bayZ - 34), ({ Color3.fromRGB(30, 80, 160), Color3.fromRGB(200, 40, 40), Color3.fromRGB(30, 80, 160) })[k + 1], Enum.Material.Metal, DECOR)
	end
	PartKit.Box(model, "Compressor", Vector3.new(3, 3, 5), CFrame.new(bayX - 30, floorY + 1.5, bayZ - 32), Color3.fromRGB(200, 40, 40), Enum.Material.Metal, DECOR)
	PartKit.Cylinder(model, "CompressorTank", 2.6, 4.6, CFrame.new(bayX - 30, floorY + 3.6, bayZ - 32) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(200, 40, 40), Enum.Material.Metal, DECOR)
	PartKit.Box(model, "Balancer", Vector3.new(3, 4, 3), CFrame.new(bayX - 30, floorY + 2, bayZ - 4), Color3.fromRGB(40, 44, 50), Enum.Material.Metal, DECOR)
	PartKit.Cylinder(model, "BalancerWheel", 3.2, 0.9, CFrame.new(bayX - 30, floorY + 4.6, bayZ - 4), Color3.fromRGB(26, 26, 28), SMOOTH, DECOR)
	-- a bike rack and bins by the forecourt
	for k = 0, 4 do
		local hoop = Vector3.new(scx - entrance / 2 - 20 - k * 4, floorY, front + 20)
		PartKit.Box(model, "BikeRack", Vector3.new(0.4, 3, 2.6), CFrame.new(hoop + Vector3.new(0, 1.5, 0)), Color3.fromRGB(150, 154, 160), Enum.Material.Metal, DECOR)
	end
	return model
end

--------------------------------------------------------------------------------
-- Police station
--------------------------------------------------------------------------------
function Landmarks.Police(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "PoliceStation")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx = (x0 + x1) / 2
	local NEON = Enum.Material.Neon
	local WHITE = Color3.fromRGB(255, 255, 255)
	local navy = Color3.fromRGB(30, 50, 90)
	local stone = Color3.fromRGB(214, 210, 200)
	local brick = Color3.fromRGB(120, 70, 55)
	local steel = Color3.fromRGB(150, 154, 160)
	PartKit.Box(model, "Lot", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, (z0 + z1) / 2), Color3.fromRGB(86, 88, 92), Enum.Material.Asphalt)
	local floorY = Y + 0.3

	-- Main building: two storeys and a parapet, brick ground floor, stone upper floor, facing south (+Z)
	local bw, bd = 150, 70
	local storey = 15
	local bh = storey * 2 + 4
	local bx = cx - 40
	local bz = z0 + 12 + bd / 2
	local front = bz + bd / 2
	PartKit.Box(model, "Building", Vector3.new(bw, bh, bd), CFrame.new(bx, floorY + bh / 2, bz), stone, CONCRETE)
	PartKit.Box(model, "BrickBase", Vector3.new(bw + 0.6, storey, bd + 0.6), CFrame.new(bx, floorY + storey / 2, bz), brick, Enum.Material.Brick, DECOR)
	PartKit.Box(model, "FloorBand", Vector3.new(bw + 1.2, 1.2, bd + 1.2), CFrame.new(bx, floorY + storey, bz), stone:Lerp(Color3.new(0, 0, 0), 0.15), CONCRETE, DECOR)
	PartKit.Box(model, "Parapet", Vector3.new(bw + 1.6, 2.2, bd + 1.6), CFrame.new(bx, floorY + bh + 0.1, bz), stone:Lerp(Color3.new(0, 0, 0), 0.1), CONCRETE)
	PartKit.Box(model, "Stripe", Vector3.new(bw + 1.4, 2.4, bd + 1.4), CFrame.new(bx, floorY + bh - 2.6, bz), navy, SMOOTH, DECOR)
	PartKit.Box(model, "StripeCheck", Vector3.new(bw + 1.5, 0.6, bd + 1.5), CFrame.new(bx, floorY + bh - 1.2, bz), WHITE, SMOOTH, DECOR)
	-- windows, one per bay, on every face (named Window so they light up at night)
	local function windowsAlong(faceCF: CFrame, length: number)
		local n = math.floor(length / 12)
		for i = 0, n - 1 do
			local u = -length / 2 + (i + 0.5) * length / n
			for f = 0, 1 do
				local y = floorY + 7.5 + f * storey
				PartKit.Box(model, "WindowSurround", Vector3.new(6.6, 8.6, 0.4), faceCF * CFrame.new(u, y, 0.15), stone:Lerp(WHITE, 0.4), SMOOTH, DECOR)
				PartKit.Box(model, "Window", Vector3.new(5.6, 7.6, 0.4), faceCF * CFrame.new(u, y, 0.3), Color3.fromRGB(60, 80, 100), GLASS, DECOR)
				PartKit.Box(model, "Mullion", Vector3.new(0.3, 7.6, 0.5), faceCF * CFrame.new(u, y, 0.35), Color3.fromRGB(40, 44, 50), SMOOTH, DECOR)
			end
		end
	end
	windowsAlong(CFrame.new(bx, 0, front) , bw)
	windowsAlong(CFrame.new(bx, 0, bz - bd / 2) * CFrame.Angles(0, math.pi, 0), bw)
	windowsAlong(CFrame.new(bx + bw / 2, 0, bz) * CFrame.Angles(0, math.pi / 2, 0), bd)
	windowsAlong(CFrame.new(bx - bw / 2, 0, bz) * CFrame.Angles(0, -math.pi / 2, 0), bd)

	-- Entrance: a stone portico on four columns, glass doors, steps and a ramp, the blue lamps
	local ex = bx
	PartKit.Box(model, "Portico", Vector3.new(40, 3, 16), CFrame.new(ex, floorY + storey + 1.5, front + 8), stone, CONCRETE)
	PartKit.Box(model, "PorticoStripe", Vector3.new(40.4, 1, 16.4), CFrame.new(ex, floorY + storey + 0.6, front + 8), navy, SMOOTH, DECOR)
	local porticoSign = PartKit.Box(model, "Sign", Vector3.new(34, 4.4, 0.6), CFrame.new(ex, floorY + storey + 5.2, front + 15.6), navy, SMOOTH)
	PartKit.Sign(porticoSign, Enum.NormalId.Back, "POLICE", WHITE, nil, Enum.Font.GothamBlack, 10)
	PartKit.Sign(porticoSign, Enum.NormalId.Front, "POLICE", WHITE, nil, Enum.Font.GothamBlack, 10)
	for _, x in { -18, -7, 7, 18 } do
		PartKit.Post(model, "Column", 2.4, storey, Vector3.new(ex + x, floorY, front + 14), stone:Lerp(WHITE, 0.3), Enum.Material.Marble)
	end
	PartKit.Box(model, "EntranceGlass", Vector3.new(16, 11, 0.5), CFrame.new(ex, floorY + 5.5, front + 0.3), Color3.fromRGB(120, 160, 190), GLASS, DECOR).Transparency = 0.4
	for _, x in { -8, 0, 8 } do
		PartKit.Box(model, "DoorFrame", Vector3.new(0.6, 11, 0.7), CFrame.new(ex + x, floorY + 5.5, front + 0.4), Color3.fromRGB(40, 44, 50), SMOOTH, DECOR)
	end
	for _, x in { -11, 11 } do
		-- the classic blue lamp either side of the door
		PartKit.Box(model, "LampBracket", Vector3.new(0.4, 0.4, 2), CFrame.new(ex + x, floorY + 9, front + 1), Color3.fromRGB(30, 30, 34), Enum.Material.Metal, DECOR)
		local lamp = PartKit.Box(model, "BlueLamp", Vector3.new(1.6, 2.2, 1.6), CFrame.new(ex + x, floorY + 9, front + 2.2), Color3.fromRGB(40, 110, 255), NEON, DECOR)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(80, 140, 255)
		glow.Range = 14
		glow.Brightness = 1.2
		glow.Parent = lamp
	end
	for i = 1, 3 do
		PartKit.Box(model, "Step", Vector3.new(26, i * 0.5, 2.2), CFrame.new(ex, floorY + i * 0.25, front + 20 - i * 2.2), Color3.fromRGB(200, 196, 188), CONCRETE)
	end
	PartKit.Ramp(model, "AccessRamp", Vector3.new(ex + 30, floorY, front + 18), Vector3.new(ex + 20, floorY + 1.5, front + 18), 6, Color3.fromRGB(200, 196, 188), CONCRETE)
	for _, x in { -14, -9, 9, 14 } do
		PartKit.Post(model, "Bollard", 1.4, 3, Vector3.new(ex + x, floorY, front + 26), Color3.fromRGB(40, 44, 50), Enum.Material.Metal)
	end
	-- the big rooftop sign, a radio mast, aircon, a rooftop helipad
	local roofY = floorY + bh + 1.2
	local sign = PartKit.Box(model, "Sign", Vector3.new(60, 9, 1), CFrame.new(bx, roofY + 5, front - 1), navy, SMOOTH)
	PartKit.Sign(sign, Enum.NormalId.Back, "CITY POLICE", WHITE, nil, Enum.Font.GothamBlack, 10)
	PartKit.Sign(sign, Enum.NormalId.Front, "CITY POLICE", WHITE, nil, Enum.Font.GothamBlack, 10)
	PartKit.Box(model, "SignGlow", Vector3.new(61, 0.5, 1.4), CFrame.new(bx, roofY + 0.6, front - 1), Color3.fromRGB(60, 130, 255), NEON, DECOR)
	local mast = Vector3.new(bx - bw / 2 + 14, roofY, bz - bd / 2 + 12)
	PartKit.Post(model, "RadioMast", 1, 46, mast, steel, Enum.Material.Metal, DECOR)
	for k = 1, 4 do
		PartKit.Box(model, "MastBrace", Vector3.new(6 - k, 0.3, 0.3), CFrame.new(mast + Vector3.new(0, k * 9, 0)), steel, Enum.Material.Metal, DECOR)
		PartKit.Box(model, "MastAntenna", Vector3.new(0.4, 4, 0.4), CFrame.new(mast + Vector3.new((6 - k) / 2, k * 9 + 2, 0)), Color3.fromRGB(230, 230, 230), SMOOTH, DECOR)
	end
	PartKit.Ball(model, "MastBeacon", 1.4, mast + Vector3.new(0, 46.5, 0), Color3.fromRGB(255, 40, 40), NEON, DECOR)
	for k = 0, 2 do
		local unit = Vector3.new(bx - 30 + k * 16, roofY, bz - bd / 2 + 14)
		PartKit.Box(model, "AirCon", Vector3.new(10, 5, 7), CFrame.new(unit + Vector3.new(0, 2.5, 0)), Color3.fromRGB(196, 198, 200), Enum.Material.Metal, DECOR)
		PartKit.Cylinder(model, "AirConFan", 5, 0.3, CFrame.new(unit + Vector3.new(0, 5.1, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 62, 66), Enum.Material.Metal, DECOR)
	end
	local pad = Vector3.new(bx + bw / 2 - 26, roofY, bz)
	PartKit.Post(model, "Helipad", 40, 0.4, pad, Color3.fromRGB(60, 62, 66), Enum.Material.Asphalt)
	PartKit.Post(model, "HelipadRing", 34, 0.45, pad, Color3.fromRGB(240, 200, 40), SMOOTH, DECOR)
	PartKit.Post(model, "HelipadInner", 32, 0.5, pad, Color3.fromRGB(60, 62, 66), Enum.Material.Asphalt, DECOR)
	for _, x in { -4, 4 } do
		PartKit.Box(model, "HelipadH", Vector3.new(1.6, 0.1, 13), CFrame.new(pad + Vector3.new(x, 0.55, 0)), WHITE, SMOOTH, DECOR)
	end
	PartKit.Box(model, "HelipadH", Vector3.new(8, 0.1, 1.6), CFrame.new(pad + Vector3.new(0, 0.55, 0)), WHITE, SMOOTH, DECOR)
	-- CCTV on the corners
	for _, corner in { Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		local at = Vector3.new(bx + corner.X * (bw / 2 + 0.5), floorY + bh - 6, front + 0.5)
		PartKit.Box(model, "CCTVArm", Vector3.new(0.3, 0.3, 2), CFrame.new(at + Vector3.new(0, 0, 1)), WHITE, SMOOTH, DECOR)
		PartKit.Box(model, "CCTV", Vector3.new(1, 1, 2.2), CFrame.new(at + Vector3.new(corner.X * 0.4, -0.5, 2.2)) * CFrame.Angles(math.rad(-20), 0, 0), WHITE, SMOOTH, DECOR)
	end

	-- Vehicle garage (sally port) on the east with three roller doors, and the impound yard behind a fence
	local gx = bx + bw / 2 + 32
	local gw, gd, gh = 60, 56, 20
	local gz = z0 + 12 + gd / 2
	PartKit.Box(model, "Garage", Vector3.new(gw, gh, gd), CFrame.new(gx, floorY + gh / 2, gz), Color3.fromRGB(170, 172, 176), Enum.Material.Concrete)
	PartKit.Box(model, "GarageStripe", Vector3.new(gw + 0.6, 2, gd + 0.6), CFrame.new(gx, floorY + gh - 2, gz), navy, SMOOTH, DECOR)
	for k = -1, 1 do
		local dx = gx + k * 19
		PartKit.Box(model, "RollerDoor", Vector3.new(15, 13, 0.4), CFrame.new(dx, floorY + 6.5, gz + gd / 2 + 0.2), Color3.fromRGB(205, 208, 212), Enum.Material.CorrodedMetal, DECOR)
		PartKit.Box(model, "DoorHead", Vector3.new(16, 1, 1), CFrame.new(dx, floorY + 13.5, gz + gd / 2 + 0.5), Color3.fromRGB(60, 64, 70), Enum.Material.Metal, DECOR)
		PartKit.Box(model, "BayNumber", Vector3.new(3, 3, 0.2), CFrame.new(dx, floorY + 16, gz + gd / 2 + 0.3), Color3.fromRGB(240, 200, 40), SMOOTH, DECOR)
	end
	-- impound yard: chain-link on posts round the north-east corner, impounded bikes inside
	local yx0, yx1 = gx + gw / 2 + 8, x1 - 6
	local yz0, yz1 = z0 + 6, z0 + 90
	local function fence(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local cf = CFrame.lookAt(mid, b)
		PartKit.Box(model, "Fence", Vector3.new(0.2, 10, len), cf * CFrame.new(0, 5, 0), Color3.fromRGB(150, 156, 160), Enum.Material.DiamondPlate, { Transparency = 0.45 })
		PartKit.Box(model, "FenceRail", Vector3.new(0.4, 0.4, len), cf * CFrame.new(0, 10, 0), steel, Enum.Material.Metal, DECOR)
		for t = 0, math.floor(len / 10) do
			PartKit.Post(model, "FencePost", 0.5, 10.5, a + (b - a).Unit * math.min(t * 10, len), steel, Enum.Material.Metal, DECOR)
		end
	end
	if yx1 - yx0 > 20 then
		fence(Vector3.new(yx0, floorY, yz0), Vector3.new(yx0, floorY, yz1))
		fence(Vector3.new(yx0, floorY, yz1), Vector3.new(yx1 - 16, floorY, yz1))
		fence(Vector3.new(yx1, floorY, yz1), Vector3.new(yx1, floorY, yz0))
		fence(Vector3.new(yx1, floorY, yz0), Vector3.new(yx0, floorY, yz0))
		local yardSign = PartKit.Box(model, "YardSign", Vector3.new(12, 3, 0.3), CFrame.new((yx0 + yx1) / 2 - 8, floorY + 6, yz1 + 0.4), WHITE, SMOOTH, DECOR)
		PartKit.Sign(yardSign, Enum.NormalId.Back, "IMPOUND - NO ENTRY", Color3.fromRGB(180, 20, 20), nil, Enum.Font.GothamBlack, 20)
		for k, id in { "trail_t", "hornet_6", "flit_s" } do
			local spec = Bikes.Get(id)
			if spec then
				local impounded = BikeModel.Build(spec, nil, { Static = true })
				PartKit.Scale(impounded, 1 / Config.WORLD_SCALE)
				PartKit.PlaceStatic(impounded, CFrame.new(yx0 + 10, floorY, yz0 + 14 + (k - 1) * 14) * CFrame.Angles(0, math.rad(90), math.rad(-8)))
				impounded.Name = "Impounded_" .. id
				impounded.Parent = model
			end
		end
	end

	-- Car park: marked bays, cruisers, a barrier at the gate, the gatehouse, a flag
	for i = 0, 4 do
		local car = CarModel.Build("Police", { Static = true })
		PartKit.Scale(car, 1 / Config.WORLD_SCALE) -- cars are built at the city's scale; the city is scaled later
		PartKit.PlaceStatic(car, CFrame.new(x0 + 30 + i * 26, floorY, z1 - 40) * CFrame.Angles(0, math.pi, 0))
		car.Parent = model
		PartKit.Box(model, "Bay", Vector3.new(0.4, 0.05, 24), CFrame.new(x0 + 17 + i * 26, floorY + 0.03, z1 - 40), WHITE, SMOOTH, DECOR)
	end
	PartKit.Box(model, "Bay", Vector3.new(0.4, 0.05, 24), CFrame.new(x0 + 17 + 5 * 26, floorY + 0.03, z1 - 40), WHITE, SMOOTH, DECOR)
	local bayText = PartKit.Box(model, "BayText", Vector3.new(24, 0.05, 4), CFrame.new(x0 + 82, floorY + 0.03, z1 - 24), Color3.fromRGB(86, 88, 92), Enum.Material.Asphalt, DECOR)
	PartKit.Sign(bayText, Enum.NormalId.Top, "POLICE ONLY", WHITE, nil, Enum.Font.GothamBlack, 10)
	local gate = Vector3.new(x1 - 30, floorY, z1 - 8)
	PartKit.Box(model, "Gatehouse", Vector3.new(10, 10, 8), CFrame.new(gate + Vector3.new(-12, 5, -4)), stone, CONCRETE)
	PartKit.Box(model, "Window", Vector3.new(10.2, 4, 5), CFrame.new(gate + Vector3.new(-12, 6, -4)), Color3.fromRGB(60, 80, 100), GLASS, DECOR)
	PartKit.Box(model, "GatehouseRoof", Vector3.new(12, 0.8, 10), CFrame.new(gate + Vector3.new(-12, 10.4, -4)), navy, SMOOTH, DECOR)
	PartKit.Box(model, "BarrierPost", Vector3.new(1.4, 4, 1.4), CFrame.new(gate + Vector3.new(-6, 2, 0)), Color3.fromRGB(240, 200, 40), SMOOTH, DECOR)
	local arm = PartKit.Box(model, "BarrierArm", Vector3.new(22, 0.6, 0.6), CFrame.new(gate + Vector3.new(5, 3.6, 0)) * CFrame.Angles(0, 0, math.rad(70)), WHITE, SMOOTH, DECOR)
	local _ = arm
	PartKit.Post(model, "FlagPole", 0.6, 40, Vector3.new(ex + 40, floorY, front + 22), Color3.fromRGB(220, 220, 225), Enum.Material.Metal, NO_COLLIDE)
	PartKit.Box(model, "Flag", Vector3.new(0.2, 7, 11), CFrame.new(ex + 40, floorY + 35.5, front + 27.6), navy, Enum.Material.Fabric, DECOR)
	-- a strip of lawn with trees and a low wall along the street
	PartKit.Box(model, "Lawn", Vector3.new(bw - 50, 0.2, 10), CFrame.new(bx - 20, floorY + 0.1, front + 34), Color3.fromRGB(80, 140, 70), Enum.Material.Grass, DECOR)
	for i = 0, 3 do
		Props.Tree(model, Vector3.new(bx - 60 + i * 26, floorY, front + 34), rng, 0.8)
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
	PartKit.Scale(statue, 1 / (Config.WORLD_SCALE * BIKE)) -- a life-size bike next to the city (scaled later)
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
	-- the back board sits under the lip, not past it: a board standing beyond the lip caught the
	-- front tyre's ground ray as it rolled off, and the nose dipped and jumped back at every takeoff
	local backTop = height - 1.0
	local backCenter = base + dir * (length - 0.6) + Vector3.new(0, backTop / 2, 0)
	PartKit.Box(model, "Back", Vector3.new(width, backTop, 0.6), CFrame.lookAt(backCenter, backCenter + dir), Color3.fromRGB(140, 104, 66), Enum.Material.Wood)
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
-- Loop Park (the jump park's second block): two loop-the-loops, a halfpipe, a fun box and a
-- kicker into a foam landing mat
--------------------------------------------------------------------------------
local RAMP_WOOD = Color3.fromRGB(176, 136, 90)
local STEEL = Color3.fromRGB(70, 74, 80)

-- A loop-the-loop: the riding surface is the inside of a circle of radius `r` standing on
-- `entry` (on the ground, LookVector along the loop), shifted `shift` studs sideways over the turn.
-- The plate at the bottom ("LoopEntry") is what the bike's physics looks for.
local function loopTheLoop(parent: Instance, entry: CFrame, r: number, shift: number, width: number, color: Color3)
	local model = PartKit.Model(parent, "Loop")
	local up, fwd, right = entry.UpVector, entry.LookVector, entry.RightVector
	local t = 0.8
	local center = entry.Position + up * r
	local n = 44
	for i = 0, n - 1 do
		local theta = (i + 0.5) / n * math.pi * 2
		local radial = -up * math.cos(theta) + fwd * math.sin(theta)
		local tangent = fwd * math.cos(theta) + up * math.sin(theta)
		local p = center + radial * (r + t / 2) + right * (shift * theta / (math.pi * 2))
		local seg = PartKit.Box(model, "Track", Vector3.new(width, t, 2 * math.pi * (r + t) / n * 1.12), CFrame.lookAt(p, p + tangent, -radial), color, Enum.Material.SmoothPlastic)
		seg.CanQuery = false -- the physics rides the loop as a path; keep it out of ground rays
		seg:SetAttribute("Surface", "Ramp")
		-- side rails
		for _, side in { -0.5, 0.5 } do
			local rail = PartKit.Box(model, "Rail", Vector3.new(0.5, 1.6, 2 * math.pi * (r + t) / n * 1.12), CFrame.lookAt(p + right * (side * width) - radial * 0.4, p + right * (side * width) - radial * 0.4 + tangent, -radial), STEEL, Enum.Material.Metal, NO_COLLIDE)
			rail.CanQuery = false
		end
	end
	-- support towers on both sides of the loop
	for _, side in { -1, 1 } do
		local base = center + right * (shift / 2 + side * (width / 2 + shift / 2 + 3)) - up * r
		PartKit.Post(model, "Support", 2, r * 1.6, base, STEEL, Enum.Material.Metal, NO_COLLIDE)
		PartKit.Box(model, "SupportArm", Vector3.new(math.abs(shift) + width + 8, 1.2, 1.2), CFrame.new(center + right * (shift / 2) + up * (r * 0.55)), STEEL, Enum.Material.Metal, NO_COLLIDE)
	end
	local plate = PartKit.Box(model, "LoopEntry", Vector3.new(width, 0.4, 12), entry * CFrame.new(0, -0.2, -2), Color3.fromRGB(255, 200, 40), Enum.Material.DiamondPlate)
	plate:SetAttribute("LoopRadius", r)
	plate:SetAttribute("LoopShift", shift)
	plate:SetAttribute("Surface", "Ramp")
	-- arrows painted on the run-in
	for k = 1, 3 do
		Detail.Arrow(model, entry.Position + fwd * (-6 - k * 8) + Vector3.new(0, 0.05, 0), fwd, 0, Color3.fromRGB(255, 255, 255))
	end
	return model
end

-- A quarter pipe: a curved transition of radius `r` up to `angle` degrees, rising along `dir`
local function quarterPipe(parent: Instance, base: Vector3, dir: Vector3, r: number, angle: number, width: number)
	local model = PartKit.Model(parent, "QuarterPipe")
	local up = Vector3.yAxis
	local right = dir:Cross(up).Unit
	local center = base + up * r
	local steps = 10
	local t = 0.8
	local topAlpha = math.rad(angle)
	for i = 0, steps - 1 do
		local a = (i + 0.5) / steps * topAlpha
		local radial = -up * math.cos(a) + dir * math.sin(a)
		local tangent = dir * math.cos(a) + up * math.sin(a)
		local p = center + radial * (r + t / 2)
		local seg = PartKit.Box(model, "Transition", Vector3.new(width, t, r * topAlpha / steps * 1.15), CFrame.lookAt(p, p + tangent, -radial), RAMP_WOOD, Enum.Material.WoodPlanks)
		seg:SetAttribute("Surface", "Ramp")
	end
	local lipH = r * (1 - math.cos(topAlpha))
	local lipRun = r * math.sin(topAlpha)
	-- coping, deck and the solid back
	-- the coping is part of the ride (you go up past it and come back down), never a wall
	PartKit.Cylinder(model, "Coping", 0.9, width, CFrame.new(base + dir * lipRun + up * lipH) * CFrame.fromMatrix(Vector3.zero, right, up, -dir), Color3.fromRGB(200, 200, 205), Enum.Material.Metal):SetAttribute("Surface", "Ramp")
	local deck = base + dir * (lipRun + 6) + up * (lipH - 0.3)
	PartKit.Box(model, "Deck", Vector3.new(width, 0.6, 12), CFrame.lookAt(deck, deck + dir), RAMP_WOOD, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	-- the solid body under the deck, behind the lip (the curve stays open in front)
	local back = base + dir * (lipRun + 6) + up * (lipH / 2 - 0.3)
	PartKit.Box(model, "Back", Vector3.new(width, lipH - 0.6, 12), CFrame.lookAt(back, back + dir), Color3.fromRGB(140, 104, 66), Enum.Material.Wood, { Query = false })
	-- framing under the curve
	for k = 1, 3 do
		local a = topAlpha * k / 4
		local px = r * math.sin(a)
		local h = r * (1 - math.cos(a))
		for _, side in { -0.5, 0.5 } do
			local post = base + dir * px + right * (side * (width - 1))
			PartKit.Box(model, "Frame", Vector3.new(0.8, h, 0.8), CFrame.new(post + up * (h / 2)), Color3.fromRGB(120, 88, 56), Enum.Material.Wood, NO_COLLIDE)
		end
	end
	return model
end

function Landmarks.LoopPark(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "LoopPark")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local gy = Y + 0.3
	local pad = PartKit.Box(model, "Concrete", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(176, 176, 172), Enum.Material.Concrete)
	pad:SetAttribute("Surface", "Ramp")
	local north = Vector3.new(0, 0, -1)

	-- Big loop (west lane) and small loop (next lane), long run-ins from the south
	local bigEntry = CFrame.lookAt(Vector3.new(x0 + 24, gy, z1 - 150), Vector3.new(x0 + 24, gy, z1 - 151))
	loopTheLoop(model, bigEntry, 24, 22, 16, Color3.fromRGB(255, 122, 24))
	local smallEntry = CFrame.lookAt(Vector3.new(x0 + 84, gy, z1 - 120), Vector3.new(x0 + 84, gy, z1 - 121))
	loopTheLoop(model, smallEntry, 14, 18, 14, Color3.fromRGB(40, 150, 255))
	local loopSigns: { { X: number, Text: string } } = { { X = x0 + 24, Text = "BIG LOOP" }, { X = x0 + 84, Text = "LOOP" } }
	for _, spec in loopSigns do
		local sign = PartKit.Box(model, "LoopSign", Vector3.new(18, 4, 0.6), CFrame.new(spec.X, gy + 6, z1 - 12), Color3.fromRGB(26, 28, 34), SMOOTH, NO_COLLIDE)
		PartKit.Sign(sign, Enum.NormalId.Back, spec.Text, Color3.fromRGB(255, 200, 40), nil, Enum.Font.FredokaOne, 10)
		PartKit.Post(model, "SignPost", 0.6, 4, Vector3.new(spec.X, gy, z1 - 12), STEEL, Enum.Material.Metal, NO_COLLIDE)
	end

	-- Halfpipe in the middle: two quarters facing each other across a flat bottom (along X)
	local hpZ = cz - 20
	local hpX = cx + 30
	quarterPipe(model, Vector3.new(hpX - 18, gy, hpZ), Vector3.new(-1, 0, 0), 16, 72, 40)
	quarterPipe(model, Vector3.new(hpX + 18, gy, hpZ), Vector3.new(1, 0, 0), 16, 72, 40)

	-- Fun box near the south: ramps up both ends and a flat top
	local fb = Vector3.new(cx + 30, gy, z1 - 50)
	local fbH, fbLen = 5, 14
	PartKit.Ramp(model, "FunUp", fb + Vector3.new(0, 0, fbLen + 10), fb + Vector3.new(0, fbH, 10), 24, RAMP_WOOD, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	PartKit.Box(model, "FunTop", Vector3.new(24, fbH, 20), CFrame.new(fb + Vector3.new(0, fbH / 2, 0)), RAMP_WOOD, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	PartKit.Ramp(model, "FunDown", fb - Vector3.new(0, 0, fbLen + 10), fb + Vector3.new(0, fbH, -10), 24, RAMP_WOOD, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	PartKit.Box(model, "FunRail", Vector3.new(0.8, 0.8, 20), CFrame.new(fb + Vector3.new(9, fbH + 2.2, 0)), Color3.fromRGB(220, 60, 60), Enum.Material.Metal, NO_COLLIDE)

	-- Foam mat (east lane): a big kicker launches you onto a soft landing mat
	local fx = x1 - 40
	local kickStart = Vector3.new(fx, gy, z1 - 30)
	Landmarks.Kicker(model, kickStart, north, 9, 15, 18)
	local matCenter = Vector3.new(fx, gy, z1 - 120)
	local mat = PartKit.Box(model, "FoamMat", Vector3.new(54, 1, 70), CFrame.new(matCenter + Vector3.new(0, 0.5, 0)), Color3.fromRGB(70, 140, 230), Enum.Material.Fabric)
	mat:SetAttribute("Surface", "Foam")
	local foamColors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 230, 120), Color3.fromRGB(230, 130, 255) }
	for _ = 1, 70 do
		local p = matCenter + Vector3.new(rng:NextNumber(-25, 25), 1.6, rng:NextNumber(-33, 33))
		local cube = PartKit.Box(model, "FoamCube", Vector3.new(2.2, 2.2, 2.2), CFrame.new(p) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1)), foamColors[rng:NextInteger(1, #foamColors)], Enum.Material.Fabric, { Collide = false, Query = false, Touch = false, Shadow = false })
		local _ = cube
	end
	local foamSign = PartKit.Box(model, "FoamSign", Vector3.new(20, 4, 0.6), CFrame.new(fx, gy + 6, z1 - 10), Color3.fromRGB(26, 28, 34), SMOOTH, NO_COLLIDE)
	PartKit.Sign(foamSign, Enum.NormalId.Back, "FOAM PIT", Color3.fromRGB(90, 200, 255), nil, Enum.Font.FredokaOne, 10)

	-- floodlights at the corners
	for _, corner in { Vector3.new(x0 + 6, gy, z0 + 6), Vector3.new(x1 - 6, gy, z0 + 6), Vector3.new(x0 + 6, gy, z1 - 6), Vector3.new(x1 - 6, gy, z1 - 6) } do
		PartKit.Post(model, "FloodPole", 1.4, 40, corner, STEEL, Enum.Material.Metal)
		PartKit.Box(model, "Flood", Vector3.new(6, 3, 2), CFrame.lookAt(corner + Vector3.new(0, 41, 0), Vector3.new(cx, gy, cz)), Color3.fromRGB(255, 250, 230), Enum.Material.Neon, NO_COLLIDE)
	end
	return model
end

--------------------------------------------------------------------------------
-- Bayfront Park: lawns and palm groves on the bay, a bandshell over a stage, a fountain, a grassy
-- mound to ride over
--------------------------------------------------------------------------------
function Landmarks.BayPark(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "BayfrontPark")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local lawn = PartKit.Box(model, "Lawn", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Props.Palette.Lawn, Enum.Material.Grass)
	lawn:SetAttribute("Surface", "Grass")
	local py = Y + 0.3
	local paving = Color3.fromRGB(222, 208, 186)
	for _, size in { Vector3.new(14, 0.2, z1 - z0), Vector3.new(x1 - x0, 0.2, 14) } do
		local path = PartKit.Box(model, "Path", size, CFrame.new(cx, py + 0.1, cz), paving, Enum.Material.Pavement)
		path:SetAttribute("Surface", "Sidewalk")
	end
	-- the fountain at the crossing
	PartKit.Post(model, "FountainRim", 54, 1.8, Vector3.new(cx, py, cz), Color3.fromRGB(236, 232, 224), Enum.Material.Marble)
	local water = PartKit.Post(model, "Water", 50, 1.85, Vector3.new(cx, py, cz), Color3.fromRGB(60, 170, 210), SMOOTH)
	water.Transparency = 0.25
	water.Reflectance = 0.3
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		PartKit.Ball(model, "Jet", 3, Vector3.new(cx + math.cos(a) * 14, py + 6, cz + math.sin(a) * 14), Color3.fromRGB(210, 236, 255), GLASS, DECOR).Transparency = 0.5
	end
	PartKit.Post(model, "Spout", 2, 14, Vector3.new(cx, py, cz), Color3.fromRGB(236, 232, 224), Enum.Material.Marble)
	PartKit.Ball(model, "Spray", 8, Vector3.new(cx, py + 15, cz), Color3.fromRGB(210, 236, 255), GLASS, DECOR).Transparency = 0.5

	-- the bandshell in the north-east quarter, its stage facing the lawn to the south-west
	local sx, sz = cx + (x1 - x0) / 4, cz - (z1 - z0) / 4
	local toward = Vector3.new(-1, 0, 1).Unit
	local stage = CFrame.lookAt(Vector3.new(sx, py, sz), Vector3.new(sx, py, sz) + toward)
	PartKit.Box(model, "Stage", Vector3.new(56, 4, 30), stage * CFrame.new(0, 2, 0), Color3.fromRGB(230, 226, 218), CONCRETE)
	PartKit.Box(model, "StageFloor", Vector3.new(54, 0.2, 28), stage * CFrame.new(0, 4.1, 0), Color3.fromRGB(110, 80, 56), Enum.Material.WoodPlanks, DECOR)
	-- the shell: arched ribs of slabs leaning in over the back of the stage
	for k = 0, 6 do
		local a = math.rad(-75 + k * 25)
		local base = stage * CFrame.new(math.sin(a) * 26, 4, 12 + (1 - math.cos(a)) * -6)
		local top = base * CFrame.new(0, 26, -10)
		PartKit.Slab(model, "Shell", base.Position, top.Position, 9, 1.2, Color3.fromRGB(248, 248, 244), SMOOTH)
	end
	PartKit.Box(model, "ShellCrown", Vector3.new(50, 2, 14), stage * CFrame.new(0, 31, 3) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(248, 248, 244), SMOOTH, NO_COLLIDE)
	for _, x in { -22, 22 } do
		PartKit.Box(model, "Speaker", Vector3.new(5, 12, 5), stage * CFrame.new(x, 10, -12), Color3.fromRGB(26, 26, 30), SMOOTH)
	end
	-- a grassy mound in the south-west quarter (rideable both ways)
	local hx, hz = cx - (x1 - x0) / 4, cz + (z1 - z0) / 4
	local hill = PartKit.Box(model, "HillTop", Vector3.new(34, 7, 34), CFrame.new(hx, py + 3.5, hz), Props.Palette.Lawn, Enum.Material.Grass)
	hill:SetAttribute("Surface", "Grass")
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local edge = Vector3.new(hx, py + 7, hz) + d * 17
		local foot = edge + d * 30 - Vector3.new(0, 7, 0)
		local slope = PartKit.Ramp(model, "HillSide", foot, edge, 34, Props.Palette.Lawn, Enum.Material.Grass)
		slope:SetAttribute("Surface", "Grass")
	end
	-- palm groves, benches and lamps
	for _ = 1, 44 do
		local x = rng:NextNumber(x0 + 8, x1 - 8)
		local z = rng:NextNumber(z0 + 8, z1 - 8)
		local onPath = math.abs(x - cx) < 14 or math.abs(z - cz) < 14
		local nearFountain = (Vector3.new(x, 0, z) - Vector3.new(cx, 0, cz)).Magnitude < 44
		local nearStage = (Vector3.new(x, 0, z) - Vector3.new(sx, 0, sz)).Magnitude < 52
		local onHill = math.abs(x - hx) < 52 and math.abs(z - hz) < 52
		if not (onPath or nearFountain or nearStage or onHill) then
			Props.Palm(model, Vector3.new(x, py, z), rng)
		end
	end
	for i = -3, 3 do
		if i ~= 0 then
			Props.Bench(model, CFrame.new(cx + 12, py, cz + i * 38) * CFrame.Angles(0, math.rad(90), 0))
			Props.Lamp(model, Vector3.new(cx - 10, py, cz + i * 38 + 10))
			Props.Lamp(model, Vector3.new(cx + i * 38 + 10, py, cz - 10))
		end
	end
	local sign = PartKit.Box(model, "ParkSign", Vector3.new(30, 6, 1.2), CFrame.new(cx, py + 3, z1 - 6), Color3.fromRGB(30, 110, 90), SMOOTH)
	PartKit.Sign(sign, Enum.NormalId.Back, "BAYFRONT PARK", Color3.fromRGB(250, 250, 245), nil, Enum.Font.GothamBold, 10)
	return model
end

--------------------------------------------------------------------------------
-- The marina's shore block: a yacht club on the bay, a dry-stack boat barn, parking
-- (its docks are the Shore's, off the baywalk)
--------------------------------------------------------------------------------
function Landmarks.Marina(parent: Instance, block: LayoutModule.Block, rng: Random)
	local model = PartKit.Model(parent, "Marina")
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	PartKit.Box(model, "Paving", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(226, 220, 206), Enum.Material.Pavement):SetAttribute("Surface", "Sidewalk")
	local fy = Y + 0.3
	-- the yacht club: two white storeys, glass all round, a roof terrace with sails over it
	local club = Vector3.new(x1 - 60, fy, cz - 50)
	local white = Color3.fromRGB(248, 248, 244)
	PartKit.Box(model, "Club", Vector3.new(90, 13, 60), CFrame.new(club + Vector3.new(0, 6.5, 0)), white, SMOOTH)
	local glass = PartKit.Box(model, "ShopGlass", Vector3.new(90.4, 8, 60.4), CFrame.new(club + Vector3.new(0, 5, 0)), Color3.fromRGB(80, 120, 140), GLASS, DECOR)
	glass.Reflectance = 0.3
	PartKit.Box(model, "UpperFloor", Vector3.new(70, 11, 46), CFrame.new(club + Vector3.new(-6, 18.5, 0)), white, SMOOTH)
	local upper = PartKit.Box(model, "Window", Vector3.new(70.4, 6, 46.4), CFrame.new(club + Vector3.new(-6, 18.5, 0)), Color3.fromRGB(80, 120, 140), GLASS, DECOR)
	upper.Reflectance = 0.3
	PartKit.Box(model, "Terrace", Vector3.new(96, 1, 66), CFrame.new(club + Vector3.new(0, 13.5, 0)), Color3.fromRGB(150, 116, 80), Enum.Material.WoodPlanks)
	for k = 0, 2 do
		local p = club + Vector3.new(14 + k * 8, 30, -18 + k * 18)
		PartKit.Slab(model, "Sail", p, p + Vector3.new(20, -6, 10), 16, 0.3, white, Enum.Material.Fabric, NO_COLLIDE)
	end
	local name = PartKit.Box(model, "ClubName", Vector3.new(40, 4, 0.3), CFrame.new(club + Vector3.new(0, 26, 23.2)), white, SMOOTH, DECOR)
	name.Transparency = 1
	PartKit.Sign(name, Enum.NormalId.Back, "BISCAYNE YACHT CLUB", Color3.fromRGB(20, 50, 100), nil, Enum.Font.GothamBold, 10)
	-- the dry-stack barn: steel racks with boats on three tiers
	local barn = Vector3.new(x0 + 60, fy, cz)
	local steel = Color3.fromRGB(170, 176, 182)
	PartKit.Box(model, "BarnRoof", Vector3.new(90, 2, 200), CFrame.new(barn + Vector3.new(0, 46, 0)), Color3.fromRGB(230, 230, 226), Enum.Material.CorrodedMetal)
	for _, sx in { -1, 1 } do
		for z = -95, 95, 38 do
			PartKit.Box(model, "RackPost", Vector3.new(2, 45, 2), CFrame.new(barn + Vector3.new(sx * 43, 22.5, z)), steel, Enum.Material.Metal)
		end
	end
	for tier = 0, 2 do
		local y = 4 + tier * 14
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "RackArm", Vector3.new(30, 1, 200), CFrame.new(barn + Vector3.new(sx * 26, y, 0)), steel, Enum.Material.Metal, NO_COLLIDE)
			for z = -80, 80, 32 do
				if rng:NextNumber() < 0.75 then
					Shore.Boat(model, CFrame.lookAt(barn + Vector3.new(sx * 26, y + 1.5, z), barn + Vector3.new(sx * 60, y + 1.5, z)), rng)
				end
			end
		end
	end
	-- a forklift, the parking between, palms
	PartKit.Box(model, "Forklift", Vector3.new(8, 8, 12), CFrame.new(barn + Vector3.new(0, 4, -110)), Color3.fromRGB(240, 190, 30), SMOOTH)
	for _ = 1, 10 do
		Props.Palm(model, Vector3.new(rng:NextNumber(x0 + 120, x1 - 10), fy, rng:NextNumber(cz + 20, z1 - 10)), rng)
	end
	return model
end

return Landmarks
