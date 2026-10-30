--[[
	Buildings: Miami's blocks. Glass condo towers on parking podiums (Brickell, Downtown, Edgewater
	and the island's Collins Ave), office towers, art-deco hotels on Ocean Drive, pastel midrises,
	Wynwood's mural-covered warehouses, fast-food outlets with drive-thrus and pylon signs, strip
	malls, gas stations, car parks and a parking garage you can ride to the roof of, and the
	suburbs' stucco houses with pools. Everything sits on a block's lot at Layout.CURB_Y.

	The brands, hotel and tower names are made up.
]]

local LayoutModule = require(script.Parent.Layout)
-- Built in design units (1 stud = 0.28 m); the Builder scales the finished city by WORLD_SCALE
local Layout: typeof(LayoutModule) = (LayoutModule :: any).Design
local Props = require(script.Parent.Props)
local Detail = require(script.Parent.Detail)
local Interior = require(script.Parent.Interior)
local CarModel = require(script.Parent.Parent.Models.CarModel)
local Config = require(script.Parent.Parent.Config)
local PartKit = require(script.Parent.Parent.PartKit)

local Buildings = {}

local C = Props.Palette
local Y = Layout.CURB_Y
local SMOOTH = Enum.Material.SmoothPlastic
local CONCRETE = Enum.Material.Concrete
local GLASS = Enum.Material.Glass
local METAL = Enum.Material.Metal
local DECOR = { Collide = false, Query = false, Touch = false, Shadow = false }
local NO_COLLIDE = { Collide = false, Query = false, Touch = false }

local GLASS_TINTS = {
	Color3.fromRGB(78, 128, 158),
	Color3.fromRGB(62, 102, 132),
	Color3.fromRGB(110, 150, 172),
	Color3.fromRGB(72, 92, 112),
	Color3.fromRGB(120, 168, 186),
	Color3.fromRGB(90, 118, 140),
}
local CONCRETE_TONES = {
	Color3.fromRGB(205, 208, 212),
	Color3.fromRGB(182, 186, 192),
	Color3.fromRGB(226, 226, 222),
	Color3.fromRGB(160, 166, 172),
}
local BRICKS = {
	Color3.fromRGB(158, 82, 62),
	Color3.fromRGB(176, 120, 90),
	Color3.fromRGB(196, 170, 140),
	Color3.fromRGB(120, 72, 58),
	Color3.fromRGB(214, 200, 180),
	Color3.fromRGB(140, 150, 160),
}
local HOUSE_COLORS = {
	Color3.fromRGB(250, 246, 238),
	Color3.fromRGB(246, 222, 200),
	Color3.fromRGB(214, 234, 228),
	Color3.fromRGB(250, 232, 180),
	Color3.fromRGB(236, 214, 226),
	Color3.fromRGB(206, 226, 240),
	Color3.fromRGB(240, 240, 232),
}
-- mostly barrel-tile terracotta, some grey shingle
local ROOFS = {
	Color3.fromRGB(178, 86, 54),
	Color3.fromRGB(196, 104, 64),
	Color3.fromRGB(164, 74, 48),
	Color3.fromRGB(110, 112, 118),
}
-- Miami stucco
local PASTELS = {
	Color3.fromRGB(250, 196, 206),
	Color3.fromRGB(176, 228, 214),
	Color3.fromRGB(252, 230, 160),
	Color3.fromRGB(204, 196, 236),
	Color3.fromRGB(252, 212, 176),
	Color3.fromRGB(160, 214, 236),
	Color3.fromRGB(246, 244, 236),
	Color3.fromRGB(196, 232, 176),
}
local SHOPS = {
	"Cafe Sol", "Farmacia", "Lavanderia", "Cuban Bakery", "Phone Fix", "Nail Spa", "Botanica",
	"Taco Loco", "Surf Shop", "Gadget Hub", "Fruteria", "Noodle Bar", "Flower Shop", "Game Zone",
	"Ink Tattoo", "Bike Parts", "Gelato", "Panaderia", "Sushi Go", "Hardware", "Barber", "Vape & Co",
}
local AWNINGS = {
	Color3.fromRGB(200, 40, 40),
	Color3.fromRGB(30, 110, 70),
	Color3.fromRGB(30, 80, 160),
	Color3.fromRGB(230, 150, 30),
	Color3.fromRGB(120, 60, 140),
	Color3.fromRGB(40, 40, 40),
}

local TOWER_NAMES = { "VOLTA TOWER", "ONE MERIDIAN", "HARBOR TRUST", "BAYSIDE CENTER", "NOVA CENTRE", "ATLAS HOUSE", "CIRCUIT BANK", "SOLARA FINANCIAL" }
local COMPANIES = { "VOLT LOGISTICS", "CELLWORKS", "IRONSIDE", "NORTHLINE FREIGHT", "AMP SUPPLY", "GRIDCO" }

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- A glass tower: curtain wall with mullions on every face, floor bands, corner piers, a lobby,
-- roof plant and sometimes a crown and antenna
function Buildings.Tower(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, rng: Random): Model
	local model = PartKit.Model(parent, "Tower")
	local glass = pick(rng, GLASS_TINTS)
	local stone = pick(rng, CONCRETE_TONES)
	local lobbyH = 16
	local core = PartKit.Box(model, "Glass", Vector3.new(w - 1.6, h - lobbyH, d - 1.6), CFrame.new(cx, Y + lobbyH + (h - lobbyH) / 2, cz), glass, GLASS)
	core.Reflectance = 0.2
	-- recessed lobby: darker glass behind columns
	local lobby = PartKit.Box(model, "Lobby", Vector3.new(w - 6, lobbyH, d - 6), CFrame.new(cx, Y + lobbyH / 2, cz), Color3.fromRGB(60, 80, 90), GLASS)
	lobby.Reflectance = 0.25
	local floor = 15
	for y = lobbyH, h - 4, floor do
		PartKit.Box(model, "Floor", Vector3.new(w, 1.2, d), CFrame.new(cx, Y + y, cz), stone, CONCRETE)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartKit.Box(model, "Pier", Vector3.new(2.4, h, 2.4), CFrame.new(cx + sx * (w / 2 - 1.2), Y + h / 2, cz + sz * (d / 2 - 1.2)), stone, CONCRETE)
		end
	end
	-- mullions on all four faces
	local spacing = 7
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half - 0.6, Y)
		local n = math.floor((faceW - 6) / spacing)
		for i = 1, n - 1 do
			local x = -faceW / 2 + 3 + i * (faceW - 6) / n
			PartKit.Box(model, "Mullion", Vector3.new(0.5, h - lobbyH, 0.6), face * CFrame.new(x, lobbyH + (h - lobbyH) / 2, -0.2), stone, CONCRETE, DECOR)
		end
		-- lobby columns and doors
		local cols = math.max(3, math.floor(faceW / 14))
		for i = 1, cols - 1 do
			local x = -faceW / 2 + i * faceW / cols
			PartKit.Box(model, "Column", Vector3.new(1.8, lobbyH, 1.8), face * CFrame.new(x, lobbyH / 2, 1.5), stone, CONCRETE)
		end
	end
	local front = Detail.Face(cx, cz, Vector3.new(0, 0, 1), d / 2 - 3, Y)
	for _, x in { -3, 3 } do
		PartKit.Box(model, "LobbyDoor", Vector3.new(5, 9, 0.3), front * CFrame.new(x, 4.5, -0.2), Color3.fromRGB(150, 180, 190), GLASS, DECOR).Transparency = 0.3
	end
	PartKit.Box(model, "Canopy", Vector3.new(w * 0.45, 0.8, 9), front * CFrame.new(0, lobbyH - 2, -4.5), stone, CONCRETE, NO_COLLIDE)
	local label = PartKit.Box(model, "TowerName", Vector3.new(w * 0.4, 2.4, 0.3), front * CFrame.new(0, lobbyH - 0.4, -9.1), Color3.fromRGB(30, 30, 34), SMOOTH, DECOR)
	PartKit.Sign(label, Enum.NormalId.Front, pick(rng, TOWER_NAMES), Color3.fromRGB(240, 240, 240), nil, Enum.Font.GothamBold, 12)
	PartKit.Box(model, "Parapet", Vector3.new(w + 0.8, 3, d + 0.8), CFrame.new(cx, Y + h + 1.5, cz), stone, CONCRETE)
	PartKit.Box(model, "Roof", Vector3.new(w - 3, 0.4, d - 3), CFrame.new(cx, Y + h + 2.8, cz), Color3.fromRGB(80, 82, 86), CONCRETE, DECOR)
	PartKit.Box(model, "Plant", Vector3.new(w * 0.3, 8, d * 0.3), CFrame.new(cx + w * 0.15, Y + h + 4, cz - d * 0.1), Color3.fromRGB(150, 155, 160), Enum.Material.DiamondPlate)
	Detail.Roof(model, cx - w * 0.15, cz + d * 0.15, w * 0.55, d * 0.55, Y + h + 3, rng)
	if rng:NextNumber() < 0.4 then
		-- stepped glass crown
		for k = 1, 2 do
			local f = 1 - k * 0.22
			local crown = PartKit.Box(model, "Crown", Vector3.new(w * f, 10, d * f), CFrame.new(cx, Y + h + 3 + (k - 0.5) * 10, cz), glass, GLASS)
			crown.Reflectance = 0.2
			PartKit.Box(model, "CrownBand", Vector3.new(w * f + 0.6, 1, d * f + 0.6), CFrame.new(cx, Y + h + 3 + k * 10, cz), stone, CONCRETE, DECOR)
		end
	end
	if h > 260 then
		PartKit.Post(model, "Antenna", 1.2, 40, Vector3.new(cx - w * 0.2, Y + h + 3, cz + d * 0.15), Color3.fromRGB(200, 200, 205), Enum.Material.Metal)
		PartKit.Ball(model, "Beacon", 2, Vector3.new(cx - w * 0.2, Y + h + 43, cz + d * 0.15), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, DECOR)
	end
	return model
end

-- A brick (or render) building with framed windows on every face; the ground floor is a shopfront
-- facing `front`, sometimes a fire escape on a side, roof plant on top
function Buildings.Midrise(parent: Instance, cx: number, cz: number, w: number, d: number, floors: number, front: Vector3, rng: Random, openSides: { Vector3 }?, stucco: boolean?, shopNames: { string }?)
	local model = PartKit.Model(parent, "Building")
	local floorH = 12
	local h = floors * floorH + 2
	local brick = if stucco then pick(rng, PASTELS) else pick(rng, BRICKS)
	local material = if stucco or rng:NextNumber() >= 0.75 then Enum.Material.Plaster else Enum.Material.Brick
	-- the ground floor is the shop (Interior, built with the storefront below); the body sits on it
	PartKit.Box(model, "Body", Vector3.new(w, h - floorH, d), CFrame.new(cx, Y + floorH + (h - floorH) / 2, cz), brick, material)
	local trim = pick(rng, { Color3.fromRGB(235, 230, 220), Color3.fromRGB(60, 62, 66), Color3.fromRGB(200, 196, 186) })
	local style: Detail.WindowStyle = {
		Width = pick(rng, { 4, 4.5, 5 }),
		Height = pick(rng, { 6, 7, 7.5 }),
		Spacing = pick(rng, { 8, 9, 10 }),
		Frame = trim,
	}
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half, Y)
		-- side walls in a row face their neighbours: windows only where a street can see them
		local isSide = math.abs(out:Dot(front)) < 0.5
		local open = not isSide
		if isSide and openSides then
			for _, o in openSides do
				if o:Dot(out) > 0.5 then
					open = true
				end
			end
		end
		if open then
			-- the street face gets the full set; the back and the open ends plainer, wider-spaced
			-- windows without sills
			local faceStyle = style
			if out ~= front then
				faceStyle = table.clone(style)
				faceStyle.Spacing = style.Spacing * 1.4
				faceStyle.Sill = false
			end
			Detail.Windows(model, face, faceW, floorH, h - 2, floorH, faceStyle, 3)
		end
		-- string course between floors on the street face
		if out == front then
			for f = 1, floors - 1 do
				PartKit.Box(model, "StringCourse", Vector3.new(faceW + 0.4, 0.6, 0.5), face * CFrame.new(0, f * floorH, -0.15), trim, CONCRETE, DECOR)
			end
		end
	end
	-- shopfront
	local faceWidth = if math.abs(front.X) > 0.5 then d else w
	local faceDepth = if math.abs(front.X) > 0.5 then w else d
	local face = Detail.Face(cx, cz, front, faceDepth / 2, Y)
	local shopName = pick(rng, shopNames or SHOPS)
	Detail.Storefront(model, face, faceWidth, 9.5, shopName, pick(rng, AWNINGS), rng)
	Interior.Build(model, face * CFrame.new(0, 0, faceDepth / 2) * CFrame.Angles(0, 0, 0), faceWidth, faceDepth, floorH, {
		Kind = "Shop",
		Name = shopName,
		Accent = pick(rng, AWNINGS),
		Wall = brick:Lerp(Color3.new(1, 1, 1), 0.6),
		Front = false,
		Sides = true,
		Rng = rng,
	})
	-- the wall above the shopfront, up to the first floor
	PartKit.Box(model, "ShopHeader", Vector3.new(faceWidth, floorH - 9.5, 1), face * CFrame.new(0, 9.5 + (floorH - 9.5) / 2, 0.5), brick, material)
	-- side door to the flats above
	-- fire escape on one side
	if floors >= 3 and rng:NextNumber() < 0.45 then
		local side = Vector3.new(-front.Z, 0, front.X) * (if rng:NextNumber() < 0.5 then 1 else -1)
		local sideWidth = if math.abs(side.X) > 0.5 then d else w
		local sideDepth = if math.abs(side.X) > 0.5 then w else d
		Detail.FireEscape(model, Detail.Face(cx, cz, side, sideDepth / 2, Y), sideWidth * 0.15, floors, floorH)
	end
	-- cornice, roof clutter and sometimes a water tank
	PartKit.Box(model, "Cornice", Vector3.new(w + 1.4, 1.4, d + 1.4), CFrame.new(cx, Y + h + 0.2, cz), trim, CONCRETE)
	PartKit.Box(model, "CorniceDentil", Vector3.new(w + 0.8, 0.6, d + 0.8), CFrame.new(cx, Y + h - 0.8, cz), trim, CONCRETE, DECOR)
	Detail.Roof(model, cx, cz, w - 4, d - 4, Y + h + 0.9, rng)
	if rng:NextNumber() < 0.35 then
		local tank = Vector3.new(cx + rng:NextNumber(-w / 4, w / 4), Y + h + 1, cz + rng:NextNumber(-d / 4, d / 4))
		for _, o in { Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2), Vector3.new(2, 0, 2) } do
			PartKit.Post(model, "TankLeg", 0.4, 6, tank + o, Color3.fromRGB(60, 50, 40), Enum.Material.Wood, DECOR)
		end
		PartKit.Post(model, "Tank", 7, 7, tank + Vector3.new(0, 6, 0), Color3.fromRGB(130, 96, 66), Enum.Material.WoodPlanks)
		PartKit.Cylinder(model, "TankRoof", 7.6, 1.2, CFrame.new(tank + Vector3.new(0, 13.4, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(70, 60, 50), Enum.Material.WoodPlanks, DECOR)
	end
end

function Buildings.Warehouse(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, front: Vector3, rng: Random): Model
	local model = PartKit.Model(parent, "Warehouse")
	local wall = pick(rng, { Color3.fromRGB(190, 192, 186), Color3.fromRGB(160, 170, 175), Color3.fromRGB(196, 180, 150), Color3.fromRGB(120, 140, 150) })
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), CFrame.new(cx, Y + h / 2, cz), wall, Enum.Material.Concrete)
	PartKit.Box(model, "Roof", Vector3.new(w + 2, 1.5, d + 2), CFrame.new(cx, Y + h + 0.75, cz), Color3.fromRGB(110, 115, 120), Enum.Material.DiamondPlate)
	local rib = wall:Lerp(Color3.new(0, 0, 0), 0.12)
	-- corrugated cladding (ribs) above a concrete plinth, and a strip of high windows
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half, Y)
		PartKit.Box(model, "Plinth", Vector3.new(faceW + 0.4, 4, 0.6), face * CFrame.new(0, 2, -0.2), Color3.fromRGB(150, 150, 146), CONCRETE, DECOR)
		local n = math.floor(faceW / 3.5)
		for i = 0, n do
			local x = -faceW / 2 + i * faceW / n
			PartKit.Box(model, "Rib", Vector3.new(0.6, h - 4, 0.35), face * CFrame.new(x, 4 + (h - 4) / 2, -0.12), rib, METAL, DECOR)
		end
		local band = PartKit.Box(model, "HighWindows", Vector3.new(faceW - 8, 3, 0.3), face * CFrame.new(0, h - 5, -0.3), Color3.fromRGB(150, 180, 196), GLASS, DECOR)
		band.Reflectance = 0.15
	end
	local right = Vector3.new(-front.Z, 0, front.X)
	local faceWidth = if math.abs(front.X) > 0.5 then d else w
	local faceDepth = if math.abs(front.X) > 0.5 then w else d
	local face = Detail.Face(cx, cz, front, faceDepth / 2, Y)
	local doors = math.max(1, math.floor(faceWidth / 40))
	for i = 1, doors do
		local x = -faceWidth / 2 + (i - 0.5) * faceWidth / doors
		local at = face * CFrame.new(x, 0, 0)
		PartKit.Box(model, "LoadingDoor", Vector3.new(16, 16, 0.5), at * CFrame.new(0, 8, -0.4), Color3.fromRGB(90, 96, 104), Enum.Material.CorrodedMetal, DECOR)
		for k = 1, 7 do
			PartKit.Box(model, "DoorSlat", Vector3.new(16, 0.25, 0.6), at * CFrame.new(0, k * 2, -0.45), Color3.fromRGB(70, 76, 84), METAL, DECOR)
		end
		PartKit.Box(model, "DoorStripe", Vector3.new(16.6, 1, 0.7), at * CFrame.new(0, 16.6, -0.4), Color3.fromRGB(240, 190, 30), SMOOTH, DECOR)
		-- dock: a raised concrete apron with rubber bumpers
		PartKit.Box(model, "Dock", Vector3.new(20, 4, 6), at * CFrame.new(0, 2, -3), Color3.fromRGB(170, 168, 162), CONCRETE)
		for _, s in { -1, 1 } do
			PartKit.Box(model, "Bumper", Vector3.new(1, 1.6, 0.8), at * CFrame.new(s * 6, 2.6, -6.3), Color3.fromRGB(20, 20, 20), SMOOTH, DECOR)
		end
		PartKit.Box(model, "DockLight", Vector3.new(1.2, 0.6, 1.2), at * CFrame.new(10.5, 18, -1), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
	end
	-- personnel door with a small canopy
	local pd = face * CFrame.new(faceWidth / 2 - 8, 0, 0)
	PartKit.Box(model, "StaffDoor", Vector3.new(3.6, 7.5, 0.4), pd * CFrame.new(0, 3.75, -0.35), Color3.fromRGB(40, 90, 150), METAL, DECOR)
	PartKit.Box(model, "DoorCanopy", Vector3.new(6, 0.4, 3), pd * CFrame.new(0, 8.6, -1.5), Color3.fromRGB(80, 84, 90), METAL, DECOR)
	local logo = PartKit.Box(model, "Logo", Vector3.new(math.min(30, faceWidth * 0.4), 4, 0.3), face * CFrame.new(-faceWidth * 0.2, h - 10, -0.5), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	PartKit.Sign(logo, Enum.NormalId.Front, pick(rng, COMPANIES), Color3.fromRGB(30, 60, 120), nil, Enum.Font.GothamBlack, 10)
	-- roof vents
	for i = 1, math.max(2, math.floor(w / 30)) do
		local p = Vector3.new(cx - w / 2 + i * w / (math.floor(w / 30) + 1), Y + h + 1.5, cz)
		PartKit.Post(model, "RoofVent", 2.4, 2.4, p, Color3.fromRGB(190, 192, 196), METAL, DECOR)
		PartKit.Ball(model, "VentCap", 2.6, p + Vector3.new(0, 2.6, 0), Color3.fromRGB(190, 192, 196), METAL, DECOR)
	end
	-- a pipe run down one side
	local side = Detail.Face(cx, cz, right, (if math.abs(right.X) > 0.5 then w else d) / 2, Y)
	PartKit.Box(model, "Pipe", Vector3.new(1.2, h, 1.2), side * CFrame.new(faceWidth * 0.3, h / 2, -0.8), Color3.fromRGB(180, 70, 50), METAL, DECOR)
	return model
end

function Buildings.Chimney(parent: Instance, base: Vector3, height: number)
	local model = PartKit.Model(parent, "Chimney")
	local bands = 6
	for i = 0, bands - 1 do
		local color = if i % 2 == 0 then Color3.fromRGB(196, 60, 50) else Color3.fromRGB(235, 235, 230)
		PartKit.Post(model, "Stack", 9 - i * 0.6, height / bands, base + Vector3.new(0, i * height / bands, 0), color, Enum.Material.Brick)
	end
end

-- A suburban house facing `front` (a unit axis vector toward its street), `setback` studs from it
function Buildings.House(parent: Instance, center: Vector3, front: Vector3, setback: number, rng: Random, lotWidth: number?)
	local model = PartKit.Model(parent, "House")
	-- two storeys (real suburban houses: ~2.7 m a storey, eaves ~5.5 m), a 35 degree gable roof
	local w, d, h = rng:NextNumber(30, 38), rng:NextNumber(26, 32), rng:NextNumber(19, 20.5)
	local look = CFrame.lookAt(center, center + front) -- -Z toward the street
	local wall = pick(rng, HOUSE_COLORS)
	local roof = pick(rng, ROOFS)
	local material = if rng:NextNumber() < 0.85 then Enum.Material.Plaster else Enum.Material.WoodPlanks
	PartKit.Box(model, "Walls", Vector3.new(w, h, d), look * CFrame.new(0, h / 2, 0), wall, material)
	-- gable roof: two pitched slabs meeting at the ridge (along the width), wedge gables closing the ends
	local pitch = math.rad(35)
	local rise = d / 2 * math.tan(pitch)
	local over = 1.6
	local eaveY = h - over * math.tan(pitch)
	for _, zs in { -1, 1 } do
		PartKit.Slab(model, "Roof", (look * CFrame.new(0, eaveY, zs * (d / 2 + over))).Position, (look * CFrame.new(0, h + rise + 0.35, 0)).Position, w + 2.4, 0.7, roof, Enum.Material.Slate)
		for _, xs in { -1, 1 } do
			-- full height on local +Z: turn the back half round so both rise to the ridge
			local turn = if zs > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity
			PartKit.Wedge(model, "Gable", Vector3.new(0.8, rise, d / 2), look * CFrame.new(xs * (w / 2 - 0.4), h + rise / 2, zs * d / 4) * turn, wall, material)
		end
	end
	PartKit.Box(model, "Ridge", Vector3.new(w + 2.6, 0.6, 0.9), look * CFrame.new(0, h + rise + 0.3, 0), roof:Lerp(Color3.new(0, 0, 0), 0.3), Enum.Material.Slate, DECOR)
	-- the floor line between the storeys
	PartKit.Box(model, "Band", Vector3.new(w + 0.4, 0.6, d + 0.4), look * CFrame.new(0, 10.4, 0), Color3.fromRGB(245, 245, 242), SMOOTH, DECOR)
	for _, x in { -w * 0.36, -w * 0.12, w * 0.15, w * 0.36 } do
		PartKit.Box(model, "WindowFrame", Vector3.new(5, 5, 0.3), look * CFrame.new(x, 15.4, -d / 2 - 0.12), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		PartKit.Box(model, "Window", Vector3.new(4.2, 4.2, 0.35), look * CFrame.new(x, 15.4, -d / 2 - 0.15), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
		PartKit.Box(model, "Sill", Vector3.new(5.8, 0.4, 0.9), look * CFrame.new(x, 12.7, -d / 2 - 0.4), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	for _, side in { -1, 1 } do
		for _, z in { -d * 0.2, d * 0.2 } do
			PartKit.Box(model, "SideWindow", Vector3.new(0.35, 4.2, 4.2), look * CFrame.new(side * (w / 2 + 0.1), 15.4, z), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
			PartKit.Box(model, "SideFrame", Vector3.new(0.3, 5, 5), look * CFrame.new(side * (w / 2 + 0.05), 15.4, z), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		end
		-- a small window up in each gable
		PartKit.Box(model, "SideWindow", Vector3.new(0.35, 2.6, 2.6), look * CFrame.new(side * (w / 2 + 0.1), h + rise * 0.4, 0), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	for _, x in { -w * 0.25, w * 0.25 } do
		PartKit.Box(model, "BackWindow", Vector3.new(5, 4.2, 0.35), look * CFrame.new(x, 15.4, d / 2 + 0.1), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	PartKit.Box(model, "Door", Vector3.new(4, 7.5, 0.4), look * CFrame.new(-w * 0.15, 3.75, -d / 2 - 0.15), Color3.fromRGB(90, 56, 40), Enum.Material.Wood, DECOR)
	PartKit.Box(model, "Step", Vector3.new(7, 0.8, 3), look * CFrame.new(-w * 0.15, 0.4, -d / 2 - 1.5), Color3.fromRGB(190, 186, 180), CONCRETE)
	for _, x in { -w * 0.36, w * 0.15, w * 0.36 } do
		PartKit.Box(model, "WindowFrame", Vector3.new(5, 5, 0.3), look * CFrame.new(x, 6.5, -d / 2 - 0.12), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		PartKit.Box(model, "Window", Vector3.new(4.2, 4.2, 0.35), look * CFrame.new(x, 6.5, -d / 2 - 0.15), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	-- garage + driveway
	local gx = w / 2 + 9
	PartKit.Box(model, "Garage", Vector3.new(16, 10, 22), look * CFrame.new(gx, 5, -d / 2 + 11), wall, material)
	PartKit.Box(model, "GarageRoof", Vector3.new(17, 1, 23), look * CFrame.new(gx, 10.5, -d / 2 + 11), roof, Enum.Material.Slate)
	PartKit.Box(model, "GarageDoor", Vector3.new(12, 8, 0.3), look * CFrame.new(gx, 4, -d / 2 - 0.1), Color3.fromRGB(240, 240, 238), SMOOTH, DECOR)
	local drive = setback - d / 2
	if drive > 1 then
		PartKit.Box(model, "Driveway", Vector3.new(12, 0.1, drive), look * CFrame.new(gx, 0.05, -d / 2 - drive / 2), Color3.fromRGB(176, 174, 170), CONCRETE, DECOR)
		PartKit.Box(model, "Path", Vector3.new(3.5, 0.1, drive - 3), look * CFrame.new(-w * 0.15, 0.05, -d / 2 - 3 - (drive - 3) / 2), Color3.fromRGB(190, 186, 180), CONCRETE, DECOR)
	end
	if rng:NextNumber() < 0.5 then
		PartKit.Box(model, "Chimney", Vector3.new(3, rise + 5, 3), look * CFrame.new(-w * 0.35, h + (rise + 5) / 2, d * 0.15), Color3.fromRGB(150, 80, 60), Enum.Material.Brick)
	end
	-- porch over the door: roof on two posts
	local porchX = -w * 0.15
	PartKit.Box(model, "PorchRoof", Vector3.new(10, 0.6, 6), look * CFrame.new(porchX, 9.2, -d / 2 - 3) * CFrame.Angles(math.rad(8), 0, 0), roof, Enum.Material.Slate, NO_COLLIDE)
	for _, sx in { -4.4, 4.4 } do
		PartKit.Box(model, "PorchPost", Vector3.new(0.6, 9, 0.6), look * CFrame.new(porchX + sx, 4.5, -d / 2 - 5.6), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	PartKit.Box(model, "PorchLight", Vector3.new(0.7, 1, 0.5), look * CFrame.new(porchX + 2.8, 6.4, -d / 2 - 0.4), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, DECOR)
	-- shutters beside the front windows, windows on the sides and back
	local shutter = pick(rng, { Color3.fromRGB(40, 70, 110), Color3.fromRGB(40, 90, 60), Color3.fromRGB(120, 40, 40), Color3.fromRGB(50, 50, 54) })
	for _, x in { -w * 0.36, w * 0.15, w * 0.36 } do
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "Shutter", Vector3.new(1.6, 5, 0.3), look * CFrame.new(x + sx * 3.4, 6.5, -d / 2 - 0.2), shutter, SMOOTH, DECOR)
		end
		PartKit.Box(model, "Sill", Vector3.new(5.8, 0.4, 0.9), look * CFrame.new(x, 3.8, -d / 2 - 0.4), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
	end
	for _, side in { -1, 1 } do
		for _, z in { -d * 0.2, d * 0.2 } do
			PartKit.Box(model, "SideWindow", Vector3.new(0.35, 4.2, 4.2), look * CFrame.new(side * (w / 2 + 0.1), 6.5, z), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
			PartKit.Box(model, "SideFrame", Vector3.new(0.3, 5, 5), look * CFrame.new(side * (w / 2 + 0.05), 6.5, z), Color3.fromRGB(250, 250, 250), SMOOTH, DECOR)
		end
	end
	for _, x in { -w * 0.25, w * 0.25 } do
		PartKit.Box(model, "BackWindow", Vector3.new(5, 4.2, 0.35), look * CFrame.new(x, 6.5, d / 2 + 0.1), Color3.fromRGB(70, 100, 125), GLASS, DECOR)
	end
	PartKit.Box(model, "Gutter", Vector3.new(w + 2.4, 0.5, 0.6), look * CFrame.new(0, eaveY - 0.6, -d / 2 - over - 0.2), Color3.fromRGB(240, 240, 240), SMOOTH, DECOR)
	-- garage door panels and a light
	for k = 1, 3 do
		PartKit.Box(model, "GaragePanel", Vector3.new(12, 0.2, 0.4), look * CFrame.new(gx, k * 2, -d / 2 - 0.2), Color3.fromRGB(215, 215, 212), SMOOTH, DECOR)
	end

	-- the garden out front: flower bed under the windows, a fence or hedge with gaps for the drive
	-- and path, a mailbox at the end of the drive, sometimes a car on the drive or a hoop
	local lot = lotWidth or (w + 30)
	if rng:NextNumber() < 0.6 then
		Detail.FlowerBed(model, look * CFrame.new(w * 0.25, 0, -d / 2 - 2), 14, rng)
	end
	local fz = -(setback - 1.5)
	local function at(x: number): Vector3
		return (look * CFrame.new(x, 0, fz)).Position
	end
	local gaps = { { porchX - 2.5, porchX + 2.5 }, { gx - 7, gx + 7 } }
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local x = -lot / 2 + 1
	local picket = rng:NextNumber() < 0.35
	for _, gap in gaps do
		if gap[1] > x then
			if picket then
				Detail.Picket(model, at(x), at(gap[1]))
			else
				Detail.Hedge(model, at(x), at(gap[1]), 3.2)
			end
		end
		x = gap[2]
	end
	if lot / 2 - 1 > x then
		if picket then
			Detail.Picket(model, at(x), at(lot / 2 - 1))
		else
			Detail.Hedge(model, at(x), at(lot / 2 - 1), 3.2)
		end
	end
	Detail.Mailbox(model, (look * CFrame.new(gx - 8.5, 0, fz + 0.5)).Position, -front, pick(rng, { Color3.fromRGB(30, 30, 30), Color3.fromRGB(40, 70, 130), Color3.fromRGB(150, 30, 30) }))
	if rng:NextNumber() < 0.4 and drive > 20 then
		Buildings.ParkedCar(model, look * CFrame.new(gx, 0.1, -d / 2 - 12), rng, pick(rng, { "Sedan", "Hatch", "SUV" }))
	elseif rng:NextNumber() < 0.25 and drive > 20 then
		local hoop = look * CFrame.new(gx + 6.5, 0, -d / 2 - 2)
		PartKit.Post(model, "HoopPole", 0.5, 10, hoop.Position, Color3.fromRGB(40, 40, 40), METAL, DECOR)
		PartKit.Box(model, "Backboard", Vector3.new(5, 3.4, 0.3), hoop * CFrame.new(0, 10.5, -0.6), Color3.fromRGB(245, 245, 245), SMOOTH, DECOR)
		PartKit.Cylinder(model, "Rim", 2.4, 0.2, hoop * CFrame.new(0, 9.4, -1.9) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(230, 90, 30), METAL, DECOR)
	end
	return model
end

--------------------------------------------------------------------------------
-- Miami
--------------------------------------------------------------------------------

-- Distant towers draw as low-detail stand-ins beyond the streaming radius (the skyline stays up)
local function skyline(model: Model)
	pcall(function()
		(model :: any).LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	end)
end

local CAR_S = Config.CAR_STUDS_PER_METER / Config.WORLD_SCALE -- cars in the design-unit city

-- A light parked car (a dozen parts: the part-built CarModel is ~150). CityService swaps it for
-- the Blender car of its CarKind when those are imported. `cf` is on the ground; the car's front
-- is -Z.
function Buildings.ParkedCar(parent: Instance, cf: CFrame, rng: Random, kind: string?): Model
	local k = kind or pick(rng, CarModel.CivilianKinds)
	local dims = CarModel.Dims[k] or CarModel.Dims.Sedan
	local color = if k == "Taxi" then Color3.fromRGB(250, 196, 18) else pick(rng, CarModel.CivilianColors)
	local model = PartKit.Model(parent, k)
	model:SetAttribute("Kind", "Car")
	model:SetAttribute("CarKind", k)
	local root = PartKit.Box(model, "Root", Vector3.new(0.4, 0.2, 0.4), cf, color, SMOOTH, { Transparency = 1, Collide = false, Query = false, Touch = false })
	model.PrimaryPart = root
	local L, W = dims.Length * CAR_S, dims.Width * CAR_S
	local clear, bodyH, cabH = dims.Clearance * CAR_S, dims.BodyHeight * CAR_S, dims.CabinHeight * CAR_S
	local body = PartKit.Box(model, "Body", Vector3.new(W, bodyH, L), cf * CFrame.new(0, clear + bodyH / 2, 0), color, SMOOTH)
	body.Reflectance = 0.08
	body:SetAttribute("Paint", true)
	local cabL = dims.CabinLength * CAR_S
	local cabZ = -L / 2 + dims.Hood * L + cabL / 2
	local cabin = PartKit.Box(model, "Cabin", Vector3.new(W * 0.9, cabH, cabL), cf * CFrame.new(0, clear + bodyH + cabH / 2, cabZ), Color3.fromRGB(34, 42, 50), GLASS, DECOR)
	cabin.Reflectance = 0.25
	PartKit.Box(model, "Roof", Vector3.new(W * 0.86, 0.22, cabL * 0.72), cf * CFrame.new(0, clear + bodyH + cabH + 0.05, cabZ + cabL * 0.06), color, SMOOTH, DECOR)
	local r = dims.Wheel * CAR_S / 2
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			PartKit.Cylinder(model, "Wheel", r * 2, 0.5, cf * CFrame.new(x * (W / 2 - 0.15), r, z * dims.Wheelbase * CAR_S / 2), Color3.fromRGB(24, 24, 26), Enum.Material.Rubber, DECOR)
		end
		PartKit.Box(model, "Headlight", Vector3.new(W * 0.22, 0.45, 0.15), cf * CFrame.new(x * W * 0.32, clear + bodyH * 0.7, -L / 2 - 0.05), Color3.fromRGB(240, 240, 230), GLASS, DECOR)
		PartKit.Box(model, "Taillight", Vector3.new(W * 0.2, 0.4, 0.15), cf * CFrame.new(x * W * 0.34, clear + bodyH * 0.72, L / 2 + 0.05), Color3.fromRGB(180, 20, 20), GLASS, DECOR)
	end
	return model
end

-- Painted parking stalls in a row along `dir` from `a` (on the ground, the row's kerb-side end),
-- `depth` deep toward `into`, and cars in some of them (no more than `budget.Cars` more, if given)
local function stalls(parent: Instance, a: Vector3, dir: Vector3, into: Vector3, count: number, depth: number, fill: number, rng: Random, budget: { Cars: number }?)
	local width = 9.5
	for i = 0, count do
		local p = a + dir * (i * width) + into * (depth / 2)
		PartKit.Box(parent, "StallLine", Vector3.new(0.45, 0.05, depth), CFrame.lookAt(p, p + into) + Vector3.new(0, 0.03, 0), Color3.fromRGB(236, 236, 230), SMOOTH, DECOR)
	end
	for i = 0, count - 1 do
		if rng:NextNumber() < fill and (not budget or budget.Cars > 0) then
			if budget then
				budget.Cars -= 1
			end
			local p = a + dir * ((i + 0.5) * width) + into * (depth / 2)
			-- nose in (or backed in)
			local face = if rng:NextNumber() < 0.8 then into else -into
			Buildings.ParkedCar(parent, CFrame.lookAt(p, p + face) * CFrame.Angles(0, math.pi, 0) + Vector3.new(0, 0.05, 0), rng)
		end
	end
end

-- A surface car park over a rect at height `y`: up to LOT_ROWS double rows of stalls along X with
-- aisles, light poles and palm islands at the row ends; any depth left over is a planted lawn
-- either side. Never more than LOT_CARS cars (each is a dozen parts), the middle rows first.
local LOT_CARS = 32
local LOT_ROWS = 2
function Buildings.ParkingLot(parent: Instance, x0: number, x1: number, z0: number, z1: number, y: number, rng: Random, fill: number?)
	local model = PartKit.Model(parent, "CarPark")
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local depth, aisle = 18, 24
	local unit = depth * 2 + aisle
	local rows = math.clamp(math.floor((z1 - z0 - aisle) / unit), 1, LOT_ROWS)
	local used = rows * unit + aisle
	local paved = math.min(z1 - z0, used + 8)
	PartKit.Box(model, "Asphalt", Vector3.new(x1 - x0, 0.2, paved), CFrame.new(cx, y + 0.1, cz), Color3.fromRGB(70, 72, 76), Enum.Material.Asphalt)
	local spare = (z1 - z0 - paved) / 2
	if spare > 4 then
		for _, side in { -1, 1 } do
			local lz = cz + side * (paved / 2 + spare / 2)
			local lawn = PartKit.Box(model, "Lawn", Vector3.new(x1 - x0, 0.3, spare), CFrame.new(cx, y + 0.15, lz), C.Lawn, Enum.Material.Grass)
			lawn:SetAttribute("Surface", "Grass")
			-- a few shade trees and palms on it
			for _ = 1, if spare > 16 then math.min(5, math.floor((x1 - x0) * spare / 9000)) else 0 do
				local p = Vector3.new(rng:NextNumber(x0 + 10, x1 - 10), y + 0.3, lz + rng:NextNumber(-spare / 2 + 6, spare / 2 - 6))
				if rng:NextNumber() < 0.5 then
					Props.Palm(model, p, rng)
				else
					Props.Tree(model, p, rng, 0.9)
				end
			end
		end
	end
	local top = y + 0.2
	local start = cz - used / 2 + aisle
	local count = math.floor((x1 - x0 - 34) / 9.5)
	local rowX = cx - count * 9.5 / 2
	local budget = { Cars = LOT_CARS }
	-- the rows from the middle out, so a capped lot is full in the middle, empty at the edges
	local order = {}
	for r = 0, rows - 1 do
		table.insert(order, r)
	end
	table.sort(order, function(a, b)
		return math.abs(a - (rows - 1) / 2) < math.abs(b - (rows - 1) / 2)
	end)
	for _, r in order do
		local mid = start + r * unit + depth
		stalls(model, Vector3.new(rowX, top, mid), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), count, depth, fill or 0.35, rng, budget)
		stalls(model, Vector3.new(rowX, top, mid), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), count, depth, fill or 0.35, rng, budget)
		-- island at each row end: kerbed grass with a palm, a light at one end
		for _, side in { -1, 1 } do
			local ix = if side < 0 then rowX - 8 else rowX + count * 9.5 + 8
			local island = PartKit.Box(model, "Island", Vector3.new(12, 0.6, depth * 2 - 2), CFrame.new(ix, top + 0.3, mid), C.Lawn, Enum.Material.Grass)
			island:SetAttribute("Surface", "Grass")
			Props.Palm(model, Vector3.new(ix, top + 0.6, mid - 6), rng, 0.8)
			if side > 0 then
				Props.StreetLight(model, Vector3.new(ix, top + 0.6, mid + 8), Vector3.new(-1, 0, 0))
			end
		end
	end
	return model
end

--------------------------------------------------------------------------------
-- Towers
--------------------------------------------------------------------------------
local CONDO_GLASS = {
	Color3.fromRGB(70, 120, 150),
	Color3.fromRGB(96, 150, 170),
	Color3.fromRGB(60, 96, 120),
	Color3.fromRGB(110, 160, 160),
	Color3.fromRGB(80, 110, 130),
	Color3.fromRGB(130, 170, 190),
}
local CONDO_WHITE = { Color3.fromRGB(246, 246, 242), Color3.fromRGB(236, 236, 230), Color3.fromRGB(222, 228, 232) }
local LED = { Color3.fromRGB(0, 210, 255), Color3.fromRGB(255, 60, 170), Color3.fromRGB(150, 90, 255), Color3.fromRGB(255, 255, 255) }
local CONDO_NAMES = { "AURA", "THE EDGE", "MARQUIS", "ONE BAY", "SOLÉ", "ICON", "VELA", "ARIA", "OPAL", "PARAMOUNT", "ELYSIAN", "NAUTILUS" }

-- A Miami condo tower from `baseY`: a glass shaft ringed with white balconies on every floor
-- (glass railings), sometimes stepping back near the top, and a crown: an open frame, a fin or a
-- spire. The floor glass is named Window, so floors light up at night.
function Buildings.CondoTower(parent: Instance, cx: number, cz: number, w: number, d: number, h: number, baseY: number, rng: Random): Model
	local model = PartKit.Model(parent, "Tower")
	skyline(model)
	local floorH = 11
	local glass = pick(rng, CONDO_GLASS)
	local white = pick(rng, CONDO_WHITE)
	local floors = math.max(6, math.floor(h / floorH))
	local setback = if rng:NextNumber() < 0.4 then math.floor(floors * rng:NextNumber(0.7, 0.85)) else floors
	local balcony = rng:NextNumber(4, 7)
	-- one collider for the shaft (and one for the setback above it)
	local dark = glass:Lerp(Color3.new(0, 0, 0), 0.45)
	PartKit.Box(model, "Core", Vector3.new(w - 2, setback * floorH, d - 2), CFrame.new(cx, baseY + setback * floorH / 2, cz), dark, GLASS)
	if setback < floors then
		local upper = (floors - setback) * floorH
		PartKit.Box(model, "Core", Vector3.new(w * 0.72 - 2, upper, d * 0.72 - 2), CFrame.new(cx, baseY + setback * floorH + upper / 2, cz), dark, GLASS)
	end
	for f = 0, floors - 1 do
		local y = baseY + f * floorH
		local fw, fd = w, d
		if f >= setback then
			fw, fd = w * 0.72, d * 0.72
		end
		local band = PartKit.Box(model, "Window", Vector3.new(fw - 1.2, floorH - 1.4, fd - 1.2), CFrame.new(cx, y + 1.3 + (floorH - 1.4) / 2, cz), glass, GLASS, DECOR)
		band.Reflectance = 0.25
		PartKit.Box(model, "Balcony", Vector3.new(fw + balcony * 2, 1.3, fd + balcony * 2), CFrame.new(cx, y + 0.65, cz), white, CONCRETE, DECOR)
		local rail = PartKit.Box(model, "Railing", Vector3.new(fw + balcony * 2 - 0.4, 3.6, fd + balcony * 2 - 0.4), CFrame.new(cx, y + 1.3 + 1.8, cz), Color3.fromRGB(190, 214, 224), GLASS, DECOR)
		rail.Transparency = 0.72
	end
	local top = baseY + floors * floorH
	local tw, td = if setback < floors then w * 0.72 else w, if setback < floors then d * 0.72 else d
	PartKit.Box(model, "RoofSlab", Vector3.new(tw + balcony * 2, 1.6, td + balcony * 2), CFrame.new(cx, top + 0.8, cz), white, CONCRETE)
	local crown = rng:NextNumber()
	if crown < 0.35 then
		-- an open frame round the top, lit along its top edge
		local fh = rng:NextNumber(22, 40)
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "CrownFrame", Vector3.new(2.5, fh, td + balcony * 2), CFrame.new(cx + sx * (tw / 2 + balcony - 1.25), top + 1.6 + fh / 2, cz), white, CONCRETE, NO_COLLIDE)
			PartKit.Box(model, "CrownFrame", Vector3.new(tw + balcony * 2, fh, 2.5), CFrame.new(cx, top + 1.6 + fh / 2, cz + sx * (td / 2 + balcony - 1.25)), white, CONCRETE, NO_COLLIDE)
		end
		PartKit.Box(model, "CrownLED", Vector3.new(tw + balcony * 2 + 0.4, 0.8, td + balcony * 2 + 0.4), CFrame.new(cx, top + 1.6 + fh, cz), pick(rng, LED), Enum.Material.Neon, DECOR)
	elseif crown < 0.6 then
		-- a sail-like fin rising off one side
		local fh = rng:NextNumber(40, 80)
		PartKit.Box(model, "Fin", Vector3.new(tw * 0.7, fh, 3), CFrame.new(cx, top + 1.6 + fh / 2, cz + td / 2 - 1.5), white, CONCRETE, NO_COLLIDE)
		PartKit.Box(model, "FinLED", Vector3.new(0.8, fh, 3.2), CFrame.new(cx + tw * 0.35, top + 1.6 + fh / 2, cz + td / 2 - 1.5), pick(rng, LED), Enum.Material.Neon, DECOR)
	elseif crown < 0.8 then
		PartKit.Box(model, "Penthouse", Vector3.new(tw * 0.5, 12, td * 0.5), CFrame.new(cx, top + 7.6, cz), glass, GLASS)
		PartKit.Post(model, "Spire", 1.8, rng:NextNumber(40, 70), Vector3.new(cx, top + 13.6, cz), Color3.fromRGB(220, 222, 226), Enum.Material.Metal, NO_COLLIDE)
	else
		-- a rooftop helipad
		PartKit.Cylinder(model, "Helipad", math.min(tw, td) * 0.8, 0.5, CFrame.new(cx, top + 1.85, cz) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(60, 62, 66), CONCRETE, DECOR)
		local mark = PartKit.Box(model, "HelipadMark", Vector3.new(math.min(tw, td) * 0.4, 0.1, math.min(tw, td) * 0.4), CFrame.new(cx, top + 2.15, cz), Color3.fromRGB(240, 240, 240), SMOOTH, DECOR)
		mark.Transparency = 1
		PartKit.Sign(mark, Enum.NormalId.Top, "H", Color3.fromRGB(250, 250, 250), nil, Enum.Font.GothamBlack, 4)
	end
	return model
end

-- A parking podium under a tower: concrete decks with dark openings, a screen of fins on the street
-- faces, a glass lobby, and a pool deck on its roof. Returns the roof height.
function Buildings.Podium(parent: Instance, cx: number, cz: number, w: number, d: number, levels: number, rng: Random, accent: Color3?): number
	local model = PartKit.Model(parent, "Podium")
	local levelH = 11
	local h = levels * levelH
	local tone = pick(rng, CONCRETE_TONES)
	PartKit.Box(model, "Body", Vector3.new(w, h, d), CFrame.new(cx, Y + h / 2, cz), tone, CONCRETE)
	local lobby = PartKit.Box(model, "ShopGlass", Vector3.new(w + 0.3, 9, d + 0.3), CFrame.new(cx, Y + 5, cz), Color3.fromRGB(80, 110, 124), GLASS, DECOR)
	lobby.Reflectance = 0.2
	for l = 1, levels - 1 do
		PartKit.Box(model, "Opening", Vector3.new(w + 0.3, levelH - 3.8, d + 0.3), CFrame.new(cx, Y + l * levelH + 1.9 + (levelH - 3.8) / 2, cz), Color3.fromRGB(38, 40, 44), SMOOTH, DECOR)
	end
	-- the screen: vertical fins over the openings on all four faces
	local fin = accent or pick(rng, { Color3.fromRGB(245, 245, 240), Color3.fromRGB(230, 120, 60), Color3.fromRGB(60, 150, 170), Color3.fromRGB(200, 200, 196) })
	for _, out in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local faceW = if out.X ~= 0 then d else w
		local half = if out.X ~= 0 then w / 2 else d / 2
		local face = Detail.Face(cx, cz, out, half, Y)
		local n = math.floor(faceW / 8)
		for i = 1, n - 1 do
			PartKit.Box(model, "ScreenFin", Vector3.new(1.2, h - levelH, 2), face * CFrame.new(-faceW / 2 + i * faceW / n, levelH + (h - levelH) / 2, -0.8), fin, SMOOTH, DECOR)
		end
	end
	local top = Y + h
	PartKit.Box(model, "Parapet", Vector3.new(w + 0.6, 3.4, d + 0.6), CFrame.new(cx, top + 1.7, cz), tone, CONCRETE)
	-- pool deck
	local deck = PartKit.Box(model, "PoolDeck", Vector3.new(w - 4, 0.3, d - 4), CFrame.new(cx, top + 0.15, cz), Color3.fromRGB(226, 216, 196), Enum.Material.Pavement)
	deck:SetAttribute("Surface", "Sidewalk")
	-- (the tower stands on the west part: Podium's caller keeps it within -0.4 .. 0.1 of w)
	local px, pz = cx + w * 0.28, cz
	PartKit.Box(model, "PoolEdge", Vector3.new(w * 0.32, 0.5, d * 0.32), CFrame.new(px, top + 0.4, pz), Color3.fromRGB(245, 245, 240), Enum.Material.Marble, DECOR)
	local pool = PartKit.Box(model, "Pool", Vector3.new(w * 0.3, 0.55, d * 0.3), CFrame.new(px, top + 0.42, pz), Color3.fromRGB(60, 190, 220), GLASS, DECOR)
	pool.Transparency = 0.15
	pool.Reflectance = 0.3
	for i = 0, 3 do
		PartKit.Box(model, "Lounger", Vector3.new(2.2, 1, 6), CFrame.new(px - w * 0.12 + i * w * 0.08, top + 0.8, pz + d * 0.22), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	end
	for _, sx in { -1, 1 } do
		Props.Palm(model, Vector3.new(px, top + 0.3, cz + sx * d * 0.4), rng, 0.7)
	end
	return top
end

-- An office tower with a podium of its own lobby (Buildings.Tower), at Y
local function officeTower(folder: Instance, cx: number, cz: number, w: number, d: number, h: number, rng: Random)
	skyline(Buildings.Tower(folder, cx, cz, w, d, h, rng))
end

-- Height ranges (design studs; 1 stud = 0.28 m) by district
local TOWER_HEIGHTS: { [string]: { number } } = {
	Brickell = { 380, 700 },
	Downtown = { 300, 620 },
	Edgewater = { 280, 560 },
	Condo = { 180, 420 },
}

-- A block of towers: two on podiums (north and south halves), or four smaller ones (one may be a
-- plaza), condos and offices mixed downtown
local function towerBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local range = TOWER_HEIGHTS[block.District] or TOWER_HEIGHTS.Downtown
	local offices = block.District == "Downtown" or block.District == "Brickell"
	local function height(): number
		return rng:NextNumber(range[1], range[2])
	end
	local narrow = w < 200
	-- the block's ground: paving round the buildings, a garden of palms in what's left
	local paving = PartKit.Box(folder, "Plaza", Vector3.new(w, 0.3, d), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(214, 206, 192), Enum.Material.Pavement)
	paving:SetAttribute("Surface", "Sidewalk")
	if narrow or rng:NextNumber() < 0.55 then
		-- two towers on podiums, one in each half (along the block's long side); a podium is at
		-- most ~85 m long, the rest of the half a garden
		for _, half in { -1, 1 } do
			local pcx, pcz, pw, pd
			if narrow or d >= w then
				pw, pd = math.min(w - 8, 300), d / 2 - 14
				pcx, pcz = cx, cz + half * d / 4
			else
				pw, pd = w / 2 - 14, math.min(d - 8, 300)
				pcx, pcz = cx + half * w / 4, cz
			end
			if offices and rng:NextNumber() < 0.35 then
				officeTower(folder, pcx, pcz, math.min(pw * 0.7, 170), math.min(pd * 0.7, 130), height(), rng)
			else
				local top = Buildings.Podium(folder, pcx, pcz, pw, pd, rng:NextInteger(3, 6), rng)
				local tw, td = math.min(pw * 0.5, 90), math.min(pd * 0.62, 80)
				Buildings.CondoTower(folder, pcx - pw * 0.15, pcz, tw, td, height() - (top - Y), top, rng)
			end
		end
		-- palms in the garden left beside the podiums (if the podiums leave one)
		local acrossX = narrow or d >= w
		local span = if acrossX then w else d
		if span / 2 - 8 > 170 then
			for _ = 1, 6 do
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				local off = side * rng:NextNumber(165, span / 2 - 8)
				local p = if acrossX then Vector3.new(cx + off, Y + 0.3, cz + rng:NextNumber(-d / 2 + 10, d / 2 - 10)) else Vector3.new(cx + rng:NextNumber(-w / 2 + 10, w / 2 - 10), Y + 0.3, cz + off)
				Props.Palm(folder, p, rng)
			end
		end
	else
		local plaza = rng:NextInteger(0, 5)
		local k = 0
		for _, qx in { -1, 1 } do
			for _, qz in { -1, 1 } do
				k += 1
				local qcx, qcz = cx + qx * w / 4, cz + qz * d / 4
				if k == plaza then
					PartKit.Box(folder, "Plaza", Vector3.new(w / 2 - 6, 0.3, d / 2 - 6), CFrame.new(qcx, Y + 0.15, qcz), Color3.fromRGB(220, 210, 192), Enum.Material.Pavement)
					for _ = 1, 4 do
						Props.Palm(folder, Vector3.new(qcx + rng:NextNumber(-w / 6, w / 6), Y + 0.3, qcz + rng:NextNumber(-d / 6, d / 6)), rng)
					end
					Props.Bench(folder, CFrame.new(qcx, Y + 0.3, qcz))
				elseif offices and rng:NextNumber() < 0.45 then
					officeTower(folder, qcx, qcz, math.min(w / 2 - rng:NextNumber(18, 30), 150), math.min(d / 2 - rng:NextNumber(18, 30), 130), height() * 0.85, rng)
				else
					-- a condo on a podium of its own
					local pw, pd = w / 2 - 16, d / 2 - 16
					local top = Buildings.Podium(folder, qcx, qcz, pw, pd, rng:NextInteger(2, 4), rng)
					local tw, td = math.min(pw * 0.5, 95), math.min(pd * 0.6, 85)
					Buildings.CondoTower(folder, qcx - pw * 0.15, qcz, tw, td, height() * 0.8 - (top - Y), top, rng)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Art deco hotels (Ocean Drive)
--------------------------------------------------------------------------------
local DECO_COLORS = {
	Color3.fromRGB(252, 200, 210),
	Color3.fromRGB(170, 230, 216),
	Color3.fromRGB(254, 232, 150),
	Color3.fromRGB(210, 196, 240),
	Color3.fromRGB(254, 214, 180),
	Color3.fromRGB(150, 216, 238),
	Color3.fromRGB(250, 250, 246),
}
local DECO_TRIM = { Color3.fromRGB(80, 200, 200), Color3.fromRGB(240, 110, 150), Color3.fromRGB(250, 250, 250), Color3.fromRGB(120, 110, 200), Color3.fromRGB(250, 170, 60) }
local NEON = { Color3.fromRGB(255, 70, 160), Color3.fromRGB(60, 230, 255), Color3.fromRGB(255, 240, 90), Color3.fromRGB(150, 255, 120), Color3.fromRGB(190, 120, 255) }
local HOTELS = { "CORALINE", "SEABREEZE", "STARLITE", "NEPTUNE", "MARISOL", "LAGUNA", "SOLARA", "MOONGLOW", "PALMETTO", "AQUARIUS", "OCEANA", "SANDPIPER", "FLAMINGO", "AZURE" }

-- A three or four storey art-deco hotel facing `front`: pastel stucco, rounded front corners,
-- ribbon windows under "eyebrow" ledges, a stepped central tower with a neon fin sign, and a
-- terrace of café tables out front. `along` is its frontage, `depth` how far back it goes.
function Buildings.DecoHotel(parent: Instance, center: Vector3, front: Vector3, along: number, depth: number, floors: number, rng: Random, terrace: boolean?): Model
	local model = PartKit.Model(parent, "Hotel")
	local look = CFrame.lookAt(center, center + front) -- -Z toward the street
	local floorH = 11.5
	local h = floors * floorH + 2
	local wall = pick(rng, DECO_COLORS)
	local trim = pick(rng, DECO_TRIM)
	local neon = pick(rng, NEON)
	local plaster = Enum.Material.Plaster
	PartKit.Box(model, "Body", Vector3.new(along, h, depth), look * CFrame.new(0, h / 2, 0), wall, plaster)
	-- rounded corners on the street side
	for _, sx in { -1, 1 } do
		PartKit.Post(model, "Corner", 9, h, (look * CFrame.new(sx * (along / 2 - 3.5), 0, -depth / 2 + 3.5)).Position, wall, plaster)
	end
	-- ground floor: a glass lobby and a canopy
	local lobby = PartKit.Box(model, "ShopGlass", Vector3.new(along - 14, 8, 0.4), look * CFrame.new(0, 4.5, -depth / 2 - 0.15), Color3.fromRGB(70, 96, 110), GLASS, DECOR)
	lobby.Reflectance = 0.2
	PartKit.Box(model, "Canopy", Vector3.new(along * 0.4, 0.8, 7), look * CFrame.new(0, 9.6, -depth / 2 - 3.5), trim, SMOOTH, NO_COLLIDE)
	-- ribbon windows and eyebrows, floor by floor
	for f = 1, floors - 1 do
		local y = f * floorH
		local band = PartKit.Box(model, "Window", Vector3.new(along - 16, 4.6, 0.4), look * CFrame.new(0, y + 5, -depth / 2 - 0.15), Color3.fromRGB(64, 92, 112), GLASS, DECOR)
		band.Reflectance = 0.18
		PartKit.Box(model, "Eyebrow", Vector3.new(along + 1, 0.6, 3.2), look * CFrame.new(0, y + 8.2, -depth / 2 - 1.5), trim:Lerp(Color3.new(1, 1, 1), 0.4), SMOOTH, DECOR)
		-- the mullions that break the ribbon into bays
		for i = 1, 3 do
			PartKit.Box(model, "Mullion", Vector3.new(0.6, 4.6, 0.5), look * CFrame.new(-along / 2 + 8 + i * (along - 16) / 4, y + 5, -depth / 2 - 0.3), wall, plaster, DECOR)
		end
	end
	-- the stepped central tower and the fin sign
	local tw = math.min(22, along * 0.36)
	PartKit.Box(model, "Tower", Vector3.new(tw, 14, 8), look * CFrame.new(0, h + 7, -depth / 2 + 4), wall, plaster)
	PartKit.Box(model, "TowerStep", Vector3.new(tw * 0.6, 8, 6), look * CFrame.new(0, h + 18, -depth / 2 + 4), wall, plaster)
	for k = 1, 3 do
		PartKit.Box(model, "TowerBand", Vector3.new(tw + 0.4, 0.7, 8.4), look * CFrame.new(0, h + 2 + k * 3.5, -depth / 2 + 4), trim, SMOOTH, DECOR)
	end
	local name = pick(rng, HOTELS)
	local finH = h + 10
	local fin = PartKit.Box(model, "FinSign", Vector3.new(1.2, finH * 0.7, 6), look * CFrame.new(-along / 2 + 10, finH * 0.35 + h * 0.35, -depth / 2 - 3), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	local letters = {}
	for i = 1, #name do
		table.insert(letters, string.sub(name, i, i))
	end
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		PartKit.Sign(fin, face, table.concat(letters, "\n"), neon, nil, Enum.Font.GothamBlack, 8)
	end
	local fascia = PartKit.Box(model, "HotelName", Vector3.new(along * 0.5, 2.6, 0.3), look * CFrame.new(0, 11.4, -depth / 2 - 7.1), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
	fascia.Transparency = 1
	PartKit.Sign(fascia, Enum.NormalId.Front, name, neon, nil, Enum.Font.GothamBlack, 12)
	PartKit.Box(model, "Parapet", Vector3.new(along + 0.6, 2.2, depth + 0.6), look * CFrame.new(0, h + 1.1, 0), trim:Lerp(wall, 0.5), plaster)
	if terrace == false then
		return model
	end
	-- the terrace: a step up, café tables under umbrellas
	local deck = PartKit.Box(model, "Terrace", Vector3.new(along - 4, 1.4, 12), look * CFrame.new(0, 0.7, -depth / 2 - 6), Color3.fromRGB(226, 214, 196), Enum.Material.Pavement)
	deck:SetAttribute("Surface", "Sidewalk")
	local umbrellas = { Color3.fromRGB(250, 250, 248), trim, Color3.fromRGB(230, 60, 60) }
	for i = 1, math.max(2, math.floor(along / 16)) do
		local x = -along / 2 + i * along / (math.floor(along / 16) + 1)
		local at = look * CFrame.new(x, 1.4, -depth / 2 - 6)
		PartKit.Post(model, "TableLeg", 0.3, 2.6, at.Position, Color3.fromRGB(40, 40, 44), METAL, DECOR)
		PartKit.Cylinder(model, "TableTop", 3, 0.2, CFrame.new(at.Position + Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 245, 240), SMOOTH, DECOR)
		PartKit.Post(model, "UmbrellaPole", 0.25, 7, at.Position, Color3.fromRGB(240, 240, 240), METAL, DECOR)
		PartKit.Ellipsoid(model, "Umbrella", Vector3.new(8, 1.6, 8), CFrame.new(at.Position + Vector3.new(0, 7, 0)), umbrellas[(i % #umbrellas) + 1], Enum.Material.Fabric, DECOR)
	end
	return model
end

local function decoBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	-- hotels facing Ocean Drive (east) with their terraces out front, smaller deco buildings
	-- backing onto them facing Collins Ave
	local rows = {
		{ Side = 1, Depth = 52, X = x1 - 14 - 26, Floors = { 3, 4 }, Terrace = true },
		{ Side = -1, Depth = (x1 - x0) - 70, X = x0 + 1 + ((x1 - x0) - 70) / 2, Floors = { 2, 3 }, Terrace = false },
	}
	for _, row in rows do
		if row.Depth < 24 then
			continue
		end
		local z = z0
		while z1 - z > 40 do
			local along = math.min(rng:NextNumber(42, 64), z1 - z - 2)
			if along < 34 then
				break
			end
			Buildings.DecoHotel(folder, Vector3.new(row.X, Y, z + along / 2), Vector3.new(row.Side, 0, 0), along, row.Depth, rng:NextInteger(row.Floors[1], row.Floors[2]), rng, row.Terrace)
			z += along + rng:NextNumber(3, 8)
		end
	end
end

--------------------------------------------------------------------------------
-- Fast food (made-up brands)
--------------------------------------------------------------------------------
type Brand = { Name: string, Icon: string, Main: Color3, Trim: Color3, Roof: string, Kiosk: boolean? }
local BRANDS: { Brand } = {
	{ Name = "BURGER BAY", Icon = "🍔", Main = Color3.fromRGB(214, 36, 36), Trim = Color3.fromRGB(255, 196, 30), Roof = "Mansard" },
	{ Name = "CLUCK SHACK", Icon = "🍗", Main = Color3.fromRGB(196, 28, 40), Trim = Color3.fromRGB(250, 250, 245), Roof = "Stripes" },
	{ Name = "TACO OLA", Icon = "🌮", Main = Color3.fromRGB(0, 150, 150), Trim = Color3.fromRGB(255, 140, 40), Roof = "Tiles" },
	{ Name = "PIZZA PALMA", Icon = "🍕", Main = Color3.fromRGB(30, 120, 60), Trim = Color3.fromRGB(220, 40, 40), Roof = "Hut" },
	{ Name = "CAFECITO EXPRESS", Icon = "☕", Main = Color3.fromRGB(110, 70, 40), Trim = Color3.fromRGB(245, 230, 200), Roof = "Flat", Kiosk = true },
	{ Name = "FROSTY SWIRL", Icon = "🍦", Main = Color3.fromRGB(255, 150, 190), Trim = Color3.fromRGB(255, 255, 255), Roof = "Cone" },
	{ Name = "FLAMINGO FRIES", Icon = "🍟", Main = Color3.fromRGB(255, 105, 160), Trim = Color3.fromRGB(255, 220, 60), Roof = "Flat" },
	{ Name = "GATOR BITES", Icon = "🐊", Main = Color3.fromRGB(60, 120, 40), Trim = Color3.fromRGB(250, 210, 40), Roof = "Mansard" },
	{ Name = "MANGO WAVE", Icon = "🥭", Main = Color3.fromRGB(255, 140, 0), Trim = Color3.fromRGB(60, 160, 60), Roof = "Flat" },
	{ Name = "CUBAN CORNER", Icon = "🥪", Main = Color3.fromRGB(30, 80, 160), Trim = Color3.fromRGB(250, 250, 250), Roof = "Tiles" },
}
Buildings.Brands = BRANDS

-- A tall pylon sign at `base` with the brand on both faces
local function pylon(parent: Instance, base: Vector3, brand: Brand, height: number)
	local model = PartKit.Model(parent, "Pylon")
	PartKit.Post(model, "PylonPole", 2.6, height, base, Color3.fromRGB(150, 154, 158), METAL)
	local box = PartKit.Box(model, "PylonSign", Vector3.new(20, 11, 3), CFrame.new(base + Vector3.new(0, height + 4, 0)), brand.Main, SMOOTH, NO_COLLIDE)
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back } do
		local text = if face == Enum.NormalId.Left or face == Enum.NormalId.Right then brand.Icon else brand.Icon .. " " .. brand.Name
		PartKit.Sign(box, face, text, brand.Trim, nil, Enum.Font.FredokaOne, 8)
	end
	local drive = PartKit.Box(model, "PylonDrive", Vector3.new(14, 3.4, 2), CFrame.new(base + Vector3.new(0, height - 3.5, 0)), Color3.fromRGB(250, 250, 248), SMOOTH, NO_COLLIDE)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		PartKit.Sign(drive, face, "DRIVE-THRU · OPEN 24H", brand.Main, nil, Enum.Font.GothamBold, 10)
	end
	return model
end

-- One outlet on a pad (x0..x1, z0..z1) facing `front` (toward its street): the restaurant, a
-- drive-thru lane round it with the menu board and window, parking, a pylon sign at the kerb
function Buildings.FastFood(parent: Instance, x0: number, x1: number, z0: number, z1: number, front: Vector3, brand: Brand, rng: Random): Model
	local model = PartKit.Model(parent, "FastFood")
	model:SetAttribute("Brand", brand.Name)
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local alongX = math.abs(front.Z) > 0.5
	local W = if alongX then x1 - x0 else z1 - z0 -- frontage
	local D = if alongX then z1 - z0 else x1 - x0 -- depth from the street
	local look = CFrame.lookAt(Vector3.new(cx, Y, cz), Vector3.new(cx, Y, cz) + front) -- -Z toward the street
	local lot = PartKit.Box(model, "Lot", Vector3.new(W - 2, 0.2, D - 2), look * CFrame.new(0, 0.1, 0), Color3.fromRGB(74, 76, 80), Enum.Material.Asphalt)
	local _ = lot
	local top = 0.2
	local bw, bd, bh = math.min(46, W * 0.36), math.min(32, D * 0.36), 16
	if brand.Kiosk then
		bw, bd, bh = 18, 13, 12
	end
	local bx, bz = -W * 0.1, D * 0.08
	local building = look * CFrame.new(bx, top, bz)
	-- a dining room you walk into (Interior: glazed front, counter, tables), under the brand band
	Interior.Build(model, building, bw, bd, bh - 3.4, {
		Kind = "Food",
		Name = brand.Icon .. " " .. brand.Name,
		Accent = brand.Main,
		Wall = brand.Trim:Lerp(Color3.new(1, 1, 1), 0.5),
		Front = true,
		DoorX = bw / 2 - 6,
		Sides = true,
		Rng = rng,
	})
	local band = PartKit.Box(model, "Band", Vector3.new(bw + 0.4, 3.4, bd + 0.4), building * CFrame.new(0, bh - 1.7, 0), brand.Main, SMOOTH)
	local sign = PartKit.Box(model, "BrandSign", Vector3.new(bw * 0.8, 3, 0.2), building * CFrame.new(0, bh - 1.7, -bd / 2 - 0.35), brand.Main, SMOOTH, DECOR)
	sign.Transparency = 1
	PartKit.Sign(sign, Enum.NormalId.Front, brand.Icon .. " " .. brand.Name, brand.Trim, nil, Enum.Font.FredokaOne, 10)
	local _b = band
	if brand.Roof == "Mansard" then
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "Mansard", Vector3.new(bw + 3, 0.8, 5), building * CFrame.new(0, bh + 1.5, sx * (bd / 2 + 0.2)) * CFrame.Angles(sx * math.rad(-35), 0, 0), brand.Main:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Slate, DECOR)
			PartKit.Box(model, "Mansard", Vector3.new(5, 0.8, bd + 3), building * CFrame.new(sx * (bw / 2 + 0.2), bh + 1.5, 0) * CFrame.Angles(0, 0, sx * math.rad(35)), brand.Main:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Slate, DECOR)
		end
	elseif brand.Roof == "Stripes" then
		local n = math.floor(bw / 4)
		for i = 0, n - 1, 2 do
			PartKit.Box(model, "Stripe", Vector3.new(bw / n, bh - 4, 0.3), building * CFrame.new(-bw / 2 + (i + 0.5) * bw / n, (bh - 4) / 2, bd / 2 + 0.1), brand.Main, SMOOTH, DECOR)
		end
		PartKit.Box(model, "RoofBox", Vector3.new(bw * 0.4, 6, bd * 0.4), building * CFrame.new(0, bh + 3, 0), brand.Main, SMOOTH, DECOR)
	elseif brand.Roof == "Tiles" or brand.Roof == "Hut" then
		local pitch = math.rad(if brand.Roof == "Hut" then 30 else 22)
		local rise = bd / 2 * math.tan(pitch)
		local tile = if brand.Roof == "Hut" then brand.Main else Color3.fromRGB(184, 92, 58)
		for _, zs in { -1, 1 } do
			PartKit.Slab(model, "Roof", (building * CFrame.new(0, bh, zs * (bd / 2 + 1.5))).Position, (building * CFrame.new(0, bh + rise + 0.3, 0)).Position, bw + 2.4, 0.7, tile, Enum.Material.ClayRoofTiles, DECOR)
		end
	elseif brand.Roof == "Cone" then
		-- a giant cone on the roof
		local c = building * CFrame.new(0, bh, 0)
		for k = 0, 3 do
			PartKit.Post(model, "Cone", 7 - k * 1.6, 3.2, (c * CFrame.new(0, k * 3.2, 0)).Position, Color3.fromRGB(214, 160, 90), Enum.Material.WoodPlanks, DECOR)
		end
		PartKit.Ball(model, "Scoop", 9, (c * CFrame.new(0, 15.5, 0)).Position, Color3.fromRGB(255, 200, 220), SMOOTH, DECOR)
		PartKit.Ball(model, "Scoop", 6.5, (c * CFrame.new(0, 20, 0)).Position, Color3.fromRGB(250, 250, 245), SMOOTH, DECOR)
		PartKit.Ball(model, "Cherry", 2, (c * CFrame.new(0, 23.4, 0)).Position, Color3.fromRGB(220, 20, 40), SMOOTH, DECOR)
	else
		PartKit.Box(model, "Parapet", Vector3.new(bw + 1, 1.6, bd + 1), building * CFrame.new(0, bh + 0.8, 0), brand.Trim, SMOOTH, DECOR)
	end
	-- the drive-thru: a painted lane down the building's left side, the window and menu board
	local laneX = -bw / 2 - 7
	local function laneCF(z: number): CFrame
		return building * CFrame.new(laneX, 0.03, z)
	end
	for _, edge in { -1, 1 } do
		PartKit.Box(model, "LaneLine", Vector3.new(0.5, 0.05, bd + 30), laneCF(-2) * CFrame.new(edge * 5.5, 0, 0), Color3.fromRGB(250, 210, 40), SMOOTH, DECOR)
	end
	local arrow = PartKit.Box(model, "LaneText", Vector3.new(8, 0.05, 6), laneCF(bd / 2 + 6), Color3.new(1, 1, 1), SMOOTH, DECOR)
	arrow.Transparency = 1
	PartKit.Sign(arrow, Enum.NormalId.Top, "DRIVE THRU ↓", Color3.fromRGB(250, 250, 248), nil, Enum.Font.GothamBold, 6)
	PartKit.Box(model, "DriveWindow", Vector3.new(0.4, 4, 5), building * CFrame.new(-bw / 2 - 0.2, 4.5, -bd * 0.1), Color3.fromRGB(70, 96, 110), GLASS, DECOR)
	PartKit.Box(model, "WindowAwning", Vector3.new(4, 0.5, 8), building * CFrame.new(-bw / 2 - 2, 9, -bd * 0.1), brand.Main, SMOOTH, NO_COLLIDE)
	local menu = PartKit.Box(model, "MenuBoard", Vector3.new(0.6, 6, 7), building * CFrame.new(laneX - 6.5, 3.5, bd / 2 + 8), Color3.fromRGB(30, 30, 34), SMOOTH)
	PartKit.Sign(menu, Enum.NormalId.Right, brand.Icon .. "\nMENU\n#1 COMBO $7.99", brand.Trim, Color3.fromRGB(30, 30, 34), Enum.Font.GothamBold, 8)
	-- parking along the street side and the right of the building
	local rowZ = -D / 2 + 26
	local count = math.max(0, math.floor((W * 0.5 - 6) / 9.5))
	stalls(model, (look * CFrame.new(W * 0.5 - 4 - count * 9.5, top, rowZ)).Position, (look.RightVector), -look.LookVector, count, 16, 0.45, rng, { Cars = 10 })
	-- patio, bins, palms
	for i = 0, 1 do
		local at = building * CFrame.new(bw / 2 + 6, 0, -bd / 2 + 6 + i * 9)
		PartKit.Post(model, "TableLeg", 0.3, 2.6, at.Position, Color3.fromRGB(40, 40, 44), METAL, DECOR)
		PartKit.Cylinder(model, "TableTop", 3, 0.2, CFrame.new(at.Position + Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 245, 240), SMOOTH, DECOR)
		PartKit.Post(model, "UmbrellaPole", 0.25, 7, at.Position, Color3.fromRGB(240, 240, 240), METAL, DECOR)
		PartKit.Ellipsoid(model, "Umbrella", Vector3.new(7, 1.4, 7), CFrame.new(at.Position + Vector3.new(0, 7, 0)), brand.Main, Enum.Material.Fabric, DECOR)
	end
	Detail.Bin(model, (building * CFrame.new(bw / 2 + 3, 0, bd / 2 - 3)).Position)
	Props.Palm(model, (look * CFrame.new(-W / 2 + 6, top, -D / 2 + 6)).Position, rng, 0.9)
	Props.Palm(model, (look * CFrame.new(W / 2 - 6, top, D / 2 - 6)).Position, rng, 0.9)
	pylon(model, (look * CFrame.new(-W / 2 + 14, top, -D / 2 + 5)).Position, brand, rng:NextNumber(36, 52))
	return model
end

-- A one-storey strip mall along the back of a pad, its car park out front and a tenant pylon
function Buildings.StripMall(parent: Instance, x0: number, x1: number, z0: number, z1: number, front: Vector3, rng: Random): Model
	local model = PartKit.Model(parent, "StripMall")
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local alongX = math.abs(front.Z) > 0.5
	local W = if alongX then x1 - x0 else z1 - z0
	local D = if alongX then z1 - z0 else x1 - x0
	local look = CFrame.lookAt(Vector3.new(cx, Y, cz), Vector3.new(cx, Y, cz) + front)
	PartKit.Box(model, "Lot", Vector3.new(W - 2, 0.2, D - 2), look * CFrame.new(0, 0.1, 0), Color3.fromRGB(74, 76, 80), Enum.Material.Asphalt)
	local bd, bh = math.min(44, D * 0.4), 18
	local row = look * CFrame.new(0, 0.2, D / 2 - bd / 2 - 4)
	local wall = pick(rng, PASTELS)
	-- the units are rooms (Interior); the mall's box is only the storey above them
	local shopH = 12
	PartKit.Box(model, "Mall", Vector3.new(W - 12, bh - shopH, bd), row * CFrame.new(0, shopH + (bh - shopH) / 2, 0), wall, Enum.Material.Plaster)
	PartKit.Box(model, "Arcade", Vector3.new(W - 10, 1, 8), row * CFrame.new(0, 11, -bd / 2 - 4), Color3.fromRGB(245, 245, 240), SMOOTH, NO_COLLIDE)
	local units = math.max(2, math.floor((W - 12) / 30))
	local unitW = (W - 12) / units
	local face = row * CFrame.new(0, 0, -bd / 2)
	for i = 0, units - 1 do
		local x = -(W - 12) / 2 + (i + 0.5) * unitW
		local shopName = pick(rng, SHOPS)
		local awning = pick(rng, AWNINGS)
		Detail.Storefront(model, face * CFrame.new(x, 0, 0), unitW - 1, 9.5, shopName, awning, rng)
		Interior.Build(model, face * CFrame.new(x, 0, bd / 2), unitW, bd, shopH, {
			Kind = if i == 0 and rng:NextNumber() < 0.5 then "Food" else "Shop",
			Name = shopName,
			Accent = awning,
			Wall = wall:Lerp(Color3.new(1, 1, 1), 0.6),
			Front = false,
			Sides = true,
			Rng = rng,
		})
		PartKit.Box(model, "ShopHeader", Vector3.new(unitW, shopH - 9.5, 1), face * CFrame.new(x, 9.5 + (shopH - 9.5) / 2, 0.5), wall, Enum.Material.Plaster)
		if i > 0 then
			PartKit.Box(model, "Column", Vector3.new(1.2, 10.5, 1.2), face * CFrame.new(x - unitW / 2, 5.25, -7.5), Color3.fromRGB(245, 245, 240), SMOOTH)
		end
	end
	PartKit.Box(model, "Parapet", Vector3.new(W - 11, 3, bd + 1), row * CFrame.new(0, bh + 1.5, 0), wall:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Plaster)
	local count = math.floor((W - 30) / 9.5)
	local mid = -D / 2 + (D - bd - 8) / 2
	local cars = { Cars = 16 }
	stalls(model, (look * CFrame.new(-count * 9.5 / 2, 0.2, mid)).Position, look.RightVector, -look.LookVector, count, 17, 0.35, rng, cars)
	stalls(model, (look * CFrame.new(-count * 9.5 / 2, 0.2, mid)).Position, look.RightVector, look.LookVector, count, 17, 0.35, rng, cars)
	local brand = pick(rng, BRANDS)
	local _ = brand
	local base = (look * CFrame.new(W / 2 - 10, 0.2, -D / 2 + 6)).Position
	PartKit.Post(model, "PylonPole", 2.4, 30, base, Color3.fromRGB(150, 154, 158), METAL)
	local board = PartKit.Box(model, "PylonSign", Vector3.new(16, 14, 2.4), CFrame.new(base + Vector3.new(0, 36, 0)) * (look - look.Position), wall, SMOOTH, NO_COLLIDE)
	for _, f in { Enum.NormalId.Front, Enum.NormalId.Back } do
		PartKit.Sign(board, f, "PALM PLAZA\n" .. pick(rng, SHOPS) .. "\n" .. pick(rng, SHOPS), Color3.fromRGB(40, 40, 44), nil, Enum.Font.GothamBold, 8)
	end
	return model
end

-- A gas station: a canopy over two pump islands, a convenience store behind and a price sign
function Buildings.GasStation(parent: Instance, x0: number, x1: number, z0: number, z1: number, front: Vector3, rng: Random): Model
	local model = PartKit.Model(parent, "GasStation")
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local alongX = math.abs(front.Z) > 0.5
	local W = if alongX then x1 - x0 else z1 - z0
	local D = if alongX then z1 - z0 else x1 - x0
	local look = CFrame.lookAt(Vector3.new(cx, Y, cz), Vector3.new(cx, Y, cz) + front)
	local brand = Color3.fromRGB(255, 120, 20)
	PartKit.Box(model, "Forecourt", Vector3.new(W - 2, 0.2, D - 2), look * CFrame.new(0, 0.1, 0), Color3.fromRGB(176, 176, 172), CONCRETE)
	local canopy = look * CFrame.new(-W * 0.12, 0.2, -D * 0.12)
	local cw, cd = math.min(70, W * 0.55), math.min(42, D * 0.5)
	PartKit.Box(model, "Canopy", Vector3.new(cw, 2.6, cd), canopy * CFrame.new(0, 19, 0), Color3.fromRGB(250, 250, 248), SMOOTH)
	local fascia = PartKit.Box(model, "CanopyBand", Vector3.new(cw + 0.4, 1.6, cd + 0.4), canopy * CFrame.new(0, 18.4, 0), brand, SMOOTH, DECOR)
	local _ = fascia
	local logo = PartKit.Box(model, "CanopyLogo", Vector3.new(cw * 0.5, 1.4, 0.2), canopy * CFrame.new(0, 18.6, -cd / 2 - 0.4), brand, SMOOTH, DECOR)
	logo.Transparency = 1
	PartKit.Sign(logo, Enum.NormalId.Front, "☀ SUNFUEL", Color3.fromRGB(255, 255, 255), nil, Enum.Font.GothamBlack, 10)
	for _, sx in { -1, 1 } do
		local island = canopy * CFrame.new(sx * cw * 0.22, 0, 0)
		PartKit.Box(model, "PumpIsland", Vector3.new(4, 0.7, cd - 10), island * CFrame.new(0, 0.35, 0), Color3.fromRGB(200, 200, 196), CONCRETE)
		for _, sz in { -1, 1 } do
			PartKit.Box(model, "Pump", Vector3.new(2.6, 6, 3.6), island * CFrame.new(0, 3.7, sz * (cd / 4)), Color3.fromRGB(240, 240, 236), SMOOTH)
			PartKit.Box(model, "PumpTop", Vector3.new(2.8, 1.2, 3.8), island * CFrame.new(0, 7.2, sz * (cd / 4)), brand, SMOOTH, DECOR)
		end
		PartKit.Post(model, "CanopyColumn", 2, 18, (island * CFrame.new(0, 0.7, 0)).Position, Color3.fromRGB(240, 240, 236), METAL)
	end
	-- the store
	local store = look * CFrame.new(W * 0.18, 0.2, D / 2 - 18)
	Interior.Build(model, store, math.min(50, W * 0.4), 28, 11.6, {
		Kind = "Gas",
		Name = "☀ SUNFUEL MART",
		Accent = brand,
		Wall = Color3.fromRGB(240, 238, 230),
		Front = true,
		DoorX = 0,
		Sides = true,
		Rng = rng,
	})
	PartKit.Box(model, "StoreBand", Vector3.new(math.min(50, W * 0.4) + 0.4, 2.4, 28.4), store * CFrame.new(0, 12.8, 0), brand, SMOOTH, DECOR)
	-- price sign
	local base = (look * CFrame.new(-W / 2 + 10, 0.2, -D / 2 + 5)).Position
	PartKit.Post(model, "PricePole", 1.6, 20, base, Color3.fromRGB(150, 154, 158), METAL)
	local board = PartKit.Box(model, "PriceSign", Vector3.new(12, 12, 1.6), CFrame.new(base + Vector3.new(0, 26, 0)) * (look - look.Position), Color3.fromRGB(30, 30, 34), SMOOTH, NO_COLLIDE)
	for _, f in { Enum.NormalId.Front, Enum.NormalId.Back } do
		PartKit.Sign(board, f, "☀ SUNFUEL\nREG 3.49\nPREM 4.19\n⚡ EV  FREE", Color3.fromRGB(255, 190, 60), nil, Enum.Font.GothamBold, 8)
	end
	-- an e-bike charger out front (they're everywhere now)
	Props.Palm(model, (look * CFrame.new(W / 2 - 6, 0.2, -D / 2 + 6)).Position, rng, 0.9)
	return model
end

-- A car wash tunnel
function Buildings.CarWash(parent: Instance, cx: number, cz: number, front: Vector3, length: number, rng: Random): Model
	local model = PartKit.Model(parent, "CarWash")
	local look = CFrame.lookAt(Vector3.new(cx, Y, cz), Vector3.new(cx, Y, cz) + front)
	local blue = Color3.fromRGB(40, 140, 220)
	-- the tunnel runs across the frontage (local X)
	PartKit.Box(model, "TunnelRoof", Vector3.new(length, 2, 22), look * CFrame.new(0, 15, 0), Color3.fromRGB(245, 245, 240), SMOOTH)
	PartKit.Box(model, "TunnelWall", Vector3.new(length, 14, 1.4), look * CFrame.new(0, 7, 10.3), Color3.fromRGB(245, 245, 240), Enum.Material.Plaster)
	for _, sx in { -1, 1 } do
		PartKit.Box(model, "TunnelPier", Vector3.new(2, 14, 2), look * CFrame.new(sx * (length / 2 - 1), 7, -10), Color3.fromRGB(245, 245, 240), Enum.Material.Plaster)
		PartKit.Box(model, "Brush", Vector3.new(2.4, 10, 2.4), look * CFrame.new(sx * length * 0.2, 6, 0), blue, Enum.Material.Fabric, DECOR)
	end
	local sign = PartKit.Box(model, "WashSign", Vector3.new(length * 0.6, 4, 0.4), look * CFrame.new(0, 18, -10.5), blue, SMOOTH, DECOR)
	PartKit.Sign(sign, Enum.NormalId.Front, "🫧 SPLASH CAR WASH", Color3.fromRGB(255, 255, 255), nil, Enum.Font.FredokaOne, 10)
	local _ = rng
	return model
end

-- A pad of fast food: pick a brand for each outlet without repeats in the block
local function brandPicker(rng: Random): () -> Brand
	local used: { [string]: boolean } = {}
	return function(): Brand
		for _ = 1, 20 do
			local b = pick(rng, BRANDS)
			if not used[b.Name] then
				used[b.Name] = true
				return b
			end
		end
		return pick(rng, BRANDS)
	end
end

local function fastFoodBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local nextBrand = brandPicker(rng)
	-- the north half faces north, the south half south; each is two outlets or a strip mall
	for _, side in { -1, 1 } do
		local hz0, hz1 = if side < 0 then z0 else cz + 2, if side < 0 then cz - 2 else z1
		local front = Vector3.new(0, 0, side)
		if rng:NextNumber() < 0.3 then
			Buildings.StripMall(folder, x0, x1, hz0, hz1, front, rng)
		else
			Buildings.FastFood(folder, x0, cx - 2, hz0, hz1, front, nextBrand(), rng)
			Buildings.FastFood(folder, cx + 2, x1, hz0, hz1, front, nextBrand(), rng)
		end
	end
end

--------------------------------------------------------------------------------
-- The parking garage (ridable to the roof)
--------------------------------------------------------------------------------
-- Decks LEVEL_H apart; a straight ramp up between each pair of decks, alternately in the west and
-- east ramp lanes, all climbing north. Ride in at the south end on the ground, up the west ramp,
-- across the deck to the east lane's south end, up again, and so on to the roof.
local LEVEL_H = 11
function Buildings.Garage(parent: Instance, cx: number, cz: number, w: number, d: number, levels: number, rng: Random): Model
	local model = PartKit.Model(parent, "Garage")
	local budget = { Cars = LOT_CARS }
	local concrete = Color3.fromRGB(196, 194, 188)
	local slab = 1.4
	local laneW = 24
	local run = 76
	local rz0, rz1 = cz - run / 2, cz + run / 2 -- each ramp runs from rz1 (low, south) to rz0 (high, north)
	local lanes = { cx - w / 2 + 4 + laneW / 2, cx + w / 2 - 4 - laneW / 2 } -- west, east lane centres
	PartKit.Box(model, "GroundSlab", Vector3.new(w, 0.3, d), CFrame.new(cx, Y + 0.15, cz), concrete, CONCRETE):SetAttribute("Surface", "Sidewalk")
	local function deckAt(level: number): number
		return Y + 0.3 + level * LEVEL_H
	end
	for level = 1, levels do
		local y = deckAt(level)
		-- the deck, less the hole over the ramp arriving from below
		local hole = lanes[((level - 1) % 2) + 1]
		local hx0, hx1 = hole - laneW / 2, hole + laneW / 2
		local function piece(px0: number, px1: number, pz0: number, pz1: number)
			if px1 - px0 > 0.5 and pz1 - pz0 > 0.5 then
				local p = PartKit.Box(model, "Deck", Vector3.new(px1 - px0, slab, pz1 - pz0), CFrame.new((px0 + px1) / 2, y - slab / 2, (pz0 + pz1) / 2), concrete, CONCRETE)
				p:SetAttribute("Surface", "Sidewalk")
			end
		end
		local gx0, gx1, gz0, gz1 = cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2
		piece(gx0, hx0, gz0, gz1)
		piece(hx1, gx1, gz0, gz1)
		piece(hx0, hx1, gz0, rz0)
		piece(hx0, hx1, rz1, gz1)
		-- a kerb wall along the hole's open side and its south end, so nobody drops in
		local inner = if hole < cx then hx1 else hx0
		PartKit.Box(model, "HoleWall", Vector3.new(1.2, 3.4, run), CFrame.new(inner, y + 1.7, cz), concrete, CONCRETE)
		PartKit.Box(model, "HoleWall", Vector3.new(laneW, 3.4, 1.2), CFrame.new(hole, y + 1.7, rz1 + 0.6), concrete, CONCRETE)
		-- the parapet round the deck (open where the lanes meet the south end for light)
		for _, sx in { -1, 1 } do
			PartKit.Box(model, "Parapet", Vector3.new(1.2, 3.6, d), CFrame.new(cx + sx * (w / 2 - 0.6), y + 1.8, cz), concrete, CONCRETE)
			PartKit.Box(model, "Parapet", Vector3.new(w, 3.6, 1.2), CFrame.new(cx, y + 1.8, cz + sx * (d / 2 - 0.6)), concrete, CONCRETE)
		end
		-- the level's stall lines down the middle, a few cars
		if level == levels or rng:NextNumber() < 0.6 then
			local count = math.floor((d - run - 40) / 2 / 9.5)
			for _, sz in { -1, 1 } do
				local zStart = if sz < 0 then cz - d / 2 + 6 else rz1 + 14
				stalls(model, Vector3.new(cx - 2, y, zStart), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), count, 17, 0.25, rng, budget)
				stalls(model, Vector3.new(cx + 2, y, zStart), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), count, 17, 0.25, rng, budget)
			end
		end
	end
	-- the ramps, and a barrier across each ramp's lane under its high end (the slab comes down low
	-- there: ride up it from the south, not under it from the north)
	for level = 0, levels - 1 do
		local lane = lanes[(level % 2) + 1]
		local lo, hi = deckAt(level), deckAt(level + 1)
		local ramp = PartKit.Slab(model, "Ramp", Vector3.new(lane, lo, rz1), Vector3.new(lane, hi, rz0), laneW - 0.4, slab, concrete, CONCRETE)
		ramp:SetAttribute("Surface", "Ramp")
		PartKit.Box(model, "RampStop", Vector3.new(laneW, 3.2, 1.4), CFrame.new(lane, lo + 1.6, rz0 + 18), Color3.fromRGB(240, 200, 40), SMOOTH)
		-- arrows painted on the deck toward the next ramp
		local arrow = PartKit.Box(model, "RampArrow", Vector3.new(8, 0.05, 10), CFrame.new(lane, lo + 0.03, rz1 + 14), Color3.new(1, 1, 1), SMOOTH, DECOR)
		arrow.Transparency = 1
		PartKit.Sign(arrow, Enum.NormalId.Top, "↑ UP", Color3.fromRGB(250, 250, 248), nil, Enum.Font.GothamBlack, 6)
	end
	-- columns the full height round the edge and down the middle (clear of the lanes)
	local top = deckAt(levels)
	for _, sx in { -1, 1 } do
		for z = cz - d / 2 + 3, cz + d / 2 - 3, 36 do
			PartKit.Box(model, "Column", Vector3.new(2.4, top - Y, 2.4), CFrame.new(cx + sx * (w / 2 - 2.4), Y + (top - Y) / 2, z), concrete, CONCRETE)
		end
	end
	for z = cz - d / 2 + 30, cz + d / 2 - 30, 40 do
		if math.abs(z - cz) > run / 2 + 6 then
			PartKit.Box(model, "Column", Vector3.new(2.4, top - Y, 2.4), CFrame.new(cx, Y + (top - Y) / 2, z), concrete, CONCRETE)
		end
	end
	-- the roof: lights, a stair tower, the big P
	for _, c in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, 1) } do
		Props.StreetLight(model, Vector3.new(cx + c.X * (w / 2 - 6), top, cz + c.Z * (d / 2 - 6)), Vector3.new(-c.X, 0, 0))
	end
	local stair = Vector3.new(cx + w / 2 + 7, Y, cz - d / 2 + 10)
	PartKit.Box(model, "StairTower", Vector3.new(14, top - Y + 12, 16), CFrame.new(stair + Vector3.new(0, (top - Y + 12) / 2, 0)), Color3.fromRGB(240, 120, 50), Enum.Material.Plaster)
	local p = PartKit.Box(model, "ParkSign", Vector3.new(14.2, 14, 16.2), CFrame.new(stair + Vector3.new(0, top - Y + 2, 0)), Color3.fromRGB(240, 120, 50), SMOOTH, DECOR)
	for _, f in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		PartKit.Sign(p, f, "P", Color3.fromRGB(255, 255, 255), Color3.fromRGB(30, 80, 170), Enum.Font.GothamBlack, 4)
	end
	-- the entrance (south) with a booth and a barrier arm
	local booth = Vector3.new(lanes[1] + laneW / 2 + 6, Y + 0.3, cz + d / 2 - 6)
	PartKit.Box(model, "Booth", Vector3.new(6, 8, 6), CFrame.new(booth + Vector3.new(0, 4, 0)), Color3.fromRGB(245, 245, 240), SMOOTH)
	local arm = PartKit.Box(model, "BarrierArm", Vector3.new(0.4, 0.4, 0.4), CFrame.new(booth + Vector3.new(-3, 4, -6)), Color3.fromRGB(230, 40, 40), SMOOTH, DECOR)
	local _ = arm
	return model
end

local function parkingBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local w, d = x1 - x0, z1 - z0
	-- the garage takes the west two thirds, a surface lot the rest
	local gw = math.min(170, w * 0.6)
	local gx = x0 + gw / 2 + 4
	Buildings.Garage(folder, gx, cz, gw, d - 30, 4, rng)
	Buildings.ParkingLot(folder, gx + gw / 2 + 24, x1, z0, z1, Y, rng, 0.3)
	local _ = cx
end

--------------------------------------------------------------------------------
-- Wynwood
--------------------------------------------------------------------------------
local MURAL = {
	Color3.fromRGB(255, 64, 129),
	Color3.fromRGB(0, 188, 212),
	Color3.fromRGB(255, 235, 59),
	Color3.fromRGB(124, 77, 255),
	Color3.fromRGB(255, 152, 0),
	Color3.fromRGB(76, 175, 80),
	Color3.fromRGB(233, 30, 99),
	Color3.fromRGB(3, 169, 244),
	Color3.fromRGB(255, 87, 34),
	Color3.fromRGB(28, 28, 30),
	Color3.fromRGB(250, 250, 250),
}
local TAGS = { "WYNWOOD", "305", "MIAMI", "VIBES", "SOL", "DREAM", "ART LIVES", "FLOW", "ELECTRIC", "RIDE ON" }

-- A mural across a face (`face` from Detail.Face), `width` wide and `height` tall from `y0`: a
-- background wash, bold bands, discs and triangles, and a tag
function Buildings.Mural(parent: Instance, face: CFrame, width: number, height: number, y0: number, rng: Random)
	local bg = pick(rng, MURAL)
	PartKit.Box(parent, "Mural", Vector3.new(width, height, 0.12), face * CFrame.new(0, y0 + height / 2, -0.1), bg, SMOOTH, DECOR)
	local n = rng:NextInteger(6, 10)
	for i = 1, n do
		local c = pick(rng, MURAL)
		local depth = -0.18 - i * 0.012
		local kind = rng:NextNumber()
		if kind < 0.35 then
			local len = rng:NextNumber(0.4, 0.75) * math.min(width, height * 2)
			local th = rng:NextNumber(1.5, math.max(2, height * 0.18))
			local y = y0 + height * rng:NextNumber(0.3, 0.7)
			local angle = rng:NextNumber(-0.5, 0.5)
			local reach = len / 2 * math.abs(math.sin(angle)) + th
			if reach < height / 2 then
				PartKit.Box(parent, "MuralBand", Vector3.new(len, th, 0.1), face * CFrame.new(rng:NextNumber(-1, 1) * (width - len) / 2 * 0.8, y, depth) * CFrame.Angles(0, 0, angle), c, SMOOTH, DECOR)
			end
		elseif kind < 0.7 then
			local r = rng:NextNumber(2.5, math.min(height * 0.4, width * 0.2, 14))
			local x = rng:NextNumber(-width / 2 + r + 1, width / 2 - r - 1)
			local y = y0 + rng:NextNumber(r + 1, height - r - 1)
			PartKit.Cylinder(parent, "MuralDisc", r * 2, 0.1, face * CFrame.new(x, y, depth) * CFrame.Angles(0, math.pi / 2, 0), c, SMOOTH, DECOR)
		else
			local size = rng:NextNumber(4, math.min(height * 0.6, 14))
			local x = rng:NextNumber(-width / 2 + size, width / 2 - size)
			local y = y0 + rng:NextNumber(size * 0.6, height - size * 0.6)
			PartKit.Wedge(parent, "MuralTri", Vector3.new(0.1, size, size), face * CFrame.new(x, y, depth) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(rng:NextNumber(0, math.pi * 2), 0, 0), c, SMOOTH, DECOR)
		end
	end
	if width > 24 and rng:NextNumber() < 0.7 then
		local tag = PartKit.Box(parent, "MuralTag", Vector3.new(math.min(width * 0.6, 40), math.min(height * 0.35, 10), 0.1), face * CFrame.new(0, y0 + height * 0.5, -0.4), bg, SMOOTH, DECOR)
		tag.Transparency = 1
		PartKit.Sign(tag, Enum.NormalId.Front, pick(rng, TAGS), pick(rng, MURAL), nil, Enum.Font.PermanentMarker, 8)
	end
end

local function wynwoodBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	-- warehouses along the north and south streets with murals on every street face
	for _, side in { -1, 1 } do
		local front = Vector3.new(0, 0, side)
		local n = math.max(2, math.floor(w / rng:NextNumber(130, 170) + 0.5)) -- 35 - 50 m frontages
		local each = w / n
		for i = 0, n - 1 do
			local bw, bd = each - rng:NextNumber(6, 12), rng:NextNumber(70, 95)
			local bh = rng:NextNumber(24, 34)
			local bx = x0 + each * (i + 0.5)
			local bz = cz + side * (d / 2 - bd / 2 - 3)
			local model = Buildings.Warehouse(folder, bx, bz, bw, bd, bh, front, rng)
			-- the street face above the doors, and the end walls at the block's corners
			Buildings.Mural(model, Detail.Face(bx, bz, front, bd / 2 + 0.3, Y), bw - 2, bh - 20, 18, rng)
			for _, sx in { -1, 1 } do
				if (sx < 0 and i == 0) or (sx > 0 and i == n - 1) or rng:NextNumber() < 0.3 then
					Buildings.Mural(model, Detail.Face(bx, bz, Vector3.new(sx, 0, 0), bw / 2 + 0.3, Y), bd - 4, bh - 6, 4, rng)
				end
			end
		end
	end
	-- the walls garden in the middle: free-standing mural walls, food trucks, picnic tables
	local garden = PartKit.Model(folder, "MuralGarden")
	local gd = d - 2 * 100
	if gd > 40 then
		local ground = PartKit.Box(garden, "Turf", Vector3.new(w - 20, 0.3, gd), CFrame.new(cx, Y + 0.15, cz), Color3.fromRGB(110, 160, 80), Enum.Material.Grass)
		ground:SetAttribute("Surface", "Grass")
		for i = 0, 3 do
			local wx = x0 + 30 + i * (w - 60) / 3
			local wall = PartKit.Box(garden, "MuralWall", Vector3.new(36, 16, 2), CFrame.new(wx, Y + 8.3, cz - gd / 2 + 8), Color3.fromRGB(230, 228, 222), CONCRETE)
			local _ = wall
			Buildings.Mural(garden, Detail.Face(wx, cz - gd / 2 + 8, Vector3.new(0, 0, 1), 1.05, Y + 0.3), 35, 15, 0.5, rng)
		end
		local truckColors = { Color3.fromRGB(255, 90, 140), Color3.fromRGB(40, 190, 210), Color3.fromRGB(255, 200, 40) }
		for i = 0, 1 do
			Detail.BoxTruck(garden, CFrame.new(cx - 40 + i * 70, Y + 0.3, cz + gd / 2 - 16) * CFrame.Angles(0, math.rad(90), 0), pick(rng, truckColors), pick(rng, { "AREPA LOCA", "EMPANADA BUS", "TACO WAVE", "COCO FRIO" }))
		end
		for i = 0, 3 do
			Props.Bench(garden, CFrame.new(cx - 60 + i * 40, Y + 0.3, cz + 4))
		end
		for _ = 1, 4 do
			Props.Palm(garden, Vector3.new(rng:NextNumber(x0 + 15, x1 - 15), Y + 0.3, cz + rng:NextNumber(-gd / 4, gd / 4)), rng, 0.85)
		end
	end
end

--------------------------------------------------------------------------------
-- Midtown, the freeway corridors, the suburbs
--------------------------------------------------------------------------------
local function midtownBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	-- pastel shops and flats along the north and south streets, a car park in the middle
	for _, side in { -1, 1 } do
		local front = Vector3.new(0, 0, side)
		local n = math.max(3, math.floor(w / 150 + 0.5)) -- ~40 m frontages
		local each = w / n
		for i = 0, n - 1 do
			local bw = each - rng:NextNumber(4, 10)
			local bd = rng:NextNumber(70, 95)
			local bx = x0 + each * (i + 0.5)
			local bz = cz + side * (d / 2 - bd / 2 - 2)
			local open = {}
			if i == 0 then
				table.insert(open, Vector3.new(-1, 0, 0))
			end
			if i == n - 1 then
				table.insert(open, Vector3.new(1, 0, 0))
			end
			Buildings.Midrise(folder, bx, bz, bw, bd, rng:NextInteger(3, 8), front, rng, open, rng:NextNumber() < 0.75)
		end
	end
	local depth = d - 200
	if depth > 30 then
		Buildings.ParkingLot(folder, x0 + 6, x1 - 6, cz - depth / 2, cz + depth / 2, Y, rng, 0.4)
	end
end

-- A strip of a block along the side of a freeway: outlets (or a strip mall, a gas station) facing
-- the street `front`, from z0 to z1 (or x0 to x1)
local function roadsideStrip(folder: Instance, x0: number, x1: number, z0: number, z1: number, front: Vector3, rng: Random, nextBrand: () -> Brand, allowGas: boolean)
	local alongX = math.abs(front.Z) > 0.5
	local length = if alongX then x1 - x0 else z1 - z0
	local depth = if alongX then z1 - z0 else x1 - x0
	if depth < 40 or length < 60 then
		return
	end
	local n = math.max(1, math.floor(length / 140))
	for i = 0, n - 1 do
		local a = (if alongX then x0 else z0) + i * length / n
		local b = a + length / n
		local px0, px1, pz0, pz1 = if alongX then a + 2 else x0, if alongX then b - 2 else x1, if alongX then z0 else a + 2, if alongX then z1 else b - 2
		local r = rng:NextNumber()
		if depth < 60 then
			-- too shallow for a drive-thru: a row of small shops
			local cx, cz = (px0 + px1) / 2, (pz0 + pz1) / 2
			local bw = if alongX then px1 - px0 else pz1 - pz0
			local bd = depth - 10
			if alongX then
				Buildings.Midrise(folder, cx, cz, bw, bd, 1, front, rng, { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) }, true)
			else
				Buildings.Midrise(folder, cx, cz, bd, bw, 1, front, rng, { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1) }, true)
			end
		elseif allowGas and r < 0.25 then
			Buildings.GasStation(folder, px0, px1, pz0, pz1, front, rng)
		elseif r < 0.4 then
			Buildings.StripMall(folder, px0, px1, pz0, pz1, front, rng)
		else
			Buildings.FastFood(folder, px0, px1, pz0, pz1, front, nextBrand(), rng)
		end
	end
end

-- The car park under a freeway deck: rows of stalls between the piers (x or z the deck's axis)
local function underDeckParking(folder: Instance, x0: number, x1: number, z0: number, z1: number, y: number, axis: string, rng: Random)
	local model = PartKit.Model(folder, "UnderDeckParking")
	local budget = { Cars = LOT_CARS }
	if axis == "Z" then
		local cx = (x0 + x1) / 2
		local count = math.floor((z1 - z0 - 20) / 9.5)
		local start = z0 + 10
		stalls(model, Vector3.new(cx - 12, y, start), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), count, 18, 0.35, rng, budget)
		stalls(model, Vector3.new(cx + 12, y, start), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), count, 18, 0.35, rng, budget)
	else
		local cz = (z0 + z1) / 2
		local count = math.floor((x1 - x0 - 20) / 9.5)
		local start = x0 + 10
		stalls(model, Vector3.new(start, y, cz - 12), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), count, 18, 0.35, rng, budget)
		stalls(model, Vector3.new(start, y, cz + 12), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), count, 18, 0.35, rng, budget)
	end
end

local function freewayBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local u0, u1 = Layout.UnderDeck(block)
	local nextBrand = brandPicker(rng)
	local ramps = table.find(Layout.RAMP_ROWS, block.Bz) ~= nil
	-- the car park under I-95 (between its piers; not in the ramp lanes)
	underDeckParking(folder, Layout.I95_X - 30, Layout.I95_X + 30, z0, z1, Layout.ROAD_Y, "Z", rng)
	-- the strips either side face the streets along them (west: Miami Ave, east: NE 2nd Ave);
	-- where I-395 leaves the junction it passes over the east strip
	local deckZ0, deckZ1 = Layout.I395_Z - Layout.FREEWAY_WIDTH / 2 - 6, Layout.I395_Z + Layout.FREEWAY_WIDTH / 2 + 6
	local function strip(sx0: number, sx1: number, front: Vector3)
		if sx1 - sx0 < 30 then
			return
		end
		local crossed = block.Bz == 3 and front.X > 0
		if crossed then
			roadsideStrip(folder, sx0, sx1, z0, deckZ0, front, rng, nextBrand, false)
			roadsideStrip(folder, sx0, sx1, deckZ1, z1, front, rng, nextBrand, false)
		else
			roadsideStrip(folder, sx0, sx1, z0, z1, front, rng, nextBrand, not ramps)
		end
	end
	strip(x0, u0 - 4, Vector3.new(-1, 0, 0))
	strip(u1 + 4, x1, Vector3.new(1, 0, 0))
end

local function corridorBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local nextBrand = brandPicker(rng)
	local deckZ0, deckZ1 = Layout.I395_Z - Layout.FREEWAY_WIDTH / 2 - 6, Layout.I395_Z + Layout.FREEWAY_WIDTH / 2 + 6
	-- under I-395: a car park between the piers
	PartKit.Box(folder, "Asphalt", Vector3.new(x1 - x0, 0.2, deckZ1 - deckZ0), CFrame.new((x0 + x1) / 2, Y + 0.1, (deckZ0 + deckZ1) / 2), Color3.fromRGB(70, 72, 76), Enum.Material.Asphalt)
	underDeckParking(folder, x0, x1, Layout.I395_Z - 30, Layout.I395_Z + 30, Y + 0.2, "X", rng)
	-- outlets facing the street to the north, a gas station and outlets to the south
	roadsideStrip(folder, x0, x1, z0, deckZ0 - 4, Vector3.new(0, 0, -1), rng, nextBrand, false)
	roadsideStrip(folder, x0, x1, deckZ1 + 4, z1, Vector3.new(0, 0, 1), rng, nextBrand, true)
end

local function suburbBlock(folder: Instance, block: LayoutModule.Block, rng: Random)
	local x0, x1, z0, z1 = block.LotMinX, block.LotMaxX, block.LotMinZ, block.LotMaxZ
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local lawn = PartKit.Box(folder, "Lawns", Vector3.new(w, 0.3, d), CFrame.new(cx, Y + 0.15, cz), Props.Palette.Lawn, Enum.Material.Grass)
	lawn:SetAttribute("Surface", "Grass")
	local lotDepth = math.min(d / 2 - 2, 140)
	for _, side in { -1, 1 } do
		local front = Vector3.new(0, 0, side)
		local n = math.max(4, math.floor(w / 82 + 0.5))
		local each = w / n
		local fenceZ = cz + side * (d / 2 - lotDepth)
		for i = 0, n - 1 do
			local hx = x0 + each * (i + 0.5) + 6 * side
			local hz = cz + side * (d / 2 - 42)
			Buildings.House(folder, Vector3.new(hx, Y + 0.3, hz), front, 42, rng, each)
			-- a palm out front, a pool and loungers in the back yard
			if rng:NextNumber() < 0.75 then
				Props.Palm(folder, Vector3.new(hx + 24 * side, Y + 0.3, cz + side * (d / 2 - 12)), rng, rng:NextNumber(0.7, 0.95))
			end
			local yardZ = (hz + fenceZ) / 2 - side * 8
			if rng:NextNumber() < 0.6 then
				local pw, pd = rng:NextNumber(16, 22), rng:NextNumber(9, 12)
				local px = hx - 4 * side
				PartKit.Box(folder, "PoolDeck", Vector3.new(pw + 8, 0.35, pd + 8), CFrame.new(px, Y + 0.45, yardZ), Color3.fromRGB(226, 216, 196), Enum.Material.Pavement, DECOR)
				local pool = PartKit.Box(folder, "Pool", Vector3.new(pw, 0.4, pd), CFrame.new(px, Y + 0.5, yardZ), Color3.fromRGB(60, 190, 220), GLASS, DECOR)
				pool.Transparency = 0.1
				pool.Reflectance = 0.3
				for k = 0, 1 do
					PartKit.Box(folder, "Lounger", Vector3.new(2.2, 1, 6), CFrame.new(px - pw / 2 + 3 + k * 4, Y + 1, yardZ + side * (pd / 2 + 2.5)), Color3.fromRGB(250, 250, 248), SMOOTH, DECOR)
				end
			elseif rng:NextNumber() < 0.5 then
				Props.Tree(folder, Vector3.new(hx, Y + 0.3, yardZ), rng)
			end
			-- back fence (white vinyl)
			PartKit.Box(folder, "Fence", Vector3.new(each - 2, 5, 0.5), CFrame.new(x0 + each * (i + 0.5), Y + 2.8, fenceZ), Color3.fromRGB(245, 245, 240), Enum.Material.SmoothPlastic)
		end
	end
	-- the green between the back fences: a row of shade trees
	local green = d - 2 * lotDepth
	if green > 30 then
		for k = 0, math.floor(w / 70) - 1 do
			Props.Tree(folder, Vector3.new(x0 + 35 + k * 70 + rng:NextNumber(-10, 10), Y + 0.3, cz + rng:NextNumber(-green / 4, green / 4)), rng)
		end
	end
end

Buildings.TowerBlock = towerBlock
Buildings.Pastels = PASTELS

-- Fills a block according to its district (the landmarks are the Builder's)
function Buildings.Fill(parent: Instance, block: LayoutModule.Block, rng: Random)
	local folder = PartKit.Folder(parent, block.District .. "_" .. block.Grid .. "_" .. block.Bx .. "_" .. block.Bz)
	local district = block.District
	if district == "Downtown" or district == "Brickell" or district == "Edgewater" or district == "Condo" then
		towerBlock(folder, block, rng)
	elseif district == "Midtown" then
		midtownBlock(folder, block, rng)
	elseif district == "Wynwood" then
		wynwoodBlock(folder, block, rng)
	elseif district == "FastFood" then
		fastFoodBlock(folder, block, rng)
	elseif district == "Parking" then
		parkingBlock(folder, block, rng)
	elseif district == "Freeway" then
		freewayBlock(folder, block, rng)
	elseif district == "Corridor" then
		corridorBlock(folder, block, rng)
	elseif district == "ArtDeco" then
		decoBlock(folder, block, rng)
	elseif district == "Suburb" then
		suburbBlock(folder, block, rng)
	end
end

return Buildings
