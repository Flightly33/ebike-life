--[[
	Everglades: the wetlands west of Little Havana, crossed by the Tamiami Trail (Calle Ocho's
	continuation) with its canal. An airboat tour stop on the canal (dock, airboats, gift shop, a
	gator pen), a raised wooden boardwalk loop out over the marsh to an observation tower (ridable),
	dirt trails, hardwood hammocks and cypress domes, sawgrass, alligators sunning on the banks and
	egrets. The marsh ground itself is Terrain at runtime (Layout.OpenGround "Marsh").
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder scales the finished city by WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local PartKit = require(script.Parent.Parent.PartKit)

local Everglades = {}

local S = Layout.SPREAD -- plan positions are spread (City/Layout)

local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }
local DECK = Color3.fromRGB(150, 118, 84)

-- An alligator lying at `cf` (on the ground, snout along -Z)
function Everglades.Gator(parent: Instance, cf: CFrame, rng: Random)
	local model = PartKit.Model(parent, "Alligator")
	local skin = Color3.fromRGB(58, 66, 46):Lerp(Color3.fromRGB(40, 44, 36), rng:NextNumber(0, 1))
	local s = rng:NextNumber(0.8, 1.2)
	PartKit.Ellipsoid(model, "Body", Vector3.new(4.4, 2, 10) * s, cf * CFrame.new(0, 1 * s, 0), skin, Enum.Material.Slate, NO_COLLIDE)
	PartKit.Ellipsoid(model, "Head", Vector3.new(2.6, 1.4, 4.4) * s, cf * CFrame.new(0, 0.9 * s, -6.4 * s), skin, Enum.Material.Slate, DECOR)
	PartKit.Ellipsoid(model, "Snout", Vector3.new(1.6, 0.8, 3.4) * s, cf * CFrame.new(0, 0.7 * s, -9.4 * s), skin, Enum.Material.Slate, DECOR)
	local bend = rng:NextNumber(-0.5, 0.5)
	PartKit.Ellipsoid(model, "Tail", Vector3.new(2.4, 1.2, 9) * s, cf * CFrame.new(0, 0.7 * s, 8.5 * s) * CFrame.Angles(0, bend, 0), skin, Enum.Material.Slate, DECOR)
	PartKit.Ellipsoid(model, "TailTip", Vector3.new(1.2, 0.8, 6) * s, cf * CFrame.new(bend * 4 * s, 0.5 * s, 14 * s) * CFrame.Angles(0, bend * 2, 0), skin, Enum.Material.Slate, DECOR)
	for _, sx in { -1, 1 } do
		for _, sz in { -2.6, 2.4 } do
			PartKit.Ellipsoid(model, "Leg", Vector3.new(2.2, 0.8, 1.2) * s, cf * CFrame.new(sx * 2.4 * s, 0.4 * s, sz * s), skin, Enum.Material.Slate, DECOR)
		end
		PartKit.Ball(model, "Eye", 0.5 * s, (cf * CFrame.new(sx * 0.7 * s, 1.6 * s, -6.8 * s)).Position, Color3.fromRGB(200, 170, 40), SMOOTH, DECOR)
	end
	return model
end

-- An airboat moored at `cf` (the waterline, bow along -Z): a flat hull, raised seats, the big
-- fan in its cage at the back
function Everglades.Airboat(parent: Instance, cf: CFrame, color: Color3)
	local model = PartKit.Model(parent, "Airboat")
	PartKit.Box(model, "Hull", Vector3.new(8, 1.4, 18), cf * CFrame.new(0, 0.4, 0), Color3.fromRGB(196, 200, 204), METAL)
	PartKit.Wedge(model, "Bow", Vector3.new(8, 1.4, 4), cf * CFrame.new(0, 0.4, -11) * CFrame.Angles(0, 0, math.pi), Color3.fromRGB(196, 200, 204), METAL)
	for k = 0, 2 do
		PartKit.Box(model, "Bench", Vector3.new(7, 1, 2), cf * CFrame.new(0, 1.8 + k * 0.6, -5 + k * 3), color, SMOOTH, DECOR)
	end
	PartKit.Box(model, "PilotSeat", Vector3.new(2.4, 1, 2.4), cf * CFrame.new(0, 5, 4), color, SMOOTH, DECOR)
	PartKit.Box(model, "SeatPost", Vector3.new(0.4, 4, 0.4), cf * CFrame.new(0, 3, 4), Color3.fromRGB(160, 164, 168), METAL, DECOR)
	PartKit.Cylinder(model, "FanCage", 9, 1.6, cf * CFrame.new(0, 5.5, 8) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(60, 60, 64), METAL, DECOR).Transparency = 0.5
	PartKit.Box(model, "Engine", Vector3.new(3, 3, 3.4), cf * CFrame.new(0, 3, 6.6), Color3.fromRGB(40, 40, 44), METAL, DECOR)
	PartKit.Box(model, "Rudder", Vector3.new(0.3, 6, 2), cf * CFrame.new(0, 5.5, 9.8), color, SMOOTH, DECOR)
	return model
end

-- A clump of sawgrass: three tall thin blades
local function sawgrass(parent: Instance, base: Vector3, rng: Random)
	local tone = Color3.fromRGB(150, 140, 80):Lerp(Color3.fromRGB(110, 120, 60), rng:NextNumber(0, 1))
	for k = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local h = rng:NextNumber(4, 7)
		PartKit.Wedge(parent, "Sawgrass", Vector3.new(0.2, h, 2), CFrame.new(base + Vector3.new(math.cos(a) * 0.8, h / 2, math.sin(a) * 0.8)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), a + k, 0), tone, Enum.Material.Grass, DECOR)
	end
end

-- A cypress: a tall straight trunk with a buttressed base and a flat, feathery crown
local function cypress(parent: Instance, base: Vector3, rng: Random)
	local model = PartKit.Model(parent, "Cypress")
	local h = rng:NextNumber(26, 40)
	PartKit.Post(model, "Trunk", 1.6, h, base, Color3.fromRGB(110, 96, 80), Enum.Material.Wood)
	PartKit.Post(model, "Roots", 4, 2, base, Color3.fromRGB(110, 96, 80), Enum.Material.Wood, NO_COLLIDE)
	local leaves = Color3.fromRGB(96, 120, 70)
	PartKit.Ellipsoid(model, "Leaves", Vector3.new(14, 5, 14), CFrame.new(base + Vector3.new(0, h, 0)), leaves, Enum.Material.Grass, NO_COLLIDE)
	PartKit.Ellipsoid(model, "Leaves", Vector3.new(9, 4, 9), CFrame.new(base + Vector3.new(rng:NextNumber(-2, 2), h - 5, rng:NextNumber(-2, 2))), leaves:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Grass, NO_COLLIDE)
	return model
end

-- An egret standing in the shallows
local function egret(parent: Instance, base: Vector3, rng: Random)
	local model = PartKit.Model(parent, "Egret")
	local yaw = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local cf = CFrame.new(base) * yaw
	PartKit.Ellipsoid(model, "Body", Vector3.new(1, 1.2, 2.2), cf * CFrame.new(0, 3.4, 0), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	PartKit.Bar(model, "Neck", (cf * CFrame.new(0, 3.8, -0.8)).Position, (cf * CFrame.new(0, 5.4, -1.2)).Position, 0.3, 0.3, Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	PartKit.Bar(model, "Beak", (cf * CFrame.new(0, 5.4, -1.2)).Position, (cf * CFrame.new(0, 5.3, -2.2)).Position, 0.15, 0.15, Color3.fromRGB(230, 190, 40), SMOOTH, DECOR)
	for _, x in { -0.25, 0.25 } do
		PartKit.Bar(model, "Leg", (cf * CFrame.new(x, 0, 0)).Position, (cf * CFrame.new(x, 3, 0)).Position, 0.12, 0.12, Color3.fromRGB(30, 30, 30), SMOOTH, DECOR)
	end
end

-- A raised wooden walk from `a` to `b` (both on the ground; the deck `h` up), with posts and rails
local function boardwalk(parent: Instance, a: Vector3, b: Vector3, h: number)
	local up = Vector3.new(0, h, 0)
	local deck = PartKit.Slab(parent, "Boardwalk", a + up, b + up, 10, 0.8, DECK, Enum.Material.WoodPlanks)
	deck:SetAttribute("Surface", "Sidewalk")
	local dir = (b - a).Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local length = (b - a).Magnitude
	for k = 0, math.floor(length / 16) do
		local p = a + dir * math.min(length, k * 16)
		for _, side in { -1, 1 } do
			local q = p + right * side * 4.5
			PartKit.Post(parent, "Post", 0.8, h + 3.4, q - Vector3.new(0, 2, 0), Color3.fromRGB(120, 92, 64), Enum.Material.Wood, NO_COLLIDE)
		end
	end
	for _, side in { -1, 1 } do
		local o = right * side * 4.5 + Vector3.new(0, h + 3.2, 0)
		PartKit.Bar(parent, "Rail", a + o, b + o, 0.4, 0.4, Color3.fromRGB(130, 100, 70), Enum.Material.Wood, DECOR)
	end
end

function Everglades.Build(city: Instance, rng: Random)
	local folder = PartKit.Folder(city, "Everglades")
	local trailZ = Layout.TAMIAMI_Z
	local edge = Layout.EVERGLADES_X
	local W = Layout.WORLD_HALF
	local roadHalf = Layout.RURAL_WIDTH / 2

	-- the airboat tour stop: gift shop south of the trail, a dock on the canal north of it
	local stop = PartKit.Folder(folder, "AirboatTours")
	local shopX = -3950 * S
	local shopZ = trailZ + roadHalf + 40
	local lot = PartKit.Box(stop, "Lot", Vector3.new(120, 0.3, 50), CFrame.new(shopX + 30, 0.15, shopZ - 6), Color3.fromRGB(176, 166, 140), Enum.Material.Ground)
	lot:SetAttribute("Surface", "Dirt")
	PartKit.Box(stop, "Shop", Vector3.new(50, 14, 30), CFrame.new(shopX - 20, 7.3, shopZ + 10), Color3.fromRGB(196, 160, 110), Enum.Material.WoodPlanks)
	PartKit.Slab(stop, "ShopRoof", Vector3.new(shopX - 20, 13, shopZ - 8), Vector3.new(shopX - 20, 19, shopZ + 10), 54, 0.6, Color3.fromRGB(150, 154, 158), Enum.Material.CorrodedMetal)
	PartKit.Slab(stop, "ShopRoof", Vector3.new(shopX - 20, 13, shopZ + 28), Vector3.new(shopX - 20, 19, shopZ + 10), 54, 0.6, Color3.fromRGB(150, 154, 158), Enum.Material.CorrodedMetal, NO_COLLIDE)
	local sign = PartKit.Box(stop, "Sign", Vector3.new(40, 8, 0.6), CFrame.new(shopX - 20, 24, shopZ - 6), Color3.fromRGB(40, 90, 50), SMOOTH, NO_COLLIDE)
	PartKit.Sign(sign, Enum.NormalId.Front, "🐊 GLADES AIRBOAT TOURS", Color3.fromRGB(250, 230, 120), nil, Enum.Font.FredokaOne, 8)
	PartKit.Post(stop, "SignPost", 0.8, 20, Vector3.new(shopX - 36, 0, shopZ - 6), Color3.fromRGB(110, 90, 60), Enum.Material.Wood)
	PartKit.Post(stop, "SignPost", 0.8, 20, Vector3.new(shopX - 4, 0, shopZ - 6), Color3.fromRGB(110, 90, 60), Enum.Material.Wood)
	-- the dock and the airboats on the canal
	local canal = Layout.Lakes[1]
	local dockZ = canal.MaxZ - 4
	local dock = PartKit.Box(stop, "Dock", Vector3.new(90, 0.8, 10), CFrame.new(shopX + 20, 0.6, dockZ), DECK, Enum.Material.WoodPlanks)
	dock:SetAttribute("Surface", "Sidewalk")
	for k = 0, 2 do
		Everglades.Airboat(stop, CFrame.lookAt(Vector3.new(shopX - 10 + k * 28, Layout.WATER_Y + 0.4, (canal.MinZ + canal.MaxZ) / 2 - 1), Vector3.new(shopX - 11 + k * 28, Layout.WATER_Y + 0.4, (canal.MinZ + canal.MaxZ) / 2 - 1)), ({ Color3.fromRGB(40, 110, 60), Color3.fromRGB(200, 60, 40), Color3.fromRGB(40, 80, 160) })[k + 1])
	end
	-- the gator pen
	local pen = Vector3.new(shopX + 70, 0, shopZ + 30)
	for k = 0, 11 do
		local a0, a1 = k / 12 * math.pi * 2, (k + 1) / 12 * math.pi * 2
		PartKit.Bar(stop, "PenFence", pen + Vector3.new(math.cos(a0) * 22, 2, math.sin(a0) * 22), pen + Vector3.new(math.cos(a1) * 22, 2, math.sin(a1) * 22), 0.4, 4, Color3.fromRGB(130, 100, 70), Enum.Material.WoodPlanks)
	end
	local pool = PartKit.Box(stop, "PenPool", Vector3.new(18, 0.4, 12), CFrame.new(pen + Vector3.new(0, 0.2, 4)), Color3.fromRGB(70, 100, 70), Enum.Material.Glass, DECOR)
	pool.Transparency = 0.2
	for k = 0, 3 do
		Everglades.Gator(stop, CFrame.new(pen + Vector3.new(-12 + k * 7, 0.1, -8 + (k % 2) * 4)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng)
	end

	-- the boardwalk loop: from the trail south over the marsh, west, back north; a tower at the far
	-- corner with a ramp up to its deck
	local walk = PartKit.Folder(folder, "Boardwalk")
	local bx0 = -3620 * S
	local bx1 = bx0 - 260
	local bz0, bz1 = trailZ + roadHalf + 30, trailZ + 560
	local h = 3
	PartKit.Ramp(walk, "BoardwalkRamp", Vector3.new(bx0, 0, bz0 - 24), Vector3.new(bx0, h, bz0), 10, DECK, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	boardwalk(walk, Vector3.new(bx0, 0, bz0), Vector3.new(bx0, 0, bz1), h)
	boardwalk(walk, Vector3.new(bx0 + 5, 0, bz1), Vector3.new(bx1 - 5, 0, bz1), h)
	boardwalk(walk, Vector3.new(bx1, 0, bz1), Vector3.new(bx1, 0, bz0 + 120), h)
	PartKit.Ramp(walk, "BoardwalkRamp", Vector3.new(bx1, 0, bz0 + 96), Vector3.new(bx1, h, bz0 + 120), 10, DECK, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	-- the observation tower: a square deck on legs, reached by a long ramp off the walk
	local tower = Vector3.new(bx1 - 60, 0, bz1)
	local th = 24
	PartKit.Box(walk, "TowerDeck", Vector3.new(30, 1, 30), CFrame.new(tower + Vector3.new(0, th, 0)), DECK, Enum.Material.WoodPlanks):SetAttribute("Surface", "Sidewalk")
	for _, o in { Vector3.new(-14, 0, -14), Vector3.new(14, 0, -14), Vector3.new(-14, 0, 14), Vector3.new(14, 0, 14) } do
		PartKit.Post(walk, "TowerLeg", 1.6, th, tower + o, Color3.fromRGB(120, 92, 64), Enum.Material.Wood)
	end
	PartKit.Slab(walk, "TowerRamp", Vector3.new(bx1 - 5, h, bz1), tower + Vector3.new(15, th, 0), 10, 0.8, DECK, Enum.Material.WoodPlanks):SetAttribute("Surface", "Ramp")
	PartKit.Box(walk, "TowerRoof", Vector3.new(32, 1, 32), CFrame.new(tower + Vector3.new(0, th + 12, 0)), Color3.fromRGB(110, 86, 60), Enum.Material.WoodPlanks, NO_COLLIDE)

	-- dirt trails through the marsh (ridable off-road)
	local trails = PartKit.Folder(folder, "Trails")
	local points = {
		Vector3.new(-3500 * S, 0, trailZ - roadHalf - 40),
		Vector3.new(-3500 * S, 0, -700 * S),
		Vector3.new(-3800 * S, 0, -1000 * S),
		Vector3.new(-4050 * S, 0, -700 * S),
		Vector3.new(-4050 * S, 0, -200 * S),
		Vector3.new(-3750 * S, 0, trailZ - roadHalf - 40),
	}
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local strip = PartKit.Slab(trails, "Trail", a + Vector3.new(0, 0.15, 0), b + Vector3.new(0, 0.15, 0), 9, 0.3, Color3.fromRGB(150, 128, 92), Enum.Material.Ground)
		strip:SetAttribute("Surface", "Dirt")
	end
	local south = { Vector3.new(-3450 * S, 0, trailZ + roadHalf + 40), Vector3.new(-3450 * S, 0, 1500 * S), Vector3.new(-3700 * S, 0, 2400 * S), Vector3.new(-4100 * S, 0, 2600 * S) }
	for k = 1, #south - 1 do
		local strip = PartKit.Slab(trails, "Trail", south[k] + Vector3.new(0, 0.15, 0), south[k + 1] + Vector3.new(0, 0.15, 0), 9, 0.3, Color3.fromRGB(150, 128, 92), Enum.Material.Ground)
		strip:SetAttribute("Surface", "Dirt")
	end

	-- hammocks (islands of hardwoods and palms), cypress domes, sawgrass, gators on the banks, egrets
	local life = PartKit.Folder(folder, "Wildlife")
	local function free(x: number, z: number, margin: number): boolean
		if not Layout.InMarsh(x, z) or math.abs(z - trailZ) < roadHalf + margin then
			return false
		end
		if math.abs(x - bx0) < margin + 8 and z > bz0 - 30 and z < bz1 + 10 then
			return false
		end
		if math.abs(z - bz1) < margin + 8 and x < bx0 + 10 and x > bx1 - 80 then
			return false
		end
		return true
	end
	local hammocks = 0
	for _ = 1, 80 do
		if hammocks >= 12 then
			break
		end
		local x, z = rng:NextNumber(-W + 60, edge - 40), rng:NextNumber(-2200 * S, W - 60)
		if free(x, z, 40) then
			hammocks += 1
			for _ = 1, rng:NextInteger(5, 9) do
				local p = Vector3.new(x + rng:NextNumber(-30, 30), 0, z + rng:NextNumber(-30, 30))
				local r = rng:NextNumber()
				if r < 0.4 then
					Props.Tree(life, p, rng, rng:NextNumber(1.1, 1.6))
				elseif r < 0.7 then
					Props.Palm(life, p, rng, rng:NextNumber(0.9, 1.2))
				else
					cypress(life, p, rng)
				end
			end
		end
	end
	local clumps = 0
	for _ = 1, 600 do
		if clumps >= 160 then
			break
		end
		local x, z = rng:NextNumber(-W + 20, edge - 10), rng:NextNumber(-2200 * S, W - 20)
		if free(x, z, 6) then
			clumps += 1
			sawgrass(life, Vector3.new(x, 0, z), rng)
		end
	end
	local gators = 0
	for _, lake in Layout.Lakes do
		if lake.MaxX < edge and gators < 14 then
			for _ = 1, 3 do
				local alongX = rng:NextNumber() < 0.5
				local x = if alongX then rng:NextNumber(lake.MinX + 10, lake.MaxX - 10) else (if rng:NextNumber() < 0.5 then lake.MinX - 8 else lake.MaxX + 8)
				local z = if alongX then (if rng:NextNumber() < 0.5 then lake.MinZ - 8 else lake.MaxZ + 8) else rng:NextNumber(lake.MinZ + 10, lake.MaxZ - 10)
				if free(x, z, 4) then
					Everglades.Gator(life, CFrame.new(x, 0.1, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng)
					gators += 1
				end
			end
			for _ = 1, 2 do
				egret(life, Vector3.new(rng:NextNumber(lake.MinX + 4, lake.MaxX - 4), Layout.WATER_Y + 0.6, rng:NextNumber(lake.MinZ + 2, lake.MaxZ - 2)), rng)
			end
		end
	end
	return folder
end

return Everglades
