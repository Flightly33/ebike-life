--[[
	Neighborhoods: the districts round downtown. Little Havana's Calle Ocho shops and Domino Park,
	Coral Gables' Mediterranean villas, banyans and grand hotel, Coconut Grove's bungalows under the
	tree canopy and its waterfront, North Beach's mansions, and Key Biscayne's homes, park and
	lighthouse. Everything sits on a block's lot at Layout.CURB_Y. Names are made up.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder shrinks the finished city to WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local Buildings = require(script.Parent.Buildings)
local PartKit = require(script.Parent.Parent.PartKit)

local Neighborhoods = {}

local C = Props.Palette
local Y = Layout.CURB_Y
local SMOOTH = Enum.Material.SmoothPlastic
local PLASTER = Enum.Material.Plaster
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local CONCRETE = Enum.Material.Concrete
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

-- (towers and other tall landmarks keep a low-detail stand-in beyond the streaming radius)
local function skylineModel(model: Model)
	pcall(function()
		(model :: any).LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	end)
end

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local HAVANA_SHOPS = {
	"La Ventanita", "Cafe El Sol", "Tabaqueria Habana", "Panaderia La Palma", "Farmacia del Pueblo",
	"Botanica", "Joyeria Oro", "Dulceria", "Fruteria Los Mangos", "Libreria", "Peluqueria",
	"Bodega Mi Tierra", "Guayaberas", "Cafeteria 8", "Sabor Latino", "Musica Cubana",
}
local MEDITERRANEAN = {
	Color3.fromRGB(244, 230, 204),
	Color3.fromRGB(240, 214, 182),
	Color3.fromRGB(236, 222, 196),
	Color3.fromRGB(246, 238, 220),
	Color3.fromRGB(232, 206, 178),
}
local TILE = Color3.fromRGB(176, 84, 52)

-- A broad shade tree for the Gables and the Grove: a banyan (aerial roots dropping from wide
-- limbs) or a live oak. Its own model ("Banyan"), so the city kit leaves it.
function Neighborhoods.Banyan(parent: Instance, base: Vector3, rng: Random, size: number?)
	local s = size or rng:NextNumber(0.9, 1.3)
	local model = PartKit.Model(parent, "Banyan")
	local bark = Color3.fromRGB(120, 108, 92)
	local h = 13 * s
	PartKit.Post(model, "Trunk", 3.4 * s, h, base, bark, Enum.Material.Wood)
	PartKit.Post(model, "Roots", 6 * s, 1.2 * s, base, bark, Enum.Material.Wood, NO_COLLIDE)
	local top = base + Vector3.new(0, h, 0)
	local leaves = Props.Leaves[rng:NextInteger(1, 5)]
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local tip = top + out * (12 * s) + Vector3.new(0, 3 * s, 0)
		PartKit.Tube(model, "Limb", top - Vector3.new(0, 2 * s, 0), tip, 1.4 * s, bark, Enum.Material.Wood, NO_COLLIDE)
		-- an aerial root dropping from the limb
		local drop = top + out * (8 * s)
		PartKit.Tube(model, "AerialRoot", drop, Vector3.new(drop.X, base.Y, drop.Z), 0.6 * s, bark:Lerp(Color3.new(1, 1, 1), 0.1), Enum.Material.Wood, DECOR)
		PartKit.Ellipsoid(model, "Leaves", Vector3.new(16, 8, 16) * s, CFrame.new(tip + Vector3.new(0, 2 * s, 0)), leaves:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.15)), Enum.Material.Grass, NO_COLLIDE)
	end
	PartKit.Ellipsoid(model, "Leaves", Vector3.new(26, 11, 26) * s, CFrame.new(top + Vector3.new(0, 6 * s, 0)), leaves, Enum.Material.Grass, NO_COLLIDE)
	PartKit.Ellipsoid(model, "Leaves", Vector3.new(14, 6, 14) * s, CFrame.new(top + Vector3.new(0, 10 * s, 0)), leaves:Lerp(Color3.fromRGB(255, 240, 170), 0.15), Enum.Material.Grass, NO_COLLIDE)
	return model
end

-- A back-yard pool with a deck and loungers (`cf` at the pool's centre on the ground)
local function pool(parent: Instance, cf: CFrame, w: number, d: number)
	PartKit.Box(parent, "PoolDeck", Vector3.new(w + 8, 0.35, d + 8), cf * CFrame.new(0, 0.18, 0), Color3.fromRGB(226, 216, 196), Enum.Material.Pavement, DECOR)
	local water = PartKit.Box(parent, "Pool", Vector3.new(w, 0.4, d), cf * CFrame.new(0, 0.22, 0), Color3.fromRGB(60, 190, 220), GLASS, DECOR)
	water.Transparency = 0.1
	water.Reflectance = 0.3
	for k = 0, 1 do
		PartKit.Box(parent, "Lounger", Vector3.new(2.2, 1, 6), cf * CFrame.new(-w / 2 + 3 + k * 4, 0.7, d / 2 + 3), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	end
end

-- A low-pitched hip roof of four slabs over a box `w` x `d` with its eaves at `eave` (in `cf`)
local function hipRoof(parent: Instance, cf: CFrame, w: number, d: number, eave: number, color: Color3)
	local pitch = math.rad(24)
	local over = 2
	for _, zs in { -1, 1 } do
		local low = (cf * CFrame.new(0, eave, zs * (d / 2 + over))).Position
		local high = (cf * CFrame.new(0, eave + (d / 2 + over) * math.tan(pitch), 0)).Position
		PartKit.Slab(parent, "Roof", low, high, w + over * 2, 0.8, color, Enum.Material.ClayRoofTiles)
	end
	for _, xs in { -1, 1 } do
		local low = (cf * CFrame.new(xs * (w / 2 + over), eave, 0)).Position
		local high = (cf * CFrame.new(xs * (w / 2 + over - (d / 2 + over)), eave + (d / 2 + over) * math.tan(pitch), 0)).Position
		PartKit.Slab(parent, "Roof", low, high, d + over * 2, 0.8, color, Enum.Material.ClayRoofTiles, NO_COLLIDE)
	end
end

-- Windows with arched heads (a frame, dark glass, a half-round on top) along a face
local function archedWindows(parent: Instance, face: CFrame, width: number, y: number, count: number, frame: Color3)
	for i = 1, count do
		local x = -width / 2 + i * width / (count + 1)
		local at = face * CFrame.new(x, y, -0.2)
		PartKit.Box(parent, "Window", Vector3.new(4, 6, 0.3), at, Color3.fromRGB(60, 72, 82), GLASS, DECOR)
		PartKit.Cylinder(parent, "WindowArch", 4, 0.3, at * CFrame.new(0, 3, 0) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(60, 72, 82), GLASS, DECOR)
		PartKit.Box(parent, "WindowFrame", Vector3.new(4.8, 0.5, 0.5), at * CFrame.new(0, -3.2, -0.1), frame, SMOOTH, DECOR)
	end
end

-- A Mediterranean Revival villa facing `front`, `setback` from its street: cream stucco, a red
-- barrel-tile hip roof, an arched loggia, sometimes a little tower, a pool behind
function Neighborhoods.Villa(parent: Instance, center: Vector3, front: Vector3, rng: Random, lotWidth: number)
	local model = PartKit.Model(parent, "Villa")
	local look = CFrame.lookAt(center, center + front) -- -Z toward the street
	local w, d, h = math.min(rng:NextNumber(44, 56), lotWidth - 16), rng:NextNumber(30, 38), 22
	local wall = pick(rng, MEDITERRANEAN)
	local trim = Color3.fromRGB(250, 248, 240)
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), look * CFrame.new(0, h / 2, 0), wall, PLASTER)
	hipRoof(model, look, w, d, h, TILE)
	-- the loggia: arches across part of the front
	local lw = w * 0.45
	PartKit.Box(model, "Loggia", Vector3.new(lw, 10, 0.5), look * CFrame.new(-w * 0.18, 5, -d / 2 - 0.1), Color3.fromRGB(70, 66, 60), SMOOTH, DECOR)
	for i = 0, 3 do
		local x = -w * 0.18 - lw / 2 + i * lw / 3
		PartKit.Box(model, "Column", Vector3.new(1.4, 9, 1.4), look * CFrame.new(x, 4.5, -d / 2 - 1.2), trim, Enum.Material.Marble)
	end
	PartKit.Box(model, "LoggiaBeam", Vector3.new(lw + 2, 2, 2.4), look * CFrame.new(-w * 0.18, 10, -d / 2 - 1.2), wall, PLASTER)
	archedWindows(model, CFrame.lookAt((look * CFrame.new(0, 0, -d / 2)).Position, (look * CFrame.new(0, 0, -d / 2 - 1)).Position), w, 15.5, 4, trim)
	PartKit.Box(model, "Door", Vector3.new(4.5, 8, 0.4), look * CFrame.new(w * 0.25, 4, -d / 2 - 0.15), Color3.fromRGB(96, 60, 36), Enum.Material.Wood, DECOR)
	PartKit.Cylinder(model, "DoorArch", 4.5, 0.4, look * CFrame.new(w * 0.25, 8, -d / 2 - 0.15) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(96, 60, 36), Enum.Material.Wood, DECOR)
	-- wrought-iron balcony over the door
	PartKit.Box(model, "Balcony", Vector3.new(8, 0.5, 3), look * CFrame.new(w * 0.25, 12.5, -d / 2 - 1.5), trim, SMOOTH, NO_COLLIDE)
	PartKit.Box(model, "BalconyRail", Vector3.new(8, 2.4, 0.2), look * CFrame.new(w * 0.25, 13.9, -d / 2 - 2.9), Color3.fromRGB(30, 30, 32), METAL, DECOR)
	if rng:NextNumber() < 0.5 then
		-- a stair tower with its own little roof
		local tower = look * CFrame.new(-w / 2 + 6, 0, -d / 2 + 6)
		PartKit.Box(model, "Tower", Vector3.new(12, h + 10, 12), tower * CFrame.new(0, (h + 10) / 2, 0), wall, PLASTER)
		hipRoof(model, tower, 12, 12, h + 10, TILE)
		archedWindows(model, tower * CFrame.new(0, 0, -6) * CFrame.Angles(0, math.pi, 0), 12, h + 4, 1, trim)
	end
	-- driveway, hedges, palms and a banyan out front, a pool behind
	PartKit.Box(model, "Driveway", Vector3.new(12, 0.1, 30), look * CFrame.new(w / 2 + 4, 0.05, -d / 2 - 15), Color3.fromRGB(196, 180, 160), Enum.Material.Cobblestone, DECOR)
	Detail.Hedge(model, (look * CFrame.new(-lotWidth / 2 + 2, 0, -d / 2 - 28)).Position, (look * CFrame.new(w / 2 - 4, 0, -d / 2 - 28)).Position, 4)
	Props.Palm(model, (look * CFrame.new(-w / 2 - 4, 0, -d / 2 - 8)).Position, rng, 0.9)
	if rng:NextNumber() < 0.6 then
		pool(model, look * CFrame.new(0, 0, d / 2 + 14), rng:NextNumber(18, 26), rng:NextNumber(10, 13))
	end
	if rng:NextNumber() < 0.4 then
		Buildings.ParkedCar(model, look * CFrame.new(w / 2 + 4, 0.1, -d / 2 - 10), rng, pick(rng, { "SUV", "Sedan" }))
	end
	return model
end

-- A modern mansion: white boxes, glass walls, a cantilevered top floor, flat roofs, a pool
function Neighborhoods.Mansion(parent: Instance, center: Vector3, front: Vector3, rng: Random, lotWidth: number)
	local model = PartKit.Model(parent, "Mansion")
	local look = CFrame.lookAt(center, center + front)
	local white = Color3.fromRGB(248, 248, 244)
	local w, d = math.min(rng:NextNumber(56, 72), lotWidth - 14), rng:NextNumber(34, 44)
	PartKit.Box(model, "Ground", Vector3.new(w, 12, d), look * CFrame.new(0, 6, 0), white, PLASTER)
	local glassWall = PartKit.Box(model, "ShopGlass", Vector3.new(w * 0.7, 10, 0.4), look * CFrame.new(-w * 0.1, 5.5, -d / 2 - 0.15), Color3.fromRGB(70, 96, 110), GLASS, DECOR)
	glassWall.Reflectance = 0.35
	-- the upper floor, slid forward over the entrance
	PartKit.Box(model, "Upper", Vector3.new(w * 0.75, 11, d * 0.85), look * CFrame.new(w * 0.1, 17.5, -4), white, PLASTER)
	local upper = PartKit.Box(model, "Window", Vector3.new(w * 0.72, 7, 0.4), look * CFrame.new(w * 0.1, 17.5, -4 - d * 0.425 - 0.15), Color3.fromRGB(60, 84, 98), GLASS, DECOR)
	upper.Reflectance = 0.35
	PartKit.Box(model, "RoofSlab", Vector3.new(w * 0.75 + 4, 1, d * 0.85 + 4), look * CFrame.new(w * 0.1, 23.5, -4), white, CONCRETE)
	PartKit.Box(model, "Canopy", Vector3.new(14, 0.8, 10), look * CFrame.new(-w * 0.32, 11.8, -d / 2 - 5), white, CONCRETE, NO_COLLIDE)
	-- wood slat screen and a glass balustrade on the roof terrace
	for i = 0, 6 do
		PartKit.Box(model, "Slat", Vector3.new(0.8, 10, 0.6), look * CFrame.new(w / 2 - 2 - i * 1.6, 5, -d / 2 - 0.4), Color3.fromRGB(150, 110, 76), Enum.Material.Wood, DECOR)
	end
	local rail = PartKit.Box(model, "Railing", Vector3.new(w * 0.25, 3.2, 0.3), look * CFrame.new(-w * 0.37, 13.6, -d / 2 + 0.5), Color3.fromRGB(190, 214, 224), GLASS, DECOR)
	rail.Transparency = 0.6
	-- gate, hedge wall, palms, pool
	Detail.Hedge(model, (look * CFrame.new(-lotWidth / 2 + 2, 0, -d / 2 - 22)).Position, (look * CFrame.new(lotWidth / 2 - 16, 0, -d / 2 - 22)).Position, 6)
	PartKit.Box(model, "Gate", Vector3.new(12, 6, 0.4), look * CFrame.new(lotWidth / 2 - 9, 3, -d / 2 - 22), Color3.fromRGB(40, 40, 42), METAL, NO_COLLIDE)
	for _, x in { -w / 2 - 3, w / 2 + 3 } do
		Props.Palm(model, (look * CFrame.new(x, 0, -d / 2 - 12)).Position, rng, 1.05)
	end
	pool(model, look * CFrame.new(-w * 0.1, 0, d / 2 + 15), w * 0.5, 12)
	if rng:NextNumber() < 0.5 then
		Buildings.ParkedCar(model, look * CFrame.new(w / 2 - 10, 0.1, -d / 2 - 12), rng, "SUV")
	end
	return model
end

-- A wooden Grove bungalow with a deep porch (cheaper than the suburban two-storey house)
function Neighborhoods.Bungalow(parent: Instance, center: Vector3, front: Vector3, rng: Random)
	local model = PartKit.Model(parent, "Bungalow")
	local look = CFrame.lookAt(center, center + front)
	local colors = { Color3.fromRGB(196, 222, 214), Color3.fromRGB(240, 224, 186), Color3.fromRGB(222, 206, 226), Color3.fromRGB(250, 248, 240), Color3.fromRGB(206, 226, 196) }
	local wall = pick(rng, colors)
	local w, d, h = rng:NextNumber(30, 38), rng:NextNumber(26, 32), 12
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), look * CFrame.new(0, h / 2 + 1.5, 0), wall, Enum.Material.WoodPlanks)
	PartKit.Box(model, "Plinth", Vector3.new(w + 0.4, 1.5, d + 0.4), look * CFrame.new(0, 0.75, 0), Color3.fromRGB(200, 196, 188), CONCRETE)
	hipRoof(model, look * CFrame.new(0, 1.5, 0), w, d, h, pick(rng, { Color3.fromRGB(90, 92, 98), Color3.fromRGB(150, 70, 50), Color3.fromRGB(200, 200, 196) }))
	PartKit.Box(model, "Porch", Vector3.new(w - 6, 1.5, 8), look * CFrame.new(0, 0.75, -d / 2 - 4), Color3.fromRGB(170, 140, 100), Enum.Material.WoodPlanks)
	for _, x in { -w / 2 + 4, 0, w / 2 - 4 } do
		PartKit.Box(model, "PorchPost", Vector3.new(0.8, 10, 0.8), look * CFrame.new(x, 6.5, -d / 2 - 7.4), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	end
	for _, x in { -w * 0.3, w * 0.3 } do
		PartKit.Box(model, "Window", Vector3.new(5, 5, 0.3), look * CFrame.new(x, 8, -d / 2 - 0.12), Color3.fromRGB(70, 96, 112), GLASS, DECOR)
		PartKit.Box(model, "Shutter", Vector3.new(1.6, 5, 0.3), look * CFrame.new(x - 3.4, 8, -d / 2 - 0.2), Color3.fromRGB(60, 110, 90), SMOOTH, DECOR)
	end
	PartKit.Box(model, "Door", Vector3.new(4, 7.5, 0.3), look * CFrame.new(0, 5.25, -d / 2 - 0.12), Color3.fromRGB(150, 60, 50), Enum.Material.Wood, DECOR)
	return model
end

local function houseRow(folder: Instance, block: LayoutModule.Block, rng: Random, perSide: number, build: (Vector3, Vector3, number) -> (), setback: number)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cz = (z0 + z1) / 2
	for _, side in { -1, 1 } do
		local front = Vector3.new(0, 0, side)
		local each = w / perSide
		for i = 0, perSide - 1 do
			local hx = x0 + each * (i + 0.5)
			local hz = cz + side * (d / 2 - setback)
			build(Vector3.new(hx, Y + 0.3, hz), front, each)
		end
		-- back fence or hedge between the rows
		Detail.Hedge(folder, Vector3.new(x0 + 2, Y + 0.3, cz + side * 2), Vector3.new(x1 - 2, Y + 0.3, cz + side * 2), 5)
	end
end

local function lawn(folder: Instance, block: LayoutModule.Block, color: Color3?)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local g = PartKit.Box(folder, "Lawn", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new((x0 + x1) / 2, Y + 0.15, (z0 + z1) / 2), color or C.Lawn, Enum.Material.Grass)
	g:SetAttribute("Surface", "Grass")
end

--------------------------------------------------------------------------------
-- Little Havana
--------------------------------------------------------------------------------
local function havana(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	-- one- and two-storey shops along both streets, painted bright; a car park behind
	for _, side in { -1, 1 } do
		local front = Vector3.new(0, 0, side)
		local n = 4
		local each = w / n
		for i = 0, n - 1 do
			local bw = each - rng:NextNumber(2, 6)
			local bd = rng:NextNumber(60, 80)
			local bx = x0 + each * (i + 0.5)
			local bz = cz + side * (d / 2 - bd / 2 - 1)
			local open = {}
			if i == 0 then
				table.insert(open, Vector3.new(-1, 0, 0))
			end
			if i == n - 1 then
				table.insert(open, Vector3.new(1, 0, 0))
			end
			Buildings.Midrise(folder, bx, bz, bw, bd, rng:NextInteger(1, 2), front, rng, open, true, HAVANA_SHOPS)
		end
	end
	local depth = d - 170
	if depth > 30 then
		Buildings.ParkingLot(folder, x0 + 6, x1 - 6, cz - depth / 2, cz + depth / 2, Y, rng, 0.45)
	end
	-- a mural on the corner building's flank
	local face = Detail.Face(x0 + 1, cz + d / 2 - 40, Vector3.new(-1, 0, 0), 0.6, Y)
	Buildings.Mural(folder, face, 50, 18, 3, rng)
end

-- Domino Park and the old cinema on Calle Ocho
local function havanaPark(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local paving = PartKit.Box(folder, "Paving", Vector3.new(x1 - x0, 0.3, z1 - z0), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(214, 196, 170), Enum.Material.Pavement)
	paving:SetAttribute("Surface", "Sidewalk")
	local fy = Y + 0.3
	-- the domino pavilion: a pergola over rows of tables, a mural of dominoes behind
	local px, pz = cx - (x1 - x0) / 4, z0 + 50
	PartKit.Box(folder, "PergolaRoof", Vector3.new(70, 1, 36), CFrame.new(px, fy + 12, pz), Color3.fromRGB(246, 238, 220), PLASTER, NO_COLLIDE)
	for _, ox in { -33, -11, 11, 33 } do
		for _, oz in { -16, 16 } do
			PartKit.Box(folder, "PergolaColumn", Vector3.new(2, 12, 2), CFrame.new(px + ox, fy + 6, pz + oz), Color3.fromRGB(246, 238, 220), PLASTER)
		end
	end
	for i = -2, 2 do
		for j = -1, 1 do
			local t = Vector3.new(px + i * 12, fy, pz + j * 9)
			PartKit.Box(folder, "DominoTable", Vector3.new(4, 0.4, 4), CFrame.new(t + Vector3.new(0, 2.8, 0)), Color3.fromRGB(30, 90, 60), SMOOTH)
			PartKit.Post(folder, "TableLeg", 0.6, 2.6, t, Color3.fromRGB(60, 60, 64), METAL, DECOR)
			for _, o in { Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3) } do
				PartKit.Post(folder, "Stool", 1.4, 1.8, t + o, Color3.fromRGB(200, 60, 50), SMOOTH, DECOR)
			end
		end
	end
	local muralWall = PartKit.Box(folder, "MuralWall", Vector3.new(70, 14, 2), CFrame.new(px, fy + 7, z0 + 4), Color3.fromRGB(240, 232, 214), PLASTER)
	local _ = muralWall
	Buildings.Mural(folder, Detail.Face(px, z0 + 4, Vector3.new(0, 0, 1), 1.05, fy), 68, 13, 0.5, rng)
	-- the cinema on the corner: art deco front and a tall vertical sign
	local tx, tz = cx + (x1 - x0) / 4, z0 + 45
	local front = CFrame.lookAt(Vector3.new(tx, fy, z0 + 80), Vector3.new(tx, fy, z0 + 80) + Vector3.new(0, 0, 1))
	PartKit.Box(folder, "Cinema", Vector3.new(70, 34, 70), CFrame.new(tx, fy + 17, tz), Color3.fromRGB(242, 228, 200), PLASTER)
	PartKit.Box(folder, "Marquee", Vector3.new(50, 5, 10), front * CFrame.new(0, 12, -5), Color3.fromRGB(250, 250, 246), SMOOTH, NO_COLLIDE)
	local marquee = PartKit.Box(folder, "MarqueeText", Vector3.new(46, 3.6, 0.2), front * CFrame.new(0, 12, -10.2), Color3.fromRGB(20, 20, 24), SMOOTH, DECOR)
	PartKit.Sign(marquee, Enum.NormalId.Front, "CINE TROPICAL · FILMS EN ESPAÑOL", Color3.fromRGB(255, 70, 160), Color3.fromRGB(20, 20, 24), Enum.Font.GothamBlack, 8)
	local fin = PartKit.Box(folder, "FinSign", Vector3.new(1.4, 30, 9), front * CFrame.new(-20, 32, -3), Color3.fromRGB(250, 250, 246), SMOOTH, DECOR)
	for _, f in { Enum.NormalId.Left, Enum.NormalId.Right } do
		PartKit.Sign(fin, f, "T\nR\nO\nP\nI\nC\nA\nL", Color3.fromRGB(60, 220, 255), nil, Enum.Font.GothamBlack, 6)
	end
	local glass = PartKit.Box(folder, "ShopGlass", Vector3.new(30, 8, 0.4), front * CFrame.new(0, 4.5, -0.2), Color3.fromRGB(70, 96, 110), GLASS, DECOR)
	glass.Reflectance = 0.2
	-- palms, benches, a fountain between
	for _ = 1, 8 do
		Props.Palm(folder, Vector3.new(rng:NextNumber(x0 + 10, x1 - 10), fy, rng:NextNumber(cz + 20, z1 - 10)), rng)
	end
	PartKit.Post(folder, "FountainRim", 24, 1.6, Vector3.new(cx, fy, cz + 60), Color3.fromRGB(230, 220, 200), Enum.Material.Marble)
	local water = PartKit.Post(folder, "Water", 21, 1.65, Vector3.new(cx, fy, cz + 60), Color3.fromRGB(70, 160, 200), SMOOTH)
	water.Transparency = 0.25
	for i = 0, 3 do
		Props.Bench(folder, CFrame.new(cx - 30 + i * 20, fy, cz + 30))
	end
end

--------------------------------------------------------------------------------
-- Coral Gables
--------------------------------------------------------------------------------
local function gables(folder: Instance, block: LayoutModule.Block, rng: Random)
	lawn(folder, block)
	houseRow(folder, block, rng, 3, function(at: Vector3, front: Vector3, each: number)
		Neighborhoods.Villa(folder, at, front, rng, each)
	end, 60)
	-- banyans down the middle
	local x0, x1 = block.LotMinX, block.LotMaxX
	local cz = (block.LotMinZ + block.LotMaxZ) / 2
	for i = 0, 2 do
		Neighborhoods.Banyan(folder, Vector3.new(x0 + (i + 0.5) * (x1 - x0) / 3, Y + 0.3, cz + rng:NextNumber(-12, 12)), rng)
	end
end

-- The grand hotel: an H-plan Mediterranean palace with a tall bell tower, its pool and terraces
local function gablesHotel(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	lawn(folder, block)
	local model = PartKit.Model(folder, "GrandHotel")
	local wall = Color3.fromRGB(240, 222, 190)
	local fy = Y + 0.3
	-- the main range and two wings
	local function range(rx: number, rz: number, w: number, d: number, h: number)
		PartKit.Box(model, "Range", Vector3.new(w, h, d), CFrame.new(rx, fy + h / 2, rz), wall, PLASTER)
		hipRoof(model, CFrame.new(rx, fy, rz), w, d, h, TILE)
		for _, out in { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			local face = Detail.Face(rx, rz, out, d / 2, fy)
			for floor = 0, math.floor(h / 12) - 1 do
				archedWindows(model, face, w, 6 + floor * 12, math.floor(w / 14), Color3.fromRGB(250, 248, 240))
			end
		end
	end
	range(cx, cz - 20, 220, 50, 60)
	range(cx - 85, cz + 40, 50, 120, 48)
	range(cx + 85, cz + 40, 50, 120, 48)
	-- the bell tower over the entrance: stacked stages, a lantern, a cupola
	local tx, tz = cx, cz - 20
	local stages = { { 34, 140 }, { 26, 40 }, { 18, 30 } }
	local y = fy
	for _, stage in stages do
		local size, h = stage[1], stage[2]
		PartKit.Box(model, "Tower", Vector3.new(size, h, size), CFrame.new(tx, y + h / 2, tz), wall, PLASTER)
		PartKit.Box(model, "TowerCornice", Vector3.new(size + 2, 1.6, size + 2), CFrame.new(tx, y + h, tz), Color3.fromRGB(250, 246, 236), Enum.Material.Marble, DECOR)
		for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			archedWindows(model, Detail.Face(tx, tz, out, size / 2, y), size, h - 10, if size > 30 then 2 else 1, Color3.fromRGB(250, 248, 240))
		end
		y += h
	end
	PartKit.Ball(model, "Cupola", 14, Vector3.new(tx, y + 3, tz), TILE, Enum.Material.ClayRoofTiles)
	PartKit.Post(model, "Finial", 0.8, 10, Vector3.new(tx, y + 9, tz), Color3.fromRGB(210, 180, 90), METAL, DECOR)
	skylineModel(model)
	-- the big pool in the courtyard between the wings, palms and loungers round it
	pool(model, CFrame.new(cx, fy, cz + 60), 100, 40)
	for i = 0, 9 do
		Props.Palm(model, Vector3.new(cx - 60 + i * 13, fy, cz + 95), rng, 1.1)
	end
	local sign = PartKit.Box(model, "HotelSign", Vector3.new(40, 6, 1.2), CFrame.new(cx, fy + 3, z0 + 6), Color3.fromRGB(230, 214, 186), Enum.Material.Marble)
	PartKit.Sign(sign, Enum.NormalId.Front, "THE PALMERA GRAND", Color3.fromRGB(110, 70, 40), nil, Enum.Font.Garamond, 10)
	local _ = rng
end

--------------------------------------------------------------------------------
-- Coconut Grove
--------------------------------------------------------------------------------
local function grove(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1 = block.LotMinX, block.LotMaxX
	-- the blocks either side of Main Hwy are its village of shops and cafés under the trees
	local onMain = math.abs(block.MinX - 0) < 40 or math.abs(block.MaxX - 0) < 40
	if onMain then
		local z0, z1 = block.LotMinZ, block.LotMaxZ
		local cz = (z0 + z1) / 2
		local d = z1 - z0
		for _, side in { -1, 1 } do
			local front = Vector3.new(0, 0, side)
			local n = 3
			local each = (x1 - x0) / n
			for i = 0, n - 1 do
				local bd = rng:NextNumber(60, 80)
				Buildings.Midrise(folder, x0 + each * (i + 0.5), cz + side * (d / 2 - bd / 2 - 2), each - 6, bd, rng:NextInteger(2, 3), front, rng, { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) }, true)
			end
		end
		Buildings.ParkingLot(folder, x0 + 6, x1 - 6, cz - (d - 170) / 2, cz + (d - 170) / 2, Y, rng, 0.4)
		return
	end
	lawn(folder, block, Color3.fromRGB(84, 140, 64))
	houseRow(folder, block, rng, 4, function(at: Vector3, front: Vector3, _each: number)
		Neighborhoods.Bungalow(folder, at, front, rng)
	end, 50)
	-- the canopy: big shade trees through the gardens, palms by the street
	local z0, z1 = block.LotMinZ, block.LotMaxZ
	for _ = 1, 7 do
		local x = rng:NextNumber(x0 + 12, x1 - 12)
		local z = (z0 + z1) / 2 + rng:NextNumber(-30, 30)
		if rng:NextNumber() < 0.55 then
			Neighborhoods.Banyan(folder, Vector3.new(x, Y + 0.3, z), rng, rng:NextNumber(0.8, 1.1))
		else
			Props.Tree(folder, Vector3.new(x, Y + 0.3, z), rng, rng:NextNumber(1.2, 1.6))
		end
	end
end

-- The waterfront by Bayshore Dr: a park on the bay, a sailing club and its dinghy racks
local function groveBay(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	lawn(folder, block)
	local fy = Y + 0.3
	local path = PartKit.Box(folder, "Path", Vector3.new(12, 0.2, z1 - z0), CFrame.new(cx, fy + 0.1, cz), Color3.fromRGB(214, 200, 178), Enum.Material.Pavement)
	path:SetAttribute("Surface", "Sidewalk")
	if block.Bz % 2 == 0 then
		-- the sailing club
		local club = Vector3.new(x1 - 50, fy, cz)
		PartKit.Box(folder, "SailingClub", Vector3.new(60, 14, 40), CFrame.new(club + Vector3.new(0, 7, 0)), Color3.fromRGB(250, 250, 246), Enum.Material.WoodPlanks)
		hipRoof(folder, CFrame.new(club), 60, 40, 14, Color3.fromRGB(70, 110, 140))
		local glass = PartKit.Box(folder, "ShopGlass", Vector3.new(50, 8, 0.4), CFrame.new(club + Vector3.new(0, 5, -20.2)), Color3.fromRGB(70, 96, 110), GLASS, DECOR)
		glass.Reflectance = 0.2
		local sign = PartKit.Box(folder, "ClubSign", Vector3.new(30, 4, 0.3), CFrame.new(club + Vector3.new(0, 16, -20.3)), Color3.fromRGB(250, 250, 246), SMOOTH, DECOR)
		sign.Transparency = 1
		PartKit.Sign(sign, Enum.NormalId.Front, "GROVE SAILING CLUB", Color3.fromRGB(30, 70, 120), nil, Enum.Font.GothamBold, 10)
		-- dinghies on racks
		for i = 0, 5 do
			local p = Vector3.new(x0 + 30 + i * 18, fy, z0 + 30)
			PartKit.Box(folder, "Rack", Vector3.new(14, 4, 6), CFrame.new(p + Vector3.new(0, 2, 0)), Color3.fromRGB(150, 150, 150), METAL, NO_COLLIDE)
			PartKit.Box(folder, "Dinghy", Vector3.new(5, 2, 12), CFrame.new(p + Vector3.new(0, 5, 0)), pick(rng, { Color3.fromRGB(240, 240, 236), Color3.fromRGB(220, 60, 50), Color3.fromRGB(50, 110, 190) }), SMOOTH, DECOR)
		end
	end
	for _ = 1, 10 do
		local x, z = rng:NextNumber(x0 + 10, x1 - 10), rng:NextNumber(z0 + 10, z1 - 10)
		if math.abs(x - cx) > 12 then
			if rng:NextNumber() < 0.6 then
				Props.Palm(folder, Vector3.new(x, fy, z), rng)
			else
				Neighborhoods.Banyan(folder, Vector3.new(x, fy, z), rng, 0.9)
			end
		end
	end
	for i = -2, 2 do
		Props.Bench(folder, CFrame.new(cx + 9, fy, cz + i * 40) * CFrame.Angles(0, math.rad(90), 0))
		Props.Lamp(folder, Vector3.new(cx - 9, fy, cz + i * 40 + 12))
	end
end

--------------------------------------------------------------------------------
-- North Beach and Key Biscayne
--------------------------------------------------------------------------------
local function mansions(folder: Instance, block: LayoutModule.Block, rng: Random)
	lawn(folder, block)
	houseRow(folder, block, rng, 2, function(at: Vector3, front: Vector3, each: number)
		Neighborhoods.Mansion(folder, at, front, rng, each)
	end, 50)
end

local function keyHomes(folder: Instance, block: LayoutModule.Block, rng: Random)
	lawn(folder, block)
	houseRow(folder, block, rng, 3, function(at: Vector3, front: Vector3, each: number)
		if rng:NextNumber() < 0.5 then
			Neighborhoods.Mansion(folder, at, front, rng, each)
		else
			Neighborhoods.Villa(folder, at, front, rng, each)
		end
	end, 55)
end

-- Crandon Park: picnic shelters under the palms; at the south tip, the lighthouse and its cottage
local function keyPark(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	lawn(folder, block)
	local fy = Y + 0.3
	for i = 0, 2 do
		local p = Vector3.new(cx - 40 + i * 40, fy, cz - 50)
		PartKit.Box(folder, "Shelter", Vector3.new(24, 1, 16), CFrame.new(p + Vector3.new(0, 10, 0)), Color3.fromRGB(150, 110, 76), Enum.Material.WoodPlanks, NO_COLLIDE)
		for _, o in { Vector3.new(-10, 0, -6), Vector3.new(10, 0, -6), Vector3.new(-10, 0, 6), Vector3.new(10, 0, 6) } do
			PartKit.Box(folder, "ShelterPost", Vector3.new(1, 10, 1), CFrame.new(p + o + Vector3.new(0, 5, 0)), Color3.fromRGB(130, 96, 66), Enum.Material.Wood)
		end
		PartKit.Box(folder, "PicnicTable", Vector3.new(12, 3, 4), CFrame.new(p + Vector3.new(0, 1.5, 0)), Color3.fromRGB(160, 120, 80), Enum.Material.WoodPlanks, NO_COLLIDE)
	end
	for _ = 1, 14 do
		Props.Palm(folder, Vector3.new(rng:NextNumber(x0 + 10, x1 - 10), fy, rng:NextNumber(z0 + 10, z1 - 10)), rng)
	end
	if block.Bz == #Layout.KEY_ZS - 2 then
		-- the lighthouse: a white tapering tower, a black lantern and gallery, the keeper's cottage
		local lx, lz = cx, z1 - 40
		local model = PartKit.Model(folder, "Lighthouse")
		local stages = 5
		for k = 0, stages - 1 do
			local dia = 18 - k * 1.6
			PartKit.Post(model, "Tower", dia, 20, Vector3.new(lx, fy + k * 20, lz), Color3.fromRGB(248, 248, 244), Enum.Material.Brick)
		end
		local top = fy + stages * 20
		PartKit.Post(model, "Gallery", 16, 1, Vector3.new(lx, top, lz), Color3.fromRGB(30, 30, 32), METAL)
		PartKit.Post(model, "Lantern", 9, 9, Vector3.new(lx, top + 1, lz), Color3.fromRGB(40, 50, 56), GLASS)
		PartKit.Ball(model, "Globe", 5, Vector3.new(lx, top + 5.5, lz), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
		PartKit.Ball(model, "LanternCap", 9.5, Vector3.new(lx, top + 10, lz), Color3.fromRGB(30, 30, 32), METAL)
		PartKit.Box(model, "Cottage", Vector3.new(30, 14, 22), CFrame.new(lx - 40, fy + 7, lz), Color3.fromRGB(250, 248, 240), Enum.Material.WoodPlanks)
		hipRoof(model, CFrame.new(lx - 40, fy, lz), 30, 22, 14, Color3.fromRGB(150, 70, 50))
		skylineModel(model)
	end
end

local FILL: { [string]: (Instance, LayoutModule.Block, Random) -> () } = {
	Havana = havana,
	HavanaPark = havanaPark,
	Gables = gables,
	GablesHotel = gablesHotel,
	Grove = grove,
	GroveBay = groveBay,
	Mansion = mansions,
	KeyHomes = keyHomes,
	KeyPark = keyPark,
}

-- Fills a block of one of these districts; false if it isn't one
Neighborhoods.HipRoof = hipRoof
Neighborhoods.ArchedWindows = archedWindows
Neighborhoods.Pool = pool

function Neighborhoods.Fill(parent: Instance, block: LayoutModule.Block, rng: Random): boolean
	local fill = FILL[block.District]
	if not fill then
		return false
	end
	local folder = PartKit.Folder(parent, block.District .. "_" .. block.Grid .. "_" .. block.Bx .. "_" .. block.Bz)
	fill(folder, block, rng)
	return true
end

return Neighborhoods
